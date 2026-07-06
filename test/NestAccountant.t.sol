// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// utils
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Options, DefenderOptions, TxOverrides} from "@openzeppelin/foundry-upgrades/src/Options.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";

// contracts
import {Constants} from "test/Constants.sol";
import {MockNestAccountant, NestHubAccountant} from "test/mock/MockNestAccountant.sol";
import {NestAccountant} from "contracts/accountant/NestAccountant.sol";
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

    function test_updateManagementFee_revertsBeforeMinimumDelayWhenTimeElapsed() public {
        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();
        uint128 supply = uint128(IERC20(NALPHA).totalSupply());
        vm.warp(uint256(state.lastUpdateTimestamp) + state.minimumUpdateDelayInSeconds - 1);

        vm.expectRevert(Errors.MinimumUpdateDelayNotPassed.selector);
        NEST_ACCOUNTANT.updateManagementFee(20_000, supply);
    }

    function test_updateManagementFee_succeedsAfterRateUpdateInSameTimestamp() public {
        NestHubAccountant.AccountantState memory state = NEST_ACCOUNTANT.getAccountantState();
        uint128 supply = uint128(IERC20(NALPHA).totalSupply());
        vm.warp(uint256(state.lastUpdateTimestamp) + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(state.exchangeRate, supply);

        NestHubAccountant.AccountantState memory afterRateUpdate = NEST_ACCOUNTANT.getAccountantState();
        NEST_ACCOUNTANT.updateManagementFee(20_000, supply);

        NestHubAccountant.AccountantState memory afterFeeUpdate = NEST_ACCOUNTANT.getAccountantState();
        assertEq(afterFeeUpdate.managementFee, 20_000, "management fee should update");
        assertEq(afterFeeUpdate.exchangeRate, afterRateUpdate.exchangeRate, "fee update should not move rate");
        assertEq(
            afterFeeUpdate.lastUpdateTimestamp,
            afterRateUpdate.lastUpdateTimestamp,
            "fee update should not create another checkpoint"
        );
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

    /// @dev Regression: a sub-unit management-fee haircut must not be lost. On short, low-fee intervals the
    ///      per-share discount is below one rate unit; instead of truncating to zero each update (and never
    ///      charging the fee), the fraction is carried in managementFeeReserve and realized once it crosses
    ///      a whole rate unit. The realized fee must match the rate drop (conservation) and the total realized
    ///      haircut must match the analytic accrual over the elapsed time (no loss).
    function test_updateExchangeRate_subUnitMgmtFeeCarriesAndRealizes() public {
        // Widen bounds so the gradual rate drop is never clipped
        NEST_ACCOUNTANT.updateUpper(1_100_000);
        NEST_ACCOUNTANT.updateLower(900_000);

        uint128 supply = uint128(IERC20(NALPHA).totalSupply());
        uint256 totalShares = IERC20(NALPHA).totalSupply();
        uint256 oneShare = 10 ** IERC20Metadata(NALPHA).decimals();

        // 0.1% fee + ~1h interval => per-share discount of ~0.1 rate units, i.e. sub-unit and truncated by
        // the old code. Realization threshold here is ~31500s (~8.75h).
        uint32 lowFee = 1000;
        NEST_ACCOUNTANT.updateManagementFee(lowFee, supply);

        uint96 grossRate = 1_000_000;
        uint256 step = 3601; // just above the 3600s minimum delay, below the realization threshold
        uint256 t = block.timestamp;

        // Phase 1: several sub-threshold updates accrue into the carry without moving rate or booking fees
        uint256 nUpdates;
        for (uint256 i = 0; i < 5; i++) {
            t += step;
            vm.warp(t);
            NEST_ACCOUNTANT.updateExchangeRate(grossRate, supply);
            nUpdates++;
        }
        NestHubAccountant.AccountantState memory s = NEST_ACCOUNTANT.getAccountantState();
        assertEq(s.exchangeRate, grossRate, "rate must not move while the discount is sub-unit");
        assertEq(s.feesOwedInBase, 0, "no fee booked while the discount is sub-unit");
        assertGt(NEST_ACCOUNTANT.managementFeeCarryForTesting(), 0, "carried remainder must accumulate the fraction");

        // Phase 2: keep updating until the carry crosses one whole rate unit and is realized
        while (NEST_ACCOUNTANT.getAccountantState().exchangeRate == grossRate) {
            t += step;
            vm.warp(t);
            NEST_ACCOUNTANT.updateExchangeRate(grossRate, supply);
            nUpdates++;
        }
        s = NEST_ACCOUNTANT.getAccountantState();

        // Conservation: the fee booked equals the realized rate haircut applied to all shares
        uint256 realizedHaircut = uint256(grossRate) - uint256(s.exchangeRate);
        assertGt(realizedHaircut, 0, "rate must drop once the carry crosses a whole unit");
        assertEq(
            s.feesOwedInBase,
            realizedHaircut * totalShares / oneShare,
            "feesOwedInBase must match the realized rate haircut (no over/under-claim)"
        );

        // No loss: total realized haircut equals the analytic accrual over the elapsed time, within 1 unit
        uint256 totalElapsed = nUpdates * step;
        uint256 expectedHaircut = uint256(grossRate) * lowFee * totalElapsed / (1e6 * 365 days);
        assertApproxEqAbs(realizedHaircut, expectedHaircut, 1, "realized haircut must match analytic accrual");

        // Invariant: the carried remainder (base terms) stays below one rate unit's worth of base, plus rounding
        assertLt(
            NEST_ACCOUNTANT.managementFeeCarryForTesting(),
            uint256(1e6 * 365 days) * totalShares / oneShare + 2 * uint256(1e6 * 365 days),
            "remainder must stay below one rate unit in base terms"
        );
    }

    /// @dev Edge case: with sub-one-share supply, one whole rate unit is worth less than one base unit, so a
    ///      rate haircut can round to a zero base fee. The rate, the reserve consumption, and the booked fee
    ///      must stay in lockstep: the rate must NOT drop (and the reserve must keep accruing past one rate
    ///      unit) until the realized fee is nonzero in base units, at which point all three move together.
    function test_updateExchangeRate_subOneShareSupplyKeepsRateAndFeeInLockstep() public {
        uint256 totalShares = 5e5; // 0.5 of one 6-decimal share => oneShare (1e6) > totalShares
        uint256 oneShare = 1e6;
        TinyShareToken share = new TinyShareToken(6, totalShares);

        MockNestAccountant impl = new MockNestAccountant(USDC, address(share));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(this),
            abi.encodeCall(
                NestHubAccountant.initialize,
                (
                    totalShares, // totalSharesLastUpdate
                    address(this), // payoutAddress
                    uint96(1e6), // startingExchangeRate
                    uint32(1_100_000), // upper
                    uint32(900_000), // lower
                    uint32(1), // minimumUpdateDelayInSeconds
                    uint32(200_000), // managementFee = 20% (max)
                    uint32(0), // performanceFee
                    uint32(0), // hurdleRate
                    uint32(0), // holdbackRate
                    uint32(0), // crystallizationWindow
                    uint32(0), // epochsPerWindow
                    address(this) // owner
                )
            )
        );
        MockNestAccountant acct = MockNestAccountant(address(proxy));

        uint96 grossRate = 1_000_000;
        uint256 step = 100;
        uint256 t = block.timestamp;

        // Drive updates until one whole rate unit's worth of base fee has accrued, but a whole base unit has
        // not. The code must NOT realize: rate stays at gross, no fee, and the reserve keeps accruing.
        uint256 den = 1e6 * 365 days;
        uint256 oneRateUnitInBase = den * totalShares / oneShare; // < den since totalShares < oneShare
        while (acct.managementFeeCarryForTesting() < oneRateUnitInBase) {
            t += step;
            vm.warp(t);
            acct.updateExchangeRate(grossRate, uint128(totalShares));
            if (acct.getAccountantState().exchangeRate < grossRate) break; // safety: realized earlier than expected
        }
        NestHubAccountant.AccountantState memory s = acct.getAccountantState();
        assertEq(s.exchangeRate, grossRate, "rate must not drop while the fee rounds to zero base units");
        assertEq(s.feesOwedInBase, 0, "no fee booked while it rounds to zero base units");
        assertGe(
            acct.managementFeeCarryForTesting(),
            oneRateUnitInBase,
            "reserve must accrue past one rate unit instead of being consumed"
        );

        // Keep updating until the fee becomes representable in base units; then rate + fee realize together.
        while (acct.getAccountantState().exchangeRate == grossRate) {
            t += step;
            vm.warp(t);
            acct.updateExchangeRate(grossRate, uint128(totalShares));
        }
        s = acct.getAccountantState();

        uint256 rateDrop = uint256(grossRate) - uint256(s.exchangeRate);
        assertGt(rateDrop, 0, "rate must drop once the fee is representable");
        assertGt(s.feesOwedInBase, 0, "a nonzero fee must be booked when the rate drops");
        assertEq(
            s.feesOwedInBase,
            rateDrop * totalShares / oneShare,
            "booked fee must match the realized rate haircut (lockstep)"
        );
        assertLt(acct.managementFeeCarryForTesting(), den, "reserve drops back below one base unit after realizing");
    }

    /// @dev Regression (P1 stale carry): under sub-one-share supply a nonzero fee accrues into the reserve
    ///      past one whole rate unit without ever booking a base fee (it rounds to zero base units). If the
    ///      fee is then disabled and supply later grows past one share, the carry must NOT be charged while
    ///      the configured fee is 0. Accrual is skipped while the fee is 0, so the carry is frozen (still
    ///      owed, neither realized nor forfeited) and the rate stays at gross; once the fee is re-enabled the
    ///      earned carry resumes and realizes when representable.
    function test_updateExchangeRate_noStaleCarryChargedAfterFeeDisabledInSubOneShareState() public {
        uint256 localSupply = 5e5; // 0.5 of one 6-decimal share => oneShare (1e6) > localSupply
        uint256 oneShare = 1e6;
        TinyShareToken share = new TinyShareToken(6, localSupply);

        MockNestAccountant impl = new MockNestAccountant(USDC, address(share));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(this),
            abi.encodeCall(
                NestHubAccountant.initialize,
                (
                    localSupply, // totalSharesLastUpdate
                    address(this), // payoutAddress
                    uint96(1e6), // startingExchangeRate
                    uint32(1_100_000), // upper
                    uint32(900_000), // lower
                    uint32(1), // minimumUpdateDelayInSeconds
                    uint32(200_000), // managementFee = 20% (max)
                    uint32(0), // performanceFee
                    uint32(0), // hurdleRate
                    uint32(0), // holdbackRate
                    uint32(0), // crystallizationWindow
                    uint32(0), // epochsPerWindow
                    address(this) // owner
                )
            )
        );
        MockNestAccountant acct = MockNestAccountant(address(proxy));

        uint96 grossRate = 1_000_000;
        uint256 step = 100;
        uint256 den = 1e6 * 365 days;
        uint256 t = block.timestamp;

        // Phase 1: accrue under the nonzero fee while sub-one-share — the carry crosses one rate unit's worth
        // of base fee but no whole base unit is bookable, so the rate must not move.
        uint256 oneRateUnitInBase = den * localSupply / oneShare; // < den since localSupply < oneShare
        while (acct.managementFeeCarryForTesting() < oneRateUnitInBase) {
            t += step;
            vm.warp(t);
            acct.updateExchangeRate(grossRate, uint128(localSupply));
            if (acct.getAccountantState().exchangeRate < grossRate) break; // safety: realized earlier than expected
        }
        assertGe(
            acct.managementFeeCarryForTesting(), oneRateUnitInBase, "reserve must exceed one rate unit before disabling"
        );
        assertEq(acct.getAccountantState().exchangeRate, grossRate, "rate must not move while sub-unit");
        assertEq(acct.getAccountantState().feesOwedInBase, 0, "no fee booked while sub-unit");

        // Phase 2: disable the fee while still sub-one-share. The earned carry is owed, so it must be
        // preserved (frozen) — not forfeited and not realized while the fee is 0.
        t += step;
        vm.warp(t);
        acct.updateManagementFee(0, uint128(localSupply));
        uint256 carryAtDisable = acct.managementFeeCarryForTesting();
        assertEq(acct.getAccountantState().managementFee, 0, "fee must be disabled");
        assertGe(carryAtDisable, oneRateUnitInBase, "earned carry must be preserved when the fee is disabled");

        // Phase 3: supply grows past one share while the fee is 0. No fee may be charged, the rate must stay
        // at gross, and the carry must stay frozen (the bug realized it here because the fee was 0).
        uint128 grownSupply = uint128(2 * oneShare); // >= oneShare and >= localSupply
        t += step;
        vm.warp(t);
        acct.updateExchangeRate(grossRate, grownSupply);

        NestHubAccountant.AccountantState memory s = acct.getAccountantState();
        assertEq(s.exchangeRate, grossRate, "rate must equal gross when configured fee is 0");
        assertEq(s.feesOwedInBase, 0, "no management fee may be booked when configured fee is 0");
        assertEq(acct.managementFeeCarryForTesting(), carryAtDisable, "carry must stay frozen while fee is 0");

        // Phase 4: re-enable the fee. The preserved carry resumes accruing and realizes once a whole base
        // unit is owed — its base value is fixed at what was earned, NOT amplified by the grown supply.
        t += step;
        vm.warp(t);
        acct.updateManagementFee(1000, grownSupply); // 0.1%
        while (acct.getAccountantState().exchangeRate == grossRate) {
            t += step;
            vm.warp(t);
            acct.updateExchangeRate(grossRate, grownSupply);
        }

        s = acct.getAccountantState();
        uint256 rateDrop = uint256(grossRate) - uint256(s.exchangeRate);
        assertGt(s.feesOwedInBase, 0, "the earned carry must eventually be booked, not forfeited");
        assertEq(
            s.feesOwedInBase, rateDrop * grownSupply / oneShare, "booked fee must match the rate haircut (lockstep)"
        );
        assertLe(s.feesOwedInBase, 2, "carry must realize at its earned base value, not scaled up by new supply");
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

    /// @dev Clawback fires on genuine investment drawdown (posted rate drops below the clawback
    ///      reference), not on flat NAV: HWM tracks the posted rate, so submitting the same rate twice
    ///      does NOT trigger clawback — only an actual decline does. The clawback credits reserve on
    ///      top of the posted rate, which is sound because the posted rate is net of the reserve
    ///      (see `updateExchangeRate` natspec).
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

        (uint128 reserveAfterUpdate1,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertGt(reserveAfterUpdate1, 0, "Reserve should be positive after gain");

        // Sanity: submitting the same gross again does NOT clawback (HWM == raw gross, no drawdown).
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_100_000, uint128(IERC20(NALPHA).totalSupply()));
        (uint128 reserveAfterFlat,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertEq(reserveAfterFlat, reserveAfterUpdate1, "Flat NAV should not reduce reserve");

        // Actual drawdown: gross drops to 1_090_000 < HWM 1_100_000 → partial clawback.
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_090_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveAfterDrawdown,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();

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
        NestHubAccountant.PerformanceFeeCheckpoint memory checkpoint = NEST_ACCOUNTANT.getPerformanceFeeCheckpoint();
        assertEq(checkpoint.highWaterMark, state.exchangeRate, "HWM should be set to starting exchange rate");
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

        NestHubAccountant.PerformanceFeeCheckpoint memory afterEnable = NEST_ACCOUNTANT.getPerformanceFeeCheckpoint();
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
            NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark,
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

        NestHubAccountant.PerformanceFeeCheckpoint memory afterReEnable = NEST_ACCOUNTANT.getPerformanceFeeCheckpoint();
        // HWM now seeds from lastPreFeeRate (raw gross) so that it stays in gross terms,
        // consistent with how _accruePerformanceFees stores HWM = _grossRate on gain.
        assertEq(afterReEnable.highWaterMark, 1_080_000, "HWM should reset to lastPreFeeRate on re-enable");
    }

    /// @dev NEST-40: re-enabling perf fees while reserve is live must NOT reseed the HWM from
    ///      lastGrossRate. With reserve outstanding, lastGrossRate is net of held-back fees and sits
    ///      below the true gross peak, so reseeding would lower the HWM and re-tax a recovery that has
    ///      not cleared the old high. The baseline must be preserved.
    function test_updatePerformanceFee_reEnableWithLiveReservePreservesHWM() public {
        uint256 _supply = IERC20(NALPHA).totalSupply();
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(_supply));
        NEST_ACCOUNTANT.updateUpper(1_200_000);
        NEST_ACCOUNTANT.updateLower(800_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000); // 20%
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_000); // 100% holdback → gains create live reserve
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days);

        uint32 _delay = NEST_ACCOUNTANT.getAccountantState().minimumUpdateDelayInSeconds;

        // Gain to gross 1_100_000: HWM = 1_100_000 (true peak), reserve held back, net rate = 1_080_000.
        vm.warp(block.timestamp + _delay + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_100_000, uint128(_supply));
        assertEq(NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark, 1_100_000, "HWM at true gross peak");
        (uint128 _reserveLive,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertGt(_reserveLive, 0, "reserve held back after gain");

        // Disable perf fee; reserve stays live.
        NEST_ACCOUNTANT.updatePerformanceFee(0);

        // Keeper posts the flat NAV net of the held-back reserve (1_080_000 < true peak 1_100_000).
        // No clawback (rate == clawbackRef), so reserve survives and lastGrossRate is now net-of-reserve.
        vm.warp(block.timestamp + _delay + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_080_000, uint128(_supply));
        assertEq(NEST_ACCOUNTANT.getAccountantState().lastGrossRate, 1_080_000, "lastGrossRate now net-of-reserve");
        (uint128 _reserveBeforeReEnable,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertEq(_reserveBeforeReEnable, _reserveLive, "reserve survived the flat post");

        // Re-enable with live reserve: HWM must be preserved at 1_100_000, NOT lowered to 1_080_000.
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        assertEq(
            NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark,
            1_100_000,
            "HWM preserved when reserve is live (not reseeded from net-of-reserve lastGrossRate)"
        );

        // Recovery below the old peak (1_090_000 < 1_100_000) must charge NO new performance fee.
        (uint128 _reserveBeforeRecovery,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        uint128 _feesBeforeRecovery = NEST_ACCOUNTANT.getAccountantState().feesOwedInBase;
        vm.warp(block.timestamp + _delay + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_090_000, uint128(_supply));
        (uint128 _reserveAfterRecovery,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertEq(_reserveAfterRecovery, _reserveBeforeRecovery, "recovery below old peak accrues no new reserve");
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().feesOwedInBase,
            _feesBeforeRecovery,
            "recovery below old peak charges no new perf fee"
        );
    }

    /// @dev NEST-40 follow-up: the HWM ratchets up only. If the rate ROSE while fees were disabled
    ///      (with reserve still live), re-enabling must advance the HWM to the higher posted rate so
    ///      those disabled-period gains are not retroactively taxed — the case a `totalReserve == 0`
    ///      gate that preserved the old HWM would get wrong.
    function test_updatePerformanceFee_reEnableRatchetsHWMUpOnDisabledPeriodGain() public {
        uint256 _supply = IERC20(NALPHA).totalSupply();
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(_supply));
        NEST_ACCOUNTANT.updateUpper(1_200_000);
        NEST_ACCOUNTANT.updateLower(800_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000); // 20%
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_000); // 100% holdback → gain leaves live reserve
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days);

        uint32 _delay = NEST_ACCOUNTANT.getAccountantState().minimumUpdateDelayInSeconds;

        // Gain to gross 1_100_000: HWM = 1_100_000, reserve held back.
        vm.warp(block.timestamp + _delay + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_100_000, uint128(_supply));
        assertEq(NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark, 1_100_000, "HWM at first peak");
        (uint128 _reserveLive,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertGt(_reserveLive, 0, "reserve held back");

        // Disable, then the rate RISES during the disabled window (no fee charged, HWM frozen at 1_100_000).
        NEST_ACCOUNTANT.updatePerformanceFee(0);
        vm.warp(block.timestamp + _delay + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_150_000, uint128(_supply));
        assertEq(NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark, 1_100_000, "HWM frozen while disabled");
        (uint128 _reserveBeforeReEnable,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertEq(_reserveBeforeReEnable, _reserveLive, "reserve still live at re-enable");

        // Re-enable with live reserve: HWM must ADVANCE to 1_150_000 so the 1_100_000 -> 1_150_000
        // disabled-period gain is not retroactively taxed.
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        assertEq(
            NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark,
            1_150_000,
            "HWM ratchets up to the higher posted rate despite live reserve"
        );

        // A flat post at 1_150_000 (== new HWM) must charge no fee: the disabled gain is not taxed.
        (uint128 _reserveBeforeFlat,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        uint128 _feesBeforeFlat = NEST_ACCOUNTANT.getAccountantState().feesOwedInBase;
        vm.warp(block.timestamp + _delay + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_150_000, uint128(_supply));
        (uint128 _reserveAfterFlat,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertEq(_reserveAfterFlat, _reserveBeforeFlat, "no new reserve: disabled-period gain not taxed");
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().feesOwedInBase, _feesBeforeFlat, "no new perf fee on the disabled gain"
        );
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

        uint96 hwmAfterGain = NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark;
        assertEq(hwmAfterGain, 1_050_000, "HWM should track the gross rate");

        // Change fee from 20% to 10% — should NOT reset HWM
        NEST_ACCOUNTANT.updatePerformanceFee(100_000);

        assertEq(
            NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark, hwmAfterGain, "HWM must not reset on >0 to >0"
        );
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
        NestHubAccountant.PerformanceFeeCheckpoint memory checkpoint = NEST_ACCOUNTANT.getPerformanceFeeCheckpoint();
        uint96 newHWM = 1_500_000;

        vm.expectEmit();
        emit NestHubAccountant.HighWaterMarkUpdated(checkpoint.highWaterMark, newHWM);
        NEST_ACCOUNTANT.resetHighWaterMark(newHWM);

        assertEq(NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark, newHWM);
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
        assertEq(
            NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark,
            1_050_000,
            "HWM should update to the gross rate"
        );
        assertGt(newState.feesOwedInBase, 0, "Fees should be owed");

        // Lockstep: the booked fee must equal exactly what holders lose through the rate haircut
        uint256 totalShares = IERC20(NALPHA).totalSupply();
        uint256 oneShare = 10 ** IERC20Metadata(NALPHA).decimals();
        uint256 haircut = uint256(grossRate) - uint256(newState.exchangeRate);
        assertEq(
            newState.feesOwedInBase,
            haircut * totalShares / oneShare,
            "booked perf fee must match the rate haircut (no overbooking)"
        );
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
        uint96 hwmAfterGain = NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark; // 1_050_000
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
        assertEq(
            NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark,
            hwmAfterGain,
            "HWM should not decrease on drawdown"
        );
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
        uint96 hwmPeak = NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark;

        // Drawdown
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_000_000, uint128(IERC20(NALPHA).totalSupply()));
        assertEq(NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark, hwmPeak, "HWM must not decrease");

        // Recovery but still below HWM
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_030_000, uint128(IERC20(NALPHA).totalSupply()));
        assertEq(
            NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark, hwmPeak, "HWM still at peak during recovery"
        );
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
        uint96 hwmBefore = NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark;
        // Wait 1 year so hurdle-adjusted HWM = 1_000_000 + 1_000_000 * 100_000 * 365days / (1e6 * 365days) = 1_100_000
        uint256 oneYear = 365 days;
        vm.warp(block.timestamp + oneYear);

        // Gross rate = 1_050_000, below the hurdle-adjusted HWM of 1_100_000
        NEST_ACCOUNTANT.updateExchangeRate(1_050_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory newState = NEST_ACCOUNTANT.getAccountantState();
        // No perf fee (below hurdle), no mgmt fee (set to 0)
        assertEq(newState.exchangeRate, 1_050_000, "Net rate should equal gross rate when below hurdle");
        assertEq(
            NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark,
            hwmBefore,
            "HWM should not change when below hurdle"
        );
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
        assertEq(
            NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark,
            1_100_000,
            "HWM should update to the gross rate"
        );
    }

    /// @dev V13: an above-HWM gain accrued while supply is zero must ratchet the HWM (no cohort to charge),
    ///      so pre-supply appreciation is not retroactively taxed on the first entrants. Dust gains with
    ///      supply > 0 must still defer (no ratchet) so sub-rate-unit gains stay captured for a later fee.
    function test_perfFee_zeroSupplyRatchetsHwmButDustDefers() public {
        NEST_ACCOUNTANT.updatePerformanceFee(200_000); // 20%, hurdle stays 0

        uint96 _hwm0 = NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark;
        uint64 _now = uint64(block.timestamp);

        // Zero supply: ratchet HWM to the new rate, charge nothing.
        uint256 _newRate = uint256(_hwm0) + 100_000;
        uint256 _ret = NEST_ACCOUNTANT.accruePerformanceFeesForTesting(_newRate, _newRate, 0, 1e6, _now);

        NestHubAccountant.PerformanceFeeCheckpoint memory _cp = NEST_ACCOUNTANT.getPerformanceFeeCheckpoint();
        assertEq(_cp.highWaterMark, uint96(_newRate), "Zero-supply gain must ratchet HWM");
        assertEq(_cp.hwmLastUpdateTimestamp, _now, "Zero-supply gain must advance HWM timestamp");
        assertEq(_ret, _newRate, "Zero-supply path charges no fee");

        // Dust gain with supply > 0 (gainBase floors to 0) must NOT ratchet — deferral preserved.
        uint96 _hwm1 = _cp.highWaterMark;
        uint256 _dustRate = uint256(_hwm1) + 1;
        NEST_ACCOUNTANT.accruePerformanceFeesForTesting(_dustRate, _dustRate, 1, 1e6, _now + 1);
        assertEq(
            NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark,
            _hwm1,
            "Dust gain (supply > 0) must not ratchet HWM"
        );
    }

    /// @dev NEST-44/NEST-37: when share supply hits zero, held-back reserve is crystallized to the
    ///      manager and the clawback baseline re-anchors to the posted rate. A drawdown posted while
    ///      supply is zero must NOT leave a stale clawback reference and live reserve that a later
    ///      cohort can replay to drain. After the fix the reserve moves to feesOwedInBase (the holders
    ///      it was deferred against have all exited), and a same-rate update once supply returns credits
    ///      nothing back.
    function test_perfFee_zeroSupplyDrawdownCrystallizesReserveAndBlocksReplay() public {
        uint256 _supply = IERC20(NALPHA).totalSupply();
        NEST_ACCOUNTANT.updateUpper(1_200_000);
        NEST_ACCOUNTANT.updateLower(800_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000); // 20%
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(_supply));
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_000); // 100% holdback → all fee to reserve
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days);

        NestHubAccountant.AccountantState memory _state = NEST_ACCOUNTANT.getAccountantState();

        // Gain → reserve accrues, HWM = 1_100_000, clawbackRef = net rate 1_080_000, feesOwed = 0.
        vm.warp(block.timestamp + _state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_100_000, uint128(_supply));

        (uint128 _reserveAfterGain,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertGt(_reserveAfterGain, 0, "reserve held back after gain");
        assertEq(NEST_ACCOUNTANT.getAccountantState().feesOwedInBase, 0, "100% holdback leaves no immediate fees");

        // Zero-supply drawdown (below the stale clawback reference). Driven through the test hook because
        // the public path cannot pass supply 0 while live SHARE supply is non-zero.
        uint64 _now = uint64(block.timestamp);
        uint256 _ret = NEST_ACCOUNTANT.accruePerformanceFeesForTesting(1_050_000, 1_050_000, 0, 1e6, _now);

        (uint128 _reserveAfterDrawdown,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        NestHubAccountant.PerformanceFeeCheckpoint memory _cp = NEST_ACCOUNTANT.getPerformanceFeeCheckpoint();
        assertEq(_ret, 1_050_000, "zero-supply path posts the rate as-is, no clawback bump");
        assertEq(_reserveAfterDrawdown, 0, "reserve crystallized away on zero-supply drawdown");
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().feesOwedInBase,
            _reserveAfterGain,
            "reserve credited to manager fees, not burned or carried"
        );
        assertEq(_cp.clawbackReferenceRate, 1_050_000, "clawback reference re-anchored (no stale shortfall)");
        assertEq(_cp.highWaterMark, 1_050_000, "HWM re-anchored to the posted rate");

        // Supply returns and a flat update at the same rate must not resurrect reserve or credit the new cohort.
        uint256 _retReplay =
            NEST_ACCOUNTANT.accruePerformanceFeesForTesting(1_050_000, 1_050_000, _supply, 1e6, _now + 1);
        (uint128 _reserveAfterReplay,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertEq(_retReplay, 1_050_000, "no replay: flat update credits nothing to the new cohort");
        assertEq(_reserveAfterReplay, 0, "no reserve resurrected for the new cohort");
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().feesOwedInBase,
            _reserveAfterGain,
            "fees unchanged on replay (no double-count)"
        );
    }

    /// @dev NEST-37: a zero-supply GAIN with live reserve must crystallize the reserve to the manager
    ///      and re-anchor the baseline, not leave legacy reserve to be clawed into the next cohort
    ///      against an empty-period high. Counterpart to the zero-supply drawdown test above.
    function test_perfFee_zeroSupplyGainCrystallizesReserveAndBlocksReplay() public {
        uint256 _supply = IERC20(NALPHA).totalSupply();
        NEST_ACCOUNTANT.updateUpper(1_300_000);
        NEST_ACCOUNTANT.updateLower(800_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000); // 20%
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(_supply));
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_000); // 100% holdback → all fee to reserve
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days);

        NestHubAccountant.AccountantState memory _state = NEST_ACCOUNTANT.getAccountantState();

        // Gain → reserve accrues, HWM = 1_100_000, feesOwed = 0.
        vm.warp(block.timestamp + _state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_100_000, uint128(_supply));
        (uint128 _reserveAfterGain,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertGt(_reserveAfterGain, 0, "reserve held back after gain");
        assertEq(NEST_ACCOUNTANT.getAccountantState().feesOwedInBase, 0, "100% holdback leaves no immediate fees");

        // Zero-supply GAIN (posted rate ABOVE the HWM) while reserve is still live. Driven through the
        // test hook because the public path cannot pass supply 0 while live SHARE supply is non-zero.
        uint64 _now = uint64(block.timestamp);
        uint256 _ret = NEST_ACCOUNTANT.accruePerformanceFeesForTesting(1_200_000, 1_200_000, 0, 1e6, _now);

        (uint128 _reserveAfterZeroGain,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        NestHubAccountant.PerformanceFeeCheckpoint memory _cp = NEST_ACCOUNTANT.getPerformanceFeeCheckpoint();
        assertEq(_ret, 1_200_000, "zero-supply gain posts the rate as-is, charges nothing");
        assertEq(_reserveAfterZeroGain, 0, "reserve crystallized away on zero-supply gain (not left to leak)");
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().feesOwedInBase,
            _reserveAfterGain,
            "legacy reserve credited to manager fees, not carried into the next cohort"
        );
        assertEq(_cp.highWaterMark, 1_200_000, "HWM re-anchored to the empty-period rate");
        assertEq(_cp.clawbackReferenceRate, 1_200_000, "clawback reference re-anchored");

        // New cohort enters; a later drawdown below the re-anchored reference must find no legacy reserve
        // to claw into the cohort (it was already crystallized to the manager).
        uint256 _retDrawdown =
            NEST_ACCOUNTANT.accruePerformanceFeesForTesting(1_150_000, 1_150_000, _supply, 1e6, _now + 1);
        (uint128 _reserveAfterDrawdown,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertEq(_retDrawdown, 1_150_000, "no clawback bump: no legacy reserve survives for the new cohort");
        assertEq(_reserveAfterDrawdown, 0, "no reserve resurrected for the new cohort");
        assertEq(
            NEST_ACCOUNTANT.getAccountantState().feesOwedInBase,
            _reserveAfterGain,
            "manager fees unchanged on the new cohort drawdown (no double-count)"
        );
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
        (uint128 totalReserve,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();

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
        (uint128 reserveBefore,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertGt(reserveBefore, 0, "Reserve should have holdback");
        // With 100% holdback, no immediate fees
        assertEq(afterGain.feesOwedInBase, 0, "No immediate fees with 100% holdback");

        // Wait for crystallization window to pass + update at HWM (no drawdown, so no clawback)
        vm.warp(block.timestamp + 91 days);
        NEST_ACCOUNTANT.updateExchangeRate(
            NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark, uint128(IERC20(NALPHA).totalSupply())
        );

        NestHubAccountant.AccountantState memory afterCrystal = NEST_ACCOUNTANT.getAccountantState();
        (uint128 reserveAfter,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertEq(reserveAfter, 0, "Reserve should be zero after crystallization");
        assertGt(afterCrystal.feesOwedInBase, 0, "Crystallized reserve should move to feesOwedInBase");
    }

    /// @dev W6: with epochsPerWindow == 0, multiple gains inside one crystallization window must merge
    ///      into a single reserve batch (not one per accrual), bounding the crystallize/clawback loops.
    function test_holdback_zeroEpochsMergesBatchesWithinWindow() public {
        NEST_ACCOUNTANT.updateUpper(1_200_000);
        NEST_ACCOUNTANT.updateLower(900_000);
        NEST_ACCOUNTANT.updatePerformanceFee(200_000);
        NEST_ACCOUNTANT.updateManagementFee(0, uint128(IERC20(NALPHA).totalSupply()));
        NEST_ACCOUNTANT.updateHoldbackRate(1_000_000); // 100% holdback: every gain creates reserve
        NEST_ACCOUNTANT.updateCrystallizationWindow(90 days);
        NEST_ACCOUNTANT.updateEpochsPerWindow(0); // disabled epoching: fix collapses to one epoch/window

        uint32 _delay = NEST_ACCOUNTANT.getAccountantState().minimumUpdateDelayInSeconds;

        // Align to a 90-day bucket boundary so the gains below all fall in the same epoch.
        vm.warp(90 days * 1000);

        uint96[4] memory _grosses = [uint96(1_040_000), 1_080_000, 1_120_000, 1_160_000];
        for (uint256 i = 0; i < _grosses.length; i++) {
            vm.warp(block.timestamp + _delay + 1);
            NEST_ACCOUNTANT.updateExchangeRate(_grosses[i], uint128(IERC20(NALPHA).totalSupply()));
        }

        (uint128 totalReserve, uint64 head, uint64 tail) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertGt(totalReserve, 0, "Reserve should hold the merged holdback");
        assertEq(tail - head, 1, "Zero-epoch accruals within one window must merge into a single batch");

        // The merged batch still crystallizes cleanly after the window elapses.
        vm.warp(block.timestamp + 91 days);
        NEST_ACCOUNTANT.updateExchangeRate(
            NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().highWaterMark, uint128(IERC20(NALPHA).totalSupply())
        );
        (uint128 reserveAfter,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertEq(reserveAfter, 0, "Merged batch should fully crystallize after the window");
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

        (uint128 reserveBeforeClawback,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertGt(reserveBeforeClawback, 0, "Reserve should exist before clawback");

        // Drawdown below HWM — triggers clawback
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_000_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterDrop = NEST_ACCOUNTANT.getAccountantState();
        (uint128 reserveAfterClawback,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();

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

        (uint128 reserveBeforeDisable,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertGt(reserveBeforeDisable, 0, "Reserve should exist before disabling performance fees");

        // Disable performance fees, then submit a genuine drawdown before the reserve crystallizes
        NEST_ACCOUNTANT.updatePerformanceFee(0);
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_000_000, uint128(IERC20(NALPHA).totalSupply()));

        NestHubAccountant.AccountantState memory afterDrop = NEST_ACCOUNTANT.getAccountantState();
        (uint128 reserveAfterDrop,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();

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

        (uint128 reserveAfterGain,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertGt(reserveAfterGain, 0, "Reserve should exist after gain");

        uint96 netRefBeforeDisable = NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().clawbackReferenceRate;
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

        assertEq(
            NEST_ACCOUNTANT.getPerformanceFeeCheckpoint().clawbackReferenceRate,
            netRefBeforeDisable,
            "Clawback ref should be preserved (not overwritten with lastGrossRate)"
        );

        // 5. Mild drawdown above old net reference but below lastGrossRate —
        //    should NOT trigger clawback (would have without the fix)
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_042_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveAfterDip,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
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

        (uint128 totalReserve,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
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

        (uint128 reserveBefore,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertEq(reserveBefore, 1, "Reserve should be 1 wei");

        // Drawdown below HWM — clawback = min(shortfallBase, 1) = 1, but 1 * oneShare / totalShares rounds to 0
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_000_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveAfter,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
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

        (uint128 reserveAfterGain,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertGt(reserveAfterGain, 0, "Reserve should exist after gain");

        // First drawdown to 1_070_000 (below clawbackRef ~1_080_001) — partial clawback
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_070_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveAfterFirstDrawdown,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertLt(reserveAfterFirstDrawdown, reserveAfterGain, "First drawdown should reduce reserve");
        assertGt(reserveAfterFirstDrawdown, 0, "Should be partial clawback only");

        // Same rate again — clawbackRef was set to 1_070_000, so gross == ref → no clawback
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_070_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint128 reserveAfterRepeat,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
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
        (uint128 reserveAfterGain,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();

        // First drawdown to 1_090_000 (shortfall = 10_000/share)
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_090_000, uint128(IERC20(NALPHA).totalSupply()));
        (uint128 reserveAfterFirst,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        uint128 firstClawback = reserveAfterGain - reserveAfterFirst;

        // Further drawdown to 1_085_000 (incremental shortfall = 5_000/share)
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_085_000, uint128(IERC20(NALPHA).totalSupply()));
        (uint128 reserveAfterSecond,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
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
        (uint128 reserveAfterGain,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();

        // Drawdown to 1_090_000 — still above clawbackRef (~1_080_001) → no clawback
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_090_000, uint128(IERC20(NALPHA).totalSupply()));
        (uint128 reserveAfterDrawdown,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertEq(reserveAfterDrawdown, reserveAfterGain, "No clawback when gross > clawbackRef");

        // Recover to HWM — reference ratchets up to postFeeRate (≈ 1_100_000)
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_100_000, uint128(IERC20(NALPHA).totalSupply()));
        (uint128 reserveAfterRecovery,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
        assertEq(reserveAfterRecovery, reserveAfterGain, "Recovery should not change reserve");

        // Same drawdown to 1_090_000 — NOW below the ratcheted reference → clawback triggers
        vm.warp(block.timestamp + state.minimumUpdateDelayInSeconds + 1);
        NEST_ACCOUNTANT.updateExchangeRate(1_090_000, uint128(IERC20(NALPHA).totalSupply()));
        (uint128 reserveAfterSecondDrawdown,,) = NEST_ACCOUNTANT.getPerformanceFeeReserve();

        assertLt(reserveAfterSecondDrawdown, reserveAfterRecovery, "Clawback should trigger after reference reset");
    }

    // ======================= getPerformanceFeeReserve Tests =======================

    /// @dev Ensures getPerformanceFeeReserve returns zeros initially
    function test_getPerformanceFeeReserve_returnsZerosInitially() public view {
        (uint128 totalReserve, uint64 head, uint64 tail) = NEST_ACCOUNTANT.getPerformanceFeeReserve();
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

    /// @dev Ensures updateManagementFee accrues the elapsed old fee by reducing the net exchangeRate (only
    ///      down), while leaving lastGrossRate and the HWM untouched, and that the booked fee matches the
    ///      rate drop (lockstep, same as updateExchangeRate).
    function test_updateManagementFee_reducesNetRateNotGrossOrHWM() public {
        // Wide bounds so the multi-day accrual isn't clipped by allowedExchangeRateChange.
        address _impl = _deployNestAccountantImplementation();
        address _proxy =
            _deployNestAccountantProxyWithInitParams(_impl, IERC20(NALPHA).totalSupply(), 1_100_000, 900_000, 3600);
        MockNestAccountant accountant = MockNestAccountant(_proxy);

        NestHubAccountant.AccountantState memory stateBefore = accountant.getAccountantState();
        NestHubAccountant.PerformanceFeeCheckpoint memory checkpointBefore = accountant.getPerformanceFeeCheckpoint();
        uint96 lastGrossBefore = stateBefore.lastGrossRate;
        uint256 t0 = stateBefore.lastUpdateTimestamp;
        uint256 totalShares = IERC20(NALPHA).totalSupply();
        uint256 oneShare = 10 ** IERC20Metadata(NALPHA).decimals();

        vm.warp(t0 + 5 days);
        accountant.updateManagementFee(20_000, uint128(totalShares));

        NestHubAccountant.AccountantState memory stateAfter = accountant.getAccountantState();
        NestHubAccountant.PerformanceFeeCheckpoint memory checkpointAfter = accountant.getPerformanceFeeCheckpoint();

        // Net rate drops by the accrued management fee; gross rate and HWM are untouched.
        assertLt(stateAfter.exchangeRate, stateBefore.exchangeRate, "exchangeRate should drop by the accrued fee");
        assertEq(stateAfter.lastGrossRate, lastGrossBefore, "lastGrossRate should not change on fee update");
        assertEq(checkpointAfter.highWaterMark, checkpointBefore.highWaterMark, "HWM should not change on fee update");

        // Lockstep: the booked fee equals the realized rate haircut applied to all shares.
        uint256 rateDrop = uint256(stateBefore.exchangeRate) - uint256(stateAfter.exchangeRate);
        assertEq(
            stateAfter.feesOwedInBase, rateDrop * totalShares / oneShare, "booked fee must match the net-rate haircut"
        );
    }

    /// @dev updateManagementFee mutates the net exchangeRate when it accrues the elapsed old fee, so it must
    ///      emit ExchangeRateUpdated (same as updateExchangeRate) for off-chain rate trackers.
    function test_updateManagementFee_emitsExchangeRateUpdatedOnAccrual() public {
        // Wide bounds so the multi-day accrual isn't clipped by allowedExchangeRateChange.
        address _impl = _deployNestAccountantImplementation();
        address _proxy =
            _deployNestAccountantProxyWithInitParams(_impl, IERC20(NALPHA).totalSupply(), 1_100_000, 900_000, 3600);
        MockNestAccountant accountant = MockNestAccountant(_proxy);

        NestHubAccountant.AccountantState memory stateBefore = accountant.getAccountantState();
        uint256 t0 = stateBefore.lastUpdateTimestamp;
        uint96 oldRate = stateBefore.exchangeRate;
        uint128 supply = uint128(IERC20(NALPHA).totalSupply());

        vm.warp(t0 + 5 days);

        vm.recordLogs();
        accountant.updateManagementFee(20_000, supply);

        uint96 newRate = accountant.getAccountantState().exchangeRate;
        assertLt(newRate, oldRate, "accrual should drop the rate in this setup");

        // Exactly one ExchangeRateUpdated must fire, carrying (oldRate, newRate, currentTime).
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("ExchangeRateUpdated(uint96,uint96,uint64)");
        uint256 found = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != sig) continue;
            found++;
            (uint96 emittedOld, uint96 emittedNew, uint64 emittedTime) =
                abi.decode(logs[i].data, (uint96, uint96, uint64));
            assertEq(emittedOld, oldRate, "emitted oldRate");
            assertEq(emittedNew, newRate, "emitted newRate must match stored rate");
            assertEq(emittedTime, uint64(t0 + 5 days), "emitted currentTime");
        }
        assertEq(found, 1, "exactly one ExchangeRateUpdated expected");
    }

    /// @dev updateManagementFee that accrues nothing realized (sub-threshold, rate stays flat) must NOT emit
    ///      ExchangeRateUpdated — a no-op rate "change" would be a misleading event.
    function test_updateManagementFee_noExchangeRateEventWhenRateFlat() public {
        address _impl = _deployNestAccountantImplementation();
        address _proxy =
            _deployNestAccountantProxyWithInitParams(_impl, IERC20(NALPHA).totalSupply(), 1_100_000, 900_000, 3600);
        MockNestAccountant accountant = MockNestAccountant(_proxy);
        uint128 supply = uint128(IERC20(NALPHA).totalSupply());
        accountant.updateManagementFee(1000, supply); // 0.1%, dt == 0 so nothing accrues

        uint96 rate = accountant.getAccountantState().exchangeRate;
        uint256 t = accountant.getAccountantState().lastUpdateTimestamp + 3601; // one step past min delay
        vm.warp(t);

        vm.recordLogs();
        accountant.updateManagementFee(2000, supply);
        assertEq(accountant.getAccountantState().exchangeRate, rate, "rate must stay flat while sub-threshold");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("ExchangeRateUpdated(uint96,uint96,uint64)");
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != sig, "must not emit ExchangeRateUpdated when rate is flat");
        }
    }

    /// @dev The rate drop in updateManagementFee is subject to the same lower bound as updateExchangeRate.
    ///      A long elapsed interval accrues a haircut that breaches it, so the call reverts; calling
    ///      updateExchangeRate first (which drains the fee within bounds and re-checkpoints) unblocks it.
    function test_updateManagementFee_revertsWhenAccruedFeeBreachesLowerBound() public {
        NestHubAccountant.AccountantState memory s = NEST_ACCOUNTANT.getAccountantState();
        uint128 supply = uint128(IERC20(NALPHA).totalSupply());
        uint256 t0 = s.lastUpdateTimestamp;

        // One day of the 1% fee drops the rate ~27 units — far past the tight lower bound (~3 units).
        vm.warp(t0 + 1 days);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateManagementFee(20_000, supply);

        // Workaround: updateExchangeRate first (gross offsets the haircut so net stays within bounds) drains
        // the accrued fee and advances the checkpoint; the fee change then succeeds.
        NEST_ACCOUNTANT.updateExchangeRate(uint96(1_000_027), supply);
        NEST_ACCOUNTANT.updateManagementFee(20_000, supply);
        assertEq(NEST_ACCOUNTANT.getAccountantState().managementFee, 20_000, "fee should update after draining");
    }

    /// @dev The managementFeeReserve carry is a single shared accumulator: a sub-threshold accrual from
    ///      updateExchangeRate must be continued (not reset) by a following updateManagementFee.
    function test_managementFeeReserve_carryContinuesAcrossUpdateExchangeRateAndUpdateManagementFee() public {
        address _impl = _deployNestAccountantImplementation();
        address _proxy =
            _deployNestAccountantProxyWithInitParams(_impl, IERC20(NALPHA).totalSupply(), 1_100_000, 900_000, 3600);
        MockNestAccountant accountant = MockNestAccountant(_proxy);
        uint128 supply = uint128(IERC20(NALPHA).totalSupply());
        accountant.updateManagementFee(1000, supply); // 0.1%, dt == 0 so nothing accrues

        uint96 grossRate = 1_000_000;
        uint256 step = 3601;
        uint256 t = accountant.getAccountantState().lastUpdateTimestamp;

        // Sub-threshold updateExchangeRate: reserve accrues, nothing realized.
        t += step;
        vm.warp(t);
        accountant.updateExchangeRate(grossRate, supply);
        uint256 r1 = accountant.managementFeeCarryForTesting();
        assertGt(r1, 0, "reserve should accrue on updateExchangeRate");
        assertEq(accountant.getAccountantState().exchangeRate, grossRate, "rate flat while sub-threshold");
        assertEq(accountant.getAccountantState().feesOwedInBase, 0, "no fee yet");

        // updateManagementFee over an equal step must continue from r1 (same fee, rate, supply => equal
        // increment), so the reserve doubles. If it reset, it would equal one increment, not two.
        t += step;
        vm.warp(t);
        accountant.updateManagementFee(2000, supply);
        assertEq(accountant.managementFeeCarryForTesting(), 2 * r1, "reserve must continue across the two paths");
        assertEq(accountant.getAccountantState().exchangeRate, grossRate, "rate still flat while sub-threshold");
        assertEq(accountant.getAccountantState().feesOwedInBase, 0, "still no fee");
    }

    /// @dev updateManagementFee routes through the shared accrual, so a short, low-fee interval is carried
    ///      into the reserve instead of being truncated to zero (the bug the standalone path used to have).
    function test_updateManagementFee_subThresholdAccruesToReserveNotZero() public {
        address _impl = _deployNestAccountantImplementation();
        address _proxy =
            _deployNestAccountantProxyWithInitParams(_impl, IERC20(NALPHA).totalSupply(), 1_100_000, 900_000, 3600);
        MockNestAccountant accountant = MockNestAccountant(_proxy);
        uint128 supply = uint128(IERC20(NALPHA).totalSupply());
        accountant.updateManagementFee(1000, supply); // 0.1%, dt == 0

        NestHubAccountant.AccountantState memory before = accountant.getAccountantState();
        vm.warp(uint256(before.lastUpdateTimestamp) + 3601);
        accountant.updateManagementFee(2000, supply);

        NestHubAccountant.AccountantState memory s = accountant.getAccountantState();
        assertGt(accountant.managementFeeCarryForTesting(), 0, "short interval must carry, not truncate to zero");
        assertEq(s.exchangeRate, before.exchangeRate, "rate unchanged while sub-unit");
        assertEq(s.feesOwedInBase, 0, "no fee booked while sub-unit");
    }

    /// @dev Cadence invariance: many small updates accrue the same TOTAL fee as one big update over the same
    ///      elapsed time. feesOwedInBase is the cumulative measure (exchangeRate is not — each update resets it
    ///      to gross minus that interval's fee). Uses a round supply (multiple of oneShare) so the base
    ///      conversion is exact, making the carry's losslessness observable with assertEq.
    function test_managementFee_totalFeeIndependentOfUpdateCadence() public {
        uint256 supply = 1_000_000 * 1e6; // round multiple of oneShare (1e6) => exact base conversion
        MockNestAccountant a = _deployRoundSupplyAccountant(supply);
        MockNestAccountant b = _deployRoundSupplyAccountant(supply);

        uint96 grossRate = 1_000_000;
        uint256 step = 6 hours;
        uint256 nSteps = 40; // 10 days total

        // A: many small updates.
        uint256 ta = a.getAccountantState().lastUpdateTimestamp;
        for (uint256 i = 0; i < nSteps; i++) {
            ta += step;
            vm.warp(ta);
            a.updateExchangeRate(grossRate, uint128(supply));
        }

        // B: one big update over the same elapsed time.
        uint256 tb = b.getAccountantState().lastUpdateTimestamp;
        vm.warp(tb + nSteps * step);
        b.updateExchangeRate(grossRate, uint128(supply));

        NestHubAccountant.AccountantState memory sa = a.getAccountantState();
        NestHubAccountant.AccountantState memory sb = b.getAccountantState();
        assertEq(sa.feesOwedInBase, sb.feesOwedInBase, "total fee must be independent of update cadence");
        assertGt(sa.feesOwedInBase, 0, "sanity: some fee was actually accrued");
    }

    // ======================= waiveFees Tests =======================

    /// @dev Deploys a fresh wide-bounds accountant and accrues management fees over a 5-day window.
    ///      Returns the total accrued liability (realized fees plus management-fee carry).
    function _deployAccountantWithAccruedFees() internal returns (MockNestAccountant accountant, uint128 owed) {
        address _impl = _deployNestAccountantImplementation();
        address _proxy =
            _deployNestAccountantProxyWithInitParams(_impl, IERC20(NALPHA).totalSupply(), 1_100_000, 900_000, 3600);
        accountant = MockNestAccountant(_proxy);

        uint256 t0 = accountant.getAccountantState().lastUpdateTimestamp;
        vm.warp(t0 + 5 days);
        accountant.updateExchangeRate(1_000_000, uint128(IERC20(NALPHA).totalSupply()));

        (uint256 _feesOwed, uint256 _carry,) = accountant.feeLiabilities();
        owed = uint128(_feesOwed + _carry);
        assertGt(owed, 0, "fees should accrue over the elapsed window");
    }

    /// @dev Ensures waiveFees reduces the total accrued liability by the requested amount and emits FeesWaived
    function test_waiveFees_partial() public {
        (MockNestAccountant accountant, uint128 owed) = _deployAccountantWithAccruedFees();
        uint128 amount = owed / 3;

        vm.expectEmit(false, false, false, true);
        emit NestHubAccountant.FeesWaived(amount, owed - amount);
        accountant.waiveFees(amount);

        (uint256 _feesOwed, uint256 _carry,) = accountant.feeLiabilities();
        assertEq(_feesOwed + _carry, owed - amount, "remainder should stay owed");
    }

    /// @dev Ensures waiveFees can clear the full outstanding liability (realized + carry)
    function test_waiveFees_full() public {
        (MockNestAccountant accountant, uint128 owed) = _deployAccountantWithAccruedFees();

        vm.expectEmit(false, false, false, true);
        emit NestHubAccountant.FeesWaived(owed, 0);
        accountant.waiveFees(owed);

        (uint256 _feesOwed, uint256 _carry,) = accountant.feeLiabilities();
        assertEq(_feesOwed + _carry, 0, "all fees should be waived");
    }

    /// @dev Ensures waiveFees reverts when the amount exceeds the outstanding balance
    function test_waiveFees_revertsWhenAmountExceedsOwed() public {
        (MockNestAccountant accountant, uint128 owed) = _deployAccountantWithAccruedFees();
        vm.expectRevert(Errors.InsufficientBalance.selector);
        accountant.waiveFees(owed + 1);
    }

    /// @dev Ensures waiveFees reverts when no fees are owed (fresh accountant: zero realized + zero carry)
    function test_waiveFees_revertsWhenNoFeesOwed() public {
        address _impl = _deployNestAccountantImplementation();
        address _proxy =
            _deployNestAccountantProxyWithInitParams(_impl, IERC20(NALPHA).totalSupply(), 1_100_000, 900_000, 3600);
        // Warm the freshly-deployed proxy on the active fork before expectRevert; otherwise forge's
        // expectRevert backend can't resolve the contract when a global --fork-url makes ethereum non-default.
        MockNestAccountant(_proxy).getAccountantState();
        vm.expectRevert(Errors.InsufficientBalance.selector);
        MockNestAccountant(_proxy).waiveFees(1);
    }

    /// @dev Ensures waiveFees is gated by auth
    function test_waiveFees_revertsForUnauthorized() public {
        (MockNestAccountant accountant, uint128 owed) = _deployAccountantWithAccruedFees();
        vm.prank(address(1));
        _expectAuthUnauthorized();
        accountant.waiveFees(owed);
    }

    /// @dev Replays the 2026-06 nTBILL incident: the off-chain updater passed a global share supply
    ///      that summed an 18-decimal raw OFT supply into the 6-decimal aggregate (~1e6x inflated).
    ///      The first bad update poisons the checkpoint but accrues ~0 fees (the haircut floors to
    ///      zero against the inflated denominator). The second bad update applies the full per-share
    ///      haircut to the inflated supply, exploding feesOwedInBase past real TVL while the
    ///      published exchange rate only drops by the normal per-share haircut.
    function test_waiveFees_incidentReplay_inflatedSupplyExplodesFeesNotRate() public {
        address _impl = _deployNestAccountantImplementation();
        uint256 _realSupply = IERC20(NALPHA).totalSupply();
        address _proxy = _deployNestAccountantProxyWithInitParams(_impl, _realSupply, 1_100_000, 900_000, 3600);
        MockNestAccountant accountant = MockNestAccountant(_proxy);

        uint128 _inflatedSupply = uint128(_realSupply * 1e6);
        uint96 _rate = accountant.getAccountantState().exchangeRate;
        uint256 t0 = accountant.getAccountantState().lastUpdateTimestamp;

        // First bad update: checkpoint poisoned, no fees accrued yet
        vm.warp(t0 + 12 hours);
        accountant.updateExchangeRate(_rate, _inflatedSupply);

        NestHubAccountant.AccountantState memory s = accountant.getAccountantState();
        assertEq(s.feesOwedInBase, 0, "first bad update should accrue ~0 fees");
        assertEq(s.totalSharesLastUpdate, _inflatedSupply, "checkpoint stores inflated supply");
        assertEq(s.exchangeRate, _rate, "rate unaffected by first bad update");

        // Second bad update: full per-share haircut applied to the inflated supply
        vm.warp(t0 + 24 hours);
        accountant.updateExchangeRate(_rate, _inflatedSupply);

        s = accountant.getAccountantState();
        uint256 _haircut = uint256(_rate) * 10_000 * 12 hours / (1e6 * 365 days);
        assertEq(s.feesOwedInBase, _haircut * _inflatedSupply / 1e6, "fees scale with inflated supply");
        assertGt(s.feesOwedInBase, _realSupply * _rate / 1e6, "fees owed exceed real TVL");
        assertEq(s.exchangeRate, _rate - _haircut, "rate haircut stays per-share sized");
    }

    /// @dev Full incident cleanup path: explode fees, waive them, then verify the next update with
    ///      the corrected supply accrues only the normal magnitude and self-heals the checkpoint
    function test_waiveFees_incidentReplay_waiveThenCleanAccrual() public {
        address _impl = _deployNestAccountantImplementation();
        uint256 _realSupply = IERC20(NALPHA).totalSupply();
        address _proxy = _deployNestAccountantProxyWithInitParams(_impl, _realSupply, 1_100_000, 900_000, 3600);
        MockNestAccountant accountant = MockNestAccountant(_proxy);

        uint128 _inflatedSupply = uint128(_realSupply * 1e6);
        uint96 _rate = accountant.getAccountantState().exchangeRate;
        uint256 t0 = accountant.getAccountantState().lastUpdateTimestamp;

        vm.warp(t0 + 12 hours);
        accountant.updateExchangeRate(_rate, _inflatedSupply);
        vm.warp(t0 + 24 hours);
        accountant.updateExchangeRate(_rate, _inflatedSupply);

        (uint256 _feesOwed, uint256 _carry,) = accountant.feeLiabilities();
        uint256 _exploded = _feesOwed + _carry;
        assertGt(_exploded, 0, "fees should have exploded");

        vm.expectEmit(false, false, false, true);
        emit NestHubAccountant.FeesWaived(uint128(_exploded), 0);
        accountant.waiveFees(uint128(_exploded));
        (uint256 _feesOwedAfter, uint256 _carryAfter,) = accountant.feeLiabilities();
        assertEq(_feesOwedAfter + _carryAfter, 0, "fees fully waived");

        // Next update with the corrected supply: min(inflatedCheckpoint, correct) = correct,
        // so accrual self-heals to the normal magnitude
        uint96 _netRate = accountant.getAccountantState().exchangeRate;
        vm.warp(t0 + 36 hours);
        accountant.updateExchangeRate(_netRate, uint128(_realSupply));

        NestHubAccountant.AccountantState memory s = accountant.getAccountantState();
        uint256 _haircut = uint256(_netRate) * 10_000 * 12 hours / (1e6 * 365 days);
        assertEq(s.feesOwedInBase, _haircut * _realSupply / 1e6, "post-waive accrual is normal magnitude");
        assertEq(s.totalSharesLastUpdate, _realSupply, "checkpoint self-heals to correct supply");
    }

    /// @dev waiveReserve reduces totalReserve by the requested amount and emits ReserveWaived
    function test_waiveReserve_partial() public {
        (MockNestAccountant accountant,) = _deployAccountantWithAccruedFees();
        accountant.setReserveForTesting(6_000_000, uint64(block.timestamp));

        vm.expectEmit(false, false, false, true);
        emit NestHubAccountant.ReserveWaived(2_000_000, 4_000_000);
        accountant.waiveReserve(2_000_000);

        (,, uint256 reserve) = accountant.feeLiabilities();
        assertEq(reserve, 4_000_000, "reserve reduced by amount");
    }

    /// @dev waiveReserve can clear the full reserve
    function test_waiveReserve_full() public {
        (MockNestAccountant accountant,) = _deployAccountantWithAccruedFees();
        accountant.setReserveForTesting(6_000_000, uint64(block.timestamp));

        vm.expectEmit(false, false, false, true);
        emit NestHubAccountant.ReserveWaived(6_000_000, 0);
        accountant.waiveReserve(6_000_000);

        (,, uint256 reserve) = accountant.feeLiabilities();
        assertEq(reserve, 0, "reserve fully cleared");
    }

    /// @dev waiveReserve reverts when the amount exceeds the reserve
    function test_waiveReserve_revertsWhenAmountExceedsReserve() public {
        (MockNestAccountant accountant,) = _deployAccountantWithAccruedFees();
        accountant.setReserveForTesting(6_000_000, uint64(block.timestamp));
        vm.expectRevert(Errors.InsufficientBalance.selector);
        accountant.waiveReserve(6_000_001);
    }

    /// @dev waiveReserve is gated by auth
    function test_waiveReserve_revertsForUnauthorized() public {
        (MockNestAccountant accountant,) = _deployAccountantWithAccruedFees();
        accountant.setReserveForTesting(6_000_000, uint64(block.timestamp));
        vm.prank(address(1));
        _expectAuthUnauthorized();
        accountant.waiveReserve(6_000_000);
    }

    /// @dev A bad total-supply feed can corrupt all three liability buckets; waiveFees + waiveReserve
    ///      must be able to zero every one (feesOwedInBase, managementFeeCarry, totalReserve).
    function test_waiveFees_totalRemovalAcrossAllBuckets() public {
        (MockNestAccountant accountant, uint128 owed) = _deployAccountantWithAccruedFees();
        // Seed a reserve as if a bad-feed performance-fee holdback had also accrued.
        accountant.setReserveForTesting(5_000_000, uint64(block.timestamp));

        (uint256 feesOwed, uint256 carry, uint256 reserve) = accountant.feeLiabilities();
        assertGt(feesOwed + carry, 0, "accrued liability present");
        assertEq(reserve, 5_000_000, "reserve present");

        accountant.waiveFees(owed); // owed == feesOwed + carry
        accountant.waiveReserve(uint128(reserve));

        (feesOwed, carry, reserve) = accountant.feeLiabilities();
        assertEq(feesOwed, 0, "feesOwedInBase cleared");
        assertEq(carry, 0, "managementFeeCarry cleared");
        assertEq(reserve, 0, "totalReserve cleared");
    }

    /// @dev Deploys an accountant whose share has the given round supply (for exact-arithmetic tests).
    function _deployRoundSupplyAccountant(uint256 _supply) internal returns (MockNestAccountant) {
        TinyShareToken share = new TinyShareToken(6, _supply);
        MockNestAccountant impl = new MockNestAccountant(USDC, address(share));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(this),
            abi.encodeCall(
                NestHubAccountant.initialize,
                (
                    _supply, // totalSharesLastUpdate
                    address(this), // payoutAddress
                    uint96(1e6), // startingExchangeRate
                    uint32(1_100_000), // upper
                    uint32(900_000), // lower
                    uint32(1), // minimumUpdateDelayInSeconds
                    uint32(1000), // managementFee = 0.1%
                    uint32(0), // performanceFee
                    uint32(0), // hurdleRate
                    uint32(0), // holdbackRate
                    uint32(0), // crystallizationWindow
                    uint32(0), // epochsPerWindow
                    address(this) // owner
                )
            )
        );
        return MockNestAccountant(address(proxy));
    }
}

/// @dev Minimal share stub exposing only the `decimals()` and `totalSupply()` the accountant reads, so a
///      sub-one-share supply (totalSupply < 10**decimals) can be exercised.
contract TinyShareToken {
    uint8 public immutable decimals;
    uint256 public totalSupply;

    constructor(uint8 _decimals, uint256 _supply) {
        decimals = _decimals;
        totalSupply = _supply;
    }
}
