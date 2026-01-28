// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {Constants} from "script/Constants.sol";

contract BaseScript is Script, Constants {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
}
