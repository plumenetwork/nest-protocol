// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// contracts
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {AuthUpgradeable, Authority} from "contracts/auth/AuthUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {NestVault} from "contracts/NestVault.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    ReentrancyGuardTransientUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

// libraries
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

// interfaces
import {IComplianceHook} from "contracts/compliance/interfaces/IComplianceHook.sol";
import {IComplianceProxy} from "contracts/compliance/interfaces/IComplianceProxy.sol";
import {ISignatureTransfer} from "@uniswap/permit2/interfaces/ISignatureTransfer.sol";

/// @title  ComplianceProxy
/// @author plumenetwork
/// @notice Compliance-gated deposit/mint entrypoint for NestVault. Provider-agnostic successor to
///         NestVaultPredicateProxy: proofs travel as opaque `bytes` validated by a pluggable IComplianceHook.
/// @dev    Upgradeable. Owns the canonical policy payloads so hooks stay provider-only;
///         payload shapes match NestVaultPredicateProxy for policy parity.
contract ComplianceProxy is
    Initializable,
    AuthUpgradeable,
    ReentrancyGuardTransientUpgradeable,
    PausableUpgradeable,
    IComplianceProxy
{
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Error thrown when a zero address is provided.
    error ComplianceProxy__ZeroAddress();

    /// @dev Error thrown when the compliance hook rejects the transaction.
    error ComplianceProxy__UnauthorizedTransaction();

    /// @dev Error thrown when the Permit2 transfer delivers fewer tokens than requested.
    error ComplianceProxy__InsufficientPermit2Transfer();

    /// @dev Error thrown when the vault mints fewer shares than requested.
    error ComplianceProxy__InsufficientShares();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev   Emitted when a deposit is made. Shape matches NestVaultPredicateProxy.Deposit.
    /// @param receiver         address indexed The address receiving the shares from the deposit
    /// @param depositAsset     address indexed The address of the ERC20 token deposited
    /// @param depositAmount    uint256         The amount of the deposit asset deposited
    /// @param shareAmount      uint256         The amount of shares minted from the deposit
    /// @param depositTimestamp uint256         The timestamp of when the deposit occurred
    /// @param vault            address         The address of the NestVault contract the deposit was made to
    event Deposit(
        address indexed receiver,
        address indexed depositAsset,
        uint256 depositAmount,
        uint256 shareAmount,
        uint256 depositTimestamp,
        address vault
    );

    /// @dev   Emitted when a redeem request is submitted through the compliance proxy.
    /// @param owner            address indexed The owner supplying the shares
    /// @param controller       address indexed The controller credited with the request
    /// @param shareAmount      uint256         The amount of shares requested for redemption
    /// @param requestId        uint256         The request identifier returned by the vault
    /// @param requestTimestamp uint256         The timestamp of the request
    /// @param vault            address         The NestVault receiving the request
    event RedeemRequest(
        address indexed owner,
        address indexed controller,
        uint256 shareAmount,
        uint256 requestId,
        uint256 requestTimestamp,
        address vault
    );

    /// @dev   Emitted when an instant redemption is executed through the compliance proxy.
    /// @param owner           address indexed The owner supplying the shares
    /// @param receiver        address indexed The address receiving the assets
    /// @param shareAmount     uint256         The amount of shares redeemed
    /// @param postFeeAmount   uint256         The amount of assets delivered after fees
    /// @param feeAmount       uint256         The fee charged on the redemption
    /// @param redeemTimestamp uint256         The timestamp of the redemption
    /// @param vault           address         The NestVault executing the redemption
    event InstantRedeem(
        address indexed owner,
        address indexed receiver,
        uint256 shareAmount,
        uint256 postFeeAmount,
        uint256 feeAmount,
        uint256 redeemTimestamp,
        address vault
    );

    /// @notice Emitted when the compliance hook is updated.
    /// @param oldHook address The previous hook.
    /// @param newHook address The new hook.
    event ComplianceHookUpdated(address indexed oldHook, address indexed newHook);

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The compliance hook consulted before every deposit/mint.
    IComplianceHook public complianceHook;

    /*//////////////////////////////////////////////////////////////
                       CONSTRUCTOR & INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @dev Disables initializers on the implementation.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the specified owner and compliance hook.
    /// @param _owner          address         The address to be set as the contract owner
    /// @param _complianceHook IComplianceHook The hook validating compliance proofs
    function initialize(address _owner, IComplianceHook _complianceHook) external initializer {
        if (_owner == address(0) || address(_complianceHook) == address(0)) revert ComplianceProxy__ZeroAddress();
        __Auth_init(_owner, Authority(address(0)));
        complianceHook = _complianceHook;
        emit ComplianceHookUpdated(address(0), address(_complianceHook));
    }

    /// @notice Returns the version of the ComplianceProxy contract.
    /// @dev    This version is used to track contract upgrades.
    /// @return string A string representing the version of the contract.
    function version() public pure returns (string memory) {
        return "1.0.0";
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IComplianceProxy
    /// @dev Public by default through the configured authority; authorization is revocable per selector.
    function deposit(
        ERC20 _depositAsset,
        uint256 _assets,
        address _receiver,
        NestVault _vault,
        bytes calldata _complianceData
    ) external override requiresAuth nonReentrant whenNotPaused returns (uint256 _shares) {
        // @dev Payload is only validated by the hook against the policy; no call is made with it.
        // The real deposit logic executes below after authorization succeeds.
        _checkCompliance(msg.sender, abi.encodeWithSignature("deposit()"), _complianceData);

        _depositAsset.safeTransferFrom(msg.sender, address(this), _assets);
        _shares = _deposit(_depositAsset, _assets, _receiver, _vault);
    }

    /// @inheritdoc IComplianceProxy
    /// @dev Uses Permit2 SignatureTransfer for gasless token approvals.
    function depositWithPermit2(
        ERC20 _depositAsset,
        uint256 _assets,
        address _receiver,
        NestVault _vault,
        ISignatureTransfer _permit2,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _signature,
        bytes calldata _complianceData
    ) external override requiresAuth nonReentrant whenNotPaused returns (uint256 _shares) {
        // @dev Payload is only validated by the hook against the policy; no call is made with it.
        // The real deposit logic executes below after authorization succeeds.
        _checkCompliance(msg.sender, abi.encodeWithSignature("deposit()"), _complianceData);

        _permit2TransferFrom(_depositAsset, _assets, _permit2, _nonce, _deadline, _signature);
        _shares = _deposit(_depositAsset, _assets, _receiver, _vault);
    }

    /// @inheritdoc IComplianceProxy
    /// @dev Public by default through the configured authority; authorization is revocable per selector.
    function depositOnBehalf(
        NestVault _vault,
        ERC20 _depositAsset,
        uint256 _assets,
        address _receiver,
        bytes32 _depositor,
        bytes calldata _complianceData
    ) external override requiresAuth nonReentrant whenNotPaused returns (uint256 _shares) {
        _checkCompliance(msg.sender, abi.encodeWithSignature("deposit(bytes32)", _depositor), _complianceData);

        _depositAsset.safeTransferFrom(msg.sender, address(this), _assets);
        _shares = _deposit(_depositAsset, _assets, _receiver, _vault);
    }

    /// @inheritdoc IComplianceProxy
    /// @dev Public by default through the configured authority; msg.sender supplies the assets using Permit2.
    function depositOnBehalfWithPermit2(
        NestVault _vault,
        ERC20 _depositAsset,
        uint256 _assets,
        address _receiver,
        bytes32 _depositor,
        ISignatureTransfer _permit2,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _signature,
        bytes calldata _complianceData
    ) external override requiresAuth nonReentrant whenNotPaused returns (uint256 _shares) {
        _checkCompliance(msg.sender, abi.encodeWithSignature("deposit(bytes32)", _depositor), _complianceData);

        _permit2TransferFrom(_depositAsset, _assets, _permit2, _nonce, _deadline, _signature);
        _shares = _deposit(_depositAsset, _assets, _receiver, _vault);
    }

    /// @inheritdoc IComplianceProxy
    /// @dev Public by default through the configured authority; authorization is revocable per selector.
    function mint(
        ERC20 _depositAsset,
        uint256 _shares,
        address _receiver,
        NestVault _vault,
        bytes calldata _complianceData
    ) external override requiresAuth nonReentrant whenNotPaused returns (uint256 _actualShares) {
        // @dev Payload is only validated by the hook against the policy; no call is made with it.
        _checkCompliance(msg.sender, abi.encodeWithSignature("deposit()"), _complianceData);

        uint256 _assets = _vault.previewMint(_shares);
        _depositAsset.safeTransferFrom(msg.sender, address(this), _assets);
        _actualShares = _deposit(_depositAsset, _assets, _receiver, _vault);
        if (_actualShares < _shares) revert ComplianceProxy__InsufficientShares();
    }

    /// @inheritdoc IComplianceProxy
    /// @dev Attests `_depositor` distinct from msg.sender for cross-chain mint integrations.
    function mintOnBehalf(
        ERC20 _depositAsset,
        uint256 _shares,
        address _receiver,
        NestVault _vault,
        bytes32 _depositor,
        bytes calldata _complianceData
    ) external override requiresAuth nonReentrant whenNotPaused returns (uint256 _actualShares) {
        _checkCompliance(msg.sender, abi.encodeWithSignature("deposit(bytes32)", _depositor), _complianceData);

        uint256 _assets = _vault.previewMint(_shares);
        _depositAsset.safeTransferFrom(msg.sender, address(this), _assets);
        _actualShares = _deposit(_depositAsset, _assets, _receiver, _vault);
        if (_actualShares < _shares) revert ComplianceProxy__InsufficientShares();
    }

    /*//////////////////////////////////////////////////////////////
                           REDEEM FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IComplianceProxy
    /// @dev Pulls shares into the proxy before requesting redemption so users do not need to grant
    ///      the upgradeable proxy a standing ERC-7540 operator approval.
    function requestRedeem(uint256 _shares, address _controller, NestVault _vault, bytes calldata _complianceData)
        external
        override
        requiresAuth
        nonReentrant
        whenNotPaused
        returns (uint256 _requestId)
    {
        // @dev This payload is only validated by the hook to match the compliance policy.
        _checkCompliance(msg.sender, abi.encodeWithSignature("requestRedeem()"), _complianceData);

        ERC20 _share = ERC20(_vault.share());
        _share.safeTransferFrom(msg.sender, address(this), _shares);
        _requestId = _requestRedeem(_share, _shares, msg.sender, _controller, _vault);
    }

    /// @inheritdoc IComplianceProxy
    function requestRedeemWithPermit2(
        uint256 _shares,
        address _controller,
        NestVault _vault,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _signature,
        bytes calldata _complianceData
    ) external override requiresAuth nonReentrant whenNotPaused returns (uint256 _requestId) {
        _checkCompliance(msg.sender, abi.encodeWithSignature("requestRedeem()"), _complianceData);

        ERC20 _share = ERC20(_vault.share());
        _permit2TransferFrom(_share, _shares, _vault.PERMIT2(), _nonce, _deadline, _signature);
        _requestId = _requestRedeem(_share, _shares, msg.sender, _controller, _vault);
    }

    /// @inheritdoc IComplianceProxy
    /// @dev Pulls shares into the proxy before redeeming so users do not need to grant the
    ///      upgradeable proxy a standing ERC-7540 operator approval.
    function instantRedeem(uint256 _shares, address _receiver, NestVault _vault, bytes calldata _complianceData)
        external
        override
        requiresAuth
        nonReentrant
        whenNotPaused
        returns (uint256 _postFeeAmount, uint256 _feeAmount)
    {
        // @dev This payload is only validated by the hook to match the compliance policy.
        _checkCompliance(msg.sender, abi.encodeWithSignature("instantRedeem()"), _complianceData);

        ERC20 _share = ERC20(_vault.share());
        _share.safeTransferFrom(msg.sender, address(this), _shares);
        (_postFeeAmount, _feeAmount) = _instantRedeem(_share, _shares, msg.sender, _receiver, _vault);
    }

    /// @inheritdoc IComplianceProxy
    function instantRedeemWithPermit2(
        uint256 _shares,
        address _receiver,
        NestVault _vault,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _signature,
        bytes calldata _complianceData
    ) external override requiresAuth nonReentrant whenNotPaused returns (uint256 _postFeeAmount, uint256 _feeAmount) {
        _checkCompliance(msg.sender, abi.encodeWithSignature("instantRedeem()"), _complianceData);

        ERC20 _share = ERC20(_vault.share());
        _permit2TransferFrom(_share, _shares, _vault.PERMIT2(), _nonce, _deadline, _signature);
        (_postFeeAmount, _feeAmount) = _instantRedeem(_share, _shares, msg.sender, _receiver, _vault);
    }

    /*//////////////////////////////////////////////////////////////
                            USER CHECK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IComplianceProxy
    /// @dev Executes no transfer; restricted because successful checks consume their attestation.
    function genericUserCheck(address _user, bytes calldata _complianceData)
        external
        override
        requiresAuth
        returns (bool)
    {
        return complianceHook.checkCompliance(
            _user, abi.encodeWithSignature("accessCheck(address)", _user), _complianceData
        );
    }

    /// @inheritdoc IComplianceProxy
    /// @dev Executes no transfer; checks an attestation for the explicit caller/user pair.
    function genericUserCheck(address _caller, bytes32 _user, bytes calldata _complianceData)
        external
        override
        requiresAuth
        returns (bool)
    {
        return complianceHook.checkCompliance(
            _caller, abi.encodeWithSignature("accessCheck(bytes32)", _user), _complianceData
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IComplianceProxy
    /// @dev Swapping the hook is how the proxy migrates compliance providers without a redeploy.
    function setComplianceHook(IComplianceHook _complianceHook) external override requiresAuth {
        if (address(_complianceHook) == address(0)) revert ComplianceProxy__ZeroAddress();
        emit ComplianceHookUpdated(address(complianceHook), address(_complianceHook));
        complianceHook = _complianceHook;
    }

    /// @notice Pauses all user entrypoints. Access-controlled.
    function pause() public requiresAuth {
        _pause();
    }

    /// @notice Unpauses all user entrypoints. Access-controlled.
    function unpause() public requiresAuth {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Reverts unless the compliance hook authorizes `_sender` for `_payload`.
    function _checkCompliance(address _sender, bytes memory _payload, bytes calldata _complianceData) internal {
        if (!complianceHook.checkCompliance(_sender, _payload, _complianceData)) {
            revert ComplianceProxy__UnauthorizedTransaction();
        }
    }

    /// @dev Deposits assets already acquired by the proxy and returns the shares minted by the vault.
    function _deposit(ERC20 _depositAsset, uint256 _assets, address _receiver, NestVault _vault)
        internal
        returns (uint256 _shares)
    {
        _depositAsset.safeApprove(address(_vault), _assets);
        _shares = _vault.deposit(_assets, _receiver);
        _depositAsset.safeApprove(address(_vault), 0);

        emit Deposit(_receiver, address(_depositAsset), _assets, _shares, block.timestamp, address(_vault));
    }

    /// @dev Approves shares already held by the proxy for one vault call. The proxy is the vault-level
    ///      owner, while the public event emitted by the caller preserves the original owner.
    function _requestRedeem(ERC20 _share, uint256 _shares, address _owner, address _controller, NestVault _vault)
        internal
        returns (uint256 _requestId)
    {
        _share.safeApprove(address(_vault), _shares);
        _requestId = _vault.requestRedeem(_shares, _controller, address(this));
        _share.safeApprove(address(_vault), 0);

        emit RedeemRequest(_owner, _controller, _shares, _requestId, block.timestamp, address(_vault));
    }

    /// @dev Approves shares already held by the proxy for one vault call and sends redeemed assets
    ///      directly from the vault to `_receiver`.
    function _instantRedeem(ERC20 _share, uint256 _shares, address _owner, address _receiver, NestVault _vault)
        internal
        returns (uint256 _postFeeAmount, uint256 _feeAmount)
    {
        _share.safeApprove(address(_vault), _shares);
        (_postFeeAmount, _feeAmount) = _vault.instantRedeem(_shares, _receiver, address(this));
        _share.safeApprove(address(_vault), 0);

        emit InstantRedeem(_owner, _receiver, _shares, _postFeeAmount, _feeAmount, block.timestamp, address(_vault));
    }

    /// @dev Pulls `_amount` of `_token` from msg.sender using Permit2 and verifies the full amount arrived.
    function _permit2TransferFrom(
        ERC20 _token,
        uint256 _amount,
        ISignatureTransfer _permit2,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _signature
    ) internal {
        uint256 _balanceBefore = _token.balanceOf(address(this));

        _permit2.permitTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: address(_token), amount: _amount}),
                nonce: _nonce,
                deadline: _deadline
            }),
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _amount}),
            msg.sender,
            _signature
        );

        if (_token.balanceOf(address(this)) - _balanceBefore < _amount) {
            revert ComplianceProxy__InsufficientPermit2Transfer();
        }
    }
}
