// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// contracts
import {NestVaultCore} from "contracts/NestVaultCore.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

// interfaces
import {ISignatureTransfer} from "@uniswap/permit2/interfaces/ISignatureTransfer.sol";

// libraries
import {Errors} from "contracts/types/Errors.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {NestVaultRedeemLogic} from "contracts/libraries/nest-vault/NestVaultRedeemLogic.sol";
import {NestVaultTransferLogic} from "contracts/libraries/nest-vault/NestVaultTransferLogic.sol";

/// @title  NestVaultPermit2
/// @notice Optional Permit2 extension for NestVault implementations
/// @author plumenetwork
abstract contract NestVaultPermit2 is NestVaultCore {
    using NestVaultRedeemLogic for NestVaultCoreTypes.NestVaultCoreStorage;
    using NestVaultTransferLogic for ERC20;

    /// @dev Canonical Permit2 contract used for signature-based share transfers.
    ISignatureTransfer public immutable PERMIT2;

    /// @param _share The address of the share token
    constructor(address payable _share, address _permit2) NestVaultCore(_share) {
        if (_permit2 == address(0)) revert Errors.ZeroAddress();

        PERMIT2 = ISignatureTransfer(_permit2);
    }

    /// @notice Requests a redeem of shares using Permit2 signature-based transfer
    /// @dev    Allows users to request redemption using Permit2 SignatureTransfer for gasless token approvals.
    ///         Reference: https://docs.uniswap.org/contracts/permit2/reference/signature-transfer
    /// @param  _shares     uint256            The number of shares to redeem
    /// @param  _controller address            The address of the controller managing the redemption
    /// @param  _owner      address            The owner of the shares being redeemed
    /// @param  _nonce      uint256            Unique nonce for Permit2 signature
    /// @param  _deadline   uint256            Expiration timestamp for the permit
    /// @param  _signature  bytes              Permit2 signature from the token owner
    /// @return _requestId  uint256            The request ID for the redemption
    function requestRedeemWithPermit2(
        uint256 _shares,
        address _controller,
        address _owner,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _signature
    ) external virtual requiresAuth returns (uint256 _requestId) {
        uint256 _sharesReceived = ERC20(address(SHARE))
            .safePermit2TransferFrom(PERMIT2, _owner, address(this), _shares, _nonce, _deadline, _signature);

        _requestId = _getNestVaultCoreStorage()
            .executeRequestRedeem(_sharesReceived, _controller, _owner, msg.sender, ERC20(address(SHARE)));
    }

    /// @notice Redeems shares instantly using Permit2 signature-based transfer
    /// @dev    This function allows immediate redemption of shares using Permit2 SignatureTransfer for gasless token approvals.
    ///         Reference: https://docs.uniswap.org/contracts/permit2/reference/signature-transfer
    /// @param  _shares         uint256            The number of shares to redeem instantly
    /// @param  _receiver       address            The address to which the assets will be sent
    /// @param  _owner          address            The owner of the shares being redeemed
    /// @param  _nonce          uint256            Unique nonce for Permit2 signature
    /// @param  _deadline       uint256            Expiration timestamp for the permit
    /// @param  _signature      bytes              Permit2 signature from the token owner
    /// @return _postFeeAmount  uint256            The amount of assets received by the receiver after fees
    /// @return _feeAmount      uint256            The fee deducted from the total redemption amount
    function instantRedeemWithPermit2(
        uint256 _shares,
        address _receiver,
        address _owner,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _signature
    ) external virtual requiresAuth nonReentrant returns (uint256 _postFeeAmount, uint256 _feeAmount) {
        uint256 _sharesReceived = ERC20(address(SHARE))
            .safePermit2TransferFrom(PERMIT2, _owner, address(this), _shares, _nonce, _deadline, _signature);

        (_postFeeAmount, _feeAmount) = _getNestVaultCoreStorage()
            .executeInstantRedeem(
                _sharesReceived, _receiver, _owner, msg.sender, SHARE, ERC20(asset()), _getValidatedRate()
            );
    }
}
