// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

/// @title  Errors Library
/// @notice This library defines common error messages used throughout the system to ensure
///         better clarity and standardized error handling.
/// @dev    Each error represents a specific failure condition, allowing contracts to handle
///         issues more easily and transparently.
library Errors {
    /// @dev Error thrown when a user is not authorized to perform an action
    error UNAUTHORIZED();

    /// @dev Error thrown when an address is address(0)
    error ZERO_ADDRESS();

    /// @dev Error thrown when the balance is insufficient for a transfer or operation
    error INSUFFICIENT_BALANCE();

    /// @dev Error thrown when the number of shares is zero
    error ZERO_SHARES();

    /// @dev Error thrown when the number of assets is zero
    error ZERO_ASSETS();

    /// @dev Error thrown when there are no pending redeem shares for the specified controller
    error NO_PENDING_REDEEM();

    /// @dev Error thrown when an operation attempts to modify an account's own operator status
    error ERC7540_SELF_OPERATOR_NOT_ALLOWED();

    /// @dev Error thrown when an ERC7540 authorization has expired
    error ERC7540_EXPIRED();

    /// @dev Error thrown when an ERC7540 authorization has already been used
    error ERC7540_USED_AUTHORIZATION();

    /// @dev Error thrown when an invalid signer is detected
    error INVALID_SIGNER();

    /// @dev Error thrown when the payout is set to zero in an ERC7540 operation
    error ERC7540_ZERO_PAYOUT();

    /// @dev Error thrown when there user tries to call restricted function
    error ERC7540_ASYNC_FLOW();

    /// @dev Error thrown when a transfer fails due to insufficient funds or other issues
    error TRANSFER_INSUFFICIENT();

    /// @dev Error thrown when trying to set zero rate
    error INVALID_RATE();

    /// @dev Error thrown when rate out of bounds
    error RATE_OUT_OF_BOUNDS();

    /// @dev Error thrown when unauthorized user tries to perform transaction via predicate proxy
    error NestPredicateProxy__PredicateUnauthorizedTransaction();

    /// @dev Error thrown when fee type is invalid
    error InvalidFee();

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
}
