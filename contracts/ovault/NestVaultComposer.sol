// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// contracts
import {AuthUpgradeable, Authority} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {VaultComposerSyncUpgradeable} from "contracts/upgradeable/ovault/VaultComposerSyncUpgradeable.sol";
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

/// @title  NestVaultComposer
/// @author plumenetwork
/// @notice NestVaultComposer is a VaultComposerSyncUpgradeable that integrates with NestVault and NestVaultPredicateProxy
/// @dev    This contract extends VaultComposerSyncUpgradeable and overrides necessary functions to interact with NestVault and NestVaultPredicateProxy.
contract NestVaultComposer is VaultComposerSyncUpgradeable, AuthUpgradeable {
    using SafeERC20 for IERC20;

    error ShareOFTNotNestShare(address shareOFT);
    error ShareTokenNotVaultShare(address shareToken, address vault);

    /// @notice Address of the NestVaultPredicateProxy contract
    INestVaultPredicateProxy public immutable PREDICATE_PROXY;

    /// @param _predicateProxy   address The address of the NestVaultPredicateProxy contract
    constructor(address _predicateProxy) {
        PREDICATE_PROXY = INestVaultPredicateProxy(_predicateProxy);

        _disableInitializers();
    }

    /// @notice Initializes the contract with the given owner
    /// @dev    This function is called only during contract initialization and delegates to `__Auth_init_unchained`
    /// @param _owner       address The address of the owner of the contract
    /// @param _vault       address The address of the NestVault contract
    /// @param _assetOFT    address The address of the underlying asset OFT contract
    /// @param _shareOFT    address The address of the share OFT contract
    function initialize(address _owner, address _vault, address _assetOFT, address _shareOFT)
        external
        virtual
        initializer
    {
        __Auth_init_unchained(_owner, Authority(address(0)));
        __VaultComposerSyncUpgradeable_init(_vault, _assetOFT, _shareOFT);
        __NestVaultComposer_init();
    }

    /// @dev Internal initializer function to set up approvals for the predicate proxy
    function __NestVaultComposer_init() internal onlyInitializing {
        /// @dev Approve the predicate proxy to pull assets for deposits
        IERC20(ASSET_ERC20()).forceApprove(address(PREDICATE_PROXY), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            PREDICATE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits ERC20 assets from the caller into the vault and sends them to the recipient,
    ///         adds a custom _depositor for predicate verification on cross-chain deposits
    /// @dev    Callable by RELAYER_ROLE. Requires authorization via the requiresAuth modifier
    /// @param _depositor The depositor (bytes32 format to account for non-evm addresses)
    /// @param _assetAmount The number of ERC20 tokens to deposit and send
    /// @param _sendParam Parameters on how to send the shares to the recipient
    /// @param _refundAddress Address to receive excess `msg.value`
    function depositAndSend(
        bytes32 _depositor,
        uint256 _assetAmount,
        SendParam memory _sendParam,
        address _refundAddress
    ) external payable requiresAuth nonReentrant {
        IERC20(ASSET_ERC20()).safeTransferFrom(msg.sender, address(this), _assetAmount);
        _depositAndSend(_depositor, _assetAmount, _sendParam, _refundAddress, msg.value);
    }

    /// @notice Redeems vault shares and sends the resulting assets to the recipient,
    ///         adds a custom _redeemer for predicate verification on cross-chain redemptions
    /// @dev    Callable by RELAYER_ROLE. Requires authorization via the requiresAuth modifier
    /// @param _redeemer The redeemer (bytes32 format to account for non-evm addresses)
    /// @param _shareAmount The number of vault shares to redeem
    /// @param _sendParam Parameter that defines how to send the assets
    /// @param _refundAddress Address to receive excess payment of the LZ fees
    function redeemAndSend(bytes32 _redeemer, uint256 _shareAmount, SendParam memory _sendParam, address _refundAddress)
        external
        payable
        requiresAuth
        nonReentrant
    {
        IERC20(SHARE_ERC20()).safeTransferFrom(msg.sender, address(this), _shareAmount);
        _redeemAndSend(_redeemer, _shareAmount, _sendParam, _refundAddress, msg.value);
    }

    /// @dev Internal function to deposit assets using a predicate message
    /// @param  _depositor     bytes32          The depositor (bytes32 format to account for non-evm addresses)
    /// @param  _assetAmount   uint256          The amount of underlying asset to deposit
    /// @param  _predicateMsg  PredicateMessage The predicate message containing deposit conditions
    /// @return shareAmount    uint256          The amount of shares received from the deposit
    function _depositWithPredicate(bytes32 _depositor, uint256 _assetAmount, PredicateMessage memory _predicateMsg)
        internal
        returns (uint256 shareAmount)
    {
        shareAmount = PREDICATE_PROXY.deposit(
            ERC20(ASSET_ERC20()), _assetAmount, address(this), NestVault(address(VAULT())), _depositor, _predicateMsg
        );
    }

    /*//////////////////////////////////////////////////////////////
                    VaultComposerSyncUpgradeable OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal function to initialize the share token
    /// @return shareERC20 The address of the share ERC20 token
    /// @dev Overrides to remove revert if `ShareTokenNotVault` as NestVaultOFT is IERC7575 compliant
    /// @dev Overrides to remove revert if `ShareOFTNotAdapter` as NestVaultOFT acts as an OFT adapter but doesn't require share approval
    function _initializeShareToken() internal override returns (address shareERC20) {
        shareERC20 = IOFT(SHARE_OFT()).token();

        /// @dev Ensure the share token matches the vault's share token, NestVault are IERC7575 compliant
        if (IERC7575(address(VAULT())).share() != shareERC20) {
            revert ShareTokenNotVaultShare(shareERC20, IERC7575(address(VAULT())).share());
        }

        /// @dev in Nest SHARE_OFT is either NestShareOFT or NestShare, both don't require approval
        if (IOFT(SHARE_OFT()).approvalRequired()) revert ShareOFTNotNestShare(SHARE_OFT());

        /// @dev Approve the share adapter with the share tokens held by this contract
        IERC20(shareERC20).forceApprove(address(VAULT()), type(uint256).max);
    }

    /// @inheritdoc VaultComposerSyncUpgradeable
    /// @dev Overrides the redeem logic to interact with NestVault.instantRedeem
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
    /// @dev Predicate message is decoded from the oftCmd field in SendParam
    function _depositAndSend(
        bytes32 _depositor,
        uint256 _assetAmount,
        SendParam memory _sendParam,
        address _refundAddress,
        uint256 _msgValue
    ) internal override {
        PredicateMessage memory predicateMsg = abi.decode(_sendParam.oftCmd, (PredicateMessage));

        uint256 shareAmountReceived = _depositWithPredicate(_depositor, _assetAmount, predicateMsg);
        _assertSlippage(shareAmountReceived, _sendParam.minAmountLD);

        _sendParam.amountLD = shareAmountReceived;
        _sendParam.minAmountLD = 0;
        _sendParam.oftCmd = new bytes(0);

        _send(SHARE_OFT(), _sendParam, _refundAddress, _msgValue);

        emit Deposited(_depositor, _sendParam.to, _sendParam.dstEid, _assetAmount, shareAmountReceived);
    }

    /// @inheritdoc VaultComposerSyncUpgradeable
    /// @dev Overrides the quote send logic to account for proper share-asset conversions when redeeming through instantRedeem
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
