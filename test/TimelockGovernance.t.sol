// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @dev Minimal two-step ownable mirroring AuthUpgradeable's owner/pendingOwner/accept semantics
///      (contracts/auth/AuthUpgradeable.sol) so the schedule→execute acceptOwnership flow
///      can be exercised without the full vault stack.
contract MockTwoStepOwnable {
    address public owner;
    address public pendingOwner;

    constructor(address _owner) {
        owner = _owner;
    }

    function transferOwnership(address n) external {
        require(msg.sender == owner, "not owner");
        pendingOwner = n;
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "not pending");
        owner = pendingOwner;
        pendingOwner = address(0);
    }
}

/// @title  TimelockGovernanceTest
/// @notice Validates the two-tier timelock governance model on-chain: the DeployTimelock handoff
///         invariants, the closed self-admin hole, the TransferOwnership schedule→execute accept flow,
///         and the admin-tier recovery path. Uses the real OZ TimelockController so behavior is faithful;
///         the AT/PT wiring here mirrors script/deploy/DeployTimelock.s.sol exactly.
contract TimelockGovernanceTest is Test {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    uint256 internal constant PROTOCOL_DELAY = 48 hours;
    uint256 internal constant ADMIN_DELAY = 7 days;

    address internal deployer = makeAddr("deployer");
    address internal opSafe = makeAddr("opSafe"); // operational multisig: PT proposer/executor/canceller
    address internal adminSafe = makeAddr("adminSafe"); // council multisig: AT admin/proposer/executor/canceller
    address internal partner = makeAddr("partner"); // partner canceller on PT only

    TimelockController internal at; // admin timelock (7d)
    TimelockController internal pt; // protocol timelock (48h)

    bytes32 internal CANCELLER_ROLE;
    bytes32 internal PROPOSER_ROLE;
    bytes32 internal EXECUTOR_ROLE;

    function setUp() public {
        // ── Mirror DeployTimelock: AT first (adminSafe = admin + proposer + executor + canceller) ──
        address[] memory adminArr = _one(adminSafe);
        at = new TimelockController(ADMIN_DELAY, adminArr, adminArr, adminSafe);

        // ── PT next: opSafe = proposer + executor + canceller; deployer = transient admin ──
        address[] memory opArr = _one(opSafe);
        pt = new TimelockController(PROTOCOL_DELAY, opArr, opArr, deployer);

        CANCELLER_ROLE = pt.CANCELLER_ROLE();
        PROPOSER_ROLE = pt.PROPOSER_ROLE();
        EXECUTOR_ROLE = pt.EXECUTOR_ROLE();

        // ── Handoff (as transient admin): partner canceller → AT admin → strip PT self-admin → renounce ──
        vm.startPrank(deployer);
        pt.grantRole(CANCELLER_ROLE, partner); // 3a partner canceller (PT only)
        pt.grantRole(DEFAULT_ADMIN_ROLE, address(at)); // 3b AT becomes admin
        pt.revokeRole(DEFAULT_ADMIN_ROLE, address(pt)); // 3c strip PT self-admin
        pt.renounceRole(DEFAULT_ADMIN_ROLE, deployer); // 3d deployer steps down
        vm.stopPrank();
    }

    // ─── Handoff invariants ─────────────────────────────────────────────

    function test_handoff_adminTimelock_is_sole_admin_of_protocol() public view {
        assertTrue(pt.hasRole(DEFAULT_ADMIN_ROLE, address(at)), "AT must be admin of PT");
        assertFalse(pt.hasRole(DEFAULT_ADMIN_ROLE, address(pt)), "PT must NOT be self-admin");
        assertFalse(pt.hasRole(DEFAULT_ADMIN_ROLE, deployer), "deployer must hold no admin");
        assertFalse(pt.hasRole(DEFAULT_ADMIN_ROLE, opSafe), "op Safe must hold no admin on PT");
    }

    function test_handoff_roles_and_delays() public view {
        // PT: op Safe is proposer/executor/canceller
        assertTrue(pt.hasRole(PROPOSER_ROLE, opSafe));
        assertTrue(pt.hasRole(EXECUTOR_ROLE, opSafe));
        assertTrue(pt.hasRole(CANCELLER_ROLE, opSafe));
        // PT: partner is canceller only
        assertTrue(pt.hasRole(CANCELLER_ROLE, partner));
        assertFalse(pt.hasRole(PROPOSER_ROLE, partner), "partner must not propose");
        assertFalse(pt.hasRole(EXECUTOR_ROLE, partner), "partner must not execute");
        // AT: partner has nothing; adminSafe controls it
        assertFalse(at.hasRole(CANCELLER_ROLE, partner), "partner must have no power on AT");
        assertTrue(at.hasRole(DEFAULT_ADMIN_ROLE, adminSafe));
        assertTrue(at.hasRole(PROPOSER_ROLE, adminSafe));
        // delays + escape-window invariant (adminDelay > protocolDelay)
        assertEq(pt.getMinDelay(), PROTOCOL_DELAY);
        assertEq(at.getMinDelay(), ADMIN_DELAY);
        assertGt(at.getMinDelay(), pt.getMinDelay(), "escape-window invariant: adminDelay > protocolDelay");
    }

    // ─── The closed self-admin hole ─────────────────────────────────────

    /// @notice The operational Safe must NOT be able to sever the admin tier from PT.
    function test_opSafe_cannot_sever_admin_tier() public {
        vm.prank(opSafe);
        vm.expectRevert(); // opSafe is not DEFAULT_ADMIN on PT
        pt.revokeRole(DEFAULT_ADMIN_ROLE, address(at));

        vm.prank(opSafe);
        vm.expectRevert(); // ...nor grant itself admin
        pt.grantRole(DEFAULT_ADMIN_ROLE, opSafe);
    }

    function test_partner_cannot_propose_on_protocol() public {
        vm.prank(partner);
        vm.expectRevert();
        pt.schedule(address(0xBEEF), 0, "", bytes32(0), bytes32("x"), PROTOCOL_DELAY);
    }

    // ─── TransferOwnership: schedule → warp → execute acceptOwnership ────

    /// @notice Mirrors TransferOwnership timelock mode: a surface owned by the op Safe sets pendingOwner=PT,
    ///         then PT (proposer = op Safe) schedules acceptOwnership, waits the delay, and executes it.
    function test_transferOwnership_accept_via_timelock() public {
        MockTwoStepOwnable target = new MockTwoStepOwnable(opSafe);

        // Phase 1: op Safe sets pendingOwner = PT (the queued transferOwnership in migration mode).
        vm.prank(opSafe);
        target.transferOwnership(address(pt));
        assertEq(target.pendingOwner(), address(pt));

        // Phase 2: schedule acceptOwnership batch via PT (proposer = op Safe).
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = _acceptBatch(address(target));
        bytes32 salt = keccak256("TransferOwnership-test");
        vm.prank(opSafe);
        pt.scheduleBatch(targets, values, payloads, bytes32(0), salt, PROTOCOL_DELAY);

        // Cannot execute before the delay elapses.
        vm.prank(opSafe);
        vm.expectRevert();
        pt.executeBatch(targets, values, payloads, bytes32(0), salt);

        // Phase 3: warp past the delay, then execute → PT becomes owner.
        vm.warp(block.timestamp + PROTOCOL_DELAY + 1);
        vm.prank(opSafe);
        pt.executeBatch(targets, values, payloads, bytes32(0), salt);

        assertEq(target.owner(), address(pt), "PT must own the surface after accept");
        assertEq(target.pendingOwner(), address(0));
    }

    // ─── Admin-tier recovery (revoke a compromised partner canceller) ───

    function test_recovery_admin_revokes_partner_canceller() public {
        bytes memory data = abi.encodeWithSignature("revokeRole(bytes32,address)", CANCELLER_ROLE, partner);
        bytes32 salt = keccak256("recovery-test");

        // adminSafe schedules on AT; AT (admin of PT) will revoke the partner's canceller role.
        vm.prank(adminSafe);
        at.schedule(address(pt), 0, data, bytes32(0), salt, ADMIN_DELAY);

        // Too slow before the admin delay.
        vm.prank(adminSafe);
        vm.expectRevert();
        at.execute(address(pt), 0, data, bytes32(0), salt);

        vm.warp(block.timestamp + ADMIN_DELAY + 1);
        vm.prank(adminSafe);
        at.execute(address(pt), 0, data, bytes32(0), salt);

        assertFalse(pt.hasRole(CANCELLER_ROLE, partner), "partner canceller must be revoked via AT");
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    function _acceptBatch(address target)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        targets = new address[](1);
        values = new uint256[](1);
        payloads = new bytes[](1);
        targets[0] = target;
        values[0] = 0;
        payloads[0] = abi.encodeWithSignature("acceptOwnership()");
    }

    function _one(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }
}
