// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {SYTest, IStandardizedYield} from "test/vendor/Pendle/SYTest_flatten.t.sol";
import {Constants} from "script/Constants.sol";
import {Options, DefenderOptions, TxOverrides} from "@openzeppelin/foundry-upgrades/src/Options.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";
import {BoringVaultSY} from "contracts/BoringVaultSY.sol";
import {NestVault} from "contracts/NestVault.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {console} from "forge-std/console.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TestBoringVaultSY is SYTest, Constants {
    using FixedPointMathLib for uint256;

    /// @dev Constant address of Ethereum USDC whale for testing
    address public constant ETHEREUM_USDC_WHALE = 0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;

    NestVault public nestVault;

    function setUpFork() internal override {
        vm.createSelectFork("ethereum");
    }

    function deploySY() internal override {
        vm.startPrank(deployer);

        // deploy NestVault
        Options memory _nestVaultProxyOpts = Options({
            referenceContract: "",
            referenceBuildInfoDir: "",
            constructorData: abi.encode(NALPHA, USDC),
            exclude: new string[](0),
            unsafeAllow: "",
            unsafeAllowRenames: false,
            unsafeSkipProxyAdminCheck: false,
            unsafeSkipStorageCheck: false,
            unsafeSkipAllChecks: true,
            defender: DefenderOptions({
                useDefenderDeploy: false,
                skipVerifySourceCode: false,
                relayerId: "",
                salt: bytes32(0),
                upgradeApprovalProcessId: "",
                licenseType: "",
                skipLicenseType: false,
                txOverrides: TxOverrides({gasLimit: 30000000, gasPrice: 0, maxFeePerGas: 10, maxPriorityFeePerGas: 1}),
                metadata: ""
            })
        });
        address _accountantWithRateProviders = NALPHA_ACCOUNTANT;
        address _asset = USDC;
        address _owner = address(this);
        uint256 _minRate = 1e3;
        address _nestVaultProxy = Upgrades.deployTransparentProxy(
            "NestVault.sol",
            address(this),
            abi.encodeCall(NestVault.initialize, (_accountantWithRateProviders, _asset, _owner, _minRate)),
            _nestVaultProxyOpts
        );

        nestVault = NestVault(_nestVaultProxy);

        address logic = address(new BoringVaultSY(NALPHA, deployer, USDC, 1e3));
        sy = IStandardizedYield(
            deployTransparentProxy(
                logic,
                deployer,
                abi.encodeCall(BoringVaultSY.initialize, (NALPHA_ACCOUNTANT, "SY Nest ALPHA", "SY-nALPHA", deployer))
            )
        );

        vm.stopPrank();
    }

    function initializeSY() internal override {
        super.initializeSY();

        // Set the starting token for tests
        startToken = address(USDC);

        // Any additional initialization logic
        // set the authority
        RolesAuthority boringAuthority = RolesAuthority(address(BoringVault(NALPHA).authority()));
        nestVault.setAuthority(Authority(address(boringAuthority)));
        vm.startPrank(boringAuthority.owner());
        boringAuthority.setPublicCapability(address(nestVault), nestVault.mint.selector, true);
        boringAuthority.setPublicCapability(NALPHA, BoringVault.enter.selector, true);
    }

    function hasFee() internal pure override returns (bool) {
        return false; // set to true if your protocol has mint/redemption fee
    }

    function getPreviewTestAllowedEps() internal pure override returns (uint256) {
        // Specify the acceptable error margin (epsilon) for preview calculations,
        // accommodating minor rounding differences in protocols with fees.
        return 1e15; // e.g: 0.001%
    }

    function hasReward() internal pure override returns (bool) {
        return false; // set to true if protocol has reward
    }

    function addFakeRewards() internal override returns (bool[] memory) {
        // This function simulates the accrual of rewards over time for testing purposes.
        // It allows us to test the reward distribution logic without relying on real user activity.
        // By "fast-forwarding" the blockchain state, we can trigger reward calculations
        // as if a significant amount of time has passed.

        // Simulate time passing to accrue rewards
        vm.roll(block.number + 7200); // ~1 day of blocks
        skip(1 days);

        bool[] memory _retBool = new bool[](3);
        _retBool[0] = true;
        _retBool[1] = false;
        _retBool[2] = false;

        // Return which reward tokens have accrued rewards
        return _retBool; // First reward tokens have rewards
    }

    function fundToken(address wallet, address token, uint256 amount) internal override {
        if (token == NATIVE) {
            deal(wallet, amount);
        } else if (token == USDC) {
            vm.prank(ETHEREUM_USDC_WHALE);
            ERC20(USDC).transfer(wallet, amount);
        } else if (token == NALPHA) {
            vm.startPrank(ETHEREUM_USDC_WHALE);
            ERC20(USDC).approve(address(nestVault), type(uint256).max);

            // Call the mint function, requesting to mint amount of NALPHA shares
            nestVault.mint(amount, wallet);

            vm.stopPrank();
        } else {
            deal(wallet, token, amount, false);
        }
    }
}
