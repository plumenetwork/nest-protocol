// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

/// @title  Errors Library
/// @notice This library defines common error messages used throughout the CCTP integration to ensure
///         better clarity and standardized error handling.
/// @dev    Each error represents a specific failure condition, allowing contracts to handle
///         issues more easily and transparently.
library Errors {
    /// @dev Error thrown when the CCTP message version is invalid
    error InvalidMessageVersion();

    /// @dev Error thrown when the CCTP message body version is invalid
    error InvalidMessageBodyVersion();

    /// @dev Error thrown when the hook type is invalid
    error InvalidHookData();

    /// @dev Error thrown when the hook data length is too short
    error HookDataLengthTooShort();

    /// @dev Error thrown when the composer address is unauthorized
    error UnauthorizedComposer();

    /// @dev Error thrown when the received amount is insufficient
    error InsufficientReceivedAmount();

    /// @dev Error thrown when the composer asset OFT is invalid
    error InvalidComposerAssetOFT();

    /// @dev Error thrown when the composer asset is invalid
    error InvalidComposerAsset();

    /// @dev Error thrown when the message is not found in the message store
    error MessageNotFound();

    /// @dev Error thrown when the message has already been processed
    error MessageReceived();

    /// @dev Error thrown when the message has already been refunded
    error MessageRefunded();

    /// @dev Error thrown when the message nonce is invalid
    error MessageNonceMismatch();

    /// @dev Error thrown when the message transmitter is invalid
    error InvalidMessageTransmitter();

    /// @dev Error thrown when the token messenger is invalid
    error InvalidTokenMessenger();

    /// @dev Error thrown when the USDC address is invalid
    error InvalidUSDC();

    /// @dev Error thrown when message relay fails
    error MessageRelayFailed();

    /// @dev Error thrown when recover to address is invalid
    error InvalidRecoverToAddress();

    /// @dev Error thrown when refund fails
    error RefundFailed();

    /// @dev Error thrown when caller is not self
    error OnlySelf();

    /// @dev Error thrown when hook execution fails
    error HookExecutionFailed();

    /// @dev Error thrown when destination domain is invalid
    error InvalidDestinationDomain();

    /// @dev Error thrown when destination EID is invalid
    error InvalidDestinationEID();

    /// @dev Error thrown when fee is invalid
    error InvalidFee();
}
