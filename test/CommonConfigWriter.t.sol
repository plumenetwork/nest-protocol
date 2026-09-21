// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {CommonContracts} from "script/lib/ConfigReader.sol";

/// @dev Exposes BaseConfigScript internals so the common-config writer can be tested without an RPC.
contract CommonConfigWriterHarness is BaseConfigScript {
    function seed(CommonContracts memory common, uint256 chainId, string memory rawJson) external {
        vaultConfig.common = common;
        vaultConfig.deployChainId = chainId;
        rawVaultConfigJson = rawJson;
    }

    function applyOverridesAndSnapshot(uint256 chainId) external {
        _applyCommonOverrides(chainId);
        snapshotCommon();
    }

    function setOperatorRegistry(address addr) external {
        vaultConfig.common.operatorRegistry = addr;
    }

    function effectiveCommon() external view returns (CommonContracts memory) {
        return vaultConfig.common;
    }

    function write() external {
        writeCommonConfigIfChanged();
    }
}

/// @dev Octane V15: per-vault `commonOverrides` must never persist into the canonical common file.
contract CommonConfigWriterTest is Test {
    uint256 internal constant CHAIN_A = 999999991;
    uint256 internal constant CHAIN_B = 999999992;

    address internal constant NEW_REGISTRY = address(0xBEEF);

    CommonConfigWriterHarness internal harness;

    function setUp() public {
        harness = new CommonConfigWriterHarness();
    }

    function _canonical() internal pure returns (CommonContracts memory c) {
        c.predicateProxy = address(0xA1);
        c.complianceProxy = address(0xA2);
        c.operatorRegistry = address(0xA3);
        c.redeemOperator = address(0xA4);
        c.cctpRelayer = address(0xA5);
        c.seizer = address(0xA6);
        c.blacklistHook = address(0xA7);
        c.commonRolesAuthority = address(0xA8);
        c.nestAdapter = address(0xA9);
        c.nestBundler = address(0xAA);
        c.nestUnlooper = address(0xAB);
        c.protocolTimelock = address(0xAC);
        c.adminTimelock = address(0xAD);
    }

    function _overridesJson() internal pure returns (string memory) {
        return '{"commonOverrides":{"nestAdapter":"0x0000000000000000000000000000000000000000","blacklistHook":"0x0000000000000000000000000000000000000001"}}';
    }

    function _path(uint256 chainId) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/script/deployment-config/common/", vm.toString(chainId), ".json");
    }

    function _cleanup(uint256 chainId) internal {
        if (vm.exists(_path(chainId))) vm.removeFile(_path(chainId));
    }

    function test_overridesNeverPersisted_deployedFieldIs() public {
        harness.seed(_canonical(), CHAIN_A, _overridesJson());
        harness.applyOverridesAndSnapshot(CHAIN_A);

        // Overlay is live for the run: nestAdapter disabled, blacklistHook swapped.
        CommonContracts memory eff = harness.effectiveCommon();
        assertEq(eff.nestAdapter, address(0));
        assertEq(eff.blacklistHook, address(1));

        // Simulate a fresh deploy mutating one common field, then persist.
        harness.setOperatorRegistry(NEW_REGISTRY);
        harness.write();

        string memory json = vm.readFile(_path(CHAIN_A));
        assertEq(vm.parseJsonUint(json, ".chainId"), CHAIN_A);
        // The mutated field keeps its new value; overridden fields keep the canonical ones.
        assertEq(vm.parseJsonAddress(json, ".operatorRegistry"), NEW_REGISTRY);
        assertEq(vm.parseJsonAddress(json, ".nestAdapter"), address(0xA9));
        assertEq(vm.parseJsonAddress(json, ".blacklistHook"), address(0xA7));
        assertEq(vm.parseJsonAddress(json, ".commonRolesAuthority"), address(0xA8));
        assertEq(vm.parseJsonAddress(json, ".adminTimelock"), address(0xAD));

        _cleanup(CHAIN_A);
    }

    function test_noMutation_writesNothing() public {
        _cleanup(CHAIN_B);
        harness.seed(_canonical(), CHAIN_B, _overridesJson());
        harness.applyOverridesAndSnapshot(CHAIN_B);
        harness.write();
        assertFalse(vm.exists(_path(CHAIN_B)));
    }
}
