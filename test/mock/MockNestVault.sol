// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {NestVault} from "contracts/NestVault.sol";
import {Constants} from "script/Constants.sol";

contract MockNestVault is NestVault, Constants {
    constructor(address payable _boringVault) NestVault(_boringVault) {}

    function getRequestId() public pure returns (uint256) {
        return REQUEST_ID;
    }

    function getValidatedRate() public view returns (uint256) {
        return _getValidatedRate();
    }

    function getDomainSeparatorV4() public view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
