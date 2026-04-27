// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.22;

// contracts
import {VaultComposerSyncUpgradeable} from "./VaultComposerSyncUpgradeable.sol";

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOFT, SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IVaultComposerSync} from "@layerzerolabs/ovault-evm/contracts/interfaces/IVaultComposerSync.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";

// libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {Errors} from "contracts/types/Errors.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title  VaultComposerAsyncUpgradeable
/// @notice Async vault composer supporting IERC7540 redemption lifecycle via LayerZero OFT
/// @author plumenetwork
contract VaultComposerAsyncUpgradeable is VaultComposerSyncUpgradeable {
    using OFTComposeMsgCodec for bytes;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice Emitted when compose blocking status is updated for a message guid
    /// @param guid    bytes32 LayerZero compose guid
    /// @param blocked bool    Whether compose execution is blocked
    event BlockComposeSet(bytes32 indexed guid, bool blocked);

    /// @notice Emitted when max retryable value is updated
    /// @param maxRetryableValue New maximum retryable minMsgValue
    event MaxRetryableValueSet(uint256 maxRetryableValue);

    /// @notice Revert when a blocked compose guid is retried
    /// @param guid bytes32 LayerZero compose guid
    error ComposeBlocked(bytes32 guid);

    /*//////////////////////////////////////////////////////////////
                            STORAGE STRUCT
    //////////////////////////////////////////////////////////////*/

    /// @notice Storage struct for VaultComposerAsyncUpgradeable
    /// @dev    Used by library functions that need access to full storage
    struct VaultComposerAsyncStorage {
        /// @dev Total pending shares across all endpoint IDs
        uint256 totalPendingSharesSum;
        /// @dev Total fulfilled shares already attributed to users
        uint256 totalFulfilledSharesSum;
        /// @dev Total fulfilled claimable assets already attributed to users
        uint256 totalFulfilledAssetsSum;
        /// @dev Maximum minMsgValue considered retryable in lzCompose
        uint256 maxRetryableValue;
        /// @dev Pending shares per endpoint
        mapping(uint32 eid => uint256 shares) totalPendingShares;
        /// @dev Per-user pending redemption tracking (redeemer => eid => PendingRedeem)
        mapping(bytes32 redeemer => mapping(uint32 eid => NestVaultCoreTypes.PendingRedeem)) pendingRedeem;
        /// @dev Per-user claimable balance tracking (redeemer => eid => ClaimableRedeem)
        mapping(bytes32 redeemer => mapping(uint32 eid => NestVaultCoreTypes.ClaimableRedeem)) claimableRedeem;
        /// @dev Per-guid compose block switch
        mapping(bytes32 guid => bool blocked) composeBlocked;
    }

    /// @notice Enum defining the type of redemption operation for cross-chain compose messages
    /// @dev Used by VaultComposerAsyncUpgradeable to route redemption operations
    enum RedeemType {
        /// @dev Instant redemption - redeems shares immediately and sends assets back
        InstantRedeem,
        /// @dev Request redemption - queues shares for async IERC7540 redemption
        RequestRedeem,
        /// @dev Update redemption request - modifies pending shares, returns excess to user
        UpdateRedeemRequest,
        /// @dev Finish redemption - redeems claimable shares and sends assets cross-chain
        FinishRedeem
    }

    // keccak256(abi.encode(uint256(keccak256("plumenetwork.storage.VaultComposerAsyncUpgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VaultComposerAsyncUpgradeableStorageLocation =
        0x675d05f61eb76f02999633de01879883f3d5f70be938ea35e43653caafefd900;

    /// @dev Returns the async storage slot
    /// @return $ VaultComposerAsyncStorage storage reference
    function _getVaultComposerAsyncStorage() private pure returns (VaultComposerAsyncStorage storage $) {
        assembly {
            $.slot := VaultComposerAsyncUpgradeableStorageLocation
        }
    }

    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes async composer storage values
    /// @param _maxRetryableValue Initial maximum retryable minMsgValue
    function __VaultComposerAsyncUpgradeable_init(uint256 _maxRetryableValue) internal onlyInitializing {
        _getVaultComposerAsyncStorage().maxRetryableValue = _maxRetryableValue;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Total pending shares across all endpoint IDs
    /// @dev Reads from async storage slot
    /// @return uint256 Sum of all pending shares
    function totalPendingSharesSum() public view virtual returns (uint256) {
        return _getVaultComposerAsyncStorage().totalPendingSharesSum;
    }

    /// @notice Pending shares for a specific endpoint ID
    /// @dev Reads from async storage slot mapping
    /// @param _eid uint32 Endpoint ID to query
    /// @return    uint256 Pending shares for the endpoint
    function totalPendingShares(uint32 _eid) public view virtual returns (uint256) {
        return _getVaultComposerAsyncStorage().totalPendingShares[_eid];
    }

    /// @notice Total fulfilled claimable assets already attributed to users
    /// @dev Reads from async storage slot
    /// @return uint256 Sum of user-level claimable assets tracked by the composer
    function totalFulfilledAssetsSum() public view virtual returns (uint256) {
        return _getVaultComposerAsyncStorage().totalFulfilledAssetsSum;
    }

    /// @notice Pending redeem for a redeemer on a specific endpoint
    /// @dev Reads from async storage nested mapping
    /// @param _redeemer bytes32 Redeemer identifier
    /// @param _eid      uint32  Endpoint ID
    /// @return NestVaultCoreTypes.PendingRedeem Pending redeem data
    function pendingRedeem(bytes32 _redeemer, uint32 _eid)
        public
        view
        virtual
        returns (NestVaultCoreTypes.PendingRedeem memory)
    {
        return _getVaultComposerAsyncStorage().pendingRedeem[_redeemer][_eid];
    }

    /// @notice Claimable redeem for a redeemer on a specific endpoint
    /// @dev Reads from async storage nested mapping
    /// @param _redeemer bytes32                   Redeemer identifier
    /// @param _eid      uint32                    Endpoint ID
    /// @return          NestVaultCoreTypes.ClaimableRedeem Claimable redeem data
    function claimableRedeem(bytes32 _redeemer, uint32 _eid)
        public
        view
        virtual
        returns (NestVaultCoreTypes.ClaimableRedeem memory)
    {
        return _getVaultComposerAsyncStorage().claimableRedeem[_redeemer][_eid];
    }

    /// @notice Returns whether compose execution is blocked for a guid
    /// @param _guid bytes32 LayerZero compose guid
    /// @return bool True when compose execution is blocked
    function composeBlocked(bytes32 _guid) public view virtual returns (bool) {
        return _getVaultComposerAsyncStorage().composeBlocked[_guid];
    }

    /// @notice Get the maximum minMsgValue considered retryable in lzCompose
    /// @return uint256 Current retryable threshold
    function maxRetryableValue() public view virtual returns (uint256) {
        return _getVaultComposerAsyncStorage().maxRetryableValue;
    }

    /// @inheritdoc VaultComposerSyncUpgradeable
    function lzCompose(
        address _composeSender, // The OFT used on refund, also the vaultIn token.
        bytes32 _guid,
        bytes calldata _message, // expected to contain a composeMessage = abi.encode(SendParam sendParam,uint256 minMsgValue)
        address,
        /*_executor*/
        bytes calldata /*_extraData*/
    )
        public
        payable
        virtual
        override
    {
        // Validate caller is the LayerZero endpoint
        if (msg.sender != ENDPOINT()) revert IVaultComposerSync.OnlyEndpoint(msg.sender);

        // Validate compose sender is either asset or share OFT
        if (_composeSender != ASSET_OFT() && _composeSender != SHARE_OFT()) {
            revert IVaultComposerSync.OnlyValidComposeCaller(_composeSender);
        }
        if (composeBlocked(_guid)) revert ComposeBlocked(_guid);

        // Parse message header
        uint32 srcEid = _message.srcEid();
        bytes32 composeFrom = _message.composeFrom();
        uint256 amount = _message.amountLD();
        bytes memory composeMsg = _message.composeMsg();

        /// @dev try...catch to handle the compose operation. if it fails we refund the user
        try this.handleAsyncCompose{value: msg.value}(_composeSender, srcEid, composeFrom, composeMsg, amount) {
            emit Sent(_guid);
        } catch (bytes memory _err) {
            /// @dev A revert where _err is considered retryable is handled separately
            if (_retryable(_err)) {
                assembly {
                    revert(add(32, _err), mload(_err))
                }
            }

            _refund(_composeSender, _message, amount, tx.origin, msg.value);
            emit Refunded(_guid);
        }
    }

    /// @notice Detects if the `handleAsyncCompose` error is considered retryable
    /// @dev If user-defined minMsgValue < msg.value, refund if msg.value is above the `maxRetryableValue`.
    ///      This is because it is possible to re-trigger from the endpoint the compose operation with the right msg.value
    ///      If `minMsgValue > maxRetryableValue`, the compose is considered non-executable; refunding here avoids permanently failing compose retries.
    /// @param _err bytes The error data from the revert
    /// @return bool True if the error is considered retryable, false otherwise
    function _retryable(bytes memory _err) internal view virtual returns (bool) {
        if (bytes4(_err) == InsufficientMsgValue.selector && _err.length == 68) {
            uint256 minMsgValue;
            assembly {
                minMsgValue := mload(add(_err, 0x24))
            }

            if (minMsgValue <= maxRetryableValue()) return true;
        }

        return false;
    }

    /// @notice Handles async compose for OFT transactions
    /// @dev Self-call only. Supports InstantRedeem, RequestRedeem, FinishRedeem, UpdateRedeemRequest
    /// @param _oftIn       address   OFT token received
    /// @param _srcEid      uint32    Source endpoint ID
    /// @param _composeFrom bytes32   Compose sender identifier
    /// @param _composeMsg  bytes     Encoded SendParam and minMsgValue
    /// @param _amount      uint256   Tokens received
    function handleAsyncCompose(
        address _oftIn,
        uint32 _srcEid,
        bytes32 _composeFrom,
        bytes calldata _composeMsg,
        uint256 _amount
    ) external payable virtual {
        /// @dev Can only be called by self
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);

        (SendParam memory sendParam, uint256 minMsgValue) = abi.decode(_composeMsg, (SendParam, uint256));
        if (msg.value < minMsgValue) revert InsufficientMsgValue(minMsgValue, msg.value);

        if (_oftIn == ASSET_OFT()) {
            _depositAndSend(_composeFrom, _amount, sendParam, tx.origin, msg.value);
        } else {
            _handleRedeemCompose(_srcEid, _composeFrom, sendParam, _amount, tx.origin, msg.value);
        }
    }

    /// @dev Routes redeem compose by RedeemType
    /// @param _srcEid      uint32    Source endpoint ID
    /// @param _composeFrom bytes32   Compose sender
    /// @param _sendParam   SendParam Contains redeem type in oftCmd
    /// @param _amount      uint256   Shares received
    /// @param _msgValue    uint256   Native value for LZ fees
    function _handleRedeemCompose(
        uint32 _srcEid,
        bytes32 _composeFrom,
        SendParam memory _sendParam,
        uint256 _amount,
        address _refundAddress,
        uint256 _msgValue
    ) internal virtual {
        RedeemType _redeemType = _decodeRedeemType(_sendParam.oftCmd);

        if (_redeemType == RedeemType.InstantRedeem) {
            _redeemAndSend(_composeFrom, _amount, _sendParam, _refundAddress, _msgValue);
        } else if (_redeemType == RedeemType.RequestRedeem) {
            _requestRedeem(_srcEid, _composeFrom, _amount);
        } else if (_redeemType == RedeemType.FinishRedeem) {
            if (_amount > 0) revert Errors.UnexpectedNonZeroAmount();
            _finishRedeemAndSend(_srcEid, _composeFrom, _sendParam, _refundAddress, _msgValue);
        } else if (_redeemType == RedeemType.UpdateRedeemRequest) {
            if (_amount > 0) revert Errors.UnexpectedNonZeroAmount();
            _updateRequestRedeemAndSend(_srcEid, _composeFrom, _sendParam, _refundAddress, _msgValue);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ASYNC REDEEM FUNCTIONS (IERC7540)
    //////////////////////////////////////////////////////////////*/

    /// @dev Decodes and validates redeem type from oftCmd (expects a single ABI-encoded word)
    /// @param _oftCmd bytes from SendParam.oftCmd
    function _decodeRedeemType(bytes memory _oftCmd) internal pure returns (RedeemType redeemType) {
        if (_oftCmd.length != 32) revert Errors.UnknownRedeemType();
        uint256 rawType = abi.decode(_oftCmd, (uint256));
        if (rawType > uint256(RedeemType.FinishRedeem)) {
            revert Errors.UnknownRedeemType();
        }
        redeemType = RedeemType(rawType);
    }

    /// @dev Queues shares for async redemption via IERC7540
    /// @param _srcEid      uint32  Source endpoint ID
    /// @param _redeemer    bytes32 User identifier
    /// @param _shareAmount uint256 Shares to queue
    function _requestRedeem(uint32 _srcEid, bytes32 _redeemer, uint256 _shareAmount) internal virtual {
        VaultComposerAsyncStorage storage $ = _getVaultComposerAsyncStorage();

        $.totalPendingSharesSum += _shareAmount;
        $.totalPendingShares[_srcEid] += _shareAmount;
        uint256 _currentPendingShares = $.pendingRedeem[_redeemer][_srcEid].shares;
        $.pendingRedeem[_redeemer][_srcEid] =
            NestVaultCoreTypes.PendingRedeem({shares: _shareAmount + _currentPendingShares});

        INestVaultCore(address(VAULT())).requestRedeem(_shareAmount, address(this), address(this));
    }

    /// @dev Updates pending redemption. Returns excess shares to user if reducing.
    /// @param _srcEid        uint32    Source endpoint ID
    /// @param _redeemer      bytes32   User identifier
    /// @param _sendParam     SendParam New share amount in amountLD
    /// @param _refundAddress address   LZ fee refund address
    /// @param _msgValue      uint256   Native value for LZ fees
    function _updateRequestRedeemAndSend(
        uint32 _srcEid,
        bytes32 _redeemer,
        SendParam memory _sendParam,
        address _refundAddress,
        uint256 _msgValue
    ) internal virtual {
        VaultComposerAsyncStorage storage $ = _getVaultComposerAsyncStorage();
        uint256 _oldShares = $.pendingRedeem[_redeemer][_srcEid].shares;
        if (_oldShares == 0) {
            revert Errors.NoPendingRedeem();
        }

        uint256 _newShares = _sendParam.amountLD;
        if (_oldShares < _newShares) {
            revert Errors.InsufficientBalance();
        }
        if (_oldShares == _newShares) {
            // No change in shares, nothing to do
            return;
        }

        uint256 _returnAmount = _oldShares - _newShares;
        IERC20 shareErc20 = IERC20(SHARE_ERC20());

        $.pendingRedeem[_redeemer][_srcEid] = NestVaultCoreTypes.PendingRedeem({shares: _newShares});
        $.totalPendingSharesSum -= _returnAmount;
        $.totalPendingShares[_srcEid] -= _returnAmount;

        uint256 preShareBalance = shareErc20.balanceOf(address(this));
        INestVaultCore(address(VAULT())).updateRedeem($.totalPendingSharesSum, address(this), address(this));
        uint256 postShareBalance = shareErc20.balanceOf(address(this));

        if (_returnAmount > postShareBalance - preShareBalance) {
            revert Errors.TransferInsufficient();
        }

        // Update sendParam with the actual return amount for the cross-chain send
        _sendParam.oftCmd = new bytes(0);
        _sendParam.amountLD = _returnAmount;
        _sendParam.minAmountLD = 0;

        _send(SHARE_OFT(), _sendParam, _refundAddress, _msgValue);
    }

    /// @dev Redeems claimable shares and sends assets cross-chain
    /// @param _srcEid        uint32    Source endpoint ID
    /// @param _redeemer      bytes32   User identifier
    /// @param _sendParam     SendParam Share amount and destination
    /// @param _refundAddress address   LZ fee refund address
    /// @param _msgValue      uint256   Native value for LZ fees
    function _finishRedeemAndSend(
        uint32 _srcEid,
        bytes32 _redeemer,
        SendParam memory _sendParam,
        address _refundAddress,
        uint256 _msgValue
    ) internal virtual {
        VaultComposerAsyncStorage storage $ = _getVaultComposerAsyncStorage();

        uint256 _shareAmount = _sendParam.amountLD;

        // Validate claimable shares
        if (_shareAmount == 0) {
            revert Errors.ZeroShares();
        }

        NestVaultCoreTypes.ClaimableRedeem storage _userClaimable = $.claimableRedeem[_redeemer][_srcEid];
        if (_userClaimable.shares < _shareAmount) {
            revert Errors.InsufficientClaimable();
        }

        uint256 _claimableShares = _userClaimable.shares;
        uint256 _claimableAssets = _userClaimable.assets;

        uint256 assetAmount;
        if (_shareAmount == _claimableShares) {
            assetAmount = _claimableAssets;
            _userClaimable.shares = 0;
            _userClaimable.assets = 0;
        } else {
            assetAmount = _shareAmount.mulDiv(_claimableAssets, _claimableShares);
            if (assetAmount == 0) {
                revert Errors.ERC7540ZeroPayout();
            }

            _userClaimable.shares = _claimableShares.saturatingSub(_shareAmount);
            _userClaimable.assets = _claimableAssets.saturatingSub(assetAmount);
        }

        // Withdraw from vault using user-level claimable ratio
        IERC20 _assetErc20 = IERC20(ASSET_ERC20());
        uint256 preAssetBalance = _assetErc20.balanceOf(address(this));
        uint256 sharesConsumed = VAULT().withdraw(assetAmount, address(this), address(this));
        uint256 postAssetBalance = _assetErc20.balanceOf(address(this));

        uint256 assetAmountReceived = postAssetBalance - preAssetBalance;
        if (assetAmountReceived < _sendParam.minAmountLD) {
            revert IVaultComposerSync.SlippageExceeded(assetAmountReceived, _sendParam.minAmountLD);
        }

        // Update tracked vault claimable shares consumed from vault
        $.totalFulfilledSharesSum = $.totalFulfilledSharesSum.saturatingSub(sharesConsumed);
        $.totalFulfilledAssetsSum = $.totalFulfilledAssetsSum.saturatingSub(assetAmount);

        emit Redeemed(_redeemer, _sendParam.to, _sendParam.dstEid, _shareAmount, assetAmountReceived);

        // Update sendParam with the actual asset amount for the cross-chain send
        _sendParam.amountLD = assetAmountReceived;
        _sendParam.minAmountLD = 0;

        _send(ASSET_OFT(), _sendParam, _refundAddress, _msgValue);
    }

    /// @dev Fulfills pending redemption: calls vault, updates tracking, credits claimable.
    ///      Guards against double-counting by detecting if vault.fulfillRedeem was called directly.
    /// @param _srcEid   uint32  Source endpoint ID
    /// @param _redeemer bytes32 User identifier
    /// @param _shares   uint256 Shares to fulfill
    /// @return _assets  uint256 Assets made claimable
    function _fulfillRedeem(uint32 _srcEid, bytes32 _redeemer, uint256 _shares)
        internal
        virtual
        returns (uint256 _assets)
    {
        VaultComposerAsyncStorage storage $ = _getVaultComposerAsyncStorage();
        NestVaultCoreTypes.PendingRedeem storage _request = $.pendingRedeem[_redeemer][_srcEid];

        if (_request.shares == 0) {
            revert Errors.NoPendingRedeem();
        }
        if (_shares > _request.shares) {
            revert Errors.InsufficientBalance();
        }

        INestVaultCore _vaultCore = INestVaultCore(address(VAULT()));

        // Read the vault's live controller-level claimable state. This may already include shares/assets that
        // became claimable through a direct `vault.fulfillRedeem(address(this), ...)` call outside the composer.
        uint256 claimableShares = _vaultCore.claimableRedeemRequest(0, address(this));
        uint256 claimableAssets = _vaultCore.maxWithdraw(address(this));

        // Clamp totalFulfilled state to the vault's current state before diffing.
        $.totalFulfilledSharesSum = Math.min($.totalFulfilledSharesSum, claimableShares);
        $.totalFulfilledAssetsSum = Math.min($.totalFulfilledAssetsSum, claimableAssets);
        uint256 totalFulfilledSharesSum = $.totalFulfilledSharesSum;
        uint256 trackedFulfilledAssetsSum = $.totalFulfilledAssetsSum;

        // Anything claimable in the vault above the amount already attributed to users is "unaccounted"
        uint256 unaccountedClaimableShares = claimableShares.saturatingSub(totalFulfilledSharesSum);
        uint256 unaccountedClaimableAssets = claimableAssets.saturatingSub(trackedFulfilledAssetsSum);
        uint256 sharesFromUnaccounted = Math.min(_shares, unaccountedClaimableShares);

        if (sharesFromUnaccounted > 0) {
            // Preserve the vault's current share/assets ratio when only part of the unaccounted claimable
            // balance is being assigned to this user.
            _assets = sharesFromUnaccounted == unaccountedClaimableShares
                ? unaccountedClaimableAssets
                : unaccountedClaimableAssets.mulDiv(sharesFromUnaccounted, unaccountedClaimableShares);
        }

        // Only the remainder still needs a fresh vault fulfillment.
        uint256 sharesToFulfill = _shares - sharesFromUnaccounted;

        if (sharesToFulfill > 0) {
            _assets += _vaultCore.fulfillRedeem(address(this), sharesToFulfill);
        }

        if (_assets == 0) {
            revert Errors.ZeroAssets();
        }

        // Update the user's pending shares
        _request.shares -= _shares;

        // Track claimable shares already attributed to users
        $.totalPendingSharesSum = $.totalPendingSharesSum.saturatingSub(_shares);
        $.totalPendingShares[_srcEid] = $.totalPendingShares[_srcEid].saturatingSub(_shares);

        // Mark this portion of the controller-level claimable pool as now attributed to users.
        $.totalFulfilledSharesSum = totalFulfilledSharesSum + _shares;
        $.totalFulfilledAssetsSum = trackedFulfilledAssetsSum + _assets;

        // Credit the claimable balance to the specific user
        $.claimableRedeem[_redeemer][_srcEid] = NestVaultCoreTypes.ClaimableRedeem(
            $.claimableRedeem[_redeemer][_srcEid].assets + _assets,
            $.claimableRedeem[_redeemer][_srcEid].shares + _shares
        );
    }

    /// @dev Internal setter for compose block switch
    /// @param _guid    bytes32 LayerZero compose guid
    /// @param _blocked bool    Block status
    function _setBlockCompose(bytes32 _guid, bool _blocked) internal virtual {
        _getVaultComposerAsyncStorage().composeBlocked[_guid] = _blocked;

        emit BlockComposeSet(_guid, _blocked);
    }

    /// @dev Internal setter for max retryable minMsgValue threshold
    /// @param _maxRetryableValue New retryable threshold
    function _setMaxRetryableValue(uint256 _maxRetryableValue) internal virtual {
        _getVaultComposerAsyncStorage().maxRetryableValue = _maxRetryableValue;

        emit MaxRetryableValueSet(_maxRetryableValue);
    }
}
