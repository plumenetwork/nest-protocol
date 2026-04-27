// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// contracts
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {
    ReentrancyGuardTransientUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {NestAccountant} from "contracts/NestAccountant.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC7540Redeem, IERC7540Operator} from "contracts/interfaces/IERC7540.sol";
import {IERC7575} from "forge-std/interfaces/IERC7575.sol";

// libraries
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {Errors} from "contracts/types/Errors.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {NestVaultOperatorLogic} from "contracts/libraries/nest-vault/NestVaultOperatorLogic.sol";
import {NestVaultRedeemLogic} from "contracts/libraries/nest-vault/NestVaultRedeemLogic.sol";
import {NestVaultDepositLogic} from "contracts/libraries/nest-vault/NestVaultDepositLogic.sol";
import {NestVaultAdminLogic} from "contracts/libraries/nest-vault/NestVaultAdminLogic.sol";
import {NestVaultAccountingLogic} from "contracts/libraries/nest-vault/NestVaultAccountingLogic.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {NestVaultCoreValidationLogic} from "contracts/libraries/nest-vault/NestVaultCoreValidationLogic.sol";
import {NestVaultTransferLogic} from "contracts/libraries/nest-vault/NestVaultTransferLogic.sol";

/// @title  NestVaultCore
/// @notice NestVaultCore is an IERC7575 & IERC7540Redeem-compatible vault.
///         It allows users to deposit assets and mint shares, redeem shares for assets, and interact with operators
///         via the ERC7540 standard.
/// @dev    This contract delegates deposit and redeem operations to external logic libraries:
///         - NestVaultDepositLogic: handles deposits via NestShareOFT.enter()
///         - NestVaultRedeemLogic: handles redemptions via NestShareOFT.exit()
///         Asset movement is managed entirely by these libraries calling the share token directly.
///         Inheriting contracts should NOT attempt to override asset movement behavior - customization
///         should be done by modifying the logic libraries or the NestShareOFT implementation.
///         This contract is upgradeable using OpenZeppelin's Initializable pattern and provides
///         ERC4626-compatible accounting with ERC7540 operator/redeem extensions.
/// @author plumenetwork
abstract contract NestVaultCore is
    Initializable,
    ERC4626Upgradeable,
    AuthUpgradeable,
    EIP712Upgradeable,
    IERC7540Operator,
    IERC7540Redeem,
    ERC165,
    ReentrancyGuardTransientUpgradeable
{
    using NestVaultOperatorLogic for NestVaultCoreTypes.NestVaultCoreStorage;
    using NestVaultRedeemLogic for NestVaultCoreTypes.NestVaultCoreStorage;
    using NestVaultDepositLogic for NestVaultCoreTypes.NestVaultCoreStorage;
    using NestVaultAdminLogic for NestVaultCoreTypes.NestVaultCoreStorage;
    using NestVaultCoreValidationLogic for NestVaultCoreTypes.NestVaultCoreStorage;
    using NestVaultAccountingLogic for uint256;
    using NestVaultTransferLogic for ERC20;

    /// @dev This is used to track the redemption request ID, which is initialized to 0 for the contract.
    uint256 internal constant REQUEST_ID = 0;

    /// @dev This is an immutable variable that stores the address of the share token to honour ERC7575 specs
    NestShareOFT internal immutable SHARE;

    /// @dev    the fee is denominated in basis points described by 1e6
    uint32 internal constant FEE_CAP = 0.2e6; // 20%

    /// @dev maximum exchange rate allowed
    uint256 internal constant UPPER_BOUND_RATE_CAP = 1e30;

    // keccak256(abi.encode(uint256(keccak256("plumenetwork.storage.NestVaultCore")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NestVaultCoreStorageLocation =
        0x8d327cc9157d67bbcdfb7458a8210f70aaa0f2cbd2dc6f3d23140e557560c200;

    /// @notice Initializes the contract with the address of the SHARE token.
    /// @dev The constructor initializes the SHARE address.
    /// @param _share The address of the share token
    constructor(address payable _share) {
        if (_share == address(0)) revert Errors.ZeroAddress();

        SHARE = NestShareOFT(_share);
        _disableInitializers();
    }

    /// @dev Internal function to access the contract's NestAccountant slot
    /// @return $ A reference to the NestVaultCoreTypes.NestVaultCoreStorage struct
    function _getNestVaultCoreStorage() internal pure returns (NestVaultCoreTypes.NestVaultCoreStorage storage $) {
        assembly {
            $.slot := NestVaultCoreStorageLocation
        }
    }

    /// @notice Initializes the vault with the necessary configurations.
    /// @dev    Initializes key components such as the accountant, asset, owner, and operator registry.
    /// @param  _accountant       address The address of the NestAccountant contract
    /// @param  _asset            address The underlying asset that users deposit (e.g., ERC20 token)
    /// @param  _owner            address The address of the owner of the vault
    /// @param  _minRate          uint256 The minimum rate allowed for the vault
    /// @param  _operatorRegistry address The operator registry (zero disables registry)
    function __NestVaultCore_init(
        address _accountant,
        address _asset,
        address _owner,
        uint256 _minRate,
        address _operatorRegistry,
        string memory _version
    ) internal onlyInitializing {
        __NestVaultCore_init_unchained(_accountant, _asset, _owner, _minRate, _operatorRegistry);
        __EIP712_init(SHARE.name(), _version);
        __ERC4626_init(IERC20(_asset));
        __Auth_init(_owner, Authority(address(0)));
    }

    /// @dev Internal function to initialize the contract's state
    /// @param  _accountant       address The address of the NestAccountant contract
    /// @param  _asset            address The underlying asset that users deposit (e.g., ERC20 token)
    /// @param  _owner            address The address of the owner of the vault
    /// @param  _minRate          uint256 The minimum rate allowed for the vault
    /// @param  _operatorRegistry address The operator registry (zero disables registry)
    function __NestVaultCore_init_unchained(
        address _accountant,
        address _asset,
        address _owner,
        uint256 _minRate,
        address _operatorRegistry
    ) internal onlyInitializing {
        if (_accountant == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_asset == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_owner == address(0)) {
            revert Errors.ZeroAddress();
        }
        NestVaultCoreTypes.NestVaultCoreStorage storage $ = _getNestVaultCoreStorage();

        if (_minRate >= 10 ** IERC20Metadata(_asset).decimals()) {
            revert Errors.InvalidRate();
        }
        $.accountant = NestAccountant(_accountant);
        $.maxFees[NestVaultCoreTypes.Fees.InstantRedemption] = FEE_CAP;
        $.minRate = _minRate;
        $.executeSetOperatorRegistry(_operatorRegistry);
    }

    /// @notice Returns the `SHARE` address
    /// @dev    ERC-7575 compliant view
    /// @return address Address of the share
    function share() external view virtual returns (address) {
        return address(SHARE);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the decimals of the token, sourced from the SHARE
    /// @dev    The decimals are inherited from the share token
    /// @return uint8 The number of decimals used by the token
    function decimals() public view override returns (uint8) {
        return SHARE.decimals();
    }

    /// @notice Returns the name of the token, sourced from the SHARE
    /// @dev    The name is inherited from the share token
    /// @return string The name of the token
    function name() public view override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
        return SHARE.name();
    }

    /// @notice Returns the symbol of the token, sourced from the SHARE.
    /// @dev    The symbol is inherited from the share token.
    /// @return string The symbol of the token.
    function symbol() public view override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
        return SHARE.symbol();
    }

    /// @notice Returns the total supply of the token, sourced from the SHARE.
    /// @dev    The total supply is inherited from the share token.
    /// @return uint256 The total supply of the token.
    function totalSupply() public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        return SHARE.totalSupply();
    }

    /// @notice Returns the balance of a specific account, sourced from the SHARE.
    /// @dev    The balance is inherited from the share token.
    /// @param  _account address The address of the account to query.
    /// @return uint256 The balance of the specified account.
    function balanceOf(address _account) public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        return SHARE.balanceOf(_account);
    }

    /// @notice Returns the allowance of a spender for a specific owner, sourced from the SHARE.
    /// @dev    The allowance is inherited from the share token.
    /// @param  _owner   address The address of the token owner.
    /// @param  _spender address The address of the spender.
    /// @return uint256 The remaining allowance for the spender on behalf of the owner.
    function allowance(address _owner, address _spender)
        public
        view
        override(ERC20Upgradeable, IERC20)
        returns (uint256)
    {
        return SHARE.allowance(_owner, _spender);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC7540 OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets an operator for a given controller
    /// @dev    Allows controllers to set approved operators. Operators can perform actions on behalf of the controller
    /// @param  _operator  address The address of the operator
    /// @param  _approved  bool    Whether the operator is approved or not
    /// @return _success   bool    A boolean indicating the success of the operation
    function setOperator(address _operator, bool _approved) public override returns (bool _success) {
        return _getNestVaultCoreStorage().executeSetOperator(_operator, _approved, msg.sender);
    }

    /// @notice Checks whether an operator is authorized for a given controller.
    /// @dev    The mapping tracks which operators have permission to act on behalf of each controller.
    /// @param  _controller  address The address of the controller whose operator permissions are being queried.
    /// @param  _operator    address The address of the operator being checked.
    /// @return              bool    True if the operator is authorized for the controller, otherwise false.
    function isOperator(address _controller, address _operator) external view override returns (bool) {
        return _getNestVaultCoreStorage().isOperator(_controller, _operator);
    }

    /*//////////////////////////////////////////////////////////////
                        EIP-7441 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorizes an operator for a controller, using a signature to validate
    /// @dev    The authorization is verified via EIP712 signatures.
    /// @param  _controller address The controller's address
    /// @param  _operator   address The operator's address
    /// @param  _approved   bool    Whether the operator is approved or not
    /// @param  _nonce      bytes32 A unique identifier for the authorization
    /// @param  _deadline   uint256 The deadline for the authorization
    /// @param  _signature  bytes   The signature to validate the authorization
    /// @return _success   bool    A boolean indicating the success of the operation
    function authorizeOperator(
        address _controller,
        address _operator,
        bool _approved,
        bytes32 _nonce,
        uint256 _deadline,
        bytes memory _signature
    ) public returns (bool _success) {
        return _getNestVaultCoreStorage()
            .executeAuthorizeOperator(
                _controller, _operator, _approved, _nonce, _deadline, _signature, EIP712Upgradeable._domainSeparatorV4()
            );
    }

    /*//////////////////////////////////////////////////////////////
                        ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if the contract supports a given interface
    /// @dev    Supports IERC165, IERC7540Operator, IERC7575, IERC7540Redeem, IERC20, IERC20Metadata
    ///         and ERC7540Redeem interfaces
    /// @param  _interfaceId bytes4 The interface ID to check for support
    /// @return              bool   true if the contract supports the given interface ID, false otherwise
    function supportsInterface(bytes4 _interfaceId) public pure override returns (bool) {
        return _interfaceId == type(IERC7540Operator).interfaceId || _interfaceId == type(IERC165).interfaceId
            || _interfaceId == type(IERC7540Redeem).interfaceId || _interfaceId == type(IERC7575).interfaceId
            || _interfaceId == type(IERC20).interfaceId || _interfaceId == type(IERC20Metadata).interfaceId;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC7540Redeem OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC7540Redeem
    function requestRedeem(uint256 _shares, address _controller, address _owner)
        external
        override
        requiresAuth
        returns (uint256 _requestId)
    {
        ERC20(address(SHARE)).safeTransferFrom(_owner, address(this), _shares);
        _requestId = _getNestVaultCoreStorage()
            .executeRequestRedeem(_shares, _controller, _owner, msg.sender, ERC20(address(SHARE)));
    }

    /// @inheritdoc IERC7540Redeem
    function pendingRedeemRequest(uint256, address _controller) public view override returns (uint256 _pendingShares) {
        _pendingShares = _getNestVaultCoreStorage().pendingRedeem[_controller].shares;
    }

    /// @inheritdoc IERC7540Redeem
    function claimableRedeemRequest(uint256, address _controller)
        public
        view
        override
        returns (uint256 _claimableShares)
    {
        _claimableShares = _getNestVaultCoreStorage().claimableRedeem[_controller].shares;
    }

    /*//////////////////////////////////////////////////////////////
                        REDEMPTION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Fulfills pending redeem shares and credits claimable balances for a controller
    /// @dev    Validates pending state, converts shares to assets at the current rate, exits through `NestShareOFT`,
    ///         and updates pending/claimable redeem state. Restricted to authorized callers.
    /// @param  _controller address The controller address requesting the redeem
    /// @param  _shares     uint256 The number of shares being redeemed
    /// @return  _assets    uint256 The asset amount computed from `_shares` at the current rate
    function fulfillRedeem(address _controller, uint256 _shares)
        public
        requiresAuth
        nonReentrant
        returns (uint256 _assets)
    {
        _assets = _getNestVaultCoreStorage()
            .executeFulfillRedeem(_controller, _shares, SHARE, ERC20(asset()), _getValidatedRate());
    }

    /// @notice Redeems shares instantly by transferring assets directly to a specified receiver and deducting applicable fees
    /// @dev    This function is used for immediate redemption of shares and ensures that the fees are deducted from the amount
    ///         transferred to the receiver. The function requires approval from the share owner, and the share balance must be
    ///         sufficient for the redemption. It also calculates and applies the necessary fee deductions before transferring
    ///         the assets.InstantRedeem Emitted after the instant redemption is completed, with details about the shares redeemed,
    ///         the total post-fee amount, the fee amount deducted, and the receiver address
    /// @param  _shares         uint256 The number of shares to redeem instantly
    /// @param  _receiver       address The address to which the assets will be sent
    /// @param  _owner          address The owner of the shares being redeemed
    /// @return _postFeeAmount  uint256 The amount of assets received by the receiver after fees
    /// @return _feeAmount      uint256 The fee deducted from the total redemption amount
    function instantRedeem(uint256 _shares, address _receiver, address _owner)
        public
        requiresAuth
        nonReentrant
        returns (uint256 _postFeeAmount, uint256 _feeAmount)
    {
        ERC20(address(SHARE)).safeTransferFrom(_owner, address(this), _shares);
        (_postFeeAmount, _feeAmount) = _getNestVaultCoreStorage()
            .executeInstantRedeem(_shares, _receiver, _owner, msg.sender, SHARE, ERC20(asset()), _getValidatedRate());
    }

    /// @notice Update the number of shares in an existing redeem request
    /// @dev    Allows the controller or an authorized operator to reduce a pending redeem amount.
    ///         - If `_newShares` is lower, the difference in shares is returned to `_receiver`
    ///         - If `_newShares` equals the current pending shares, this is a no-op
    ///         - `_newShares` cannot exceed the current pending shares
    ///         - Redeem requests must already exist; otherwise this reverts
    /// @param  _newShares  uint256  The new amount of shares to set for the redeem request
    /// @param  _controller address  The controller address associated with this redeem request
    /// @param  _receiver   address  The address receiving the returned shares
    function updateRedeem(uint256 _newShares, address _controller, address _receiver) external requiresAuth {
        _getNestVaultCoreStorage()
            .executeUpdateRedeem(_newShares, _controller, _receiver, msg.sender, ERC20(address(SHARE)));
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Withdraws a specified amount of assets from the vault, transferring them to the receiver
    /// @dev    This function reduces the claimable assets for the controller and calculates the corresponding shares
    /// @param  _assets     uint256 The number of assets to withdraw
    /// @param  _receiver   address The address of the receiver
    /// @param  _controller address The controller address requesting the withdrawal
    /// @return  _shares    uint256 The number of shares burned for the withdrawal
    function withdraw(uint256 _assets, address _receiver, address _controller)
        public
        override
        requiresAuth
        returns (uint256 _shares)
    {
        _shares = _getNestVaultCoreStorage()
            .executeWithdraw(_assets, _receiver, _controller, msg.sender, ERC20(asset()));
    }

    /// @notice Redeems a specified number of shares for assets
    /// @dev    This function performs the redemption, reducing the claimable assets and shares, and transferring the
    ///         appropriate amount of assets to the receiver
    /// @param  _shares     uint256 The number of shares to redeem
    /// @param  _receiver   address The address of the receiver
    /// @param  _controller address The controller address requesting the redeem
    /// @return  _assets    uint256 The amount of assets redeemed for the shares
    function redeem(uint256 _shares, address _receiver, address _controller)
        public
        override
        requiresAuth
        returns (uint256 _assets)
    {
        _assets = _getNestVaultCoreStorage().executeRedeem(_shares, _receiver, _controller, msg.sender, ERC20(asset()));
    }

    /// @dev   This function performs the asset transfer from the caller, enters the nest share, and mints the appropriate number of shares
    /// @param _receiver address The address receiving the minted shares
    /// @param _assets   uint256 The amount of assets being deposited
    /// @param _shares   uint256 The number of shares being minted
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal virtual override {
        _getNestVaultCoreStorage()
            .executeDeposit(
                _caller, _receiver, _assets, _shares, SHARE, ERC20(asset()), isAuthorized(_msgSender(), msg.sig)
            );
    }

    /// @dev   Internal helper to validate rate from external rate provider
    /// @param _rate uint256 The validated rate obtained from the rate provider
    function _getValidatedRate() internal view returns (uint256 _rate) {
        NestVaultCoreTypes.NestVaultCoreStorage storage $ = _getNestVaultCoreStorage();

        _rate = $.accountant.getRateInQuoteSafe(ERC20(asset()));

        // prevent division by zero
        if (_rate == 0) revert Errors.InvalidRate();

        // prevent extreme values
        if (_rate < $.minRate || _rate > UPPER_BOUND_RATE_CAP) {
            revert Errors.RateOutOfBounds();
        }
    }

    /// @inheritdoc ERC4626Upgradeable
    function _convertToShares(uint256 _assets, Math.Rounding _rounding) internal view override returns (uint256) {
        return _assets.convertToShares(_getValidatedRate(), SHARE, _rounding);
    }

    /// @inheritdoc ERC4626Upgradeable
    function _convertToAssets(uint256 _shares, Math.Rounding _rounding) internal view override returns (uint256) {
        return _shares.convertToAssets(_getValidatedRate(), SHARE, _rounding);
    }

    /// @dev     This function calculates the post-fee asset amount and instant fee amount based on the shares redeemed.
    /// @param   _shares         uint256        Amount of nTokens to redeem.
    /// @return  _postFeeAmount  uint256         Post-fee asset amount
    /// @return  _feeAmount      uint256         Fee amount
    function _convertToAssetsForInstantRedeem(uint256 _shares)
        internal
        view
        returns (uint256 _postFeeAmount, uint256 _feeAmount)
    {
        uint256 _assets = _convertToAssets(_shares, Math.Rounding.Floor);
        (_postFeeAmount, _feeAmount) =
            _assets.calculatePostFeeAmounts(_getNestVaultCoreStorage().fees[NestVaultCoreTypes.Fees.InstantRedemption]);
    }

    /// @inheritdoc ERC4626Upgradeable
    function totalAssets() public view override returns (uint256) {
        return totalSupply().convertToAssets(_getValidatedRate(), SHARE, Math.Rounding.Floor);
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxWithdraw(address _controller) public view virtual override returns (uint256) {
        return _getNestVaultCoreStorage().claimableRedeem[_controller].assets;
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxRedeem(address _controller) public view virtual override returns (uint256) {
        return _getNestVaultCoreStorage().claimableRedeem[_controller].shares;
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewWithdraw(uint256) public pure virtual override returns (uint256) {
        revert Errors.ERC7540AsyncFlow();
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewRedeem(uint256) public pure virtual override returns (uint256) {
        revert Errors.ERC7540AsyncFlow();
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates accountant with rate provider
    /// @dev    Only authorized entity can update rate provider.
    ///         Compatibility note:
    ///         - Legacy AccountantWithRateProviders is supported.
    ///         - Global pending-share methods are treated as optional and handled best-effort.
    /// @param _accountant address rate provider address
    function setAccountant(address _accountant) external requiresAuth {
        _getNestVaultCoreStorage().executeSetAccountant(_accountant, ERC20(asset()));
    }

    /// @notice Set fee
    /// @dev    This function allows an authorized entity to set the fee amount for a specific fee type.
    /// @param  _f    NestVaultCoreTypes.Fees   Fee
    /// @param  _fee  uint32                    Fee amount
    function setFee(NestVaultCoreTypes.Fees _f, uint32 _fee) external requiresAuth {
        _getNestVaultCoreStorage().executeSetFee(_f, _fee);
    }

    /// @notice Sets the operator registry used for global operator approvals
    /// @param _operatorRegistry address The operator registry (zero disables registry)
    function setOperatorRegistry(address _operatorRegistry) external requiresAuth {
        _getNestVaultCoreStorage().executeSetOperatorRegistry(_operatorRegistry);
    }

    /// @notice Claims accrued fees for a fee type to a receiver
    /// @dev    Restricted to authorized callers
    /// @param  _f          NestVaultCoreTypes.Fees The fee type being claimed
    /// @param  _receiver   address                 The address receiving claimed fees
    /// @return _feeAmount  uint256                 The amount of fees claimed
    function claimFee(NestVaultCoreTypes.Fees _f, address _receiver)
        external
        requiresAuth
        nonReentrant
        returns (uint256 _feeAmount)
    {
        _feeAmount = _getNestVaultCoreStorage().executeClaimFee(_f, _receiver, ERC20(asset()));
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Preview the result of an instant redeem operation
    /// @dev    Allows an on-chain or off-chain user to simulate the effects of their instant redemption at the current block, given
    ///         current on-chain conditions.
    /// @param  _shares         uint256 The number of shares to be redeemed instantly
    /// @return _postFeeAmount  uint256 The amount of assets that would be received after fees
    /// @return _feeAmount      uint256 The fee amount that would be deducted
    function previewInstantRedeem(uint256 _shares) public view returns (uint256 _postFeeAmount, uint256 _feeAmount) {
        (_postFeeAmount, _feeAmount) = _convertToAssetsForInstantRedeem(_shares);
    }

    /// @notice Mapping of fees for different operations in the contract
    /// @dev    The `fees` mapping associates each fee type (Deposit, Redemption, InstantRedemption) with its corresponding fee percentage
    ///         For example, a value of 5000 represents a 0.5% fee (5000 / 1000000)
    ///         Authorized users can modify these fees directly through this public mapping
    /// @param  _f   NestVaultCoreTypes.Fees  The fee type for which the fee amount is requested
    /// @return _fee uint32          fee in basis point
    function fees(NestVaultCoreTypes.Fees _f) external view returns (uint32 _fee) {
        _fee = _getNestVaultCoreStorage().fees[_f];
    }

    /// @notice The minimum rate allowed for exchange rate calculations
    /// @dev    It represents the smallest allowed rate
    /// @return uint256 min rate
    function minRate() external view returns (uint256) {
        return _getNestVaultCoreStorage().minRate;
    }

    /// @notice The total number of pending shares for redemption
    /// @dev    This value represents the total shares that are currently pending redemption across all controllers
    /// @return uint256 total pending shares
    function totalPendingShares() external view returns (uint256) {
        return _getNestVaultCoreStorage().totalPendingShares;
    }

    /// @notice Returns the configured maximum fee for a fee type
    /// @dev    Fee caps use 1e6 precision (e.g., 200000 = 20%) and are enforced by `setFee`.
    /// @param  f NestVaultCoreTypes.Fees the type of fee
    /// @return   uint32         fee in basis points
    function maxFees(NestVaultCoreTypes.Fees f) external view returns (uint32) {
        return _getNestVaultCoreStorage().maxFees[f];
    }

    /// @notice Total unclaimed fees for a given fee type denominated in vault assets
    /// @param  _f NestVaultCoreTypes.Fees The fee type to query
    /// @return uint256 The total unclaimed fee amount for the fee type
    function claimableFees(NestVaultCoreTypes.Fees _f) external view returns (uint256) {
        return _getNestVaultCoreStorage().claimableFees[_f];
    }

    /// @notice Mapping to track whether a particular authorization has been used for a specific controller address
    /// @dev    This mapping prevents replay attacks by ensuring that authorizations cannot be reused
    /// @param  _controller  address The address of the controller whose authorization is being checked
    /// @param  _nonce       bytes32 The unique bytes32 nonce representing a specific authorization attempt
    /// @return              bool     whether controller has been authorized or not
    function authorizations(address _controller, bytes32 _nonce) external view returns (bool) {
        return _getNestVaultCoreStorage().authorizations[_controller][_nonce];
    }

    /// @notice Returns the accountant with rate providers used to obtain asset conversion rates
    /// @dev    The accountant is responsible for providing up-to-date conversion rates between assets and shares,
    ///         enabling accurate calculations for deposits, withdrawals, and redemptions
    /// @return NestAccountant The NestAccountant contract associated with the vault
    function accountant() external view returns (NestAccountant) {
        return _getNestVaultCoreStorage().accountant;
    }

    /// @notice Returns the configured operator registry
    /// @return OperatorRegistry The operator registry contract (zero if disabled)
    function operatorRegistry() external view returns (OperatorRegistry) {
        return _getNestVaultCoreStorage().operatorRegistry;
    }
}
