// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {ConfigReader, CCTPConfig, VaultEntry, CommonContracts, VaultDeployConfig} from "script/lib/ConfigReader.sol";
import {SerializedTx} from "script/lib/SafeBatchSerialize.sol";
import {ICreateX} from "createx/ICreateX.sol";

// Contracts (implementations)
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {NestAccountant} from "contracts/accountant/NestAccountant.sol";
import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";
import {NestSpokeAccountant} from "contracts/accountant/NestSpokeAccountant.sol";
import {NestVaultOFT} from "contracts/NestVaultOFT.sol";
import {NestVault} from "contracts/NestVault.sol";
import {NestVaultPredicateProxy} from "contracts/compliance/NestVaultPredicateProxy.sol";
import {NestCCTPRelayer} from "contracts/integrations/cctp/NestCCTPRelayer.sol";
import {NestVaultComposer} from "contracts/integrations/ovault/NestVaultComposer.sol";
import {NestVaultComposer as NestVaultComposerUpgrade} from "contracts/upgrades/compliance-proxy/NestVaultComposer.sol";
import {NestVaultRedeemOperator} from "contracts/operators/NestVaultRedeemOperator.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {NestVaultCore} from "contracts/NestVaultCore.sol";

// Proxy admin
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Auth} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {console} from "forge-std/console.sol";

/// @title  Upgrade
/// @notice Config-driven upgrade script with common, vault-scoped relayer, and vault contract scopes.
/// @dev    Uses the ERC-1967 admin slot to find each proxy's ProxyAdmin, then calls upgradeAndCall.
///
///         CONTRACT=common — upgrades common proxies (predicateProxy, cctpRelayer, redeemOperator).
///           Reads from script/deployment-config/common/{chainId}.json.
///           CHAIN_ID env var required.
///
///         CONTRACT=cctpRelayer — upgrades only the relayer resolved for a vault symbol.
///           Reads the canonical chain config plus the vault's `commonOverrides.cctpRelayer`.
///           CHAIN_ID and VAULT_SYMBOL env vars required.
///
///         CONTRACT=vault — upgrades vault-specific proxies (share, accountant, vaults, composers).
///           Reads from script/deployment-config/vaults/{symbol}.json.
///           VAULT_SYMBOL env var required.
///           Post-upgrade config: setOperatorRegistry, setMaxRetryableValue, setBeforeTransferHook.
///           Pre-flight: asserts zero pending redemptions; blocks Spoke targets with unclaimed feesOwedInBase.
///
///         Usage:
///           CONTRACT=common CHAIN_ID=98866 forge script script/deploy/Upgrade.s.sol --sig "runDirect()" --rpc-url $RPC --broadcast
///           CONTRACT=cctpRelayer CHAIN_ID=98866 VAULT_SYMBOL=nTEST forge script script/deploy/Upgrade.s.sol --sig "runDirect()" --rpc-url $RPC --broadcast
///           CONTRACT=vault VAULT_SYMBOL=nBYBIT1 forge script script/deploy/Upgrade.s.sol --sig "runMsig()" --rpc-url $RPC
contract Upgrade is BaseConfigScript {
    /// @notice Prepare only the canonical chain relayer upgrade for the combined V2 migration.
    /// @dev Returns owner-authorized calls for one atomic Safe/timelock batch. Does not execute them.
    function prepareCommonRelayerUpgrade(address governance)
        external
        returns (address implementation, SerializedTx[] memory calls)
    {
        chainId = vm.envUint("CHAIN_ID");
        require(block.chainid == chainId, "Upgrade: RPC chain mismatch");
        commonConfig = ConfigReader.readCommonConfig(chainId);
        commonAddrs = ConfigReader.readCommonProxyConfig(chainId);
        address relayer = commonAddrs.cctpRelayer;
        require(relayer.code.length > 0, "Upgrade: common relayer missing");
        CCTPConfig memory cc = ConfigReader.readCCTPConfig(chainId);
        address endpoint = ConfigReader.readLZConfig(chainId).endpoint;
        address usdc = ConfigReader.readAssetAddress(chainId, "USDC");
        require(
            cc.messageTransmitter.code.length > 0 && cc.tokenMessenger.code.length > 0 && endpoint.code.length > 0
                && usdc.code.length > 0,
            "Upgrade: CCTP dependencies missing"
        );
        NestCCTPRelayer live = NestCCTPRelayer(payable(relayer));
        require(
            address(live.MESSAGE_TRANSMITTER()) == cc.messageTransmitter
                && address(live.TOKEN_MESSENGER()) == cc.tokenMessenger && address(live.USDC()) == usdc
                && address(live.endpoint()) == endpoint,
            "Upgrade: CCTP constructor config differs from live relayer"
        );
        address admin = address(uint160(uint256(vm.load(relayer, ADMIN_SLOT))));
        require(
            admin.code.length > 0 && ProxyAdmin(admin).owner() == governance,
            "Upgrade: relayer ProxyAdmin has different governance"
        );
        require(
            live.owner() == governance
                || (address(live.authority()) != address(0)
                    && live.authority().canCall(governance, relayer, NestCCTPRelayer.setEidToDomain.selector)),
            "Upgrade: governance cannot configure relayer"
        );

        // This reference is local to script simulation; only the CREATE3 deployment is broadcast.
        NestCCTPRelayer templateImpl = new NestCCTPRelayer(cc.messageTransmitter, cc.tokenMessenger, endpoint, usdc);
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address previous = address(uint160(uint256(vm.load(relayer, implementationSlot))));
        bytes32 expectedHash = keccak256(address(templateImpl).code);
        // A direct upgrade can have installed the implementation before its separate remap
        // transaction landed. Reapply the idempotent remap even when no upgrade is needed.
        if (keccak256(previous.code) == expectedHash) {
            calls = new SerializedTx[](1);
            calls[0] = SerializedTx({
                name: "NestCCTPRelayer.setEidToDomain", to: relayer, value: 0, data: _cctpDomainRemapData(relayer)
            });
            return (previous, calls);
        }

        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        CREATEX = ICreateX(commonConfig.createx);
        string memory component = string.concat("NestCCTPRelayer-impl-", vm.toString(expectedHash));
        implementation = computeCreate3AddressCommon(component);
        if (implementation.code.length == 0) {
            vm.startBroadcast(deployerPrivateKey);
            address deployed = CREATEX.deployCreate3(
                generateCreate3SaltCommon(component),
                abi.encodePacked(
                    type(NestCCTPRelayer).creationCode,
                    abi.encode(cc.messageTransmitter, cc.tokenMessenger, endpoint, usdc)
                )
            );
            vm.stopBroadcast();
            require(deployed == implementation, "Upgrade: unexpected implementation address");
        }
        require(keccak256(implementation.code) == expectedHash, "Upgrade: occupied implementation salt differs");
        calls = new SerializedTx[](2);
        calls[0] = SerializedTx({
            name: "NestCCTPRelayer.upgradeAndCall",
            to: admin,
            value: 0,
            data: abi.encodeCall(
                ProxyAdmin.upgradeAndCall, (ITransparentUpgradeableProxy(relayer), implementation, bytes(""))
            )
        });
        calls[1] = SerializedTx({
            name: "NestCCTPRelayer.setEidToDomain", to: relayer, value: 0, data: _cctpDomainRemapData(relayer)
        });
        console.log("CCTP relayer implementation prepared:", implementation);
        console.log("Previous CCTP relayer implementation:", previous);
    }

    /// @dev ERC-1967 admin slot: keccak256("eip1967.proxy.admin") - 1
    bytes32 private constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @dev ERC-7201 base of `plumenetwork.storage.NestAccountant`; feesOwedInBase = slot+1 low 16B.
    bytes32 private constant ACCOUNTANT_NS = 0xb378036f9633fc394c3579301b38ac88997c2589544525e367cd650f76eaa300;

    /// @dev `eidToDomain` is the third field in the relayer's ERC-7201 storage namespace.
    bytes32 private constant CCTP_RELAYER_STORAGE_LOCATION =
        0x9cb715fddca002bac31d3e28125e9692c952dae06c29708874aa1ab8a9f63300;

    bool internal isCommonScope;
    bool internal isCCTPRelayerScope;
    uint256 private chainId;
    CommonContracts internal commonAddrs;
    bytes private initData;

    /// @dev Share address used as constructor arg. Resolved from config or output.
    address private shareRef;

    /// @dev Deployment output loaded from script/output/{symbol}/{chainId}-{symbol}.json.
    ///      Input config is upgrade scope; output provides fallback for config-setter wiring
    ///      (e.g. wiring new vaults to an accountant that exists on-chain but isn't in the input).
    VaultDeployConfig private outputConfig;
    bool private hasOutput;
    address[] private upgradeTargets;
    bool private hasUpgradeTargets;
    bool private force;
    address private governanceTimelock;

    function setUp() public {
        string memory scope = vm.envString("CONTRACT");
        isCommonScope = keccak256(bytes(scope)) == keccak256(bytes("common"));
        isCCTPRelayerScope = keccak256(bytes(scope)) == keccak256(bytes("cctpRelayer"));

        if (isCommonScope) {
            chainId = vm.envUint("CHAIN_ID");
            commonAddrs = ConfigReader.readCommonProxyConfig(chainId); // zeros relayer on non-CCTP chains
            commonConfig = ConfigReader.readCommonConfig(chainId);
            lzConfig = ConfigReader.readLZConfig(chainId);
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        } else {
            string memory vaultSymbol = vm.envString("VAULT_SYMBOL");
            loadConfigs(vaultSymbol); // loadConfigs now calls resolveConfigForChain
            chainId = vaultConfig.deployChainId;
            if (isCCTPRelayerScope) {
                require(
                    _hasCommonOverride("cctpRelayer", chainId),
                    "Upgrade: cctpRelayer scope requires commonOverrides.cctpRelayer"
                );
                commonAddrs = vaultConfig.common;
                require(
                    ConfigReader.isActive(commonAddrs.cctpRelayer) && commonAddrs.cctpRelayer.code.length > 0,
                    "Upgrade: vault-scoped CCTP relayer is not deployed"
                );
                console.log("Vault-scoped CCTP relayer:", commonAddrs.cctpRelayer);
            } else {
                _loadOutput(vaultSymbol);
                _resolveShareRef();
            }
        }

        try vm.envBool("VERBOSE") returns (bool v) {
            verbose = v;
        } catch {}

        try vm.envBytes("INIT_DATA") returns (bytes memory data) {
            initData = data;
        } catch {}

        try vm.envAddress("UPGRADE_TARGETS", ",") returns (address[] memory targets) {
            upgradeTargets = targets;
            hasUpgradeTargets = true;
            console.log("Upgrade target allowlist:", targets.length);
        } catch {}

        try vm.envBool("FORCE") returns (bool f) {
            force = f;
            if (f) console.log("FORCE=true: skipping pre-flight checks");
        } catch {}

        try vm.envAddress("GOVERNANCE_TIMELOCK") returns (address timelock) {
            governanceTimelock = timelock;
            require(timelock.code.length > 0, "Upgrade: GOVERNANCE_TIMELOCK has no code");
            console.log("Governance timelock:", timelock);
        } catch {}
    }

    // ─── Entry Points ────────────────────────────────────────────────

    function runDirect() external {
        vm.startBroadcast(deployerPrivateKey);
        if (isCommonScope || isCCTPRelayerScope) {
            _upgradeCommonScope();
        } else {
            _upgradeVaultScope();
            _broadcastDeployerOwnedConfig();
        }
        vm.stopBroadcast();
    }

    function runMsig() external {
        // Pre-flight (before any deployment or batch building)
        if (!isCommonScope && !isCCTPRelayerScope) {
            _assertNoPendingRedemptions();
            _assertNoLegacyFeesBeforeSpoke();
        }

        // Phase 1: broadcast — deploy new implementations + deployer-owned setters
        vm.startBroadcast(deployerPrivateKey);
        address[] memory impls;
        if (isCommonScope || isCCTPRelayerScope) {
            impls = _deployCommonImpls();
        } else {
            impls = _deployVaultImpls();
            _broadcastDeployerOwnedConfig();
        }
        vm.stopBroadcast();

        // Phase 2: Safe batch — queue upgradeAndCall + config setters
        msigMode = true;
        if (isCommonScope) {
            _applyCommonUpgrades(impls);
            writeMsigBatchForChain(chainId, "Upgrade-common");
        } else if (isCCTPRelayerScope) {
            _applyCommonUpgrades(impls);
            writeMsigBatch("Upgrade-cctpRelayer");
        } else {
            _applyVaultUpgrades(impls);
            _writeVaultGovernanceBatches();
        }
    }

    /// @dev Vault ProxyAdmins are sometimes owned by a TimelockController rather than the proposer Safe.
    ///      Opting into GOVERNANCE_TIMELOCK wraps the queued owner calls into deterministic matching
    ///      schedule/execute batches. The default direct-Safe output remains unchanged for existing vaults.
    function _writeVaultGovernanceBatches() internal {
        if (governanceTimelock == address(0)) {
            writeMsigBatch("Upgrade-vault");
            return;
        }

        uint256 length = serializedTxs.length;
        address[] memory targets = new address[](length);
        bytes[] memory payloads = new bytes[](length);
        for (uint256 i; i < length; ++i) {
            require(serializedTxs[i].value == 0, "Upgrade: timelock value unsupported");
            _assertTimelockAuthority(governanceTimelock, serializedTxs[i]);
            targets[i] = serializedTxs[i].to;
            payloads[i] = serializedTxs[i].data;
        }

        delete serializedTxs;
        uint256 delay = TimelockController(payable(governanceTimelock)).getMinDelay();
        bytes32 salt = keccak256(bytes(string.concat(vaultConfig.symbol, ":Upgrade-vault:v1")));
        _buildTimelockBatches(
            governanceTimelock, targets, payloads, salt, delay, "Upgrade-vault-Schedule", "Upgrade-vault-Execute"
        );
    }

    /// @dev ProxyAdmin is owner-only; vault setters use the shared Auth ABI (including
    ///      AuthUpgradeable). Check the exact selector against the target's current authority.
    function _assertTimelockAuthority(address timelock, SerializedTx memory tx_) internal view {
        require(tx_.to.code.length > 0 && tx_.data.length >= 4, "Upgrade: invalid timelock target");
        bytes4 selector = bytes4(tx_.data);
        if (selector == ProxyAdmin.upgradeAndCall.selector) {
            require(ProxyAdmin(tx_.to).owner() == timelock, "Upgrade: timelock does not own ProxyAdmin");
            return;
        }

        Auth target = Auth(tx_.to);
        // Match requiresAuth's authority-first evaluation, including a reverting authority.
        require(
            (address(target.authority()) != address(0) && target.authority().canCall(timelock, tx_.to, selector))
                || target.owner() == timelock,
            "Upgrade: timelock cannot configure target"
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  COMMON SCOPE
    // ═══════════════════════════════════════════════════════════════════

    function _upgradeCommonScope() internal {
        address[] memory impls = _deployCommonImpls();
        _applyCommonUpgrades(impls);
    }

    /// @dev Deploy implementations for common proxies. Returns [predicateProxy, cctpRelayer, redeemOperator].
    function _deployCommonImpls() internal returns (address[] memory impls) {
        impls = new address[](3);

        // predicateProxy
        if (!isCCTPRelayerScope && commonAddrs.predicateProxy.code.length > 0) {
            impls[0] = address(new NestVaultPredicateProxy());
            console.log("PredicateProxy impl deployed:", impls[0]);
        }

        // cctpRelayer
        if (commonAddrs.cctpRelayer.code.length > 0) {
            CCTPConfig memory cctpConfig = ConfigReader.readCCTPConfig(chainId);
            address usdc = ConfigReader.readAssetAddress(chainId, "USDC");
            impls[1] = address(
                new NestCCTPRelayer(cctpConfig.messageTransmitter, cctpConfig.tokenMessenger, lzConfig.endpoint, usdc)
            );
            console.log("NestCCTPRelayer impl deployed:", impls[1]);
        }

        // redeemOperator
        if (!isCCTPRelayerScope && commonAddrs.redeemOperator.code.length > 0) {
            impls[2] = address(new NestVaultRedeemOperator());
            console.log("RedeemOperator impl deployed:", impls[2]);
        }
    }

    function _applyCommonUpgrades(address[] memory impls) internal {
        if (impls[0] != address(0)) {
            _upgradeProxy(commonAddrs.predicateProxy, impls[0], "PredicateProxy");
        }
        if (impls[1] != address(0)) {
            bytes memory domainRemapData = _cctpDomainRemapData(commonAddrs.cctpRelayer);
            _upgradeProxy(commonAddrs.cctpRelayer, impls[1], "NestCCTPRelayer");
            execute(commonAddrs.cctpRelayer, domainRemapData, "setEidToDomain(migrate legacy domains)");
        }
        if (impls[2] != address(0)) {
            _upgradeProxy(commonAddrs.redeemOperator, impls[2], "RedeemOperator");
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  VAULT SCOPE
    // ═══════════════════════════════════════════════════════════════════

    function _upgradeVaultScope() internal {
        _assertNoPendingRedemptions();
        _assertNoLegacyFeesBeforeSpoke();
        address[] memory impls = _deployVaultImpls();
        _applyVaultUpgrades(impls);
    }

    /// @dev Deploy implementations for vault-specific proxies.
    ///      Returns [share, accountant, vault0..vaultN, composer0..composerN].
    ///      Layout: [0]=share, [1]=accountant, [2..2+vaults.length-1]=vaults, [2+vaults.length..]=composers
    function _deployVaultImpls() internal returns (address[] memory impls) {
        uint256 n = vaultConfig.vaults.length;
        impls = new address[](2 + n + n); // share + accountant + vaults + composers

        // share (skip if not behind a proxy, e.g. NestVaultOFT deploys share without a proxy)
        if (_shouldUpgrade(vaultConfig.contracts.share) && _isProxy(vaultConfig.contracts.share)) {
            impls[0] = address(new NestShareOFT(lzConfig.endpoint));
            console.log("NestShareOFT impl deployed:", impls[0]);
        }

        // accountant — impl resolved from .accountantType / .hubChainId in the vault JSON.
        if (_shouldUpgrade(vaultConfig.contracts.accountant) && _isProxy(vaultConfig.contracts.accountant)) {
            address baseAsset = ConfigReader.readAssetAddress(chainId, vaultConfig.baseAssetSymbol);
            bytes32 h = keccak256(bytes(effectiveAccountantType()));
            if (h == keccak256(bytes("NestHubAccountant"))) {
                impls[1] = address(new NestHubAccountant(baseAsset, shareRef));
                console.log("NestHubAccountant impl deployed:", impls[1]);
            } else if (h == keccak256(bytes("NestSpokeAccountant"))) {
                impls[1] = address(new NestSpokeAccountant(baseAsset, shareRef));
                console.log("NestSpokeAccountant impl deployed:", impls[1]);
            } else {
                impls[1] = address(new NestAccountant(baseAsset, shareRef));
                console.log("NestAccountant impl deployed:", impls[1]);
            }
        }

        // vaults
        for (uint256 i = 0; i < n; i++) {
            if (!_shouldUpgrade(vaultConfig.vaults[i].addr) || !_isProxy(vaultConfig.vaults[i].addr)) continue;
            if (isOFT()) {
                impls[2 + i] = address(new NestVaultOFT(payable(shareRef), lzConfig.endpoint, commonConfig.permit2));
            } else {
                impls[2 + i] = address(new NestVault(payable(shareRef), commonConfig.permit2));
            }
            console.log("Vault impl deployed for", vaultConfig.vaults[i].assetSymbol, ":", impls[2 + i]);
        }

        // composers
        for (uint256 i = 0; i < n; i++) {
            if (!_shouldUpgrade(vaultConfig.vaults[i].composer) || !_isProxy(vaultConfig.vaults[i].composer)) continue;
            // V2-only vaults bind to the shared proxy; others keep their per-vault compliance file.
            address complianceProxy = isV2Only()
                ? vaultConfig.common.complianceProxy
                : ConfigReader.readComplianceProxy(vaultConfig.deployChainId, vaultConfig.symbol);
            require(complianceProxy.code.length > 0, "Upgrade: complianceProxy not deployed");
            impls[2 + n + i] = address(new NestVaultComposerUpgrade(complianceProxy));
            console.log("Composer impl deployed for", vaultConfig.vaults[i].assetSymbol, ":", impls[2 + n + i]);
        }
    }

    function _applyVaultUpgrades(address[] memory impls) internal {
        uint256 n = vaultConfig.vaults.length;

        // Upgrades use input config only — zero-in-input skips the proxy.
        if (impls[0] != address(0)) {
            _upgradeProxy(vaultConfig.contracts.share, impls[0], "NestShareOFT");
            if (vaultConfig.common.blacklistHook.code.length > 0) {
                execute(
                    vaultConfig.contracts.share,
                    abi.encodeCall(NestShareOFT.setBeforeTransferHook, (vaultConfig.common.blacklistHook)),
                    "setBeforeTransferHook"
                );
            }
        }
        if (impls[1] != address(0)) {
            string memory accountantName = effectiveAccountantType();
            _upgradeProxy(vaultConfig.contracts.accountant, impls[1], accountantName);
            bytes32 accountantHash = keccak256(bytes(accountantName));
            if (accountantHash == keccak256(bytes("NestHubAccountant"))) {
                // Storage layout is preserved across NestAccountant/NestSpokeAccountant -> NestHubAccountant
                // so no initializer runs. Seed the HWM checkpoint once at the live exchange rate;
                // fee parameters (perf/hurdle/holdback/window/epochs) stay at 0 and the operator
                // configures them after the next `updateExchangeRate`. Skip when HWM is already seeded
                // so re-runs don't clobber clawback state.
                if (_needsHwmSeed(vaultConfig.contracts.accountant)) {
                    uint96 currentRate = uint96(NestAccountant(vaultConfig.contracts.accountant).getRate());
                    require(currentRate > 0, "Upgrade: accountant exchange rate is zero, cannot seed HWM");
                    execute(
                        vaultConfig.contracts.accountant,
                        abi.encodeCall(NestHubAccountant.resetHighWaterMark, (currentRate)),
                        "resetHighWaterMark-NestHubAccountant"
                    );
                }
            }
            // updateExchangeRate's selector changed to updateExchangeRate(uint96,uint128) for both
            // Hub and Spoke accountants; the legacy role capability only covers the 1-arg selector.
            // Grant the new selector to UPDATE_EXCHANGE_RATE_ROLE so keepers can still push rates
            // after the upgrade (legacy NestAccountant keeps the 1-arg selector and needs no grant).
            if (
                accountantHash == keccak256(bytes("NestHubAccountant"))
                    || accountantHash == keccak256(bytes("NestSpokeAccountant"))
            ) {
                _grantUpdateExchangeRateCapability();
            }
        }
        for (uint256 i = 0; i < n; i++) {
            if (impls[2 + i] != address(0)) {
                _upgradeProxy(
                    vaultConfig.vaults[i].addr, impls[2 + i], string.concat("Vault-", vaultConfig.vaults[i].assetSymbol)
                );
            }
        }
        for (uint256 i = 0; i < n; i++) {
            if (impls[2 + n + i] != address(0)) {
                _upgradeProxyWithData(
                    vaultConfig.vaults[i].composer,
                    impls[2 + n + i],
                    string.concat("Composer-", vaultConfig.vaults[i].assetSymbol),
                    abi.encodeCall(NestVaultComposerUpgrade.initializeComplianceProxy, ())
                );
            }
        }

        // Config setters use the resolved view (input ∪ output) so freshly deployed
        // contracts not in the input still get wired to upgraded dependencies.
        _applyVaultConfigSetters();
    }

    /// @dev Grants UPDATE_EXCHANGE_RATE_ROLE the capability for the 2-arg
    ///      `updateExchangeRate(uint96,uint128)` selector used by Hub/Spoke accountants.
    ///      The pre-upgrade authority only covers the legacy 1-arg selector, which the new
    ///      impls no longer expose. Idempotent: skipped when the capability already exists.
    function _grantUpdateExchangeRateCapability() internal {
        address ra = vaultConfig.contracts.rolesAuthority;
        require(ra != address(0), "Upgrade: rolesAuthority required to grant updateExchangeRate capability");

        uint8 updateRateRole = 4; // UPDATE_EXCHANGE_RATE_ROLE — see config/authority/authority.json
        bytes4 newSig = bytes4(keccak256(bytes("updateExchangeRate(uint96,uint128)")));
        address accountant = vaultConfig.contracts.accountant;

        if (RolesAuthority(ra).doesRoleHaveCapability(updateRateRole, accountant, newSig)) return;

        execute(
            ra,
            abi.encodeCall(RolesAuthority.setRoleCapability, (updateRateRole, accountant, newSig, true)),
            "setRoleCapability(UPDATE_EXCHANGE_RATE_ROLE, accountant, updateExchangeRate(uint96,uint128))"
        );
    }

    /// @dev Queues setAccountant and setOperatorRegistry on every known vault (input + output fallback),
    ///      each gated by an on-chain mismatch check. Composer setMaxRetryableValue is broadcast for
    ///      deployer-owned composers first (see _broadcastDeployerOwnedConfig); composers the deployer
    ///      does not own get the idempotent setter queued here when live != config (the Safe executes
    ///      via owner() or its RolesAuthority capability).
    function _applyVaultConfigSetters() internal {
        address accountant = _resolvedAccountant();
        address operatorRegistry = vaultConfig.common.operatorRegistry;

        VaultEntry[] memory vaults = _resolvedVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            address vault = vaults[i].addr;
            string memory sym = vaults[i].assetSymbol;

            // Composer maxRetryableValue: apply when live != config. Deployer-owned composers were
            // already set in the broadcast phase (_broadcastDeployerOwnedConfig), so their live value
            // matches by now and this self-skips — the Safe batch only receives targets the deployer
            // does not own.
            address composer = vaults[i].composer;
            if (vaultConfig.maxRetryableValue != 0 && composer != address(0) && composer.code.length > 0) {
                bool dup; // vaults can share a composer (see TransferOwnership dedup) — queue once
                for (uint256 j = 0; j < i; j++) {
                    if (vaults[j].composer == composer) dup = true;
                }
                bool needsSet = true;
                try NestVaultComposer(payable(composer)).maxRetryableValue() returns (uint256 cur) {
                    needsSet = cur != vaultConfig.maxRetryableValue;
                } catch {
                    // No getter: only safe when this run installs the impl that has the setter.
                    needsSet = _shouldUpgrade(composer) && _isProxy(composer);
                    if (!needsSet) {
                        console.log("  setMaxRetryableValue skipped (no getter, composer not upgraded this run):", sym);
                    }
                }
                if (!dup && needsSet) {
                    execute(
                        composer,
                        abi.encodeCall(NestVaultComposer.setMaxRetryableValue, (vaultConfig.maxRetryableValue)),
                        string.concat("setMaxRetryableValue-", sym)
                    );
                }
            }

            if (vault == address(0) || vault.code.length == 0) continue;

            if (accountant != address(0) && accountant.code.length > 0) {
                bool needsSet;
                // old impls may lack accountant() selector — treat revert as mismatch.
                try INestVaultCore(vault).accountant() returns (NestHubAccountant current) {
                    needsSet = address(current) != accountant;
                } catch {
                    needsSet = true;
                }
                if (needsSet) {
                    execute(
                        vault,
                        abi.encodeCall(NestVaultCore.setAccountant, (accountant)),
                        string.concat("setAccountant-", sym)
                    );
                }
            }

            if (operatorRegistry != address(0) && operatorRegistry.code.length > 0) {
                bool needsSet;
                try NestVaultCore(vault).operatorRegistry() returns (OperatorRegistry current) {
                    needsSet = address(current) != operatorRegistry;
                } catch {
                    needsSet = true;
                }
                if (needsSet) {
                    execute(
                        vault,
                        abi.encodeCall(NestVaultCore.setOperatorRegistry, (operatorRegistry)),
                        string.concat("setOperatorRegistry-", sym)
                    );
                }
            }
        }
    }

    /// @dev Broadcasts composer config that only the deployer-as-owner can set
    ///      (e.g. setMaxRetryableValue) before ownership transfers to the Safe.
    ///      Skips when the deployer is no longer owner — _applyVaultConfigSetters
    ///      queues that case into the Safe batch.
    function _broadcastDeployerOwnedConfig() internal {
        uint256 maxRetryable = vaultConfig.maxRetryableValue;
        if (maxRetryable == 0) return;

        VaultEntry[] memory vaults = _resolvedVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            address composer = vaults[i].composer;
            string memory sym = vaults[i].assetSymbol;
            if (composer == address(0) || composer.code.length == 0) continue;

            address ownerAddr;
            try Auth(composer).owner() returns (address o) {
                ownerAddr = o;
            } catch {
                console.log(string.concat("setMaxRetryableValue skip (no owner getter) - ", sym));
                continue;
            }
            if (ownerAddr != deployer()) {
                console.log(string.concat("setMaxRetryableValue skip (deployer not owner) - ", sym));
                continue;
            }

            try NestVaultComposer(payable(composer)).maxRetryableValue() returns (uint256 cur) {
                if (cur == maxRetryable) {
                    console.log(string.concat("setMaxRetryableValue skip (already set) - ", sym));
                    continue;
                }
            } catch {}

            NestVaultComposer(payable(composer)).setMaxRetryableValue(maxRetryable);
            console.log(string.concat("setMaxRetryableValue broadcast - ", sym));
        }
    }

    // ─── Pre-flight Safety ───────────────────────────────────────────

    /// @notice Reverts if any vault has pending redemptions that the upgrade would strand.
    /// @dev    On fulfillment, `decreaseTotalPendingShares` decrements the accountant's global pending
    ///         counter. An underflow is only possible when the upgrade resets that counter to 0 — i.e.
    ///         a migration whose target accountant does NOT share the source storage layout. The
    ///         NestAccountant/NestSpokeAccountant -> NestHubAccountant (and Spoke) upgrades preserve the
    ///         accountant storage (same ERC-7201 slot `plumenetwork.storage.NestAccountant`, with
    ///         `totalPendingShares` at the same offset in all three impls), so a populated counter
    ///         carries over and pending redemptions remain safe. We therefore allow pending shares when
    ///         the target is layout-preserving AND the live accountant counter already covers the
    ///         vaults' pending sum; otherwise we block. `FORCE=true` overrides regardless.
    function _assertNoPendingRedemptions() internal view {
        if (force) {
            console.log("Pre-flight check skipped (FORCE=true)");
            return;
        }
        if (!_shouldUpgrade(vaultConfig.contracts.accountant)) return;

        console.log("Checking vaults for pending redemptions...");
        uint256 sumVaultPending;
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (ve.addr.code.length == 0) continue;

            uint256 pending = INestVaultCore(ve.addr).totalPendingShares();
            console.log("  Vault", ve.assetSymbol, "totalPendingShares:", pending);
            sumVaultPending += pending;
        }

        if (sumVaultPending == 0) {
            console.log("Pre-flight check passed: no pending redemptions");
            return;
        }

        // Layout-preserving accountant upgrades keep the global pending counter, so fulfillment
        // decrements the carried-over value instead of underflowing from zero.
        if (_accountantPreservesPending(sumVaultPending)) {
            console.log(
                "Pre-flight: pending shares present, but accountant storage is preserved across this upgrade; OK"
            );
            return;
        }

        revert(
            "BLOCKED: vaults have pending shares and this upgrade would not preserve the accountant pending counter. Fulfill or cancel all pending redemptions before upgrading (or set FORCE=true if intentional)."
        );
    }

    /// @dev True when the target accountant keeps `totalPendingShares` at its existing storage slot
    ///      (NestHubAccountant / NestSpokeAccountant share the NestAccountant ERC-7201 layout) and the
    ///      live accountant counter already covers `sumVaultPending`, so the value survives the impl
    ///      swap. Any non-layout-preserving target, a missing `totalPendingShares()` getter, or a
    ///      counter below the vaults' pending sum returns false (block).
    function _accountantPreservesPending(uint256 sumVaultPending) internal view returns (bool) {
        bytes32 h = keccak256(bytes(effectiveAccountantType()));
        if (h != keccak256("NestHubAccountant") && h != keccak256("NestSpokeAccountant")) {
            return false;
        }
        try NestAccountant(vaultConfig.contracts.accountant).totalPendingShares() returns (uint256 acctPending) {
            return acctPending >= sumVaultPending;
        } catch {
            return false;
        }
    }

    /// @notice Blocks a Spoke-target accountant upgrade while the live accountant still owes fees: Spoke has no
    ///         claim/waive surface, so `feesOwedInBase` would be stranded. FORCE=true downgrades to a warning.
    function _assertNoLegacyFeesBeforeSpoke() internal view {
        if (!_shouldUpgrade(vaultConfig.contracts.accountant)) return;
        if (keccak256(bytes(effectiveAccountantType())) != keccak256("NestSpokeAccountant")) return;
        uint256 feesOwed = _liveFeesOwedInBase(vaultConfig.contracts.accountant);
        if (feesOwed == 0) return;
        string memory message = string.concat(
            "accountant owes feesOwedInBase=",
            vm.toString(feesOwed),
            " and NestSpokeAccountant cannot claim or waive it. Claim via share.manage(accountant,",
            " claimFees(feeAsset)) first - see contracts/accountant/README.md, 'Claim fees'"
        );
        if (force) {
            console.log(string.concat("WARNING (FORCE=true): ", message, "; continuing - balance will be stranded"));
            return;
        }
        revert(string.concat("BLOCKED: ", message, " (or set FORCE=true to accept stranding)."));
    }

    /// @dev Shape-agnostic fee read: every accountant variant's AccountantState leads with (payoutAddress,
    ///      feesOwedInBase), so decode only the two leading words; getter-less impls fall back to the slot.
    function _liveFeesOwedInBase(address accountant) internal view returns (uint256) {
        if (accountant.code.length == 0) return 0;
        (bool ok, bytes memory ret) = accountant.staticcall(abi.encodeWithSignature("getAccountantState()"));
        if (!ok || ret.length < 64) {
            return uint128(uint256(vm.load(accountant, bytes32(uint256(ACCOUNTANT_NS) + 1))));
        }
        (, uint256 feesOwed) = abi.decode(ret, (address, uint256));
        return feesOwed;
    }

    // ─── Core Upgrade Logic ──────────────────────────────────────────

    /// @dev Returns true if the given address has a non-zero ERC-1967 admin slot (i.e. is a TUP).
    function _isProxy(address target) internal view returns (bool) {
        if (target == address(0) || target.code.length == 0) return false;
        return uint256(vm.load(target, ADMIN_SLOT)) != 0;
    }

    function _shouldUpgrade(address target) internal view returns (bool) {
        if (!isActive(target)) return false;
        if (!hasUpgradeTargets) return true;
        for (uint256 i = 0; i < upgradeTargets.length; i++) {
            if (upgradeTargets[i] == target) return true;
        }
        return false;
    }

    /// @dev Builds the authenticated post-upgrade call that rewrites every currently mapped CCTP route
    ///      from raw-domain storage to domain-plus-one storage. EVM domains come from config,
    ///      which also corrects Ethereum from the old value 5 to domain 0. Solana has no CCTP
    ///      config file; its canonical domain 5 is used for both legacy and already encoded storage.
    function _cctpDomainRemapData(address relayer) internal view returns (bytes memory) {
        uint256[6] memory candidateChainIds = [uint256(1), 101, 43_114, 480, 8_453, 98_866];
        uint256 mappedCount;

        for (uint256 i = 0; i < candidateChainIds.length; i++) {
            uint32 eid = ConfigReader.readLZConfig(candidateChainIds[i]).eid;
            if (_storedCCTPDomain(relayer, eid) != 0) mappedCount++;
        }

        uint32[] memory eids = new uint32[](mappedCount);
        uint32[] memory domains = new uint32[](mappedCount);
        uint256 mappedIndex;

        for (uint256 i = 0; i < candidateChainIds.length; i++) {
            uint256 peerChainId = candidateChainIds[i];
            uint32 eid = ConfigReader.readLZConfig(peerChainId).eid;
            uint32 storedDomain = _storedCCTPDomain(relayer, eid);
            if (storedDomain == 0) continue;

            eids[mappedIndex] = eid;
            domains[mappedIndex] = peerChainId == 101 ? 5 : ConfigReader.readCCTPConfig(peerChainId).domain;
            mappedIndex++;
        }

        return abi.encodeCall(NestCCTPRelayer.setEidToDomain, (eids, domains));
    }

    function _storedCCTPDomain(address relayer, uint32 eid) internal view returns (uint32) {
        bytes32 mappingSlot = keccak256(abi.encode(eid, uint256(CCTP_RELAYER_STORAGE_LOCATION) + 2));
        return uint32(uint256(vm.load(relayer, mappingSlot)));
    }

    /// @dev Returns true when the Hub HWM checkpoint has not yet been seeded on the proxy.
    ///      - Reverts (no selector) → still on legacy NestAccountant/NestSpokeAccountant impl, needs seed.
    ///      - Returns highWaterMark == 0 → Hub impl already active but unseeded, needs seed.
    ///      - Returns highWaterMark > 0 → already seeded, skip.
    function _needsHwmSeed(address accountant) internal view returns (bool) {
        try NestHubAccountant(accountant).getPerformanceFeeCheckpoint() returns (
            NestHubAccountant.PerformanceFeeCheckpoint memory cp
        ) {
            return cp.highWaterMark == 0;
        } catch {
            return true;
        }
    }

    function _upgradeProxy(address proxy, address newImpl, string memory label) internal {
        _upgradeProxyWithData(proxy, newImpl, label, initData);
    }

    function _upgradeProxyWithData(address proxy, address newImpl, string memory label, bytes memory data) internal {
        address proxyAdmin = address(uint160(uint256(vm.load(proxy, ADMIN_SLOT))));
        require(proxyAdmin != address(0), string.concat("Upgrade: could not find ProxyAdmin for ", label));

        string memory upgradeLabel =
            bytes(label).length > 0 ? string.concat("upgradeAndCall(", label, ")") : "upgradeAndCall";

        execute(
            proxyAdmin,
            abi.encodeCall(ProxyAdmin.upgradeAndCall, (ITransparentUpgradeableProxy(proxy), newImpl, data)),
            upgradeLabel
        );
    }

    // ─── Output Merge ───────────────────────────────────────────────

    /// @dev Loads the deployment output snapshot if it exists. Used as fallback for
    ///      config-setter wiring when contracts aren't in the input config.
    function _loadOutput(string memory symbol) internal {
        string memory path =
            string.concat(vm.projectRoot(), "/script/output/", symbol, "/", vm.toString(chainId), "-", symbol, ".json");
        if (vm.isFile(path)) {
            outputConfig = ConfigReader.readOutputConfig(chainId, symbol);
            hasOutput = true;
        }
    }

    /// @dev Resolves the share address baked into new impls as an immutable. Input, output, and any
    ///      live share() bindings must agree — no silent preference between sources.
    function _resolveShareRef() internal {
        address input = isActive(vaultConfig.contracts.share) ? vaultConfig.contracts.share : address(0);
        address output =
            (hasOutput && isActive(outputConfig.contracts.share)) ? outputConfig.contracts.share : address(0);
        if (input != address(0) && output != address(0) && input != output) {
            revert(
                string.concat(
                    "Upgrade: share mismatch: input=",
                    vm.toString(input),
                    " output=",
                    vm.toString(output),
                    " - fix contracts.share in the vault JSON or regenerate the output snapshot"
                )
            );
        }
        shareRef = input != address(0) ? input : output;
        require(
            shareRef != address(0) && shareRef.code.length > 0, "Upgrade: share address not found in config or output"
        );

        _requireLiveShare(_resolvedAccountant(), "accountant");
        VaultEntry[] memory vaults = _resolvedVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            _requireLiveShare(vaults[i].addr, string.concat("vault-", vaults[i].assetSymbol));
        }
    }

    /// @dev Reverts when `target` exposes share() and it disagrees with the resolved shareRef.
    ///      Legacy impls without the getter are skipped.
    function _requireLiveShare(address target, string memory label) internal view {
        if (target == address(0) || target.code.length == 0) return;
        (bool ok, bytes memory ret) = target.staticcall(abi.encodeWithSignature("share()"));
        if (!ok || ret.length < 32) return;
        address live = abi.decode(ret, (address));
        require(
            live == shareRef,
            string.concat(
                "Upgrade: live share() on ",
                label,
                " is ",
                vm.toString(live),
                " but resolved share is ",
                vm.toString(shareRef),
                " - resolve before deploying impls"
            )
        );
    }

    /// @dev Input if non-zero, else output. Used for wiring vaults to the live accountant.
    function _resolvedAccountant() internal view returns (address) {
        if (vaultConfig.contracts.accountant != address(0)) return vaultConfig.contracts.accountant;
        if (hasOutput) return outputConfig.contracts.accountant;
        return address(0);
    }

    /// @dev Merged vault list: input entries with zero addr/composer filled from output by assetSymbol.
    function _resolvedVaults() internal view returns (VaultEntry[] memory) {
        if (!hasOutput) return vaultConfig.vaults;

        uint256 n = vaultConfig.vaults.length;
        VaultEntry[] memory merged = new VaultEntry[](n);
        for (uint256 i = 0; i < n; i++) {
            merged[i] = vaultConfig.vaults[i];
            if (merged[i].addr != address(0) && merged[i].composer != address(0)) continue;

            bytes32 symHash = keccak256(bytes(merged[i].assetSymbol));
            for (uint256 j = 0; j < outputConfig.vaults.length; j++) {
                if (keccak256(bytes(outputConfig.vaults[j].assetSymbol)) != symHash) continue;
                if (merged[i].addr == address(0)) merged[i].addr = outputConfig.vaults[j].addr;
                if (merged[i].composer == address(0)) merged[i].composer = outputConfig.vaults[j].composer;
                break;
            }
        }
        return merged;
    }
}
