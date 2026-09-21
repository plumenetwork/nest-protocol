// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// utils
import {Test} from "forge-std/Test.sol";

// script under test
import {DeployAndSetup} from "script/deploy/DeployAndSetup.s.sol";
import {Authority} from "@solmate/auth/Auth.sol";

/// @dev Deployed contract without an authority() function — authority() reverts.
contract NotAnAuth {}

/// @dev Looks Safe-owned to the hybrid router, but still has no authority() interface.
contract OwnedButNotAuth {
    function owner() external pure returns (address) {
        return address(0xB0B);
    }
}

/// @dev Exposes internal guards of DeployAndSetup for fork-free unit testing.
contract DeployAndSetupAuthorityAssertHarness is DeployAndSetup {
    function exposedAssertAuthority(string memory name, address target, address expectedAuth) external {
        _assertAuthority(name, target, expectedAuth);
    }

    function exposedSetAuthorityIfNeeded(string memory name, address target, address expectedAuth) external {
        _setAuthorityIfNeeded(name, target, Authority(expectedAuth));
    }

    function setRouting(bool useMsigMode, bool useHybridMode) external {
        msigMode = useMsigMode;
        hybridMode = useHybridMode;
    }

    function setPrivateKey(uint256 key) external {
        deployerPrivateKey = key;
    }
}

/// @dev Octane W8: _assertAuthority must fail closed on no-code / non-Auth targets.
contract DeployAndSetupAuthorityAssertTest is Test {
    DeployAndSetupAuthorityAssertHarness internal harness;
    address internal expectedAuth = address(0xA0);

    function setUp() public {
        harness = new DeployAndSetupAuthorityAssertHarness();
        harness.setPrivateKey(1);
    }

    function test_assertAuthority_revertsOnNoCodeTarget() public {
        address eoa = makeAddr("eoa");
        vm.expectRevert(
            bytes(
                string.concat(
                    "DeployAndSetup: no code at eoa (",
                    vm.toString(eoa),
                    ") - configured address is wrong or the deploy step did not run"
                )
            )
        );
        harness.exposedAssertAuthority("eoa", eoa, expectedAuth);
    }

    function test_assertAuthority_revertsOnNonAuthContract() public {
        address notAuth = address(new NotAnAuth());
        vm.expectRevert(bytes("DeployAndSetup: authority() read failed on notAuth - target is not an Auth contract"));
        harness.exposedAssertAuthority("notAuth", notAuth, expectedAuth);
    }

    function test_assertAuthority_skipsInactiveTargets() public {
        // 0 and DEAD-disabled addresses are legitimately absent: silent return.
        harness.exposedAssertAuthority("zero", address(0), expectedAuth);
        harness.exposedAssertAuthority("dead", address(0xdead), expectedAuth);
    }

    function test_assertAuthority_msigStillRejectsNoCodeTarget() public {
        harness.setRouting(true, false);
        address eoa = makeAddr("msig-eoa");
        vm.expectRevert(
            bytes(
                string.concat(
                    "DeployAndSetup: no code at msig-eoa (",
                    vm.toString(eoa),
                    ") - configured address is wrong or the deploy step did not run"
                )
            )
        );
        harness.exposedAssertAuthority("msig-eoa", eoa, expectedAuth);
    }

    function test_assertAuthority_hybridStillRejectsSafeOwnedNonAuthTarget() public {
        harness.setRouting(false, true);
        address target = address(new OwnedButNotAuth());
        vm.expectRevert(
            bytes("DeployAndSetup: authority() read failed on hybridTarget - target is not an Auth contract")
        );
        harness.exposedAssertAuthority("hybridTarget", target, expectedAuth);
    }

    function test_setAuthority_msigStillRejectsNoCodeTarget() public {
        harness.setRouting(true, false);
        address eoa = makeAddr("set-msig-eoa");
        vm.expectRevert(
            bytes(
                string.concat(
                    "DeployAndSetup: no code at set-msig-eoa (",
                    vm.toString(eoa),
                    ") - configured address is wrong or the deploy step did not run"
                )
            )
        );
        harness.exposedSetAuthorityIfNeeded("set-msig-eoa", eoa, expectedAuth);
    }
}
