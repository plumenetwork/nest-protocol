// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {Upgrade} from "script/deploy/Upgrade.s.sol";

contract UpgradeScopeHarness is Upgrade {
    function cctpRelayerTarget() external view returns (address) {
        return commonAddrs.cctpRelayer;
    }

    function relayerOnly() external view returns (bool) {
        return isCCTPRelayerScope;
    }
}

contract UpgradeScopeTest is Test {
    address internal constant PRODUCTION_RELAYER = 0x7de01896d36Bea9CF072Ac64E41685418941d8bE;
    address internal constant NTEST_RELAYER = 0x45bD35BEb70a3F0937f9701fE49AC1842dCc97b3;

    function setUp() public {
        vm.setEnv("CHAIN_ID", "98866");
        vm.setEnv("PRIVATE_KEY", "1");
    }

    function test_scopeSelectsCanonicalOrNtestRelayer() public {
        vm.setEnv("CONTRACT", "common");

        UpgradeScopeHarness commonUpgrade = new UpgradeScopeHarness();
        commonUpgrade.setUp();

        assertFalse(commonUpgrade.relayerOnly());
        assertEq(commonUpgrade.cctpRelayerTarget(), PRODUCTION_RELAYER);

        vm.setEnv("CONTRACT", "cctpRelayer");
        vm.setEnv("VAULT_SYMBOL", "nTEST");
        vm.etch(NTEST_RELAYER, hex"00");

        UpgradeScopeHarness ntestUpgrade = new UpgradeScopeHarness();
        ntestUpgrade.setUp();

        assertTrue(ntestUpgrade.relayerOnly());
        assertEq(ntestUpgrade.cctpRelayerTarget(), NTEST_RELAYER);

        vm.setEnv("VAULT_SYMBOL", "nBASIS");
        UpgradeScopeHarness unscopedUpgrade = new UpgradeScopeHarness();
        vm.expectRevert("Upgrade: cctpRelayer scope requires commonOverrides.cctpRelayer");
        unscopedUpgrade.setUp();
    }
}
