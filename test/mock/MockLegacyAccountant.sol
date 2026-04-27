// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {ERC20} from "@solmate/tokens/ERC20.sol";

/// @title MockLegacyAccountant
/// @notice A mock for a legacy AccountantWithRateProviders that does not implement global pending-share methods.
///         This contract deliberately omits totalPendingShares(), increaseTotalPendingShares(), and
///         decreaseTotalPendingShares() to test backward compatibility behavior.
contract MockLegacyAccountant {
    uint256 internal rate;

    function setRate(uint256 _rate) public {
        rate = _rate;
    }

    function getRateInQuoteSafe(ERC20) external view returns (uint256) {
        return rate;
    }

    function getRate() external view returns (uint256) {
        return rate;
    }

    // NOTE: Deliberately does NOT implement:
    // - totalPendingShares()
    // - increaseTotalPendingShares()
    // - decreaseTotalPendingShares()
    // This simulates a base AccountantWithRateProviders without global pending-share tracking.
}
