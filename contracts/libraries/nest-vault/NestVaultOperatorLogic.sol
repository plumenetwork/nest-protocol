// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Errors} from "contracts/types/Errors.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {NestVaultCoreValidationLogic} from "contracts/libraries/nest-vault/NestVaultCoreValidationLogic.sol";

/// @title  NestVaultOperatorLogic
/// @notice Library containing operator-related logic for NestVaultCore
/// @author plumenetwork
/// @custom:oz-upgrades-unsafe-allow external-library-linking
library NestVaultOperatorLogic {
    using NestVaultCoreValidationLogic for NestVaultCoreTypes.NestVaultCoreStorage;
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev   Emitted when an operator is set or revoked
    /// @param controller address The controller setting the operator
    /// @param operator   address The operator being set
    /// @param approved   bool    Whether the operator is approved
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    /*//////////////////////////////////////////////////////////////
                          EXECUTE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes the setOperator logic
    /// @param  $         NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _operator address The operator address
    /// @param  _approved bool    Whether to approve or revoke
    /// @param  _caller   address The caller (msg.sender)
    /// @return _success  bool    Always returns true on success
    function executeSetOperator(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        address _operator,
        bool _approved,
        address _caller
    ) external returns (bool _success) {
        $.validateSetOperator(_operator, _caller);
        $.isVaultOperator[_caller][_operator] = _approved;
        emit OperatorSet(_caller, _operator, _approved);
        return true;
    }

    /// @notice Validates and executes an operator authorization
    /// @dev    Validates inputs, verifies via EIP712 signatures, and updates state
    /// @param  $                NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _controller       address The controller's address
    /// @param  _operator         address The operator's address
    /// @param  _approved         bool    Whether the operator is approved or not
    /// @param  _nonce            bytes32 A unique identifier for the authorization
    /// @param  _deadline         uint256 The deadline for the authorization
    /// @param  _signature        bytes   The signature to validate the authorization
    /// @param  _domainSeparator  bytes32 The EIP712 domain separator
    /// @return _success          bool    Always returns true on success
    function executeAuthorizeOperator(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        address _controller,
        address _operator,
        bool _approved,
        bytes32 _nonce,
        uint256 _deadline,
        bytes memory _signature,
        bytes32 _domainSeparator
    ) external returns (bool _success) {
        $.validateAuthorizeOperator(_controller, _operator, _nonce, _deadline);

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

        bytes32 _hash = MessageHashUtils.toTypedDataHash(_domainSeparator, _structHash);

        if (!SignatureChecker.isValidSignatureNow(_controller, _hash, _signature)) {
            revert Errors.ERC7540InvalidSigner();
        }

        $.authorizations[_controller][_nonce] = true;
        $.isVaultOperator[_controller][_operator] = _approved;
        emit OperatorSet(_controller, _operator, _approved);
        return true;
    }
}
