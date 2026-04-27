// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// contracts
import {Auth, Authority} from "@solmate/auth/Auth.sol";

// interfaces
import {ITransferHook} from "contracts/interfaces/ITransferHook.sol";

/// @title  BlacklistHook
/// @author plumenetwork
/// @notice Before-transfer hook that can pause transfers and block blacklisted senders.
/// @dev    Implements ITransferHook and only enforces checks against `from`.
contract BlacklistHook is Auth, ITransferHook {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Error thrown when transfers are paused.
    error BlacklistHook__Paused();

    /// @dev Error thrown when a blacklisted address attempts to transfer.
    /// @param account address The blacklisted sender.
    error BlacklistHook__Blacklisted(address account);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the hook is paused.
    event Paused();

    /// @notice Emitted when the hook is unpaused.
    event Unpaused();

    /// @notice Emitted when a blacklist entry is updated.
    /// @param account       address The account whose status was updated.
    /// @param isBlacklisted bool    Whether the account is blacklisted.
    event BlacklistUpdated(address indexed account, bool isBlacklisted);

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice True when transfers are paused.
    bool public isPaused;

    /// @notice Tracks blacklisted addresses.
    mapping(address => bool) public isBlacklisted;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the hook with an owner and authority.
    /// @param _owner     address   The owner address for auth.
    /// @param _authority Authority The authority contract for role checks.
    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {}

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause transfers enforced by this hook.
    /// @dev    Callable by authorized roles.
    function pause() external requiresAuth {
        isPaused = true;
        emit Paused();
    }

    /// @notice Unpause transfers enforced by this hook.
    /// @dev    Callable by authorized roles.
    function unpause() external requiresAuth {
        isPaused = false;
        emit Unpaused();
    }

    /// @notice Update blacklist status for an account.
    /// @dev    Callable by authorized roles.
    /// @param  _account       address The account to update.
    /// @param  _isBlacklisted bool    Whether the account is blacklisted.
    function setBlacklisted(address _account, bool _isBlacklisted) external requiresAuth {
        isBlacklisted[_account] = _isBlacklisted;
        emit BlacklistUpdated(_account, _isBlacklisted);
    }

    /*//////////////////////////////////////////////////////////////
                        BEFORE TRANSFER HOOK
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks the sender against pause state and blacklist.
    /// @param  from address The address sending shares.
    function beforeTransfer(address from) public view {
        if (isPaused) {
            revert BlacklistHook__Paused();
        }
        if (isBlacklisted[from]) {
            revert BlacklistHook__Blacklisted(from);
        }
    }
}
