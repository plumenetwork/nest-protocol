// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {CrossChainTellerBase} from "@boring-vault/src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import {PredicateMessage} from "contracts/NestVaultPredicateProxy.sol";

contract MockLegacyPredicateProxyMinimal {
    Authority public authority;
    uint256 public depositCalls;
    address public lastRecipient;
    address public lastTeller;
    bool public predicateAuthorized = true;

    function setAuthority(Authority _authority) external {
        authority = _authority;
    }

    function setPredicateAuthorized(bool _predicateAuthorized) external {
        predicateAuthorized = _predicateAuthorized;
    }

    function genericUserCheckPredicate(address, PredicateMessage calldata) external view returns (bool) {
        return predicateAuthorized;
    }

    function deposit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address recipient,
        CrossChainTellerBase teller,
        PredicateMessage calldata
    ) external returns (uint256 shares) {
        depositCalls++;
        lastRecipient = recipient;
        lastTeller = address(teller);

        require(depositAsset.transferFrom(msg.sender, address(this), depositAmount), "transferFrom failed");
        shares = depositAmount;
        require(shares >= minimumMint, "minimum mint not met");
    }
}
