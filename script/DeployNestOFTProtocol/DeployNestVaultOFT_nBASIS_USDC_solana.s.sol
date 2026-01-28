// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {DeployNestVaultOFT} from "script/DeployNestOFTProtocol/DeployNestVaultOFT.sol";
import {NestVaultConfig, L0Config, Asset} from "script/L0Constants.sol";
import "forge-std/console.sol";

/// @title DeployNestVaultOFT_nBASIS_USDC_solana
/// @notice Deployment script for nBASIS vault NestVaultOFT with USDC as underlying asset, Solana peer mapping
/// @dev This script deploys a single NestVaultOFT for the nBASIS vault with USDC asset.
///      - Vault and asset configurations are read from L0Config.json.
///      - Peer mapping for Solana is read from NonEvmPeers.json, which is a flat array of peers with an `eid` field for direct mapping to L0Config.json#Non-EVM.
///      - Only the peer with symbol "nBASIS" and matching eid is set for Solana.
///      - Uses the shared ProxyAdmin from L0Config to manage the proxy.
///      - The minRate is set to 1 in the deployment.
///      To run: forge script script/DeployNestOFTProtocol/DeployNestVaultOFT_nBASIS_USDC_solana.s.sol:DeployNestVaultOFT_nBASIS_USDC_solana --rpc-url $RPC_URL --broadcast
contract DeployNestVaultOFT_nBASIS_USDC_solana is DeployNestVaultOFT {
    function run() public virtual override {
        deploySource();
        setupSource();
    }

    /// @dev Override to only deploy NestVaultOFT for nBASIS vault with USDC asset
    function deployOFTs() public override broadcastAs(oftDeployerPK) {
        require(broadcastConfig.nestVaultConfigs.length > 0, "No vault configs found");
        require(broadcastConfig.assets.length > 0, "No assets found");

        // Find nBASIS vault
        NestVaultConfig memory nBasisVaultConfig;
        bool foundVault = false;
        for (uint256 v = 0; v < broadcastConfig.nestVaultConfigs.length; v++) {
            if (isStringEqual(broadcastConfig.nestVaultConfigs[v].symbol, "nBASIS")) {
                nBasisVaultConfig = broadcastConfig.nestVaultConfigs[v];
                foundVault = true;
                break;
            }
        }
        require(foundVault, "nBASIS vault not found in config");

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

        // Deploy NestVaultOFT for nBASIS + USDC
        deployNestVaultOFT(nBasisVaultConfig, usdcAsset);
    }

    /// @dev Override post-deployment checks for single vault deployment
    function postDeployChecks() internal view override {
        require(nestVaultOFTs.length == 1, "Should deploy exactly 1 NestVaultOFT (nBASIS)");
        require(nestVaultOFTs[0] != address(0), "Invalid nBASIS OFT proxy address");
    }

    function setupSource() public override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupNonEvms();

        /// @dev configures legacy configs as well
        setDVNs({_connectedConfig: broadcastConfig, _connectedOfts: nestVaultOFTs, _configs: nonEvmConfigs});

        setLibs({_connectedConfig: broadcastConfig, _connectedOfts: nestVaultOFTs, _configs: nonEvmConfigs});
    }

    function setNonEvmPeers(address[] memory _connectedOfts) public override {
        // Only set peer for Solana (eid match) and only if symbol is nBASIS.
        // Peers are mapped by eid (from NonEvmPeers.json) to the corresponding L0Config non-EVM entry.
        // This ensures robust, order-independent mapping between config and peer for Solana.
        if (_nonEvmPeersArrays.length == 0) return;
        uint32 solanaEid = uint32(nonEvmConfigs[0].eid);
        uint256 peerCount = 0;
        for (uint256 i = 0; i < _nonEvmPeersArrays.length; i++) {
            if (_nonEvmPeersArrays[i].eid == solanaEid && isStringEqual(_nonEvmPeersArrays[i].symbol, "nBASIS")) {
                if (peerCount < _connectedOfts.length) {
                    setPeer({
                        _config: nonEvmConfigs[0],
                        _connectedOft: _connectedOfts[peerCount],
                        _peerOftAsBytes32: _nonEvmPeersArrays[i].addressBytes32
                    });
                    peerCount++;
                }
            }
        }
    }
}
