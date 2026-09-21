// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployComplianceProxy} from "script/deploy/DeployComplianceProxy.s.sol";
import {Upgrade} from "script/deploy/Upgrade.s.sol";
import {
    ConfigReader,
    CommonContracts,
    VaultDeployConfig,
    MorphoChainConfig,
    CCTPConfig
} from "script/lib/ConfigReader.sol";
import {SerializedTx} from "script/lib/SafeBatchSerialize.sol";
import {Auth} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {NestCCTPRelayer} from "contracts/integrations/cctp/NestCCTPRelayer.sol";
import {NestBundler} from "contracts/integrations/morpho/NestBundler.sol";
import {NestUnlooper} from "contracts/integrations/morpho/NestUnlooper.sol";
import {ComplianceProxy} from "contracts/compliance/ComplianceProxy.sol";
import {PredicateV2Hook} from "contracts/compliance/hooks/PredicateV2Hook.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract PredicateV2MigrationHarness is DeployComplianceProxy {
    function prepare()
        external
        returns (address hook, address proxy, address implementation, CommonContracts memory common)
    {
        _prepareCommon(true);
        return (predicateV2Hook, complianceProxy, cctpImplementation, vaultConfig.common);
    }

    function transactions() external view returns (SerializedTx[] memory) {
        return serializedTxs;
    }
}

contract DomainRemapHarness is Upgrade {
    function remap(address relayer) external view returns (bytes memory) {
        return _cctpDomainRemapData(relayer);
    }
}

contract PredicateV2MigrationTest is Test {
    uint256 constant KEY = 12345;
    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    uint256 constant RELAYER_NS = 0x9cb715fddca002bac31d3e28125e9692c952dae06c29708874aa1ab8a9f63300;

    function _domainSlot(uint32 eid) internal pure returns (bytes32) {
        return keccak256(abi.encode(eid, RELAYER_NS + 2));
    }

    function test_domainRemapNormalizesLegacyAndEncodedRoutesWithoutEnablingUnmappedEids() public {
        address relayer = address(0xCC79); // storage fixture only
        DomainRemapHarness script = new DomainRemapHarness();
        uint32 eth = ConfigReader.readLZConfig(1).eid;
        uint32 sol = ConfigReader.readLZConfig(101).eid;
        uint32 plume = ConfigReader.readLZConfig(98866).eid;
        vm.store(relayer, _domainSlot(eth), bytes32(uint256(5))); // old Ethereum workaround
        vm.store(relayer, _domainSlot(sol), bytes32(uint256(5)));
        vm.store(relayer, _domainSlot(plume), bytes32(uint256(22)));
        bytes memory original = script.remap(relayer);
        assertEq(original, abi.encodeCall(NestCCTPRelayer.setEidToDomain, (_eids(eth, sol, plume), _eids(0, 5, 22))));
        // A later implementation upgrade must not treat Solana's encoded 6 as domain 6.
        vm.store(relayer, _domainSlot(eth), bytes32(uint256(1)));
        vm.store(relayer, _domainSlot(sol), bytes32(uint256(6)));
        vm.store(relayer, _domainSlot(plume), bytes32(uint256(23)));
        assertEq(script.remap(relayer), original);
        vm.store(relayer, _domainSlot(eth), bytes32(0));
        vm.store(relayer, _domainSlot(sol), bytes32(0));
        vm.store(relayer, _domainSlot(plume), bytes32(0));
        assertEq(
            script.remap(relayer), abi.encodeCall(NestCCTPRelayer.setEidToDomain, (new uint32[](0), new uint32[](0)))
        );
    }

    function _eids(uint32 a, uint32 b, uint32 c) internal pure returns (uint32[] memory result) {
        result = new uint32[](3);
        result[0] = a;
        result[1] = b;
        result[2] = c;
    }

    function test_currentImplementationStillRepairsInterruptedDomainRemap() public {
        uint256 chain = 98866;
        vm.chainId(chain);
        CCTPConfig memory cc = ConfigReader.readCCTPConfig(chain);
        address endpoint = ConfigReader.readLZConfig(chain).endpoint;
        address usdc = ConfigReader.readAssetAddress(chain, "USDC");
        vm.etch(cc.messageTransmitter, hex"00");
        vm.etch(cc.tokenMessenger, hex"00");
        vm.etch(endpoint, hex"00");
        vm.etch(usdc, hex"00");
        vm.mockCall(
            usdc,
            abi.encodeWithSignature("approve(address,uint256)", cc.tokenMessenger, type(uint256).max),
            abi.encode(true)
        );
        NestCCTPRelayer implementation = new NestCCTPRelayer(cc.messageTransmitter, cc.tokenMessenger, endpoint, usdc);
        TransparentUpgradeableProxy fixture = new TransparentUpgradeableProxy(
            address(implementation), address(this), abi.encodeCall(NestCCTPRelayer.initialize, (address(this)))
        );
        address relayer = ConfigReader.readCommonProxyConfig(chain).cctpRelayer;
        // Replace existing fork storage as well as code, so this remains an isolated fixture in CI.
        vm.cloneAccount(address(fixture), relayer);
        // Unloaded mapping slots can still be fetched from the fork after cloneAccount.
        uint256[6] memory candidates = _chainIds();
        for (uint256 i; i < candidates.length; ++i) {
            vm.store(relayer, _domainSlot(ConfigReader.readLZConfig(candidates[i]).eid), bytes32(0));
        }
        uint32 eth = ConfigReader.readLZConfig(1).eid;
        uint32 sol = ConfigReader.readLZConfig(101).eid;
        uint32 plume = ConfigReader.readLZConfig(chain).eid;
        vm.store(relayer, _domainSlot(eth), bytes32(uint256(5)));
        vm.store(relayer, _domainSlot(sol), bytes32(uint256(5)));
        vm.store(relayer, _domainSlot(plume), bytes32(uint256(22)));

        string memory originalChain = vm.envOr("CHAIN_ID", string(""));
        vm.setEnv("CHAIN_ID", vm.toString(chain));
        Upgrade script = new Upgrade();
        (address prepared, SerializedTx[] memory calls) = script.prepareCommonRelayerUpgrade(address(this));
        assertEq(prepared, address(implementation));
        assertEq(calls.length, 1);
        assertEq(calls[0].to, relayer);
        assertEq(
            calls[0].data, abi.encodeCall(NestCCTPRelayer.setEidToDomain, (_eids(eth, sol, plume), _eids(0, 5, 22)))
        );
        _executeGovernance(address(this), calls);
        assertEq(uint256(vm.load(relayer, _domainSlot(eth))), 1);
        assertEq(uint256(vm.load(relayer, _domainSlot(sol))), 6);
        assertEq(uint256(vm.load(relayer, _domainSlot(plume))), 23);
        (, SerializedTx[] memory replay) = script.prepareCommonRelayerUpgrade(address(this));
        vm.setEnv("CHAIN_ID", originalChain);
        assertEq(keccak256(abi.encode(replay)), keccak256(abi.encode(calls)));
        _executeGovernance(address(this), replay);
        assertEq(uint256(vm.load(relayer, _domainSlot(sol))), 6);
        assertEq(vm.load(relayer, IMPLEMENTATION_SLOT), bytes32(uint256(uint160(prepared))));
        uint32 unmapped = ConfigReader.readLZConfig(8453).eid;
        assertEq(vm.load(relayer, _domainSlot(unmapped)), bytes32(0));
    }

    struct Snapshot {
        CommonContracts common;
        VaultDeployConfig vault;
        address governance;
        address implementation;
        address composer;
        bytes32 configHash;
        bytes32[3] peripheryCode;
        bool composerEnabled;
        uint256 fee;
        bool[6] wasMapped;
    }

    struct Prepared {
        address hook;
        address proxy;
        address implementation;
        CommonContracts common;
    }

    function _chainIds() internal pure returns (uint256[6] memory) {
        return [uint256(1), 101, 43114, 480, 8453, 98866];
    }

    function _configHash() internal view returns (bytes32) {
        return keccak256(
            bytes(vm.readFile(string.concat("script/deployment-config/common/", vm.toString(block.chainid), ".json")))
        );
    }

    function _snapshot() internal view returns (Snapshot memory s) {
        s.common = ConfigReader.readCommonProxyConfig(block.chainid);
        s.governance = Auth(s.common.commonRolesAuthority).owner();
        s.configHash = _configHash();
        s.implementation = address(uint160(uint256(vm.load(s.common.cctpRelayer, IMPLEMENTATION_SLOT))));
        s.peripheryCode = [
            keccak256(s.common.nestAdapter.code),
            keccak256(s.common.nestBundler.code),
            keccak256(s.common.nestUnlooper.code)
        ];
        s.vault = ConfigReader.resolveConfigForChain(ConfigReader.readVaultConfig("nBASIS"), block.chainid);
        s.composer = s.vault.vaults.length == 0 ? address(0) : s.vault.vaults[0].composer;
        if (s.common.cctpRelayer.code.length > 0) {
            s.composerEnabled = NestCCTPRelayer(payable(s.common.cctpRelayer)).isComposer(s.composer);
            s.fee = NestCCTPRelayer(payable(s.common.cctpRelayer)).getMaxFeeBasisPoints();
        }
        uint256[6] memory chainIds = _chainIds();
        for (uint256 i; i < chainIds.length; ++i) {
            s.wasMapped[i] =
                vm.load(s.common.cctpRelayer, _domainSlot(ConfigReader.readLZConfig(chainIds[i]).eid)) != bytes32(0);
        }
    }

    function _assertPrepared(Snapshot memory s, Prepared memory p) internal view {
        assertEq(
            vm.load(s.common.cctpRelayer, IMPLEMENTATION_SLOT),
            bytes32(uint256(uint160(s.implementation))),
            "upgrade executed before governance"
        );
        assertEq(
            PredicateV2Hook(p.hook).getPolicyID(),
            ConfigReader.readVaultConfig("nCOMMON").compliance.v2.verificationHash
        );
        assertEq(ComplianceProxy(p.proxy).owner(), vm.addr(KEY));
        assertEq(ComplianceProxy(p.proxy).pendingOwner(), s.governance);
        assertEq(address(ComplianceProxy(p.proxy).authority()), s.common.commonRolesAuthority);
        assertEq(_configHash(), s.configHash, "active config changed");
        assertEq(keccak256(s.common.nestAdapter.code), s.peripheryCode[0]);
        assertEq(keccak256(s.common.nestBundler.code), s.peripheryCode[1]);
        assertEq(keccak256(s.common.nestUnlooper.code), s.peripheryCode[2]);
        (bool hasMorpho, MorphoChainConfig memory mc) = ConfigReader.tryReadMorphoConfig(block.chainid);
        if (!hasMorpho) return;
        assertNotEq(p.common.nestAdapter, s.common.nestAdapter);
        assertNotEq(p.common.nestBundler, s.common.nestBundler);
        assertNotEq(p.common.nestUnlooper, s.common.nestUnlooper);
        NestBundler bundler = NestBundler(p.common.nestBundler);
        assertEq(bundler.COMPLIANCE_PROXY(), p.proxy);
        assertEq(bundler.ADAPTER(), p.common.nestAdapter);
        assertEq(address(bundler.MORPHO()), mc.morpho);
        assertEq(address(bundler.BUNDLER3()), mc.bundler3);
        NestUnlooper unlooper = NestUnlooper(p.common.nestUnlooper);
        assertEq(unlooper.owner(), s.governance);
        assertEq(address(unlooper.authority()), s.common.commonRolesAuthority);
        assertEq(address(unlooper.NEST_ADAPTER()), p.common.nestAdapter);
        if (s.vault.vaults.length > 0) assertFalse(unlooper.approvedVault(s.vault.vaults[0].addr));
    }

    function _assertGovernanceApplied(Snapshot memory s, Prepared memory p) internal view {
        RolesAuthority authority = RolesAuthority(s.common.commonRolesAuthority);
        assertEq(ComplianceProxy(p.proxy).owner(), s.governance);
        assertEq(ComplianceProxy(p.proxy).pendingOwner(), address(0));
        assertFalse(authority.doesUserHaveRole(p.proxy, 7));
        (bool hasMorpho,) = ConfigReader.tryReadMorphoConfig(block.chainid);
        if (hasMorpho) {
            assertTrue(authority.doesUserHaveRole(p.common.nestAdapter, 16));
            assertTrue(authority.doesRoleHaveCapability(14, p.common.nestUnlooper, NestUnlooper.execute.selector));
        }
        if (p.implementation == address(0)) return;
        NestCCTPRelayer relayer = NestCCTPRelayer(payable(s.common.cctpRelayer));
        assertEq(address(uint160(uint256(vm.load(address(relayer), IMPLEMENTATION_SLOT)))), p.implementation);
        assertEq(relayer.owner(), s.governance);
        assertEq(relayer.isComposer(s.composer), s.composerEnabled);
        assertEq(relayer.getMaxFeeBasisPoints(), s.fee);
        uint256[6] memory chainIds = _chainIds();
        for (uint256 i; i < chainIds.length; ++i) {
            uint32 eid = ConfigReader.readLZConfig(chainIds[i]).eid;
            uint32 domain = chainIds[i] == 101 ? 5 : ConfigReader.readCCTPConfig(chainIds[i]).domain;
            assertEq(uint256(vm.load(address(relayer), _domainSlot(eid))), s.wasMapped[i] ? uint256(domain) + 1 : 0);
        }
    }

    function _prepare(PredicateV2MigrationHarness script) internal returns (Prepared memory p) {
        (p.hook, p.proxy, p.implementation, p.common) = script.prepare();
    }

    function _executeGovernance(address governance, SerializedTx[] memory calls) internal {
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(governance);
            (bool ok, bytes memory reason) = calls[i].to.call(calls[i].data);
            if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        }
    }

    /// @dev Existing chain fork; disposable signer, local governance execution, no artifact writes.
    function test_forkCombinedMigrationPreservesActiveStackAndResumesIdempotently() public {
        vm.skip(!vm.envOr("PREDICATE_V2_MIGRATION_FORK", false));
        vm.setEnv("CHAIN_ID", vm.toString(block.chainid));
        vm.setEnv("PRIVATE_KEY", vm.toString(KEY));
        vm.deal(vm.addr(KEY), 100 ether);
        Snapshot memory before = _snapshot();
        PredicateV2MigrationHarness script = new PredicateV2MigrationHarness();
        Prepared memory prepared = _prepare(script);
        _assertPrepared(before, prepared);
        SerializedTx[] memory calls = script.transactions();
        assertGt(calls.length, 0);
        if (prepared.implementation != address(0) && prepared.implementation != before.implementation) {
            address admin = address(
                uint160(
                    uint256(
                        vm.load(
                            before.common.cctpRelayer,
                            0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
                        )
                    )
                )
            );
            assertEq(calls[calls.length - 2].to, admin);
            assertEq(calls[calls.length - 1].to, before.common.cctpRelayer);
        }
        uint64 beforeGovernanceNonce = vm.getNonce(vm.addr(KEY));
        assertEq(keccak256(abi.encode(_prepare(script))), keccak256(abi.encode(prepared)));
        assertEq(vm.getNonce(vm.addr(KEY)), beforeGovernanceNonce);
        assertEq(keccak256(abi.encode(script.transactions())), keccak256(abi.encode(calls)));
        _executeGovernance(before.governance, calls);
        _assertGovernanceApplied(before, prepared);
        uint64 nonce = vm.getNonce(vm.addr(KEY));
        assertEq(keccak256(abi.encode(_prepare(script))), keccak256(abi.encode(prepared)));
        assertEq(vm.getNonce(vm.addr(KEY)), nonce);
        // The relayer remap is deliberately replayable after an interrupted direct upgrade.
        SerializedTx[] memory resumed = script.transactions();
        assertEq(resumed.length, prepared.implementation == address(0) ? 0 : 1);
        _executeGovernance(before.governance, resumed);
        _assertGovernanceApplied(before, prepared);
        assertEq(_configHash(), before.configHash);
    }
}
