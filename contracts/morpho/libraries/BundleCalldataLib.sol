// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Call} from "contracts/vendor/bundler3/interfaces/IBundler3.sol";
import {NestAdapter} from "contracts/morpho/NestAdapter.sol";
import {MorphoAdapter} from "contracts/morpho/MorphoAdapter.sol";
import {ITellerPredicateProxy} from "contracts/interfaces/ITellerPredicateProxy.sol";
import {GeneralAdapter1} from "contracts/vendor/morpho/GeneralAdapter1.sol";
import {AtomicSolverV3} from "contracts/vendor/boring-vault/AtomicSolverV3.sol";
import {NestVaultPredicateProxy} from "contracts/NestVaultPredicateProxy.sol";
import {AtomicQueue} from "@boring-vault/src/atomic-queue/AtomicQueue.sol";
import {CrossChainTellerBase} from "@boring-vault/src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MarketParams, Position as MorphoPosition} from "@morpho/interfaces/IMorpho.sol";
import {MathLib} from "@morpho/libraries/MathLib.sol";
import {MarketParamsLib} from "@morpho/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "@morpho/libraries/SharesMathLib.sol";
import {MorphoBalancesLib} from "@morpho/libraries/periphery/MorphoBalancesLib.sol";
import {Bundle, PositionMode} from "../types/BundleTypes.sol";
import {MorphoMarketLib} from "./MorphoMarketLib.sol";
import {NestShareMathLib} from "./NestShareMathLib.sol";
import {NestVaultLib} from "./NestVaultLib.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {NestVaultAccountingLogic} from "contracts/libraries/nest-vault/NestVaultAccountingLogic.sol";
import {NestBundleErrors} from "../types/Errors.sol";

/// @title BundleCalldataLib
/// @notice Encodes bundle actions as Bundler3 `Call[]` payloads.
library BundleCalldataLib {
    using MorphoMarketLib for MarketParams;
    using MarketParamsLib for MarketParams;
    using NestShareMathLib for uint256;
    using NestVaultLib for INestVaultCore;
    using MathLib for uint256;
    using SharesMathLib for uint256;

    /// @notice E27 fixed-point scale used for share-price math.
    uint256 private constant SHARE_PRICE_SCALE = 1e27;

    /// @notice Maximum flash-loan loops a single looped deleverage may emit.
    /// @dev Available liquidity grows by each repay, so loop count is logarithmic in
    ///      `totalRepay / morphoBalance`; this cap bounds gas and guards degenerate inputs.
    uint256 private constant MAX_DELEVERAGE_LOOPS = 32;

    /// @notice Builds top-level bundler calls, wrapping callback calls in a flash loan when needed.
    /// @param bundle Fully derived bundle input.
    /// @return calls Bundler call sequence to execute.
    function getBundleCalls(Bundle memory bundle) internal view returns (Call[] memory calls) {
        uint256 flashLoanAssets = _flashLoanAssets(bundle);

        // When a pure deleverage needs more loanToken liquidity than Morpho currently holds, split it into sequential flash loans.
        if (flashLoanAssets > 0 && _canLoop(bundle)) {
            uint256 morphoBalance = ERC20(bundle.intent.market.loanToken).balanceOf(address(bundle.ctx.morpho));
            if (flashLoanAssets > morphoBalance) {
                return _getLoopCalls(bundle, flashLoanAssets, morphoBalance);
            }
        }

        Call[] memory callbackBundle = _getCallbackCalls(bundle);
        if (callbackBundle.length == 0) return new Call[](0);

        if (flashLoanAssets == 0) {
            uint256 len = callbackBundle.length;
            calls = new Call[](len + 1);
            for (uint256 i; i < len; i++) {
                calls[i] = callbackBundle[i];
            }
            calls[len] = adapterSweep(bundle);
            return calls;
        }

        calls = new Call[](2);
        calls[0] = morphoFlashLoan(bundle, callbackBundle);
        calls[1] = adapterSweep(bundle);
    }

    /// @dev Builds N sequential flash-loan calls for a deleverage too large for Morpho's current liquidity.
    ///      Loop `i` repays `repays[i]`, withdraws and redeems exactly enough collateral to repay its own
    ///      flash loan, and defers the remaining (equity) collateral to the final loop. Intermediate loops
    ///      are switched to delta mode so `morphoRepay` repays by assets rather than clearing the full debt.
    ///      Each loop redeems separately, so a flat redemption fee is charged per chunk rather than once,
    ///      raising total fees and lowering leftover equity the more chunks low liquidity forces.
    /// @param bundle Fully derived deleverage bundle.
    /// @param totalRepay Total loan assets to repay (== aggregate flash-loan amount).
    /// @param morphoBalance Loan-token liquidity Morpho holds at build time (== first-loop ceiling).
    /// @return calls Sequential flash-loan calls followed by a single adapter sweep.
    function _getLoopCalls(Bundle memory bundle, uint256 totalRepay, uint256 morphoBalance)
        private
        view
        returns (Call[] memory calls)
    {
        if (morphoBalance == 0) revert NestBundleErrors.ZeroLiquidity();

        // Read the live Morpho borrow state once so loop sizing can simulate Morpho's exact share accounting.
        MorphoPosition memory position = bundle.ctx.morpho.position(bundle.intent.market.id(), bundle.ctx.owner);
        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) =
            MorphoBalancesLib.expectedMarketBalances(bundle.ctx.morpho, bundle.intent.market);

        // A full exit repays the residual via `shares = max` (see `morphoRepay`); every other final loop repays by assets.
        (uint256[] memory repays, uint256[] memory residualBorrow, uint256 loops) = _repayLoops(
            totalRepay, morphoBalance, position.borrowShares, totalBorrowAssets, totalBorrowShares, _isFullExit(bundle)
        );

        calls = new Call[](loops + 1);
        // Cumulative collateral withdrawn across loops: each intermediate loop's redeem slice, then the final
        // loop's full remainder. Reused by the per-loop health check as the collateral pulled so far.
        uint256 redeemed;
        // Sum of every loop's redeem shares, re-validated against the redeem buffer after the loop.
        uint256 totalRedeemShares;
        // Instant and async redemptions may charge different fees.
        NestVaultCoreTypes.Fees feeType =
            bundle.route.instantRedeem ? NestVaultCoreTypes.Fees.InstantRedemption : NestVaultCoreTypes.Fees.Redemption;
        (, uint256 flatFee) = bundle.ctx.vault.fees(feeType);

        for (uint256 i; i < loops; i++) {
            Bundle memory loopBundle = abi.decode(abi.encode(bundle), (Bundle));
            // Each chunk flash-borrows and repays exactly its slice, so both fields are the per-loop amount.
            loopBundle.ma.repay = repays[i];
            loopBundle.ma.flashRepay = repays[i];
            // Fee-aware: size shares so the loop's post-fee redeem proceeds cover its flash-loan repayment.
            uint256 redeemShares = loopBundle.ctx.vault.getMinRedeemShares(repays[i], feeType);
            loopBundle.va.redeem = redeemShares;
            // Relax the aggregate per-share floor by the flat fee this chunk alone bears, since chunking charges it per chunk.
            if (flatFee != 0) {
                uint256 flatFeeE27 = Math.mulDiv(flatFee, SHARE_PRICE_SCALE, redeemShares, Math.Rounding.Ceil);
                loopBundle.intent.minSharePriceE27 =
                    bundle.intent.minSharePriceE27 > flatFeeE27 ? bundle.intent.minSharePriceE27 - flatFeeE27 : 0;
            }
            totalRedeemShares += redeemShares;
            _validateRedeemFee(loopBundle.ctx.vault, redeemShares, feeType);

            if (i + 1 < loops) {
                // Intermediate: assets-based partial repay; withdraw exactly this loop's redeem slice.
                loopBundle.ma.withdrawCollateral = redeemShares;
                loopBundle.intent.mode = PositionMode.Delta;
                redeemed += redeemShares;
                // Prevent underflow in the health check.
                if (redeemed > position.collateral) {
                    revert NestBundleErrors.InsufficientCollateralForRedeem(redeemed, position.collateral);
                }
            } else {
                // Final: withdraw the remaining collateral.
                uint256 totalCollateralWithdraw = bundle.ma.withdrawCollateral;
                if (redeemed + redeemShares > totalCollateralWithdraw) {
                    totalCollateralWithdraw = redeemed + redeemShares;
                }
                if (totalCollateralWithdraw > position.collateral) {
                    revert NestBundleErrors.InsufficientCollateralForRedeem(
                        totalCollateralWithdraw, position.collateral
                    );
                }
                loopBundle.ma.withdrawCollateral = totalCollateralWithdraw - redeemed;
                redeemed = totalCollateralWithdraw;
            }

            // Health check on the state this loop leaves behind: the residual debt simulated by `_repayLoops`
            // must stay within LLTV against the collateral remaining after this loop's withdrawal.
            if (residualBorrow[i] != 0) {
                uint256 maxBorrowAfter = bundle.intent.market.convertToAssets(position.collateral - redeemed)
                    .wMulDown(bundle.intent.market.lltv);
                if (maxBorrowAfter < residualBorrow[i]) revert NestBundleErrors.LoopBreachesLltv();
            }

            // Record the loop calls
            calls[i] = morphoFlashLoan(loopBundle, _getCallbackCalls(loopBundle));
        }

        // Per-chunk floors are relaxed only when a flat fee applies, so cumulative fees can erode the whole-redeem
        // net price below the user's floor. Enforce it in aggregate; without a flat fee the per-chunk
        // floors are unrelaxed and already sufficient, so skip (and avoid a ceil-rounding false revert here).
        if (flatFee != 0 && totalRedeemShares != 0) {
            uint256 netSharePriceE27 = Math.mulDiv(totalRepay, SHARE_PRICE_SCALE, totalRedeemShares);
            if (netSharePriceE27 < bundle.intent.minSharePriceE27) {
                revert NestBundleErrors.AggregateSharePriceBelowMin(netSharePriceE27, bundle.intent.minSharePriceE27);
            }
        }

        // Instant redeems only need their peak buffer draw.
        if (bundle.route.instantRedeem) {
            uint256 bufferAssets = ERC20(bundle.ctx.vault.asset()).balanceOf(bundle.ctx.vault.share());
            uint256 peakRedeemDraw = _instantPeakDraw(bundle.ctx.vault, repays, feeType);
            if (peakRedeemDraw > bufferAssets) {
                revert NestBundleErrors.InsufficientRedeemLiquidity(peakRedeemDraw, bufferAssets);
            }
        } else {
            // Async redeems consume the gross share sum.
            uint256 redeemLiquidity = bundle.ctx.vault.getInstantRedeemLiquidity();
            if (totalRedeemShares > redeemLiquidity) {
                revert NestBundleErrors.InsufficientRedeemLiquidity(totalRedeemShares, redeemLiquidity);
            }
        }

        // Final sweep of any remaining assets to owner.
        calls[loops] = adapterSweep(bundle);
    }

    /// @dev Repay loops simulating Morpho's exact borrow-share accounting. After every loop repays `repays[n]`
    ///      Morpho can flash-loan that `repays[n]` again in later top-level calls, so available liquidity
    ///      grows by the repaid amount. The final loop is sized to the amount it will actually pull according to the
    ///      simulated market state.
    /// @param totalRepay Total loan assets the deleverage must repay.
    /// @param morphoBalance Loan-token liquidity Morpho holds (== first-loop ceiling).
    /// @param borrowShares Owner's current Morpho borrow shares.
    /// @param totalBorrowAssets Market total borrow assets (interest-accrued).
    /// @param totalBorrowShares Market total borrow shares.
    /// @param fullExit Whether this deleverage is a target full exit.
    /// @return repays Per-loop repay assets.
    /// @return residualBorrow Per-loop residual borrow assets left after that loop's repay.
    /// @return loops Number of loops emitted.
    function _repayLoops(
        uint256 totalRepay,
        uint256 morphoBalance,
        uint256 borrowShares,
        uint256 totalBorrowAssets,
        uint256 totalBorrowShares,
        bool fullExit
    ) private pure returns (uint256[] memory repays, uint256[] memory residualBorrow, uint256 loops) {
        repays = new uint256[](MAX_DELEVERAGE_LOOPS);
        residualBorrow = new uint256[](MAX_DELEVERAGE_LOOPS);
        uint256 remaining = totalRepay;

        while (true) {
            if (loops == MAX_DELEVERAGE_LOOPS) revert NestBundleErrors.ExceedsMaxLoops();

            // A full exit's final loop is sized to the live debt and cleared via `shares = max`, leaving zero residual;
            // padded for interest accrued between build and execution, surplus sweeps back.
            uint256 residualAssets;
            if (fullExit) {
                residualAssets = borrowShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);
                uint256 borrowAssets = residualAssets.applyBuffer();
                if (borrowAssets <= morphoBalance) {
                    repays[loops] = borrowAssets;
                    residualBorrow[loops] = 0;
                    loops++;
                    break;
                }
            }

            // Otherwise repay what current liquidity allows, by assets, simulating Morpho's `toSharesDown` burn so
            // later loops size against the reduced debt and each loop's residual feeds the caller's health check.
            // A full-exit intermediate leaves at least 1 asset of debt so the final `shares = max` loop is never empty.
            uint256 repay = fullExit ? Math.min(morphoBalance, residualAssets - 1) : Math.min(remaining, morphoBalance);
            uint256 burned = repay.toSharesDown(totalBorrowAssets, totalBorrowShares);
            // Clean error instead of a panic.
            if (burned == 0) {
                revert NestBundleErrors.LoopRepayBurnsZeroShares(repay, totalBorrowAssets, totalBorrowShares);
            }
            borrowShares = burned >= borrowShares ? 0 : borrowShares - burned;
            totalBorrowShares -= burned;
            totalBorrowAssets -= repay;
            residualBorrow[loops] = borrowShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);

            repays[loops] = repay;
            loops++;

            // A partial exit ends once its linear target is fully repaid (`repay` consumed all of `remaining`).
            if (!fullExit && repay == remaining) break;

            // a full-exit `repay` can exceed the stale `remaining`.
            remaining = repay >= remaining ? 0 : remaining - repay;
            morphoBalance += repay;
        }
    }

    /// @dev Worst-case share-token buffer draw across instant-redeem loop chunks, in asset units. Each chunk pulls its
    ///      full gross out of the buffer, then its fee is recycled back, so only the post-fee amount stays drained.
    ///      The peak (prior chunks' net drain + this chunk's gross) is the binding constraint — not the gross sum,
    ///      which the recycled fee overstates. Mirrors the per-chunk sizing in `_getLoopCalls`/execution.
    function _instantPeakDraw(INestVaultCore vault, uint256[] memory repays, NestVaultCoreTypes.Fees feeType)
        private
        view
        returns (uint256 peak)
    {
        (uint32 rateFee, uint256 flatFee) = vault.fees(feeType);
        uint256 netDrained;
        for (uint256 i; i < repays.length; i++) {
            uint256 grossAssets =
                vault.getMinRedeemShares(repays[i], feeType).convertToAssets(vault, Math.Rounding.Floor);
            (uint256 postFeeAssets,) = NestVaultAccountingLogic.calculatePostFeeAmounts(grossAssets, rateFee, flatFee);
            uint256 drawNow = netDrained + grossAssets;
            if (drawNow > peak) peak = drawNow;
            netDrained += postFeeAssets;
        }
    }

    /// @dev True when the bundle is a redeem-funded deleverage (instant or modern async) with no owner-funded or
    ///      leverage-up legs, i.e. a flow whose flash loan equals `ma.repay` and can be safely looped.
    function _canLoop(Bundle memory bundle) private pure returns (bool) {
        return bundle.ma.repay != 0 && bundle.va.redeem != 0 && bundle.ma.withdrawCollateral != 0
            && !bundle.route.legacyRedemption && bundle.ma.borrow == 0 && bundle.ma.supplyCollateral == 0
            && bundle.va.deposit == 0 && bundle.va.pullAssets == 0 && bundle.va.pullShares == 0;
    }

    /// @dev True when `morphoRepay` clears the whole debt via `shares = max`. Read by both the
    ///      single-shot and looped builders, so both paths must share the one condition.
    function _isFullExit(Bundle memory bundle) private pure returns (bool) {
        return bundle.intent.mode == PositionMode.Target && bundle.intent.target.loan == 0 && bundle.ma.repay > 0;
    }

    /// @dev Mirrors each path's exact runtime fee guard so tiny loops fail during build: async `fulfillRedeem`
    ///      caps the flat fee at FEE_CAP; instant `executeInstantRedeem` only rejects a zero post-fee amount.
    function _validateRedeemFee(INestVaultCore vault, uint256 redeemShares, NestVaultCoreTypes.Fees feeType)
        private
        view
    {
        (uint32 rateFee, uint256 flatFee) = vault.fees(feeType);
        bool instant = feeType == NestVaultCoreTypes.Fees.InstantRedemption;
        if (instant ? (rateFee == 0 && flatFee == 0) : flatFee == 0) return;

        uint256 grossAssets = redeemShares.convertToAssets(vault, Math.Rounding.Floor);
        bool tooSmall;
        if (instant) {
            (uint256 postFee,) = NestVaultAccountingLogic.calculatePostFeeAmounts(grossAssets, rateFee, flatFee);
            tooSmall = postFee == 0;
        } else {
            tooSmall = grossAssets == 0
                || Math.mulDiv(flatFee, NestVaultAccountingLogic.FEE_DENOMINATOR, grossAssets)
                    > NestVaultCoreTypes.FEE_CAP;
        }
        if (tooSmall) {
            revert NestBundleErrors.RedeemTooSmallForFlatFee(redeemShares, grossAssets, flatFee);
        }
    }

    /// @notice Encodes instant vault redeem.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function nestInstantRedeem(Bundle memory bundle) internal pure returns (Call memory) {
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                NestAdapter.nestInstantRedeem,
                (
                    bundle.ctx.vault,
                    bundle.va.redeem,
                    bundle.intent.minSharePriceE27,
                    bundle.ctx.adapter,
                    bundle.ctx.adapter
                )
            )
        );
    }

    /// @notice Encodes predicate-protected vault deposit.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function nestPredicateDeposit(Bundle memory bundle) internal pure returns (Call memory) {
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                NestAdapter.nestPredicateDeposit,
                (
                    NestVaultPredicateProxy(bundle.ctx.predicateProxy),
                    bundle.ctx.vault,
                    bundle.va.deposit,
                    bundle.intent.maxSharePriceE27,
                    bundle.ctx.adapter,
                    bundle.predicateMessage
                )
            )
        );
    }

    /// @notice Encodes predicate-protected vault mint.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function nestPredicateMint(Bundle memory bundle) internal pure returns (Call memory) {
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                NestAdapter.nestPredicateMint,
                (
                    NestVaultPredicateProxy(bundle.ctx.predicateProxy),
                    bundle.ctx.vault,
                    bundle.va.mint,
                    bundle.intent.maxSharePriceE27,
                    bundle.ctx.adapter,
                    bundle.predicateMessage
                )
            )
        );
    }

    /// @notice Encodes legacy teller predicate deposit.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function tellerPredicateDeposit(Bundle memory bundle) internal pure returns (Call memory) {
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                NestAdapter.tellerPredicateDeposit,
                (
                    ITellerPredicateProxy(bundle.ctx.predicateProxy),
                    ERC20(bundle.intent.market.loanToken),
                    bundle.va.deposit,
                    bundle.va.mint,
                    bundle.ctx.adapter,
                    CrossChainTellerBase(payable(bundle.ctx.teller)),
                    bundle.predicateMessage
                )
            )
        );
    }

    /// @notice Selects deposit path between legacy teller and vault predicate mint.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function nestDeposit(Bundle memory bundle) internal pure returns (Call memory) {
        if (bundle.route.legacyDeposit) return tellerPredicateDeposit(bundle);

        return nestPredicateMint(bundle);
    }

    /// @notice Encodes direct vault mint.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function nestMint(Bundle memory bundle) internal pure returns (Call memory) {
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                NestAdapter.nestMint,
                (bundle.ctx.vault, bundle.va.mint, bundle.intent.maxSharePriceE27, bundle.ctx.adapter)
            )
        );
    }

    /// @notice Encodes request-and-redeem flow for non-instant redemption.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function nestRequestAndRedeem(Bundle memory bundle) internal pure returns (Call memory) {
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                NestAdapter.nestRequestAndRedeem,
                (
                    bundle.ctx.vault,
                    bundle.va.redeem,
                    bundle.intent.minSharePriceE27,
                    bundle.ctx.adapter,
                    bundle.ctx.controller,
                    bundle.ctx.adapter
                )
            )
        );
    }

    /// @notice Encodes Morpho collateral withdrawal on behalf of owner.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function morphoWithdrawCollateralOnBehalf(Bundle memory bundle) internal pure returns (Call memory) {
        // Keep withdrawn collateral with the owner only when the legacy async redeem leg still needs to consume it.
        address receiver = bundle.route.legacyRedemption ? bundle.ctx.owner : bundle.ctx.adapter;
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                MorphoAdapter.morphoWithdrawCollateralOnBehalf,
                (bundle.intent.market, bundle.ma.withdrawCollateral, bundle.ctx.owner, receiver)
            )
        );
    }

    /// @notice Encodes legacy atomic solver redemption.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function atomicSolverRedeemSolve(Bundle memory bundle) internal view returns (Call memory) {
        (uint256 maxAssets, uint256 minimumAssetsOut) = legacyRedeemRequestAmounts(bundle);
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                NestAdapter.atomicSolverRedeemSolve,
                (
                    AtomicSolverV3(bundle.ctx.atomicSolver),
                    AtomicQueue(bundle.ctx.atomicQueue),
                    TellerWithMultiAssetSupport(bundle.ctx.teller),
                    bundle.intent.market,
                    bundle.ctx.owner,
                    bundle.ctx.adapter,
                    maxAssets,
                    minimumAssetsOut
                )
            )
        );
    }

    /// @notice Encodes Morpho flash loan with callback bundle payload.
    /// @param bundle Fully derived bundle input.
    /// @param callbackBundle Calls executed in flash-loan callback.
    /// @return Encoded adapter call with callback hash set.
    function morphoFlashLoan(Bundle memory bundle, Call[] memory callbackBundle) internal pure returns (Call memory) {
        bytes memory callbackData = abi.encode(callbackBundle);
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                GeneralAdapter1.morphoFlashLoan,
                (bundle.intent.market.loanToken, _flashLoanAssets(bundle), callbackData)
            ),
            keccak256(callbackData)
        );
    }

    /// @notice Encodes pull of loan assets from owner.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function pullLoanAssets(Bundle memory bundle) internal pure returns (Call memory) {
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                GeneralAdapter1.erc20TransferFrom,
                (bundle.intent.market.loanToken, bundle.ctx.adapter, bundle.va.pullAssets)
            )
        );
    }

    /// @notice Encodes pull of collateral shares from owner.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function pullCollateralShares(Bundle memory bundle) internal pure returns (Call memory) {
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                GeneralAdapter1.erc20TransferFrom,
                (bundle.intent.market.collateralToken, bundle.ctx.adapter, bundle.va.pullShares)
            )
        );
    }

    /// @notice Encodes Morpho collateral supply.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call with callback hash disabled.
    function morphoSupplyCollateral(Bundle memory bundle) internal pure returns (Call memory) {
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                GeneralAdapter1.morphoSupplyCollateral,
                (bundle.intent.market, bundle.ma.supplyCollateral, bundle.ctx.owner, bytes(""))
            ),
            bytes32(0)
        );
    }

    /// @notice Encodes Morpho collateral withdrawal to initiator.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function morphoWithdrawCollateral(Bundle memory bundle) internal pure returns (Call memory) {
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                GeneralAdapter1.morphoWithdrawCollateral,
                (bundle.intent.market, bundle.ma.withdrawCollateral, bundle.ctx.initiator)
            )
        );
    }

    /// @notice Encodes Morpho borrow on behalf of owner.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function morphoBorrowOnBehalf(Bundle memory bundle) internal pure returns (Call memory) {
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                MorphoAdapter.morphoBorrowOnBehalf,
                (bundle.intent.market, bundle.ma.borrow, 0, 0, bundle.ctx.owner, bundle.ctx.adapter)
            )
        );
    }

    /// @notice Encodes Morpho repay with max repay share-price guard.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call with callback hash disabled.
    function morphoRepay(Bundle memory bundle) internal pure returns (Call memory) {
        // Full repay (target loan == 0): use shares = max to avoid toAssetsUp rounding overflow.
        uint256 repayAssets = bundle.ma.repay;
        uint256 repayShares;
        if (_isFullExit(bundle)) {
            repayAssets = 0;
            repayShares = type(uint256).max;
        }
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(
                GeneralAdapter1.morphoRepay,
                (
                    bundle.intent.market,
                    repayAssets,
                    repayShares,
                    bundle.intent.maxRepaySharePriceE27,
                    bundle.ctx.owner,
                    bytes("")
                )
            ),
            bytes32(0)
        );
    }

    /// @notice Selects redemption path between instant, legacy, and request-and-redeem.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function nestRedeem(Bundle memory bundle) internal view returns (Call memory) {
        if (bundle.route.instantRedeem) return nestInstantRedeem(bundle);

        if (bundle.route.legacyRedemption) return atomicSolverRedeemSolve(bundle);

        return nestRequestAndRedeem(bundle);
    }

    /// @notice Encodes sweep of remaining assets to owner.
    /// @param bundle Fully derived bundle input.
    /// @return Encoded adapter call.
    function adapterSweep(Bundle memory bundle) private pure returns (Call memory) {
        return _call(
            bundle.ctx.adapter,
            abi.encodeCall(NestAdapter.adapterSweep, (bundle.intent.market, bundle.ctx.owner)),
            bytes32(0)
        );
    }

    /// @notice Returns the solver limits for the legacy redeem solve using bundle-derived amounts only.
    function legacyRedeemRequestAmounts(Bundle memory bundle)
        internal
        view
        returns (uint256 maxAssets, uint256 minimumAssetsOut)
    {
        maxAssets = bundle.ma.withdrawCollateral.convertToAssets(bundle.ctx.vault, Math.Rounding.Floor);
        minimumAssetsOut = bundle.va.withdraw != 0
            ? bundle.va.withdraw
            : Math.mulDiv(bundle.va.redeem, bundle.intent.minSharePriceE27, SHARE_PRICE_SCALE, Math.Rounding.Ceil);
    }

    /// @dev Wraps target and calldata into a default Bundler3 call.
    /// @param to Call target.
    /// @param data Encoded calldata.
    /// @return Encoded bundler call struct.
    function _call(address to, bytes memory data) private pure returns (Call memory) {
        return Call({to: to, data: data, value: 0, skipRevert: false, callbackHash: bytes32(0)});
    }

    /// @dev Wraps target and calldata into a Bundler3 call with callback hash.
    /// @param to Call target.
    /// @param data Encoded calldata.
    /// @param callbackHash Expected callback hash for flash-loan callbacks.
    /// @return Encoded bundler call struct.
    function _call(address to, bytes memory data, bytes32 callbackHash) private pure returns (Call memory) {
        return Call({to: to, data: data, value: 0, skipRevert: false, callbackHash: callbackHash});
    }

    /// @dev Computes flash-loan assets required after owner-funded assets are pulled.
    /// @param bundle Fully derived bundle input.
    /// @return assets Flash-loaned loan assets.
    function _flashLoanAssets(Bundle memory bundle) private pure returns (uint256 assets) {
        uint256 requiredLoanAssets = bundle.ma.flashRepay + bundle.va.deposit;
        if (bundle.va.pullAssets >= requiredLoanAssets) return 0;
        assets = requiredLoanAssets - bundle.va.pullAssets;
    }

    /// @dev Builds the ordered callback bundle and omits zero-amount actions.
    /// @param bundle Fully derived bundle input.
    /// @return callbackBundle Ordered callback calls.
    function _getCallbackCalls(Bundle memory bundle) private view returns (Call[] memory callbackBundle) {
        bool hasPullAssets = bundle.va.pullAssets != 0;
        bool hasPullShares = bundle.va.pullShares != 0;
        bool hasRepay = bundle.ma.repay != 0;
        bool hasWithdrawCollateral = bundle.ma.withdrawCollateral != 0;
        bool hasRedeem = bundle.va.redeem != 0;
        bool hasDeposit = bundle.va.deposit != 0;
        bool hasSupplyCollateral = bundle.ma.supplyCollateral != 0;
        bool hasBorrow = bundle.ma.borrow != 0;

        uint256 actionCount;
        if (hasPullAssets) actionCount++;
        if (hasPullShares) actionCount++;
        if (hasRepay) actionCount++;
        if (hasWithdrawCollateral) actionCount++;
        if (hasDeposit) actionCount++;
        if (hasSupplyCollateral) actionCount++;
        if (hasBorrow) actionCount++;
        if (hasRedeem) actionCount++;

        callbackBundle = new Call[](actionCount);
        uint256 i;

        if (hasPullAssets) callbackBundle[i++] = pullLoanAssets(bundle);
        if (hasPullShares) callbackBundle[i++] = pullCollateralShares(bundle);
        if (hasRepay) callbackBundle[i++] = morphoRepay(bundle);
        if (hasWithdrawCollateral) callbackBundle[i++] = morphoWithdrawCollateralOnBehalf(bundle);
        if (hasDeposit) callbackBundle[i++] = nestDeposit(bundle);
        if (hasSupplyCollateral) callbackBundle[i++] = morphoSupplyCollateral(bundle);
        if (hasBorrow) callbackBundle[i++] = morphoBorrowOnBehalf(bundle);
        if (hasRedeem) callbackBundle[i++] = nestRedeem(bundle);
    }
}
