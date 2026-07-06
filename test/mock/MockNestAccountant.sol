// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";

contract MockNestAccountant is NestHubAccountant {
    constructor(address _base, address _share) NestHubAccountant(_base, _share) {}

    function getLastGrossRate() external view returns (uint96) {
        return getAccountantState().lastGrossRate;
    }

    /// @dev Test helper: invoke the internal performance-fee accrual directly (e.g. with zero supply,
    ///      which the public path cannot reach when live SHARE supply is non-zero).
    function accruePerformanceFeesForTesting(
        uint256 _newExchangeRate,
        uint256 _postManagementFeeRate,
        uint256 _totalShares,
        uint256 _oneShare,
        uint64 _currentTime
    ) external returns (uint256) {
        return _accruePerformanceFees(_newExchangeRate, _postManagementFeeRate, _totalShares, _oneShare, _currentTime);
    }

    /// @dev Test helper: read the carried management fee from the EIP-7201 storage slot.
    function managementFeeCarryForTesting() external view returns (uint256) {
        bytes32 slot = 0xb378036f9633fc394c3579301b38ac88997c2589544525e367cd650f76eaa300;
        NestAccountantStorage storage $;
        assembly {
            $.slot := slot
        }
        return $.managementFeeCarry;
    }

    /// @dev Test helper: directly set the management fee carry in the EIP-7201 storage slot.
    function setManagementFeeCarryForTesting(uint256 _carry) external {
        bytes32 slot = 0xb378036f9633fc394c3579301b38ac88997c2589544525e367cd650f76eaa300;
        NestAccountantStorage storage $;
        assembly {
            $.slot := slot
        }
        $.managementFeeCarry = _carry;
    }

    /// @dev Test helper: directly set feesOwedInBase in the EIP-7201 storage slot.
    function setFeesOwedForTesting(uint128 _feesOwed) external {
        bytes32 slot = 0xb378036f9633fc394c3579301b38ac88997c2589544525e367cd650f76eaa300;
        NestAccountantStorage storage $;
        assembly {
            $.slot := slot
        }
        $.accountantState.feesOwedInBase = _feesOwed;
    }

    /// @dev Test helper: directly set the reserve to a single batch with the given amount.
    function setReserveForTesting(uint128 _amount, uint64 _timestamp) external {
        // Access the same EIP-7201 storage slot as the main contract
        bytes32 slot = 0xb378036f9633fc394c3579301b38ac88997c2589544525e367cd650f76eaa300;
        NestAccountantStorage storage $;
        assembly {
            $.slot := slot
        }
        PerformanceFeeReserve storage rs = $.performanceFeeState.reserve;
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
