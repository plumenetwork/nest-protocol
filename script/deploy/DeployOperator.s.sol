// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";
import {NestVaultRedeemOperator} from "contracts/operators/NestVaultRedeemOperator.sol";
import {NestShareSeizer} from "contracts/compliance/NestShareSeizer.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {console} from "forge-std/console.sol";

/// @title  DeployOperator
/// @notice Deploys OperatorRegistry and NestVaultRedeemOperator.
/// @dev    Skips deployment if the contract address is already non-zero in the vault config.
///         The OperatorRegistry's authority is derived from predicateProxy.authority() (common authority).
///
///         Usage:
///           VAULT_SYMBOL=nTEST forge script script/deploy/DeployOperator.s.sol --sig "runDirect()" --rpc-url $RPC --broadcast
///           VAULT_SYMBOL=nTEST forge script script/deploy/DeployOperator.s.sol --sig "runMsig()" --rpc-url $RPC
contract DeployOperator is BaseConfigScript {
    function setUp() public {
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");
        loadConfigs(vaultSymbol);
    }

    function runDirect() external {
        _deploy(false);
    }

    function runMsig() external {
        _deploy(true);
        writeMsigBatch("DeployOperator");
    }

    function _deploy(bool _msigMode) internal directOrMsig(_msigMode) {
        // 1. Deploy OperatorRegistry if needed (non-upgradeable)
        if (needsDeploy(vaultConfig.common.operatorRegistry)) {
            // Derive common authority from predicateProxy
            Authority commonAuth = Authority(address(0));
            if (vaultConfig.common.predicateProxy.code.length > 0) {
                commonAuth = Auth(vaultConfig.common.predicateProxy).authority();
            }
            bytes32 salt = generateCreate3SaltCommon("OperatorRegistry");
            vaultConfig.common.operatorRegistry = CREATEX.deployCreate3(
                salt, abi.encodePacked(type(OperatorRegistry).creationCode, abi.encode(deployer(), commonAuth))
            );
            console.log("OperatorRegistry deployed:", vaultConfig.common.operatorRegistry);
        }

        // 2. Deploy NestVaultRedeemOperator if needed (upgradeable)
        if (needsDeploy(vaultConfig.common.redeemOperator)) {
            NestVaultRedeemOperator impl = new NestVaultRedeemOperator();
            bytes memory initData = abi.encodeWithSelector(NestVaultRedeemOperator.initialize.selector, deployer());
            bytes32 salt = generateCreate3SaltCommon("NestVaultRedeemOperator");
            vaultConfig.common.redeemOperator = CREATEX.deployCreate3(
                salt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode, abi.encode(address(impl), deployer(), initData)
                )
            );
            console.log("NestVaultRedeemOperator deployed:", vaultConfig.common.redeemOperator);
        }

        // 3. Deploy NestShareSeizer if needed (non-upgradeable)
        if (needsDeploy(vaultConfig.common.seizer)) {
            bytes32 salt = generateCreate3SaltCommon("NestShareSeizer");
            vaultConfig.common.seizer = CREATEX.deployCreate3(
                salt,
                abi.encodePacked(type(NestShareSeizer).creationCode, abi.encode(deployer(), Authority(address(0))))
            );
            console.log("NestShareSeizer deployed:", vaultConfig.common.seizer);
        }

        console.log("=== Operator Deployment Summary ===");
        console.log("OperatorRegistry:", vaultConfig.common.operatorRegistry);
        console.log("RedeemOperator:", vaultConfig.common.redeemOperator);
        console.log("Seizer:", vaultConfig.common.seizer);
        console.log("===================================");
    }
}
