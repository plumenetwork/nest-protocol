// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {Authority} from "@solmate/auth/Auth.sol";

import {IRateProvider} from "contracts/interfaces/IRateProvider.sol";
import {Errors} from "contracts/types/Errors.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

/// @title  NestSpokeAccountant
/// @author plumenetwork
/// @notice Lightweight accountant for spoke (satellite) chains in an omnichain OFT setup.
/// @dev    Stores and serves an exchange rate pushed by the hub chain. No fee accrual logic —
///         management, performance, holdback, and clawback fees are all handled on the hub chain.
///         ABI-compatible with NestHubAccountant for rate queries, pending shares, and admin functions.
contract NestSpokeAccountant is Initializable, AuthUpgradeable {
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
    }

    /// @param isPeggedToBase whether or not the asset is 1:1 with the base asset
    /// @param rateProvider the rate provider for this asset if `isPeggedToBase` is false
    struct RateProviderData {
        bool isPeggedToBase;
        IRateProvider rateProvider;
    }

    /// @notice Storage struct for NestSpokeAccountant
    struct NestAccountantStorage {
        AccountantState accountantState;
        mapping(ERC20 => RateProviderData) rateProviderData;
        uint256 totalPendingShares;
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS AND IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    ERC20 public immutable base;
    uint8 public immutable baseDecimals;
    address internal immutable SHARE;

    uint256 internal constant DENOMINATOR = 1e6;
    uint256 internal constant UPDATE_DELAY_CAP = 14 days;

    // keccak256(abi.encode(uint256(keccak256("plumenetwork.storage.NestAccountant")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NestAccountantStorageLocation =
        0xb378036f9633fc394c3579301b38ac88997c2589544525e367cd650f76eaa300;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the exchange rate is updated
    /// @param  oldRate     uint96 The previous exchange rate
    /// @param  newRate     uint96 The newly set exchange rate
    /// @param  currentTime uint64 The timestamp when the update occurred
    event ExchangeRateUpdated(uint96 oldRate, uint96 newRate, uint64 currentTime);

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

    /// @notice Emitted when the rate provider for an asset is updated
    /// @param  asset        address The asset for which the rate provider is updated
    /// @param  isPegged     bool    Whether the asset is treated as pegged (uses fixed rate)
    /// @param  rateProvider address The newly assigned rate provider address
    event RateProviderUpdated(address asset, bool isPegged, address rateProvider);

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

    /// @dev    Internal function to access the contract's NestSpokeAccountant slot
    /// @return $ NestAccountantStorage A reference to the NestAccountantStorage struct for reading/writing exchange rate
    function _getNestAccountantStorage() private pure returns (NestAccountantStorage storage $) {
        assembly {
            $.slot := NestAccountantStorageLocation
        }
    }

    /// @notice Sets up the initial state of the NestSpokeAccountant contract
    /// @dev    This function is called only during contract initialization
    /// @param  _startingExchangeRate           uint96  The initial exchange rate used for share-to-asset conversions
    /// @param  _allowedExchangeRateChangeUpper uint32  The maximum allowed increase in exchange rate per update (in basis points where 1e6 = 100%)
    /// @param  _allowedExchangeRateChangeLower uint32  The maximum allowed decrease in exchange rate per update (in basis points where 1e6 = 100%)
    /// @param  _minimumUpdateDelayInSeconds    uint32  Minimum delay between successive exchange rate updates
    /// @param  _owner                          address The address of the owner of the accountant
    function initialize(
        uint96 _startingExchangeRate,
        uint32 _allowedExchangeRateChangeUpper,
        uint32 _allowedExchangeRateChangeLower,
        uint32 _minimumUpdateDelayInSeconds,
        address _owner
    ) external initializer {
        if (_startingExchangeRate == 0) revert Errors.InvalidRate();
        if (_owner == address(0)) revert Errors.ZeroAddress();

        AccountantState storage state = _getNestAccountantStorage().accountantState;
        state.lastUpdateTimestamp = uint64(block.timestamp);
        state.exchangeRate = _startingExchangeRate;

        _setAllowedExchangeRateChangeUpper(_allowedExchangeRateChangeUpper);
        _setAllowedExchangeRateChangeLower(_allowedExchangeRateChangeLower);
        _setMinimumUpdateDelayInSeconds(_minimumUpdateDelayInSeconds);

        __Auth_init(_owner, Authority(address(0)));
    }

    /// @notice Returns the version of the NestSpokeAccountant contract.
    /// @dev    This version is used to track contract upgrades.
    /// @return string A string representing the version of the contract.
    function version() public pure returns (string memory) {
        return "1.1.0";
    }

    /*//////////////////////////////////////////////////////////////
                        EXCHANGE RATE UPDATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the exchange rate directly without fee accrual
    /// @dev    On spoke chains the hub computes the post-fee net rate and pushes it here.
    ///         Only bounds checking and timing validation are enforced.
    ///         Second parameter (totalShareSupply) is accepted for call-signature compatibility but ignored.
    /// @param  _newExchangeRate uint96 The post-fee net exchange rate from the hub
    function updateExchangeRate(uint96 _newExchangeRate, uint128) external requiresAuth {
        AccountantState storage state = _getNestAccountantStorage().accountantState;
        uint64 _currentTime = uint64(block.timestamp);
        uint256 _currentExchangeRate = state.exchangeRate;

        if (_currentTime < state.lastUpdateTimestamp + state.minimumUpdateDelayInSeconds) {
            revert Errors.MinimumUpdateDelayNotPassed();
        }

        if (
            _newExchangeRate > _currentExchangeRate.mulDivDown(state.allowedExchangeRateChangeUpper, DENOMINATOR)
                || _newExchangeRate < _currentExchangeRate.mulDivDown(state.allowedExchangeRateChangeLower, DENOMINATOR)
        ) {
            revert Errors.RateOutOfBounds();
        }

        state.lastUpdateTimestamp = _currentTime;
        state.exchangeRate = _newExchangeRate;

        emit ExchangeRateUpdated(uint96(_currentExchangeRate), _newExchangeRate, _currentTime);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause this contract, which causes safe rate calls to revert
    /// @dev    Callable by MULTISIG_ROLE
    function pause() external requiresAuth {
        _getNestAccountantStorage().accountantState.isPaused = true;
        emit Paused();
    }

    /// @notice Unpause this contract, which allows safe rate calls to resume
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

    /// @notice Get the rate provider data configured for an asset
    /// @dev    Returns the zero-valued struct (isPeggedToBase false, rateProvider address(0)) if unset
    /// @param  asset The ERC20 token to look up
    /// @return The `RateProviderData` for `asset`
    function getRateProviderData(ERC20 asset) external view returns (RateProviderData memory) {
        return _getNestAccountantStorage().rateProviderData[asset];
    }

    /// @notice Get the complete current state of the accountant
    /// @dev    Returns the full AccountantState struct containing all configuration and tracking parameters
    /// @return The current AccountantState including exchange rate, fees, bounds, timestamps, and pause status
    function getAccountantState() public view returns (AccountantState memory) {
        return _getNestAccountantStorage().accountantState;
    }

    /// @notice Returns the share token associated with this accountant
    /// @return The share token address
    function share() external view returns (address) {
        return SHARE;
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
