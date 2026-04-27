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

// interfaces
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// types
import {Errors} from "contracts/types/Errors.sol";

contract NestAccountantForkTest is Constants, Test {
    MockNestAccountant internal immutable NEST_ACCOUNTANT;

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
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
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
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        NEST_ACCOUNTANT.unpause();
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

    /// @dev Ensures invalid timing reverts while unpaused and does not double-charge later updates.
    function test_updateExchangeRate_invalidDueToTimingDoesNotDoubleChargeOnValidUpdate() public {
        NestAccountant.AccountantState memory initialState = NEST_ACCOUNTANT.getAccountantState();
        uint256 initialExchangeRate = initialState.exchangeRate;
        uint64 minimumDelay = initialState.minimumUpdateDelayInSeconds;

        uint256 earlyTimeDelta = minimumDelay / 2;
        vm.warp(block.timestamp + earlyTimeDelta);
        vm.expectRevert(Errors.MinimumUpdateDelayNotPassed.selector);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialExchangeRate));

        NestAccountant.AccountantState memory stateAfterEarlyAttempt = NEST_ACCOUNTANT.getAccountantState();
        assertEq(stateAfterEarlyAttempt.feesOwedInBase, initialState.feesOwedInBase, "Reverted call should not accrue");
        assertEq(
            stateAfterEarlyAttempt.lastUpdateTimestamp,
            initialState.lastUpdateTimestamp,
            "Reverted call should not checkpoint"
        );

        uint256 waitTime = minimumDelay;
        vm.warp(block.timestamp + waitTime);
        NEST_ACCOUNTANT.updateExchangeRate(uint96(initialExchangeRate + 1));

        NestAccountant.AccountantState memory stateAfterValid = NEST_ACCOUNTANT.getAccountantState();
        uint256 expectedFees = calculateExpectedFees(
            initialState.totalSharesLastUpdate,
            initialExchangeRate,
            initialState.managementFee,
            earlyTimeDelta + waitTime
        );

        assertTrue(
            stateAfterValid.feesOwedInBase >= expectedFees - 1 && stateAfterValid.feesOwedInBase <= expectedFees + 1,
            "Only elapsed time since prior successful checkpoint should be charged"
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
        uint64 minimumDelay = initialState.minimumUpdateDelayInSeconds;

        NEST_ACCOUNTANT.pause();
        NestAccountant.AccountantState memory pausedState = NEST_ACCOUNTANT.getAccountantState();
        uint64 pauseTimestamp = pausedState.lastUpdateTimestamp;

        vm.warp(pauseTimestamp + minimumDelay + 1);
        uint96 outOfBoundsRate = uint96(initialState.exchangeRate + 50000);
        vm.expectRevert(Errors.RateOutOfBounds.selector);
        NEST_ACCOUNTANT.updateExchangeRate(outOfBoundsRate);

        NestAccountant.AccountantState memory stateAfterPausedUpdate = NEST_ACCOUNTANT.getAccountantState();
        assertTrue(stateAfterPausedUpdate.isPaused, "Should remain paused");
        assertEq(
            stateAfterPausedUpdate.exchangeRate, pausedState.exchangeRate, "Rate should not change on reverted update"
        );
        assertEq(
            stateAfterPausedUpdate.lastUpdateTimestamp, pauseTimestamp, "Timestamp should not update on reverted update"
        );
        assertEq(
            stateAfterPausedUpdate.feesOwedInBase,
            pausedState.feesOwedInBase,
            "Fees should not accrue on reverted update"
        );
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
}
