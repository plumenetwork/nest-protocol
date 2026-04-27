// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "script/BaseScript.sol";
import {NestVaultComposer} from "contracts/ovault/NestVaultComposer.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// forge script script/test/UpgradeTestNestVaultComposer.s.sol:UpgradeTestNestVaultComposer --rpc-url https://rpc.plume.org
contract UpgradeTestNestVaultComposer is BaseScript {
    address constant PROXY = 0xb009Ae185dcc23419d2D1e4abdC42FC30648DacB;
    address constant PROXY_ADMIN = 0xC0E97710c479828F309377A2EED10599EC83FCcF;
    address constant PREDICATE_PROXY = 0xfC0c4222B3A0c9B060C0B959DEc62442036b9035;

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        NestVaultComposer impl = new NestVaultComposer(PREDICATE_PROXY);
        ProxyAdmin(PROXY_ADMIN).upgradeAndCall(ITransparentUpgradeableProxy(PROXY), address(impl), "");

        vm.stopBroadcast();
    }
}
