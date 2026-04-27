// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {OFTUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {Authority} from "@solmate/auth/Auth.sol";

/// @dev Legacy implementation used to simulate pre-permit upgrade behavior in tests.
contract MockNestShareOFTV1 is OFTUpgradeable, AuthUpgradeable {
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    function initialize(string memory _name, string memory _symbol, address _owner, address _delegate)
        public
        initializer
    {
        __OFT_init(_name, _symbol, _delegate);
        __Auth_init(_owner, Authority(address(0)));
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function owner() public view override(OwnableUpgradeable, AuthUpgradeable) returns (address) {
        return AuthUpgradeable.owner();
    }

    function transferOwnership(address newOwner) public override(OwnableUpgradeable, AuthUpgradeable) requiresAuth {
        AuthUpgradeable.transferOwnership(newOwner);
    }

    function acceptOwnership() public override {
        address oldOwner = owner();
        AuthUpgradeable.acceptOwnership();
        emit OwnershipTransferred(oldOwner, owner());
    }
}
