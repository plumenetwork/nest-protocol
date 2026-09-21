// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";

interface IAtomicQueue {
    struct AtomicRequest {
        uint64 deadline;
        uint88 atomicPrice;
        uint96 offerAmount;
        bool inSolve;
    }

    struct SolveMetaData {
        address user;
        uint8 flags;
        uint256 assetsToOffer;
        uint256 assetsForWant;
    }

    function getUserAtomicRequest(address user, ERC20 offer, ERC20 want) external view returns (AtomicRequest memory);

    function isAtomicRequestValid(ERC20 offer, address user, AtomicRequest calldata userRequest)
        external
        view
        returns (bool);

    function updateAtomicRequest(ERC20 offer, ERC20 want, AtomicRequest calldata userRequest) external;

    function solve(ERC20 offer, ERC20 want, address[] calldata users, bytes calldata runData, address solver) external;

    function viewSolveMetaData(ERC20 offer, ERC20 want, address[] calldata users)
        external
        view
        returns (SolveMetaData[] memory metaData, uint256 totalAssetsForWant, uint256 totalAssetsToOffer);
}
