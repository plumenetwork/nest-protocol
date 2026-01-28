// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IVaultComposerSync, SendParam} from "@layerzerolabs/ovault-evm/contracts/interfaces/IVaultComposerSync.sol";

/// @title  INestVaultComposer
/// @notice Interface for interacting with NestVaultComposer
interface INestVaultComposer is IVaultComposerSync {
    error ShareOFTNotNestShare(address shareOFT);
    error ShareTokenNotVaultShare(address shareToken, address vault);

    /// @notice Deposits ERC20 assets from the caller into the vault and sends them to the recipient,
    ///         adds a custom _depositor for predicate verification on cross-chain deposits
    /// @dev    Callable by RELAYER_ROLE. Requires authorization via the requiresAuth modifier
    /// @param _depositor The depositor (bytes32 format to account for non-evm addresses)
    /// @param _assetAmount The number of ERC20 tokens to deposit and send
    /// @param _sendParam Parameters on how to send the shares to the recipient
    /// @param _refundAddress Address to receive excess `msg.value`
    function depositAndSend(
        bytes32 _depositor,
        uint256 _assetAmount,
        SendParam memory _sendParam,
        address _refundAddress
    ) external payable;

    /// @notice Redeems vault shares and sends the resulting assets to the recipient,
    ///         adds a custom _redeemer for predicate verification on cross-chain redemptions
    /// @dev    Callable by RELAYER_ROLE. Requires authorization via the requiresAuth modifier
    /// @param _redeemer The redeemer (bytes32 format to account for non-evm addresses)
    /// @param _shareAmount The number of vault shares to redeem
    /// @param _sendParam Parameter that defines how to send the assets
    /// @param _refundAddress Address to receive excess payment of the LZ fees
    function redeemAndSend(bytes32 _redeemer, uint256 _shareAmount, SendParam memory _sendParam, address _refundAddress)
        external
        payable;
}
