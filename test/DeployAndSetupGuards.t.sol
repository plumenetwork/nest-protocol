// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {DeployAndSetup} from "../script/deploy/DeployAndSetup.s.sol";

/// @dev Exposes _processPublicCapabilities with msig queueing so no tx is ever broadcast.
contract DeployAndSetupHarness is DeployAndSetup {
    constructor() {
        msigMode = true;
    }

    function addVault(address vault) external {
        vaultConfig.vaults.push();
        vaultConfig.vaults[vaultConfig.vaults.length - 1].addr = vault;
    }

    function setPredicateProxy(address proxy) external {
        vaultConfig.common.predicateProxy = proxy;
    }

    function processPublic(string memory json, address auth) external {
        _processPublicCapabilities(json, auth);
    }

    function queued() external view returns (uint256) {
        return serializedTxs.length;
    }
}

/// @dev Octane V3: stale public deposit/mint bits must fail the run, not be silently skipped.
contract DeployAndSetupGuardsTest is Test {
    DeployAndSetupHarness internal harness;
    RolesAuthority internal auth;

    address internal constant VAULT = address(0xBEEF);
    bytes4 internal constant DEPOSIT_SEL = bytes4(keccak256("deposit(uint256,address)"));

    string internal constant PUB_JSON =
        '{"publicCapabilities":[{"target":"vault","functions":["deposit(uint256,address)","mint(uint256,address)"],"conditionalOn":"noPredicateProxy"}]}';

    function setUp() public {
        harness = new DeployAndSetupHarness();
        harness.addVault(VAULT);
        auth = new RolesAuthority(address(this), Authority(address(0)));
    }

    function test_processPublic_revertsOnStalePublicCapability() public {
        harness.setPredicateProxy(address(0xCAFE));
        auth.setPublicCapability(VAULT, DEPOSIT_SEL, true);

        vm.expectRevert(
            bytes(
                "DeployAndSetup: stale public capability - 'noPredicateProxy' no longer holds but on-chain state is public: setPublicCapability(target=vault, fn=deposit(uint256,address))"
            )
        );
        harness.processPublic(PUB_JSON, address(auth));
    }

    function test_processPublic_queuesEnableWhenConditionHolds() public {
        harness.processPublic(PUB_JSON, address(auth));
        assertEq(harness.queued(), 2);
    }

    function test_processPublic_skipsWhenConditionFailsAndStateClean() public {
        harness.setPredicateProxy(address(0xCAFE));
        harness.processPublic(PUB_JSON, address(auth));
        assertEq(harness.queued(), 0);
    }
}
