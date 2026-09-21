// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockTwoStepOwnable} from "test/TimelockGovernance.t.sol";
import {TransferOwnership} from "script/setup/TransferOwnership.s.sol";

/// @dev Exposes the internal Phase 2 queue helper so the dedup rule (Octane V13) is unit-testable.
contract TransferOwnershipDedupHarness is TransferOwnership {
    function setNewOwner(address o) external {
        newOwner = o;
    }

    function queueAccept(address t) external {
        _queueAcceptOwnership(t);
    }

    function updateOutputOwner(uint256 chainId, string memory symbol) external {
        vaultConfig.deployChainId = chainId;
        vaultConfig.symbol = symbol;
        _updateOutputOwner();
    }

    function queued() external view returns (uint256) {
        return serializedTxs.length;
    }
}

/// @title  TransferOwnershipDedupTest
/// @notice Verifies the non-timelock msig batch queues acceptOwnership once per target even when
///         a config lists the same two-step contract twice (e.g. vaults sharing a composer).
contract TransferOwnershipDedupTest is Test {
    function test_ownerOutputUpdate_keepsOwnerOutsideRoles() public {
        TransferOwnershipDedupHarness h = new TransferOwnershipDedupHarness();
        string memory symbol = "owner-layout-test";
        string memory dir = string.concat(vm.projectRoot(), "/script/output/", symbol);
        string memory path = string.concat(dir, "/999999984-", symbol, ".json");
        vm.createDir(dir, true);
        vm.writeFile(
            path,
            '{"owner":"0x0000000000000000000000000000000000000001","roles":{"OWNER_ROLE":["0x0000000000000000000000000000000000000002"]}}'
        );
        h.setNewOwner(address(3));
        h.updateOutputOwner(999999984, symbol);
        string memory json = vm.readFile(path);
        assertEq(vm.parseJsonAddress(json, ".owner"), address(3));
        assertFalse(vm.keyExistsJson(json, ".roles.owner"));
        assertEq(vm.parseJsonAddressArray(json, ".roles.OWNER_ROLE")[0], address(2));
        vm.removeDir(dir, true);
    }

    function test_queueAcceptOwnership_dedupsSharedTarget() public {
        TransferOwnershipDedupHarness h = new TransferOwnershipDedupHarness();
        address safe = makeAddr("safe");
        MockTwoStepOwnable composer = new MockTwoStepOwnable(address(this));
        composer.transferOwnership(safe); // pendingOwner = safe (Phase 1 done)
        h.setNewOwner(safe);
        h.queueAccept(address(composer));
        h.queueAccept(address(composer)); // shared composer: second vault entry
        assertEq(h.queued(), 1, "acceptOwnership queued twice for the same target");
    }
}
