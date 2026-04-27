// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

// contracts
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Authority} from "@solmate/auth/Auth.sol";

/// @title AuthUpgradeable Contract
/// @notice This contract provides a flexible and updatable authentication pattern
///         that is entirely separate from the application logic. The original
///         implementation has been modified to support upgradeable proxies,
///         using OpenZeppelin's Initializable contract for initialization.
///
/// @dev This contract is an upgradeable version of the `Auth` contract from Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/Auth.sol).
///      It has been modified to include the `Initializable` and `ContextUpgradeable` contracts from OpenZeppelin to support the use of upgradeable proxies.
///      This ensures that the contract logic can be updated in the future while maintaining its state and existing data.
///      The contract is designed to be used in proxy-based patterns (such as UUPS or Transparent proxies).
///      Ensure that the initialization is done properly in the proxy's constructor to avoid any issues.
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/Auth.sol)
/// @author Further modified by plumenetwork to support upgradeable proxies
abstract contract AuthUpgradeable is Initializable, ContextUpgradeable {
    /// @notice Emitted when ownership is transferred to a new address
    /// @param previousOwner The address of the current owner before the transfer
    /// @param newOwner The address of the new owner.
    event AUTH_OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when the authority is updated
    /// @param user address of the user updating the authority
    /// @param newAuthority address of the new authority
    event AUTH_AuthorityUpdated(address indexed user, Authority indexed newAuthority);

    /// @notice Emitted when ownership transfer is started
    /// @param previousOwner The address of current owner
    /// @param newOwner The address of new owner
    event AUTH_OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /// @dev The caller account is not authorized to perform an operation
    error AUTH_UNAUTHORIZED();

    /// @dev The address(0) is not allowed
    error AUTH_ZERO_ADDRESS();

    /// @dev This struct stores the current owner's address and the contract's authority
    /// @param _owner The address of the current contract owner
    /// @param _authority The address of the current authority
    /// @param _pendingOwner The address of the pending owner
    /// @custom:storage-location erc7201:plumenetwork.storage.Auth
    struct AuthStorage {
        address _owner;
        Authority _authority;
        address _pendingOwner;
    }

    // keccak256(abi.encode(uint256(keccak256("plumenetwork.storage.Auth")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AuthStorageLocation = 0x341f7c713c76cb881fd7047f7cccebe3fe10eddfc5e20fe83ee7e0b505e8ea00;

    /// @dev Internal function to access the contract's AuthStorage slot
    /// @return $ A reference to the AuthStorage struct for reading/writing authentication data
    function _getAuthStorage() private pure returns (AuthStorage storage $) {
        assembly {
            $.slot := AuthStorageLocation
        }
    }

    /// @notice Initializes the contract with the owner's address and the authority
    /// @param _owner The address to set as the owner of the contract
    /// @param _authority The address of the initial authority responsible for managing permissions
    function __Auth_init(address _owner, Authority _authority) internal onlyInitializing {
        __Auth_init_unchained(_owner, _authority);
    }

    /// @dev Internal function to initialize the contract's state
    /// @param _owner The address to set as the owner of the contract
    /// @param _authority The address of the initial authority
    function __Auth_init_unchained(address _owner, Authority _authority) internal onlyInitializing {
        AuthStorage storage $ = _getAuthStorage();
        $._owner = _owner;
        emit AUTH_OwnershipTransferred(address(0), _owner);
        $._authority = _authority;
        emit AUTH_AuthorityUpdated(_msgSender(), _authority);
    }

    /// @notice Modifier that ensures the caller is authorized to perform the action
    /// @dev This modifier checks whether the caller is authorized based on the current
    ///      authority or is the owner of the contract
    modifier requiresAuth() virtual {
        _checkAuth();
        _;
    }

    /// @dev Internal function to check authorization
    /// @dev Reverts with UNAUTHORIZED if msg.sender is not authorized for msg.sig
    function _checkAuth() internal view virtual {
        if (!isAuthorized(_msgSender(), msg.sig)) {
            revert AUTH_UNAUTHORIZED();
        }
    }

    /// @notice Retrieves the current owner of the contract
    /// @return The address of the current owner
    function owner() public view virtual returns (address) {
        AuthStorage storage $ = _getAuthStorage();
        return $._owner;
    }

    /// @notice Retrieves the current authority of the contract
    /// @return The address of the current authority
    function authority() public view virtual returns (Authority) {
        AuthStorage storage $ = _getAuthStorage();
        return $._authority;
    }

    /// @notice Checks if a user is authorized to call a specific function in the contract
    /// @param user The address of the user requesting access
    /// @param functionSig The signature of the function being called
    /// @return A boolean indicating whether the user is authorized
    function isAuthorized(address user, bytes4 functionSig) internal view virtual returns (bool) {
        Authority auth = authority(); // Memoizing authority saves us a warm SLOAD, around 100 gas.

        // Checking if the caller is the owner only after calling the authority saves gas in most cases, but be
        // aware that this makes protected functions uncallable even to the owner if the authority is out of order.
        return (address(auth) != address(0) && auth.canCall(user, address(this), functionSig)) || user == owner();
    }

    /// @notice Allows the owner to set a new authority for the contract
    /// @param newAuthority The address of the new authority
    function setAuthority(Authority newAuthority) public virtual {
        AuthStorage storage $ = _getAuthStorage();
        // We check if the caller is the owner first because we want to ensure they can
        // always swap out the authority even if it's reverting or using up a lot of gas.
        require(_msgSender() == owner() || $._authority.canCall(_msgSender(), address(this), msg.sig));

        $._authority = newAuthority;

        emit AUTH_AuthorityUpdated(_msgSender(), newAuthority);
    }

    /// @notice Initiates ownership transfer to a new address (step 1 of 2)
    /// @param newOwner The address of the proposed new owner
    function transferOwnership(address newOwner) public virtual requiresAuth {
        if (newOwner == address(0)) revert AUTH_ZERO_ADDRESS();

        AuthStorage storage $ = _getAuthStorage();
        $._pendingOwner = newOwner;

        emit AUTH_OwnershipTransferStarted(_msgSender(), newOwner);
    }

    /// @notice Accepts ownership transfer (step 2 of 2)
    /// @dev Must be called by the pending owner to complete the transfer
    function acceptOwnership() public virtual {
        AuthStorage storage $ = _getAuthStorage();

        if (_msgSender() != $._pendingOwner) revert AUTH_UNAUTHORIZED();

        address oldOwner = $._owner;
        $._owner = $._pendingOwner;
        $._pendingOwner = address(0);

        emit AUTH_OwnershipTransferred(oldOwner, $._owner);
    }

    /// @notice Returns the pending owner address
    /// @return The address of the pending owner (if any)
    function pendingOwner() public view virtual returns (address) {
        AuthStorage storage $ = _getAuthStorage();
        return $._pendingOwner;
    }
}
