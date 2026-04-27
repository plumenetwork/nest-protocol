// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ISignatureTransfer} from "@uniswap/permit2/interfaces/ISignatureTransfer.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {Errors} from "contracts/types/Errors.sol";

/// @title  NestVaultTransferLogic
/// @notice Library containing transfer helpers with receipt validation
/// @author plumenetwork
/// @custom:oz-upgrades-unsafe-allow external-library-linking
library NestVaultTransferLogic {
    using SafeTransferLib for ERC20;

    /// @notice Executes transferFrom and validates receiver balance increase
    /// @param  token         ERC20    The token to transfer
    /// @param  _owner        address  Owner/source address
    /// @param  _receiver     address  Receiver address
    /// @param  _amount       uint256  Requested transfer amount
    /// @return _amountReceived uint256 Actual amount received by `_receiver`
    function safeTransferFrom(ERC20 token, address _owner, address _receiver, uint256 _amount)
        external
        returns (uint256 _amountReceived)
    {
        if (_owner == _receiver) return _amount;

        uint256 _balanceBefore = token.balanceOf(_receiver);
        // avoid relying on self allowance when transferring from this contract
        if (_owner == address(this)) {
            token.safeTransfer(_receiver, _amount);
        } else {
            token.safeTransferFrom(_owner, _receiver, _amount);
        }
        uint256 _balanceAfter = token.balanceOf(_receiver);

        if (_balanceAfter < _balanceBefore + _amount) revert Errors.TransferInsufficient();
        _amountReceived = _balanceAfter - _balanceBefore;
    }

    /// @notice Executes Permit2 transferFrom and validates receiver balance increase
    /// @param  token         ERC20               The token to transfer
    /// @param  permit2       ISignatureTransfer  The Permit2 contract
    /// @param  _owner        address             Owner/source address
    /// @param  _receiver     address             Receiver address
    /// @param  _amount       uint256             Requested transfer amount
    /// @param  _nonce        uint256             Permit2 nonce
    /// @param  _deadline     uint256             Permit2 deadline
    /// @param  _signature    bytes               Permit2 signature
    /// @return _amountReceived uint256           Actual amount received by `_receiver`
    function safePermit2TransferFrom(
        ERC20 token,
        ISignatureTransfer permit2,
        address _owner,
        address _receiver,
        uint256 _amount,
        uint256 _nonce,
        uint256 _deadline,
        bytes memory _signature
    ) external returns (uint256 _amountReceived) {
        uint256 _balanceBefore = token.balanceOf(_receiver);
        permit2.permitTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: address(token), amount: _amount}),
                nonce: _nonce,
                deadline: _deadline
            }),
            ISignatureTransfer.SignatureTransferDetails({to: _receiver, requestedAmount: _amount}),
            _owner,
            _signature
        );
        uint256 _balanceAfter = token.balanceOf(_receiver);

        if (_balanceAfter < _balanceBefore + _amount) revert Errors.TransferInsufficient();
        _amountReceived = _balanceAfter - _balanceBefore;
    }

    /// @notice Executes share enter and validates receiver share balance increase
    /// @param  shareToken      NestShareOFT  Share token
    /// @param  assetToken      ERC20         Asset token
    /// @param  _assets         uint256       Asset amount to enter
    /// @param  _receiver       address       Receiver of minted shares
    /// @param  _shares         uint256       Expected shares to mint
    function safeEnter(NestShareOFT shareToken, ERC20 assetToken, uint256 _assets, address _receiver, uint256 _shares)
        external
    {
        uint256 _balanceBefore = shareToken.balanceOf(_receiver);
        shareToken.enter(address(this), assetToken, _assets, _receiver, _shares);
        uint256 _balanceAfter = shareToken.balanceOf(_receiver);

        if (_balanceAfter < _balanceBefore + _shares) revert Errors.TransferInsufficient();
    }

    /// @notice Executes share exit and validates receiver asset balance increase
    /// @param  shareToken      NestShareOFT  Share token
    /// @param  assetToken      ERC20         Asset token
    /// @param  _receiver       address       Receiver of assets
    /// @param  _assets         uint256       Expected asset amount
    /// @param  _shares         uint256       Shares to burn
    /// @return _amountReceived uint256       Actual assets received by `_receiver`
    function safeExit(NestShareOFT shareToken, ERC20 assetToken, address _receiver, uint256 _assets, uint256 _shares)
        external
        returns (uint256 _amountReceived)
    {
        uint256 _balanceBefore = assetToken.balanceOf(_receiver);
        shareToken.exit(_receiver, assetToken, _assets, address(this), _shares);
        uint256 _balanceAfter = assetToken.balanceOf(_receiver);

        if (_balanceAfter < _balanceBefore + _assets) revert Errors.TransferInsufficient();
        _amountReceived = _balanceAfter - _balanceBefore;
    }
}
