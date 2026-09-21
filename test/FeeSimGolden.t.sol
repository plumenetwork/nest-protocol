// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockNestAccountant} from "test/mock/MockNestAccountant.sol";
import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";

/// @dev Minimal token — the accountant only reads `decimals()` and `totalSupply()`.
contract GoldenMockToken {
    uint8 public immutable decimals;
    uint256 public totalSupply;

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }
}

/// @title  FeeSimGoldenTest
/// @notice Replays a fixed set of fee scenarios through the real NestHubAccountant
///         and writes the results to ../nest-fee-simulator/fixtures/expected.json.
///         The fee-simulator engine replays the SAME scenarios and asserts equality.
/// @dev    Run: `forge test --mc FeeSimGolden`. Requires the nest-fee-simulator repo
///         checked out as a sibling directory. Keep the scenarios below in sync
///         with ../nest-fee-simulator/src/engine/__tests__/golden.test.ts.
contract FeeSimGoldenTest is Test {
    struct InitCfg {
        uint96 startingRate;
        uint256 initialShares;
        uint32 upper;
        uint32 lower;
        uint32 minDelay;
        uint32 mgmtFee;
        uint32 perfFee;
        uint32 hurdle;
        uint32 holdback;
        uint32 window;
        uint32 epochs;
    }

    struct Update {
        uint64 dt; // seconds after T0
        uint96 gross;
        uint128 shares;
    }

    uint64 internal constant T0 = 1_000_000;
    uint128 internal constant SHARES = 1_000_000_000_000; // 1,000,000 shares at 6dp

    function _deploy(InitCfg memory c) internal returns (MockNestAccountant) {
        GoldenMockToken base = new GoldenMockToken(6);
        GoldenMockToken shareToken = new GoldenMockToken(6);
        MockNestAccountant impl = new MockNestAccountant(address(base), address(shareToken));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(this),
            abi.encodeCall(
                NestHubAccountant.initialize,
                (
                    c.initialShares,
                    address(this),
                    c.startingRate,
                    c.upper,
                    c.lower,
                    c.minDelay,
                    c.mgmtFee,
                    c.perfFee,
                    c.hurdle,
                    c.holdback,
                    c.window,
                    c.epochs,
                    address(this)
                )
            )
        );
        return MockNestAccountant(address(proxy));
    }

    function _runScenario(string memory root, string memory name, InitCfg memory cfg, Update[] memory ups)
        internal
        returns (string memory)
    {
        vm.warp(T0);
        MockNestAccountant acc = _deploy(cfg);

        uint256 n = ups.length;
        string[] memory exchangeRate = new string[](n);
        string[] memory feesOwed = new string[](n);
        string[] memory reserve = new string[](n);
        string[] memory hwm = new string[](n);

        for (uint256 i; i < n; i++) {
            vm.warp(T0 + ups[i].dt);
            acc.updateExchangeRate(ups[i].gross, ups[i].shares);
            NestHubAccountant.AccountantState memory st = acc.getAccountantState();
            NestHubAccountant.PerformanceFeeCheckpoint memory cp = acc.getPerformanceFeeCheckpoint();
            (uint128 totalReserve,,) = acc.getPerformanceFeeReserve();
            exchangeRate[i] = vm.toString(uint256(st.exchangeRate));
            feesOwed[i] = vm.toString(uint256(st.feesOwedInBase));
            reserve[i] = vm.toString(uint256(totalReserve));
            hwm[i] = vm.toString(uint256(cp.highWaterMark));
        }

        string memory obj = string.concat("scn_", name);
        vm.serializeString(obj, "exchangeRate", exchangeRate);
        vm.serializeString(obj, "feesOwedInBase", feesOwed);
        vm.serializeString(obj, "totalReserve", reserve);
        string memory scenarioJson = vm.serializeString(obj, "highWaterMark", hwm);
        return vm.serializeString(root, name, scenarioJson);
    }

    function test_generateGoldenVectors() public {
        string memory root = "goldenRoot";
        string memory out;

        // S1 — management fee only: 1% over two consecutive years on a flat NAV.
        {
            Update[] memory ups = new Update[](2);
            ups[0] = Update(31_536_000, 1_000_000, SHARES);
            ups[1] = Update(63_072_000, 1_000_000, SHARES);
            out =
                _runScenario(root, "mgmtOnly", InitCfg(1_000_000, SHARES, 2_000_000, 1, 0, 10_000, 0, 0, 0, 0, 0), ups);
        }

        // S2 — performance fee: a 10% gain, a drop below the HWM, then a new high.
        {
            Update[] memory ups = new Update[](3);
            ups[0] = Update(3_600, 1_100_000, SHARES);
            ups[1] = Update(7_200, 1_050_000, SHARES);
            ups[2] = Update(10_800, 1_200_000, SHARES);
            out =
                _runScenario(root, "perfFee", InitCfg(1_000_000, SHARES, 2_000_000, 1, 0, 0, 100_000, 0, 0, 0, 0), ups);
        }

        // S3 — hurdle rate: a gain below the hurdle, then one above it.
        {
            Update[] memory ups = new Update[](2);
            ups[0] = Update(31_536_000, 1_050_000, SHARES);
            ups[1] = Update(63_072_000, 1_300_000, SHARES);
            out = _runScenario(
                root, "hurdle", InitCfg(1_000_000, SHARES, 2_000_000, 1, 0, 0, 100_000, 100_000, 0, 0, 0), ups
            );
        }

        // S4 — holdback + crystallization: 50% held back, released after a 90-day window.
        {
            Update[] memory ups = new Update[](2);
            ups[0] = Update(3_600, 1_100_000, SHARES);
            ups[1] = Update(3_600 + 7_776_000 + 100, 1_100_000, SHARES);
            out = _runScenario(
                root, "holdback", InitCfg(1_000_000, SHARES, 2_000_000, 1, 0, 0, 100_000, 0, 500_000, 7_776_000, 0), ups
            );
        }

        // S5 — clawback: a perf fee fully held back, then a drawdown returns reserve.
        {
            Update[] memory ups = new Update[](2);
            ups[0] = Update(3_600, 1_100_000, SHARES);
            ups[1] = Update(7_200, 1_000_000, SHARES);
            out = _runScenario(
                root,
                "clawback",
                InitCfg(1_000_000, SHARES, 2_000_000, 1, 0, 0, 100_000, 0, 1_000_000, 7_776_000, 0),
                ups
            );
        }

        // Compose an absolute sibling-repo path. Foundry's fs_permissions matcher
        // rejects access paths containing ".." segments, so we strip path
        // components off projectRoot() until we reach the sibling parent dir.
        // Layout: <parent>/nest-contracts/main/  →  <parent>/nest-fee-simulator/...
        string[] memory parts = vm.split(vm.projectRoot(), "/");
        string memory siblingDir = "";
        for (uint256 i = 0; i < parts.length - 2; i++) {
            siblingDir = string.concat(siblingDir, parts[i], "/");
        }
        vm.writeJson(out, string.concat(siblingDir, "nest-fee-simulator/fixtures/expected.json"));
        assertGt(bytes(out).length, 0);
    }
}
