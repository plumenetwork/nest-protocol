// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {SerializedTx} from "script/lib/SafeBatchSerialize.sol";

import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";

import {AuthUpgradeable} from "contracts/auth/AuthUpgradeable.sol";
import {ComplianceProxy} from "contracts/compliance/ComplianceProxy.sol";
import {NestCCTPRelayer} from "contracts/integrations/cctp/NestCCTPRelayer.sol";
import {NestVaultComposer} from "contracts/integrations/ovault/NestVaultComposer.sol";

/// @title DeployPredicateV2Composer
/// @notice Deploys a second nTEST Composer for Predicate V2 without touching the live V1 Composer proxy.
/// @dev The CCTP hook payload selects a Composer address, and NestCCTPRelayer supports multiple enabled
///      Composers. The new proxy uses a distinct CREATE3 salt and is wired alongside, never over, V1.
///
///      Usage:
///        CHAIN_ID=98866 forge script script/deploy/DeployPredicateV2Composer.s.sol \
///          --sig "run(string)" "nTEST" --rpc-url $PLUME_RPC_URL --broadcast --verify --ffi
contract DeployPredicateV2Composer is BaseConfigScript {
    using stdJson for string;

    uint8 internal constant TEMPORARY_MIGRATION_ROLE = 17;
    address internal constant EXPECTED_DEPLOYER = 0xc28e1cDfB582953fEf53f76C64426c2aC79C716e;

    string internal complianceConfigPath;
    address internal complianceProxy;
    address internal composerV1;
    address internal composerV2;
    address internal baseVault;
    address internal vaultAuthority;
    address internal governanceOwner;

    function run(string memory vaultSymbol) external {
        loadConfigs(vaultSymbol);
        _loadComplianceConfig(vaultSymbol);
        _resolveTopology();

        hybridMode = true;
        vm.startBroadcast(deployerPrivateKey);

        _deployComposerV2();
        _setComposerAuthority();
        _configureCapabilities();
        _queueRelayerEnablement();
        _handoffOwnership();

        vm.stopBroadcast();

        _persistAddress();
        _printSummary();
        _writeGovernanceBatches();
    }

    function _loadComplianceConfig(string memory vaultSymbol) internal {
        complianceConfigPath = string.concat(
            vm.projectRoot(),
            "/script/deployment-config/compliance/",
            vm.toString(vaultConfig.deployChainId),
            "-",
            vaultSymbol,
            ".json"
        );

        string memory json = vm.readFile(complianceConfigPath);
        require(json.readUint(".chainId") == vaultConfig.deployChainId, "DeployPredicateV2Composer: chain mismatch");
        require(
            keccak256(bytes(json.readString(".symbol"))) == keccak256(bytes(vaultConfig.symbol)),
            "DeployPredicateV2Composer: symbol mismatch"
        );

        complianceProxy = json.readAddress(".complianceProxy");
        try vm.parseJsonAddress(json, ".composerV2") returns (address configuredComposerV2) {
            composerV2 = configuredComposerV2;
        } catch {}
    }

    function _resolveTopology() internal {
        require(vaultConfig.deployChainId == 98866, "DeployPredicateV2Composer: nTEST Plume only");
        require(
            keccak256(bytes(vaultConfig.symbol)) == keccak256(bytes("nTEST")), "DeployPredicateV2Composer: nTEST only"
        );
        require(
            deployer() == EXPECTED_DEPLOYER,
            "DeployPredicateV2Composer: PRIVATE_KEY does not match the pinned CREATE3 deployer"
        );
        require(complianceProxy.code.length > 0, "DeployPredicateV2Composer: ComplianceProxy not deployed");
        require(
            isActive(vaultConfig.common.cctpRelayer) && vaultConfig.common.cctpRelayer.code.length > 0,
            "DeployPredicateV2Composer: CCTP relayer not deployed"
        );

        for (uint256 i; i < vaultConfig.vaults.length; ++i) {
            if (keccak256(bytes(vaultConfig.vaults[i].assetSymbol)) != keccak256(bytes(vaultConfig.baseAssetSymbol))) {
                continue;
            }
            baseVault = vaultConfig.vaults[i].addr;
            composerV1 = vaultConfig.vaults[i].composer;
            break;
        }

        require(baseVault.code.length > 0, "DeployPredicateV2Composer: base vault not deployed");
        require(composerV1.code.length > 0, "DeployPredicateV2Composer: V1 Composer not deployed");
        require(composerV2 != composerV1, "DeployPredicateV2Composer: V2 must differ from V1");
        require(
            NestCCTPRelayer(payable(vaultConfig.common.cctpRelayer)).isComposer(composerV1),
            "DeployPredicateV2Composer: V1 Composer is not enabled"
        );

        vaultAuthority = address(Auth(vaultConfig.contracts.share).authority());
        require(vaultAuthority != address(0), "DeployPredicateV2Composer: vault authority not set");
        require(
            vaultConfig.contracts.rolesAuthority == address(0)
                || vaultConfig.contracts.rolesAuthority == vaultAuthority,
            "DeployPredicateV2Composer: configured authority differs from share"
        );
        governanceOwner = RolesAuthority(vaultAuthority).owner();
        require(governanceOwner != address(0), "DeployPredicateV2Composer: authority owner not set");
    }

    function _deployComposerV2() internal {
        if (composerV2 != address(0) && composerV2.code.length > 0) {
            _assertComposerV2();
            _logExists("NestVaultComposerV2", composerV2);
            return;
        }

        bytes32 salt = generateCreate3SaltForAsset("NestVaultComposerV2", vaultConfig.baseAssetSymbol);
        address expected = computeCreate3AddressForAsset("NestVaultComposerV2", vaultConfig.baseAssetSymbol);
        require(
            composerV2 == address(0) || composerV2 == expected,
            "DeployPredicateV2Composer: configured V2 address does not match CREATE3 address"
        );
        composerV2 = expected;

        NestVaultComposer implementation = new NestVaultComposer(complianceProxy);
        bytes memory initData = abi.encodeCall(
            NestVaultComposer.initialize,
            (
                deployer(),
                baseVault,
                vaultConfig.common.cctpRelayer,
                isOFT() ? baseVault : vaultConfig.contracts.share,
                vaultConfig.maxRetryableValue
            )
        );
        address deployed = CREATEX.deployCreate3(
            salt,
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(address(implementation), governanceOwner, initData)
            )
        );
        require(deployed == composerV2, "DeployPredicateV2Composer: unexpected Composer V2 address");
        _assertComposerV2();
        _logDeploy("NestVaultComposerV2", composerV2);
    }

    function _assertComposerV2() internal view {
        NestVaultComposer composer = NestVaultComposer(payable(composerV2));
        require(address(composer.COMPLIANCE_PROXY()) == complianceProxy, "DeployPredicateV2Composer: proxy mismatch");
        require(address(composer.VAULT()) == baseVault, "DeployPredicateV2Composer: vault mismatch");
        require(composer.ASSET_OFT() == vaultConfig.common.cctpRelayer, "DeployPredicateV2Composer: asset OFT mismatch");
        require(
            composer.SHARE_OFT() == (isOFT() ? baseVault : vaultConfig.contracts.share),
            "DeployPredicateV2Composer: share OFT mismatch"
        );
    }

    function _setComposerAuthority() internal {
        NestVaultComposer composer = NestVaultComposer(payable(composerV2));
        if (address(composer.authority()) == vaultAuthority) return;
        execute(
            composerV2,
            abi.encodeCall(AuthUpgradeable.setAuthority, (Authority(vaultAuthority))),
            "NestVaultComposerV2.setAuthority"
        );
    }

    function _configureCapabilities() internal {
        RolesAuthority authority = RolesAuthority(vaultAuthority);

        _setRoleCapability(authority, COMPOSER_ROLE, complianceProxy, ComplianceProxy.mintOnBehalf.selector, true);
        _setUserRole(authority, composerV2, COMPOSER_ROLE, true);

        _setRoleCapability(
            authority,
            CAN_SOLVE_ROLE,
            composerV2,
            bytes4(keccak256("fulfillRedeem(uint32,bytes32,bytes32,uint256)")),
            true
        );
        _setRoleCapability(
            authority,
            KEEPER_ROLE,
            composerV2,
            bytes4(
                keccak256(
                    "updateRequestRedeemAndSend(uint32,bytes32,(uint32,bytes32,uint256,uint256,bytes,bytes,bytes),address)"
                )
            ),
            true
        );
        _setRoleCapability(
            authority,
            KEEPER_ROLE,
            composerV2,
            bytes4(
                keccak256(
                    "finishRedeemAndSend(uint32,bytes32,(uint32,bytes32,uint256,uint256,bytes,bytes,bytes),address)"
                )
            ),
            true
        );
        _setRoleCapability(authority, OWNER_ROLE, composerV2, NestVaultComposer.blockCompose.selector, true);
        _setRoleCapability(authority, OWNER_ROLE, composerV2, NestVaultComposer.unblockCompose.selector, true);
        _setRoleCapability(authority, OWNER_ROLE, composerV2, NestVaultComposer.setMaxRetryableValue.selector, true);
        _setRoleCapability(authority, OWNER_ROLE, composerV2, bytes4(keccak256("recover(address,uint256,bytes)")), true);
        _setRoleCapability(
            authority,
            RELAYER_ROLE,
            composerV2,
            bytes4(
                keccak256("depositAndSend(bytes32,uint256,(uint32,bytes32,uint256,uint256,bytes,bytes,bytes),address)")
            ),
            true
        );
        _setRoleCapability(
            authority,
            RELAYER_ROLE,
            composerV2,
            bytes4(
                keccak256("redeemAndSend(bytes32,uint256,(uint32,bytes32,uint256,uint256,bytes,bytes,bytes),address)")
            ),
            true
        );

        _setPublicCapability(
            authority,
            composerV2,
            bytes4(keccak256("depositAndSend(uint256,(uint32,bytes32,uint256,uint256,bytes,bytes,bytes),address)")),
            true
        );
        _setPublicCapability(
            authority,
            composerV2,
            bytes4(keccak256("redeemAndSend(uint256,(uint32,bytes32,uint256,uint256,bytes,bytes,bytes),address)")),
            true
        );
    }

    /// @dev The legacy relayer is still EOA-owned, while its RolesAuthority is timelock-owned. Give the
    ///      timelock one narrowly scoped role only for the duration of executeBatch, then revoke both
    ///      the role and capability in the same atomic operation.
    function _queueRelayerEnablement() internal {
        NestCCTPRelayer relayer = NestCCTPRelayer(payable(vaultConfig.common.cctpRelayer));
        if (relayer.isComposer(composerV2)) return;

        RolesAuthority authority = RolesAuthority(vaultAuthority);
        bytes4 selector = NestCCTPRelayer.setComposer.selector;
        require(
            !authority.doesUserHaveRole(governanceOwner, TEMPORARY_MIGRATION_ROLE),
            "DeployPredicateV2Composer: temporary role already assigned"
        );
        require(
            !authority.doesRoleHaveCapability(TEMPORARY_MIGRATION_ROLE, vaultConfig.common.cctpRelayer, selector),
            "DeployPredicateV2Composer: temporary capability already assigned"
        );

        _setRoleCapability(authority, TEMPORARY_MIGRATION_ROLE, vaultConfig.common.cctpRelayer, selector, true);
        _setUserRole(authority, governanceOwner, TEMPORARY_MIGRATION_ROLE, true);
        execute(
            vaultConfig.common.cctpRelayer,
            abi.encodeCall(NestCCTPRelayer.setComposer, (composerV2, true)),
            "NestCCTPRelayer.setComposer(V2,true)"
        );
        // Queue these unconditionally. The enabling calls above are only serialized at generation
        // time, so on-chain idempotency reads still report `false` until executeBatch runs.
        execute(
            address(authority),
            abi.encodeCall(RolesAuthority.setUserRole, (governanceOwner, TEMPORARY_MIGRATION_ROLE, false)),
            "RolesAuthority.revokeTemporaryComposerMigrationRole"
        );
        execute(
            address(authority),
            abi.encodeCall(
                RolesAuthority.setRoleCapability,
                (TEMPORARY_MIGRATION_ROLE, vaultConfig.common.cctpRelayer, selector, false)
            ),
            "RolesAuthority.revokeTemporaryComposerMigrationCapability"
        );
    }

    function _handoffOwnership() internal {
        NestVaultComposer composer = NestVaultComposer(payable(composerV2));
        address owner = composer.owner();
        if (owner == deployer() && governanceOwner != deployer()) {
            composer.transferOwnership(governanceOwner);
            serializedTxs.push(
                SerializedTx({
                    name: "NestVaultComposerV2.acceptOwnership",
                    to: composerV2,
                    value: 0,
                    data: abi.encodeCall(AuthUpgradeable.acceptOwnership, ())
                })
            );
            return;
        }
        require(
            owner == governanceOwner || composer.pendingOwner() == governanceOwner || governanceOwner == deployer(),
            "DeployPredicateV2Composer: unexpected Composer V2 owner"
        );
    }

    function _writeGovernanceBatches() internal {
        uint256 delay = TimelockController(payable(governanceOwner)).getMinDelay();
        uint256 length = serializedTxs.length;
        address[] memory targets = new address[](length);
        bytes[] memory payloads = new bytes[](length);
        for (uint256 i; i < length; ++i) {
            require(serializedTxs[i].value == 0, "DeployPredicateV2Composer: timelock value unsupported");
            targets[i] = serializedTxs[i].to;
            payloads[i] = serializedTxs[i].data;
        }

        delete serializedTxs;
        bytes32 salt = keccak256(bytes(string.concat(vaultConfig.symbol, ":DeployPredicateV2Composer:v1")));
        _buildTimelockBatches(
            governanceOwner,
            targets,
            payloads,
            salt,
            delay,
            "DeployPredicateV2Composer-Schedule",
            "DeployPredicateV2Composer-Execute"
        );
    }

    function _setRoleCapability(RolesAuthority authority, uint8 role, address target, bytes4 selector, bool enabled)
        internal
    {
        if (authority.doesRoleHaveCapability(role, target, selector) == enabled) return;
        execute(
            address(authority),
            abi.encodeCall(RolesAuthority.setRoleCapability, (role, target, selector, enabled)),
            "RolesAuthority.setRoleCapability(ComposerV2)"
        );
    }

    function _setPublicCapability(RolesAuthority authority, address target, bytes4 selector, bool enabled) internal {
        if (authority.isCapabilityPublic(target, selector) == enabled) return;
        execute(
            address(authority),
            abi.encodeCall(RolesAuthority.setPublicCapability, (target, selector, enabled)),
            "RolesAuthority.setPublicCapability(ComposerV2)"
        );
    }

    function _setUserRole(RolesAuthority authority, address user, uint8 role, bool enabled) internal {
        if (authority.doesUserHaveRole(user, role) == enabled) return;
        execute(
            address(authority),
            abi.encodeCall(RolesAuthority.setUserRole, (user, role, enabled)),
            "RolesAuthority.setUserRole(ComposerV2)"
        );
    }

    function _persistAddress() internal {
        vm.writeJson(vm.toString(composerV2), complianceConfigPath, ".composerV2");
        console.log("Compliance config Composer V2 updated:", complianceConfigPath);
    }

    function _printSummary() internal view {
        console.log("=== Predicate V2 Composer (parallel deployment) ===");
        console.log("Composer V1 (unchanged):", composerV1);
        console.log(
            "Composer V1 still enabled:",
            NestCCTPRelayer(payable(vaultConfig.common.cctpRelayer)).isComposer(composerV1)
        );
        console.log("Composer V2:", composerV2);
        console.log("ComplianceProxy V2:", complianceProxy);
        console.log("CCTP relayer:", vaultConfig.common.cctpRelayer);
        console.log("Vault authority:", vaultAuthority);
        console.log("Governance owner:", governanceOwner);
        console.log("===================================================");
    }
}
