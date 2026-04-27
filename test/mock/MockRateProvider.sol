// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Errors} from "contracts/types/Errors.sol";

contract MockRateProvider {
    uint256 internal rate;
    uint256 internal _totalPendingShares;

    function setRate(uint256 _rate) public {
        rate = _rate;
    }

    function getRateInQuoteSafe(ERC20) external view returns (uint256) {
        return rate;
    }

    // Mock functions for NestAccountant compatibility
    function totalPendingShares() external view returns (uint256) {
        return _totalPendingShares;
    }

    function increaseTotalPendingShares(uint256 _amount) external {
        _totalPendingShares += _amount;
    }

    /// @dev Mirrors production NestAccountant.decreaseTotalPendingShares behavior:
    ///      reverts with Errors.InsufficientBalance()
    function decreaseTotalPendingShares(uint256 _amount) external {
        if (_amount > _totalPendingShares) {
            revert Errors.InsufficientBalance();
        }
        _totalPendingShares -= _amount;
    }
}
