// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title  Constants
/// @notice Centralized, compile-time values shared by the CCTP relayer stack
library Constants {
    /// @notice Canonical zero address sentinel used in validation gates.
    address internal constant ADDRESS_ZERO = address(0);

    /// @notice Byte-length of an Ethereum address used when slicing hook data.
    uint256 internal constant ADDRESS_BYTE_LENGTH = 20;

    /// @notice Hook status marker for messages without a hook.
    bytes32 internal constant NO_HOOK_HASH = bytes32(0);

    /// @notice Hook status marker for successfully executed hooks.
    bytes32 internal constant RECEIVED_HOOK_HASH = bytes32(uint256(1));

    /// @notice Hook status marker for refunded messages.
    bytes32 internal constant REFUNDED_MESSAGE_HASH = bytes32(uint256(2));
}
