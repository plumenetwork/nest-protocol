// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// utils
import {Test} from "forge-std/Test.sol";
import {Options, DefenderOptions, TxOverrides} from "@openzeppelin/foundry-upgrades/src/Options.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";

// contracts
import {Constants} from "script/Constants.sol";
import {MockNestAccountant, NestHubAccountant} from "test/mock/MockNestAccountant.sol";
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

    /// @dev Helper to deploy a fresh NestHubAccountant implementation.
    function _deployNestAccountantImplementation() internal returns (address) {
        return address(new MockNestAccountant(USDC, NALPHA));
    }

    /// @dev Helper to deploy a fresh NestHubAccountant proxy with configurable initialize bounds/delay
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
                NestHubAccountant.initialize,
                (
                    _totalSharesLastUpdate,
                    address(this),
                    uint96(1e6),
                    _allowedExchangeRateChangeUpper,
                    _allowedExchangeRateChangeLower,
                    _minimumUpdateDelayInSeconds,
                    uint32(10_000),
                    uint32(0),
                    uint32(0),
                    uint32(0),
                    uint32(0),
                    uint32(0),
                    address(this)
                )
            )
        );
        return address(_proxy);
    }

    constructor() {
        vm.createSelectFork("ethereum");

        // deploy NestHubAccountant
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
                    uint32(10_000), // managementFee
                    uint32(0), // performanceFee
                    uint32(0), // hurdleRate
                    uint32(0), // holdbackRate
                    uint32(0), // crystallizationWindow
                    uint32(0), // epochsPerWindow
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
            __totalSharesLastUpdate,
            address(this),
            1000000,
            1_000_003,
            999_997,
            3600,
            10_000,
            0,
            0,
            0,
            0,
            0,
            address(this)
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
        emit NestHubAccountant.Paused();

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
        emit NestHubAccountant.Unpaused();

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
        NestHubAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint32 initialDelay = initialState.minimumUpdateDelayInSeconds;
        uint32 newDelay = 7200; // 2 hours

        vm.expectEmit();
        emit NestHubAccountant.DelayInSecondsUpdated(initialDelay, newDelay);

        NEST_ACCOUNTANT.updateDelay(newDelay);

        NestHubAccountant.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
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
        NestHubAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint32 initialBound = initialState.allowedExchangeRateChangeUpper;
        uint32 newBound = 1015000; // 1.5% increase allowed

        NEST_ACCOUNTANT.updateUpper(newBound);

        NestHubAccountant.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
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
        NestHubAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint32 initialBound = initialState.allowedExchangeRateChangeLower;
        uint32 newBound = 990000; // 0.1% decrease allowed

        vm.expectEmit();
        emit NestHubAccountant.LowerBoundUpdated(initialBound, newBound);

        NEST_ACCOUNTANT.updateLower(newBound);

        NestHubAccountant.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
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
        NestHubAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint32 initialFee = initialState.managementFee;
        uint32 newFee = 20000; // 2% annual fee

        vm.expectEmit();
        emit NestHubAccountant.ManagementFeeUpdated(initialFee, newFee);

        NEST_ACCOUNTANT.updateManagementFee(newFee, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(updatedState.managementFee, newFee);
    }

    /// @dev Ensures updateManagementFee accrues old-fee fees and then the new fee applies from the next updateExchangeRate
    function test_updateManagementFee_newFeeAppliesFromNextUpdate() public {
        // Deploy accountant with wider bounds — this test exercises fee accrual, not bounds checking
        address _impl = _deployNestAccountantImplementation();
        address _proxy =
            _deployNestAccountantProxyWithInitParams(_impl, IERC20(NALPHA).totalSupply(), 1_100_000, 900_000, 3600);
        MockNestAccountant accountant = MockNestAccountant(_proxy);

        NestHubAccountant.AccountantState memory initialState = accountant.getAccountantState();
        uint32 newFee = 20000; // 2% annual fee

        // Use lastUpdateTimestamp as base (equals block.timestamp at init) to avoid optimizer
        // re-evaluating block.timestamp after vm.warp
        uint256 t0 = initialState.lastUpdateTimestamp;

        // Warp so there is elapsed time for the old fee to accrue
        vm.warp(t0 + 5 days);

        accountant.updateManagementFee(newFee, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory stateAfterFeeUpdate = accountant.getAccountantState();
        assertEq(stateAfterFeeUpdate.managementFee, newFee, "Management fee should be updated");
        // Old fee should have accrued during the elapsed period
        assertGt(stateAfterFeeUpdate.feesOwedInBase, 0, "Old fee should accrue on management fee update");
        // Timestamp and shares checkpoint should be refreshed
        assertEq(stateAfterFeeUpdate.lastUpdateTimestamp, uint64(t0 + 5 days), "Timestamp should refresh");

        uint128 feesAfterFeeChange = stateAfterFeeUpdate.feesOwedInBase;

        // Now update exchange rate — only the new fee applies from here
        vm.warp(t0 + 10 days);

        uint96 grossRate = initialState.exchangeRate; // same rate
        accountant.updateExchangeRate(grossRate, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory finalState = accountant.getAccountantState();
        // Net rate should be less than gross rate due to management fee
        assertLt(finalState.exchangeRate, grossRate, "Net rate should be less than gross rate");
        assertGt(finalState.feesOwedInBase, feesAfterFeeChange, "Additional fees should accrue on exchange rate update");
    }

    /// @dev Ensures `updateManagementFee` reverts when fee exceeds cap (20%)
    function test_updateManagementFee_revertsWhenFeeExceedsCap() public {
        uint32 excessiveFee = 200001; // Just over 20%
        uint128 _supply = uint128(IERC20(NALPHA).totalSupply());
        vm.expectRevert(Errors.ManagementFeeTooLarge.selector);
        NEST_ACCOUNTANT.updateManagementFee(excessiveFee, _supply);
    }

    /// @dev Ensures `updateManagementFee` reverts when called by unauthorized address
    function test_updateManagementFee_revertsWhenUnauthorized() public {
        uint128 _supply = uint128(IERC20(NALPHA).totalSupply());
        vm.prank(address(1));
        _expectAuthUnauthorized();
        NEST_ACCOUNTANT.updateManagementFee(15000, _supply);
    }

    // ======================= updatePayoutAddress Tests =======================

    /// @dev Ensures `updatePayoutAddress` updates the payout address correctly
    function test_updatePayoutAddress_updatesAddressAndEmitsEvent() public {
        address newPayoutAddress = address(0x1234567890123456789012345678901234567890);

        vm.expectEmit();
        emit NestHubAccountant.PayoutAddressUpdated(address(this), newPayoutAddress);

        NEST_ACCOUNTANT.updatePayoutAddress(newPayoutAddress);

        NestHubAccountant.AccountantState memory updatedState = NEST_ACCOUNTANT.getAccountantState();
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
        emit NestHubAccountant.RateProviderUpdated(testAsset, true, testProvider);

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
        NestHubAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint256 initialExchangeRate = initialState.exchangeRate;
        uint64 minimumDelay = initialState.minimumUpdateDelayInSeconds;
        uint128 _supply = uint128(IERC20(NALPHA).totalSupply());

        vm.warp(block.timestamp + minimumDelay + 1000);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialExchangeRate + 20), _supply);

        NestHubAccountant.AccountantState memory stateAfterFirst = NEST_ACCOUNTANT.getAccountantState();
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
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialExchangeRate - 30), _supply);

        NestHubAccountant.AccountantState memory stateAfterSecond = NEST_ACCOUNTANT.getAccountantState();
        assertEq(stateAfterSecond.feesOwedInBase, initialState.feesOwedInBase, "Repeated invalid updates should revert");
    }

    /// @dev Ensures pause state does not bypass minimum delay checks.
    function test_updateExchangeRate_pausedDoesNotBypassMinimumDelay() public {
        NestHubAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        _pauseContract();
        NestHubAccountant.AccountantState memory pausedState = NEST_ACCOUNTANT.getAccountantState();
        uint256 initialExchangeRate = pausedState.exchangeRate;

        uint128 _supply = uint128(IERC20(NALPHA).totalSupply());
        vm.warp(block.timestamp + 50);
        vm.expectRevert(Errors.MinimumUpdateDelayNotPassed.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialExchangeRate), _supply);

        NestHubAccountant.AccountantState memory stateAfterAttempt = NEST_ACCOUNTANT.getAccountantState();
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
        NestHubAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint256 initialRate = initialState.exchangeRate;
        uint64 minimumDelay = initialState.minimumUpdateDelayInSeconds;
        uint128 _supply = uint128(IERC20(NALPHA).totalSupply());

        vm.warp(block.timestamp + minimumDelay + 1000);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialRate + 50), _supply);

        assertEq(
            NEST_ACCOUNTANT.getAccountantState().exchangeRate,
            initialRate,
            "Exchange rate should not change on invalid update"
        );
    }

    /// @dev Ensures invalid updates do not advance total shares or timestamps.
    function test_updateExchangeRate_invalidUpdateDoesNotAdvanceTotalSharesAndTimestamp() public {
        NestHubAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint64 initialTimestamp = initialState.lastUpdateTimestamp;
        uint128 _supply = uint128(IERC20(NALPHA).totalSupply());

        vm.warp(block.timestamp + initialState.minimumUpdateDelayInSeconds + 2000);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialState.exchangeRate + 100), _supply);

        NestHubAccountant.AccountantState memory stateAfterInvalid = NEST_ACCOUNTANT.getAccountantState();
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
        NestHubAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(initialState.isPaused, false, "Contract should start unpaused");
        uint64 minimumDelay = initialState.minimumUpdateDelayInSeconds;
        uint128 _supply = uint128(IERC20(NALPHA).totalSupply());

        uint256 invalidRate = initialState.exchangeRate + 100;
        vm.warp(block.timestamp + minimumDelay + 1000);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(invalidRate), _supply);

        NestHubAccountant.AccountantState memory stateAfterUpdate = NEST_ACCOUNTANT.getAccountantState();
        assertFalse(stateAfterUpdate.isPaused, "Invalid update should revert instead of pausing");
    }

    /// @dev Ensures that invalid updates due to rate below lower bound revert while unpaused.
    function test_updateExchangeRate_invalidRateLowerBoundRevertsWhenUnpaused() public {
        NestHubAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(initialState.isPaused, false, "Contract should start unpaused");
        uint64 minimumDelay = initialState.minimumUpdateDelayInSeconds;
        uint128 _supply = uint128(IERC20(NALPHA).totalSupply());

        uint256 invalidRate = initialState.exchangeRate - 100;
        vm.warp(block.timestamp + minimumDelay + 1000);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(invalidRate), _supply);

        NestHubAccountant.AccountantState memory stateAfterUpdate = NEST_ACCOUNTANT.getAccountantState();
        assertFalse(stateAfterUpdate.isPaused, "Invalid update should revert instead of pausing");
    }

    /// @dev Ensures that invalid updates due to insufficient time delay revert while unpaused.
    function test_updateExchangeRate_invalidTimingRevertsWhenUnpaused() public {
        NestHubAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(initialState.isPaused, false, "Contract should start unpaused");
        uint128 _supply = uint128(IERC20(NALPHA).totalSupply());

        uint256 timeTooEarly = initialState.minimumUpdateDelayInSeconds / 2;
        vm.warp(block.timestamp + timeTooEarly);
        vm.expectRevert(Errors.MinimumUpdateDelayNotPassed.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialState.exchangeRate), _supply);

        NestHubAccountant.AccountantState memory stateAfterUpdate = NEST_ACCOUNTANT.getAccountantState();
        assertFalse(stateAfterUpdate.isPaused, "Invalid update should revert instead of pausing");
    }

    /// @dev Ensures pause state does not bypass exchange-rate bounds checks.
    function test_updateExchangeRate_pausedDoesNotBypassBounds() public {
        NestHubAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint256 initialRate = initialState.exchangeRate;
        uint64 minimumDelay = initialState.minimumUpdateDelayInSeconds;

        vm.warp(block.timestamp + minimumDelay + 100);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialRate), uint128(IERC20(NALPHA).totalSupply()));

        _pauseContract();
        NestHubAccountant.AccountantState memory pausedState = NEST_ACCOUNTANT.getAccountantState();
        uint64 pauseTimestamp = pausedState.lastUpdateTimestamp;
        uint96 outOfBoundsRate = uint96(initialRate + 50000);
        uint128 _supply = uint128(IERC20(NALPHA).totalSupply());

        vm.warp(pauseTimestamp + minimumDelay + 1);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateExchangeRate(outOfBoundsRate, _supply);

        NestHubAccountant.AccountantState memory afterBypass = NEST_ACCOUNTANT.getAccountantState();
        assertEq(afterBypass.lastUpdateTimestamp, pauseTimestamp, "Timestamp should not change on reverted update");
        assertEq(afterBypass.exchangeRate, pausedState.exchangeRate, "Rate should not change on reverted update");
        assertEq(afterBypass.feesOwedInBase, pausedState.feesOwedInBase, "Fees should not accrue on reverted update");
        assertTrue(afterBypass.isPaused, "Should still be paused");
    }

    /// @dev Helper function to calculate expected management fee discount per share (gross rate model)
    function calculateExpectedMgmtDiscount(uint256 grossRate, uint32 managementFee, uint256 timeDelta)
        internal
        pure
        returns (uint256)
    {
        uint256 ONE_YEAR = 365 days;
        uint256 DENOMINATOR = 1e6;
        return grossRate * managementFee * timeDelta / (DENOMINATOR * ONE_YEAR);
    }

    /// @dev Helper function to calculate expected fee base amount from rate spread
    function calculateExpectedFeeBase(uint256 rateSpread, uint256 totalShares) internal view returns (uint256) {
        uint256 ONE_SHARE = 10 ** IERC20Metadata(NALPHA).decimals();
        return rateSpread * totalShares / ONE_SHARE;
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
        emit NestHubAccountant.TotalPendingSharesUpdated(0, amount);

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
        emit NestHubAccountant.TotalPendingSharesUpdated(initialAmount, initialAmount - decreaseAmount);

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

    // ======================= Gross Rate / Net Rate Model Tests =======================

    /// @dev Ensures updateExchangeRate stores a net rate lower than the gross rate when managementFee > 0
    function test_updateExchangeRate_grossRateProducesLowerNetRate() public {
        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();
        uint96 grossRate = state.exchangeRate; // 1_000_000

        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(grossRate, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory newState = NEST_ACCOUNTANT.getAccountantState();
        assertLt(newState.exchangeRate, grossRate, "Net rate should be less than gross rate");
    }

    /// @dev Ensures feesOwedInBase is correctly computed from rate spread
    function test_updateExchangeRate_feesOwedMatchesRateSpread() public {
        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();
        uint96 grossRate = state.exchangeRate;
        uint256 timeDelta = state.minimumUpdateDelayInSeconds + 1;

        vm.warp(block.timestamp + timeDelta);
        NEST_ACCOUNTANT.updateExchangeRate(grossRate, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory newState = NEST_ACCOUNTANT.getAccountantState();
        uint256 rateSpread = uint256(grossRate) - uint256(newState.exchangeRate);
        uint256 totalShares = IERC20(NALPHA).totalSupply();
        uint256 expectedFeeBase = calculateExpectedFeeBase(rateSpread, totalShares);
        assertEq(newState.feesOwedInBase, expectedFeeBase, "feesOwedInBase should match rate spread * totalShares");
    }

    /// @dev Ensures zero management fee passes gross rate through unchanged
    function test_updateExchangeRate_zeroMgmtFeePassesGrossRateThrough() public {
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();
        uint96 grossRate = state.exchangeRate;

        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(grossRate, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory newState = NEST_ACCOUNTANT.getAccountantState();
        assertEq(newState.exchangeRate, grossRate, "Net rate should equal gross rate when mgmt fee is 0");
        assertEq(newState.feesOwedInBase, 0, "No fees when mgmt fee is 0");
    }

    /// @dev Regression: net rate must stay near the prior update's level when fees are unclaimed and NAV is flat.
    ///      Without the fix the second update would bounce back toward the gross rate because
    ///      _accrueManagementFees was called with the raw gross that still includes feesOwedInBase.
    function test_updateExchangeRate_netRateStaysStableWhenFeesUnclaimedAndNAVFlat() public {
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();
        uint96 grossRate = 1_001_000;

        // Update 1: accrue management fees → feesOwedInBase > 0
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(grossRate, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterUpdate1 = NEST_ACCOUNTANT.getAccountantState();
        assertGt(afterUpdate1.feesOwedInBase, 0, "feesOwedInBase should be positive after first update");

        // Update 2: same gross (pool flat, unclaimed fees still inside)
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(grossRate, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterUpdate2 = NEST_ACCOUNTANT.getAccountantState();

        // Net rate must stay well below gross (fee liability deducted from adjustedGross)
        assertLt(afterUpdate2.exchangeRate, grossRate, "Net rate must be below gross when fees are unclaimed");
        // Net rate must be near update-1's rate (only offset by the tiny new mgmt fee)
        // Using 1000 micro-USDC tolerance since the new mgmt fee is << feesOwedInBase/share
        assertApproxEqAbs(
            afterUpdate2.exchangeRate,
            afterUpdate1.exchangeRate,
            1000,
            "Net rate should stay near prior update rate, not bounce back toward gross"
        );
        // feesOwedInBase accumulates monotonically
        assertGt(afterUpdate2.feesOwedInBase, afterUpdate1.feesOwedInBase, "Fees should accumulate across updates");
    }

    /// @dev The adjusted-gross approach deducts the holdback reserve from the gross before comparing to HWM.
    ///      When gross is flat (equal to the prior update), adjustedGross = gross − reserve/share < HWM,
    ///      which triggers clawback and returns the full reserve to investors.
    ///      Without the fix no deduction occurs, grossRate == HWM, no clawback fires, and the reserve
    ///      remains locked even though investor value hasn't genuinely grown above the HWM.
    /// @dev Clawback fires on genuine investment drawdown (raw gross drops below HWM), not on flat NAV.
    ///      With approach C, HWM tracks raw gross, so submitting the same gross twice does NOT trigger
    ///      clawback — only an actual pool NAV decline below HWM does.
    function test_updateExchangeRate_clawbackOnActualDrawdown() public {
        NEST_ACCOUNTANT.updateUpper(1_200_000);
        NEST_ACCOUNTANT.updateLower(800_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000); // 20%
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_000); // 100% holdback
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // Update 1: gain → reserve = 20_000/share, HWM = 1_100_000 (raw gross)
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_100_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveAfterUpdate1,,) = NEST_ACCOUNTANT.getReserveState();
        assertGt(reserveAfterUpdate1, 0, "Reserve should be positive after gain");

        // Sanity: submitting the same gross again does NOT clawback (HWM == raw gross, no drawdown).
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_100_000, uint128(IERC20(NALPHA).totalSupply()));
        (uint128 reserveAfterFlat,,) = NEST_ACCOUNTANT.getReserveState();
        assertEq(reserveAfterFlat, reserveAfterUpdate1, "Flat NAV should not reduce reserve");

        // Actual drawdown: gross drops to 1_090_000 < HWM 1_100_000 → partial clawback.
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_090_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveAfterDrawdown,,) = NEST_ACCOUNTANT.getReserveState();

        // Shortfall = (clawbackRef − gross) per share, capped at reserve per share → partial clawback
        assertLt(reserveAfterDrawdown, reserveAfterUpdate1, "Reserve should decrease on drawdown");
        assertGt(reserveAfterDrawdown, 0, "Reserve should not be fully consumed on partial drawdown");
        // Clawback adds the returned reserve per share on top of the gross rate.
        // net = gross + clawbackRate
        uint256 clawbackRate = uint256(reserveAfterUpdate1 - reserveAfterDrawdown) * 1e6 / IERC20(NALPHA).totalSupply();
        assertApproxEqAbs(
            NEST_ACCOUNTANT.getAccountantState().exchangeRate,
            1_090_000 + clawbackRate,
            2,
            "Net rate should reflect partial clawback above gross"
        );
    }

    /// @dev Sanity: when pre-accrual liability is zero the fix is a no-op and existing behaviour is preserved.
    function test_updateExchangeRate_zeroLiabilityIsNoOp() public {
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // Update 1: zero management fee → no fees accrue
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(state.exchangeRate, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterUpdate1 = NEST_ACCOUNTANT.getAccountantState();
        assertEq(afterUpdate1.feesOwedInBase, 0, "feesOwedInBase must be zero");

        // Update 2: preAccrualLiability = 0 → adjustedGross = grossRate → net == gross
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(state.exchangeRate, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterUpdate2 = NEST_ACCOUNTANT.getAccountantState();
        assertEq(afterUpdate2.exchangeRate, state.exchangeRate, "Net rate should equal gross when no liability exists");
    }

    // ======================= Initialize HWM Tests =======================

    /// @dev Ensures initialize sets HWM to starting exchange rate
    function test_initialize_setsHighWaterMark() public view {
        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();
        assertEq(state.highWaterMark, state.exchangeRate, "HWM should be set to starting exchange rate");
    }

    // ======================= Performance Fee Admin Tests =======================

    /// @dev Ensures updatePerformanceFee sets fee and emits event
    function test_updatePerformanceFee_setsFeeAndEmitsEvent() public {
        uint32 newFee = 200_000; // 20%
        vm.expectEmit();
        emit NestHubAccountant.PerformanceFeeUpdated(0, newFee);
        NEST_ACCOUNTANT.updatePerformanceFee(newFee);

        assertEq(NEST_ACCOUNTANT.getPerformanceFeeConfig().performanceFee, newFee);
    }

    /// @dev Ensures updatePerformanceFee reverts when fee exceeds cap
    function test_updatePerformanceFee_revertsWhenExceedsCap() public {
        vm.expectRevert(Errors.PerformanceFeeTooLarge.selector);
        NEST_ACCOUNTANT.updatePerformanceFee(500_001);
    }

    /// @dev Enables perf fee after zero-fee growth; HWM must reset to the current gross checkpoint
    function test_updatePerformanceFee_resetsHWMOnEnable() public {
        // Disable management fee for clarity
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // Grow exchangeRate while performanceFee == 0
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory grown = NEST_ACCOUNTANT.getAccountantState();
        assertEq(grown.exchangeRate, 1_050_000, "Rate should reflect zero-fee growth");

        // Enable a nonzero perf fee
        NEST_ACCOUNTANT.updatePerformanceFee(200_000); // 20%

        NestHubAccountant.AccountantState memory afterEnable = NEST_ACCOUNTANT.getAccountantState();
        assertEq(afterEnable.highWaterMark, 1_050_000, "HWM should reset to current gross rate on enable");
    }

    /// @dev After HWM reset on enable, submitting the same gross rate must not charge perf fees
    function test_updatePerformanceFee_noRetroactiveTaxation() public {
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // Grow while perf fee is off
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));

        // Enable perf fee — HWM resets to 1_050_000
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        uint128 feesBeforeUpdate = NEST_ACCOUNTANT.getAccountantState().feesOwedInBase;

        // Submit the same gross rate again after delay — no gain above HWM
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterUpdate = NEST_ACCOUNTANT.getAccountantState();
        assertEq(afterUpdate.exchangeRate, 1_050_000, "Rate should not drop from perf fee");
        assertEq(afterUpdate.feesOwedInBase, feesBeforeUpdate, "No perf fees should accrue at same rate as HWM");
    }

    /// @dev Disable then re-enable perf fee: HWM resets again on second 0->non-zero transition
    function test_updatePerformanceFee_reEnableResetsHWM() public {
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // First enable
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().highWaterMark,
            state.exchangeRate,
            "HWM should be at starting rate after first enable"
        );

        // Grow, then disable
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updatePerformanceFee(0); // disable

        // Grow more while disabled
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_080_000, uint128(IERC20(NALPHA).totalSupply()));

        // Re-enable — HWM should reset to the last submitted gross rate (1_080_000)
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);

        NestHubAccountant.AccountantState memory afterReEnable = NEST_ACCOUNTANT.getAccountantState();
        // HWM now seeds from lastPreFeeRate (raw gross) so that it stays in gross terms,
        // consistent with how _accruePerformanceFees stores HWM = _grossRate on gain.
        assertEq(afterReEnable.highWaterMark, 1_080_000, "HWM should reset to lastPreFeeRate on re-enable");
    }

    /// @dev Changing fee from >0 to >0 must NOT reset HWM
    function test_updatePerformanceFee_noResetOnFeeChange() public {
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // Enable and grow to push HWM up
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));

        uint96 hwmAfterGain = NEST_ACCOUNTANT.getAccountantState().highWaterMark;
        assertEq(hwmAfterGain, 1_050_000, "HWM should track the gross rate");

        // Change fee from 20% to 10% — should NOT reset HWM
        NEST_ACCOUNTANT.updatePerformanceFee(100_000);

        assertEq(NEST_ACCOUNTANT.getAccountantState().highWaterMark, hwmAfterGain, "HWM must not reset on >0 to >0");
    }

    /// @dev Ensures updatePerformanceFee reverts when unauthorized
    function test_updatePerformanceFee_revertsWhenUnauthorized() public {
        vm.prank(address(1));
        _expectAuthUnauthorized();
        NEST_ACCOUNTANT.updatePerformanceFee(100_000);
    }

    // ======================= Reset HWM Tests =======================

    /// @dev Ensures resetHighWaterMark updates HWM and emits event
    function test_resetHighWaterMark_updatesAndEmits() public {
        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();
        uint96 newHWM = 1_500_000;

        vm.expectEmit();
        emit NestHubAccountant.HighWaterMarkUpdated(state.highWaterMark, newHWM);
        NEST_ACCOUNTANT.resetHighWaterMark(newHWM);

        assertEq(NEST_ACCOUNTANT.getAccountantState().highWaterMark, newHWM);
    }

    /// @dev Ensures resetHighWaterMark reverts when zero
    function test_resetHighWaterMark_revertsWhenZero() public {
        vm.expectRevert(Errors.InvalidRate.selector);
        NEST_ACCOUNTANT.resetHighWaterMark(0);
    }

    /// @dev Ensures resetHighWaterMark reverts when unauthorized
    function test_resetHighWaterMark_revertsWhenUnauthorized() public {
        vm.prank(address(1));
        _expectAuthUnauthorized();
        NEST_ACCOUNTANT.resetHighWaterMark(1_000_000);
    }

    // ======================= Hurdle Rate Admin Tests =======================

    /// @dev Ensures updateHurdleRate sets rate and emits event
    function test_updateHurdleRate_setsRateAndEmitsEvent() public {
        uint32 newRate = 50_000; // 5%
        vm.expectEmit();
        emit NestHubAccountant.HurdleRateUpdated(0, newRate);
        NEST_ACCOUNTANT.updateHurdleRate(newRate);

        assertEq(NEST_ACCOUNTANT.getPerformanceFeeConfig().hurdleRate, newRate);
    }

    /// @dev Ensures updateHurdleRate reverts when exceeds cap
    function test_updateHurdleRate_revertsWhenExceedsCap() public {
        vm.expectRevert(Errors.HurdleRateTooLarge.selector);
        NEST_ACCOUNTANT.updateHurdleRate(300_001);
    }

    // ======================= Holdback Admin Tests =======================

    /// @dev Ensures updateHoldbackRate sets rate and emits event
    function test_updateHoldbackRate_setsRateAndEmitsEvent() public {
        uint32 newRate = 500_000; // 50%
        vm.expectEmit();
        emit NestHubAccountant.HoldbackRateUpdated(0, newRate);
        NEST_ACCOUNTANT.updateHoldbackRate(newRate);

        assertEq(NEST_ACCOUNTANT.getPerformanceFeeConfig().holdbackRate, newRate);
    }

    /// @dev Ensures updateHoldbackRate reverts when exceeds 100%
    function test_updateHoldbackRate_revertsWhenExceedsDenominator() public {
        vm.expectRevert(Errors.HoldbackRateTooLarge.selector);
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_001);
    }

    // ======================= Crystallization Window Admin Tests =======================

    /// @dev Ensures updateCrystallizationWindow sets window and emits event
    function test_updateCrystallizationWindow_setsWindowAndEmitsEvent() public {
        uint32 newWindow = 90 days;
        vm.expectEmit();
        emit NestHubAccountant.CrystallizationWindowUpdated(0, newWindow);
        NEST_ACCOUNTANT.updateCrystallizationWindow(newWindow);

        assertEq(NEST_ACCOUNTANT.getPerformanceFeeConfig().crystallizationWindow, newWindow);
    }

    /// @dev Ensures updateCrystallizationWindow reverts when exceeds cap
    function test_updateCrystallizationWindow_revertsWhenExceedsCap() public {
        vm.expectRevert(Errors.CrystallizationWindowTooLarge.selector);
        NEST_ACCOUNTANT.updateCrystallizationWindow(uint32(366 days));
    }

    // ======================= Performance Fee with HWM Tests =======================

    /// @dev Ensures performance fee is charged on gains above HWM
    function test_perfFee_chargedOnGainsAboveHWM() public {
        // Widen bounds for performance fee testing
        NEST_ACCOUNTANT.updateUpper(1_100_000); // 10% upper bound
        NEST_ACCOUNTANT.updateLower(900_000); // 10% lower bound

        NEST_ACCOUNTANT.updatePerformanceFee(200_000); // 20%
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply())); // disable mgmt fee for clarity

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // Gross rate with 5% gain
        uint96 grossRate = 1_050_000;
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(grossRate, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory newState = NEST_ACCOUNTANT.getAccountantState();
        // gain = 1_050_000 - 1_000_000 = 50_000
        // perfFee = 50_000 * 200_000 / 1_000_000 = 10_000
        // netRate = 1_050_000 - 10_000 = 1_040_000 (±1 from round-trip mulDivDown)
        assertApproxEqAbs(newState.exchangeRate, 1_040_000, 1, "Net rate should reflect 20% perf fee on 50k gain");
        assertEq(newState.highWaterMark, 1_050_000, "HWM should update to the gross rate");
        assertGt(newState.feesOwedInBase, 0, "Fees should be owed");
    }

    /// @dev Ensures no performance fee when rate is below HWM
    function test_perfFee_notChargedBelowHWM() public {
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // First: gain above HWM to set HWM to 1_050_000
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterGain = NEST_ACCOUNTANT.getAccountantState();
        uint96 hwmAfterGain = afterGain.highWaterMark; // 1_050_000
        uint256 feesAfterGain = afterGain.feesOwedInBase;

        // Now: rate below HWM — no performance fee
        vm.warp(block.timestamp + afterGain.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(hwmAfterGain - 10_000), uint128(IERC20(NALPHA).totalSupply())); // 1_040_000

        NestHubAccountant.AccountantState memory afterDrop = NEST_ACCOUNTANT.getAccountantState();
        // No new perf fee (below HWM) and mgmt fee = 0, so net = gross.
        // This contract does not deduct pre-existing feesOwedInBase from the rate.
        assertEq(
            afterDrop.exchangeRate, uint96(hwmAfterGain - 10_000), "Net rate equals gross when no new fees below HWM"
        );
        assertEq(afterDrop.highWaterMark, hwmAfterGain, "HWM should not decrease on drawdown");
        // feesOwedInBase should not increase (no fees when below HWM and mgmt fee is 0)
        assertEq(afterDrop.feesOwedInBase, feesAfterGain, "No new fees below HWM");
    }

    /// @dev Ensures HWM does not decrease on drawdowns
    function test_perfFee_hwmDoesNotDecrease() public {
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // Push HWM up
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));
        uint96 hwmPeak = NEST_ACCOUNTANT.getAccountantState().highWaterMark;

        // Drawdown
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_000_000, uint128(IERC20(NALPHA).totalSupply()));
        assertEq(NEST_ACCOUNTANT.getAccountantState().highWaterMark, hwmPeak, "HWM must not decrease");

        // Recovery but still below HWM
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_030_000, uint128(IERC20(NALPHA).totalSupply()));
        assertEq(NEST_ACCOUNTANT.getAccountantState().highWaterMark, hwmPeak, "HWM still at peak during recovery");
    }

    /// @dev Ensures combined management + performance fees are correctly deducted
    function test_perfFee_combinedWithManagementFee() public {
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000); // 20%
        // managementFee stays at 10_000 (1%)

        // Use 30 days so the management fee is large enough to be visible alongside perf fee
        uint96 grossRate = 1_050_000;
        vm.warp(block.timestamp + 30 days);
        NEST_ACCOUNTANT.updateExchangeRate(grossRate, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory newState = NEST_ACCOUNTANT.getAccountantState();
        // Net rate should be lower than gross rate (both mgmt + perf fees deducted)
        assertLt(newState.exchangeRate, grossRate, "Net rate should have both fees deducted");
        // Net rate should be lower than 1_040_000 (perf-fee-only result) due to mgmt fee
        assertLt(newState.exchangeRate, 1_040_000, "Should be lower than perf-fee-only case due to mgmt fee");
    }

    // ======================= Hurdle Rate Tests =======================

    /// @dev Ensures hurdle rate prevents perf fee when gain does not exceed hurdle
    function test_hurdleRate_preventsPerfFeeWhenBelowHurdle() public {
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000); // 20%
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateHurdleRate(100_000); // 10% annualized hurdle

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();
        uint96 hwmBefore = state.highWaterMark;
        // Wait 1 year so hurdle-adjusted HWM = 1_000_000 + 1_000_000 * 100_000 * 365days / (1e6 * 365days) = 1_100_000
        uint256 oneYear = 365 days;
        vm.warp(block.timestamp + oneYear);

        // Gross rate = 1_050_000, below the hurdle-adjusted HWM of 1_100_000
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory newState = NEST_ACCOUNTANT.getAccountantState();
        // No perf fee (below hurdle), no mgmt fee (set to 0)
        assertEq(newState.exchangeRate, 1_050_000, "Net rate should equal gross rate when below hurdle");
        assertEq(newState.highWaterMark, hwmBefore, "HWM should not change when below hurdle");
    }

    /// @dev Ensures hurdle rate allows perf fee only on excess above hurdle
    function test_hurdleRate_perfFeeOnlyOnExcessAboveHurdle() public {
        NEST_ACCOUNTANT.updateUpper(1_200_000);
        NEST_ACCOUNTANT.updateLower(800_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateHurdleRate(50_000); // 5% annualized

        // Wait 1 year: effectiveHWM = 1_000_000 + 1_000_000 * 50_000 / 1_000_000 = 1_050_000
        vm.warp(block.timestamp + 365 days);

        // Gross rate = 1_100_000, above hurdle-adjusted HWM of 1_050_000
        NEST_ACCOUNTANT.updateExchangeRate(1_100_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory newState = NEST_ACCOUNTANT.getAccountantState();
        // gain above hurdle = 1_100_000 - 1_050_000 = 50_000
        // perfFee = 50_000 * 200_000 / 1_000_000 = 10_000
        // netRate = 1_100_000 - 10_000 = 1_090_000 (±1 from round-trip mulDivDown)
        assertApproxEqAbs(newState.exchangeRate, 1_090_000, 1, "Perf fee should only apply to excess above hurdle");
        assertEq(newState.highWaterMark, 1_100_000, "HWM should update to the gross rate");
    }

    // ======================= Holdback / Clawback Reserve Tests =======================

    /// @dev Ensures holdback splits performance fee between immediate and reserve
    function test_holdback_splitsPerformanceFee() public {
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateHoldbackRate(500_000); // 50% holdback
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days); // 90 day window

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory newState = NEST_ACCOUNTANT.getAccountantState();
        (uint128 totalReserve,,) = NEST_ACCOUNTANT.getReserveState();

        // gain = 50_000, perfFee = 10_000 per share, netRate = 1_040_000 (±1 from round-trip mulDivDown)
        assertApproxEqAbs(newState.exchangeRate, 1_040_000, 1, "Net rate should reflect full perf fee deduction");
        assertGt(totalReserve, 0, "Reserve should have holdback amount");
        // feesOwedInBase should be less than total fee (holdback portion in reserve)
        assertGt(newState.feesOwedInBase, 0, "Immediate fees should be owed");
    }

    /// @dev Ensures reserve crystallizes after window passes
    function test_holdback_crystallizesAfterWindow() public {
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_000); // 100% holdback (all to reserve)
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // Generate holdback
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterGain = NEST_ACCOUNTANT.getAccountantState();
        (uint128 reserveBefore,,) = NEST_ACCOUNTANT.getReserveState();
        assertGt(reserveBefore, 0, "Reserve should have holdback");
        // With 100% holdback, no immediate fees
        assertEq(afterGain.feesOwedInBase, 0, "No immediate fees with 100% holdback");

        // Wait for crystallization window to pass + update at HWM (no drawdown, so no clawback)
        vm.warp(block.timestamp + 91 days);
        NestHubAccountant.AccountantState memory stateBeforeCrystal = NEST_ACCOUNTANT.getAccountantState();
        NEST_ACCOUNTANT.updateExchangeRate(stateBeforeCrystal.highWaterMark, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterCrystal = NEST_ACCOUNTANT.getAccountantState();
        (uint128 reserveAfter,,) = NEST_ACCOUNTANT.getReserveState();
        assertEq(reserveAfter, 0, "Reserve should be zero after crystallization");
        assertGt(afterCrystal.feesOwedInBase, 0, "Crystallized reserve should move to feesOwedInBase");
    }

    /// @dev Ensures clawback reduces reserve on drawdown and bumps net rate
    function test_holdback_clawbackOnDrawdown() public {
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_000); // 100% holdback
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // Generate holdback via gain
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveBeforeClawback,,) = NEST_ACCOUNTANT.getReserveState();
        assertGt(reserveBeforeClawback, 0, "Reserve should exist before clawback");

        // Drawdown below HWM — triggers clawback
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_000_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterDrop = NEST_ACCOUNTANT.getAccountantState();
        (uint128 reserveAfterClawback,,) = NEST_ACCOUNTANT.getReserveState();

        // Reserve should decrease; a small residual may remain due to per-share rounding
        // protection (finding #6: only consume the representable portion so unrepresentable
        // remainder is not burned from the reserve).
        assertLt(reserveAfterClawback, reserveBeforeClawback, "Reserve should decrease on clawback");

        uint256 totalShares = IERC20(NALPHA).totalSupply();
        uint256 oneShare = 10 ** IERC20Metadata(NALPHA).decimals();
        // The residual is bounded by the per-share rounding: at most (totalShares - 1) wei.
        assertLe(reserveAfterClawback, totalShares / oneShare, "Residual should be at most rounding dust");

        // Clawback adds the returned reserve per share on top of the gross rate.
        // net = gross + clawbackPerShare
        uint256 clawbackPerShare = uint256(reserveBeforeClawback - reserveAfterClawback) * oneShare / totalShares;
        assertApproxEqAbs(
            afterDrop.exchangeRate, 1_000_000 + clawbackPerShare, 1, "Net rate equals gross plus clawback per share"
        );
    }

    /// @dev Ensures disabling performance fees does not disable reserve clawback on later drawdowns
    function test_holdback_clawbackOnDrawdown_whenPerformanceFeeDisabled() public {
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_000); // 100% holdback
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // Generate holdback reserve while performance fees are enabled
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveBeforeDisable,,) = NEST_ACCOUNTANT.getReserveState();
        assertGt(reserveBeforeDisable, 0, "Reserve should exist before disabling performance fees");

        // Disable performance fees, then submit a genuine drawdown before the reserve crystallizes
        NEST_ACCOUNTANT.updatePerformanceFee(0);
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_000_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterDrop = NEST_ACCOUNTANT.getAccountantState();
        (uint128 reserveAfterDrop,,) = NEST_ACCOUNTANT.getReserveState();

        assertLt(reserveAfterDrop, reserveBeforeDisable, "Reserve should still claw back after disabling perf fees");
        // Clawback adds the returned reserve per share on top of the gross rate.
        uint256 clawbackPerShare2 =
            uint256(reserveBeforeDisable - reserveAfterDrop) * 1e6 / IERC20(NALPHA).totalSupply();
        assertApproxEqAbs(
            afterDrop.exchangeRate,
            1_000_000 + clawbackPerShare2,
            1,
            "Net rate should include the disabled-fee clawback bump"
        );
        assertEq(afterDrop.feesOwedInBase, 0, "Holdback should remain uncrystallized before the window elapses");
    }

    /// @dev Re-enabling performance fees (0→>0) must NOT overwrite clawbackReferenceRate
    ///      when holdback reserve exists, as the existing reserve was accumulated under a lower
    ///      net post-fee reference. Overwriting with lastGrossRate would cause spurious clawbacks.
    function test_holdback_reEnablePreservesClawbackRef_whenReserveExists() public {
        NEST_ACCOUNTANT.updateUpper(1_200_000);
        NEST_ACCOUNTANT.updateLower(800_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000); // 20%
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_000); // 100% holdback
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // 1. Generate holdback reserve via gain
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveAfterGain,,) = NEST_ACCOUNTANT.getReserveState();
        assertGt(reserveAfterGain, 0, "Reserve should exist after gain");

        NestHubAccountant.AccountantState memory afterGain = NEST_ACCOUNTANT.getAccountantState();
        uint96 netRefBeforeDisable = afterGain.clawbackReferenceRate;
        // Net reference should be below gross (fees were deducted)
        assertLt(netRefBeforeDisable, 1_050_000, "Clawback ref should be net (below gross)");

        // 2. Disable performance fees
        NEST_ACCOUNTANT.updatePerformanceFee(0);

        // 3. Rate moves down but stays above net ref and below old HWM —
        //    recovery check won't ratchet reference, no clawback triggered
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_045_000, uint128(IERC20(NALPHA).totalSupply()));

        // 4. Re-enable performance fees — should NOT overwrite clawbackReferenceRate
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);

        NestHubAccountant.AccountantState memory afterReEnable = NEST_ACCOUNTANT.getAccountantState();
        assertEq(
            afterReEnable.clawbackReferenceRate,
            netRefBeforeDisable,
            "Clawback ref should be preserved (not overwritten with lastGrossRate)"
        );

        // 5. Mild drawdown above old net reference but below lastGrossRate —
        //    should NOT trigger clawback (would have without the fix)
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_042_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveAfterDip,,) = NEST_ACCOUNTANT.getReserveState();
        assertEq(reserveAfterDip, reserveAfterGain, "No spurious clawback above net reference");
    }

    /// @dev Ensures holdback with rate 0 means all fees are immediate
    function test_holdback_zeroRateMeansAllImmediate() public {
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        // holdbackRate defaults to 0

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 totalReserve,,) = NEST_ACCOUNTANT.getReserveState();
        assertEq(totalReserve, 0, "No reserve when holdback rate is 0");
        assertGt(NEST_ACCOUNTANT.getAccountantState().feesOwedInBase, 0, "All fees should be immediate");
    }

    /// @dev Ensures sub-threshold clawback preserves reserve when the base amount is too small to produce a rate bump
    function test_holdback_clawbackSkippedWhenSubThreshold() public {
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_000); // 100% holdback
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // Generate HWM via gain: HWM moves to 1_050_000
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));

        // Overwrite reserve to 1 wei — below the per-share threshold (totalShares / oneShare)
        NEST_ACCOUNTANT.setReserveForTesting(1, uint64(block.timestamp));

        (uint128 reserveBefore,,) = NEST_ACCOUNTANT.getReserveState();
        assertEq(reserveBefore, 1, "Reserve should be 1 wei");

        // Drawdown below HWM — clawback = min(shortfallBase, 1) = 1, but 1 * oneShare / totalShares rounds to 0
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_000_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveAfter,,) = NEST_ACCOUNTANT.getReserveState();
        assertEq(reserveAfter, 1, "Sub-threshold reserve must not be consumed");
    }

    // ======================= Clawback Reference Rate Tests =======================

    /// @dev Repeated below-HWM updates must NOT drain additional reserve (PLUM1-28 regression).
    function test_repeatedBelowHWM_doesNotDrainExtraReserve() public {
        NEST_ACCOUNTANT.updateUpper(1_200_000);
        NEST_ACCOUNTANT.updateLower(800_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000); // 20%
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_000); // 100% holdback
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // Gain → reserve created, HWM = 1_100_000, clawbackRef ≈ 1_080_001 (postFeeRate)
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_100_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveAfterGain,,) = NEST_ACCOUNTANT.getReserveState();
        assertGt(reserveAfterGain, 0, "Reserve should exist after gain");

        // First drawdown to 1_070_000 (below clawbackRef ~1_080_001) — partial clawback
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_070_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveAfterFirstDrawdown,,) = NEST_ACCOUNTANT.getReserveState();
        assertLt(reserveAfterFirstDrawdown, reserveAfterGain, "First drawdown should reduce reserve");
        assertGt(reserveAfterFirstDrawdown, 0, "Should be partial clawback only");

        // Same rate again — clawbackRef was set to 1_070_000, so gross == ref → no clawback
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_070_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveAfterRepeat,,) = NEST_ACCOUNTANT.getReserveState();
        assertEq(reserveAfterRepeat, reserveAfterFirstDrawdown, "Repeated update must not drain extra reserve");
    }

    /// @dev After a partial clawback, a further drawdown should only claw back the incremental shortfall.
    function test_clawback_furtherDrawdownAfterPartial() public {
        NEST_ACCOUNTANT.updateUpper(1_200_000);
        NEST_ACCOUNTANT.updateLower(800_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000); // 20%
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_000); // 100% holdback
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // Gain → HWM = 1_100_000
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_100_000, uint128(IERC20(NALPHA).totalSupply()));
        (uint128 reserveAfterGain,,) = NEST_ACCOUNTANT.getReserveState();

        // First drawdown to 1_090_000 (shortfall = 10_000/share)
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_090_000, uint128(IERC20(NALPHA).totalSupply()));
        (uint128 reserveAfterFirst,,) = NEST_ACCOUNTANT.getReserveState();
        uint128 firstClawback = reserveAfterGain - reserveAfterFirst;

        // Further drawdown to 1_085_000 (incremental shortfall = 5_000/share)
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_085_000, uint128(IERC20(NALPHA).totalSupply()));
        (uint128 reserveAfterSecond,,) = NEST_ACCOUNTANT.getReserveState();
        uint128 secondClawback = reserveAfterFirst - reserveAfterSecond;

        // Second clawback should be ~half of the first (5_000 vs 10_000 shortfall)
        assertApproxEqAbs(
            secondClawback * 2, firstClawback, 2, "Incremental clawback should match incremental shortfall"
        );
    }

    /// @dev After recovery to HWM, the clawback reference ratchets up so that a drawdown that
    ///      previously sat above the reference now triggers clawback.
    ///      In this contract, clawbackRef is the post-fee net rate (≈ HWM − perfFeePerShare after a gain),
    ///      NOT the HWM. Recovery resets it to the current postFeeRate (≈ gross when no new fees).
    function test_clawback_referenceResetsOnRecovery() public {
        NEST_ACCOUNTANT.updateUpper(1_200_000);
        NEST_ACCOUNTANT.updateLower(800_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000); // 20%
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_000); // 100% holdback
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        // Gain → HWM = 1_100_000, clawbackRef ≈ 1_080_001 (postFeeRate)
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_100_000, uint128(IERC20(NALPHA).totalSupply()));
        (uint128 reserveAfterGain,,) = NEST_ACCOUNTANT.getReserveState();

        // Drawdown to 1_090_000 — still above clawbackRef (~1_080_001) → no clawback
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_090_000, uint128(IERC20(NALPHA).totalSupply()));
        (uint128 reserveAfterDrawdown,,) = NEST_ACCOUNTANT.getReserveState();
        assertEq(reserveAfterDrawdown, reserveAfterGain, "No clawback when gross > clawbackRef");

        // Recover to HWM — reference ratchets up to postFeeRate (≈ 1_100_000)
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_100_000, uint128(IERC20(NALPHA).totalSupply()));
        (uint128 reserveAfterRecovery,,) = NEST_ACCOUNTANT.getReserveState();
        assertEq(reserveAfterRecovery, reserveAfterGain, "Recovery should not change reserve");

        // Same drawdown to 1_090_000 — NOW below the ratcheted reference → clawback triggers
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_090_000, uint128(IERC20(NALPHA).totalSupply()));
        (uint128 reserveAfterSecondDrawdown,,) = NEST_ACCOUNTANT.getReserveState();

        assertLt(reserveAfterSecondDrawdown, reserveAfterRecovery, "Clawback should trigger after reference reset");
    }

    // ======================= getReserveState Tests =======================

    /// @dev Ensures getReserveState returns zeros initially
    function test_getReserveState_returnsZerosInitially() public view {
        (uint128 totalReserve, uint64 head, uint64 tail) = NEST_ACCOUNTANT.getReserveState();
        assertEq(totalReserve, 0);
        assertEq(head, 0);
        assertEq(tail, 0);
    }

    // ======================= Gross Checkpoint / Management Fee Regression Tests =======================

    /// @dev Fresh deploy: lastPostLiabilityRate == startingExchangeRate
    function test_initialize_setsLastPostLiabilityRate() public view {
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().lastGrossRate,
            NEST_ACCOUNTANT.getAccountantState().exchangeRate,
            "lastGrossRate should equal starting exchange rate on fresh deploy"
        );
    }

    /// @dev Late NAV increase: discount uses min(lastGross, newGross), not the full ending gross rate
    function test_mgmtFee_lateNAVIncrease_usesMinGrossCheckpoint() public {
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);
        NEST_ACCOUNTANT.updateManagementFee(10_000, uint128(IERC20(NALPHA).totalSupply())); // 1%
        NEST_ACCOUNTANT.updatePerformanceFee(0);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();
        uint256 timeDelta = state.minimumUpdateDelayInSeconds + 1;
        vm.warp(block.timestamp + timeDelta);

        // First update at the same rate — seeds the gross checkpoint
        NEST_ACCOUNTANT.updateExchangeRate(state.exchangeRate, uint128(IERC20(NALPHA).totalSupply()));
        NestHubAccountant.AccountantState memory afterFirst = NEST_ACCOUNTANT.getAccountantState();
        uint128 feesAfterFirst = afterFirst.feesOwedInBase;

        // Second update with a higher gross rate
        vm.warp(block.timestamp + timeDelta);
        uint96 higherGross = uint96(uint256(state.exchangeRate) + 2); // just within bounds
        NEST_ACCOUNTANT.updateExchangeRate(higherGross, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterSecond = NEST_ACCOUNTANT.getAccountantState();
        uint128 feesSecondInterval = afterSecond.feesOwedInBase - feesAfterFirst;

        // The discount should be based on min(lastPostLiabilityRate=1_000_000, newGross=1_000_002) = 1_000_000
        // NOT on 1_000_002. So fees should be the same as the first interval (same basis, same time).
        // First interval: basis was min(lastPostLiabilityRate=1_000_000, gross=1_000_000) = 1_000_000
        // They should match exactly since timeDelta is the same and rateBasis is the same.
        assertEq(feesSecondInterval, feesAfterFirst, "Fees should use min(lastPostLiabilityRate, newGross) as basis");
    }

    /// @dev Fee change with initialized gross checkpoint: old fee stops at checkpoint, new fee starts fresh
    function test_mgmtFee_feeChangeAccruesOldFeeAndCheckpoints() public {
        // Deploy accountant with wider bounds — this test exercises fee accrual, not bounds checking
        address _impl = _deployNestAccountantImplementation();
        address _proxy =
            _deployNestAccountantProxyWithInitParams(_impl, IERC20(NALPHA).totalSupply(), 1_100_000, 900_000, 3600);
        MockNestAccountant accountant = MockNestAccountant(_proxy);

        NestHubAccountant.AccountantState memory state = accountant.getAccountantState();
        uint256 t0 = state.lastUpdateTimestamp;

        // Warp and accrue under old fee
        vm.warp(t0 + 10 days);

        accountant.updateManagementFee(20_000, uint128(IERC20(NALPHA).totalSupply())); // 2% — accrues old 1% for 10 days

        NestHubAccountant.AccountantState memory afterChange = accountant.getAccountantState();
        uint128 feesFromOldFee = afterChange.feesOwedInBase;
        assertGt(feesFromOldFee, 0, "Old fee should have accrued");
        assertEq(afterChange.lastUpdateTimestamp, uint64(t0 + 10 days), "Checkpoint should refresh");

        // Now warp again and do an exchange rate update — new 2% fee should apply
        vm.warp(t0 + 20 days);
        accountant.updateExchangeRate(state.exchangeRate, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterUpdate = accountant.getAccountantState();
        uint128 feesFromNewFee = afterUpdate.feesOwedInBase - feesFromOldFee;

        // New fee is 2x old fee, same time period, same basis → fees should be ~2x
        // Allow 1% relative tolerance for integer rounding across different fee computations
        assertApproxEqRel(
            feesFromNewFee, feesFromOldFee * 2, 0.01e18, "New 2% fee should produce ~2x fees vs old 1% fee"
        );
    }

    /// @dev Upgrade fallback: lastPostLiabilityRate == 0 means net-rate fallback; first update seeds it
    function test_mgmtFee_upgradeFallback_seedsGrossCheckpoint() public {
        // Deploy a fresh accountant and manually zero out lastPostLiabilityRate to simulate upgrade
        address _impl = _deployNestAccountantImplementation();
        address _proxy =
            _deployNestAccountantProxyWithInitParams(_impl, IERC20(NALPHA).totalSupply(), 1_000_003, 999_997, 3600);
        MockNestAccountant _accountant = MockNestAccountant(_proxy);

        // Confirm lastPostLiabilityRate was set by initialize
        assertEq(_accountant.getAccountantState().lastGrossRate, 1e6, "Fresh deploy should have lastGrossRate set");

        // First update should seed lastPostLiabilityRate
        uint256 t0 = _accountant.getAccountantState().lastUpdateTimestamp;
        vm.warp(t0 + 3601);
        _accountant.updateExchangeRate(uint96(1e6), uint128(IERC20(NALPHA).totalSupply()));

        assertEq(_accountant.getAccountantState().lastGrossRate, uint96(1e6), "First update should seed lastGrossRate");

        // Second update should use the gross checkpoint path
        vm.warp(t0 + 7202);
        _accountant.updateExchangeRate(uint96(1e6), uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory finalState = _accountant.getAccountantState();
        assertGt(finalState.feesOwedInBase, 0, "Second update should accrue fees via gross checkpoint");
    }

    /// @dev Late mint: shares minted mid-interval should not inflate management fees or over-discount the rate.
    ///      Uses a fresh accountant with a large management fee and long interval to produce a
    ///      multi-unit discount that exercises the supply-ratio scaling with meaningful numbers.
    function test_mgmtFee_lateMint_usesMinShareSupply() public {
        // Deploy a fresh accountant with 10% management fee and wide bounds
        address impl = _deployNestAccountantImplementation();
        uint256 totalSharesBefore = IERC20(NALPHA).totalSupply();
        MockNestAccountant accountant = MockNestAccountant(
            _deployNestAccountantProxyWithInitParams(impl, totalSharesBefore, 1_100_000, 900_000, 3600)
        );
        accountant.updateManagementFee(100_000, uint128(IERC20(NALPHA).totalSupply())); // 10%
        uint256 oneShare = 10 ** IERC20Metadata(NALPHA).decimals();

        // First update — baseline with current supply, 30 days elapsed
        uint256 timeDelta = 30 days;
        vm.warp(block.timestamp + timeDelta);
        accountant.updateExchangeRate(1_000_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterFirst = accountant.getAccountantState();
        uint128 baselineFees = afterFirst.feesOwedInBase;
        uint256 baselineRate = afterFirst.exchangeRate;
        assertGt(baselineFees, 0, "Baseline fees must be nonzero for a meaningful test");

        // Double the share supply mid-interval
        address minter = address(0xBEEF);
        deal(NALPHA, minter, totalSharesBefore, true);
        uint256 totalSharesAfterMint = IERC20(NALPHA).totalSupply();
        assertEq(totalSharesAfterMint, totalSharesBefore * 2, "Supply should double");

        // Second update with grown supply — same elapsed time
        vm.warp(afterFirst.lastUpdateTimestamp + timeDelta);
        accountant.updateExchangeRate(1_000_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterSecond = accountant.getAccountantState();
        uint128 secondIntervalFees = afterSecond.feesOwedInBase - baselineFees;

        // feesOwedInBase must not exceed what the checkpointed (pre-mint) supply implies
        assertLe(secondIntervalFees, baselineFees, "Fees must not exceed what the checkpointed supply implies");

        // The rate haircut should be smaller when supply grew (discount is spread over more shares)
        uint256 rateDropSecond = 1_000_000 - afterSecond.exchangeRate;
        uint256 rateDropFirst = 1_000_000 - baselineRate;
        assertLt(rateDropSecond, rateDropFirst, "Rate haircut should shrink when supply grows");

        // The aggregate value removed by the rate haircut must exactly equal the
        // booked liability — no over- or under-discount.
        uint256 aggregateHaircut = rateDropSecond * totalSharesAfterMint / oneShare;
        assertEq(aggregateHaircut, secondIntervalFees, "Aggregate haircut must equal booked fees exactly");
    }

    /// @dev Ensures lastPostLiabilityRate is updated after each successful exchange rate update
    function test_lastPostLiabilityRate_updatedOnSuccessfulUpdate() public {
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);

        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();

        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        uint96 grossRate1 = uint96(uint256(state.exchangeRate) + 2);
        NEST_ACCOUNTANT.updateExchangeRate(grossRate1, uint128(IERC20(NALPHA).totalSupply()));
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().lastGrossRate,
            grossRate1,
            "lastGrossRate should be updated to grossRate1"
        );

        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NestHubAccountant.AccountantState memory state2 = NEST_ACCOUNTANT.getAccountantState();
        uint96 grossRate2 = uint96(uint256(state2.exchangeRate) + 1);
        NEST_ACCOUNTANT.updateExchangeRate(grossRate2, uint128(IERC20(NALPHA).totalSupply()));
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().lastGrossRate,
            grossRate2,
            "lastGrossRate should be updated to grossRate2"
        );
    }

    /// @dev Ensures updateManagementFee does NOT change lastPostLiabilityRate or exchangeRate
    function test_updateManagementFee_doesNotChangeRates() public {
        NestHubAccountant.AccountantState memory stateBefore = NEST_ACCOUNTANT.getAccountantState();
        uint96 lastGrossBefore = NEST_ACCOUNTANT.getAccountantState().lastGrossRate;
        uint256 t0 = stateBefore.lastUpdateTimestamp;

        vm.warp(t0 + 5 days);
        NEST_ACCOUNTANT.updateManagementFee(20_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory stateAfter = NEST_ACCOUNTANT.getAccountantState();
        assertEq(stateAfter.exchangeRate, stateBefore.exchangeRate, "exchangeRate should not change on fee update");
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().lastGrossRate,
            lastGrossBefore,
            "lastGrossRate should not change on fee update"
        );
        assertEq(stateAfter.highWaterMark, stateBefore.highWaterMark, "HWM should not change on fee update");
    }
}
