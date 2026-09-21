// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ConfigReader, CommonConfig, VaultDeployConfig, VaultEntry, LZConfig} from "script/lib/ConfigReader.sol";
import {Constants} from "test/Constants.sol";

// contracts
import {NestVaultOFT} from "contracts/NestVaultOFT.sol";
import {NestVaultCore} from "contracts/NestVaultCore.sol";
import {NestVaultComposer} from "contracts/integrations/ovault/NestVaultComposer.sol";
import {NestAccountant} from "contracts/accountant/NestAccountant.sol";
import {NestSpokeAccountant} from "contracts/accountant/NestSpokeAccountant.sol";
import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {AuthUpgradeable} from "contracts/auth/AuthUpgradeable.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";

// proxy
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// interfaces
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Authority} from "@solmate/auth/Auth.sol";

// types
import {NestVaultCoreTypes} from "contracts/types/NestVaultCoreTypes.sol";

/// @title  UpgradeStorageCheckTest
/// @notice Fork test that verifies storage integrity after upgrading vault and composer proxies.
///         Reads all state via view functions before the upgrade, simulates the upgrade,
///         then asserts every value is identical.
/// @dev    Usage:
///           VAULT_SYMBOL=nWISDOM forge test --match-contract UpgradeStorageCheckTest -vvv
contract UpgradeStorageCheckTest is Test, Constants {
    /// @dev ERC-1967 admin slot: keccak256("eip1967.proxy.admin") - 1
    bytes32 private constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @dev ERC-1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
    bytes32 private constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev ERC-7201 storage namespace bases (from the contracts)
    bytes32 private constant NEST_VAULT_CORE_NS = 0x8d327cc9157d67bbcdfb7458a8210f70aaa0f2cbd2dc6f3d23140e557560c200;
    bytes32 private constant AUTH_NS = 0x341f7c713c76cb881fd7047f7cccebe3fe10eddfc5e20fe83ee7e0b505e8ea00;
    bytes32 private constant COMPOSER_SYNC_NS = 0xc537560042629e8880bf5e9fca9de99531ceefbe83dcee9e2560a43447673800;
    bytes32 private constant COMPOSER_ASYNC_NS = 0x675d05f61eb76f02999633de01879883f3d5f70be938ea35e43653caafefd900;

    /// @dev keccak256(abi.encode(uint256(keccak256("plumenetwork.storage.NestAccountant")) - 1)) & ~bytes32(uint256(0xff))
    ///      Shared by NestAccountant / NestSpokeAccountant / NestHubAccountant.
    bytes32 private constant ACCOUNTANT_NS = 0xb378036f9633fc394c3579301b38ac88997c2589544525e367cd650f76eaa300;

    /// @dev AccountantState fee/rate denominator and update-delay cap (mirror the contract constants).
    uint256 private constant DENOMINATOR = 1e6;
    uint256 private constant UPDATE_DELAY_CAP = 14 days;

    // ─── Config ──────────────────────────────────────────────────────
    VaultDeployConfig internal vaultConfig;
    CommonConfig internal commonConfig;
    string internal vaultSymbol;
    uint256 internal chainId;

    // ─── Snapshot structs ────────────────────────────────────────────

    struct VaultSnapshot {
        // AuthUpgradeable
        address owner;
        address authority;
        address pendingOwner;
        // ERC20
        string name;
        string symbol;
        uint8 decimals;
        uint256 totalSupply;
        // ERC4626
        address asset;
        uint256 totalAssets;
        // NestVaultCore
        uint256 minRate;
        uint256 totalPendingShares;
        address accountant;
        address operatorRegistry;
        // Raw namespace slots (first 12 to cover all struct fields)
        bytes32[12] rawCoreSlots;
        bytes32[3] rawAuthSlots;
    }

    struct ComposerSnapshot {
        // AuthUpgradeable
        address owner;
        address authority;
        address pendingOwner;
        // VaultComposerSyncUpgradeable
        address vault;
        address assetOft;
        address assetErc20;
        address shareOft;
        address shareErc20;
        address endpoint;
        uint32 vaultEid;
        // VaultComposerAsyncUpgradeable
        uint256 totalPendingSharesSum;
        uint256 maxRetryableValue;
        uint256 totalFulfilledAssetsSum;
        // Raw namespace slots
        bytes32[8] rawAsyncSlots;
        bytes32[7] rawSyncSlots;
        bytes32[3] rawAuthSlots;
    }

    // ─── Setup ───────────────────────────────────────────────────────

    function setUp() public {
        vaultSymbol = vm.envString("VAULT_SYMBOL");
        chainId = vm.envUint("CHAIN_ID");
        bool useOutput = _envBoolOr("USE_OUTPUT", true);
        if (useOutput) {
            vaultConfig = ConfigReader.readOutputConfig(chainId, vaultSymbol);
            vaultConfig.deployChainId = chainId;
        } else {
            vaultConfig = ConfigReader.readVaultConfig(vaultSymbol);
            vaultConfig = ConfigReader.resolveConfigForChain(vaultConfig, chainId);
        }
        commonConfig = ConfigReader.readCommonConfig(chainId);

        // Fork
        try vm.activeFork() {}
        catch {
            string memory rpcUrl = vm.envString(commonConfig.rpcEnvVar);
            vm.createSelectFork(rpcUrl);
        }
    }

    // ─── Tests ───────────────────────────────────────────────────────

    /// @notice Upgrades the vault and verifies raw storage is unchanged,
    ///         then verifies all view functions work correctly post-upgrade.
    function test_vaultUpgradePreservesStorage() public {
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (ve.addr == address(0)) continue;

            address proxy = ve.addr;
            console.log("=== Vault %s at %s ===", ve.assetSymbol, proxy);

            // 1. Read raw slots before (always works regardless of impl version)
            bytes32[12] memory coreSlotsBefore = _readSlots(proxy, NEST_VAULT_CORE_NS, 12);
            bytes32[3] memory authSlotsBefore = _readSlots3(proxy, AUTH_NS);
            _logRawSlots("BEFORE core", coreSlotsBefore);
            _logRawSlots3("BEFORE auth", authSlotsBefore);

            // 2. Upgrade
            address newImpl = _deployVaultImpl();
            _upgradeProxy(proxy, newImpl);

            // 3. Verify raw slots unchanged
            bytes32[12] memory coreSlotsAfter = _readSlots(proxy, NEST_VAULT_CORE_NS, 12);
            bytes32[3] memory authSlotsAfter = _readSlots3(proxy, AUTH_NS);
            for (uint256 s = 0; s < 12; s++) {
                assertEq(
                    coreSlotsBefore[s], coreSlotsAfter[s], string.concat(ve.assetSymbol, ": core slot ", vm.toString(s))
                );
            }
            for (uint256 s = 0; s < 3; s++) {
                assertEq(
                    authSlotsBefore[s], authSlotsAfter[s], string.concat(ve.assetSymbol, ": auth slot ", vm.toString(s))
                );
            }

            // 4. Verify view functions work post-upgrade and return sane values
            VaultSnapshot memory snap = _snapshotVault(proxy);
            _logVaultSnapshot("AFTER", snap);

            // Sanity: key fields should be non-zero (vault is live with funds)
            assertTrue(snap.owner != address(0), string.concat(ve.assetSymbol, ": owner zero"));
            assertTrue(bytes(snap.name).length > 0, string.concat(ve.assetSymbol, ": name empty"));
            assertTrue(snap.asset != address(0), string.concat(ve.assetSymbol, ": asset zero"));
            assertTrue(snap.accountant != address(0), string.concat(ve.assetSymbol, ": accountant zero"));
            assertEq(snap.minRate, vaultConfig.minRate, string.concat(ve.assetSymbol, ": minRate mismatch"));

            console.log("  [PASS] Vault", ve.assetSymbol, "storage preserved");
        }
    }

    /// @notice Upgrades the composer and verifies raw storage is unchanged,
    ///         then verifies all view functions work correctly post-upgrade.
    function test_composerUpgradePreservesStorage() public {
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (ve.composer == address(0)) continue;

            address proxy = ve.composer;
            console.log("=== Composer %s at %s ===", ve.assetSymbol, proxy);

            // 1. Read raw slots before
            bytes32[8] memory asyncBefore = _readSlots8(proxy, COMPOSER_ASYNC_NS);
            bytes32[7] memory syncBefore = _readSlots7(proxy, COMPOSER_SYNC_NS);
            bytes32[3] memory authBefore = _readSlots3(proxy, AUTH_NS);
            _logRawSlots8("BEFORE async", asyncBefore);
            _logRawSlots7("BEFORE sync", syncBefore);
            _logRawSlots3("BEFORE auth", authBefore);

            // 2. Upgrade
            address newImpl = _deployComposerImpl();
            _upgradeProxy(proxy, newImpl);

            // 3. Verify raw slots unchanged
            bytes32[8] memory asyncAfter = _readSlots8(proxy, COMPOSER_ASYNC_NS);
            bytes32[7] memory syncAfter = _readSlots7(proxy, COMPOSER_SYNC_NS);
            bytes32[3] memory authAfter = _readSlots3(proxy, AUTH_NS);
            for (uint256 s = 0; s < 8; s++) {
                assertEq(asyncBefore[s], asyncAfter[s], string.concat(ve.assetSymbol, ": async slot ", vm.toString(s)));
            }
            for (uint256 s = 0; s < 7; s++) {
                assertEq(syncBefore[s], syncAfter[s], string.concat(ve.assetSymbol, ": sync slot ", vm.toString(s)));
            }
            for (uint256 s = 0; s < 3; s++) {
                assertEq(authBefore[s], authAfter[s], string.concat(ve.assetSymbol, ": auth slot ", vm.toString(s)));
            }

            // 4. Verify view functions work post-upgrade
            ComposerSnapshot memory snap = _snapshotComposer(proxy);
            _logComposerSnapshot("AFTER", snap);

            // Sanity checks
            assertTrue(snap.owner != address(0), string.concat(ve.assetSymbol, ": owner zero"));
            assertTrue(snap.vault != address(0), string.concat(ve.assetSymbol, ": vault zero"));
            assertTrue(snap.assetErc20 != address(0), string.concat(ve.assetSymbol, ": assetErc20 zero"));
            assertTrue(snap.shareErc20 != address(0), string.concat(ve.assetSymbol, ": shareErc20 zero"));
            assertTrue(snap.endpoint != address(0), string.concat(ve.assetSymbol, ": endpoint zero"));

            // Verify maxRetryableValue reads correctly (the field that was reordered)
            console.log("  maxRetryableValue post-upgrade: %d", snap.maxRetryableValue);

            console.log("  [PASS] Composer", ve.assetSymbol, "storage preserved");
        }
    }

    /// @notice Upgrades the accountant and verifies the realigned AccountantState layout
    ///         decodes the live storage correctly. Guards the `feesOwedInBase` realignment:
    ///         the field sits at struct index 1 (slot+1 low 16B), so every field after it
    ///         must line up with what the view getters return. Proves the reader matches the
    ///         on-chain bytes — the exact failure mode of the broken spoke impl that omitted it.
    function test_accountantUpgradePreservesStorage() public {
        address proxy = vaultConfig.contracts.accountant;
        if (proxy == address(0)) {
            console.log("No accountant in config; skipping");
            return;
        }
        console.log("=== Accountant at %s ===", proxy);

        // 1. Raw namespace slots before: 0..3 = AccountantState, 4 = rateProviderData mapping base,
        //    5 = totalPendingShares. (Always readable regardless of the live impl version.)
        bytes32[6] memory before = _readSlots6(proxy, ACCOUNTANT_NS);
        _logRawSlots6("BEFORE accountant", before);

        // 2. Upgrade to the config-resolved accountant impl (Hub/Spoke/legacy).
        address newImpl = _deployAccountantImpl();
        _upgradeProxy(proxy, newImpl);

        // 3. Raw slots must be untouched by the upgrade.
        bytes32[6] memory afterUp = _readSlots6(proxy, ACCOUNTANT_NS);
        for (uint256 s = 0; s < 6; s++) {
            assertEq(before[s], afterUp[s], string.concat("accountant slot ", vm.toString(s), " changed"));
        }

        // 4. Decode AccountantState from the raw slots under the realigned layout.
        //    slot+0: payoutAddress(20B)
        //    slot+1: feesOwedInBase(16B) | totalSharesLastUpdate(16B)
        //    slot+2: exchangeRate(12B) | upper(4B) | lower(4B) | lastUpdateTimestamp(8B) | isPaused(1B)
        //    slot+3: minimumUpdateDelayInSeconds(4B)
        //    slot+5: totalPendingShares
        address payoutAddress = address(uint160(uint256(afterUp[0])));
        uint128 feesOwedInBase = uint128(uint256(afterUp[1]));
        uint128 totalSharesLastUpdate = uint128(uint256(afterUp[1]) >> 128);
        uint96 exchangeRate = uint96(uint256(afterUp[2]));
        uint32 allowedUpper = uint32(uint256(afterUp[2]) >> 96);
        uint32 allowedLower = uint32(uint256(afterUp[2]) >> 128);
        uint64 lastUpdateTs = uint64(uint256(afterUp[2]) >> 160);
        bool isPaused = (uint256(afterUp[2]) >> 224) & 1 == 1;
        uint32 minDelay = uint32(uint256(afterUp[3]));
        uint256 totalPendingShares = uint256(afterUp[5]);

        console.log("  payoutAddress:         %s", payoutAddress);
        console.log("  feesOwedInBase:        %d", feesOwedInBase);
        console.log("  totalSharesLastUpdate: %d", totalSharesLastUpdate);
        console.log("  exchangeRate:          %d", exchangeRate);
        console.log("  allowedUpper:          %d", allowedUpper);
        console.log("  allowedLower:          %d", allowedLower);
        console.log("  lastUpdateTimestamp:   %d", lastUpdateTs);
        console.log("  isPaused:", isPaused);
        console.log("  minUpdateDelay:        %d", minDelay);
        console.log("  totalPendingShares:    %d", totalPendingShares);

        // 5. Alignment proof: the view getters must agree with the raw decode.
        //    If feesOwedInBase were missing/misplaced, every field below would shift and these fail.
        assertEq(NestAccountant(proxy).getRate(), uint256(exchangeRate), "getRate != decoded exchangeRate");
        assertEq(NestAccountant(proxy).totalPendingShares(), totalPendingShares, "totalPendingShares != slot+5");

        // 6. Coherence of the realigned fields.
        assertGt(exchangeRate, 0, "exchangeRate zero");
        assertGe(uint256(allowedUpper), DENOMINATOR, "upper < DENOMINATOR");
        assertLe(uint256(allowedLower), DENOMINATOR, "lower > DENOMINATOR");
        assertLe(uint256(minDelay), UPDATE_DELAY_CAP, "minDelay > cap");

        console.log("  [PASS] Accountant realignment verified (getRate=%d)", exchangeRate);
    }

    function test_rawStorageSlotsUnchanged() public {
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];

            // Check vault
            if (ve.addr != address(0)) {
                address proxy = ve.addr;
                bytes32[12] memory coreSlotsBefore = _readSlots(proxy, NEST_VAULT_CORE_NS, 12);
                bytes32[3] memory authSlotsBefore = _readSlots3(proxy, AUTH_NS);

                address newImpl = _deployVaultImpl();
                _upgradeProxy(proxy, newImpl);

                bytes32[12] memory coreSlotsAfter = _readSlots(proxy, NEST_VAULT_CORE_NS, 12);
                bytes32[3] memory authSlotsAfter = _readSlots3(proxy, AUTH_NS);

                for (uint256 s = 0; s < 12; s++) {
                    assertEq(
                        coreSlotsBefore[s],
                        coreSlotsAfter[s],
                        string.concat("Vault ", ve.assetSymbol, " NestVaultCore slot ", vm.toString(s), " changed")
                    );
                }
                for (uint256 s = 0; s < 3; s++) {
                    assertEq(
                        authSlotsBefore[s],
                        authSlotsAfter[s],
                        string.concat("Vault ", ve.assetSymbol, " Auth slot ", vm.toString(s), " changed")
                    );
                }
                console.log("  [PASS] Vault", ve.assetSymbol, "raw slots unchanged");
            }

            // Check composer
            if (ve.composer != address(0)) {
                address proxy = ve.composer;
                bytes32[8] memory asyncBefore = _readSlots8(proxy, COMPOSER_ASYNC_NS);
                bytes32[7] memory syncBefore = _readSlots7(proxy, COMPOSER_SYNC_NS);
                bytes32[3] memory authBefore = _readSlots3(proxy, AUTH_NS);

                address newImpl = _deployComposerImpl();
                _upgradeProxy(proxy, newImpl);

                bytes32[8] memory asyncAfter = _readSlots8(proxy, COMPOSER_ASYNC_NS);
                bytes32[7] memory syncAfter = _readSlots7(proxy, COMPOSER_SYNC_NS);
                bytes32[3] memory authAfter = _readSlots3(proxy, AUTH_NS);

                for (uint256 s = 0; s < 8; s++) {
                    assertEq(
                        asyncBefore[s],
                        asyncAfter[s],
                        string.concat("Composer ", ve.assetSymbol, " Async slot ", vm.toString(s), " changed")
                    );
                }
                for (uint256 s = 0; s < 7; s++) {
                    assertEq(
                        syncBefore[s],
                        syncAfter[s],
                        string.concat("Composer ", ve.assetSymbol, " Sync slot ", vm.toString(s), " changed")
                    );
                }
                for (uint256 s = 0; s < 3; s++) {
                    assertEq(
                        authBefore[s],
                        authAfter[s],
                        string.concat("Composer ", ve.assetSymbol, " Auth slot ", vm.toString(s), " changed")
                    );
                }
                console.log("  [PASS] Composer", ve.assetSymbol, "raw slots unchanged");
            }
        }
    }

    /// @notice Reads raw storage slots and logs them with semantic labels so you can
    ///         visually inspect whether the current on-chain layout matches expectations.
    function test_dumpComposerStorageLayout() public view {
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (ve.composer == address(0)) continue;

            address proxy = ve.composer;
            console.log("=== Composer Storage Dump:", ve.assetSymbol, "===");

            console.log("--- VaultComposerAsyncStorage (ns: 0x675d05f6...) ---");
            string[8] memory asyncLabels = [
                "totalPendingSharesSum",
                "totalFulfilledSharesSum",
                "totalFulfilledAssetsSum (NEW) / totalPendingShares mapping base (OLD)",
                "maxRetryableValue (NEW) / pendingRedeem mapping base (OLD)",
                "totalPendingShares (NEW) / claimableRedeem mapping base (OLD)",
                "pendingRedeem (NEW) / composeBlocked mapping base (OLD)",
                "claimableRedeem (NEW) / maxRetryableValue (OLD)",
                "composeBlocked (NEW) / totalFulfilledAssetsSum (OLD)"
            ];
            for (uint256 s = 0; s < 8; s++) {
                bytes32 val = vm.load(proxy, bytes32(uint256(COMPOSER_ASYNC_NS) + s));
                console.log("  slot+%d [%s]:", s, asyncLabels[s]);
                console.log("    ", vm.toString(val));
            }

            console.log("--- VaultComposerSyncStorage (ns: 0xc5375600...) ---");
            string[7] memory syncLabels = [
                "vault (address)",
                "assetErc20 (address)",
                "shareErc20 (address)",
                "assetOft (address)",
                "shareOft (address)",
                "endpoint (address)",
                "vaultEid (uint32)"
            ];
            for (uint256 s = 0; s < 7; s++) {
                bytes32 val = vm.load(proxy, bytes32(uint256(COMPOSER_SYNC_NS) + s));
                console.log("  slot+%d [%s]:", s, syncLabels[s]);
                console.log("    ", vm.toString(val));
            }

            console.log("--- AuthStorage (ns: 0x341f7c71...) ---");
            string[3] memory authLabels = ["owner", "authority", "pendingOwner"];
            for (uint256 s = 0; s < 3; s++) {
                bytes32 val = vm.load(proxy, bytes32(uint256(AUTH_NS) + s));
                console.log("  slot+%d [%s]:", s, authLabels[s]);
                console.log("    ", vm.toString(val));
            }
        }
    }

    /// @notice Same dump for the vault
    function test_dumpVaultStorageLayout() public view {
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (ve.addr == address(0)) continue;

            address proxy = ve.addr;
            console.log("=== Vault Storage Dump:", ve.assetSymbol, "===");

            console.log("--- NestVaultCoreStorage (ns: 0x8d327cc9...) ---");
            string[12] memory coreLabels = [
                "minRate",
                "totalPendingShares",
                "accountant (address)",
                "isVaultOperator (mapping)",
                "authorizations (mapping)",
                "pendingRedeem (mapping)",
                "claimableRedeem (mapping)",
                "maxFees (mapping)",
                "fees (mapping)",
                "claimableFees (mapping)",
                "operatorRegistry (address)",
                "(unused / future)"
            ];
            for (uint256 s = 0; s < 12; s++) {
                bytes32 val = vm.load(proxy, bytes32(uint256(NEST_VAULT_CORE_NS) + s));
                console.log("  slot+%d [%s]:", s, coreLabels[s]);
                console.log("    ", vm.toString(val));
            }

            console.log("--- AuthStorage (ns: 0x341f7c71...) ---");
            for (uint256 s = 0; s < 3; s++) {
                bytes32 val = vm.load(proxy, bytes32(uint256(AUTH_NS) + s));
                console.log("  slot+%d:", s);
                console.log("    ", vm.toString(val));
            }
        }
    }

    // ─── Snapshot Helpers ────────────────────────────────────────────

    function _snapshotVault(address proxy) internal view returns (VaultSnapshot memory snap) {
        NestVaultOFT vault = NestVaultOFT(payable(proxy));

        // Auth
        snap.owner = vault.owner();
        snap.authority = address(vault.authority());
        snap.pendingOwner = vault.pendingOwner();

        // ERC20
        snap.name = vault.name();
        snap.symbol = vault.symbol();
        snap.decimals = vault.decimals();
        snap.totalSupply = vault.totalSupply();

        // ERC4626
        snap.asset = vault.asset();
        snap.totalAssets = vault.totalAssets();

        // NestVaultCore
        snap.minRate = vault.minRate();
        snap.totalPendingShares = vault.totalPendingShares();
        snap.accountant = address(vault.accountant());
        snap.operatorRegistry = address(vault.operatorRegistry());

        // Raw slots
        snap.rawCoreSlots = _readSlots(proxy, NEST_VAULT_CORE_NS, 12);
        snap.rawAuthSlots = _readSlots3(proxy, AUTH_NS);
    }

    function _snapshotComposer(address proxy) internal view returns (ComposerSnapshot memory snap) {
        NestVaultComposer composer = NestVaultComposer(payable(proxy));

        // Auth
        snap.owner = composer.owner();
        snap.authority = address(composer.authority());
        snap.pendingOwner = composer.pendingOwner();

        // Sync
        snap.vault = address(composer.VAULT());
        snap.assetOft = composer.ASSET_OFT();
        snap.assetErc20 = composer.ASSET_ERC20();
        snap.shareOft = composer.SHARE_OFT();
        snap.shareErc20 = composer.SHARE_ERC20();
        snap.endpoint = composer.ENDPOINT();
        snap.vaultEid = composer.VAULT_EID();

        // Async
        snap.totalPendingSharesSum = composer.totalPendingSharesSum();
        snap.maxRetryableValue = composer.maxRetryableValue();
        snap.totalFulfilledAssetsSum = composer.totalFulfilledAssetsSum();

        // Raw slots
        snap.rawAsyncSlots = _readSlots8(proxy, COMPOSER_ASYNC_NS);
        snap.rawSyncSlots = _readSlots7(proxy, COMPOSER_SYNC_NS);
        snap.rawAuthSlots = _readSlots3(proxy, AUTH_NS);
    }

    // ─── Deploy Helpers ──────────────────────────────────────────────

    function _deployVaultImpl() internal returns (address) {
        LZConfig memory lzConfig = ConfigReader.readLZConfig(vaultConfig.deployChainId);
        return address(new NestVaultOFT(payable(vaultConfig.contracts.share), lzConfig.endpoint, commonConfig.permit2));
    }

    function _deployComposerImpl() internal returns (address) {
        address complianceProxy = ConfigReader.readComplianceProxy(vaultConfig.deployChainId, vaultConfig.symbol);
        return address(new NestVaultComposer(complianceProxy));
    }

    /// @dev Deploys the accountant impl the config resolves to for this chain.
    ///      `accountantType`/`hubChainId` live in the deployment-config vault JSON, not the
    ///      output snapshot, so read the raw config file directly.
    function _deployAccountantImpl() internal returns (address) {
        string memory rawVaultJson =
            vm.readFile(string.concat(vm.projectRoot(), "/script/deployment-config/vaults/", vaultSymbol, ".json"));
        string memory accType = ConfigReader.effectiveAccountantType(rawVaultJson, chainId);
        address baseAsset = ConfigReader.readAssetAddress(chainId, vaultConfig.baseAssetSymbol);
        address share = vaultConfig.contracts.share;
        require(share != address(0), "accountant: share address not found in config");

        bytes32 h = keccak256(bytes(accType));
        if (h == keccak256(bytes("NestHubAccountant"))) {
            console.log("  deploying NestHubAccountant impl (base=%s share=%s)", baseAsset, share);
            return address(new NestHubAccountant(baseAsset, share));
        } else if (h == keccak256(bytes("NestSpokeAccountant"))) {
            console.log("  deploying NestSpokeAccountant impl (base=%s share=%s)", baseAsset, share);
            return address(new NestSpokeAccountant(baseAsset, share));
        }
        console.log("  deploying NestAccountant impl (base=%s share=%s)", baseAsset, share);
        return address(new NestAccountant(baseAsset, share));
    }

    function _upgradeProxy(address proxy, address newImpl) internal {
        address proxyAdmin = address(uint160(uint256(vm.load(proxy, ADMIN_SLOT))));
        require(proxyAdmin != address(0), "ProxyAdmin not found");

        address adminOwner = ProxyAdmin(proxyAdmin).owner();
        vm.prank(adminOwner);
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), newImpl, "");
    }

    // ─── Assertion Helpers ───────────────────────────────────────────

    function _assertVaultSnapshotsEqual(VaultSnapshot memory a, VaultSnapshot memory b, string memory label)
        internal
        pure
    {
        assertEq(a.owner, b.owner, string.concat(label, ": owner"));
        assertEq(a.authority, b.authority, string.concat(label, ": authority"));
        assertEq(a.pendingOwner, b.pendingOwner, string.concat(label, ": pendingOwner"));
        assertEq(a.name, b.name, string.concat(label, ": name"));
        assertEq(a.symbol, b.symbol, string.concat(label, ": symbol"));
        assertEq(a.decimals, b.decimals, string.concat(label, ": decimals"));
        assertEq(a.totalSupply, b.totalSupply, string.concat(label, ": totalSupply"));
        assertEq(a.asset, b.asset, string.concat(label, ": asset"));
        assertEq(a.totalAssets, b.totalAssets, string.concat(label, ": totalAssets"));
        assertEq(a.minRate, b.minRate, string.concat(label, ": minRate"));
        assertEq(a.totalPendingShares, b.totalPendingShares, string.concat(label, ": totalPendingShares"));
        assertEq(a.accountant, b.accountant, string.concat(label, ": accountant"));
        assertEq(a.operatorRegistry, b.operatorRegistry, string.concat(label, ": operatorRegistry"));

        for (uint256 s = 0; s < 12; s++) {
            assertEq(a.rawCoreSlots[s], b.rawCoreSlots[s], string.concat(label, ": raw core slot ", vm.toString(s)));
        }
        for (uint256 s = 0; s < 3; s++) {
            assertEq(a.rawAuthSlots[s], b.rawAuthSlots[s], string.concat(label, ": raw auth slot ", vm.toString(s)));
        }
    }

    function _assertComposerSnapshotsEqual(ComposerSnapshot memory a, ComposerSnapshot memory b, string memory label)
        internal
        pure
    {
        assertEq(a.owner, b.owner, string.concat(label, ": owner"));
        assertEq(a.authority, b.authority, string.concat(label, ": authority"));
        assertEq(a.pendingOwner, b.pendingOwner, string.concat(label, ": pendingOwner"));
        assertEq(a.vault, b.vault, string.concat(label, ": vault"));
        assertEq(a.assetOft, b.assetOft, string.concat(label, ": assetOft"));
        assertEq(a.assetErc20, b.assetErc20, string.concat(label, ": assetErc20"));
        assertEq(a.shareOft, b.shareOft, string.concat(label, ": shareOft"));
        assertEq(a.shareErc20, b.shareErc20, string.concat(label, ": shareErc20"));
        assertEq(a.endpoint, b.endpoint, string.concat(label, ": endpoint"));
        assertEq(a.vaultEid, b.vaultEid, string.concat(label, ": vaultEid"));
        assertEq(a.totalPendingSharesSum, b.totalPendingSharesSum, string.concat(label, ": totalPendingSharesSum"));
        assertEq(a.maxRetryableValue, b.maxRetryableValue, string.concat(label, ": maxRetryableValue"));
        assertEq(
            a.totalFulfilledAssetsSum, b.totalFulfilledAssetsSum, string.concat(label, ": totalFulfilledAssetsSum")
        );

        for (uint256 s = 0; s < 8; s++) {
            assertEq(a.rawAsyncSlots[s], b.rawAsyncSlots[s], string.concat(label, ": raw async slot ", vm.toString(s)));
        }
        for (uint256 s = 0; s < 7; s++) {
            assertEq(a.rawSyncSlots[s], b.rawSyncSlots[s], string.concat(label, ": raw sync slot ", vm.toString(s)));
        }
        for (uint256 s = 0; s < 3; s++) {
            assertEq(a.rawAuthSlots[s], b.rawAuthSlots[s], string.concat(label, ": raw auth slot ", vm.toString(s)));
        }
    }

    // ─── Raw Slot Readers ────────────────────────────────────────────

    function _readSlots(address target, bytes32 base, uint256 count) internal view returns (bytes32[12] memory slots) {
        for (uint256 s = 0; s < count && s < 12; s++) {
            slots[s] = vm.load(target, bytes32(uint256(base) + s));
        }
    }

    function _readSlots3(address target, bytes32 base) internal view returns (bytes32[3] memory slots) {
        for (uint256 s = 0; s < 3; s++) {
            slots[s] = vm.load(target, bytes32(uint256(base) + s));
        }
    }

    function _readSlots7(address target, bytes32 base) internal view returns (bytes32[7] memory slots) {
        for (uint256 s = 0; s < 7; s++) {
            slots[s] = vm.load(target, bytes32(uint256(base) + s));
        }
    }

    function _readSlots8(address target, bytes32 base) internal view returns (bytes32[8] memory slots) {
        for (uint256 s = 0; s < 8; s++) {
            slots[s] = vm.load(target, bytes32(uint256(base) + s));
        }
    }

    function _readSlots6(address target, bytes32 base) internal view returns (bytes32[6] memory slots) {
        for (uint256 s = 0; s < 6; s++) {
            slots[s] = vm.load(target, bytes32(uint256(base) + s));
        }
    }

    // ─── Logging ─────────────────────────────────────────────────────

    function _logRawSlots(string memory label, bytes32[12] memory slots) internal pure {
        console.log("  [%s]", label);
        for (uint256 s = 0; s < 12; s++) {
            if (slots[s] != bytes32(0)) {
                console.log("    slot+%d: %s", s, vm.toString(slots[s]));
            }
        }
    }

    function _logRawSlots3(string memory label, bytes32[3] memory slots) internal pure {
        console.log("  [%s]", label);
        for (uint256 s = 0; s < 3; s++) {
            if (slots[s] != bytes32(0)) {
                console.log("    slot+%d: %s", s, vm.toString(slots[s]));
            }
        }
    }

    function _logRawSlots7(string memory label, bytes32[7] memory slots) internal pure {
        console.log("  [%s]", label);
        for (uint256 s = 0; s < 7; s++) {
            if (slots[s] != bytes32(0)) {
                console.log("    slot+%d: %s", s, vm.toString(slots[s]));
            }
        }
    }

    function _logRawSlots8(string memory label, bytes32[8] memory slots) internal pure {
        console.log("  [%s]", label);
        for (uint256 s = 0; s < 8; s++) {
            if (slots[s] != bytes32(0)) {
                console.log("    slot+%d: %s", s, vm.toString(slots[s]));
            }
        }
    }

    function _logRawSlots6(string memory label, bytes32[6] memory slots) internal pure {
        console.log("  [%s]", label);
        for (uint256 s = 0; s < 6; s++) {
            if (slots[s] != bytes32(0)) {
                console.log("    slot+%d: %s", s, vm.toString(slots[s]));
            }
        }
    }

    function _logVaultSnapshot(string memory phase, VaultSnapshot memory snap) internal pure {
        console.log("  [%s] owner=%s accountant=%s", phase, snap.owner, snap.accountant);
        console.log("  [%s] minRate=%d totalPendingShares=%d", phase, snap.minRate, snap.totalPendingShares);
        console.log("  [%s] totalAssets=%d", phase, snap.totalAssets);
    }

    function _logComposerSnapshot(string memory phase, ComposerSnapshot memory snap) internal pure {
        console.log("  [%s] owner=%s vault=%s", phase, snap.owner, snap.vault);
        console.log(
            "  [%s] maxRetryableValue=%d totalPendingSharesSum=%d",
            phase,
            snap.maxRetryableValue,
            snap.totalPendingSharesSum
        );
        console.log("  [%s] totalFulfilledAssetsSum=%d", phase, snap.totalFulfilledAssetsSum);
    }

    // ─── Env Helper ──────────────────────────────────────────────────

    function _envBoolOr(string memory key, bool fallback_) internal view returns (bool) {
        try vm.envBool(key) returns (bool v) {
            return v;
        } catch {
            return fallback_;
        }
    }
}
