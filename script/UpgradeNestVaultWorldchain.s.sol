// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {NestVault} from "contracts/NestVault.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

interface IProxyAdmin {
    function upgradeAndCall(ITransparentUpgradeableProxy proxy, address implementation, bytes memory data)
        external
        payable;
}

/// @title  UpgradeNestVaultWorldchain
/// @notice Script to upgrade NestVault implementations on Worldchain and set public capabilities for Permit2 functions
/// @dev    This script:
///         1. Deploys new NestVault implementations for each vault (nBASIS, nALPHA, nTBILL)
///         2. Simulates upgrades and setPublicCapability via prank (validates before execution)
///         3. Executes upgrades and setPublicCapability via broadcast
///
///         Usage:
///         forge script ./script/UpgradeNestVaultWorldchain.s.sol --rpc-url $WORLDCHAIN_RPC_URL --broadcast
contract UpgradeNestVaultWorldchain is Script {
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // ========================================= WORLDCHAIN ADDRESSES =========================================

    // nBASIS
    address constant NBASIS_NEST_VAULT = 0x5F35D1cef957467F4c7b35B36371355170A0DbB1;
    address constant NBASIS_ROLES_AUTHORITY = 0x5886A35bE0bD4533C2295C0e8083364ab0b27205;
    address payable constant NBASIS_NEST_SHARE_OFT = payable(0x11113Ff3a60C2450F4b22515cB760417259eE94B);

    // nALPHA
    address constant NALPHA_NEST_VAULT = 0x0342EE795e7864319fB8D48651b47feBf1163C34;
    address constant NALPHA_ROLES_AUTHORITY = 0xe04eD3c5b41B4F0B82F952d14aec5598B1092b15;
    address payable constant NALPHA_NEST_SHARE_OFT = payable(0x593cCcA4c4bf58b7526a4C164cEEf4003C6388db);

    // nTBILL
    address constant NTBILL_NEST_VAULT = 0x250c2D14Ed6376fB392FbA1edd2cfd11d2Bf7F12;
    address constant NTBILL_ROLES_AUTHORITY = 0x0A4F939b5D51157c58bA053275Eaf77a782B4996;
    address payable constant NTBILL_NEST_SHARE_OFT = payable(0xE72Fe64840F4EF80E3Ec73a1c749491b5c938CB9);

    // ProxyAdmin addresses
    address constant NBASIS_PROXY_ADMIN = 0xB4EFD5FC2950377965956306d5fFAf22E2412F59;
    address constant NALPHA_PROXY_ADMIN = 0xD7036e717c4E009B93064a18292E127183C69bEd;
    address constant NTBILL_PROXY_ADMIN = 0xCEC84Cac23a659217F10EE2A9476d6c4A8901067;

    // ProxyAdmin owner (same for all)
    address constant PROXY_ADMIN_OWNER = 0xc28e1cDfB582953fEf53f76C64426c2aC79C716e;

    // Function selectors for the new Permit2 functions
    bytes4 constant INSTANT_REDEEM_WITH_PERMIT2_SELECTOR =
        bytes4(keccak256("instantRedeemWithPermit2(uint256,address,address,uint256,uint256,bytes)"));
    bytes4 constant REQUEST_REDEEM_WITH_PERMIT2_SELECTOR =
        bytes4(keccak256("requestRedeemWithPermit2(uint256,address,address,uint256,uint256,bytes)"));

    uint256 deployerPrivateKey;

    function setUp() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function run() external {
        // ==================== STEP 1: Deploy implementations ====================
        vm.startBroadcast(deployerPrivateKey);

        NestVault nBasisImpl = new NestVault(NBASIS_NEST_SHARE_OFT, PERMIT2);
        console.log("nBASIS NestVault Implementation deployed at:", address(nBasisImpl));

        NestVault nAlphaImpl = new NestVault(NALPHA_NEST_SHARE_OFT, PERMIT2);
        console.log("nALPHA NestVault Implementation deployed at:", address(nAlphaImpl));

        NestVault nTbillImpl = new NestVault(NTBILL_NEST_SHARE_OFT, PERMIT2);
        console.log("nTBILL NestVault Implementation deployed at:", address(nTbillImpl));

        vm.stopBroadcast();

        // ==================== STEP 2: Simulate upgrades (prank) ====================
        console.log("\n========== SIMULATING UPGRADES ==========");
        vm.startPrank(PROXY_ADMIN_OWNER);

        IProxyAdmin(NBASIS_PROXY_ADMIN)
            .upgradeAndCall(ITransparentUpgradeableProxy(NBASIS_NEST_VAULT), address(nBasisImpl), "");
        console.log("nBASIS NestVault upgrade simulated");
        _setPublicCapabilities(NBASIS_ROLES_AUTHORITY, NBASIS_NEST_VAULT);
        console.log("nBASIS public capabilities simulated");

        IProxyAdmin(NALPHA_PROXY_ADMIN)
            .upgradeAndCall(ITransparentUpgradeableProxy(NALPHA_NEST_VAULT), address(nAlphaImpl), "");
        console.log("nALPHA NestVault upgrade simulated");
        _setPublicCapabilities(NALPHA_ROLES_AUTHORITY, NALPHA_NEST_VAULT);
        console.log("nALPHA public capabilities simulated");

        IProxyAdmin(NTBILL_PROXY_ADMIN)
            .upgradeAndCall(ITransparentUpgradeableProxy(NTBILL_NEST_VAULT), address(nTbillImpl), "");
        console.log("nTBILL NestVault upgrade simulated");
        _setPublicCapabilities(NTBILL_ROLES_AUTHORITY, NTBILL_NEST_VAULT);
        console.log("nTBILL public capabilities simulated");

        vm.stopPrank();
        console.log("========== SIMULATION SUCCESSFUL ==========\n");

        // ==================== STEP 3: Execute upgrades (broadcast) ====================
        vm.startBroadcast(deployerPrivateKey);

        IProxyAdmin(NBASIS_PROXY_ADMIN)
            .upgradeAndCall(ITransparentUpgradeableProxy(NBASIS_NEST_VAULT), address(nBasisImpl), "");
        console.log("nBASIS NestVault upgraded");
        _setPublicCapabilities(NBASIS_ROLES_AUTHORITY, NBASIS_NEST_VAULT);
        console.log("nBASIS public capabilities set");

        IProxyAdmin(NALPHA_PROXY_ADMIN)
            .upgradeAndCall(ITransparentUpgradeableProxy(NALPHA_NEST_VAULT), address(nAlphaImpl), "");
        console.log("nALPHA NestVault upgraded");
        _setPublicCapabilities(NALPHA_ROLES_AUTHORITY, NALPHA_NEST_VAULT);
        console.log("nALPHA public capabilities set");

        IProxyAdmin(NTBILL_PROXY_ADMIN)
            .upgradeAndCall(ITransparentUpgradeableProxy(NTBILL_NEST_VAULT), address(nTbillImpl), "");
        console.log("nTBILL NestVault upgraded");
        _setPublicCapabilities(NTBILL_ROLES_AUTHORITY, NTBILL_NEST_VAULT);
        console.log("nTBILL public capabilities set");

        vm.stopBroadcast();
    }

    /// @notice Sets public capabilities for the new Permit2 functions on a RolesAuthority
    function _setPublicCapabilities(address rolesAuthority, address nestVault) internal {
        RolesAuthority authority = RolesAuthority(rolesAuthority);

        // Set public capability for instantRedeemWithPermit2
        authority.setPublicCapability(nestVault, INSTANT_REDEEM_WITH_PERMIT2_SELECTOR, true);

        // Set public capability for requestRedeemWithPermit2
        authority.setPublicCapability(nestVault, REQUEST_REDEEM_WITH_PERMIT2_SELECTOR, true);
    }
}
