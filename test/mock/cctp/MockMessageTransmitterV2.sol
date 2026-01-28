// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// libraries
import {TypedMemView} from "contracts/libraries/vendor/cctp/TypedMemView.sol";
import {MessageV2} from "contracts/libraries/vendor/cctp/MessageV2.sol";
import {BurnMessageV2} from "contracts/libraries/vendor/cctp/BurnMessageV2.sol";
import {AddressUtils} from "contracts/libraries/vendor/cctp/AddressUtils.sol";

// interfaces
import {IMessageHandlerV2} from "contracts/interfaces/vendor/cctp/IMessageHandlerV2.sol";

contract MockMessageTransmitterV2 {
    // ============ Constants ============
    // A constant value indicating that a nonce has been used
    uint256 public constant NONCE_USED = 1;

    // ============ State Variables ============
    // Domain of chain on which the contract is deployed
    uint32 public immutable localDomain;

    // Message Format version
    uint32 public immutable version;

    // Maps a bytes32 nonce -> uint256 (0 if unused, 1 if used)
    mapping(bytes32 => uint256) public usedNonces;

    // The threshold at which (and above) messages are considered finalized.
    uint32 constant FINALITY_THRESHOLD_FINALIZED = 2000;

    /**
     * @notice Emitted when a new message is received
     * @param caller Caller (msg.sender) on destination domain
     * @param sourceDomain The source domain this message originated from
     * @param nonce The nonce unique to this message
     * @param sender The sender of this message
     * @param finalityThresholdExecuted The finality at which message was attested to
     * @param messageBody message body bytes
     */
    event MessageReceived(
        address indexed caller,
        uint32 sourceDomain,
        bytes32 indexed nonce,
        bytes32 sender,
        uint32 indexed finalityThresholdExecuted,
        bytes messageBody
    );

    // ============ Libraries ============
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using MessageV2 for bytes29;
    using AddressUtils for bytes32;
    using AddressUtils for address;

    function receiveMessage(bytes calldata message, bytes calldata attestation) external returns (bool success) {
        // Validate message
        (
            bytes32 _nonce,
            uint32 _sourceDomain,
            bytes32 _sender,
            address _recipient,
            uint32 _finalityThresholdExecuted,
            bytes memory _messageBody
        ) = _validateReceivedMessage(message, attestation);

        // Mark nonce as used
        usedNonces[_nonce] = NONCE_USED;

        // Handle receive message
        if (_finalityThresholdExecuted < FINALITY_THRESHOLD_FINALIZED) {
            require(
                IMessageHandlerV2(_recipient)
                    .handleReceiveUnfinalizedMessage(_sourceDomain, _sender, _finalityThresholdExecuted, _messageBody),
                "handleReceiveUnfinalizedMessage() failed"
            );
        } else {
            require(
                IMessageHandlerV2(_recipient)
                    .handleReceiveFinalizedMessage(_sourceDomain, _sender, _finalityThresholdExecuted, _messageBody),
                "handleReceiveFinalizedMessage() failed"
            );
        }

        // Emit MessageReceived event
        emit MessageReceived(msg.sender, _sourceDomain, _nonce, _sender, _finalityThresholdExecuted, _messageBody);

        return true;
    }

    /**
     * @notice Validates a received message, including the attestation signatures as well
     * as the message contents.
     * @param _message Message bytes
     * @param _attestation Concatenated 65-byte signature(s) of `message`
     * @return _nonce Message nonce, as bytes32
     * @return _sourceDomain Domain where message originated from
     * @return _sender Sender of the message
     * @return _recipient Recipient of the message
     * @return _finalityThresholdExecuted The level of finality at which the message was attested to
     * @return _messageBody The message body bytes
     */
    function _validateReceivedMessage(bytes calldata _message, bytes calldata _attestation)
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
        // Validate each signature in the attestation
        _verifyAttestationSignatures(_message, _attestation);

        bytes29 _msg = _message.ref(0);

        // Validate message format
        _msg._validateMessageFormat();

        // Validate domain
        require(_msg._getDestinationDomain() == localDomain, "Invalid destination domain");

        // Validate destination caller
        if (_msg._getDestinationCaller() != bytes32(0)) {
            require(_msg._getDestinationCaller() == msg.sender.toBytes32(), "Invalid caller for message");
        }

        // Validate version
        require(_msg._getVersion() == version, "Invalid message version");

        // Validate nonce is available
        _nonce = _msg._getNonce();
        require(usedNonces[_nonce] == 0, "Nonce already used");

        // Unpack remaining values
        _sourceDomain = _msg._getSourceDomain();
        _sender = _msg._getSender();
        _recipient = _msg._getRecipient().toAddress();
        _finalityThresholdExecuted = _msg._getFinalityThresholdExecuted();
        _messageBody = _msg._getMessageBody().clone();
    }

    function _verifyAttestationSignatures(bytes calldata _message, bytes calldata _attestation) internal view {}
}
