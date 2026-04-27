// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {IERC7540Operator} from "contracts/interfaces/IERC7540.sol";
import {Errors} from "contracts/types/Errors.sol";

/// @title  OperatorRegistry
/// @notice Global operator registry for ERC7540 operator approvals.
/// @dev    Stores controller => operator approvals and emits IERC7540 OperatorSet events.
contract OperatorRegistry is Auth, EIP712, IERC7540Operator {
    // This mapping tracks whether an operator is enabled for a given controller.
    mapping(address controller => mapping(address operator => bool)) internal operatorEnabled;
    // This mapping prevents replay attacks by ensuring that authorizations cannot be reused.
    mapping(address controller => mapping(bytes32 nonce => bool used)) authorizations;

    /// @param _owner     Owner address for access-controlled operations
    /// @param _authority Authority contract used by Solmate Auth
    constructor(address _owner, Authority _authority) Auth(_owner, _authority) EIP712("OperatorRegistry", "1") {
        if (_owner == address(0)) revert Errors.ZeroAddress();
    }

    /// @inheritdoc IERC7540Operator
    function setOperator(address _operator, bool _approved) external override requiresAuth returns (bool _success) {
        if (_operator == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (msg.sender == _operator) {
            revert Errors.ERC7540SelfOperatorNotAllowed();
        }

        operatorEnabled[msg.sender][_operator] = _approved;
        _success = true;

        emit OperatorSet(msg.sender, _operator, _approved);
    }

    /// @notice Authorizes an operator for a controller, using a signature to validate
    /// @dev    The authorization is verified via EIP712 signatures.
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
        bytes calldata _signature
    ) external requiresAuth returns (bool _success) {
        if (_controller == address(0)) revert Errors.ZeroAddress();
        if (_operator == address(0)) revert Errors.ZeroAddress();
        if (_controller == _operator) {
            revert Errors.ERC7540SelfOperatorNotAllowed();
        }
        if (block.timestamp > _deadline) {
            revert Errors.ERC7540Expired();
        }
        if (authorizations[_controller][_nonce]) {
            revert Errors.ERC7540UsedAuthorization();
        }

        bytes32 _structHash = keccak256(
            abi.encode(
                keccak256(
                    "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint256 deadline)"
                ),
                _controller,
                _operator,
                _approved,
                _nonce,
                _deadline
            )
        );

        bytes32 _hash = MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), _structHash);

        if (!SignatureChecker.isValidSignatureNow(_controller, _hash, _signature)) {
            revert Errors.ERC7540InvalidSigner();
        }

        authorizations[_controller][_nonce] = true;
        operatorEnabled[_controller][_operator] = _approved;
        emit OperatorSet(_controller, _operator, _approved);
        return true;
    }

    /// @inheritdoc IERC7540Operator
    function isOperator(address _controller, address _operator) external view override returns (bool) {
        return operatorEnabled[_controller][_operator];
    }
}
