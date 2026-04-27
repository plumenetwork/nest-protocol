// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/// @title  Errors Library
/// @notice This library defines common error messages used throughout the system to ensure
///         better clarity and standardized error handling.
/// @dev    Each error represents a specific failure condition, allowing contracts to handle
///         issues more easily and transparently.
library Errors {
    /// @dev Error thrown when a caller is not authorized for an account-scoped action
    error Unauthorized();

    /// @dev Error thrown when an address is address(0)
    error ZeroAddress();

    /// @dev Error thrown when the number of shares is zero
    error ZeroShares();

    /// @dev Error thrown when the number of assets is zero
    error ZeroAssets();

    /// @dev Error thrown when a token name or symbol is empty
    error EmptyNameOrSymbol();

    /// @dev Error thrown when there are no pending redeem shares
    error NoPendingRedeem();

    /// @dev Error thrown when requested amount exceeds available balance
    error InsufficientBalance();

    /// @dev Error thrown when requested amount exceeds claimable amount
    error InsufficientClaimable();

    /// @dev Error thrown when transfer amount is lower than expected
    error TransferInsufficient();

    /// @dev Error thrown when trying to use an invalid rate
    error InvalidRate();

    /// @dev Error thrown when rate is outside accepted bounds
    error RateOutOfBounds();

    /// @dev Error thrown when fee exceeds configured max fee
    error InvalidFee();

    /// @dev Error thrown when an operation attempts to modify an account's own operator status
    error ERC7540SelfOperatorNotAllowed();

    /// @dev Error thrown when an ERC7540 authorization has expired
    error ERC7540Expired();

    /// @dev Error thrown when an ERC7540 authorization has already been used
    error ERC7540UsedAuthorization();

    /// @dev Error thrown when an invalid signer is detected for ERC7540 authorization
    error ERC7540InvalidSigner();

    /// @dev Error thrown when the payout is set to zero in an ERC7540 operation
    error ERC7540ZeroPayout();

    /// @dev Error thrown when user attempts to call sync preview functions in async ERC7540 flow
    error ERC7540AsyncFlow();

    /// @dev Error thrown when unauthorized user tries to perform transaction via predicate proxy
    error NestPredicateProxyPredicateUnauthorizedTransaction();

    /// @dev Error thrown when the new upper exchange-rate bound is set below the minimum allowed value
    error UpperBoundTooSmall();

    /// @dev Error thrown when the new lower exchange-rate bound is set above the maximum allowed value
    error LowerBoundTooLarge();

    /// @dev Error thrown when attempting to set a management fee greater than the permitted maximum (20%)
    error ManagementFeeTooLarge();

    /// @dev Error thrown when a function is called while the contract is paused
    error Paused();

    /// @dev Error thrown when attempting to claim fees but no fees are owed
    error ZeroFeesOwed();

    /// @dev Error thrown when a function restricted to the NestShare is called by another address
    error OnlyCallableByNestShare();

    /// @dev Error thrown when the update delay exceeds the maximum allowed duration of 14 days
    error UpdateDelayTooLarge();

    /// @dev Error thrown when exchange-rate update is attempted before minimumUpdateDelayInSeconds elapses
    error MinimumUpdateDelayNotPassed();

    /// @dev Error thrown when a message-only compose operation receives non-zero OFT tokens
    error UnexpectedNonZeroAmount();

    /// @dev Error thrown when an unrecognized redeem type is provided in compose payload
    error UnknownRedeemType();

    /// @dev Error thrown when the share OFT is not a valid NestShare
    error ShareOFTNotNestShare(address shareOFT);

    /// @dev Error thrown when the share token does not match the vault's share token
    error ShareTokenNotVaultShare(address shareToken, address vault);

    /// @dev Error thrown when a recover call fails
    error RecoverFailed();

    /// @dev Error thrown when msg.value is non-zero in a local cross-chain operation
    error NonZeroMsgValueLocal(uint256 msgValue);

    /// @dev Error thrown when attempting to renounce ownership (disabled for upgradeable flow)
    error RenounceOwnershipDisabled();

    /// @dev Error thrown when the accountant does not implement the required rate-provider interface.
    error IncompatibleAccountant();

    /// @dev Error thrown when operator registry does not implement IERC7540Operator.isOperator(address,address)
    error IncompatibleOperatorRegistry();
}
