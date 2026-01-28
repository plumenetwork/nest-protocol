// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// contracts
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccountantWithRateProviders} from "@boring-vault/src/base/Roles/AccountantWithRateProviders.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {Authority} from "@solmate/auth/Auth.sol";

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";

// libraries
import {Errors} from "contracts/types/Errors.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

// types
import {DataTypes} from "contracts/types/DataTypes.sol";

/// @title  NestAccountant
/// @author plumenetwork
/// @notice Provides exchange-rate tracking, management-fee accounting, and rate-provider integration for NestVault
/// @dev    Handles exchange-rate updates with safety bounds, fee accumulation, pausing logic,
///         rate-provider lookups, and cross-asset rate conversions while maintaining a compact storage layout
contract NestAccountant is Initializable, AuthUpgradeable {
    using FixedPointMathLib for uint256;

    struct NestAccountantStorage {
        // store the accountant state in 3 packed slots.
        DataTypes.AccountantState accountantState;
        // maps ERC20s to their RateProviderData.
        mapping(ERC20 => AccountantWithRateProviders.RateProviderData) rateProviderData;
    }

    /// @notice The address of the base deposit asset used for rate calculations
    /// @dev    This is an immutable variable that stores the address of the base asset
    ERC20 public immutable base;

    /// @notice The decimals rates are provided in
    /// @dev    Specifies the reference decimal precision used internally to scale and normalize rate values
    uint8 public immutable baseDecimals;

    /// @dev    This is an immutable variable that stores the address of the share token to honour ERC7575 specs
    address internal immutable SHARE;

    /// @dev    This value is used to convert between assets and shares
    uint256 internal immutable ONE_SHARE;

    /// @dev This constant is used as a divisor in various mathematical calculations
    ///      throughout the contract to achieve precise percentages and ratios
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

    /// @notice Emitted when protocol fees are claimed
    /// @param  feeAsset address The asset in which the fees were denominated
    /// @param  amount   uint256 The amount of fees claimed
    event FeesClaimed(address indexed feeAsset, uint256 amount);

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

    /// @notice Initializes the contract with the given base asset
    /// @param  _base        address         The address of the base asset used for rate calculations
    constructor(address _base, address _share) {
        base = ERC20(_base);
        baseDecimals = ERC20(_base).decimals();
        SHARE = _share;
        ONE_SHARE = 10 ** ERC20(_share).decimals();
        _disableInitializers();
    }

    /// @dev    Internal function to access the contract's NestAccountant slot
    /// @return $ NestAccountantStorage A reference to the NestAccountantStorage struct for reading/writing exchange rate
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
            revert Errors.INVALID_RATE();
        }
        if (_owner == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        $.accountantState = DataTypes.AccountantState({
            payoutAddress: _payoutAddress,
            feesOwedInBase: 0,
            totalSharesLastUpdate: uint128(_totalSharesLastUpdate),
            exchangeRate: _startingExchangeRate,
            allowedExchangeRateChangeUpper: _allowedExchangeRateChangeUpper,
            allowedExchangeRateChangeLower: _allowedExchangeRateChangeLower,
            lastUpdateTimestamp: uint64(block.timestamp),
            isPaused: false,
            minimumUpdateDelayInSeconds: _minimumUpdateDelayInSeconds,
            managementFee: _managementFee
        });
        __Auth_init(_owner, Authority(address(0)));
    }

    /// @notice Claims accrued management fees owed to the vault
    /// @dev    This function must be called by the NestShare. Fees are accrued in the base asset
    ///         whenever the exchange rate is updated and can optionally be claimed in a different
    ///         ERC20 token. Precision may be lost if the fee asset has fewer decimals than the base
    /// @param  _feeAsset ERC20 The ERC20 token in which pending fees should be claimed
    function claimFees(ERC20 _feeAsset) external {
        if (msg.sender != SHARE) {
            revert Errors.OnlyCallableByNestShare();
        }

        NestAccountantStorage storage $ = _getNestAccountantStorage();

        if ($.accountantState.isPaused) revert Errors.Paused();
        if ($.accountantState.feesOwedInBase == 0) {
            revert Errors.ZeroFeesOwed();
        }

        // Determine amount of fees owed in feeAsset.
        uint256 _feesOwedInFeeAsset;
        uint128 _remainder;
        if (address(_feeAsset) == address(base)) {
            _feesOwedInFeeAsset = $.accountantState.feesOwedInBase;
        } else {
            AccountantWithRateProviders.RateProviderData memory _data = $.rateProviderData[_feeAsset];
            uint8 _feeAssetDecimals = ERC20(_feeAsset).decimals();
            (uint256 _feesOwedInBaseUsingFeeAssetDecimals, uint128 remainder_) =
                changeDecimals($.accountantState.feesOwedInBase, baseDecimals, _feeAssetDecimals);
            _remainder = remainder_;
            if (_data.isPeggedToBase) {
                _feesOwedInFeeAsset = _feesOwedInBaseUsingFeeAssetDecimals;
            } else {
                uint256 _rate = _data.rateProvider.getRate();
                _feesOwedInFeeAsset = _feesOwedInBaseUsingFeeAssetDecimals.mulDivDown(10 ** _feeAssetDecimals, _rate);
            }
        }

        // carry forward remainder dust
        $.accountantState.feesOwedInBase = _remainder;
        // Transfer fee asset to payout address.
        SafeERC20.safeTransferFrom(
            IERC20(address(_feeAsset)), msg.sender, $.accountantState.payoutAddress, _feesOwedInFeeAsset
        );

        emit FeesClaimed(address(_feeAsset), _feesOwedInFeeAsset);
    }

    /// @notice Pause this contract, which prevents future calls to `updateExchangeRate`, and any safe rate
    ///         calls will revert
    /// @dev    Callable by MULTISIG_ROLE
    function pause() external requiresAuth {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        $.accountantState.isPaused = true;
        emit Paused();
    }

    /// @notice Unpause this contract, which allows future calls to `updateExchangeRate`, and any safe rate
    ///         calls will stop reverting
    /// @dev    Callable by MULTISIG_ROLE
    function unpause() external requiresAuth {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        $.accountantState.isPaused = false;
        emit Unpaused();
    }

    /// @notice Update the minimum time delay between `updateExchangeRate` calls
    /// @dev    There are no input requirements, as it is possible the admin would want
    ///         the exchange rate updated as frequently as needed
    ///         Callable by OWNER_ROLE
    /// @param  _minimumUpdateDelayInSeconds uint32 The new minimum delay (in seconds) required between successive exchange rate updates
    function updateDelay(uint32 _minimumUpdateDelayInSeconds) external requiresAuth {
        if (_minimumUpdateDelayInSeconds > UPDATE_DELAY_CAP) {
            revert Errors.UpdateDelayTooLarge();
        }
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        uint32 _oldDelay = $.accountantState.minimumUpdateDelayInSeconds;
        $.accountantState.minimumUpdateDelayInSeconds = _minimumUpdateDelayInSeconds;
        emit DelayInSecondsUpdated(_oldDelay, _minimumUpdateDelayInSeconds);
    }

    /// @notice Update the allowed upper bound change of exchange rate between `updateExchangeRateCalls`.
    /// @dev    Callable by OWNER_ROLE
    /// @param  _allowedExchangeRateChangeUpper uint32 The new upper bound for allowed exchange rate changes expressed in basis points where 1e6 = 100%
    function updateUpper(uint32 _allowedExchangeRateChangeUpper) external requiresAuth {
        if (_allowedExchangeRateChangeUpper < DENOMINATOR) {
            revert Errors.UpperBoundTooSmall();
        }
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        uint32 _oldBound = $.accountantState.allowedExchangeRateChangeUpper;
        $.accountantState.allowedExchangeRateChangeUpper = _allowedExchangeRateChangeUpper;
        emit UpperBoundUpdated(_oldBound, _allowedExchangeRateChangeUpper);
    }

    /// @notice Update the allowed lower bound change of exchange rate between `updateExchangeRateCalls`.
    /// @dev    Callable by OWNER_ROLE
    /// @param  _allowedExchangeRateChangeLower uint32 The new lower bound for allowed exchange rate changes, expressed in basis points where 1e6 = 100%
    function updateLower(uint32 _allowedExchangeRateChangeLower) external requiresAuth {
        if (_allowedExchangeRateChangeLower > DENOMINATOR) {
            revert Errors.LowerBoundTooLarge();
        }
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        uint32 _oldBound = $.accountantState.allowedExchangeRateChangeLower;
        $.accountantState.allowedExchangeRateChangeLower = _allowedExchangeRateChangeLower;
        emit LowerBoundUpdated(_oldBound, _allowedExchangeRateChangeLower);
    }

    /// @notice Update the management fee to a new value
    /// @dev    Callable by OWNER_ROLE
    /// @param  _managementFee uint32 The new management fee, expressed in basis points where 1e6 = 100%
    function updateManagementFee(uint32 _managementFee) external virtual requiresAuth {
        if (_managementFee > MANAGEMENT_FEE_CAP) {
            revert Errors.ManagementFeeTooLarge();
        }
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        uint32 _oldFee = $.accountantState.managementFee;
        $.accountantState.managementFee = _managementFee;
        emit ManagementFeeUpdated(_oldFee, _managementFee);
    }

    /// @notice Update the payout address fees are sent to
    /// @dev    Callable by OWNER_ROLE
    /// @param  _payoutAddress address The new address where accrued fees will be sent
    function updatePayoutAddress(address _payoutAddress) external requiresAuth {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        address _oldPayout = $.accountantState.payoutAddress;
        $.accountantState.payoutAddress = _payoutAddress;
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
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        $.rateProviderData[asset] = AccountantWithRateProviders.RateProviderData({
            isPeggedToBase: isPeggedToBase, rateProvider: IRateProvider(rateProvider)
        });
        emit RateProviderUpdated(address(asset), isPeggedToBase, rateProvider);
    }

    /// @notice Updates this contract exchangeRate
    /// @dev    If new exchange rate is outside of accepted bounds, or if not enough time has passed, this
    ///         will pause the contract, accrue management fees for the elapsed period, and advance the
    ///         lastUpdateTimestamp to prevent fee double-charging on the next valid update.
    /// @dev    Callable by UPDATE_EXCHANGE_RATE_ROLE
    /// @param  _newExchangeRate uint96 The new exchange rate to set, expressed in the same units as `exchangeRate`
    function updateExchangeRate(uint96 _newExchangeRate) external requiresAuth {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        DataTypes.AccountantState storage _state = $.accountantState;
        uint64 _currentTime = uint64(block.timestamp);
        uint256 _currentExchangeRate = _state.exchangeRate;
        uint256 _currentTotalShares = IERC20(SHARE).totalSupply();
        // When paused, skip the minimum delay check to allow immediate rate correction
        bool _invalid =
            (!_state.isPaused && _currentTime < _state.lastUpdateTimestamp + _state.minimumUpdateDelayInSeconds)
                || _newExchangeRate
                    > _currentExchangeRate.mulDivDown(_state.allowedExchangeRateChangeUpper, DENOMINATOR)
                || _newExchangeRate
                    < _currentExchangeRate.mulDivDown(_state.allowedExchangeRateChangeLower, DENOMINATOR);
        uint256 _timeDelta;
        uint256 _managementFeesAnnual;
        uint256 _newFeesOwedInBase;
        if (_invalid) {
            // Only accrue fees and pause if not already paused (to avoid redundant fee accrual)
            if (!_state.isPaused) {
                _timeDelta = _currentTime - _state.lastUpdateTimestamp;

                uint256 _assets = uint256(_state.totalSharesLastUpdate).mulDivDown(_currentExchangeRate, ONE_SHARE);

                _managementFeesAnnual = _assets.mulDivDown(_state.managementFee, DENOMINATOR);
                _newFeesOwedInBase = _managementFeesAnnual.mulDivDown(_timeDelta, ONE_YEAR);

                _state.feesOwedInBase += uint128(_newFeesOwedInBase);

                _state.isPaused = true;
                emit ExchangeRateUpdatePaused(uint96(_currentExchangeRate), _newExchangeRate, _currentTime);
            }
            // Update timestamp and shares even while paused to prevent fee double-charging
            _state.lastUpdateTimestamp = _currentTime;
            _state.totalSharesLastUpdate = uint128(_currentTotalShares);

            return;
        }

        uint256 _shareSupplyToUse = _currentTotalShares;

        if (_state.totalSharesLastUpdate < _shareSupplyToUse) {
            _shareSupplyToUse = _state.totalSharesLastUpdate;
        }

        _timeDelta = _currentTime - _state.lastUpdateTimestamp;

        uint256 _minimumAssets = _newExchangeRate > _currentExchangeRate
            ? _shareSupplyToUse.mulDivDown(_currentExchangeRate, ONE_SHARE)
            : _shareSupplyToUse.mulDivDown(_newExchangeRate, ONE_SHARE);

        _managementFeesAnnual = _minimumAssets.mulDivDown(_state.managementFee, DENOMINATOR);
        _newFeesOwedInBase = _managementFeesAnnual.mulDivDown(_timeDelta, ONE_YEAR);

        _state.feesOwedInBase += uint128(_newFeesOwedInBase);

        _state.exchangeRate = _newExchangeRate;
        _state.totalSharesLastUpdate = uint128(_currentTotalShares);
        _state.lastUpdateTimestamp = _currentTime;

        emit ExchangeRateUpdated(uint96(_currentExchangeRate), _newExchangeRate, _currentTime);
    }

    // ========================================= RATE FUNCTIONS =========================================

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
        DataTypes.AccountantState storage accountantState = $.accountantState;
        if (address(_quote) == address(base)) {
            _rateInQuote = accountantState.exchangeRate;
        } else {
            AccountantWithRateProviders.RateProviderData memory _data = $.rateProviderData[_quote];
            uint8 _quoteDecimals = ERC20(_quote).decimals();
            (uint256 _exchangeRateInQuoteDecimals,) =
                changeDecimals(accountantState.exchangeRate, baseDecimals, _quoteDecimals);
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
    function getAccountantState() public view virtual returns (DataTypes.AccountantState memory) {
        NestAccountantStorage storage $ = _getNestAccountantStorage();
        return $.accountantState;
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
    function changeDecimals(uint256 _amount, uint8 _fromDecimals, uint8 _toDecimals)
        internal
        pure
        returns (uint256 _amountAdjusted, uint128 _remainder)
    {
        if (_fromDecimals == _toDecimals) {
            _amountAdjusted = _amount;
        } else if (_fromDecimals < _toDecimals) {
            _amountAdjusted = _amount * 10 ** (_toDecimals - _fromDecimals);
        } else {
            _amountAdjusted = _amount / 10 ** (_fromDecimals - _toDecimals);
            _remainder = uint128(_amount % 10 ** (_fromDecimals - _toDecimals));
        }
    }
}
