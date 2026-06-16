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

import {MarketParams} from "@morpho/interfaces/IMorpho.sol";
import {Bundle, PositionMode} from "../types/BundleTypes.sol";
import {MorphoMarketLib} from "./MorphoMarketLib.sol";
import {NestShareMathLib} from "./NestShareMathLib.sol";

/// @title BundleCalldataLib
/// @notice Encodes bundle actions as Bundler3 `Call[]` payloads.
library BundleCalldataLib {
    using MorphoMarketLib for MarketParams;
    using NestShareMathLib for uint256;

    /// @notice E27 fixed-point scale used for share-price math.
    uint256 private constant SHARE_PRICE_SCALE = 1e27;

    /// @notice Builds top-level bundler calls, wrapping callback calls in a flash loan when needed.
    /// @param bundle Fully derived bundle input.
    /// @return calls Bundler call sequence to execute.
    function getBundleCalls(Bundle memory bundle) internal view returns (Call[] memory calls) {
        Call[] memory callbackBundle = _getCallbackCalls(bundle);
        if (callbackBundle.length == 0) return new Call[](0);

        if (_flashLoanAssets(bundle) == 0) {
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
        if (
            bundle.intent.mode == PositionMode.Target && bundle.intent.target.loan == 0
                && bundle.ma.withdrawCollateral > 0
        ) {
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
        uint256 requiredLoanAssets = bundle.ma.repay + bundle.va.deposit;
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

        uint256 n;
        if (hasPullAssets) n++;
        if (hasPullShares) n++;
        if (hasRepay) n++;
        if (hasWithdrawCollateral) n++;
        if (hasDeposit) n++;
        if (hasSupplyCollateral) n++;
        if (hasBorrow) n++;
        if (hasRedeem) n++;

        callbackBundle = new Call[](n);
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
