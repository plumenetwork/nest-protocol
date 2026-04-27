// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title  ITransferHook
/// @notice Interface for pre-transfer validation hooks.
/// @dev    Implementations should revert when a transfer should be blocked.
interface ITransferHook {
    /// @notice Runs validation before a transfer executes.
    /// @param from address The address sending tokens.
    function beforeTransfer(address from) external view;
}
