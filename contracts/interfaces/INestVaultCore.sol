// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {AccountantWithRateProviders} from "@boring-vault/src/base/Roles/AccountantWithRateProviders.sol";
import {DataTypes} from "contracts/types/DataTypes.sol";
import {IERC7540Redeem} from "contracts/interfaces/IERC7540.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title  INestVaultCore
/// @notice Interface for interacting with the Nest vault core logic without importing the full implementation
interface INestVaultCore is IERC7540Redeem, IERC4626 {
    /// @notice Performs an instant redemption of shares for assets, applying the instant redemption fee
    /// @param _shares    Number of shares to redeem
    /// @param _receiver  Address receiving the assets
    /// @param _owner     Address that owns the shares
    /// @return _postFeeAmount Assets received after fees
    /// @return _feeAmount     Fee amount retained by the vault
    function instantRedeem(uint256 _shares, address _receiver, address _owner)
        external
        returns (uint256 _postFeeAmount, uint256 _feeAmount);

    /// @notice Fulfills a pending redeem request and makes assets claimable for the controller
    /// @param _controller Controller address associated with the request
    /// @param _shares     Number of shares to fulfill
    /// @return _assets    Assets made claimable for the controller
    function fulfillRedeem(address _controller, uint256 _shares) external returns (uint256 _assets);

    /// @notice Updates the number of shares in an existing redeem request
    /// @param _newShares  New amount of shares to request
    /// @param _controller Controller address for the request
    /// @param _owner      Owner of the shares being updated
    function updateRedeem(uint256 _newShares, address _controller, address _owner) external;

    /// @notice Updates the accountant with rate providers reference
    /// @param _accountantWithRateProviders Address of the accountant contract
    function setAccountantWithRateProviders(address _accountantWithRateProviders) external;

    /// @notice Sets a fee for the given fee type
    /// @param _f   Fee type identifier
    /// @param _fee Fee value in ppm
    function setFee(DataTypes.Fees _f, uint32 _fee) external;

    /// @notice Enables or disables the usage of the external rate provider
    /// @param _set Boolean flag to toggle rate provider usage
    function setUseRateProvider(bool _set) external;

    /// @notice Returns the configured fee for the given fee type
    /// @param _f Fee type identifier
    /// @return _fee Fee value in ppm
    function fees(DataTypes.Fees _f) external view returns (uint32 _fee);

    /// @notice Indicates whether the rate provider is currently used for conversions
    /// @return Boolean flag for rate provider usage
    function useRateProvider() external view returns (bool);

    /// @notice Minimum allowed rate for exchange calculations
    /// @return Minimum rate value
    function minRate() external view returns (uint256);

    /// @notice Total shares pending redemption across all controllers
    /// @return Total pending shares
    function totalPendingShares() external view returns (uint256);

    /// @notice Maximum fee that can be applied for a given fee type
    /// @param _f Fee type identifier
    /// @return Maximum fee value in ppm
    function maxFees(DataTypes.Fees _f) external view returns (uint32);

    /// @notice Tracks whether an authorization nonce has already been used for a controller
    /// @param _controller Controller address
    /// @param _nonce      Authorization nonce
    /// @return Whether the nonce has been consumed
    function authorizations(address _controller, bytes32 _nonce) external view returns (bool);

    /// @notice Returns the accountant contract used to fetch conversion rates
    /// @return AccountantWithRateProviders instance
    function accountantWithRateProviders() external view returns (AccountantWithRateProviders);

    /// @notice Returns the configured management fee
    /// @return Management fee value in ppm
    function getManagementFee() external view returns (uint256);

    /// @notice Previews the result of an instant redemption of shares for assets
    /// @param _shares          Number of shares to redeem
    /// @return _postFeeAmount  Assets received after fees
    /// @return _feeAmount      Fee amount retained by the vault
    function previewInstantRedeem(uint256 _shares) external view returns (uint256 _postFeeAmount, uint256 _feeAmount);

    /// @notice Authorizes an operator for a controller, using a signature to validate
    /// @dev    The authorization is verified via EIP712 signatures, ensuring security and non-repudiation
    /// @param  _controller address The controller's address
    /// @param  _operator   address The operator's address
    /// @param  _approved   bool    Whether the operator is approved or not
    /// @param  _nonce      bytes32 A unique identifier for the authorization
    /// @param  _deadline   uint256 The deadline for the authorization
    /// @param  _signature  bytes   The signature to validate the authorization
    /// @return _success   bool    A boolean indicating the success of the operation
    function authorizeOperator(
        address _controller,
        address _operator,
        bool _approved,
        bytes32 _nonce,
        uint256 _deadline,
        bytes memory _signature
    ) external returns (bool _success);
}
