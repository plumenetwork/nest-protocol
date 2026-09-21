// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SetupFees} from "script/setup/SetupFees.s.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {NestVaultCoreTypes} from "contracts/types/NestVaultCoreTypes.sol";

/// @dev Minimal fee surface the state-aware pass reads: settable fees()/maxFees() per type.
contract MockFeeVault {
    mapping(NestVaultCoreTypes.Fees => NestVaultCoreTypes.Fee) internal _fees;
    mapping(NestVaultCoreTypes.Fees => NestVaultCoreTypes.Fee) internal _maxFees;

    function setState(NestVaultCoreTypes.Fees f, uint32 rate, uint256 flat, uint32 maxRate, uint256 maxFlat) external {
        _fees[f] = NestVaultCoreTypes.Fee({rate: rate, flat: flat});
        _maxFees[f] = NestVaultCoreTypes.Fee({rate: maxRate, flat: maxFlat});
    }

    function fees(NestVaultCoreTypes.Fees f) external view returns (uint32, uint256) {
        return (_fees[f].rate, _fees[f].flat);
    }

    function maxFees(NestVaultCoreTypes.Fees f) external view returns (uint32, uint256) {
        return (_maxFees[f].rate, _maxFees[f].flat);
    }
}

contract SetupFeesMixedCapGuardHarness is SetupFees {
    function applyStateAware(address vault, uint32 activeRate, uint256 activeFlat, uint32 maxRate, uint256 maxFlat)
        external
    {
        msigMode = true;
        _applyFeeForType(
            vault,
            NestVaultCoreTypes.Fees.Redemption,
            FeeTarget({rate: activeRate, flat: activeFlat}),
            FeeTarget({rate: maxRate, flat: maxFlat}),
            "Redemption"
        );
    }

    function queuedCount() external view returns (uint256) {
        return serializedTxs.length;
    }

    function queued(uint256 index) external view returns (address to, bytes memory data) {
        to = serializedTxs[index].to;
        data = serializedTxs[index].data;
    }
}

/// @dev Octane V17: a setMaxFee that executes against the CURRENT active fee (queued before setFee,
///      or with no setFee queued) must fail fast at generation when a component is below that fee.
contract SetupFeesMixedCapGuardTest is Test {
    NestVaultCoreTypes.Fees internal constant F = NestVaultCoreTypes.Fees.Redemption;

    SetupFeesMixedCapGuardHarness internal harness;
    MockFeeVault internal vault;

    function setUp() public {
        harness = new SetupFeesMixedCapGuardHarness();
        vault = new MockFeeVault();
    }

    function test_mixedCapRaiseBelowCurrentFeeReverts() public {
        vault.setState(F, 5000, 0, 5000, 0);
        _expectGuardRevert(1000, 100, 1000, 100);
    }

    function test_capLowerWithoutSetFeeBelowCurrentFeeReverts() public {
        vault.setState(F, 1000, 100, 1000, 100);
        _expectGuardRevert(0, 0, 1000, 50);
    }

    function test_capRaiseQueuedBeforeSetFee() public {
        vault.setState(F, 0, 0, 200_000, 0);
        harness.applyStateAware(address(vault), 500, 100, 200_000, 100);

        assertEq(harness.queuedCount(), 2);
        _assertQueued(0, abi.encodeCall(INestVaultCore.setMaxFee, (F, _fee(200_000, 100))));
        _assertQueued(1, abi.encodeCall(INestVaultCore.setFee, (F, _fee(500, 100))));
    }

    function test_capLowerAloneWhenActiveMatches() public {
        vault.setState(F, 500, 100, 200_000, 100);
        harness.applyStateAware(address(vault), 500, 100, 1000, 100);

        assertEq(harness.queuedCount(), 1);
        _assertQueued(0, abi.encodeCall(INestVaultCore.setMaxFee, (F, _fee(1000, 100))));
    }

    function test_capLowerQueuedAfterSetFee() public {
        vault.setState(F, 5000, 0, 200_000, 0);
        harness.applyStateAware(address(vault), 1000, 0, 2000, 0);

        assertEq(harness.queuedCount(), 2);
        _assertQueued(0, abi.encodeCall(INestVaultCore.setFee, (F, _fee(1000, 0))));
        _assertQueued(1, abi.encodeCall(INestVaultCore.setMaxFee, (F, _fee(2000, 0))));
    }

    function _expectGuardRevert(uint32 activeRate, uint256 activeFlat, uint32 maxRate, uint256 maxFlat) internal {
        try harness.applyStateAware(address(vault), activeRate, activeFlat, maxRate, maxFlat) {
            fail("expected the mixed-cap guard to revert");
        } catch Error(string memory reason) {
            assertTrue(vm.contains(reason, "has a component below the current active fee"), reason);
        }
        assertEq(harness.queuedCount(), 0, "nothing may be queued");
    }

    function _assertQueued(uint256 index, bytes memory expected) internal view {
        (address to, bytes memory data) = harness.queued(index);
        assertEq(to, address(vault));
        assertEq(keccak256(data), keccak256(expected));
    }

    function _fee(uint32 rate, uint256 flat) internal pure returns (NestVaultCoreTypes.Fee memory) {
        return NestVaultCoreTypes.Fee({rate: rate, flat: flat});
    }
}
