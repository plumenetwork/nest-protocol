// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {DeployNestShareOFT} from "script/DeployNestOFTProtocol/DeployNestShareOFT.sol";
import {NestShareConfig, Asset} from "script/L0Constants.sol";
import "forge-std/console.sol";
import {L0Config} from "script/L0Constants.sol";

/// @title DeployNestShareOFT_nTBILL_USDC
/// @notice Deployment script for nTBILL share NestShareOFT with USDC as underlying asset
/// @dev This script deploys NestShareOFT for the nTBILL share with USDC asset.
///      Share and asset configurations are read from L0Config.json.
///      Uses the shared ProxyAdmin from L0Config to manage the proxy.
///      To run: forge script script/DeployNestOFTProtocol/DeployNestShareOFT_nTBILL_USDC.s.sol --rpc-url $RPC_URL --broadcast
contract DeployNestShareOFT_nTBILL_USDC is DeployNestShareOFT {
    L0Config[] public tempConfigs;

    function run() public override {
        for (uint256 i; i < proxyConfigs.length; i++) {
            // Set up destinations for Plume and this chain only
            if (proxyConfigs[i].chainid == 98866 || proxyConfigs[i].chainid == broadcastConfig.chainid) {
                tempConfigs.push(proxyConfigs[i]);
            }
        }
        require(tempConfigs.length == 2, "Incorrect tempConfigs array");
        delete proxyConfigs;
        for (uint256 i = 0; i < tempConfigs.length; i++) {
            proxyConfigs.push(tempConfigs[i]);
        }
        delete tempConfigs;
        deploySource();
        setupSource();
        setupDestinations();
    }

    function setupSource() public override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        setupNonEvms();

        /// @dev configures legacy configs as well
        setDVNs({_connectedConfig: broadcastConfig, _connectedOfts: nestShareOFTs, _configs: proxyConfigs});

        setLibs({_connectedConfig: broadcastConfig, _connectedOfts: nestShareOFTs, _configs: proxyConfigs});

        // setPrivilegedRoles();
    }

    function setupEvms() public override {
        setEvmEnforcedOptions({_connectedOfts: nestShareOFTs, _configs: proxyConfigs});
        address[] memory nestVaultOfts = new address[](1);
        nestVaultOfts[0] = expectedNestVaultOfts[3]; // index 3 for nTBILL
        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({_connectedOfts: nestShareOFTs, _peerOfts: nestVaultOfts, _configs: proxyConfigs});
    }

    /// @dev Override to only deploy NestShareOFT for nTBILL share with USDC asset
    function deployOFTs() public override broadcastAs(oftDeployerPK) {
        require(broadcastConfig.nestShareConfigs.length > 0, "No share configs found");
        require(broadcastConfig.assets.length > 0, "No assets found");

        // Find nTBILL share
        NestShareConfig memory nTbillShareConfig;
        bool foundShare = false;
        for (uint256 v = 0; v < broadcastConfig.nestShareConfigs.length; v++) {
            if (isStringEqual(broadcastConfig.nestShareConfigs[v].symbol, "nTBILL")) {
                nTbillShareConfig = broadcastConfig.nestShareConfigs[v];
                foundShare = true;
                break;
            }
        }
        require(foundShare, "nTBILL share not found in config");

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

        // 1. deploy RolesAuthority
        deployRolesAuthority(nTbillShareConfig);
        // 2. deploy NestShareOFT
        (, address _nestShareOFT) = deployNestShareOFT(nTbillShareConfig);
        // 3. deploy NestAccountant
        (, address _nestAccountant) = deployNestAccountant(nTbillShareConfig, _nestShareOFT, usdcAsset.assetAddress);
        // 4. deploy NestVault
        deployNestVault(nTbillShareConfig, _nestShareOFT, _nestAccountant, usdcAsset.assetAddress);
    }

    /// @dev Override post-deployment checks for single share deployment
    function postDeployChecks() internal view override {
        require(nestShareOFTs.length == 1, "Should deploy exactly 1 NestShareOFT (nTBILL)");
        require(nestShareOFTs[0] != address(0), "Invalid nTBILL OFT proxy address");
    }

    function setupNonEvms() public override {}

    function _validateAndPopulateMainnetOfts() internal virtual override {
        // @dev Populate connectedOfts from the deployed nestShareOFTs
        // The nestShareOFTs array is filled during deployment in deployNestShareOFT()
        // require(nestShareOFTs.length > 0, "nestShareOFTs not yet deployed");
        if (nestShareOFTs.length == 0) {
            for (uint256 i = 0; i < expectedNestShareOfts.length; i++) {
                nestShareOFTs.push(expectedNestShareOfts[i]);
            }
        } else {
            require(nestShareOFTs.length == 1, "nestShareOFTs.length != 1");
        }

        connectedOfts = new address[](1);

        connectedOfts[0] = expectedNestVaultOfts[3]; //index 3 is nTBILLVaultOFT_USDC
    }

    function getPeerFromArray(address _oft, address[] memory _oftArray) public view override returns (address peer) {
        require(_oftArray.length == 1, "getPeerFromArray index mismatch");
        require(_oft != address(0), "getPeerFromArray() OFT == address(0)");
        /// @dev maintains array from deployNestVaultOFTs(), where nestVaultOFTs is pushed to in the respective order
        peer = _oftArray[0];
    }

    function getFileExtension() internal view override returns (string memory) {
        return "-nTBILL_USDC.json";
    }
}
