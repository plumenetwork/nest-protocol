// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {NestAccountant} from "contracts/accountant/NestAccountant.sol";
import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";
import {Errors} from "contracts/types/Errors.sol";
import {NestSpokeAccountant} from "contracts/accountant/NestSpokeAccountant.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC20Mock} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/ERC20Mock.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract NestAccountantMigrationTest is Test {
    bytes32 private constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    ERC20Mock private base;
    ERC20Mock private share;
    ERC20Mock private quote;

    function setUp() public {
        base = new ERC20Mock("Base", "BASE");
        share = new ERC20Mock("Share", "SHARE");
        quote = new ERC20Mock("Quote", "QUOTE");
    }

    /// @notice Verifies the NestAccountant -> NestHubAccountant migration flow:
    ///         1. `upgradeAndCall` with empty data (no initializer is invoked; storage layout is preserved).
    ///         2. `resetHighWaterMark(currentExchangeRate)` seeds HWM and clawback reference.
    ///         3. The next `updateExchangeRate` accrues no fees because `lastGrossRate` starts at 0
    ///            and every fee parameter (perf/hurdle/holdback/window/epochs) defaults to 0.
    ///         4. Operators then enable fees through the dedicated setters.
    function test_migrateToHubAndConfigureFees() public {
        uint96 startingRate = 1e18;
        uint32 legacyManagementFee = 10_000;

        NestAccountant legacyImpl = new NestAccountant(address(base), address(share));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(legacyImpl),
            address(this),
            abi.encodeCall(
                NestAccountant.initialize,
                (
                    1_000e18,
                    address(0xBEEF),
                    startingRate,
                    uint32(1_100_000),
                    uint32(900_000),
                    uint32(3600),
                    legacyManagementFee,
                    address(this)
                )
            )
        );

        NestAccountant legacy = NestAccountant(address(proxy));
        legacy.setRateProviderData(ERC20(address(quote)), true, address(0));
        legacy.increaseTotalPendingShares(123e18);
        uint96 currentRate = uint96(legacy.getRate());
        assertEq(currentRate, startingRate, "legacy rate read");

        // Step 1: swap impl with empty initData — no initializer is invoked.
        NestHubAccountant hubImpl = new NestHubAccountant(address(base), address(share));
        ProxyAdmin(_proxyAdmin(address(proxy)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(hubImpl), "");
        NestHubAccountant hub = NestHubAccountant(address(proxy));

        // Step 2: seed HWM at the live exchange rate.
        hub.resetHighWaterMark(currentRate);

        // Legacy slots survived the swap.
        assertEq(hub.totalPendingShares(), 123e18, "pending shares moved slot");
        assertEq(hub.getRateInQuote(ERC20(address(quote))), startingRate, "rate provider mapping moved slot");
        NestHubAccountant.AccountantState memory stateAfterReset = hub.getAccountantState();
        assertEq(stateAfterReset.exchangeRate, startingRate, "exchange rate changed");
        assertEq(stateAfterReset.totalSharesLastUpdate, 1_000e18, "totalSharesLastUpdate moved slot");
        assertEq(stateAfterReset.managementFee, legacyManagementFee, "legacy management fee dropped");
        // New AccountantState field starts uninitialized; first `updateExchangeRate` seeds it.
        assertEq(stateAfterReset.lastGrossRate, 0, "lastGrossRate seeded prematurely");

        // HWM checkpoint is seeded; reserve and fee config are untouched.
        NestHubAccountant.PerformanceFeeCheckpoint memory checkpoint = hub.getPerformanceFeeCheckpoint();
        assertEq(checkpoint.highWaterMark, currentRate, "HWM not seeded");
        assertEq(checkpoint.clawbackReferenceRate, currentRate, "clawback ref not seeded");
        assertEq(checkpoint.hwmLastUpdateTimestamp, uint64(block.timestamp), "HWM timestamp not seeded");

        NestHubAccountant.PerformanceFeeConfig memory configBefore = hub.getPerformanceFeeConfig();
        assertEq(configBefore.performanceFee, 0, "performance fee leaked");
        assertEq(configBefore.hurdleRate, 0, "hurdle rate leaked");
        assertEq(configBefore.holdbackRate, 0, "holdback rate leaked");
        assertEq(configBefore.crystallizationWindow, 0, "crystallization window leaked");
        assertEq(configBefore.epochsPerWindow, 0, "epochs per window leaked");

        // Enabling a perf fee before the first post-migration rate post reverts: no checkpoint yet.
        vm.expectRevert(Errors.InvalidRate.selector);
        hub.updatePerformanceFee(150_000);

        // Step 3: the next `updateExchangeRate` accrues no fees. `lastGrossRate` starts at 0,
        // so the management-fee discount basis is 0; perf-fee path skips because the perf fee is 0.
        vm.warp(block.timestamp + 3601);
        uint96 nextRate = uint96(1.05e18);
        hub.updateExchangeRate(nextRate, 0);

        NestHubAccountant.AccountantState memory stateAfterUpdate = hub.getAccountantState();
        assertEq(stateAfterUpdate.exchangeRate, nextRate, "rate not advanced");
        assertEq(stateAfterUpdate.lastGrossRate, nextRate, "lastGrossRate not seeded by first update");
        assertEq(stateAfterUpdate.feesOwedInBase, 0, "fees accrued on first post-migration update");

        // Step 4: operators enable fees through the individual setters.
        hub.updateManagementFee(20_000); // 2% mgmt fee
        hub.updatePerformanceFee(150_000); // 15% perf fee
        hub.updateHurdleRate(50_000); // 5% hurdle
        hub.updateHoldbackRate(250_000); // 25% holdback
        hub.updateCrystallizationWindow(30 days);
        hub.updateEpochsPerWindow(4);

        NestHubAccountant.PerformanceFeeConfig memory configAfter = hub.getPerformanceFeeConfig();
        assertEq(configAfter.performanceFee, 150_000, "performance fee not set");
        assertEq(configAfter.hurdleRate, 50_000, "hurdle rate not set");
        assertEq(configAfter.holdbackRate, 250_000, "holdback rate not set");
        assertEq(configAfter.crystallizationWindow, 30 days, "crystallization window not set");
        assertEq(configAfter.epochsPerWindow, 4, "epochs per window not set");
        assertEq(hub.getAccountantState().managementFee, 20_000, "management fee not set");
    }

    /// @notice The upgrade preflight reads `feesOwedInBase` via a raw `getAccountantState()` staticcall decoding
    ///         only the two leading words; proves that read is shape-agnostic and the value survives a Spoke swap.
    function test_feesOwedLeadingWordsDecode_survivesSpokeSwap() public {
        share.mint(address(this), 1_000e18);

        NestAccountant legacyImpl = new NestAccountant(address(base), address(share));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(legacyImpl),
            address(this),
            abi.encodeCall(
                NestAccountant.initialize,
                (
                    1_000e18,
                    address(0xBEEF),
                    uint96(1e18),
                    uint32(1_100_000),
                    uint32(900_000),
                    uint32(3600),
                    uint32(10_000),
                    address(this)
                )
            )
        );
        NestAccountant legacy = NestAccountant(address(proxy));

        // Accrue management fees: one year at 1% on 1000e18 of base assets.
        vm.warp(block.timestamp + 365 days);
        legacy.updateExchangeRate(uint96(1e18));
        uint128 typedFees = legacy.getAccountantState().feesOwedInBase;
        assertGt(typedFees, 0, "no fees accrued");

        // Leading-two-words decode matches the typed getter on the legacy (10-word) shape.
        (bool ok, bytes memory ret) = address(proxy).staticcall(abi.encodeWithSignature("getAccountantState()"));
        assertTrue(ok, "legacy staticcall failed");
        (, uint256 rawFees) = abi.decode(ret, (address, uint256));
        assertEq(rawFees, typedFees, "legacy raw decode mismatch");

        // The balance carries over the Spoke (9-word) swap and the same decode still reads it.
        NestSpokeAccountant spokeImpl = new NestSpokeAccountant(address(base), address(share));
        ProxyAdmin(_proxyAdmin(address(proxy)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(spokeImpl), "");
        (ok, ret) = address(proxy).staticcall(abi.encodeWithSignature("getAccountantState()"));
        assertTrue(ok, "spoke staticcall failed");
        (, rawFees) = abi.decode(ret, (address, uint256));
        assertEq(rawFees, typedFees, "fees lost or decode shape-dependent after Spoke swap");
    }

    function _proxyAdmin(address proxy) private view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ADMIN_SLOT))));
    }
}
