// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {DeployNestVaultOFT} from "script/DeployNestOFTProtocol/DeployNestVaultOFT.sol";
import {NestVaultConfig, Asset} from "script/L0Constants.sol";
import "forge-std/console.sol";

/// @title DeployNestVaultOFT_nTEST_USDC
/// @notice Deployment script for nTEST vault NestVaultOFT with USDC as underlying asset
/// @dev This script deploys a single NestVaultOFT for the nTEST vault with USDC asset.
///      Vault and asset configurations are read from L0Config.json.
///      Uses the shared ProxyAdmin from L0Config to manage the proxy.
///      To run: forge script script/DeployNestOFTProtocol/DeployNestVaultOFT_nTEST_USDC.s.sol --rpc-url $RPC_URL --broadcast
contract DeployNestVaultOFT_nTest_USDC is DeployNestVaultOFT {
    function run() public virtual override {
        deploySource();
    }

    /// @dev Override to only deploy NestVaultOFT for nTEST vault with USDC asset
    function deployOFTs() public override broadcastAs(oftDeployerPK) {
        require(broadcastConfig.nestVaultConfigs.length > 0, "No vault configs found");
        require(broadcastConfig.assets.length > 0, "No assets found");

        // Find nTEST vault
        NestVaultConfig memory nTestVaultConfig;
        bool foundVault = false;
        for (uint256 v = 0; v < broadcastConfig.nestVaultConfigs.length; v++) {
            if (isStringEqual(broadcastConfig.nestVaultConfigs[v].symbol, "nTEST")) {
                nTestVaultConfig = broadcastConfig.nestVaultConfigs[v];
                foundVault = true;
                break;
            }
        }
        require(foundVault, "nTEST vault not found in config");

        // Find USDC asset
        Asset memory usdcAsset;
        bool foundAsset = false;
        for (uint256 a = 0; a < broadcastConfig.assets.length; a++) {
            if (isStringEqual(broadcastConfig.assets[a].symbol, "USDC")) {
                usdcAsset = broadcastConfig.assets[a];
                foundAsset = true;
                break;
            }
        }
        require(foundAsset, "USDC asset not found in config");

        // Deploy NestVaultOFT for nTEST + USDC
        deployNestVaultOFT(nTestVaultConfig, usdcAsset);
    }

    /// @dev Override post-deployment checks for single vault deployment
    function postDeployChecks() internal view override {
        require(nestVaultOFTs.length == 1, "Should deploy exactly 1 NestVaultOFT (nTEST)");
        require(nestVaultOFTs[0] != address(0), "Invalid nTEST OFT proxy address");
    }
}
