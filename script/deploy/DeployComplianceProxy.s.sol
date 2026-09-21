// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {ConfigReader} from "script/lib/ConfigReader.sol";
import {DeployMorpho} from "script/deploy/DeployMorpho.s.sol";
import {Upgrade} from "script/deploy/Upgrade.s.sol";
import {NestUnlooper} from "contracts/integrations/morpho/NestUnlooper.sol";
import {ICreateX} from "createx/ICreateX.sol";
import {SerializedTx} from "script/lib/SafeBatchSerialize.sol";

import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";

import {AuthUpgradeable} from "contracts/auth/AuthUpgradeable.sol";
import {ComplianceProxy} from "contracts/compliance/ComplianceProxy.sol";
import {IComplianceHook} from "contracts/compliance/interfaces/IComplianceHook.sol";
import {PredicateV2Hook} from "contracts/compliance/hooks/PredicateV2Hook.sol";

/// @title  DeployComplianceProxy
/// @notice Deploys and wires the Predicate V2 compliance stack alongside the live V1 proxy.
/// @dev    The script intentionally does not revoke V1 permissions or close direct vault routes.
///         Safe-owned authority changes are written to a Transaction Builder batch.
///
///         The vault's `compliance.v2.verificationHash` may be left empty initially and set on a rerun
///         after the Predicate dashboard project has been created.
///
///         Usage:
///           CHAIN_ID=98866 forge script script/deploy/DeployComplianceProxy.s.sol \
///             --sig "runMigration()" --rpc-url $PLUME_RPC_URL --broadcast --verify
contract DeployComplianceProxy is BaseConfigScript {
    using stdJson for string;

    // Keep the previously prepared shared CREATE3 addresses stable.
    string internal constant COMMON_HOOK_SALT = "NestPredicateV2Hook-stage-v1";
    string internal constant COMMON_PROXY_SALT = "NestComplianceProxy-stage-v1";
    bool internal deployOnlyMode;
    bool internal migrationMode;
    bool internal leverageDeployed;
    address internal cctpImplementation;
    address internal previousCctpImplementation;

    string internal constant VERIFICATION_HASH_PLACEHOLDER = "REPLACE_WITH_DASHBOARD_VERIFICATION_HASH";
    bytes32 internal constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    string internal complianceConfigPath;
    string internal apiChain;
    string internal verificationHash;
    address internal predicateRegistry;
    address internal predicateV2Hook;
    address internal legacyPredicateV2Hook;
    address internal complianceProxy;
    address internal vaultAuthority;
    address internal governanceOwner;
    bool internal activateHook;

    function run(string memory vaultSymbol) external {
        deployOnlyMode = false;
        loadConfigs(vaultSymbol);
        _loadComplianceConfig(vaultSymbol);
        _resolveGovernance();

        hybridMode = true;
        vm.startBroadcast(deployerPrivateKey);

        _deployHook();
        _deployProxy();
        _upgradeImplementations();
        _configureCapabilities();
        _wireContracts();
        _handoffOwnership();

        vm.stopBroadcast();

        _persistAddresses();
        _printSummary();
        _writeGovernanceBatches();
    }

    /// @notice Deploy the shared stack with common authority attached; apply or queue its permission config.
    /// @dev Reads nCOMMON's configured policy. Does not grant vault access, upgrade existing
    ///      contracts, or write active deployment addresses. The existing run(string) retains
    ///      its separate vault-specific deployment and wiring flow.
    function runDeployOnly() external {
        _runCommon(false);
    }

    /// @notice Record the shared stack in the chain's common config after all configuration is applied.
    /// @dev No transactions: re-reads code, ownership, policy and every common permission before publishing config.
    ///      On a chain that still runs V1, vaults opt into the recorded stack with compliance.v2Only.
    function activateCommon() external {
        _loadDeployOnlyConfig();
        if (chainComplianceConfig.v2Only) {
            require(!isActive(vaultConfig.common.predicateProxy), "DeployComplianceProxy: V1 proxy configured");
        }
        require(bytes(verificationHash).length > 0, "DeployComplianceProxy: policy missing");
        _assertDeployOnlyHook();
        _assertDeployOnlyComplianceProxy();
        _queueCommonConfiguration();
        require(serializedTxs.length == 0, "DeployComplianceProxy: execute common governance batch first");
        snapshotCommon();
        vaultConfig.common.complianceProxy = complianceProxy;
        writeCommonConfigIfChanged();
        _printSummary();
    }

    /// @notice Prepare the shared V2 stack, canonical CCTP relayer upgrade and parallel leverage stack.
    /// @dev Deployments broadcast directly; all governance changes share one batch. Existing vault
    ///      permissions, composers, active address config and old periphery remain unchanged.
    function runMigration() external {
        _runCommon(true);
    }

    function _runCommon(bool includeDependencies) internal {
        _prepareCommon(includeDependencies);
        _printSummary();
        console.log("Common authority attached; configuration applied or queued; no vault grants or routing changes.");
        _writeDeployOnlyCandidate();
        _writeGovernanceBatches();
    }

    function _prepareCommon(bool includeDependencies) internal {
        migrationMode = includeDependencies;
        leverageDeployed = false;
        cctpImplementation = address(0);
        previousCctpImplementation = address(0);
        _loadDeployOnlyConfig();
        snapshotCommon();
        vm.startBroadcast(deployerPrivateKey);
        _deployHook();
        _deployProxy();
        vm.stopBroadcast();
        _assertDeployOnlyHook();
        _assertDeployOnlyComplianceProxy();

        SerializedTx[] memory relayerCalls;
        if (includeDependencies) {
            if (isActive(vaultConfig.common.cctpRelayer)) {
                previousCctpImplementation = _implementation(vaultConfig.common.cctpRelayer);
                (cctpImplementation, relayerCalls) = new Upgrade().prepareCommonRelayerUpgrade(governanceOwner);
            } else {
                console.log("CCTP: no active canonical relayer configured on this chain; skipped.");
            }
            (bool hasMorpho,) = ConfigReader.tryReadMorphoConfig(vaultConfig.deployChainId);
            if (hasMorpho) {
                (vaultConfig.common.nestAdapter, vaultConfig.common.nestBundler, vaultConfig.common.nestUnlooper) =
                    new DeployMorpho().deployParallel(complianceProxy, governanceOwner);
                leverageDeployed = true;
            } else {
                require(
                    !isActive(vaultConfig.common.nestAdapter) && !isActive(vaultConfig.common.nestBundler)
                        && !isActive(vaultConfig.common.nestUnlooper),
                    "DeployComplianceProxy: active leverage stack has no Morpho config"
                );
                console.log("Leverage: no Morpho config on this chain; skipped.");
            }
        }
        _applyCommonConfiguration();
        if (leverageDeployed) {
            bool previousMsigMode = msigMode;
            msigMode = true;
            RolesAuthority authority = RolesAuthority(vaultConfig.common.commonRolesAuthority);
            _setRoleCapability(authority, KEEPER_ROLE, vaultConfig.common.nestUnlooper, NestUnlooper.execute.selector);
            _setRoleCapability(
                authority, OWNER_ROLE, vaultConfig.common.nestUnlooper, NestUnlooper.setVaultApproval.selector
            );
            msigMode = previousMsigMode;
        }
        // The relayer upgrade and storage remap must execute atomically in this order.
        for (uint256 i; i < relayerCalls.length; ++i) {
            serializedTxs.push(relayerCalls[i]);
        }
    }

    function _loadDeployOnlyConfig() internal {
        deployOnlyMode = true;
        uint256 chainId = vm.envUint("CHAIN_ID");
        require(block.chainid == chainId, "DeployComplianceProxy: RPC chain mismatch");
        commonConfig = ConfigReader.readCommonConfig(chainId);
        chainComplianceConfig = ConfigReader.readComplianceConfig(chainId);
        predicateRegistry = chainComplianceConfig.v2.predicateRegistry;
        apiChain = chainComplianceConfig.v2.apiChain;
        vaultConfig.symbol = "nCOMMON";
        vaultConfig.deployChainId = chainId;
        vaultConfig.common = ConfigReader.readCommonProxyConfig(chainId);
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        verificationHash = ConfigReader.readVaultConfig("nCOMMON").compliance.v2.verificationHash;
        CREATEX = ICreateX(commonConfig.createx);
        require(commonConfig.createx.code.length > 0, "DeployComplianceProxy: CreateX missing");
        require(predicateRegistry.code.length > 0, "DeployComplianceProxy: registry missing");
        require(bytes(apiChain).length > 0, "DeployComplianceProxy: Predicate chain missing");
        address commonAuthority = vaultConfig.common.commonRolesAuthority;
        require(commonAuthority.code.length > 0, "DeployComplianceProxy: common authority missing");
        governanceOwner = Auth(commonAuthority).owner();
        require(
            governanceOwner.code.length > 0
                || (chainComplianceConfig.v2Only && !migrationMode && governanceOwner == deployer()),
            "DeployComplianceProxy: governance must be a contract or V2 bootstrap deployer"
        );
        _prepareDeployOnly();
    }

    function _prepareDeployOnly() internal {
        predicateV2Hook = computeCreate3AddressCommon(COMMON_HOOK_SALT);
        complianceProxy = computeCreate3AddressCommon(COMMON_PROXY_SALT);
        address configured = vaultConfig.common.complianceProxy;
        require(
            configured == address(0) || configured == complianceProxy,
            "DeployComplianceProxy: common compliance proxy already configured"
        );
        // Validate both occupied slots before deploying either missing component.
        if (predicateV2Hook.code.length > 0) _assertDeployOnlyHook();
        if (complianceProxy.code.length > 0) _assertDeployOnlyComplianceProxy();
    }

    function _assertDeployOnlyHook() internal view {
        _assertDeployOnlyProxy(predicateV2Hook, type(PredicateV2Hook).runtimeCode);
        PredicateV2Hook hook = PredicateV2Hook(predicateV2Hook);
        require(hook.owner() == governanceOwner, "DeployComplianceProxy: hook owner mismatch");
        require(hook.pendingOwner() == address(0), "DeployComplianceProxy: hook ownership transfer pending");
        require(
            address(hook.authority()) == vaultConfig.common.commonRolesAuthority,
            "DeployComplianceProxy: hook authority mismatch"
        );
        require(hook.getRegistry() == predicateRegistry, "DeployComplianceProxy: hook registry mismatch");
    }

    function _assertDeployOnlyComplianceProxy() internal view {
        _assertDeployOnlyProxy(complianceProxy, type(ComplianceProxy).runtimeCode);
        ComplianceProxy proxy = ComplianceProxy(complianceProxy);
        bool bootstrapping = proxy.owner() == deployer();
        require(proxy.owner() == governanceOwner || bootstrapping, "DeployComplianceProxy: proxy owner mismatch");
        require(
            proxy.pendingOwner() == address(0)
                || (bootstrapping && governanceOwner != deployer() && proxy.pendingOwner() == governanceOwner),
            "DeployComplianceProxy: unexpected pending proxy owner"
        );
        require(
            address(proxy.authority()) == vaultConfig.common.commonRolesAuthority
                || (bootstrapping && address(proxy.authority()) == address(0)),
            "DeployComplianceProxy: proxy authority mismatch"
        );
        require(address(proxy.complianceHook()) == predicateV2Hook, "DeployComplianceProxy: hook binding mismatch");
    }

    /// @dev Fresh V2-only chains stay deployer-owned through configuration. Existing contract-owned
    ///      governance retains the staged Safe/timelock flow. Activation calls the queue-only check.
    function _applyCommonConfiguration() internal {
        _queueCommonConfiguration();
        if (governanceOwner != deployer()) return;
        require(
            chainComplianceConfig.v2Only && !migrationMode, "DeployComplianceProxy: direct config requires fresh V2"
        );
        vm.startBroadcast(deployerPrivateKey);
        for (uint256 i; i < serializedTxs.length; ++i) {
            SerializedTx memory tx_ = serializedTxs[i];
            execute(tx_.to, tx_.data, tx_.value, tx_.name);
        }
        vm.stopBroadcast();
        delete serializedTxs;
    }

    function _queueCommonConfiguration() internal {
        delete serializedTxs;
        PredicateV2Hook hook = PredicateV2Hook(predicateV2Hook);
        // Existing deployments may have an earlier policy. Only governance applies this change.
        if (keccak256(bytes(hook.getPolicyID())) != keccak256(bytes(verificationHash))) {
            serializedTxs.push(
                SerializedTx({
                    name: "PredicateV2Hook.setPolicyID",
                    to: predicateV2Hook,
                    value: 0,
                    data: abi.encodeCall(PredicateV2Hook.setPolicyID, (verificationHash))
                })
            );
        }
        ComplianceProxy proxy = ComplianceProxy(complianceProxy);
        if (proxy.owner() != governanceOwner) {
            require(proxy.pendingOwner() == governanceOwner, "DeployComplianceProxy: ownership handoff not started");
            serializedTxs.push(
                SerializedTx({
                    name: "ComplianceProxy.acceptOwnership",
                    to: complianceProxy,
                    value: 0,
                    data: abi.encodeCall(AuthUpgradeable.acceptOwnership, ())
                })
            );
        }
        bool previousMsigMode = msigMode;
        msigMode = true;
        _configureComplianceCapabilities(RolesAuthority(vaultConfig.common.commonRolesAuthority));
        msigMode = previousMsigMode;
    }

    function _assertDeployOnlyProxy(address target, bytes memory expectedRuntime) internal view {
        address implementation = _implementation(target);
        address admin = _proxyAdmin(target);
        require(
            implementation.code.length > 0 && keccak256(implementation.code) == keccak256(expectedRuntime),
            "DeployComplianceProxy: implementation mismatch"
        );
        require(admin.code.length > 0, "DeployComplianceProxy: ProxyAdmin missing");
        require(ProxyAdmin(admin).owner() == governanceOwner, "DeployComplianceProxy: ProxyAdmin owner mismatch");
    }

    function _writeDeployOnlyCandidate() internal {
        string memory object = "predicate-v2-stage";
        vm.serializeString(object, "status", "candidate-verify-broadcast-receipts");
        vm.serializeUint(object, "chainId", vaultConfig.deployChainId);
        vm.serializeAddress(object, "deployer", deployer());
        vm.serializeAddress(object, "governance", governanceOwner);
        vm.serializeAddress(object, "commonRolesAuthority", vaultConfig.common.commonRolesAuthority);
        vm.serializeAddress(object, "predicateRegistry", predicateRegistry);
        vm.serializeString(object, "apiChain", apiChain);
        vm.serializeString(object, "policyId", verificationHash);
        vm.serializeAddress(object, "predicateV2Hook", predicateV2Hook);
        vm.serializeAddress(object, "complianceProxy", complianceProxy);
        vm.serializeAddress(object, "complianceProxyOwner", ComplianceProxy(complianceProxy).owner());
        vm.serializeAddress(object, "complianceProxyPendingOwner", ComplianceProxy(complianceProxy).pendingOwner());
        vm.serializeAddress(object, "hookImplementation", _implementation(predicateV2Hook));
        vm.serializeAddress(object, "proxyImplementation", _implementation(complianceProxy));
        vm.serializeAddress(object, "hookProxyAdmin", _proxyAdmin(predicateV2Hook));
        vm.serializeBool(object, "includesMigrationDependencies", migrationMode);
        vm.serializeAddress(object, "cctpRelayer", vaultConfig.common.cctpRelayer);
        vm.serializeAddress(object, "previousCctpImplementation", previousCctpImplementation);
        vm.serializeAddress(object, "cctpImplementation", cctpImplementation);
        vm.serializeBool(object, "includesLeverage", leverageDeployed);
        vm.serializeAddress(object, "previousNestAdapter", commonSnapshot.nestAdapter);
        vm.serializeAddress(object, "previousNestBundler", commonSnapshot.nestBundler);
        vm.serializeAddress(object, "previousNestUnlooper", commonSnapshot.nestUnlooper);
        vm.serializeAddress(object, "nestAdapter", leverageDeployed ? vaultConfig.common.nestAdapter : address(0));
        vm.serializeAddress(object, "nestBundler", leverageDeployed ? vaultConfig.common.nestBundler : address(0));
        vm.serializeAddress(object, "nestUnlooper", leverageDeployed ? vaultConfig.common.nestUnlooper : address(0));
        string memory json = vm.serializeAddress(object, "complianceProxyAdmin", _proxyAdmin(complianceProxy));
        string memory dir = string.concat(vm.projectRoot(), "/script/output/predicate-v2");
        vm.createDir(dir, true);
        string memory path = string.concat(dir, "/", vm.toString(vaultConfig.deployChainId), "-stage.json");
        vm.writeJson(json, path);
        console.log("Candidate manifest (also written by simulation):", path);
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
        require(json.readUint(".chainId") == vaultConfig.deployChainId, "DeployComplianceProxy: chain mismatch");
        require(
            keccak256(bytes(json.readString(".symbol"))) == keccak256(bytes(vaultConfig.symbol)),
            "DeployComplianceProxy: symbol mismatch"
        );

        apiChain = chainComplianceConfig.v2.apiChain;
        predicateRegistry = chainComplianceConfig.v2.predicateRegistry;
        verificationHash = vaultConfig.compliance.v2.verificationHash;
        if (
            keccak256(bytes(verificationHash)) == keccak256(bytes(VERIFICATION_HASH_PLACEHOLDER))
                || keccak256(bytes(verificationHash)) == keccak256(bytes("0x0000000000000000000000000000000000000000"))
        ) {
            verificationHash = "";
        }
        predicateV2Hook = json.readAddress(".predicateV2Hook");
        complianceProxy = json.readAddress(".complianceProxy");
        try vm.parseJsonAddress(json, ".legacyPredicateV2Hook") returns (address legacyHook) {
            legacyPredicateV2Hook = legacyHook;
        } catch {}
        try vm.parseJsonBool(json, ".activateHook") returns (bool shouldActivateHook) {
            activateHook = shouldActivateHook;
        } catch {}

        require(predicateRegistry.code.length > 0, "DeployComplianceProxy: registry has no code");
        require(bytes(apiChain).length > 0, "DeployComplianceProxy: apiChain required");
    }

    function _resolveGovernance() internal {
        require(vaultConfig.contracts.share.code.length > 0, "DeployComplianceProxy: share not deployed");

        address onchainAuthority = address(Auth(vaultConfig.contracts.share).authority());
        require(onchainAuthority != address(0), "DeployComplianceProxy: share authority not set");
        if (vaultConfig.contracts.rolesAuthority != address(0)) {
            require(
                vaultConfig.contracts.rolesAuthority == onchainAuthority,
                "DeployComplianceProxy: configured authority differs from share"
            );
        }

        vaultAuthority = onchainAuthority;
        governanceOwner = RolesAuthority(vaultAuthority).owner();
        require(governanceOwner != address(0), "DeployComplianceProxy: authority owner not set");
    }

    function _deployHook() internal {
        bytes32 salt =
            deployOnlyMode ? generateCreate3SaltCommon(COMMON_HOOK_SALT) : generateCreate3Salt("PredicateV2HookProxy");
        address expected = deployOnlyMode
            ? computeCreate3AddressCommon(COMMON_HOOK_SALT)
            : computeCreate3Address("PredicateV2HookProxy");
        address configuredHook = predicateV2Hook;

        if (configuredHook != address(0) && configuredHook != expected) {
            require(configuredHook.code.length > 0, "DeployComplianceProxy: configured PredicateV2Hook has no code");
            require(
                _proxyAdmin(configuredHook) == address(0),
                "DeployComplianceProxy: configured PredicateV2Hook is a different upgradeable proxy"
            );
            require(
                PredicateV2Hook(configuredHook).getRegistry() == predicateRegistry,
                "DeployComplianceProxy: legacy PredicateV2Hook registry mismatch"
            );
            legacyPredicateV2Hook = configuredHook;
            console.log("Legacy direct PredicateV2Hook retained for rollback:", legacyPredicateV2Hook);
        }
        predicateV2Hook = expected;

        if (predicateV2Hook.code.length > 0) {
            _assertHookProxy(predicateV2Hook);
            _logExists("PredicateV2Hook", predicateV2Hook);
            return;
        }

        PredicateV2Hook implementation = new PredicateV2Hook();
        bytes memory initData = abi.encodeCall(
            PredicateV2Hook.initialize,
            (
                deployOnlyMode ? governanceOwner : deployer(),
                Authority(deployOnlyMode ? vaultConfig.common.commonRolesAuthority : vaultAuthority),
                predicateRegistry,
                verificationHash
            )
        );
        address deployed = CREATEX.deployCreate3(
            salt,
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(address(implementation), governanceOwner, initData)
            )
        );
        require(deployed == predicateV2Hook, "DeployComplianceProxy: unexpected hook address");
        _assertHookProxy(predicateV2Hook);
        _logDeploy("PredicateV2Hook", predicateV2Hook);
    }

    /// @dev Re-runs converge existing proxies onto the current build: when a proxy's implementation
    ///      runtime code differs from this compilation, deploy a fresh implementation and queue
    ///      `ProxyAdmin.upgradeAndCall` for the governance owner (neither contract has a reinitializer).
    function _upgradeImplementations() internal {
        if (predicateV2Hook.code.length > 0 && _proxyAdmin(predicateV2Hook) != address(0)) {
            _upgradeIfStale(predicateV2Hook, type(PredicateV2Hook).runtimeCode, "PredicateV2Hook");
        }
        if (complianceProxy.code.length > 0 && _proxyAdmin(complianceProxy) != address(0)) {
            _upgradeIfStale(complianceProxy, type(ComplianceProxy).runtimeCode, "ComplianceProxy");
        }
    }

    function _upgradeIfStale(address proxy, bytes memory expectedRuntimeCode, string memory label) internal {
        address currentImpl = _implementation(proxy);
        if (keccak256(currentImpl.code) == keccak256(expectedRuntimeCode)) return;

        address newImpl;
        if (keccak256(bytes(label)) == keccak256(bytes("PredicateV2Hook"))) {
            newImpl = address(new PredicateV2Hook());
        } else {
            newImpl = address(new ComplianceProxy());
        }
        console.log(string.concat(label, " implementation is stale; new implementation deployed:"), newImpl);

        execute(
            _proxyAdmin(proxy),
            abi.encodeCall(ProxyAdmin.upgradeAndCall, (ITransparentUpgradeableProxy(proxy), newImpl, "")),
            string.concat("ProxyAdmin.upgradeAndCall(", label, ")")
        );
    }

    function _implementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT))));
    }

    function _assertHookProxy(address hook) internal view {
        require(
            _proxyAdmin(hook) != address(0),
            "DeployComplianceProxy: existing PredicateV2Hook is not upgradeable; deploy a new proxy hook"
        );
    }

    function _proxyAdmin(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_ADMIN_SLOT))));
    }

    function _deployProxy() internal {
        // v2 deliberately deploys alongside the original nTEST proxy. The original
        // `ComplianceProxy` CREATE3 slot is occupied and must never be treated as an
        // upgrade target for this migration.
        bytes32 salt =
            deployOnlyMode ? generateCreate3SaltCommon(COMMON_PROXY_SALT) : generateCreate3Salt("ComplianceProxy-v2");
        address expected = deployOnlyMode
            ? computeCreate3AddressCommon(COMMON_PROXY_SALT)
            : computeCreate3Address("ComplianceProxy-v2");
        _assertConfiguredAddress("ComplianceProxy", complianceProxy, expected);
        complianceProxy = expected;

        if (complianceProxy.code.length > 0) {
            if (deployOnlyMode) _configureDeployOnlyProxy();
            _logExists("ComplianceProxy", complianceProxy);
            return;
        }

        ComplianceProxy implementation = new ComplianceProxy();
        bytes memory initData =
            abi.encodeCall(ComplianceProxy.initialize, (deployer(), IComplianceHook(predicateV2Hook)));
        address deployed = CREATEX.deployCreate3(
            salt,
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(address(implementation), governanceOwner, initData)
            )
        );
        require(deployed == complianceProxy, "DeployComplianceProxy: unexpected proxy address");
        if (deployOnlyMode) _configureDeployOnlyProxy();
        _logDeploy("ComplianceProxy", complianceProxy);
    }

    /// @dev Use the existing initializer/setters. Governance completes the existing two-step handoff.
    function _configureDeployOnlyProxy() internal {
        _assertDeployOnlyComplianceProxy();
        ComplianceProxy proxy = ComplianceProxy(complianceProxy);
        if (proxy.owner() == deployer()) {
            if (address(proxy.authority()) != vaultConfig.common.commonRolesAuthority) {
                proxy.setAuthority(Authority(vaultConfig.common.commonRolesAuthority));
            }
            if (governanceOwner != deployer() && proxy.pendingOwner() != governanceOwner) {
                proxy.transferOwnership(governanceOwner);
            }
        }
        require(
            address(proxy.authority()) == vaultConfig.common.commonRolesAuthority,
            "DeployComplianceProxy: proxy authority not attached"
        );
    }

    function _configureCapabilities() internal {
        RolesAuthority authority = RolesAuthority(vaultAuthority);

        // Vault access. V1 keeps its existing role while V2 receives the same deposit/mint
        // permissions plus the standard compliance-gated redeem entrypoints. Permit2 shares are
        // pulled into ComplianceProxy before it calls these standard entrypoints as the owner.
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            address vault = vaultConfig.vaults[i].addr;
            if (!isActive(vault)) continue;

            _setRoleCapability(authority, PREDICATE_PROXY_ROLE, vault, bytes4(keccak256("deposit(uint256,address)")));
            _setRoleCapability(authority, PREDICATE_PROXY_ROLE, vault, bytes4(keccak256("mint(uint256,address)")));
            _setRoleCapability(
                authority, PREDICATE_PROXY_ROLE, vault, bytes4(keccak256("requestRedeem(uint256,address,address)"))
            );
            _setRoleCapability(
                authority, PREDICATE_PROXY_ROLE, vault, bytes4(keccak256("instantRedeem(uint256,address,address)"))
            );
        }
        _setUserRole(authority, complianceProxy, PREDICATE_PROXY_ROLE);

        _configureComplianceCapabilities(authority);
    }

    function _configureComplianceCapabilities(RolesAuthority authority) internal {
        // Keep attestation consumption limited to the V2 proxy. Reusing PREDICATE_PROXY_ROLE
        // would also authorize the live V1 proxy, which already holds that role.
        _setRoleCapability(authority, COMPLIANCE_HOOK_ROLE, predicateV2Hook, PredicateV2Hook.checkCompliance.selector);
        _setUserRole(authority, complianceProxy, COMPLIANCE_HOOK_ROLE);

        // User actions are public by default, but every entrypoint remains authority-gated so
        // governance can revoke individual selectors without another proxy upgrade.
        _setPublicCapability(authority, complianceProxy, ComplianceProxy.deposit.selector);
        _setPublicCapability(authority, complianceProxy, ComplianceProxy.depositWithPermit2.selector);
        _setPublicCapability(authority, complianceProxy, ComplianceProxy.depositOnBehalf.selector);
        _setPublicCapability(authority, complianceProxy, ComplianceProxy.depositOnBehalfWithPermit2.selector);
        _setPublicCapability(authority, complianceProxy, ComplianceProxy.mint.selector);
        _setPublicCapability(authority, complianceProxy, ComplianceProxy.mintOnBehalf.selector);
        _setPublicCapability(authority, complianceProxy, ComplianceProxy.requestRedeem.selector);
        _setPublicCapability(authority, complianceProxy, ComplianceProxy.requestRedeemWithPermit2.selector);
        _setPublicCapability(authority, complianceProxy, ComplianceProxy.instantRedeem.selector);
        _setPublicCapability(authority, complianceProxy, ComplianceProxy.instantRedeemWithPermit2.selector);

        // Standalone checks consume attestations, so only the Bundler3 adapter may reach them.
        _setRoleCapability(
            authority, COMPLIANCE_PROXY_ROLE, complianceProxy, bytes4(keccak256("genericUserCheck(address,bytes)"))
        );
        _setRoleCapability(
            authority,
            COMPLIANCE_PROXY_ROLE,
            complianceProxy,
            bytes4(keccak256("genericUserCheck(address,bytes32,bytes)"))
        );
        if (isActive(vaultConfig.common.nestAdapter)) {
            _setUserRole(authority, vaultConfig.common.nestAdapter, COMPLIANCE_PROXY_ROLE);
        }

        // Preserve the composer-specific grant so mintOnBehalf can later be made non-public without
        // interrupting configured cross-chain composers.
        _setRoleCapability(authority, COMPOSER_ROLE, complianceProxy, ComplianceProxy.mintOnBehalf.selector);
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            address composer = vaultConfig.vaults[i].composer;
            if (isActive(composer)) _setUserRole(authority, composer, COMPOSER_ROLE);
        }

        // Operational administration mirrors the V1 pause split: pausers can pause;
        // OWNER_ROLE can recover and manage the provider hook.
        _setRoleCapability(authority, PAUSER_ROLE, complianceProxy, ComplianceProxy.pause.selector);
        _setRoleCapability(authority, OWNER_ROLE, complianceProxy, ComplianceProxy.unpause.selector);
        _setRoleCapability(authority, OWNER_ROLE, complianceProxy, ComplianceProxy.setComplianceHook.selector);
        _setRoleCapability(authority, OWNER_ROLE, predicateV2Hook, PredicateV2Hook.setPolicyID.selector);
        _setRoleCapability(authority, OWNER_ROLE, predicateV2Hook, PredicateV2Hook.setRegistry.selector);
    }

    function _wireContracts() internal {
        PredicateV2Hook hook = PredicateV2Hook(predicateV2Hook);
        ComplianceProxy proxy = ComplianceProxy(complianceProxy);

        if (address(hook.authority()) != vaultAuthority) {
            execute(
                predicateV2Hook,
                abi.encodeCall(AuthUpgradeable.setAuthority, (Authority(vaultAuthority))),
                "PredicateV2Hook.setAuthority"
            );
        }
        if (address(proxy.authority()) != vaultAuthority) {
            execute(
                complianceProxy,
                abi.encodeCall(AuthUpgradeable.setAuthority, (Authority(vaultAuthority))),
                "ComplianceProxy.setAuthority"
            );
        }
        if (hook.getRegistry() != predicateRegistry) {
            execute(
                predicateV2Hook,
                abi.encodeCall(PredicateV2Hook.setRegistry, (predicateRegistry)),
                "PredicateV2Hook.setRegistry"
            );
        }
        if (
            bytes(verificationHash).length > 0
                && keccak256(bytes(hook.getPolicyID())) != keccak256(bytes(verificationHash))
        ) {
            execute(
                predicateV2Hook,
                abi.encodeCall(PredicateV2Hook.setPolicyID, (verificationHash)),
                "PredicateV2Hook.setPolicyID"
            );
        }
        if (address(proxy.complianceHook()) != predicateV2Hook) {
            if (activateHook) {
                execute(
                    complianceProxy,
                    abi.encodeCall(ComplianceProxy.setComplianceHook, (IComplianceHook(predicateV2Hook))),
                    "ComplianceProxy.setComplianceHook"
                );
            } else {
                console.log(
                    "[STAGED] PredicateV2Hook proxy deployed but not activated; set activateHook=true to cut over"
                );
            }
        }
    }

    function _handoffOwnership() internal {
        PredicateV2Hook hook = PredicateV2Hook(predicateV2Hook);
        address hookOwner = hook.owner();
        if (hookOwner == deployer() && governanceOwner != deployer()) {
            hook.transferOwnership(governanceOwner);
            serializedTxs.push(
                SerializedTx({
                    name: "PredicateV2Hook.acceptOwnership",
                    to: predicateV2Hook,
                    value: 0,
                    data: abi.encodeCall(AuthUpgradeable.acceptOwnership, ())
                })
            );
        } else {
            require(
                hookOwner == governanceOwner || hook.pendingOwner() == governanceOwner || governanceOwner == deployer(),
                "DeployComplianceProxy: unexpected hook owner"
            );
        }

        ComplianceProxy proxy = ComplianceProxy(complianceProxy);
        address proxyOwner = proxy.owner();
        if (proxyOwner == deployer() && governanceOwner != deployer()) {
            proxy.transferOwnership(governanceOwner);
            serializedTxs.push(
                SerializedTx({
                    name: "ComplianceProxy.acceptOwnership",
                    to: complianceProxy,
                    value: 0,
                    data: abi.encodeCall(AuthUpgradeable.acceptOwnership, ())
                })
            );
        } else {
            require(
                proxyOwner == governanceOwner || proxy.pendingOwner() == governanceOwner
                    || governanceOwner == deployer(),
                "DeployComplianceProxy: unexpected proxy owner"
            );
        }
    }

    /// @dev A Safe-owned authority can execute the queued calls directly. A timelock-owned
    ///      authority instead needs matching schedule/execute batches; importing the raw calls
    ///      into its proposer Safe would revert because the Safe is not the authority owner.
    function _writeGovernanceBatches() internal {
        if (deployOnlyMode) {
            // A rerun must not leave an obsolete batch after governance has applied its calls.
            string memory prefix = string.concat(
                vm.projectRoot(),
                "/script/output/msig/",
                vm.toString(vaultConfig.deployChainId),
                "-",
                vaultConfig.symbol
            );
            string[3] memory suffixes = [
                "-DeployComplianceProxy.json",
                "-DeployComplianceProxy-Schedule.json",
                "-DeployComplianceProxy-Execute.json"
            ];
            for (uint256 i; i < suffixes.length; ++i) {
                string memory path = string.concat(prefix, suffixes[i]);
                if (vm.exists(path)) vm.removeFile(path);
            }
        }
        if (serializedTxs.length == 0) {
            writeMsigBatch("DeployComplianceProxy");
            return;
        }

        try TimelockController(payable(governanceOwner)).getMinDelay() returns (uint256 delay) {
            console.log("Governance timelock delay:", delay);
            uint256 length = serializedTxs.length;
            address[] memory targets = new address[](length);
            bytes[] memory payloads = new bytes[](length);
            for (uint256 i; i < length; ++i) {
                require(serializedTxs[i].value == 0, "DeployComplianceProxy: timelock value unsupported");
                targets[i] = serializedTxs[i].to;
                payloads[i] = serializedTxs[i].data;
            }

            delete serializedTxs;
            bytes32 salt = keccak256(bytes(string.concat(vaultConfig.symbol, ":DeployComplianceProxy:v2")));
            _buildTimelockBatches(
                governanceOwner,
                targets,
                payloads,
                salt,
                delay,
                "DeployComplianceProxy-Schedule",
                "DeployComplianceProxy-Execute"
            );
        } catch {
            writeMsigBatch("DeployComplianceProxy");
        }
    }

    function _setRoleCapability(RolesAuthority authority, uint8 role, address target, bytes4 selector) internal {
        if (authority.doesRoleHaveCapability(role, target, selector)) return;
        execute(
            address(authority),
            abi.encodeCall(RolesAuthority.setRoleCapability, (role, target, selector, true)),
            string.concat(
                "setRoleCapability(role=",
                vm.toString(role),
                ", target=",
                vm.toString(target),
                ", selector=",
                vm.toString(selector),
                ")"
            )
        );
    }

    function _setPublicCapability(RolesAuthority authority, address target, bytes4 selector) internal {
        if (authority.isCapabilityPublic(target, selector)) return;
        execute(
            address(authority),
            abi.encodeCall(RolesAuthority.setPublicCapability, (target, selector, true)),
            string.concat("setPublicCapability(target=", vm.toString(target), ", selector=", vm.toString(selector), ")")
        );
    }

    function _setUserRole(RolesAuthority authority, address user, uint8 role) internal {
        if (authority.doesUserHaveRole(user, role)) return;
        execute(
            address(authority),
            abi.encodeCall(RolesAuthority.setUserRole, (user, role, true)),
            string.concat("setUserRole(user=", vm.toString(user), ", role=", vm.toString(role), ")")
        );
    }

    function _assertConfiguredAddress(string memory label, address configured, address expected) internal pure {
        require(
            configured == address(0) || configured == expected,
            string.concat("DeployComplianceProxy: configured ", label, " does not match CREATE3 address")
        );
    }

    function _persistAddresses() internal {
        vm.writeJson(vm.toString(predicateV2Hook), complianceConfigPath, ".predicateV2Hook");
        if (legacyPredicateV2Hook != address(0)) {
            vm.writeJson(vm.toString(legacyPredicateV2Hook), complianceConfigPath, ".legacyPredicateV2Hook");
        }
        vm.writeJson(vm.toString(complianceProxy), complianceConfigPath, ".complianceProxy");
        console.log("Compliance deployment config updated:", complianceConfigPath);
    }

    function _printSummary() internal view {
        console.log("=== Predicate V2 Compliance Deployment ===");
        console.log("Chain ID:", vaultConfig.deployChainId);
        console.log("Predicate API chain:", apiChain);
        console.log("Predicate Registry:", predicateRegistry);
        console.log("PredicateV2Hook:", predicateV2Hook);
        if (legacyPredicateV2Hook != address(0)) {
            console.log("Legacy PredicateV2Hook rollback target:", legacyPredicateV2Hook);
        }
        console.log("ComplianceProxy:", complianceProxy);
        console.log("Active compliance hook:", address(ComplianceProxy(complianceProxy).complianceHook()));
        if (deployOnlyMode) {
            console.log("Common authority attached:", vaultConfig.common.commonRolesAuthority);
        } else {
            console.log("Vault authority:", vaultAuthority);
        }
        console.log("Governance owner:", governanceOwner);
        console.log("Dashboard contract to register:", predicateV2Hook);
        console.log("Attestation request `to`:", predicateV2Hook);
        if (deployOnlyMode) {
            console.log("Configured policy ID:", verificationHash);
            console.log("Current on-chain policy ID:", PredicateV2Hook(predicateV2Hook).getPolicyID());
            console.log("Governance configuration calls queued:", serializedTxs.length);
        } else if (bytes(verificationHash).length == 0) {
            console.log("Predicate policy: pending dashboard verificationHash; rerun after setting it in config");
        }
        console.log("==========================================");

        if (ComplianceProxy(complianceProxy).pendingOwner() == governanceOwner) {
            console.log("ComplianceProxy ownership is pending governanceOwner.acceptOwnership()");
        }
        if (PredicateV2Hook(predicateV2Hook).pendingOwner() == governanceOwner) {
            console.log("PredicateV2Hook ownership is pending governanceOwner.acceptOwnership()");
        }
    }
}
