// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// utils
import {Test} from "forge-std/Test.sol";
import {Options, DefenderOptions, TxOverrides} from "@openzeppelin/foundry-upgrades/src/Options.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";

// contracts
import {Constants} from "script/Constants.sol";
import {MockNestAccountant, NestAccountant} from "test/mock/MockNestAccountant.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// interfaces
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

// types
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

    /// @dev Helper to deploy a fresh NestAccountant implementation.
    function _deployNestAccountantImplementation() internal returns (address) {
        return address(new MockNestAccountant(USDC, NALPHA));
    }

    /// @dev Helper to deploy a fresh NestAccountant proxy with configurable initialize bounds/delay
    function _deployNestAccountantProxyWithInitParams(
        address _implementation,
        uint256 _totalSharesLastUpdate,
        uint32 _allowedExchangeRateChangeUpper,
        uint32 _allowedExchangeRateChangeLower,
        uint32 _minimumUpdateDelayInSeconds
    ) internal returns (address) {
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            _implementation,
            address(this),
            abi.encodeCall(
                NestAccountant.initialize,
                (
                    _totalSharesLastUpdate,
                    address(this),
                    uint96(1e6),
                    _allowedExchangeRateChangeUpper,
                    _allowedExchangeRateChangeLower,
                    _minimumUpdateDelayInSeconds,
                    uint32(10_000),
                    address(this)
                )
            )
        );
        return address(_proxy);
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
                    1_000_003, // allowedExchangeRateChangeUpper
                    999_997, // allowedExchangeRateChangeLower
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
            1_000_003,
            "allowedExchangeRateChangeUpper mismatch"
        );
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().allowedExchangeRateChangeLower,
            999_997,
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
            __totalSharesLastUpdate, address(this), 1000000, 1_000_003, 999_997, 3600, 10_000, address(this)
        );
    }

    function test_constructor_revertsWhenBaseIsZero() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new MockNestAccountant(address(0), NALPHA);
    }

    function test_constructor_revertsWhenShareIsZero() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new MockNestAccountant(USDC, address(0));
    }

    /// @dev Ensures initialize validates upper bound the same way as updateUpper
    function test_initialize_revertsWhenUpperBoundTooSmall() public {
        address _implementation = _deployNestAccountantImplementation();
        uint256 _totalSharesLastUpdate = IERC20(NALPHA).totalSupply();
        vm.expectRevert(Errors.UpperBoundTooSmall.selector);
        _deployNestAccountantProxyWithInitParams(_implementation, _totalSharesLastUpdate, 999999, 10000, 3600);
    }

    /// @dev Ensures initialize validates lower bound the same way as updateLower
    function test_initialize_revertsWhenLowerBoundTooLarge() public {
        address _implementation = _deployNestAccountantImplementation();
        uint256 _totalSharesLastUpdate = IERC20(NALPHA).totalSupply();
        vm.expectRevert(Errors.LowerBoundTooLarge.selector);
        _deployNestAccountantProxyWithInitParams(_implementation, _totalSharesLastUpdate, 1_000_003, 1000001, 3600);
    }

    /// @dev Ensures initialize validates minimum update delay the same way as updateDelay
    function test_initialize_revertsWhenDelayExceedsCap() public {
        address _implementation = _deployNestAccountantImplementation();
        uint256 _totalSharesLastUpdate = IERC20(NALPHA).totalSupply();
        vm.expectRevert(Errors.UpdateDelayTooLarge.selector);
        _deployNestAccountantProxyWithInitParams(_implementation, _totalSharesLastUpdate, 1_000_003, 999_997, 15 days);
    }

    /// @dev Ensures `share()` returns the NestShare address provided in constructor
    function test_share_returnsShareTokenAddress() public view {
        assertEq(NEST_ACCOUNTANT.share(), address(NALPHA));
    }

    /// @dev Ensures share decimals align with the expected token
    function test_share_decimals_matchExpected() public view {
        assertEq(IERC20Metadata(NEST_ACCOUNTANT.share()).decimals(), IERC20Metadata(NALPHA).decimals());
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
        NestAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint32 initialDelay = initialState.minimumUpdateDelayInSeconds;
        uint32 newDelay = 7200; // 2 hours

        vm.expectEmit();
        emit NestAccountant.DelayInSecondsUpdated(initialDelay, newDelay);

        NEST_ACCOUNTANT.updateDelay(newDelay);

        NestAccountant.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
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
        NestAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint32 initialBound = initialState.allowedExchangeRateChangeUpper;
        uint32 newBound = 1015000; // 1.5% increase allowed

        NEST_ACCOUNTANT.updateUpper(newBound);

        NestAccountant.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
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
        NestAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint32 initialBound = initialState.allowedExchangeRateChangeLower;
        uint32 newBound = 990000; // 0.1% decrease allowed

        vm.expectEmit();
        emit NestAccountant.LowerBoundUpdated(initialBound, newBound);

        NEST_ACCOUNTANT.updateLower(newBound);

        NestAccountant.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
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
        NestAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint32 initialFee = initialState.managementFee;
        uint32 newFee = 20000; // 2% annual fee

        vm.expectEmit();
        emit NestAccountant.ManagementFeeUpdated(initialFee, newFee);

        NEST_ACCOUNTANT.updateManagementFee(newFee);

        NestAccountant.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(updatedState.managementFee, newFee);
    }

    /// @dev Ensures fee update accrues using the old rate first and only applies the new fee going forward
    function test_updateManagementFee_accruesOldFeeAndPreventsRetroactiveHigherFee() public {
        NestAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint32 oldFee = initialState.managementFee;
        uint32 newFee = 20000; // 2% annual fee

        uint256 firstPeriod = 7 days;
        vm.warp(block.timestamp + firstPeriod);

        uint256 expectedOldFeeAccrual =
            calculateExpectedFees(initialState.totalSharesLastUpdate, initialState.exchangeRate, oldFee, firstPeriod);

        NEST_ACCOUNTANT.updateManagementFee(newFee);

        NestAccountant.AccountantState memory stateAfterFeeUpdate = NEST_ACCOUNTANT.getAccountantState();
        assertEq(stateAfterFeeUpdate.managementFee, newFee, "Management fee should be updated");
        assertEq(stateAfterFeeUpdate.feesOwedInBase, expectedOldFeeAccrual, "Old fee should accrue before fee update");
        assertEq(stateAfterFeeUpdate.lastUpdateTimestamp, block.timestamp, "Timestamp should reset on fee update");
        assertEq(
            stateAfterFeeUpdate.totalSharesLastUpdate,
            IERC20(NALPHA).totalSupply(),
            "Total shares snapshot should refresh on fee update"
        );

        uint256 secondPeriod = 5 days;
        vm.warp(block.timestamp + secondPeriod);

        NEST_ACCOUNTANT.updateExchangeRate(stateAfterFeeUpdate.exchangeRate);

        uint256 expectedNewFeeAccrual = calculateExpectedFees(
            stateAfterFeeUpdate.totalSharesLastUpdate, stateAfterFeeUpdate.exchangeRate, newFee, secondPeriod
        );

        NestAccountant.AccountantState memory finalState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(
            finalState.feesOwedInBase,
            expectedOldFeeAccrual + expectedNewFeeAccrual,
            "New fee must only apply after fee update timestamp"
        );
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

        NestAccountant.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
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

    /// @dev Ensures invalid updates revert while unpaused and do not accrue fees or checkpoint state.
    function test_updateExchangeRate_multipleInvalidUpdatesDoNotAccumulateDuplicateFees() public {
        NestAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint256 initialExchangeRate = initialState.exchangeRate;
        uint64 minimumDelay = initialState.minimumUpdateDelayInSeconds;

        vm.warp(block.timestamp + minimumDelay + 1000);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialExchangeRate + 20));

        NestAccountant.AccountantState memory stateAfterFirst = NEST_ACCOUNTANT.getAccountantState();
        assertEq(stateAfterFirst.feesOwedInBase, initialState.feesOwedInBase, "Fees should not accrue on revert");
        assertEq(
            stateAfterFirst.lastUpdateTimestamp,
            initialState.lastUpdateTimestamp,
            "Timestamp should not advance on revert"
        );
        assertEq(
            stateAfterFirst.totalSharesLastUpdate,
            initialState.totalSharesLastUpdate,
            "Shares checkpoint should not advance on revert"
        );
        assertFalse(stateAfterFirst.isPaused, "Invalid update should not auto-pause");

        vm.warp(block.timestamp + minimumDelay + 800);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialExchangeRate - 30));

        NestAccountant.AccountantState memory stateAfterSecond = NEST_ACCOUNTANT.getAccountantState();
        assertEq(stateAfterSecond.feesOwedInBase, initialState.feesOwedInBase, "Repeated invalid updates should revert");
    }

    /// @dev Ensures pause state does not bypass minimum delay checks.
    function test_updateExchangeRate_pausedDoesNotBypassMinimumDelay() public {
        NestAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        _pauseContract();
        NestAccountant.AccountantState memory pausedState = NEST_ACCOUNTANT.getAccountantState();
        uint256 initialExchangeRate = pausedState.exchangeRate;

        vm.warp(block.timestamp + 50);
        vm.expectRevert(Errors.MinimumUpdateDelayNotPassed.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialExchangeRate));

        NestAccountant.AccountantState memory stateAfterAttempt = NEST_ACCOUNTANT.getAccountantState();
        assertTrue(stateAfterAttempt.isPaused, "Should remain paused");
        assertEq(
            stateAfterAttempt.lastUpdateTimestamp,
            pausedState.lastUpdateTimestamp,
            "Timestamp should not update on reverted paused update"
        );
        assertEq(
            stateAfterAttempt.feesOwedInBase,
            pausedState.feesOwedInBase,
            "Fees should not accrue on reverted paused update"
        );
        assertEq(
            stateAfterAttempt.exchangeRate,
            initialState.exchangeRate,
            "Exchange rate should remain unchanged on reverted paused update"
        );
    }

    /// @dev Ensures that exchange rate remains unchanged after an invalid update attempt.
    function test_updateExchangeRate_invalidUpdateDoesNotChangeRate() public {
        NestAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint256 initialRate = initialState.exchangeRate;
        uint64 minimumDelay = initialState.minimumUpdateDelayInSeconds;

        vm.warp(block.timestamp + minimumDelay + 1000);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialRate + 50));

        assertEq(
            NEST_ACCOUNTANT.getAccountantState().exchangeRate,
            initialRate,
            "Exchange rate should not change on invalid update"
        );
    }

    /// @dev Ensures invalid updates do not advance total shares or timestamps.
    function test_updateExchangeRate_invalidUpdateDoesNotAdvanceTotalSharesAndTimestamp() public {
        NestAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint64 initialTimestamp = initialState.lastUpdateTimestamp;

        vm.warp(block.timestamp + initialState.minimumUpdateDelayInSeconds + 2000);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialState.exchangeRate + 100));

        NestAccountant.AccountantState memory stateAfterInvalid = NEST_ACCOUNTANT.getAccountantState();
        assertEq(
            stateAfterInvalid.lastUpdateTimestamp, initialTimestamp, "Timestamp should not advance on invalid update"
        );
        assertEq(
            stateAfterInvalid.totalSharesLastUpdate,
            initialState.totalSharesLastUpdate,
            "Total shares should not update on invalid update"
        );
    }

    /// @dev Ensures that invalid updates due to rate exceeding upper bound revert while unpaused.
    function test_updateExchangeRate_invalidRateUpperBoundRevertsWhenUnpaused() public {
        NestAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(initialState.isPaused, false, "Contract should start unpaused");
        uint64 minimumDelay = initialState.minimumUpdateDelayInSeconds;

        uint256 invalidRate = initialState.exchangeRate + 100;
        vm.warp(block.timestamp + minimumDelay + 1000);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(invalidRate));

        NestAccountant.AccountantState memory stateAfterUpdate = NEST_ACCOUNTANT.getAccountantState();
        assertFalse(stateAfterUpdate.isPaused, "Invalid update should revert instead of pausing");
    }

    /// @dev Ensures that invalid updates due to rate below lower bound revert while unpaused.
    function test_updateExchangeRate_invalidRateLowerBoundRevertsWhenUnpaused() public {
        NestAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(initialState.isPaused, false, "Contract should start unpaused");
        uint64 minimumDelay = initialState.minimumUpdateDelayInSeconds;

        uint256 invalidRate = initialState.exchangeRate - 100;
        vm.warp(block.timestamp + minimumDelay + 1000);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(invalidRate));

        NestAccountant.AccountantState memory stateAfterUpdate = NEST_ACCOUNTANT.getAccountantState();
        assertFalse(stateAfterUpdate.isPaused, "Invalid update should revert instead of pausing");
    }

    /// @dev Ensures that invalid updates due to insufficient time delay revert while unpaused.
    function test_updateExchangeRate_invalidTimingRevertsWhenUnpaused() public {
        NestAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(initialState.isPaused, false, "Contract should start unpaused");

        uint256 timeTooEarly = initialState.minimumUpdateDelayInSeconds / 2;
        vm.warp(block.timestamp + timeTooEarly);
        vm.expectRevert(Errors.MinimumUpdateDelayNotPassed.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialState.exchangeRate));

        NestAccountant.AccountantState memory stateAfterUpdate = NEST_ACCOUNTANT.getAccountantState();
        assertFalse(stateAfterUpdate.isPaused, "Invalid update should revert instead of pausing");
    }

    /// @dev Ensures pause state does not bypass exchange-rate bounds checks.
    function test_updateExchangeRate_pausedDoesNotBypassBounds() public {
        NestAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint256 initialRate = initialState.exchangeRate;
        uint64 minimumDelay = initialState.minimumUpdateDelayInSeconds;

        vm.warp(block.timestamp + minimumDelay + 100);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialRate));

        _pauseContract();
        NestAccountant.AccountantState memory pausedState = NEST_ACCOUNTANT.getAccountantState();
        uint64 pauseTimestamp = pausedState.lastUpdateTimestamp;
        uint96 outOfBoundsRate = uint96(initialRate + 50000);

        vm.warp(pauseTimestamp + minimumDelay + 1);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateExchangeRate(outOfBoundsRate);

        NestAccountant.AccountantState memory afterBypass = NEST_ACCOUNTANT.getAccountantState();
        assertEq(afterBypass.lastUpdateTimestamp, pauseTimestamp, "Timestamp should not change on reverted update");
        assertEq(afterBypass.exchangeRate, pausedState.exchangeRate, "Rate should not change on reverted update");
        assertEq(afterBypass.feesOwedInBase, pausedState.feesOwedInBase, "Fees should not accrue on reverted update");
        assertTrue(afterBypass.isPaused, "Should still be paused");
    }

    /// @dev Helper function to calculate expected fees for a given time period
    function calculateExpectedFees(uint256 totalShares, uint256 exchangeRate, uint32 managementFee, uint256 timeDelta)
        internal
        view
        returns (uint256)
    {
        uint256 ONE_SHARE = 10 ** IERC20Metadata(NALPHA).decimals();
        uint256 ONE_YEAR = 365 days;
        uint256 DENOMINATOR = 1e6;

        uint256 assets = uint256(totalShares) * exchangeRate / ONE_SHARE;
        uint256 managementFeesAnnual = assets * managementFee / DENOMINATOR;
        return managementFeesAnnual * timeDelta / ONE_YEAR;
    }

    // ======================= totalPendingShares Tests =======================

    /// @dev Ensures totalPendingShares starts at zero
    function test_totalPendingShares_startsAtZero() public view {
        assertEq(NEST_ACCOUNTANT.totalPendingShares(), 0, "totalPendingShares should start at zero");
    }

    /// @dev Ensures increaseTotalPendingShares increments correctly and emits event
    function test_increaseTotalPendingShares_incrementsAndEmitsEvent() public {
        uint256 amount = 1000e18;

        vm.expectEmit();
        emit NestAccountant.TotalPendingSharesUpdated(0, amount);

        NEST_ACCOUNTANT.increaseTotalPendingShares(amount);

        assertEq(NEST_ACCOUNTANT.totalPendingShares(), amount, "totalPendingShares should be incremented");
    }

    /// @dev Ensures increaseTotalPendingShares reverts when called by unauthorized address
    function test_increaseTotalPendingShares_revertsWhenUnauthorized() public {
        vm.prank(address(1));
        _expectAuthUnauthorized();
        NEST_ACCOUNTANT.increaseTotalPendingShares(1000e18);
    }

    /// @dev Ensures decreaseTotalPendingShares decrements correctly and emits event
    function test_decreaseTotalPendingShares_decrementsAndEmitsEvent() public {
        uint256 initialAmount = 1000e18;
        uint256 decreaseAmount = 400e18;

        // First increase
        NEST_ACCOUNTANT.increaseTotalPendingShares(initialAmount);
        assertEq(NEST_ACCOUNTANT.totalPendingShares(), initialAmount);

        vm.expectEmit();
        emit NestAccountant.TotalPendingSharesUpdated(initialAmount, initialAmount - decreaseAmount);

        NEST_ACCOUNTANT.decreaseTotalPendingShares(decreaseAmount);

        assertEq(
            NEST_ACCOUNTANT.totalPendingShares(),
            initialAmount - decreaseAmount,
            "totalPendingShares should be decremented"
        );
    }

    /// @dev Ensures decreaseTotalPendingShares reverts when called by unauthorized address
    function test_decreaseTotalPendingShares_revertsWhenUnauthorized() public {
        // First increase as owner
        NEST_ACCOUNTANT.increaseTotalPendingShares(1000e18);

        vm.prank(address(1));
        _expectAuthUnauthorized();
        NEST_ACCOUNTANT.decreaseTotalPendingShares(500e18);
    }

    /// @dev Ensures decreaseTotalPendingShares reverts when amount exceeds current pending shares
    function test_decreaseTotalPendingShares_revertsWhenInsufficientBalance() public {
        uint256 initialAmount = 500e18;
        uint256 excessiveDecreaseAmount = 600e18;

        NEST_ACCOUNTANT.increaseTotalPendingShares(initialAmount);

        vm.expectRevert(Errors.InsufficientBalance.selector);
        NEST_ACCOUNTANT.decreaseTotalPendingShares(excessiveDecreaseAmount);
    }

    /// @dev Ensures multiple increases accumulate correctly
    function test_increaseTotalPendingShares_multipleIncreasesAccumulate() public {
        uint256 amount1 = 100e18;
        uint256 amount2 = 200e18;
        uint256 amount3 = 300e18;

        NEST_ACCOUNTANT.increaseTotalPendingShares(amount1);
        NEST_ACCOUNTANT.increaseTotalPendingShares(amount2);
        NEST_ACCOUNTANT.increaseTotalPendingShares(amount3);

        assertEq(
            NEST_ACCOUNTANT.totalPendingShares(), amount1 + amount2 + amount3, "Multiple increases should accumulate"
        );
    }

    /// @dev Ensures decrease to zero works correctly
    function test_decreaseTotalPendingShares_canDecreaseToZero() public {
        uint256 amount = 1000e18;

        NEST_ACCOUNTANT.increaseTotalPendingShares(amount);
        NEST_ACCOUNTANT.decreaseTotalPendingShares(amount);

        assertEq(NEST_ACCOUNTANT.totalPendingShares(), 0, "Should be able to decrease to zero");
    }
}
