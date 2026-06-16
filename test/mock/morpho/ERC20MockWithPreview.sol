// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ERC20Mock} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/ERC20Mock.sol";

/// @dev ERC20Mock that also implements previewFulfillRedeem, previewInstantRedeem, and fees
///      using a configurable rate (assets = shares * rate / 1e18, fee = 0).
contract ERC20MockWithPreview is ERC20Mock {
    uint256 public previewRate;

    constructor(string memory name_, string memory symbol_, uint256 rate_) ERC20Mock(name_, symbol_) {
        previewRate = rate_;
    }

    function previewFulfillRedeem(uint256 shares) external view returns (uint256 postFeeAssets, uint256 feeAmount) {
        postFeeAssets = shares * previewRate / 1e18;
        feeAmount = 0;
    }

    function previewInstantRedeem(uint256 shares) external view returns (uint256 postFeeAssets, uint256 feeAmount) {
        postFeeAssets = shares * previewRate / 1e18;
        feeAmount = 0;
    }

    function fees(uint8) external pure returns (uint32 rate, uint256 flat) {
        return (0, 0);
    }
}
