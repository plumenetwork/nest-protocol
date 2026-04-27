// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "script/BaseScript.sol";
import {NestVaultPredicateProxy, Authority} from "contracts/NestVaultPredicateProxy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {MockServiceManager} from "test/mock/MockServiceManager.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {NestVaultComposer} from "contracts/ovault/NestVaultComposer.sol";
import {NestCCTPRelayer, BaseCCTPRelayer} from "contracts/cctp/NestCCTPRelayer.sol";
import {OFTCore} from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";

// Setup initial roles configurations
// --- Roles ---
// 7. PREDICATE_PROXY_ROLE
//     - vault.deposit()
//     - vault.mint()
//     - assigned to PREDICATE_PROXY (contract)
// 8. CAN_SOLVE_ROLE
//     - vault.fulfillRedeem()
//     - assigned to KEEPER (EOA)
// --- Public Capabilities ---
//     - vault.send()
//     - vault.instantRedeem()
//     - vault.updateRedeem()
// --- Users / Role Assignments ---
// PREDICATE_PROXY_ROLE -> NestVaultPredicateProxy (contract)
// CAN_SOLVE_ROLE -> KEEPER (EOA)
// TELLER_ROLE -> NestVault (contract)
contract SetupVaultAuthority is BaseScript {
    address nestVault = 0x802E1f92A6890430bCF350Ad553C936fA425266c; // nestVault / oftVault
    address predicateProxy = 0xfC0c4222B3A0c9B060C0B959DEc62442036b9035; // nestVaultPredicateProxy
    address keeper = 0xB73d3D25D6F67f3cd077a43f6828BeE93cBc06F7; // nestVaultComposer
    address composer = 0xaFe1F7B0105c6Da9e79f886A20eb55F17a791aa1; // nestVaultComposer
    address _rolesAuthority = 0x9995311BF7Bf8675eeA58258bcf3f99bcFC18478;

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        RolesAuthority rolesAuthority = RolesAuthority(_rolesAuthority);

        //  --- Set Vault Roles Setup ---
        NestVaultComposer vault = NestVaultComposer(payable(nestVault));
        vault.setAuthority(Authority(address(rolesAuthority)));

        // --- Set Role Capabilities ---
        rolesAuthority.setRoleCapability(COMPOSER_ROLE, nestVault, INestVaultCore.instantRedeem.selector, true);
        rolesAuthority.setRoleCapability(CAN_SOLVE_ROLE, nestVault, INestVaultCore.fulfillRedeem.selector, true);
        predicateProxy != address(0)
            ? rolesAuthority.setRoleCapability(PREDICATE_PROXY_ROLE, nestVault, ERC4626.deposit.selector, true)
            : rolesAuthority.setPublicCapability(nestVault, ERC4626.deposit.selector, true);

        // --- Set Public Capabilities ---
        rolesAuthority.setPublicCapability(nestVault, OFTCore.send.selector, true);
        rolesAuthority.setPublicCapability(nestVault, INestVaultCore.updateRedeem.selector, true);

        // --- Assign roles to users ---
        if (predicateProxy != address(0)) rolesAuthority.setUserRole(predicateProxy, PREDICATE_PROXY_ROLE, true);
        rolesAuthority.setUserRole(nestVault, TELLER_ROLE, true);
        rolesAuthority.setUserRole(keeper, CAN_SOLVE_ROLE, true);
        rolesAuthority.setUserRole(composer, COMPOSER_ROLE, true);

        vm.stopBroadcast();
    }
}
