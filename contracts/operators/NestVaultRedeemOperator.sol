// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// contracts
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    ReentrancyGuardTransientUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

// interfaces
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";

// types
import {Errors} from "contracts/types/Errors.sol";

/// @title  NestVaultRedeemOperator
/// @author plumenetwork
/// @notice Permissioned operator that fulfills and redeems on behalf of controllers.
/// @dev    Controllers can set a preferred receiver per vault; otherwise redemptions default to the controller.
contract NestVaultRedeemOperator is Initializable, AuthUpgradeable, ReentrancyGuardTransientUpgradeable {
    struct RedeemRequest {
        INestVaultCore vault;
        address controller;
        uint256 shares;
    }

    struct NestVaultRedeemOperatorStorage {
        mapping(address vault => mapping(address controller => address receiver)) receiver;
    }

    // keccak256(abi.encode(uint256(keccak256("plumenetwork.storage.nestvaultredeemoperator")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NestVaultRedeemOperatorStorageLocation =
        0xc6de488efe39134e6ba080600240582250f24fd278baeceaf63a2ef56d0a0700;

    /// @notice Emitted when a controller sets or clears their receiver.
    /// @param vault      The vault the receiver is set for.
    /// @param controller The controller setting the receiver.
    /// @param receiver   The receiver address (zero clears and defaults to controller).
    event ReceiverSet(address indexed vault, address indexed controller, address indexed receiver);

    constructor() {
        _disableInitializers();
    }

    /// @notice Returns the storage struct.
    function _getNestVaultRedeemOperatorStorage() private pure returns (NestVaultRedeemOperatorStorage storage $) {
        assembly {
            $.slot := NestVaultRedeemOperatorStorageLocation
        }
    }

    /// @notice Initializes the operator with the given owner.
    /// @param _owner   address     Owner for Auth initialization.
    function initialize(address _owner) external initializer {
        if (_owner == address(0)) revert Errors.ZeroAddress();
        __Auth_init(_owner, Authority(address(0)));
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets a custom receiver for the caller on a specific vault.
    /// @dev    Setting receiver to address(0) clears and defaults to controller.
    /// @param _vault    address    The vault to set the receiver for.
    /// @param _receiver address    The receiver address (zero clears and defaults to controller).
    function setReceiver(address _vault, address _receiver) external {
        _validateAddresses(_vault, msg.sender);
        _setReceiver(_vault, msg.sender, _receiver);
    }

    /// @notice Redeems claimable shares for a controller and sends assets to their configured receiver.
    /// @dev    Permissioned; requires the keeper role via RolesAuthority.
    /// @param _request     RedeemRequest Redeem request to process.
    function redeem(RedeemRequest memory _request) external requiresAuth nonReentrant returns (uint256 _assets) {
        _validateRedeemRequest(_request);
        _assets = _redeem(_request);
    }

    /// @notice Fulfills and redeems in a single call.
    /// @dev    Permissioned; requires the keeper role via RolesAuthority.
    /// @param _request     RedeemRequest Redeem request to process.
    function fulfillAndRedeem(RedeemRequest memory _request)
        external
        requiresAuth
        nonReentrant
        returns (uint256 _assets)
    {
        _validateRedeemRequest(_request);
        _fulfillRedeem(_request);
        _assets = _redeem(_request);
    }

    /// @notice Redeems all claimable shares for a controller.
    /// @dev    Permissioned; requires the keeper role via RolesAuthority.
    /// @param _vault      INestVaultCore   The vault to redeem from.
    /// @param _controller address          The controller whose shares are being redeemed.
    function redeemAll(INestVaultCore _vault, address _controller)
        external
        requiresAuth
        nonReentrant
        returns (uint256 _assets)
    {
        _validateAddresses(address(_vault), _controller);
        uint256 _shares = _vault.claimableRedeemRequest(0, _controller);
        if (_shares == 0) revert Errors.ZeroShares();
        RedeemRequest memory _request = RedeemRequest({vault: _vault, controller: _controller, shares: _shares});
        _assets = _redeem(_request);
    }

    /// @notice Fulfills and redeems all pending shares for a controller.
    /// @dev    Permissioned; requires the keeper role via RolesAuthority.
    /// @param _vault      INestVaultCore   The vault to redeem from.
    /// @param _controller address          The controller whose shares are being redeemed.
    function fulfillAndRedeemAll(INestVaultCore _vault, address _controller)
        external
        requiresAuth
        nonReentrant
        returns (uint256 _assets)
    {
        _validateAddresses(address(_vault), _controller);
        uint256 _shares = _vault.pendingRedeemRequest(0, _controller);
        if (_shares == 0) revert Errors.ZeroShares();
        RedeemRequest memory _request = RedeemRequest({vault: _vault, controller: _controller, shares: _shares});
        _fulfillRedeem(_request);
        _assets = _redeem(_request);
    }

    /// @notice Redeems claimable shares for multiple controllers.
    /// @dev    Permissioned; requires the keeper role via RolesAuthority.
    /// @param _requests RedeemRequest[] Redeem requests to process.
    function batchRedeem(RedeemRequest[] calldata _requests)
        external
        requiresAuth
        nonReentrant
        returns (uint256[] memory _assets)
    {
        uint256 _len = _requests.length;
        _assets = new uint256[](_len);
        for (uint256 i; i < _len;) {
            _validateRedeemRequest(_requests[i]);
            _assets[i] = _redeem(_requests[i]);
            unchecked {
                i++;
            }
        }
    }

    /// @notice Fulfills and redeems multiple requests in a single call.
    /// @dev    Permissioned; requires the keeper role via RolesAuthority.
    /// @param _requests Redeem requests to process.
    function batchFulfillAndRedeem(RedeemRequest[] calldata _requests)
        external
        requiresAuth
        nonReentrant
        returns (uint256[] memory _assets)
    {
        uint256 _len = _requests.length;
        _assets = new uint256[](_len);
        for (uint256 i; i < _len;) {
            _validateRedeemRequest(_requests[i]);
            _fulfillRedeem(_requests[i]);
            _assets[i] = _redeem(_requests[i]);
            unchecked {
                i++;
            }
        }
    }

    /// @notice Uses an EIP-712 signature to authorize this operator for a controller.
    /// @dev    Permissioned; keeper submits the signed authorization.
    /// @param _vault      INestVaultCore   The vault to authorize the operator for.
    /// @param _controller address          The controller authorizing the operator.
    /// @param _approved   bool             Whether the operator is approved.
    /// @param _nonce      bytes32          The nonce for the signature.
    /// @param _deadline   uint256          The deadline for the signature.
    /// @param _signature  bytes            The EIP-712 signature.
    function authorizeAsOperator(
        INestVaultCore _vault,
        address _controller,
        bool _approved,
        bytes32 _nonce,
        uint256 _deadline,
        bytes calldata _signature
    ) external requiresAuth returns (bool _success) {
        _validateAddresses(address(_vault), _controller);
        return _vault.authorizeOperator(_controller, address(this), _approved, _nonce, _deadline, _signature);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns redemption status for a controller on a vault.
    /// @param  _vault          INestVaultCore The vault to query.
    /// @param  _controller     address        The controller to check.
    /// @return _pending         uint256        Shares waiting to be fulfilled by keeper.
    /// @return _claimable       uint256        Shares ready to be redeemed.
    /// @return _receiver        address        Address that will receive redeemed assets.
    /// @return _isAuthorized    bool           Whether this operator is authorized for the controller.
    function getRedemptionStatus(INestVaultCore _vault, address _controller)
        external
        view
        returns (uint256 _pending, uint256 _claimable, address _receiver, bool _isAuthorized)
    {
        _pending = _vault.pendingRedeemRequest(0, _controller);
        _claimable = _vault.claimableRedeemRequest(0, _controller);
        _receiver = _getReceiver(address(_vault), _controller);
        _isAuthorized = _vault.isOperator(_controller, address(this));
    }

    /// @notice Returns the receiver for a controller, defaulting to the controller when unset.
    /// @param _vault      address    The vault to get the receiver for.
    /// @param _controller address    The controller to get the receiver for.
    function getReceiver(address _vault, address _controller) external view returns (address _receiver) {
        return _getReceiver(_vault, _controller);
    }

    /// @notice Returns the receivers for a list of vaults for a specific controller.
    /// @param _vaults     address[]      The vaults to get the receivers for.
    /// @param _controller address        The controller to get the receivers for.
    function getReceivers(address[] calldata _vaults, address _controller)
        external
        view
        returns (address[] memory _receivers)
    {
        _receivers = new address[](_vaults.length);
        uint256 _len = _vaults.length;
        for (uint256 i; i < _len;) {
            _receivers[i] = _getReceiver(_vaults[i], _controller);
            unchecked {
                i++;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the receiver for a controller on a specific vault.
    /// @dev    Internal function without address validation.
    /// @param _vault      address    The vault to set the receiver for.
    /// @param _controller address    The controller setting the receiver.
    /// @param _receiver   address    The receiver address (zero clears and defaults to controller).
    function _setReceiver(address _vault, address _controller, address _receiver) internal {
        _getNestVaultRedeemOperatorStorage().receiver[_vault][_controller] = _receiver;
        emit ReceiverSet(_vault, _controller, _receiver);
    }

    /// @notice Returns the receiver for a controller, defaulting to the controller when unset.
    /// @param _vault      address    The vault to get the receiver for.
    /// @param _controller address    The controller to get the receiver for.
    function _getReceiver(address _vault, address _controller) internal view returns (address _receiver) {
        _receiver = _getNestVaultRedeemOperatorStorage().receiver[_vault][_controller];
        if (_receiver == address(0)) _receiver = _controller;
    }

    /// @notice Validates that the given addresses are non-zero.
    /// @param _vault       address The vault address to validate.
    /// @param _controller  address The controller address to validate.
    function _validateAddresses(address _vault, address _controller) internal pure {
        if (_vault == address(0) || _controller == address(0)) {
            revert Errors.ZeroAddress();
        }
    }

    /// @notice Validates the addresses in a redeem request.
    /// @param _request Redeem request to validate.
    function _validateRedeemRequest(RedeemRequest memory _request) internal pure {
        _validateAddresses(address(_request.vault), _request.controller);
    }

    /// @notice Fulfills shares for a valid request.
    /// @param _request Redeem request to process.
    function _fulfillRedeem(RedeemRequest memory _request) internal returns (uint256 _assets) {
        if (_request.shares == 0) return 0;

        uint256 _pending = _request.vault.pendingRedeemRequest(0, _request.controller);
        uint256 _sharesToFulfill = _request.shares;
        if (_sharesToFulfill > _pending) {
            uint256 _claimable = _request.vault.claimableRedeemRequest(0, _request.controller);
            if (_sharesToFulfill - _pending > _claimable) revert Errors.InsufficientClaimable();
            _sharesToFulfill = _pending;
        }

        if (_sharesToFulfill == 0) return 0;
        _assets = _request.vault.fulfillRedeem(_request.controller, _sharesToFulfill);
    }

    /// @notice Redeems shares without validating the request.
    /// @param _request Redeem request to process.
    function _redeem(RedeemRequest memory _request) internal returns (uint256 _assets) {
        address _receiver = _getReceiver(address(_request.vault), _request.controller);
        uint256 _maxShares = _request.vault.maxRedeem(_request.controller);
        if (_request.shares > _maxShares) revert Errors.InsufficientClaimable();
        if (_request.shares == 0) return 0;
        _assets = _request.vault.redeem(_request.shares, _receiver, _request.controller);
    }
}
