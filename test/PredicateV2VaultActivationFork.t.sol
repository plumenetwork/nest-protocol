// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {NestVault} from "contracts/NestVault.sol";
import {ComplianceProxy} from "contracts/compliance/ComplianceProxy.sol";
import {PredicateV2Hook} from "contracts/compliance/hooks/PredicateV2Hook.sol";
import {Statement, Attestation} from "@predicate-v2/interfaces/IPredicateRegistry.sol";

interface IActivationSafe {
    function getOwners() external view returns (address[] memory);
    function getTransactionHash(
        address,
        uint256,
        bytes calldata,
        uint8,
        uint256,
        uint256,
        uint256,
        address,
        address,
        uint256
    ) external view returns (bytes32);
    function execTransaction(
        address,
        uint256,
        bytes calldata,
        uint8,
        uint256,
        uint256,
        uint256,
        address,
        address,
        bytes calldata
    ) external payable returns (bool);
}

interface IActivationRegistry {
    function owner() external view returns (address);
    function registerAttester(address) external;
    function hashStatementWithExpiry(Statement calldata) external view returns (bytes32);
    function usedStatementUUIDs(string calldata) external view returns (bool);
}

/// Runs the exact JSON Safe scheduling transaction and delayed execution on each live-chain fork.
/// Only Safe signature/nonce storage, test balances, time, and a fork-only Registry attester are changed.
/// Production vault/proxy/hook/registry code and vault permissions are never mocked or replaced.
contract PredicateV2VaultActivationForkTest is Test {
    string constant BASE = "generated/predicate-v2-nwisdom-ntbill-2026-09-10/";
    address constant SAFE = 0xa08A0Dc480BD60d1d56C8Eec6c722125eAfEa982;
    address constant TIMELOCK = 0x8fAACdC65de5D78975dF4f9DC4B6548979cEb23A;
    address constant PROXY = 0xB65B65CfF0CA1f3cc12fe58a13110E43DfA999F1;
    address constant HOOK = 0xAc002355Fe37C73e9E53BE8296D4A75eeCC257ef;
    uint256 constant ATTESTER_KEY = 0xA77E57;
    bytes4 constant DEPOSIT = bytes4(keccak256("deposit(uint256,address)"));
    bytes4 constant MINT = bytes4(keccak256("mint(uint256,address)"));
    bytes4 constant REQUEST = bytes4(keccak256("requestRedeem(uint256,address,address)"));
    bytes4 constant INSTANT = bytes4(keccak256("instantRedeem(uint256,address,address)"));
    ComplianceProxy proxy = ComplianceProxy(PROXY);
    PredicateV2Hook hook = PredicateV2Hook(HOOK);
    IActivationRegistry registry;
    string dir;
    string manifest;
    address user;
    uint256 uuidIndex;

    function setUp() public {
        if (!vm.envExists("ROLLOUT_CHAIN_ID")) {
            vm.skip(true);
            return;
        }
        uint256 chain = vm.envUint("ROLLOUT_CHAIN_ID");
        dir = string.concat(BASE, vm.toString(chain), "/");
        manifest = vm.readFile(string.concat(dir, "manifest.json"));
        string memory common = vm.readFile(string.concat("config/common/", vm.toString(chain), ".json"));
        string memory rpcVar = vm.parseJsonString(common, ".rpc");
        if (chain == 56 && !vm.envExists(rpcVar)) rpcVar = "BNB_RPC_URL";
        vm.createSelectFork(vm.envString(rpcVar), vm.parseJsonUint(manifest, ".block"));
        assertEq(block.chainid, chain);
        registry = IActivationRegistry(vm.parseJsonAddress(manifest, ".registry"));
        user = makeAddr("predicate-v2-activation-user");
    }

    function _safeExec(string memory file, bytes32 expectedHash) internal {
        string memory j = vm.readFile(string.concat(dir, file));
        address target = vm.parseJsonAddress(j, ".to");
        bytes memory data = vm.parseJsonBytes(j, ".data");
        uint8 operation = uint8(vm.parseJsonUint(j, ".operation"));
        uint256 nonce = vm.parseJsonUint(j, ".nonce");
        assertEq(vm.parseJsonString(j, ".value"), "0");
        assertEq(vm.parseJsonString(j, ".safeTxGas"), "0");
        assertEq(vm.parseJsonString(j, ".baseGas"), "0");
        assertEq(vm.parseJsonString(j, ".gasPrice"), "0");
        assertEq(vm.parseJsonAddress(j, ".gasToken"), address(0));
        assertEq(vm.parseJsonAddress(j, ".refundReceiver"), address(0));
        IActivationSafe safe = IActivationSafe(SAFE);
        assertEq(
            safe.getTransactionHash(target, 0, data, operation, 0, 0, 0, address(0), address(0), nonce), expectedHash
        );
        address owner = safe.getOwners()[0];
        vm.store(SAFE, bytes32(uint256(4)), bytes32(uint256(1)));
        vm.store(SAFE, bytes32(uint256(5)), bytes32(nonce));
        vm.prank(owner);
        assertTrue(
            safe.execTransaction(
                target,
                0,
                data,
                operation,
                0,
                0,
                0,
                address(0),
                address(0),
                abi.encodePacked(bytes32(uint256(uint160(owner))), bytes32(0), uint8(1))
            )
        );
    }

    function _call(address caller, address target, bytes memory data) internal {
        vm.prank(caller);
        (bool ok, bytes memory result) = target.call(data);
        if (!ok) assembly { revert(add(result, 32), mload(result)) }
    }

    function _routeKey(uint256 i) internal pure returns (string memory) {
        return string.concat(".routes[", vm.toString(i), "]");
    }

    function _snapshot() internal view returns (bytes32) {
        bytes memory state;
        uint256 n = vm.parseJsonUint(manifest, ".routeCount");
        for (uint256 i; i < n; ++i) {
            string memory key = _routeKey(i);
            address vault = vm.parseJsonAddress(manifest, string.concat(key, ".address"));
            RolesAuthority a = RolesAuthority(vm.parseJsonAddress(manifest, string.concat(key, ".authority")));
            address composer = vm.parseJsonAddress(manifest, string.concat(key, ".composer"));
            state = abi.encode(
                state,
                a.owner(),
                a.getUserRoles(composer),
                a.getUserRoles(0xfC0c4222B3A0c9B060C0B959DEc62442036b9035),
                a.isCapabilityPublic(vault, REQUEST),
                a.isCapabilityPublic(vault, INSTANT),
                a.getRolesWithCapability(vault, REQUEST),
                a.getRolesWithCapability(vault, INSTANT),
                a.getRolesWithCapability(vault, DEPOSIT),
                a.getRolesWithCapability(vault, MINT)
            );
        }
        return keccak256(state);
    }

    function _assertGrants(bool enabled) internal view {
        uint256 n = vm.parseJsonUint(manifest, ".routeCount");
        for (uint256 i; i < n; ++i) {
            string memory key = _routeKey(i);
            address vault = vm.parseJsonAddress(manifest, string.concat(key, ".address"));
            RolesAuthority a = RolesAuthority(vm.parseJsonAddress(manifest, string.concat(key, ".authority")));
            assertEq(a.getUserRoles(PROXY), enabled ? bytes32(uint256(1 << 7)) : bytes32(0));
            assertEq(a.canCall(PROXY, vault, DEPOSIT), enabled);
            assertEq(a.canCall(PROXY, vault, MINT), enabled);
            assertFalse(a.doesRoleHaveCapability(7, vault, REQUEST));
            assertFalse(a.doesRoleHaveCapability(7, vault, INSTANT));
            assertTrue(a.isCapabilityPublic(vault, REQUEST));
            assertTrue(a.isCapabilityPublic(vault, INSTANT));
            assertTrue(a.canCall(0xfC0c4222B3A0c9B060C0B959DEc62442036b9035, vault, DEPOSIT));
        }
    }

    function _activate() internal {
        _assertGrants(false);
        // Replay the existing reviewed prerequisite only when still pending at the pinned fork block.
        if (proxy.owner() != SAFE) {
            _safeExec("prerequisite-safe-transaction.json", vm.parseJsonBytes32(manifest, ".prerequisiteHash"));
        }
        assertEq(proxy.owner(), SAFE);
        assertEq(address(proxy.complianceHook()), HOOK);
        assertEq(hook.getRegistry(), address(registry));
        assertEq(hook.getPolicyID(), vm.parseJsonString(manifest, ".policy"));
        bytes32 beforeState = _snapshot();
        string memory batch = vm.readFile(string.concat(dir, "safe-batch.json"));
        bytes memory schedule = vm.parseJsonBytes(batch, ".transactions[0].data");
        vm.prank(user);
        (bool unauthorized,) = TIMELOCK.call(schedule);
        assertFalse(unauthorized, "Unauthorized scheduling succeeded");
        string memory identity = vm.readFile(string.concat(dir, "identity.json"));
        _safeExec("safe-transaction.json", vm.parseJsonBytes32(identity, ".safeTxHash"));
        _assertGrants(false);
        batch = vm.readFile(string.concat(dir, "execute-batch.json"));
        bytes memory execute = vm.parseJsonBytes(batch, ".transactions[0].data");
        vm.prank(user);
        (bool early,) = TIMELOCK.call(execute);
        assertFalse(early, "Timelock delay bypassed");
        vm.warp(block.timestamp + 172800);
        _call(user, TIMELOCK, execute);
        _assertGrants(true);
        assertEq(_snapshot(), beforeState, "Existing roles, redemptions or capabilities changed");
        vm.prank(user);
        (bool duplicate,) = TIMELOCK.call(execute);
        assertFalse(duplicate, "Operation executed twice");
    }

    function _proof(address sender, bytes memory payload) internal returns (bytes memory) {
        string memory uuid = string.concat("activation-", vm.toString(++uuidIndex));
        Attestation memory attestation = Attestation(uuid, block.timestamp + 1 hours, vm.addr(ATTESTER_KEY), "");
        Statement memory statement =
            Statement(uuid, sender, HOOK, 0, payload, hook.getPolicyID(), attestation.expiration);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTER_KEY, registry.hashStatementWithExpiry(statement));
        attestation.signature = abi.encodePacked(r, s, v);
        return abi.encode(attestation);
    }

    function test_exactSafeBatchTimelockAndAllVaultDepositFlows() public {
        _activate();
        vm.prank(registry.owner());
        registry.registerAttester(vm.addr(ATTESTER_KEY));
        uint256 n = vm.parseJsonUint(manifest, ".routeCount");
        for (uint256 i; i < n; ++i) {
            _testVault(i);
        }
    }

    function _testVault(uint256 i) internal {
        string memory key = _routeKey(i);
        NestVault vault = NestVault(vm.parseJsonAddress(manifest, string.concat(key, ".address")));
        ERC20 asset = ERC20(vm.parseJsonAddress(manifest, string.concat(key, ".asset")));
        ERC20 share = ERC20(vm.parseJsonAddress(manifest, string.concat(key, ".share")));
        uint256 amount = 10 ** asset.decimals(); // One asset unit, existing live fees/caps/rates.
        deal(address(asset), user, amount * 10);
        vm.prank(user);
        asset.approve(PROXY, type(uint256).max);
        bytes memory payload = abi.encodeWithSignature("deposit()");
        bytes memory proof = _proof(user, payload);
        uint256 beforeShares = share.balanceOf(user);
        uint256 beforeAssets = asset.balanceOf(user);
        vm.prank(user);
        uint256 minted = proxy.deposit(asset, amount, user, vault, proof);
        assertGt(minted, 0);
        assertEq(share.balanceOf(user), beforeShares + minted);
        assertEq(asset.balanceOf(user), beforeAssets - amount);
        assertEq(asset.allowance(PROXY, address(vault)), 0);
        // Real registry enforces replay and binds the caller and on-behalf identity.
        vm.expectRevert();
        vm.prank(user);
        proxy.deposit(asset, amount, user, vault, proof);
        bytes memory wrongSender = _proof(makeAddr("wrong-sender"), payload);
        vm.expectRevert();
        vm.prank(user);
        proxy.deposit(asset, amount, user, vault, wrongSender);
        bytes memory mintProof = _proof(user, payload);
        uint256 mintShares = vault.previewDeposit(amount);
        vm.prank(user);
        assertGe(proxy.mint(asset, mintShares, user, vault, mintProof), mintShares);
        bytes32[2] memory identities = [bytes32(uint256(uint160(user))), keccak256("32-byte-Solana-public-key")];
        for (uint256 j; j < identities.length; ++j) {
            bytes memory behalfProof = _proof(user, abi.encodeWithSignature("deposit(bytes32)", identities[j]));
            vm.expectRevert();
            vm.prank(user);
            proxy.depositOnBehalf(vault, asset, amount, user, bytes32(uint256(42)), behalfProof);
            vm.prank(user);
            assertGt(proxy.depositOnBehalf(vault, asset, amount, user, identities[j], behalfProof), 0);
        }
        // No Predicate proof or proxy is required for a direct vault redemption request.
        uint256 pendingBefore = vault.pendingRedeemRequest(0, user);
        vm.prank(user);
        share.approve(address(vault), minted);
        vm.prank(user);
        vault.requestRedeem(minted, user, user);
        assertEq(vault.pendingRedeemRequest(0, user), pendingBefore + minted);
        emit log_named_address("Verified deposit/mint, EVM/Solana identity, direct redemption", address(vault));
    }
}
