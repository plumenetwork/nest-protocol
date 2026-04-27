// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {NestAccountant} from "contracts/NestAccountant.sol";

contract MockNestAccountant is NestAccountant {
    constructor(address _base, address _share) NestAccountant(_base, _share) {}

    function share() external view returns (address) {
        return SHARE;
    }
}
