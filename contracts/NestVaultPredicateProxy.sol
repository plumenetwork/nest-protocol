// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// contracts
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {PredicateClient} from "@predicate/src/mixins/PredicateClient.sol";
import {AuthUpgradeable, Authority} from "contracts/upgradeable/auth/AuthUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {NestVault} from "contracts/NestVault.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    ReentrancyGuardTransientUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

// libraries
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

// types
import {Errors} from "contracts/types/Errors.sol";
import {IPredicateClient, PredicateMessage} from "@predicate/src/interfaces/IPredicateClient.sol";

/// @title  NestVaultPredicateProxy
/// @author plumenetwork
/// @notice Proxy contract allowing users to deposit into the NestShare with authorization via predicates
/// @dev    This contract is upgradeable and uses various mixins for access control, pausing functionality, and reentrancy protection
contract NestVaultPredicateProxy is
    Initializable,
    AuthUpgradeable,
    ReentrancyGuardTransientUpgradeable,
    PredicateClient,
    PausableUpgradeable
{
    using SafeTransferLib for ERC20;

    /// @dev   Emitted when a deposit is made
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

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the specified owner and service manager
    /// @param _owner          address The address to be set as the contract owner
    /// @param _serviceManager address The address of the service manager to manage predicates
    /// @param _policyID       string  The policy ID to be used for authorization
    function initialize(address _owner, address _serviceManager, string memory _policyID) external initializer {
        __Auth_init(_owner, Authority(address(0)));
        _initPredicateClient(_serviceManager, _policyID);
    }

    // ========================================= USER FUNCTIONS =========================================

    /// @notice Allows users to deposit into the NestVault, if PredicateProxy is not paused
    /// @dev    Publicly callable. Uses the predicate authorization pattern to validate the transaction
    /// @param  _depositAsset     ERC20            asset to deposit
    /// @param  _depositAmount    uint256          amount of deposit asset to deposit
    /// @param  _recipient        address          address which to forward shares
    /// @param  _vault            NestVault        contract to deposit into
    /// @param  _predicateMessage PredicateMessage Predicate message to authorize the transaction
    /// @return _shares           uint256          amount of shares minted
    function deposit(
        ERC20 _depositAsset,
        uint256 _depositAmount,
        address _recipient,
        NestVault _vault,
        PredicateMessage calldata _predicateMessage
    ) external nonReentrant whenNotPaused returns (uint256 _shares) {
        // @dev This payload is only hashed by _authorizeTransaction to match the predicate policy.
        // No call is made with it. The policy whitelists the canonical "deposit()" entrypoint, and
        // the real deposit logic executes below after authorization succeeds.
        bytes memory _encodedSigAndArgs = abi.encodeWithSignature("deposit()");
        if (!_authorizeTransaction(_predicateMessage, _encodedSigAndArgs, msg.sender, 0)) {
            revert Errors.NestPredicateProxy__PredicateUnauthorizedTransaction();
        }
        //approve vault to take assets from proxy
        _depositAsset.safeApprove(address(_vault), _depositAmount);
        //transfer deposit assets from sender to this contract
        _depositAsset.safeTransferFrom(msg.sender, address(this), _depositAmount);
        // mint shares
        _shares = _vault.deposit(_depositAmount, _recipient);
        emit Deposit(_recipient, address(_depositAsset), _depositAmount, _shares, block.timestamp, address(_vault));
    }

    /// @notice Allows whitelisted users to deposit into the NestVault, if PredicateProxy is not paused.
    /// @dev    Restricted to COMPOSER_ROLE. Allows specifying a _depositor (bytes32) different from msg.sender,
    ///         enabling custom predicate verifications for cross-chain deposit integrations.
    /// @dev    Uses the predicate authorization pattern to validate the transaction
    /// @param  _depositAsset     ERC20            asset to deposit
    /// @param  _depositAmount    uint256          amount of deposit asset to deposit
    /// @param  _recipient        address          address which to forward shares
    /// @param  _vault            NestVault        contract to deposit into
    /// @param  _depositor        bytes32          The depositor (bytes32 format to account for non-evm addresses)
    /// @param  _predicateMessage PredicateMessage Predicate message to authorize the transaction
    /// @return _shares           uint256          amount of shares minted
    function deposit(
        ERC20 _depositAsset,
        uint256 _depositAmount,
        address _recipient,
        NestVault _vault,
        bytes32 _depositor, // added to verify the original sender address
        PredicateMessage calldata _predicateMessage
    ) external requiresAuth nonReentrant whenNotPaused returns (uint256 _shares) {
        //@dev This is NOT the actual function that is called, it is the against which the predicate is authorized
        bytes memory _encodedSigAndArgs = abi.encodeWithSignature("deposit(string)", toHexString(_depositor));
        if (!_authorizeTransaction(_predicateMessage, _encodedSigAndArgs, msg.sender, 0)) {
            revert Errors.NestPredicateProxy__PredicateUnauthorizedTransaction();
        }
        //approve vault to take assets from proxy
        _depositAsset.safeApprove(address(_vault), _depositAmount);
        //transfer deposit assets from sender to this contract
        _depositAsset.safeTransferFrom(msg.sender, address(this), _depositAmount);
        // mint shares
        _shares = _vault.deposit(_depositAmount, _recipient);
        emit Deposit(_recipient, address(_depositAsset), _depositAmount, _shares, block.timestamp, address(_vault));
    }

    /// @notice Allows users to mint, if the PredicateProxy contract is not paused
    /// @dev    Publicly callable. Uses the predicate authorization pattern to validate the transaction
    /// @param  _depositAsset     ERC20            asset to deposit
    /// @param  _shares           uint256          amount of shares to mint
    /// @param  _recipient        address          address which to forward shares
    /// @param  _vault            NestVault        contract to deposit into
    /// @param  _predicateMessage PredicateMessage Predicate message to authorize the transaction
    /// @return _depositAmount    uint256          amount of asset deposited
    function mint(
        ERC20 _depositAsset,
        uint256 _shares,
        address _recipient,
        NestVault _vault,
        PredicateMessage calldata _predicateMessage
    ) external nonReentrant whenNotPaused returns (uint256 _depositAmount) {
        // @dev This payload is only hashed by _authorizeTransaction to match the predicate policy.
        // No call is made with it. The policy whitelists the canonical "deposit()" entrypoint, and
        // the real deposit logic executes below after authorization succeeds.
        bytes memory _encodedSigAndArgs = abi.encodeWithSignature("deposit()");
        if (!_authorizeTransaction(_predicateMessage, _encodedSigAndArgs, msg.sender, 0)) {
            revert Errors.NestPredicateProxy__PredicateUnauthorizedTransaction();
        }
        // calculate assets to deposit for minting `_shares`
        uint256 _requiredDepositAmount = _vault.previewMint(_shares);
        //approve vault to take assets from proxy
        _depositAsset.safeApprove(address(_vault), _requiredDepositAmount);
        //transfer deposit assets from sender to this contract
        _depositAsset.safeTransferFrom(msg.sender, address(this), _requiredDepositAmount);
        // mint shares
        _depositAmount = _vault.mint(_shares, _recipient);
        // reset allowance
        _depositAsset.safeApprove(address(_vault), 0);
        emit Deposit(_recipient, address(_depositAsset), _depositAmount, _shares, block.timestamp, address(_vault));
    }

    /// @notice Allows whitelisted users to mint into the NestVault, if PredicateProxy is not paused.
    /// @dev    Restricted to COMPOSER_ROLE. Allows specifying a _depositor (bytes32) different from msg.sender,
    ///         enabling custom predicate verifications for cross-chain mint integrations.
    /// @dev    Uses the predicate authorization pattern to validate the transaction
    /// @param  _depositAsset     ERC20            asset to deposit
    /// @param  _shares           uint256          amount of shares to mint
    /// @param  _recipient        address          address which to forward shares
    /// @param  _vault            NestVault        contract to deposit into
    /// @param  _depositor        bytes32          The depositor (bytes32 format to account for non-evm addresses)
    /// @param  _predicateMessage PredicateMessage Predicate message to authorize the transaction
    /// @return _depositAmount    uint256          amount of asset deposited
    function mint(
        ERC20 _depositAsset,
        uint256 _shares,
        address _recipient,
        NestVault _vault,
        bytes32 _depositor,
        PredicateMessage calldata _predicateMessage
    ) external requiresAuth nonReentrant whenNotPaused returns (uint256 _depositAmount) {
        //@dev This is NOT the actual function that is called, it is the against which the predicate is authorized
        bytes memory _encodedSigAndArgs = abi.encodeWithSignature("deposit(string)", toHexString(_depositor));
        if (!_authorizeTransaction(_predicateMessage, _encodedSigAndArgs, msg.sender, 0)) {
            revert Errors.NestPredicateProxy__PredicateUnauthorizedTransaction();
        }
        // calculate assets to deposit for minting `_shares`
        uint256 _requiredDepositAmount = _vault.previewMint(_shares);
        //approve vault to take assets from proxy
        _depositAsset.safeApprove(address(_vault), _requiredDepositAmount);
        //transfer deposit assets from sender to this contract
        _depositAsset.safeTransferFrom(msg.sender, address(this), _requiredDepositAmount);
        // mint shares
        _depositAmount = _vault.mint(_shares, _recipient);
        // reset allowance
        _depositAsset.safeApprove(address(_vault), 0);
        emit Deposit(_recipient, address(_depositAsset), _depositAmount, _shares, block.timestamp, address(_vault));
    }

    /// @notice Function to check if the user is authorized to call the predicate
    /// @dev    This is NOT an actual function that is called, it serves as a function to allow any contract to check a user
    ///         against the predicate
    /// @param  _user             address          address of the user
    /// @param  _predicateMessage PredicateMessage Predicate message to authorize the transaction
    /// @return                   bool             returns `true` is user is authorized to call predicate
    function genericUserCheckPredicate(address _user, PredicateMessage calldata _predicateMessage)
        external
        returns (bool)
    {
        //@dev This is NOT an actual function that is called, it is the against which the predicate is authorized
        bytes memory encodedSigAndArgs = abi.encodeWithSignature("accessCheck(address)", _user);
        //still use 0 for msg.value since we only need validation against sender and user address
        return _authorizeTransaction(_predicateMessage, encodedSigAndArgs, _user, 0);
    }

    /// @notice Function to check if the user is authorized to call the predicate
    /// @dev    This is NOT an actual function that is called, it serves as a function to allow any contract to check a user
    ///         against the predicate
    /// @param  _user             string           string representation of the user (for non-EVM addresses)
    /// @param  _predicateMessage PredicateMessage Predicate message to authorize the transaction
    /// @return                   bool             returns `true` is user is authorized to call predicate
    function genericUserCheckPredicate(string memory _user, PredicateMessage calldata _predicateMessage)
        external
        returns (bool)
    {
        //@dev This is NOT an actual function that is called, it is the against which the predicate is authorized
        bytes memory encodedSigAndArgs = abi.encodeWithSignature("accessCheck(string)", _user);
        //still use 0 for msg.value since we only need validation against sender and user address
        return _authorizeTransaction(_predicateMessage, encodedSigAndArgs, msg.sender, 0);
    }

    /// @inheritdoc IPredicateClient
    function setPolicy(string memory _policyID) external override requiresAuth {
        _setPolicy(_policyID);
    }

    /// @notice Function for setting the ServiceManager
    /// @dev    Only the owner can update the predicate manager
    /// @param  _predicateManager address address of the service manager
    function setPredicateManager(address _predicateManager) public requiresAuth {
        _setPredicateManager(_predicateManager);
    }

    /// @notice Pauses the contract, disabling certain functionalities.
    ///         Can only be called by the owner of the contract.
    /// @dev    This function calls the internal `_pause` function to halt contract operations.
    ///         It ensures that only the owner can trigger this action.
    function pause() public requiresAuth {
        _pause();
    }

    /// @notice Unpauses the contract, re-enabling functionalities.
    ///         Can only be called by the owner of the contract.
    /// @dev    This function calls the internal `_unpause` function to resume contract operations.
    ///         It ensures that only the owner can trigger this action.
    function unpause() public requiresAuth {
        _unpause();
    }

    /// @notice Converts a bytes32 value to its hexadecimal string representation
    /// @dev used to convert bytes32 depositor to string for predicate verification
    /// @param data The bytes32 value to convert
    /// @return The hexadecimal string representation of the bytes32 value
    function toHexString(bytes32 data) internal pure returns (string memory) {
        bytes16 HEX_DIGITS2 = "0123456789abcdef";
        uint256 localValue = uint256(data);
        bytes memory buffer = new bytes(66);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 65; i > 1; --i) {
            buffer[i] = HEX_DIGITS2[localValue & 0xf];
            localValue >>= 4;
        }

        return string(buffer);
    }
}
