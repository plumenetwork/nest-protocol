// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {DeployAndSetup} from "script/deploy/DeployAndSetup.s.sol";

/// @dev Minimal Auth-shaped target for the on-chain preflight cases.
contract MockDirectModeAuthTarget {
    address public owner;
    Authority public authority;

    constructor(address owner_, Authority authority_) {
        owner = owner_;
        authority = authority_;
    }
}

contract MockDirectModeAuthority is Authority {
    bool internal immutable allowed;

    constructor(bool allowed_) {
        allowed = allowed_;
    }

    function canCall(address, address, bytes4) external view returns (bool) {
        return allowed;
    }
}

/// @dev Exposes the internal Direct Mode preflight and its inputs for unit testing.
contract DeployAndSetupDirectModeHarness is DeployAndSetup {
    function setGuardState(
        bool stepDeploy_,
        bool stepAuthority_,
        address predicateProxy,
        string memory policyID,
        address owner_,
        uint256 pk
    ) external {
        stepDeploy = stepDeploy_;
        stepAuthority = stepAuthority_;
        vaultConfig.common.predicateProxy = predicateProxy;
        vaultConfig.compliance.v1.policyID = policyID;
        vaultConfig.owner = owner_;
        deployerPrivateKey = pk;
    }

    function setCommonRolesAuthority(address commonAuth) external {
        vaultConfig.common.commonRolesAuthority = commonAuth;
    }

    function exposedPreflight() external view {
        _requireDirectModeCanWirePredicateProxy();
    }
}

contract DeployAndSetupDirectModeGuardTest is Test {
    uint256 internal constant PK = 0xA11CE;
    bytes internal constant GUARD_REVERT =
        "DeployAndSetup: Direct Mode cannot setAuthority on a Safe-owned PredicateProxy - use hybrid run(string)";

    DeployAndSetupDirectModeHarness internal harness;
    address internal safe;
    address internal commonAuth;

    function setUp() public {
        harness = new DeployAndSetupDirectModeHarness();
        safe = makeAddr("safe");
        commonAuth = makeAddr("commonAuth");
        harness.setCommonRolesAuthority(commonAuth);
    }

    function test_preflight_revertsOnFreshSafeOwnedPredicateDeploy() public {
        harness.setGuardState(true, true, address(0), "policy", safe, PK);
        vm.expectRevert(GUARD_REVERT);
        harness.exposedPreflight();
    }

    function test_preflight_allowsFreshSafeOwnedPredicateDeployWithoutAuthorityStep() public {
        harness.setGuardState(true, false, address(0), "policy", safe, PK);
        harness.exposedPreflight();
    }

    function test_preflight_allowsFreshDeployWhenDeployerIsOwner() public {
        harness.setGuardState(true, true, address(0), "policy", vm.addr(PK), PK);
        harness.exposedPreflight();
    }

    function test_preflight_inertWithoutPolicyID() public {
        harness.setGuardState(true, true, address(0), "", safe, PK);
        harness.exposedPreflight();
    }

    function test_preflight_revertsOnUnwiredSafeOwnedProxyOnChain() public {
        address pp = address(new MockDirectModeAuthTarget(safe, Authority(address(0))));
        harness.setGuardState(false, true, pp, "", safe, PK);
        vm.expectRevert(GUARD_REVERT);
        harness.exposedPreflight();
    }

    function test_preflight_revertsOnUnwiredSafeOwnedProxyWhenCommonAuthorityDeploysThisRun() public {
        harness.setCommonRolesAuthority(address(0));
        address pp = address(new MockDirectModeAuthTarget(safe, Authority(address(0))));
        harness.setGuardState(true, true, pp, "", safe, PK);
        vm.expectRevert(GUARD_REVERT);
        harness.exposedPreflight();
    }

    function test_preflight_allowsWhenDeployerOwnsExistingProxy() public {
        address pp = address(new MockDirectModeAuthTarget(vm.addr(PK), Authority(address(0))));
        harness.setGuardState(false, true, pp, "", safe, PK);
        harness.exposedPreflight();
    }

    function test_preflight_allowsAlreadyWiredSafeOwnedProxy() public {
        Authority denying = Authority(address(new MockDirectModeAuthority(false)));
        harness.setCommonRolesAuthority(address(denying));
        address pp = address(new MockDirectModeAuthTarget(safe, denying));
        harness.setGuardState(false, true, pp, "", safe, PK);
        harness.exposedPreflight();
    }

    function test_preflight_revertsWhenExistingAuthorityDeniesDeployer() public {
        Authority denying = Authority(address(new MockDirectModeAuthority(false)));
        address pp = address(new MockDirectModeAuthTarget(safe, denying));
        harness.setGuardState(false, true, pp, "", safe, PK);
        vm.expectRevert(GUARD_REVERT);
        harness.exposedPreflight();
    }

    function test_preflight_allowsWhenExistingAuthorityAuthorizesDeployer() public {
        Authority allowing = Authority(address(new MockDirectModeAuthority(true)));
        address pp = address(new MockDirectModeAuthTarget(safe, allowing));
        harness.setGuardState(false, true, pp, "", safe, PK);
        harness.exposedPreflight();
    }
}
