// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {NestAccountant} from "contracts/NestAccountant.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

interface IProxyAdmin {
    function upgradeAndCall(ITransparentUpgradeableProxy proxy, address implementation, bytes memory data)
        external
        payable;
}

/// @title  UpgradeNestAccountant
/// @notice Script to upgrade NestAccountant implementations with pre-flight safety checks
/// @dev    Before upgrading, this script asserts that no vault has pending redemptions.
///         This is critical because the new NestAccountant introduces a `totalPendingShares`
///         storage variable that starts at 0. If any vault already has pending shares,
///         subsequent `decreaseTotalPendingShares` calls (during fulfillRedeem/updateRedeem)
///         would revert with InsufficientBalance.
///
///         Inheriting contracts must override `_accountant()`, `_vaults()`, `_asset()`,
///         and `_share()` with chain-specific addresses.
///
///         Usage:
///         forge script ./script/UpgradeNestAccountant.s.sol:UpgradeNestAccountant_nBASIS \
///             --rpc-url $RPC_URL --broadcast
abstract contract UpgradeNestAccountant is Script {
    /// @dev ERC-1967 admin slot used by TransparentUpgradeableProxy
    bytes32 private constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    uint256 deployerPrivateKey;

    function setUp() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    /*//////////////////////////////////////////////////////////////
                        CHAIN-SPECIFIC OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @dev The NestAccountant proxy address to upgrade
    function _accountant() internal view virtual returns (address);

    /// @dev All NestVault proxy addresses associated with this accountant
    function _vaults() internal view virtual returns (address[] memory);

    /// @dev The base asset address (immutable constructor arg for NestAccountant)
    function _asset() internal view virtual returns (address);

    /// @dev The NestShareOFT address (immutable constructor arg for NestAccountant)
    function _share() internal view virtual returns (address payable);

    /*//////////////////////////////////////////////////////////////
                            MAIN ENTRY POINT
    //////////////////////////////////////////////////////////////*/

    function run() external {
        // ==================== PRE-FLIGHT: assert no pending redemptions ====================
        _assertNoPendingRedemptions();

        // ==================== DEPLOY & UPGRADE ====================
        address proxyAdmin = _getProxyAdmin(_accountant());
        console.log("ProxyAdmin for accountant:", proxyAdmin);

        vm.startBroadcast(deployerPrivateKey);

        NestAccountant implementation = new NestAccountant(_asset(), _share());
        console.log("NestAccountant implementation deployed at:", address(implementation));

        IProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(_accountant()), address(implementation), "");
        console.log("NestAccountant proxy upgraded:", _accountant());

        vm.stopBroadcast();

        // ==================== POST-UPGRADE SANITY ====================
        NestAccountant accountant = NestAccountant(_accountant());
        require(accountant.totalPendingShares() == 0, "totalPendingShares should be 0 after upgrade");
        console.log("Post-upgrade check passed: totalPendingShares == 0");
    }

    /*//////////////////////////////////////////////////////////////
                        PRE-FLIGHT SAFETY CHECK
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts if any vault associated with this accountant has pending redemptions
    /// @dev    Must be called BEFORE upgrading the NestAccountant. After the upgrade, the new
    ///         `totalPendingShares` storage slot starts at 0. If vaults already have pending
    ///         shares, `decreaseTotalPendingShares` will underflow and revert.
    function _assertNoPendingRedemptions() internal view {
        address[] memory vaults = _vaults();
        console.log("Checking %d vault(s) for pending redemptions...", vaults.length);

        for (uint256 i = 0; i < vaults.length; i++) {
            uint256 pending = INestVaultCore(vaults[i]).totalPendingShares();
            console.log("  Vault %s totalPendingShares: %d", vaults[i], pending);
            require(
                pending == 0,
                string.concat(
                    "BLOCKED: vault ",
                    vm.toString(vaults[i]),
                    " has ",
                    vm.toString(pending),
                    " pending shares. Fulfill or cancel all pending redemptions before upgrading."
                )
            );
        }

        console.log("Pre-flight check passed: no pending redemptions");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Reads the ProxyAdmin address from the ERC-1967 admin slot of a TransparentUpgradeableProxy
    function _getProxyAdmin(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ADMIN_SLOT))));
    }
}

/*//////////////////////////////////////////////////////////////
                    CHAIN-SPECIFIC INSTANCES
//////////////////////////////////////////////////////////////*/

/// @notice Worldchain: upgrade nBASIS accountant
contract UpgradeNestAccountant_nBASIS is UpgradeNestAccountant {
    function _accountant() internal pure override returns (address) {
        return 0xa67d20A49e6Fe68Cf97E556DB6b2f5DE1dF4dC2f;
    }

    function _vaults() internal pure override returns (address[] memory v) {
        v = new address[](1);
        v[0] = 0x5F35D1cef957467F4c7b35B36371355170A0DbB1;
    }

    function _asset() internal pure override returns (address) {
        return 0x79a02482A880BCE3B13E09dA970DC34Db4CD24d1; // USDC.e on Worldchain
    }

    function _share() internal pure override returns (address payable) {
        return payable(0x11113Ff3a60C2450F4b22515cB760417259eE94B);
    }
}

/// @notice Worldchain: upgrade nALPHA accountant
contract UpgradeNestAccountant_nALPHA is UpgradeNestAccountant {
    function _accountant() internal pure override returns (address) {
        return 0xe0CF451d6E373FF04e8eE3c50340F18AFa6421E1;
    }

    function _vaults() internal pure override returns (address[] memory v) {
        v = new address[](1);
        v[0] = 0x0342EE795e7864319fB8D48651b47feBf1163C34;
    }

    function _asset() internal pure override returns (address) {
        return 0x79a02482A880BCE3B13E09dA970DC34Db4CD24d1; // USDC.e on Worldchain
    }

    function _share() internal pure override returns (address payable) {
        return payable(0x593cCcA4c4bf58b7526a4C164cEEf4003C6388db);
    }
}

/// @notice Worldchain: upgrade nTBILL accountant
contract UpgradeNestAccountant_nTBILL is UpgradeNestAccountant {
    function _accountant() internal pure override returns (address) {
        return 0x0b738cd187872b265A689e8e4130C336e76892eC;
    }

    function _vaults() internal pure override returns (address[] memory v) {
        v = new address[](1);
        v[0] = 0x250c2D14Ed6376fB392FbA1edd2cfd11d2Bf7F12;
    }

    function _asset() internal pure override returns (address) {
        return 0x79a02482A880BCE3B13E09dA970DC34Db4CD24d1; // USDC.e on Worldchain
    }

    function _share() internal pure override returns (address payable) {
        return payable(0xE72Fe64840F4EF80E3Ec73a1c749491b5c938CB9);
    }
}
