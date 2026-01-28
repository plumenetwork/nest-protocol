// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract MockRateProvider {
    uint256 internal rate;

    function setRate(uint256 _rate) public {
        rate = _rate;
    }

    function getRateInQuoteSafe(ERC20) external view returns (uint256) {
        return rate;
    }
}
