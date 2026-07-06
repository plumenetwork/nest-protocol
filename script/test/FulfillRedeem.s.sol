// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "script/BaseScript.sol";
import {NestVaultComposer} from "contracts/ovault/NestVaultComposer.sol";

/// @title  FulfillRedeem
/// @notice Script to call fulfillRedeem on NestVaultOFT
contract FulfillRedeem is BaseScript {
    /// @notice The NestVaultComposer contract address
    address payable public composer = payable(0x75eea7b4514550119f86b6da4a909e3f4A92E7BA);

    /// @notice The redeemer (main account) of the request
    bytes32 public redeemer = 0xee4074018ea58d900f5952d94a38040f2d5540b9b3bc45263dbf204d82063057;

    /// @notice The receiver (token account / ATA) that controls the request in composer context
    bytes32 public receiver = 0xee4074018ea58d900f5952d94a38040f2d5540b9b3bc45263dbf204d82063057;

    /// @notice The amount of shares to fulfill
    uint256 public shares = 1000;

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        NestVaultComposer _nestVaultComposer = NestVaultComposer(composer);

        // Call fulfillRedeem for the (redeemer, receiver) pair
        uint256 assets = _nestVaultComposer.fulfillRedeem(30168, redeemer, receiver, shares);

        console.log("FulfillRedeem called on composer:", composer);
        console.logBytes32(redeemer);
        console.logBytes32(receiver);
        console.log("Shares fulfilled:", shares);
        console.log("Assets returned:", assets);

        vm.stopBroadcast();
    }
}
