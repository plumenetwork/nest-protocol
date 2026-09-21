// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/src/base/Roles/TellerWithMultiAssetSupport.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMorpho, Id, MarketParams, Market, Position as MorphoPosition} from "@morpho/interfaces/IMorpho.sol";
import {MarketParamsLib} from "@morpho/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "@morpho/libraries/SharesMathLib.sol";
import {IOracle} from "@morpho/interfaces/IOracle.sol";
import {Statement, Attestation} from "@predicate-v2/interfaces/IPredicateRegistry.sol";
import {ComplianceProxy} from "contracts/compliance/ComplianceProxy.sol";
import {PredicateV2Hook} from "contracts/compliance/hooks/PredicateV2Hook.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {NestAdapter} from "contracts/integrations/morpho/NestAdapter.sol";
import {NestBundler} from "contracts/integrations/morpho/NestBundler.sol";
import {NestUnlooper} from "contracts/integrations/morpho/NestUnlooper.sol";
import {Call, IBundler3} from "contracts/vendor/bundler3/interfaces/IBundler3.sol";
import {UserIntent, PositionMode, Position, RouteInput} from "contracts/integrations/morpho/types/BundleTypes.sol";

/// @dev Additional public methods of the deployed Predicate V2 registry. No registry mock.
interface IForkPredicateRegistry {
    function owner() external view returns (address);
    function registerAttester(address attester) external;
    function deregisterAttester(address attester) external;
    function hashStatementWithExpiry(Statement calldata statement) external view returns (bytes32);
    function usedStatementUUIDs(string calldata uuid) external view returns (bool);
}

/// @dev A fixed-price oracle only for the fork-created market, quoted from the real nTEST vault.
contract ForkNtestOracle is IOracle {
    uint256 public immutable price;

    constructor(uint256 price_) {
        price = price_;
    }
}

/// @notice Runs real Morpho/Bundler3 and deployed nTEST vault/proxy/hook/registry on a Plume fork.
/// @dev Only test adapters, a market/oracle, balances and role grants are created locally.
///      Local signatures test on-chain validation, not Predicate's off-chain policy engine.
contract MorphoPredicateV2ForkTest is Test {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    uint256 internal constant FORK_BLOCK = 92_177_336;
    uint256 internal constant UNIT = 1e6;
    uint256 internal constant ATTESTER_KEY = 0xA77E57;
    uint8 internal constant ADAPTER_ROLE = 16;
    uint8 internal constant FORK_VAULT_ROLE = 250;
    uint8 internal constant KEEPER_ROLE = 14;

    address internal user = makeAddr("morpho-v2-user");
    address internal keeper = makeAddr("morpho-v2-keeper");
    IMorpho internal morpho;
    INestVaultCore internal vault;
    IERC20 internal loan;
    IERC20 internal share;
    ComplianceProxy internal proxy;
    PredicateV2Hook internal hook;
    IForkPredicateRegistry internal registry;
    RolesAuthority internal authority;
    NestAdapter internal adapter;
    NestBundler internal bundler;
    NestUnlooper internal unlooper;
    MarketParams internal marketParams;

    function setUp() public {
        vm.createSelectFork(
            vm.envOr("PLUME_RPC_URL", string("https://rpc.plume.org")), vm.envOr("MORPHO_V2_FORK_BLOCK", FORK_BLOCK)
        );
        assertEq(block.chainid, 98866, "requires a Plume fork");
        string memory config = vm.readFile("script/deployment-config/compliance/98866-nTEST.json");
        proxy = ComplianceProxy(vm.parseJsonAddress(config, ".complianceProxy"));
        hook = PredicateV2Hook(vm.parseJsonAddress(config, ".predicateV2Hook"));
        config = vm.readFile("config/compliance/98866.json");
        registry = IForkPredicateRegistry(vm.parseJsonAddress(config, ".v2.predicateRegistry"));
        assertEq(address(proxy.complianceHook()), address(hook), "nTEST V2 hook is not active");
        assertEq(hook.getRegistry(), address(registry), "registry differs from config");
        // Fork-only governance action: enables deterministic real ECDSA attestations without API keys.
        vm.prank(registry.owner());
        registry.registerAttester(vm.addr(ATTESTER_KEY));

        config = vm.readFile("script/deployment-config/vaults/nTEST.json");
        assertEq(
            hook.getPolicyID(),
            vm.parseJsonString(config, ".compliance.v2.verificationHash"),
            "policy differs from config"
        );
        assertEq(vm.parseJsonString(config, ".contracts.vaults[0].assetSymbol"), "USDC", "expected nTEST USDC vault");
        vault = INestVaultCore(vm.parseJsonAddress(config, ".contracts.vaults[0].address"));
        loan = IERC20(vault.asset());
        share = IERC20(vault.share());
        assertEq(address(share), vm.parseJsonAddress(config, ".contracts.share"));
        authority = RolesAuthority(address(Auth(address(vault)).authority()));
        assertEq(address(proxy.authority()), address(authority), "unexpected proxy authority");

        config = vm.readFile("config/morpho/98866.json");
        morpho = IMorpho(vm.parseJsonAddress(config, ".morpho"));
        address bundler3 = vm.parseJsonAddress(config, ".bundler3");
        address atomicSolver = vm.parseJsonAddress(config, ".atomicSolver");
        address atomicQueue = vm.parseJsonAddress(config, ".atomicQueue");
        adapter = new NestAdapter(bundler3, address(morpho), vm.parseJsonAddress(config, ".wrappedNative"));
        bundler = new NestBundler(
            address(morpho),
            bundler3,
            address(adapter),
            address(proxy),
            vm.parseJsonAddress(config, ".legacyPredicateProxy"),
            atomicSolver,
            atomicQueue
        );
        RolesAuthority keeperAuthority = new RolesAuthority(address(this), Authority(address(0)));
        unlooper = new NestUnlooper(
            address(this),
            Authority(address(keeperAuthority)),
            address(morpho),
            bundler3,
            address(adapter),
            atomicSolver,
            atomicQueue
        );
        keeperAuthority.setRoleCapability(KEEPER_ROLE, address(unlooper), NestUnlooper.execute.selector, true);
        keeperAuthority.setUserRole(keeper, KEEPER_ROLE, true);
        unlooper.setVaultApproval(address(vault), true);
        _wireForkRoles();

        // The market exists only in the fork. Zero IRM gives deterministic debt within each test.
        marketParams = MarketParams({
            loanToken: address(loan),
            collateralToken: address(share),
            oracle: address(new ForkNtestOracle(vault.convertToAssets(UNIT) * 1e36 / UNIT)),
            irm: address(0),
            lltv: 860_000_000_000_000_000
        });
        morpho.createMarket(marketParams);
        deal(address(loan), address(this), 10_000 * UNIT);
        loan.approve(address(morpho), type(uint256).max);
        morpho.supply(marketParams, 10_000 * UNIT, 0, address(this), "");
        deal(address(loan), user, 500 * UNIT);

        vm.startPrank(user);
        loan.approve(address(bundler), type(uint256).max);
        loan.approve(address(adapter), type(uint256).max);
        share.approve(address(adapter), type(uint256).max);
        share.approve(address(bundler), type(uint256).max);
        vault.setOperator(address(adapter), true);
        vault.setOperator(address(bundler), true);
        vault.setOperator(address(unlooper), true);
        morpho.setAuthorization(address(adapter), true);
        morpho.setAuthorization(address(bundler), true);
        morpho.setAuthorization(address(unlooper), true);
        vm.stopPrank();
    }

    function test_loop_wrapper_acceptsV2OnBehalfProof() public {
        bytes memory proof = _proof("loop", address(bundler), _onBehalfPayload(user));
        vm.prank(user);
        // Modern routes never call the teller; the builder still requires a nonzero placeholder.
        bundler.getBundleAndExecute(_intent(50 * UNIT, 100 * UNIT), _route(false), proof, vault, address(vault));
        _assertPosition(50 * UNIT, 100 * UNIT);
        assertTrue(registry.usedStatementUUIDs("loop"), "real registry must consume the proof");
        _assertNoDust();
    }

    function test_unloop_wrapper_instant_closesPositionWithFreshV2Proof() public {
        _openPosition();
        bytes memory proof = _proof("instant-exit", address(bundler), _onBehalfPayload(user));
        _executeWrapper(0, 0, true, proof);
        _assertPosition(0, 0);
        assertGt(share.balanceOf(user), 0, "remaining collateral must return to the user");
        assertTrue(registry.usedStatementUUIDs("instant-exit"));
        _assertNoDust();
    }

    function test_unloop_wrapper_requestAndRedeem_closesPositionWithFreshV2Proof() public {
        _openPosition();
        _executeWrapper(0, 0, false, _proof("async-exit", address(bundler), _onBehalfPayload(user)));
        _assertPosition(0, 0);
        assertTrue(registry.usedStatementUUIDs("async-exit"));
        assertGt(share.balanceOf(user), 0, "remaining collateral must return to the user");
        assertEq(vault.pendingRedeemRequest(0, user), 0);
        assertEq(vault.claimableRedeemRequest(0, user), 0);
        _assertNoDust();
    }

    function test_unlooper_keeper_closesPositionWithoutCompliance() public {
        _openPosition();
        _requestUnloop();
        // Remove the adapter's compliance permission and the test attester. The keeper exit must
        // still work: it deliberately uses the non-compliance route, not an empty/fake V2 proof.
        vm.prank(authority.owner());
        authority.setUserRole(address(adapter), ADAPTER_ROLE, false);
        vm.prank(registry.owner());
        registry.deregisterAttester(vm.addr(ATTESTER_KEY));
        vm.recordLogs();
        vm.prank(keeper);
        unlooper.execute(marketParams, vault, TellerWithMultiAssetSupport(address(vault)), user, false);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].emitter != address(registry), "keeper exit must not consume an attestation");
        }
        _assertPosition(0, 0);
        assertEq(unlooper.getUnloopRequest(user, marketParams).deadline, 0, "successful request must clear");
        assertEq(vault.pendingRedeemRequest(0, user), 0);
        assertEq(vault.claimableRedeemRequest(0, user), 0);
        assertGt(share.balanceOf(user), 0);
        _assertNoDust();
    }

    function test_loop_directBundler3_acceptsUserAccessProof() public {
        // Direct Bundler3 execution binds the statement to the user, unlike the wrapper's
        // from=NestBundler / accessCheck(bytes32 user) pair.
        bytes memory proof = _proof("direct-loop", user, abi.encodeWithSignature("accessCheck(address)", user));
        (Call[] memory calls,) = bundler.getBundleCalls(
            _intent(50 * UNIT, 100 * UNIT), _route(false), proof, vault, address(vault), user, user
        );
        IBundler3 bundler3 = bundler.BUNDLER3();
        vm.prank(user);
        bundler3.multicall(calls);
        _assertPosition(50 * UNIT, 100 * UNIT);
        assertTrue(registry.usedStatementUUIDs("direct-loop"));
        _assertNoDust();
    }

    function test_loop_rejectsProofForWrongInitiator() public {
        bytes memory proof = _proof("wrong-sender", user, _onBehalfPayload(user));
        vm.expectRevert("Predicate.validateAttestation: Invalid signature");
        _executeWrapper(50 * UNIT, 100 * UNIT, false, proof);
        _assertRejectedLoop("wrong-sender");
    }

    function test_loop_rejectsProofForWrongRepresentedUser() public {
        bytes memory proof = _proof("wrong-user", address(bundler), _onBehalfPayload(keeper));
        vm.expectRevert("Predicate.validateAttestation: Invalid signature");
        _executeWrapper(50 * UNIT, 100 * UNIT, false, proof);
        _assertRejectedLoop("wrong-user");
    }

    function test_loop_rejectsDepositProofInsteadOfAccessCheck() public {
        bytes memory proof = _proof(
            "wrong-action",
            address(bundler),
            abi.encodeWithSignature("deposit(bytes32)", bytes32(uint256(uint160(user))))
        );
        vm.expectRevert("Predicate.validateAttestation: Invalid signature");
        _executeWrapper(50 * UNIT, 100 * UNIT, false, proof);
        _assertRejectedLoop("wrong-action");
    }

    function test_loop_rejectsExpiredProof() public {
        Attestation memory attestation =
            abi.decode(_proof("expired", address(bundler), _onBehalfPayload(user)), (Attestation));
        attestation.expiration = block.timestamp - 1;
        vm.expectRevert("Predicate.validateAttestation: attestation expired");
        _executeWrapper(50 * UNIT, 100 * UNIT, false, abi.encode(attestation));
        _assertRejectedLoop("expired");
    }

    function test_loop_rejectsUnregisteredAttester() public {
        bytes memory proof = _proof("unregistered", address(bundler), _onBehalfPayload(user));
        vm.prank(registry.owner());
        registry.deregisterAttester(vm.addr(ATTESTER_KEY));
        vm.expectRevert("Predicate.validateAttestation: Attester is not a registered attester");
        _executeWrapper(50 * UNIT, 100 * UNIT, false, proof);
        _assertRejectedLoop("unregistered");
    }

    function test_loop_rejectsMissingAdapterComplianceRole() public {
        bytes memory proof = _proof("no-role", address(bundler), _onBehalfPayload(user));
        vm.prank(authority.owner());
        authority.setUserRole(address(adapter), ADAPTER_ROLE, false);
        vm.expectRevert(bytes4(keccak256("AUTH_UNAUTHORIZED()")));
        _executeWrapper(50 * UNIT, 100 * UNIT, false, proof);
        _assertRejectedLoop("no-role");
    }

    function test_loop_rejectsReplayedProofWithoutChangingPosition() public {
        _openPosition();
        uint256 balanceBefore = loan.balanceOf(user);
        bytes memory proof = _proof("open", address(bundler), _onBehalfPayload(user));
        vm.expectRevert("Predicate.validateAttestation: statement UUID already used");
        _executeWrapper(60 * UNIT, 120 * UNIT, false, proof);
        _assertPosition(50 * UNIT, 100 * UNIT);
        assertEq(loan.balanceOf(user), balanceBefore);
        _assertNoDust();
    }

    function test_unloop_instant_rejectsWrongUserProofAndRollsBack() public {
        _assertRejectedUnloop(true);
    }

    function test_unloop_requestAndRedeem_rejectsWrongUserProofAndRollsBack() public {
        _assertRejectedUnloop(false);
    }

    function test_unlooper_rejectsUnauthorizedKeeper() public {
        _openPosition();
        _requestUnloop();
        uint64 deadline = unlooper.getUnloopRequest(user, marketParams).deadline;
        vm.prank(user);
        vm.expectRevert("UNAUTHORIZED");
        unlooper.execute(marketParams, vault, TellerWithMultiAssetSupport(address(vault)), user, false);
        _assertPosition(50 * UNIT, 100 * UNIT);
        assertEq(unlooper.getUnloopRequest(user, marketParams).deadline, deadline);
        _assertNoDust();
    }

    function test_unlooper_requiresUserRequestEvenForAuthorizedKeeper() public {
        _openPosition();
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSignature("UnloopRequestNotSet(address,bytes32)", user, Id.unwrap(marketParams.id()))
        );
        unlooper.execute(marketParams, vault, TellerWithMultiAssetSupport(address(vault)), user, false);
        _assertPosition(50 * UNIT, 100 * UNIT);
    }

    function _assertRejectedLoop(string memory uuid) internal view {
        _assertPosition(0, 0);
        assertEq(loan.balanceOf(user), 500 * UNIT, "rejected loop must return all funds");
        assertEq(share.balanceOf(user), 0);
        assertFalse(registry.usedStatementUUIDs(uuid), "rejected proof must not be consumed");
        _assertNoDust();
    }

    function _assertRejectedUnloop(bool instant) internal {
        _openPosition();
        uint256 balanceBefore = loan.balanceOf(user);
        bytes memory proof = _proof("denied-exit", address(bundler), _onBehalfPayload(keeper));
        vm.expectRevert("Predicate.validateAttestation: Invalid signature");
        _executeWrapper(0, 0, instant, proof);
        _assertPosition(50 * UNIT, 100 * UNIT);
        assertEq(loan.balanceOf(user), balanceBefore);
        assertEq(share.balanceOf(user), 0);
        assertEq(vault.pendingRedeemRequest(0, user), 0);
        assertEq(vault.claimableRedeemRequest(0, user), 0);
        assertFalse(registry.usedStatementUUIDs("denied-exit"));
        _assertNoDust();
    }

    function _requestUnloop() internal {
        vm.prank(user);
        unlooper.updateUnloopRequest(marketParams, 0, 0, uint64(block.timestamp + 1 hours));
    }

    function _openPosition() internal {
        _executeWrapper(50 * UNIT, 100 * UNIT, false, _proof("open", address(bundler), _onBehalfPayload(user)));
        _assertPosition(50 * UNIT, 100 * UNIT);
    }

    function _executeWrapper(uint256 debt, uint256 collateral, bool instant, bytes memory proof) internal {
        UserIntent memory intent = _intent(debt, collateral);
        vm.prank(user);
        bundler.getBundleAndExecute(intent, _route(instant), proof, vault, address(vault));
    }

    function _wireForkRoles() internal {
        vm.startPrank(authority.owner());
        // Match the configured adapter role for restricted genericUserCheck, without bypassing the hook.
        authority.setUserRole(address(adapter), ADAPTER_ROLE, true);
        // nTEST has no deployed Morpho adapters. Grant the fork-only contracts vault execution permissions.
        bytes4[7] memory selectors = [
            vault.deposit.selector,
            vault.mint.selector,
            vault.instantRedeem.selector,
            vault.requestRedeem.selector,
            vault.fulfillRedeem.selector,
            vault.withdraw.selector,
            vault.redeem.selector
        ];
        for (uint256 i; i < selectors.length; ++i) {
            authority.setRoleCapability(FORK_VAULT_ROLE, address(vault), selectors[i], true);
        }
        authority.setUserRole(address(adapter), FORK_VAULT_ROLE, true);
        authority.setUserRole(address(bundler), FORK_VAULT_ROLE, true);
        authority.setUserRole(address(unlooper), FORK_VAULT_ROLE, true);
        vm.stopPrank();
    }

    function _proof(string memory uuid, address sender, bytes memory payload) internal view returns (bytes memory) {
        Attestation memory attestation = Attestation(uuid, block.timestamp + 1 hours, vm.addr(ATTESTER_KEY), "");
        Statement memory statement = Statement({
            uuid: uuid,
            msgSender: sender,
            target: address(hook),
            msgValue: 0,
            encodedSigAndArgs: payload,
            policy: hook.getPolicyID(),
            expiration: attestation.expiration
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTER_KEY, registry.hashStatementWithExpiry(statement));
        attestation.signature = abi.encodePacked(r, s, v);
        return abi.encode(attestation);
    }

    function _onBehalfPayload(address owner) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("accessCheck(bytes32)", bytes32(uint256(uint160(owner))));
    }

    function _intent(uint256 debt, uint256 collateral) internal view returns (UserIntent memory intent) {
        intent.market = marketParams;
        intent.assetAllowance = type(uint256).max;
        intent.shareAllowance = 0;
        intent.maxSharePriceE27 = type(uint256).max;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
        intent.target = Position(debt, collateral);
    }

    function _route(bool instant) internal pure returns (RouteInput memory route) {
        route.instantRedeem = instant;
        route.compliantRedemption = true;
    }

    function _assertPosition(uint256 debt, uint256 collateral) internal view {
        MorphoPosition memory position = morpho.position(marketParams.id(), user);
        Market memory market = morpho.market(marketParams.id());
        assertApproxEqAbs(
            uint256(position.borrowShares).toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares), debt, 1
        );
        assertEq(position.collateral, collateral);
    }

    function _assertNoDust() internal view {
        assertEq(loan.balanceOf(address(adapter)), 0, "adapter USDC dust");
        assertEq(share.balanceOf(address(adapter)), 0, "adapter share dust");
        assertEq(loan.balanceOf(address(bundler)), 0, "wrapper USDC dust");
        assertEq(share.balanceOf(address(bundler)), 0, "wrapper share dust");
    }
}
