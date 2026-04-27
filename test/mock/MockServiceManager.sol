// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "@predicate/src/interfaces/IPredicateManager.sol";

contract MockServiceManager {
    mapping(address => string) public clientToPolicyID;

    bool public isVerified;

    function setPolicy(string memory _policyID) external {
        clientToPolicyID[msg.sender] = _policyID;
    }

    function setIsVerified(bool _isVerified) external {
        isVerified = _isVerified;
    }

    function validateSignatures(
        Task calldata, /*task*/
        address[] memory, /*signerAddresses*/
        bytes[] memory /*signatures*/
    )
        external
        view
        returns (bool)
    {
        return isVerified;
    }
}
