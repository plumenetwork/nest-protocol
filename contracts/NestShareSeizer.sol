// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// contracts
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";

// hooks
import {BlacklistHook} from "contracts/hooks/BlacklistHook.sol";

// interfaces
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";

/// @title  NestShareSeizer
/// @author plumenetwork
/// @notice Seizes shares or redeems assets from a user and enforces blacklisting.
/// @dev    Uses NestShareOFT `enter`/`exit` to move shares without allowances.
contract NestShareSeizer is Auth {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Error thrown when a required address is zero.
    error NestShareSeizer__ZeroAddress();

    /// @dev Error thrown when a share amount is zero.
    error NestShareSeizer__ZeroShares();

    /// @dev Error thrown when an asset amount is zero.
    error NestShareSeizer__ZeroAssets();

    /// @dev Error thrown when the share transfer hook is not set.
    error NestShareSeizer__HookNotSet();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when shares are seized and transferred.
    /// @param share  address The share token seized.
    /// @param from   address The account whose shares are seized.
    /// @param to     address The recipient of the seized shares.
    /// @param shares uint256 The amount of shares seized.
    event SharesSeized(address indexed share, address indexed from, address indexed to, uint256 shares);

    /// @notice Emitted when shares are seized and redeemed for assets.
    /// @param share  address The share token seized.
    /// @param from   address The account whose shares are seized.
    /// @param to     address The recipient of the redeemed assets.
    /// @param asset  address The asset transferred out.
    /// @param shares uint256 The amount of shares seized.
    /// @param assets uint256 The amount of assets transferred.
    event SharesSeizedAndRedeemed(
        address indexed share, address indexed from, address indexed to, address asset, uint256 shares, uint256 assets
    );

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the seizer.
    /// @param _owner         address       The owner address for auth.
    /// @param _authority     Authority     The authority contract for role checks.
    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {
        if (_owner == address(0)) {
            revert NestShareSeizer__ZeroAddress();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            SEIZE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Seize shares from an account and transfer them to a recipient.
    /// @dev    Callable by authorized roles.
    /// @param  share       NestShareOFT The share token to seize from.
    /// @param  from        address The account whose shares are seized.
    /// @param  to          address The recipient of the seized shares.
    /// @param  shareAmount uint256 The amount of shares to seize.
    function seize(NestShareOFT share, address from, address to, uint256 shareAmount) external requiresAuth {
        if (from == address(0) || to == address(0) || address(share) == address(0)) {
            revert NestShareSeizer__ZeroAddress();
        }
        if (shareAmount == 0) revert NestShareSeizer__ZeroShares();

        BlacklistHook hook = _blacklistHook(share);
        _setBlacklist(hook, from, false);

        // Burn shares from `from` and mint to `to` with zero asset movement.
        share.exit(address(0), ERC20(address(0)), 0, from, shareAmount);
        share.enter(address(0), ERC20(address(0)), 0, to, shareAmount);

        _setBlacklist(hook, from, true);

        emit SharesSeized(address(share), from, to, shareAmount);
    }

    /// @notice Seize shares from an account and redeem them for assets.
    /// @dev    Callable by authorized roles.
    /// @param  from        address        The account whose shares are seized.
    /// @param  to          address        The recipient of the redeemed assets.
    /// @param  vault       INestVaultCore The vault used to convert shares to assets.
    /// @param  shareAmount uint256        The amount of shares to burn.
    function seizeAndRedeem(INestVaultCore vault, address from, address to, uint256 shareAmount) external requiresAuth {
        if (from == address(0) || to == address(0) || address(vault) == address(0)) {
            revert NestShareSeizer__ZeroAddress();
        }
        if (shareAmount == 0) revert NestShareSeizer__ZeroShares();

        NestShareOFT share = NestShareOFT(vault.share());
        if (address(share) == address(0)) {
            revert NestShareSeizer__ZeroAddress();
        }

        ERC20 asset = ERC20(vault.asset());
        uint256 assetAmount = vault.convertToAssets(shareAmount);
        if (assetAmount == 0) revert NestShareSeizer__ZeroAssets();

        BlacklistHook hook = _blacklistHook(share);
        _setBlacklist(hook, from, false);

        // Burn shares from `from` and transfer assets to `to`.
        share.exit(to, asset, assetAmount, from, shareAmount);

        _setBlacklist(hook, from, true);

        emit SharesSeizedAndRedeemed(address(share), from, to, address(asset), shareAmount, assetAmount);
    }

    /// @notice Returns whether this contract can perform seize operations for a share.
    /// @dev    Checks the hook authority for `setBlacklisted` and the share authority for `enter` and `exit`.
    /// @param  share    NestShareOFT The share token to seize from.
    /// @return bool     Whether this contract can call all required functions.
    function canSeize(NestShareOFT share) external view returns (bool) {
        address hookAddress = address(share.hook());
        if (hookAddress == address(0)) {
            return false;
        }

        BlacklistHook hook = BlacklistHook(hookAddress);

        bool canSetBlacklist =
            _canCall(hook.authority(), address(this), address(hook), BlacklistHook.setBlacklisted.selector);
        bool canExit = _canCall(share.authority(), address(this), address(share), NestShareOFT.exit.selector);
        bool canEnter = _canCall(share.authority(), address(this), address(share), NestShareOFT.enter.selector);

        return canSetBlacklist && canExit && canEnter;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the current blacklist hook from the share token.
    /// @return hook BlacklistHook The active blacklist hook contract.
    function _blacklistHook(NestShareOFT share) internal view returns (BlacklistHook hook) {
        address hookAddress = address(share.hook());
        if (hookAddress == address(0)) {
            revert NestShareSeizer__HookNotSet();
        }
        hook = BlacklistHook(hookAddress);
    }

    /// @dev Checks whether `user` can call a function on `target` via `authority` or ownership.
    /// @param authority   Authority The authority used for role checks.
    /// @param user        address   The account being checked.
    /// @param target      address   The target contract to call.
    /// @param functionSig bytes4    The function selector to check.
    /// @return            bool      Whether the call is authorized.
    function _canCall(Authority authority, address user, address target, bytes4 functionSig)
        internal
        view
        returns (bool)
    {
        return authority.canCall(user, target, functionSig);
    }

    /// @dev Sets blacklist status for `from`.
    /// @param hook       BlacklistHook The active blacklist hook contract.
    /// @param from       address       The account to update.
    /// @param _blacklist bool          Whether the account should be blacklisted.
    function _setBlacklist(BlacklistHook hook, address from, bool _blacklist) internal {
        if (hook.isBlacklisted(from) != _blacklist) {
            hook.setBlacklisted(from, _blacklist);
        }
    }
}
