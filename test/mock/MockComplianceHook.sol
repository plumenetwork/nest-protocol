// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {IComplianceHook} from "contracts/compliance/interfaces/IComplianceHook.sol";

/// @notice Mock compliance hook: records the last check and returns a configurable verdict.
contract MockComplianceHook is IComplianceHook {
    bool public authorized = true;
    bool public shouldRevert;

    uint256 public checkCalls;
    address public lastSender;
    bytes public lastPayload;
    bytes public lastComplianceData;

    function setAuthorized(bool _authorized) external {
        authorized = _authorized;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function checkCompliance(address _sender, bytes calldata _payload, bytes calldata _complianceData)
        external
        returns (bool)
    {
        return _recordCheck(_sender, _payload, _complianceData);
    }

    function _recordCheck(address _sender, bytes calldata _payload, bytes calldata _complianceData)
        internal
        returns (bool)
    {
        if (shouldRevert) revert("MockComplianceHook: revert");
        checkCalls++;
        lastSender = _sender;
        lastPayload = _payload;
        lastComplianceData = _complianceData;
        return authorized;
    }
}
