// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {
    ReentrancyGuardTransientUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import {IOFT, SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

import {IVaultComposerSync} from "@layerzerolabs/ovault-evm/contracts/interfaces/IVaultComposerSync.sol";
import {Errors} from "contracts/types/Errors.sol";

/// @title VaultComposerSync - Synchronous Vault Composer
/// @notice This contract is a composer that allows deposits and redemptions operations against a
///         synchronous vault across different chains using LayerZero's OFT protocol.
/// @author Modified from LayerZero (https://github.com/LayerZero-Labs/devtools/blob/main/packages/ovault-evm/contracts/VaultComposerSync.sol)
/// @author Modified by plumenetwork to support upgradeable proxies
contract VaultComposerSyncUpgradeable is IVaultComposerSync, Initializable, ReentrancyGuardTransientUpgradeable {
    using OFTComposeMsgCodec for bytes;
    using OFTComposeMsgCodec for bytes32;
    using SafeERC20 for IERC20;

    /// @notice Storage struct for VaultComposerSyncUpgradeable
    /// @dev    Used by library functions that need access to full storage
    struct VaultComposerSyncStorage {
        /// @dev The ERC4626 vault contract for deposits and redemptions
        IERC4626 vault;
        /// @dev The underlying asset ERC20 token address
        address assetErc20;
        /// @dev The vault share ERC20 token address
        address shareErc20;
        /// @dev The asset OFT (Omnichain Fungible Token) contract address
        address assetOft;
        /// @dev The share OFT contract address
        address shareOft;
        /// @dev The LayerZero endpoint address
        address endpoint;
        /// @dev The LayerZero endpoint ID for the vault's chain
        uint32 vaultEid;
    }

    // keccak256(abi.encode(uint256(keccak256("plumenetwork.storage.VaultComposerSyncUpgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VaultComposerSyncUpgradeableStorageLocation =
        0xc537560042629e8880bf5e9fca9de99531ceefbe83dcee9e2560a43447673800;

    constructor() {
        _disableInitializers();
    }

    /// @dev Private function to access the contract's storage slot
    /// @return $ A reference to the VaultComposerSyncStorage struct
    function _getVaultComposerSyncStorage() private pure returns (VaultComposerSyncStorage storage $) {
        assembly {
            $.slot := VaultComposerSyncUpgradeableStorageLocation
        }
    }

    /// @notice Initializes the VaultComposerSync contract with vault and OFT token addresses
    /// @dev Calls the internal __VaultComposerSyncUpgradeable_init function
    /// @param _vault    address The address of the ERC4626 vault contract
    /// @param _assetOFT address The address of the asset OFT (Omnichain Fungible Token) contract
    /// @param _shareOFT address The address of the share OFT contract (must be an adapter)
    function initialize(address _vault, address _assetOFT, address _shareOFT) external virtual initializer {
        __VaultComposerSyncUpgradeable_init(_vault, _assetOFT, _shareOFT);
    }

    /// @dev Initializes the VaultComposerSync contract with vault and OFT token addresses
    /// @param _vault    address The address of the ERC4626 vault contract
    /// @param _assetOFT address The address of the asset OFT (Omnichain Fungible Token) contract
    /// @param _shareOFT address The address of the share OFT contract (must be an adapter)
    function __VaultComposerSyncUpgradeable_init(address _vault, address _assetOFT, address _shareOFT)
        internal
        onlyInitializing
    {
        VaultComposerSyncStorage storage $ = _getVaultComposerSyncStorage();

        $.vault = IERC4626(_vault);

        $.shareOft = _shareOFT;
        $.assetOft = _assetOFT;

        $.shareErc20 = _initializeShareToken();
        $.assetErc20 = _initializeAssetToken();

        $.endpoint = address(IOAppCore(_assetOFT).endpoint());
        $.vaultEid = ILayerZeroEndpointV2($.endpoint).eid();
    }

    /// @notice Returns the vault associated with this composer
    function VAULT() public view returns (IERC4626) {
        return _getVaultComposerSyncStorage().vault;
    }

    /// @notice Returns the address of the asset OFT token
    function ASSET_OFT() public view returns (address) {
        return _getVaultComposerSyncStorage().assetOft;
    }

    /// @notice Returns the address of the asset ERC20 token
    function ASSET_ERC20() public view returns (address) {
        return _getVaultComposerSyncStorage().assetErc20;
    }

    /// @notice Returns the address of the share OFT token
    function SHARE_OFT() public view returns (address) {
        return _getVaultComposerSyncStorage().shareOft;
    }

    /// @notice Returns the address of the share ERC20 token
    function SHARE_ERC20() public view returns (address) {
        return _getVaultComposerSyncStorage().shareErc20;
    }

    /// @notice Returns the address of the LayerZero endpoint
    function ENDPOINT() public view returns (address) {
        return _getVaultComposerSyncStorage().endpoint;
    }

    /// @notice Returns the LayerZero endpoint ID associated with the vault
    function VAULT_EID() public view returns (uint32) {
        return _getVaultComposerSyncStorage().vaultEid;
    }

    /// @notice Handles LayerZero compose operations for vault transactions with automatic refund functionality
    /// @dev This composer is designed to handle refunds to an EOA address and not a contract
    ///      Any revert in handleCompose() causes a refund back to the src EXCEPT for InsufficientMsgValue
    /// @param _composeSender address The OFT contract address used for refunds, must be either ASSET_OFT or SHARE_OFT
    /// @param _guid          bytes32 LayerZero's unique tx id (created on the source tx)
    /// @param _message       bytes   Decomposable bytes object into [composeHeader][composeMessage]
    function lzCompose(
        address _composeSender, // The OFT used on refund, also the vaultIn token.
        bytes32 _guid,
        bytes calldata _message, // expected to contain a composeMessage = abi.encode(SendParam hopSendParam,uint256 minMsgValue)
        address,
        /*_executor*/
        bytes calldata /*_extraData*/
    )
        public
        payable
        virtual
        override
    {
        VaultComposerSyncStorage storage $ = _getVaultComposerSyncStorage();

        if (msg.sender != $.endpoint) revert OnlyEndpoint(msg.sender);
        if (_composeSender != $.assetOft && _composeSender != $.shareOft) {
            revert OnlyValidComposeCaller(_composeSender);
        }

        bytes32 composeFrom = _message.composeFrom();
        uint256 amount = _message.amountLD();
        bytes memory composeMsg = _message.composeMsg();

        /// @dev try...catch to handle the compose operation. if it fails we refund the user
        try this.handleCompose{value: msg.value}(_composeSender, composeFrom, composeMsg, amount) {
            emit Sent(_guid);
        } catch (bytes memory _err) {
            /// @dev A revert where the msg.value passed is lower than the min expected msg.value is handled separately
            /// @dev This is because it is possible to re-trigger from the endpoint the compose operation with the right msg.value
            if (bytes4(_err) == InsufficientMsgValue.selector) {
                assembly {
                    revert(add(32, _err), mload(_err))
                }
            }

            _refund(_composeSender, _message, amount, tx.origin, msg.value);
            emit Refunded(_guid);
        }
    }

    /// @notice Handles the compose operation for OFT (Omnichain Fungible Token) transactions
    /// @dev This function can only be called by the contract itself (self-call restriction)
    ///      Decodes the compose message to extract SendParam and minimum message value
    ///      Routes to either deposit or redeem flow based on the input OFT token type
    /// @param _oftIn       address The OFT token whose funds have been received in the lzReceive associated with this lzTx
    /// @param _composeFrom bytes32 The bytes32 identifier of the compose sender
    /// @param _composeMsg  bytes   The encoded message containing SendParam and minMsgValue
    /// @param _amount      uint256 The amount of tokens received in the lzReceive associated with this lzTx
    function handleCompose(address _oftIn, bytes32 _composeFrom, bytes memory _composeMsg, uint256 _amount)
        external
        payable
    {
        /// @dev Can only be called by self
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);

        /// @dev SendParam defines how the composer will handle the user's funds
        /// @dev When msg.value < minMsgValue we revert and payload will stay in the endpoint for future retries
        (SendParam memory sendParam, uint256 minMsgValue) = abi.decode(_composeMsg, (SendParam, uint256));
        if (msg.value < minMsgValue) revert InsufficientMsgValue(minMsgValue, msg.value);

        if (_oftIn == ASSET_OFT()) {
            _depositAndSend(_composeFrom, _amount, sendParam, tx.origin, msg.value);
        } else {
            _redeemAndSend(_composeFrom, _amount, sendParam, tx.origin, msg.value);
        }
    }

    /// @notice Deposits ERC20 assets from the caller into the vault and sends them to the recipient
    /// @dev Transfers assets from caller, deposits into vault, and sends shares cross-chain
    /// @param _assetAmount   uint256   The number of ERC20 tokens to deposit and send
    /// @param _sendParam     SendParam Parameters on how to send the shares to the recipient
    /// @param _refundAddress address   Address to receive excess `msg.value`
    function depositAndSend(uint256 _assetAmount, SendParam memory _sendParam, address _refundAddress)
        external
        payable
        virtual
        nonReentrant
    {
        IERC20(ASSET_ERC20()).safeTransferFrom(msg.sender, address(this), _assetAmount);
        _depositAndSend(
            OFTComposeMsgCodec.addressToBytes32(msg.sender), _assetAmount, _sendParam, _refundAddress, msg.value
        );
    }

    /// @dev Internal function that deposits assets and sends shares to another chain
    ///      This function first deposits the assets to mint shares, validates the shares meet minimum slippage requirements,
    ///      then sends the minted shares cross-chain using the OFT (Omnichain Fungible Token) protocol
    ///      _sendParam.amountLD is set to the share amount minted, and minAmountLD is reset to 0 for send operation
    /// @param _depositor     bytes32   The depositor (bytes32 format to account for non-evm addresses)
    /// @param _assetAmount   uint256   The number of assets to deposit
    /// @param _sendParam     SendParam Parameter that defines how to send the shares
    /// @param _refundAddress address   Address to receive excess payment of the LZ fees
    /// @param _msgValue      uint256   The amount of native tokens sent with the transaction
    function _depositAndSend(
        bytes32 _depositor,
        uint256 _assetAmount,
        SendParam memory _sendParam,
        address _refundAddress,
        uint256 _msgValue
    ) internal virtual {
        VaultComposerSyncStorage storage $ = _getVaultComposerSyncStorage();

        uint256 preShareBalance = IERC20($.shareErc20).balanceOf(address(this));
        /// @dev Async functions may return an amount on `deposit`, but not transfer share tokens.
        _deposit(_depositor, _assetAmount);
        uint256 postShareBalance = IERC20($.shareErc20).balanceOf(address(this));

        uint256 shareAmountReceived = postShareBalance - preShareBalance;
        if (shareAmountReceived == 0) revert Errors.ZeroShares();
        _assertSlippage(shareAmountReceived, _sendParam.minAmountLD);

        _sendParam.amountLD = shareAmountReceived;
        _sendParam.minAmountLD = 0;

        _send($.shareOft, _sendParam, _refundAddress, _msgValue);
        emit Deposited(_depositor, _sendParam.to, _sendParam.dstEid, _assetAmount, shareAmountReceived);
    }

    /// @dev Internal function to deposit assets into the vault
    ///      This function is expected to be overridden by the inheriting contract to implement custom/nonERC4626 deposit logic
    /// @param _assetAmount uint256 The number of assets to deposit into the vault
    /// @return shareAmount uint256 The number of shares received from the vault deposit
    function _deposit(
        bytes32,
        /*_depositor*/
        uint256 _assetAmount
    )
        internal
        virtual
        returns (uint256 shareAmount)
    {
        shareAmount = VAULT().deposit(_assetAmount, address(this));
    }

    /// @notice Redeems vault shares and sends the resulting assets to the user
    /// @dev Transfers shares from caller, redeems from vault, and sends assets cross-chain
    /// @param _shareAmount   uint256   The number of vault shares to redeem
    /// @param _sendParam     SendParam Parameter that defines how to send the assets
    /// @param _refundAddress address   Address to receive excess payment of the LZ fees
    function redeemAndSend(uint256 _shareAmount, SendParam memory _sendParam, address _refundAddress)
        external
        payable
        virtual
        nonReentrant
    {
        IERC20(SHARE_ERC20()).safeTransferFrom(msg.sender, address(this), _shareAmount);
        _redeemAndSend(
            OFTComposeMsgCodec.addressToBytes32(msg.sender), _shareAmount, _sendParam, _refundAddress, msg.value
        );
    }

    /// @dev Internal function that redeems shares for assets and sends them cross-chain
    ///      This function first redeems the specified share amount for the underlying asset,
    ///      validates the received amount against slippage protection, then initiates a cross-chain
    ///      transfer of the redeemed assets using the OFT (Omnichain Fungible Token) protocol
    ///      The minAmountLD in _sendParam is reset to 0 after slippage validation since the
    ///      actual amount has already been verified
    /// @param _redeemer      bytes32   The address of the redeemer in bytes32 format
    /// @param _shareAmount   uint256   The number of shares to redeem
    /// @param _sendParam     SendParam Parameter that defines how to send the assets
    /// @param _refundAddress address   Address to receive excess payment of the LZ fees
    /// @param _msgValue      uint256   The amount of native tokens sent with the transaction
    function _redeemAndSend(
        bytes32 _redeemer,
        uint256 _shareAmount,
        SendParam memory _sendParam,
        address _refundAddress,
        uint256 _msgValue
    ) internal virtual {
        VaultComposerSyncStorage storage $ = _getVaultComposerSyncStorage();

        uint256 preAssetBalance = IERC20($.assetErc20).balanceOf(address(this));
        /// @dev Async functions may return an amount on `redeem`, but not transfer asset tokens.
        _redeem(_redeemer, _shareAmount);
        uint256 postAssetBalance = IERC20($.assetErc20).balanceOf(address(this));

        uint256 assetAmountReceived = postAssetBalance - preAssetBalance;
        if (assetAmountReceived == 0) revert Errors.ZeroAssets();
        _assertSlippage(assetAmountReceived, _sendParam.minAmountLD);

        _sendParam.amountLD = assetAmountReceived;
        _sendParam.minAmountLD = 0;

        _send($.assetOft, _sendParam, _refundAddress, _msgValue);
        emit Redeemed(_redeemer, _sendParam.to, _sendParam.dstEid, _shareAmount, assetAmountReceived);
    }

    /// @dev Internal function to redeem shares from the vault
    ///      This function is expected to be overridden by the inheriting contract to implement custom/nonERC4626 redemption logic
    /// @param _shareAmount uint256 The number of shares to redeem from the vault
    /// @return assetAmount uint256 The number of assets received from the vault redemption
    function _redeem(
        bytes32,
        /*_redeemer*/
        uint256 _shareAmount
    )
        internal
        virtual
        returns (uint256 assetAmount)
    {
        assetAmount = VAULT().redeem(_shareAmount, address(this), address(this));
    }

    /// @dev Internal function to check slippage
    ///      This function checks if the amount sent is less than the minimum amount
    ///      If it is, it reverts with SlippageExceeded error
    ///      This function can be overridden to implement custom slippage logic
    /// @param _amountLD    uint256 The amount of tokens to send
    /// @param _minAmountLD uint256 The minimum amount of tokens that must be sent to avoid slippage
    function _assertSlippage(uint256 _amountLD, uint256 _minAmountLD) internal view virtual {
        if (_amountLD < _minAmountLD) revert SlippageExceeded(_amountLD, _minAmountLD);
    }

    /// @notice Quotes the send operation for the given OFT and SendParam
    /// @dev Revert on slippage will be thrown by the OFT and not _assertSlippage
    ///      This function can be overridden to implement custom quoting logic
    /// @param _from          address   The "sender address" used for the quote
    /// @param _targetOFT     address   The OFT contract address to quote
    /// @param _vaultInAmount uint256   The amount of tokens to send to the vault
    /// @param _sendParam     SendParam The parameters for the send operation
    /// @return MessagingFee  The estimated fee for the send operation
    function quoteSend(address _from, address _targetOFT, uint256 _vaultInAmount, SendParam memory _sendParam)
        external
        view
        virtual
        returns (MessagingFee memory)
    {
        IERC4626 vault = VAULT();

        /// @dev When quoting the asset OFT, if the input is shares, SendParam.amountLD must be assets (and vice versa)
        if (_targetOFT == ASSET_OFT()) {
            uint256 maxRedeem = vault.maxRedeem(_from);
            if (_vaultInAmount > maxRedeem) {
                revert ERC4626.ERC4626ExceededMaxRedeem(_from, _vaultInAmount, maxRedeem);
            }

            _sendParam.amountLD = vault.previewRedeem(_vaultInAmount);
        } else {
            uint256 maxDeposit = vault.maxDeposit(_from);
            if (_vaultInAmount > maxDeposit) {
                revert ERC4626.ERC4626ExceededMaxDeposit(_from, _vaultInAmount, maxDeposit);
            }

            _sendParam.amountLD = vault.previewDeposit(_vaultInAmount);
        }
        return IOFT(_targetOFT).quoteSend(_sendParam, false);
    }

    /// @dev Internal function that routes token transfers to local or remote destinations
    /// @param _oft           address   The OFT contract address to use for sending
    /// @param _sendParam     SendParam The parameters for the send operation
    /// @param _refundAddress address   Address to receive excess payment of the LZ fees
    /// @param _msgValue      uint256   The amount of native tokens sent with the transaction
    function _send(address _oft, SendParam memory _sendParam, address _refundAddress, uint256 _msgValue)
        internal
        virtual
    {
        if (_sendParam.dstEid == VAULT_EID()) {
            if (_msgValue != 0) revert Errors.NonZeroMsgValueLocal(_msgValue);
            _sendLocal(_oft, _sendParam, _refundAddress, _msgValue);
        } else {
            _sendRemote(_oft, _sendParam, _refundAddress, _msgValue);
        }
    }

    /// @dev Internal function that handles token transfer to recipients on the same chain
    ///      Transfers tokens directly without LayerZero messaging
    ///      _refundAddress is unused for local transfers
    ///      _msgValue must be 0 for local transfers, accidental transfers accumulate in the contract and are locked
    /// @param _oft       address   The OFT contract address to determine which token to transfer
    /// @param _sendParam SendParam The parameters for the send operation
    function _sendLocal(
        address _oft,
        SendParam memory _sendParam,
        address,
        /*_refundAddress*/
        uint256 /*_msgValue*/
    )
        internal
        virtual
    {
        VaultComposerSyncStorage storage $ = _getVaultComposerSyncStorage();

        /// @dev Can do this because _oft is validated before this function is called
        address erc20 = _oft == $.assetOft ? $.assetErc20 : $.shareErc20;
        IERC20(erc20).safeTransfer(_sendParam.to.bytes32ToAddress(), _sendParam.amountLD);
    }

    /// @dev Internal function that handles token transfer to recipients on remote chains
    ///      Uses LayerZero messaging to send tokens cross-chain
    /// @param _oft           address   The OFT contract address to use for sending
    /// @param _sendParam     SendParam The parameters for the send operation
    /// @param _refundAddress address   Address to receive excess payment of the LZ fees
    /// @param _msgValue      uint256   The amount of native tokens sent with the transaction
    function _sendRemote(address _oft, SendParam memory _sendParam, address _refundAddress, uint256 _msgValue)
        internal
        virtual
    {
        IOFT(_oft).send{value: _msgValue}(_sendParam, MessagingFee(_msgValue, 0), _refundAddress);
    }

    /// @dev Internal function to refund input tokens to sender on source during a failed transaction
    /// @param _oft           address The OFT contract address used for refunding
    /// @param _message       bytes   The original message that was sent
    /// @param _amount        uint256 The amount of tokens to refund
    /// @param _refundAddress address Address to receive the refund
    /// @param _msgValue      uint256 The amount of native tokens sent with the transaction
    function _refund(address _oft, bytes calldata _message, uint256 _amount, address _refundAddress, uint256 _msgValue)
        internal
        virtual
    {
        /// @dev Extracted from the _message header. Will always be part of the _message since it is created by lzReceive
        SendParam memory refundSendParam;
        refundSendParam.dstEid = OFTComposeMsgCodec.srcEid(_message);
        refundSendParam.to = OFTComposeMsgCodec.composeFrom(_message);
        refundSendParam.amountLD = _amount;

        _sendRemote(_oft, refundSendParam, _refundAddress, _msgValue);
    }

    /// @dev Internal function to validate the share token compatibility
    ///      Validate part of the constructor in an overridable function due to differences in asset and OFT token
    ///      requirement Share token must be the vault itself
    ///      requirement Share OFT must be an adapter (approvalRequired() returns true)
    /// @return shareERC20 address The address of the share ERC20 token
    function _initializeShareToken() internal virtual returns (address shareERC20) {
        VaultComposerSyncStorage storage $ = _getVaultComposerSyncStorage();

        shareERC20 = IOFT($.shareOft).token();

        if (shareERC20 != address($.vault)) {
            revert ShareTokenNotVault(shareERC20, address($.vault));
        }

        /// @dev ShareOFT must be an OFT adapter. We can infer this by checking 'approvalRequired()'.
        /// @dev burn() on tokens when a user sends changes totalSupply() which the asset:share ratio depends on.
        if (!IOFT($.shareOft).approvalRequired()) revert ShareOFTNotAdapter($.shareOft);

        /// @dev Approve the share adapter with the share tokens held by this contract
        IERC20(shareERC20).forceApprove($.shareOft, type(uint256).max);
    }

    /// @dev Internal function to validate the asset token compatibility
    ///      Validate part of the constructor in an overridable function due to differences in asset and OFT token
    ///      For example, in the case of VaultComposerSyncPoolNative, the asset token is WETH but the OFT token is native
    ///      Asset token should match the vault's underlying asset (overridable behavior)
    /// @return assetERC20 address The address of the asset ERC20 token
    function _initializeAssetToken() internal virtual returns (address assetERC20) {
        VaultComposerSyncStorage storage $ = _getVaultComposerSyncStorage();

        assetERC20 = IOFT($.assetOft).token();

        if (assetERC20 != address($.vault.asset())) {
            revert AssetTokenNotVaultAsset(assetERC20, address($.vault.asset()));
        }

        /// @dev If the asset OFT is an adapter, approve it as well
        if (IOFT($.assetOft).approvalRequired()) IERC20(assetERC20).forceApprove($.assetOft, type(uint256).max);

        /// @dev Approve the vault to spend the asset tokens held by this contract
        IERC20(assetERC20).forceApprove(address($.vault), type(uint256).max);
    }
}
