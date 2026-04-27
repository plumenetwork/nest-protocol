// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {NestVaultCoreValidationLogic} from "contracts/libraries/nest-vault/NestVaultCoreValidationLogic.sol";
import {NestVaultTransferLogic} from "contracts/libraries/nest-vault/NestVaultTransferLogic.sol";

/// @title  NestVaultDepositLogic
/// @notice Library containing deposit-related logic for NestVaultCore
/// @author plumenetwork
/// @custom:oz-upgrades-unsafe-allow external-library-linking
library NestVaultDepositLogic {
    using NestVaultCoreValidationLogic for NestVaultCoreTypes.NestVaultCoreStorage;
    using NestVaultTransferLogic for ERC20;
    using NestVaultTransferLogic for NestShareOFT;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev   Emitted when a deposit is made
    /// @param caller   address The caller making the deposit
    /// @param receiver address The receiver of the shares
    /// @param assets   uint256 The assets deposited
    /// @param shares   uint256 The shares minted
    event Deposit(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);

    /*//////////////////////////////////////////////////////////////
                          EXECUTE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes the deposit/enter logic including authorization check
    /// @param  $             NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _caller       address The caller address
    /// @param  _receiver     address The receiver address
    /// @param  _assets       uint256 Assets to deposit
    /// @param  _shares       uint256 Shares to mint
    /// @param  shareToken    NestShareOFT The share token
    /// @param  assetToken    ERC20        The asset token
    /// @param  _isAuthorized bool         Whether the caller is authorized
    function executeDeposit(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        address _caller,
        address _receiver,
        uint256 _assets,
        uint256 _shares,
        NestShareOFT shareToken,
        ERC20 assetToken,
        bool _isAuthorized
    ) external {
        // All validation in one call
        $.validateDeposit(_isAuthorized, _assets, _shares);

        assetToken.safeTransferFrom(_caller, address(this), _assets);
        SafeERC20.forceApprove(IERC20(address(assetToken)), address(shareToken), _assets);

        shareToken.safeEnter(assetToken, _assets, _receiver, _shares);

        SafeERC20.forceApprove(IERC20(address(assetToken)), address(shareToken), 0);

        emit Deposit(_caller, _receiver, _assets, _shares);
    }
}
