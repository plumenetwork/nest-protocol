// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ICreateX} from "createx/ICreateX.sol";
import {Auth} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {NestVaultCoreTypes} from "contracts/types/NestVaultCoreTypes.sol";
import {Constants} from "script/lib/Constants.sol";
import {SerializedTx, SafeTxUtil} from "script/lib/SafeBatchSerialize.sol";
import {
    ConfigReader,
    CommonConfig,
    ChainComplianceConfig,
    CommonContracts,
    LZConfig,
    CCTPConfig,
    VaultDeployConfig,
    VaultEntry,
    DVNConfig,
    EnforcedOptionsConfig
} from "script/lib/ConfigReader.sol";
import {console} from "forge-std/console.sol";

/// @title BaseConfigScript
/// @notice Base script with config loading and dual-mode execution (direct broadcast or Safe multisig batch).
/// @dev All deployment and setup scripts inherit from this contract.
///      - `runDirect()` executes via vm.startBroadcast (EOA signs)
///      - `runMsig()` accumulates calls into a Safe-compatible JSON batch
abstract contract BaseConfigScript is Script, Constants {
    using Strings for uint256;

    // ─── Config State ─────────────────────────────────────────────────

    CommonConfig internal commonConfig;
    ChainComplianceConfig internal chainComplianceConfig;
    LZConfig internal lzConfig;
    VaultDeployConfig internal vaultConfig;

    // ─── Execution State ──────────────────────────────────────────────

    bool internal msigMode;
    bool internal hybridMode;
    bool internal verbose;
    SerializedTx[] internal serializedTxs;
    /// @notice Tracks every call routed through `execute` that ran directly (broadcast or simulated)
    ///         instead of being queued into the multisig batch.  Used by `_logDirectTxs` for dry-run
    ///         visibility into hybrid execution.
    SerializedTx[] internal directTxs;

    ICreateX internal CREATEX;
    uint256 internal deployerPrivateKey;
    string internal rawVaultConfigJson;

    /// @notice Snapshot of `vaultConfig.common` taken before any deploy mutation.
    ///         Used by `writeCommonConfigIfChanged` to skip writes when nothing changed.
    CommonContracts internal commonSnapshot;

    /// @notice Chain-level common config as loaded, before per-vault `commonOverrides` — base for
    ///         `writeCommonConfigIfChanged`, so overrides never leak into the canonical common file.
    CommonContracts internal commonCanonical;
    bool internal commonOverridesApplied;

    // ─── Config Loading ───────────────────────────────────────────────

    function loadConfigs(string memory vaultSymbol) internal {
        rawVaultConfigJson =
            vm.readFile(string.concat(vm.projectRoot(), "/script/deployment-config/vaults/", vaultSymbol, ".json"));
        vaultConfig = ConfigReader.readVaultConfig(vaultSymbol);
        // CHAIN_ID env var is the source of truth for the target chain.
        // Falls back to deployChainId from the JSON (output configs still have it).
        uint256 chainId;
        try vm.envUint("CHAIN_ID") returns (uint256 id) {
            chainId = id;
        } catch {
            chainId = vaultConfig.deployChainId;
            require(chainId != 0, "BaseConfigScript: CHAIN_ID env var required");
        }
        // Resolve config for the target chain: sets deployChainId, filters vaults, zeros CCTP relayer on non-CCTP chains
        vaultConfig = ConfigReader.resolveConfigForChain(vaultConfig, chainId);
        string memory ownerKey = string.concat(".ownerOverrides.", Strings.toString(chainId));
        if (vm.keyExistsJson(rawVaultConfigJson, ownerKey)) {
            vaultConfig.owner = vm.parseJsonAddress(rawVaultConfigJson, ownerKey);
            require(vaultConfig.owner != address(0), "BaseConfigScript: owner override is zero");
        }
        // Limit a new chain to its supported pathways without changing other chains' peer lists.
        string memory peersKey = string.concat(".peerOverrides.", Strings.toString(chainId));
        if (vm.keyExistsJson(rawVaultConfigJson, peersKey)) {
            vaultConfig.peers = vm.parseJsonUintArray(rawVaultConfigJson, peersKey);
        }
        // Prefer the canonical chain-level common config (script/deployment-config/common/<chainId>.json)
        // over the vault file's inline `.common` block — the inline block is a snapshot that goes stale
        // whenever a new common contract (e.g. nestAdapter, nestUnlooper) is added to the chain.
        try vm.readFile(
            string.concat(vm.projectRoot(), "/script/deployment-config/common/", Strings.toString(chainId), ".json")
        ) returns (
            string memory
        ) {
            vaultConfig.common = ConfigReader.readCommonProxyConfig(chainId);
        } catch {}
        _applyBaseAssetOverrides(chainId);
        // Apply vaultType override for the target chain (e.g. NestVaultOFT → NestVault on World Chain).
        // Flips isOFT() so DeployAndSetup/Upgrade pick the matching impl + OFT wiring is skipped.
        try vm.parseJsonString(
            rawVaultConfigJson, string.concat(".vaultTypeOverrides.", Strings.toString(chainId))
        ) returns (
            string memory override_
        ) {
            vaultConfig.vaultType = override_;
        } catch {}
        // Apply per-vault commonOverrides on top of the chain-level common config.
        //   Top-level: `.commonOverrides.<field>`                  (every chain)
        //   Per-chain: `.commonOverrides.<chainId>.<field>`        (wins over top-level)
        // `0x0000…0000` disables a field for wiring checks (e.g. opt out of nestAdapter/nestUnlooper
        // role grants), but DeployAndSetup still treats it as deploy-if-missing; `0xdead` hard-disables.
        _applyCommonOverrides(chainId);
        commonConfig = ConfigReader.readCommonConfig(chainId);
        chainComplianceConfig = ConfigReader.readComplianceConfig(chainId);
        lzConfig = ConfigReader.readLZConfig(chainId);
        CREATEX = ICreateX(commonConfig.createx);
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        try vm.envBool("VERBOSE") returns (bool v) {
            verbose = v;
        } catch {}
    }

    /// @dev Applies the chain's base-asset override and converts the hub-denominated starting
    ///      rate into the selected asset's decimal precision.
    function _applyBaseAssetOverrides(uint256 chainId) internal {
        uint256 hubChainId = ConfigReader.readHubChainId(rawVaultConfigJson);
        string memory hubBaseAssetSymbol = vaultConfig.baseAssetSymbol;
        try vm.parseJsonString(
            rawVaultConfigJson, string.concat(".baseAssetOverrides.", Strings.toString(hubChainId))
        ) returns (
            string memory hubOverride
        ) {
            hubBaseAssetSymbol = hubOverride;
        } catch {}
        try vm.parseJsonString(
            rawVaultConfigJson, string.concat(".baseAssetOverrides.", Strings.toString(chainId))
        ) returns (
            string memory override_
        ) {
            vaultConfig.baseAssetSymbol = override_;
            uint8 hubDecimals = _readAssetDecimals(hubChainId, hubBaseAssetSymbol);
            uint8 targetDecimals = _readAssetDecimals(chainId, override_);
            vaultConfig.accountantParams.startingExchangeRate =
                _scaleRate(vaultConfig.accountantParams.startingExchangeRate, hubDecimals, targetDecimals);
        } catch {}
    }

    /// @dev Reads target-chain assets directly and remote assets through their configured RPC.
    ///      Virtual so config parsing tests can supply deterministic decimal metadata without RPCs.
    function _readAssetDecimals(uint256 chainId, string memory symbol) internal virtual returns (uint8) {
        address asset = ConfigReader.readAssetAddress(chainId, symbol);
        if (chainId == vaultConfig.deployChainId) return ERC20(asset).decimals();

        CommonConfig memory chainConfig = ConfigReader.readCommonConfig(chainId);
        string memory rpcUrl = ConfigReader.resolveRPC(chainConfig);
        bytes memory result = vm.rpc(
            rpcUrl, "eth_call", string.concat('[{"to":"', vm.toString(asset), '","data":"0x313ce567"},"latest"]')
        );
        require(result.length == 32, "BaseConfigScript: invalid decimals response");
        return abi.decode(result, (uint8));
    }

    function _scaleRate(uint96 rate, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint96) {
        if (fromDecimals == toDecimals) return rate;

        uint256 scaled = rate;
        if (toDecimals > fromDecimals) {
            uint256 decimalDelta = uint256(toDecimals - fromDecimals);
            require(decimalDelta <= 77, "BaseConfigScript: decimal scale overflow");
            scaled *= 10 ** decimalDelta;
        } else {
            uint256 decimalDelta = uint256(fromDecimals - toDecimals);
            require(decimalDelta <= 77, "BaseConfigScript: decimal scale overflow");
            uint256 divisor = 10 ** decimalDelta;
            require(scaled % divisor == 0, "BaseConfigScript: decimal scaling loses precision");
            scaled /= divisor;
        }
        require(scaled <= type(uint96).max, "BaseConfigScript: starting exchange rate exceeds uint96");
        return uint96(scaled);
    }

    // ─── Fee launch gate ───────────────────────────────────────────

    /// @dev Vaults whose fees this run bootstrapped: the launch gate is strict only for them.
    address[] internal bootstrappedVaults;

    struct ConfiguredFee {
        uint32 rate;
        uint256 flat;
    }

    /// @dev Applies configured active fees to a vault immediately after deployment, while the
    ///      deployer still owns it and before any user-facing authority capability is opened.
    function _bootstrapVaultFees(address vault, string memory assetSymbol) internal {
        bootstrappedVaults.push(vault);
        if (_feeAssetSkipped(assetSymbol)) return;

        _bootstrapVaultFee(vault, NestVaultCoreTypes.Fees.Deposit, ".vaultFees.deposit", ".vaultMaxFees.deposit");
        _bootstrapVaultFee(
            vault, NestVaultCoreTypes.Fees.Redemption, ".vaultFees.redemption", ".vaultMaxFees.redemption"
        );
        _bootstrapVaultFee(
            vault,
            NestVaultCoreTypes.Fees.InstantRedemption,
            ".vaultFees.instantRedemption",
            ".vaultMaxFees.instantRedemption"
        );
    }

    function _bootstrapVaultFee(
        address vault,
        NestVaultCoreTypes.Fees feeType,
        string memory activePath,
        string memory maxPath
    ) private {
        ConfiguredFee memory active = _configuredFee(activePath);
        if (active.rate == 0 && active.flat == 0) return;

        (uint32 maxRate, uint256 maxFlat) = INestVaultCore(vault).maxFees(feeType);
        if (active.rate > maxRate || active.flat > maxFlat) {
            ConfiguredFee memory configuredMax = _configuredFee(maxPath);
            require(
                configuredMax.rate >= active.rate && configuredMax.flat >= active.flat,
                "BaseConfigScript: active fee exceeds cap; configure vaultMaxFees"
            );
            execute(
                vault,
                abi.encodeCall(
                    INestVaultCore.setMaxFee,
                    (feeType, NestVaultCoreTypes.Fee({rate: configuredMax.rate, flat: configuredMax.flat}))
                ),
                "bootstrap setMaxFee before launch"
            );
        }

        execute(
            vault,
            abi.encodeCall(
                INestVaultCore.setFee, (feeType, NestVaultCoreTypes.Fee({rate: active.rate, flat: active.flat}))
            ),
            "bootstrap setFee before launch"
        );
    }

    /// @dev Launch gate: a vault bootstrapped in this run must carry every configured, non-exempt active
    ///      fee before an authority script opens user-facing capabilities. Already-live vaults only warn:
    ///      their fees converge in the SetupFees step (slot 4), which runs after this script.
    function _requireVaultFeesReadyForLaunch() internal view {
        ConfiguredFee memory deposit = _configuredFee(".vaultFees.deposit");
        ConfiguredFee memory redemption = _configuredFee(".vaultFees.redemption");
        ConfiguredFee memory instantRedemption = _configuredFee(".vaultFees.instantRedemption");
        if (
            deposit.rate == 0 && deposit.flat == 0 && redemption.rate == 0 && redemption.flat == 0
                && instantRedemption.rate == 0 && instantRedemption.flat == 0
        ) return;

        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory entry = vaultConfig.vaults[i];
            if (entry.addr == address(0) || _feeAssetSkipped(entry.assetSymbol)) continue;
            if (!isActive(entry.addr) || entry.addr.code.length == 0) {
                console.log("    [SKIP] launch gate: vault not deployed on this chain -", entry.assetSymbol);
                continue;
            }
            bool strict = _wasBootstrapped(entry.addr);
            _checkFeeLive(entry.addr, NestVaultCoreTypes.Fees.Deposit, deposit, strict);
            _checkFeeLive(entry.addr, NestVaultCoreTypes.Fees.Redemption, redemption, strict);
            _checkFeeLive(entry.addr, NestVaultCoreTypes.Fees.InstantRedemption, instantRedemption, strict);
        }
    }

    function _wasBootstrapped(address vault) private view returns (bool) {
        for (uint256 i = 0; i < bootstrappedVaults.length; i++) {
            if (bootstrappedVaults[i] == vault) return true;
        }
        return false;
    }

    function _checkFeeLive(address vault, NestVaultCoreTypes.Fees feeType, ConfiguredFee memory target, bool strict)
        private
        view
    {
        if (target.rate == 0 && target.flat == 0) return;
        uint32 currentRate;
        uint256 currentFlat;
        try INestVaultCore(vault).fees(feeType) returns (uint32 rate, uint256 flat) {
            currentRate = rate;
            currentFlat = flat;
        } catch {
            // Pre-Fee-struct impl: fees() only exists after the queued upgrade executes.
            console.log(
                "    [LAUNCH GATE] fees() unreadable (impl predates the Fee struct); execute the upgrade first -", vault
            );
            return;
        }
        if (currentRate == target.rate && currentFlat == target.flat) return;
        require(!strict, "BaseConfigScript: configured vault fees must be live before authority setup");
        console.log(
            string.concat(
                "    [LAUNCH GATE] fee mismatch on ",
                vm.toString(vault),
                " feeType=",
                vm.toString(uint256(feeType)),
                ": live=(",
                vm.toString(uint256(currentRate)),
                ",",
                vm.toString(currentFlat),
                ") config=(",
                vm.toString(uint256(target.rate)),
                ",",
                vm.toString(target.flat),
                ") - converges in SetupFees (slot 4); do not route users until it executes"
            )
        );
    }

    function _configuredFee(string memory path) private view returns (ConfiguredFee memory target) {
        uint256 rate;
        try vm.parseJsonUint(rawVaultConfigJson, string.concat(path, ".rate")) returns (uint256 value) {
            rate = value;
        } catch {}
        require(rate <= type(uint32).max, "BaseConfigScript: configured fee rate exceeds uint32");
        target.rate = uint32(rate);
        try vm.parseJsonUint(rawVaultConfigJson, string.concat(path, ".flat")) returns (uint256 value) {
            target.flat = value;
        } catch {}
    }

    /// @dev Union of the SKIP_FEE_ASSET_SYMBOLS env and config `.skipFeeAssetSymbols.<chainId>`, as SetupFees.
    function _feeAssetSkipped(string memory assetSymbol) private view returns (bool) {
        bytes32 assetHash = keccak256(bytes(assetSymbol));
        string[] memory none = new string[](0);
        string[] memory envSkips = vm.envOr("SKIP_FEE_ASSET_SYMBOLS", ",", none);
        for (uint256 i = 0; i < envSkips.length; i++) {
            if (keccak256(bytes(envSkips[i])) == assetHash) return true;
        }
        string[] memory skipped;
        try vm.parseJsonStringArray(
            rawVaultConfigJson, string.concat(".skipFeeAssetSymbols.", Strings.toString(vaultConfig.deployChainId))
        ) returns (
            string[] memory configured
        ) {
            skipped = configured;
        } catch {
            return false;
        }

        for (uint256 i = 0; i < skipped.length; i++) {
            if (keccak256(bytes(skipped[i])) == assetHash) return true;
        }
        return false;
    }

    // ─── Dual-Mode Execution ──────────────────────────────────────────

    /// @notice Routes a call to either broadcast or Safe batch accumulation.
    function execute(address target, bytes memory data) internal {
        execute(target, data, 0, "");
    }

    function execute(address target, bytes memory data, string memory label) internal {
        execute(target, data, 0, label);
    }

    /// @notice Routes a call with ETH value to either broadcast or Safe batch accumulation.
    ///         In hybrid mode, auto-detects ownership: executes directly if deployer is owner,
    ///         otherwise queues for multisig.
    function execute(address target, bytes memory data, uint256 value) internal {
        execute(target, data, value, "");
    }

    function execute(address target, bytes memory data, uint256 value, string memory label) internal {
        if (msigMode || (hybridMode && !_isOwner(target))) {
            serializedTxs.push(SerializedTx({name: label, to: target, value: value, data: data}));
            _logVerbose("[QUEUED]", label);
        } else {
            (bool success,) = target.call{value: value}(data);
            require(success, "BaseConfigScript: execute call failed");
            directTxs.push(SerializedTx({name: label, to: target, value: value, data: data}));
            _logVerbose("[TRUE]", label);
        }
    }

    /// @notice Like execute, but does not revert on failure. Returns true if the call succeeded.
    ///         Useful for idempotent calls that revert when already configured (e.g. LZ_SameValue).
    function tryExecute(address target, bytes memory data) internal returns (bool) {
        return tryExecute(target, data, "");
    }

    function tryExecute(address target, bytes memory data, string memory label) internal returns (bool) {
        if (msigMode || (hybridMode && !_isOwner(target))) {
            serializedTxs.push(SerializedTx({name: label, to: target, value: 0, data: data}));
            _logVerbose("[QUEUED]", label);
            return true;
        } else {
            (bool success,) = target.call(data);
            if (success) directTxs.push(SerializedTx({name: label, to: target, value: 0, data: data}));
            _logVerbose(success ? "[TRUE]" : "[SKIP]", label);
            return success;
        }
    }

    // ─── Verbose Logging ──────────────────────────────────────────────

    function _logVerbose(string memory status, string memory label) internal view {
        if (!verbose || bytes(label).length == 0) return;
        console.log(string.concat("    ", status, " ", label));
    }

    function _logSkipped(string memory label) internal pure {
        console.log(string.concat("    [SKIP] ", label));
    }

    function _logDeploy(string memory label, address addr) internal pure {
        console.log(string.concat("    [DEPLOY] ", label, ": ", vm.toString(addr)));
    }

    function _logExists(string memory label, address addr) internal pure {
        console.log(string.concat("    [EXISTS] ", label, ": ", vm.toString(addr)));
    }

    /// @notice Checks if the deployer can execute directly against the target.
    ///         For the LZ endpoint, checks if the deployer is the delegate for the current OFT context.
    ///         For Auth contracts, checks if the deployer is the owner.
    ///         For non-Auth contracts (no owner() function), returns true.
    function _isOwner(address target) internal view returns (bool) {
        if (target == lzConfig.endpoint) return _isLzDelegate();
        try Auth(target).owner() returns (address ownerAddr) {
            return ownerAddr == deployer();
        } catch {
            return true;
        }
    }

    /// @dev The OFT address whose LZ delegate is being checked. Set before LZ config calls.
    address internal _currentLzOft;

    /// @notice Returns true if the deployer is the LZ delegate (or the OApp itself) for _currentLzOft.
    function _isLzDelegate() internal view returns (bool) {
        if (_currentLzOft == address(0)) return false;
        if (_currentLzOft == deployer()) return true;
        (bool ok, bytes memory ret) =
            lzConfig.endpoint.staticcall(abi.encodeWithSignature("delegates(address)", _currentLzOft));
        if (ok && ret.length >= 32) {
            address delegate = abi.decode(ret, (address));
            return delegate == deployer();
        }
        return false;
    }

    /// @notice Writes accumulated Safe batch to script/output/msig/{chainId}-{symbol}-{scriptName}.json
    function writeMsigBatch(string memory scriptName) internal {
        _logDirectTxs();
        if (serializedTxs.length == 0) return;

        _logQueuedTxs();

        string memory root = vm.projectRoot();
        string memory outputDir = string.concat(root, "/script/output/msig");
        vm.createDir(outputDir, true);
        string memory path = string.concat(
            outputDir, "/", vaultConfig.deployChainId.toString(), "-", vaultConfig.symbol, "-", scriptName, ".json"
        );

        new SafeTxUtil().writeTxs(serializedTxs, path);
    }

    /// @notice Routes a set of owner-authorized calls through a TimelockController as two Safe batches:
    ///         a `scheduleBatch` (appended to the current `serializedTxs`, so it ships alongside any calls
    ///         already queued this run) written as `scheduleName`, and a matching `executeBatch` written as
    ///         `executeName` for the Safe to run after `delay` elapses.
    /// @dev    `predecessor` is 0 and all `values` are 0; `salt` must be stable across the schedule/execute
    ///         pair (and across re-runs) so the operation ids match. Idempotent: skips re-scheduling when the
    ///         op id already exists on the timelock, and skips the execute batch once the op is done.
    function _buildTimelockBatches(
        address timelock,
        address[] memory targets,
        bytes[] memory payloads,
        bytes32 salt,
        uint256 delay,
        string memory scheduleName,
        string memory executeName
    ) internal {
        require(targets.length == payloads.length, "BaseConfigScript: timelock batch length mismatch");
        if (targets.length == 0) {
            console.log("  No timelock operations to schedule");
            writeMsigBatch(scheduleName); // still flush any Phase-1 transfers queued this run
            return;
        }

        uint256[] memory values = new uint256[](targets.length);
        TimelockController tl = TimelockController(payable(timelock));
        bytes32 id = tl.hashOperationBatch(targets, values, payloads, bytes32(0), salt);

        // ── Schedule batch (joins any transfers already in serializedTxs from this run) ──
        if (tl.isOperation(id)) {
            console.log("  Timelock op already scheduled/known, skipping scheduleBatch:", vm.toString(id));
        } else {
            serializedTxs.push(
                SerializedTx({
                    name: "timelock.scheduleBatch",
                    to: timelock,
                    value: 0,
                    data: abi.encodeCall(
                        TimelockController.scheduleBatch, (targets, values, payloads, bytes32(0), salt, delay)
                    )
                })
            );
        }
        writeMsigBatch(scheduleName);

        // ── Execute batch (separate file; the Safe runs it after `delay`) ──
        if (tl.isOperationDone(id)) {
            console.log("  Timelock op already executed, skipping executeBatch");
            return;
        }
        delete serializedTxs;
        serializedTxs.push(
            SerializedTx({
                name: "timelock.executeBatch",
                to: timelock,
                value: 0,
                data: abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, bytes32(0), salt))
            })
        );
        writeMsigBatch(executeName);
    }

    /// @notice Writes accumulated Safe batch for chain-scoped (symbol-independent) operations.
    function writeMsigBatchForChain(uint256 chainId, string memory scriptName) internal {
        if (serializedTxs.length == 0) return;

        _logQueuedTxs();

        string memory root = vm.projectRoot();
        string memory outputDir = string.concat(root, "/script/output/msig");
        vm.createDir(outputDir, true);
        string memory path = string.concat(outputDir, "/", chainId.toString(), "-", scriptName, ".json");

        new SafeTxUtil().writeTxs(serializedTxs, path);
    }

    /// @notice Logs a human-readable summary of all queued multisig transactions.
    function _logQueuedTxs() internal view {
        console.log("");
        console.log(
            string.concat("=== Queued Multisig Transactions (", vm.toString(serializedTxs.length), " total) ===")
        );
        for (uint256 i = 0; i < serializedTxs.length; i++) {
            SerializedTx memory tx_ = serializedTxs[i];
            string memory label = bytes(tx_.name).length > 0 ? tx_.name : "unlabeled";
            string memory line = string.concat("  [", vm.toString(i), "] ", label, " -> ", vm.toString(tx_.to));
            if (tx_.value > 0) {
                line = string.concat(line, " (value: ", vm.toString(tx_.value), ")");
            }
            console.log(line);
        }
        console.log("==============================================");
        console.log("");
    }

    /// @notice Logs the calls executed directly via broadcast (or simulated in dry-run).
    ///         Mirrors `_logQueuedTxs` so hybrid runs make routing visible without VERBOSE.
    function _logDirectTxs() internal view {
        if (directTxs.length == 0) return;

        console.log("");
        console.log(string.concat("=== Directly Executed Transactions (", vm.toString(directTxs.length), " total) ==="));
        for (uint256 i = 0; i < directTxs.length; i++) {
            SerializedTx memory tx_ = directTxs[i];
            string memory label = bytes(tx_.name).length > 0 ? tx_.name : "unlabeled";
            string memory line = string.concat("  [", vm.toString(i), "] ", label, " -> ", vm.toString(tx_.to));
            if (tx_.value > 0) {
                line = string.concat(line, " (value: ", vm.toString(tx_.value), ")");
            }
            console.log(line);
        }
        console.log("==============================================");
        console.log("");
    }

    /// @notice Modifier that wraps execution in either broadcast or msig accumulation mode.
    modifier directOrMsig(bool _msigMode) {
        msigMode = _msigMode;
        if (!_msigMode) {
            vm.startBroadcast(deployerPrivateKey);
        }
        _;
        if (!_msigMode) {
            vm.stopBroadcast();
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    function shouldDeploy(address addr) internal pure returns (bool) {
        return ConfigReader.shouldDeploy(addr);
    }

    /// @notice Returns true when a fresh deployment is needed on this chain.
    ///         True for address(0) (never set), false for DEAD (disabled),
    ///         and checks on-chain code existence for deterministic addresses.
    function needsDeploy(address addr) internal view returns (bool) {
        if (addr == address(0)) return true;
        if (isDisabled(addr)) return false;
        return addr.code.length == 0;
    }

    function isDisabled(address addr) internal pure returns (bool) {
        return ConfigReader.isDisabled(addr);
    }

    function isActive(address addr) internal pure returns (bool) {
        return ConfigReader.isActive(addr);
    }

    function isOFT() internal view returns (bool) {
        return ConfigReader.isOFT(vaultConfig.vaultType);
    }

    /// @notice True when this run deploys on the shared ComplianceProxy only: forced chain-wide by
    ///         config/compliance/<chainId>.json or opted in per vault through compliance.v2Only.
    function isV2Only() internal view returns (bool) {
        return chainComplianceConfig.v2Only || vaultConfig.compliance.v2Only;
    }

    /// @notice Resolves the accountant impl name to use for the loaded chain.
    ///         See `ConfigReader.effectiveAccountantType` for the resolution rules.
    function effectiveAccountantType() internal view returns (string memory) {
        return ConfigReader.effectiveAccountantType(rawVaultConfigJson, vaultConfig.deployChainId);
    }

    /// @dev Reads an address from `commonOverrides` for `field`, preferring the per-chain
    ///      key over the top-level key. Returns `fallback_` when neither is present.
    function _commonOverride(string memory field, uint256 chainId, address fallback_) internal view returns (address) {
        return ConfigReader.effectiveCommonAddress(rawVaultConfigJson, field, chainId, fallback_);
    }

    /// @dev Overlays per-vault `commonOverrides` (runtime-only, never persisted). `0x0` disables a field
    ///      for wiring checks, but DeployAndSetup still treats it as deploy-if-missing — `0xdead` hard-disables.
    function _applyCommonOverrides(uint256 chainId) internal {
        CommonContracts memory c = vaultConfig.common;
        commonCanonical = c;
        commonOverridesApplied = true;
        c.predicateProxy = _commonOverride("predicateProxy", chainId, c.predicateProxy);
        c.complianceProxy = _commonOverride("complianceProxy", chainId, c.complianceProxy);
        c.operatorRegistry = _commonOverride("operatorRegistry", chainId, c.operatorRegistry);
        c.redeemOperator = _commonOverride("redeemOperator", chainId, c.redeemOperator);
        c.cctpRelayer = _commonOverride("cctpRelayer", chainId, c.cctpRelayer);
        c.seizer = _commonOverride("seizer", chainId, c.seizer);
        c.blacklistHook = _commonOverride("blacklistHook", chainId, c.blacklistHook);
        c.commonRolesAuthority = _commonOverride("commonRolesAuthority", chainId, c.commonRolesAuthority);
        c.nestAdapter = _commonOverride("nestAdapter", chainId, c.nestAdapter);
        c.nestBundler = _commonOverride("nestBundler", chainId, c.nestBundler);
        c.nestUnlooper = _commonOverride("nestUnlooper", chainId, c.nestUnlooper);
        c.protocolTimelock = _commonOverride("protocolTimelock", chainId, c.protocolTimelock);
        c.adminTimelock = _commonOverride("adminTimelock", chainId, c.adminTimelock);
        vaultConfig.common = c;
    }

    /// @dev True when a relayer (or other common field) was explicitly overridden for this vault.
    ///      Needed when merging deployment output so an explicit zero/disabled override remains authoritative.
    function _hasCommonOverride(string memory field, uint256 chainId) internal view returns (bool) {
        string memory chainKey = string.concat(".commonOverrides.", Strings.toString(chainId), ".", field);
        try vm.parseJsonAddress(rawVaultConfigJson, chainKey) returns (address) {
            return true;
        } catch {}
        try vm.parseJsonAddress(rawVaultConfigJson, string.concat(".commonOverrides.", field)) returns (address) {
            return true;
        } catch {}
        return false;
    }

    /// @notice Fills missing runtime addresses from the standard deployment output artifact.
    /// @dev Reviewed input and explicit disable/override values win. Vault entries are matched by asset symbol.
    function overlayDeploymentOutput() internal returns (bool exists) {
        VaultDeployConfig memory output;
        (exists, output) = ConfigReader.tryReadOutputConfig(vaultConfig.deployChainId, vaultConfig.symbol);
        if (!exists) return false;

        if (vaultConfig.contracts.share == address(0)) vaultConfig.contracts.share = output.contracts.share;
        if (vaultConfig.contracts.accountant == address(0)) {
            vaultConfig.contracts.accountant = output.contracts.accountant;
        }
        if (vaultConfig.contracts.rolesAuthority == address(0)) {
            vaultConfig.contracts.rolesAuthority = output.contracts.rolesAuthority;
        }

        if (
            vaultConfig.common.cctpRelayer == address(0)
                && !_hasCommonOverride("cctpRelayer", vaultConfig.deployChainId) && isActive(output.common.cctpRelayer)
        ) {
            vaultConfig.common.cctpRelayer = output.common.cctpRelayer;
        }

        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            bytes32 symbolHash = keccak256(bytes(vaultConfig.vaults[i].assetSymbol));
            for (uint256 j = 0; j < output.vaults.length; j++) {
                if (keccak256(bytes(output.vaults[j].assetSymbol)) != symbolHash) continue;
                if (vaultConfig.vaults[i].addr == address(0)) {
                    vaultConfig.vaults[i].addr = output.vaults[j].addr;
                }
                if (vaultConfig.vaults[i].composer == address(0) && isActive(output.vaults[j].composer)) {
                    vaultConfig.vaults[i].composer = output.vaults[j].composer;
                }
                break;
            }
        }
    }

    function deployer() internal view returns (address) {
        return vm.addr(deployerPrivateKey);
    }

    /// @notice Generates a deterministic CREATE3 salt from deployer address and a component name.
    ///         Checks `saltOverrides.{component}` in the vault config JSON first.
    function generateCreate3Salt(string memory component) internal view returns (bytes32) {
        bytes32 override_ = _tryReadSaltOverride(component);
        if (override_ != bytes32(0)) return override_;
        string memory saltString = string.concat(component, "-", vaultConfig.symbol);
        return bytes32(abi.encodePacked(deployer(), hex"00", bytes11(keccak256(bytes(saltString)))));
    }

    /// @notice Generates a deterministic CREATE3 salt for common (vault-agnostic) contracts.
    ///         Checks `saltOverrides.{component}` in the vault config JSON first.
    function generateCreate3SaltCommon(string memory component) internal view returns (bytes32) {
        bytes32 override_ = _tryReadSaltOverride(component);
        if (override_ != bytes32(0)) return override_;
        return bytes32(abi.encodePacked(deployer(), hex"00", bytes11(keccak256(bytes(component)))));
    }

    /// @notice Generates a deterministic CREATE3 salt that includes the deposit asset symbol.
    ///         Checks `saltOverrides.{component}-{assetSymbol}` in the vault config JSON first.
    function generateCreate3SaltForAsset(string memory component, string memory assetSymbol)
        internal
        view
        returns (bytes32)
    {
        bytes32 override_ = _tryReadSaltOverride(string.concat(component, "-", assetSymbol));
        if (override_ != bytes32(0)) return override_;
        string memory saltString = string.concat(component, "-", vaultConfig.symbol, "-", assetSymbol);
        return bytes32(abi.encodePacked(deployer(), hex"00", bytes11(keccak256(bytes(saltString)))));
    }

    /// @dev Reads an optional salt override from `saltOverrides.{key}` in the vault config JSON.
    function _tryReadSaltOverride(string memory key) internal view returns (bytes32) {
        try vm.parseJsonBytes32(rawVaultConfigJson, string.concat(".saltOverrides.", key)) returns (bytes32 salt) {
            console.log(string.concat("  [SALT OVERRIDE] ", key));
            return salt;
        } catch {
            return bytes32(0);
        }
    }

    /// @notice Computes the expected CREATE3 address for a component.
    function computeCreate3Address(string memory component) internal view returns (address) {
        bytes32 salt = generateCreate3Salt(component);
        return _computeCreate3Address(salt);
    }

    /// @notice Computes the expected CREATE3 address for a common (vault-agnostic) component.
    function computeCreate3AddressCommon(string memory component) internal view returns (address) {
        bytes32 salt = generateCreate3SaltCommon(component);
        return _computeCreate3Address(salt);
    }

    /// @notice Computes the expected CREATE3 address for an asset-specific component.
    function computeCreate3AddressForAsset(string memory component, string memory assetSymbol)
        internal
        view
        returns (address)
    {
        bytes32 salt = generateCreate3SaltForAsset(component, assetSymbol);
        return _computeCreate3Address(salt);
    }

    /// @dev Mirrors CreateX.deployCreate3 salt guarding so local verification matches on-chain deployment.
    function _computeCreate3Address(bytes32 salt) internal view returns (address) {
        return CREATEX.computeCreate3Address(_guardCreate3Salt(salt), commonConfig.createx);
    }

    /// @dev Reproduces the deterministic branches of CreateX._guard using the broadcast deployer as msg.sender.
    function _guardCreate3Salt(bytes32 salt) internal view returns (bytes32 guardedSalt) {
        address deployerAddr = deployer();
        address saltSender = address(bytes20(salt));
        bytes1 redeployProtectionFlag = bytes1(salt[20]);

        if (saltSender == deployerAddr && redeployProtectionFlag == hex"01") {
            return keccak256(abi.encode(deployerAddr, block.chainid, salt));
        }
        if (saltSender == deployerAddr && redeployProtectionFlag == hex"00") {
            return keccak256(abi.encodePacked(bytes32(uint256(uint160(deployerAddr))), salt));
        }
        if (saltSender == deployerAddr) {
            revert("BaseConfigScript: invalid CREATE3 salt");
        }
        if (saltSender == address(0) && redeployProtectionFlag == hex"01") {
            return keccak256(abi.encodePacked(bytes32(block.chainid), salt));
        }
        if (saltSender == address(0) && redeployProtectionFlag != hex"00") {
            revert("BaseConfigScript: invalid CREATE3 salt");
        }

        // The script only uses explicit deterministic salts, so all remaining cases map to CreateX's
        // non-pseudo-random branch, which hashes the provided salt before deriving the CREATE3 address.
        return keccak256(abi.encode(salt));
    }

    // ─── Reference Output Verification ──────────────────────────────────

    /// @notice Verifies that all CREATE3 addresses match a reference deployment output.
    ///         Set REFERENCE_CHAIN_ID env var to the chain ID of the reference deployment.
    ///         Skips verification if REFERENCE_CHAIN_ID is not set (first deployment).
    function verifyCreate3Addresses() internal view {
        uint256 refChainId;
        try vm.envUint("REFERENCE_CHAIN_ID") returns (uint256 id) {
            refChainId = id;
        } catch {
            return; // No reference — first deployment, skip verification
        }

        console.log("=== Verifying CREATE3 addresses against reference chain", refChainId, "===");

        VaultDeployConfig memory ref = ConfigReader.readOutputConfig(refChainId, vaultConfig.symbol);

        // Core vault stack
        _verifyAddress("RolesAuthority", computeCreate3Address("RolesAuthority"));
        _verifyAddress("CommonRolesAuthority", computeCreate3AddressCommon("Nest RolesAuthority"));
        _verifyMatch("NestShareOFT", computeCreate3Address("NestShareOFT"), ref.contracts.share);
        _verifyMatch("NestAccountant", computeCreate3Address("NestAccountant"), ref.contracts.accountant);
        _verifyMatch("BlacklistHook", computeCreate3AddressCommon("BlacklistHook"), ref.common.blacklistHook);
        _verifyMatch(
            "NestVaultPredicateProxy", computeCreate3AddressCommon("NestVaultPredicateProxy"), ref.common.predicateProxy
        );

        // Vaults (per asset)
        string memory vaultComponent = ConfigReader.isOFT(vaultConfig.vaultType) ? "NestVaultOFT" : "NestVault";
        for (uint256 i = 0; i < ref.vaults.length; i++) {
            VaultEntry memory ve = ref.vaults[i];
            if (!isActive(ve.addr)) continue;
            _verifyMatch(
                string.concat(vaultComponent, "-", ve.assetSymbol),
                computeCreate3AddressForAsset(vaultComponent, ve.assetSymbol),
                ve.addr
            );
        }

        // Operators
        _verifyMatch("OperatorRegistry", computeCreate3AddressCommon("OperatorRegistry"), ref.common.operatorRegistry);
        _verifyMatch(
            "NestVaultRedeemOperator", computeCreate3AddressCommon("NestVaultRedeemOperator"), ref.common.redeemOperator
        );
        _verifyMatch("NestShareSeizer", computeCreate3AddressCommon("NestShareSeizer"), ref.common.seizer);

        // Composers
        _verifyMatch("NestCCTPRelayer", computeCreate3AddressCommon("NestCCTPRelayer"), ref.common.cctpRelayer);
        for (uint256 i = 0; i < ref.vaults.length; i++) {
            VaultEntry memory ve = ref.vaults[i];
            if (!isActive(ve.composer)) continue;
            _verifyMatch(
                string.concat("NestVaultComposer-", ve.assetSymbol),
                computeCreate3AddressForAsset("NestVaultComposer", ve.assetSymbol),
                ve.composer
            );
        }

        console.log("=== All CREATE3 addresses verified ===");
    }

    function _verifyAddress(string memory name, address computed) internal pure {
        require(computed != address(0), string.concat("BaseConfigScript: zero address for ", name));
    }

    function _verifyMatch(string memory name, address computed, address expected) internal view {
        if (expected == address(0) || expected == ConfigReader.DEAD_ADDRESS) return;
        // Skip verification if the contract is already deployed at the expected address —
        // no CREATE3 deployment will occur, so the computed address is irrelevant.
        if (expected.code.length > 0) return;
        require(computed == expected, string.concat("BaseConfigScript: address mismatch for ", name));
    }

    // ─── Standard Deployment Output ────────────────────────────────────

    /// @notice Resolves the vault-specific RolesAuthority for deployment output.
    ///         Defaults to config and falls back to the authority currently installed on the share.
    function _resolveRolesAuthority() internal view virtual returns (address) {
        if (vaultConfig.contracts.rolesAuthority != address(0)) return vaultConfig.contracts.rolesAuthority;
        if (vaultConfig.contracts.share.code.length > 0) {
            return address(Auth(vaultConfig.contracts.share).authority());
        }
        return address(0);
    }

    /// @notice Writes the standard deployment artifact consumed by setup and ownership scripts.
    /// @dev Writes only under script/output; reviewed deployment input JSON is never mutated.
    function writeDeploymentOutput() internal {
        string memory obj = "out";

        vm.serializeString(obj, "symbol", vaultConfig.symbol);
        vm.serializeString(obj, "name", vaultConfig.name);
        vm.serializeUint(obj, "deployChainId", vaultConfig.deployChainId);
        vm.serializeString(obj, "baseAssetSymbol", vaultConfig.baseAssetSymbol);
        vm.serializeString(obj, "vaultType", vaultConfig.vaultType);

        string memory contracts = "contracts_obj";
        vm.serializeAddress(contracts, "share", vaultConfig.contracts.share);
        vm.serializeAddress(contracts, "accountant", vaultConfig.contracts.accountant);
        string memory contractsJson = vm.serializeAddress(contracts, "rolesAuthority", _resolveRolesAuthority());
        vm.serializeString(obj, "contracts", contractsJson);

        string memory common = "common_obj";
        vm.serializeAddress(common, "predicateProxy", vaultConfig.common.predicateProxy);
        vm.serializeAddress(common, "complianceProxy", vaultConfig.common.complianceProxy);
        vm.serializeAddress(common, "operatorRegistry", vaultConfig.common.operatorRegistry);
        vm.serializeAddress(common, "redeemOperator", vaultConfig.common.redeemOperator);
        vm.serializeAddress(common, "cctpRelayer", vaultConfig.common.cctpRelayer);
        vm.serializeAddress(common, "seizer", vaultConfig.common.seizer);
        vm.serializeAddress(common, "blacklistHook", vaultConfig.common.blacklistHook);
        vm.serializeAddress(common, "nestAdapter", vaultConfig.common.nestAdapter);
        vm.serializeAddress(common, "nestBundler", vaultConfig.common.nestBundler);
        vm.serializeAddress(common, "nestUnlooper", vaultConfig.common.nestUnlooper);
        vm.serializeAddress(common, "commonRolesAuthority", _resolveCommonRolesAuthority());
        vm.serializeAddress(common, "protocolTimelock", vaultConfig.common.protocolTimelock);
        string memory commonJson = vm.serializeAddress(common, "adminTimelock", vaultConfig.common.adminTimelock);
        vm.serializeString(obj, "common", commonJson);

        string memory ap = "ap_obj";
        vm.serializeUint(ap, "totalSharesLastUpdate", vaultConfig.accountantParams.totalSharesLastUpdate);
        vm.serializeAddress(ap, "payoutAddress", vaultConfig.accountantParams.payoutAddress);
        vm.serializeUint(ap, "startingExchangeRate", vaultConfig.accountantParams.startingExchangeRate);
        vm.serializeUint(
            ap, "allowedExchangeRateChangeUpper", vaultConfig.accountantParams.allowedExchangeRateChangeUpper
        );
        vm.serializeUint(
            ap, "allowedExchangeRateChangeLower", vaultConfig.accountantParams.allowedExchangeRateChangeLower
        );
        vm.serializeUint(ap, "minimumUpdateDelayInSeconds", vaultConfig.accountantParams.minimumUpdateDelayInSeconds);
        string memory apJson = vm.serializeUint(ap, "managementFee", vaultConfig.accountantParams.managementFee);
        vm.serializeString(obj, "accountantParams", apJson);

        string memory vp = "vp_obj";
        string memory vpJson = vm.serializeUint(vp, "minRate", vaultConfig.minRate);
        vm.serializeString(obj, "vaultParams", vpJson);

        string memory v1Json = vm.serializeString("compliance_v1_obj", "policyID", vaultConfig.compliance.v1.policyID);
        string memory v2Json =
            vm.serializeString("compliance_v2_obj", "verificationHash", vaultConfig.compliance.v2.verificationHash);
        vm.serializeString("compliance_obj", "v1", v1Json);
        // Written only when set so V1 vault outputs keep their existing shape.
        if (vaultConfig.compliance.v2Only) vm.serializeBool("compliance_obj", "v2Only", true);
        string memory complianceJson = vm.serializeString("compliance_obj", "v2", v2Json);
        vm.serializeString(obj, "compliance", complianceJson);

        string memory cp = "cp_obj";
        string memory cpJson = vm.serializeUint(cp, "maxRetryableValue", vaultConfig.maxRetryableValue);
        vm.serializeString(obj, "composerParams", cpJson);

        string memory roles = "roles_obj";
        vm.serializeAddress(obj, "owner", ConfigReader.resolvedOwner(vaultConfig));
        vm.serializeAddress(roles, "KEEPER_ROLE", vaultConfig.roles.KEEPER_ROLE);
        vm.serializeAddress(roles, "UPDATE_EXCHANGE_RATE_ROLE", vaultConfig.roles.UPDATE_EXCHANGE_RATE_ROLE);
        vm.serializeAddress(roles, "MANAGER_ROLE", vaultConfig.roles.MANAGER_ROLE);
        string memory rolesJson = vm.serializeAddress(roles, "CAN_SOLVE_ROLE", vaultConfig.roles.CAN_SOLVE_ROLE);
        vm.serializeString(obj, "roles", rolesJson);

        string memory finalJson = vm.serializeUint(obj, "peers", vaultConfig.peers);

        string memory root = vm.projectRoot();
        string memory dir = string.concat(root, "/script/output/", vaultConfig.symbol);
        string memory path =
            string.concat(dir, "/", vaultConfig.deployChainId.toString(), "-", vaultConfig.symbol, ".json");
        vm.createDir(dir, true);
        vm.writeJson(finalJson, path);

        string memory vaultsArray = "[";
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            string memory veKey = string.concat("ve_obj_", vm.toString(i));
            vm.serializeString(veKey, "assetSymbol", vaultConfig.vaults[i].assetSymbol);
            vm.serializeAddress(veKey, "address", vaultConfig.vaults[i].addr);
            vm.serializeBool(veKey, "isPegged", vaultConfig.vaults[i].isPegged);
            vm.serializeAddress(veKey, "rateProvider", vaultConfig.vaults[i].rateProvider);
            vm.serializeAddress(veKey, "composer", vaultConfig.vaults[i].composer);
            string memory veJson = vm.serializeAddress(veKey, "legacyTeller", vaultConfig.vaults[i].legacyTeller);
            if (i > 0) vaultsArray = string.concat(vaultsArray, ",");
            vaultsArray = string.concat(vaultsArray, veJson);
        }
        vaultsArray = string.concat(vaultsArray, "]");
        vm.writeJson(vaultsArray, path, ".contracts.vaults");

        console.log("Output written to:", path);
    }

    // ─── Common Config Snapshot & Writer ────────────────────────────────

    /// @notice Captures `vaultConfig.common` so subsequent writers can detect changes.
    function snapshotCommon() internal {
        commonSnapshot = vaultConfig.common;
        // Chain-level scripts (DeployMorpho/DeployTimelock) apply no overrides: canonical == effective.
        if (!commonOverridesApplied) commonCanonical = vaultConfig.common;
    }

    /// @notice Resolves the common RolesAuthority address.
    ///         Defaults to the config field, falling back to predicateProxy.authority().
    ///         Subclasses may override to layer in locally-deployed overrides.
    function _resolveCommonRolesAuthority() internal view virtual returns (address) {
        if (vaultConfig.common.commonRolesAuthority != address(0)) return vaultConfig.common.commonRolesAuthority;
        if (vaultConfig.common.predicateProxy.code.length > 0) {
            return address(Auth(vaultConfig.common.predicateProxy).authority());
        }
        return address(0);
    }

    /// @notice Persists the canonical common config for the current chain when any field changed.
    ///         Source of truth for `script/deployment-config/common/<chainId>.json`.
    function writeCommonConfigIfChanged() internal {
        if (keccak256(abi.encode(vaultConfig.common)) == keccak256(abi.encode(commonSnapshot))) return;
        // Canonical (pre-override) values plus only the fields this run mutated (fresh deploys);
        // per-vault overrides are runtime-only and never reach the canonical file.
        CommonContracts memory cur = vaultConfig.common;
        CommonContracts memory s = commonSnapshot;
        CommonContracts memory c = commonCanonical;

        string memory cObj = "common_config";
        vm.serializeUint(cObj, "chainId", vaultConfig.deployChainId);
        vm.serializeAddress(cObj, "predicateProxy", _pick(cur.predicateProxy, s.predicateProxy, c.predicateProxy));
        vm.serializeAddress(cObj, "complianceProxy", _pick(cur.complianceProxy, s.complianceProxy, c.complianceProxy));
        vm.serializeAddress(
            cObj, "operatorRegistry", _pick(cur.operatorRegistry, s.operatorRegistry, c.operatorRegistry)
        );
        vm.serializeAddress(cObj, "redeemOperator", _pick(cur.redeemOperator, s.redeemOperator, c.redeemOperator));
        vm.serializeAddress(cObj, "cctpRelayer", _pick(cur.cctpRelayer, s.cctpRelayer, c.cctpRelayer));
        vm.serializeAddress(cObj, "seizer", _pick(cur.seizer, s.seizer, c.seizer));
        vm.serializeAddress(cObj, "blacklistHook", _pick(cur.blacklistHook, s.blacklistHook, c.blacklistHook));
        vm.serializeAddress(cObj, "nestAdapter", _pick(cur.nestAdapter, s.nestAdapter, c.nestAdapter));
        vm.serializeAddress(cObj, "nestBundler", _pick(cur.nestBundler, s.nestBundler, c.nestBundler));
        vm.serializeAddress(cObj, "nestUnlooper", _pick(cur.nestUnlooper, s.nestUnlooper, c.nestUnlooper));
        vm.serializeAddress(
            cObj,
            "commonRolesAuthority",
            _pick(_resolveCommonRolesAuthority(), s.commonRolesAuthority, c.commonRolesAuthority)
        );
        vm.serializeAddress(
            cObj, "protocolTimelock", _pick(cur.protocolTimelock, s.protocolTimelock, c.protocolTimelock)
        );
        string memory cJson =
            vm.serializeAddress(cObj, "adminTimelock", _pick(cur.adminTimelock, s.adminTimelock, c.adminTimelock));

        string memory root = vm.projectRoot();
        string memory cDir = string.concat(root, "/script/deployment-config/common");
        string memory cPath = string.concat(cDir, "/", vaultConfig.deployChainId.toString(), ".json");
        vm.createDir(cDir, true);
        vm.writeJson(cJson, cPath);
        console.log("Common config written to:", cPath);
    }

    /// @dev This run changed the field → persist the new value; else keep the canonical one.
    function _pick(address cur, address snap, address canon) private pure returns (address) {
        return cur != snap ? cur : canon;
    }
}
