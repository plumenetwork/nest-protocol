// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import "../types/BundleTypes.sol";
import {NestBundleErrors} from "../types/Errors.sol";

import {Id, Position as MorphoPosition, IMorpho, MarketParams} from "@morpho/interfaces/IMorpho.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/src/base/Roles/TellerWithMultiAssetSupport.sol";

import {SharesMathLib} from "@morpho/libraries/SharesMathLib.sol";
import {MathLib} from "@morpho/libraries/MathLib.sol";
import {MarketParamsLib} from "@morpho/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "@morpho/libraries/periphery/MorphoBalancesLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MorphoMarketLib} from "./MorphoMarketLib.sol";
import {NestShareMathLib} from "./NestShareMathLib.sol";
import {NestVaultLib} from "./NestVaultLib.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {NestVaultAccountingLogic} from "contracts/libraries/nest-vault/NestVaultAccountingLogic.sol";

/// @title BundleBuildLib
/// @notice Derives bundle actions from target or delta inputs.
library BundleBuildLib {
    using MarketParamsLib for MarketParams;
    using MorphoMarketLib for MarketParams;
    using NestVaultLib for INestVaultCore;
    using NestShareMathLib for uint256;
    using SharesMathLib for uint256;
    using MathLib for uint256;
    using Math for uint256;

    /// @notice Builds a bundle from either target or delta user intent.
    /// @param ctx Runtime contracts/addresses used by the bundle.
    /// @param intent User market config, allowances, and price guards.
    /// @param route Route flags selecting deposit/redemption paths.
    /// @return bundle Fully derived bundle ready for calldata encoding.
    function getBundle(BundleContext memory ctx, UserIntent memory intent, RouteInput memory route)
        internal
        view
        returns (Bundle memory bundle)
    {
        validateBundleContext(ctx);
        validateUserIntent(ctx, intent);
        validateRouteInput(route);
        MarketActions memory ma = getValidMarketActions(ctx, intent);

        return _buildBundle(ctx, intent, route, ma);
    }

    /// @notice Builds an async bundle for either legacy AtomicQueue redemption or modern async redeem.
    /// @param ctx Runtime contracts/addresses used by the bundle.
    /// @param intent User market config, allowances, and price guards.
    /// @param useAtomicQueue Whether to build the legacy AtomicQueue redemption route.
    /// @return bundle Fully derived bundle ready for calldata encoding.
    function getAsyncBundle(BundleContext memory ctx, UserIntent memory intent, bool useAtomicQueue)
        internal
        view
        returns (Bundle memory bundle)
    {
        if (!useAtomicQueue) {
            RouteInput memory route;
            return getBundle(ctx, intent, route);
        }

        validateBundleContext(ctx);
        validateUserIntent(ctx, intent);

        MarketActions memory ma = _getAtomicQueueAsyncMarketActions(ctx, intent);

        bundle.ctx = ctx;
        bundle.intent = intent;
        bundle.route.legacyRedemption = true;
        bundle.ma = ma;
        bundle.va.redeem = ma.withdrawCollateral;
        bundle.va.withdraw = Math.mulDiv(ma.withdrawCollateral, intent.minSharePriceE27, 1e27, Math.Rounding.Floor);
    }

    /// @notice Derives market-side actions from target or delta intent.
    /// @param ctx Runtime contracts/addresses used by the bundle.
    /// @param intent User market config, allowances, and price guards.
    /// @return ma Derived market-side actions.
    function getValidMarketActions(BundleContext memory ctx, UserIntent memory intent)
        internal
        view
        returns (MarketActions memory ma)
    {
        (uint256 currentBorrow, uint256 currentCollateral) = getCurrentPosition(ctx, intent.market, ctx.owner);

        if (intent.mode == PositionMode.Target) {
            validatePosition(intent.target, intent.market);
            ma = _getMarketActions(intent.target, currentBorrow, currentCollateral);
        } else {
            ma = _getMarketActions(intent.delta, currentBorrow, currentCollateral);
            Position memory target = Position({
                loan: currentBorrow + ma.borrow - ma.repay,
                collateral: currentCollateral + ma.supplyCollateral - ma.withdrawCollateral
            });
            validatePosition(target, intent.market);
        }

        validateMarketActions(ma);
    }

    /// @notice Computes total and owner-funded loan-asset requirements for the bundle.
    /// @param ctx Runtime contracts/addresses used by the bundle.
    /// @param ma Derived market-side actions.
    /// @param va Derived vault-side actions.
    /// @return requiredLoanAssets Total loan assets needed by repay + deposit legs.
    /// @return requiredDepositLoanAssets Owner-funded assets needed for deposit after endogenous sources.
    /// @return requiredRepayLoanAssets Owner-funded assets needed for repay after redeem sourcing.
    function getRequiredLoanAssets(
        BundleContext memory ctx,
        MarketActions memory ma,
        VaultActions memory va,
        RouteInput memory route
    )
        internal
        view
        returns (uint256 requiredLoanAssets, uint256 requiredDepositLoanAssets, uint256 requiredRepayLoanAssets)
    {
        // Required loan assets are those needed to repay debt and deposit assets into the vault.
        requiredLoanAssets = ma.repay + va.deposit;

        if (ma.repay == 0) {
            // No redeem leg: borrow is the only endogenous loan-asset source.
            requiredDepositLoanAssets = va.deposit.saturatingSub(ma.borrow);
            return (requiredLoanAssets, requiredDepositLoanAssets, 0);
        }

        // Use fee-aware previews so the planning estimate matches the actual post-fee assets
        // the redeem will produce at execution time. Legacy redemption goes through the teller
        // which does not charge redemption fees, so use gross conversion.
        uint256 withdrawCollateralLoanAssets;
        if (route.legacyRedemption) {
            withdrawCollateralLoanAssets = ma.withdrawCollateral.convertToAssets(ctx.vault, Math.Rounding.Floor);
        } else if (route.instantRedeem) {
            (withdrawCollateralLoanAssets,) = ctx.vault.previewInstantRedeem(ma.withdrawCollateral);
        } else {
            (withdrawCollateralLoanAssets,) = ctx.vault.previewFulfillRedeem(ma.withdrawCollateral);
        }

        uint256 redeemForRepay = Math.min(withdrawCollateralLoanAssets, ma.repay);
        requiredRepayLoanAssets = ma.repay - redeemForRepay;

        uint256 redeemRemainder = withdrawCollateralLoanAssets - redeemForRepay;
        requiredDepositLoanAssets = va.deposit.saturatingSub(redeemRemainder);
    }

    /// @notice Reads the current Morpho borrow and collateral position for an owner.
    /// @param ctx Runtime contracts/addresses used by the bundle.
    /// @param market Market to query.
    /// @param owner Position owner.
    /// @return borrow Current borrowed assets.
    /// @return collateral Current collateral shares.
    function getCurrentPosition(BundleContext memory ctx, MarketParams memory market, address owner)
        internal
        view
        returns (uint256 borrow, uint256 collateral)
    {
        IMorpho morpho = ctx.morpho;
        Id marketId = market.id();
        MorphoPosition memory position = morpho.position(marketId, owner);
        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) =
            MorphoBalancesLib.expectedMarketBalances(morpho, market);

        borrow = uint256(position.borrowShares).toAssetsUp(totalBorrowAssets, totalBorrowShares);
        collateral = uint256(position.collateral);
    }

    /* VALIDATION METHODS */

    /// @dev Validates that deltas are non-conflicting and non-empty.
    /// @param ma Derived market-side actions.
    function validateMarketActions(MarketActions memory ma) internal pure {
        uint256 deltaLoanAssets = ma.borrow + ma.repay;
        uint256 deltaCollateral = ma.supplyCollateral + ma.withdrawCollateral;
        if (ma.borrow != 0 && ma.repay != 0) {
            revert NestBundleErrors.BorrowAndRepayCannotBothBeNonZero(ma.borrow, ma.repay);
        }
        if (ma.supplyCollateral != 0 && ma.withdrawCollateral != 0) {
            revert NestBundleErrors.SupplyAndWithdrawCannotBothBeNonZero(ma.supplyCollateral, ma.withdrawCollateral);
        }
        if (deltaLoanAssets + deltaCollateral == 0) revert NestBundleErrors.AtLeastOneActionMustBeNonZero();
    }

    /// @dev Validates that target borrow does not exceed LLTV-constrained maximum.
    /// @param target Target position.
    /// @param market Market used to compute max borrow.
    function validatePosition(Position memory target, MarketParams memory market) internal view {
        if (target.loan == 0) return;

        uint256 collateralValue = market.convertToAssets(target.collateral);
        uint256 maxBorrow = collateralValue.wMulDown(market.lltv);

        if (target.loan > maxBorrow) revert NestBundleErrors.TargetLtvExceedsMarketMax(target.loan, maxBorrow);
    }

    /// @dev Validates core user intent input fields.
    /// @dev Action-level delta validity is checked separately via `validateMarketActions`.
    /// @param ctx Runtime contracts/addresses used by the bundle.
    /// @param intent User market config, allowances, and price guards.
    function validateUserIntent(BundleContext memory ctx, UserIntent memory intent) internal view {
        // Check slippage guards are mutually compatible.
        if (intent.maxSharePriceE27 == 0) revert NestBundleErrors.ZeroMaxSharePrice();
        if (intent.minSharePriceE27 > intent.maxSharePriceE27) {
            revert NestBundleErrors.MinSharePriceExceedsMaxSharePrice(intent.minSharePriceE27, intent.maxSharePriceE27);
        }

        // Check if the market exists.
        Id id = intent.market.id();
        if (ctx.morpho.market(id).lastUpdate == 0) {
            revert NestBundleErrors.MarketNotInitialized(Id.unwrap(id));
        }

        // Market collateral token must match vault share token for correct share-asset conversions and redemption sourcing.
        address vaultShareToken = ctx.vault.share();
        if (intent.market.collateralToken != vaultShareToken) {
            revert NestBundleErrors.MarketCollateralMustEqualVaultShare(intent.market.collateralToken, vaultShareToken);
        }

        // Market loan token must match vault asset token for correct loan-asset planning and execution.
        address vaultAssetToken = ctx.vault.asset();
        if (intent.market.loanToken != vaultAssetToken) {
            revert NestBundleErrors.MarketLoanTokenMustEqualVaultAsset(intent.market.loanToken, vaultAssetToken);
        }

        // Target mode requires delta to be zeroed to avoid conflicting inputs.
        // Delta mode requires target to be zeroed to ensure intent is fully captured by deltas.
        bool isTargetZero = intent.target.loan == 0 && intent.target.collateral == 0;
        bool isDeltaZero = intent.delta.borrow == 0 && intent.delta.repay == 0 && intent.delta.supplyCollateral == 0
            && intent.delta.withdrawCollateral == 0;
        if (intent.mode == PositionMode.Target) {
            if (!isDeltaZero) revert NestBundleErrors.TargetModeRequiresZeroDeltaPosition();
        } else {
            if (!isTargetZero) revert NestBundleErrors.DeltaModeRequiresZeroTargetPosition();
        }
    }

    /// @dev Validates route flags are mutually compatible.
    /// @param route Route flags selecting deposit/redemption paths.
    function validateRouteInput(RouteInput memory route) internal pure {
        if (route.legacyRedemption && route.instantRedeem) {
            revert NestBundleErrors.LegacyRedemptionCannotUseInstantRedeem();
        }
    }

    /// @dev Validates mandatory context addresses.
    /// @param ctx Runtime contracts/addresses used by the bundle.
    function validateBundleContext(BundleContext memory ctx) internal pure {
        if (address(ctx.morpho) == address(0)) revert NestBundleErrors.ZeroAddress("Morpho");
        if (ctx.adapter == address(0)) revert NestBundleErrors.ZeroAddress("Adapter");
        if (ctx.bundler == address(0)) revert NestBundleErrors.ZeroAddress("Bundler");
        if (address(ctx.vault) == address(0)) revert NestBundleErrors.ZeroAddress("Vault");
        if (ctx.teller == address(0)) revert NestBundleErrors.ZeroAddress("Teller");
        if (ctx.predicateProxy == address(0)) revert NestBundleErrors.ZeroAddress("PredicateProxy");
        if (ctx.initiator == address(0)) revert NestBundleErrors.ZeroAddress("Initiator");
        if (ctx.owner == address(0)) revert NestBundleErrors.ZeroAddress("Owner");
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Builds vault actions, enforces allowances/liquidity, and finalizes market actions.
    /// @param ctx Runtime contracts/addresses used by the bundle.
    /// @param intent User market config, allowances, and price guards.
    /// @param route Route flags selecting deposit/redemption paths.
    /// @param ma Derived market-side actions.
    /// @return bundle Fully derived bundle.
    function _buildBundle(
        BundleContext memory ctx,
        UserIntent memory intent,
        RouteInput memory route,
        MarketActions memory ma
    ) private view returns (Bundle memory bundle) {
        bundle.ctx = ctx;
        bundle.intent = intent;
        bundle.route = route;

        VaultActions memory va;
        uint256 ownerShareBalance = ctx.vault.getShareBalance(ctx.owner);
        uint256 maxPullShares = Math.min(ownerShareBalance, ma.supplyCollateral);

        if (intent.shareAllowance == type(uint256).max) {
            va.pullShares = maxPullShares;
        } else {
            va.pullShares = Math.min(intent.shareAllowance, maxPullShares);
        }

        // Owner shares offset the collateral mint leg.
        va.mint = ma.supplyCollateral - va.pullShares;
        if (va.mint == 0) {
            va.deposit = 0;
        } else if (route.legacyDeposit) {
            va.deposit = va.mint.convertToAssets(ctx.vault, Math.Rounding.Ceil);
        } else {
            va.deposit = ctx.vault.previewMint(va.mint);
        }

        (uint256 requiredLoanAssets, uint256 requiredDepositLoanAssets, uint256 requiredRepayLoanAssets) =
            getRequiredLoanAssets(ctx, ma, va, route);

        uint256 requiredOwnerLoanAssets = requiredDepositLoanAssets + requiredRepayLoanAssets;
        uint256 ownerLoanAssetBalance = ctx.vault.getAssetBalance(ctx.owner);

        if (intent.assetAllowance != type(uint256).max && intent.assetAllowance < requiredOwnerLoanAssets) {
            revert NestBundleErrors.OwnerLoanAssetsBelowRequired(intent.assetAllowance, requiredOwnerLoanAssets);
        }
        va.pullAssets = requiredOwnerLoanAssets;

        // Adapter pulls from `initiator`, so owner-funded paths require owner == initiator.
        // `redeemForRepay` assets don't count towards `requiredOwnerLoanAssets`.
        if (requiredOwnerLoanAssets != 0 || va.pullShares != 0) {
            if (ctx.owner != ctx.initiator) {
                revert NestBundleErrors.OwnerMustBeInitiatorWhenPullingBalances(ctx.owner, ctx.initiator);
            }
        }
        if (ownerLoanAssetBalance < va.pullAssets) {
            revert NestBundleErrors.InsufficientOwnerLoanAssets(ownerLoanAssetBalance, va.pullAssets);
        }

        uint256 flashLoanAssets = requiredLoanAssets - va.pullAssets;

        // Redeem is only needed for deleverage-style flows where the callback repays debt.
        // Legacy redemption goes through the teller which has no redemption fees, so use
        // gross conversion. Modern paths use the exact fee-inversion formula.
        if (ma.repay == 0 || flashLoanAssets == 0) {
            va.redeem = 0;
        } else if (route.legacyRedemption) {
            va.redeem = flashLoanAssets.convertToShares(ctx.vault, Math.Rounding.Ceil);
        } else if (route.instantRedeem) {
            va.redeem = ctx.vault.getMinRedeemShares(flashLoanAssets, NestVaultCoreTypes.Fees.InstantRedemption);

            uint256 instantRedeemLiquidity = ctx.vault.getInstantRedeemLiquidity();
            if (va.redeem > instantRedeemLiquidity) {
                revert NestBundleErrors.InsufficientInstantRedeemLiquidity(va.redeem, instantRedeemLiquidity);
            }
        } else {
            va.redeem = ctx.vault.getMinRedeemShares(flashLoanAssets, NestVaultCoreTypes.Fees.Redemption);

            // Reject bundles where the flat fee exceeds FEE_CAP (20%) of the gross assets the redeem would produce.
            (, uint256 flatFee) = ctx.vault.fees(NestVaultCoreTypes.Fees.Redemption);
            if (flatFee > 0 && va.redeem > 0) {
                uint256 grossAssets = va.redeem.convertToAssets(ctx.vault, Math.Rounding.Floor);
                if (
                    grossAssets == 0
                        || Math.mulDiv(flatFee, NestVaultAccountingLogic.FEE_DENOMINATOR, grossAssets)
                            > NestVaultCoreTypes.FEE_CAP
                ) {
                    revert NestBundleErrors.RedeemTooSmallForFlatFee(va.redeem, grossAssets, flatFee);
                }
            }
        }

        if (va.redeem > 0 && va.redeem > ma.withdrawCollateral) {
            revert NestBundleErrors.InsufficientCollateralForRedeem(va.redeem, ma.withdrawCollateral);
        }

        if (va.deposit != 0) {
            if (route.legacyDeposit) {
                if (!_canCall(ctx.predicateProxy, ctx.teller, TellerWithMultiAssetSupport.deposit.selector)) {
                    revert NestBundleErrors.IncompatibleContext(ctx.predicateProxy, ctx.teller);
                }
            } else if (!_canCall(ctx.predicateProxy, address(ctx.vault), ERC4626.mint.selector)) {
                revert NestBundleErrors.IncompatibleContext(ctx.predicateProxy, address(ctx.vault));
            }
        }

        bundle.ma = ma;
        bundle.va = va;
    }

    /// @dev returns the market actions derived from a target intent, given the current position.
    function _getMarketActions(Position memory target, uint256 currentBorrow, uint256 currentCollateral)
        private
        pure
        returns (MarketActions memory ma)
    {
        ma.borrow = target.loan.saturatingSub(currentBorrow);
        ma.repay = currentBorrow.saturatingSub(target.loan);
        ma.supplyCollateral = target.collateral.saturatingSub(currentCollateral);
        ma.withdrawCollateral = currentCollateral.saturatingSub(target.collateral);
    }

    /// @dev returns the market actions derived from a delta intent, given the current position.
    function _getMarketActions(MarketActions memory delta, uint256 currentBorrow, uint256 currentCollateral)
        private
        pure
        returns (MarketActions memory ma)
    {
        if (delta.repay > currentBorrow) {
            revert NestBundleErrors.RepayExceedsCurrentBorrow(delta.repay, currentBorrow);
        }
        if (delta.withdrawCollateral > currentCollateral) {
            revert NestBundleErrors.WithdrawExceedsCurrentCollateral(delta.withdrawCollateral, currentCollateral);
        }

        ma = delta;
    }

    /// @dev Legacy AtomicQueue unloops only need current-position caps; they intentionally skip post-withdraw LTV checks.
    function _getAtomicQueueAsyncMarketActions(BundleContext memory ctx, UserIntent memory intent)
        private
        view
        returns (MarketActions memory ma)
    {
        if (intent.mode == PositionMode.Target) return getValidMarketActions(ctx, intent);

        (uint256 currentBorrow, uint256 currentCollateral) = getCurrentPosition(ctx, intent.market, ctx.owner);
        ma = _getMarketActions(intent.delta, currentBorrow, currentCollateral);
        validateMarketActions(ma);
    }

    /* BUNDLE SPLITTING */

    /// @notice Returns whether the bundle can execute entirely in the owner-sync phase.
    function isSyncRedeem(Bundle memory bundle) internal pure returns (bool) {
        return bundle.route.instantRedeem || bundle.va.redeem == 0;
    }

    /// @notice Returns whether a bundle contains at least one non-zero market action.
    function hasActions(Bundle memory bundle) internal pure returns (bool) {
        return bundle.ma.borrow != 0 || bundle.ma.repay != 0 || bundle.ma.supplyCollateral != 0
            || bundle.ma.withdrawCollateral != 0;
    }

    /// @notice Derives the owner-sync portion of a bundle for redeem-dependent routes.
    /// @param bundle Fully derived bundle to split.
    /// @return syncBundle Owner-executable phase that can run immediately.
    function getSyncBundle(Bundle memory bundle) internal pure returns (Bundle memory syncBundle) {
        if (isSyncRedeem(bundle)) return bundle;
        if (!hasActions(bundle)) return syncBundle;

        uint256 pullAssetsForRepay =
            bundle.va.pullAssets > bundle.va.deposit ? bundle.va.pullAssets - bundle.va.deposit : 0;

        syncBundle = abi.decode(abi.encode(bundle), (Bundle));
        syncBundle.va.redeem = 0;
        syncBundle.ma.repay = pullAssetsForRepay;
        syncBundle.ma.withdrawCollateral = 0;

        if (!hasActions(syncBundle)) return _emptyBundle();
    }

    /// @notice Derives the later async portion of a bundle for redeem-dependent routes.
    /// @param bundle Fully derived bundle to split.
    /// @return asyncBundle Redeem-dependent phase intended for later execution.
    function getAsyncBundle(Bundle memory bundle) internal pure returns (Bundle memory asyncBundle) {
        if (isSyncRedeem(bundle) || !hasActions(bundle)) return asyncBundle;

        asyncBundle = abi.decode(abi.encode(bundle), (Bundle));
        uint256 pullAssetsForRepay =
            bundle.va.pullAssets > bundle.va.deposit ? bundle.va.pullAssets - bundle.va.deposit : 0;
        asyncBundle.va.mint = 0;
        asyncBundle.va.deposit = 0;
        asyncBundle.va.pullAssets = 0;
        asyncBundle.va.pullShares = 0;
        asyncBundle.ma.borrow = 0;
        asyncBundle.ma.supplyCollateral = 0;
        asyncBundle.ma.repay = asyncBundle.ma.repay - pullAssetsForRepay;
        asyncBundle.ma.withdrawCollateral = bundle.ma.withdrawCollateral;

        if (!hasActions(asyncBundle)) return _emptyBundle();
    }

    /// @dev Returns a default-initialized empty bundle.
    function _emptyBundle() private pure returns (Bundle memory) {}

    /// @dev Checks if `caller` can call `functionSig` on `target` via `target`'s authority.
    /// @param caller The address attempting to call the function.
    /// @param target The address of the contract being called.
    /// @param functionSig The function signature being called.
    /// @return True if the call is allowed, false otherwise.
    function _canCall(address caller, address target, bytes4 functionSig) private view returns (bool) {
        return Authority(Auth(target).authority()).canCall(caller, target, functionSig);
    }
}
