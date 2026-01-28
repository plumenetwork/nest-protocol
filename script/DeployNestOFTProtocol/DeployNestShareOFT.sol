// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "../BaseL0Script.sol";
import {ICreateX} from "createx/ICreateX.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {NestAccountant} from "contracts/NestAccountant.sol";
import {DeployNestProtocolOFT} from "script/DeployNestOFTProtocol/DeployNestProtocolOFT.sol";

/// @title DeployNestShareOFT
/// @notice Deployment script for NestShareOFT contracts - standalone omnichain fungible tokens
/// @dev Abstract contract that deploys NestShareOFT for each share configuration defined in L0Config.json.
///      NestShareOFT represents standalone tokens that can be bridged across chains via LayerZero.
///
///      Deployment flow:
///      1. deployOFTs() - Deploys NestShareOFT implementation and proxy for each share config
///      2. setupSource() - Configures the source chain (enforced options, peers, DVNs, libs)
///      3. setupDestinations() (inherited) - Generates transaction batches for destination chains
///
///      To create a specific share deployment, inherit from this contract and override:
///      - deployOFTs(): To deploy specific share token(s)
///      - postDeployChecks(): To validate specific deployment requirements
abstract contract DeployNestShareOFT is DeployNestProtocolOFT {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    function setupSource() public virtual override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        setupNonEvms();

        /// @dev configures legacy configs as well
        setDVNs({_connectedConfig: broadcastConfig, _connectedOfts: nestShareOFTs, _configs: allConfigs});

        setLibs({_connectedConfig: broadcastConfig, _connectedOfts: nestShareOFTs, _configs: allConfigs});

        setPrivilegedRoles();
    }

    function setupDestination(L0Config memory _connectedConfig) public override simulateAndWriteTxs(_connectedConfig) {
        setEvmEnforcedOptions({_connectedOfts: connectedOfts, _config: broadcastConfig});

        setEvmPeers({_connectedOfts: connectedOfts, _peerOfts: nestShareOFTs, _config: broadcastConfig});

        setDVNs({_connectedConfig: _connectedConfig, _connectedOfts: connectedOfts, _config: broadcastConfig});

        setLibs({_connectedConfig: _connectedConfig, _connectedOfts: connectedOfts, _config: broadcastConfig});
    }

    function setupEvms() public virtual {
        setEvmEnforcedOptions({_connectedOfts: nestShareOFTs, _configs: proxyConfigs});

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({_connectedOfts: nestShareOFTs, _peerOfts: expectedNestVaultOfts, _configs: proxyConfigs});
    }

    function setupNonEvms() public virtual {
        require(nestShareOFTs.length == 5, "Error: non-evm setup will be incorrect");

        setSolanaEnforcedOptions({_connectedOfts: nestShareOFTs});

        /// @dev additional enforced options for non-evms set here

        setNonEvmPeers({_connectedOfts: nestShareOFTs});
    }

    function deployOFTs() public virtual override broadcastAs(oftDeployerPK) {
        // Deploy one NestShareOFT per (share, asset) combination
        for (uint256 v = 0; v < broadcastConfig.nestShareConfigs.length; v++) {
            for (uint256 a = 0; a < broadcastConfig.assets.length; a++) {
                // 1. deploy RolesAuthority
                deployRolesAuthority(broadcastConfig.nestShareConfigs[v]);
                // 2. deploy NestShareOFT
                (, address _nestShareOFT) = deployNestShareOFT(broadcastConfig.nestShareConfigs[v]);
                // 3. deploy NestAccountant
                (, address _nestAccountant) = deployNestAccountant(
                    broadcastConfig.nestShareConfigs[v], _nestShareOFT, broadcastConfig.assets[a].assetAddress
                );
                // 4. deploy NestVault
                deployNestVault(
                    broadcastConfig.nestShareConfigs[v],
                    _nestShareOFT,
                    _nestAccountant,
                    broadcastConfig.assets[a].assetAddress
                );
            }
        }
    }

    function deployRolesAuthority(NestShareConfig memory nestShareConfig) public returns (address) {
        // Deploy RolesAuthority using CREATE3 for deterministic addresses (non-upgradeable)
        string memory saltString =
            string.concat("RolesAuthority", "-", nestShareConfig.name, "-", nestShareConfig.symbol);
        bytes32 salt = generateCreate3Salt(vm.addr(oftDeployerPK), saltString);

        bytes memory creationCode = type(RolesAuthority).creationCode;
        address rolesAuthority = CREATEX.deployCreate3(
            salt,
            abi.encodePacked(
                creationCode,
                abi.encode(
                    vm.addr(oftDeployerPK), // owner
                    Authority(address(0)) // authority
                )
            )
        );
        console.log("=== RolesAuthority Deployed ===");
        console.log("Address:", rolesAuthority);
        console.log("===============================");
        return rolesAuthority;
    }

    function deployNestShareOFT(NestShareConfig memory nestShareConfig)
        public
        returns (address implementation, address proxy)
    {
        // Deploy the NestShareOFT implementation
        implementation = address(new NestShareOFT(broadcastConfig.endpoint));

        // Prepare initialization arguments
        /// @dev broadcastConfig deployer is temporary OFT owner until setPrivilegedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            NestShareOFT.initialize.selector,
            nestShareConfig.name, // name
            nestShareConfig.symbol, // symbol
            vm.addr(oftDeployerPK), // owner
            vm.addr(oftDeployerPK) // delegate
        );

        // Deploy proxy deterministically using CREATE3
        string memory saltString = string.concat("NestShareOFT", "-", nestShareConfig.symbol);
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

        // Add to nestShareOFTs array
        nestShareOFTs.push(proxy);

        // Log deployment information
        console.log("=== NestShareOFT Deployed ===");
        console.log("Share Symbol:", nestShareConfig.symbol);
        console.log("Implementation:", implementation);
        console.log("Proxy:", proxy);
        console.log("============================");

        // State checks
        require(NestShareOFT(proxy).owner() == vm.addr(oftDeployerPK), "NestShareOFT owner incorrect");
        require(address(NestShareOFT(proxy).endpoint()) == broadcastConfig.endpoint, "NestShareOFT endpoint incorrect");
    }

    function deployNestAccountant(NestShareConfig memory nestShareConfig, address nestShareOFT, address asset)
        public
        returns (address implementation, address proxy)
    {
        // Deploy the NestAccountant implementation
        implementation = address(new NestAccountant(asset, nestShareOFT));

        // Prepare initialization arguments
        bytes memory initializeArgs = abi.encodeWithSelector(
            NestAccountant.initialize.selector,
            0, // totalSharesLastUpdate
            vm.addr(oftDeployerPK), // payoutAddress
            1000000, // startingExchangeRate
            10003, // allowedExchangeRateChangeUpper
            10000, // allowedExchangeRateChangeLower
            3600, // minimumUpdateDelayInSeconds
            0, // managementFee
            vm.addr(oftDeployerPK) // owner
        );

        // Deploy proxy deterministically using CREATE3
        string memory saltString =
            string.concat("NestAccountant", "-", nestShareConfig.name, "-", nestShareConfig.symbol);
        bytes32 salt = generateCreate3Salt(vm.addr(oftDeployerPK), saltString);

        // Deploy TransparentUpgradeableProxy with the existing ProxyAdmin from L0Config
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

        console.log("=== NestAccountant Deployed ===");
        console.log("Share Symbol:", nestShareConfig.symbol);
        console.log("Implementation:", implementation);
        console.log("Proxy:", proxy);
        console.log("NestShareOFT:", nestShareOFT);
        console.log("===============================");

        // State checks
        require(NestAccountant(proxy).owner() == vm.addr(oftDeployerPK), "NestAccountant owner incorrect");
    }

    function deployNestVault(
        NestShareConfig memory nestShareConfig,
        address nestShareOFT,
        address nestAccountant,
        address asset
    ) public returns (address implementation, address proxy) {
        // Deploy the NestVault implementation
        implementation = address(new NestVault(payable(nestShareOFT)));

        // Prepare initialization arguments
        bytes memory initializeArgs = abi.encodeWithSelector(
            NestVault.initialize.selector,
            nestAccountant, // accountantWithRateProviders
            asset, // asset
            vm.addr(oftDeployerPK), // owner
            100000 // minRate
        );

        // Deploy proxy deterministically using CREATE3
        string memory saltString = string.concat("NestVault", "-", nestShareConfig.name, "-", nestShareConfig.symbol);
        bytes32 salt = generateCreate3Salt(vm.addr(oftDeployerPK), saltString);

        // Deploy TransparentUpgradeableProxy with the existing ProxyAdmin from L0Config
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

        console.log("=== NestVault Deployed ===");
        console.log("Implementation:", implementation);
        console.log("Proxy:", proxy);
        console.log("==========================");

        // State checks
        require(NestVault(proxy).owner() == vm.addr(oftDeployerPK), "NestVault owner incorrect");
    }

    function postDeployChecks() internal view virtual override {
        // Expected number is shares * assets
        uint256 expectedCount = broadcastConfig.nestShareConfigs.length * broadcastConfig.assets.length;
        require(nestShareOFTs.length == expectedCount, "Did not deploy all NestShareOFTs (shares * assets)");

        // Verify each deployed OFT
        for (uint256 i = 0; i < nestShareOFTs.length; i++) {
            require(nestShareOFTs[i] != address(0), "Invalid OFT proxy address");
        }
    }

    function _validateAndPopulateMainnetOfts() internal virtual override {
        // @dev Populate connectedOfts from the deployed nestShareOFTs
        // The nestShareOFTs array is filled during deployment in deployNestShareOFT()
        // require(nestShareOFTs.length > 0, "nestShareOFTs not yet deployed");
        if (nestShareOFTs.length == 0) {
            for (uint256 i = 0; i < expectedNestShareOfts.length; i++) {
                nestShareOFTs.push(expectedNestShareOfts[i]);
            }
        } else {
            require(nestShareOFTs.length == 5, "nestShareOFTs.length != 5");
        }

        connectedOfts = new address[](5);

        connectedOfts[0] = expectedNestShareOfts[0];
        connectedOfts[1] = expectedNestShareOfts[1];
        connectedOfts[2] = expectedNestShareOfts[2];
        connectedOfts[3] = expectedNestShareOfts[3];
        connectedOfts[4] = expectedNestShareOfts[4];
    }

    function setPrivilegedRoles() public {
        /// @dev transfer ownership of OFT
        for (uint256 o = 0; o < nestShareOFTs.length; o++) {
            address proxyOft = nestShareOFTs[o];
            NestShareOFT(proxyOft).setDelegate(broadcastConfig.delegate);
            NestShareOFT(proxyOft).transferOwnership(broadcastConfig.delegate);
            // TODO : delegate should accept ownership
            // TODO : proxyAdmin's owner need to transferred to msig
        }
    }
}
