// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {ConfigReader, VaultDeployConfig} from "script/lib/ConfigReader.sol";
import {SerializedTx, SafeTxUtil} from "script/lib/SafeBatchSerialize.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {ComplianceProxy} from "contracts/compliance/ComplianceProxy.sol";
import {Auth} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console} from "forge-std/console.sol";

interface IAuthUpgradeable {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function acceptOwnership() external;
}

interface IOwnable {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

/// @title  TransferOwnership
/// @notice Transfers ownership of vault and/or common contracts to a new owner (e.g. multisig).
/// @dev    Controlled by env var SCOPE: "all" (default), "vault", or "common".
///
///         Vault-specific contracts: share, accountant, vaults, composers, and vault authority.
///         Common contracts: predicateProxy, operatorRegistry, redeemOperator,
///         cctpRelayer, seizer, blacklistHook, commonRolesAuthority, ComplianceProxy and its hook.
///
///         Two phases:
///         Phase 1 (deployer broadcast): calls transferOwnership + migrates roles.
///           - AuthUpgradeable contracts: two-step (sets pendingOwner)
///           - RolesAuthority / Solmate Auth: one-step (immediate)
///           - ProxyAdmin (OZ Ownable): one-step (immediate)
///         Phase 2 (msig batch): generates Safe batch with acceptOwnership() calls for
///           AuthUpgradeable contracts only, to be executed by the new owner.
///
///         Usage:
///           VAULT_SYMBOL=nFALCON NEW_OWNER=0x... forge script script/setup/TransferOwnership.s.sol \
///             --sig "run()" --rpc-url $RPC --broadcast
///           # Optional: SCOPE=vault or SCOPE=common (defaults to "all")
///           # Optional: ALLOW_AUTHORITY_MISMATCH=true (staged RolesAuthority replacement)
contract TransferOwnership is BaseConfigScript {
    using Strings for uint256;

    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    uint8 internal constant ROLE_COUNT = 17;

    address internal newOwner;
    bool internal includeVault;
    bool internal includeCommon;
    /// @notice True when NEW_OWNER is an OZ TimelockController (the protocol timelock). Routes ownership
    ///         through schedule/execute batches instead of a direct Safe acceptOwnership.
    bool internal newOwnerIsTimelock;

    function setUp() public {
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");
        loadConfigs(vaultSymbol);

        // Override vaultConfig with output (deployed addresses)
        uint256 chainId = vaultConfig.deployChainId;
        vaultConfig = ConfigReader.readOutputConfig(chainId, vaultSymbol);

        newOwner = vm.envAddress("NEW_OWNER");
        require(newOwner != address(0), "TransferOwnership: NEW_OWNER is zero");

        // Parse scope: "all" (default), "vault", or "common"
        string memory scope = vm.envOr("SCOPE", string("all"));
        bytes32 scopeHash = keccak256(bytes(scope));
        if (scopeHash == keccak256("all")) {
            includeVault = true;
            includeCommon = true;
        } else if (scopeHash == keccak256("vault")) {
            includeVault = true;
        } else if (scopeHash == keccak256("common")) {
            includeCommon = true;
        } else {
            revert("TransferOwnership: invalid SCOPE (use all, vault, or common)");
        }

        // Common output can predate V2 activation. Use the canonical active stack at final handoff.
        if (includeCommon && chainComplianceConfig.v2Only) {
            vaultConfig.common = ConfigReader.readCommonProxyConfig(chainId);
        }

        // Detect whether NEW_OWNER is an OZ TimelockController (protocol timelock); override via env.
        try vm.envBool("NEW_OWNER_IS_TIMELOCK") returns (bool v) {
            newOwnerIsTimelock = v;
        } catch {
            newOwnerIsTimelock = _isTimelock(newOwner);
        }
    }

    /// @dev True when `a` is a deployed OZ TimelockController (responds to getMinDelay()).
    function _isTimelock(address a) internal view returns (bool) {
        if (a.code.length == 0) return false;
        try TimelockController(payable(a)).getMinDelay() returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    /// @dev True when `target` is a two-step AuthUpgradeable (exposes pendingOwner()). One-step Solmate
    ///      Auth cores (e.g. the BoringVault share) revert here and must transfer ownership immediately.
    function _isTwoStep(address target) internal view returns (bool) {
        try IAuthUpgradeable(target).pendingOwner() returns (address) {
            return true;
        } catch {
            return false;
        }
    }

    function run() external {
        if (newOwnerIsTimelock) {
            _runTimelock();
            return;
        }

        address _deployer = deployer();

        console.log("=== TransferOwnership ===");
        console.log("Deployer:", _deployer);
        console.log("New owner:", newOwner);

        // ── Phase 1: deployer broadcast ──────────────────────────────────
        vm.startBroadcast(deployerPrivateKey);

        if (includeVault) _transferVaultOwnership(_deployer);
        if (includeCommon) _transferCommonOwnership(_deployer);

        vm.stopBroadcast();

        // ── Phase 2: msig batch for acceptOwnership (AuthUpgradeable contracts only) ──
        console.log("-> Generating msig batch for acceptOwnership");

        if (includeVault) {
            _queueAcceptOwnership(vaultConfig.contracts.share);
            _queueAcceptOwnership(vaultConfig.contracts.accountant);
            for (uint256 i; i < vaultConfig.vaults.length; ++i) {
                _queueAcceptOwnership(vaultConfig.vaults[i].addr);
                _queueAcceptOwnership(vaultConfig.vaults[i].composer);
            }
        }

        if (includeCommon) {
            _queueAcceptOwnership(vaultConfig.common.complianceProxy);
            _queueAcceptOwnership(_complianceHook());
            _queueAcceptOwnership(vaultConfig.common.predicateProxy);
            _queueAcceptOwnership(vaultConfig.common.redeemOperator);
            _queueAcceptOwnership(vaultConfig.common.cctpRelayer);
        }

        // Write the msig batch
        msigMode = true;
        writeMsigBatch("TransferOwnership-AcceptOwnership");

        // ── Update output file ───────────────────────────────────────────
        if (includeVault) _updateOutputOwner();

        console.log("=== Done ===");
    }

    // ─── Timelock Mode (NEW_OWNER is a TimelockController) ──────────────

    /// @notice Transfers ownership of the privileged surfaces to the protocol timelock (PT).
    /// @dev    Runs in hybrid mode so each transfer routes directly when the deployer still owns the target
    ///         (fresh deploy) or into the Safe batch when the operational Safe owns it (migration). The
    ///         two-step AuthUpgradeable contracts only get `pendingOwner = PT` here; the matching
    ///         `acceptOwnership()` calls must be executed BY the timelock, so they are emitted as a
    ///         schedule batch (Safe signs now) + execute batch (Safe runs after the delay). Operational
    ///         roles are migrated to the operational Safe, never to the timelock.
    function _runTimelock() internal {
        address _deployer = deployer();
        address pt = newOwner;

        console.log("=== TransferOwnership (timelock mode) ===");
        console.log("Deployer:", _deployer);
        console.log("Protocol timelock (new owner):", pt);

        // ── Phase 1: route every ownership transfer through execute() (direct or queued) ──
        hybridMode = true;
        vm.startBroadcast(deployerPrivateKey);
        if (includeVault) _transferVaultOwnershipHybrid(pt);
        if (includeCommon) _transferCommonOwnershipHybrid(pt);
        vm.stopBroadcast();

        // ── Phase 2/3: schedule + execute batches for the two-step acceptOwnership calls ──
        address[] memory targets = _collectAcceptTargets(pt);
        bytes[] memory payloads = new bytes[](targets.length);
        for (uint256 i; i < targets.length; ++i) {
            payloads[i] = abi.encodeCall(IAuthUpgradeable.acceptOwnership, ());
        }
        uint256 delay = TimelockController(payable(pt)).getMinDelay();
        bytes32 salt = keccak256(abi.encodePacked("TransferOwnership", vaultConfig.symbol, vaultConfig.deployChainId));

        console.log("acceptOwnership targets to schedule:", targets.length);
        _buildTimelockBatches(
            pt, targets, payloads, salt, delay, "TransferOwnership-Schedule", "TransferOwnership-Execute"
        );

        if (includeVault) _updateOutputOwner();
        console.log("=== Done ===");
    }

    function _transferVaultOwnershipHybrid(address pt) internal {
        _transferArcDelegates(_roleMigrationTarget());
        address vaultAuth = _deriveVaultAuthority();
        console.log("--- Vault-specific contracts (timelock) ---");
        console.log("Vault authority:", vaultAuth);

        // Operational roles → operational Safe (never the timelock).
        if (vaultAuth != address(0)) {
            _migrateRoles(RolesAuthority(vaultAuth), deployer(), _roleMigrationTarget());
        }

        // Two-step AuthUpgradeable → pendingOwner = PT.
        _queueAuthTransfer(vaultConfig.contracts.share, pt);
        _queueAuthTransfer(vaultConfig.contracts.accountant, pt);
        for (uint256 i; i < vaultConfig.vaults.length; ++i) {
            _queueAuthTransfer(vaultConfig.vaults[i].addr, pt);
            _queueAuthTransfer(vaultConfig.vaults[i].composer, pt);
        }

        // One-step Solmate RolesAuthority + ProxyAdmins → PT immediately.
        if (vaultAuth != address(0)) _queueSolmateTransfer(vaultAuth, pt);
        _queueProxyAdminTransfer(vaultConfig.contracts.share, pt);
        _queueProxyAdminTransfer(vaultConfig.contracts.accountant, pt);
        for (uint256 i; i < vaultConfig.vaults.length; ++i) {
            _queueProxyAdminTransfer(vaultConfig.vaults[i].addr, pt);
            _queueProxyAdminTransfer(vaultConfig.vaults[i].composer, pt);
        }
    }

    function _transferCommonOwnershipHybrid(address pt) internal {
        address commonAuth = _deriveCommonAuthority();
        console.log("--- Common/infrastructure contracts (timelock) ---");
        console.log("Common authority:", commonAuth);

        if (commonAuth != address(0)) {
            _migrateRoles(RolesAuthority(commonAuth), deployer(), _roleMigrationTarget());
        }

        // Two-step AuthUpgradeable → pendingOwner = PT.
        _queueAuthTransfer(vaultConfig.common.complianceProxy, pt);
        _queueAuthTransfer(_complianceHook(), pt);
        _queueAuthTransfer(vaultConfig.common.predicateProxy, pt);
        _queueAuthTransfer(vaultConfig.common.redeemOperator, pt);
        _queueAuthTransfer(vaultConfig.common.cctpRelayer, pt);

        // One-step Solmate Auth → PT immediately.
        if (commonAuth != address(0)) _queueSolmateTransfer(commonAuth, pt);
        _queueSolmateTransfer(vaultConfig.common.operatorRegistry, pt);
        _queueSolmateTransfer(vaultConfig.common.seizer, pt);
        _queueSolmateTransfer(vaultConfig.common.blacklistHook, pt);
        _queueSolmateTransfer(vaultConfig.common.nestUnlooper, pt);

        // One-step ProxyAdmins → PT immediately.
        _queueProxyAdminTransfer(vaultConfig.common.complianceProxy, pt);
        _queueProxyAdminTransfer(_complianceHook(), pt);
        _queueProxyAdminTransfer(vaultConfig.common.predicateProxy, pt);
        _queueProxyAdminTransfer(vaultConfig.common.operatorRegistry, pt);
        _queueProxyAdminTransfer(vaultConfig.common.redeemOperator, pt);
        _queueProxyAdminTransfer(vaultConfig.common.cctpRelayer, pt);
        _queueProxyAdminTransfer(vaultConfig.common.seizer, pt);
    }

    /// @dev Two-step AuthUpgradeable transfer: sets pendingOwner = PT (idempotent), routed via execute().
    function _queueAuthTransfer(address target, address pt) internal {
        if (!isActive(target)) return;
        // One-step cores (Solmate Auth, e.g. the BoringVault share) have no pendingOwner — transfer to PT
        // immediately instead of the two-step pendingOwner dance.
        if (!_isTwoStep(target)) {
            _queueSolmateTransfer(target, pt);
            return;
        }
        IAuthUpgradeable auth = IAuthUpgradeable(target);
        if (auth.owner() == pt) {
            console.log("  Already owned by timelock:", target);
            return;
        }
        if (auth.pendingOwner() == pt) {
            console.log("  pendingOwner already timelock:", target);
            return;
        }
        execute(
            target,
            abi.encodeCall(IAuthUpgradeable.transferOwnership, (pt)),
            string.concat("transferOwnership(", vm.toString(target), ")")
        );
    }

    /// @dev One-step Solmate Auth transfer → PT immediately, routed via execute().
    function _queueSolmateTransfer(address target, address pt) internal {
        if (!isActive(target)) return;
        if (Auth(target).owner() == pt) {
            console.log("  Solmate Auth already timelock:", target);
            return;
        }
        execute(
            target,
            abi.encodeCall(Auth.transferOwnership, (pt)),
            string.concat("solmate.transferOwnership(", vm.toString(target), ")")
        );
    }

    /// @dev One-step ProxyAdmin (OZ Ownable) transfer → PT immediately, routed via execute().
    function _queueProxyAdminTransfer(address proxy, address pt) internal {
        if (!isActive(proxy)) return;
        address proxyAdmin = _getProxyAdmin(proxy);
        if (proxyAdmin == address(0)) return;
        if (IOwnable(proxyAdmin).owner() == pt) {
            console.log("  ProxyAdmin already timelock for:", proxy);
            return;
        }
        execute(
            proxyAdmin,
            abi.encodeCall(IOwnable.transferOwnership, (pt)),
            string.concat("proxyAdmin.transferOwnership(", vm.toString(proxy), ")")
        );
    }

    /// @dev Active two-step AuthUpgradeable surfaces whose owner is not yet PT — these need an
    ///      `acceptOwnership()` executed by the timelock. Collected by intent (owner != PT) because in
    ///      migration the `transferOwnership` that sets pendingOwner is only queued, not yet executed.
    function _collectAcceptTargets(address pt) internal view returns (address[] memory) {
        address[] memory buf = new address[](2 + vaultConfig.vaults.length * 2 + 5);
        uint256 n;
        if (includeVault) {
            n = _appendIfNeedsAccept(buf, n, vaultConfig.contracts.share, pt);
            n = _appendIfNeedsAccept(buf, n, vaultConfig.contracts.accountant, pt);
            for (uint256 i; i < vaultConfig.vaults.length; ++i) {
                n = _appendIfNeedsAccept(buf, n, vaultConfig.vaults[i].addr, pt);
                n = _appendIfNeedsAccept(buf, n, vaultConfig.vaults[i].composer, pt);
            }
        }
        if (includeCommon) {
            n = _appendIfNeedsAccept(buf, n, vaultConfig.common.complianceProxy, pt);
            n = _appendIfNeedsAccept(buf, n, _complianceHook(), pt);
            n = _appendIfNeedsAccept(buf, n, vaultConfig.common.predicateProxy, pt);
            n = _appendIfNeedsAccept(buf, n, vaultConfig.common.redeemOperator, pt);
            n = _appendIfNeedsAccept(buf, n, vaultConfig.common.cctpRelayer, pt);
        }
        address[] memory out = new address[](n);
        for (uint256 i; i < n; ++i) {
            out[i] = buf[i];
        }
        return out;
    }

    function _appendIfNeedsAccept(address[] memory buf, uint256 n, address target, address pt)
        internal
        view
        returns (uint256)
    {
        if (!isActive(target)) return n;
        // Only genuine two-step (AuthUpgradeable) surfaces need a timelock-executed acceptOwnership; one-step
        // cores transfer immediately in phase 1 and are already owned by PT.
        if (!_isTwoStep(target)) return n;
        // Dedup: vaults can share a composer — schedule each acceptOwnership only once, else the second call
        // reverts (pendingOwner already cleared) and the whole executeBatch fails.
        for (uint256 i; i < n; ++i) {
            if (buf[i] == target) return n;
        }
        // Skip non-AuthUpgradeable targets and those already fully owned by the timelock.
        try IAuthUpgradeable(target).owner() returns (address o) {
            if (o == pt) return n;
        } catch {
            return n;
        }
        buf[n] = target;
        return n + 1;
    }

    /// @dev Operational roles migrate to the operational Safe by default (never the timelock). Override with
    ///      ROLE_MIGRATION_TARGET to home them elsewhere — e.g. set it to the deployer EOA to leave
    ///      operational roles untouched (_migrateRoles self-skips when target == the current holder).
    function _roleMigrationTarget() internal view returns (address) {
        try vm.envAddress("ROLE_MIGRATION_TARGET") returns (address t) {
            if (t != address(0)) return t;
        } catch {}
        return commonConfig.multisig;
    }

    // ─── Vault-Specific Transfers ───────────────────────────────────────

    function _transferVaultOwnership(address _deployer) internal {
        _transferArcDelegates(newOwner);
        address vaultAuth = _deriveVaultAuthority();

        console.log("--- Vault-specific contracts ---");
        console.log("Vault authority:", vaultAuth);

        // Migrate deployer roles on vault authority
        if (vaultAuth != address(0)) {
            console.log("-> Migrating roles on vault authority");
            _migrateRoles(RolesAuthority(vaultAuth), _deployer, newOwner);
        }

        // Two-step transferOwnership on AuthUpgradeable contracts
        console.log("-> Transferring AuthUpgradeable ownership (two-step)");
        _transferAuthOwnership(vaultConfig.contracts.share);
        _transferAuthOwnership(vaultConfig.contracts.accountant);
        for (uint256 i; i < vaultConfig.vaults.length; ++i) {
            _transferAuthOwnership(vaultConfig.vaults[i].addr);
            _transferAuthOwnership(vaultConfig.vaults[i].composer);
        }

        // One-step transferOwnership on Solmate Auth (RolesAuthority)
        console.log("-> Transferring Solmate Auth ownership (one-step)");
        if (vaultAuth != address(0)) {
            _transferSolmateAuthOwnership(vaultAuth);
        }

        // One-step transferOwnership on ProxyAdmin (OZ Ownable)
        console.log("-> Transferring ProxyAdmin ownership (one-step)");
        _transferProxyAdminOwnership(vaultConfig.contracts.share);
        _transferProxyAdminOwnership(vaultConfig.contracts.accountant);
        for (uint256 i; i < vaultConfig.vaults.length; ++i) {
            _transferProxyAdminOwnership(vaultConfig.vaults[i].addr);
            _transferProxyAdminOwnership(vaultConfig.vaults[i].composer);
        }
    }

    // ─── Common/Infrastructure Transfers ────────────────────────────────

    function _transferCommonOwnership(address _deployer) internal {
        address commonAuth = _deriveCommonAuthority();

        console.log("--- Common/infrastructure contracts ---");
        console.log("Common authority:", commonAuth);

        // Migrate deployer roles on common authority
        if (commonAuth != address(0)) {
            console.log("-> Migrating roles on common authority");
            _migrateRoles(RolesAuthority(commonAuth), _deployer, newOwner);
        }

        // Two-step transferOwnership on AuthUpgradeable contracts
        console.log("-> Transferring AuthUpgradeable ownership (two-step)");
        _transferAuthOwnership(vaultConfig.common.complianceProxy);
        _transferAuthOwnership(_complianceHook());
        _transferAuthOwnership(vaultConfig.common.predicateProxy);
        _transferAuthOwnership(vaultConfig.common.redeemOperator);
        _transferAuthOwnership(vaultConfig.common.cctpRelayer);

        // One-step transferOwnership on Solmate Auth contracts
        console.log("-> Transferring Solmate Auth ownership (one-step)");
        if (commonAuth != address(0)) {
            _transferSolmateAuthOwnership(commonAuth);
        }
        _transferSolmateAuthOwnership(vaultConfig.common.operatorRegistry);
        _transferSolmateAuthOwnership(vaultConfig.common.seizer);
        _transferSolmateAuthOwnership(vaultConfig.common.blacklistHook);
        _transferSolmateAuthOwnership(vaultConfig.common.nestUnlooper);

        // One-step transferOwnership on ProxyAdmin (OZ Ownable)
        console.log("-> Transferring ProxyAdmin ownership (one-step)");
        _transferProxyAdminOwnership(vaultConfig.common.complianceProxy);
        _transferProxyAdminOwnership(_complianceHook());
        _transferProxyAdminOwnership(vaultConfig.common.predicateProxy);
        _transferProxyAdminOwnership(vaultConfig.common.operatorRegistry);
        _transferProxyAdminOwnership(vaultConfig.common.redeemOperator);
        _transferProxyAdminOwnership(vaultConfig.common.cctpRelayer);
        _transferProxyAdminOwnership(vaultConfig.common.seizer);
    }

    /// @dev Arc's deployer configures endpoint libraries before handoff. Move this remaining
    ///      configuration permission in the final phase too, while the deployer still owns the OApp.
    function _transferArcDelegates(address target) internal {
        if (vaultConfig.deployChainId != 5042) return;
        if (isOFT()) {
            for (uint256 i; i < vaultConfig.vaults.length; ++i) {
                _transferArcDelegate(vaultConfig.vaults[i].addr, target);
            }
        } else {
            _transferArcDelegate(vaultConfig.contracts.share, target);
        }
    }

    function _transferArcDelegate(address oapp, address target) internal {
        if (!isActive(oapp)) return;
        (bool ok, bytes memory data) = lzConfig.endpoint.staticcall(abi.encodeWithSignature("delegates(address)", oapp));
        require(ok && data.length == 32, "TransferOwnership: cannot read Arc LZ delegate");
        if (abi.decode(data, (address)) == target) return;
        execute(oapp, abi.encodeCall(IOAppCore.setDelegate, (target)), "setDelegate(final ownership handoff)");
    }

    /// @dev Discover the active shared hook from the proxy, never from a stale candidate manifest.
    function _complianceHook() internal view returns (address) {
        address proxy = vaultConfig.common.complianceProxy;
        if (!isActive(proxy)) return address(0);
        require(proxy.code.length > 0, "TransferOwnership: compliance proxy missing");
        address hook = address(ComplianceProxy(proxy).complianceHook());
        require(hook.code.length > 0, "TransferOwnership: compliance hook missing");
        return hook;
    }

    // ─── Derive Authorities ─────────────────────────────────────────────

    /// @dev Prefers the authority recorded in output/common config when it has code, else the live pointer.
    ///      Both known but different = staged replacement; refuse unless ALLOW_AUTHORITY_MISMATCH=true.
    function _deriveVaultAuthority() internal view returns (address) {
        address live = vaultConfig.contracts.share.code.length > 0
            ? address(Auth(vaultConfig.contracts.share).authority())
            : address(0);
        return _pickAuthority("vault", vaultConfig.contracts.rolesAuthority, live);
    }

    function _deriveCommonAuthority() internal view returns (address) {
        address live = vaultConfig.common.predicateProxy.code.length > 0
            ? address(Auth(vaultConfig.common.predicateProxy).authority())
            : address(0);
        return _pickAuthority("common", vaultConfig.common.commonRolesAuthority, live);
    }

    function _pickAuthority(string memory label, address configured, address live) internal view returns (address) {
        if (configured.code.length == 0) return live;
        if (live != address(0) && live != configured) {
            require(
                vm.envOr("ALLOW_AUTHORITY_MISMATCH", false),
                string.concat(
                    "TransferOwnership: ",
                    label,
                    " authority mismatch - configured ",
                    vm.toString(configured),
                    " vs live ",
                    vm.toString(live),
                    " (setAuthority still queued? set ALLOW_AUTHORITY_MISMATCH=true to hand off the configured one)"
                )
            );
            console.log("  WARNING: live", label, "authority differs; handing off configured:", configured);
        }
        return configured;
    }

    // ─── Role Migration ─────────────────────────────────────────────────

    function _migrateRoles(RolesAuthority rolesAuthority, address from, address to) internal {
        if (from == to) return;

        // If the authority is already owned by the msig (common authority on
        // chains where DeployAndSetup didn't deploy it fresh), deployer can't
        // call setUserRole directly — queue into the Safe batch instead.
        address authOwner;
        try rolesAuthority.owner() returns (address o) {
            authOwner = o;
        } catch {}
        bool deployerIsOwner = (authOwner == from);

        bool movedAny;
        for (uint8 role; role < ROLE_COUNT; ++role) {
            if (!rolesAuthority.doesUserHaveRole(from, role)) continue;
            if (deployerIsOwner) {
                rolesAuthority.setUserRole(to, role, true);
                rolesAuthority.setUserRole(from, role, false);
            } else {
                serializedTxs.push(
                    SerializedTx({
                        name: string.concat("setUserRole(grant role=", Strings.toString(uint256(role)), ")"),
                        to: address(rolesAuthority),
                        value: 0,
                        data: abi.encodeCall(RolesAuthority.setUserRole, (to, role, true))
                    })
                );
                serializedTxs.push(
                    SerializedTx({
                        name: string.concat("setUserRole(revoke role=", Strings.toString(uint256(role)), ")"),
                        to: address(rolesAuthority),
                        value: 0,
                        data: abi.encodeCall(RolesAuthority.setUserRole, (from, role, false))
                    })
                );
            }
            movedAny = true;
            console.log("  Moved role", uint256(role), deployerIsOwner ? "(direct)" : "(queued for msig)");
        }
        if (!movedAny) {
            console.log("  No deployer roles to migrate");
        }
    }

    // ─── Two-Step AuthUpgradeable Transfers ─────────────────────────────

    function _transferAuthOwnership(address target) internal {
        if (!isActive(target)) return;

        // One-step cores (Solmate Auth, e.g. the BoringVault share) have no pendingOwner — transfer in one step.
        if (!_isTwoStep(target)) {
            _transferSolmateAuthOwnership(target);
            return;
        }

        IAuthUpgradeable auth = IAuthUpgradeable(target);
        address currentOwner = auth.owner();

        if (currentOwner == newOwner) {
            console.log("  Already owned by new owner:", target);
            return;
        }

        address pending = auth.pendingOwner();
        if (pending == newOwner) {
            console.log("  PendingOwner already set:", target);
            return;
        }

        auth.transferOwnership(newOwner);
        console.log("  transferOwnership called:", target);
    }

    // ─── One-Step Solmate Auth Transfers (RolesAuthority) ───────────────

    function _transferSolmateAuthOwnership(address target) internal {
        if (!isActive(target)) return;

        address currentOwner = Auth(target).owner();
        if (currentOwner == newOwner) {
            console.log("  Solmate Auth already owned by new owner:", target);
            return;
        }

        Auth(target).transferOwnership(newOwner);
        require(Auth(target).owner() == newOwner, "TransferOwnership: Solmate Auth transfer failed");
        console.log("  Solmate Auth transferred:", target);
    }

    // ─── ProxyAdmin Transfers ───────────────────────────────────────────

    function _transferProxyAdminOwnership(address proxy) internal {
        if (!isActive(proxy)) return;

        address proxyAdmin = _getProxyAdmin(proxy);
        if (proxyAdmin == address(0)) return;

        address currentOwner = IOwnable(proxyAdmin).owner();
        if (currentOwner == newOwner) {
            console.log("  ProxyAdmin already owned by new owner for:", proxy);
            return;
        }

        IOwnable(proxyAdmin).transferOwnership(newOwner);
        require(IOwnable(proxyAdmin).owner() == newOwner, "TransferOwnership: ProxyAdmin transfer failed");
        console.log("  ProxyAdmin transferred for:", proxy);
    }

    function _getProxyAdmin(address proxy) internal view returns (address) {
        bytes32 adminSlot = vm.load(proxy, ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }

    // ─── Queue acceptOwnership for Msig ─────────────────────────────────

    function _queueAcceptOwnership(address target) internal {
        if (!isActive(target)) return;

        try IAuthUpgradeable(target).pendingOwner() returns (address pending) {
            if (pending != newOwner) return;
        } catch {
            return;
        }

        bytes memory data = abi.encodeCall(IAuthUpgradeable.acceptOwnership, ());
        // Dedup (same rule as _appendIfNeedsAccept): vaults can share a composer — queue each acceptOwnership once,
        // else the second call reverts (pendingOwner already cleared) and the whole Safe batch fails.
        for (uint256 i; i < serializedTxs.length; ++i) {
            if (serializedTxs[i].to == target && keccak256(serializedTxs[i].data) == keccak256(data)) return;
        }

        serializedTxs.push(SerializedTx({name: "acceptOwnership", to: target, value: 0, data: data}));
        console.log("  Queued acceptOwnership for:", target);
    }

    // ─── Update Output File ─────────────────────────────────────────────

    function _updateOutputOwner() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/script/output/",
            vaultConfig.symbol,
            "/",
            vaultConfig.deployChainId.toString(),
            "-",
            vaultConfig.symbol,
            ".json"
        );

        vm.writeJson(vm.toString(newOwner), path, ".owner");
        console.log("Output updated:", path);
    }
}
