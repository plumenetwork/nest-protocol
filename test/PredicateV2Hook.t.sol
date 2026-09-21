// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {AuthUpgradeable} from "contracts/auth/AuthUpgradeable.sol";
import {PredicateV2Hook} from "contracts/compliance/hooks/PredicateV2Hook.sol";
import {Attestation} from "@predicate-v2/interfaces/IPredicateRegistry.sol";
import {MockPredicateRegistry} from "test/mock/MockPredicateRegistry.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract PredicateV2HookV2 is PredicateV2Hook {
    function upgraded() external pure returns (bool) {
        return true;
    }
}

contract PredicateV2HookTest is Test {
    string internal constant POLICY_ID = "x-a1b2c3d4e5f6a7b8";
    uint8 internal constant COMPLIANCE_HOOK_ROLE = 9;
    bytes32 internal constant ERC1967_ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);

    MockPredicateRegistry internal registry;
    PredicateV2Hook internal hook;
    RolesAuthority internal authority;

    address internal user = makeAddr("user");
    address internal attester = makeAddr("attester");
    address internal authorizedCaller = makeAddr("authorizedCaller");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        registry = new MockPredicateRegistry();
        authority = new RolesAuthority(address(this), Authority(address(0)));
        hook = _deployHook(address(this), Authority(address(authority)), address(registry), POLICY_ID);
        authority.setRoleCapability(COMPLIANCE_HOOK_ROLE, address(hook), PredicateV2Hook.checkCompliance.selector, true);
        authority.setUserRole(authorizedCaller, COMPLIANCE_HOOK_ROLE, true);
    }

    function _attestation(string memory _uuid) internal view returns (Attestation memory) {
        return Attestation({uuid: _uuid, expiration: block.timestamp + 300, attester: attester, signature: hex"c0ffee"});
    }

    function _deployHook(address _owner, Authority _authority, address _registry, string memory _policyID)
        internal
        returns (PredicateV2Hook)
    {
        PredicateV2Hook implementation = new PredicateV2Hook();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(this),
            abi.encodeCall(PredicateV2Hook.initialize, (_owner, _authority, _registry, _policyID))
        );
        return PredicateV2Hook(address(proxy));
    }

    // ========================================= INITIALIZER =========================================

    function test_initialize_registers_policy_with_registry() public view {
        assertEq(registry.getPolicyID(address(hook)), POLICY_ID);
        assertEq(hook.getPolicyID(), POLICY_ID);
        assertEq(hook.getRegistry(), address(registry));
        assertEq(hook.owner(), address(this));
        assertEq(address(hook.authority()), address(authority));
        assertEq(hook.version(), "1.0.0");
    }

    function test_initialize_allows_policy_to_be_set_after_deployment() public {
        PredicateV2Hook pendingHook = _deployHook(address(this), Authority(address(0)), address(registry), "");

        assertEq(pendingHook.getPolicyID(), "");
        assertEq(registry.getPolicyID(address(pendingHook)), "");

        pendingHook.setPolicyID(POLICY_ID);

        assertEq(pendingHook.getPolicyID(), POLICY_ID);
        assertEq(registry.getPolicyID(address(pendingHook)), POLICY_ID);
    }

    function test_initialize_reverts_on_zero_registry_or_owner() public {
        PredicateV2Hook zeroRegistryImplementation = new PredicateV2Hook();
        vm.expectRevert(PredicateV2Hook.PredicateV2Hook__ZeroAddress.selector);
        new TransparentUpgradeableProxy(
            address(zeroRegistryImplementation),
            address(this),
            abi.encodeCall(PredicateV2Hook.initialize, (address(this), Authority(address(0)), address(0), POLICY_ID))
        );

        PredicateV2Hook zeroOwnerImplementation = new PredicateV2Hook();
        vm.expectRevert(PredicateV2Hook.PredicateV2Hook__ZeroAddress.selector);
        new TransparentUpgradeableProxy(
            address(zeroOwnerImplementation),
            address(this),
            abi.encodeCall(
                PredicateV2Hook.initialize, (address(0), Authority(address(0)), address(registry), POLICY_ID)
            )
        );
    }

    function test_initialize_reverts_when_called_twice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        hook.initialize(address(this), Authority(address(authority)), address(registry), POLICY_ID);
    }

    function test_implementation_initializers_are_disabled() public {
        PredicateV2Hook implementation = new PredicateV2Hook();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(address(this), Authority(address(authority)), address(registry), POLICY_ID);
    }

    // ========================================= CALLER GATING =========================================

    function test_checkCompliance_reverts_for_unauthorized_caller() public {
        vm.prank(stranger);
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        hook.checkCompliance(user, abi.encodeWithSignature("deposit()"), abi.encode(_attestation("uuid-x")));
    }

    function test_checkCompliance_allows_roles_authority_caller() public {
        vm.prank(authorizedCaller);
        assertTrue(hook.checkCompliance(user, abi.encodeWithSignature("deposit()"), abi.encode(_attestation("uuid-y"))));
    }

    // ========================================= CHECK COMPLIANCE =========================================

    function test_checkCompliance_builds_statement_and_returns_verdict() public {
        bytes memory _payload = abi.encodeWithSignature("deposit()");
        Attestation memory _att = _attestation("uuid-1");

        bool _ok = hook.checkCompliance(user, _payload, abi.encode(_att));

        assertTrue(_ok);
        assertEq(registry.validateCalls(), 1);
        assertEq(registry.lastMsgSender(), user);
        assertEq(registry.lastTarget(), address(hook));
        assertEq(registry.lastMsgValue(), 0);
        assertEq(registry.lastEncodedSigAndArgs(), _payload);
        assertEq(registry.lastPolicy(), POLICY_ID);
        assertEq(registry.lastUuid(), "uuid-1");
        assertEq(registry.lastExpiration(), _att.expiration);
        assertEq(registry.lastAttester(), attester);
    }

    function test_checkCompliance_forwards_on_behalf_payload_in_standard_statement() public {
        bytes32 _depositor = bytes32(uint256(uint160(makeAddr("original-depositor"))));
        bytes memory _payload = abi.encodeWithSignature("deposit(bytes32)", _depositor);
        Attestation memory _att = _attestation("uuid-on-behalf-1");

        vm.prank(authorizedCaller);
        bool _ok = hook.checkCompliance(user, _payload, abi.encode(_att));

        assertTrue(_ok);
        assertEq(registry.validateCalls(), 1);
        assertEq(registry.lastMsgSender(), user);
        assertEq(registry.lastTarget(), address(hook));
        assertEq(registry.lastMsgValue(), 0);
        assertEq(registry.lastEncodedSigAndArgs(), _payload);
        assertEq(registry.lastPolicy(), POLICY_ID);
        assertEq(registry.lastUuid(), "uuid-on-behalf-1");
        assertEq(registry.lastExpiration(), _att.expiration);
        assertEq(registry.lastAttester(), attester);
    }

    function test_checkCompliance_returns_false_when_registry_denies() public {
        registry.setIsVerified(false);
        bool _ok = hook.checkCompliance(user, abi.encodeWithSignature("deposit()"), abi.encode(_attestation("uuid-2")));
        assertFalse(_ok);
    }

    function test_checkCompliance_propagates_registry_revert() public {
        registry.setRevertOnValidate(true);
        vm.expectRevert("MockPredicateRegistry: invalid attestation");
        hook.checkCompliance(user, abi.encodeWithSignature("deposit()"), abi.encode(_attestation("uuid-3")));
    }

    function test_checkCompliance_reverts_on_replayed_uuid() public {
        bytes memory _payload = abi.encodeWithSignature("deposit()");
        hook.checkCompliance(user, _payload, abi.encode(_attestation("uuid-4")));

        vm.expectRevert("MockPredicateRegistry: uuid spent");
        hook.checkCompliance(user, _payload, abi.encode(_attestation("uuid-4")));
    }

    function test_checkCompliance_reverts_on_malformed_data() public {
        vm.expectRevert();
        hook.checkCompliance(user, abi.encodeWithSignature("deposit()"), hex"deadbeef");
    }

    // ========================================= ADMIN =========================================

    function test_setPolicyID_updates_registry_and_storage() public {
        hook.setPolicyID("x-new");
        assertEq(hook.getPolicyID(), "x-new");
        assertEq(registry.getPolicyID(address(hook)), "x-new");
    }

    function test_setPolicyID_reverts_for_stranger() public {
        vm.prank(stranger);
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        hook.setPolicyID("x-new");
    }

    function test_setRegistry_reregisters_policy_on_new_registry() public {
        MockPredicateRegistry _newRegistry = new MockPredicateRegistry();
        hook.setRegistry(address(_newRegistry));
        assertEq(hook.getRegistry(), address(_newRegistry));
        assertEq(_newRegistry.getPolicyID(address(hook)), POLICY_ID);
    }

    function test_setRegistry_reverts_on_zero_address() public {
        vm.expectRevert(PredicateV2Hook.PredicateV2Hook__ZeroAddress.selector);
        hook.setRegistry(address(0));
    }

    function test_setRegistry_reverts_for_stranger() public {
        vm.prank(stranger);
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        hook.setRegistry(address(1));
    }

    function test_upgrade_preserves_auth_and_predicate_config() public {
        address proxyAdmin = address(uint160(uint256(vm.load(address(hook), ERC1967_ADMIN_SLOT))));
        PredicateV2HookV2 implementationV2 = new PredicateV2HookV2();

        ProxyAdmin(proxyAdmin)
            .upgradeAndCall(ITransparentUpgradeableProxy(address(hook)), address(implementationV2), bytes(""));

        PredicateV2HookV2 upgradedHook = PredicateV2HookV2(address(hook));
        assertTrue(upgradedHook.upgraded());
        assertEq(upgradedHook.owner(), address(this));
        assertEq(address(upgradedHook.authority()), address(authority));
        assertEq(upgradedHook.getRegistry(), address(registry));
        assertEq(upgradedHook.getPolicyID(), POLICY_ID);
        vm.prank(authorizedCaller);
        assertTrue(
            upgradedHook.checkCompliance(
                user, abi.encodeWithSignature("deposit()"), abi.encode(_attestation("uuid-v2"))
            )
        );
    }
}
