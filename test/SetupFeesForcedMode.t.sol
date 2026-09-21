// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SetupFees} from "script/setup/SetupFees.s.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {NestVaultCoreTypes} from "contracts/types/NestVaultCoreTypes.sol";

contract SetupFeesForcedModeHarness is SetupFees {
    function applyForced(address vault, uint32 activeRate, uint256 activeFlat, uint32 maxRate, uint256 maxFlat)
        external
    {
        forceSetFee = true;
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

    function queuedSelector(uint256 index) external view returns (bytes4) {
        return bytes4(serializedTxs[index].data);
    }
}

/// @dev Octane V17 Scenario 3: the live fee cannot be read before the upgrade, so forced mode
///      must not put a potentially-lowering maxFee ahead of the forced active-fee update.
contract SetupFeesForcedModeTest is Test {
    function test_forceModeSkipsMaxFeeAndQueuesOnlyActiveFee() public {
        SetupFeesForcedModeHarness harness = new SetupFeesForcedModeHarness();

        // Scenario 3 targets: live active is (4000, 50), while active=max becomes (3000, 100).
        // Forced mode deliberately cannot read the live values, so the cap must be deferred.
        harness.applyForced(address(0xBEEF), 3000, 100, 3000, 100);

        assertEq(harness.queuedCount(), 1, "forced mode must defer maxFee");
        assertEq(harness.queuedSelector(0), INestVaultCore.setFee.selector, "only setFee should be queued");
    }
}
