// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// libraries
import {PMath} from "@pendle/core-v2/contracts/core/libraries/math/PMath.sol";
import {ArrayLib} from "@pendle/core-v2/contracts/core/libraries/ArrayLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// contracts
import {SYBaseUpgV2} from "contracts/vendor/Pendle/SYBaseUpgV2.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MerklRewardAbstract__NoStorage} from "contracts/vendor/Pendle/MerklRewardAbstract__NoStorage.sol";
import {AccountantWithRateProviders} from "@boring-vault/src/base/Roles/AccountantWithRateProviders.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVaultSYStorage} from "contracts/BoringVaultSYStorage.sol";

// types
import {Errors} from "contracts/types/Errors.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title BoringVaultSY
/// @author PlumeNetwork
/// @notice A specialized vault that integrates with Pendle and rate providers via an external accountant.
/// @dev Inherits from Pendle SY base contracts, enabling yield-bearing asset management and Merkl reward distribution.
///      Reference : https://github.com/pendle-finance/Pendle-SY-Public/blob/21ccfee6c24936fb73c1ae78d1a87c83b05f105c/contracts/core/StandardizedYield/implementations/PendleERC4626NoRedeemNoDepositUpgSY.sol
contract BoringVaultSY is Initializable, SYBaseUpgV2, MerklRewardAbstract__NoStorage, BoringVaultSYStorage {
    /// @notice The base asset associated with this vault (ERC20 token address)
    /// @dev Immutable; set once at deployment
    address public immutable asset;

    /// @notice The minimum rate allowed for exchange calculation
    /// @dev This constant represents the smallest allowed rate
    uint256 public immutable MIN_RATE;

    /// @notice The maximum rate allowed for certain calculations (e.g., fee rates)
    /// @dev This constant prevents overflow by capping the rate at 1e30 in base units
    uint256 public constant MAX_RATE = 1e30; // Example: prevent overflow

    /// @dev Ensures consistent math when converting between shares and assets
    uint256 internal immutable ONE_SHARE;

    /// @notice Constructs the PendleNestVault contract
    /// @param _erc4626 The ERC4626-compatible yield token (SYBase) to wrap
    /// @param _offchainRewardManager The address managing off-chain Merkl reward reporting
    /// @param _asset The address of underlying asset
    /// @param _minRate The minimum rate allowed for the vault, it should be less than the decimals of the underlying asset
    constructor(address _erc4626, address _offchainRewardManager, address _asset, uint256 _minRate)
        SYBaseUpgV2(_erc4626)
        MerklRewardAbstract__NoStorage(_offchainRewardManager)
    {
        asset = _asset;
        ONE_SHARE = 10 ** IERC20Metadata(_erc4626).decimals();
        if (_minRate >= 10 ** IERC20Metadata(_asset).decimals()) {
            revert Errors.INVALID_RATE();
        }
        MIN_RATE = _minRate;
    }

    /// @notice Initializes the PendleNestVault after deployment
    /// @dev Should be called only once. Sets vault metadata and the rate accountant
    /// @param _accountantWithRateProviders The address of accountant with rate providers
    /// @param _name The vault token name
    /// @param _symbol The vault token symbol
    /// @param _owner The address with ownership privileges
    function initialize(
        address _accountantWithRateProviders,
        string memory _name,
        string memory _symbol,
        address _owner
    ) external virtual initializer {
        accountantWithRateProviders = AccountantWithRateProviders(_accountantWithRateProviders);
        __SYBaseUpgV2_init(_name, _symbol, _owner);
    }

    /// @dev Returns 1:1 shares for deposited amount since vault and token are equivalent.
    /// @param amountDeposited The amount of token deposited.
    /// @return amountSharesOut The amount of shares issued (equal to amountDeposited).
    function _deposit(
        address,
        /*tokenIn*/
        uint256 amountDeposited
    )
        internal
        virtual
        override
        returns (
            uint256 /*amountSharesOut*/
        )
    {
        return amountDeposited;
    }

    /// @dev Transfers out the corresponding amount of yield tokens to the receiver.
    /// @param receiver The address receiving redeemed tokens.
    /// @param amountSharesToRedeem The amount of shares to redeem.
    /// @return amountRedeemed The amount of underlying tokens redeemed (equal to shares).
    function _redeem(
        address receiver,
        address,
        /*tokenOut*/
        uint256 amountSharesToRedeem
    )
        internal
        virtual
        override
        returns (uint256)
    {
        _transferOut(yieldToken, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /// @notice Returns the current exchange rate between assets and shares
    /// @dev Uses rate provided by the accountant and normalized by `ONE_SHARE`
    /// @return The exchange rate as a fixed-point number
    function exchangeRate() public view virtual override returns (uint256) {
        return Math.mulDiv(PMath.ONE, _getValidatedRate(), ONE_SHARE, Math.Rounding.Floor);
    }

    /// @dev Returns 1:1 shares for deposit previews.
    /// @param amountTokenToDeposit The amount of input tokens to deposit.
    /// @return amountSharesOut The expected number of shares to be minted.
    function _previewDeposit(
        address,
        /*tokenIn*/
        uint256 amountTokenToDeposit
    )
        internal
        view
        virtual
        override
        returns (
            uint256 /*amountSharesOut*/
        )
    {
        return amountTokenToDeposit;
    }

    /// @dev Returns 1:1 token output for shares redeemed.
    /// @param amountSharesToRedeem The number of shares to redeem.
    /// @return amountTokenOut The expected token output amount.
    function _previewRedeem(
        address,
        /*tokenOut*/
        uint256 amountSharesToRedeem
    )
        internal
        view
        virtual
        override
        returns (
            uint256 /*amountTokenOut*/
        )
    {
        return amountSharesToRedeem;
    }

    /// @notice Returns the list of valid input tokens for deposits.
    /// @dev Always returns the yield token.
    /// @return res Array containing only the yield token address.
    function getTokensIn() public view virtual override returns (address[] memory res) {
        return ArrayLib.create(yieldToken);
    }

    /// @notice Returns the list of valid output tokens for withdrawals
    /// @dev Always returns the yield token
    /// @return res Array containing only the yield token address
    function getTokensOut() public view virtual override returns (address[] memory res) {
        return ArrayLib.create(yieldToken);
    }

    /// @notice Checks if a token is valid for deposits
    /// @param token The address of the token to check
    /// @return True if the token matches the yield token, false otherwise
    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == yieldToken;
    }

    /// @notice Checks if a token is valid for redemptions.
    /// @param token The address of the token to check.
    /// @return True if the token matches the yield token, false otherwise.
    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == yieldToken;
    }

    /// @notice Returns information about the underlying asset.
    /// @return assetType The type of asset (always TOKEN).
    /// @return assetAddress The address of the underlying ERC20 asset.
    /// @return assetDecimals The decimals of the underlying asset.
    function assetInfo()
        external
        view
        virtual
        returns (AssetType assetType, address assetAddress, uint8 assetDecimals)
    {
        return (AssetType.TOKEN, asset, IERC20Metadata(asset).decimals());
    }

    /// @dev Internal helper to validate rate from external oracle
    function _getValidatedRate() internal view returns (uint256 rate) {
        rate = accountantWithRateProviders.getRateInQuoteSafe(ERC20(asset));

        // prevent division by zero
        if (rate == 0) revert Errors.INVALID_RATE();

        // prevent extreme values
        if (rate < MIN_RATE || rate > MAX_RATE) {
            revert Errors.RATE_OUT_OF_BOUNDS();
        }

        return rate;
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates accountant with rate provider
    /// @dev Only authorized entity can update rate provider
    /// @param _accountantWithRateProviders rate provider address
    function setAccountantWithRateProviders(address _accountantWithRateProviders) external onlyOwner {
        if (_accountantWithRateProviders == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        accountantWithRateProviders = AccountantWithRateProviders(_accountantWithRateProviders);
    }
}
