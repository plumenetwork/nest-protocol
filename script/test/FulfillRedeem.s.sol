// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "script/BaseScript.sol";
import {NestVaultComposer} from "contracts/ovault/NestVaultComposer.sol";

/// @title  FulfillRedeem
/// @notice Script to call fulfillRedeem on NestVaultOFT
contract FulfillRedeem is BaseScript {
    /// @notice The NestVaultComposer contract address
    address payable public composer = payable(0x75eea7b4514550119f86b6da4a909e3f4A92E7BA);

    /// @notice The amount of shares to fulfill
    uint256 public shares = 1000;

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        NestVaultComposer _nestVaultComposer = NestVaultComposer(composer);

        // Call fulfillRedeem
        uint256 assets = _nestVaultComposer.fulfillRedeem(
            30168, 0xee4074018ea58d900f5952d94a38040f2d5540b9b3bc45263dbf204d82063057, shares
        );

        console.log("FulfillRedeem called on composer:", composer);
        console.log("Controller: 0xee4074018ea58d900f5952d94a38040f2d5540b9b3bc45263dbf204d82063057");
        console.log("Shares fulfilled:", shares);
        console.log("Assets returned:", assets);

        vm.stopBroadcast();
    }
}
