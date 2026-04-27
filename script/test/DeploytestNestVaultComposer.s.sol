// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "script/BaseScript.sol";
import {NestCCTPRelayer} from "contracts/cctp/NestCCTPRelayer.sol";
import {NestVaultComposer} from "contracts/ovault/NestVaultComposer.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";

/// @title  DeployNestCCTPRelayerAndComposer
/// @notice Deployment script for the NestCCTPRelayer and NestVaultComposer contracts
/// @dev    Deploys implementations and TransparentUpgradeableProxy for both contracts
///
///         NestCCTPRelayer is a cross-chain USDC relayer that:
///         - Bridges USDC tokens using Circle's CCTP (Cross-Chain Transfer Protocol)
///         - Implements the LayerZero IOFT interface for cross-chain messaging
///         - Integrates with NestVaultComposer for deposit/redeem operations
///         - Supports finality thresholds and fee management
///
///         NestVaultComposer is a cross-chain vault composer that integrates with:
///         - NestVault (ERC7540 vault) for deposit/redeem operations
///         - NestVaultPredicateProxy for predicate verification on cross-chain operations
///         - LayerZero OFT contracts for cross-chain asset/share transfers
///         - CCTP for cross-chain USDC transfers
///
///         The composer handles the following redeem types:
///         - INSTANT: Immediate redemption if liquidity available
///         - REQUEST: Request async redemption (pending state)
///         - UPDATE_REQUEST: Modify existing redemption request
///         - REDEEM: Complete redemption by share amount (after fulfillment)
///         - WITHDRAW: Complete redemption by asset amount (after fulfillment)
///
///         Post-deployment configuration for NestCCTPRelayer:
///         - setEidToDomain: Map LayerZero endpoint IDs to CCTP domains
///         - setFinalityThreshold: Set minimum finality for message relaying
///         - setComposer: Whitelist VaultComposer contracts
///         - setMaxFeeBasisPoints: Configure maximum relay fees
contract DeployNestCCTPRelayerAndComposer is BaseScript {
    /*//////////////////////////////////////////////////////////////
                            COMMON CONFIG
    //////////////////////////////////////////////////////////////*/

    /// @notice The owner address for the deployed contracts and ProxyAdmin
    address public owner;

    /// @notice The LayerZero endpoint address
    address public endpoint = 0xC1b15d3B262bEeC0e3565C11C9e0F6134BdaCB36;

    /*//////////////////////////////////////////////////////////////
                        NEST CCTP RELAYER CONFIG
    //////////////////////////////////////////////////////////////*/

    /// @notice The CCTP MessageTransmitter contract address
    address public messageTransmitter = 0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;

    /// @notice The CCTP TokenMessenger contract address
    address public tokenMessenger = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;

    /// @notice The USDC token address
    address public usdc = 0x222365EF19F7947e5484218551B56bb3965Aa7aF;

    /*//////////////////////////////////////////////////////////////
                      NEST VAULT COMPOSER CONFIG
    //////////////////////////////////////////////////////////////*/

    /// @notice The NestVaultPredicateProxy contract address (immutable in constructor)
    address public predicateProxy = 0xfC0c4222B3A0c9B060C0B959DEc62442036b9035;

    /// @notice The NestVault (ERC7540) contract address
    address public vault = 0x802E1f92A6890430bCF350Ad553C936fA425266c;

    /// @notice The share OFT contract address (e.g., NestVaultOFT)
    address public shareOFT = 0x802E1f92A6890430bCF350Ad553C936fA425266c;

    address public authority = 0x9995311BF7Bf8675eeA58258bcf3f99bcFC18478;

    function run() external {
        owner = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        /*//////////////////////////////////////////////////////////////
                          DEPLOY NEST CCTP RELAYER
        //////////////////////////////////////////////////////////////*/

        // Deploy NestCCTPRelayer implementation
        NestCCTPRelayer cctpImplementation = new NestCCTPRelayer(messageTransmitter, tokenMessenger, endpoint, usdc);
        console.log("NestCCTPRelayer Implementation:", address(cctpImplementation));

        // Encode initialization data
        bytes memory cctpInitData = abi.encodeWithSelector(NestCCTPRelayer.initialize.selector, owner);

        // Deploy TransparentUpgradeableProxy for NestCCTPRelayer
        TransparentUpgradeableProxy cctpProxy =
            new TransparentUpgradeableProxy(address(cctpImplementation), owner, cctpInitData);
        console.log("NestCCTPRelayer Proxy deployed at:", address(cctpProxy));

        /*//////////////////////////////////////////////////////////////
                        DEPLOY NEST VAULT COMPOSER
        //////////////////////////////////////////////////////////////*/

        // Deploy NestVaultComposer implementation with immutable predicateProxy
        NestVaultComposer composerImplementation = new NestVaultComposer(predicateProxy);
        console.log("NestVaultComposer Implementation:", address(composerImplementation));

        // Encode initialization data (assetOFT is the NestCCTPRelayer proxy)
        bytes memory composerInitData = abi.encodeWithSelector(
            NestVaultComposer.initialize.selector, owner, vault, address(cctpProxy), shareOFT, 0
        );

        // Deploy TransparentUpgradeableProxy for NestVaultComposer
        TransparentUpgradeableProxy composerProxy =
            new TransparentUpgradeableProxy(address(composerImplementation), owner, composerInitData);
        console.log("NestVaultComposer Proxy deployed at:", address(composerProxy));

        RolesAuthority rolesAuthority = RolesAuthority(authority);

        NestCCTPRelayer nestCCTPRelayer = NestCCTPRelayer(address(cctpProxy));
        NestVaultComposer nestVaultComposer = NestVaultComposer(payable(address(composerProxy)));

        // Configure NestCCTPRelayer
        nestCCTPRelayer.setEidToDomain(30168, 5); // Map LayerZero EID to CCTP domain
        nestCCTPRelayer.setComposer(address(composerProxy), true); // Whitelist composer
        nestCCTPRelayer.setAuthority(rolesAuthority); // Set authority

        // Configure NestVaultComposer
        nestVaultComposer.setAuthority(rolesAuthority); // Set authority

        // Set roles on authority
        rolesAuthority.setUserRole(address(composerProxy), COMPOSER_ROLE, true);
        rolesAuthority.setUserRole(address(cctpProxy), RELAYER_ROLE, true);
        rolesAuthority.setUserRole(owner, OWNER_ROLE, true);

        // Authorize NestCCTPRelayer.send to be callable by composerProxy (COMPOSER_ROLE)
        rolesAuthority.setRoleCapability(COMPOSER_ROLE, address(cctpProxy), NestCCTPRelayer.send.selector, true);

        // Authorize NestVaultOFT (vault) functions to be callable by composerProxy (COMPOSER_ROLE)
        // NestVaultOFT.send
        rolesAuthority.setRoleCapability(
            COMPOSER_ROLE,
            vault,
            bytes4(keccak256("send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)")),
            true
        );
        // NestVaultCore.requestRedeem
        rolesAuthority.setRoleCapability(
            COMPOSER_ROLE, vault, bytes4(keccak256("requestRedeem(uint256,address,address)")), true
        );
        // NestVaultCore.instantRedeem
        rolesAuthority.setRoleCapability(
            COMPOSER_ROLE, vault, bytes4(keccak256("instantRedeem(uint256,address,address)")), true
        );
        // NestVaultCore.updateRedeem
        rolesAuthority.setRoleCapability(
            COMPOSER_ROLE, vault, bytes4(keccak256("updateRedeem(uint256,address,address)")), true
        );
        // NestVaultCore.redeem
        rolesAuthority.setRoleCapability(
            COMPOSER_ROLE, vault, bytes4(keccak256("redeem(uint256,address,address)")), true
        );
        // NestVaultCore.fulfillRedeem
        rolesAuthority.setRoleCapability(
            COMPOSER_ROLE, vault, bytes4(keccak256("fulfillRedeem(address,uint256)")), true
        );
        // NestVaultComposer.fulfillRedeem
        rolesAuthority.setRoleCapability(
            OWNER_ROLE, address(composerProxy), NestVaultComposer.fulfillRedeem.selector, true
        );

        vm.stopBroadcast();
    }
}
