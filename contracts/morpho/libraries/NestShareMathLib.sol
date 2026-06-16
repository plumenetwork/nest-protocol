// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {NestVaultLib} from "./NestVaultLib.sol";

/// @title NestShareMathLib
/// @notice Minimal share/asset conversion helpers using a vault accountant rate.
library NestShareMathLib {
    /// @notice Converts vault shares to assets using the vault's live accountant rate.
    /// @param shares Amount of shares to convert.
    /// @param vault Vault used to fetch `rate` and `oneShare`.
    /// @param rounding OpenZeppelin rounding mode used in `mulDiv`.
    /// @return assets Converted asset amount.
    function convertToAssets(uint256 shares, INestVaultCore vault, Math.Rounding rounding)
        internal
        view
        returns (uint256 assets)
    {
        (uint256 rate, uint256 oneShare) = NestVaultLib.getRate(vault);
        assets = Math.mulDiv(shares, rate, oneShare, rounding);
    }

    /// @notice Converts assets to vault shares using the vault's live accountant rate.
    /// @param assets Amount of assets to convert.
    /// @param vault Vault used to fetch `rate` and `oneShare`.
    /// @param rounding OpenZeppelin rounding mode used in `mulDiv`.
    /// @return shares Converted share amount.
    function convertToShares(uint256 assets, INestVaultCore vault, Math.Rounding rounding)
        internal
        view
        returns (uint256 shares)
    {
        (uint256 rate, uint256 oneShare) = NestVaultLib.getRate(vault);
        shares = Math.mulDiv(assets, oneShare, rate, rounding);
    }

    /// @notice Converts shares to assets using explicit conversion inputs.
    /// @param shares Amount of shares to convert.
    /// @param rate Accountant quote per share.
    /// @param oneShare Base units representing one share.
    /// @param rounding OpenZeppelin rounding mode used in `mulDiv`.
    /// @return assets Converted asset amount.
    function convertToAssets(uint256 shares, uint256 rate, uint256 oneShare, Math.Rounding rounding)
        internal
        pure
        returns (uint256 assets)
    {
        assets = Math.mulDiv(shares, rate, oneShare, rounding);
    }

    /// @notice Converts assets to shares using explicit conversion inputs.
    /// @param assets Amount of assets to convert.
    /// @param rate Accountant quote per share.
    /// @param oneShare Base units representing one share.
    /// @param rounding OpenZeppelin rounding mode used in `mulDiv`.
    /// @return shares Converted share amount.
    function convertToShares(uint256 assets, uint256 rate, uint256 oneShare, Math.Rounding rounding)
        internal
        pure
        returns (uint256 shares)
    {
        shares = Math.mulDiv(assets, oneShare, rate, rounding);
    }
}
