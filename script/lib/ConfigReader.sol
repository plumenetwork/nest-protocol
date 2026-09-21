// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {stdJson as StdJson} from "forge-std/StdJson.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

struct CommonConfig {
    uint256 chainId;
    string name;
    string rpcEnvVar;
    bool isEvm;
    // Common addresses
    address permit2;
    address createx;
    address multisig;
}

struct ComplianceV1CommonConfig {
    address serviceManager;
    string defaultPolicyID;
}

struct ComplianceV2CommonConfig {
    string apiChain;
    address predicateRegistry;
}

struct ChainComplianceConfig {
    uint256 chainId;
    bool v2Only;
    ComplianceV1CommonConfig v1;
    ComplianceV2CommonConfig v2;
}

struct LZConfig {
    uint256 chainId;
    uint32 eid;
    address endpoint;
    address sendLib302;
    address receiveLib302;
    address executor;
    address delegate;
}

struct DVNConfig {
    address lz;
    address nethermind;
    address canary;
}

struct EnforcedOptionsConfig {
    uint128 receiveGas;
    uint128 receiveMsgValue;
    uint128 sendGas;
    uint128 sendMsgValue;
    uint128 composeGas;
    uint128 composeMsgValue;
}

struct CCTPConfig {
    address messageTransmitter;
    address tokenMessenger;
    address tokenMinter;
    uint32 domain;
    uint256 maxFeeBasisPoints; // optional key, 0 = unconfigured
    uint32 finalityThreshold; // optional key, 0 = unconfigured
}

/// @notice config/timelock/<chainId>.json is keyed by pair name, each with admin/protocol tiers.
struct TimelockConfig {
    TimelockPairConfig[] pairs;
}

struct TimelockPairConfig {
    string name;
    TimelockTierConfig admin;
    TimelockTierConfig protocol;
}

/// @dev All fields and role lists are explicit. Zero in executor means public execution.
struct TimelockTierConfig {
    address addr;
    bytes32 salt;
    uint256 delay;
    TimelockRoles roles;
}

struct TimelockRoles {
    address[] admin;
    address[] executor;
    address[] proposer;
    address[] canceller;
}

struct VaultEntry {
    string assetSymbol;
    uint256[] chains;
    address addr;
    bool isPegged;
    address rateProvider;
    address composer;
    address legacyTeller;
}

struct VaultContracts {
    address share;
    address accountant;
    address rolesAuthority;
}

struct CommonContracts {
    address predicateProxy;
    // V2 ComplianceProxy consumed by compliance-gated integrations (NestBundler deposit routes).
    address complianceProxy;
    address operatorRegistry;
    address redeemOperator;
    address cctpRelayer;
    address seizer;
    address blacklistHook;
    address commonRolesAuthority;
    address nestAdapter;
    address nestBundler;
    address nestUnlooper;
    // Two-tier timelock governance (see config/timelock/<chainId>.json, DeployTimelock.s.sol).
    // protocolTimelock owns the vault privileged surfaces; adminTimelock is its sole DEFAULT_ADMIN.
    address protocolTimelock;
    address adminTimelock;
}

struct MorphoChainConfig {
    address morpho;
    address bundler3;
    address wrappedNative;
    address atomicSolver;
    address atomicQueue;
    address legacyPredicateProxy;
}

/// @notice Per-vault Morpho market parameters for a Morpho-enabled (loop/unloop) Nest vault.
/// @dev    Keyed by vault symbol under `.markets.<symbol>` in `config/morpho/<chainId>.json`.
///         `collateralToken` is the vault SHARE token; `loanToken` is the borrowed asset (pUSD).
struct MorphoMarketParams {
    address collateralToken;
    address loanToken;
    address oracle;
    address irm;
    uint256 lltv;
    address legacyTeller;
}

struct AccountantParams {
    uint128 totalSharesLastUpdate;
    address payoutAddress;
    uint96 startingExchangeRate;
    uint32 allowedExchangeRateChangeUpper;
    uint32 allowedExchangeRateChangeLower;
    uint32 minimumUpdateDelayInSeconds;
    uint32 managementFee;
}

struct VaultRoles {
    address[] OWNER_ROLE; // role 0 holders (operational Safe(s)) — NOT the contract owner
    address[] PAUSER_ROLE; // role 6 holders
    address[] KEEPER_ROLE;
    address[] UPDATE_EXCHANGE_RATE_ROLE;
    address[] MANAGER_ROLE;
    address[] CAN_SOLVE_ROLE;
    address[] DEPOSITOR_ROLE; // role 8 holders (direct deposit/mint)
}

struct ComplianceV1Config {
    string policyID;
}

struct ComplianceV2Config {
    // Predicate dashboard policy identifier; empty while awaiting project registration.
    string verificationHash;
}

struct VaultComplianceConfig {
    ComplianceV1Config v1;
    ComplianceV2Config v2;
    // Deploy this vault on the shared ComplianceProxy only, even where the chain still runs V1.
    bool v2Only;
}

struct VaultDeployConfig {
    // Contract ownership is separate from RolesAuthority membership.
    address owner;
    string symbol;
    string name;
    uint256 deployChainId;
    string baseAssetSymbol;
    string vaultType;
    VaultContracts contracts;
    CommonContracts common;
    VaultEntry[] vaults;
    VaultEntry[] allVaults;
    AccountantParams accountantParams;
    uint256 minRate;
    VaultComplianceConfig compliance;
    uint256 maxRetryableValue;
    VaultRoles roles;
    uint256[] peers;
}

/// @title ConfigReader
/// @notice Library for reading deployment configuration from JSON files.
/// @dev All JSON paths use per-field reads (not abi.decode) to avoid Foundry's alphabetical ordering requirement.
library ConfigReader {
    using StdJson for string;

    VmSafe private constant VM = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant CCTP_MAX_ALLOWED_FEE_BASIS_POINTS = 1_000;
    uint256 private constant CCTP_FAST_FINALITY_THRESHOLD = 1_000;
    uint256 private constant CCTP_STANDARD_FINALITY_THRESHOLD = 2_000;

    // ─── Common Config ────────────────────────────────────────────────

    function readCommonConfig(uint256 chainId) internal view returns (CommonConfig memory config) {
        string memory json = _readConfigFile("config/common/", chainId);

        config.chainId = json.readUint(".chainId");
        config.name = json.readString(".name");
        config.rpcEnvVar = json.readString(".rpc");
        config.isEvm = json.readBool(".isEvm");

        config.permit2 = json.readAddress(".common.permit2");
        config.createx = json.readAddress(".common.createx");
        config.multisig = json.readAddress(".common.multisig");
    }

    // ─── Compliance Config ────────────────────────────────────────────

    function readComplianceConfig(uint256 chainId) internal view returns (ChainComplianceConfig memory config) {
        string memory json = _readConfigFile("config/compliance/", chainId);
        config.chainId = json.readUint(".chainId");
        require(config.chainId == chainId, "ConfigReader: compliance chain mismatch");
        config.v2Only = _readBoolOr(json, ".v2Only", false);
        config.v1.serviceManager = json.readAddress(".v1.serviceManager");
        config.v1.defaultPolicyID = json.readString(".v1.defaultPolicyID");
        config.v2.apiChain = json.readString(".v2.apiChain");
        config.v2.predicateRegistry = json.readAddress(".v2.predicateRegistry");
    }

    // ─── LayerZero Config ─────────────────────────────────────────────

    function readLZConfig(uint256 chainId) internal view returns (LZConfig memory config) {
        string memory json = _readConfigFile("config/layerzero/", chainId);

        config.chainId = json.readUint(".chainId");
        config.eid = uint32(json.readUint(".eid"));
        config.endpoint = json.readAddress(".endpoint");
        config.sendLib302 = json.readAddress(".sendLib302");
        config.receiveLib302 = json.readAddress(".receiveLib302");
        config.executor = json.readAddress(".executor");
        config.delegate = json.readAddress(".delegate");
    }

    function readDVNs(uint256 sourceChainId, uint256 destChainId) internal view returns (DVNConfig memory dvn) {
        string memory json = _readConfigFile("config/layerzero/", sourceChainId);
        string memory destKey = Strings.toString(destChainId);

        dvn.lz = json.readAddress(string.concat(".dvns.", destKey, ".lz"));
        dvn.nethermind = json.readAddress(string.concat(".dvns.", destKey, ".nethermind"));
        dvn.canary = json.readAddress(string.concat(".dvns.", destKey, ".canary"));
    }

    function readEnforcedOptions(uint256 chainId) internal view returns (EnforcedOptionsConfig memory opts) {
        string memory json = _readConfigFile("config/layerzero/", chainId);

        opts.receiveGas = uint128(json.readUint(".enforcedOptions.receive.gas"));
        opts.receiveMsgValue = uint128(json.readUint(".enforcedOptions.receive.msgValue"));
        opts.sendGas = uint128(json.readUint(".enforcedOptions.send.gas"));
        opts.sendMsgValue = uint128(json.readUint(".enforcedOptions.send.msgValue"));
        opts.composeGas = uint128(json.readUint(".enforcedOptions.compose.gas"));
        opts.composeMsgValue = uint128(json.readUint(".enforcedOptions.compose.msgValue"));
    }

    // ─── CCTP Config ──────────────────────────────────────────────────

    function readCCTPConfig(uint256 chainId) internal view returns (CCTPConfig memory config) {
        string memory json = _readConfigFile("config/cctp/", chainId);
        config = _parseCCTPConfig(json);
    }

    /// @notice Tries to read CCTP config for a chain. Returns false if the config file does not exist.
    function tryReadCCTPConfig(uint256 chainId) internal view returns (bool exists, CCTPConfig memory config) {
        string memory root = VM.projectRoot();
        string memory path = string.concat(root, "/config/cctp/", Strings.toString(chainId), ".json");
        try VM.readFile(path) returns (string memory json) {
            exists = true;
            config = _parseCCTPConfig(json);
        } catch {
            exists = false;
        }
    }

    function _parseCCTPConfig(string memory json) private pure returns (CCTPConfig memory config) {
        config.messageTransmitter = json.readAddress(".messageTransmitter");
        config.tokenMessenger = json.readAddress(".tokenMessenger");
        config.tokenMinter = json.readAddress(".tokenMinter");
        config.domain = uint32(json.readUint(".domain"));
        // Optional reviewed runtime policy; 0 = unconfigured (leave the live relayer alone and warn).
        config.maxFeeBasisPoints = _readUintOr(json, ".maxFeeBasisPoints", 0);
        uint256 finalityThreshold = _readUintOr(json, ".finalityThreshold", 0);
        require(
            config.maxFeeBasisPoints <= CCTP_MAX_ALLOWED_FEE_BASIS_POINTS,
            "ConfigReader: CCTP maxFeeBasisPoints must be 0..1000"
        );
        require(
            finalityThreshold == 0 || finalityThreshold == CCTP_FAST_FINALITY_THRESHOLD
                || finalityThreshold == CCTP_STANDARD_FINALITY_THRESHOLD,
            "ConfigReader: CCTP finalityThreshold must be 1000 or 2000"
        );
        config.finalityThreshold = uint32(finalityThreshold);
    }

    /// @notice Reads the vault-specific ComplianceProxy deployed for `symbol` on `chainId`.
    function readComplianceProxy(uint256 chainId, string memory symbol) internal view returns (address) {
        string memory root = VM.projectRoot();
        string memory path = string.concat(
            root, "/script/deployment-config/compliance/", Strings.toString(chainId), "-", symbol, ".json"
        );
        return VM.readFile(path).readAddress(".complianceProxy");
    }

    /// @notice Like readComplianceProxy but returns false when the config file is missing.
    function tryReadComplianceProxy(uint256 chainId, string memory symbol)
        internal
        view
        returns (bool exists, address complianceProxy)
    {
        string memory root = VM.projectRoot();
        string memory path = string.concat(
            root, "/script/deployment-config/compliance/", Strings.toString(chainId), "-", symbol, ".json"
        );
        try VM.readFile(path) returns (string memory json) {
            exists = true;
            complianceProxy = json.readAddress(".complianceProxy");
        } catch {
            exists = false;
        }
    }

    // ─── Morpho Chain Config ──────────────────────────────────────────

    function readMorphoConfig(uint256 chainId) internal view returns (MorphoChainConfig memory config) {
        string memory json = _readConfigFile("config/morpho/", chainId);

        config.morpho = json.readAddress(".morpho");
        config.bundler3 = json.readAddress(".bundler3");
        config.wrappedNative = json.readAddress(".wrappedNative");
        config.atomicSolver = json.readAddress(".atomicSolver");
        config.atomicQueue = json.readAddress(".atomicQueue");
        config.legacyPredicateProxy = json.readAddress(".legacyPredicateProxy");
    }

    function tryReadMorphoConfig(uint256 chainId) internal view returns (bool exists, MorphoChainConfig memory config) {
        string memory root = VM.projectRoot();
        string memory path = string.concat(root, "/config/morpho/", Strings.toString(chainId), ".json");
        try VM.readFile(path) returns (string memory json) {
            exists = true;
            config.morpho = json.readAddress(".morpho");
            config.bundler3 = json.readAddress(".bundler3");
            config.wrappedNative = json.readAddress(".wrappedNative");
            config.atomicSolver = json.readAddress(".atomicSolver");
            config.atomicQueue = json.readAddress(".atomicQueue");
            config.legacyPredicateProxy = json.readAddress(".legacyPredicateProxy");
        } catch {
            exists = false;
        }
    }

    /// @notice Reads the Morpho market params for `symbol` from `config/morpho/<chainId>.json`.
    /// @dev    Reverts if the vault has no `.markets.<symbol>` entry (i.e. not Morpho-enabled).
    function readMorphoMarket(uint256 chainId, string memory symbol)
        internal
        view
        returns (MorphoMarketParams memory m)
    {
        string memory json = _readConfigFile("config/morpho/", chainId);
        string memory key = string.concat(".markets.", symbol);
        require(VM.keyExistsJson(json, key), string.concat("morpho market not configured for ", symbol));
        m.collateralToken = json.readAddress(string.concat(key, ".collateralToken"));
        m.loanToken = json.readAddress(string.concat(key, ".loanToken"));
        m.oracle = json.readAddress(string.concat(key, ".oracle"));
        m.irm = json.readAddress(string.concat(key, ".irm"));
        m.lltv = json.readUint(string.concat(key, ".lltv"));
        m.legacyTeller = json.readAddress(string.concat(key, ".legacyTeller"));
    }

    // ─── Timelock Config ──────────────────────────────────────────────

    /// @notice Reads the two-tier timelock config for `chainId` from config/timelock/<chainId>.json.
    /// @dev Reverts on missing fields. Every tier carries explicit addresses, salts, delays, and roles.
    function readTimelockConfig(uint256 chainId) internal view returns (TimelockConfig memory config) {
        config = _parseTimelockConfig(_readConfigFile("config/timelock/", chainId));
    }

    /// @notice Like readTimelockConfig but returns false instead of reverting when the file is missing.
    function tryReadTimelockConfig(uint256 chainId) internal view returns (bool exists, TimelockConfig memory config) {
        string memory root = VM.projectRoot();
        string memory path = string.concat(root, "/config/timelock/", Strings.toString(chainId), ".json");
        try VM.readFile(path) returns (string memory json) {
            exists = true;
            config = _parseTimelockConfig(json);
        } catch {
            exists = false;
        }
    }

    function _parseTimelockConfig(string memory json) private pure returns (TimelockConfig memory config) {
        string[] memory names = VM.parseJsonKeys(json, ".");
        require(names.length > 0, "Timelock config: pairs empty");
        config.pairs = new TimelockPairConfig[](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            string memory k = string.concat(".[\"", names[i], "\"]");
            TimelockPairConfig memory st = config.pairs[i];
            st.name = names[i];
            require(bytes(st.name).length > 0, "Timelock config: empty pair name");
            st.admin = _parseTimelockTier(json, string.concat(k, ".admin"));
            st.protocol = _parseTimelockTier(json, string.concat(k, ".protocol"));
        }
    }

    function _parseTimelockTier(string memory json, string memory key)
        private
        pure
        returns (TimelockTierConfig memory tier)
    {
        tier.addr = VM.parseJsonAddress(json, string.concat(key, ".address"));
        tier.salt = VM.parseJsonBytes32(json, string.concat(key, ".salt"));
        tier.delay = VM.parseJsonUint(json, string.concat(key, ".delay"));
        tier.roles.admin = VM.parseJsonAddressArray(json, string.concat(key, ".roles.admin"));
        tier.roles.executor = VM.parseJsonAddressArray(json, string.concat(key, ".roles.executor"));
        tier.roles.proposer = VM.parseJsonAddressArray(json, string.concat(key, ".roles.proposer"));
        tier.roles.canceller = VM.parseJsonAddressArray(json, string.concat(key, ".roles.canceller"));
    }

    function _readUintOr(string memory json, string memory key, uint256 dflt) private pure returns (uint256) {
        try VM.parseJsonUint(json, key) returns (uint256 v) {
            return v;
        } catch {
            return dflt;
        }
    }

    function _readBoolOr(string memory json, string memory key, bool dflt) private pure returns (bool) {
        try VM.parseJsonBool(json, key) returns (bool v) {
            return v;
        } catch {
            return dflt;
        }
    }

    // ─── Asset Config ─────────────────────────────────────────────────

    function readAssetAddress(uint256 chainId, string memory symbol) internal view returns (address) {
        string memory json = _readConfigFile("config/assets/", chainId);
        return json.readAddress(string.concat(".", symbol));
    }

    // ─── Vault Deploy Config ──────────────────────────────────────────

    function readVaultConfig(string memory symbol) internal view returns (VaultDeployConfig memory config) {
        string memory root = VM.projectRoot();
        string memory path = string.concat(root, "/script/deployment-config/vaults/", symbol, ".json");
        config = _parseVaultConfig(VM.readFile(path));
    }

    /// @notice Reads the deployment output config written by DeployAndSetup.
    ///         Zeros the CCTP relayer on chains without a CCTP config file.
    function readOutputConfig(uint256 chainId, string memory symbol)
        internal
        view
        returns (VaultDeployConfig memory config)
    {
        string memory root = VM.projectRoot();
        string memory path =
            string.concat(root, "/script/output/", symbol, "/", Strings.toString(chainId), "-", symbol, ".json");
        config = _parseVaultConfig(VM.readFile(path));
        (bool hasCCTP,) = tryReadCCTPConfig(chainId);
        if (!hasCCTP) config.common.cctpRelayer = address(0);
    }

    /// @notice Like readOutputConfig but returns false instead of reverting when the file is missing.
    function tryReadOutputConfig(uint256 chainId, string memory symbol)
        internal
        view
        returns (bool exists, VaultDeployConfig memory config)
    {
        string memory root = VM.projectRoot();
        string memory path =
            string.concat(root, "/script/output/", symbol, "/", Strings.toString(chainId), "-", symbol, ".json");
        try VM.readFile(path) returns (string memory json) {
            exists = true;
            config = _parseVaultConfig(json);
            (bool hasCCTP,) = tryReadCCTPConfig(chainId);
            if (!hasCCTP) config.common.cctpRelayer = address(0);
        } catch {
            exists = false;
        }
    }

    function _parseVaultConfig(string memory json) private view returns (VaultDeployConfig memory config) {
        config.symbol = json.readString(".symbol");
        config.name = json.readString(".name");
        config.owner = readOwner(json);
        // deployChainId is optional in input configs (set via CHAIN_ID env var),
        // but present in output configs for backwards compatibility.
        try VM.parseJsonUint(json, ".deployChainId") returns (uint256 id) {
            config.deployChainId = id;
        } catch {}
        config.baseAssetSymbol = json.readString(".baseAssetSymbol");
        config.vaultType = json.readString(".vaultType");

        config.contracts = _readContracts(json);
        config.common = _readCommon(json);
        config.vaults = _readVaults(json);
        // allVaults mirrors the unfiltered vaults list. resolveConfigForChain replaces
        // config.vaults with a filtered array, which leaves allVaults pointing at the
        // original memory array.
        config.allVaults = config.vaults;
        config.accountantParams = _readAccountantParams(json);

        config.minRate = json.readUint(".vaultParams.minRate");
        if (VM.keyExistsJson(json, ".compliance")) {
            config.compliance.v1.policyID = json.readString(".compliance.v1.policyID");
            config.compliance.v2.verificationHash = json.readString(".compliance.v2.verificationHash");
            config.compliance.v2Only = _readBoolOr(json, ".compliance.v2Only", false);
        } else {
            // Deployment outputs written before the versioned compliance schema remain readable.
            config.compliance.v1.policyID = json.readString(".predicateParams.policyID");
        }
        config.maxRetryableValue = json.readUint(".composerParams.maxRetryableValue");

        config.roles = _readRoles(json);
        config.peers = json.readUintArray(".peers");
    }

    function _readContracts(string memory json) private pure returns (VaultContracts memory c) {
        c.share = _tryReadAddress(json, ".contracts.share");
        c.accountant = _tryReadAddress(json, ".contracts.accountant");
        c.rolesAuthority = _tryReadAddress(json, ".contracts.rolesAuthority");
    }

    function _readCommon(string memory json) private view returns (CommonContracts memory c) {
        // Try to read from the canonical common config first; fall back to per-symbol .common block.
        uint256 chainId;
        try VM.parseJsonUint(json, ".deployChainId") returns (uint256 id) {
            chainId = id;
        } catch {
            // No chainId in this JSON — fall back to inline .common block
            return _readCommonFromJson(json);
        }

        try VM.readFile(_commonConfigPath(chainId)) returns (string memory commonJson) {
            return _readCommonFromJson(commonJson);
        } catch {
            return _readCommonFromJson(json);
        }
    }

    /// @notice Reads the canonical common proxy config for a chain.
    ///         Zeros the CCTP relayer on chains without a CCTP config file.
    function readCommonProxyConfig(uint256 chainId) internal view returns (CommonContracts memory c) {
        string memory json = VM.readFile(_commonConfigPath(chainId));
        c = _readCommonFromJson(json);
        (bool hasCCTP,) = tryReadCCTPConfig(chainId);
        if (!hasCCTP) c.cctpRelayer = address(0);
    }

    function _commonConfigPath(uint256 chainId) private view returns (string memory) {
        string memory root = VM.projectRoot();
        return string.concat(root, "/script/deployment-config/common/", Strings.toString(chainId), ".json");
    }

    function _readCommonFromJson(string memory json) private view returns (CommonContracts memory c) {
        if (VM.keyExistsJson(json, ".common")) {
            // Nested .common.* format (per-symbol vault/output files)
            c.predicateProxy = _tryReadAddress(json, ".common.predicateProxy");
            c.complianceProxy = _tryReadAddress(json, ".common.complianceProxy");
            c.operatorRegistry = _tryReadAddress(json, ".common.operatorRegistry");
            c.redeemOperator = _tryReadAddress(json, ".common.redeemOperator");
            c.cctpRelayer = _tryReadAddress(json, ".common.cctpRelayer");
            c.seizer = _tryReadAddress(json, ".common.seizer");
            c.blacklistHook = _tryReadAddress(json, ".common.blacklistHook");
            c.commonRolesAuthority = _tryReadAddress(json, ".common.commonRolesAuthority");
            c.nestAdapter = _tryReadAddress(json, ".common.nestAdapter");
            c.nestBundler = _tryReadAddress(json, ".common.nestBundler");
            c.nestUnlooper = _tryReadAddress(json, ".common.nestUnlooper");
            c.protocolTimelock = _tryReadAddress(json, ".common.protocolTimelock");
            c.adminTimelock = _tryReadAddress(json, ".common.adminTimelock");
        } else {
            // Flat format (common config file)
            c.predicateProxy = _tryReadAddress(json, ".predicateProxy");
            c.complianceProxy = _tryReadAddress(json, ".complianceProxy");
            c.operatorRegistry = _tryReadAddress(json, ".operatorRegistry");
            c.redeemOperator = _tryReadAddress(json, ".redeemOperator");
            c.cctpRelayer = _tryReadAddress(json, ".cctpRelayer");
            c.seizer = _tryReadAddress(json, ".seizer");
            c.blacklistHook = _tryReadAddress(json, ".blacklistHook");
            c.commonRolesAuthority = _tryReadAddress(json, ".commonRolesAuthority");
            c.nestAdapter = _tryReadAddress(json, ".nestAdapter");
            c.nestBundler = _tryReadAddress(json, ".nestBundler");
            c.nestUnlooper = _tryReadAddress(json, ".nestUnlooper");
            c.protocolTimelock = _tryReadAddress(json, ".protocolTimelock");
            c.adminTimelock = _tryReadAddress(json, ".adminTimelock");
        }
    }

    function _readVaults(string memory json) private pure returns (VaultEntry[] memory entries) {
        bytes memory rawVaults = json.parseRaw(".contracts.vaults");
        uint256 length;
        assembly {
            let dataStart := add(rawVaults, 32)
            let offset := mload(dataStart)
            length := mload(add(dataStart, offset))
        }
        entries = new VaultEntry[](length);
        for (uint256 i = 0; i < length; i++) {
            string memory prefix = string.concat(".contracts.vaults[", Strings.toString(i), "]");
            entries[i].assetSymbol = json.readString(string.concat(prefix, ".assetSymbol"));
            try VM.parseJsonUintArray(json, string.concat(prefix, ".chains")) returns (uint256[] memory ch) {
                entries[i].chains = ch;
            } catch {}
            entries[i].addr = _tryReadAddress(json, string.concat(prefix, ".address"));
            entries[i].isPegged = json.readBool(string.concat(prefix, ".isPegged"));
            entries[i].rateProvider = _tryReadAddress(json, string.concat(prefix, ".rateProvider"));
            entries[i].composer = _tryReadAddress(json, string.concat(prefix, ".composer"));
            entries[i].legacyTeller = _tryReadAddress(json, string.concat(prefix, ".legacyTeller"));
        }
    }

    function _readAccountantParams(string memory json) private pure returns (AccountantParams memory a) {
        a.totalSharesLastUpdate = uint128(json.readUint(".accountantParams.totalSharesLastUpdate"));
        a.payoutAddress = json.readAddress(".accountantParams.payoutAddress");
        a.startingExchangeRate = uint96(json.readUint(".accountantParams.startingExchangeRate"));
        a.allowedExchangeRateChangeUpper = uint32(json.readUint(".accountantParams.allowedExchangeRateChangeUpper"));
        a.allowedExchangeRateChangeLower = uint32(json.readUint(".accountantParams.allowedExchangeRateChangeLower"));
        a.minimumUpdateDelayInSeconds = uint32(json.readUint(".accountantParams.minimumUpdateDelayInSeconds"));
        a.managementFee = uint32(json.readUint(".accountantParams.managementFee"));
    }

    function _readRoles(string memory json) private pure returns (VaultRoles memory r) {
        r.OWNER_ROLE = _tryReadAddressArray(json, ".roles.OWNER_ROLE");
        r.PAUSER_ROLE = _tryReadAddressArray(json, ".roles.PAUSER_ROLE");
        r.KEEPER_ROLE = json.readAddressArray(".roles.KEEPER_ROLE");
        r.UPDATE_EXCHANGE_RATE_ROLE = json.readAddressArray(".roles.UPDATE_EXCHANGE_RATE_ROLE");
        r.MANAGER_ROLE = json.readAddressArray(".roles.MANAGER_ROLE");
        r.CAN_SOLVE_ROLE = _tryReadAddressArray(json, ".roles.CAN_SOLVE_ROLE");
        r.DEPOSITOR_ROLE = _tryReadAddressArray(json, ".roles.DEPOSITOR_ROLE");
    }

    function _tryReadAddressArray(string memory json, string memory key) private pure returns (address[] memory) {
        try VM.parseJsonAddressArray(json, key) returns (address[] memory arr) {
            return arr;
        } catch {
            return new address[](0);
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    /// @dev Sentinel value meaning "do not deploy and do not configure this contract".
    address internal constant DEAD_ADDRESS = address(0xdead);

    /// @notice Returns true when the slot is empty and a fresh deployment is needed.
    function shouldDeploy(address addr) internal pure returns (bool) {
        return addr == address(0);
    }

    /// @notice Returns true when the address was explicitly disabled (set to 0x…dead).
    function isDisabled(address addr) internal pure returns (bool) {
        return addr == DEAD_ADDRESS;
    }

    /// @notice Returns true when the address points to a real, deployed contract.
    ///         False for address(0) (not yet deployed) and DEAD_ADDRESS (disabled).
    function isActive(address addr) internal pure returns (bool) {
        return addr != address(0) && addr != DEAD_ADDRESS;
    }

    /// @notice Every vault config must explicitly name a non-zero top-level contract owner.
    function readOwner(string memory json) internal view returns (address owner) {
        require(VM.keyExistsJson(json, ".owner"), "ConfigReader: owner required");
        owner = VM.parseJsonAddress(json, ".owner");
        require(owner != address(0), "ConfigReader: owner required");
    }

    /// @notice Returns the explicit owner; never infers ownership from common config or role membership.
    function resolvedOwner(VaultDeployConfig memory config) internal pure returns (address owner) {
        owner = config.owner;
        require(owner != address(0), "ConfigReader: owner required");
    }

    function isOFT(string memory vaultType) internal pure returns (bool) {
        return keccak256(bytes(vaultType)) == keccak256(bytes("NestVaultOFT"));
    }

    // ─── Accountant Type Resolution ───────────────────────────────────

    /// @dev Default hub chain when `.hubChainId` is not set in the vault config.
    uint256 internal constant DEFAULT_HUB_CHAIN_ID = 98866;

    /// @notice Reads the configured accountant type from the raw vault JSON.
    ///         Returns "NestAccountant" when the field is absent (legacy default).
    function readAccountantTypeRaw(string memory rawJson) internal pure returns (string memory) {
        try VM.parseJsonString(rawJson, ".accountantType") returns (string memory t) {
            if (bytes(t).length != 0) return t;
        } catch {}
        return "NestAccountant";
    }

    /// @notice Reads the configured hub chain id from the raw vault JSON.
    ///         Defaults to Plume mainnet (98866) when absent.
    function readHubChainId(string memory rawJson) internal pure returns (uint256) {
        try VM.parseJsonUint(rawJson, ".hubChainId") returns (uint256 id) {
            if (id != 0) return id;
        } catch {}
        return DEFAULT_HUB_CHAIN_ID;
    }

    /// @notice Resolves the accountant impl to use for `chainId` based on the configured
    ///         `accountantType` and `hubChainId` in the raw vault JSON.
    ///         - "NestAccountant"      → legacy impl on every chain.
    ///         - "NestHubAccountant"   → Hub on `hubChainId`, Spoke elsewhere.
    ///         - "NestSpokeAccountant" → Spoke on every chain.
    function effectiveAccountantType(string memory rawJson, uint256 chainId) internal pure returns (string memory) {
        bytes32 h = keccak256(bytes(readAccountantTypeRaw(rawJson)));
        if (h == keccak256(bytes("NestHubAccountant"))) {
            return chainId == readHubChainId(rawJson) ? "NestHubAccountant" : "NestSpokeAccountant";
        }
        if (h == keccak256(bytes("NestSpokeAccountant"))) return "NestSpokeAccountant";
        return "NestAccountant";
    }

    /// @notice Resolves a `commonOverrides` address for `field` from a raw vault-config JSON,
    ///         preferring the per-chain key (`.commonOverrides.<chainId>.<field>`) over the
    ///         top-level key (`.commonOverrides.<field>`), and falling back to `fallback_`
    ///         when neither is present. `0x0…0` disables that common contract for wiring checks
    ///         (DeployAndSetup still deploys it if missing; `0xdead` hard-disables). Shared by
    ///         deploy/setup (BaseConfigScript) and fork tests so both
    ///         see identical effective addresses.
    function effectiveCommonAddress(string memory rawVaultJson, string memory field, uint256 chainId, address fallback_)
        internal
        pure
        returns (address)
    {
        try VM.parseJsonAddress(
            rawVaultJson, string.concat(".commonOverrides.", Strings.toString(chainId), ".", field)
        ) returns (
            address a
        ) {
            return a;
        } catch {}
        try VM.parseJsonAddress(rawVaultJson, string.concat(".commonOverrides.", field)) returns (address a) {
            return a;
        } catch {}
        return fallback_;
    }

    function resolveRPC(CommonConfig memory config) internal view returns (string memory) {
        return VM.envString(config.rpcEnvVar);
    }

    /// @notice Returns all vault addresses from vault entries.
    function getVaultAddresses(VaultDeployConfig memory config) internal pure returns (address[] memory) {
        address[] memory addrs = new address[](config.vaults.length);
        for (uint256 i = 0; i < config.vaults.length; i++) {
            addrs[i] = config.vaults[i].addr;
        }
        return addrs;
    }

    /// @notice Returns all non-zero composer addresses from vault entries.
    function getComposerAddresses(VaultDeployConfig memory config) internal pure returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < config.vaults.length; i++) {
            if (config.vaults[i].composer != address(0)) count++;
        }
        address[] memory composers = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < config.vaults.length; i++) {
            if (config.vaults[i].composer != address(0)) {
                composers[idx++] = config.vaults[i].composer;
            }
        }
        return composers;
    }

    /// @notice Reads contract addresses from a prior deployment output in script/deployment-config/revoke/.
    ///         Only extracts addresses needed for role revocation — does not parse roles or params.
    ///         Returns false if the file does not exist.
    function readOldOutput(uint256 chainId, string memory symbol)
        internal
        view
        returns (
            bool exists,
            VaultContracts memory contracts,
            CommonContracts memory common,
            VaultEntry[] memory vaults
        )
    {
        string memory root = VM.projectRoot();
        string memory path =
            string.concat(root, "/script/deployment-config/revoke/", Strings.toString(chainId), "-", symbol, ".json");

        try VM.readFile(path) returns (string memory json) {
            exists = true;
            contracts = _readContracts(json);
            common = _readCommon(json);
            vaults = _readVaults(json);
        } catch {
            exists = false;
        }
    }

    // ─── Chain Resolution ─────────────────────────────────────────────

    /// @notice Filters vault entries to only those whose `chains` array includes `chainId`.
    ///         Entries with an empty `chains` array are always included (backwards-compatible).
    function filterVaultsForChain(VaultEntry[] memory vaults, uint256 chainId)
        internal
        pure
        returns (VaultEntry[] memory)
    {
        uint256 count;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (_vaultIncludesChain(vaults[i], chainId)) count++;
        }
        VaultEntry[] memory filtered = new VaultEntry[](count);
        uint256 idx;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (_vaultIncludesChain(vaults[i], chainId)) {
                filtered[idx++] = vaults[i];
            }
        }
        return filtered;
    }

    function _vaultIncludesChain(VaultEntry memory ve, uint256 chainId) private pure returns (bool) {
        if (ve.chains.length == 0) return true;
        for (uint256 i = 0; i < ve.chains.length; i++) {
            if (ve.chains[i] == chainId) return true;
        }
        return false;
    }

    /// @notice Applies all chain-specific config resolution in one place:
    ///         sets deployChainId, filters vaults, and zeros CCTP relayer on non-CCTP chains.
    function resolveConfigForChain(VaultDeployConfig memory config, uint256 chainId)
        internal
        view
        returns (VaultDeployConfig memory)
    {
        config.deployChainId = chainId;
        config.vaults = filterVaultsForChain(config.vaults, chainId);
        // Zero CCTP relayer on non-CCTP chains
        (bool hasCCTP,) = tryReadCCTPConfig(chainId);
        if (!hasCCTP) config.common.cctpRelayer = address(0);
        return config;
    }

    // ─── Internal Helpers ────────────────────────────────────────────

    function _readConfigFile(string memory prefix, uint256 chainId) private view returns (string memory) {
        string memory root = VM.projectRoot();
        string memory path = string.concat(root, "/", prefix, Strings.toString(chainId), ".json");
        return VM.readFile(path);
    }

    function _tryReadBytes32(string memory json, string memory key) private pure returns (bytes32) {
        try VM.parseJsonBytes32(json, key) returns (bytes32 v) {
            return v;
        } catch {
            return bytes32(0);
        }
    }

    function _tryReadAddress(string memory json, string memory key) private pure returns (address) {
        try VM.parseJsonAddress(json, key) returns (address addr) {
            return addr;
        } catch {
            return address(0);
        }
    }
}
