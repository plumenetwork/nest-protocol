// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SetupFees} from "script/setup/SetupFees.s.sol";
import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";

/// @dev Hub accountant stand-in exposing only the getters the perf-fee guard reads.
contract MockHubAccountant {
    NestHubAccountant.AccountantState internal state;
    NestHubAccountant.PerformanceFeeConfig internal config;

    function setState(uint96 lastGrossRate, uint64 lastUpdateTimestamp, uint32 minimumUpdateDelayInSeconds) external {
        state.lastGrossRate = lastGrossRate;
        state.lastUpdateTimestamp = lastUpdateTimestamp;
        state.minimumUpdateDelayInSeconds = minimumUpdateDelayInSeconds;
    }

    function setPerformanceFee(uint32 performanceFee) external {
        config.performanceFee = performanceFee;
    }

    function getAccountantState() external view returns (NestHubAccountant.AccountantState memory) {
        return state;
    }

    function getPerformanceFeeConfig() external view returns (NestHubAccountant.PerformanceFeeConfig memory) {
        return config;
    }
}

contract SetupFeesPerformanceGuardHarness is SetupFees {
    function applyPerf(address accountant, uint32 targetPerf) external {
        msigMode = true;
        _applyPerformanceFeeChange(accountant, targetPerf);
    }

    function queued(uint256 index) external view returns (address target, bytes memory data) {
        target = serializedTxs[index].to;
        data = serializedTxs[index].data;
    }

    function queuedLength() external view returns (uint256) {
        return serializedTxs.length;
    }
}

contract SetupFeesPerformanceGuardTest is Test {
    uint32 internal constant DELAY = 3600;
    uint32 internal constant TARGET = 150_000;

    SetupFeesPerformanceGuardHarness internal harness;
    MockHubAccountant internal accountant;

    function setUp() public {
        vm.warp(1_000_000);
        harness = new SetupFeesPerformanceGuardHarness();
        accountant = new MockHubAccountant();
        accountant.setPerformanceFee(0);
    }

    function test_skipsWhenLastGrossRateIsZero() public {
        accountant.setState(0, uint64(block.timestamp), DELAY);
        harness.applyPerf(address(accountant), TARGET);
        assertEq(harness.queuedLength(), 0, "post-migration enable must not be queued");
    }

    function test_skipsWhenCheckpointIsStale() public {
        accountant.setState(1_050_000, uint64(block.timestamp - DELAY - 1), DELAY);
        harness.applyPerf(address(accountant), TARGET);
        assertEq(harness.queuedLength(), 0, "stale checkpoint must not be queued");
    }

    function test_queuesWhenCheckpointIsFresh() public {
        accountant.setState(1_050_000, uint64(block.timestamp - 60), DELAY);
        harness.applyPerf(address(accountant), TARGET);

        assertEq(harness.queuedLength(), 1, "exactly one tx queued");
        (address target, bytes memory data) = harness.queued(0);
        assertEq(target, address(accountant));
        assertEq(keccak256(data), keccak256(abi.encodeCall(NestHubAccountant.updatePerformanceFee, (TARGET))));
    }

    function test_queuesAtExactDelayBoundary() public {
        accountant.setState(1_050_000, uint64(block.timestamp - DELAY), DELAY);
        harness.applyPerf(address(accountant), TARGET);
        assertEq(harness.queuedLength(), 1, "checkpoint aged exactly the delay is still fresh");
    }
}
