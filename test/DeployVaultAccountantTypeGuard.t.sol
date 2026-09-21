// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployVault} from "script/deploy/DeployVault.s.sol";

/// @dev Exposes the internal legacy-only guard and seeds the config state it reads.
contract DeployVaultHarness is DeployVault {
    function seed(string memory json, uint256 chainId) external {
        rawVaultConfigJson = json;
        vaultConfig.deployChainId = chainId;
    }

    function guard() external view {
        _requireLegacyAccountantType();
    }
}

contract DeployVaultAccountantTypeGuardTest is Test {
    DeployVaultHarness internal harness;

    function setUp() public {
        harness = new DeployVaultHarness();
    }

    function test_guard_revertsForHubConfigOnSpokeChain() public {
        harness.seed('{"accountantType":"NestHubAccountant","hubChainId":98866}', 1);
        vm.expectRevert(
            bytes("DeployVault: accountantType resolves to NestSpokeAccountant on this chain; use DeployAndSetup")
        );
        harness.guard();
    }

    function test_guard_revertsForHubConfigOnHubChain() public {
        harness.seed('{"accountantType":"NestHubAccountant","hubChainId":98866}', 98866);
        vm.expectRevert(
            bytes("DeployVault: accountantType resolves to NestHubAccountant on this chain; use DeployAndSetup")
        );
        harness.guard();
    }

    function test_guard_allowsLegacyDefaultWhenTypeAbsent() public {
        harness.seed("{}", 1);
        harness.guard();
    }
}
