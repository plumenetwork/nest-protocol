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

    struct AccountantState {
        address payoutAddress;
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

    event ExchangeRateUpdated(uint96 oldRate, uint96 newRate, uint64 currentTime);
    event TotalPendingSharesUpdated(uint256 oldPendingShares, uint256 newPendingShares);
    event Paused();
    event Unpaused();
    event DelayInSecondsUpdated(uint32 oldDelay, uint32 newDelay);
    event UpperBoundUpdated(uint32 oldBound, uint32 newBound);
    event LowerBoundUpdated(uint32 oldBound, uint32 newBound);
    event PayoutAddressUpdated(address oldPayout, address newPayout);
    event RateProviderUpdated(address asset, bool isPegged, address rateProvider);

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor(address _base, address _share) {
        if (_base == address(0) || _share == address(0)) revert Errors.ZeroAddress();
        base = ERC20(_base);
        baseDecimals = ERC20(_base).decimals();
        SHARE = _share;
        _disableInitializers();
    }

    function _getNestAccountantStorage() private pure returns (NestAccountantStorage storage $) {
        assembly {
            $.slot := NestAccountantStorageLocation
        }
    }

    /// @notice Initialize the spoke accountant
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

    function pause() external requiresAuth {
        _getNestAccountantStorage().accountantState.isPaused = true;
        emit Paused();
    }

    function unpause() external requiresAuth {
        _getNestAccountantStorage().accountantState.isPaused = false;
        emit Unpaused();
    }

    function updateDelay(uint32 _minimumUpdateDelayInSeconds) external requiresAuth {
        uint32 _oldDelay = _getNestAccountantStorage().accountantState.minimumUpdateDelayInSeconds;
        _setMinimumUpdateDelayInSeconds(_minimumUpdateDelayInSeconds);
        emit DelayInSecondsUpdated(_oldDelay, _minimumUpdateDelayInSeconds);
    }

    function updateUpper(uint32 _allowedExchangeRateChangeUpper) external requiresAuth {
        uint32 _oldBound = _getNestAccountantStorage().accountantState.allowedExchangeRateChangeUpper;
        _setAllowedExchangeRateChangeUpper(_allowedExchangeRateChangeUpper);
        emit UpperBoundUpdated(_oldBound, _allowedExchangeRateChangeUpper);
    }

    function updateLower(uint32 _allowedExchangeRateChangeLower) external requiresAuth {
        uint32 _oldBound = _getNestAccountantStorage().accountantState.allowedExchangeRateChangeLower;
        _setAllowedExchangeRateChangeLower(_allowedExchangeRateChangeLower);
        emit LowerBoundUpdated(_oldBound, _allowedExchangeRateChangeLower);
    }

    function updatePayoutAddress(address _payoutAddress) external requiresAuth {
        address _oldPayout = _getNestAccountantStorage().accountantState.payoutAddress;
        _setPayoutAddress(_payoutAddress);
        emit PayoutAddressUpdated(_oldPayout, _payoutAddress);
    }

    function setRateProviderData(ERC20 asset, bool isPeggedToBase, address rateProvider) external requiresAuth {
        if (!isPeggedToBase && rateProvider == address(0)) revert Errors.ZeroAddress();
        _getNestAccountantStorage().rateProviderData[asset] =
            RateProviderData({isPeggedToBase: isPeggedToBase, rateProvider: IRateProvider(rateProvider)});
        emit RateProviderUpdated(address(asset), isPeggedToBase, rateProvider);
    }

    /*//////////////////////////////////////////////////////////////
                            RATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getRate() public view returns (uint256 rate) {
        rate = _getNestAccountantStorage().accountantState.exchangeRate;
    }

    function getRateSafe() external view returns (uint256 rate) {
        AccountantState storage state = _getNestAccountantStorage().accountantState;
        if (state.isPaused) revert Errors.Paused();
        rate = state.exchangeRate;
    }

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

    function getRateInQuoteSafe(ERC20 _quote) public view returns (uint256 _rateInQuote) {
        if (_getNestAccountantStorage().accountantState.isPaused) revert Errors.Paused();
        _rateInQuote = getRateInQuote(_quote);
    }

    function getAccountantState() public view returns (AccountantState memory) {
        return _getNestAccountantStorage().accountantState;
    }

    /*//////////////////////////////////////////////////////////////
                        PENDING SHARES FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function totalPendingShares() external view returns (uint256) {
        return _getNestAccountantStorage().totalPendingShares;
    }

    function increaseTotalPendingShares(uint256 _amount) external requiresAuth {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        uint256 _oldPendingShares = $.totalPendingShares;
        $.totalPendingShares = _oldPendingShares + _amount;
        emit TotalPendingSharesUpdated(_oldPendingShares, $.totalPendingShares);
    }

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

    function _setMinimumUpdateDelayInSeconds(uint32 _minimumUpdateDelayInSeconds) internal {
        if (_minimumUpdateDelayInSeconds > UPDATE_DELAY_CAP) revert Errors.UpdateDelayTooLarge();
        _getNestAccountantStorage().accountantState.minimumUpdateDelayInSeconds = _minimumUpdateDelayInSeconds;
    }

    function _setAllowedExchangeRateChangeUpper(uint32 _allowedExchangeRateChangeUpper) internal {
        if (_allowedExchangeRateChangeUpper < DENOMINATOR) revert Errors.UpperBoundTooSmall();
        _getNestAccountantStorage().accountantState.allowedExchangeRateChangeUpper = _allowedExchangeRateChangeUpper;
    }

    function _setAllowedExchangeRateChangeLower(uint32 _allowedExchangeRateChangeLower) internal {
        if (_allowedExchangeRateChangeLower > DENOMINATOR) revert Errors.LowerBoundTooLarge();
        _getNestAccountantStorage().accountantState.allowedExchangeRateChangeLower = _allowedExchangeRateChangeLower;
    }

    function _setPayoutAddress(address _payoutAddress) internal {
        if (_payoutAddress == address(0)) revert Errors.ZeroAddress();
        _getNestAccountantStorage().accountantState.payoutAddress = _payoutAddress;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

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
