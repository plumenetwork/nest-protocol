// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {CrossChainTellerBase} from "@boring-vault/src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import {PredicateMessage} from "@predicate/src/interfaces/IPredicateClient.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

/// @notice Minimal interface for legacy predicate proxy teller deposits.
interface ITellerPredicateProxy {
    function deposit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address recipient,
        CrossChainTellerBase teller,
        PredicateMessage calldata predicateMessage
    ) external returns (uint256 shares);

    function genericUserCheckPredicate(address user, PredicateMessage calldata predicateMessage) external returns (bool);
}
