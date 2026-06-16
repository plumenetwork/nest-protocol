// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Constants} from "script/Constants.sol";
import {NestSpokeAccountant} from "contracts/accountant/NestSpokeAccountant.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

import {Errors} from "contracts/types/Errors.sol";

contract NestSpokeAccountantTest is Constants, Test {
    NestSpokeAccountant internal accountant;

    uint96 constant STARTING_RATE = 1e6;
    uint32 constant UPPER_BOUND = 1_100_000; // +10%
    uint32 constant LOWER_BOUND = 900_000; // -10%
    uint32 constant MIN_DELAY = 3600;

    function setUp() public {
        vm.createSelectFork("ethereum");

        NestSpokeAccountant impl = new NestSpokeAccountant(USDC, NALPHA);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(this),
            abi.encodeCall(
                NestSpokeAccountant.initialize, (STARTING_RATE, UPPER_BOUND, LOWER_BOUND, MIN_DELAY, address(this))
            )
        );

        accountant = NestSpokeAccountant(address(proxy));
    }

    // ======================= Initialization =======================

    function test_initialize_setsRate() public view {
        assertEq(accountant.getRate(), STARTING_RATE);
    }

    function test_initialize_boundsSet() public view {
        NestSpokeAccountant.AccountantState memory state = accountant.getAccountantState();
        assertEq(state.allowedExchangeRateChangeUpper, UPPER_BOUND);
        assertEq(state.allowedExchangeRateChangeLower, LOWER_BOUND);
        assertEq(state.minimumUpdateDelayInSeconds, MIN_DELAY);
    }

    // ======================= updateExchangeRate =======================

    function test_updateExchangeRate_storesRate() public {
        vm.warp(block.timestamp + MIN_DELAY + 1);

        uint96 newRate = 1_050_000; // +5%, within bounds
        accountant.updateExchangeRate(newRate, 0);

        assertEq(accountant.getRate(), newRate);
    }

    function test_updateExchangeRate_noFeeHaircut() public {
        vm.warp(block.timestamp + MIN_DELAY + 1);

        uint96 newRate = 1_050_000;
        accountant.updateExchangeRate(newRate, 0);

        // Rate stored exactly as passed — no fee deduction
        assertEq(accountant.getRate(), newRate, "Spoke should store rate without fee haircut");
    }

    function test_updateExchangeRate_emitsEvent() public {
        vm.warp(block.timestamp + MIN_DELAY + 1);

        uint96 newRate = 1_050_000;
        vm.expectEmit();
        emit NestSpokeAccountant.ExchangeRateUpdated(STARTING_RATE, newRate, uint64(block.timestamp));
        accountant.updateExchangeRate(newRate, 0);
    }

    function test_updateExchangeRate_revertsOnUpperBound() public {
        vm.warp(block.timestamp + MIN_DELAY + 1);

        uint96 tooHigh = 1_200_000; // +20%, exceeds +10% upper bound
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        accountant.updateExchangeRate(tooHigh, 0);
    }

    function test_updateExchangeRate_revertsOnLowerBound() public {
        vm.warp(block.timestamp + MIN_DELAY + 1);

        uint96 tooLow = 800_000; // -20%, exceeds -10% lower bound
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        accountant.updateExchangeRate(tooLow, 0);
    }

    function test_updateExchangeRate_revertsOnMinimumDelay() public {
        vm.warp(block.timestamp + 50); // less than MIN_DELAY

        vm.expectRevert(Errors.MinimumUpdateDelayNotPassed.selector);
        accountant.updateExchangeRate(STARTING_RATE, 0);
    }

    function test_updateExchangeRate_revertsWhenUnauthorized() public {
        vm.warp(block.timestamp + MIN_DELAY + 1);

        vm.prank(address(1));
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        accountant.updateExchangeRate(1_050_000, 0);
    }

    // ======================= View functions =======================

    function test_getRateSafe_revertsWhenPaused() public {
        accountant.pause();
        vm.expectRevert(Errors.Paused.selector);
        accountant.getRateSafe();
    }

    function test_getRateInQuoteSafe_revertsWhenPaused() public {
        accountant.pause();
        vm.expectRevert(Errors.Paused.selector);
        accountant.getRateInQuoteSafe(ERC20(USDC));
    }

    function test_getRateInQuoteSafe_returnsRate() public view {
        uint256 rate = accountant.getRateInQuoteSafe(ERC20(USDC));
        assertEq(rate, STARTING_RATE);
    }

    // ======================= Pending shares =======================

    function test_increaseTotalPendingShares() public {
        accountant.increaseTotalPendingShares(100);
        assertEq(accountant.totalPendingShares(), 100);
    }

    function test_decreaseTotalPendingShares() public {
        accountant.increaseTotalPendingShares(100);
        accountant.decreaseTotalPendingShares(40);
        assertEq(accountant.totalPendingShares(), 60);
    }

    // ======================= Pause/Unpause =======================

    function test_pause_unpause() public {
        accountant.pause();
        assertTrue(accountant.getAccountantState().isPaused);

        accountant.unpause();
        assertFalse(accountant.getAccountantState().isPaused);
    }
}
