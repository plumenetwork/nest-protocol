// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {IPredicateRegistry, Statement, Attestation} from "@predicate-v2/interfaces/IPredicateRegistry.sol";

/// @notice Mock of the Predicate V2 Registry: records the last validated statement and simulates
///         UUID replay protection.
contract MockPredicateRegistry is IPredicateRegistry {
    mapping(address => string) public clientToPolicyID;
    mapping(string => bool) public spentUuids;

    bool public isVerified = true;
    bool public revertOnValidate;

    uint256 public validateCalls;
    address public firstMsgSender;
    bytes public firstEncodedSigAndArgs;
    string public firstUuid;
    address public lastMsgSender;
    address public lastTarget;
    uint256 public lastMsgValue;
    bytes public lastEncodedSigAndArgs;
    string public lastPolicy;
    string public lastUuid;
    uint256 public lastExpiration;
    address public lastAttester;

    function setIsVerified(bool _isVerified) external {
        isVerified = _isVerified;
    }

    function setRevertOnValidate(bool _revertOnValidate) external {
        revertOnValidate = _revertOnValidate;
    }

    function setPolicyID(string memory _policyID) external {
        clientToPolicyID[msg.sender] = _policyID;
    }

    function getPolicyID(address _client) external view returns (string memory) {
        return clientToPolicyID[_client];
    }

    function validateAttestation(Statement memory _statement, Attestation memory _attestation) external returns (bool) {
        if (revertOnValidate) revert("MockPredicateRegistry: invalid attestation");
        if (spentUuids[_attestation.uuid]) revert("MockPredicateRegistry: uuid spent");
        spentUuids[_attestation.uuid] = true;

        if (validateCalls == 0) {
            firstMsgSender = _statement.msgSender;
            firstEncodedSigAndArgs = _statement.encodedSigAndArgs;
            firstUuid = _statement.uuid;
        }
        validateCalls++;
        lastMsgSender = _statement.msgSender;
        lastTarget = _statement.target;
        lastMsgValue = _statement.msgValue;
        lastEncodedSigAndArgs = _statement.encodedSigAndArgs;
        lastPolicy = _statement.policy;
        lastUuid = _statement.uuid;
        lastExpiration = _statement.expiration;
        lastAttester = _attestation.attester;

        return isVerified;
    }
}
