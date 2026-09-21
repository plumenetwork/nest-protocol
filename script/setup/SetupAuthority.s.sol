// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {ConfigReader, VaultDeployConfig} from "script/lib/ConfigReader.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {NestUnlooper} from "contracts/integrations/morpho/NestUnlooper.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {NestShareSeizer} from "contracts/compliance/NestShareSeizer.sol";
import {ITransferHook} from "contracts/interfaces/ITransferHook.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";

/// @title  SetupAuthority
/// @notice Configures roles and capabilities by parsing config/authority/authority.json and common-authority.json.
/// @dev    Two separate RolesAuthority instances are used:
///         - rolesAuthority: governs vault-specific contracts (share, accountant, vaults, composers)
///           Derived on-chain from share.authority().
///         - commonRolesAuthority: governs common/infrastructure contracts (predicateProxy, operatorRegistry,
///           redeemOperator, cctpRelayer, seizer, blacklistHook, nestUnlooper)
///           Derived on-chain from predicateProxy.authority().
///         Resolves symbolic target/user names (e.g., "share", "vault", "MANAGER_ROLE") to addresses from the vault config.
///         "vault" and "composer" resolve to ALL vault/composer addresses.
///         Supports conditionalOn checks to skip entries when the referenced contract is address(0).
///
///         Optional `revokeCapabilities` / `revokeRoleAssignments` arrays (same shape as
///         `capabilities` / `roleAssignments`) emit setRoleCapability(...,false) / setUserRole(...,false).
///         They run AFTER the add passes, so a same-batch move (e.g. pause role 0->6) grants the new
///         wiring before removing the old, leaving no gap. Idempotent: skips entries already cleared.
///
///         Usage:
///           VAULT_SYMBOL=nTEST forge script script/setup/SetupAuthority.s.sol --sig "runDirect()" --rpc-url $RPC --broadcast
///           VAULT_SYMBOL=nTEST forge script script/setup/SetupAuthority.s.sol --sig "runMsig()" --rpc-url $RPC
contract SetupAuthority is BaseConfigScript {
    using stdJson for string;

    function setUp() public {
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");
        loadConfigs(vaultSymbol);
    }

    function runDirect() external {
        _setup(false);
        _logDirectTxs();
    }

    function runMsig() external {
        _setup(true);
        writeMsigBatch("SetupAuthority");
    }

    /// @notice Hybrid: broadcasts every call the deployer is owner of, queues the rest.
    ///         For each `execute(target, ...)`, the router in `BaseConfigScript.execute` checks
    ///         `_isOwner(target)` (Auth.owner() == deployer) and either broadcasts directly or
    ///         appends to the Safe batch.  Ideal post-DeployMorpho when the deployer still owns
    ///         the freshly-deployed NestUnlooper but the vault/common authorities are already
    ///         held by the multisig.
    function run() external {
        hybridMode = true;
        _setup(false);
        writeMsigBatch("SetupAuthority");
    }

    function _setup(bool _msigMode) internal directOrMsig(_msigMode) {
        address vaultAuth = _deriveVaultAuthority();
        address commonAuth = _deriveCommonAuthority();
        require(vaultAuth != address(0), "SetupAuthority: rolesAuthority not set on share");
        require(commonAuth != address(0), "SetupAuthority: commonRolesAuthority not set on predicateProxy");

        _setAuthorityOnContracts(vaultAuth, commonAuth);

        // SetupAuthority is also a launch surface: do not let a standalone invocation
        // bypass DeployAndSetup's fee postcondition before it opens public/user routes.
        _requireVaultFeesReadyForLaunch();

        string memory root = vm.projectRoot();

        // Vault authority config (governs share, accountant, vaults, composers)
        string memory vaultJson = vm.readFile(string.concat(root, "/config/authority/authority.json"));
        _processCapabilities(vaultJson, vaultAuth);
        _processPublicCapabilities(vaultJson, vaultAuth);
        _processRoleAssignments(vaultJson, vaultAuth);
        _processRevokeCapabilities(vaultJson, vaultAuth);
        _processRevokeRoleAssignments(vaultJson, vaultAuth);

        // Common authority config (governs predicateProxy, operatorRegistry, redeemOperator, cctpRelayer,
        // seizer, blacklistHook, nestUnlooper)
        string memory commonJson = vm.readFile(string.concat(root, "/config/authority/common-authority.json"));
        _processCapabilities(commonJson, commonAuth);
        _processPublicCapabilities(commonJson, commonAuth);
        _processRoleAssignments(commonJson, commonAuth);
        _processRevokeCapabilities(commonJson, commonAuth);
        _processRevokeRoleAssignments(commonJson, commonAuth);

        _approveUnlooperTargets();
        _assertCanSeize();
    }

    // ─── NestUnlooper Vault/Teller Approval ───────────────────────────

    /// @dev Idempotently calls `setVaultApproval(target, true)` on the chain-wide NestUnlooper for
    ///      every active vault entry on this chain plus their optional legacyTeller.  These targets
    ///      are gated by `approvedVault` inside `NestUnlooper.execute` ([NestUnlooper.sol:241-246]).
    function _approveUnlooperTargets() internal {
        if (!isActive(vaultConfig.common.nestUnlooper)) return;
        NestUnlooper unlooper = NestUnlooper(vaultConfig.common.nestUnlooper);

        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            _approveOnUnlooper(unlooper, vaultConfig.vaults[i].addr);
            _approveOnUnlooper(unlooper, vaultConfig.vaults[i].legacyTeller);
        }
    }

    function _approveOnUnlooper(NestUnlooper unlooper, address target) internal {
        if (!isActive(target)) return;
        try unlooper.approvedVault(target) returns (bool approved) {
            if (approved) {
                _logSkipped(string.concat("setVaultApproval(", vm.toString(target), ")"));
                return;
            }
        } catch {}
        execute(
            address(unlooper),
            abi.encodeCall(NestUnlooper.setVaultApproval, (target, true)),
            string.concat("setVaultApproval(", vm.toString(target), ")")
        );
    }

    /// @dev Direct-mode postcondition: after wiring, the seizer must be able to seize the share.
    ///      Skipped when calls were queued (msig/hybrid), a target is not deployed (try/catch does not
    ///      cover empty-returndata decode failures), or the hook is not installed on the share.
    function _assertCanSeize() internal view {
        if (msigMode || hybridMode) return;
        if (!isActive(vaultConfig.common.seizer) || !isActive(vaultConfig.contracts.share)) return;
        if (vaultConfig.contracts.share.code.length == 0 || vaultConfig.common.seizer.code.length == 0) {
            _logSkipped("canSeize postcondition (share or seizer not deployed)");
            return;
        }
        NestShareOFT share_ = NestShareOFT(payable(vaultConfig.contracts.share));
        try share_.hook() returns (ITransferHook h) {
            if (address(h) == address(0)) return;
        } catch {
            return; // pre-hook share impl
        }
        try NestShareSeizer(vaultConfig.common.seizer).canSeize(share_) returns (bool ok) {
            require(ok, "SetupAuthority: seizer cannot seize share after setup (role 15 wiring incomplete)");
        } catch {
            revert("SetupAuthority: canSeize reverted (seizer/hook authority unset)");
        }
    }

    // ─── Derive Authority from On-Chain ───────────────────────────────

    /// @dev Returns the vault-specific RolesAuthority from config, falling back to share.authority().
    function _deriveVaultAuthority() internal view returns (address) {
        if (vaultConfig.contracts.rolesAuthority.code.length > 0) return vaultConfig.contracts.rolesAuthority;
        if (vaultConfig.contracts.share.code.length > 0) {
            return address(Auth(vaultConfig.contracts.share).authority());
        }
        return address(0);
    }

    /// @dev Returns the common RolesAuthority from config, falling back to predicateProxy.authority().
    function _deriveCommonAuthority() internal view returns (address) {
        if (vaultConfig.common.commonRolesAuthority.code.length > 0) return vaultConfig.common.commonRolesAuthority;
        if (vaultConfig.common.predicateProxy.code.length > 0) {
            return address(Auth(vaultConfig.common.predicateProxy).authority());
        }
        return address(0);
    }

    // ─── Set Authority on Contracts ───────────────────────────────────

    function _setAuthorityOnContracts(address vaultAuth, address commonAuth) internal {
        Authority vaultAuthority = Authority(vaultAuth);
        Authority commonAuthority = Authority(commonAuth);

        // Vault-specific contracts → vault authority
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            _setAuthorityIfNeeded(vaultConfig.vaults[i].addr, vaultAuthority);
            _setAuthorityIfNeeded(vaultConfig.vaults[i].composer, vaultAuthority);
        }
        _setAuthorityIfNeeded(vaultConfig.contracts.share, vaultAuthority);
        _setAuthorityIfNeeded(vaultConfig.contracts.accountant, vaultAuthority);

        // Common/infrastructure contracts → common authority
        _setAuthorityIfNeeded(vaultConfig.common.predicateProxy, commonAuthority);
        if (isActive(vaultConfig.common.operatorRegistry)) {
            _setAuthorityIfNeeded(vaultConfig.common.operatorRegistry, commonAuthority);
        }
        if (isActive(vaultConfig.common.cctpRelayer)) {
            _setAuthorityIfNeeded(vaultConfig.common.cctpRelayer, commonAuthority);
        }
        if (isActive(vaultConfig.common.redeemOperator)) {
            _setAuthorityIfNeeded(vaultConfig.common.redeemOperator, commonAuthority);
        }
        if (isActive(vaultConfig.common.seizer)) {
            _setAuthorityIfNeeded(vaultConfig.common.seizer, commonAuthority);
        }
        if (isActive(vaultConfig.common.blacklistHook)) {
            _setAuthorityIfNeeded(vaultConfig.common.blacklistHook, commonAuthority);
        }
        if (isActive(vaultConfig.common.nestUnlooper)) {
            _setAuthorityIfNeeded(vaultConfig.common.nestUnlooper, commonAuthority);
        }
    }

    function _setAuthorityIfNeeded(address target, Authority expected) internal {
        if (target == address(0) || target.code.length == 0) return;
        try Auth(target).authority() returns (Authority current) {
            if (current == expected) {
                _logSkipped(string.concat("setAuthority(", vm.toString(target), ")"));
                return;
            }
        } catch {}
        execute(
            target,
            abi.encodeCall(Auth.setAuthority, (expected)),
            string.concat("setAuthority(", vm.toString(target), ")")
        );
    }

    // ─── Process Capabilities ─────────────────────────────────────────

    function _processCapabilities(string memory json, address auth) internal {
        bytes memory rawCaps = json.parseRaw(".capabilities");
        bytes[] memory capsArray = abi.decode(rawCaps, (bytes[]));

        for (uint256 i = 0; i < capsArray.length; i++) {
            string memory prefix = string.concat(".capabilities[", vm.toString(i), "]");

            uint8 role = uint8(json.readUint(string.concat(prefix, ".role")));
            string memory targetName = json.readString(string.concat(prefix, ".target"));

            string memory conditionalOn = _tryReadString(json, string.concat(prefix, ".conditionalOn"));
            if (bytes(conditionalOn).length > 0 && !_checkCondition(conditionalOn)) continue;

            address[] memory targets = _resolveTargets(targetName);

            string[] memory functions = json.readStringArray(string.concat(prefix, ".functions"));
            for (uint256 t = 0; t < targets.length; t++) {
                if (!isActive(targets[t])) continue;
                for (uint256 f = 0; f < functions.length; f++) {
                    bytes4 selector = bytes4(keccak256(bytes(functions[f])));
                    string memory capLabel = string.concat(
                        "setRoleCapability(role=",
                        vm.toString(role),
                        ", target=",
                        targetName,
                        ", fn=",
                        functions[f],
                        ")"
                    );
                    if (RolesAuthority(auth).doesRoleHaveCapability(role, targets[t], selector)) {
                        _logSkipped(capLabel);
                        continue;
                    }
                    execute(
                        auth,
                        abi.encodeCall(RolesAuthority.setRoleCapability, (role, targets[t], selector, true)),
                        capLabel
                    );
                }
            }
        }
    }

    // ─── Process Public Capabilities ──────────────────────────────────

    function _processPublicCapabilities(string memory json, address auth) internal {
        bytes memory rawPubs = json.parseRaw(".publicCapabilities");
        bytes[] memory pubsArray = abi.decode(rawPubs, (bytes[]));

        for (uint256 i = 0; i < pubsArray.length; i++) {
            string memory prefix = string.concat(".publicCapabilities[", vm.toString(i), "]");

            string memory targetName = json.readString(string.concat(prefix, ".target"));

            string memory conditionalOn = _tryReadString(json, string.concat(prefix, ".conditionalOn"));
            bool condHolds = bytes(conditionalOn).length == 0 || _checkCondition(conditionalOn);

            address[] memory targets = _resolveTargets(targetName);

            string[] memory functions = json.readStringArray(string.concat(prefix, ".functions"));
            for (uint256 t = 0; t < targets.length; t++) {
                if (!isActive(targets[t])) continue;
                for (uint256 f = 0; f < functions.length; f++) {
                    bytes4 selector = bytes4(keccak256(bytes(functions[f])));
                    string memory pubLabel =
                        string.concat("setPublicCapability(target=", targetName, ", fn=", functions[f], ")");
                    // Fail closed: condition no longer holds but the reused authority still has this selector
                    // public - revoke with setPublicCapability(target, selector, false) and rerun.
                    if (!condHolds) {
                        if (RolesAuthority(auth).isCapabilityPublic(targets[t], selector)) {
                            revert(_stalePublicMsg(conditionalOn, pubLabel));
                        }
                        continue;
                    }
                    if (RolesAuthority(auth).isCapabilityPublic(targets[t], selector)) {
                        _logSkipped(pubLabel);
                        continue;
                    }
                    execute(
                        auth, abi.encodeCall(RolesAuthority.setPublicCapability, (targets[t], selector, true)), pubLabel
                    );
                }
            }
        }
    }

    /// @dev Builds the fail-closed error for a conditional public capability still public on-chain.
    function _stalePublicMsg(string memory conditionalOn, string memory pubLabel)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "SetupAuthority: stale public capability - '",
            conditionalOn,
            "' no longer holds but on-chain state is public: ",
            pubLabel
        );
    }

    // ─── Process Role Assignments ─────────────────────────────────────

    function _processRoleAssignments(string memory json, address auth) internal {
        bytes memory rawAssignments = json.parseRaw(".roleAssignments");
        bytes[] memory assignmentsArray = abi.decode(rawAssignments, (bytes[]));

        for (uint256 i = 0; i < assignmentsArray.length; i++) {
            string memory prefix = string.concat(".roleAssignments[", vm.toString(i), "]");

            string memory userName = json.readString(string.concat(prefix, ".user"));
            uint8 role = uint8(json.readUint(string.concat(prefix, ".role")));

            string memory conditionalOn = _tryReadString(json, string.concat(prefix, ".conditionalOn"));
            if (bytes(conditionalOn).length > 0 && !_checkCondition(conditionalOn)) continue;

            address[] memory users = _resolveUsers(userName);
            for (uint256 u = 0; u < users.length; u++) {
                if (isActive(users[u])) {
                    string memory roleLabel = string.concat(
                        "setUserRole(user=",
                        userName,
                        ", role=",
                        vm.toString(role),
                        ", addr=",
                        vm.toString(users[u]),
                        ")"
                    );
                    if (RolesAuthority(auth).doesUserHaveRole(users[u], role)) {
                        _logSkipped(roleLabel);
                        continue;
                    }
                    execute(auth, abi.encodeCall(RolesAuthority.setUserRole, (users[u], role, true)), roleLabel);
                }
            }
        }
    }

    // ─── Process Revocations (capability disables + role removals) ─────
    // Mirror the add passes but emit `false` and skip when already cleared. Both source arrays
    // (`revokeCapabilities`, `revokeRoleAssignments`) are optional; absent => no-op.

    function _processRevokeCapabilities(string memory json, address auth) internal {
        uint256 capsLen = _objectArrayLength(json, ".revokeCapabilities");

        for (uint256 i = 0; i < capsLen; i++) {
            string memory prefix = string.concat(".revokeCapabilities[", vm.toString(i), "]");

            uint8 role = uint8(json.readUint(string.concat(prefix, ".role")));
            string memory targetName = json.readString(string.concat(prefix, ".target"));

            string memory conditionalOn = _tryReadString(json, string.concat(prefix, ".conditionalOn"));
            if (bytes(conditionalOn).length > 0 && !_checkCondition(conditionalOn)) continue;

            address[] memory targets = _resolveTargets(targetName);

            string[] memory functions = json.readStringArray(string.concat(prefix, ".functions"));
            for (uint256 t = 0; t < targets.length; t++) {
                if (!isActive(targets[t])) continue;
                for (uint256 f = 0; f < functions.length; f++) {
                    bytes4 selector = bytes4(keccak256(bytes(functions[f])));
                    string memory capLabel = string.concat(
                        "REVOKE setRoleCapability(role=",
                        vm.toString(role),
                        ", target=",
                        targetName,
                        ", fn=",
                        functions[f],
                        ")"
                    );
                    if (!RolesAuthority(auth).doesRoleHaveCapability(role, targets[t], selector)) {
                        _logSkipped(capLabel);
                        continue;
                    }
                    execute(
                        auth,
                        abi.encodeCall(RolesAuthority.setRoleCapability, (role, targets[t], selector, false)),
                        capLabel
                    );
                }
            }
        }
    }

    function _processRevokeRoleAssignments(string memory json, address auth) internal {
        uint256 revLen = _objectArrayLength(json, ".revokeRoleAssignments");

        for (uint256 i = 0; i < revLen; i++) {
            string memory prefix = string.concat(".revokeRoleAssignments[", vm.toString(i), "]");

            string memory userName = json.readString(string.concat(prefix, ".user"));
            uint8 role = uint8(json.readUint(string.concat(prefix, ".role")));

            string memory conditionalOn = _tryReadString(json, string.concat(prefix, ".conditionalOn"));
            if (bytes(conditionalOn).length > 0 && !_checkCondition(conditionalOn)) continue;

            address[] memory users = _resolveUsers(userName);
            for (uint256 u = 0; u < users.length; u++) {
                if (!isActive(users[u])) continue;
                string memory roleLabel = string.concat(
                    "REVOKE setUserRole(user=",
                    userName,
                    ", role=",
                    vm.toString(role),
                    ", addr=",
                    vm.toString(users[u]),
                    ")"
                );
                if (!RolesAuthority(auth).doesUserHaveRole(users[u], role)) {
                    _logSkipped(roleLabel);
                    continue;
                }
                // Safety: never revoke a (user, role) the config still grants on THIS chain — e.g. an
                // address that is the active nestUnlooper on one chain but superseded on another.
                if (_isDesiredAssignment(json, users[u], role)) {
                    _logSkipped(string.concat(roleLabel, " [still in desired set]"));
                    continue;
                }
                execute(auth, abi.encodeCall(RolesAuthority.setUserRole, (users[u], role, false)), roleLabel);
            }
        }
    }

    /// @dev True if the config's `roleAssignments` still grant `role` to `user` on the current chain
    ///      (resolving symbolic names + conditionalOn). Guards revokes from removing a live assignment
    ///      whose address is the active contract here but superseded elsewhere.
    function _isDesiredAssignment(string memory json, address user, uint8 role) internal view returns (bool) {
        uint256 n = _objectArrayLength(json, ".roleAssignments");
        for (uint256 i = 0; i < n; i++) {
            string memory prefix = string.concat(".roleAssignments[", vm.toString(i), "]");
            if (uint8(json.readUint(string.concat(prefix, ".role"))) != role) continue;
            string memory cond = _tryReadString(json, string.concat(prefix, ".conditionalOn"));
            if (bytes(cond).length > 0 && !_checkCondition(cond)) continue;
            address[] memory users = _resolveUsers(json.readString(string.concat(prefix, ".user")));
            for (uint256 u2 = 0; u2 < users.length; u2++) {
                if (users[u2] == user) return true;
            }
        }
        return false;
    }

    /// @dev Length of the object array at `key`, or 0 if absent. Counts by probing `key[i].role`
    ///      rather than abi-decoding the array — foundry's parseJson type-inference can choke on
    ///      single-element / address-valued arrays, and we only need the length to drive the loops.
    function _objectArrayLength(string memory json, string memory key) internal view returns (uint256 n) {
        if (!vm.keyExistsJson(json, key)) return 0;
        while (vm.keyExistsJson(json, string.concat(key, "[", vm.toString(n), "].role"))) {
            n++;
        }
    }

    // ─── Resolution Helpers ───────────────────────────────────────────

    function _resolveTargets(string memory name) internal view returns (address[] memory) {
        bytes32 h = keccak256(bytes(name));

        // Literal address (e.g. revoking a capability on a superseded contract with no config alias).
        if (bytes(name).length == 42 && bytes(name)[0] == 0x30 && bytes(name)[1] == 0x78) {
            return _toArray(vm.parseAddress(name));
        }

        if (h == keccak256("vault")) return ConfigReader.getVaultAddresses(vaultConfig);
        if (h == keccak256("composer")) return ConfigReader.getComposerAddresses(vaultConfig);
        if (h == keccak256("share")) return _toArray(vaultConfig.contracts.share);
        if (h == keccak256("accountant")) return _toArray(vaultConfig.contracts.accountant);
        if (h == keccak256("cctpRelayer")) return _toArray(vaultConfig.common.cctpRelayer);
        if (h == keccak256("redeemOperator")) return _toArray(vaultConfig.common.redeemOperator);
        if (h == keccak256("operatorRegistry")) return _toArray(vaultConfig.common.operatorRegistry);
        if (h == keccak256("predicateProxy")) return _toArray(vaultConfig.common.predicateProxy);
        if (h == keccak256("complianceProxy")) return _toArray(vaultConfig.common.complianceProxy);
        if (h == keccak256("shareSeizer")) return _toArray(vaultConfig.common.seizer);
        if (h == keccak256("blacklistHook")) return _toArray(vaultConfig.common.blacklistHook);
        if (h == keccak256("nestAdapter")) return _toArray(vaultConfig.common.nestAdapter);
        if (h == keccak256("nestBundler")) return _toArray(vaultConfig.common.nestBundler);
        if (h == keccak256("nestUnlooper")) return _toArray(vaultConfig.common.nestUnlooper);
        revert(string.concat("SetupAuthority: unknown target '", name, "'"));
    }

    function _resolveUsers(string memory name) internal view returns (address[] memory) {
        bytes32 h = keccak256(bytes(name));

        // Literal address (e.g. revoking a superseded contract with no config alias).
        if (bytes(name).length == 42 && bytes(name)[0] == 0x30 && bytes(name)[1] == 0x78) {
            return _toArray(vm.parseAddress(name));
        }

        if (h == keccak256("vault")) return ConfigReader.getVaultAddresses(vaultConfig);
        if (h == keccak256("composer")) return ConfigReader.getComposerAddresses(vaultConfig);
        if (h == keccak256("share")) return _toArray(vaultConfig.contracts.share);
        if (h == keccak256("predicateProxy")) return _toArray(vaultConfig.common.predicateProxy);
        if (h == keccak256("cctpRelayer")) return _toArray(vaultConfig.common.cctpRelayer);
        if (h == keccak256("redeemOperator")) return _toArray(vaultConfig.common.redeemOperator);
        if (h == keccak256("owner")) return _toArray(ConfigReader.resolvedOwner(vaultConfig));

        if (h == keccak256("shareSeizer")) return _toArray(vaultConfig.common.seizer);

        if (h == keccak256("MANAGER_ROLE")) return vaultConfig.roles.MANAGER_ROLE;
        if (h == keccak256("UPDATE_EXCHANGE_RATE_ROLE")) return vaultConfig.roles.UPDATE_EXCHANGE_RATE_ROLE;
        if (h == keccak256("KEEPER_ROLE")) return vaultConfig.roles.KEEPER_ROLE;
        if (h == keccak256("CAN_SOLVE_ROLE")) return vaultConfig.roles.CAN_SOLVE_ROLE;
        if (h == keccak256("OWNER_ROLE")) return vaultConfig.roles.OWNER_ROLE;
        if (h == keccak256("PAUSER_ROLE")) return vaultConfig.roles.PAUSER_ROLE;
        if (h == keccak256("DEPOSITOR_ROLE")) return vaultConfig.roles.DEPOSITOR_ROLE;

        if (h == keccak256("nestAdapter")) return _toArray(vaultConfig.common.nestAdapter);
        if (h == keccak256("nestUnlooper")) return _toArray(vaultConfig.common.nestUnlooper);

        revert(string.concat("SetupAuthority: unknown user '", name, "'"));
    }

    function _checkCondition(string memory condition) internal view returns (bool) {
        bytes32 h = keccak256(bytes(condition));
        if (h == keccak256("predicateProxy")) return isActive(vaultConfig.common.predicateProxy);
        if (h == keccak256("noPredicateProxy")) return !isActive(vaultConfig.common.predicateProxy);
        if (h == keccak256("composer")) {
            for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
                if (isActive(vaultConfig.vaults[i].composer)) return true;
            }
            return false;
        }
        if (h == keccak256("cctpRelayer")) return isActive(vaultConfig.common.cctpRelayer);
        if (h == keccak256("redeemOperator")) return isActive(vaultConfig.common.redeemOperator);
        if (h == keccak256("operatorRegistry")) return isActive(vaultConfig.common.operatorRegistry);
        if (h == keccak256("shareSeizer")) return isActive(vaultConfig.common.seizer);
        if (h == keccak256("blacklistHook")) return isActive(vaultConfig.common.blacklistHook);
        if (h == keccak256("vaultTypeOFT")) return isOFT();
        if (h == keccak256("vaultTypeNotOFT")) return !isOFT();
        if (h == keccak256("nestAdapter")) return isActive(vaultConfig.common.nestAdapter);
        if (h == keccak256("nestBundler")) return isActive(vaultConfig.common.nestBundler);
        if (h == keccak256("nestUnlooper")) return isActive(vaultConfig.common.nestUnlooper);
        if (h == keccak256("complianceProxy")) return isActive(vaultConfig.common.complianceProxy);
        // True when `vaultConfig.owner` points to a contract (i.e. a Safe/multisig).
        // Used to gate role assignments that should never reach an EOA "owner".
        if (h == keccak256("ownerIsMsig")) {
            address o = vaultConfig.owner;
            return o != address(0) && o != deployer() && o.code.length > 0;
        }
        return true;
    }

    function _toArray(address addr) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = addr;
    }

    function _tryReadString(string memory json, string memory key) internal pure returns (string memory) {
        try vm.parseJsonString(json, key) returns (string memory val) {
            return val;
        } catch {
            return "";
        }
    }
}
