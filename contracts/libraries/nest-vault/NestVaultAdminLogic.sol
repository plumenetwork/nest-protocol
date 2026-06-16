// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {NestVaultCoreValidationLogic} from "contracts/libraries/nest-vault/NestVaultCoreValidationLogic.sol";
import {NestVaultTransferLogic} from "contracts/libraries/nest-vault/NestVaultTransferLogic.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";

/// @title  NestVaultAdminLogic
/// @notice Library containing admin-related logic for NestVaultCore
/// @author plumenetwork
/// @custom:oz-upgrades-unsafe-allow external-library-linking
library NestVaultAdminLogic {
    using NestVaultCoreValidationLogic for NestVaultCoreTypes.NestVaultCoreStorage;
    using NestVaultTransferLogic for ERC20;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev    Emitted when the fee configuration for a fee type is updated
    /// @param  f      NestVaultCoreTypes.Fees indexed fee type
    /// @param  oldFee NestVaultCoreTypes.Fee    Previous fee configuration
    /// @param  fee    NestVaultCoreTypes.Fee    New fee configuration
    event SetFee(NestVaultCoreTypes.Fees indexed f, NestVaultCoreTypes.Fee oldFee, NestVaultCoreTypes.Fee fee);

    /// @dev    Emitted when the maximum fee cap for a fee type is updated
    /// @param  f         NestVaultCoreTypes.Fees indexed fee type
    /// @param  oldMaxFee NestVaultCoreTypes.Fee    Previous max fee configuration
    /// @param  maxFee    NestVaultCoreTypes.Fee    New max fee configuration
    event SetMaxFee(NestVaultCoreTypes.Fees indexed f, NestVaultCoreTypes.Fee oldMaxFee, NestVaultCoreTypes.Fee maxFee);

    /// @notice Emitted when the operator registry address is updated.
    /// @param oldOperatorRegistry address The previous operator registry address.
    /// @param newOperatorRegistry address The new operator registry address.
    event OperatorRegistryUpdated(address indexed oldOperatorRegistry, address indexed newOperatorRegistry);

    /// @notice Emitted when accountant address is updated.
    /// @param oldAccountant The previous accountant address.
    /// @param newAccountant The new accountant address.
    event SetAccountant(address indexed oldAccountant, address indexed newAccountant);

    /// @notice Emitted when fees are claimed
    /// @param f        NestVaultCoreTypes.Fees The fee type being claimed
    /// @param receiver address The address receiving claimed fees
    /// @param amount   uint256 The amount of fees claimed
    event FeeClaimed(NestVaultCoreTypes.Fees indexed f, address indexed receiver, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                          EXECUTE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the operator registry used for global operator approvals
    /// @param  $         NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _registry address                                 The operator registry address (zero disables registry)
    function executeSetOperatorRegistry(NestVaultCoreTypes.NestVaultCoreStorage storage $, address _registry) external {
        address oldOperatorRegistry = address($.operatorRegistry);
        $.validateOperatorRegistry(_registry);
        $.operatorRegistry = OperatorRegistry(_registry);

        emit OperatorRegistryUpdated(oldOperatorRegistry, _registry);
    }

    /// @notice Executes accountant update with compatibility checks
    /// @dev    Compatibility note:
    ///         - Legacy AccountantWithRateProviders is supported.
    ///         - Global pending-share methods are treated as optional and handled best-effort.
    /// @param  $           NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _accountant address                                 Candidate accountant address
    /// @param  _asset      ERC20                                   Vault asset used to probe safe quote rates
    function executeSetAccountant(NestVaultCoreTypes.NestVaultCoreStorage storage $, address _accountant, ERC20 _asset)
        external
    {
        $.validateSetAccountant(_accountant, _asset);

        address _oldAccountant = address($.accountant);
        $.accountant = NestHubAccountant(_accountant);

        emit SetAccountant(_oldAccountant, _accountant);
    }

    /// @notice Executes fee configuration update for a fee type
    /// @param  $    NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _f   NestVaultCoreTypes.Fees                 Fee type
    /// @param  _fee NestVaultCoreTypes.Fee             New fee configuration (rate + flat)
    function executeSetFee(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        NestVaultCoreTypes.Fees _f,
        NestVaultCoreTypes.Fee calldata _fee
    ) external {
        $.validateSetFee(_f, _fee);

        NestVaultCoreTypes.Fee memory _oldFee = NestVaultCoreTypes.Fee({rate: $.fees[_f].rate, flat: $.fees[_f].flat});
        $.fees[_f].rate = _fee.rate;
        $.fees[_f].flat = _fee.flat;

        emit SetFee(_f, _oldFee, _fee);
    }

    /// @notice Executes max fee configuration update for a fee type
    /// @param  $       NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _f      NestVaultCoreTypes.Fees                 Fee type
    /// @param  _maxFee NestVaultCoreTypes.Fee             New max fee configuration (rate + flat)
    function executeSetMaxFee(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        NestVaultCoreTypes.Fees _f,
        NestVaultCoreTypes.Fee calldata _maxFee
    ) external {
        $.validateSetMaxFee(_f, _maxFee);

        NestVaultCoreTypes.Fee memory _oldMaxFee =
            NestVaultCoreTypes.Fee({rate: $.maxFees[_f].rate, flat: $.maxFees[_f].flat});
        $.maxFees[_f].rate = _maxFee.rate;
        $.maxFees[_f].flat = _maxFee.flat;

        emit SetMaxFee(_f, _oldMaxFee, _maxFee);
    }

    /// @notice Claims accrued fees for a given fee type to a receiver
    /// @param  $          NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _f         NestVaultCoreTypes.Fees                 Fee type to claim
    /// @param  _receiver  address                                 The address receiving claimed fees
    /// @param  _assetToken ERC20                                  Vault asset token used for payout
    /// @return _feeAmount uint256                                 The amount of fees claimed
    function executeClaimFee(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        NestVaultCoreTypes.Fees _f,
        address _receiver,
        ERC20 _assetToken
    ) external returns (uint256 _feeAmount) {
        $.validateClaimFee(_f, _receiver);

        _feeAmount = $.claimableFees[_f];
        $.claimableFees[_f] = 0;
        _assetToken.safeTransferFrom(address(this), _receiver, _feeAmount);

        emit FeeClaimed(_f, _receiver, _feeAmount);
    }
}
