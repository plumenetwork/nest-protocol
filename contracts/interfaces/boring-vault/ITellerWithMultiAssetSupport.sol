// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";

interface ITellerWithMultiAssetSupport {
    function deposit(ERC20 depositAsset, uint256 depositAmount, uint256 minimumMint) external returns (uint256 shares);

    function depositWithPermit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares);

    function bulkDeposit(ERC20 depositAsset, uint256 depositAmount, uint256 minimumMint, address to)
        external
        returns (uint256 shares);

    function bulkWithdraw(ERC20 withdrawAsset, uint256 shareAmount, uint256 minimumAssets, address to)
        external
        returns (uint256 assetsOut);
}
