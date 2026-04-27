// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.30;

// contracts
import {BaseCCTPRelayer, CCTPDepositParams} from "contracts/cctp/BaseCCTPRelayer.sol";
import {Authority} from "@solmate/auth/Auth.sol";

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IOFT,
    OFTLimit,
    OFTFeeDetail,
    OFTReceipt,
    SendParam,
    MessagingReceipt,
    MessagingFee
} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {INestVaultComposer} from "contracts/interfaces/ovault/INestVaultComposer.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

// libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TypedMemView} from "contracts/libraries/vendor/cctp/TypedMemView.sol";
import {MessageV2} from "contracts/libraries/vendor/cctp/MessageV2.sol";
import {BurnMessageV2} from "contracts/libraries/vendor/cctp/BurnMessageV2.sol";
import {Errors} from "contracts/cctp/type/Errors.sol";
import {Constants} from "contracts/cctp/type/Constants.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

/// @title  NestCCTPRelayer
/// @notice NestCCTPRelayer is a relayer contract that facilitates cross-chain transfers
///         of USDC tokens using the CCTP protocol and LayerZero messaging.
///         It integrates with LayerZero's OFT and VaultComposerSync contracts to enable
///         seamless cross-chain asset transfers and messaging.
/// @dev    This contract extends the BaseCCTPRelayer and implements the IOFT interface.
/// @author plumenetwork
contract NestCCTPRelayer is BaseCCTPRelayer, IOFT {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using MessageV2 for bytes29;
    using SafeERC20 for IERC20;

    struct NestCCTPRelayerStorage {
        // Minimum finality threshold required when relaying
        uint32 finalityThreshold;

        // Maximum fee basis points for relaying operations
        uint256 maxFeeBasisPoints;

        // Mapping of LayerZero endpoint ids to CCTP domains
        mapping(uint32 => uint32) eidToDomain;

        // Allowed VaultComposerSync contracts
        mapping(address => bool) isComposer;
    }

    // keccak256(abi.encode(uint256(keccak256("plumenetwork.storage.NestCCTPRelayer")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NestCCTPRelayerStorageLocation =
        0x9cb715fddca002bac31d3e28125e9692c952dae06c29708874aa1ab8a9f63300;

    // Address of the LayerZero endpoint used by this relayer
    address private immutable LAYERZERO_ENDPOINT;

    // Minimum bytes to decode: 20 (address) + 4 (selector) + 416 (ABI tuple uint256, SendParam, address)
    // SendParam min = 320 (7-field head + 3 empty bytes tails), tuple head = 96 -> 96 + 320 = 416
    uint256 private constant MIN_HOOK_DATA_LENGTH = 440;

    // Maximum fee basis points (100% = 10,000)
    uint256 private constant FEE_BASIS = 10_000;

    // Absolute maximum fee basis points allowed
    uint256 private constant MAX_FEE_BASIS_POINTS = 1_000;

    event EidToDomainSet(uint32 eid, uint32 domain);
    event FinalityThresholdSet(uint32 minFinalityThreshold);
    event ComposerSet(address lzComposer, bool enabled);
    event MaxFeeBasisPointsSet(uint256 maxFeeBasisPoints);

    /// @param _messageTransmitter address The address of the local message transmitter.
    /// @param _tokenMessenger     address The address of the local token messenger.
    /// @param _endpoint           address The LayerZero endpoint for the OFT interface.
    /// @param _usdc               address The address of the USDC token contract.
    constructor(address _messageTransmitter, address _tokenMessenger, address _endpoint, address _usdc)
        BaseCCTPRelayer(_messageTransmitter, _tokenMessenger, _usdc)
    {
        LAYERZERO_ENDPOINT = _endpoint;

        _disableInitializers();
    }

    /// @dev Internal function to access the contract's NestAccountant slot
    /// @return $ A reference to the NestCCTPRelayerStorage struct for reading/writing exchange rate
    function _getNestCCTPRelayerStorage() private pure returns (NestCCTPRelayerStorage storage $) {
        assembly {
            $.slot := NestCCTPRelayerStorageLocation
        }
    }

    /// @notice Initializes the contract with the given owner
    /// @dev    This function is called only during contract initialization.
    /// @param _owner address The address of the owner of the contract
    function initialize(address _owner) external virtual override initializer {
        __Auth_init_unchained(_owner, Authority(address(0)));
        __BaseCCTPRelayer_init();
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Map a LayerZero endpoint id to a CCTP domain id.
    /// @param _eid    uint32 The LayerZero endpoint id.
    /// @param _domain uint32 The corresponding CCTP domain id.
    function setEidToDomain(uint32 _eid, uint32 _domain) external requiresAuth {
        _getNestCCTPRelayerStorage().eidToDomain[_eid] = _domain;

        emit EidToDomainSet(_eid, _domain);
    }

    /// @notice Set the minimum finality threshold to be used when relaying messages.
    /// @param _minFinalityThreshold uint32 The finality threshold value to enforce.
    function setFinalityThreshold(uint32 _minFinalityThreshold) external requiresAuth {
        _getNestCCTPRelayerStorage().finalityThreshold = _minFinalityThreshold;

        emit FinalityThresholdSet(_minFinalityThreshold);
    }

    /// @notice Allow or disallow a VaultComposerSync contract to be used by this relayer.
    /// @dev Reverts if the provided composer is not configured for this OFT and USDC token.
    /// @param _lzComposer address The VaultComposerSync contract to configure.
    /// @param _enabled    bool    Whether the composer is enabled.
    function setComposer(address _lzComposer, bool _enabled) external requiresAuth {
        INestVaultComposer lzComposer = INestVaultComposer(_lzComposer);
        if (lzComposer.ASSET_OFT() != address(this)) revert Errors.InvalidComposerAssetOFT();
        if (lzComposer.ASSET_ERC20() != address(USDC)) revert Errors.InvalidComposerAsset();

        _getNestCCTPRelayerStorage().isComposer[_lzComposer] = _enabled;

        _enabled ? USDC.approve(_lzComposer, type(uint256).max) : USDC.approve(_lzComposer, 0);

        emit ComposerSet(_lzComposer, _enabled);
    }

    /// @notice Set the maximum fee basis points for relaying operations.
    /// @param _maxFeeBasisPoints uint256 The maximum fee basis points (out of 10,000).
    function setMaxFeeBasisPoints(uint256 _maxFeeBasisPoints) external requiresAuth {
        if (
            TOKEN_MESSENGER.getMinFeeAmount(FEE_BASIS) > _maxFeeBasisPoints || _maxFeeBasisPoints > MAX_FEE_BASIS_POINTS
        ) revert Errors.InvalidFee();

        _getNestCCTPRelayerStorage().maxFeeBasisPoints = _maxFeeBasisPoints;

        emit MaxFeeBasisPointsSet(_maxFeeBasisPoints);
    }

    /*//////////////////////////////////////////////////////////////
                    VaultComposer RELATED LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Quote the LayerZero fee for relaying and composing the hook in a received message.
    /// @param  _message      bytes calldata        The encoded CCTP message containing hook data.
    /// @param  _data         bytes calldata        PredicateMessage encoded data for the hook execution.
    /// @param  _extraOptions bytes calldata        Relayer-controlled options that overwrite user sendParam.extraOptions.
    /// @return _quote        MessagingFee memory   The quoted LayerZero fee breakdown.
    function quoteRelay(bytes calldata _message, bytes calldata _data, bytes calldata _extraOptions)
        external
        view
        returns (MessagingFee memory _quote)
    {
        _validateMessage(_message);

        // decode hook data
        (address target,,, uint256 amount, SendParam memory sendParam,) =
            _decodeNestHookData(_getHookData(_message, _data, _extraOptions));

        if (!_getNestCCTPRelayerStorage().isComposer[target]) revert Errors.UnauthorizedComposer();

        INestVaultComposer composer = INestVaultComposer(target);

        // quote composer lzCompose call
        return composer.quoteSend(address(this), composer.SHARE_OFT(), amount, sendParam);
    }

    /// @notice Decode hook data for the VaultComposerSync invocation.
    /// @param _hookData        bytes29          The hook data extracted from the CCTP message body.
    /// @return lzComposer      address          The configured composer contract.
    /// @return selector        bytes4           The function selector to call on the composer.
    /// @return refundRecipient bytes32          The address to refund the deposit if hook fails (bytes32 format to account for non-evm addresses).
    /// @return amount          uint256          The asset amount to deposit.
    /// @return sendParam       SendParam memory The LayerZero send parameters for the compose call.
    /// @return refundAddress   address          The address to receive excess `msg.value`
    function _decodeNestHookData(bytes29 _hookData)
        internal
        view
        returns (
            address lzComposer,
            bytes4 selector,
            bytes32 refundRecipient,
            uint256 amount,
            SendParam memory sendParam,
            address refundAddress
        )
    {
        lzComposer = _hookData.indexAddress(0);

        selector = bytes4(_hookData.slice(Constants.ADDRESS_BYTE_LENGTH, 4, 0).clone());

        bytes memory argsOnly = _hookData.postfix(_hookData.len() - 24, 0).clone();

        (refundRecipient, amount, sendParam, refundAddress) =
            abi.decode(argsOnly, (bytes32, uint256, SendParam, address));
    }

    /*//////////////////////////////////////////////////////////////
                    BaseCCTPRelayer OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal function to extract hook data from a CCTP message.
    /// @dev Overrides to include additional _data parameter for PredicateMessage, which is encoded in oftCmd as the NestVaultComposer expects.
    /// @param _message   bytes memory  The encoded CCTP message.
    /// @param _data      bytes memory  PredicateMessage encoded data for the hook execution.
    /// @return _hookData bytes29       The extracted hook data.
    function _getHookData(bytes memory _message, bytes memory _data, bytes memory _extraOptions)
        internal
        view
        override
        returns (bytes29 _hookData)
    {
        bytes29 _msg = _message.ref(0);
        bytes29 _msgBody = MessageV2._getMessageBody(_msg);
        bytes29 hookData = BurnMessageV2._getHookData(_msgBody);
        bytes32 depositor = BurnMessageV2._getMessageSender(_msgBody);

        (address target, bytes4 selector,, uint256 assetAmount, SendParam memory sendParam, address refundAddress) =
            _decodeNestHookData(hookData);

        sendParam.oftCmd = _data;
        sendParam.extraOptions = _extraOptions;

        _hookData = abi.encodePacked(
                target, abi.encodeWithSelector(selector, depositor, assetAmount, sendParam, refundAddress)
            ).ref(0);
    }

    /// @notice Validate hook data for a received message.
    /// @dev Ensures the composer is authorized and the received USDC covers the requested amount.
    /// @param _hookData       bytes29 The hook data to validate.
    /// @param _amountReceived uint256 The amount of USDC received alongside the message.
    /// @return _invalid       bool    Whether the hook data is invalid.
    /// @return _errorData     bytes   Error data describing the failure reason.
    function _validateHookData(bytes29 _hookData, uint256 _amountReceived)
        internal
        view
        override
        returns (bool _invalid, bytes memory _errorData)
    {
        if (!_hookData.isValid()) {
            return (true, abi.encodeWithSelector(Errors.InvalidHookData.selector));
        }

        if (_hookData.len() < MIN_HOOK_DATA_LENGTH) {
            return (true, abi.encodeWithSelector(Errors.HookDataLengthTooShort.selector));
        }

        (address composer, bytes4 selector,, uint256 assetAmount,,) = _decodeNestHookData(_hookData);
        if (assetAmount > _amountReceived) {
            return (true, abi.encodeWithSelector(Errors.InsufficientReceivedAmount.selector));
        }

        if (!_getNestCCTPRelayerStorage().isComposer[composer]) {
            return (true, abi.encodeWithSelector(Errors.UnauthorizedComposer.selector));
        }

        if (selector != INestVaultComposer.depositAndSend.selector) {
            return (true, abi.encodeWithSelector(Errors.UnauthorizedComposer.selector));
        }
    }

    /// @notice Internal function to extract from the message body the address to refund in case of hook failure.
    /// @dev Overrides to account for BurnMessageV2 sender not being able to receive USDC refunds directly.
    /// @param _msgBody             bytes memory    The message body.
    /// @return _refundToAddress    bytes32         The sender address extracted from the message body (bytes32 format to account for non-evm addresses).
    function _getRefundRecipient(bytes memory _msgBody) internal view override returns (bytes32 _refundToAddress) {
        bytes29 hookData = BurnMessageV2._getHookData(_msgBody.ref(0));
        (,, _refundToAddress,,,) = _decodeNestHookData(hookData);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculate the maximum fee for a given amount based on configured basis points.
    /// @param _amount            uint256 The amount to calculate the max fee for.
    /// @param _revertIfInvalid   bool    Whether to revert if the calculated max fee is less than the minimum required fee.
    /// @return _maxFee           uint256 The calculated maximum fee.
    function getMaxFeeAmount(uint256 _amount, bool _revertIfInvalid) public view returns (uint256 _maxFee) {
        uint256 maxFeeBasisPoints = _getNestCCTPRelayerStorage().maxFeeBasisPoints;

        _maxFee = FixedPointMathLib.mulDivUp(_amount, maxFeeBasisPoints, FEE_BASIS);

        if (TOKEN_MESSENGER.getMinFeeAmount(_amount) > _maxFee && _revertIfInvalid) {
            revert Errors.InvalidFee();
        }
    }

    /// @notice Get the maximum fee basis points configured for this relayer.
    /// @return uint256 The maximum fee basis points.
    function getMaxFeeBasisPoints() external view returns (uint256) {
        return _getNestCCTPRelayerStorage().maxFeeBasisPoints;
    }

    /// @notice Get the CCTP domain for a given LayerZero endpoint id.
    /// @param _eid     uint32 The LayerZero endpoint id.
    /// @return domain  uint32 The corresponding CCTP domain id.
    function getEidToDomain(uint32 _eid) external view returns (uint32 domain) {
        return _getNestCCTPRelayerStorage().eidToDomain[_eid];
    }

    /// @notice Check if a VaultComposerSync contract is configured for this relayer.
    /// @param _lzComposer  address The VaultComposerSync contract to check.
    /// @return             bool    True if the composer is enabled, false otherwise.
    function isComposer(address _lzComposer) external view returns (bool) {
        return _getNestCCTPRelayerStorage().isComposer[_lzComposer];
    }

    /// @notice Get the minimum finality threshold for relaying messages.
    /// @return minFinalityThreshold uint32 The finality threshold value.
    function getFinalityThreshold() external view returns (uint32) {
        return _getNestCCTPRelayerStorage().finalityThreshold;
    }

    /*//////////////////////////////////////////////////////////////
                        IOFT OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Return the OFT interface id and version.
    /// @return interfaceId bytes4 The interface id for IOFT.
    /// @return version     uint64 The IOFT version supported.
    function oftVersion() external pure returns (bytes4 interfaceId, uint64 version) {
        return (type(IOFT).interfaceId, 1);
    }

    /// @notice Return the underlying token address (USDC).
    function token() external view returns (address) {
        return address(USDC);
    }

    /// @notice Indicate that approvals are required for OFT sends.
    function approvalRequired() external pure returns (bool) {
        return true;
    }

    /// @notice Return the shared decimals for OFT (USDC has 6).
    function sharedDecimals() external pure returns (uint8) {
        return 6;
    }

    /// @notice Quote OFT send limits, fees, and receipts (no fees or limits applied).
    /// @param _sendParam SendParam calldata The parameters for the OFT send.
    /// @return oftLimit     OFTLimit        Limit information for the transfer (unused).
    /// @return oftFeeDetails OFTFeeDetail[] Fee breakdown (empty).
    /// @return oftReceipt   OFTReceipt      Receipt showing the amount sent and received.
    function quoteOFT(SendParam calldata _sendParam)
        external
        pure
        returns (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt)
    {
        oftLimit = OFTLimit(0, type(uint256).max); // no bridge limits
        oftFeeDetails = new OFTFeeDetail[](0);
        oftReceipt = OFTReceipt(_sendParam.amountLD, _sendParam.amountLD);
    }

    /// @notice Quote the LayerZero messaging fee for sending (always zero for this relayer).
    /// @return MessagingFee memory The zero-fee quote.
    function quoteSend(SendParam calldata, bool) external pure returns (MessagingFee memory) {
        return MessagingFee(0, 0);
    }

    /// @notice Burn USDC for cross-chain minting via CCTP using OFT semantics.
    /// @dev Transfers USDC from the caller and initiates a CCTP burn with the provided parameters.
    /// @dev This function is payable to comply with the IOFT interface, but does not require any ETH.
    /// @param _sendParam SendParam calldata The LayerZero send parameters including destination and amount.
    /// @return MessagingReceipt memory The LayerZero messaging receipt (empty for CCTP burn).
    /// @return OFTReceipt memory       Receipt indicating amount sent and received.
    function send(SendParam calldata _sendParam, MessagingFee calldata, address)
        external
        payable
        requiresAuth
        returns (MessagingReceipt memory, OFTReceipt memory)
    {
        NestCCTPRelayerStorage storage $ = _getNestCCTPRelayerStorage();
        uint256 amount = _sendParam.amountLD;

        uint32 dstDomain = $.eidToDomain[_sendParam.dstEid];
        if (dstDomain == 0) revert Errors.InvalidDestinationDomain();

        USDC.safeTransferFrom(msg.sender, address(this), amount);

        CCTPDepositParams memory params = CCTPDepositParams({
            amount: amount,
            destinationDomain: dstDomain,
            mintRecipient: _sendParam.to,
            burnToken: address(USDC),
            destinationCaller: bytes32(0),
            maxFee: getMaxFeeAmount(amount, true),
            minFinalityThreshold: $.finalityThreshold,
            hookData: ""
        });

        _depositForBurn(params);

        return (MessagingReceipt(bytes32(0), 0, MessagingFee(0, 0)), OFTReceipt(amount, amount));
    }

    /// @notice Return the LayerZero endpoint
    /// @dev Required by VaultComposerSync, not used directly in this relayer.
    function endpoint() external view returns (ILayerZeroEndpointV2) {
        return ILayerZeroEndpointV2(LAYERZERO_ENDPOINT);
    }
}
