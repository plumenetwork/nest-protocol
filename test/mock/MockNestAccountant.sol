// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";

contract MockNestAccountant is NestHubAccountant {
    constructor(address _base, address _share) NestHubAccountant(_base, _share) {}

    function share() external view returns (address) {
        return SHARE;
    }

    function getLastGrossRate() external view returns (uint96) {
        return getAccountantState().lastGrossRate;
    }

    /// @dev Test helper: directly set the reserve to a single batch with the given amount.
    function setReserveForTesting(uint128 _amount, uint64 _timestamp) external {
        // Access the same EIP-7201 storage slot as the main contract
        bytes32 slot = 0xb378036f9633fc394c3579301b38ac88997c2589544525e367cd650f76eaa300;
        NestAccountantStorage storage $;
        assembly {
            $.slot := slot
        }
        ReserveState storage rs = $.reserveState;
        // Clear existing batches
        uint64 head = rs.batchHead;
        uint64 tail = rs.batchTail;
        for (uint64 i = head; i < tail; i++) {
            delete rs.batches[i];
        }
        // Set a single batch
        rs.batches[0] = ReserveBatch(_amount, _timestamp);
        rs.batchHead = 0;
        rs.batchTail = 1;
        rs.totalReserve = _amount;
    }
}
