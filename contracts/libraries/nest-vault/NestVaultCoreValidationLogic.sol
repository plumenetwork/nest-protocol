// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {IERC7540Operator} from "contracts/interfaces/IERC7540.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";
import {NestAccountant} from "contracts/NestAccountant.sol";
import {Errors} from "contracts/types/Errors.sol";

/// @title  NestVaultCoreValidationLogic
/// @notice Library containing validation logic for NestVaultCore operations
/// @author plumenetwork
library NestVaultCoreValidationLogic {
    /// @notice Validates parameters for requestRedeem operation
    /// @param  $           NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _shares     uint256 The shares to redeem
    /// @param  _controller address The controller address
    /// @param  _owner      address The owner address
    /// @param  _caller     address The caller address
    function validateRequestRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint256 _shares,
        address _controller,
        address _owner,
        address _caller,
        ERC20 /*shareToken*/
    ) external view {
        _validateCaller($, _owner, _caller);
        if (_controller == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_shares == 0) {
            revert Errors.ZeroShares();
        }
    }

    /// @notice Validates parameters for fulfillRedeem operation
    /// @param  $           NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _controller address The controller address
    /// @param  _shares     uint256 The shares to fulfill
    /// @param  _assets     uint256 The calculated assets
    function validateFulfillRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        address _controller,
        uint256 _shares,
        uint256 _assets
    ) external view {
        uint256 pendingShares = $.pendingRedeem[_controller].shares;
        if (pendingShares == 0) {
            revert Errors.NoPendingRedeem();
        }
        if (_shares > pendingShares) {
            revert Errors.InsufficientBalance();
        }
        if (_assets == 0) {
            revert Errors.ZeroAssets();
        }
    }

    /// @notice Validates parameters for instantRedeem operation
    /// @param  $          NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _shares    uint256 The shares to redeem
    /// @param  _receiver  address The receiver address
    /// @param  _owner     address The owner of the shares
    /// @param  _caller    address The caller address
    function validateInstantRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint256 _shares,
        address _receiver,
        address _owner,
        address _caller,
        ERC20 /*shareToken*/
    ) external view {
        _validateCaller($, _owner, _caller);
        if (_receiver == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_shares == 0) {
            revert Errors.ZeroShares();
        }
    }

    /// @notice Validates parameters for updateRedeem operation
    /// @param  $            NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _newShares   uint256 The new shares amount
    /// @param  _controller  address The controller address
    /// @param  _receiver    address The receiver address
    /// @param  _caller      address The caller address
    /// @param  _oldShares   uint256 The old shares amount
    function validateUpdateRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint256 _newShares,
        address _controller,
        address _receiver,
        address _caller,
        uint256 _oldShares
    ) external view {
        _validateCaller($, _controller, _caller);
        if (_receiver == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_oldShares == 0) {
            revert Errors.NoPendingRedeem();
        }
        if (_oldShares < _newShares) {
            revert Errors.InsufficientBalance();
        }
    }

    /// @notice Validates parameters for withdraw operation
    /// @param  $           NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _assets     uint256 The assets to withdraw
    /// @param  _receiver   address The receiver address
    /// @param  _controller address The controller address
    /// @param  _caller     address The caller address
    function validateWithdraw(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint256 _assets,
        address _receiver,
        address _controller,
        address _caller
    ) external view {
        _validateCaller($, _controller, _caller);
        if (_receiver == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_assets == 0) {
            revert Errors.ZeroAssets();
        }
        uint256 claimableAssets = $.claimableRedeem[_controller].assets;
        if (claimableAssets < _assets) {
            revert Errors.InsufficientClaimable();
        }
    }

    /// @notice Validates parameters for redeem operation
    /// @param  $           NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _shares     uint256 The shares to redeem
    /// @param  _controller address The controller address
    /// @param  _receiver   address The receiver address
    /// @param  _caller     address The caller address
    function validateRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint256 _shares,
        address _controller,
        address _receiver,
        address _caller
    ) external view {
        _validateCaller($, _controller, _caller);
        if (_receiver == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_shares == 0) {
            revert Errors.ZeroShares();
        }
        uint256 claimableShares = $.claimableRedeem[_controller].shares;
        if (claimableShares < _shares) {
            revert Errors.InsufficientClaimable();
        }
    }

    /// @notice Validates parameters for authorizeOperator operation
    /// @param  $           NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _controller address The controller address
    /// @param  _operator   address The operator address
    /// @param  _nonce      bytes32 The nonce value
    /// @param  _deadline   uint256 The deadline timestamp
    function validateAuthorizeOperator(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        address _controller,
        address _operator,
        bytes32 _nonce,
        uint256 _deadline
    ) external view {
        if (_controller == address(0)) revert Errors.ZeroAddress();
        if (_operator == address(0)) revert Errors.ZeroAddress();
        if (_controller == _operator) {
            revert Errors.ERC7540SelfOperatorNotAllowed();
        }
        if (block.timestamp > _deadline) {
            revert Errors.ERC7540Expired();
        }
        if ($.authorizations[_controller][_nonce]) {
            revert Errors.ERC7540UsedAuthorization();
        }
    }

    /// @notice Validates parameters for setOperator operation
    /// @dev    $         NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _operator address The operator address
    /// @param  _caller   address The caller address
    function validateSetOperator(
        NestVaultCoreTypes.NestVaultCoreStorage storage,
        /*$*/
        address _operator,
        address _caller
    ) external pure {
        if (_operator == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_caller == _operator) {
            revert Errors.ERC7540SelfOperatorNotAllowed();
        }
    }

    /// @notice Validates parameters for deposit operation
    /// @dev    $             NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _isAuthorized bool    Whether the caller is authorized
    /// @param  _assets       uint256 The assets being deposited
    /// @param  _shares       uint256 The shares to mint
    function validateDeposit(
        NestVaultCoreTypes.NestVaultCoreStorage storage,
        /*$*/
        bool _isAuthorized,
        uint256 _assets,
        uint256 _shares
    ) external pure {
        if (!_isAuthorized) {
            revert Errors.Unauthorized();
        }
        if (_assets > 0 && _shares == 0) {
            revert Errors.ZeroShares();
        }
    }

    /// @notice Validates candidate accountant compatibility
    /// @dev    Verifies the candidate is a contract and exposes `getRateInQuoteSafe(ERC20)`.
    ///         A paused NestAccountant reverts `getRateInQuoteSafe` with `Errors.Paused()`,
    ///         which is treated as a valid compatibility signal.
    /// @param  _accountant address Candidate accountant address
    /// @param  _asset      ERC20   Vault asset used to probe safe quote rates
    function validateSetAccountant(
        NestVaultCoreTypes.NestVaultCoreStorage storage,
        /*$*/
        address _accountant,
        ERC20 _asset
    ) external view {
        // Validate that the address is a contract (not an EOA)
        if (_accountant.code.length == 0) {
            revert Errors.IncompatibleAccountant();
        }
        // Validate that the accountant exposes getRateInQuoteSafe(ERC20).
        // We verify the call returns at least 32 bytes (a valid uint256) to avoid false positives
        // from contracts with fallback functions that return empty data.
        (bool success, bytes memory returnData) =
            _accountant.staticcall(abi.encodeWithSelector(NestAccountant.getRateInQuoteSafe.selector, _asset));
        bool validResponse = success && returnData.length >= 32;
        bool revertedPaused = !success && returnData.length >= 4 && bytes4(returnData) == Errors.Paused.selector;

        if (!validResponse && !revertedPaused) {
            revert Errors.IncompatibleAccountant();
        }
    }

    /// @notice Validates fee-rate update for a given fee type
    /// @param  _f   NestVaultCoreTypes.Fees                 Fee type
    /// @param  _fee uint32                                  Candidate fee amount
    function validateSetFee(NestVaultCoreTypes.NestVaultCoreStorage storage $, NestVaultCoreTypes.Fees _f, uint32 _fee)
        external
        view
    {
        uint256 maxFee = $.maxFees[_f];
        if (_fee > maxFee) revert Errors.InvalidFee();
    }

    /// @notice Validates fee claim request for a fee type
    /// @param  _f        NestVaultCoreTypes.Fees                 Fee type to claim
    /// @param  _receiver address                                 Claim receiver
    function validateClaimFee(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        NestVaultCoreTypes.Fees _f,
        address _receiver
    ) external view {
        if (_receiver == address(0)) {
            revert Errors.ZeroAddress();
        }
        if ($.claimableFees[_f] == 0) {
            revert Errors.ZeroFeesOwed();
        }
    }

    /// @notice Validates redeem payout is non-zero
    /// @dev    $                NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _assets          uint256 The assets to pay out
    /// @param  _shares          uint256 The shares being redeemed
    /// @param  _claimableShares uint256 The total claimable shares
    function validateRedeemPayout(
        NestVaultCoreTypes.NestVaultCoreStorage storage,
        /*$*/
        uint256 _assets,
        uint256 _shares,
        uint256 _claimableShares
    ) external pure {
        if (_assets == 0 && _shares != _claimableShares) {
            revert Errors.ERC7540ZeroPayout();
        }
    }

    /// @notice Validates operator registry compatibility
    /// @dev    Allows zero address (registry disabled). For non-zero addresses, probes IERC7540Operator.isOperator via staticcall.
    /// @param  _operatorRegistry address Candidate operator registry address
    function validateOperatorRegistry(
        NestVaultCoreTypes.NestVaultCoreStorage storage,
        /*$*/
        address _operatorRegistry
    )
        internal
        view
    {
        if (_operatorRegistry == address(0)) return;

        (bool success, bytes memory data) = _operatorRegistry.staticcall(
            abi.encodeWithSelector(IERC7540Operator.isOperator.selector, address(0), address(0))
        );
        if (!success || data.length < 32) {
            revert Errors.IncompatibleOperatorRegistry();
        }
    }

    /// @dev    Internal function to check if an operator is authorized for a given controller
    /// @param  _controller address The controller whose operator permissions are being queried
    /// @param  _operator   address The operator being checked
    /// @return             bool    True if the operator is authorized for the controller
    function isOperator(NestVaultCoreTypes.NestVaultCoreStorage storage $, address _controller, address _operator)
        internal
        view
        returns (bool)
    {
        bool _approved = $.isVaultOperator[_controller][_operator];
        OperatorRegistry registry = $.operatorRegistry;
        if (address(registry) == address(0)) return _approved;
        return _approved || registry.isOperator(_controller, _operator);
    }

    /// @notice Internal function to validate caller authorization
    /// @param  $        NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _account address    The account whose authorization is being checked
    /// @param  _caller  address    The caller address
    function _validateCaller(NestVaultCoreTypes.NestVaultCoreStorage storage $, address _account, address _caller)
        private
        view
    {
        if (_account != _caller && !isOperator($, _account, _caller)) {
            revert Errors.Unauthorized();
        }
    }
}
