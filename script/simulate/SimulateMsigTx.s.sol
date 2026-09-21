// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ConfigReader, CommonConfig} from "script/lib/ConfigReader.sol";

/// @title SimulateMsigTx
/// @notice Simulates a Safe multisig batch TX on a fork by pranking the multisig.
///         Reads a JSON file from script/output/msig/ and replays every call.
/// @dev Usage:
///        TX_FILE=98866-nFALCON-DeployAndSetup forge script script/simulate/SimulateMsigTx.s.sol -vvv
///
///      TX_FILE is the filename (without directory, without .json) inside script/output/msig/.
contract SimulateMsigTx is Script {
    using stdJson for string;

    function run() external {
        // ── Read env ──────────────────────────────────────────────────
        string memory txFile = vm.envString("TX_FILE");
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/output/msig/", txFile, ".json");

        console.log("=== SimulateMsigTx ===");
        console.log("TX file:", path);

        // ── Parse JSON ────────────────────────────────────────────────
        string memory json = vm.readFile(path);
        uint256 chainId = json.readUint(".chainId");

        // Load multisig from common config
        CommonConfig memory common = ConfigReader.readCommonConfig(chainId);
        address msig = common.multisig;
        string memory rpcUrl = vm.envString(common.rpcEnvVar);

        console.log("Chain ID:", chainId);
        console.log("Multisig:", msig);
        console.log("RPC env var:", common.rpcEnvVar);

        // ── Fork ──────────────────────────────────────────────────────
        vm.createSelectFork(rpcUrl);

        // ── Count transactions ────────────────────────────────────────
        // Parse the raw array to get its length
        bytes memory rawArray = json.parseRaw(".transactions");
        // The ABI-encoded dynamic array starts with offset then length
        uint256 txCount;
        assembly {
            let dataStart := add(rawArray, 32)
            let offset := mload(dataStart)
            txCount := mload(add(dataStart, offset))
        }

        console.log("Total transactions:", txCount);
        console.log("");

        // ── Execute each tx as the multisig ───────────────────────────
        for (uint256 i = 0; i < txCount; i++) {
            string memory prefix = string.concat(".transactions[", Strings.toString(i), "]");

            address to = json.readAddress(string.concat(prefix, ".to"));
            bytes memory data = json.readBytes(string.concat(prefix, ".data"));
            // value is stored as a string in Safe batch format
            uint256 value = vm.parseUint(json.readString(string.concat(prefix, ".value")));

            console.log("--- TX", i, "---");
            console.log("  to:", to);
            console.log("  value:", value);
            console.log("  data length:", data.length);

            vm.prank(msig);
            (bool success, bytes memory returnData) = to.call{value: value}(data);

            if (success) {
                console.log("  [PASS]");
            } else {
                console.log("  [FAIL]");
                if (returnData.length > 0) {
                    console.log("  revert data:");
                    console.logBytes(returnData);
                }
                revert(string.concat("TX ", Strings.toString(i), " reverted"));
            }
        }

        console.log("");
        console.log("=== All transactions simulated successfully ===");
    }
}
