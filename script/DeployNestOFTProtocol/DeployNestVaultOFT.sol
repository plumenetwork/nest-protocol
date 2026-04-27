// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "../BaseL0Script.sol";
import {NestVaultConfig, Asset} from "script/L0Constants.sol";
import {ICreateX} from "createx/ICreateX.sol";

import {DeployNestProtocolOFT} from "script/DeployNestOFTProtocol/DeployNestProtocolOFT.sol";

/// @title DeployNestVaultOFT
/// @notice Deployment script for NestVaultOFT contracts - vault-backed omnichain fungible tokens
/// @dev Abstract contract that deploys NestVaultOFT for each (vault, asset) combination defined in L0Config.json.
///      NestVaultOFT represents vault shares that can be bridged across chains via LayerZero.
///
///      Deployment flow:
///      1. deployOFTs() - Deploys NestVaultOFT implementation and proxy for each vault/asset combo
///      2. setupSource() - Configures the source chain (enforced options, peers, DVNs, libs)
///      3. setupDestinations() (inherited) - Generates transaction batches for destination chains
///
///      To create a specific vault deployment, inherit from this contract and override:
///      - deployOFTs(): To deploy specific vault(s)
///      - postDeployChecks(): To validate specific deployment requirements
abstract contract DeployNestVaultOFT is DeployNestProtocolOFT {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setupSource() public virtual override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        setupNonEvms();

        /// @dev configures legacy configs as well
        setDVNs({_connectedConfig: broadcastConfig, _connectedOfts: nestVaultOFTs, _configs: allConfigs});

        setLibs({_connectedConfig: broadcastConfig, _connectedOfts: nestVaultOFTs, _configs: allConfigs});

        setPriviledgedRoles();
    }

    function setupDestination(L0Config memory _connectedConfig) public override simulateAndWriteTxs(_connectedConfig) {
        setEvmEnforcedOptions({_connectedOfts: connectedOfts, _config: broadcastConfig});

        setEvmPeers({_connectedOfts: connectedOfts, _peerOfts: nestVaultOFTs, _config: broadcastConfig});

        setDVNs({_connectedConfig: _connectedConfig, _connectedOfts: connectedOfts, _config: broadcastConfig});

        setLibs({_connectedConfig: _connectedConfig, _connectedOfts: connectedOfts, _config: broadcastConfig});
    }

    function setupEvms() public {
        setEvmEnforcedOptions({_connectedOfts: nestVaultOFTs, _configs: proxyConfigs});

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({_connectedOfts: nestVaultOFTs, _peerOfts: nestVaultOFTs, _configs: proxyConfigs});
    }

    function setupNonEvms() public {
        // TODO : ensure deployments happen

        setSolanaEnforcedOptions({_connectedOfts: nestVaultOFTs});

        /// @dev additional enforced options for non-evms set here

        setNonEvmPeers({_connectedOfts: nestVaultOFTs});
    }

    function deployOFTs() public virtual override broadcastAs(oftDeployerPK) {
        // Deploy one NestVaultOFT per (vault, asset) combination
        for (uint256 v = 0; v < broadcastConfig.nestVaultConfigs.length; v++) {
            for (uint256 a = 0; a < broadcastConfig.assets.length; a++) {
                deployNestVaultOFT(broadcastConfig.nestVaultConfigs[v], broadcastConfig.assets[a]);
            }
        }
    }

    function deployNestVaultOFT(NestVaultConfig memory _nestVaultConfig, Asset memory _asset)
        public
        returns (address implementation, address proxy)
    {
        // Deploy the implementation
        implementation =
            address(new NestVaultOFT(payable(_nestVaultConfig.boringVault), broadcastConfig.endpoint, PERMIT2));

        // Prepare initialization arguments
        /// @dev broadcastConfig deployer is temporary OFT owner until setPriviledgedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            NestVaultOFT.initialize.selector,
            _nestVaultConfig.accountant, // _accountantWithRateProviders
            _asset.assetAddress, // _asset
            vm.addr(oftDeployerPK), // _delegate (LayerZero delegate)
            vm.addr(oftDeployerPK), // _owner (Auth owner)
            1, // _minRate
            address(0) // _operatorRegistry
        );

        // Deploy proxy deterministically using CREATE3
        // Include both vault symbol and asset symbol in salt for uniqueness
        string memory saltString = string.concat(
            "NestVaultOFT",
            _nestVaultConfig.symbol,
            "_",
            _asset.symbol,
            "_",
            Strings.toHexString(uint160(_nestVaultConfig.boringVault), 20)
        );
        bytes32 salt = generateCreate3Salt(vm.addr(oftDeployerPK), saltString);

        // Deploy TransparentUpgradeableProxy with the existing ProxyAdmin from L0Config
        // This directly uses the shared ProxyAdmin without creating a new one
        bytes memory creationCode = type(TransparentUpgradeableProxy).creationCode;
        proxy = CREATEX.deployCreate3(
            salt,
            abi.encodePacked(
                creationCode,
                abi.encode(
                    implementation, // _logic
                    vm.addr(oftDeployerPK), // _admin
                    initializeArgs // _data
                )
            )
        );

        // Add to nestVaultOFTs array
        nestVaultOFTs.push(proxy);

        // Log deployment information
        console.log("=== NestVaultOFT Deployed ===");
        console.log("Vault Symbol:", _nestVaultConfig.symbol);
        console.log("Asset Symbol:", _asset.symbol);
        console.log("Asset Address:", _asset.assetAddress);
        console.log("Implementation:", implementation);
        console.log("Proxy:", proxy);
        console.log("Boring Vault:", _nestVaultConfig.boringVault);
        console.log("============================");

        // State checks
        require(NestVaultOFT(proxy).share() == _nestVaultConfig.boringVault, "NestVaultOFT share incorrect");
        require(address(NestVaultOFT(proxy).endpoint()) == broadcastConfig.endpoint, "NestVaultOFT endpoint incorrect");
        require(NestVaultOFT(proxy).owner() == vm.addr(configDeployerPK), "NestVaultOFT owner incorrect");
    }

    function postDeployChecks() internal view virtual override {
        // Expected number is vaults * assets
        uint256 expectedCount = broadcastConfig.nestVaultConfigs.length * broadcastConfig.assets.length;
        require(nestVaultOFTs.length == expectedCount, "Did not deploy all NestVaultOFTs (vaults * assets)");

        // Verify each deployed OFT
        for (uint256 i = 0; i < nestVaultOFTs.length; i++) {
            require(nestVaultOFTs[i] != address(0), "Invalid OFT proxy address");
        }
    }

    function _validateAndPopulateMainnetOfts() internal override {
        // @dev Populate connectedOfts from the deployed nestVaultOFTs
        // The nestVaultOFTs array is filled during deployment in deployNestVaultOFT()
        require(nestVaultOFTs.length > 0, "nestVaultOFTs not yet deployed");

        for (uint256 i = 0; i < nestVaultOFTs.length; i++) {
            connectedOfts.push(nestVaultOFTs[i]);
        }
    }

    function setPriviledgedRoles() public {
        /// @dev transfer ownership of OFT
        for (uint256 o = 0; o < nestVaultOFTs.length; o++) {
            address proxyOft = nestVaultOFTs[o];
            NestVaultOFT(proxyOft).setDelegate(broadcastConfig.delegate);
            NestVaultOFT(proxyOft).transferOwnership(broadcastConfig.delegate);
            // TODO : delegate should accept ownership
            // TODO : proxyAdmin's owner need to transferred to msig
        }
    }
}
