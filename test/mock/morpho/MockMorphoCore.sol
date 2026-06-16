// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {MarketParams} from "@morpho/interfaces/IMorpho.sol";

contract MockMorphoCore {
    MarketParams public lastMarketParams;
    uint256 public withdrawCollateralCalls;
    uint256 public lastWithdrawAssets;
    address public lastOnBehalf;
    address public lastReceiver;

    function isAuthorized(address, address) external pure returns (bool) {
        return true;
    }

    function withdrawCollateral(MarketParams calldata marketParams, uint256 assets, address onBehalf, address receiver)
        external
    {
        lastMarketParams = marketParams;
        withdrawCollateralCalls++;
        lastWithdrawAssets = assets;
        lastOnBehalf = onBehalf;
        lastReceiver = receiver;
    }
}
