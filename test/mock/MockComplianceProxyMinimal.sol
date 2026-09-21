// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {NestVault} from "contracts/NestVault.sol";

contract MockComplianceProxyMinimal {
    Authority public authority;
    uint256 public depositCalls;
    uint256 public genericUserCheckCalls;
    address public lastCheckedUser;
    address public lastCheckedCaller;
    bytes32 public lastCheckedOnBehalf;
    bool public complianceAuthorized = true;

    function setAuthority(Authority _authority) external {
        authority = _authority;
    }

    function setComplianceAuthorized(bool _complianceAuthorized) external {
        complianceAuthorized = _complianceAuthorized;
    }

    function genericUserCheck(address user, bytes calldata) external returns (bool) {
        genericUserCheckCalls++;
        lastCheckedUser = user;
        return complianceAuthorized;
    }

    function genericUserCheck(address caller, bytes32 onBehalf, bytes calldata) external returns (bool) {
        genericUserCheckCalls++;
        lastCheckedCaller = caller;
        lastCheckedOnBehalf = onBehalf;
        return complianceAuthorized;
    }

    function deposit(
        ERC20 depositAsset,
        uint256 depositAmount,
        address receiver,
        NestVault vault,
        bytes32,
        bytes calldata
    ) external returns (uint256 shares) {
        depositCalls++;

        require(depositAsset.transferFrom(msg.sender, address(this), depositAmount), "transferFrom failed");
        require(depositAsset.approve(address(vault), depositAmount), "approve failed");

        (bool success, bytes memory returnData) =
            address(vault).call(abi.encodeWithSignature("deposit(uint256,address)", depositAmount, receiver));
        require(success, "deposit failed");
        shares = abi.decode(returnData, (uint256));

        require(depositAsset.approve(address(vault), 0), "reset approve failed");
    }
}
