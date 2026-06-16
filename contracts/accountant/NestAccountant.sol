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

/// @title  NestAccountant
/// @author plumenetwork
/// @notice Provides exchange-rate tracking, management-fee accounting, and rate-provider integration for NestVault
/// @dev    Handles exchange-rate updates with safety bounds, fee accumulation, pausing logic,
///         rate-provider lookups, and cross-asset rate conversions while maintaining a compact storage layout
contract NestAccountant is Initializable, AuthUpgradeable {
    using NestVaultAccountingLogic for uint256;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                            STORAGE STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @param payoutAddress                  address the address `claimFees` sends fees to
    /// @param feesOwedInBase                 uint128 total pending fees owed in terms of base
    /// @param totalSharesLastUpdate          uint128 total amount of shares the last exchange rate update
    /// @param exchangeRate                   uint96  the current exchange rate in terms of base
    /// @param allowedExchangeRateChangeUpper uint32  the max allowed change to exchange rate from an update
    /// @param allowedExchangeRateChangeLower uint32  the min allowed change to exchange rate from an update
    /// @param lastUpdateTimestamp            uint64  the block timestamp of the last exchange rate update
    /// @param isPaused                       bool    whether or not this contract is paused
    /// @param minimumUpdateDelayInSeconds    uint32  the minimum amount of time that must pass between
    ///                                               exchange rate updates, such that the update won't trigger
    ///                                               the contract to be paused
    /// @param managementFee                  uint32  the management fee
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
    }

    /// @param isPeggedToBase whether or not the asset is 1:1 with the base asset
    /// @param rateProvider the rate provider for this asset if `isPeggedToBase` is false
    struct RateProviderData {
        bool isPeggedToBase;
        IRateProvider rateProvider;
    }

    /// @notice Storage struct for NestAccountant
    /// @dev    Used by library functions that need access to full storage
    struct NestAccountantStorage {
        // store the accountant state in 3 packed slots.
        AccountantState accountantState;
        // maps ERC20s to their RateProviderData.
        mapping(ERC20 => RateProviderData) rateProviderData;
        // Global total pending shares across all vaults sharing this accountant's SHARE token.
        // This is used in totalAssets() calculation to properly report NAV.
        uint256 totalPendingShares;
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

    /// @dev This constant is used as a divisor for precise percentage calculations
    uint256 internal constant DENOMINATOR = 1e6;

    /// @dev This constant is maximum cap on management fee
    uint256 internal constant MANAGEMENT_FEE_CAP = 0.2e6; // 20%

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
    event ExchangeRateUpdatePaused(uint96 oldRate, uint96 newRate, uint64 currentTime);

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with the given base asset
    /// @param  _base        address         The address of the base asset used for rate calculations
    /// @param  _share       address         The address of the share token associated with this accountant
    constructor(address _base, address _share) {
        if (_base == address(0) || _share == address(0)) revert Errors.ZeroAddress();
        base = ERC20(_base);
        baseDecimals = ERC20(_base).decimals();
        SHARE = _share;
        _disableInitializers();
    }

    /// @dev    Internal function to access the contract's NestAccountant slot
    /// @return $ NestAccountantStorage A reference to the storage struct
    function _getNestAccountantStorage() private pure returns (NestAccountantStorage storage $) {
        assembly {
            $.slot := NestAccountantStorageLocation
        }
    }

    /// @notice Sets up the initial state of the NestAccountant contract
    /// @dev    This function is called only during contract initialization
    /// @param  _totalSharesLastUpdate          uint256 The last recorded total shares at initialization
    /// @param  _payoutAddress                  address The address to which management fees and payouts will be sent
    /// @param  _startingExchangeRate           uint96  The initial exchange rate used for share-to-asset conversions
    /// @param  _allowedExchangeRateChangeUpper uint32  The maximum allowed increase in exchange rate per update (in basis points where 1e6 = 100%)
    /// @param  _allowedExchangeRateChangeLower uint32  The maximum allowed decrease in exchange rate per update (in basis points where 1e6 = 100%)
    /// @param  _minimumUpdateDelayInSeconds    uint32  Minimum delay between successive exchange rate updates
    /// @param  _managementFee                  uint32  The management fee percentage applied to the total assets (in basis points where 1e6 = 100%)
    /// @param  _owner                          address The address of the owner of the accountant
    function initialize(
        uint256 _totalSharesLastUpdate,
        address _payoutAddress,
        uint96 _startingExchangeRate,
        uint32 _allowedExchangeRateChangeUpper,
        uint32 _allowedExchangeRateChangeLower,
        uint32 _minimumUpdateDelayInSeconds,
        uint32 _managementFee,
        address _owner
    ) external virtual initializer {
        if (_startingExchangeRate == 0) {
            revert Errors.InvalidRate();
        }
        if (_owner == address(0)) {
            revert Errors.ZeroAddress();
        }
        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;
        accountantState.lastUpdateTimestamp = uint64(block.timestamp);
        accountantState.totalSharesLastUpdate = _toUint128(_totalSharesLastUpdate);
        accountantState.exchangeRate = _startingExchangeRate;
        _setPayoutAddress(accountantState, _payoutAddress);
        _setAllowedExchangeRateChangeUpper(accountantState, _allowedExchangeRateChangeUpper);
        _setAllowedExchangeRateChangeLower(accountantState, _allowedExchangeRateChangeLower);
        _setMinimumUpdateDelayInSeconds(accountantState, _minimumUpdateDelayInSeconds);
        _setManagementFee(accountantState, _managementFee);

        __Auth_init(_owner, Authority(address(0)));
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
        if (msg.sender != SHARE) {
            revert Errors.OnlyCallableByNestShare();
        }

        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;

        if (accountantState.isPaused) revert Errors.Paused();
        if (accountantState.feesOwedInBase == 0) {
            revert Errors.ZeroFeesOwed();
        }

        // Determine amount of fees owed in feeAsset.
        uint256 _feesOwedInFeeAsset;
        uint256 _remainder;
        if (address(_feeAsset) == address(base)) {
            _feesOwedInFeeAsset = accountantState.feesOwedInBase;
        } else {
            RateProviderData memory _data = _getNestAccountantStorage().rateProviderData[_feeAsset];
            uint8 _feeAssetDecimals = ERC20(_feeAsset).decimals();
            (uint256 _feesOwedInBaseUsingFeeAssetDecimals, uint256 remainder_) =
                _changeDecimals(accountantState.feesOwedInBase, baseDecimals, _feeAssetDecimals);
            _remainder = remainder_;
            if (_data.isPeggedToBase) {
                _feesOwedInFeeAsset = _feesOwedInBaseUsingFeeAssetDecimals;
            } else {
                uint256 _rate = _data.rateProvider.getRate();
                _feesOwedInFeeAsset = _feesOwedInBaseUsingFeeAssetDecimals.mulDivDown(10 ** _feeAssetDecimals, _rate);
            }
        }

        // carry forward remainder dust
        accountantState.feesOwedInBase = _toUint128(_remainder);
        // Transfer fee asset to payout address.
        SafeERC20.safeTransferFrom(
            IERC20(address(_feeAsset)), SHARE, accountantState.payoutAddress, _feesOwedInFeeAsset
        );

        emit FeesClaimed(address(_feeAsset), _feesOwedInFeeAsset);
    }

    /// @notice Pause this contract.
    /// @dev    While paused, `getRateSafe`, `getRateInQuoteSafe`, and `claimFees` revert with `Errors.Paused`.
    ///         Exchange-rate validation in `updateExchangeRate` is unchanged by pause state.
    /// @dev    Callable by MULTISIG_ROLE
    function pause() external requiresAuth {
        _getNestAccountantStorage().accountantState.isPaused = true;
        emit Paused();
    }

    /// @notice Unpause this contract.
    /// @dev    Re-enables `getRateSafe`, `getRateInQuoteSafe`, and `claimFees`.
    /// @dev    Callable by MULTISIG_ROLE
    function unpause() external requiresAuth {
        _getNestAccountantStorage().accountantState.isPaused = false;
        emit Unpaused();
    }

    /// @notice Update the minimum time delay between `updateExchangeRate` calls
    /// @dev    `_minimumUpdateDelayInSeconds` must be less than or equal to `UPDATE_DELAY_CAP`
    ///         Callable by OWNER_ROLE
    /// @param  _minimumUpdateDelayInSeconds uint32 The new minimum delay (in seconds) required between successive exchange rate updates
    function updateDelay(uint32 _minimumUpdateDelayInSeconds) external requiresAuth {
        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;
        uint32 _oldDelay = accountantState.minimumUpdateDelayInSeconds;
        _setMinimumUpdateDelayInSeconds(accountantState, _minimumUpdateDelayInSeconds);
        emit DelayInSecondsUpdated(_oldDelay, _minimumUpdateDelayInSeconds);
    }

    /// @notice Update the allowed upper bound change of exchange rate between `updateExchangeRateCalls`.
    /// @dev    Callable by OWNER_ROLE
    /// @param  _allowedExchangeRateChangeUpper uint32 The new upper bound for allowed exchange rate changes expressed in basis points where 1e6 = 100%
    function updateUpper(uint32 _allowedExchangeRateChangeUpper) external requiresAuth {
        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;
        uint32 _oldBound = accountantState.allowedExchangeRateChangeUpper;
        _setAllowedExchangeRateChangeUpper(accountantState, _allowedExchangeRateChangeUpper);
        emit UpperBoundUpdated(_oldBound, _allowedExchangeRateChangeUpper);
    }

    /// @notice Update the allowed lower bound change of exchange rate between `updateExchangeRateCalls`.
    /// @dev    Callable by OWNER_ROLE
    /// @param  _allowedExchangeRateChangeLower uint32 The new lower bound for allowed exchange rate changes, expressed in basis points where 1e6 = 100%
    function updateLower(uint32 _allowedExchangeRateChangeLower) external requiresAuth {
        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;
        uint32 _oldBound = accountantState.allowedExchangeRateChangeLower;
        _setAllowedExchangeRateChangeLower(accountantState, _allowedExchangeRateChangeLower);
        emit LowerBoundUpdated(_oldBound, _allowedExchangeRateChangeLower);
    }

    /// @notice Update the management fee to a new value
    /// @dev    Callable by OWNER_ROLE. Accrues fees owed using the previous fee rate
    ///         up to the current timestamp before applying the new fee and resetting checkpoints.
    /// @param  _managementFee uint32 The new management fee, expressed in basis points where 1e6 = 100%
    function updateManagementFee(uint32 _managementFee) external virtual requiresAuth {
        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;
        uint32 _oldFee = accountantState.managementFee;

        _accrueManagementFees(accountantState, uint64(block.timestamp), accountantState.exchangeRate);

        _setManagementFee(accountantState, _managementFee);
        emit ManagementFeeUpdated(_oldFee, _managementFee);
    }

    /// @notice Update the payout address fees are sent to
    /// @dev    Callable by OWNER_ROLE
    /// @param  _payoutAddress address The new address where accrued fees will be sent
    function updatePayoutAddress(address _payoutAddress) external requiresAuth {
        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;
        address _oldPayout = accountantState.payoutAddress;
        _setPayoutAddress(accountantState, _payoutAddress);
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

    /// @notice Updates this contract exchangeRate
    /// @dev    Invalid updates always revert (too early, above upper bound, below lower bound),
    ///         regardless of pause state. Successful updates accrue elapsed management fees and refresh checkpoints.
    /// @dev    Callable by UPDATE_EXCHANGE_RATE_ROLE
    /// @param  _newExchangeRate uint96 The new exchange rate to set, expressed in the same units as `exchangeRate`
    function updateExchangeRate(uint96 _newExchangeRate) external requiresAuth {
        AccountantState storage accountantState = _getNestAccountantStorage().accountantState;
        uint64 _currentTime = uint64(block.timestamp);

        uint256 _currentExchangeRate = accountantState.exchangeRate;

        if (_currentTime < accountantState.lastUpdateTimestamp + accountantState.minimumUpdateDelayInSeconds) {
            revert Errors.MinimumUpdateDelayNotPassed();
        }
        if (
            _newExchangeRate
                    > _currentExchangeRate.mulDivDown(accountantState.allowedExchangeRateChangeUpper, DENOMINATOR)
                || _newExchangeRate
                    < _currentExchangeRate.mulDivDown(accountantState.allowedExchangeRateChangeLower, DENOMINATOR)
        ) {
            revert Errors.RateOutOfBounds();
        }

        _accrueManagementFees(accountantState, _currentTime, _newExchangeRate);

        accountantState.exchangeRate = _newExchangeRate;

        emit ExchangeRateUpdated(uint96(_currentExchangeRate), _newExchangeRate, _currentTime);
    }

    /*//////////////////////////////////////////////////////////////
                            RATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get this NestShare's current rate in the base.
    function getRate() public view returns (uint256 rate) {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        rate = $.accountantState.exchangeRate;
    }

    /// @notice Get this NestShare's current rate in the base.
    /// @dev    Revert if paused.
    function getRateSafe() external view returns (uint256 rate) {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        if ($.accountantState.isPaused) {
            revert Errors.Paused();
        }
        rate = $.accountantState.exchangeRate;
    }

    /// @notice Get this NestShare's current rate in the provided quote
    /// @dev    `quote` must have its RateProviderData set, else this will revert
    ///         This function will lose precision if the exchange rate
    ///         decimals is greater than the quote's decimals
    /// @param  _quote        ERC20  The ERC20 token in which to express the exchange rate
    /// @return _rateInQuote uint256 The current exchange rate expressed in units of `_quote`
    function getRateInQuote(ERC20 _quote) public view returns (uint256 _rateInQuote) {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        AccountantState storage accountantState = $.accountantState;
        if (address(_quote) == address(base)) {
            _rateInQuote = accountantState.exchangeRate;
        } else {
            RateProviderData memory _data = $.rateProviderData[_quote];
            uint8 _quoteDecimals = ERC20(_quote).decimals();
            (uint256 _exchangeRateInQuoteDecimals,) =
                _changeDecimals(accountantState.exchangeRate, baseDecimals, _quoteDecimals);
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
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        if ($.accountantState.isPaused) {
            revert Errors.Paused();
        }
        _rateInQuote = getRateInQuote(_quote);
    }

    /// @notice Get the complete current state of the accountant
    /// @dev    Returns the full AccountantState struct containing all configuration and tracking parameters
    /// @return The current AccountantState including exchange rate, fees, bounds, timestamps, and pause status
    function getAccountantState() public view virtual returns (AccountantState memory) {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        return $.accountantState;
    }

    /*//////////////////////////////////////////////////////////////
                        PENDING SHARES FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the global total pending shares across all vaults sharing this accountant
    /// @dev    This value is used in totalAssets() calculation to properly report NAV
    /// @return uint256 The total pending shares awaiting redemption
    function totalPendingShares() external view returns (uint256) {
        return _getNestAccountantStorage().totalPendingShares;
    }

    /// @notice Increases the global total pending shares
    /// @dev    Called by vaults when a redeem request is made. Only callable by authorized vaults.
    /// @param  _amount uint256 The amount of shares to add to pending
    function increaseTotalPendingShares(uint256 _amount) external requiresAuth {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        uint256 _oldPendingShares = $.totalPendingShares;
        $.totalPendingShares = _oldPendingShares + _amount;
        emit TotalPendingSharesUpdated(_oldPendingShares, $.totalPendingShares);
    }

    /// @notice Decreases the global total pending shares
    /// @dev    Called by vaults when a redeem request is fulfilled or cancelled. Only callable by authorized vaults.
    /// @param  _amount uint256 The amount of shares to remove from pending
    function decreaseTotalPendingShares(uint256 _amount) external requiresAuth {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        uint256 _oldPendingShares = $.totalPendingShares;
        if (_amount > _oldPendingShares) {
            revert Errors.InsufficientBalance();
        }
        $.totalPendingShares = _oldPendingShares - _amount;
        emit TotalPendingSharesUpdated(_oldPendingShares, $.totalPendingShares);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal setter that validates and stores minimum update delay.
    function _setMinimumUpdateDelayInSeconds(
        AccountantState storage accountantState,
        uint32 _minimumUpdateDelayInSeconds
    ) internal {
        if (_minimumUpdateDelayInSeconds > UPDATE_DELAY_CAP) {
            revert Errors.UpdateDelayTooLarge();
        }
        accountantState.minimumUpdateDelayInSeconds = _minimumUpdateDelayInSeconds;
    }

    /// @dev Internal setter that validates and stores allowed upper exchange-rate change.
    function _setAllowedExchangeRateChangeUpper(
        AccountantState storage accountantState,
        uint32 _allowedExchangeRateChangeUpper
    ) internal {
        if (_allowedExchangeRateChangeUpper < DENOMINATOR) {
            revert Errors.UpperBoundTooSmall();
        }
        accountantState.allowedExchangeRateChangeUpper = _allowedExchangeRateChangeUpper;
    }

    /// @dev Internal setter that validates and stores allowed lower exchange-rate change.
    function _setAllowedExchangeRateChangeLower(
        AccountantState storage accountantState,
        uint32 _allowedExchangeRateChangeLower
    ) internal {
        if (_allowedExchangeRateChangeLower > DENOMINATOR) {
            revert Errors.LowerBoundTooLarge();
        }
        accountantState.allowedExchangeRateChangeLower = _allowedExchangeRateChangeLower;
    }

    /// @dev Internal setter that validates and stores management fee.
    function _setManagementFee(AccountantState storage accountantState, uint32 _managementFee) internal {
        if (_managementFee > MANAGEMENT_FEE_CAP) {
            revert Errors.ManagementFeeTooLarge();
        }
        accountantState.managementFee = _managementFee;
    }

    /// @dev Internal setter that stores payout address.
    function _setPayoutAddress(AccountantState storage accountantState, address _payoutAddress) internal {
        if (_payoutAddress == address(0)) {
            revert Errors.ZeroAddress();
        }
        accountantState.payoutAddress = _payoutAddress;
    }

    /// @dev Internal helper that snapshots the latest timestamp and total share supply.
    function _updateAccountingCheckpoints(
        AccountantState storage accountantState,
        uint64 _currentTime,
        uint256 _currentTotalShares
    ) internal {
        accountantState.lastUpdateTimestamp = _currentTime;
        accountantState.totalSharesLastUpdate = _toUint128(_currentTotalShares);
    }

    /// @dev Internal helper that accrues management fees between the last checkpoint and `_currentTime`.
    ///      Uses the lower of historical/current total shares and old/new exchange rates to avoid
    ///      retroactively charging on growth that happened after the accrual window started.
    function _accrueManagementFees(
        AccountantState storage accountantState,
        uint64 _currentTime,
        uint256 _newExchangeRate
    ) internal {
        uint256 _currentTotalShares = IERC20(SHARE).totalSupply();
        uint256 _timeDelta = _currentTime - accountantState.lastUpdateTimestamp;
        uint256 _shareSupplyToUse = Math.min(uint256(accountantState.totalSharesLastUpdate), _currentTotalShares);
        uint256 _rateToAccrueOn = Math.min(uint256(accountantState.exchangeRate), _newExchangeRate);

        uint256 _assets = _shareSupplyToUse.convertToAssets(_rateToAccrueOn, NestShareOFT(SHARE), Math.Rounding.Floor);
        uint256 _managementFeesAnnual = _assets.mulDivDown(accountantState.managementFee, DENOMINATOR);

        uint256 _feesOwedInBase = uint256(accountantState.feesOwedInBase);
        _feesOwedInBase += _managementFeesAnnual.mulDivDown(_timeDelta, ONE_YEAR);

        accountantState.feesOwedInBase = _toUint128(_feesOwedInBase);
        accountantState.lastUpdateTimestamp = _currentTime;
        accountantState.totalSharesLastUpdate = _toUint128(_currentTotalShares);
    }

    /// @dev Internal helper that downcasts uint256 to uint128, clamping on overflow.
    function _toUint128(uint256 _value) internal pure returns (uint128 _value128) {
        _value128 = _value > type(uint128).max ? type(uint128).max : uint128(_value);
    }

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
