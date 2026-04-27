// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title  NestVaultAccountingLogic
/// @notice Library containing common accounting utilities for NestVault operations
/// @dev    View/pure functions for share/asset conversions and fee calculations
/// @author plumenetwork
library NestVaultAccountingLogic {
    using Math for uint256;

    /// @notice Converts shares to assets using the provided rate
    /// @param  _shares   uint256 The shares to convert
    /// @param  _rate     uint256 The exchange rate
    /// @param  _share    NestShareOFT Share token used to derive decimals
    /// @param  _rounding Math.Rounding The rounding direction
    /// @return _assets   uint256 The calculated assets
    function convertToAssets(uint256 _shares, uint256 _rate, NestShareOFT _share, Math.Rounding _rounding)
        internal
        pure
        returns (uint256 _assets)
    {
        _assets = _shares.mulDiv(_rate, oneShare(_share), _rounding);
    }

    /// @notice Converts assets to shares using the provided rate
    /// @param  _assets   uint256 The assets to convert
    /// @param  _rate     uint256 The exchange rate
    /// @param  _share    NestShareOFT Share token used to derive decimals
    /// @param  _rounding Math.Rounding The rounding direction
    /// @return _shares   uint256 The calculated shares
    function convertToShares(uint256 _assets, uint256 _rate, NestShareOFT _share, Math.Rounding _rounding)
        internal
        pure
        returns (uint256 _shares)
    {
        _shares = _assets.mulDiv(oneShare(_share), _rate, _rounding);
    }

    /// @notice Calculates fee amount from assets
    /// @param  _assets  uint256 The asset amount
    /// @param  _feeRate uint32  The fee rate (denominated in 1e6, e.g., 5000 = 0.5%)
    /// @return _fee     uint256 The calculated fee amount
    function calculateFee(uint256 _assets, uint32 _feeRate) internal pure returns (uint256 _fee) {
        if (_feeRate == 0) return 0;
        _fee = _assets.mulDiv(_feeRate, 1_000_000, Math.Rounding.Floor);
    }

    /// @notice Calculates post-fee amount and fee from assets
    /// @param  _assets        uint256 The asset amount
    /// @param  _feeRate       uint32  The fee rate (denominated in 1e6)
    /// @return _postFeeAmount uint256 The amount after fees
    /// @return _feeAmount     uint256 The fee amount
    function calculatePostFeeAmounts(uint256 _assets, uint32 _feeRate)
        internal
        pure
        returns (uint256 _postFeeAmount, uint256 _feeAmount)
    {
        if (_feeRate == 0) return (_assets, 0);
        _feeAmount = _assets.mulDiv(_feeRate, 1_000_000, Math.Rounding.Floor);
        _postFeeAmount = _assets - _feeAmount;
    }

    /// @notice Returns the scaling factor for one share based on its decimals
    /// @param  _share NestShareOFT Share token used to derive decimals
    /// @return uint256 The scaling factor representing one share
    function oneShare(NestShareOFT _share) internal pure returns (uint256) {
        return 10 ** _share.decimals();
    }
}
