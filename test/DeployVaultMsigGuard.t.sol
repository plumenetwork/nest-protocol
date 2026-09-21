// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployVault} from "script/deploy/DeployVault.s.sol";

contract DeployVaultMsigGuardHarness is DeployVault {
    function seed(address share, address accountant, address hook, string memory policyID) external {
        vaultConfig.contracts.share = share;
        vaultConfig.contracts.accountant = accountant;
        vaultConfig.common.blacklistHook = hook;
        vaultConfig.compliance.v1.policyID = policyID;
    }

    function pushVault(string memory sym, address addr) external {
        vaultConfig.vaults.push();
        vaultConfig.vaults[vaultConfig.vaults.length - 1].assetSymbol = sym;
        vaultConfig.vaults[vaultConfig.vaults.length - 1].addr = addr;
    }

    function guard() external view {
        _requireDeployedForMsig();
    }
}

contract DeployVaultMsigGuardTest is Test {
    address internal constant DEAD = address(0xdead);

    function test_requireDeployedForMsig() public {
        DeployVaultMsigGuardHarness h = new DeployVaultMsigGuardHarness();

        // Zero share: fresh deployment would be simulated-only in msig mode.
        h.seed(address(0), DEAD, DEAD, "");
        vm.expectRevert(bytes("DeployVault: runMsig requires deployed share; use runDirect"));
        h.guard();

        // Share deployed but accountant missing.
        address share = makeAddr("share");
        vm.etch(share, hex"60");
        h.seed(share, address(0), DEAD, "");
        vm.expectRevert(bytes("DeployVault: runMsig requires deployed accountant; use runDirect"));
        h.guard();

        // policyID set but predicate proxy missing.
        h.seed(share, DEAD, DEAD, "x-policy");
        vm.expectRevert(bytes("DeployVault: runMsig requires deployed predicateProxy; use runDirect"));
        h.guard();

        // Everything present or deliberately disabled (DEAD): passes.
        h.seed(share, DEAD, DEAD, "");
        h.guard();
    }

    function test_requireDeployedForMsig_hookAndVaults() public {
        DeployVaultMsigGuardHarness h = new DeployVaultMsigGuardHarness();
        address share = makeAddr("share");
        vm.etch(share, hex"60");

        // Hook missing.
        h.seed(share, DEAD, address(0), "");
        vm.expectRevert(bytes("DeployVault: runMsig requires deployed blacklistHook; use runDirect"));
        h.guard();

        // Vault entry not yet deployed: message names the asset symbol.
        h.seed(share, DEAD, DEAD, "");
        h.pushVault("USDC", address(0));
        vm.expectRevert(bytes("DeployVault: runMsig requires deployed vault-USDC"));
        h.guard();

        // Deployed vault entry: passes.
        DeployVaultMsigGuardHarness h2 = new DeployVaultMsigGuardHarness();
        address vault = makeAddr("vault");
        vm.etch(vault, hex"60");
        h2.seed(share, DEAD, DEAD, "");
        h2.pushVault("USDT", vault);
        h2.guard();
    }
}
