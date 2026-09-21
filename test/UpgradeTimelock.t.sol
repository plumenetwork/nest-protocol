// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Upgrade} from "script/deploy/Upgrade.s.sol";
import {SerializedTx} from "script/lib/SafeBatchSerialize.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract UpgradeTimelockHarness is Upgrade {
    function validate(address timelock, address target, bytes memory data) external view {
        _assertTimelockAuthority(timelock, SerializedTx({name: "test", to: target, value: 0, data: data}));
    }
}

contract UpgradeAuthTarget is Auth {
    uint256 public value;

    constructor(address owner_, Authority authority_) Auth(owner_, authority_) {}

    function setValue(uint256 value_) external requiresAuth {
        value = value_;
    }
}

contract UpgradeTimelockTest is Test {
    UpgradeTimelockHarness script;
    TimelockController timelock;
    RolesAuthority authority;

    function setUp() public {
        script = new UpgradeTimelockHarness();
        address[] memory participants = new address[](1);
        participants[0] = address(this);
        timelock = new TimelockController(1 days, participants, participants, address(this));
        authority = new RolesAuthority(address(this), Authority(address(0)));
    }

    function test_rejectsProxyAdminOwnedByDifferentGovernance() public {
        ProxyAdmin admin = new ProxyAdmin(address(this));
        vm.expectRevert("Upgrade: timelock does not own ProxyAdmin");
        script.validate(
            address(timelock),
            address(admin),
            abi.encodeCall(ProxyAdmin.upgradeAndCall, (ITransparentUpgradeableProxy(address(1)), address(2), bytes("")))
        );
    }

    function test_rejectsSetterWithoutTimelockPermission() public {
        UpgradeAuthTarget target = new UpgradeAuthTarget(address(this), authority);
        // A role on a different selector must not authorize the queued setter.
        authority.setUserRole(address(timelock), 1, true);
        authority.setRoleCapability(1, address(target), Auth.setAuthority.selector, true);
        vm.expectRevert("Upgrade: timelock cannot configure target");
        script.validate(address(timelock), address(target), abi.encodeCall(UpgradeAuthTarget.setValue, (42)));
    }

    function test_acceptsOwnerAndRoleAuthorizedSettersAndExecutesUpgradeBatch() public {
        UpgradeAuthTarget owned = new UpgradeAuthTarget(address(timelock), Authority(address(0)));
        UpgradeAuthTarget delegated = new UpgradeAuthTarget(address(this), authority);
        authority.setUserRole(address(timelock), 1, true);
        authority.setRoleCapability(1, address(delegated), UpgradeAuthTarget.setValue.selector, true);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(owned), address(timelock), "");
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        address admin = address(uint160(uint256(vm.load(address(proxy), adminSlot))));
        address[] memory targets = new address[](3);
        targets[0] = admin;
        targets[1] = address(owned);
        targets[2] = address(delegated);
        uint256[] memory values = new uint256[](3);
        bytes[] memory payloads = new bytes[](3);
        payloads[0] = abi.encodeCall(
            ProxyAdmin.upgradeAndCall, (ITransparentUpgradeableProxy(address(proxy)), address(delegated), bytes(""))
        );
        payloads[1] = abi.encodeCall(UpgradeAuthTarget.setValue, (42));
        payloads[2] = abi.encodeCall(UpgradeAuthTarget.setValue, (43));
        for (uint256 i; i < targets.length; ++i) {
            script.validate(address(timelock), targets[i], payloads[i]);
        }
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), 1 days);
        vm.warp(block.timestamp + 1 days);
        timelock.executeBatch(targets, values, payloads, bytes32(0), bytes32(0));
        assertEq(owned.value(), 42);
        assertEq(delegated.value(), 43);
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assertEq(vm.load(address(proxy), implementationSlot), bytes32(uint256(uint160(address(delegated)))));
    }

    function test_rejectsTargetWithoutCode() public {
        vm.expectRevert("Upgrade: invalid timelock target");
        script.validate(address(timelock), address(1), abi.encodeCall(UpgradeAuthTarget.setValue, (42)));
    }
}
