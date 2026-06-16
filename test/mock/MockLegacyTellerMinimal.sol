// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

interface IMockVaultPuller {
    function pullAssetFrom(address from, uint256 assets) external;
}

contract MockLegacyTellerMinimal {
    Authority public authority;
    address public vault;
    uint256 public depositCalls;

    constructor(address _vault) {
        vault = _vault;
    }

    function setAuthority(Authority _authority) external {
        authority = _authority;
    }

    function deposit(ERC20, uint256 depositAmount, uint256 minimumMint) external returns (uint256 shares) {
        depositCalls++;
        shares = depositAmount;
        require(shares >= minimumMint, "minimum mint not met");
        IMockVaultPuller(vault).pullAssetFrom(msg.sender, depositAmount);
    }
}
