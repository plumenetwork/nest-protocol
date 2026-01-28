// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// contracts
import {NestVaultCore} from "contracts/NestVaultCore.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {OFTCoreUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTCoreUpgradeable.sol";
import {AuthUpgradeable} from "contracts/upgradeable/auth/AuthUpgradeable.sol";

// interfaces
import {
    IOFT,
    SendParam,
    OFTReceipt,
    MessagingReceipt,
    MessagingFee
} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/// @title  NestVaultOFT
/// @notice NestVaultOFT is an IOFT & IERC7575 & IERC7540Redeem-compatible vault
///         It allows users to deposit assets and mint shares, redeem shares for assets, and interact with operators
///         via the ERC7540 standard. The vault uses NestShare for managing underlying assets
/// @dev    This contract is upgradeable using OpenZeppelin's Initializable pattern. It inherits from ERC4626,
///         ERC20Permit, and implements the ERC7540 standard for operator authorization
/// @author plumenetwork
contract NestVaultOFT is NestVaultCore, OFTCoreUpgradeable {
    constructor(address payable _share, address _lzEndpoint)
        NestVaultCore(_share)
        OFTCoreUpgradeable(NestShareOFT(_share).decimals(), _lzEndpoint)
    {
        _disableInitializers();
    }

    /// @notice Initializes the vault with the necessary configurations
    /// @dev    Initializes key components such as the accountant, asset, and owner
    ///         `_delegate` is set as LZ delegate whereas `_owner` is used for Auth
    /// @param  _accountantWithRateProviders address The address of the AccountantWithRateProviders contract
    /// @param  _asset                       address The underlying asset that users deposit (e.g., ERC20 token)
    /// @param  _delegate                    address The address of the LayerZero delegate
    /// @param  _owner                       address The address of the owner of the vault
    /// @param  _minRate                     uint256 The minimum rate allowed for the vault,
    ///                                              it should be less than the decimals of the underlying asset
    function initialize(
        address _accountantWithRateProviders,
        address _asset, // underlying aka deposit asset
        address _delegate,
        address _owner,
        uint256 _minRate
    ) external virtual initializer {
        __NestVaultCore_init(_accountantWithRateProviders, _asset, _owner, _minRate, version());
        __OFTCore_init(_delegate);
    }

    /// @notice Returns the version of the NestVault contract.
    /// @dev    This version is used to track contract upgrades.
    /// @return string A string representing the version of the contract.
    function version() public pure returns (string memory) {
        return "0.0.1";
    }

    /// @inheritdoc IOFT
    function token() external view returns (address) {
        return address(SHARE);
    }

    /// @inheritdoc IOFT
    function approvalRequired() external pure returns (bool) {
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                    OFTCoreUpgradeable OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOFT
    function send(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress)
        external
        payable
        override
        requiresAuth
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
    {
        return _send(_sendParam, _fee, _refundAddress);
    }

    /// @dev   Internal function to perform a debit operation
    /// @param _from             address The address to debit
    /// @param _amountLD         uint256 The amount to send in local decimals
    /// @param _minAmountLD      uint256 The minimum amount to send in local decimals
    /// @param _dstEid           uint32  The destination chain ID
    /// @return amountSentLD     uint256 The amount sent in local decimals
    /// @return amountReceivedLD uint256 The amount received in local decimals on the remote
    function _debit(address _from, uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        override
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        // Burn _amountLD shares from sender (_from) and don't transfer any assets out
        SHARE.exit(address(0), ERC20(address(0)), 0, _from, amountSentLD);

        return (amountSentLD, amountReceivedLD);
    }

    /// @dev   Internal function to perform a credit operation.
    /// @param _to               address The address to credit.
    /// @param _amountLD         uint256 The amount to credit in local decimals.
    /// @return amountReceivedLD uint256 The amount ACTUALLY received in local decimals.
    function _credit(address _to, uint256 _amountLD, uint32) internal override returns (uint256 amountReceivedLD) {
        // Mint _amountLD shares to receiver (_to) and don't transfer any assets in
        SHARE.enter(address(0), ERC20(address(0)), 0, _to, _amountLD);

        return _amountLD;
    }

    /*//////////////////////////////////////////////////////////////
                        Ownable OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc AuthUpgradeable
    function owner() public view override(OwnableUpgradeable, AuthUpgradeable) returns (address) {
        return AuthUpgradeable.owner();
    }

    /// @inheritdoc AuthUpgradeable
    function transferOwnership(address newOwner) public override(OwnableUpgradeable, AuthUpgradeable) requiresAuth {
        AuthUpgradeable.transferOwnership(newOwner);
    }
}
