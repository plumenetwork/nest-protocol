// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ISignatureTransfer} from "@uniswap/permit2/interfaces/ISignatureTransfer.sol";

/// @notice Minimal Permit2 stand-in: performs the transfer with a plain transferFrom (owner must
///         approve this mock) and can be configured to shortchange the recipient.
contract MockPermit2Minimal {
    uint256 public shortchangeBy;

    function setShortchangeBy(uint256 _shortchangeBy) external {
        shortchangeBy = _shortchangeBy;
    }

    function permitTransferFrom(
        ISignatureTransfer.PermitTransferFrom memory _permit,
        ISignatureTransfer.SignatureTransferDetails calldata _transferDetails,
        address _owner,
        bytes calldata
    ) external {
        uint256 _amount = _transferDetails.requestedAmount - shortchangeBy;
        require(
            ERC20(_permit.permitted.token).transferFrom(_owner, _transferDetails.to, _amount), "transferFrom failed"
        );
    }
}
