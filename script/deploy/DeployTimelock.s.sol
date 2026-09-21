// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {ConfigReader, TimelockConfig, TimelockPairConfig, TimelockTierConfig} from "script/lib/ConfigReader.sol";
import {ICreateX} from "createx/ICreateX.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";

/// @title  DeployTimelock
/// @notice Deploys the chain-wide two-tier timelock governance: an admin timelock (AT) and a protocol
///         timelock (PT). PT owns the vault privileged surfaces (wired later by TransferOwnership); AT is
///         PT's sole DEFAULT_ADMIN — the recovery/role-granting tier. Reads AT/PT pairs keyed by name at the config root,
///         including `general` and vault-scoped pairs (e.g. veto / test), with the same handoff.
/// @dev    Direct broadcast only (CREATE3 salts embed the deployer EOA). Chain-level: only `CHAIN_ID` and
///         `config/timelock/<chainId>.json` are required; no vault config is read.
///
///         Each tier has explicit address, salt, delay, and roles (admin/executor/proposer/canceller).
///         Zero in roles.executor allows public execution. Proposer and canceller membership are independent.
///         Both tiers use a transient deployer admin to establish the exact configured role sets. The admin
///         tier retains self-administration plus its council; the protocol tier retains only AT as admin.
///         Reruns skip role configuration after the deployer has renounced admin, preserving governance changes.
///
///         Cross-chain address guarantee: every address is computed locally (CreateX CREATE3 math) BEFORE
///         anything is broadcast and compared with the config's tier `address` fields; a mismatch aborts.
///         On a chain where the Nest CreateX instance is missing, step 0 reproduces it through the Arachnid
///         CREATE2 factory from `config/createx/` (same salt + init code ⇒ same address).
///
///         Usage:
///           # preflight only (no broadcast): prints computed vs expected addresses
///           CHAIN_ID=5042 forge script script/deploy/DeployTimelock.s.sol --sig "check()" --rpc-url $RPC
///           # deploy (optional TIMELOCK_PAIRS=general,veto; omitted = all configured pairs)
///           CHAIN_ID=5042 forge script script/deploy/DeployTimelock.s.sol \
///             --sig "runDirect()" --rpc-url $RPC --broadcast
contract DeployTimelock is BaseConfigScript {
    using stdJson for string;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    /// @dev CreateX CREATE3 proxy child bytecode (CreateX.sol `proxyChildBytecode`).
    bytes32 internal constant CREATE3_PROXY_INITCODE_HASH = keccak256(hex"67363d3d37363d34f03d5260086018f3");

    struct PairResult {
        string name;
        address adminTimelock;
        address protocolTimelock;
    }

    TimelockConfig internal tc;
    TimelockPairConfig[] internal pairs;
    PairResult[] internal results;

    function setUp() public {
        uint256 chainId = vm.envUint("CHAIN_ID");
        // Chain-level config only; this script never reads a vault file.
        commonConfig = ConfigReader.readCommonConfig(chainId);
        vaultConfig.deployChainId = chainId;
        vaultConfig.common = ConfigReader.readCommonProxyConfig(chainId);
        CREATEX = ICreateX(commonConfig.createx);
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        snapshotCommon();
        tc = _selectPairs(ConfigReader.readTimelockConfig(chainId), vm.envOr("TIMELOCK_PAIRS", ",", new string[](0)));
        _buildPairs();
    }

    /// @notice Preflight only: validates config, computes every address and asserts it matches the configured addresses.
    function check() external view {
        _preflight();
    }

    /// @notice Bootstrap only CreateX when governance will initially remain with the multisig.
    function runCreateX() external {
        require(block.chainid == vaultConfig.deployChainId, "DeployTimelock: RPC chain mismatch");
        vm.startBroadcast(deployerPrivateKey);
        _ensureCreateX();
        vm.stopBroadcast();
    }

    function runDirect() external {
        _preflight();

        vm.startBroadcast(deployerPrivateKey);
        _ensureCreateX();
        for (uint256 i = 0; i < pairs.length; i++) {
            _deployPair(pairs[i]);
        }
        vm.stopBroadcast();

        _postConditions();
        _summary();
        writeCommonConfigIfChanged();
    }

    // ─── Pair construction ─────────────────────────────────────────────

    /// @dev Empty selection means all configured pairs; explicit names must exist and be unique.
    function _selectPairs(TimelockConfig memory config, string[] memory selected)
        internal
        pure
        returns (TimelockConfig memory filtered)
    {
        if (selected.length == 0) return config;
        filtered.pairs = new TimelockPairConfig[](selected.length);
        for (uint256 i; i < selected.length; i++) {
            bool found;
            for (uint256 j; j < i; j++) {
                require(
                    keccak256(bytes(selected[i])) != keccak256(bytes(selected[j])),
                    _err(selected[i], "duplicate selection")
                );
            }
            for (uint256 j; j < config.pairs.length; j++) {
                if (keccak256(bytes(selected[i])) == keccak256(bytes(config.pairs[j].name))) {
                    filtered.pairs[i] = config.pairs[j];
                    found = true;
                    break;
                }
            }
            require(found, _err(selected[i], "unknown pair"));
        }
    }

    function _buildPairs() internal {
        for (uint256 i; i < tc.pairs.length; i++) {
            TimelockPairConfig memory pair = tc.pairs[i];
            for (uint256 j; j < i; j++) {
                require(
                    keccak256(bytes(pair.name)) != keccak256(bytes(tc.pairs[j].name)),
                    _err(pair.name, "duplicate pair name")
                );
            }
            require(
                pair.admin.addr != address(0) && pair.protocol.addr != address(0), _err(pair.name, "addresses unset")
            );
            require(pair.admin.salt != bytes32(0) && pair.protocol.salt != bytes32(0), _err(pair.name, "salts unset"));
            pairs.push(pair);
        }
    }

    // ─── Preflight ─────────────────────────────────────────────────────

    /// @dev Validates every pair and asserts the CREATE3 addresses match the configured addresses. Nothing is broadcast.
    function _preflight() internal view {
        address _deployer = deployer();
        console.log("=== Timelock preflight ===");
        console.log("chain:   ", vaultConfig.deployChainId);
        console.log("deployer:", _deployer);
        console.log(
            "createx: ", commonConfig.createx, commonConfig.createx.code.length > 0 ? "(deployed)" : "(missing)"
        );
        if (commonConfig.createx.code.length == 0) _checkCreateXBootstrap();

        for (uint256 i = 0; i < pairs.length; i++) {
            TimelockPairConfig memory p = pairs[i];
            require(p.admin.delay > p.protocol.delay, _err(p.name, "admin delay must be > protocol delay"));
            address at = _assertAddress(p.name, "AdminTimelock", p.admin.salt, p.admin.addr);
            address pt = _assertAddress(p.name, "ProtocolTimelock", p.protocol.salt, p.protocol.addr);
            require(at != pt, _err(p.name, "AT and PT salts collide"));
            require(
                p.protocol.roles.admin.length == 1 && p.protocol.roles.admin[0] == at,
                _err(p.name, "AT must be sole protocol admin")
            );
            require(_contains(p.admin.roles.admin, at), _err(p.name, "AT must retain self administration"));
            bool council;
            for (uint256 j; j < p.admin.roles.admin.length; j++) {
                address holder = p.admin.roles.admin[j];
                if (holder == at) continue;
                require(
                    holder != address(0) && holder != _deployer && holder.code.length > 0,
                    _err(p.name, "council admin must be a deployed contract")
                );
                require(
                    !_contains(p.protocol.roles.proposer, holder), _err(p.name, "council must differ from PT proposers")
                );
                council = true;
            }
            require(council, _err(p.name, "council admin unset"));
            _warnCodeless(p.name, "AT proposer", p.admin.roles.proposer);
            _warnCodeless(p.name, "AT executor", p.admin.roles.executor);
            _warnCodeless(p.name, "AT canceller", p.admin.roles.canceller);
            _warnCodeless(p.name, "PT proposer", p.protocol.roles.proposer);
            _warnCodeless(p.name, "PT executor", p.protocol.roles.executor);
            _warnCodeless(p.name, "PT canceller", p.protocol.roles.canceller);
        }
        console.log("preflight OK: all computed addresses match expected");
    }

    /// @dev Computes the CREATE3 address for `salt` and requires it to equal `expected` (when set).
    function _assertAddress(string memory name, string memory label, bytes32 salt, address expected)
        internal
        view
        returns (address computed)
    {
        // CreateX guards a salt whose first 20 bytes are msg.sender (flag byte 0x00 = no redeploy protection)
        // by hashing it with the sender: the same salt from another EOA lands elsewhere, so pin the deployer.
        require(address(bytes20(salt)) == deployer(), _err(name, string.concat(label, ": salt not bound to deployer")));
        require(salt[20] == 0x00, _err(name, string.concat(label, ": unexpected salt flag byte")));
        computed = computeCreate3Address(salt);
        // Cross-check the local math against the live factory whenever it exists on this chain.
        if (commonConfig.createx.code.length > 0) {
            bytes32 guarded = keccak256(abi.encode(deployer(), salt));
            require(
                CREATEX.computeCreate3Address(guarded, commonConfig.createx) == computed,
                _err(name, string.concat(label, ": local CREATE3 math disagrees with CreateX"))
            );
        }
        console.log(
            string.concat("  [", name, "] ", label, ":"), computed, expected == address(0) ? "" : "(expected)", expected
        );
        if (expected != address(0)) {
            require(computed == expected, _err(name, string.concat(label, ": computed address != expected")));
        }
        if (computed.code.length > 0) console.log("      already deployed on this chain");
    }

    /// @dev Pure CREATE3 math for a sender-guarded CreateX salt (no RPC, works before CreateX exists here).
    function computeCreate3Address(bytes32 salt) public view returns (address) {
        bytes32 guarded = keccak256(abi.encode(deployer(), salt));
        address proxy = _create2(commonConfig.createx, guarded, CREATE3_PROXY_INITCODE_HASH);
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", proxy, hex"01")))));
    }

    function _create2(address factory, bytes32 salt, bytes32 initCodeHash) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", factory, salt, initCodeHash)))));
    }

    function _warnCodeless(string memory name, string memory role, address[] memory holders) internal view {
        for (uint256 i = 0; i < holders.length; i++) {
            if (holders[i] == address(0) || holders[i].code.length > 0) continue;
            console.log(string.concat("  [", name, "] WARNING: ", role, " has no code on this chain:"), holders[i]);
        }
    }

    // ─── Step 0: CreateX bootstrap ─────────────────────────────────────

    struct CreateXBootstrap {
        address factory;
        bytes32 salt;
        bytes32 initCodeHash;
        address expected;
        bytes initCode;
    }

    function _readCreateXBootstrap() internal view returns (CreateXBootstrap memory b) {
        string memory root = vm.projectRoot();
        string memory json = vm.readFile(string.concat(root, "/config/createx/deployment.json"));
        b.factory = json.readAddress(".factory");
        b.salt = json.readBytes32(".salt");
        b.initCodeHash = json.readBytes32(".initCodeHash");
        b.expected = json.readAddress(".address");
        b.initCode = vm.parseBytes(vm.trim(vm.readFile(string.concat(root, "/config/createx/initcode.hex"))));
    }

    /// @dev Proves the bundled init code + salt reproduce `common.createx` through the CREATE2 factory.
    function _checkCreateXBootstrap() internal view returns (CreateXBootstrap memory b) {
        b = _readCreateXBootstrap();
        require(b.expected == commonConfig.createx, "DeployTimelock: config/createx address != common.createx");
        require(keccak256(b.initCode) == b.initCodeHash, "DeployTimelock: createx init code hash mismatch");
        require(
            _create2(b.factory, b.salt, b.initCodeHash) == commonConfig.createx,
            "DeployTimelock: createx salt/initcode do not reproduce common.createx"
        );
        require(b.factory.code.length > 0, "DeployTimelock: CREATE2 factory missing on this chain");
        console.log("  CreateX bootstrap OK: factory", b.factory, "reproduces", commonConfig.createx);
    }

    function _ensureCreateX() internal {
        if (commonConfig.createx.code.length > 0) {
            _logExists("CreateX", commonConfig.createx);
            return;
        }
        CreateXBootstrap memory b = _checkCreateXBootstrap();
        (bool ok,) = b.factory.call(abi.encodePacked(b.salt, b.initCode));
        require(ok, "DeployTimelock: CreateX CREATE2 deployment failed");
        require(commonConfig.createx.code.length > 0, "DeployTimelock: CreateX not at expected address");
        _logDeploy("CreateX", commonConfig.createx);
    }

    // ─── Pair deployment ───────────────────────────────────────────────

    function _deployPair(TimelockPairConfig memory p) internal {
        address at = _deployTier(p.name, "admin", p.admin);
        address pt = _deployTier(p.name, "protocol", p.protocol);
        if (_isGeneral(p.name)) {
            vaultConfig.common.adminTimelock = at;
            vaultConfig.common.protocolTimelock = pt;
        }
        results.push(PairResult({name: p.name, adminTimelock: at, protocolTimelock: pt}));
    }

    function _deployTier(string memory name, string memory tierName, TimelockTierConfig memory tier)
        internal
        returns (address addr)
    {
        addr = computeCreate3Address(tier.salt);
        bool fresh = needsDeploy(addr);
        if (fresh) {
            // Start with no proposers, so OZ does not implicitly give them CANCELLER_ROLE.
            addr = _create3(
                tier.salt,
                abi.encodePacked(
                    type(TimelockController).creationCode,
                    abi.encode(tier.delay, new address[](0), new address[](0), deployer())
                )
            );
            _logDeploy(string.concat(name, " ", tierName), addr);
        } else {
            _logExists(string.concat(name, " ", tierName), addr);
        }
        TimelockController timelock = TimelockController(payable(addr));
        if (!timelock.hasRole(DEFAULT_ADMIN_ROLE, deployer())) return addr;
        _grantRoles(timelock, DEFAULT_ADMIN_ROLE, tier.roles.admin);
        _grantRoles(timelock, timelock.PROPOSER_ROLE(), tier.roles.proposer);
        _grantRoles(timelock, timelock.EXECUTOR_ROLE(), tier.roles.executor);
        _grantRoles(timelock, timelock.CANCELLER_ROLE(), tier.roles.canceller);
        // Also finish handoffs from the previous constructor, which auto-granted proposer cancellers.
        for (uint256 i; i < tier.roles.proposer.length; i++) {
            address holder = tier.roles.proposer[i];
            if (!_contains(tier.roles.canceller, holder) && timelock.hasRole(timelock.CANCELLER_ROLE(), holder)) {
                timelock.revokeRole(timelock.CANCELLER_ROLE(), holder);
            }
        }
        if (!_contains(tier.roles.admin, addr) && timelock.hasRole(DEFAULT_ADMIN_ROLE, addr)) {
            timelock.revokeRole(DEFAULT_ADMIN_ROLE, addr);
        }
        timelock.renounceRole(DEFAULT_ADMIN_ROLE, deployer());
    }

    function _grantRoles(TimelockController timelock, bytes32 role, address[] memory holders) internal {
        for (uint256 i; i < holders.length; i++) {
            if (!timelock.hasRole(role, holders[i])) timelock.grantRole(role, holders[i]);
        }
    }

    function _contains(address[] memory holders, address holder) internal pure returns (bool) {
        for (uint256 i; i < holders.length; i++) {
            if (holders[i] == holder) return true;
        }
        return false;
    }

    function _create3(bytes32 salt, bytes memory initCode) internal returns (address) {
        return CREATEX.deployCreate3(salt, initCode);
    }

    // ─── Post-conditions + outputs ─────────────────────────────────────

    /// @dev AT sole admin of PT; deployer holds nothing; addresses equal the preflight expectation.
    function _postConditions() internal view {
        address _deployer = deployer();
        for (uint256 i = 0; i < results.length; i++) {
            PairResult memory r = results[i];
            TimelockPairConfig memory p = pairs[i];
            TimelockController pt = TimelockController(payable(r.protocolTimelock));
            require(pt.hasRole(DEFAULT_ADMIN_ROLE, r.adminTimelock), _err(r.name, "AT not admin of PT"));
            require(!pt.hasRole(DEFAULT_ADMIN_ROLE, r.protocolTimelock), _err(r.name, "PT still self-admin"));
            require(!pt.hasRole(DEFAULT_ADMIN_ROLE, _deployer), _err(r.name, "deployer still admin of PT"));
            require(
                !TimelockController(payable(r.adminTimelock)).hasRole(DEFAULT_ADMIN_ROLE, _deployer),
                _err(r.name, "deployer still admin of AT")
            );
            if (p.admin.addr != address(0)) {
                require(r.adminTimelock == p.admin.addr, _err(r.name, "AT address != expected"));
            }
            if (p.protocol.addr != address(0)) {
                require(r.protocolTimelock == p.protocol.addr, _err(r.name, "PT address != expected"));
            }
        }
    }

    function _summary() internal view {
        console.log("=== Timelock Deployment Summary ===");
        for (uint256 i = 0; i < results.length; i++) {
            PairResult memory r = results[i];
            console.log(string.concat("[", r.name, "]"));
            console.log("  AdminTimelock (AT):   ", r.adminTimelock);
            console.log("    delay (s):          ", TimelockController(payable(r.adminTimelock)).getMinDelay());

            console.log("  ProtocolTimelock (PT):", r.protocolTimelock);
            console.log("    delay (s):          ", TimelockController(payable(r.protocolTimelock)).getMinDelay());

            console.log("    sole admin (AT):    ", r.adminTimelock);
        }
        console.log("===================================");
    }

    // ─── Helpers ───────────────────────────────────────────────────────

    function _isGeneral(string memory name) internal pure returns (bool) {
        return keccak256(bytes(name)) == keccak256("general");
    }

    function _err(string memory name, string memory msg_) internal pure returns (string memory) {
        return string.concat("DeployTimelock[", name, "]: ", msg_);
    }
}
