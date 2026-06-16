// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {PredicateMessage} from "@predicate/src/interfaces/IPredicateClient.sol";
import {BridgeData, CrossChainTellerBase} from "@boring-vault/src/base/Roles/CrossChain/CrossChainTellerBase.sol";

interface ITellerWithMultiAssetSupportPredicateProxy {
    function deposit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address recipient,
        CrossChainTellerBase teller,
        PredicateMessage calldata predicateMessage
    ) external returns (uint256 shares);

    function depositAndBridge(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        BridgeData calldata data,
        CrossChainTellerBase teller,
        PredicateMessage calldata predicateMessage
    ) external payable;

    function genericUserCheckPredicate(address user, PredicateMessage calldata predicateMessage) external returns (bool);

    function setPolicy(string memory _policyID) external;

    function setPredicateManager(address _predicateManager) external;
}
