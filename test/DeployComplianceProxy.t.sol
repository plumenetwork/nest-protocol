// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployComplianceProxy} from "script/deploy/DeployComplianceProxy.s.sol";
import {ICreateX} from "createx/ICreateX.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {AuthUpgradeable} from "contracts/auth/AuthUpgradeable.sol";
import {PredicateV2Hook} from "contracts/compliance/hooks/PredicateV2Hook.sol";
import {ComplianceProxy} from "contracts/compliance/ComplianceProxy.sol";
import {MockPredicateRegistry} from "test/mock/MockPredicateRegistry.sol";
import {ConfigReader} from "script/lib/ConfigReader.sol";
import {Auth} from "@solmate/auth/Auth.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {SerializedTx} from "script/lib/SafeBatchSerialize.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract DeployComplianceProxyHarness is DeployComplianceProxy {
    function seed(
        address createx,
        address registry,
        address authority,
        address owner_,
        uint256 key,
        string memory policy
    ) external {
        commonConfig.createx = createx;
        CREATEX = ICreateX(createx);
        deployOnlyMode = true;
        predicateRegistry = registry;
        apiChain = "plume";
        vaultConfig.common.commonRolesAuthority = authority;
        vaultConfig.deployChainId = 98866;
        vaultConfig.symbol = "COMMON_DEPLOY_TEST";
        deployerPrivateKey = key;
        governanceOwner = owner_;
        verificationHash = policy;
    }

    function deployStage() external returns (PredicateV2Hook hook, ComplianceProxy proxy) {
        _prepareDeployOnly();
        vm.startBroadcast(deployerPrivateKey);
        _deployHook();
        _deployProxy();
        _assertDeployOnlyHook();
        _assertDeployOnlyComplianceProxy();
        vm.stopBroadcast();
        _applyCommonConfiguration();
        return (PredicateV2Hook(predicateV2Hook), ComplianceProxy(complianceProxy));
    }

    function useFreshV2Mode() external {
        chainComplianceConfig.v2Only = true;
    }

    function queuedTransactions() external view returns (SerializedTx[] memory) {
        return serializedTxs;
    }

    function writeGovernanceBatches() external {
        _writeGovernanceBatches();
    }

    function setOutputSymbol(string memory symbol) external {
        vaultConfig.symbol = symbol;
    }

    function deployHookOnly() external returns (address) {
        _prepareDeployOnly();
        vm.startBroadcast(deployerPrivateKey);
        _deployHook();
        vm.stopBroadcast();
        return predicateV2Hook;
    }

    function deployVaultStack() external returns (PredicateV2Hook hook, ComplianceProxy proxy) {
        deployOnlyMode = false;
        vaultConfig.symbol = "nTEST";
        vaultAuthority = vaultConfig.common.commonRolesAuthority;
        predicateV2Hook = address(0);
        complianceProxy = address(0);
        vm.startBroadcast(deployerPrivateKey);
        _deployHook();
        _deployProxy();
        vm.stopBroadcast();
        require(predicateV2Hook == computeCreate3Address("PredicateV2HookProxy"));
        require(complianceProxy == computeCreate3Address("ComplianceProxy-v2"));
        require(ProxyAdmin(_proxyAdmin(predicateV2Hook)).owner() == governanceOwner);
        require(ProxyAdmin(_proxyAdmin(complianceProxy)).owner() == governanceOwner);
        return (PredicateV2Hook(predicateV2Hook), ComplianceProxy(complianceProxy));
    }

    function configureActiveProxy(address target) external {
        vaultConfig.common.complianceProxy = target;
    }

    function loadDeployOnlyConfig() external {
        _loadDeployOnlyConfig();
    }

    function configuredPolicyId() external view returns (string memory) {
        return verificationHash;
    }
}

contract DeployComplianceProxyTest is Test {
    uint256 internal constant KEY = 12345;
    DeployComplianceProxyHarness internal stage;
    MockPredicateRegistry internal registry;
    RolesAuthority internal authority;
    address internal createxFixture;

    function setUp() public {
        bytes memory initCode = vm.parseBytes(vm.trim(vm.readFile("config/createx/initcode.hex")));
        address factory;
        assembly {
            factory := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(factory != address(0), "CreateX fixture deployment failed");
        createxFixture = factory;
        vm.deal(vm.addr(KEY), 100 ether);
        registry = new MockPredicateRegistry();
        authority = new RolesAuthority(address(this), Authority(address(0)));
        stage = new DeployComplianceProxyHarness();
        // Keep the factory at its original address: its CREATE3 implementation embeds _SELF.
        stage.seed(factory, address(registry), address(authority), address(this), KEY, "test-policy");
    }

    function test_deploymentAttachesCommonAuthorityBeforeItsPermissionsAreConfigured() public {
        (PredicateV2Hook hook, ComplianceProxy proxy) = stage.deployStage();
        assertEq(hook.owner(), address(this));
        assertEq(proxy.owner(), vm.addr(KEY));
        assertEq(proxy.pendingOwner(), address(this));
        assertEq(address(hook.authority()), address(authority));
        assertEq(address(proxy.authority()), address(authority));
        assertEq(address(proxy.complianceHook()), address(hook));
        assertEq(registry.getPolicyID(address(hook)), "test-policy");
        assertFalse(authority.doesUserHaveRole(address(proxy), 7));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        vm.prank(address(0xBEEF));
        proxy.genericUserCheck(address(0xBEEF), "");
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        vm.prank(address(proxy));
        hook.checkCompliance(address(0xBEEF), "", "");
    }

    function test_freshV2ConfiguresDirectlyAndKeepsAllOwnershipWithDeployer() public {
        address deployer = vm.addr(KEY);
        authority.transferOwnership(deployer);
        stage.seed(createxFixture, address(registry), address(authority), deployer, KEY, "test-policy");
        stage.useFreshV2Mode();
        (PredicateV2Hook hook, ComplianceProxy proxy) = stage.deployStage();
        assertEq(hook.owner(), deployer);
        assertEq(proxy.owner(), deployer);
        assertEq(hook.pendingOwner(), address(0));
        assertEq(proxy.pendingOwner(), address(0));
        assertEq(stage.queuedTransactions().length, 0);
        assertTrue(authority.canCall(address(proxy), address(hook), PredicateV2Hook.checkCompliance.selector));
        assertTrue(authority.canCall(address(0xBEEF), address(proxy), ComplianceProxy.deposit.selector));
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        assertEq(ProxyAdmin(address(uint160(uint256(vm.load(address(hook), adminSlot))))).owner(), deployer);
        assertEq(ProxyAdmin(address(uint160(uint256(vm.load(address(proxy), adminSlot))))).owner(), deployer);
        // A policy correction is applied directly, and subsequent runs are no-ops.
        vm.prank(deployer);
        hook.setPolicyID("wrong-policy");
        stage.deployStage();
        assertEq(hook.getPolicyID(), "test-policy");
        assertEq(stage.queuedTransactions().length, 0);
        uint64 nonce = vm.getNonce(deployer);
        stage.deployStage();
        assertEq(vm.getNonce(deployer), nonce);
    }

    function test_vaultDeploymentPreservesOriginalSaltsAndInitialOwnership() public {
        (PredicateV2Hook sharedHook, ComplianceProxy sharedProxy) = stage.deployStage();
        (PredicateV2Hook vaultHook, ComplianceProxy vaultProxy) = stage.deployVaultStack();
        assertNotEq(address(vaultHook), address(sharedHook));
        assertNotEq(address(vaultProxy), address(sharedProxy));
        assertEq(vaultHook.owner(), vm.addr(KEY));
        assertEq(vaultProxy.owner(), vm.addr(KEY));
        assertEq(address(vaultHook.authority()), address(authority));
        assertEq(address(vaultProxy.authority()), address(0));
        assertEq(address(vaultProxy.complianceHook()), address(vaultHook));
        assertEq(registry.getPolicyID(address(vaultHook)), "test-policy");
    }

    function test_rerunReusesBothProxiesWithoutDeployingOrChangingPolicy() public {
        (PredicateV2Hook hook, ComplianceProxy proxy) = stage.deployStage();
        uint64 nonce = vm.getNonce(vm.addr(KEY));
        (PredicateV2Hook sameHook, ComplianceProxy sameProxy) = stage.deployStage();
        assertEq(address(sameHook), address(hook));
        assertEq(address(sameProxy), address(proxy));
        assertEq(vm.getNonce(vm.addr(KEY)), nonce);
    }

    function test_recordedSharedProxyAllowsRerunOnV1Chain() public {
        (, ComplianceProxy proxy) = stage.deployStage();
        // The chain keeps V1 (v2Only false); a recorded matching address no longer blocks reruns.
        stage.configureActiveProxy(address(proxy));
        stage.deployStage();
        stage.configureActiveProxy(address(0xBAD));
        vm.expectRevert("DeployComplianceProxy: common compliance proxy already configured");
        stage.deployStage();
    }

    function test_partialDeploymentResumesWithoutReplacingHook() public {
        address hook = stage.deployHookOnly();
        (PredicateV2Hook sameHook, ComplianceProxy proxy) = stage.deployStage();
        assertEq(address(sameHook), hook);
        assertEq(address(proxy.complianceHook()), hook);
        assertEq(proxy.owner(), vm.addr(KEY));
        assertEq(proxy.pendingOwner(), address(this));
    }

    function test_policyMismatchQueuesConfigPolicyWithoutChangingItDirectly() public {
        (PredicateV2Hook hook,) = stage.deployStage();
        hook.setPolicyID("production-policy");
        assertEq(registry.getPolicyID(address(hook)), "production-policy");
        stage.deployStage();
        assertEq(hook.getPolicyID(), "production-policy");
        SerializedTx[] memory txs = stage.queuedTransactions();
        assertGt(txs.length, 1);
        assertEq(txs[0].to, address(hook));
        assertEq(txs[0].data, abi.encodeCall(PredicateV2Hook.setPolicyID, ("test-policy")));
        (bool success,) = txs[0].to.call(txs[0].data);
        assertTrue(success);
        assertEq(registry.getPolicyID(address(hook)), "test-policy");
    }

    function test_rerunRejectsUnexpectedAuthority() public {
        (PredicateV2Hook hook,) = stage.deployStage();
        hook.setAuthority(Authority(address(0xBAD)));
        vm.expectRevert("DeployComplianceProxy: hook authority mismatch");
        stage.deployStage();
    }

    function test_safeBatchAcceptsOwnershipAndConfiguresCommonAuthorityWithoutQueuedSetAuthority() public {
        vm.chainId(98866);
        (PredicateV2Hook hook, ComplianceProxy proxy) = stage.deployStage();
        stage.writeGovernanceBatches();
        string memory path = "script/output/msig/98866-COMMON_DEPLOY_TEST-DeployComplianceProxy.json";
        string memory json = vm.readFile(path);
        assertEq(vm.parseJsonUint(json, ".chainId"), 98866);
        assertEq(vm.parseJsonString(json, ".meta.name"), "Transactions Batch");
        SerializedTx[] memory txs = stage.queuedTransactions();
        assertGt(txs.length, 0);
        assertFalse(vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(txs.length), "]")));
        for (uint256 i; i < txs.length; ++i) {
            string memory key = string.concat(".transactions[", vm.toString(i), "]");
            address target = vm.parseJsonAddress(json, string.concat(key, ".to"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(key, ".data"));
            bytes4 selector = bytes4(data);
            if (target == address(proxy)) {
                assertEq(selector, AuthUpgradeable.acceptOwnership.selector);
            } else {
                assertEq(target, address(authority));
                assertTrue(
                    selector == RolesAuthority.setRoleCapability.selector
                        || selector == RolesAuthority.setPublicCapability.selector
                        || selector == RolesAuthority.setUserRole.selector
                );
            }
            assertEq(vm.parseJsonString(json, string.concat(key, ".value")), "0");
            (bool success,) = target.call(data);
            assertTrue(success);
        }
        assertEq(address(hook.authority()), address(authority));
        assertEq(address(proxy.authority()), address(authority));
        assertFalse(authority.doesUserHaveRole(address(proxy), 7));
        assertEq(proxy.owner(), authority.owner());
        assertEq(proxy.pendingOwner(), address(0));
        assertTrue(authority.canCall(address(proxy), address(hook), PredicateV2Hook.checkCompliance.selector));
        assertTrue(authority.canCall(address(0xBEEF), address(proxy), ComplianceProxy.deposit.selector));
        assertFalse(authority.canCall(address(0xBEEF), address(hook), PredicateV2Hook.checkCompliance.selector));
        assertFalse(
            authority.canCall(address(0xBEEF), address(proxy), bytes4(keccak256("genericUserCheck(address,bytes)")))
        );
        assertTrue(authority.doesRoleHaveCapability(6, address(proxy), ComplianceProxy.pause.selector));
        assertTrue(authority.doesRoleHaveCapability(0, address(hook), PredicateV2Hook.setPolicyID.selector));
        // Vault access remains a separate grant on the vault's existing authority.
        RolesAuthority vaultAuth = new RolesAuthority(address(this), Authority(address(0)));
        bytes4 depositSelector = bytes4(keccak256("deposit(uint256,address)"));
        vaultAuth.setRoleCapability(7, address(0xCAFE), depositSelector, true);
        assertFalse(vaultAuth.canCall(address(proxy), address(0xCAFE), depositSelector));
        uint64 nonce = vm.getNonce(vm.addr(KEY));
        stage.deployStage();
        assertEq(vm.getNonce(vm.addr(KEY)), nonce);
        assertEq(stage.queuedTransactions().length, 0);
        stage.writeGovernanceBatches();
        assertFalse(vm.exists(path));
    }

    function test_timelockBatchesScheduleAndExecuteCommonAuthorityConfiguration() public {
        vm.chainId(98866);
        address[] memory signers = new address[](1);
        signers[0] = address(this);
        TimelockController timelock = new TimelockController(1 days, signers, signers, address(this));
        authority.transferOwnership(address(timelock));
        stage.seed(createxFixture, address(registry), address(authority), address(timelock), KEY, "test-policy");
        stage.setOutputSymbol("COMMON_TIMELOCK_TEST");
        (PredicateV2Hook hook, ComplianceProxy proxy) = stage.deployStage();
        assertEq(address(hook.authority()), address(authority));
        assertEq(address(proxy.authority()), address(authority));
        assertFalse(authority.canCall(address(proxy), address(hook), PredicateV2Hook.checkCompliance.selector));
        stage.writeGovernanceBatches();
        string memory prefix = "script/output/msig/98866-COMMON_TIMELOCK_TEST-DeployComplianceProxy";
        string memory schedulePath = string.concat(prefix, "-Schedule.json");
        string memory executePath = string.concat(prefix, "-Execute.json");
        string memory json = vm.readFile(schedulePath);
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), address(timelock));
        (bool scheduled,) = address(timelock).call(vm.parseJsonBytes(json, ".transactions[0].data"));
        assertTrue(scheduled);
        vm.warp(block.timestamp + 1 days);
        json = vm.readFile(executePath);
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), address(timelock));
        (bool executed,) = address(timelock).call(vm.parseJsonBytes(json, ".transactions[0].data"));
        assertTrue(executed);
        assertEq(address(hook.authority()), address(authority));
        assertEq(address(proxy.authority()), address(authority));
        assertEq(proxy.owner(), authority.owner());
        assertEq(proxy.pendingOwner(), address(0));
        assertTrue(authority.canCall(address(proxy), address(hook), PredicateV2Hook.checkCompliance.selector));
        assertTrue(authority.canCall(address(0xBEEF), address(proxy), ComplianceProxy.deposit.selector));
        vm.removeFile(schedulePath);
        vm.removeFile(executePath);
    }

    function test_rejectsExistingCanonicalProxyBeforeDeploying() public {
        stage.configureActiveProxy(address(0x123));
        uint64 nonce = vm.getNonce(vm.addr(KEY));
        vm.expectRevert("DeployComplianceProxy: common compliance proxy already configured");
        stage.deployStage();
        assertEq(vm.getNonce(vm.addr(KEY)), nonce);
    }

    function test_setupRejectsWrongRPCChain() public {
        vm.setEnv("CHAIN_ID", "98866");
        vm.chainId(1);
        vm.expectRevert("DeployComplianceProxy: RPC chain mismatch");
        stage.loadDeployOnlyConfig();
    }

    function test_setupUsesCommonPolicyConfigAndIgnoresEnvironmentOverride() public {
        vm.chainId(98866);
        vm.setEnv("CHAIN_ID", "98866");
        vm.setEnv("PRIVATE_KEY", vm.toString(KEY));
        vm.setEnv("PREDICATE_POLICY_ID", "stale-environment-policy");

        // Populate only the external dependencies needed by the config-loading preflight.
        address createx = ConfigReader.readCommonConfig(98866).createx;
        vm.etch(createx, createxFixture.code);
        address liveRegistry = ConfigReader.readComplianceConfig(98866).v2.predicateRegistry;
        vm.etch(liveRegistry, address(registry).code);
        address commonAuthority = ConfigReader.readCommonProxyConfig(98866).commonRolesAuthority;
        vm.etch(commonAuthority, address(authority).code);
        vm.mockCall(commonAuthority, abi.encodeWithSignature("owner()"), abi.encode(address(this)));

        stage.loadDeployOnlyConfig();
        string memory configured = ConfigReader.readVaultConfig("nCOMMON").compliance.v2.verificationHash;
        assertEq(configured, "x-managed-policy-8a45c2ae80a41dac8475d7b73a432c95");
        assertEq(stage.configuredPolicyId(), configured);
        assertTrue(keccak256(bytes(configured)) != keccak256("stale-environment-policy"));
    }

    /// @dev Optional integration check using a disposable test signer on a fork only.
    ///      Does not write deployment manifests or consume the real deployment key.
    function test_forkUsesLiveCreateXAndPredicateRegistry() public {
        vm.skip(!vm.envOr("STAGE_PREDICATE_V2_FORK", false));
        address createx = ConfigReader.readCommonConfig(block.chainid).createx;
        address liveRegistry = ConfigReader.readComplianceConfig(block.chainid).v2.predicateRegistry;
        address commonAuthority = ConfigReader.readCommonProxyConfig(block.chainid).commonRolesAuthority;
        address owner_ = Auth(commonAuthority).owner();
        require(createx.code.length > 0 && liveRegistry.code.length > 0 && owner_.code.length > 0);
        string memory policy = ConfigReader.readVaultConfig("nCOMMON").compliance.v2.verificationHash;
        stage.seed(createx, liveRegistry, commonAuthority, owner_, KEY, policy);
        (PredicateV2Hook hook, ComplianceProxy proxy) = stage.deployStage();
        assertEq(hook.getRegistry(), liveRegistry);
        assertEq(hook.getPolicyID(), policy);
        assertEq(hook.owner(), owner_);
        assertEq(proxy.owner(), vm.addr(KEY));
        assertEq(proxy.pendingOwner(), owner_);
        assertEq(address(hook.authority()), commonAuthority);
        assertEq(address(proxy.authority()), commonAuthority);
    }
}
