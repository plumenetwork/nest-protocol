// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployTimelock} from "script/deploy/DeployTimelock.s.sol";
import {ConfigReader, TimelockConfig, TimelockPairConfig} from "script/lib/ConfigReader.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ICreateX} from "createx/ICreateX.sol";

/// @dev Exposes the script's salt/address helpers without touching setUp (env + RPC).
contract DeployTimelockHarness is DeployTimelock {
    function seed(address createx, uint256 pk) external {
        commonConfig.createx = createx;
        CREATEX = ICreateX(createx);
        deployerPrivateKey = pk;
    }

    function build(TimelockConfig memory config, address opSafe) external returns (TimelockPairConfig[] memory) {
        delete pairs;
        tc = config;
        commonConfig.multisig = opSafe;
        _buildPairs();
        return pairs;
    }

    function select(TimelockConfig memory config, string[] memory names) external pure returns (TimelockConfig memory) {
        return _selectPairs(config, names);
    }

    function deployBuilt() external returns (PairResult[] memory) {
        delete results;
        CREATEX = ICreateX(commonConfig.createx);
        vm.startBroadcast(deployerPrivateKey);
        for (uint256 i; i < pairs.length; i++) {
            _deployPair(pairs[i]);
        }
        vm.stopBroadcast();
        _postConditions();
        return results;
    }

    function commonTimelocks() external view returns (address admin, address protocol) {
        return (vaultConfig.common.adminTimelock, vaultConfig.common.protocolTimelock);
    }
}

/// @title  DeployTimelockAddressesTest
/// @notice The cross-chain address guarantee rests on two things: the pair parser reading the pinned salts
///         faithfully, and the local CREATE3 math agreeing with CreateX. Both are checked here with the
///         real CreateX bytecode bundled in config/createx (deployed into the test VM at the canonical
///         Nest address so the arithmetic matches production exactly).
contract DeployTimelockAddressesTest is Test {
    address internal constant NEST_CREATEX = 0x1077f8ea07EA34D9F23BC39256BF234665FB391f;
    address internal constant NEST_DEPLOYER = 0xc28e1cDfB582953fEf53f76C64426c2aC79C716e;

    DeployTimelockHarness internal h;
    address internal liveCreateX;

    function setUp() public {
        h = new DeployTimelockHarness();
        // Deploy the bundled CreateX init code, then move its runtime to the canonical address.
        bytes memory initCode = vm.parseBytes(vm.trim(vm.readFile("config/createx/initcode.hex")));
        address tmp;
        assembly {
            tmp := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(tmp != address(0), "createx deploy failed");
        vm.etch(NEST_CREATEX, tmp.code);
        liveCreateX = tmp;
    }

    // JSON objects have no ordering contract. Arrange fixtures by name for the assertions below.
    function _readConfig(uint256 chainId) internal view returns (TimelockConfig memory config) {
        config = ConfigReader.readTimelockConfig(chainId);
        for (uint256 i; i < config.pairs.length; i++) {
            if (keccak256(bytes(config.pairs[i].name)) == keccak256("general")) {
                (config.pairs[0], config.pairs[i]) = (config.pairs[i], config.pairs[0]);
                break;
            }
        }
        for (uint256 i = 1; i < config.pairs.length; i++) {
            if (keccak256(bytes(config.pairs[i].name)) == keccak256("veto")) {
                (config.pairs[1], config.pairs[i]) = (config.pairs[i], config.pairs[1]);
                break;
            }
        }
    }

    function test_arcConfig_parsesNamedPairs() public view {
        TimelockConfig memory tc = _readConfig(5042);
        assertEq(tc.pairs[0].admin.addr, 0x8a8f1c32020C8C8a05E2eBd8860F3c8134f0b0e4);
        assertEq(tc.pairs[0].protocol.addr, 0x8fAACdC65de5D78975dF4f9DC4B6548979cEb23A);
        assertTrue(
            tc.pairs[0].admin.salt != bytes32(0) && tc.pairs[0].protocol.salt != bytes32(0), "general salts pinned"
        );
        assertEq(tc.pairs.length, 3);
        assertEq(tc.pairs[0].name, "general");
        assertEq(tc.pairs[1].name, "veto");
        assertEq(tc.pairs[1].protocol.addr, 0x34e8BB9E0fa50d63BfCa1D8E83ddba0D9fD5C062);
        assertEq(tc.pairs[1].protocol.roles.executor.length, 2, "nBASIS PT executors: op Safe + open");
        assertEq(tc.pairs[2].name, "test");
        assertEq(tc.pairs[2].admin.addr, 0xC03B33BC6684581D67B7d2AB6b9920B9A88557d0);
        assertEq(tc.pairs[2].protocol.roles.proposer.length, 2);
        assertEq(tc.pairs[2].protocol.roles.canceller.length, 1);
        // Every salt is bound to the Nest deployer with the no-redeploy-protection flag.
        assertEq(address(bytes20(tc.pairs[0].admin.salt)), NEST_DEPLOYER);
        assertEq(address(bytes20(tc.pairs[1].admin.salt)), NEST_DEPLOYER);
        assertEq(address(bytes20(tc.pairs[2].protocol.salt)), NEST_DEPLOYER);
        assertEq(tc.pairs[1].protocol.salt[20], bytes1(0));
    }

    function test_allChainConfigs_preserveExplicitRoles() public {
        uint256[8] memory chains = [uint256(1), 56, 480, 5042, 8453, 9745, 98866, 43114];
        address opSafe = address(0x123);
        for (uint256 i; i < chains.length; i++) {
            TimelockConfig memory config = _readConfig(chains[i]);
            TimelockPairConfig[] memory built = h.build(config, opSafe);
            uint256 expectedCount = chains[i] == 5042 || chains[i] == 98866
                ? 3
                : (chains[i] == 1 || chains[i] == 56 || chains[i] == 480 || chains[i] == 9745 ? 2 : 1);
            assertEq(built.length, expectedCount);
            for (uint256 j; j < built.length; j++) {
                assertEq(_create3(built[j].admin.salt), built[j].admin.addr);
                assertEq(_create3(built[j].protocol.salt), built[j].protocol.addr);
            }
            assertEq(built[0].name, "general");
            assertEq(built[0].admin.delay, 60);
            assertEq(built[0].protocol.delay, 30);
            assertEq(built[0].admin.roles.proposer[0], config.pairs[0].admin.roles.admin[1]);
            assertEq(built[0].admin.roles.executor[0], address(0));
            assertEq(built[0].protocol.roles.executor[0], address(0));
            assertEq(built[0].admin.salt, config.pairs[0].admin.salt);
            assertEq(built[0].protocol.salt, config.pairs[0].protocol.salt);
        }
    }

    function test_pairOrder_preservesExplicitRoles() public {
        TimelockConfig memory config = _readConfig(5042);
        (config.pairs[0], config.pairs[2]) = (config.pairs[2], config.pairs[0]);
        config.pairs[2].protocol.roles.proposer = new address[](0);
        address opSafe = address(0x123);
        TimelockPairConfig[] memory built = h.build(config, opSafe);
        assertEq(built[0].name, "test");
        assertEq(built[0].protocol.roles.proposer, config.pairs[0].protocol.roles.proposer);
        assertEq(built[0].protocol.roles.canceller, config.pairs[0].protocol.roles.canceller);
        assertEq(built[1].name, "veto");
        assertEq(built[1].admin.roles.executor, config.pairs[1].admin.roles.executor);
        assertEq(built[1].protocol.roles.executor, config.pairs[1].protocol.roles.executor);
        assertEq(built[2].name, "general");
        assertEq(built[2].protocol.roles.proposer.length, 0, "empty means empty, no implicit defaults");
    }

    function test_duplicatePairNames_revert() public {
        TimelockConfig memory config = _readConfig(5042);
        config.pairs[1].name = "general";
        vm.expectRevert("DeployTimelock[general]: duplicate pair name");
        h.build(config, address(0x123));
    }

    function test_selection_oneTwoOrAllAndUnknown() public {
        TimelockConfig memory config = _readConfig(5042);
        string[] memory names = new string[](1);
        names[0] = "veto";
        assertEq(h.select(config, names).pairs[0].name, "veto");
        assertEq(h.select(config, names).pairs.length, 1);
        names = new string[](2);
        names[0] = "test";
        names[1] = "general";
        TimelockConfig memory selected = h.select(config, names);
        assertEq(selected.pairs.length, 2);
        assertEq(selected.pairs[0].name, "test");
        assertEq(selected.pairs[1].name, "general");
        assertEq(h.select(config, new string[](0)).pairs.length, 3);
        names[1] = "typo";
        vm.expectRevert("DeployTimelock[typo]: unknown pair");
        h.select(config, names);
        names[1] = "test";
        vm.expectRevert("DeployTimelock[test]: duplicate selection");
        h.select(config, names);
    }

    function test_partialDeployments_areIdempotent() public {
        uint256 pk = 12345;
        address dep = vm.addr(pk);
        vm.deal(dep, 100 ether);
        h.seed(liveCreateX, pk);
        TimelockConfig memory config = _readConfig(5042);
        for (uint256 i; i < config.pairs.length; i++) {
            config.pairs[i].admin.salt = bytes32(abi.encodePacked(dep, hex"00", bytes11(uint88(2 * i + 1))));
            config.pairs[i].protocol.salt = bytes32(abi.encodePacked(dep, hex"00", bytes11(uint88(2 * i + 2))));
            config.pairs[i].admin.addr = h.computeCreate3Address(config.pairs[i].admin.salt);
            config.pairs[i].protocol.addr = h.computeCreate3Address(config.pairs[i].protocol.salt);
            config.pairs[i].admin.roles.admin[0] = config.pairs[i].admin.addr;
            config.pairs[i].protocol.roles.admin[0] = config.pairs[i].admin.addr;
        }
        vm.etch(config.pairs[0].admin.roles.admin[1], hex"00");
        config.pairs[1].admin.roles.proposer[0] = address(0x1234);
        config.pairs[1].admin.roles.executor = new address[](0);
        h.build(config, address(0x123));
        h.check();
        string[] memory names = new string[](1);
        names[0] = "veto";
        h.build(h.select(config, names), address(0x123));
        DeployTimelock.PairResult[] memory first = h.deployBuilt();
        TimelockController admin = TimelockController(payable(first[0].adminTimelock));
        assertTrue(admin.hasRole(admin.PROPOSER_ROLE(), address(0x1234)));
        assertFalse(admin.hasRole(admin.CANCELLER_ROLE(), address(0x1234)));
        assertTrue(admin.hasRole(admin.CANCELLER_ROLE(), config.pairs[1].admin.roles.canceller[0]));
        assertFalse(admin.hasRole(admin.DEFAULT_ADMIN_ROLE(), dep));
        assertFalse(admin.hasRole(admin.EXECUTOR_ROLE(), address(0)));
        assertFalse(admin.hasRole(admin.EXECUTOR_ROLE(), config.pairs[1].admin.roles.admin[1]));
        // Governance can change a live delay; rerunning deployment must leave it alone.
        vm.prank(first[0].protocolTimelock);
        TimelockController(payable(first[0].protocolTimelock)).updateDelay(1234);
        DeployTimelock.PairResult[] memory again = h.deployBuilt();
        assertEq(again[0].adminTimelock, first[0].adminTimelock);
        assertEq(again[0].protocolTimelock, first[0].protocolTimelock);
        assertEq(TimelockController(payable(first[0].protocolTimelock)).getMinDelay(), 1234);
        names[0] = "test";
        h.build(h.select(config, names), address(0x123));
        DeployTimelock.PairResult[] memory second = h.deployBuilt();
        TimelockController protocolTest = TimelockController(payable(second[0].protocolTimelock));
        address extra = config.pairs[2].protocol.roles.proposer[1];
        assertTrue(protocolTest.hasRole(protocolTest.PROPOSER_ROLE(), extra));
        assertFalse(protocolTest.hasRole(protocolTest.CANCELLER_ROLE(), extra));
        assertTrue(protocolTest.hasRole(protocolTest.EXECUTOR_ROLE(), address(0)));
        assertEq(first[0].protocolTimelock, config.pairs[1].protocol.addr);
        assertEq(second[0].protocolTimelock, config.pairs[2].protocol.addr);
        h.build(config, address(0x123));
        DeployTimelock.PairResult[] memory all = h.deployBuilt();
        assertEq(all.length, 3);
        (address adminAddress, address protocol) = h.commonTimelocks();
        assertEq(adminAddress, config.pairs[0].admin.addr);
        assertEq(protocol, config.pairs[0].protocol.addr);
    }

    /// @dev Local math == CreateX for arbitrary deployer-bound salts.
    function testFuzz_computeCreate3_matchesCreateX(uint256 pk, bytes11 tail) public {
        pk = bound(pk, 1, type(uint128).max);
        address dep = vm.addr(pk);
        h.seed(NEST_CREATEX, pk);
        bytes32 salt = bytes32(abi.encodePacked(dep, hex"00", tail));
        bytes32 guarded = keccak256(abi.encode(dep, salt));
        assertEq(h.computeCreate3Address(salt), ICreateX(NEST_CREATEX).computeCreate3Address(guarded, NEST_CREATEX));
    }

    /// @dev The pinned Arc salts reproduce the live addresses (deployer address is all the math needs).
    function test_pinnedSalts_reproduceLiveAddresses() public {
        // Any key whose address is the Nest deployer would do; the math only reads the address, so seed
        // the harness with a throwaway key and override the deployer lookup through the salt itself.
        TimelockConfig memory tc = _readConfig(5042);
        assertEq(_create3(tc.pairs[0].admin.salt), tc.pairs[0].admin.addr, "general AT");
        assertEq(_create3(tc.pairs[0].protocol.salt), tc.pairs[0].protocol.addr, "general PT");
        assertEq(_create3(tc.pairs[1].admin.salt), tc.pairs[1].admin.addr, "nBASIS AT");
        assertEq(_create3(tc.pairs[1].protocol.salt), tc.pairs[1].protocol.addr, "nBASIS PT");
        assertEq(_create3(tc.pairs[2].admin.salt), tc.pairs[2].admin.addr, "nTEST AT");
        assertEq(_create3(tc.pairs[2].protocol.salt), tc.pairs[2].protocol.addr, "nTEST PT");
    }

    function _create3(bytes32 salt) internal view returns (address) {
        bytes32 guarded = keccak256(abi.encode(NEST_DEPLOYER, salt));
        return ICreateX(NEST_CREATEX).computeCreate3Address(guarded, NEST_CREATEX);
    }
}
