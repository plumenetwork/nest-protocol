// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ICreateX} from "createx/ICreateX.sol";

import {DeployVault} from "script/deploy/DeployVault.s.sol";
import {CommonContracts} from "script/lib/ConfigReader.sol";

contract MockCreateXForDeployVault {
    function deployCreate3(bytes32, bytes calldata initCode) external payable returns (address deployed) {
        bytes memory code = initCode;
        assembly {
            deployed := create(callvalue(), add(code, 0x20), mload(code))
        }
        require(deployed != address(0), "mock deployment failed");
    }

    function computeCreate3Address(bytes32 salt, address deployer) external pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(salt, deployer)))));
    }
}

contract DeployVaultAuthorityHarness is DeployVault {
    function seed(
        CommonContracts memory common,
        uint256 chainId,
        string memory rawJson,
        uint256 privateKey,
        address createx
    ) external {
        vaultConfig.common = common;
        vaultConfig.deployChainId = chainId;
        vaultConfig.symbol = "nTEST";
        rawVaultConfigJson = rawJson;
        deployerPrivateKey = privateKey;
        commonConfig.createx = createx;
        CREATEX = ICreateX(createx);
    }

    function applyOverridesAndSnapshot(uint256 chainId) external {
        _applyCommonOverrides(chainId);
        snapshotCommon();
    }

    function materialize(string memory saltName, address referenceContract) external returns (address) {
        return _deployRolesAuthorityIfNeeded(saltName, referenceContract, vaultConfig.common.commonRolesAuthority, true);
    }

    function expected(string memory saltName) external view returns (address) {
        return computeCreate3AddressCommon(saltName);
    }

    function record(address commonAuth) external {
        _recordCommonAuthority(commonAuth);
    }

    function commonAuthority() external view returns (address) {
        return vaultConfig.common.commonRolesAuthority;
    }

    function write() external {
        writeCommonConfigIfChanged();
    }
}

contract DeployVaultAuthorityWiringTest is Test {
    uint256 internal constant FRESH_CHAIN_ID = 999_999_997;
    uint256 internal constant PARTIAL_CHAIN_ID = 999_999_996;
    uint256 internal constant PRIVATE_KEY = 0xA11CE;
    string internal constant COMMON_AUTHORITY_SALT = "Nest RolesAuthority";

    MockCreateXForDeployVault internal createx;
    DeployVaultAuthorityHarness internal harness;

    function setUp() public {
        createx = new MockCreateXForDeployVault();
        harness = new DeployVaultAuthorityHarness();
        _cleanup(FRESH_CHAIN_ID);
        _cleanup(PARTIAL_CHAIN_ID);
    }

    function test_predicatelessFreshAuthorityIsRecordedWithoutLeakingOverrides() public {
        CommonContracts memory canonical = _canonical();
        string memory overridesJson =
            '{"commonOverrides":{"blacklistHook":"0x0000000000000000000000000000000000000001","seizer":"0x0000000000000000000000000000000000000002"}}';
        harness.seed(canonical, FRESH_CHAIN_ID, overridesJson, PRIVATE_KEY, address(createx));
        harness.applyOverridesAndSnapshot(FRESH_CHAIN_ID);

        address commonAuth = harness.materialize(COMMON_AUTHORITY_SALT, address(0));
        assertGt(commonAuth.code.length, 0, "authority was not deployed");
        harness.record(commonAuth);
        assertEq(harness.commonAuthority(), commonAuth, "predicate-less authority not recorded");

        harness.write();
        string memory json = vm.readFile(_path(FRESH_CHAIN_ID));
        assertEq(vm.parseJsonAddress(json, ".predicateProxy"), address(0), "predicate unexpectedly required");
        assertEq(vm.parseJsonAddress(json, ".commonRolesAuthority"), commonAuth, "authority not persisted");
        assertEq(vm.parseJsonAddress(json, ".blacklistHook"), canonical.blacklistHook, "override leaked");
        assertEq(vm.parseJsonAddress(json, ".seizer"), canonical.seizer, "override leaked");

        _cleanup(FRESH_CHAIN_ID);
    }

    function test_predicatelessPartialRunReusesAndPersistsMaterializedAuthority() public {
        harness.seed(_canonical(), PARTIAL_CHAIN_ID, "{}", PRIVATE_KEY, address(createx));
        harness.applyOverridesAndSnapshot(PARTIAL_CHAIN_ID);

        address expected = harness.expected(COMMON_AUTHORITY_SALT);
        vm.etch(expected, hex"00"); // Simulate an authority deployed by an earlier partial run.
        address reused = harness.materialize(COMMON_AUTHORITY_SALT, address(0));
        assertEq(reused, expected, "partial run did not reuse deterministic authority");

        harness.record(reused);
        harness.write();
        assertEq(
            vm.parseJsonAddress(vm.readFile(_path(PARTIAL_CHAIN_ID)), ".commonRolesAuthority"),
            expected,
            "reused authority not persisted"
        );

        _cleanup(PARTIAL_CHAIN_ID);
    }

    function test_configuredCommonAuthorityIsReusedAndNeverClobbered() public {
        CommonContracts memory canonical = _canonical();
        canonical.commonRolesAuthority = makeAddr("live-common-authority");
        vm.etch(canonical.commonRolesAuthority, hex"00"); // Canonical authority already live on the chain.
        harness.seed(canonical, PARTIAL_CHAIN_ID, "{}", PRIVATE_KEY, address(createx));
        harness.applyOverridesAndSnapshot(PARTIAL_CHAIN_ID);

        address reused = harness.materialize(COMMON_AUTHORITY_SALT, address(0));
        assertEq(reused, canonical.commonRolesAuthority, "configured authority not reused");

        harness.record(makeAddr("stray-authority"));
        assertEq(harness.commonAuthority(), canonical.commonRolesAuthority, "canonical authority clobbered");

        _cleanup(PARTIAL_CHAIN_ID);
    }

    function _canonical() internal pure returns (CommonContracts memory common) {
        common.operatorRegistry = address(0xA3);
        common.redeemOperator = address(0xA4);
        common.cctpRelayer = address(0xA5);
        common.seizer = address(0xA6);
        common.blacklistHook = address(0xA7);
        common.nestAdapter = address(0xA9);
        common.nestBundler = address(0xAA);
        common.nestUnlooper = address(0xAB);
    }

    function _path(uint256 chainId) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/script/deployment-config/common/", vm.toString(chainId), ".json");
    }

    function _cleanup(uint256 chainId) internal {
        string memory path = _path(chainId);
        if (vm.exists(path)) vm.removeFile(path);
    }
}
