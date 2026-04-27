// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {Errors} from "contracts/types/Errors.sol";
import {NestVaultCoreValidationLogic} from "contracts/libraries/nest-vault/NestVaultCoreValidationLogic.sol";
import {NestVaultAccountingLogic} from "contracts/libraries/nest-vault/NestVaultAccountingLogic.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {NestVaultTransferLogic} from "contracts/libraries/nest-vault/NestVaultTransferLogic.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {NestAccountant} from "contracts/NestAccountant.sol";

/// @title  NestVaultRedeemLogic
/// @notice Library containing redeem-related logic for NestVaultCore
/// @author plumenetwork
/// @custom:oz-upgrades-unsafe-allow external-library-linking
library NestVaultRedeemLogic {
    using FixedPointMathLib for uint256;
    using NestVaultCoreValidationLogic for NestVaultCoreTypes.NestVaultCoreStorage;
    using NestVaultAccountingLogic for uint256;
    using NestVaultTransferLogic for ERC20;
    using NestVaultTransferLogic for NestShareOFT;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev   Emitted when a redeem request is fulfilled
    /// @param controller   address indexed The controller address
    /// @param shares       uint256         The number of shares fulfilled
    /// @param assets       uint256         The amount of assets calculated for the fulfilled shares
    /// @param actualAssets uint256         The actual amount of assets received and credited as claimable assets
    event RedeemFulfilled(address indexed controller, uint256 shares, uint256 assets, uint256 actualAssets);

    /// @dev   Emitted when a redemption request is updated
    /// @param controller  address  The vault or controller managing the redemption
    /// @param receiver    address  The receiver of the returned shares
    /// @param caller      address  The address initiating the update
    /// @param oldShares   uint256  Number of shares before the update
    /// @param newShares   uint256  Number of shares after the update
    event RedeemUpdated(address controller, address receiver, address caller, uint256 oldShares, uint256 newShares);

    /// @dev   Emitted when an instant redemption is performed
    /// @param shares        uint256  Number of shares redeemed
    /// @param assets        uint256  Total asset value of the redeemed shares before fees
    /// @param postFeeAmount uint256  Asset amount received by the user after deducting fees
    /// @param receiver      address  Address receiving the redeemed assets
    event InstantRedeem(uint256 shares, uint256 assets, uint256 postFeeAmount, address receiver);

    /// @dev   Emitted when a withdrawal is made
    /// @param caller     address The caller making the withdrawal
    /// @param receiver   address The receiver of the assets
    /// @param controller address The controller requesting the withdrawal
    /// @param assets     uint256 The assets withdrawn
    /// @param shares     uint256 The shares burned
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed controller, uint256 assets, uint256 shares
    );

    /// @dev   Emitted when a redeem request is made
    /// @param controller address The controller address
    /// @param owner      address The owner of the shares
    /// @param requestId  uint256 The request ID
    /// @param sender     address The sender making the request
    /// @param shares     uint256 The shares requested for redemption
    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                          EXECUTE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes the request redeem logic
    /// @param  $           NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _shares     uint256                                 Shares to request
    /// @param  _controller address                                 Controller address
    /// @param  _owner      address                                 Owner address
    /// @param  _caller     address                                 Caller address (msg.sender)
    /// @return requestId   uint256                                 The request ID (always 0)
    function executeRequestRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint256 _shares,
        address _controller,
        address _owner,
        address _caller,
        ERC20 shareToken
    ) external returns (uint256 requestId) {
        $.validateRequestRedeem(_shares, _controller, _owner, _caller, shareToken);

        // Update pending redeem state
        uint256 _currentPendingShares = $.pendingRedeem[_controller].shares;
        $.pendingRedeem[_controller].shares = _shares + _currentPendingShares;
        $.totalPendingShares = $.totalPendingShares + _shares;
        _tryUpdateTotalPendingShares($.accountant, NestAccountant.increaseTotalPendingShares.selector, _shares);

        emit RedeemRequest(_controller, _owner, 0, _caller, _shares);

        return 0;
    }

    /// @notice Executes the fulfill redeem logic including validation, asset calculation, and exit
    /// @param  $           NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _controller address                                 The controller address
    /// @param  _shares     uint256                                 The shares to fulfill
    /// @param  shareToken  NestShareOFT                            The share token for exit
    /// @param  assetToken  ERC20                                   The asset token
    /// @param  _rate       uint256                                 The exchange rate
    /// @return _assets     uint256                                 The assets calculated for shares
    function executeFulfillRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        address _controller,
        uint256 _shares,
        NestShareOFT shareToken,
        ERC20 assetToken,
        uint256 _rate
    ) external returns (uint256 _assets) {
        // Calculate assets
        _assets = _shares.convertToAssets(_rate, shareToken, Math.Rounding.Floor);

        // Validate
        $.validateFulfillRedeem(_controller, _shares, _assets);

        // Execute exit and get actual transfer amount
        uint256 _amountReceived = shareToken.safeExit(assetToken, address(this), _assets, _shares);

        // Update state
        $.pendingRedeem[_controller].shares -= _shares;
        $.totalPendingShares = $.totalPendingShares - _shares;
        $.claimableRedeem[_controller].assets += _amountReceived;
        $.claimableRedeem[_controller].shares += _shares;
        _tryUpdateTotalPendingShares($.accountant, NestAccountant.decreaseTotalPendingShares.selector, _shares);

        emit RedeemFulfilled(_controller, _shares, _assets, _amountReceived);
    }

    /// @notice Executes the instant redeem logic including validation, share transfer, and exit
    /// @param  $           NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _shares     uint256                                 Shares being redeemed
    /// @param  _receiver   address                                 Receiver address
    /// @param  _owner      address                                 Owner of the shares
    /// @param  _caller     address                                 The caller (msg.sender)
    /// @param  shareToken  NestShareOFT                            The share token for exit
    /// @param  assetToken  ERC20                                   The asset token
    /// @param  _rate       uint256                                 The exchange rate
    /// @return _postFeeAmount   uint256                            Amount after fees
    /// @return _feeAmount       uint256                            Fee amount
    function executeInstantRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint256 _shares,
        address _receiver,
        address _owner,
        address _caller,
        NestShareOFT shareToken,
        ERC20 assetToken,
        uint256 _rate
    ) external returns (uint256 _postFeeAmount, uint256 _feeAmount) {
        // Validate authorization and shares
        $.validateInstantRedeem(_shares, _receiver, _owner, _caller, ERC20(address(shareToken)));

        // Calculate assets and fees
        uint256 _assets = _shares.convertToAssets(_rate, shareToken, Math.Rounding.Floor);
        uint32 _feeRate = $.fees[NestVaultCoreTypes.Fees.InstantRedemption];
        (uint256 expectedPostFeeAmount,) = _assets.calculatePostFeeAmounts(_feeRate);

        if (expectedPostFeeAmount == 0) revert Errors.ZeroAssets();
        uint256 amountReceived = shareToken.safeExit(assetToken, address(this), _assets, _shares);

        _postFeeAmount = assetToken.safeTransferFrom(address(this), _receiver, expectedPostFeeAmount);

        _feeAmount = amountReceived - _postFeeAmount;

        $.claimableFees[NestVaultCoreTypes.Fees.InstantRedemption] += _feeAmount;

        emit InstantRedeem(_shares, _assets, _postFeeAmount, _receiver);

        return (_postFeeAmount, _feeAmount);
    }

    /// @notice Executes the update redeem logic including authorization checks
    /// @param  $           NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _newShares  uint256                                 The new share amount
    /// @param  _controller address                                 The controller address
    /// @param  _receiver   address                                 The receiver address
    /// @param  _caller     address                                 The caller address
    /// @param  shareToken  ERC20                                   The share token
    function executeUpdateRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint256 _newShares,
        address _controller,
        address _receiver,
        address _caller,
        ERC20 shareToken
    ) external {
        uint256 _oldShares = $.pendingRedeem[_controller].shares;

        // All validation in one call
        $.validateUpdateRedeem(_newShares, _controller, _receiver, _caller, _oldShares);

        if (_newShares == _oldShares) {
            return;
        }

        uint256 _returnAmount = _oldShares - _newShares;
        $.totalPendingShares = $.totalPendingShares - _returnAmount;
        $.pendingRedeem[_controller].shares = _newShares;
        _tryUpdateTotalPendingShares($.accountant, NestAccountant.decreaseTotalPendingShares.selector, _returnAmount);

        shareToken.safeTransferFrom(address(this), _receiver, _returnAmount);

        emit RedeemUpdated(_controller, _receiver, _caller, _oldShares, _newShares);
    }

    /// @notice Executes the withdraw logic including authorization check
    /// @param  $           NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _assets     uint256                                 The assets to withdraw
    /// @param  _receiver   address                                 The receiver address
    /// @param  _controller address                                 The controller address
    /// @param  _caller     address                                 The caller (msg.sender)
    /// @param  assetToken  ERC20                                   The asset token
    /// @return _shares     uint256                                 The shares burned
    function executeWithdraw(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint256 _assets,
        address _receiver,
        address _controller,
        address _caller,
        ERC20 assetToken
    ) external returns (uint256 _shares) {
        // All validation in one call
        $.validateWithdraw(_assets, _receiver, _controller, _caller);

        NestVaultCoreTypes.ClaimableRedeem storage claimableRedeem = $.claimableRedeem[_controller];
        _shares = _assets.mulDivDown($.claimableRedeem[_controller].shares, $.claimableRedeem[_controller].assets);

        if (_assets == claimableRedeem.assets) {
            claimableRedeem.assets = 0;
            claimableRedeem.shares = 0;
        } else {
            if (_shares == 0) revert Errors.ERC7540ZeroPayout();
            claimableRedeem.assets -= _assets;
            claimableRedeem.shares -= _shares;
        }

        assetToken.safeTransferFrom(address(this), _receiver, _assets);

        emit Withdraw(_caller, _receiver, _controller, _assets, _shares);
    }

    /// @notice Executes the redeem logic including authorization check
    /// @param  $           NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _shares     uint256                                 The shares to redeem
    /// @param  _receiver   address                                 The receiver address
    /// @param  _controller address                                 The controller address
    /// @param  _caller     address                                 The caller (msg.sender)
    /// @param  assetToken  ERC20                                   The asset token
    /// @return _assets     uint256                                 The assets redeemed
    function executeRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint256 _shares,
        address _receiver,
        address _controller,
        address _caller,
        ERC20 assetToken
    ) external returns (uint256 _assets) {
        // All validation in one call
        $.validateRedeem(_shares, _controller, _receiver, _caller);

        NestVaultCoreTypes.ClaimableRedeem storage claimableRedeem = $.claimableRedeem[_controller];

        if (_shares == claimableRedeem.shares) {
            _assets = claimableRedeem.assets;
            claimableRedeem.assets = 0;
            claimableRedeem.shares = 0;
        } else {
            _assets = _shares.mulDivDown(claimableRedeem.assets, claimableRedeem.shares);
            if (_assets == 0) revert Errors.ERC7540ZeroPayout();
            claimableRedeem.assets -= _assets;
            claimableRedeem.shares -= _shares;
        }

        assetToken.safeTransferFrom(address(this), _receiver, _assets);

        emit Withdraw(_caller, _receiver, _controller, _assets, _shares);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Sync global pending shares while preserving legacy compatibility.
    ///      If selector is missing (legacy accountant), revert data is empty and sync is skipped.
    ///      If selector exists and call reverts with data, revert is bubbled.
    /// @param accountant NestAccountant Accountant instance to notify
    /// @param _selector  bytes4         Selector for pending-share sync method
    /// @param _amount    uint256        Pending share delta to apply
    function _tryUpdateTotalPendingShares(NestAccountant accountant, bytes4 _selector, uint256 _amount) internal {
        (bool _success, bytes memory _reason) = address(accountant).call(abi.encodeWithSelector(_selector, _amount));
        if (_success || _reason.length == 0) return;

        assembly ("memory-safe") {
            revert(add(_reason, 32), mload(_reason))
        }
    }
}
