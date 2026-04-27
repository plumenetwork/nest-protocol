// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.30;

// contracts
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AuthUpgradeable, Authority} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {
    ReentrancyGuardTransientUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

// interfaces
import {IReceiverV2} from "contracts/interfaces/vendor/cctp/IReceiverV2.sol";
import {ITokenMessengerV2} from "contracts/interfaces/vendor/cctp/ITokenMessengerV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libraries
import {TypedMemView} from "contracts/libraries/vendor/cctp/TypedMemView.sol";
import {MessageV2} from "contracts/libraries/vendor/cctp/MessageV2.sol";
import {BurnMessageV2} from "contracts/libraries/vendor/cctp/BurnMessageV2.sol";
import {AddressUtils} from "contracts/libraries/vendor/cctp/AddressUtils.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants} from "contracts/cctp/type/Constants.sol";
import {Errors} from "contracts/cctp/type/Errors.sol";

/// @notice Parameters used when forwarding a burn to CCTP, with optional hook data.
struct CCTPDepositParams {
    uint256 amount;
    uint32 destinationDomain;
    bytes32 mintRecipient;
    address burnToken;
    bytes32 destinationCaller;
    uint256 maxFee;
    uint32 minFinalityThreshold;
    bytes hookData;
}

/// @title  BaseCCTPRelayer
/// @author plumenetwork
/// @notice Core CCTP relay logic: validates messages, executes hooks, refunds on failure,
///         and exposes helpers for composing higher-level relayers.
contract BaseCCTPRelayer is Initializable, AuthUpgradeable, ReentrancyGuardTransientUpgradeable {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using MessageV2 for bytes29;
    using AddressUtils for bytes32;
    using SafeERC20 for IERC20;

    // Address of the local message transmitter
    IReceiverV2 public immutable MESSAGE_TRANSMITTER;

    // Address of the local token messenger
    ITokenMessengerV2 public immutable TOKEN_MESSENGER;

    // Address of the USDC token contract
    IERC20 public immutable USDC;

    // The supported Message Format version
    uint32 public constant SUPPORTED_MESSAGE_VERSION = 1;

    // The supported Message Body version
    uint32 public constant SUPPORTED_MESSAGE_BODY_VERSION = 1;

    /// @notice Emitted when a hook execution fails.
    event HookFailed(bytes32 nonce);

    /// @notice Emitted when a hook is successfully relayed.
    event HookRelayed(bytes32 nonce);

    /// @notice Emitted when a message is refunded.
    event Refunded(bytes32 nonce);

    /// @param _tokenMessenger      address The address of the local token messenger
    /// @param _messageTransmitter  address The address of the local message transmitter
    constructor(address _messageTransmitter, address _tokenMessenger, address _usdc) {
        if (_messageTransmitter == Constants.ADDRESS_ZERO) revert Errors.InvalidMessageTransmitter();
        if (_tokenMessenger == Constants.ADDRESS_ZERO) revert Errors.InvalidTokenMessenger();
        if (_usdc == Constants.ADDRESS_ZERO) revert Errors.InvalidUSDC();

        MESSAGE_TRANSMITTER = IReceiverV2(_messageTransmitter);
        TOKEN_MESSENGER = ITokenMessengerV2(_tokenMessenger);
        USDC = IERC20(_usdc);

        _disableInitializers();
    }

    /// @notice Initializes the contract with the given owner
    /// @dev    This function is called only during contract initialization.
    /// @param _owner address The address of the owner of the contract
    function initialize(address _owner) external virtual initializer {
        __Auth_init_unchained(_owner, Authority(address(0)));
        __BaseCCTPRelayer_init();
    }

    /// @dev Internal initializer function to set up approval for the token messenger
    /// @dev This function is called only during contract initialization.
    function __BaseCCTPRelayer_init() internal onlyInitializing {
        USDC.forceApprove(address(TOKEN_MESSENGER), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                    RELAY, RETRY AND REFUND LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Relay a message and execute its hook if valid.
    /// @param _message      bytes   calldata The encoded CCTP message.
    /// @param _attestation  bytes   calldata Circle attestation proving message validity.
    /// @param _data         bytes   calldata Additional data for hook execution.
    /// @param _forceRefund  bool    Whether to force a refund if the hook execution fails.
    function relay(bytes calldata _message, bytes calldata _attestation, bytes calldata _data, bool _forceRefund)
        public
        payable
        virtual
        nonReentrant
        requiresAuth
        returns (bool _relaySuccess, bool _hookSuccess)
    {
        return _relay(_message, _attestation, _data, new bytes(0), _forceRefund);
    }

    /// @notice Relay a message and execute its hook if valid.
    /// @param _message      bytes   calldata The encoded CCTP message.
    /// @param _attestation  bytes   calldata Circle attestation proving message validity.
    /// @param _data         bytes   calldata Additional data for hook execution.
    /// @param _extraOptions bytes   calldata Additional relayer-controlled options for downstream hook execution.
    /// @param _forceRefund  bool    Whether to force a refund if the hook execution fails.
    function relay(
        bytes calldata _message,
        bytes calldata _attestation,
        bytes calldata _data,
        bytes calldata _extraOptions,
        bool _forceRefund
    ) public payable virtual nonReentrant requiresAuth returns (bool _relaySuccess, bool _hookSuccess) {
        return _relay(_message, _attestation, _data, _extraOptions, _forceRefund);
    }

    /// @dev Shared relay implementation used by both backward-compatible and extraOptions-aware entrypoints.
    function _relay(
        bytes calldata _message,
        bytes calldata _attestation,
        bytes calldata _data,
        bytes memory _extraOptions,
        bool _forceRefund
    ) internal returns (bool _relaySuccess, bool _hookSuccess) {
        // Relay message
        uint256 amountReceived = _receiveMessage(_message, _attestation);
        bytes32 nonce = _message.ref(0)._getNonce();

        /// @dev try...catch to handle the hook operation. if it fails we refund the user on predefined conditions
        try this.executeHook{value: msg.value}(amountReceived, _message, _data, _extraOptions) {
            emit HookRelayed(nonce);

            return (true, true);
        } catch (bytes memory _err) {
            emit HookFailed(nonce);

            /// @dev Revert if the error is NOT invalid hook data AND the caller is NOT forcing a refund
            if (bytes4(_err) != Errors.InvalidHookData.selector && !_forceRefund) {
                assembly {
                    /// @dev revert when the caller is NOT forcing a refund
                    revert(add(32, _err), mload(_err))
                }
            }

            _refund(amountReceived, _message);

            return (true, false);
        }
    }

    /// @notice Execute the hook in a CCTP message.
    /// @param _amountReceived  uint256         The amount of USDC received for the message.
    /// @param _message         bytes calldata  The encoded CCTP message.
    /// @param _data            bytes calldata  Additional data for hook execution.
    /// @param _extraOptions    bytes calldata  Additional relayer-controlled options for downstream hook execution.
    function executeHook(
        uint256 _amountReceived,
        bytes calldata _message,
        bytes calldata _data,
        bytes calldata _extraOptions
    ) public payable virtual {
        /// @dev Can only be called by self
        if (msg.sender != address(this)) revert Errors.OnlySelf();

        (bool success,) = _executeHook(_amountReceived, _message, _data, _extraOptions);

        if (!success) {
            revert Errors.HookExecutionFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Recover ETH or ERC20 tokens accidentally held by the contract.
    /// @param _token  address Token address (zero for ETH).
    /// @param _to     address Recipient of the recovered funds.
    /// @param _amount uint256 Amount to transfer.
    function recoverToken(address _token, address _to, uint256 _amount) external nonReentrant requiresAuth {
        if (_to == Constants.ADDRESS_ZERO) revert Errors.InvalidRecoverToAddress();
        if (_token == Constants.ADDRESS_ZERO) {
            (bool _success,) = payable(_to).call{value: _amount}("");
            if (!_success) {
                revert Errors.RefundFailed();
            }
        } else {
            SafeERC20.safeTransfer(IERC20(_token), _to, _amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Extract hook data from a CCTP message.
    /// @param _message   bytes calldata The encoded CCTP message.
    /// @param _data      bytes calldata Additional data for hook execution.
    /// @return _hookData bytes29        The extracted hook data.
    function getHookData(bytes calldata _message, bytes calldata _data, bytes calldata _extraOptions)
        public
        view
        returns (bytes29 _hookData)
    {
        _hookData = _getHookData(_message, _data, _extraOptions);
    }

    /// @notice Validate a CCTP message format and body version.
    /// @param _message   bytes     The encoded CCTP message.
    /// @return _msg      bytes29   The validated message.
    /// @return _msgBody  bytes29   The validated message body.
    function validateMessage(bytes calldata _message) public view returns (bytes29 _msg, bytes29 _msgBody) {
        (_msg, _msgBody) = _validateMessage(_message);
    }

    /// @notice Validate hook payload and return any error data without reverting.
    /// @param _message       bytes calldata The encoded CCTP message.
    /// @param _data          bytes calldata Additional data for hook execution.
    /// @param _extraOptions  bytes calldata Additional relayer-controlled options for downstream execution.
    /// @param _amountReceived uint256  The amount of USDC received for the message.
    /// @return _invalid       bool     Whether the hook data is invalid.
    /// @return _errorData     bytes    The error data if the hook data is invalid.
    function validateHookData(
        bytes calldata _message,
        bytes calldata _data,
        bytes calldata _extraOptions,
        uint256 _amountReceived
    ) public view returns (bool _invalid, bytes memory _errorData) {
        bytes29 _hookData = _getHookData(_message, _data, _extraOptions);

        (_invalid, _errorData) = _validateHookData(_hookData, _amountReceived);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal function to receive and relay a CCTP message
    /// @dev Validate message and call the message transmitter to receive it
    /// @param _message        bytes calldata   The encoded CCTP message.
    /// @param _attestation    bytes calldata   Circle attestation proving message validity.
    /// @return _amountReceived uint256         The amount of USDC received for the message.
    function _receiveMessage(bytes calldata _message, bytes calldata _attestation)
        internal
        returns (uint256 _amountReceived)
    {
        // Validate message
        _validateMessage(_message);

        uint256 balanceBefore = USDC.balanceOf(address(this));

        bool relaySuccess = MESSAGE_TRANSMITTER.receiveMessage(_message, _attestation);

        if (!relaySuccess) revert Errors.MessageRelayFailed();

        _amountReceived = USDC.balanceOf(address(this)) - balanceBefore;
    }

    /// @notice Internal function to execute the hook in a CCTP message
    /// @dev Validates hook data, executes the hook, and updates retryQueue state
    /// @param _amountReceived  uint256      The amount of USDC received for the message.
    /// @param _message       bytes calldata The encoded CCTP message.
    /// @param _data          bytes calldata Additional data for hook execution.
    /// @param _extraOptions  bytes calldata Additional relayer-controlled options for downstream hook execution.
    /// @return _success       bool         Whether the hook execution succeeded.
    /// @return _returnData    bytes memory The returned data from the hook execution.
    function _executeHook(
        uint256 _amountReceived,
        bytes calldata _message,
        bytes calldata _data,
        bytes calldata _extraOptions
    ) internal virtual returns (bool _success, bytes memory _returnData) {
        bytes29 hookData = _getHookData(_message, _data, _extraOptions);
        uint256 hookDataLength = hookData.len();

        (bool invalid,) = _validateHookData(hookData, _amountReceived);
        if (invalid) revert Errors.InvalidHookData();

        address target = hookData.indexAddress(0);
        bytes memory hookCalldata = hookData.postfix(hookDataLength - Constants.ADDRESS_BYTE_LENGTH, 0).clone();

        (_success, _returnData) = address(target).call{value: msg.value}(hookCalldata);
    }

    /// @notice Internal function to refund a CCTP message
    /// @dev Verifies the retry message and calls depositForBurn to refund USDC
    /// @param _message     bytes calldata  The encoded CCTP message.
    /// @param _amount      uint256         The amount of USDC to refund.
    function _refund(uint256 _amount, bytes calldata _message) internal virtual {
        if (msg.value > 0) {
            // refund unspent msg.value
            (bool _success,) = msg.sender.call{value: msg.value}("");
            if (!_success) revert Errors.RefundFailed();
        }

        (bytes32 nonce, uint32 sourceDomain,,,, bytes memory msgBody) = _decodeReceivedMessage(_message);

        _depositForBurn(
            CCTPDepositParams({
                amount: _amount,
                destinationDomain: sourceDomain,
                mintRecipient: _getRefundRecipient(msgBody),
                burnToken: address(USDC),
                destinationCaller: bytes32(0),
                maxFee: TOKEN_MESSENGER.getMinFeeAmount(_amount),
                minFinalityThreshold: 2000, // Refund with CCTP high finality threshold
                hookData: new bytes(0)
            })
        );

        emit Refunded(nonce);
    }

    /// @notice Internal function to validate a CCTP message format and body version
    /// @param _message     bytes memory   The encoded CCTP message.
    /// @return _msg        bytes29        The validated message.
    /// @return _msgBody    bytes29        The validated message body.
    function _validateMessage(bytes memory _message) internal view virtual returns (bytes29 _msg, bytes29 _msgBody) {
        _msg = _message.ref(0);
        _msgBody = MessageV2._getMessageBody(_msg);

        MessageV2._validateMessageFormat(_msg);
        if (MessageV2._getVersion(_msg) != SUPPORTED_MESSAGE_VERSION) revert Errors.InvalidMessageVersion();

        BurnMessageV2._validateBurnMessageFormat(_msgBody);
        if (BurnMessageV2._getVersion(_msgBody) != SUPPORTED_MESSAGE_BODY_VERSION) {
            revert Errors.InvalidMessageBodyVersion();
        }
    }

    /// @notice Internal function to validate hook data without reverting
    /// @dev unused _amountReceived parameter for override in child contracts
    /// @param _hookData    bytes29         The hook data to validate.
    /// @return _invalid    bool            Whether the hook data is invalid.
    /// @return _errorData  bytes memory    The error data if the hook data is invalid.
    function _validateHookData(
        bytes29 _hookData,
        uint256 /*_amountReceived*/
    )
        internal
        view
        virtual
        returns (bool _invalid, bytes memory _errorData)
    {
        if (!_hookData.isValid()) {
            return (true, abi.encodeWithSelector(Errors.InvalidHookData.selector));
        }

        if (_hookData.len() < Constants.ADDRESS_BYTE_LENGTH) {
            return (true, abi.encodeWithSelector(Errors.HookDataLengthTooShort.selector));
        }
    }

    /// @notice Internal function to extract hook data from a CCTP message.
    /// @param _message   bytes memory  The encoded CCTP message.
    /// @return _hookData bytes29       The extracted hook data.
    function _getHookData(
        bytes memory _message,
        bytes memory,
        /*_data*/
        bytes memory /*_extraOptions*/
    )
        internal
        view
        virtual
        returns (bytes29 _hookData)
    {
        bytes29 _msg = _message.ref(0);
        bytes29 _msgBody = MessageV2._getMessageBody(_msg);

        _hookData = BurnMessageV2._getHookData(_msgBody);
    }

    /// @notice Internal function to deposit USDC for burn via the token messenger.
    /// @param params    CCTPDepositParams memory   The CCTP deposit parameters.
    function _depositForBurn(CCTPDepositParams memory params) internal virtual {
        TOKEN_MESSENGER.depositForBurn(
            params.amount,
            params.destinationDomain,
            params.mintRecipient,
            params.burnToken,
            params.destinationCaller,
            params.maxFee,
            params.minFinalityThreshold
        );
    }

    /// @notice Internal function to deposit USDC for burn with hook data via the token messenger.
    /// @param params    CCTPDepositParams memory The CCTP deposit parameters.
    function _depositForBurnWithHook(CCTPDepositParams memory params) internal virtual {
        TOKEN_MESSENGER.depositForBurnWithHook(
            params.amount,
            params.destinationDomain,
            params.mintRecipient,
            params.burnToken,
            params.destinationCaller,
            params.maxFee,
            params.minFinalityThreshold,
            params.hookData
        );
    }

    /// @notice Internal function to decode a received CCTP message.
    /// @param _message                     bytes memory    The encoded CCTP message.
    /// @return _nonce                      bytes32         The message nonce.
    /// @return _sourceDomain               uint32          The source domain.
    /// @return _sender                     bytes32         The sender address.
    /// @return _recipient                  address         The recipient address.
    /// @return _finalityThresholdExecuted  uint32          The finality threshold executed.
    /// @return _messageBody                bytes memory    The message body.
    function _decodeReceivedMessage(bytes memory _message)
        internal
        view
        returns (
            bytes32 _nonce,
            uint32 _sourceDomain,
            bytes32 _sender,
            address _recipient,
            uint32 _finalityThresholdExecuted,
            bytes memory _messageBody
        )
    {
        bytes29 _msg = _message.ref(0);
        _nonce = _msg._getNonce();
        _sourceDomain = _msg._getSourceDomain();
        _sender = _msg._getSender();
        _recipient = _msg._getRecipient().toAddress();
        _finalityThresholdExecuted = _msg._getFinalityThresholdExecuted();
        _messageBody = _msg._getMessageBody().clone();
    }

    /// @notice Internal function to extract from the message body the address to refund in case of hook failure.
    /// @param _msgBody    bytes memory    The message body.
    /// @return bytes32    The sender address extracted from the message body (bytes32 format to account for non-evm addresses).
    function _getRefundRecipient(bytes memory _msgBody) internal view virtual returns (bytes32) {
        return BurnMessageV2._getMessageSender(_msgBody.ref(0));
    }
}
