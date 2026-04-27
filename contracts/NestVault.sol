// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// contracts
import {NestVaultPermit2} from "contracts/NestVaultPermit2.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

/// @title  NestVault
/// @notice NestVault is an IERC7575 & IERC7540Redeem-compatible vault
///         It allows users to deposit assets and mint shares, redeem shares for assets, and interact with operators
///         via the ERC7540 standard. The vault uses NestShare for managing underlying assets
/// @dev    This contract is upgradeable and composes `NestVaultCore` through `NestVaultPermit2`, with
///         ERC4626-style deposit/mint and ERC7540 async redeem/operator behavior.
/// @author plumenetwork
contract NestVault is NestVaultPermit2 {
    /// @notice Initializes the contract with the address of the share and base tokens.
    /// @param _share The address of the share token
    constructor(address payable _share, address _permit2) NestVaultPermit2(_share, _permit2) {
        _disableInitializers();
    }

    /// @notice Initializes the vault with the necessary configurations
    /// @dev    Initializes key components such as the accountant, asset, and owner
    /// @param  _accountant                     address The address of the NestAccountant contract
    /// @param  _asset                          address The underlying asset that users deposit (e.g., ERC20 token)
    /// @param  _owner                          address The address of the owner of the vault
    /// @param  _minRate                        uint256 The minimum rate allowed for the vault,
    ///                                                 it should be less than the decimals of the underlying asset
    /// @param  _operatorRegistry               address The operator registry (zero disables registry)
    function initialize(
        address _accountant,
        address _asset,
        address _owner,
        uint256 _minRate,
        address _operatorRegistry
    ) external virtual initializer {
        __NestVaultCore_init(_accountant, _asset, _owner, _minRate, _operatorRegistry, version());
    }

    /// @notice Returns the version of the NestVault contract.
    /// @dev    This version is used to track contract upgrades.
    /// @return string A string representing the version of the contract.
    function version() public pure returns (string memory) {
        return "0.0.2";
    }

    /// @inheritdoc ERC4626Upgradeable
    function deposit(uint256 _assets, address _receiver) public virtual override returns (uint256) {
        return super.deposit(_assets, _receiver);
    }

    /// @inheritdoc ERC4626Upgradeable
    function mint(uint256 _shares, address _receiver) public virtual override returns (uint256) {
        return super.mint(_shares, _receiver);
    }
}
