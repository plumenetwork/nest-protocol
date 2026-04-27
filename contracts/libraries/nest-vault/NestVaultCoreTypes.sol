// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {NestAccountant} from "contracts/NestAccountant.sol";
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
        NestAccountant accountant;
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
        /// The `maxFees` mapping associates each fee type in `Fees` with its corresponding maximum fee percentage.
        /// For example, a value of 200000 represents a maximum fee of 20% (200000 / 1000000).
        /// Authorized users can modify these maximum fees directly through this public mapping.
        mapping(Fees => uint32) maxFees;
        /// The `fees` mapping associates each fee type (Deposit, Redemption, InstantRedemption) with its corresponding fee percentage.
        /// For example, a value of 5000 represents a 0.5% fee (5000 / 1000000).
        ///  Authorized users can modify these fees directly through this public mapping.
        mapping(Fees => uint32) fees;
        // Tracks accrued and claimable assets per fee type.
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
        InstantRedemption
    }
}
