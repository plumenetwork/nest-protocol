// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "script/BaseScript.sol";
import {NestVaultPredicateProxy} from "contracts/NestVaultPredicateProxy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployNestVaultPredicateProxy is BaseScript {
    address public owner;
    address public serviceManager;
    address public policyId;

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        NestVaultPredicateProxy implementation = new NestVaultPredicateProxy();
        console.log("NestVault Implementation:", address(implementation));

        ProxyAdmin proxyAdmin = new ProxyAdmin(msg.sender);
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));

        bytes memory initData =
            abi.encodeWithSelector(NestVaultPredicateProxy.initialize.selector, owner, serviceManager, policyId);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);
        console.log("NestVaultPredicateProxy's Proxy deployed at:", address(proxy));

        proxyAdmin.transferOwnership(owner);
        console.log("ProxyAdmin ownership transferred to owner:", owner);

        vm.stopBroadcast();
    }
}
