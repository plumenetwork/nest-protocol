// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

/// @title NestBundleErrors
/// @notice Custom errors for Nest bundle build and validation flows.
library NestBundleErrors {
    /// @dev Example usage: `ZeroAddress("Morpho")`, `ZeroAddress("LoanToken")`.
    /// @notice A required address parameter was zero.
    /// @param field Label of the missing field.
    error ZeroAddress(string field);
    /// @notice Morpho market has not been initialized with valid parameters.
    /// @param marketId Morpho market id.
    error MarketNotInitialized(bytes32 marketId);
    /// @notice Requested repay is greater than the owner's current borrow.
    /// @param repay Requested repay assets.
    /// @param currentBorrow Current borrowed assets.
    error RepayExceedsCurrentBorrow(uint256 repay, uint256 currentBorrow);
    /// @notice Requested collateral withdrawal is greater than the owner's collateral.
    /// @param withdrawCollateral Requested withdrawal shares.
    /// @param currentCollateral Current supplied collateral shares.
    error WithdrawExceedsCurrentCollateral(uint256 withdrawCollateral, uint256 currentCollateral);
    /// @notice Owner asset allowance is below the amount needed to execute the bundle.
    /// @param allowance Allowed loan assets to pull from owner.
    /// @param requiredLoanAssets Required owner-funded loan assets.
    error OwnerLoanAssetsBelowRequired(uint256 allowance, uint256 requiredLoanAssets);
    /// @notice Pulling owner balances requires owner and initiator to be the same address.
    /// @param owner Bundle owner.
    /// @param initiator Transaction initiator.
    error OwnerMustBeInitiatorWhenPullingBalances(address owner, address initiator);
    /// @notice Owner does not hold enough loan assets for required pulls.
    /// @param ownerBalance Current owner loan-asset balance.
    /// @param requiredPullAssets Required owner-funded assets.
    error InsufficientOwnerLoanAssets(uint256 ownerBalance, uint256 requiredPullAssets);
    /// @notice Instant redeem liquidity is insufficient for requested redeem shares.
    /// @param requestedRedeemShares Shares requested for redeem.
    /// @param availableRedeemShares Shares currently redeemable instantly.
    error InsufficientInstantRedeemLiquidity(uint256 requestedRedeemShares, uint256 availableRedeemShares);
    /// @notice Borrow and repay cannot both be non-zero in the same delta.
    /// @param borrow Requested borrow amount.
    /// @param repay Requested repay amount.
    error BorrowAndRepayCannotBothBeNonZero(uint256 borrow, uint256 repay);
    /// @notice Supply and withdraw collateral cannot both be non-zero in the same delta.
    /// @param supplyCollateral Requested collateral supply.
    /// @param withdrawCollateral Requested collateral withdrawal.
    error SupplyAndWithdrawCannotBothBeNonZero(uint256 supplyCollateral, uint256 withdrawCollateral);
    /// @notice At least one bundle action must be non-zero.
    error AtLeastOneActionMustBeNonZero();

    /// @notice Instant redeem is incompatible with legacy redemption route.
    error LegacyRedemptionCannotUseInstantRedeem();
    /// @notice Legacy deposit requires predicate proxy authorization on teller deposit.
    /// @param predicateProxy Predicate proxy configured in bundle context.
    /// @param teller Teller configured in bundle context.
    error IncompatibleContext(address predicateProxy, address teller);
    /// @notice Maximum share price guard must be non-zero.
    error ZeroMaxSharePrice();
    /// @notice Minimum share price guard cannot exceed the maximum share price guard.
    /// @param minSharePriceE27 Minimum share price guard in E27.
    /// @param maxSharePriceE27 Maximum share price guard in E27.
    error MinSharePriceExceedsMaxSharePrice(uint256 minSharePriceE27, uint256 maxSharePriceE27);
    /// @notice Target mode requires delta position to be fully zeroed.
    error TargetModeRequiresZeroDeltaPosition();
    /// @notice Delta mode requires target position to be fully zeroed.
    error DeltaModeRequiresZeroTargetPosition();
    /// @notice Target borrow exceeds market max borrow at target collateral and LLTV.
    /// @param targetBorrow Target borrowed assets.
    /// @param maxBorrow Maximum borrow allowed by LLTV.
    error TargetLtvExceedsMarketMax(uint256 targetBorrow, uint256 maxBorrow);
    /// @notice Market collateral token must match the configured vault share token.
    /// @param marketCollateralToken Collateral token configured in Morpho market.
    /// @param vaultShareToken Share token returned by vault.
    error MarketCollateralMustEqualVaultShare(address marketCollateralToken, address vaultShareToken);
    /// @notice Market loan token must match the configured vault asset token.
    /// @param marketLoanToken Loan token configured in Morpho market.
    /// @param vaultAssetToken Asset token returned by vault.
    error MarketLoanTokenMustEqualVaultAsset(address marketLoanToken, address vaultAssetToken);
    /// @notice Token actions must be normalized into market loan/share tokens before bundle build.
    /// @param token Unsupported token address.
    error UnsupportedBundleToken(address token);
    /// @notice Requested leverage must be non-zero.
    /// @param leverageBps Requested leverage scaled by 1e4.
    error InvalidLeverageBps(uint256 leverageBps);
    /// @notice Final equity would be negative after applying add/remove actions.
    /// @param availableValue Current equity plus added value.
    /// @param requiredValue Current debt plus removed value.
    error NonPositiveFinalEquity(uint256 availableValue, uint256 requiredValue);
    /// @notice A normalized token cannot be both added and removed in the same bundle.
    /// @param token Token being added and removed.
    /// @param addAmount Total normalized add amount.
    /// @param removeAmount Total normalized remove amount.
    error ConflictingNormalizedExternalLegs(address token, uint256 addAmount, uint256 removeAmount);
    /// @notice Requested borrow exceeds currently available market liquidity.
    /// @param requestedBorrow Borrow assets requested by the derived bundle.
    /// @param availableLiquidity Borrowable assets currently available in the market.
    error InsufficientMarketLiquidity(uint256 requestedBorrow, uint256 availableLiquidity);
    /// @notice Requested direct share output is larger than the derived collateral withdrawal.
    /// @param requestedShares Share amount requested by remove actions.
    /// @param availableShares Share amount derivable from the target position.
    error RequestedShareOutExceedsWithdrawable(uint256 requestedShares, uint256 availableShares);
    /// @notice Internal vault exits cannot source the required loan assets.
    /// @param requiredAssets Loan assets required from vault exits.
    /// @param availableAssets Max loan assets obtainable from derived withdrawn shares.
    error InsufficientVaultExitAssets(uint256 requiredAssets, uint256 availableAssets);
    /// @notice AtomicQueue unloop bundles do not support adding new Morpho borrow.
    /// @param borrowAssets Borrow assets requested by explicit market actions.
    error AtomicQueueUnloopBorrowNotSupported(uint256 borrowAssets);
    /// @notice AtomicQueue unloop bundles do not support supplying new collateral.
    /// @param supplyCollateralShares Collateral shares requested by explicit market actions.
    error AtomicQueueUnloopSupplyCollateralNotSupported(uint256 supplyCollateralShares);
    /// @notice AtomicQueue unloop redeem assets must cover at least the requested repay amount.
    /// @param redeemAssets Explicit vault-exit assets to source from the queue redeem.
    /// @param repayAssets Morpho repay assets requested by explicit market actions.
    error AtomicQueueUnloopRedeemAssetsBelowRepay(uint256 redeemAssets, uint256 repayAssets);
    /// @notice A token action declared incompatible output bounds.
    /// @param token Action token.
    /// @param minAmountOut Lower output bound.
    /// @param maxAmountOut Upper output bound.
    error ActionOutputBoundsInvalid(address token, uint256 minAmountOut, uint256 maxAmountOut);
    /// @notice A zero-action sentinel used a non-zero token or non-disabled bounds.
    /// @param token Action token.
    /// @param amount Action amount.
    /// @param minAmountOut Lower output bound.
    /// @param maxAmountOut Upper output bound.
    error InvalidEmptyTokenAction(address token, uint256 amount, uint256 minAmountOut, uint256 maxAmountOut);
    /// @notice Output bounds were set on a leg that does not support them.
    /// @param token Action token.
    /// @param minAmountOut Lower output bound.
    /// @param maxAmountOut Upper output bound.
    error ActionOutputBoundsNotSupported(address token, uint256 minAmountOut, uint256 maxAmountOut);
    /// @notice The derived output for a token action is below its lower bound.
    /// @param token Action token.
    /// @param actualAmountOut Derived output amount.
    /// @param minimumAmountOut Required lower bound.
    error ActionOutputBelowMinimum(address token, uint256 actualAmountOut, uint256 minimumAmountOut);
    /// @notice The derived output for a token action is above its upper bound.
    /// @param token Action token.
    /// @param actualAmountOut Derived output amount.
    /// @param maximumAmountOut Allowed upper bound.
    error ActionOutputAboveMaximum(address token, uint256 actualAmountOut, uint256 maximumAmountOut);
    /// @notice Redeem size is too small relative to the configured flat redemption fee.
    /// @dev fulfillRedeem() reverts with InvalidFee when flat / grossAssets > 20%; reject at build time.
    /// @param redeemShares Shares the bundle would redeem.
    /// @param grossAssets Gross assets the shares convert to at the current rate.
    /// @param flatFee Configured flat redemption fee.
    error RedeemTooSmallForFlatFee(uint256 redeemShares, uint256 grossAssets, uint256 flatFee);
    /// @notice Fee-adjusted redeem shares exceed the adapter's available collateral shares.
    /// @param redeemShares Shares required after fee inflation.
    /// @param withdrawCollateralShares Shares available from Morpho collateral withdrawal.
    error InsufficientCollateralForRedeem(uint256 redeemShares, uint256 withdrawCollateralShares);
}

/// @title NestBundlerErrors
/// @notice Custom errors for NestBundler queueing and authorization flows.
library NestBundlerErrors {
    /// @notice Bundle hash is already queued for owner.
    /// @param owner Owner address.
    /// @param deltaHash Hash of the delta bundle payload.
    error BundleAlreadyQueued(address owner, bytes32 deltaHash);
    /// @notice Bundle hash is not currently queued for owner.
    /// @param owner Owner address.
    /// @param deltaHash Hash of the delta bundle payload.
    error BundleNotQueued(address owner, bytes32 deltaHash);
}

/// @title NestUnlooperErrors
/// @notice Custom errors for NestUnlooper request validation and execution flows.
library NestUnlooperErrors {
    /// @notice The caller does not currently have Morpho collateral to unwind.
    error NoPositionToUnloop();
    /// @notice Requested target leverage is not below the user's current leverage.
    /// @param targetLeverageBps Requested target leverage in basis points where `10_000 = 1x`.
    /// @param currentLeverageBps Current user leverage in basis points where `10_000 = 1x`.
    error TargetLeverageNotBelowCurrent(uint256 targetLeverageBps, uint256 currentLeverageBps);
    /// @notice No modern async-unloop request is stored for the user and market.
    /// @param user Position owner.
    /// @param marketId Morpho market id.
    error UnloopRequestNotSet(address user, bytes32 marketId);
    /// @notice Provided unloop deadline is already in the past.
    /// @param deadline Requested deadline.
    /// @param timestamp Current block timestamp.
    error InvalidUnloopDeadline(uint64 deadline, uint256 timestamp);
    /// @notice Stored unloop request expired before execution.
    /// @param user Position owner.
    /// @param deadline Stored request deadline.
    /// @param timestamp Current block timestamp.
    error UnloopRequestExpired(address user, uint64 deadline, uint256 timestamp);
    /// @notice AtomicQueue metadata was missing or unusable for async-unloop construction.
    /// @param user Position owner.
    /// @param marketId Morpho market id.
    error InvalidAtomicQueueRequest(address user, bytes32 marketId);
    /// @notice Position is underwater (debt exceeds collateral value); cannot compute a meaningful
    ///         target leverage. Use `clearUnloopRequest` to remove the stored request, or wait for
    ///         the position to recover above water.
    /// @param user Position owner.
    /// @param marketId Morpho market id.
    error PositionUnderwater(address user, bytes32 marketId);
    /// @notice Redemption fees consume all available equity, making the partial unloop infeasible.
    /// @param user Position owner.
    /// @param marketId Morpho market id.
    error UnloopFeeInfeasible(address user, bytes32 marketId);
    /// @notice Vault is not on the approved whitelist.
    /// @param vault Address that was rejected.
    error VaultNotApproved(address vault);
    /// @notice Teller is not on the approved whitelist.
    /// @param teller Address that was rejected.
    error TellerNotApproved(address teller);
}
