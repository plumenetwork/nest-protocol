// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

contract Events {
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    /// @dev   Emitted when an instant redemption is performed
    /// @param shares        uint256  Number of shares redeemed
    /// @param assets        uint256  Total asset value of the redeemed shares before fees
    /// @param postFeeAmount uint256  Asset amount received by the user after deducting fees
    /// @param receiver      address  Address receiving the redeemed assets
    event InstantRedeem(uint256 shares, uint256 assets, uint256 postFeeAmount, address receiver);

    /// @dev   Emitted when a redemption request is updated
    /// @param controller  address  The vault or controller managing the redemption
    /// @param owner       address  The owner of the shares being redeemed
    /// @param caller      address  The address initiating the update
    /// @param oldShares   uint256  Number of shares before the update
    /// @param newShares   uint256  Number of shares after the update
    event RedeemUpdated(address controller, address owner, address caller, uint256 oldShares, uint256 newShares);
}
