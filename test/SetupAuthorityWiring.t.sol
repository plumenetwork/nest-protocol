// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SetupAuthority} from "script/setup/SetupAuthority.s.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {BlacklistHook} from "contracts/compliance/hooks/BlacklistHook.sol";
import {NestShareSeizer} from "contracts/compliance/NestShareSeizer.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {ITransferHook} from "contracts/interfaces/ITransferHook.sol";

contract SetupAuthorityWiringHarness is SetupAuthority {
    function setCommon(address seizer_, address hook_, address commonAuth_) external {
        vaultConfig.common.seizer = seizer_;
        vaultConfig.common.blacklistHook = hook_;
        vaultConfig.common.commonRolesAuthority = commonAuth_;
    }

    function setShare(address share_) external {
        vaultConfig.contracts.share = share_;
    }

    function wire(address vaultAuth, address commonAuth) external {
        _setAuthorityOnContracts(vaultAuth, commonAuth);
    }

    function assertCanSeize() external view {
        _assertCanSeize();
    }

    function directCount() external view returns (uint256) {
        return directTxs.length;
    }
}

/// @dev Only the two getters `NestShareSeizer.canSeize` reads from the share.
contract MockShare {
    ITransferHook public hook;
    Authority public authority;

    constructor(ITransferHook hook_, Authority authority_) {
        hook = hook_;
        authority = authority_;
    }
}

/// @dev Octane V6: standalone SetupAuthority must wire seizer/blacklistHook to the common authority
///      and the direct-mode canSeize postcondition must reflect the resulting role-15 state.
contract SetupAuthorityWiringTest is Test {
    uint8 internal constant SEIZER_ROLE = 15;

    SetupAuthorityWiringHarness internal harness;
    RolesAuthority internal auth;
    BlacklistHook internal hook;
    NestShareSeizer internal seizer;
    MockShare internal share;

    function setUp() public {
        harness = new SetupAuthorityWiringHarness();
        auth = new RolesAuthority(address(this), Authority(address(0)));
        hook = new BlacklistHook(address(harness), Authority(address(0)));
        seizer = new NestShareSeizer(address(harness), Authority(address(0)));
        share = new MockShare(hook, auth);
        harness.setCommon(address(seizer), address(hook), address(auth));
        harness.setShare(address(share));
    }

    function test_wiresSeizerAndHookToCommonAuthorityIdempotently() public {
        harness.wire(address(auth), address(auth));

        assertEq(address(seizer.authority()), address(auth), "seizer authority");
        assertEq(address(hook.authority()), address(auth), "hook authority");
        assertEq(harness.directCount(), 2, "one setAuthority per target");

        harness.wire(address(auth), address(auth));
        assertEq(harness.directCount(), 2, "rewire must be a no-op");
    }

    function test_canSeizePostconditionTracksRoleWiring() public {
        // Hook authority still zero: canSeize itself reverts and the postcondition labels it.
        vm.expectRevert(bytes("SetupAuthority: canSeize reverted (seizer/hook authority unset)"));
        harness.assertCanSeize();

        harness.wire(address(auth), address(auth));
        vm.expectRevert(bytes("SetupAuthority: seizer cannot seize share after setup (role 15 wiring incomplete)"));
        harness.assertCanSeize();

        auth.setRoleCapability(SEIZER_ROLE, address(hook), BlacklistHook.blacklist.selector, true);
        auth.setRoleCapability(SEIZER_ROLE, address(share), NestShareOFT.exit.selector, true);
        auth.setRoleCapability(SEIZER_ROLE, address(share), NestShareOFT.enter.selector, true);
        auth.setUserRole(address(seizer), SEIZER_ROLE, true);
        harness.assertCanSeize();
    }

    function test_canSeizePostconditionSkipsUndeployedTargets() public {
        // Configured but codeless targets must skip, not revert with an unlabelled decode error.
        harness.setShare(address(0x1234));
        harness.assertCanSeize();

        harness.setShare(address(share));
        harness.setCommon(address(0x5678), address(hook), address(auth));
        harness.assertCanSeize();
    }
}
