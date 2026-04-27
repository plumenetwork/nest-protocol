// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "script/BaseScript.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";

/// @title  AuthFulfillRedeem
/// @notice Script to authorize fulfillRedeem on NestVaultOFT to be callable by owner
contract AuthFulfillRedeem is BaseScript {
    /// @notice The NestVault (ERC7540) contract address
    address public vault = 0x802E1f92A6890430bCF350Ad553C936fA425266c;

    /// @notice The RolesAuthority contract address
    address public authority = 0x9995311BF7Bf8675eeA58258bcf3f99bcFC18478;

    function run() external {
        address owner = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        RolesAuthority rolesAuthority = RolesAuthority(authority);

        // Set owner role for the deployer
        rolesAuthority.setUserRole(owner, OWNER_ROLE, true);

        // Authorize fulfillRedeem to be callable by OWNER_ROLE
        rolesAuthority.setRoleCapability(OWNER_ROLE, vault, bytes4(keccak256("fulfillRedeem(address,uint256)")), true);

        console.log("Authorized fulfillRedeem on vault:", vault);
        console.log("For owner:", owner);

        vm.stopBroadcast();
    }
}
