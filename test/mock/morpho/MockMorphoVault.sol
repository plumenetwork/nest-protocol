// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockMorphoVault {
    using SafeERC20 for IERC20;

    IERC20 public immutable assetToken;
    IERC20 public immutable shareToken;

    mapping(address controller => mapping(address operator => bool)) public isOperator;
    mapping(address controller => uint256 shares) public pending;
    mapping(address controller => uint256 shares) public claimable;

    uint256 public instantRedeemCalls;
    uint256 public requestRedeemCalls;
    uint256 public fulfillRedeemCalls;
    uint256 public redeemCalls;

    constructor(address _assetToken, address _shareToken) {
        assetToken = IERC20(_assetToken);
        shareToken = IERC20(_shareToken);
    }

    function asset() external view returns (address) {
        return address(assetToken);
    }

    function setOperatorFor(address controller, address operator, bool approved) external {
        isOperator[controller][operator] = approved;
    }

    function previewMint(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function convertToShares(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = assets;
        assetToken.safeTransferFrom(msg.sender, address(this), assets);
        shareToken.safeTransfer(receiver, shares);
    }

    function previewInstantRedeem(uint256 shares) external pure returns (uint256 assets, uint256 fee) {
        return (shares, 0);
    }

    function instantRedeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets, uint256 fee)
    {
        instantRedeemCalls++;
        assets = shares;
        fee = 0;

        shareToken.safeTransferFrom(owner, address(this), shares);
        assetToken.safeTransfer(receiver, assets);
    }

    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId) {
        requestRedeemCalls++;
        shareToken.safeTransferFrom(owner, address(this), shares);
        pending[controller] += shares;
        requestId = 0;
    }

    function fulfillRedeem(address controller, uint256 shares) external returns (uint256 assets) {
        fulfillRedeemCalls++;
        require(pending[controller] >= shares, "pending");
        pending[controller] -= shares;
        claimable[controller] += shares;
        assets = shares;
    }

    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets) {
        redeemCalls++;
        require(claimable[controller] >= shares, "claimable");
        claimable[controller] -= shares;
        assets = shares;
        assetToken.safeTransfer(receiver, assets);
    }

    function resetCounters() external {
        instantRedeemCalls = 0;
        requestRedeemCalls = 0;
        fulfillRedeemCalls = 0;
        redeemCalls = 0;
    }
}
