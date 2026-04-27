// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";

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
    /// @param receiver    address  The address receiving returned shares
    /// @param caller      address  The address initiating the update
    /// @param oldShares   uint256  Number of shares before the update
    /// @param newShares   uint256  Number of shares after the update
    event RedeemUpdated(address controller, address receiver, address caller, uint256 oldShares, uint256 newShares);

    /// @dev   Emitted when a redemption is requested
    /// @param controller  address  The controller address associated with this redeem request
    /// @param owner       address  The owner of the shares being redeemed
    /// @param requestId   uint256  The request ID for the redemption
    /// @param sender      address  The address initiating the request
    /// @param shares      uint256  Number of shares requested for redemption
    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 shares
    );

    /// @dev Emitted when fees are claimed
    /// @param f        NestVaultCoreTypes.Fees The fee type being claimed
    /// @param receiver address The address receiving the claimed fees
    /// @param amount   uint256 The amount of fees claimed
    event FeeClaimed(NestVaultCoreTypes.Fees indexed f, address indexed receiver, uint256 amount);

    /// @dev Emitted when accountant address is updated.
    /// @param oldAccountant The previous accountant address.
    /// @param newAccountant The new accountant address.
    event SetAccountant(address indexed oldAccountant, address indexed newAccountant);
}
