// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// contracts
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRateProvider} from "contracts/interfaces/IRateProvider.sol";

// libraries
import {NestVaultAccountingLogic} from "contracts/libraries/nest-vault/NestVaultAccountingLogic.sol";
import {Errors} from "contracts/types/Errors.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title  NestHubAccountant
/// @author plumenetwork
/// @notice Provides exchange-rate tracking, fee accounting (management + performance), and rate-provider integration for NestVault.
/// @dev    Handles exchange-rate updates with safety bounds, HWM-based performance fees with optional
///         hurdle rate and holdback/clawback reserve, pausing logic, and cross-asset rate conversions
contract NestHubAccountant is Initializable, AuthUpgradeable {
    using NestVaultAccountingLogic for uint256;
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////
                            STORAGE STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @param payoutAddress                  address the address `claimFees` sends fees to
    /// @param feesOwedInBase                 uint128 total pending fees owed in terms of base
    /// @param totalSharesLastUpdate          uint128 total amount of shares the last exchange rate update
    /// @param exchangeRate                   uint96  the current net exchange rate in terms of base
    /// @param allowedExchangeRateChangeUpper uint32  the max allowed change to exchange rate from an update
    /// @param allowedExchangeRateChangeLower uint32  the min allowed change to exchange rate from an update
    /// @param lastUpdateTimestamp            uint64  the block timestamp of the last exchange rate update
    /// @param isPaused                       bool    whether or not this contract is paused
    /// @param minimumUpdateDelayInSeconds    uint32  the minimum amount of time that must pass between exchange rate updates
    /// @param managementFee                  uint32  annualized management fee (1e6 = 100%)
    /// @param highWaterMark                  uint96  highest gross rate ever recorded
    /// @param lastGrossRate                  uint96  gross market rate from the most recent update; used as the management-fee discount basis
    /// @param clawbackReferenceRate          uint96  clawback baseline checkpoint; seeded from the stored post-fee rate on gains and recoveries, and checkpointed to the current gross rate after clawbacks
    /// @param hwmLastUpdateTimestamp         uint64  timestamp when the high-water mark was last set or reset
    struct AccountantState {
        address payoutAddress;
        uint128 feesOwedInBase;
        uint128 totalSharesLastUpdate;
        uint96 exchangeRate;
        uint32 allowedExchangeRateChangeUpper;
        uint32 allowedExchangeRateChangeLower;
        uint64 lastUpdateTimestamp;
        bool isPaused;
        uint32 minimumUpdateDelayInSeconds;
        uint32 managementFee;
        uint96 highWaterMark;
        uint96 lastGrossRate;
        uint96 clawbackReferenceRate;
        uint64 hwmLastUpdateTimestamp;
    }

    /// @param performanceFee         uint32  performance fee on gains above HWM (1e6 = 100%)
    /// @param hurdleRate             uint32  annualized minimum return before perf fee applies (0 = disabled)
    /// @param holdbackRate           uint32  fraction of perf fee held in reserve (0 = disabled, 1e6 = 100%)
    /// @param crystallizationWindow  uint32  seconds before holdback reserve becomes claimable (0 = immediate)
    /// @param epochsPerWindow        uint32  number of epochs per crystallization window for reserve batching
    struct PerformanceFeeConfig {
        uint32 performanceFee;
        uint32 hurdleRate;
        uint32 holdbackRate;
        uint32 crystallizationWindow;
        uint32 epochsPerWindow;
    }

    /// @param isPeggedToBase whether or not the asset is 1:1 with the base asset
    /// @param rateProvider the rate provider for this asset if `isPeggedToBase` is false
    struct RateProviderData {
        bool isPeggedToBase;
        IRateProvider rateProvider;
    }

    /// @param amount    uint128 holdback fee amount in base terms
    /// @param timestamp uint64  when this batch was created
    struct ReserveBatch {
        uint128 amount;
        uint64 timestamp;
    }

    /// @param batches      mapping  epoch-indexed reserve batches
    /// @param batchHead    uint64   index of the oldest active batch
    /// @param batchTail    uint64   index of the next batch to write
    /// @param totalReserve uint128  sum of all active batch amounts (cache)
    struct ReserveState {
        mapping(uint256 => ReserveBatch) batches;
        uint64 batchHead;
        uint64 batchTail;
        uint128 totalReserve;
    }

    /// @notice Storage struct for NestHubAccountant
    /// @dev    Used by library functions that need access to full storage
    struct NestAccountantStorage {
        AccountantState accountantState;
        mapping(ERC20 => RateProviderData) rateProviderData;
        uint256 totalPendingShares;
        PerformanceFeeConfig performanceFeeConfig;
        ReserveState reserveState;
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS AND IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the base deposit asset used for rate calculations
    /// @dev    This is an immutable variable that stores the address of the base asset
    ERC20 public immutable base;

    /// @notice The decimals rates are provided in
    /// @dev    Specifies the reference decimal precision used internally to scale and normalize rate values
    uint8 public immutable baseDecimals;

    /// @dev    This is an immutable variable that stores the address of the share token to honour ERC7575 specs
    address internal immutable SHARE;

    /// @dev This constant is used as a divisor in various mathematical calculations
    ///      throughout the contract to achieve precise percentages and ratios
    uint256 internal constant DENOMINATOR = 1e6;

    /// @dev This constant is maximum cap on management fee
    uint256 internal constant MANAGEMENT_FEE_CAP = 0.2e6; // 20%

    /// @dev Maximum cap on performance fee
    uint256 internal constant PERFORMANCE_FEE_CAP = 0.5e6; // 50%

    /// @dev Maximum cap on hurdle rate
    uint256 internal constant HURDLE_RATE_CAP = 0.3e6; // 30% annualized

    /// @dev Maximum cap on crystallization window
    uint256 internal constant CRYSTALLIZATION_WINDOW_CAP = 365 days;

    /// @dev Maximum cap on epochs per window
    uint256 internal constant EPOCHS_PER_WINDOW_CAP = 52;

    /// @dev This constant stores the duration of 1 year in seconds
    uint256 internal constant ONE_YEAR = 365 days;

    /// @dev This constant stores maximum allowed update delay
    uint256 internal constant UPDATE_DELAY_CAP = 14 days;

    // keccak256(abi.encode(uint256(keccak256("plumenetwork.storage.NestAccountant")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NestAccountantStorageLocation =
        0xb378036f9633fc394c3579301b38ac88997c2589544525e367cd650f76eaa300;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when protocol fees are claimed
    /// @param  feeAsset address The asset in which the fees were denominated
    /// @param  amount   uint256 The amount of fees claimed
    event FeesClaimed(address indexed feeAsset, uint256 amount);

    /// @notice Emitted when global pending shares are updated
    /// @param  oldPendingShares uint256 The previous total pending shares
    /// @param  newPendingShares uint256 The new total pending shares
    event TotalPendingSharesUpdated(uint256 oldPendingShares, uint256 newPendingShares);

    /// @notice Emitted when the contract is paused
    event Paused();

    /// @notice Emitted when the contract is unpaused
    event Unpaused();

    /// @notice Emitted when the global execution delay is updated
    /// @param  oldDelay uint32 The previous delay value
    /// @param  newDelay uint32 The newly set delay value
    event DelayInSecondsUpdated(uint32 oldDelay, uint32 newDelay);

    /// @notice Emitted when the upper price/rate bound is updated
    /// @param  oldBound uint32 The previous upper bound value
    /// @param  newBound uint32 The newly set upper bound value
    event UpperBoundUpdated(uint32 oldBound, uint32 newBound);

    /// @notice Emitted when the lower price/rate bound is updated
    /// @param  oldBound uint32 The previous lower bound value
    /// @param  newBound uint32 The newly set lower bound value
    event LowerBoundUpdated(uint32 oldBound, uint32 newBound);

    /// @notice Emitted when the management fee rate is updated
    /// @param  oldFee uint32 The previous management fee
    /// @param  newFee uint32 The newly set management fee
    event ManagementFeeUpdated(uint32 oldFee, uint32 newFee);

    /// @notice Emitted when the performance fee rate is updated
    /// @param  oldFee uint32 The previous performance fee
    /// @param  newFee uint32 The newly set performance fee
    event PerformanceFeeUpdated(uint32 oldFee, uint32 newFee);

    /// @notice Emitted when the high-water mark is updated
    /// @param  oldHWM uint96 The previous high-water mark
    /// @param  newHWM uint96 The newly set high-water mark
    event HighWaterMarkUpdated(uint96 oldHWM, uint96 newHWM);

    /// @notice Emitted when the hurdle rate is updated
    /// @param  oldRate uint32 The previous hurdle rate
    /// @param  newRate uint32 The newly set hurdle rate
    event HurdleRateUpdated(uint32 oldRate, uint32 newRate);

    /// @notice Emitted when the performance-fee holdback rate is updated
    /// @param  oldRate uint32 The previous holdback rate
    /// @param  newRate uint32 The newly set holdback rate
    event HoldbackRateUpdated(uint32 oldRate, uint32 newRate);

    /// @notice Emitted when the crystallization window is updated
    /// @param  oldWindow uint32 The previous crystallization window
    /// @param  newWindow uint32 The newly set crystallization window
    event CrystallizationWindowUpdated(uint32 oldWindow, uint32 newWindow);

    /// @notice Emitted when the number of reserve epochs per window is updated
    /// @param  oldEpochs uint32 The previous epochs-per-window value
    /// @param  newEpochs uint32 The newly set epochs-per-window value
    event EpochsPerWindowUpdated(uint32 oldEpochs, uint32 newEpochs);

    /// @notice Emitted when the payout address is changed
    /// @param  oldPayout address The previous payout address
    /// @param  newPayout address The new payout address
    event PayoutAddressUpdated(address oldPayout, address newPayout);

    /// @notice Emitted when the rate provider for an asset is updated
    /// @param  asset        address The asset for which the rate provider is updated
    /// @param  isPegged     bool    Whether the asset is treated as pegged (uses fixed rate)
    /// @param  rateProvider address The newly assigned rate provider address
    event RateProviderUpdated(address asset, bool isPegged, address rateProvider);

    /// @notice Emitted when the exchange rate is updated
    /// @param  oldRate     uint96 The previous exchange rate
    /// @param  newRate     uint96 The newly set exchange rate
    /// @param  currentTime uint64 The timestamp when the update occurred
    event ExchangeRateUpdated(uint96 oldRate, uint96 newRate, uint64 currentTime);

    /// @notice Emitted when the exchange rate is updated is paused
    /// @param  oldRate     uint96 The previous exchange rate
    /// @param  newRate     uint96 The newly set exchange rate
    /// @param  currentTime uint64 The timestamp when the update occurred

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with the given base asset
    /// @param  _base  address The address of the base asset used for rate calculations
    /// @param  _share address The address of the share token associated with this accountant
    constructor(address _base, address _share) {
        if (_base == address(0) || _share == address(0)) revert Errors.ZeroAddress();
        base = ERC20(_base);
        baseDecimals = ERC20(_base).decimals();
        SHARE = _share;
        _disableInitializers();
    }

    /// @dev    Internal function to access the contract's NestHubAccountant slot
    /// @return $ NestAccountantStorage A reference to the NestAccountantStorage struct for reading/writing exchange rate
    function _getNestAccountantStorage() private pure returns (NestAccountantStorage storage $) {
        assembly {
            $.slot := NestAccountantStorageLocation
        }
    }

    /// @notice Sets up the initial state of the NestHubAccountant contract
    /// @dev    This function is called only during contract initialization
    /// @param  _totalSharesLastUpdate          uint256 The last recorded total shares at initialization
    /// @param  _payoutAddress                  address The address to which management fees and payouts will be sent
    /// @param  _startingExchangeRate           uint96  The initial exchange rate used for share-to-asset conversions
    /// @param  _allowedExchangeRateChangeUpper uint32  The maximum allowed increase in exchange rate per update (in basis points where 1e6 = 100%)
    /// @param  _allowedExchangeRateChangeLower uint32  The maximum allowed decrease in exchange rate per update (in basis points where 1e6 = 100%)
    /// @param  _minimumUpdateDelayInSeconds    uint32  Minimum delay between successive exchange rate updates
    /// @param  _managementFee                  uint32  The management fee percentage applied to the total assets (in basis points where 1e6 = 100%)
    /// @param  _performanceFee                 uint32  Performance fee on gains above HWM (1e6 = 100%, 0 = disabled)
    /// @param  _hurdleRate                     uint32  Annualized hurdle rate (1e6 = 100%, 0 = disabled)
    /// @param  _holdbackRate                   uint32  Fraction of perf fee held in reserve (1e6 = 100%, 0 = disabled)
    /// @param  _crystallizationWindow          uint32  Seconds before holdback becomes claimable (0 = immediate)
    /// @param  _epochsPerWindow                uint32  Number of reserve epochs per crystallization window (0 = disabled)
    /// @param  _owner                          address The address of the owner of the accountant
    function initialize(
        uint256 _totalSharesLastUpdate,
        address _payoutAddress,
        uint96 _startingExchangeRate,
        uint32 _allowedExchangeRateChangeUpper,
        uint32 _allowedExchangeRateChangeLower,
        uint32 _minimumUpdateDelayInSeconds,
        uint32 _managementFee,
        uint32 _performanceFee,
        uint32 _hurdleRate,
        uint32 _holdbackRate,
        uint32 _crystallizationWindow,
        uint32 _epochsPerWindow,
        address _owner
    ) external virtual initializer {
        if (_startingExchangeRate == 0) revert Errors.InvalidRate();
        if (_owner == address(0)) revert Errors.ZeroAddress();

        AccountantState storage state = _getNestAccountantStorage().accountantState;
        state.lastUpdateTimestamp = uint64(block.timestamp);
        state.totalSharesLastUpdate = _totalSharesLastUpdate.toUint128();
        state.exchangeRate = _startingExchangeRate;
        state.highWaterMark = _startingExchangeRate;
        state.hwmLastUpdateTimestamp = uint64(block.timestamp);
        state.lastGrossRate = _startingExchangeRate;
        state.clawbackReferenceRate = _startingExchangeRate;

        _setPayoutAddress(_payoutAddress);
        _setAllowedExchangeRateChangeUpper(_allowedExchangeRateChangeUpper);
        _setAllowedExchangeRateChangeLower(_allowedExchangeRateChangeLower);
        _setMinimumUpdateDelayInSeconds(_minimumUpdateDelayInSeconds);

        _setManagementFee(_managementFee);
        _setPerformanceFee(_performanceFee);
        _setHurdleRate(_hurdleRate);
        _setHoldbackRate(_holdbackRate);
        _setCrystallizationWindow(_crystallizationWindow);
        _setEpochsPerWindow(_epochsPerWindow);

        __Auth_init(_owner, Authority(address(0)));
    }

    /// @notice Updates the exchange rate from the gross market rate of the underlying investment strategy
    /// @dev    Invalid updates revert if too early or outside the configured bounds. Successful updates
    ///         accrue elapsed management and performance fees, then store the post-fee net exchange rate.
    ///         Callable by authorized accounts.
    /// @param  _newExchangeRate   uint96  The gross market rate of the underlying investment strategy
    /// @param  _totalShareSupply  uint128 The global total share supply across all chains
    function updateExchangeRate(uint96 _newExchangeRate, uint128 _totalShareSupply) external requiresAuth {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        AccountantState storage state = $.accountantState;
        uint64 _currentTime = uint64(block.timestamp);
        uint256 _currentExchangeRate = state.exchangeRate;
        uint256 _totalShares = uint256(_totalShareSupply);
        if (_totalShareSupply < IERC20(SHARE).totalSupply()) revert Errors.TotalSupplyBelowLocal();
        uint256 _oneShare = 10 ** ERC20(SHARE).decimals();

        if (_currentTime < state.lastUpdateTimestamp + state.minimumUpdateDelayInSeconds) {
            revert Errors.MinimumUpdateDelayNotPassed();
        }

        _crystallizeMaturedBatches();

        uint256 _postManagementFeeRate = _accrueManagementFees(_newExchangeRate, _totalShares, _oneShare);

        uint256 _postFeeRate =
            _accruePerformanceFees(_newExchangeRate, _postManagementFeeRate, _totalShares, _oneShare, _currentTime);

        if (
            _postFeeRate > _currentExchangeRate.mulDivDown(state.allowedExchangeRateChangeUpper, DENOMINATOR)
                || _postFeeRate < _currentExchangeRate.mulDivDown(state.allowedExchangeRateChangeLower, DENOMINATOR)
        ) {
            revert Errors.RateOutOfBounds();
        }

        state.lastUpdateTimestamp = _currentTime;
        state.totalSharesLastUpdate = _totalShares.toUint128();
        state.lastGrossRate = uint96(_newExchangeRate);
        state.exchangeRate = _postFeeRate.toUint96();

        emit ExchangeRateUpdated(uint96(_currentExchangeRate), _postFeeRate.toUint96(), _currentTime);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claims accrued management fees owed to the vault
    /// @dev    This function must be called by the NestShare. Fees are accrued in the base asset
    ///         whenever the exchange rate is updated and can optionally be claimed in a different
    ///         ERC20 token. Precision may be lost if the fee asset has fewer decimals than the base
    /// @param  _feeAsset ERC20 The ERC20 token in which pending fees should be claimed
    function claimFees(ERC20 _feeAsset) external {
        if (msg.sender != SHARE) revert Errors.OnlyCallableByNestShare();

        NestAccountantStorage storage $ = _getNestAccountantStorage();
        AccountantState storage state = $.accountantState;

        if (state.isPaused) revert Errors.Paused();

        _crystallizeMaturedBatches();

        if (state.feesOwedInBase == 0) revert Errors.ZeroFeesOwed();

        uint256 _feesOwedInFeeAsset;
        uint256 _remainder;
        if (address(_feeAsset) == address(base)) {
            _feesOwedInFeeAsset = state.feesOwedInBase;
        } else {
            RateProviderData memory _data = $.rateProviderData[_feeAsset];
            uint8 _feeAssetDecimals = ERC20(_feeAsset).decimals();
            (uint256 _feesOwedInBaseUsingFeeAssetDecimals, uint256 remainder_) =
                _changeDecimals(state.feesOwedInBase, baseDecimals, _feeAssetDecimals);
            _remainder = remainder_;
            if (_data.isPeggedToBase) {
                _feesOwedInFeeAsset = _feesOwedInBaseUsingFeeAssetDecimals;
            } else {
                uint256 _rate = _data.rateProvider.getRate();
                _feesOwedInFeeAsset = _feesOwedInBaseUsingFeeAssetDecimals.mulDivDown(10 ** _feeAssetDecimals, _rate);
            }
        }

        state.feesOwedInBase = _remainder.toUint128();
        SafeERC20.safeTransferFrom(IERC20(address(_feeAsset)), SHARE, state.payoutAddress, _feesOwedInFeeAsset);

        emit FeesClaimed(address(_feeAsset), _feesOwedInFeeAsset);
    }

    /// @notice Pause this contract, which causes safe rate calls and fee claims to revert
    /// @dev    Callable by MULTISIG_ROLE
    function pause() external requiresAuth {
        _getNestAccountantStorage().accountantState.isPaused = true;
        emit Paused();
    }

    /// @notice Unpause this contract, which allows safe rate calls and fee claims to resume
    /// @dev    Callable by MULTISIG_ROLE
    function unpause() external requiresAuth {
        _getNestAccountantStorage().accountantState.isPaused = false;
        emit Unpaused();
    }

    /// @notice Update the minimum time delay between `updateExchangeRate` calls
    /// @dev    There are no input requirements, as it is possible the admin would want
    ///         the exchange rate updated as frequently as needed
    ///         Callable by OWNER_ROLE
    /// @param  _minimumUpdateDelayInSeconds uint32 The new minimum delay (in seconds) required between successive exchange rate updates
    function updateDelay(uint32 _minimumUpdateDelayInSeconds) external requiresAuth {
        uint32 _oldDelay = _getNestAccountantStorage().accountantState.minimumUpdateDelayInSeconds;
        _setMinimumUpdateDelayInSeconds(_minimumUpdateDelayInSeconds);
        emit DelayInSecondsUpdated(_oldDelay, _minimumUpdateDelayInSeconds);
    }

    /// @notice Update the allowed upper bound change of exchange rate between `updateExchangeRateCalls`.
    /// @dev    Callable by OWNER_ROLE
    /// @param  _allowedExchangeRateChangeUpper uint32 The new upper bound for allowed exchange rate changes expressed in basis points where 1e6 = 100%
    function updateUpper(uint32 _allowedExchangeRateChangeUpper) external requiresAuth {
        uint32 _oldBound = _getNestAccountantStorage().accountantState.allowedExchangeRateChangeUpper;
        _setAllowedExchangeRateChangeUpper(_allowedExchangeRateChangeUpper);
        emit UpperBoundUpdated(_oldBound, _allowedExchangeRateChangeUpper);
    }

    /// @notice Update the allowed lower bound change of exchange rate between `updateExchangeRateCalls`.
    /// @dev    Callable by OWNER_ROLE
    /// @param  _allowedExchangeRateChangeLower uint32 The new lower bound for allowed exchange rate changes, expressed in basis points where 1e6 = 100%
    function updateLower(uint32 _allowedExchangeRateChangeLower) external requiresAuth {
        uint32 _oldBound = _getNestAccountantStorage().accountantState.allowedExchangeRateChangeLower;
        _setAllowedExchangeRateChangeLower(_allowedExchangeRateChangeLower);
        emit LowerBoundUpdated(_oldBound, _allowedExchangeRateChangeLower);
    }

    /// @notice Update the management fee to a new value
    /// @dev    Accrues elapsed management fees under the previous rate before applying the new rate.
    ///         Callable by OWNER_ROLE
    /// @dev    Operators should call `updateExchangeRate` before changing the management fee.
    ///         This function accrues old-fee charges using the stale `lastGrossRate`,
    ///         so changing the fee during a drawdown can overaccrue management fees for the elapsed interval.
    /// @param  _managementFee    uint32  The new management fee, expressed in basis points where 1e6 = 100%
    /// @param  _totalShareSupply uint128 The global total share supply across all chains
    function updateManagementFee(uint32 _managementFee, uint128 _totalShareSupply) external virtual requiresAuth {
        AccountantState storage state = _getNestAccountantStorage().accountantState;
        uint32 _oldFee = state.managementFee;

        // Accrue elapsed management fees under the old fee before switching
        uint64 _currentTime = uint64(block.timestamp);
        uint256 _timeDelta = _currentTime - state.lastUpdateTimestamp;
        if (_timeDelta > 0) {
            uint256 _totalShares = uint256(_totalShareSupply);
            if (_totalShareSupply < IERC20(SHARE).totalSupply()) revert Errors.TotalSupplyBelowLocal();

            if (_oldFee > 0) {
                uint256 _oneShare = 10 ** ERC20(SHARE).decimals();
                uint256 _rateBasis = uint256(state.lastGrossRate);
                uint256 _mgmtDiscount = _annualize(_rateBasis * uint256(_oldFee), _timeDelta);
                if (_totalShares > 0) {
                    uint256 _shareSupplyBasis = Math.min(uint256(state.totalSharesLastUpdate), _totalShares);
                    uint256 _mgmtFeeBase = _mgmtDiscount.mulDivDown(_shareSupplyBasis, _oneShare);
                    state.feesOwedInBase = (uint256(state.feesOwedInBase) + _mgmtFeeBase).toUint128();
                }
            }

            // Always checkpoint so enabling a fee from 0 doesn't accrue retroactively
            state.lastUpdateTimestamp = _currentTime;
            state.totalSharesLastUpdate = _totalShares.toUint128();
        }

        _setManagementFee(_managementFee);
        emit ManagementFeeUpdated(_oldFee, _managementFee);
    }

    /// @notice Update the performance fee to a new value
    /// @dev    Seeds the high-water mark from the current exchange rate when enabling performance fees.
    ///         Callable by authorized accounts.
    ///
    ///         IMPORTANT: Call `updateExchangeRate` before changing the performance fee. The new fee
    ///         applies to all gains since the last rate checkpoint, so stale checkpoints cause the
    ///         new fee to be charged on gains that accrued under the old fee.
    /// @param  _performanceFee uint32 The new performance fee, expressed where 1e6 = 100%
    function updatePerformanceFee(uint32 _performanceFee) external requiresAuth {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        PerformanceFeeConfig storage feeConfig = $.performanceFeeConfig;
        AccountantState storage state = $.accountantState;
        uint32 _oldFee = feeConfig.performanceFee;
        _setPerformanceFee(_performanceFee);
        // Enabling perf fees (0 -> >0) establishes a fresh HWM baseline at the current gross rate
        // so that gains accrued while fees were disabled are not retroactively taxed.
        if (_oldFee == 0 && _performanceFee > 0) {
            if (state.lastGrossRate == 0) revert Errors.InvalidRate();
            state.highWaterMark = state.lastGrossRate;
            state.hwmLastUpdateTimestamp = uint64(block.timestamp);
            if ($.reserveState.totalReserve == 0) {
                state.clawbackReferenceRate = state.lastGrossRate;
            }
        }
        emit PerformanceFeeUpdated(_oldFee, _performanceFee);
    }

    /// @notice Reset the high-water mark
    /// @dev    `_newHighWaterMark` must be non-zero. Callable by authorized accounts.
    /// @param  _newHighWaterMark uint96 The new high-water mark in base terms
    function resetHighWaterMark(uint96 _newHighWaterMark) external requiresAuth {
        if (_newHighWaterMark == 0) revert Errors.InvalidRate();
        AccountantState storage state = _getNestAccountantStorage().accountantState;
        uint96 _oldHWM = state.highWaterMark;
        state.highWaterMark = _newHighWaterMark;
        state.hwmLastUpdateTimestamp = uint64(block.timestamp);
        state.clawbackReferenceRate = _newHighWaterMark;
        emit HighWaterMarkUpdated(_oldHWM, _newHighWaterMark);
    }

    /// @notice Update the hurdle rate used for performance-fee accrual
    /// @dev    Crystallizes hurdle accrued under the old rate into the HWM before updating
    ///         Callable by authorized accounts.
    /// @param  _hurdleRate uint32 The new annualized hurdle rate, expressed where 1e6 = 100%
    function updateHurdleRate(uint32 _hurdleRate) external requiresAuth {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        AccountantState storage state = $.accountantState;
        uint32 _oldRate = $.performanceFeeConfig.hurdleRate;
        if (_oldRate == _hurdleRate) revert Errors.SameValue();
        uint64 _currentTime = uint64(block.timestamp);

        // Accrue elapsed hurdle rate into the HWM
        if (_oldRate > 0) {
            uint256 _timeDelta = _currentTime - state.hwmLastUpdateTimestamp;
            if (_timeDelta > 0) {
                uint256 _hwm = uint256(state.highWaterMark);
                state.highWaterMark = (_hwm + _annualize(_oldRate * _hwm, _timeDelta)).toUint96();
            }
        }

        // new rate only accrues prospectively from the reset timestamp.
        state.hwmLastUpdateTimestamp = _currentTime;

        _setHurdleRate(_hurdleRate);
        emit HurdleRateUpdated(_oldRate, _hurdleRate);
    }

    /// @notice Update the fraction of performance fees held back in reserve
    /// @dev    Callable by authorized accounts.
    /// @param  _holdbackRate uint32 The new holdback rate, expressed where 1e6 = 100%
    function updateHoldbackRate(uint32 _holdbackRate) external requiresAuth {
        uint32 _oldRate = _getNestAccountantStorage().performanceFeeConfig.holdbackRate;
        _setHoldbackRate(_holdbackRate);
        emit HoldbackRateUpdated(_oldRate, _holdbackRate);
    }

    /// @notice Update the reserve crystallization window
    /// @dev    Callable by authorized accounts.
    /// @param  _crystallizationWindow uint32 The new reserve crystallization window in seconds
    function updateCrystallizationWindow(uint32 _crystallizationWindow) external requiresAuth {
        uint32 _oldWindow = _getNestAccountantStorage().performanceFeeConfig.crystallizationWindow;
        _setCrystallizationWindow(_crystallizationWindow);
        if (_crystallizationWindow == 0 && _oldWindow > 0) _crystallizeMaturedBatches();
        emit CrystallizationWindowUpdated(_oldWindow, _crystallizationWindow);
    }

    /// @notice Update how many reserve epochs are grouped into each crystallization window
    /// @dev    Callable by authorized accounts.
    /// @param  _epochsPerWindow uint32 The new number of epochs per crystallization window
    function updateEpochsPerWindow(uint32 _epochsPerWindow) external requiresAuth {
        uint32 _oldEpochs = _getNestAccountantStorage().performanceFeeConfig.epochsPerWindow;
        _setEpochsPerWindow(_epochsPerWindow);
        emit EpochsPerWindowUpdated(_oldEpochs, _epochsPerWindow);
    }

    /// @notice Update the payout address fees are sent to
    /// @dev    Callable by OWNER_ROLE
    /// @param  _payoutAddress address The new address where accrued fees will be sent
    function updatePayoutAddress(address _payoutAddress) external requiresAuth {
        address _oldPayout = _getNestAccountantStorage().accountantState.payoutAddress;
        _setPayoutAddress(_payoutAddress);
        emit PayoutAddressUpdated(_oldPayout, _payoutAddress);
    }

    /// @notice Update the rate provider data for a specific `asset`
    /// @dev    Rate providers must return rates in terms of `base` or
    ///         an asset pegged to base and they must use the same decimals
    ///         as `asset`. Callable by OWNER_ROLE
    /// @param  asset          ERC20   The ERC20 token for which the rate provider data is being set
    /// @param  isPeggedToBase bool    Boolean indicating if the asset is pegged to the base asset
    /// @param  rateProvider   address The address of the rate provider contract for the asset
    function setRateProviderData(ERC20 asset, bool isPeggedToBase, address rateProvider) external requiresAuth {
        if (!isPeggedToBase && rateProvider == address(0)) revert Errors.ZeroAddress();
        _getNestAccountantStorage().rateProviderData[asset] =
            RateProviderData({isPeggedToBase: isPeggedToBase, rateProvider: IRateProvider(rateProvider)});
        emit RateProviderUpdated(address(asset), isPeggedToBase, rateProvider);
    }

    /*//////////////////////////////////////////////////////////////
                            RATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get this NestShare's current rate in the base.
    function getRate() public view returns (uint256 rate) {
        rate = _getNestAccountantStorage().accountantState.exchangeRate;
    }

    /// @notice Get this NestShare's current rate in the base.
    /// @dev    Revert if paused.
    function getRateSafe() external view returns (uint256 rate) {
        AccountantState storage state = _getNestAccountantStorage().accountantState;
        if (state.isPaused) revert Errors.Paused();
        rate = state.exchangeRate;
    }

    /// @notice Get this NestShare's current rate in the provided quote
    /// @dev    `quote` must have its RateProviderData set, else this will revert
    ///         This function will lose precision if the exchange rate
    ///         decimals is greater than the quote's decimals
    /// @param  _quote        ERC20  The ERC20 token in which to express the exchange rate
    /// @return _rateInQuote uint256 The current exchange rate expressed in units of `_quote`
    function getRateInQuote(ERC20 _quote) public view returns (uint256 _rateInQuote) {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        if (address(_quote) == address(base)) {
            _rateInQuote = $.accountantState.exchangeRate;
        } else {
            RateProviderData memory _data = $.rateProviderData[_quote];
            uint8 _quoteDecimals = ERC20(_quote).decimals();
            (uint256 _exchangeRateInQuoteDecimals,) =
                _changeDecimals($.accountantState.exchangeRate, baseDecimals, _quoteDecimals);
            if (_data.isPeggedToBase) {
                _rateInQuote = _exchangeRateInQuoteDecimals;
            } else {
                uint256 _quoteRate = _data.rateProvider.getRate();
                uint256 _oneQuote = 10 ** _quoteDecimals;
                _rateInQuote = _oneQuote.mulDivDown(_exchangeRateInQuoteDecimals, _quoteRate);
            }
        }
    }

    /// @notice Get this NestShare's current rate in the provided quote
    /// @dev    `quote` must have its RateProviderData set, else this will revert
    ///         Revert if paused
    /// @param  _quote        ERC20   The ERC20 token in which to express the exchange rate
    /// @return _rateInQuote  uint256 The current exchange rate expressed in units of `_quote`
    function getRateInQuoteSafe(ERC20 _quote) public view returns (uint256 _rateInQuote) {
        if (_getNestAccountantStorage().accountantState.isPaused) revert Errors.Paused();
        _rateInQuote = getRateInQuote(_quote);
    }

    /// @notice Get the complete current state of the accountant
    /// @dev    Returns the full AccountantState struct containing all configuration and tracking parameters
    /// @return The current AccountantState including exchange rate, fees, bounds, timestamps, and pause status
    function getAccountantState() public view virtual returns (AccountantState memory) {
        return _getNestAccountantStorage().accountantState;
    }

    /// @notice Get the current performance-fee configuration
    /// @return The current `PerformanceFeeConfig`
    function getPerformanceFeeConfig() public view returns (PerformanceFeeConfig memory) {
        return _getNestAccountantStorage().performanceFeeConfig;
    }

    /// @notice Get aggregate reserve accounting state
    /// @return totalReserve_ uint128 The total holdback reserve currently tracked
    /// @return batchHead_    uint64  The index of the oldest active reserve batch
    /// @return batchTail_    uint64  The index of the next reserve batch slot to write
    function getReserveState() public view returns (uint128 totalReserve_, uint64 batchHead_, uint64 batchTail_) {
        ReserveState storage rs = _getNestAccountantStorage().reserveState;
        totalReserve_ = rs.totalReserve;
        batchHead_ = rs.batchHead;
        batchTail_ = rs.batchTail;
    }

    /*//////////////////////////////////////////////////////////////
                        PENDING SHARES FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the global total pending shares across all vaults sharing this accountant
    /// @dev    This value is used in `totalAssets()` calculations to properly report total assets
    /// @return uint256 The total pending shares awaiting redemption
    function totalPendingShares() external view returns (uint256) {
        return _getNestAccountantStorage().totalPendingShares;
    }

    /// @notice Increases the global total pending shares
    /// @dev    Called when a redeem request is made. Callable by authorized accounts.
    /// @param  _amount uint256 The amount of shares to add to pending
    function increaseTotalPendingShares(uint256 _amount) external requiresAuth {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        uint256 _oldPendingShares = $.totalPendingShares;
        $.totalPendingShares = _oldPendingShares + _amount;
        emit TotalPendingSharesUpdated(_oldPendingShares, $.totalPendingShares);
    }

    /// @notice Decreases the global total pending shares
    /// @dev    Called when a redeem request is fulfilled or cancelled. Callable by authorized accounts.
    /// @param  _amount uint256 The amount of shares to remove from pending
    function decreaseTotalPendingShares(uint256 _amount) external requiresAuth {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        uint256 _oldPendingShares = $.totalPendingShares;
        if (_amount > _oldPendingShares) revert Errors.InsufficientBalance();
        $.totalPendingShares = _oldPendingShares - _amount;
        emit TotalPendingSharesUpdated(_oldPendingShares, $.totalPendingShares);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev    Deducts annualized management fee from the gross rate and accrues the fee in base terms.
    ///         Uses min(lastGrossRate, _newExchangeRate) as the discount basis to avoid retroactive
    ///         overcharging when the rate rises during the interval.
    /// @param  _newExchangeRate             uint256 The gross market rate of the underlying investment strategy
    /// @param  _totalShares           uint256 Current total share supply
    /// @param  _oneShare              uint256 Share-scaling factor based on share decimals
    /// @return _postManagementFeeRate uint256 The exchange rate after management-fee deduction
    function _accrueManagementFees(uint256 _newExchangeRate, uint256 _totalShares, uint256 _oneShare)
        internal
        returns (uint256 _postManagementFeeRate)
    {
        _postManagementFeeRate = _newExchangeRate;

        if (_totalShares > 0) {
            AccountantState storage state = _getNestAccountantStorage().accountantState;
            uint256 _rateBasis = Math.min(uint256(state.lastGrossRate), _newExchangeRate);
            uint256 _mgmtDiscount =
                _annualize(_rateBasis * uint256(state.managementFee), block.timestamp - state.lastUpdateTimestamp);
            uint256 _shareSupplyBasis = Math.min(uint256(state.totalSharesLastUpdate), _totalShares);
            uint256 _rateHaircut = _mgmtDiscount.mulDivDown(_shareSupplyBasis, _totalShares);
            _postManagementFeeRate = Math.saturatingSub(_newExchangeRate, _rateHaircut);
            uint256 _mgmtFeeBase = _rateHaircut.mulDivDown(_totalShares, _oneShare);

            state.feesOwedInBase = (uint256(state.feesOwedInBase) + _mgmtFeeBase).toUint128();
        }
    }

    /// @dev    Computes performance fee on gains above the hurdle-adjusted HWM, updates the HWM,
    ///         handles holdback reserve splits, and clawback on drawdowns.
    ///         HWM is tracked in gross terms so the comparison is always gross vs gross,
    ///         avoiding circular dependency between performance fee and the net rate.
    /// @param  _newExchangeRate             uint256 The gross market rate of the underlying investment strategy
    /// @param  _postManagementFeeRate uint256 Exchange rate after management-fee accrual
    /// @param  _totalShares           uint256 Current total share supply
    /// @param  _oneShare              uint256 Share-scaling factor based on share decimals
    /// @param  _currentTime           uint64  The timestamp for the current update
    /// @return _postFeeRate       uint256 The exchange rate after performance-fee logic
    function _accruePerformanceFees(
        uint256 _newExchangeRate,
        uint256 _postManagementFeeRate,
        uint256 _totalShares,
        uint256 _oneShare,
        uint64 _currentTime
    ) internal returns (uint256 _postFeeRate) {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        PerformanceFeeConfig storage feeConfig = $.performanceFeeConfig;
        AccountantState storage state = $.accountantState;
        uint256 _hwm = uint256(state.highWaterMark);
        uint256 _totalReserve = uint256($.reserveState.totalReserve);
        _postFeeRate = _postManagementFeeRate;

        // Apply hurdle rate to HWM
        uint256 _postHurdleHWM =
            _hwm + _annualize(uint256(feeConfig.hurdleRate) * _hwm, _currentTime - state.hwmLastUpdateTimestamp);

        if (feeConfig.performanceFee == 0 || _newExchangeRate <= _postHurdleHWM) {
            uint256 _clawbackRef = uint256(state.clawbackReferenceRate);

            // Recovery: ratchet reference back up
            if (_newExchangeRate >= _hwm && _clawbackRef < _postFeeRate) {
                state.clawbackReferenceRate = _postFeeRate.toUint96();
                return _postFeeRate;
            }

            // Clawback shortfall from reserve
            if (_newExchangeRate < _clawbackRef && _totalReserve > 0 && _totalShares > 0) {
                uint256 _shortfallBase = (_clawbackRef - _newExchangeRate).mulDivDown(_totalShares, _oneShare);
                uint256 _clawback = Math.min(_shortfallBase, _totalReserve);
                uint256 _clawbackRate = _clawback.mulDivDown(_oneShare, _totalShares);
                if (_clawbackRate > 0) {
                    _clawbackReserve(_clawbackRate.mulDivUp(_totalShares, _oneShare));
                    _postFeeRate += _clawbackRate;
                    state.clawbackReferenceRate = _newExchangeRate.toUint96();
                }
            }
            return _postFeeRate;
        }

        // Performance fee on gains above hurdle-adjusted HWM
        uint256 _gain = _newExchangeRate - _postHurdleHWM;
        uint256 _gainBase = _gain.mulDivDown(_totalShares, _oneShare);
        uint256 _perfFeeBase = _gainBase.mulDivDown(feeConfig.performanceFee, DENOMINATOR);

        // Update HWM and seed clawback reference
        state.highWaterMark = _newExchangeRate.toUint96();
        state.hwmLastUpdateTimestamp = _currentTime;
        state.clawbackReferenceRate = _postFeeRate.toUint96();

        if (_perfFeeBase == 0 || _totalShares == 0) return _postFeeRate;

        // Derive per-share fee from aggregate
        uint256 _perfFeePerShare = _perfFeeBase.mulDivDown(_oneShare, _totalShares);
        _postFeeRate = Math.saturatingSub(_postManagementFeeRate, _perfFeePerShare);

        // Update clawback reference
        state.clawbackReferenceRate = _postFeeRate.toUint96();

        // Accrue performance fee with optional holdback
        if (feeConfig.holdbackRate > 0 && feeConfig.crystallizationWindow > 0) {
            uint256 _holdbackBase = _perfFeeBase.mulDivDown(feeConfig.holdbackRate, DENOMINATOR);
            state.feesOwedInBase = (uint256(state.feesOwedInBase) + _perfFeeBase - _holdbackBase).toUint128();
            _holdbackReserve(_holdbackBase, _currentTime);
        } else {
            state.feesOwedInBase = (uint256(state.feesOwedInBase) + _perfFeeBase).toUint128();
        }
    }

    /// @dev    Pro-rates `_value` over the elapsed time since `_fromTimestamp`.
    /// @param  _value       uint256 The annualised basis (e.g. rateBasis * fee)
    /// @param  _timeElapsed uint256 Seconds elapsed over which to pro-rate the value
    /// @return uint256 The pro-rated portion for the elapsed period
    function _annualize(uint256 _value, uint256 _timeElapsed) internal pure returns (uint256) {
        return _value.mulDivDown(_timeElapsed, DENOMINATOR * ONE_YEAR);
    }

    /// @dev Crystallizes any reserve batches whose crystallization window has elapsed.
    ///      When the window is 0 (immediate mode), all outstanding batches are crystallized.
    function _crystallizeMaturedBatches() internal {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        ReserveState storage rs = $.reserveState;
        uint32 _window = $.performanceFeeConfig.crystallizationWindow;

        if (rs.batchHead == rs.batchTail) return;

        uint64 _head = rs.batchHead;
        uint64 _tail = rs.batchTail;
        uint256 _crystallized = 0;
        uint64 _startHead = _head;

        while (_head < _tail) {
            ReserveBatch storage _batch = rs.batches[_head];
            if (_window > 0 && uint256(_batch.timestamp) + uint256(_window) > block.timestamp) break;
            _crystallized += _batch.amount;
            delete rs.batches[_head];
            _head++;
        }

        if (_head != _startHead) rs.batchHead = _head;

        if (_crystallized > 0) {
            rs.totalReserve -= _crystallized.toUint128();
            $.accountantState.feesOwedInBase = (uint256($.accountantState.feesOwedInBase) + _crystallized).toUint128();
        }
    }

    /// @dev    Adds holdback amount to the reserve, grouping into epoch-based batches.
    /// @param  _amount      uint256 The holdback amount to reserve in base terms
    /// @param  _currentTime uint64  The timestamp assigned to the reserve batch
    function _holdbackReserve(uint256 _amount, uint64 _currentTime) internal {
        if (_amount == 0) return;

        NestAccountantStorage storage $ = _getNestAccountantStorage();
        ReserveState storage rs = $.reserveState;
        uint256 _epochDuration = _getEpochDuration();
        uint64 _tail = rs.batchTail;

        // Try to append to last batch if same epoch
        if (_tail > rs.batchHead) {
            ReserveBatch storage _lastBatch = rs.batches[_tail - 1];
            if (_epochDuration > 0 && _currentTime / _epochDuration == _lastBatch.timestamp / _epochDuration) {
                _lastBatch.amount += _amount.toUint128();
                _lastBatch.timestamp = _currentTime;
                rs.totalReserve += _amount.toUint128();
                return;
            }
        }

        // Create new batch
        rs.batches[_tail].amount = _amount.toUint128();
        rs.batches[_tail].timestamp = _currentTime;
        rs.batchTail = _tail + 1;
        rs.totalReserve += _amount.toUint128();
    }

    /// @dev    Claws back reserve in LIFO order (newest batches first).
    /// @param  _amount uint256 The reserve amount to return to investors
    function _clawbackReserve(uint256 _amount) internal {
        ReserveState storage rs = _getNestAccountantStorage().reserveState;
        uint64 _tail = rs.batchTail;
        uint64 _head = rs.batchHead;
        uint256 _remaining = _amount;

        while (_remaining > 0 && _tail > _head) {
            _tail--;
            ReserveBatch storage _batch = rs.batches[_tail];
            if (_batch.amount <= _remaining) {
                _remaining -= _batch.amount;
                delete rs.batches[_tail];
            } else {
                _batch.amount -= uint128(_remaining);
                _remaining = 0;
                _tail++; // keep this batch
            }
        }

        rs.batchTail = _tail;
        rs.totalReserve -= _amount.toUint128();
    }

    /// @dev    Returns the epoch duration for reserve batching.
    /// @return uint256 The duration of each reserve epoch in seconds
    function _getEpochDuration() internal view returns (uint256) {
        PerformanceFeeConfig storage feeConfig = _getNestAccountantStorage().performanceFeeConfig;
        if (feeConfig.crystallizationWindow == 0 || feeConfig.epochsPerWindow == 0) return 0;
        uint256 _duration = uint256(feeConfig.crystallizationWindow) / uint256(feeConfig.epochsPerWindow);
        return _duration > 1 days ? _duration : 1 days;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @dev    Internal setter that validates and stores minimum update delay.
    /// @param  _minimumUpdateDelayInSeconds uint32 The new minimum update delay in seconds
    function _setMinimumUpdateDelayInSeconds(uint32 _minimumUpdateDelayInSeconds) internal {
        if (_minimumUpdateDelayInSeconds > UPDATE_DELAY_CAP) revert Errors.UpdateDelayTooLarge();
        _getNestAccountantStorage().accountantState.minimumUpdateDelayInSeconds = _minimumUpdateDelayInSeconds;
    }

    /// @dev    Internal setter that validates and stores allowed upper exchange-rate change.
    /// @param  _allowedExchangeRateChangeUpper uint32 The new upper bound where 1e6 = 100%
    function _setAllowedExchangeRateChangeUpper(uint32 _allowedExchangeRateChangeUpper) internal {
        if (_allowedExchangeRateChangeUpper < DENOMINATOR) revert Errors.UpperBoundTooSmall();
        _getNestAccountantStorage().accountantState.allowedExchangeRateChangeUpper = _allowedExchangeRateChangeUpper;
    }

    /// @dev    Internal setter that validates and stores allowed lower exchange-rate change.
    /// @param  _allowedExchangeRateChangeLower uint32 The new lower bound where 1e6 = 100%
    function _setAllowedExchangeRateChangeLower(uint32 _allowedExchangeRateChangeLower) internal {
        if (_allowedExchangeRateChangeLower > DENOMINATOR) revert Errors.LowerBoundTooLarge();
        _getNestAccountantStorage().accountantState.allowedExchangeRateChangeLower = _allowedExchangeRateChangeLower;
    }

    /// @dev    Internal setter that validates and stores management fee.
    /// @param  _managementFee uint32 The new management fee where 1e6 = 100%
    function _setManagementFee(uint32 _managementFee) internal {
        if (_managementFee > MANAGEMENT_FEE_CAP) revert Errors.ManagementFeeTooLarge();
        _getNestAccountantStorage().accountantState.managementFee = _managementFee;
    }

    /// @dev    Internal setter that validates and stores performance fee.
    /// @param  _performanceFee uint32 The new performance fee where 1e6 = 100%
    function _setPerformanceFee(uint32 _performanceFee) internal {
        if (_performanceFee > PERFORMANCE_FEE_CAP) revert Errors.PerformanceFeeTooLarge();
        _getNestAccountantStorage().performanceFeeConfig.performanceFee = _performanceFee;
    }

    /// @dev    Internal setter that validates and stores hurdle rate.
    /// @param  _hurdleRate uint32 The new hurdle rate where 1e6 = 100%
    function _setHurdleRate(uint32 _hurdleRate) internal {
        if (_hurdleRate > HURDLE_RATE_CAP) revert Errors.HurdleRateTooLarge();
        _getNestAccountantStorage().performanceFeeConfig.hurdleRate = _hurdleRate;
    }

    /// @dev    Internal setter that validates and stores holdback rate.
    /// @param  _holdbackRate uint32 The new holdback rate where 1e6 = 100%
    function _setHoldbackRate(uint32 _holdbackRate) internal {
        if (_holdbackRate > DENOMINATOR) revert Errors.HoldbackRateTooLarge();
        _getNestAccountantStorage().performanceFeeConfig.holdbackRate = _holdbackRate;
    }

    /// @dev    Internal setter that validates and stores crystallization window.
    /// @param  _crystallizationWindow uint32 The new crystallization window in seconds
    function _setCrystallizationWindow(uint32 _crystallizationWindow) internal {
        if (_crystallizationWindow > CRYSTALLIZATION_WINDOW_CAP) revert Errors.CrystallizationWindowTooLarge();
        _getNestAccountantStorage().performanceFeeConfig.crystallizationWindow = _crystallizationWindow;
    }

    /// @dev    Internal setter that validates and stores epochs per window.
    /// @param  _epochsPerWindow uint32 The new number of epochs per crystallization window
    function _setEpochsPerWindow(uint32 _epochsPerWindow) internal {
        if (_epochsPerWindow > EPOCHS_PER_WINDOW_CAP) revert Errors.EpochsPerWindowTooLarge();
        _getNestAccountantStorage().performanceFeeConfig.epochsPerWindow = _epochsPerWindow;
    }

    /// @dev    Internal setter that stores payout address.
    /// @param  _payoutAddress address The new payout address
    function _setPayoutAddress(address _payoutAddress) internal {
        if (_payoutAddress == address(0)) revert Errors.ZeroAddress();
        _getNestAccountantStorage().accountantState.payoutAddress = _payoutAddress;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Convert an amount from one decimal precision to another
    /// @dev    If `_fromDecimals` is equal to `_toDecimals`, the original amount is returned
    ///         If `_fromDecimals` is less than `_toDecimals`, the amount is scaled up
    ///         If `_fromDecimals` is greater than `_toDecimals`, the amount is scaled down (integer division)
    /// @param  _amount          uint256 The numeric value to convert
    /// @param  _fromDecimals    uint8   The current number of decimals of `_amount`
    /// @param  _toDecimals      uint8   The target number of decimals to convert `_amount` to
    /// @return _amountAdjusted  uint256 The amount adjusted to the target decimal precision
    /// @return _remainder       uint256 The remainder to be carry forwarded
    function _changeDecimals(uint256 _amount, uint8 _fromDecimals, uint8 _toDecimals)
        internal
        pure
        returns (uint256 _amountAdjusted, uint256 _remainder)
    {
        if (_fromDecimals == _toDecimals) {
            _amountAdjusted = _amount;
        } else if (_fromDecimals < _toDecimals) {
            _amountAdjusted = _amount * 10 ** (_toDecimals - _fromDecimals);
        } else {
            _amountAdjusted = _amount / 10 ** (_fromDecimals - _toDecimals);
            _remainder = _amount % 10 ** (_fromDecimals - _toDecimals);
        }
    }
}
