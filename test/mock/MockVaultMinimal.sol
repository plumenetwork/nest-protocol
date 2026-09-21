// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {ISignatureTransfer} from "@uniswap/permit2/interfaces/ISignatureTransfer.sol";

/// @notice Minimal NestVault surface for ComplianceProxy tests: deposit/mint/previewMint plus
///         request and instant redemption, at a deliberate 2:1 rate so amount confusion fails tests.
contract MockVaultMinimal {
    uint256 public constant ASSETS_PER_SHARE = 2;

    ERC20 public immutable asset;
    MockERC20 public immutable share;
    ISignatureTransfer public permit2;
    uint256 public depositCalls;
    uint256 public mintCalls;

    constructor(ERC20 _asset) {
        asset = _asset;
        share = new MockERC20("Mock Share", "mSH", 18);
    }

    function previewMint(uint256 _shares) public pure returns (uint256) {
        return _shares * ASSETS_PER_SHARE;
    }

    function deposit(uint256 _assets, address _receiver) external returns (uint256 _shares) {
        depositCalls++;
        require(asset.transferFrom(msg.sender, address(this), _assets), "transferFrom failed");
        _shares = _assets / ASSETS_PER_SHARE;
        share.mint(_receiver, _shares);
    }

    function mint(uint256 _shares, address _receiver) external returns (uint256 _assets) {
        mintCalls++;
        _assets = previewMint(_shares);
        require(asset.transferFrom(msg.sender, address(this), _assets), "transferFrom failed");
        share.mint(_receiver, _shares);
    }

    function setPermit2(ISignatureTransfer _permit2) external {
        permit2 = _permit2;
    }

    function PERMIT2() external view returns (ISignatureTransfer) {
        return permit2;
    }

    // ============================ REDEEM SURFACE ============================
    // Records the forwarded caller/owner/controller like the real ERC-7540 vault would see them.

    address public lastCaller;
    address public lastOwnerOrController;
    address public lastReceiver;
    uint256 public lastAmount;

    function requestRedeem(uint256 _shares, address _controller, address _owner) external returns (uint256) {
        require(_owner == msg.sender, "operator required");
        lastCaller = msg.sender;
        lastOwnerOrController = _owner;
        lastReceiver = _controller;
        lastAmount = _shares;
        require(share.transferFrom(_owner, address(this), _shares), "share transferFrom failed");
        return 0;
    }

    function requestRedeemWithPermit2(
        uint256 _shares,
        address _controller,
        address _owner,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _signature
    ) external returns (uint256) {
        require(_owner == msg.sender, "operator required");
        _recordRedeem(_shares, _controller, _owner);
        _permit2TransferFrom(_shares, _owner, _nonce, _deadline, _signature);
        return 0;
    }

    function instantRedeem(uint256 _shares, address _receiver, address _owner)
        external
        returns (uint256 _postFeeAmount, uint256 _feeAmount)
    {
        require(_owner == msg.sender, "operator required");
        lastCaller = msg.sender;
        lastOwnerOrController = _owner;
        lastReceiver = _receiver;
        lastAmount = _shares;
        require(share.transferFrom(_owner, address(this), _shares), "share transferFrom failed");
        _postFeeAmount = _shares * ASSETS_PER_SHARE - 1;
        _feeAmount = 1;
        asset.transfer(_receiver, _postFeeAmount);
    }

    function instantRedeemWithPermit2(
        uint256 _shares,
        address _receiver,
        address _owner,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _signature
    ) external returns (uint256 _postFeeAmount, uint256 _feeAmount) {
        require(_owner == msg.sender, "operator required");
        _recordRedeem(_shares, _receiver, _owner);
        _permit2TransferFrom(_shares, _owner, _nonce, _deadline, _signature);
        _postFeeAmount = _shares * ASSETS_PER_SHARE - 1;
        _feeAmount = 1;
        asset.transfer(_receiver, _postFeeAmount);
    }

    function _recordRedeem(uint256 _shares, address _receiver, address _owner) internal {
        lastCaller = msg.sender;
        lastOwnerOrController = _owner;
        lastReceiver = _receiver;
        lastAmount = _shares;
    }

    function _permit2TransferFrom(
        uint256 _shares,
        address _owner,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _signature
    ) internal {
        permit2.permitTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: address(share), amount: _shares}),
                nonce: _nonce,
                deadline: _deadline
            }),
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _shares}),
            _owner,
            _signature
        );
    }
}
