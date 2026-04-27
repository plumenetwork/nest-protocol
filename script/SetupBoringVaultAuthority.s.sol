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
// 2. MANAGER_ROLE
//     - share.manage()
//     - assigned to MANAGER (multisig)
// 3. TELLER_ROLE
//     - share.enter()
//     - share.exit()
//     - assigned to NestVault (contract)
// --- Users / Role Assignments ---
// TELLER_ROLE -> NestVault (contract)
// MANAGER_ROLE -> MANAGER (multisig)
contract SetupShareAuthority is BaseScript {
    address share = 0xED7AeA61da92f901983bD85b63ba7d217797e405; // nestShare / boringVault
    address nestVault = 0x802E1f92A6890430bCF350Ad553C936fA425266c; // nestVault / oftVault
    address manager = 0x8faf62874821D064907ac04752096Cbad06B7b94;
    address _rolesAuthority = 0x9995311BF7Bf8675eeA58258bcf3f99bcFC18478;

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        RolesAuthority rolesAuthority = RolesAuthority(_rolesAuthority);

        // --- Set Role Capabilities ---
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, share, bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)"))), true
        );

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, share, bytes4(keccak256(abi.encodePacked("manage(address[],bytes[],uint256[])"))), true
        );

        rolesAuthority.setRoleCapability(TELLER_ROLE, share, NestShareOFT.enter.selector, true);
        rolesAuthority.setRoleCapability(TELLER_ROLE, share, NestShareOFT.exit.selector, true);

        // --- Assign roles to users ---
        rolesAuthority.setUserRole(nestVault, TELLER_ROLE, true);
        rolesAuthority.setUserRole(manager, MANAGER_ROLE, true);

        vm.stopBroadcast();
    }
}
