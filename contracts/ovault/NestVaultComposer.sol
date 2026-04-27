// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// contracts
import {AuthUpgradeable, Authority} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {VaultComposerSyncUpgradeable} from "contracts/upgradeable/ovault/VaultComposerSyncUpgradeable.sol";
import {VaultComposerAsyncUpgradeable} from "contracts/upgradeable/ovault/VaultComposerAsyncUpgradeable.sol";
import {ERC4626, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC7575} from "forge-std/interfaces/IERC7575.sol";
import {IOFT, SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {
    INestVaultPredicateProxy,
    PredicateMessage,
    NestVault,
    ERC20
} from "contracts/interfaces/INestVaultPredicateProxy.sol";

// libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {Errors} from "contracts/types/Errors.sol";

/// @title  NestVaultComposer
/// @author plumenetwork
/// @notice Nest-specific vault composer with predicate proxy integration and updateRedeem support
contract NestVaultComposer is VaultComposerAsyncUpgradeable, AuthUpgradeable {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    /// @notice Address of the NestVaultPredicateProxy contract
    INestVaultPredicateProxy public immutable PREDICATE_PROXY;

    /// @notice Constructs the NestVaultComposer with a predicate proxy
    /// @dev Disables initializers to prevent re-initialization
    /// @param _predicateProxy address The address of the NestVaultPredicateProxy contract
    constructor(address _predicateProxy) {
        PREDICATE_PROXY = INestVaultPredicateProxy(_predicateProxy);

        _disableInitializers();
    }

    /// @notice Initializes the contract with the given owner
    /// @dev This function is called only during contract initialization and delegates to `__Auth_init_unchained`
    /// @param _owner    address The address of the owner of the contract
    /// @param _vault    address The address of the NestVault contract
    /// @param _assetOFT address The address of the underlying asset OFT contract
    /// @param _shareOFT address The address of the share OFT contract
    /// @param _maxRetryableValue uint256 Initial maximum retryable minMsgValue
    function initialize(
        address _owner,
        address _vault,
        address _assetOFT,
        address _shareOFT,
        uint256 _maxRetryableValue
    ) external virtual initializer {
        if (_owner == address(0)) revert Errors.ZeroAddress();
        __Auth_init_unchained(_owner, Authority(address(0)));
        __VaultComposerSyncUpgradeable_init(_vault, _assetOFT, _shareOFT);
        __VaultComposerAsyncUpgradeable_init(_maxRetryableValue);
        __NestVaultComposer_init();
    }

    /// @dev Internal initializer function to set up approvals for the predicate proxy
    function __NestVaultComposer_init() internal onlyInitializing {
        /// @dev Approve the predicate proxy to pull assets for deposits
        IERC20(ASSET_ERC20()).forceApprove(address(PREDICATE_PROXY), type(uint256).max);
    }

    /// @notice Allows the contract to receive native tokens for paying refund fees
    /// @dev Required for receiving ETH refunds from LayerZero messaging
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                            PREDICATE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits ERC20 assets from the caller into the vault and sends them to the recipient,
    ///         adds a custom _depositor for predicate verification on cross-chain deposits
    /// @dev Callable by RELAYER_ROLE. Requires authorization via the requiresAuth modifier.
    ///      The _depositor is passed to the predicate proxy for verification (e.g., KYC checks)
    ///      and is NOT used for access control - access is controlled by requiresAuth.
    /// @param _depositor     bytes32   The original depositor address for predicate verification
    ///                                 (bytes32 format to support non-EVM source chain addresses)
    /// @param _assetAmount   uint256   The number of ERC20 tokens to deposit and send
    /// @param _sendParam     SendParam Parameters for the cross-chain send (destination, recipient, etc.)
    /// @param _refundAddress address   Address to receive excess `msg.value` from LayerZero fees
    function depositAndSend(
        bytes32 _depositor,
        uint256 _assetAmount,
        SendParam memory _sendParam,
        address _refundAddress
    ) external payable requiresAuth nonReentrant {
        IERC20(ASSET_ERC20()).safeTransferFrom(msg.sender, address(this), _assetAmount);
        _depositAndSend(_depositor, _assetAmount, _sendParam, _refundAddress, msg.value);
    }

    /// @notice Deposits ERC20 assets from the caller into the vault and sends them to the recipient
    /// @dev Auth-protected override of the inherited sync overload to prevent callers from reusing
    ///      the composer's bridge permissions indirectly through permissioned OFTs.
    /// @param _assetAmount   uint256   The number of ERC20 tokens to deposit and send
    /// @param _sendParam     SendParam Parameters for the cross-chain send
    /// @param _refundAddress address   Address to receive excess `msg.value` from LayerZero fees
    function depositAndSend(uint256 _assetAmount, SendParam memory _sendParam, address _refundAddress)
        external
        payable
        virtual
        override
        requiresAuth
        nonReentrant
    {
        IERC20(ASSET_ERC20()).safeTransferFrom(msg.sender, address(this), _assetAmount);
        _depositAndSend(
            OFTComposeMsgCodec.addressToBytes32(msg.sender), _assetAmount, _sendParam, _refundAddress, msg.value
        );
    }

    /// @notice Redeems vault shares via instantRedeem and sends the resulting assets cross-chain
    /// @dev Callable by RELAYER_ROLE. Requires authorization via the requiresAuth modifier.
    ///      Uses NestVault.instantRedeem which applies the instant redemption fee.
    ///      The _redeemer is used for event tracking and is NOT used for access control.
    /// @param _redeemer      bytes32   The original redeemer address for event tracking
    ///                                 (bytes32 format to support non-EVM source chain addresses)
    /// @param _shareAmount   uint256   The number of vault shares to redeem
    /// @param _sendParam     SendParam Parameters for the cross-chain send (destination, recipient, etc.)
    /// @param _refundAddress address   Address to receive excess LayerZero fee refunds
    function redeemAndSend(bytes32 _redeemer, uint256 _shareAmount, SendParam memory _sendParam, address _refundAddress)
        external
        payable
        requiresAuth
        nonReentrant
    {
        IERC20(SHARE_ERC20()).safeTransferFrom(msg.sender, address(this), _shareAmount);
        _redeemAndSend(_redeemer, _shareAmount, _sendParam, _refundAddress, msg.value);
    }

    /// @notice Redeems vault shares and sends the resulting assets to the recipient
    /// @dev Auth-protected override of the inherited sync overload to prevent callers from reusing
    ///      the composer's bridge permissions indirectly through permissioned OFTs.
    /// @param _shareAmount   uint256   The number of vault shares to redeem
    /// @param _sendParam     SendParam Parameters for the cross-chain send
    /// @param _refundAddress address   Address to receive excess `msg.value` from LayerZero fees
    function redeemAndSend(uint256 _shareAmount, SendParam memory _sendParam, address _refundAddress)
        external
        payable
        virtual
        override
        requiresAuth
        nonReentrant
    {
        IERC20(SHARE_ERC20()).safeTransferFrom(msg.sender, address(this), _shareAmount);
        _redeemAndSend(
            OFTComposeMsgCodec.addressToBytes32(msg.sender), _shareAmount, _sendParam, _refundAddress, msg.value
        );
    }

    /// @dev Internal function to deposit assets using a predicate message
    /// @param _depositor    bytes32          The depositor (bytes32 format to account for non-evm addresses)
    /// @param _assetAmount  uint256          The amount of underlying asset to deposit
    /// @param _predicateMsg PredicateMessage The predicate message containing deposit conditions
    /// @return shareAmount  uint256          The amount of shares received from the deposit
    function _depositWithPredicate(bytes32 _depositor, uint256 _assetAmount, PredicateMessage memory _predicateMsg)
        internal
        returns (uint256 shareAmount)
    {
        shareAmount = PREDICATE_PROXY.deposit(
            ERC20(ASSET_ERC20()), _assetAmount, address(this), NestVault(address(VAULT())), _depositor, _predicateMsg
        );
    }

    /*//////////////////////////////////////////////////////////////
                        ASYNC REDEEM FUNCTIONS (NEST-SPECIFIC)
    //////////////////////////////////////////////////////////////*/

    /// @notice Fulfills a pending redemption for a specific user
    /// @dev Callable by authorized roles, calls internal _fulfillRedeem
    /// @param _srcEid   uint32  Endpoint ID associated with the redemption request
    /// @param _redeemer bytes32 Identifier of the user whose redemption is being fulfilled
    /// @param _shares   uint256 Number of shares being fulfilled
    /// @return _assets  uint256 Amount of assets made claimable for the user
    function fulfillRedeem(uint32 _srcEid, bytes32 _redeemer, uint256 _shares)
        external
        virtual
        requiresAuth
        nonReentrant
        returns (uint256 _assets)
    {
        _assets = _fulfillRedeem(_srcEid, _redeemer, _shares);
    }

    /// @notice Updates a pending redemption request and returns excess shares to the user
    /// @dev Callable by authorized roles. Can only reduce shares, not increase.
    /// @param _srcEid        uint32    Source endpoint ID
    /// @param _redeemer      bytes32   User identifier
    /// @param _sendParam     SendParam Contains new share amount in amountLD and destination for returned shares
    /// @param _refundAddress address   Address to receive excess LayerZero fee refunds
    function updateRequestRedeemAndSend(
        uint32 _srcEid,
        bytes32 _redeemer,
        SendParam memory _sendParam,
        address _refundAddress
    ) external payable virtual requiresAuth nonReentrant {
        _updateRequestRedeemAndSend(_srcEid, _redeemer, _sendParam, _refundAddress, msg.value);
    }

    /// @notice Redeems claimable shares and sends the resulting assets cross-chain
    /// @dev Callable by authorized roles. User must have claimable balance from fulfilled redemption.
    /// @param _srcEid        uint32    Source endpoint ID
    /// @param _redeemer      bytes32   User identifier
    /// @param _sendParam     SendParam Contains share amount in amountLD and destination for assets
    /// @param _refundAddress address   Address to receive excess LayerZero fee refunds
    function finishRedeemAndSend(uint32 _srcEid, bytes32 _redeemer, SendParam memory _sendParam, address _refundAddress)
        external
        payable
        virtual
        requiresAuth
        nonReentrant
    {
        _finishRedeemAndSend(_srcEid, _redeemer, _sendParam, _refundAddress, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Toggle compose blocking for a specific LayerZero guid
    /// @dev    Callable by authorized roles only. Blocked guids revert in lzCompose.
    /// @param _guid    bytes32 LayerZero compose guid
    /// @param _blocked bool    Block status to set
    function setBlockCompose(bytes32 _guid, bool _blocked) external requiresAuth {
        _setBlockCompose(_guid, _blocked);
    }

    /// @notice Set the maximum minMsgValue considered retryable in lzCompose
    /// @dev Callable by authorized roles only
    /// @param _maxRetryableValue New retryable threshold
    function setMaxRetryableValue(uint256 _maxRetryableValue) external requiresAuth {
        _setMaxRetryableValue(_maxRetryableValue);
    }

    /// @notice Recover ETH or ERC20 tokens accidentally held by the contract
    /// @dev Callable by authorized roles only. Executes arbitrary low-level call.
    ///      WARNING: This is a powerful admin function - ensure Authority is properly configured.
    ///      Common usage: recover(tokenAddress, 0, abi.encodeCall(IERC20.transfer, (recipient, amount)))
    ///      For ETH: recover(recipient, amount, "")
    /// @param _target address Target address for the call (token contract or ETH recipient)
    /// @param _value  uint256 Native ETH value to send with the call
    /// @param _data   bytes   Calldata (e.g., encoded ERC20.transfer call, or empty for ETH)
    function recover(address _target, uint256 _value, bytes memory _data) external requiresAuth {
        (bool success,) = _target.call{value: _value}(_data);
        if (!success) revert Errors.RecoverFailed();
    }

    /*//////////////////////////////////////////////////////////////
            VaultComposerSyncUpgradeable OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal function to initialize the share token
    ///      Overrides the base validation to use IERC7575.share() instead of requiring shareERC20 == vault
    ///      Overrides to check !approvalRequired() instead of approvalRequired() since NestShare/NestShareOFT
    ///      act as OFT adapters but don't require share approval (they use internal accounting)
    /// @return shareERC20 address The address of the share ERC20 token
    function _initializeShareToken() internal override returns (address shareERC20) {
        shareERC20 = IOFT(SHARE_OFT()).token();

        /// @dev Ensure the share token matches the vault's share token, NestVault are IERC7575 compliant
        if (IERC7575(address(VAULT())).share() != shareERC20) {
            revert Errors.ShareTokenNotVaultShare(shareERC20, IERC7575(address(VAULT())).share());
        }

        /// @dev in Nest SHARE_OFT is either NestShareOFT or NestVaultOFT, both don't require approval
        if (IOFT(SHARE_OFT()).approvalRequired()) revert Errors.ShareOFTNotNestShare(SHARE_OFT());

        /// @dev Approve the vault with the share tokens held by this contract
        IERC20(shareERC20).forceApprove(address(VAULT()), type(uint256).max);
    }

    /// @inheritdoc VaultComposerSyncUpgradeable
    /// @dev Overrides the redeem logic to interact with NestVault.instantRedeem
    /// @param _shareAmount uint256 The number of shares to redeem from the vault
    /// @return assetAmount uint256 The number of assets received from the vault redemption
    function _redeem(
        bytes32,
        /*_redeemer*/
        uint256 _shareAmount
    )
        internal
        override
        returns (uint256 assetAmount)
    {
        /// @dev Redeem shares for underlying assets from the NestShare or BoringVault contract, requires the asset to be available
        (assetAmount,) = INestVaultCore(address(VAULT())).instantRedeem(_shareAmount, address(this), address(this));
    }

    /// @inheritdoc VaultComposerSyncUpgradeable
    /// @dev Overrides the deposit logic to interact with NestVaultPredicateProxy.deposit
    ///      Predicate message is decoded from the oftCmd field in SendParam
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
    ) internal override {
        PredicateMessage memory predicateMsg = abi.decode(_sendParam.oftCmd, (PredicateMessage));

        uint256 shareAmountReceived = _depositWithPredicate(_depositor, _assetAmount, predicateMsg);
        if (shareAmountReceived == 0) revert Errors.ZeroShares();
        _assertSlippage(shareAmountReceived, _sendParam.minAmountLD);

        _sendParam.amountLD = shareAmountReceived;
        _sendParam.minAmountLD = 0;
        _sendParam.oftCmd = new bytes(0);

        _send(SHARE_OFT(), _sendParam, _refundAddress, _msgValue);

        emit Deposited(_depositor, _sendParam.to, _sendParam.dstEid, _assetAmount, shareAmountReceived);
    }

    /// @inheritdoc VaultComposerSyncUpgradeable
    /// @dev Overrides the quote send logic to use previewInstantRedeem for accurate asset amount estimation.
    ///      When quoting for ASSET_OFT (redeem path), uses NestVault.previewInstantRedeem to account for fees.
    ///      When quoting for SHARE_OFT (deposit path), uses standard vault.previewDeposit.
    /// @param _from          address      The address to check maxRedeem/maxDeposit limits against
    /// @param _targetOFT     address      The OFT to use: ASSET_OFT for redeem, SHARE_OFT for deposit
    /// @param _vaultInAmount uint256      Input amount: shares for redeem, assets for deposit
    /// @param _sendParam     SendParam    The LayerZero send parameters (amountLD will be overwritten)
    /// @return MessagingFee  MessagingFee The estimated LayerZero messaging fee
    function quoteSend(address _from, address _targetOFT, uint256 _vaultInAmount, SendParam memory _sendParam)
        external
        view
        override
        returns (MessagingFee memory)
    {
        IERC4626 vault = VAULT();

        /// @dev When quoting the asset OFT, if the input is shares, SendParam.amountLD must be assets (and vice versa)
        if (_targetOFT == ASSET_OFT()) {
            uint256 maxRedeem = vault.maxRedeem(_from);
            if (_vaultInAmount > maxRedeem) {
                revert ERC4626.ERC4626ExceededMaxRedeem(_from, _vaultInAmount, maxRedeem);
            }

            (_sendParam.amountLD,) = INestVaultCore(address(vault)).previewInstantRedeem(_vaultInAmount);
        } else {
            uint256 maxDeposit = vault.maxDeposit(_from);
            if (_vaultInAmount > maxDeposit) {
                revert ERC4626.ERC4626ExceededMaxDeposit(_from, _vaultInAmount, maxDeposit);
            }

            _sendParam.amountLD = vault.previewDeposit(_vaultInAmount);
        }
        return IOFT(_targetOFT).quoteSend(_sendParam, false);
    }
}
