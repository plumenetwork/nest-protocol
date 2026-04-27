// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {NestVault} from "contracts/NestVault.sol";
import {Constants} from "script/Constants.sol";

contract MockNestVault is NestVault, Constants {
    address internal constant CANONICAL_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    constructor(address payable _boringVault) NestVault(_boringVault, CANONICAL_PERMIT2) {}

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
