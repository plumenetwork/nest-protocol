// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ERC20Mock} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/ERC20Mock.sol";

contract MockVaultAwareShare is ERC20Mock {
    mapping(address asset => address vault_) internal _vaultByAsset;

    constructor(string memory name_, string memory symbol_) ERC20Mock(name_, symbol_) {}

    function setVault(address asset, address vault_) external {
        _vaultByAsset[asset] = vault_;
    }

    function vault(address asset) external view returns (address) {
        return _vaultByAsset[asset];
    }
}
