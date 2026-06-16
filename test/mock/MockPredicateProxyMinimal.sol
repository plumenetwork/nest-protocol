// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {NestVault} from "contracts/NestVault.sol";
import {PredicateMessage} from "contracts/NestVaultPredicateProxy.sol";

contract MockPredicateProxyMinimal {
    Authority public authority;
    uint256 public depositCalls;
    uint256 public genericUserCheckCalls;
    bool public predicateAuthorized = true;

    function setAuthority(Authority _authority) external {
        authority = _authority;
    }

    function setPredicateAuthorized(bool _predicateAuthorized) external {
        predicateAuthorized = _predicateAuthorized;
    }

    function genericUserCheckPredicate(address, PredicateMessage calldata) external returns (bool) {
        genericUserCheckCalls++;
        return predicateAuthorized;
    }

    function deposit(
        ERC20 depositAsset,
        uint256 depositAmount,
        address receiver,
        NestVault vault,
        bytes32,
        PredicateMessage calldata
    ) external returns (uint256 shares) {
        depositCalls++;

        require(depositAsset.transferFrom(msg.sender, address(this), depositAmount), "transferFrom failed");
        require(depositAsset.approve(address(vault), depositAmount), "approve failed");

        (bool success, bytes memory returnData) =
            address(vault).call(abi.encodeWithSignature("deposit(uint256,address)", depositAmount, receiver));
        require(success, "deposit failed");
        shares = abi.decode(returnData, (uint256));

        require(depositAsset.approve(address(vault), 0), "reset approve failed");
    }
}
