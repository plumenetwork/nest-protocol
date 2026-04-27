// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "script/BaseScript.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {INestVaultComposer} from "contracts/interfaces/ovault/INestVaultComposer.sol";
import {IVaultComposerSync} from "@layerzerolabs/ovault-evm/contracts/interfaces/IVaultComposerSync.sol";

/// @title  AuthRelayer
/// @notice Script to authorize fulfillRedeem on NestVaultOFT to be callable by owner
contract AuthRelayer is BaseScript {
    /// @notice The NestVault (ERC7540) contract address
    address public vault = 0x802E1f92A6890430bCF350Ad553C936fA425266c;

    /// @notice The RolesAuthority contract address
    address public authority = 0x9995311BF7Bf8675eeA58258bcf3f99bcFC18478;

    address public relayer = 0xba6B17f33e1eb0593B3CB876A57C5BC8F4fEcedE;

    address public composer = 0xb009Ae185dcc23419d2D1e4abdC42FC30648DacB;

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        RolesAuthority rolesAuthority = RolesAuthority(authority);

        // Grant the relayer role access to both the explicit relayer entrypoints and the auth-gated sync overloads.
        rolesAuthority.setRoleCapability(RELAYER_ROLE, composer, INestVaultComposer.depositAndSend.selector, true);
        rolesAuthority.setRoleCapability(RELAYER_ROLE, composer, INestVaultComposer.redeemAndSend.selector, true);
        rolesAuthority.setRoleCapability(RELAYER_ROLE, composer, IVaultComposerSync.depositAndSend.selector, true);
        rolesAuthority.setRoleCapability(RELAYER_ROLE, composer, IVaultComposerSync.redeemAndSend.selector, true);

        // Remove legacy public access on the inherited sync overloads.
        rolesAuthority.setPublicCapability(composer, IVaultComposerSync.depositAndSend.selector, false);
        rolesAuthority.setPublicCapability(composer, IVaultComposerSync.redeemAndSend.selector, false);

        console.log("Authorized relater on composer:");

        vm.stopBroadcast();
    }
}
