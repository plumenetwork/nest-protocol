// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";

/// @title  NestVaultCoreTypes
/// @notice Library containing storage struct and type definitions for NestVaultCore
/// @dev    Extracted to allow sharing between NestVaultCore and its libraries
/// @author plumenetwork
library NestVaultCoreTypes {
    /*//////////////////////////////////////////////////////////////
                            STORAGE STRUCT
    //////////////////////////////////////////////////////////////*/

    /// @notice Storage struct for NestVaultCore
    /// @dev    Used by library functions that need access to full storage
    struct NestVaultCoreStorage {
        // It represents the smallest allowed rate
        uint256 minRate;
        // This value is updated whenever a user requests or claims a redeem. It helps track the total shares
        // that are locked in pending redemptions and not available for new operations
        uint256 totalPendingShares;
        // This variable is used to determine the conversion rates between assets and shares, enabling accurate
        // calculation of deposits, withdrawals, and redemptions.
        NestHubAccountant accountant;
        // This mapping stores whether a given operator is authorized for a particular controller. It allows operators
        // to perform certain actions on behalf of the controller.
        mapping(address => mapping(address => bool)) isVaultOperator;
        // This mapping prevents replay attacks by ensuring that authorizations cannot be reused.
        mapping(address controller => mapping(bytes32 nonce => bool used)) authorizations;
        // This mapping holds the shares of assets that are currently pending for redemption for a specific controller.
        mapping(address => PendingRedeem) pendingRedeem;
        // This mapping tracks the claimable amount of assets and shares for each controller once the redemption request
        // has been fulfilled.
        mapping(address => ClaimableRedeem) claimableRedeem;
        /// Maximum fee configuration per fee type. The `rate` field caps the percentage fee (e.g. 200000 = 20%).
        /// The `flat` field caps the flat fee (defaults to 0; must be raised before setting a non-zero flat fee).
        mapping(Fees => Fee) maxFees;
        /// Active fee configuration per fee type. The total fee charged is `flat + floor(gross * rate / 1e6)`.
        mapping(Fees => Fee) fees;
        /// Tracks accrued and claimable assets per fee type (includes both flat and percentage components).
        mapping(Fees => uint256) claimableFees;
        // The address of the operator registry contract, which manages operator authorizations
        OperatorRegistry operatorRegistry;
    }

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
        InstantRedemption,
        Deposit,
        Redemption
    }

    /// @notice Fee configuration combining percentage rate and flat fee
    /// @dev    Total fee for an operation is `flat + floor(gross * rate / 1e6)`.
    ///         Storage-compatible with the old `uint32` layout: `rate` occupies the same
    ///         slot position as the former bare uint32 value; `flat` falls into a new slot
    ///         that defaults to zero.
    /// @param  rate uint32  Percentage fee rate (1e6 = 100%, e.g. 5000 = 0.5%)
    /// @param  flat uint256 Flat fee in asset token smallest units (e.g. 100000 = $0.10 for 6-decimal USDC)
    struct Fee {
        uint32 rate;
        uint256 flat;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev The percentage fee rate cap, denominated in 1e6. Maximum 20%.
    uint32 internal constant FEE_CAP = 0.2e6;

    /// @dev Maximum exchange rate allowed
    uint256 internal constant UPPER_BOUND_RATE_CAP = 1e30;
}
