// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {AccountantWithRateProviders} from "@boring-vault/src/base/Roles/AccountantWithRateProviders.sol";

/// @title BoringVaultSYStorage
/// @author PlumeNetwork
/// @notice Storage layout for BoringVaultSY, separated for upgrade safety
/// @dev Contains reserved storage gaps for future upgrades to prevent layout conflicts
contract BoringVaultSYStorage {
    /// @notice The accountant with rate providers used to retrieve the conversion rate of assets.
    /// @dev This variable is used to determine the conversion rates between assets and shares, enabling accurate
    ///      calculation of deposits, withdrawals, and redemptions.
    AccountantWithRateProviders public accountantWithRateProviders;

    /// @dev Reserved space for future upgrades to ensure backward compatibility.
    uint256[50] private __gap;
}
