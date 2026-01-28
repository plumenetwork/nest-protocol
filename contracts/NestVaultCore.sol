// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// contracts
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {AccountantWithRateProviders} from "@boring-vault/src/base/Roles/AccountantWithRateProviders.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {
    ReentrancyGuardTransientUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {NestAccountant} from "contracts/NestAccountant.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC7540Redeem, IERC7540Operator} from "contracts/interfaces/IERC7540.sol";
import {IERC7575} from "forge-std/interfaces/IERC7575.sol";

// libraries
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {DataTypes} from "contracts/types/DataTypes.sol";
import {Errors} from "contracts/types/Errors.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title  NestVaultCore
/// @notice NestVaultCore is an IERC7575 & IERC7540Redeem-compatible vault.
///         It allows users to deposit assets and mint shares, redeem shares for assets, and interact with operators
///         via the ERC7540 standard.
/// @dev    The vault inheriting from this contract must implement the _enter and _exit internal functions to define
///         specific behavior for asset management and share minting/burning.
///         This contract is upgradeable using OpenZeppelin's Initializable pattern. It inherits from ERC4626,
///         ERC20Permit, and implements the ERC7540 standard for operator authorization
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
    using FixedPointMathLib for uint256;

    struct NestVaultCoreStorage {
        // It represents the smallest allowed rate
        uint256 minRate;

        // This value is updated whenever a user requests or claims a redeem. It helps track the total shares
        // that are locked in pending redemptions and not available for new operations
        uint256 totalPendingShares;

        // This variable is used to determine the conversion rates between assets and shares, enabling accurate
        // calculation of deposits, withdrawals, and redemptions.
        AccountantWithRateProviders accountantWithRateProviders;

        // This mapping stores whether a given operator is authorized for a particular controller. It allows operators
        // to perform certain actions on behalf of the controller.
        mapping(address => mapping(address => bool)) isOperator;

        // This mapping prevents replay attacks by ensuring that authorizations cannot be reused.
        mapping(address controller => mapping(bytes32 nonce => bool used)) authorizations;

        // This mapping holds the shares of assets that are currently pending for redemption for a specific controller.
        mapping(address => DataTypes.PendingRedeem) pendingRedeem;

        // This mapping tracks the claimable amount of assets and shares for each controller once the redemption request
        // has been fulfilled.
        mapping(address => DataTypes.ClaimableRedeem) claimableRedeem;

        /// The `maxFees` mapping associates each fee type in `DataTypes.Fees` with its corresponding maximum fee percentage.
        /// For example, a value of 200000 represents a maximum fee of 20% (200000 / 1000000).
        /// Authorized users can modify these maximum fees directly through this public mapping.
        mapping(DataTypes.Fees => uint32) maxFees;

        /// The `fees` mapping associates each fee type (Deposit, Redemption, InstantRedemption) with its corresponding fee percentage.
        /// For example, a value of 5000 represents a 0.5% fee (5000 / 1000000).
        ///  Authorized users can modify these fees directly through this public mapping.
        mapping(DataTypes.Fees => uint32) fees;
    }

    /// @dev This is used to track the redemption request ID, which is initialized to 0 for the contract.
    uint256 internal constant REQUEST_ID = 0;

    /// @dev This value is used to convert between assets and shares and is based on the share's decimals.
    uint256 internal immutable ONE_SHARE;

    /// @dev This is an immutable variable that stores the address of the share token to honour ERC7575 specs
    NestShareOFT internal immutable SHARE;

    /// @dev    the fee is denominated in basis points described by 1e6
    uint32 internal constant FEE_CAP = 0.2e6; // 20%

    /// @dev maximum exchange rate allowed
    uint256 internal constant UPPER_BOUND_RATE_CAP = 1e30;

    // keccak256(abi.encode(uint256(keccak256("plumenetwork.storage.NestVaultCore")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NestVaultCoreStorageLocation =
        0x8d327cc9157d67bbcdfb7458a8210f70aaa0f2cbd2dc6f3d23140e557560c200;

    /// @dev   This event records the controller, number of shares, and assets that were redeemed, along with the actual amount of assets transferred
    /// @param controller   address indexed The address of the controller that requested the redemption
    /// @param shares       uint256         The number of shares redeemed
    /// @param assets       uint256         The amount of assets calculated for the redemption
    /// @param actualAssets uint256         The actual amount of assets transferred to the controller
    event RedeemFulfilled(address indexed controller, uint256 shares, uint256 assets, uint256 actualAssets);

    /// @dev    Use this event to log changes in the fee amount for a particular fee type, including the fee type and the new fee amount
    /// @param  f      DataTypes.Fees indexed for which the fee amount is being set
    /// @param  oldFee uint32                 Previous fee for the specified fee type
    /// @param  fee    uint32                 New fee amount for the specified fee type
    event SetFee(DataTypes.Fees indexed f, uint32 oldFee, uint32 fee);

    /// @dev   Emitted when an instant redemption is performed
    /// @param shares        uint256  Number of shares redeemed
    /// @param assets        uint256  Total asset value of the redeemed shares before fees
    /// @param postFeeAmount uint256  Asset amount received by the user after deducting fees
    /// @param receiver      address  Address receiving the redeemed assets
    event InstantRedeem(uint256 shares, uint256 assets, uint256 postFeeAmount, address receiver);

    /// @dev   Emitted when a redemption request is updated
    /// @param controller  address  The vault or controller managing the redemption
    /// @param owner       address  The owner of the shares being redeemed
    /// @param caller      address  The address initiating the update
    /// @param oldShares   uint256  Number of shares before the update
    /// @param newShares   uint256  Number of shares after the update
    event RedeemUpdated(address controller, address owner, address caller, uint256 oldShares, uint256 newShares);

    /// @notice Initializes the contract with the address of the SHARE token.
    /// @dev The constructor initializes the SHARE address and sets ONE_SHARE based on the vault's decimals
    /// @param _share The address of the share token
    constructor(address payable _share) {
        if (_share == address(0)) revert Errors.ZERO_ADDRESS();

        SHARE = NestShareOFT(_share);
        ONE_SHARE = 10 ** IERC20Metadata(_share).decimals();
        _disableInitializers();
    }

    /// @dev Internal function to access the contract's NestAccountant slot
    /// @return $ A reference to the NestVaultCore struct for reading/writing exchange rate
    function _getNestVaultCoreStorage() private pure returns (NestVaultCoreStorage storage $) {
        assembly {
            $.slot := NestVaultCoreStorageLocation
        }
    }

    /// @notice Initializes the vault with the necessary configurations.
    /// @dev    Initializes key components such as the accountant, asset, and owner.
    /// @param  _accountantWithRateProviders    address The address of the AccountantWithRateProviders contract
    /// @param  _asset                          address The underlying asset that users deposit (e.g., ERC20 token)
    /// @param  _owner                          address The address of the owner of the vault
    /// @param  _minRate                        uint256 The minimum rate allowed for the vault
    function __NestVaultCore_init(
        address _accountantWithRateProviders,
        address _asset,
        address _owner,
        uint256 _minRate,
        string memory _version
    ) internal onlyInitializing {
        __NestVaultCore_init_unchained(_accountantWithRateProviders, _asset, _owner, _minRate);
        __EIP712_init(SHARE.name(), _version);
        __ERC4626_init(IERC20(_asset));
        __Auth_init(_owner, Authority(address(0)));
    }

    /// @dev Internal function to initialize the contract's state
    /// @param  _accountantWithRateProviders    address The address of the AccountantWithRateProviders contract
    /// @param  _asset                          address The underlying asset that users deposit (e.g., ERC20 token)
    /// @param  _owner                          address The address of the owner of the vault
    /// @param  _minRate                        uint256 The minimum rate allowed for the vault
    function __NestVaultCore_init_unchained(
        address _accountantWithRateProviders,
        address _asset,
        address _owner,
        uint256 _minRate
    ) internal onlyInitializing {
        if (_accountantWithRateProviders == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        if (_asset == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        if (_owner == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        NestVaultCoreStorage storage $ = _getNestVaultCoreStorage();

        if (_minRate >= 10 ** IERC20Metadata(_asset).decimals()) {
            revert Errors.INVALID_RATE();
        }
        $.accountantWithRateProviders = AccountantWithRateProviders(_accountantWithRateProviders);
        $.maxFees[DataTypes.Fees.InstantRedemption] = FEE_CAP;
        $.minRate = _minRate;
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
                        ERC7540 OVERRIDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets an operator for a given controller
    /// @dev    Allows controllers to set approved operators. Operators can perform actions on behalf of the controller
    /// @param  _operator  address The address of the operator
    /// @param  _approved  bool    Whether the operator is approved or not
    /// @return _success   bool    A boolean indicating the success of the operation
    function setOperator(address _operator, bool _approved) public override returns (bool _success) {
        if (_operator == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        if (msg.sender == _operator) {
            revert Errors.ERC7540_SELF_OPERATOR_NOT_ALLOWED();
        }
        _getNestVaultCoreStorage().isOperator[msg.sender][_operator] = _approved;
        emit OperatorSet(msg.sender, _operator, _approved);
        _success = true;
    }

    /// @notice Checks whether an operator is authorized for a given controller.
    /// @dev    The mapping tracks which operators have permission to act on behalf of each controller.
    /// @param  _controller  address The address of the controller whose operator permissions are being queried.
    /// @param  _operator    address The address of the operator being checked.
    /// @return              bool    True if the operator is authorized for the controller, otherwise false.
    function isOperator(address _controller, address _operator) external view override returns (bool) {
        return _getNestVaultCoreStorage().isOperator[_controller][_operator];
    }

    /*//////////////////////////////////////////////////////////////
                        EIP-7441 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorizes an operator for a controller, using a signature to validate
    /// @dev    The authorization is verified via EIP712 signatures, ensuring security and non-repudiation
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
        if (_controller == address(0)) revert Errors.ZERO_ADDRESS();
        if (_operator == address(0)) revert Errors.ZERO_ADDRESS();
        if (_controller == _operator) {
            revert Errors.ERC7540_SELF_OPERATOR_NOT_ALLOWED();
        }
        if (block.timestamp > _deadline) {
            revert Errors.ERC7540_EXPIRED();
        }
        NestVaultCoreStorage storage $ = _getNestVaultCoreStorage();

        if ($.authorizations[_controller][_nonce]) {
            revert Errors.ERC7540_USED_AUTHORIZATION();
        }

        bytes32 _structHash = keccak256(
            abi.encode(
                keccak256(
                    "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint256 deadline)"
                ),
                _controller,
                _operator,
                _approved,
                _nonce,
                _deadline
            )
        );

        bytes32 _hash = MessageHashUtils.toTypedDataHash(EIP712Upgradeable._domainSeparatorV4(), _structHash);

        address _recoveredAddress = ECDSA.recover(_hash, _signature);

        if (_recoveredAddress != _controller) {
            revert Errors.INVALID_SIGNER();
        }

        $.authorizations[_controller][_nonce] = true;
        $.isOperator[_controller][_operator] = _approved;

        emit OperatorSet(_controller, _operator, _approved);

        _success = true;
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
                        ERC7540Redeem Override
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC7540Redeem
    function requestRedeem(uint256 _shares, address _controller, address _owner)
        external
        override
        requiresAuth
        returns (uint256 _requestId)
    {
        if (_controller == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        _isAuthorizedCaller(_owner);

        if (SHARE.balanceOf(_owner) < _shares) {
            revert Errors.INSUFFICIENT_BALANCE();
        }
        if (_shares == 0) {
            revert Errors.ZERO_SHARES();
        }

        SafeTransferLib.safeTransferFrom(ERC20(address(SHARE)), _owner, address(this), _shares);

        _requestId = _processRedeemRequest(_shares, _controller, _owner);
    }

    /// @notice Internal function to process a redeem request after shares have been transferred
    /// @dev    Updates pending redeem state and emits event
    /// @param  _shares     uint256 The number of shares being requested for redemption
    /// @param  _controller address The controller address for the redeem request
    /// @param  _owner      address The owner of the shares being redeemed
    /// @return _requestId  uint256 The request ID for the redemption
    function _processRedeemRequest(uint256 _shares, address _controller, address _owner)
        internal
        returns (uint256 _requestId)
    {
        NestVaultCoreStorage storage $ = _getNestVaultCoreStorage();

        uint256 _currentPendingShares = $.pendingRedeem[_controller].shares;
        $.pendingRedeem[_controller] = DataTypes.PendingRedeem(_shares + _currentPendingShares);

        $.totalPendingShares += _shares;

        emit RedeemRequest(_controller, _owner, REQUEST_ID, msg.sender, _shares);
        return REQUEST_ID;
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

    /// @notice Fulfills a redeem request by transferring the requested assets to the controller
    /// @dev    The function checks if the requested shares can be redeemed, calculates the corresponding asset amount
    ///         and performs the asset transfer. It updates the claimable balances and pending redeem shares accordingly
    ///         fulfillRedeem is restricted to authorized callers only.
    /// @param  _controller address The controller address requesting the redeem
    /// @param  _shares     uint256 The number of shares being redeemed
    /// @return  _assets    uint256 The amount of assets transferred to the controller
    function fulfillRedeem(address _controller, uint256 _shares)
        public
        requiresAuth
        nonReentrant
        returns (uint256 _assets)
    {
        NestVaultCoreStorage storage $ = _getNestVaultCoreStorage();

        DataTypes.PendingRedeem storage _request = $.pendingRedeem[_controller];

        if (_request.shares == 0 || _shares > _request.shares) {
            revert Errors.ZERO_SHARES();
        }

        _assets = convertToAssets(_shares);

        if (_assets == 0) {
            revert Errors.ZERO_ASSETS();
        }

        _request.shares -= _shares;

        $.totalPendingShares -= _shares;

        ERC20 _asset = ERC20(asset());

        uint256 initialBalance = _asset.balanceOf(address(this));

        _exit(address(this), _asset, _assets, address(this), _shares);

        uint256 finalBalance = _asset.balanceOf(address(this));

        // Check if the amount transferred matches the predicted amount
        uint256 actualTransfer = finalBalance - initialBalance;

        if (actualTransfer < _assets) {
            revert Errors.TRANSFER_INSUFFICIENT();
        }

        $.claimableRedeem[_controller] = DataTypes.ClaimableRedeem(
            $.claimableRedeem[_controller].assets + actualTransfer, $.claimableRedeem[_controller].shares + _shares
        );
        emit RedeemFulfilled(_controller, _shares, _assets, actualTransfer);
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
        _isAuthorizedCaller(_owner);

        if (SHARE.balanceOf(_owner) < _shares) {
            revert Errors.INSUFFICIENT_BALANCE();
        }
        if (_shares == 0) {
            revert Errors.ZERO_SHARES();
        }

        SafeTransferLib.safeTransferFrom(ERC20(address(SHARE)), _owner, address(this), _shares);

        (_postFeeAmount, _feeAmount) = _processInstantRedeem(_shares, _receiver);
    }

    /// @notice Internal function to process an instant redeem after shares have been transferred
    /// @dev    Calculates fees, transfers assets, and emits event
    /// @param  _shares         uint256 The number of shares being redeemed
    /// @param  _receiver       address The address to receive the assets
    /// @return _postFeeAmount  uint256 The amount of assets received after fees
    /// @return _feeAmount      uint256 The fee amount deducted
    function _processInstantRedeem(uint256 _shares, address _receiver)
        internal
        returns (uint256 _postFeeAmount, uint256 _feeAmount)
    {
        (_postFeeAmount, _feeAmount) = _convertToAssetsForInstantRedeem(_shares);

        ERC20 _asset = ERC20(asset());

        uint256 _initialReceiverBalance = _asset.balanceOf(_receiver);

        _exit(_receiver, _asset, _postFeeAmount, address(this), _shares);

        uint256 _finalReceiverBalance = _asset.balanceOf(_receiver);

        // Check if the amount transferred matches the predicted amount
        uint256 _receiverBalanceDelta = _finalReceiverBalance - _initialReceiverBalance;

        if (_receiverBalanceDelta < _postFeeAmount) {
            revert Errors.TRANSFER_INSUFFICIENT();
        }

        emit InstantRedeem(_shares, _postFeeAmount + _feeAmount, _postFeeAmount, _receiver);
    }

    /// @notice Update the number of shares in an existing redeem request
    /// @dev    Allows the owner or an authorized operator to decrease the pending redeem amount
    ///         - If `_newShares` is lower, excess shares are returned to the owner
    ///         - If `_newShares` is higher, additional shares are pulled from the owner
    ///         - Redeem requests must already exist; otherwise this reverts
    ///         - Ensures the caller is either the owner or an approved operator
    /// @param  _newShares  uint256  The new amount of shares to set for the redeem request
    /// @param  _controller address  The controller address associated with this redeem request
    /// @param  _owner      address  The owner of the shares being redeemed
    function updateRedeem(uint256 _newShares, address _controller, address _owner) external requiresAuth {
        _isAuthorizedCaller(_owner);
        _isAuthorizedCaller(_controller);

        NestVaultCoreStorage storage $ = _getNestVaultCoreStorage();
        uint256 _oldShares = $.pendingRedeem[_controller].shares;

        if (_oldShares == 0) {
            revert Errors.NO_PENDING_REDEEM();
        }

        if (_oldShares < _newShares) {
            revert Errors.INSUFFICIENT_BALANCE();
        }

        if (_newShares == _oldShares) {
            return;
        }

        uint256 _returnAmount = _oldShares - _newShares;

        $.totalPendingShares -= _returnAmount;

        $.pendingRedeem[_controller].shares = _newShares;

        SafeTransferLib.safeTransfer(ERC20(address(SHARE)), _owner, _returnAmount);

        emit RedeemUpdated(_controller, _owner, msg.sender, _oldShares, _newShares);
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
        _isAuthorizedCaller(_controller);

        NestVaultCoreStorage storage $ = _getNestVaultCoreStorage();

        if (_receiver == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        if (_assets == 0) {
            revert Errors.ZERO_ASSETS();
        }

        // Claiming partially introduces precision loss. The user therefore receives a rounded down amount,
        // while the claimable balance is reduced by a rounded up amount.
        DataTypes.ClaimableRedeem storage _claimable = $.claimableRedeem[_controller];
        _shares = _assets.mulDivDown(_claimable.shares, _claimable.assets);

        _claimable.assets -= _assets;
        _claimable.shares = _claimable.shares > _shares ? _claimable.shares - _shares : 0;

        SafeTransferLib.safeTransfer(ERC20(asset()), _receiver, _assets);

        emit Withdraw(msg.sender, _receiver, _controller, _assets, _shares);
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
        _isAuthorizedCaller(_controller);

        NestVaultCoreStorage storage $ = _getNestVaultCoreStorage();

        if (_receiver == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        if (_shares == 0) {
            revert Errors.ZERO_SHARES();
        }

        // Claiming partially introduces precision loss. The user therefore receives a rounded down amount,
        // while the claimable balance is reduced by a rounded up amount.
        DataTypes.ClaimableRedeem storage _claimable = $.claimableRedeem[_controller];
        _assets = _shares.mulDivDown(_claimable.assets, _claimable.shares);

        if (_assets == 0 && _shares != _claimable.shares) {
            revert Errors.ERC7540_ZERO_PAYOUT();
        }

        _claimable.assets = _claimable.assets > _assets ? _claimable.assets - _assets : 0;
        _claimable.shares -= _shares;

        SafeTransferLib.safeTransfer(ERC20(asset()), _receiver, _assets);

        emit Withdraw(msg.sender, _receiver, _controller, _assets, _shares);
    }

    /// @dev   This function performs the asset transfer from the caller, enters the nest share, and mints the appropriate number of shares
    /// @param _caller   address The address making the deposit
    /// @param _receiver address The address receiving the minted shares
    /// @param _assets   uint256 The amount of assets being deposited
    /// @param _shares   uint256 The number of shares being minted
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal virtual override {
        if (!isAuthorized(_msgSender(), msg.sig)) {
            revert Errors.UNAUTHORIZED();
        }

        _enter(_caller, _receiver, _assets, _shares);

        emit Deposit(_caller, _receiver, _assets, _shares);
    }

    /// @dev   This function is called during the deposit process to manage the asset transfer and share minting
    ///        This function must be implemented in derived contracts to define specific behavior
    /// @param _caller   address The address making the deposit
    /// @param _receiver address The address receiving the minted shares
    /// @param _assets   uint256 The amount of assets being deposited
    /// @param _shares   uint256 The number of shares being minted
    function _enter(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal virtual {
        // If asset() is ERC-777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        ERC20 assetToken = ERC20(asset());

        SafeTransferLib.safeTransferFrom(assetToken, _caller, address(this), _assets);
        SafeERC20.forceApprove(IERC20(address(assetToken)), address(SHARE), _assets);

        SHARE.enter(address(this), assetToken, _assets, _receiver, _shares);

        SafeERC20.forceApprove(IERC20(address(assetToken)), address(SHARE), 0);
    }

    /// @dev   This function is called during the withdrawal or redemption process to manage the asset transfer and share burning
    ///        This function must be implemented in derived contracts to define specific behavior
    /// @param _to     address The address receiving the assets
    /// @param _asset  ERC20   The asset being withdrawn or redeemed
    /// @param _assets uint256 The amount of assets being withdrawn or redeemed
    /// @param _from   address The address from which the shares are being burned
    /// @param _shares uint256 The number of shares being burned
    function _exit(address _to, ERC20 _asset, uint256 _assets, address _from, uint256 _shares) internal virtual {
        SHARE.exit(_to, _asset, _assets, _from, _shares);
    }

    /// @dev   Internal helper to validate rate from external rate provider
    /// @param _rate uint256 The validated rate obtained from the rate provider
    function _getValidatedRate() internal view returns (uint256 _rate) {
        NestVaultCoreStorage storage $ = _getNestVaultCoreStorage();

        _rate = $.accountantWithRateProviders.getRateInQuoteSafe(ERC20(asset()));

        // prevent division by zero
        if (_rate == 0) revert Errors.INVALID_RATE();

        // prevent extreme values
        if (_rate < $.minRate || _rate > UPPER_BOUND_RATE_CAP) {
            revert Errors.RATE_OUT_OF_BOUNDS();
        }
    }

    /// @dev   Internal helper to check if the caller is authorized to perform an action on behalf of an account
    /// @param  _account address The account to check authorization for
    function _isAuthorizedCaller(address _account) internal view {
        if (_account != msg.sender && !_getNestVaultCoreStorage().isOperator[_account][msg.sender]) {
            revert Errors.UNAUTHORIZED();
        }
    }

    /// @inheritdoc ERC4626Upgradeable
    function _convertToShares(uint256 _assets, Math.Rounding _rounding) internal view override returns (uint256) {
        return Math.mulDiv(_assets, ONE_SHARE, _getValidatedRate(), _rounding);
    }

    /// @inheritdoc ERC4626Upgradeable
    function _convertToAssets(uint256 _shares, Math.Rounding _rounding) internal view override returns (uint256) {
        return Math.mulDiv(_shares, _getValidatedRate(), ONE_SHARE, _rounding);
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
        _feeAmount = (_assets * _getNestVaultCoreStorage().fees[DataTypes.Fees.InstantRedemption]) / 1_000_000;
        _postFeeAmount = _assets - _feeAmount;
    }

    /// @inheritdoc ERC4626Upgradeable
    function totalAssets() public view override returns (uint256) {
        return
            (totalSupply() - _getNestVaultCoreStorage().totalPendingShares).mulDivDown(_getValidatedRate(), ONE_SHARE);
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
        revert Errors.ERC7540_ASYNC_FLOW();
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewRedeem(uint256) public pure virtual override returns (uint256) {
        revert Errors.ERC7540_ASYNC_FLOW();
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates accountant with rate provider
    /// @dev    Only authorized entity can update rate provider
    /// @param _accountantWithRateProviders address rate provider address
    function setAccountantWithRateProviders(address _accountantWithRateProviders) external requiresAuth {
        if (_accountantWithRateProviders == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        _getNestVaultCoreStorage().accountantWithRateProviders =
            AccountantWithRateProviders(_accountantWithRateProviders);
    }

    /// @notice Set fee
    /// @dev    This function allows an authorized entity to set the fee amount for a specific fee type.
    /// @param  _f    DataTypes.Fees  Fee
    /// @param  _fee  uint32          Fee amount
    function setFee(DataTypes.Fees _f, uint32 _fee) external requiresAuth {
        _setFee(_f, _fee);
    }

    /// @dev   Internal helper to set fee
    /// @param  _f    DataTypes.Fees  Fee
    /// @param  _fee  uint32          Fee amount
    function _setFee(DataTypes.Fees _f, uint32 _fee) internal {
        NestVaultCoreStorage storage $ = _getNestVaultCoreStorage();
        if (_fee > $.maxFees[_f]) revert Errors.InvalidFee();

        uint32 _oldFee = $.fees[_f];

        $.fees[_f] = _fee;

        emit SetFee(_f, _oldFee, _fee);
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
    /// @param  _f   DataTypes.Fees  The fee type for which the fee amount is requested
    /// @return _fee uint32          fee in basis point
    function fees(DataTypes.Fees _f) external view returns (uint32 _fee) {
        NestVaultCoreStorage storage $ = _getNestVaultCoreStorage();
        _fee = $.fees[_f];
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

    /// @notice Mapping of maximum fees allowed for different operations in the contract
    /// @dev    The `maxFees` mapping associates each fee type in `DataTypes.Fees` with its corresponding maximum fee percentage
    ///         For example, a value of 200000 represents a maximum fee of 20% (200000 / 1000000)
    ///         Authorized users can modify these maximum fees directly through this public mapping
    /// @param  f DataTypes.Fees the type of fee
    /// @return   uint32         fee in basis points
    function maxFees(DataTypes.Fees f) external view returns (uint32) {
        return _getNestVaultCoreStorage().maxFees[f];
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
    /// @return AccountantWithRateProviders The AccountantWithRateProviders contract associated with the vault
    function accountantWithRateProviders() external view returns (AccountantWithRateProviders) {
        return _getNestVaultCoreStorage().accountantWithRateProviders;
    }
}
