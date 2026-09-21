// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployTimelock} from "script/deploy/DeployTimelock.s.sol";
import {DeployAndSetup} from "script/deploy/DeployAndSetup.s.sol";
import {DeployComplianceProxy} from "script/deploy/DeployComplianceProxy.s.sol";
import {TransferOwnership} from "script/setup/TransferOwnership.s.sol";
import {ConfigReader, CommonContracts, VaultDeployConfig} from "script/lib/ConfigReader.sol";
import {Auth} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ComplianceProxy} from "contracts/compliance/ComplianceProxy.sol";
import {NestVaultComposer} from "contracts/integrations/ovault/NestVaultComposer.sol";
import {PredicateV2Hook} from "contracts/compliance/hooks/PredicateV2Hook.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @dev Opt-in, entirely on a local fork. Requires the configured CREATE3 deployer's PRIVATE_KEY.
contract ArcDeploymentForkTest is Test {
    string constant COMMON_PATH = "script/deployment-config/common/5042.json";
    address constant GOVERNANCE = 0xa08A0Dc480BD60d1d56C8Eec6c722125eAfEa982;

    function test_arcFreshV2Rollout() public {
        if (!vm.envOr("RUN_ARC_DEPLOYMENT_FORK", false)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(vm.envString("ARC_RPC_URL"));
        vm.setEnv("CHAIN_ID", "5042");
        vm.setEnv("STEPS", "deploy,operator,composer,authority,l0,share");
        vm.deal(vm.addr(vm.envUint("PRIVATE_KEY")), 1000 ether);
        string memory original = vm.readFile(COMMON_PATH);
        // Restore canonical inputs even if a script or assertion fails.
        try this.scenario() {
            vm.writeFile(COMMON_PATH, original);
        } catch (bytes memory reason) {
            vm.writeFile(COMMON_PATH, original);
            assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        }
    }

    function scenario() external {
        require(msg.sender == address(this));
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        DeployTimelock timelocks = new DeployTimelock();
        timelocks.setUp();
        timelocks.runCreateX();
        new DeployAndSetup().runCommonV2();
        _assertNoSetupBatch("nCOMMON", "DeployAndSetup");
        CommonContracts memory common = ConfigReader.readCommonProxyConfig(5042);
        assertEq(common.predicateProxy, address(0));
        assertEq(common.adminTimelock, address(0));
        assertEq(common.protocolTimelock, address(0));
        _assertCommonOwner(common, deployer);

        new DeployComplianceProxy().runDeployOnly();
        _assertNoSetupBatch("nCOMMON", "DeployComplianceProxy");
        new DeployComplianceProxy().activateCommon();
        common = ConfigReader.readCommonProxyConfig(5042);
        _assertComplianceOwner(common, deployer);
        // Configuration and activation can be repeated without starting any ownership transfer.
        new DeployComplianceProxy().runDeployOnly();
        _assertNoSetupBatch("nCOMMON", "DeployComplianceProxy");
        new DeployComplianceProxy().activateCommon();

        string[3] memory symbols = ["nOPAL", "nFALCON", "FACTOR"];
        for (uint256 i; i < symbols.length; ++i) {
            new DeployAndSetup().run(symbols[i]);
            _assertNoSetupBatch(symbols[i], "DeployAndSetup");
            _assertVault(symbols[i], common, deployer);
        }
        // Nothing changes owner until every vault and the complete common stack are configured.
        _assertCommonOwner(common, deployer);
        _assertComplianceOwner(common, deployer);
        for (uint256 i; i < symbols.length; ++i) {
            new DeployAndSetup().run(symbols[i]);
            _assertNoSetupBatch(symbols[i], "DeployAndSetup");
            _assertVault(symbols[i], common, deployer);
        }

        // Final phase only: hand off all vaults, then shared infrastructure including V2.
        for (uint256 i; i < symbols.length; ++i) {
            _handoff(symbols[i], "vault");
            _assertVault(symbols[i], common, GOVERNANCE);
        }
        _handoff("nCOMMON", "common");
        _assertCommonOwner(common, GOVERNANCE);
        _assertComplianceOwner(common, GOVERNANCE);
        assertEq(RolesAuthority(common.commonRolesAuthority).getUserRoles(deployer), bytes32(0));
        new DeployComplianceProxy().activateCommon();
        new DeployComplianceProxy().runDeployOnly();
        _assertNoSetupBatch("nCOMMON", "DeployComplianceProxy");
        for (uint256 i; i < symbols.length; ++i) {
            new DeployAndSetup().run(symbols[i]);
            _assertNoSetupBatch(symbols[i], "DeployAndSetup");
            _assertVault(symbols[i], common, GOVERNANCE);
            VaultDeployConfig memory deployed = ConfigReader.readOutputConfig(5042, symbols[i]);
            assertEq(RolesAuthority(deployed.contracts.rolesAuthority).getUserRoles(deployer), bytes32(0));
        }
    }

    function _assertCommonOwner(CommonContracts memory common, address owner) internal view {
        address[6] memory targets = [
            common.commonRolesAuthority,
            common.operatorRegistry,
            common.redeemOperator,
            common.seizer,
            common.blacklistHook,
            common.cctpRelayer
        ];
        for (uint256 i; i < targets.length; ++i) {
            assertGt(targets[i].code.length, 0);
            assertEq(Auth(targets[i]).owner(), owner);
        }
        _assertProxyAdminOwner(common.redeemOperator, owner);
        _assertProxyAdminOwner(common.cctpRelayer, owner);
    }

    function _assertComplianceOwner(CommonContracts memory common, address owner) internal view {
        assertGt(common.complianceProxy.code.length, 0);
        ComplianceProxy proxy = ComplianceProxy(common.complianceProxy);
        assertEq(proxy.owner(), owner);
        assertEq(proxy.pendingOwner(), address(0));
        address hook = address(proxy.complianceHook());
        assertEq(PredicateV2Hook(hook).owner(), owner);
        assertEq(PredicateV2Hook(hook).pendingOwner(), address(0));
        _assertProxyAdminOwner(common.complianceProxy, owner);
        _assertProxyAdminOwner(hook, owner);
    }

    function _assertVault(string memory symbol, CommonContracts memory common, address owner) internal view {
        VaultDeployConfig memory deployed = ConfigReader.readOutputConfig(5042, symbol);
        assertEq(deployed.common.complianceProxy, common.complianceProxy);
        assertEq(deployed.owner, GOVERNANCE); // Config records the intended final owner.
        address[4] memory targets = [
            deployed.contracts.share,
            deployed.contracts.accountant,
            deployed.vaults[0].addr,
            deployed.vaults[0].composer
        ];
        for (uint256 i; i < targets.length; ++i) {
            assertGt(targets[i].code.length, 0);
            assertEq(Auth(targets[i]).owner(), owner);
            _assertProxyAdminOwner(targets[i], owner);
        }
        assertEq(
            address(NestVaultComposer(payable(deployed.vaults[0].composer)).COMPLIANCE_PROXY()), common.complianceProxy
        );
        address oapp = ConfigReader.isOFT(deployed.vaultType) ? deployed.vaults[0].addr : deployed.contracts.share;
        (bool ok, bytes memory data) =
            ConfigReader.readLZConfig(5042).endpoint.staticcall(abi.encodeWithSignature("delegates(address)", oapp));
        assertTrue(ok);
        assertEq(abi.decode(data, (address)), owner);
        RolesAuthority auth = RolesAuthority(deployed.contracts.rolesAuthority);
        assertEq(auth.owner(), owner);
        bytes4 deposit = bytes4(keccak256("deposit(uint256,address)"));
        assertTrue(auth.canCall(common.complianceProxy, deployed.vaults[0].addr, deposit));
        assertFalse(auth.canCall(address(0x123), deployed.vaults[0].addr, deposit));
        string[4] memory redemptionSignatures = [
            "requestRedeem(uint256,address,address)",
            "instantRedeem(uint256,address,address)",
            "requestRedeemWithPermit2(uint256,address,address,uint256,uint256,bytes)",
            "instantRedeemWithPermit2(uint256,address,address,uint256,uint256,bytes)"
        ];
        for (uint256 i; i < redemptionSignatures.length; ++i) {
            bytes4 selector = bytes4(keccak256(bytes(redemptionSignatures[i])));
            assertTrue(auth.isCapabilityPublic(deployed.vaults[0].addr, selector), redemptionSignatures[i]);
        }
    }

    function _assertNoSetupBatch(string memory symbol, string memory script) internal view {
        string memory prefix = string.concat("script/output/msig/5042-", symbol, "-", script);
        assertFalse(vm.exists(string.concat(prefix, ".json")), "unexpected Safe configuration batch");
        assertFalse(vm.exists(string.concat(prefix, "-Schedule.json")), "unexpected timelock batch");
        assertFalse(vm.exists(string.concat(prefix, "-Execute.json")), "unexpected timelock batch");
    }

    function _handoff(string memory symbol, string memory scope) internal {
        vm.setEnv("VAULT_SYMBOL", symbol);
        vm.setEnv("SCOPE", scope);
        vm.setEnv("NEW_OWNER", vm.toString(GOVERNANCE));
        vm.setEnv("NEW_OWNER_IS_TIMELOCK", "false");
        TransferOwnership handoff = new TransferOwnership();
        handoff.setUp();
        handoff.run();
        _governance(symbol, "TransferOwnership-AcceptOwnership");
    }

    function _governance(string memory symbol, string memory script) internal {
        string memory prefix = string.concat("script/output/msig/5042-", symbol, "-", script);
        _batch(string.concat(prefix, ".json"));
    }

    function _assertProxyAdminOwner(address proxy, address owner) internal view {
        bytes32 slot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        assertEq(ProxyAdmin(address(uint160(uint256(vm.load(proxy, slot))))).owner(), owner);
    }

    function _batch(string memory path) internal {
        if (!vm.exists(path)) return;
        string memory json = vm.readFile(path);
        uint256 i;
        while (vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(i), "]"))) {
            string memory p = string.concat(".transactions[", vm.toString(i), "]");
            address target = vm.parseJsonAddress(json, string.concat(p, ".to"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(p, ".data"));
            vm.prank(GOVERNANCE);
            (bool ok, bytes memory reason) = target.call(data);
            if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
            ++i;
        }
    }
}
