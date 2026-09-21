// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";

import {DisablePeers} from "script/setup/DisablePeers.s.sol";
import {ConfigReader} from "script/lib/ConfigReader.sol";
import {SerializedTx} from "script/lib/SafeBatchSerialize.sol";

/// @dev Minimal OApp: just the peers map DisablePeers reads and the setter it queues.
contract MockOApp {
    mapping(uint32 => bytes32) public peers;

    function setPeer(uint32 eid, bytes32 peer) external {
        peers[eid] = peer;
    }
}

/// @dev Exposes the internals; never calls the inherited setUp()/loadConfigs.
contract DisablePeersHarness is DisablePeers {
    function setExtras(uint256[] memory ids) external {
        extraDisabledChainIds = ids;
    }

    function loadExtras() external {
        _loadExtraDisabledChainIds();
    }

    function extras() external view returns (uint256[] memory) {
        return extraDisabledChainIds;
    }

    function isDisabled(uint256 id) external view returns (bool) {
        return _isDisabledChain(id);
    }

    /// @dev Non-OFT vault so _srcOApp() resolves to contracts.share; msig mode queues instead of calling.
    function seed(address share, uint256 deployChainId, uint256[] memory peers) external {
        vaultConfig.vaultType = "NestVault";
        vaultConfig.contracts.share = share;
        vaultConfig.deployChainId = deployChainId;
        vaultConfig.peers = peers;
        msigMode = true;
    }

    function disable() external {
        _disable();
    }

    function queued() external view returns (SerializedTx[] memory) {
        return serializedTxs;
    }
}

contract DisablePeersExtraChainsTest is Test {
    uint256 internal constant SURVIVOR = 98866;
    uint256 internal constant RETIRED = 56;
    string internal constant ENV = "EXTRA_DISABLED_CHAIN_IDS";

    function test_hardcodedAndExtraDisabledChains() public {
        DisablePeersHarness h = new DisablePeersHarness();

        // Hardcoded teardown targets stay disabled with no extras set.
        assertTrue(h.isDisabled(56));
        assertTrue(h.isDisabled(480));
        assertTrue(h.isDisabled(9745));
        assertFalse(h.isDisabled(8453));

        h.setExtras(_ids(8453));

        assertTrue(h.isDisabled(8453));
        assertFalse(h.isDisabled(1));
    }

    function test_extraChainIdsParsedStrictly() public {
        vm.setEnv(ENV, "56,480");
        DisablePeersHarness h = new DisablePeersHarness();
        h.loadExtras();
        assertEq(h.extras().length, 2);
        assertEq(h.extras()[0], 56);
        assertEq(h.extras()[1], 480);

        // Empty keeps the default instead of failing to parse.
        vm.setEnv(ENV, "");
        h = new DisablePeersHarness();
        h.loadExtras();
        assertEq(h.extras().length, 0);

        // A typo must revert, not silently degrade to "no extras" (the original W1 bug).
        vm.setEnv(ENV, "56;480");
        vm.expectRevert();
        h.loadExtras();

        vm.setEnv(ENV, "56,abc");
        vm.expectRevert();
        h.loadExtras();

        vm.setEnv(ENV, "");
    }

    function test_retiredChainVisitedViaExtras() public {
        uint32 eidRetired = ConfigReader.readLZConfig(RETIRED).eid;
        (DisablePeersHarness h, MockOApp oapp) = _seeded(eidRetired);

        // Retired chain already dropped from config peers: without extras it is never visited.
        h.disable();
        assertEq(h.queued().length, 0, "retired chain must be invisible without extras");

        h.setExtras(_ids(RETIRED));
        h.disable();
        SerializedTx[] memory txs = h.queued();
        assertEq(txs.length, 1, "exactly one setPeer for the retired chain");
        assertEq(txs[0].to, address(oapp));
        assertEq(txs[0].data, abi.encodeCall(IOAppCore.setPeer, (eidRetired, bytes32(0))));

        // Rerun once the peer is zero on-chain: idempotent, nothing queued.
        (h, oapp) = _seeded(eidRetired);
        oapp.setPeer(eidRetired, bytes32(0));
        h.setExtras(_ids(RETIRED));
        h.disable();
        assertEq(h.queued().length, 0, "already-zero peer must be skipped");
    }

    function test_extraStillInConfigPeersZeroedOnce() public {
        uint32 eidEth = ConfigReader.readLZConfig(1).eid;
        (DisablePeersHarness h, MockOApp oapp) = _seeded(ConfigReader.readLZConfig(RETIRED).eid);
        oapp.setPeer(eidEth, bytes32(uint256(uint160(address(0xE7)))));

        // Chain 1 is a config peer AND an extra: main loop zeroes it, extras loop must not duplicate.
        h.setExtras(_ids(1));
        h.disable();
        SerializedTx[] memory txs = h.queued();
        assertEq(txs.length, 1, "config-peer extra must be zeroed exactly once");
        assertEq(txs[0].data, abi.encodeCall(IOAppCore.setPeer, (eidEth, bytes32(0))));
    }

    /// @dev Survivor 98866 with config peers [98866, 1]; the mock still has a live peer for `eidRetired`.
    function _seeded(uint32 eidRetired) internal returns (DisablePeersHarness h, MockOApp oapp) {
        oapp = new MockOApp();
        oapp.setPeer(eidRetired, bytes32(uint256(uint160(address(0xB5C)))));
        uint256[] memory peers = new uint256[](2);
        peers[0] = SURVIVOR;
        peers[1] = 1;
        h = new DisablePeersHarness();
        h.seed(address(oapp), SURVIVOR, peers);
    }

    function _ids(uint256 id) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = id;
    }
}
