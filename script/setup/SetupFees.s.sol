// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";

import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {NestVaultCoreTypes} from "contracts/types/NestVaultCoreTypes.sol";
import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";

import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";

/// @title  SetupFees
/// @notice Applies vault fee config (per-type rate + flat) and accountant fee config
///         (management + performance) from `script/deployment-config/vaults/<symbol>.json`.
/// @dev    Fees are read directly from the raw vault config JSON to keep the shared
///         ConfigReader/VaultDeployConfig layout (which is already at the IR stack
///         pressure limit) unchanged.
///
///         JSON layout consumed:
///           accountantParams.managementFee   uint32, 1e6 = 100%
///           accountantParams.performanceFee  uint32, 1e6 = 100% (optional, defaults to 0)
///           accountantParams.hurdleRate      uint32, 1e6 = 100% annualized (optional, defaults to 0)
///           accountantParams.highWaterMark   uint96, base terms (optional). When unset/0 the HWM is
///                                            left as-is — enabling a performance fee already seeds it
///                                            to the live gross rate, so an explicit pin is only needed
///                                            to override that with a specific value.
///           vaultFees.deposit.rate           uint32, 1e6 = 100% (optional)
///           vaultFees.deposit.flat           uint256, asset smallest units (optional)
///           vaultFees.redemption.rate        uint32 (optional)
///           vaultFees.redemption.flat        uint256 (optional)
///           vaultFees.instantRedemption.rate uint32 (optional)
///           vaultFees.instantRedemption.flat uint256 (optional)
///           vaultMaxFees.<type>.rate         uint32  (optional) — fee CAP, only set when present
///           vaultMaxFees.<type>.flat         uint256 (optional) — fee CAP, only set when present
///           skipFeeAssetSymbols.<chainId>    string[] (optional) — asset symbols whose vault
///                                            entries are skipped for the vault-fee pass on that
///                                            chain (unions with the SKIP_FEE_ASSET_SYMBOLS env)
///
///         Active fees (`vaultFees`) drive `setFee` ONLY — this script never derives or
///         tightens a fee cap from the active fee. A cap (`maxFee`) is changed only when an
///         explicit `vaultMaxFees.<type>` entry is present, via `setMaxFee`. When both are
///         queued for the same type, a cap RAISE is sent before `setFee` and a cap LOWER
///         after it, so maxFee >= activeFee holds across the transition. A `setFee` whose
///         target would exceed the effective cap (e.g. a flat fee above the default 0 flat
///         cap, with no `vaultMaxFees` raise) is skipped with a warning rather than queued
///         to revert on-chain. Idempotent: skips calls whose on-chain state already matches.
///
///         Inputs (env):
///           VAULT_SYMBOL           — vault config to apply (required)
///           CHAIN_ID               — target chain (required)
///           SKIP_FEE_ASSET_SYMBOLS — optional comma-separated asset symbols whose vault
///                                    entries are skipped for the vault-fee pass (accountant
///                                    fees are unaffected). Unions with the per-chain config
///                                    field `skipFeeAssetSymbols.<chainId>`; empty/unset on both
///                                    applies to all vaults. e.g. SKIP_FEE_ASSET_SYMBOLS=USDC,XUPL
///           FEE_FORCE_SETFEE       — optional bool (default false). When true, queue setFee(target)
///                                    without reading current on-chain fees (idempotency skipped) and
///                                    without any setMaxFee (caps are deferred to a later state-aware
///                                    run). For vaults on a pre-Fee-struct impl whose fees() reverts,
///                                    where an upgrade queued AHEAD of this batch makes them fee-aware
///                                    (maxFee >= target) before this setFee executes.
///
///         Usage:
///           VAULT_SYMBOL=nTEST CHAIN_ID=98866 \
///             forge script script/setup/SetupFees.s.sol --sig "runDirect()" --rpc-url $RPC --broadcast
///           VAULT_SYMBOL=nTEST CHAIN_ID=98866 \
///             forge script script/setup/SetupFees.s.sol --sig "runMsig()" --rpc-url $RPC
contract SetupFees is BaseConfigScript {
    using stdJson for string;

    struct FeeTarget {
        uint32 rate;
        uint256 flat;
    }

    string[] private skipAssetSymbols;
    bool internal forceSetFee;

    function setUp() public {
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");
        loadConfigs(vaultSymbol);
        // Asset symbols whose vault entries are excluded from the vault-fee pass (setFee/
        // setMaxFee only — accountant fees are unaffected). Union of two sources, either of
        // which may be empty:
        //   - env  SKIP_FEE_ASSET_SYMBOLS  (comma-separated), and
        //   - config `.skipFeeAssetSymbols.<chainId>` (string array) for the target chain.
        // The config form lets a per-chain policy (e.g. "no instant-redemption fee on the
        // USDC vault on Plume") live in the vault config instead of relying on every caller
        // passing the right env. Unset/absent on both => no vault is skipped.
        string[] memory none = new string[](0);
        string[] memory envSkips = vm.envOr("SKIP_FEE_ASSET_SYMBOLS", ",", none);
        for (uint256 i = 0; i < envSkips.length; i++) {
            skipAssetSymbols.push(envSkips[i]);
        }
        try vm.parseJsonStringArray(
            rawVaultConfigJson, string.concat(".skipFeeAssetSymbols.", vm.toString(uint256(vaultConfig.deployChainId)))
        ) returns (
            string[] memory cfgSkips
        ) {
            for (uint256 i = 0; i < cfgSkips.length; i++) {
                skipAssetSymbols.push(cfgSkips[i]);
            }
        } catch {}
        // When true, queue setFee(target) without reading current on-chain fees.
        // For vaults on a pre-Fee-struct impl whose fees() reverts, paired with a
        // separately-queued upgrade that executes before this batch.
        forceSetFee = vm.envOr("FEE_FORCE_SETFEE", false);
    }

    function runDirect() external {
        _setup(false);
        _logDirectTxs();
    }

    function runMsig() external {
        _setup(true);
        writeMsigBatch("SetupFees");
    }

    function run() external {
        hybridMode = true;
        _setup(false);
        writeMsigBatch("SetupFees");
    }

    function _setup(bool _msigMode) internal directOrMsig(_msigMode) {
        _applyVaultFees();
        _applyAccountantFees();
    }

    // ─── Vault fees ───────────────────────────────────────────────────

    function _applyVaultFees() internal {
        FeeTarget memory dep = _readFeeTarget(".vaultFees.deposit");
        FeeTarget memory red = _readFeeTarget(".vaultFees.redemption");
        FeeTarget memory inst = _readFeeTarget(".vaultFees.instantRedemption");
        // Optional, separate fee-CAP config. Absent/zero (rate==0 && flat==0) => the cap is
        // left untouched; only an explicit entry here ever triggers setMaxFee.
        FeeTarget memory depMax = _readFeeTarget(".vaultMaxFees.deposit");
        FeeTarget memory redMax = _readFeeTarget(".vaultMaxFees.redemption");
        FeeTarget memory instMax = _readFeeTarget(".vaultMaxFees.instantRedemption");

        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            address vault = vaultConfig.vaults[i].addr;
            if (!isActive(vault)) continue;
            // A config may list a vault entry on a chain where it isn't deployed yet
            // (the `chains` array is the intended peer set). Reading fees() there would
            // revert on a non-contract address — skip instead.
            if (vault.code.length == 0) {
                _logSkipped(
                    string.concat("fees: no code at ", vm.toString(vault), ", skipping (not deployed on this chain)")
                );
                continue;
            }
            string memory assetSymbol = vaultConfig.vaults[i].assetSymbol;
            if (_isSkippedAsset(assetSymbol)) {
                _logSkipped(
                    string.concat(
                        "fees: asset ", assetSymbol, " in fee-skip list (env/config), skipping ", vm.toString(vault)
                    )
                );
                continue;
            }
            _applyFeeForType(vault, NestVaultCoreTypes.Fees.Deposit, dep, depMax, "Deposit");
            _applyFeeForType(vault, NestVaultCoreTypes.Fees.Redemption, red, redMax, "Redemption");
            _applyFeeForType(vault, NestVaultCoreTypes.Fees.InstantRedemption, inst, instMax, "InstantRedemption");
        }
    }

    /// @notice True when `assetSymbol` is listed in SKIP_FEE_ASSET_SYMBOLS (case-sensitive, exact match).
    function _isSkippedAsset(string memory assetSymbol) internal view returns (bool) {
        bytes32 target = keccak256(bytes(assetSymbol));
        for (uint256 i = 0; i < skipAssetSymbols.length; i++) {
            if (keccak256(bytes(skipAssetSymbols[i])) == target) return true;
        }
        return false;
    }

    /// @param active the target ACTIVE fee from `vaultFees.<type>` (drives setFee)
    /// @param max    the target fee CAP from `vaultMaxFees.<type>` (drives setMaxFee). A (0,0)
    ///               value means "no cap config" — the on-chain maxFee is left untouched.
    function _applyFeeForType(
        address vault,
        NestVaultCoreTypes.Fees f,
        FeeTarget memory active,
        FeeTarget memory max,
        string memory label
    ) internal {
        // (rate==0 && flat==0) is the "not configured" sentinel for both blocks — operators
        // clear stale fees/caps out-of-band; this script only ever raises/sets configured values.
        bool wantActive = active.rate != 0 || active.flat != 0;
        bool wantMax = max.rate != 0 || max.flat != 0;

        if (!wantActive && !wantMax) {
            _logSkipped(string.concat("fees(", label, ") no active fee and no maxFee config, skipping"));
            return;
        }

        // Force mode: skip the on-chain idempotency reads. For vaults whose CURRENT impl
        // pre-dates the Fee struct, fees()/maxFees() revert (old uint32 layout); an upgrade
        // queued AHEAD of this batch makes them fee-aware by the time these execute. Cap
        // changes cannot be ordered safely without the live active fee, so apply them in a
        // state-aware run after the upgrade.
        if (forceSetFee) {
            if (wantMax) {
                _logSkipped(
                    string.concat(
                        "fees(",
                        label,
                        ") FORCED mode defers setMaxFee until a post-upgrade state-aware run on ",
                        vm.toString(vault)
                    )
                );
            }
            if (wantActive) {
                _logSkipped(
                    string.concat(
                        "fees(",
                        label,
                        ") FORCED setFee (idempotency read skipped; assumes upgrade-ahead) on ",
                        vm.toString(vault)
                    )
                );
                _queueSetFee(vault, f, NestVaultCoreTypes.Fee({rate: active.rate, flat: active.flat}), label, false);
            }
            return;
        }

        (uint32 curRate, uint256 curFlat) = INestVaultCore(vault).fees(f);
        (uint32 curMaxRate, uint256 curMaxFlat) = INestVaultCore(vault).maxFees(f);

        bool feeMatches = !wantActive || (curRate == active.rate && curFlat == active.flat);
        bool maxMatches = !wantMax || (curMaxRate == max.rate && curMaxFlat == max.flat);

        if (feeMatches && maxMatches) {
            _logSkipped(string.concat("fees(", label, ") already at target on ", vm.toString(vault)));
            return;
        }

        // The cap the active fee must fit under after this run: the new cap when we're
        // setting one, otherwise the cap currently on-chain.
        uint32 effMaxRate = wantMax ? max.rate : curMaxRate;
        uint256 effMaxFlat = wantMax ? max.flat : curMaxFlat;

        // A cap raise must precede setFee; a cap lower must follow it, so maxFee >= fee
        // holds across both transitions.
        bool raisingMax = wantMax && !maxMatches && (max.rate > curMaxRate || max.flat > curMaxFlat);

        // On-chain, setMaxFee validates componentwise against the ACTIVE fee at execution; a cap queued
        // before setFee (or with none queued) faces the CURRENT fee, so fail fast instead of a doomed batch.
        bool willQueueSetFee = wantActive && !feeMatches && active.rate <= effMaxRate && active.flat <= effMaxFlat;
        if (wantMax && !maxMatches && (raisingMax || !willQueueSetFee)) {
            require(max.rate >= curRate && max.flat >= curFlat, _mixedCapError(vault, label, max, curRate, curFlat));
        }

        if (raisingMax) {
            _queueSetMaxFee(vault, f, NestVaultCoreTypes.Fee({rate: max.rate, flat: max.flat}), label);
        }

        if (wantActive && !feeMatches) {
            // setFee validates rate/flat against the maxFee cap and reverts if either exceeds it.
            // Never queue a tx that will revert: a flat fee above the default 0 flat cap (or any
            // target above the cap) needs an explicit vaultMaxFees raise first.
            if (active.rate > effMaxRate || active.flat > effMaxFlat) {
                _logSkipped(
                    string.concat(
                        "fees(",
                        label,
                        ") active target rate=",
                        vm.toString(uint256(active.rate)),
                        " flat=",
                        vm.toString(active.flat),
                        " exceeds effective maxFee cap (rate=",
                        vm.toString(uint256(effMaxRate)),
                        " flat=",
                        vm.toString(effMaxFlat),
                        ") - add a vaultMaxFees entry to raise the cap; skipping setFee on ",
                        vm.toString(vault)
                    )
                );
            } else {
                _queueSetFee(vault, f, NestVaultCoreTypes.Fee({rate: active.rate, flat: active.flat}), label, false);
            }
        }

        if (wantMax && !maxMatches && !raisingMax) {
            _queueSetMaxFee(vault, f, NestVaultCoreTypes.Fee({rate: max.rate, flat: max.flat}), label);
        }
    }

    // Actionable message for a maxFee target with a component below the current active fee;
    // separate function to keep _applyFeeForType under the IR stack-pressure limit.
    function _mixedCapError(address vault, string memory label, FeeTarget memory max, uint32 curRate, uint256 curFlat)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "SetupFees: fees(",
            label,
            ") vaultMaxFees(rate=",
            vm.toString(uint256(max.rate)),
            ",flat=",
            vm.toString(max.flat),
            ") has a component below the current active fee (rate=",
            vm.toString(uint256(curRate)),
            ",flat=",
            vm.toString(curFlat),
            ") on ",
            vm.toString(vault),
            " and cannot execute in one batch: lower the active fee under the current cap first,",
            " or run once with vaultMaxFees at the componentwise max of target cap and current fee",
            " (plus the new vaultFees), then lower the cap in a second run"
        );
    }

    function _queueSetMaxFee(
        address vault,
        NestVaultCoreTypes.Fees f,
        NestVaultCoreTypes.Fee memory feeStruct,
        string memory label
    ) internal {
        execute(
            vault,
            abi.encodeCall(INestVaultCore.setMaxFee, (f, feeStruct)),
            string.concat(
                "setMaxFee(",
                label,
                ", rate=",
                vm.toString(uint256(feeStruct.rate)),
                ", flat=",
                vm.toString(feeStruct.flat),
                ") -> ",
                vm.toString(vault)
            )
        );
    }

    function _queueSetFee(
        address vault,
        NestVaultCoreTypes.Fees f,
        NestVaultCoreTypes.Fee memory feeStruct,
        string memory label,
        bool feeMatches
    ) internal {
        if (feeMatches) return;
        execute(
            vault,
            abi.encodeCall(INestVaultCore.setFee, (f, feeStruct)),
            string.concat(
                "setFee(",
                label,
                ", rate=",
                vm.toString(uint256(feeStruct.rate)),
                ", flat=",
                vm.toString(feeStruct.flat),
                ") -> ",
                vm.toString(vault)
            )
        );
    }

    // ─── Accountant fees ──────────────────────────────────────────────

    function _applyAccountantFees() internal {
        uint32 targetMgmt = vaultConfig.accountantParams.managementFee;
        uint32 targetPerf = uint32(_tryReadUint(".accountantParams.performanceFee"));
        uint32 targetHurdle = uint32(_tryReadUint(".accountantParams.hurdleRate"));
        uint96 targetHwm = uint96(_tryReadUint(".accountantParams.highWaterMark"));

        // Nothing to set — skip without touching the accountant. The hub-only
        // getAccountantState()/getPerformanceFeeConfig()/getPerformanceFeeCheckpoint()
        // reads below would revert on a NestSpokeAccountant (every non-Plume chain),
        // and there is no fee to apply anyway. Each on-chain read is deferred to the
        // branch that needs it.
        if (targetMgmt == 0 && targetPerf == 0 && targetHurdle == 0 && targetHwm == 0) {
            _logSkipped("accountant fees: management/performance/hurdle/HWM targets all zero, skipping");
            return;
        }

        // Accountant fee setters and their idempotency getters exist only on NestHubAccountant;
        // NestSpokeAccountant has no fee surface at all. Shared configs legitimately run per
        // chain with nonzero targets, so skip (don't abort) off-hub.
        string memory acctType = effectiveAccountantType();
        if (keccak256(bytes(acctType)) != keccak256(bytes("NestHubAccountant"))) {
            _logSkipped(
                string.concat(
                    "accountant fees: effective accountant type is ",
                    acctType,
                    " (Hub-only setters), skipping accountant fee pass on this chain"
                )
            );
            return;
        }

        address accountant = vaultConfig.contracts.accountant;
        require(isActive(accountant), "SetupFees: accountant not set");

        // Pre-upgrade guard: the proxy may still run the legacy impl (e.g. --run-upgrade queues
        // the accountant upgrade in this same run, unexecuted at read time). Defer loudly and
        // keep the vault-fee batch: execute the upgrade, then rerun SetupFees.
        if (!_hasHubGetters(accountant)) {
            _logSkipped(
                string.concat(
                    "accountant fees: impl at ",
                    vm.toString(accountant),
                    " does not expose NestHubAccountant getters (pre-upgrade legacy impl or not yet",
                    " deployed); execute the upgrade batch, then rerun SetupFees; skipping"
                )
            );
            return;
        }

        if (targetMgmt == 0) {
            _logSkipped(string.concat("updateManagementFee target is zero, skipping on ", vm.toString(accountant)));
        } else {
            uint32 curMgmt = NestHubAccountant(accountant).getAccountantState().managementFee;
            if (curMgmt == targetMgmt) {
                _logSkipped(
                    string.concat(
                        "updateManagementFee already at ",
                        vm.toString(uint256(targetMgmt)),
                        " on ",
                        vm.toString(accountant)
                    )
                );
            } else {
                execute(
                    accountant,
                    abi.encodeCall(NestHubAccountant.updateManagementFee, (targetMgmt)),
                    string.concat(
                        "updateManagementFee(", vm.toString(uint256(targetMgmt)), ") -> ", vm.toString(accountant)
                    )
                );
            }
        }

        if (targetPerf == 0) {
            _logSkipped(string.concat("updatePerformanceFee target is zero, skipping on ", vm.toString(accountant)));
        } else {
            uint32 curPerf = NestHubAccountant(accountant).getPerformanceFeeConfig().performanceFee;
            if (curPerf == targetPerf) {
                _logSkipped(
                    string.concat(
                        "updatePerformanceFee already at ",
                        vm.toString(uint256(targetPerf)),
                        " on ",
                        vm.toString(accountant)
                    )
                );
            } else {
                _applyPerformanceFeeChange(accountant, targetPerf);
            }
        }

        // High-water mark — queued AFTER updatePerformanceFee, since enabling a perf fee
        // (0 -> >0) auto-seeds the HWM to the live gross rate. A zero/unset target means
        // "leave the HWM as-is" (rely on that auto-seed); only an explicit non-zero pin
        // overrides it. resetHighWaterMark reverts on a zero value, so never queue one.
        if (targetHwm == 0) {
            _logSkipped(string.concat("resetHighWaterMark target unset, skipping on ", vm.toString(accountant)));
        } else {
            uint96 curHwm = NestHubAccountant(accountant).getPerformanceFeeCheckpoint().highWaterMark;
            if (curHwm == targetHwm) {
                _logSkipped(
                    string.concat(
                        "resetHighWaterMark already at ",
                        vm.toString(uint256(targetHwm)),
                        " on ",
                        vm.toString(accountant)
                    )
                );
            } else {
                execute(
                    accountant,
                    abi.encodeCall(NestHubAccountant.resetHighWaterMark, (targetHwm)),
                    string.concat(
                        "resetHighWaterMark(", vm.toString(uint256(targetHwm)), ") -> ", vm.toString(accountant)
                    )
                );
            }
        }

        // Hurdle rate — updateHurdleRate reverts SameValue() on a no-op, so the
        // current-equals-target read below is required (not just an optimization) to
        // keep the batch idempotent.
        if (targetHurdle == 0) {
            _logSkipped(string.concat("updateHurdleRate target is zero, skipping on ", vm.toString(accountant)));
        } else {
            uint32 curHurdle = NestHubAccountant(accountant).getPerformanceFeeConfig().hurdleRate;
            if (curHurdle == targetHurdle) {
                _logSkipped(
                    string.concat(
                        "updateHurdleRate already at ",
                        vm.toString(uint256(targetHurdle)),
                        " on ",
                        vm.toString(accountant)
                    )
                );
            } else {
                execute(
                    accountant,
                    abi.encodeCall(NestHubAccountant.updateHurdleRate, (targetHurdle)),
                    string.concat(
                        "updateHurdleRate(", vm.toString(uint256(targetHurdle)), ") -> ", vm.toString(accountant)
                    )
                );
            }
        }
    }

    /// @dev True when the live impl behind `accountant` exposes the Hub-only getters. Probe with
    ///      getPerformanceFeeConfig(): its selector is absent on legacy/Spoke impls, so the call
    ///      reverts and is caught. Do NOT probe with getAccountantState(): it exists on all three
    ///      impls but returns a shorter struct on legacy/Spoke, and a return-data DECODE failure
    ///      inside try/catch is NOT caught — it reverts in the caller (Solidity docs, try/catch).
    function _hasHubGetters(address accountant) internal view returns (bool) {
        if (accountant.code.length == 0) return false; // empty returndata would also decode-revert
        try NestHubAccountant(accountant).getPerformanceFeeConfig() returns (
            NestHubAccountant.PerformanceFeeConfig memory
        ) {
            return true;
        } catch {
            return false;
        }
    }

    /// @dev A perf-fee change needs a fresh rate checkpoint: the new fee applies to gains since the last
    ///      one, and enabling reverts InvalidRate while lastGrossRate == 0 (post-migration). Never post a
    ///      rate from here: skip, keeper posts, rerun. Stale = older than minimumUpdateDelayInSeconds.
    function _applyPerformanceFeeChange(address accountant, uint32 targetPerf) internal {
        NestHubAccountant.AccountantState memory st = NestHubAccountant(accountant).getAccountantState();
        if (st.lastGrossRate == 0 || block.timestamp > uint256(st.lastUpdateTimestamp) + st.minimumUpdateDelayInSeconds)
        {
            _logSkipped(
                string.concat(
                    "updatePerformanceFee(",
                    vm.toString(uint256(targetPerf)),
                    ") needs a fresh updateExchangeRate checkpoint on ",
                    vm.toString(accountant),
                    " (lastGrossRate=",
                    vm.toString(uint256(st.lastGrossRate)),
                    ", lastUpdateTimestamp=",
                    vm.toString(uint256(st.lastUpdateTimestamp)),
                    "): keeper posts a rate, then rerun SetupFees; skipping"
                )
            );
            return;
        }
        execute(
            accountant,
            abi.encodeCall(NestHubAccountant.updatePerformanceFee, (targetPerf)),
            string.concat("updatePerformanceFee(", vm.toString(uint256(targetPerf)), ") -> ", vm.toString(accountant))
        );
    }

    // ─── JSON helpers ─────────────────────────────────────────────────

    function _readFeeTarget(string memory prefix) internal view returns (FeeTarget memory t) {
        t.rate = uint32(_tryReadUint(string.concat(prefix, ".rate")));
        t.flat = _tryReadUint(string.concat(prefix, ".flat"));
    }

    function _tryReadUint(string memory key) internal view returns (uint256) {
        try vm.parseJsonUint(rawVaultConfigJson, key) returns (uint256 v) {
            return v;
        } catch {
            return 0;
        }
    }
}
