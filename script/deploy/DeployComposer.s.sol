// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {ConfigReader, CCTPConfig, LZConfig, VaultEntry} from "script/lib/ConfigReader.sol";
import {NestCCTPRelayer} from "contracts/integrations/cctp/NestCCTPRelayer.sol";
import {NestVaultComposer} from "contracts/integrations/ovault/NestVaultComposer.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {console} from "forge-std/console.sol";

/// @title  DeployComposer
/// @notice Deploys NestCCTPRelayer and one NestVaultComposer per vault entry that needs one.
///         Deploy-only: relayer wiring (setComposer / setEidToDomain) and authority setup run in
///         DeployAndSetup's later `authority` step (_wireRelayer), which consumes this script's
///         standard deployment output artifact.
/// @dev    Skips deployment if the contract address is already non-zero in the vault config.
///         Raw CREATE3 deployments cannot be serialized into a Safe batch, so runMsig fails before
///         simulating whenever a relayer or composer still needs deployment.
///
///         Usage:
///           VAULT_SYMBOL=nTEST forge script script/deploy/DeployComposer.s.sol --sig "runDirect()" --rpc-url $RPC --broadcast
///           VAULT_SYMBOL=nTEST forge script script/deploy/DeployComposer.s.sol --sig "runMsig()" --rpc-url $RPC
contract DeployComposer is BaseConfigScript {
    function setUp() public {
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");
        loadConfigs(vaultSymbol);
        snapshotCommon();
        overlayDeploymentOutput();
    }

    function runDirect() external {
        _deploy(false);
    }

    function runMsig() external {
        _requireExistingDeploymentsForMsig();
        _deploy(true);
        writeMsigBatch("DeployComposer");
    }

    function _requireExistingDeploymentsForMsig() internal view {
        if (needsDeploy(vaultConfig.common.cctpRelayer)) {
            (bool hasCCTP,) = ConfigReader.tryReadCCTPConfig(vaultConfig.deployChainId);
            require(!hasCCTP, "DeployComposer: runMsig cannot deploy CCTP relayer; use runDirect");
        }

        if (!isActive(vaultConfig.common.cctpRelayer)) return;
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (!needsDeploy(ve.composer)) continue;
            if (keccak256(bytes(ve.assetSymbol)) != keccak256(bytes(vaultConfig.baseAssetSymbol))) continue;
            if (ve.addr.code.length == 0) continue;
            revert("DeployComposer: runMsig cannot deploy composer; use runDirect");
        }
    }

    function _deploy(bool _msigMode) internal directOrMsig(_msigMode) {
        // 1. Deploy NestCCTPRelayer if needed — only on chains with CCTP
        if (needsDeploy(vaultConfig.common.cctpRelayer)) {
            (bool hasCCTP, CCTPConfig memory cctpConfig) = ConfigReader.tryReadCCTPConfig(vaultConfig.deployChainId);
            if (!hasCCTP) {
                console.log("[SKIP] NestCCTPRelayer: no CCTP config for this chain");
            } else {
                address usdc = ConfigReader.readAssetAddress(vaultConfig.deployChainId, "USDC");
                NestCCTPRelayer cctpImpl = new NestCCTPRelayer(
                    cctpConfig.messageTransmitter, cctpConfig.tokenMessenger, lzConfig.endpoint, usdc
                );
                bytes memory initData = abi.encodeWithSelector(NestCCTPRelayer.initialize.selector, deployer());
                bytes32 salt = generateCreate3SaltCommon("NestCCTPRelayer");
                vaultConfig.common.cctpRelayer = CREATEX.deployCreate3(
                    salt,
                    abi.encodePacked(
                        type(TransparentUpgradeableProxy).creationCode,
                        abi.encode(address(cctpImpl), deployer(), initData)
                    )
                );
                console.log("NestCCTPRelayer deployed:", vaultConfig.common.cctpRelayer);
            }
        }

        // 2. Deploy one NestVaultComposer per vault entry that needs one (only for base asset)
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (!needsDeploy(ve.composer)) continue;
            if (keccak256(bytes(ve.assetSymbol)) != keccak256(bytes(vaultConfig.baseAssetSymbol))) continue;
            if (ve.addr.code.length == 0) continue; // vault not deployed on this chain yet
            if (!isActive(vaultConfig.common.cctpRelayer)) continue; // no asset OFT without CCTP relayer

            address complianceProxy = ConfigReader.readComplianceProxy(vaultConfig.deployChainId, vaultConfig.symbol);
            require(complianceProxy.code.length > 0, "DeployComposer: complianceProxy not deployed");
            NestVaultComposer composerImpl = new NestVaultComposer(complianceProxy);
            bytes memory initData = abi.encodeWithSelector(
                NestVaultComposer.initialize.selector,
                deployer(),
                ve.addr,
                isActive(vaultConfig.common.cctpRelayer) ? vaultConfig.common.cctpRelayer : address(0),
                isOFT() ? ve.addr : vaultConfig.contracts.share,
                vaultConfig.maxRetryableValue
            );
            bytes32 salt = generateCreate3SaltForAsset("NestVaultComposer", ve.assetSymbol);
            vaultConfig.vaults[i].composer = CREATEX.deployCreate3(
                salt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(address(composerImpl), deployer(), initData)
                )
            );
            console.log("NestVaultComposer deployed for", ve.assetSymbol, ":", vaultConfig.vaults[i].composer);
        }

        console.log("=== Composer Deployment Summary ===");
        console.log("CCTP Relayer:", vaultConfig.common.cctpRelayer);
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            if (vaultConfig.vaults[i].composer != address(0)) {
                console.log("Composer", vaultConfig.vaults[i].assetSymbol, ":", vaultConfig.vaults[i].composer);
            }
        }
        console.log("===================================");
        console.log("NOTE: deploy-only. Addresses are recorded in script/output/<symbol>/.");
        console.log("      Run DeployAndSetup STEPS=authority to consume that output and wire the relayer.");
        if (!msigMode) {
            writeDeploymentOutput();
            writeCommonConfigIfChanged();
        }
    }
}
