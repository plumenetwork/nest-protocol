// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {Authority} from "@solmate/auth/Auth.sol";

contract MockAuthChild is AuthUpgradeable {
    bool public flag;

    function initialize() external initializer {
        __Auth_init(msg.sender, Authority(address(0)));
    }

    function updateFlag() public virtual requiresAuth {
        flag = true;
    }
}
