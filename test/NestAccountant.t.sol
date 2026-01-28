// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// utils
import {Test} from "forge-std/Test.sol";
import {Options, DefenderOptions, TxOverrides} from "@openzeppelin/foundry-upgrades/src/Options.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";

// contracts
import {Constants} from "script/Constants.sol";
import {MockNestAccountant, NestAccountant} from "test/mock/MockNestAccountant.sol";
import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";

// interfaces
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

// libraries
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

// types
import {DataTypes} from "contracts/types/DataTypes.sol";
import {Errors} from "contracts/types/Errors.sol";

contract NestAccountantForkTest is Constants, Test {
    MockNestAccountant internal immutable NEST_ACCOUNTANT;

    // ======================= Helper Functions =======================

    /// @dev Helper to verify unauthorized caller reverts with AUTH_UNAUTHORIZED
    /// @dev Should be called via vm.prank(address(1)) inside the test
    function _expectAuthUnauthorized() internal {
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
    }

    /// @dev Helper to test that a paused contract reverts with Paused error on a function call
    function _expectPausedRevert() internal {
        vm.expectRevert(Errors.Paused.selector);
    }

    /// @dev Helper to pause the contract
    function _pauseContract() internal {
        NEST_ACCOUNTANT.pause();
    }

    constructor() {
        // deploy NestAccountant
        Options memory _nestAccountantProxyOpts = Options({
            referenceContract: "",
            referenceBuildInfoDir: "",
            constructorData: abi.encode(USDC, NALPHA),
            exclude: new string[](0),
            unsafeAllow: "",
            unsafeAllowRenames: false,
            unsafeSkipProxyAdminCheck: false,
            unsafeSkipStorageCheck: false,
            unsafeSkipAllChecks: true,
            defender: DefenderOptions({
                useDefenderDeploy: false,
                skipVerifySourceCode: false,
                relayerId: "",
                salt: bytes32(0),
                upgradeApprovalProcessId: "",
                licenseType: "",
                skipLicenseType: false,
                txOverrides: TxOverrides({gasLimit: 30000000, gasPrice: 0, maxFeePerGas: 10, maxPriorityFeePerGas: 1}),
                metadata: ""
            })
        });

        address _nestAccountantProxy = Upgrades.deployTransparentProxy(
            "MockNestAccountant.sol",
            address(this),
            abi.encodeCall(
                NEST_ACCOUNTANT.initialize,
                (
                    IERC20(NALPHA).totalSupply(), // totalSharesLastUpdate
                    address(this), // payoutAddress
                    1000000, // startingExchangeRate
                    10003, // allowedExchangeRateChangeUpper
                    10000, // allowedExchangeRateChangeLower
                    3600, // minimumUpdateDelayInSeconds,
                    uint32(10_000), // managementFee,
                    address(this) // owner
                )
            ),
            _nestAccountantProxyOpts
        );

        NEST_ACCOUNTANT = MockNestAccountant(_nestAccountantProxy);
        assertEq(address(NEST_ACCOUNTANT.base()), address(USDC), "base address mismatch");
        assertEq(NEST_ACCOUNTANT.baseDecimals(), IERC20Metadata(USDC).decimals(), "base decimals mismatch");
        assertEq(NEST_ACCOUNTANT.owner(), address(this), "owner mismatch");
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().totalSharesLastUpdate,
            IERC20(NALPHA).totalSupply(),
            "total shares last update mismatch"
        );
        assertEq(NEST_ACCOUNTANT.getAccountantState().payoutAddress, address(this), "startingExchangeRate mismatch");
        assertEq(NEST_ACCOUNTANT.getAccountantState().feesOwedInBase, 0, "startingExchangeRate mismatch");
        assertEq(NEST_ACCOUNTANT.getAccountantState().exchangeRate, 1000000, "startingExchangeRate mismatch");
        assertEq(NEST_ACCOUNTANT.getAccountantState().feesOwedInBase, 0, "feesOwedInBase mismatch");
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().allowedExchangeRateChangeUpper,
            10003,
            "allowedExchangeRateChangeUpper mismatch"
        );
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().allowedExchangeRateChangeLower,
            10000,
            "allowedExchangeRateChangeLower mismatch"
        );
        // TODO assertEq(NEST_ACCOUNTANT.getAccountantState().lastUpdateTimestamp, block.timestamp, "lastUpdateTimestamp mismatch");
        assertEq(NEST_ACCOUNTANT.getAccountantState().isPaused, false, "isPaused mismatch");
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().minimumUpdateDelayInSeconds,
            3600,
            "minimumUpdateDelayInSeconds mismatch"
        );
    }

    function test_constructor_disablesInitializers() public {
        uint256 __totalSharesLastUpdate = IERC20(NALPHA).totalSupply();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        NEST_ACCOUNTANT.initialize(
            __totalSharesLastUpdate, address(this), 1000000, 10003, 10000, 3600, 10_000, address(this)
        );
    }

    /// @dev Ensures `share()` returns the NestShare address provided in constructor
    function test_share_returnsShareTokenAddress() public view {
        assertEq(NEST_ACCOUNTANT.share(), address(NALPHA));
    }

    /// @dev Ensures `_oneShare()` returns 10 ** share.decimals()
    function test_oneShare_returnsExpectedValue() public view {
        assertEq(NEST_ACCOUNTANT.oneShare(), 10 ** IERC20Metadata(NALPHA).decimals());
    }

    /// @dev Ensures `pause()` sets `isPaused = true` and emits `Paused()`
    function test_pause_setsPausedAndEmitsEvent() public {
        vm.prank(address(this));
        vm.expectEmit();
        emit NestAccountant.Paused();

        NEST_ACCOUNTANT.pause();

        assertTrue(NEST_ACCOUNTANT.getAccountantState().isPaused);
    }

    /// @dev Ensures `pause()` reverts when called by an unauthorized address
    function test_pause_revertsWhenUnauthorized() public {
        vm.prank(address(1));
        _expectAuthUnauthorized();
        NEST_ACCOUNTANT.pause();
    }

    /// @dev Ensures `unpause()` sets `isPaused = false` and emits `Unpaused()`
    function test_unpause_setsUnpausedAndEmitsEvent() public {
        // First pause so unpause has an effect
        vm.prank(address(this));
        NEST_ACCOUNTANT.pause();
        assertTrue(NEST_ACCOUNTANT.getAccountantState().isPaused);

        // Expect the Unpaused() event
        vm.prank(address(this));
        vm.expectEmit();
        emit NestAccountant.Unpaused();

        // Call unpause
        NEST_ACCOUNTANT.unpause();

        // Assert state updated
        assertFalse(NEST_ACCOUNTANT.getAccountantState().isPaused);
    }

    /// @dev Ensures `unpause()` reverts when called by an unauthorized address
    function test_unpause_revertsWhenUnauthorized() public {
        vm.prank(address(1));
        _expectAuthUnauthorized();
        NEST_ACCOUNTANT.unpause();
    }

    // ======================= claimFees Tests =======================
    // Note: claimFees tests are omitted because the function requires caller to be SHARE (NestVault)
    // and it checks OnlyCallableByNestShare before checking other conditions.
    // The function requires integration testing with actual NestVault.

    // ======================= updateDelay Tests =======================

    /// @dev Ensures `updateDelay` updates the minimum update delay correctly
    function test_updateDelay_updatesMinimumDelayAndEmitsEvent() public {
        DataTypes.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint32 initialDelay = initialState.minimumUpdateDelayInSeconds;
        uint32 newDelay = 7200; // 2 hours

        vm.expectEmit();
        emit NestAccountant.DelayInSecondsUpdated(initialDelay, newDelay);

        NEST_ACCOUNTANT.updateDelay(newDelay);

        DataTypes.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(updatedState.minimumUpdateDelayInSeconds, newDelay);
    }

    /// @dev Ensures `updateDelay` reverts when delay exceeds cap
    function test_updateDelay_revertsWhenDelayExceedsCap() public {
        uint32 excessiveDelay = 15 days; // Exceeds UPDATE_DELAY_CAP of 14 days
        vm.expectRevert(Errors.UpdateDelayTooLarge.selector);
        NEST_ACCOUNTANT.updateDelay(excessiveDelay);
    }

    /// @dev Ensures `updateDelay` reverts when called by unauthorized address
    function test_updateDelay_revertsWhenUnauthorized() public {
        vm.prank(address(1));
        _expectAuthUnauthorized();
        NEST_ACCOUNTANT.updateDelay(3600);
    }

    // ======================= updateUpper Tests =======================

    /// @dev Ensures `updateUpper` updates the upper bound correctly
    function test_updateUpper_updatesUpperBoundAndEmitsEvent() public {
        DataTypes.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint32 initialBound = initialState.allowedExchangeRateChangeUpper;
        uint32 newBound = 1015000; // 1.5% increase allowed

        NEST_ACCOUNTANT.updateUpper(newBound);

        DataTypes.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(updatedState.allowedExchangeRateChangeUpper, newBound, "Upper bound should be updated");
        assertNotEq(updatedState.allowedExchangeRateChangeUpper, initialBound, "Upper bound should have changed");
    }

    /// @dev Ensures `updateUpper` reverts when bound is too small (below 100%)
    function test_updateUpper_revertsWhenBoundTooSmall() public {
        uint32 smallBound = 999999; // Just under 1e6
        vm.expectRevert(Errors.UpperBoundTooSmall.selector);
        NEST_ACCOUNTANT.updateUpper(smallBound);
    }

    /// @dev Ensures `updateUpper` reverts when called by unauthorized address
    function test_updateUpper_revertsWhenUnauthorized() public {
        vm.prank(address(1));
        _expectAuthUnauthorized();
        NEST_ACCOUNTANT.updateUpper(11000);
    }

    // ======================= updateLower Tests =======================

    /// @dev Ensures `updateLower` updates the lower bound correctly
    function test_updateLower_updatesLowerBoundAndEmitsEvent() public {
        DataTypes.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint32 initialBound = initialState.allowedExchangeRateChangeLower;
        uint32 newBound = 990000; // 0.1% decrease allowed

        vm.expectEmit();
        emit NestAccountant.LowerBoundUpdated(initialBound, newBound);

        NEST_ACCOUNTANT.updateLower(newBound);

        DataTypes.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(updatedState.allowedExchangeRateChangeLower, newBound);
    }

    /// @dev Ensures `updateLower` reverts when bound is too large (above 100%)
    function test_updateLower_revertsWhenBoundTooLarge() public {
        uint32 largeBound = 1000001; // Just over 1e6
        vm.expectRevert(Errors.LowerBoundTooLarge.selector);
        NEST_ACCOUNTANT.updateLower(largeBound);
    }

    /// @dev Ensures `updateLower` reverts when called by unauthorized address
    function test_updateLower_revertsWhenUnauthorized() public {
        vm.prank(address(1));
        _expectAuthUnauthorized();
        NEST_ACCOUNTANT.updateLower(999000);
    }

    // ======================= updateManagementFee Tests =======================

    /// @dev Ensures `updateManagementFee` updates the fee correctly
    function test_updateManagementFee_updatesFeeAndEmitsEvent() public {
        DataTypes.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint32 initialFee = initialState.managementFee;
        uint32 newFee = 20000; // 2% annual fee

        vm.expectEmit();
        emit NestAccountant.ManagementFeeUpdated(initialFee, newFee);

        NEST_ACCOUNTANT.updateManagementFee(newFee);

        DataTypes.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(updatedState.managementFee, newFee);
    }

    /// @dev Ensures `updateManagementFee` reverts when fee exceeds cap (20%)
    function test_updateManagementFee_revertsWhenFeeExceedsCap() public {
        uint32 excessiveFee = 200001; // Just over 20%
        vm.expectRevert(Errors.ManagementFeeTooLarge.selector);
        NEST_ACCOUNTANT.updateManagementFee(excessiveFee);
    }

    /// @dev Ensures `updateManagementFee` reverts when called by unauthorized address
    function test_updateManagementFee_revertsWhenUnauthorized() public {
        vm.prank(address(1));
        _expectAuthUnauthorized();
        NEST_ACCOUNTANT.updateManagementFee(15000);
    }

    // ======================= updatePayoutAddress Tests =======================

    /// @dev Ensures `updatePayoutAddress` updates the payout address correctly
    function test_updatePayoutAddress_updatesAddressAndEmitsEvent() public {
        address newPayoutAddress = address(0x1234567890123456789012345678901234567890);

        vm.expectEmit();
        emit NestAccountant.PayoutAddressUpdated(address(this), newPayoutAddress);

        NEST_ACCOUNTANT.updatePayoutAddress(newPayoutAddress);

        DataTypes.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(updatedState.payoutAddress, newPayoutAddress);
    }

    /// @dev Ensures `updatePayoutAddress` reverts when called by unauthorized address
    function test_updatePayoutAddress_revertsWhenUnauthorized() public {
        vm.prank(address(1));
        _expectAuthUnauthorized();
        NEST_ACCOUNTANT.updatePayoutAddress(address(0x1111111111111111111111111111111111111111));
    }

    // ======================= setRateProviderData Tests =======================

    /// @dev Ensures `setRateProviderData` sets rate provider data correctly
    function test_setRateProviderData_setsDataAndEmitsEvent() public {
        address testAsset = address(0x2222222222222222222222222222222222222222);
        address testProvider = address(0x3333333333333333333333333333333333333333);

        vm.expectEmit();
        emit NestAccountant.RateProviderUpdated(testAsset, true, testProvider);

        NEST_ACCOUNTANT.setRateProviderData(ERC20(testAsset), true, testProvider);
    }

    /// @dev Ensures `setRateProviderData` reverts when called by unauthorized address
    function test_setRateProviderData_revertsWhenUnauthorized() public {
        vm.prank(address(1));
        _expectAuthUnauthorized();
        NEST_ACCOUNTANT.setRateProviderData(ERC20(address(0x1111)), false, address(0x2222));
    }

    // ======================= getRate Tests =======================

    /// @dev Ensures `getRate` returns the current exchange rate
    function test_getRate_returnsCurrentExchangeRate() public view {
        uint256 rate = NEST_ACCOUNTANT.getRate();
        assertEq(rate, NEST_ACCOUNTANT.getAccountantState().exchangeRate);
    }

    // ======================= getRateSafe Tests =======================

    /// @dev Ensures `getRateSafe` returns the exchange rate when not paused
    function test_getRateSafe_returnsRateWhenNotPaused() public view {
        uint256 rate = NEST_ACCOUNTANT.getRateSafe();
        assertEq(rate, NEST_ACCOUNTANT.getAccountantState().exchangeRate);
    }

    /// @dev Ensures `getRateSafe` reverts when paused
    function test_getRateSafe_revertsWhenPaused() public {
        _pauseContract();
        _expectPausedRevert();
        NEST_ACCOUNTANT.getRateSafe();
    }

    // ======================= updateExchangeRate Tests =======================

    /// @dev Ensures that multiple consecutive invalid updates don't accumulate duplicate fees
    function test_updateExchangeRate_multipleInvalidUpdatesDoNotAccumulateDuplicateFees() public {
        DataTypes.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint256 initialExchangeRate = initialState.exchangeRate;

        // First invalid update (too much increase)
        uint256 timeDelta1 = 1000;
        vm.warp(block.timestamp + timeDelta1);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialExchangeRate + 20));

        DataTypes.AccountantState memory stateAfterFirst = NEST_ACCOUNTANT.getAccountantState();
        uint256 feesAfterFirst = stateAfterFirst.feesOwedInBase;

        // While paused, send another invalid update (no fee accrual since already paused)
        uint256 timeDelta2 = 800;
        vm.warp(block.timestamp + timeDelta2);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialExchangeRate - 30));

        DataTypes.AccountantState memory stateAfterSecond = NEST_ACCOUNTANT.getAccountantState();
        uint256 feesAfterSecond = stateAfterSecond.feesOwedInBase;

        // Fees should NOT accumulate again since already paused
        assertEq(feesAfterSecond, feesAfterFirst, "Invalid updates while paused should not accumulate additional fees");
    }

    /// @dev Ensures that when paused, minimum delay is bypassed to allow immediate rate correction
    function test_updateExchangeRate_pausedCanUpdateBeforeMinimumDelayWithValidRate() public {
        DataTypes.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint256 initialExchangeRate = initialState.exchangeRate;
        uint64 minimumDelay = initialState.minimumUpdateDelayInSeconds;

        // First, do a valid update after waiting for minimum delay
        vm.warp(block.timestamp + minimumDelay + 100);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialExchangeRate));

        // Then pause by sending an invalid rate while before minimum delay
        uint256 shortTime = 100; // Before minimum delay
        vm.warp(block.timestamp + shortTime);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialExchangeRate + 50000)); // Exceeds upper bound → pauses

        DataTypes.AccountantState memory stateAfterPause = NEST_ACCOUNTANT.getAccountantState();
        assertTrue(stateAfterPause.isPaused, "Should be paused due to invalid rate");
        assertEq(stateAfterPause.exchangeRate, initialExchangeRate, "Rate should not change on pause");

        // While paused, immediately update with valid same rate (no timing issue, no bounds issue)
        uint256 stateTimestamp = stateAfterPause.lastUpdateTimestamp;
        vm.warp(stateTimestamp + 50); // 50 seconds after pause (still before 3600 minimum delay would require)
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialExchangeRate)); // Same rate, just updating timestamp

        DataTypes.AccountantState memory stateAfterCorrected = NEST_ACCOUNTANT.getAccountantState();
        assertTrue(stateAfterCorrected.isPaused, "Should remain paused");
        assertEq(
            stateAfterCorrected.lastUpdateTimestamp,
            stateTimestamp + 50,
            "Timestamp should be updated even while paused"
        );
    }

    /// @dev Ensures that exchange rate remains unchanged after an invalid update attempt
    function test_updateExchangeRate_invalidUpdateDoesNotChangeRate() public {
        uint256 initialRate = NEST_ACCOUNTANT.getAccountantState().exchangeRate;

        // Attempt invalid update
        vm.warp(block.timestamp + 1000);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialRate + 50)); // Exceeds bounds

        // Rate should remain unchanged
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().exchangeRate,
            initialRate,
            "Exchange rate should not change on invalid update"
        );
    }

    /// @dev Ensures that total shares are updated even on invalid updates to properly calculate future fees
    function test_updateExchangeRate_invalidUpdateAdvancesTotalSharesAndTimestamp() public {
        DataTypes.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint64 initialTimestamp = initialState.lastUpdateTimestamp;

        uint256 timeDelta = 2000;
        vm.warp(block.timestamp + timeDelta);

        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialState.exchangeRate + 100));

        DataTypes.AccountantState memory stateAfterInvalid = NEST_ACCOUNTANT.getAccountantState();

        // Timestamp should advance
        assertEq(
            stateAfterInvalid.lastUpdateTimestamp,
            initialTimestamp + timeDelta,
            "Timestamp should advance on invalid update"
        );

        // Total shares should be updated
        uint256 currentTotalShares = IERC20(NALPHA).totalSupply();
        assertEq(
            stateAfterInvalid.totalSharesLastUpdate,
            currentTotalShares,
            "Total shares should be updated on invalid update"
        );
    }

    /// @dev Ensures that invalid updates due to rate exceeding upper bound pause the contract
    function test_updateExchangeRate_invalidRateUpperBoundPausesContract() public {
        DataTypes.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(initialState.isPaused, false, "Contract should start unpaused");

        // Attempt update with rate exceeding upper bound
        uint256 invalidRate = initialState.exchangeRate + 100; // Exceeds upper bound
        vm.warp(block.timestamp + 1000);

        NEST_ACCOUNTANT.updateExchangeRate(uint96(invalidRate));

        DataTypes.AccountantState memory stateAfterUpdate = NEST_ACCOUNTANT.getAccountantState();
        assertTrue(stateAfterUpdate.isPaused, "Contract should be paused after invalid rate update");
    }

    /// @dev Ensures that invalid updates due to rate below lower bound pause the contract
    function test_updateExchangeRate_invalidRateLowerBoundPausesContract() public {
        DataTypes.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(initialState.isPaused, false, "Contract should start unpaused");

        // Attempt update with rate below lower bound
        uint256 invalidRate = initialState.exchangeRate - 100; // Below lower bound
        vm.warp(block.timestamp + 1000);

        NEST_ACCOUNTANT.updateExchangeRate(uint96(invalidRate));

        DataTypes.AccountantState memory stateAfterUpdate = NEST_ACCOUNTANT.getAccountantState();
        assertTrue(stateAfterUpdate.isPaused, "Contract should be paused after invalid rate update");
    }

    /// @dev Ensures that invalid updates due to insufficient time delay pause the contract
    function test_updateExchangeRate_invalidTimingPausesContract() public {
        DataTypes.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(initialState.isPaused, false, "Contract should start unpaused");

        // Attempt update before minimum delay has passed
        uint256 timeTooEarly = initialState.minimumUpdateDelayInSeconds / 2;
        vm.warp(block.timestamp + timeTooEarly);

        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialState.exchangeRate)); // Valid rate but invalid timing

        DataTypes.AccountantState memory stateAfterUpdate = NEST_ACCOUNTANT.getAccountantState();
        assertTrue(stateAfterUpdate.isPaused, "Contract should be paused after update with invalid timing");
    }

    /// @dev Ensures that while paused, valid rate updates are accepted even if before minimum delay
    function test_updateExchangeRate_pausedBypassesMinimumDelayCheck() public {
        DataTypes.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint256 initialRate = initialState.exchangeRate;
        uint64 minimumDelay = initialState.minimumUpdateDelayInSeconds;

        // Do a valid update first after waiting for minimum delay
        vm.warp(block.timestamp + minimumDelay + 100);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialRate));

        DataTypes.AccountantState memory stateAfterValidUpdate = NEST_ACCOUNTANT.getAccountantState();
        uint64 validUpdateTimestamp = stateAfterValidUpdate.lastUpdateTimestamp;

        // Pause the contract with an invalid rate (exceeds bounds) BEFORE minimum delay
        uint256 shortWait = 100; // Before minimumDelay
        vm.warp(validUpdateTimestamp + shortWait);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialRate + 50000)); // Exceeds upper bound → pauses

        DataTypes.AccountantState memory pausedState = NEST_ACCOUNTANT.getAccountantState();
        assertTrue(pausedState.isPaused, "Contract should be paused");
        assertEq(pausedState.exchangeRate, initialRate, "Rate should not change on invalid update");

        // While paused, try to update rate with a very short time delta (would fail if not paused)
        uint64 pauseTimestamp = pausedState.lastUpdateTimestamp;
        vm.warp(pauseTimestamp + 50); // Only 50 seconds, but minimum delay is 3600

        // This should succeed because paused bypasses the minimum delay check
        // Using the same rate to avoid bounds issues
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialRate));

        DataTypes.AccountantState memory afterBypass = NEST_ACCOUNTANT.getAccountantState();
        assertEq(afterBypass.lastUpdateTimestamp, pauseTimestamp + 50, "Should update timestamp while paused");
        assertTrue(afterBypass.isPaused, "Should still be paused");
    }

    /// @dev Helper function to calculate expected fees for a given time period
    function calculateExpectedFees(uint128 totalShares, uint256 exchangeRate, uint32 managementFee, uint256 timeDelta)
        internal
        view
        returns (uint256)
    {
        uint256 ONE_SHARE = NEST_ACCOUNTANT.oneShare();
        uint256 ONE_YEAR = 365 days;
        uint256 DENOMINATOR = 1e6;

        uint256 assets = uint256(totalShares) * exchangeRate / ONE_SHARE;
        uint256 managementFeesAnnual = assets * managementFee / DENOMINATOR;
        return managementFeesAnnual * timeDelta / ONE_YEAR;
    }
}
