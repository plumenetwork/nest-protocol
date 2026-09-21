// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {NestVaultCoreTypes} from "contracts/types/NestVaultCoreTypes.sol";

contract FeeLaunchVaultMock {
    mapping(NestVaultCoreTypes.Fees => NestVaultCoreTypes.Fee) internal activeFees;
    mapping(NestVaultCoreTypes.Fees => NestVaultCoreTypes.Fee) internal feeCaps;

    constructor() {
        feeCaps[NestVaultCoreTypes.Fees.Deposit].rate = 200_000;
        feeCaps[NestVaultCoreTypes.Fees.Redemption].rate = 200_000;
        feeCaps[NestVaultCoreTypes.Fees.InstantRedemption].rate = 200_000;
    }

    function fees(NestVaultCoreTypes.Fees feeType) external view returns (uint32 rate, uint256 flat) {
        NestVaultCoreTypes.Fee memory fee = activeFees[feeType];
        return (fee.rate, fee.flat);
    }

    function maxFees(NestVaultCoreTypes.Fees feeType) external view returns (uint32 rate, uint256 flat) {
        NestVaultCoreTypes.Fee memory fee = feeCaps[feeType];
        return (fee.rate, fee.flat);
    }

    function setFee(NestVaultCoreTypes.Fees feeType, NestVaultCoreTypes.Fee calldata fee) external {
        require(fee.rate <= feeCaps[feeType].rate && fee.flat <= feeCaps[feeType].flat, "fee exceeds cap");
        activeFees[feeType] = fee;
    }

    function setMaxFee(NestVaultCoreTypes.Fees feeType, NestVaultCoreTypes.Fee calldata fee) external {
        require(fee.rate >= activeFees[feeType].rate && fee.flat >= activeFees[feeType].flat, "cap below fee");
        feeCaps[feeType] = fee;
    }
}

contract FeeLaunchGateHarness is BaseConfigScript {
    function configure(string memory json, uint256 chainId, address vault, string memory assetSymbol) external {
        rawVaultConfigJson = json;
        vaultConfig.deployChainId = chainId;
        vaultConfig.vaults.push();
        uint256 index = vaultConfig.vaults.length - 1;
        vaultConfig.vaults[index].addr = vault;
        vaultConfig.vaults[index].assetSymbol = assetSymbol;
    }

    function bootstrap(address vault, string memory assetSymbol) external {
        _bootstrapVaultFees(vault, assetSymbol);
    }

    function requireReady() external view {
        _requireVaultFeesReadyForLaunch();
    }

    function markBootstrapped(address vault) external {
        bootstrappedVaults.push(vault);
    }
}

/// @dev Has code but no fees(): stands in for a pre-Fee-struct implementation.
contract NoFeesContract {}

contract FeeLaunchGateTest is Test {
    FeeLaunchGateHarness internal harness;
    FeeLaunchVaultMock internal vault;

    function setUp() public {
        harness = new FeeLaunchGateHarness();
        vault = new FeeLaunchVaultMock();
        // Process-wide env (tests run in parallel): pin one value that only the env-skip case uses.
        vm.setEnv("SKIP_FEE_ASSET_SYMBOLS", "ENVSKIP");
    }

    function testBootstrapSetsFeeBeforeLaunchPostcondition() public {
        harness.configure(_feeConfig(0, 0, 0, 0, 1_500, 0, ""), 98866, address(vault), "USDC");

        harness.bootstrap(address(vault), "USDC");
        harness.requireReady();

        (uint32 rate, uint256 flat) = vault.fees(NestVaultCoreTypes.Fees.InstantRedemption);
        assertEq(rate, 1_500);
        assertEq(flat, 0);
    }

    function testLaunchPostconditionFailsWhileBootstrappedVaultFeeIsMissing() public {
        harness.configure(_feeConfig(500, 0, 0, 0, 0, 0, ""), 98866, address(vault), "USDC");
        harness.markBootstrapped(address(vault));

        vm.expectRevert("BaseConfigScript: configured vault fees must be live before authority setup");
        harness.requireReady();
    }

    function testLaunchPostconditionOnlyWarnsForAlreadyLiveVault() public {
        harness.configure(_feeConfig(500, 0, 0, 0, 0, 0, ""), 98866, address(vault), "USDC");
        harness.requireReady();
    }

    function testLaunchPostconditionSkipsUndeployedAndLegacyVaults() public {
        harness.configure(_feeConfig(500, 0, 0, 0, 0, 0, ""), 98866, makeAddr("not-deployed"), "USDC");
        harness.configure(_feeConfig(500, 0, 0, 0, 0, 0, ""), 98866, address(new NoFeesContract()), "USDT");
        harness.requireReady();
    }

    function testEnvSkipIsHonoredLikeSetupFees() public {
        harness.configure(_feeConfig(500, 0, 0, 0, 0, 0, ""), 98866, address(vault), "ENVSKIP");
        harness.markBootstrapped(address(vault));
        harness.requireReady();
    }

    function testBootstrapFailsClosedWhenFlatFeeHasNoConfiguredCap() public {
        harness.configure(_feeConfig(500, 100, 0, 0, 0, 0, ""), 98866, address(vault), "USDC");

        vm.expectRevert("BaseConfigScript: active fee exceeds cap; configure vaultMaxFees");
        harness.bootstrap(address(vault), "USDC");
    }

    function testBootstrapRaisesExplicitCapBeforeSettingFlatFee() public {
        string memory maxFees =
            ',"vaultMaxFees":{"deposit":{"rate":500,"flat":100},"redemption":{"rate":0,"flat":0},"instantRedemption":{"rate":0,"flat":0}}';
        harness.configure(_feeConfig(500, 100, 0, 0, 0, 0, maxFees), 98866, address(vault), "USDC");

        harness.bootstrap(address(vault), "USDC");
        harness.requireReady();

        (uint32 rate, uint256 flat) = vault.fees(NestVaultCoreTypes.Fees.Deposit);
        assertEq(rate, 500);
        assertEq(flat, 100);
    }

    function testConfiguredSkipIsAnExplicitLaunchExemption() public {
        string memory skips = ',"skipFeeAssetSymbols":{"98866":["USDC"]}';
        harness.configure(_feeConfig(500, 0, 0, 0, 1_500, 0, skips), 98866, address(vault), "USDC");

        harness.bootstrap(address(vault), "USDC");
        harness.requireReady();

        (uint32 rate,) = vault.fees(NestVaultCoreTypes.Fees.InstantRedemption);
        assertEq(rate, 0);
    }

    function _feeConfig(
        uint32 depositRate,
        uint256 depositFlat,
        uint32 redemptionRate,
        uint256 redemptionFlat,
        uint32 instantRate,
        uint256 instantFlat,
        string memory suffix
    ) internal pure returns (string memory) {
        return string.concat(
            '{"vaultFees":{"deposit":{"rate":',
            vm.toString(depositRate),
            ',"flat":',
            vm.toString(depositFlat),
            '},"redemption":{"rate":',
            vm.toString(redemptionRate),
            ',"flat":',
            vm.toString(redemptionFlat),
            '},"instantRedemption":{"rate":',
            vm.toString(instantRate),
            ',"flat":',
            vm.toString(instantFlat),
            "}}",
            suffix,
            "}"
        );
    }
}
