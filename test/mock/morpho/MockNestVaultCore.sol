// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Authority} from "@solmate/auth/Auth.sol";

contract MockNestVaultCore {
    using SafeERC20 for IERC20;

    IERC20 public immutable assetToken;
    IERC20 public immutable shareToken;

    Authority public authority;

    mapping(address controller => mapping(address operator => bool)) public isOperator;
    mapping(address controller => uint256 shares) public pending;
    mapping(address controller => uint256 shares) public claimable;

    uint256 public depositCalls;
    uint256 public mintCalls;
    uint256 public instantRedeemCalls;
    uint256 public requestRedeemCalls;
    uint256 public fulfillRedeemCalls;
    uint256 public withdrawCalls;
    uint256 public redeemCalls;

    constructor(address _assetToken, address _shareToken) {
        assetToken = IERC20(_assetToken);
        shareToken = IERC20(_shareToken);
    }

    function setAuthority(Authority _authority) external {
        authority = _authority;
    }

    function asset() external view returns (address) {
        return address(assetToken);
    }

    function share() external view returns (address) {
        return address(shareToken);
    }

    function balanceOf(address owner) external view returns (uint256) {
        return shareToken.balanceOf(owner);
    }

    function setOperator(address operator, bool approved) external returns (bool) {
        isOperator[msg.sender][operator] = approved;
        return true;
    }

    function setOperatorFor(address controller, address operator, bool approved) external {
        isOperator[controller][operator] = approved;
    }

    function previewMint(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function convertToShares(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        depositCalls++;
        shares = assets;

        assetToken.safeTransferFrom(msg.sender, address(this), assets);
        shareToken.safeTransfer(receiver, shares);
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        mintCalls++;
        assets = shares;

        assetToken.safeTransferFrom(msg.sender, address(this), assets);
        shareToken.safeTransfer(receiver, shares);
    }

    function pullAssetFrom(address from, uint256 assets) external {
        assetToken.safeTransferFrom(from, address(this), assets);
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

    function withdraw(uint256 assets, address receiver, address controller) external returns (uint256 shares) {
        withdrawCalls++;
        require(claimable[controller] >= assets, "claimable");
        claimable[controller] -= assets;
        shares = assets;
        assetToken.safeTransfer(receiver, assets);
    }

    function pendingRedeemRequest(uint256, address controller) external view returns (uint256) {
        return pending[controller];
    }

    function claimableRedeemRequest(uint256, address controller) external view returns (uint256) {
        return claimable[controller];
    }

    function maxRedeem(address controller) external view returns (uint256) {
        return claimable[controller];
    }

    function maxWithdraw(address controller) external view returns (uint256) {
        return claimable[controller];
    }

    function resetCounters() external {
        depositCalls = 0;
        mintCalls = 0;
        instantRedeemCalls = 0;
        requestRedeemCalls = 0;
        fulfillRedeemCalls = 0;
        withdrawCalls = 0;
        redeemCalls = 0;
    }
}
