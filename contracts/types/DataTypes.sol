// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

/// @title  DataTypes Library
/// @notice This library defines common data structures used in the project for managing
///         pending and claimable redeem information.
/// @dev    The library includes `PendingRedeem` and `ClaimableRedeem` structs for tracking
///         the respective states in the system.
library DataTypes {
    /// @dev   This struct holds the shares of a pending redemption.
    /// @param shares uint256 The number of shares that are pending redemption.
    struct PendingRedeem {
        uint256 shares;
    }

    /// @dev   This struct holds the assets and shares of a claimable redemption.
    /// @param assets uint256 The amount of assets that can be redeemed.
    /// @param shares uint256 The number of shares associated with the claimable redemption.
    struct ClaimableRedeem {
        uint256 assets;
        uint256 shares;
    }

    // Configurable fees
    enum Fees {
        InstantRedemption
    }

    /// @param payoutAddress                  address the address `claimFees` sends fees to
    /// @param feesOwedInBase                 uint128 total pending fees owed in terms of base
    /// @param totalSharesLastUpdate          uint128 total amount of shares the last exchange rate update
    /// @param exchangeRate                   uint96  the current exchange rate in terms of base
    /// @param allowedExchangeRateChangeUpper uint32  the max allowed change to exchange rate from an update
    /// @param allowedExchangeRateChangeLower uint32  the min allowed change to exchange rate from an update
    /// @param lastUpdateTimestamp            uint64  the block timestamp of the last exchange rate update
    /// @param isPaused                       bool    whether or not this contract is paused
    /// @param minimumUpdateDelayInSeconds    uint32  the minimum amount of time that must pass between
    ///                                               exchange rate updates, such that the update won't trigger
    ///                                               the contract to be paused
    /// @param managementFee                  uint32  the management fee
    struct AccountantState {
        address payoutAddress;
        uint128 feesOwedInBase;
        uint128 totalSharesLastUpdate;
        uint96 exchangeRate;
        uint32 allowedExchangeRateChangeUpper;
        uint32 allowedExchangeRateChangeLower;
        uint64 lastUpdateTimestamp;
        bool isPaused;
        uint32 minimumUpdateDelayInSeconds;
        uint32 managementFee;
    }
}
