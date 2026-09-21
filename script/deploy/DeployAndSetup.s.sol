// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {
    ConfigReader,
    CCTPConfig,
    LZConfig,
    DVNConfig,
    EnforcedOptionsConfig,
    CommonConfig,
    VaultContracts,
    CommonContracts,
    VaultEntry
} from "script/lib/ConfigReader.sol";
import {SerializedTx, SafeTxUtil} from "script/lib/SafeBatchSerialize.sol";

// Contracts
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {ITransferHook} from "contracts/interfaces/ITransferHook.sol";
import {NestAccountant} from "contracts/accountant/NestAccountant.sol";
import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";
import {NestSpokeAccountant} from "contracts/accountant/NestSpokeAccountant.sol";
import {NestVaultOFT} from "contracts/NestVaultOFT.sol";
import {NestVault} from "contracts/NestVault.sol";
import {NestVaultPredicateProxy} from "contracts/compliance/NestVaultPredicateProxy.sol";
import {ComplianceProxy} from "contracts/compliance/ComplianceProxy.sol";
import {PredicateV2Hook} from "contracts/compliance/hooks/PredicateV2Hook.sol";
import {NestCCTPRelayer} from "contracts/integrations/cctp/NestCCTPRelayer.sol";
import {ITokenMessengerV2} from "contracts/vendor/cctp/interfaces/ITokenMessengerV2.sol";
import {NestVaultComposer} from "contracts/integrations/ovault/NestVaultComposer.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";
import {NestVaultRedeemOperator} from "contracts/operators/NestVaultRedeemOperator.sol";
import {NestShareSeizer} from "contracts/compliance/NestShareSeizer.sol";
import {NestUnlooper} from "contracts/integrations/morpho/NestUnlooper.sol";
import {BlacklistHook} from "contracts/compliance/hooks/BlacklistHook.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

// LayerZero
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {
    IOAppOptionsType3,
    EnforcedOptionParam
} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import {
    SetConfigParam,
    IMessageLibManager
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";

/// @title  DeployAndSetup
/// @notice One-shot script: deploys all contracts + configures authority + sets up LayerZero.
/// @dev    Skips any contract whose address is already non-zero in the vault config.
///         Set STEPS env var to run specific steps (comma-separated): "deploy,operator,composer,authority,l0,share"
///         Defaults to all steps if STEPS is not set.
///
///         Usage (hybrid — auto-detects ownership, queues msig txs when deployer is not owner):
///           forge script script/deploy/DeployAndSetup.s.sol --sig "run(string)" "nTEST" --rpc-url $RPC --broadcast
///           STEPS=authority,l0 forge script script/deploy/DeployAndSetup.s.sol --sig "run(string)" "nTEST" --rpc-url $RPC --broadcast
///
///         Legacy usage:
///           VAULT_SYMBOL=nTEST forge script script/deploy/DeployAndSetup.s.sol --sig "runDirect()" --rpc-url $RPC --broadcast
///           VAULT_SYMBOL=nTEST forge script script/deploy/DeployAndSetup.s.sol --sig "runMsig()" --rpc-url $RPC
contract DeployAndSetup is BaseConfigScript {
    using OptionsBuilder for bytes;
    using stdJson for string;
    uint32 constant CONFIG_TYPE_ULN = 2;

    bool internal stepDeploy;
    bool internal stepOperator;
    bool internal stepComposer;
    bool internal stepAuthority;
    bool internal stepL0;
    bool internal stepShare;

    // Deployed RolesAuthority addresses (set during deploy step, used in authority step)
    address internal rolesAuthority;
    address internal commonRolesAuthority;

    /// @notice Bootstrap shared operators, authority, blacklist hook and optional CCTP on a V2-only chain.
    /// @dev Bootstrap CreateX first, then deploy/configure compliance and vaults; transfer ownership last.
    function runCommonV2() external {
        loadConfigs("nCOMMON");
        require(block.chainid == vaultConfig.deployChainId, "DeployAndSetup: RPC chain mismatch");
        require(chainComplianceConfig.v2Only, "DeployAndSetup: chain is not V2-only");
        require(!isActive(vaultConfig.common.predicateProxy), "DeployAndSetup: V1 proxy configured");
        require(commonConfig.createx.code.length > 0, "DeployAndSetup: CreateX missing");
        require(chainComplianceConfig.v2.predicateRegistry.code.length > 0, "DeployAndSetup: registry missing");
        require(
            vaultConfig.vaults.length == 0 && isDisabled(vaultConfig.contracts.share)
                && isDisabled(vaultConfig.contracts.accountant) && isDisabled(vaultConfig.contracts.rolesAuthority),
            "DeployAndSetup: nCOMMON must disable vault stack"
        );
        snapshotCommon();
        delete vaultConfig.peers;
        hybridMode = true;
        vm.startBroadcast(deployerPrivateKey);
        _deployVaultStack();
        vaultConfig.common.commonRolesAuthority = commonRolesAuthority;
        _deployOperators();
        _deployComposers();
        _setAuthorityOnContracts(address(0), commonRolesAuthority);
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/config/authority/common-authority.json"));
        _processCapabilities(json, commonRolesAuthority);
        _processPublicCapabilities(json, commonRolesAuthority);
        _processRoleAssignments(json, commonRolesAuthority);
        _wireRelayer();
        vm.stopBroadcast();
        _writeOutput();
        _writeSetupBatch();
    }

    function _requireComplianceReady() internal view {
        if (!isV2Only()) return;
        require(block.chainid == vaultConfig.deployChainId, "DeployAndSetup: RPC chain mismatch");
        // A V2-only chain has no V1 proxy; a V2-only vault on a V1 chain leaves that proxy untouched.
        if (chainComplianceConfig.v2Only) {
            require(!isActive(vaultConfig.common.predicateProxy), "DeployAndSetup: V1 proxy configured");
        }
        address cp = vaultConfig.common.complianceProxy;
        require(cp.code.length > 0, "DeployAndSetup: activate common V2 compliance first");
        ComplianceProxy proxy = ComplianceProxy(cp);
        address authority = vaultConfig.common.commonRolesAuthority;
        require(address(proxy.authority()) == authority, "DeployAndSetup: V2 authority mismatch");
        require(
            proxy.owner() == Auth(authority).owner() && proxy.pendingOwner() == address(0),
            "DeployAndSetup: V2 ownership handoff incomplete"
        );
        PredicateV2Hook hook = PredicateV2Hook(address(proxy.complianceHook()));
        require(
            address(hook.authority()) == authority && hook.getRegistry() == chainComplianceConfig.v2.predicateRegistry,
            "DeployAndSetup: V2 hook mismatch"
        );
        require(bytes(hook.getPolicyID()).length > 0, "DeployAndSetup: V2 policy missing");
        require(
            Authority(authority).canCall(cp, address(hook), PredicateV2Hook.checkCompliance.selector),
            "DeployAndSetup: V2 hook permission missing"
        );
        for (uint256 i; i < vaultConfig.vaults.length; ++i) {
            address composer = vaultConfig.vaults[i].composer;
            if (composer.code.length == 0) continue;
            require(
                address(NestVaultComposer(payable(composer)).COMPLIANCE_PROXY()) == cp,
                "DeployAndSetup: Composer is not bound to shared V2 proxy"
            );
        }
    }

    function _requiresV2Proof(bytes4 selector) internal pure returns (bool) {
        // Compliance gates entry into the vault. Redemptions use the standard public routes.
        return selector == bytes4(keccak256("deposit(uint256,address)"))
            || selector == bytes4(keccak256("mint(uint256,address)"));
    }

    function _configureV2VaultAccess(address vaultAuth) internal {
        // The shared proxy uses the common authority; vault authorities grant only its vault access.
        string memory json =
            '{"capabilities":[{"role":7,"target":"vault","functions":["deposit(uint256,address)","mint(uint256,address)","requestRedeem(uint256,address,address)","instantRedeem(uint256,address,address)"]}],"roleAssignments":[{"user":"complianceProxy","role":7}]}';
        _processCapabilities(json, vaultAuth);
        _processRoleAssignments(json, vaultAuth);
    }

    function _writeSetupBatch() internal {
        if (isV2Only()) {
            string memory prefix = string.concat(
                vm.projectRoot(),
                "/script/output/msig/",
                vm.toString(vaultConfig.deployChainId),
                "-",
                vaultConfig.symbol,
                "-DeployAndSetup"
            );
            string[3] memory suffixes = [".json", "-Schedule.json", "-Execute.json"];
            for (uint256 i; i < suffixes.length; ++i) {
                string memory path = string.concat(prefix, suffixes[i]);
                if (vm.exists(path)) vm.removeFile(path);
            }
        }
        if (isV2Only() && serializedTxs.length > 0) {
            address owner = Auth(_resolveCommonRolesAuthority()).owner();
            try TimelockController(payable(owner)).getMinDelay() returns (uint256 delay) {
                address[] memory targets = new address[](serializedTxs.length);
                bytes[] memory payloads = new bytes[](serializedTxs.length);
                for (uint256 i; i < targets.length; ++i) {
                    require(serializedTxs[i].value == 0, "DeployAndSetup: timelock value unsupported");
                    targets[i] = serializedTxs[i].to;
                    payloads[i] = serializedTxs[i].data;
                }
                delete serializedTxs;
                _buildTimelockBatches(
                    owner,
                    targets,
                    payloads,
                    keccak256(abi.encode(vaultConfig.symbol, "DeployAndSetup:V2")),
                    delay,
                    "DeployAndSetup-Schedule",
                    "DeployAndSetup-Execute"
                );
                return;
            } catch {}
        }
        writeMsigBatch("DeployAndSetup");
    }

    function setUp() public virtual {
        // Config loaded here for legacy runDirect/runMsig; run(string) loads its own.
        try vm.envString("VAULT_SYMBOL") returns (string memory vaultSymbol) {
            loadConfigs(vaultSymbol);
            snapshotCommon();
            overlayDeploymentOutput();
        } catch {}
        _parseSteps();
    }

    /// @notice Hybrid entry point: broadcasts txs the deployer can execute directly,
    ///         queues the rest into a Safe multisig JSON batch.
    function run(string memory vaultSymbol) external {
        console.log(msg.sender);
        loadConfigs(vaultSymbol);
        snapshotCommon();
        overlayDeploymentOutput();
        _parseSteps();

        _requireComplianceReady();
        // Verify CREATE3 addresses match reference deployment (if REFERENCE_CHAIN_ID is set)
        verifyCreate3Addresses();

        hybridMode = true;
        vm.startBroadcast(deployerPrivateKey);

        if (stepOperator) {
            console.log("=== Step 1: Deploy Operators ===");
            _deployOperators();
        }
        if (stepDeploy) {
            console.log("=== Step 2: Deploy Core Vault ===");
            _deployVaultStack();
        }
        if (stepComposer) {
            console.log("=== Step 3: Deploy Composer ===");
            _deployComposers();
        }
        if (stepAuthority) {
            console.log("=== Step 4: Setup Authority ===");
            _setupAuthority();
        }
        if (stepL0) {
            console.log("=== Step 5: Setup LayerZero ===");
            _setupL0Source();
        }
        if (stepShare) {
            console.log("=== Step 6: Set Share Vault ===");
            _setupShareVaults();
        }

        vm.stopBroadcast();

        _printSummary();
        _writeOutput();
        _writeSetupBatch();
    }

    function runDirect() external {
        _requireDirectModeCanWirePredicateProxy();
        _run(false);
    }

    /// @dev Direct Mode preflight for runs that include authority wiring. A fresh PredicateProxy
    ///      initializes with owner = resolvedOwner, while an existing one may delegate setAuthority
    ///      through its current Authority. Fail before any deployment when the broadcaster cannot
    ///      perform a setAuthority the run would actually issue; deploy-only runs remain valid.
    function _requireDirectModeCanWirePredicateProxy() internal view {
        address pp = vaultConfig.common.predicateProxy;
        bool freshDeploy = !isV2Only() && stepDeploy && stepAuthority && needsDeploy(pp)
            && bytes(vaultConfig.compliance.v1.policyID).length > 0
            && ConfigReader.resolvedOwner(vaultConfig) != deployer();
        bool cannotWireExisting = !isV2Only() && stepAuthority && isActive(pp) && pp.code.length > 0
            && _predicateProxyNeedsWiring(pp) && !_canDeployerSetAuthority(pp);
        require(
            !freshDeploy && !cannotWireExisting,
            "DeployAndSetup: Direct Mode cannot setAuthority on a Safe-owned PredicateProxy - use hybrid run(string)"
        );
    }

    /// @dev Mirrors _setAuthorityIfNeeded: setAuthority is issued only when the proxy's authority differs
    ///      from the common RolesAuthority the run will use (unknown yet when this run deploys it).
    function _predicateProxyNeedsWiring(address pp) internal view returns (bool) {
        if (stepDeploy && needsDeploy(vaultConfig.common.commonRolesAuthority)) return true;
        return address(Auth(pp).authority()) != _resolveCommonRolesAuthority();
    }

    function _canDeployerSetAuthority(address target) internal view returns (bool) {
        address broadcaster = deployer();
        if (Auth(target).owner() == broadcaster) return true;

        Authority current = Auth(target).authority();
        if (address(current) == address(0)) return false;
        try current.canCall(broadcaster, target, Auth.setAuthority.selector) returns (bool allowed) {
            return allowed;
        } catch {
            return false;
        }
    }

    function runMsig() external {
        _run(true);
        _writeSetupBatch();
    }

    function _run(bool _msigMode) internal {
        _requireComplianceReady();
        // Verify CREATE3 addresses match reference deployment (if REFERENCE_CHAIN_ID is set)
        verifyCreate3Addresses();

        _runInner(_msigMode);
    }

    function _runInner(bool _msigMode) internal directOrMsig(_msigMode) {
        if (stepOperator) {
            console.log("=== Step 1: Deploy Operators ===");
            _deployOperators();
        }

        if (stepDeploy) {
            console.log("=== Step 2: Deploy Core Vault ===");
            _deployVaultStack();
        }

        if (stepComposer) {
            console.log("=== Step 3: Deploy Composer ===");
            _deployComposers();
        }

        if (stepAuthority) {
            console.log("=== Step 4: Setup Authority ===");
            _setupAuthority();
        }

        if (stepL0) {
            console.log("=== Step 5: Setup LayerZero ===");
            _setupL0Source();
        }

        if (stepShare) {
            console.log("=== Step 6: Set Share Vault ===");
            _setupShareVaults();
        }

        _printSummary();
        _writeOutput();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  STEP 1 — Deploy Core Vault Stack
    // ═══════════════════════════════════════════════════════════════════

    function _deployVaultStack() internal {
        // 1a. RolesAuthority (vault-specific)
        if (needsDeploy(vaultConfig.contracts.rolesAuthority)) {
            bytes32 salt = generateCreate3Salt("RolesAuthority");
            rolesAuthority = CREATEX.deployCreate3(
                salt, abi.encodePacked(type(RolesAuthority).creationCode, abi.encode(deployer(), Authority(address(0))))
            );
            _logDeploy("RolesAuthority", rolesAuthority);
        } else {
            rolesAuthority = vaultConfig.contracts.rolesAuthority;
            _logExists("RolesAuthority", rolesAuthority);
        }

        // 1b. CommonRolesAuthority (for common contracts: operatorRegistry, redeemOperator, cctpRelayer, predicateProxy)
        if (needsDeploy(vaultConfig.common.commonRolesAuthority)) {
            bytes32 salt = generateCreate3SaltCommon("Nest RolesAuthority");
            commonRolesAuthority = CREATEX.deployCreate3(
                salt, abi.encodePacked(type(RolesAuthority).creationCode, abi.encode(deployer(), Authority(address(0))))
            );
            _logDeploy("CommonRolesAuthority", commonRolesAuthority);
        } else {
            commonRolesAuthority = vaultConfig.common.commonRolesAuthority;
            _logExists("CommonRolesAuthority", commonRolesAuthority);
        }

        // 2. NestShareOFT
        if (needsDeploy(vaultConfig.contracts.share)) {
            NestShareOFT impl = new NestShareOFT(lzConfig.endpoint);
            bytes memory initData = abi.encodeWithSelector(
                NestShareOFT.initialize.selector, vaultConfig.name, vaultConfig.symbol, deployer(), deployer()
            );
            bytes32 salt = generateCreate3Salt("NestShareOFT");
            vaultConfig.contracts.share = CREATEX.deployCreate3(
                salt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode, abi.encode(address(impl), deployer(), initData)
                )
            );
            _logDeploy("NestShareOFT", vaultConfig.contracts.share);
        }

        // 3. NestAccountant — impl + init resolved from `.accountantType` / `.hubChainId`
        //    (same resolution Upgrade.s.sol uses). New deployments are born as the
        //    configured type: Hub on the hub chain, Spoke elsewhere, base otherwise.
        //    Deploying the Hub impl directly is what seeds the perf-fee high-water-mark
        //    at `startingExchangeRate` — the legacy deploy-base-then-upgrade path left
        //    the checkpoint at 0. The CREATE3 salt is unchanged, so the proxy address is
        //    identical regardless of impl.
        if (needsDeploy(vaultConfig.contracts.accountant)) {
            address baseAsset = ConfigReader.readAssetAddress(vaultConfig.deployChainId, vaultConfig.baseAssetSymbol);
            bytes32 typeHash = keccak256(bytes(effectiveAccountantType()));

            address impl;
            bytes memory initData;
            if (typeHash == keccak256("NestHubAccountant")) {
                impl = address(new NestHubAccountant(baseAsset, vaultConfig.contracts.share));
                // performanceFee/hurdleRate/holdbackRate/crystallizationWindow/epochsPerWindow
                // are not in the AccountantParams struct; read straight from the vault JSON,
                // defaulting to 0 (matching SetupFees + prior on-chain state).
                initData = abi.encodeWithSelector(
                    NestHubAccountant.initialize.selector,
                    vaultConfig.accountantParams.totalSharesLastUpdate,
                    vaultConfig.accountantParams.payoutAddress,
                    vaultConfig.accountantParams.startingExchangeRate,
                    vaultConfig.accountantParams.allowedExchangeRateChangeUpper,
                    vaultConfig.accountantParams.allowedExchangeRateChangeLower,
                    vaultConfig.accountantParams.minimumUpdateDelayInSeconds,
                    vaultConfig.accountantParams.managementFee,
                    uint32(_tryReadUint(".accountantParams.performanceFee")),
                    uint32(_tryReadUint(".accountantParams.hurdleRate")),
                    uint32(_tryReadUint(".accountantParams.holdbackRate")),
                    uint32(_tryReadUint(".accountantParams.crystallizationWindow")),
                    uint32(_tryReadUint(".accountantParams.epochsPerWindow")),
                    deployer()
                );
            } else if (typeHash == keccak256("NestSpokeAccountant")) {
                impl = address(new NestSpokeAccountant(baseAsset, vaultConfig.contracts.share));
                initData = abi.encodeWithSelector(
                    NestSpokeAccountant.initialize.selector,
                    vaultConfig.accountantParams.startingExchangeRate,
                    vaultConfig.accountantParams.allowedExchangeRateChangeUpper,
                    vaultConfig.accountantParams.allowedExchangeRateChangeLower,
                    vaultConfig.accountantParams.minimumUpdateDelayInSeconds,
                    deployer()
                );
            } else {
                impl = address(new NestAccountant(baseAsset, vaultConfig.contracts.share));
                initData = abi.encodeWithSelector(
                    NestAccountant.initialize.selector,
                    vaultConfig.accountantParams.totalSharesLastUpdate,
                    vaultConfig.accountantParams.payoutAddress,
                    vaultConfig.accountantParams.startingExchangeRate,
                    vaultConfig.accountantParams.allowedExchangeRateChangeUpper,
                    vaultConfig.accountantParams.allowedExchangeRateChangeLower,
                    vaultConfig.accountantParams.minimumUpdateDelayInSeconds,
                    vaultConfig.accountantParams.managementFee,
                    deployer()
                );
            }

            bytes32 salt = generateCreate3Salt("NestAccountant");
            vaultConfig.contracts.accountant = CREATEX.deployCreate3(
                salt,
                abi.encodePacked(type(TransparentUpgradeableProxy).creationCode, abi.encode(impl, deployer(), initData))
            );
            _logDeploy(effectiveAccountantType(), vaultConfig.contracts.accountant);
        }

        // 4. BlacklistHook (common contract)
        if (needsDeploy(vaultConfig.common.blacklistHook)) {
            bytes32 salt = generateCreate3SaltCommon("BlacklistHook");
            vaultConfig.common.blacklistHook = CREATEX.deployCreate3(
                salt, abi.encodePacked(type(BlacklistHook).creationCode, abi.encode(deployer(), Authority(address(0))))
            );
            _logDeploy("BlacklistHook", vaultConfig.common.blacklistHook);
        }
        // Set hook on share only when the current impl exposes `hook()`. If the
        // share is an older impl lacking the getter, defer to Upgrade.s.sol which
        // runs setBeforeTransferHook post-upgrade — queuing against the old impl
        // would revert in the Safe batch.
        if (isActive(vaultConfig.common.blacklistHook) && isActive(vaultConfig.contracts.share)) {
            string memory hookLabel = "setBeforeTransferHook";
            try NestShareOFT(payable(vaultConfig.contracts.share)).hook() returns (ITransferHook currentHook) {
                if (address(currentHook) != vaultConfig.common.blacklistHook) {
                    console.log(string.concat("    [SETUP] ", hookLabel));
                    execute(
                        vaultConfig.contracts.share,
                        abi.encodeCall(NestShareOFT.setBeforeTransferHook, (vaultConfig.common.blacklistHook)),
                        hookLabel
                    );
                } else {
                    _logSkipped(hookLabel);
                }
            } catch {
                _logSkipped(string.concat(hookLabel, " (deferred to Upgrade)"));
            }
        }

        // 5. One vault per entry
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (!needsDeploy(ve.addr)) continue;

            address asset = ConfigReader.readAssetAddress(vaultConfig.deployChainId, ve.assetSymbol);
            vaultConfig.vaults[i].addr = _deployVault(asset, ve.assetSymbol);
            _logDeploy(string.concat("Vault-", ve.assetSymbol), vaultConfig.vaults[i].addr);
            _bootstrapVaultFees(vaultConfig.vaults[i].addr, ve.assetSymbol);
        }

        // 6. Set rate provider data for non-base deposit assets
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (keccak256(bytes(ve.assetSymbol)) == keccak256(bytes(vaultConfig.baseAssetSymbol))) continue;

            address asset = ConfigReader.readAssetAddress(vaultConfig.deployChainId, ve.assetSymbol);
            // Check if rate provider data is already set by trying getRateInQuote
            try NestAccountant(vaultConfig.contracts.accountant).getRateInQuote(ERC20(asset)) {
                _logSkipped(string.concat("setRateProviderData(", ve.assetSymbol, ")"));
                continue;
            } catch {}
            execute(
                vaultConfig.contracts.accountant,
                abi.encodeCall(NestAccountant.setRateProviderData, (ERC20(asset), ve.isPegged, ve.rateProvider)),
                string.concat("setRateProviderData(", ve.assetSymbol, ")")
            );
        }

        // 7. NestVaultPredicateProxy
        if (
            !isV2Only() && needsDeploy(vaultConfig.common.predicateProxy)
                && bytes(vaultConfig.compliance.v1.policyID).length > 0
        ) {
            NestVaultPredicateProxy impl = new NestVaultPredicateProxy();
            bytes memory initData = abi.encodeWithSelector(
                NestVaultPredicateProxy.initialize.selector,
                ConfigReader.resolvedOwner(vaultConfig),
                chainComplianceConfig.v1.serviceManager,
                vaultConfig.compliance.v1.policyID
            );
            bytes32 salt = generateCreate3SaltCommon("NestVaultPredicateProxy");
            vaultConfig.common.predicateProxy = CREATEX.deployCreate3(
                salt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode, abi.encode(address(impl), deployer(), initData)
                )
            );
            _logDeploy("PredicateProxy", vaultConfig.common.predicateProxy);
        }
    }

    function _deployVault(address asset, string memory assetSymbol) internal returns (address) {
        if (isOFT()) {
            address impl = address(
                new NestVaultOFT(payable(vaultConfig.contracts.share), lzConfig.endpoint, commonConfig.permit2)
            );
            bytes memory initData = abi.encodeWithSignature(
                "initialize(address,address,address,address,uint256,address)",
                vaultConfig.contracts.accountant,
                asset,
                deployer(),
                deployer(),
                vaultConfig.minRate,
                vaultConfig.common.operatorRegistry
            );
            bytes32 salt = generateCreate3SaltForAsset("NestVaultOFT", assetSymbol);
            return CREATEX.deployCreate3(
                salt,
                abi.encodePacked(type(TransparentUpgradeableProxy).creationCode, abi.encode(impl, deployer(), initData))
            );
        } else {
            address impl = address(new NestVault(payable(vaultConfig.contracts.share), commonConfig.permit2));
            bytes memory initData = abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                vaultConfig.contracts.accountant,
                asset,
                deployer(),
                vaultConfig.minRate,
                vaultConfig.common.operatorRegistry
            );
            bytes32 salt = generateCreate3SaltForAsset("NestVault", assetSymbol);
            return CREATEX.deployCreate3(
                salt,
                abi.encodePacked(type(TransparentUpgradeableProxy).creationCode, abi.encode(impl, deployer(), initData))
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  STEP 2 — Deploy Operators
    // ═══════════════════════════════════════════════════════════════════

    function _deployOperators() internal {
        if (needsDeploy(vaultConfig.common.operatorRegistry)) {
            bytes32 salt = generateCreate3SaltCommon("OperatorRegistry");
            vaultConfig.common.operatorRegistry = CREATEX.deployCreate3(
                salt,
                abi.encodePacked(
                    type(OperatorRegistry).creationCode, abi.encode(deployer(), Authority(commonRolesAuthority))
                )
            );
            _logDeploy("OperatorRegistry", vaultConfig.common.operatorRegistry);
        }

        if (needsDeploy(vaultConfig.common.redeemOperator)) {
            NestVaultRedeemOperator impl = new NestVaultRedeemOperator();
            bytes memory initData = abi.encodeWithSelector(NestVaultRedeemOperator.initialize.selector, deployer());
            bytes32 salt = generateCreate3SaltCommon("NestVaultRedeemOperator");
            vaultConfig.common.redeemOperator = CREATEX.deployCreate3(
                salt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode, abi.encode(address(impl), deployer(), initData)
                )
            );
            _logDeploy("RedeemOperator", vaultConfig.common.redeemOperator);
        }

        if (needsDeploy(vaultConfig.common.seizer)) {
            bytes32 salt = generateCreate3SaltCommon("NestShareSeizer");
            vaultConfig.common.seizer = CREATEX.deployCreate3(
                salt,
                abi.encodePacked(type(NestShareSeizer).creationCode, abi.encode(deployer(), Authority(address(0))))
            );
            _logDeploy("NestShareSeizer", vaultConfig.common.seizer);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  STEP 3 — Deploy Composers / CCTP Relayer
    // ═══════════════════════════════════════════════════════════════════

    function _deployComposers() internal {
        // 1. Deploy NestCCTPRelayer (shared across all vault entries) — only on chains with CCTP
        if (needsDeploy(vaultConfig.common.cctpRelayer)) {
            (bool hasCCTP, CCTPConfig memory cctpConfig) = ConfigReader.tryReadCCTPConfig(vaultConfig.deployChainId);
            if (!hasCCTP) {
                console.log("    [SKIP] NestCCTPRelayer: no CCTP config for this chain");
            } else {
                address usdc = ConfigReader.readAssetAddress(vaultConfig.deployChainId, "USDC");
                NestCCTPRelayer impl = new NestCCTPRelayer(
                    cctpConfig.messageTransmitter, cctpConfig.tokenMessenger, lzConfig.endpoint, usdc
                );
                bytes memory initData = abi.encodeWithSelector(NestCCTPRelayer.initialize.selector, deployer());
                bytes32 salt = generateCreate3SaltCommon("NestCCTPRelayer");
                vaultConfig.common.cctpRelayer = CREATEX.deployCreate3(
                    salt,
                    abi.encodePacked(
                        type(TransparentUpgradeableProxy).creationCode, abi.encode(address(impl), deployer(), initData)
                    )
                );
                _logDeploy("NestCCTPRelayer", vaultConfig.common.cctpRelayer);
            }
        }

        // 2. Deploy NestVaultComposer per vault entry (only for base asset)
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (!needsDeploy(ve.composer)) continue;
            if (keccak256(bytes(ve.assetSymbol)) != keccak256(bytes(vaultConfig.baseAssetSymbol))) continue;
            if (ve.addr.code.length == 0) continue; // vault not deployed on this chain yet
            if (!isActive(vaultConfig.common.cctpRelayer)) continue; // no asset OFT without CCTP relayer

            (bool hasComplianceConfig, address complianceProxy) =
                ConfigReader.tryReadComplianceProxy(vaultConfig.deployChainId, vaultConfig.symbol);
            if (isV2Only()) {
                complianceProxy = vaultConfig.common.complianceProxy;
                hasComplianceConfig = true;
            }
            if (!hasComplianceConfig || complianceProxy.code.length == 0) {
                console.log("[SKIP] NestVaultComposer: complianceProxy not deployed");
                continue;
            }
            NestVaultComposer impl = new NestVaultComposer(complianceProxy);
            bytes memory initData = abi.encodeWithSelector(
                NestVaultComposer.initialize.selector,
                deployer(),
                ve.addr,
                isActive(vaultConfig.common.cctpRelayer) ? vaultConfig.common.cctpRelayer : address(0),
                isOFT() ? ve.addr : vaultConfig.contracts.share,
                vaultConfig.maxRetryableValue
            );
            bytes32 salt = generateCreate3SaltForAsset("NestVaultComposer", ve.assetSymbol);
            vaultConfig.vaults[i].composer = CREATEX.deployCreate3(
                salt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode, abi.encode(address(impl), deployer(), initData)
                )
            );
            _logDeploy(string.concat("NestVaultComposer-", ve.assetSymbol), vaultConfig.vaults[i].composer);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  STEP 4 — Setup Authority
    // ═══════════════════════════════════════════════════════════════════

    function _setupAuthority() internal {
        address vaultAuth = _resolveRolesAuthority();
        address commonAuth = _resolveCommonRolesAuthority();
        require(vaultAuth != address(0), "DeployAndSetup: rolesAuthority not set");
        require(commonAuth != address(0), "DeployAndSetup: commonRolesAuthority not set");

        console.log("    VaultAuthority:", vaultAuth);
        console.log("    CommonAuthority:", commonAuth);

        // Revoke roles from old contract addresses if a prior deployment output exists
        _revokeOldRoles(vaultAuth, commonAuth);

        _setAuthorityOnContracts(vaultAuth, commonAuth);

        // Assert all contracts now use the expected authority
        _assertAuthorities(vaultAuth, commonAuth);

        // User-facing role/public capabilities are processed below. Fresh vaults are
        // bootstrapped in the deploy step; retries and standalone authority runs must
        // prove the reviewed active fees are already live before opening those routes.
        _requireVaultFeesReadyForLaunch();

        string memory root = vm.projectRoot();

        // Vault authority config (governs share, accountant, vaults, composers)
        console.log("    Processing vault authority config...");
        string memory vaultJson = vm.readFile(string.concat(root, "/config/authority/authority.json"));
        _processCapabilities(vaultJson, vaultAuth);
        _processPublicCapabilities(vaultJson, vaultAuth);
        _processRoleAssignments(vaultJson, vaultAuth);
        if (isV2Only()) _configureV2VaultAccess(vaultAuth);

        // Common authority config (governs predicateProxy, operatorRegistry, redeemOperator, cctpRelayer)
        console.log("    Processing common authority config...");
        string memory commonJson = vm.readFile(string.concat(root, "/config/authority/common-authority.json"));
        _processCapabilities(commonJson, commonAuth);
        _processPublicCapabilities(commonJson, commonAuth);
        _processRoleAssignments(commonJson, commonAuth);

        // Wire relayer <-> composers and set eid-to-domain mappings
        // (must happen after authority config so the caller has OWNER_ROLE)
        _wireRelayer();
        _wireOperatorRegistry();
        _approveUnlooperTargets();
    }

    /// @dev Idempotently approves each chain-active vault and optional legacyTeller in NestUnlooper
    ///      so keepers can call `execute` against them ([NestUnlooper.sol:241-246]).
    function _approveUnlooperTargets() internal {
        if (!isActive(vaultConfig.common.nestUnlooper)) return;
        NestUnlooper unlooper = NestUnlooper(vaultConfig.common.nestUnlooper);

        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            _approveOnUnlooper(unlooper, vaultConfig.vaults[i].addr);
            _approveOnUnlooper(unlooper, vaultConfig.vaults[i].legacyTeller);
        }
    }

    function _approveOnUnlooper(NestUnlooper unlooper, address target) internal {
        if (!isActive(target)) return;
        try unlooper.approvedVault(target) returns (bool approved) {
            if (approved) {
                _logSkipped(string.concat("setVaultApproval(", vm.toString(target), ")"));
                return;
            }
        } catch {}
        execute(
            address(unlooper),
            abi.encodeCall(NestUnlooper.setVaultApproval, (target, true)),
            string.concat("setVaultApproval(", vm.toString(target), ")")
        );
    }

    function _wireRelayer() internal {
        if (!isActive(vaultConfig.common.cctpRelayer)) return;

        NestCCTPRelayer relayer = NestCCTPRelayer(payable(vaultConfig.common.cctpRelayer));

        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            address composer = vaultConfig.vaults[i].composer;
            if (composer != address(0) && !relayer.isComposer(composer)) {
                execute(
                    vaultConfig.common.cctpRelayer,
                    abi.encodeCall(NestCCTPRelayer.setComposer, (composer, true)),
                    "setComposer"
                );
            }
        }

        for (uint256 i = 0; i < vaultConfig.peers.length; i++) {
            uint256 peerChainId = vaultConfig.peers[i];
            if (peerChainId == vaultConfig.deployChainId) continue;

            (bool hasCCTP, CCTPConfig memory peerCCTP) = ConfigReader.tryReadCCTPConfig(peerChainId);
            if (!hasCCTP) continue; // Skip peers without CCTP (e.g. BNB, Plasma)

            LZConfig memory peerLZ = ConfigReader.readLZConfig(peerChainId);
            if (_relayerDomainMatches(relayer, peerLZ.eid, peerCCTP.domain)) continue;
            uint32[] memory eids = new uint32[](1);
            eids[0] = peerLZ.eid;
            uint32[] memory domains = new uint32[](1);
            domains[0] = peerCCTP.domain;
            execute(
                vaultConfig.common.cctpRelayer,
                abi.encodeCall(NestCCTPRelayer.setEidToDomain, (eids, domains)),
                string.concat("setEidToDomain(eid=", vm.toString(peerLZ.eid), ")")
            );
        }

        _wireRelayerRuntimeConfig(relayer);
    }

    /// @dev Converges the reviewed runtime policy when config/cctp defines it; warns when the live value is
    ///      still 0 and no key exists. Legacy relayers require a fee-switch TokenMessengerV2 to set the cap.
    function _wireRelayerRuntimeConfig(NestCCTPRelayer relayer) internal {
        (bool hasCCTP, CCTPConfig memory localCCTP) = ConfigReader.tryReadCCTPConfig(vaultConfig.deployChainId);
        require(hasCCTP, "DeployAndSetup: CCTP config required for active relayer");

        uint256 liveMaxFee = relayer.getMaxFeeBasisPoints();
        if (localCCTP.maxFeeBasisPoints != 0 && liveMaxFee != localCCTP.maxFeeBasisPoints) {
            if (!_feeCapSettable(relayer)) {
                console.log(
                    "    [WARN] cctpRelayer maxFeeBasisPoints cannot be converged: pre-fee-switch token messenger and a relayer impl without the getMinFeeAmount fallback (setMaxFeeBasisPoints would revert); upgrade the relayer first"
                );
            } else {
                execute(
                    vaultConfig.common.cctpRelayer,
                    abi.encodeCall(NestCCTPRelayer.setMaxFeeBasisPoints, (localCCTP.maxFeeBasisPoints)),
                    string.concat("setMaxFeeBasisPoints(", vm.toString(localCCTP.maxFeeBasisPoints), ")")
                );
            }
        } else if (liveMaxFee == 0) {
            console.log(
                "    [WARN] cctpRelayer maxFeeBasisPoints=0: send() reverts while Circle minFee > 0; add maxFeeBasisPoints to config/cctp/<chainId>.json or set manually (contracts/integrations/cctp/README.md)"
            );
        }

        uint32 liveFinality = relayer.getFinalityThreshold();
        if (localCCTP.finalityThreshold != 0 && liveFinality != localCCTP.finalityThreshold) {
            execute(
                vaultConfig.common.cctpRelayer,
                abi.encodeCall(NestCCTPRelayer.setFinalityThreshold, (localCCTP.finalityThreshold)),
                string.concat("setFinalityThreshold(", vm.toString(localCCTP.finalityThreshold), ")")
            );
        } else if (liveFinality == 0) {
            console.log(
                "    [WARN] cctpRelayer finalityThreshold=0: set 1000 (fast) or 2000 (finalized) via config/cctp or manually"
            );
        }
    }

    /// @dev setMaxFeeBasisPoints needs a minimum-fee read: either the relayer's own fallback (which treats an
    ///      absent fee switch as a zero floor) or, on older relayer impls, the messenger's getMinFeeAmount.
    function _feeCapSettable(NestCCTPRelayer relayer) internal view returns (bool ok) {
        bytes memory probe = abi.encodeCall(ITokenMessengerV2.getMinFeeAmount, (10_000));

        (ok,) = address(relayer).staticcall(probe);
        if (ok) return true;

        (ok,) = address(relayer.TOKEN_MESSENGER()).staticcall(probe);
    }

    function _relayerDomainMatches(NestCCTPRelayer relayer, uint32 eid, uint32 domain) internal view returns (bool) {
        try relayer.getEidToDomain(eid) returns (uint32 configuredDomain) {
            return configuredDomain == domain;
        } catch {
            return false;
        }
    }

    function _wireOperatorRegistry() internal {
        if (!isActive(vaultConfig.common.operatorRegistry)) return;

        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            address vaultAddr = vaultConfig.vaults[i].addr;
            if (!isActive(vaultAddr)) continue;
            string memory label = string.concat("setOperatorRegistry(", vaultConfig.vaults[i].assetSymbol, ")");
            (bool ok, bytes memory ret) = vaultAddr.staticcall(abi.encodeWithSignature("operatorRegistry()"));
            // Old vault impls lack operatorRegistry() selector — defer to Upgrade.s.sol
            // which queues setOperatorRegistry after the proxy is upgraded.
            if (!ok) {
                _logSkipped(string.concat(label, " (deferred to Upgrade)"));
                continue;
            }
            if (abi.decode(ret, (address)) == vaultConfig.common.operatorRegistry) {
                _logSkipped(label);
                continue;
            }
            execute(
                vaultAddr,
                abi.encodeWithSignature("setOperatorRegistry(address)", vaultConfig.common.operatorRegistry),
                label
            );
        }
    }

    /// @notice Loads the prior deployment output from script/deployment-config/revoke/ and revokes roles
    ///         from any contract addresses that have changed (i.e., were redeployed).
    function _revokeOldRoles(address vaultAuth, address commonAuth) internal {
        (
            bool exists,
            VaultContracts memory oldContracts,
            CommonContracts memory oldCommon,
            VaultEntry[] memory oldVaults
        ) = ConfigReader.readOldOutput(vaultConfig.deployChainId, vaultConfig.symbol);

        if (!exists) return;
        console.log("    Revoking roles from old contract addresses...");

        // Composer: role 12 on vault authority + role 12 on common authority
        for (uint256 i = 0; i < oldVaults.length; i++) {
            address oldComposer = oldVaults[i].composer;
            if (!isActive(oldComposer)) continue;
            // Find the matching new composer by assetSymbol
            bool changed = true;
            for (uint256 j = 0; j < vaultConfig.vaults.length; j++) {
                if (keccak256(bytes(oldVaults[i].assetSymbol)) == keccak256(bytes(vaultConfig.vaults[j].assetSymbol))) {
                    if (oldComposer == vaultConfig.vaults[j].composer) changed = false;
                    break;
                }
            }
            if (changed) {
                if (RolesAuthority(vaultAuth).doesUserHaveRole(oldComposer, 12)) {
                    execute(
                        vaultAuth,
                        abi.encodeCall(RolesAuthority.setUserRole, (oldComposer, 12, false)),
                        "revokeUserRole(oldComposer, role=12, vaultAuth)"
                    );
                }
                if (RolesAuthority(commonAuth).doesUserHaveRole(oldComposer, 12)) {
                    execute(
                        commonAuth,
                        abi.encodeCall(RolesAuthority.setUserRole, (oldComposer, 12, false)),
                        "revokeUserRole(oldComposer, role=12, commonAuth)"
                    );
                }
            }
        }

        // CCTPRelayer: role 13 on vault authority
        if (isActive(oldCommon.cctpRelayer) && oldCommon.cctpRelayer != vaultConfig.common.cctpRelayer) {
            if (RolesAuthority(vaultAuth).doesUserHaveRole(oldCommon.cctpRelayer, 13)) {
                execute(
                    vaultAuth,
                    abi.encodeCall(RolesAuthority.setUserRole, (oldCommon.cctpRelayer, 13, false)),
                    "revokeUserRole(oldCctpRelayer, role=13)"
                );
            }
        }

        // RedeemOperator: role 11 on vault authority
        if (isActive(oldCommon.redeemOperator) && oldCommon.redeemOperator != vaultConfig.common.redeemOperator) {
            if (RolesAuthority(vaultAuth).doesUserHaveRole(oldCommon.redeemOperator, 11)) {
                execute(
                    vaultAuth,
                    abi.encodeCall(RolesAuthority.setUserRole, (oldCommon.redeemOperator, 11, false)),
                    "revokeUserRole(oldRedeemOperator, role=11)"
                );
            }
        }

        // Seizer: role 15 on vault authority
        if (isActive(oldCommon.seizer) && oldCommon.seizer != vaultConfig.common.seizer) {
            if (RolesAuthority(vaultAuth).doesUserHaveRole(oldCommon.seizer, 15)) {
                execute(
                    vaultAuth,
                    abi.encodeCall(RolesAuthority.setUserRole, (oldCommon.seizer, 15, false)),
                    "revokeUserRole(oldSeizer, role=15)"
                );
            }
        }

        // Vault: role 3 on vault authority
        for (uint256 i = 0; i < oldVaults.length; i++) {
            address oldVaultAddr = oldVaults[i].addr;
            if (!isActive(oldVaultAddr)) continue;
            bool changed = true;
            for (uint256 j = 0; j < vaultConfig.vaults.length; j++) {
                if (keccak256(bytes(oldVaults[i].assetSymbol)) == keccak256(bytes(vaultConfig.vaults[j].assetSymbol))) {
                    if (oldVaultAddr == vaultConfig.vaults[j].addr) changed = false;
                    break;
                }
            }
            if (changed && RolesAuthority(vaultAuth).doesUserHaveRole(oldVaultAddr, 3)) {
                execute(
                    vaultAuth,
                    abi.encodeCall(RolesAuthority.setUserRole, (oldVaultAddr, 3, false)),
                    "revokeUserRole(oldVault, role=3)"
                );
            }
        }

        // PredicateProxy: role 7 on vault authority
        if (isActive(oldCommon.predicateProxy) && oldCommon.predicateProxy != vaultConfig.common.predicateProxy) {
            if (RolesAuthority(vaultAuth).doesUserHaveRole(oldCommon.predicateProxy, 7)) {
                execute(
                    vaultAuth,
                    abi.encodeCall(RolesAuthority.setUserRole, (oldCommon.predicateProxy, 7, false)),
                    "revokeUserRole(oldPredicateProxy, role=7)"
                );
            }
        }
    }

    /// @dev Uses the locally deployed authority if available, otherwise derives from on-chain share.authority().
    function _resolveRolesAuthority() internal view override returns (address) {
        if (rolesAuthority != address(0)) return rolesAuthority;
        if (vaultConfig.contracts.share.code.length > 0) {
            return address(Auth(vaultConfig.contracts.share).authority());
        }
        return address(0);
    }

    /// @dev Uses the locally deployed authority if available, otherwise falls back to the base resolver.
    function _resolveCommonRolesAuthority() internal view override returns (address) {
        if (commonRolesAuthority != address(0)) return commonRolesAuthority;
        return super._resolveCommonRolesAuthority();
    }

    function _setAuthorityOnContracts(address vaultAuth, address commonAuth) internal {
        Authority vaultAuthority = Authority(vaultAuth);
        Authority commonAuthority = Authority(commonAuth);

        // Vault-specific contracts → vault authority
        _setAuthorityIfNeeded("share", vaultConfig.contracts.share, vaultAuthority);
        _setAuthorityIfNeeded("accountant", vaultConfig.contracts.accountant, vaultAuthority);
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            _setAuthorityIfNeeded(string.concat("vault-", ve.assetSymbol), ve.addr, vaultAuthority);
            // Composer is per-chain optional (skipped on CCTP-less chains). Filter it here so
            // the shared setter can fail closed for every active target it receives.
            if (!isActive(ve.composer) || ve.composer.code.length > 0) {
                _setAuthorityIfNeeded(string.concat("composer-", ve.assetSymbol), ve.composer, vaultAuthority);
            } else {
                _logSkipped(string.concat("setAuthority(composer-", ve.assetSymbol, ") - optional target not deployed"));
            }
        }

        // Common/infrastructure contracts → common authority. A V2-only vault never touches the V1 proxy.
        if (!isV2Only()) {
            _setAuthorityIfNeeded("predicateProxy", vaultConfig.common.predicateProxy, commonAuthority);
        }
        if (isActive(vaultConfig.common.operatorRegistry)) {
            _setAuthorityIfNeeded("operatorRegistry", vaultConfig.common.operatorRegistry, commonAuthority);
        }
        if (isActive(vaultConfig.common.cctpRelayer)) {
            _setAuthorityIfNeeded("cctpRelayer", vaultConfig.common.cctpRelayer, commonAuthority);
        }
        if (isActive(vaultConfig.common.redeemOperator)) {
            _setAuthorityIfNeeded("redeemOperator", vaultConfig.common.redeemOperator, commonAuthority);
        }
        if (isActive(vaultConfig.common.seizer)) {
            _setAuthorityIfNeeded("seizer", vaultConfig.common.seizer, commonAuthority);
        }
        if (isActive(vaultConfig.common.blacklistHook)) {
            _setAuthorityIfNeeded("blacklistHook", vaultConfig.common.blacklistHook, commonAuthority);
        }
        if (isActive(vaultConfig.common.nestUnlooper)) {
            _setAuthorityIfNeeded("nestUnlooper", vaultConfig.common.nestUnlooper, commonAuthority);
        }
    }

    /// @dev Only calls setAuthority when the on-chain authority is unset or differs from expected.
    function _setAuthorityIfNeeded(string memory name, address target, Authority expected) internal {
        if (!isActive(target)) return;
        string memory label = string.concat("setAuthority(", name, ")");
        Authority current = _readAuthority(name, target);
        if (current == expected) {
            _logSkipped(label);
            return;
        }
        execute(target, abi.encodeCall(Auth.setAuthority, (expected)), label);
    }

    /// @dev Asserts that all existing contracts already have the expected authority set on-chain.
    ///      This catches mismatches where a contract was deployed with a different authority.
    function _assertAuthorities(address vaultAuth, address commonAuth) internal view {
        // Vault-specific contracts must use vaultAuth
        _assertAuthority("share", vaultConfig.contracts.share, vaultAuth);
        _assertAuthority("accountant", vaultConfig.contracts.accountant, vaultAuth);
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            _assertAuthority(string.concat("vault-", ve.assetSymbol), ve.addr, vaultAuth);
            // Composer is per-chain optional (skipped on CCTP-less chains) - assert only when deployed.
            if (!isActive(ve.composer) || ve.composer.code.length > 0) {
                _assertAuthority(string.concat("composer-", ve.assetSymbol), ve.composer, vaultAuth);
            }
        }

        // Common contracts must use commonAuth
        if (!isV2Only()) _assertAuthority("predicateProxy", vaultConfig.common.predicateProxy, commonAuth);
        if (isActive(vaultConfig.common.operatorRegistry)) {
            _assertAuthority("operatorRegistry", vaultConfig.common.operatorRegistry, commonAuth);
        }
        if (isActive(vaultConfig.common.redeemOperator)) {
            _assertAuthority("redeemOperator", vaultConfig.common.redeemOperator, commonAuth);
        }
        if (isActive(vaultConfig.common.cctpRelayer)) {
            _assertAuthority("cctpRelayer", vaultConfig.common.cctpRelayer, commonAuth);
        }
        if (isActive(vaultConfig.common.seizer)) {
            _assertAuthority("seizer", vaultConfig.common.seizer, commonAuth);
        }
        if (isActive(vaultConfig.common.blacklistHook)) {
            _assertAuthority("blacklistHook", vaultConfig.common.blacklistHook, commonAuth);
        }
        if (isActive(vaultConfig.common.nestUnlooper)) {
            _assertAuthority("nestUnlooper", vaultConfig.common.nestUnlooper, commonAuth);
        }
    }

    function _assertAuthority(string memory name, address target, address expectedAuth) internal view {
        if (!isActive(target)) return; // 0 or DEAD-disabled
        // Validate the target before routing can skip the live postcondition. Otherwise msig mode
        // accepts EOAs and hybrid mode accepts Safe-owned non-Auth contracts into a doomed batch.
        Authority actual = _readAuthority(name, target);
        // Skip assertion when setAuthority was queued rather than executed — mirrors
        // the routing guard in execute(): pure msigMode queues everything, hybridMode
        // queues only multisig-owned targets.
        if (msigMode || (hybridMode && !_isOwner(target))) return;
        require(
            address(actual) == expectedAuth,
            string.concat(
                "DeployAndSetup: authority mismatch on ",
                name,
                " - expected ",
                vm.toString(expectedAuth),
                " got ",
                vm.toString(address(actual))
            )
        );
    }

    /// @dev Reads Auth.authority() and fails closed for every active target passed by a caller.
    function _readAuthority(string memory name, address target) internal view returns (Authority actual) {
        require(
            target.code.length > 0,
            string.concat(
                "DeployAndSetup: no code at ",
                name,
                " (",
                vm.toString(target),
                ") - configured address is wrong or the deploy step did not run"
            )
        );
        try Auth(target).authority() returns (Authority current) {
            return current;
        } catch {
            revert(
                string.concat("DeployAndSetup: authority() read failed on ", name, " - target is not an Auth contract")
            );
        }
    }

    function _processCapabilities(string memory json, address auth) internal {
        bytes memory rawCaps = json.parseRaw(".capabilities");
        bytes[] memory capsArray = abi.decode(rawCaps, (bytes[]));

        for (uint256 i = 0; i < capsArray.length; i++) {
            string memory prefix = string.concat(".capabilities[", vm.toString(i), "]");

            uint8 role = uint8(json.readUint(string.concat(prefix, ".role")));
            string memory targetName = json.readString(string.concat(prefix, ".target"));

            string memory conditionalOn = _tryReadString(json, string.concat(prefix, ".conditionalOn"));
            if (bytes(conditionalOn).length > 0 && !_checkCondition(conditionalOn)) continue;

            // For vault/composer targets, apply to all vault entries
            address[] memory targets = _resolveTargets(targetName);
            for (uint256 t = 0; t < targets.length; t++) {
                if (!isActive(targets[t])) continue;

                string[] memory functions = json.readStringArray(string.concat(prefix, ".functions"));
                for (uint256 f = 0; f < functions.length; f++) {
                    bytes4 selector = bytes4(keccak256(bytes(functions[f])));
                    string memory capLabel = string.concat(
                        "setRoleCapability(role=",
                        vm.toString(role),
                        ", target=",
                        targetName,
                        ", fn=",
                        functions[f],
                        ")"
                    );
                    if (RolesAuthority(auth).doesRoleHaveCapability(role, targets[t], selector)) {
                        _logSkipped(capLabel);
                        continue;
                    }
                    execute(
                        auth,
                        abi.encodeCall(RolesAuthority.setRoleCapability, (role, targets[t], selector, true)),
                        capLabel
                    );
                }
            }
        }
    }

    function _processPublicCapabilities(string memory json, address auth) internal {
        bytes memory rawPubs = json.parseRaw(".publicCapabilities");
        bytes[] memory pubsArray = abi.decode(rawPubs, (bytes[]));

        for (uint256 i = 0; i < pubsArray.length; i++) {
            string memory prefix = string.concat(".publicCapabilities[", vm.toString(i), "]");

            string memory targetName = json.readString(string.concat(prefix, ".target"));

            string memory conditionalOn = _tryReadString(json, string.concat(prefix, ".conditionalOn"));

            address[] memory targets = _resolveTargets(targetName);
            for (uint256 t = 0; t < targets.length; t++) {
                if (!isActive(targets[t])) continue;

                string[] memory functions = json.readStringArray(string.concat(prefix, ".functions"));
                for (uint256 f = 0; f < functions.length; f++) {
                    bytes4 selector = bytes4(keccak256(bytes(functions[f])));
                    string memory pubLabel =
                        string.concat("setPublicCapability(target=", targetName, ", fn=", functions[f], ")");
                    // Fail closed: condition no longer holds but the reused authority still has this selector
                    // public - revoke with setPublicCapability(target, selector, false) and rerun.
                    if (!_publicCapabilityAllowed(conditionalOn, targetName, selector)) {
                        if (RolesAuthority(auth).isCapabilityPublic(targets[t], selector)) {
                            revert(_stalePublicMsg(conditionalOn, pubLabel));
                        }
                        continue;
                    }
                    if (RolesAuthority(auth).isCapabilityPublic(targets[t], selector)) {
                        _logSkipped(pubLabel);
                        continue;
                    }
                    execute(
                        auth, abi.encodeCall(RolesAuthority.setPublicCapability, (targets[t], selector, true)), pubLabel
                    );
                }
            }
        }
    }

    function _publicCapabilityAllowed(string memory condition, string memory target, bytes4 selector)
        internal
        view
        returns (bool)
    {
        if (isV2Only() && keccak256(bytes(target)) == keccak256("vault") && _requiresV2Proof(selector)) {
            return false;
        }
        return bytes(condition).length == 0 || _checkCondition(condition);
    }

    /// @dev Builds the fail-closed error for a conditional public capability still public on-chain.
    function _stalePublicMsg(string memory conditionalOn, string memory pubLabel)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "DeployAndSetup: stale public capability - '",
            conditionalOn,
            "' no longer holds but on-chain state is public: ",
            pubLabel
        );
    }

    function _processRoleAssignments(string memory json, address auth) internal {
        bytes memory rawAssignments = json.parseRaw(".roleAssignments");
        bytes[] memory assignmentsArray = abi.decode(rawAssignments, (bytes[]));

        for (uint256 i = 0; i < assignmentsArray.length; i++) {
            string memory prefix = string.concat(".roleAssignments[", vm.toString(i), "]");

            string memory userName = json.readString(string.concat(prefix, ".user"));
            uint8 role = uint8(json.readUint(string.concat(prefix, ".role")));

            string memory conditionalOn = _tryReadString(json, string.concat(prefix, ".conditionalOn"));
            if (bytes(conditionalOn).length > 0 && !_checkCondition(conditionalOn)) continue;

            address[] memory users = _resolveUsers(userName);
            for (uint256 u = 0; u < users.length; u++) {
                if (isActive(users[u])) {
                    string memory roleLabel = string.concat(
                        "setUserRole(user=",
                        userName,
                        ", role=",
                        vm.toString(role),
                        ", addr=",
                        vm.toString(users[u]),
                        ")"
                    );
                    if (RolesAuthority(auth).doesUserHaveRole(users[u], role)) {
                        _logSkipped(roleLabel);
                        continue;
                    }
                    execute(auth, abi.encodeCall(RolesAuthority.setUserRole, (users[u], role, true)), roleLabel);
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  STEP 5 — Setup LayerZero (source chain)
    // ═══════════════════════════════════════════════════════════════════

    function _setupL0Source() internal {
        if (isOFT()) {
            _setupL0SourceForVaults();
        } else {
            _setupL0SourceForShare();
        }
    }

    /// @dev Configures DVNs, enforced options, and libraries for the share OFT against every peer chain.
    ///      Peers themselves are not wired here — run SetPeers after all chain deployments complete.
    function _setupL0SourceForShare() internal {
        address share = vaultConfig.contracts.share;
        if (share == address(0)) return;

        _currentLzOft = share;
        console.log("    Configuring LZ for share:", share);
        for (uint256 i = 0; i < vaultConfig.peers.length; i++) {
            uint256 peerChainId = vaultConfig.peers[i];
            if (peerChainId == vaultConfig.deployChainId) continue;

            LZConfig memory peerLZ = ConfigReader.readLZConfig(peerChainId);

            _setEnforcedOptions(share, peerChainId, peerLZ.eid);
            _setDVNs(share, peerChainId);
            _setLibs(share, peerLZ);
            console.log("      LZ configured for eid", vm.toString(peerLZ.eid));
        }
        _currentLzOft = address(0);
    }

    /// @dev Configures DVNs, enforced options, and libraries for this chain's canonical vault OFT
    ///      against every peer chain. Peers themselves are not wired here — run SetupL0 after all
    ///      chain deployments complete. Non-canonical vaults (e.g. pUSD on a USDC-base chain) are
    ///      skipped because they never peer cross-chain.
    function _setupL0SourceForVaults() internal {
        VaultEntry[] memory srcVaults = vaultConfig.vaults;

        for (uint256 v = 0; v < srcVaults.length; v++) {
            if (keccak256(bytes(srcVaults[v].assetSymbol)) != keccak256(bytes(vaultConfig.baseAssetSymbol))) continue;

            address srcVault = srcVaults[v].addr;
            if (srcVault == address(0)) continue;

            _currentLzOft = srcVault;
            console.log("    Configuring LZ for vault:", srcVaults[v].assetSymbol, srcVault);

            for (uint256 i = 0; i < vaultConfig.peers.length; i++) {
                uint256 peerChainId = vaultConfig.peers[i];
                if (peerChainId == vaultConfig.deployChainId) continue;

                LZConfig memory peerLZ = ConfigReader.readLZConfig(peerChainId);

                _setEnforcedOptions(srcVault, peerChainId, peerLZ.eid);
                _setDVNs(srcVault, peerChainId);
                _setLibs(srcVault, peerLZ);
                console.log("      LZ configured for eid", vm.toString(peerLZ.eid));
            }
        }
        _currentLzOft = address(0);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  STEP 6 — Set Share Vault Mappings
    // ═══════════════════════════════════════════════════════════════════

    function _setupShareVaults() internal {
        if (isOFT()) return;
        if (vaultConfig.contracts.share == address(0)) return;

        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (ve.addr == address(0)) continue;

            address asset = ConfigReader.readAssetAddress(vaultConfig.deployChainId, ve.assetSymbol);

            // Idempotent: skip when the share already maps this asset to the target vault.
            // Treat a missing/old getter (revert) as a mismatch so the mapping still gets set.
            try NestShareOFT(payable(vaultConfig.contracts.share)).vault(asset) returns (address current) {
                if (current == ve.addr) {
                    _logSkipped(string.concat("setVault(", ve.assetSymbol, ") already set"));
                    continue;
                }
            } catch {}

            execute(
                vaultConfig.contracts.share,
                abi.encodeCall(NestShareOFT.setVault, (asset, ve.addr)),
                string.concat("setVault(", ve.assetSymbol, ")")
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  LayerZero Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @dev Enforced options are executed on the destination chain, so gas values come from the
    ///      destination chain's LZ config. msgType 2 (compose) is skipped when composeGas == 0,
    ///      which is how we disable compose-on-Solana.
    function _setEnforcedOptions(address oft, uint256 dstChainId, uint32 dstEid) internal {
        EnforcedOptionsConfig memory opts = ConfigReader.readEnforcedOptions(dstChainId);
        uint256 n = opts.composeGas > 0 ? 2 : 1;
        EnforcedOptionParam[] memory params = new EnforcedOptionParam[](n);
        params[0] = EnforcedOptionParam(
            dstEid, 1, OptionsBuilder.newOptions().addExecutorLzReceiveOption(opts.sendGas, opts.sendMsgValue)
        );
        if (n == 2) {
            params[1] = EnforcedOptionParam(
                dstEid, 2, OptionsBuilder.newOptions().addExecutorLzReceiveOption(opts.composeGas, opts.composeMsgValue)
            );
        }
        if (_enforcedOptionsMatch(oft, dstEid, params)) {
            _logSkipped(string.concat("setEnforcedOptions(eid=", vm.toString(dstEid), ")"));
            return;
        }
        tryExecute(
            oft,
            abi.encodeCall(IOAppOptionsType3.setEnforcedOptions, (params)),
            string.concat("setEnforcedOptions(eid=", vm.toString(dstEid), ")")
        );
    }

    function _setDVNs(address oft, uint256 destChainId) internal {
        DVNConfig memory dvn = ConfigReader.readDVNs(vaultConfig.deployChainId, destChainId);
        address[] memory dvns = _buildDVNArray(dvn);
        if (dvns.length == 0) return;

        LZConfig memory destLZ = ConfigReader.readLZConfig(destChainId);
        _setConfigOnEndpoint(lzConfig.endpoint, oft, lzConfig.sendLib302, destLZ.eid, dvns);
        _setConfigOnEndpoint(lzConfig.endpoint, oft, lzConfig.receiveLib302, destLZ.eid, dvns);
    }

    function _setConfigOnEndpoint(address endpoint, address oft, address lib, uint32 dstEid, address[] memory dvns)
        internal
    {
        UlnConfig memory ulnConfig;
        ulnConfig.requiredDVNCount = uint8(dvns.length);
        ulnConfig.requiredDVNs = dvns;

        if (_ulnConfigAlreadySet(endpoint, oft, lib, dstEid, dvns)) {
            _logSkipped(string.concat("setConfig(eid=", vm.toString(dstEid), ", lib=", vm.toString(lib), ")"));
            return;
        }

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({eid: dstEid, configType: CONFIG_TYPE_ULN, config: abi.encode(ulnConfig)});
        tryExecute(
            endpoint,
            abi.encodeCall(IMessageLibManager.setConfig, (oft, lib, params)),
            string.concat("setConfig(eid=", vm.toString(dstEid), ", lib=", vm.toString(lib), ")")
        );
    }

    /// @dev True when the OApp's resolved ULN config already matches our intent.
    ///      `endpoint.getConfig` returns the RESOLVED config — the OApp's custom
    ///      config merged with the endpoint default — so the on-chain `confirmations`
    ///      and optional-DVN fields come back as the default even though we only pin
    ///      `requiredDVNs` (sending `confirmations = 0` = "use default"). Comparing the
    ///      raw desired bytes against that resolved config never matches, which re-queues
    ///      setConfig on every run. Here we resolve the desired config the same way the
    ///      ULN does — requiredDVNs pinned to ours, every DEFAULT-following field taken
    ///      from the endpoint default (oapp = address(0)) — then compare resolved-to-resolved.
    ///      Any read/decode failure returns false so setConfig still runs (never skip unsafely).
    function _ulnConfigAlreadySet(address endpoint, address oft, address lib, uint32 dstEid, address[] memory dvns)
        internal
        view
        returns (bool)
    {
        UlnConfig memory desired;
        desired.requiredDVNCount = uint8(dvns.length);
        desired.requiredDVNs = dvns;

        // DEFAULT_CONFIG is keyed at address(0); getUlnConfig(address(0)) returns the default itself.
        try IMessageLibManager(endpoint).getConfig(address(0), lib, dstEid, CONFIG_TYPE_ULN) returns (bytes memory d) {
            UlnConfig memory def = abi.decode(d, (UlnConfig));
            desired.confirmations = def.confirmations;
            desired.optionalDVNCount = def.optionalDVNCount;
            desired.optionalDVNThreshold = def.optionalDVNThreshold;
            desired.optionalDVNs = def.optionalDVNs;
        } catch {
            return false;
        }

        try IMessageLibManager(endpoint).getConfig(oft, lib, dstEid, CONFIG_TYPE_ULN) returns (bytes memory c) {
            UlnConfig memory current = abi.decode(c, (UlnConfig));
            return keccak256(abi.encode(current)) == keccak256(abi.encode(desired));
        } catch {
            return false;
        }
    }

    function _buildDVNArray(DVNConfig memory dvn) internal pure returns (address[] memory) {
        uint256 count = 0;
        if (dvn.lz != address(0)) count++;
        if (dvn.nethermind != address(0)) count++;
        if (dvn.canary != address(0)) count++;

        address[] memory dvns = new address[](count);
        uint256 idx = 0;
        if (dvn.lz != address(0)) dvns[idx++] = dvn.lz;
        if (dvn.nethermind != address(0)) dvns[idx++] = dvn.nethermind;
        if (dvn.canary != address(0)) dvns[idx++] = dvn.canary;

        for (uint256 i = 1; i < count; i++) {
            for (uint256 j = i; j > 0 && dvns[j - 1] > dvns[j]; j--) {
                (dvns[j - 1], dvns[j]) = (dvns[j], dvns[j - 1]);
            }
        }
        return dvns;
    }

    function _setLibs(address oft, LZConfig memory peerLZ) internal {
        address lib = IMessageLibManager(lzConfig.endpoint).getSendLibrary(oft, peerLZ.eid);
        bool isDefault = IMessageLibManager(lzConfig.endpoint).isDefaultSendLibrary(oft, peerLZ.eid);
        if (lib != lzConfig.sendLib302 || isDefault) {
            tryExecute(
                lzConfig.endpoint,
                abi.encodeCall(IMessageLibManager.setSendLibrary, (oft, peerLZ.eid, lzConfig.sendLib302)),
                string.concat("setSendLibrary(eid=", vm.toString(peerLZ.eid), ")")
            );
        } else {
            _logSkipped(string.concat("setSendLibrary(eid=", vm.toString(peerLZ.eid), ")"));
        }

        bool isDefaultRecv;
        (lib, isDefaultRecv) = IMessageLibManager(lzConfig.endpoint).getReceiveLibrary(oft, peerLZ.eid);
        if (lib != lzConfig.receiveLib302 || isDefaultRecv) {
            tryExecute(
                lzConfig.endpoint,
                abi.encodeCall(IMessageLibManager.setReceiveLibrary, (oft, peerLZ.eid, lzConfig.receiveLib302, 0)),
                string.concat("setReceiveLibrary(eid=", vm.toString(peerLZ.eid), ")")
            );
        } else {
            _logSkipped(string.concat("setReceiveLibrary(eid=", vm.toString(peerLZ.eid), ")"));
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Authority Resolution Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @dev Returns all addresses for a target name. "vault" and "composer" return one per vault entry.
    function _resolveTargets(string memory name) internal view returns (address[] memory) {
        bytes32 h = keccak256(bytes(name));

        // Per-vault-entry targets
        if (h == keccak256("vault")) return _collectVaults();
        if (h == keccak256("composer")) return _collectComposers();

        // Shared targets
        if (h == keccak256("share")) return _toArray(vaultConfig.contracts.share);
        if (h == keccak256("accountant")) return _toArray(vaultConfig.contracts.accountant);
        if (h == keccak256("blacklistHook")) return _toArray(vaultConfig.common.blacklistHook);
        if (h == keccak256("cctpRelayer")) return _toArray(vaultConfig.common.cctpRelayer);
        if (h == keccak256("redeemOperator")) return _toArray(vaultConfig.common.redeemOperator);
        if (h == keccak256("operatorRegistry")) return _toArray(vaultConfig.common.operatorRegistry);
        if (h == keccak256("predicateProxy")) return _toArray(vaultConfig.common.predicateProxy);
        if (h == keccak256("complianceProxy")) return _toArray(vaultConfig.common.complianceProxy);
        if (h == keccak256("shareSeizer")) return _toArray(vaultConfig.common.seizer);
        if (h == keccak256("nestAdapter")) return _toArray(vaultConfig.common.nestAdapter);
        if (h == keccak256("nestBundler")) return _toArray(vaultConfig.common.nestBundler);
        if (h == keccak256("nestUnlooper")) return _toArray(vaultConfig.common.nestUnlooper);
        revert(string.concat("DeployAndSetup: unknown target '", name, "'"));
    }

    function _resolveUsers(string memory name) internal view returns (address[] memory) {
        bytes32 h = keccak256(bytes(name));

        // Per-vault-entry users
        if (h == keccak256("vault")) return _collectVaults();
        if (h == keccak256("composer")) return _collectComposers();

        // Single-address users
        if (h == keccak256("share")) return _toArray(vaultConfig.contracts.share);
        if (h == keccak256("blacklistHook")) return _toArray(vaultConfig.common.blacklistHook);
        if (h == keccak256("predicateProxy")) return _toArray(vaultConfig.common.predicateProxy);
        if (h == keccak256("complianceProxy")) return _toArray(vaultConfig.common.complianceProxy);
        if (h == keccak256("cctpRelayer")) return _toArray(vaultConfig.common.cctpRelayer);
        if (h == keccak256("redeemOperator")) return _toArray(vaultConfig.common.redeemOperator);
        if (h == keccak256("owner")) return _toArray(ConfigReader.resolvedOwner(vaultConfig));
        if (h == keccak256("shareSeizer")) return _toArray(vaultConfig.common.seizer);

        // Array users
        if (h == keccak256("MANAGER_ROLE")) return vaultConfig.roles.MANAGER_ROLE;
        if (h == keccak256("UPDATE_EXCHANGE_RATE_ROLE")) return vaultConfig.roles.UPDATE_EXCHANGE_RATE_ROLE;
        if (h == keccak256("KEEPER_ROLE")) return vaultConfig.roles.KEEPER_ROLE;
        if (h == keccak256("CAN_SOLVE_ROLE")) return vaultConfig.roles.CAN_SOLVE_ROLE;
        if (h == keccak256("OWNER_ROLE")) return vaultConfig.roles.OWNER_ROLE;
        if (h == keccak256("PAUSER_ROLE")) return vaultConfig.roles.PAUSER_ROLE;
        if (h == keccak256("DEPOSITOR_ROLE")) return vaultConfig.roles.DEPOSITOR_ROLE;

        if (h == keccak256("nestAdapter")) return _toArray(vaultConfig.common.nestAdapter);
        if (h == keccak256("nestUnlooper")) return _toArray(vaultConfig.common.nestUnlooper);
        revert(string.concat("DeployAndSetup: unknown user '", name, "'"));
    }

    function _checkCondition(string memory condition) internal view returns (bool) {
        bytes32 h = keccak256(bytes(condition));
        // V2-only runs skip every V1 grant; deposit/mint stay proof-gated instead of turning public.
        if (h == keccak256("predicateProxy")) return !isV2Only() && isActive(vaultConfig.common.predicateProxy);
        if (h == keccak256("noPredicateProxy")) return !isV2Only() && !isActive(vaultConfig.common.predicateProxy);
        if (h == keccak256("composer")) return _collectComposers().length > 0;
        if (h == keccak256("cctpRelayer")) return isActive(vaultConfig.common.cctpRelayer);
        if (h == keccak256("redeemOperator")) return isActive(vaultConfig.common.redeemOperator);
        if (h == keccak256("operatorRegistry")) return isActive(vaultConfig.common.operatorRegistry);
        if (h == keccak256("shareSeizer")) return isActive(vaultConfig.common.seizer);
        if (h == keccak256("blacklistHook")) return isActive(vaultConfig.common.blacklistHook);
        if (h == keccak256("vaultTypeOFT")) return isOFT();
        if (h == keccak256("vaultTypeNotOFT")) return !isOFT();
        if (h == keccak256("nestAdapter")) return isActive(vaultConfig.common.nestAdapter);
        if (h == keccak256("nestBundler")) return isActive(vaultConfig.common.nestBundler);
        if (h == keccak256("nestUnlooper")) return isActive(vaultConfig.common.nestUnlooper);
        if (h == keccak256("complianceProxy")) return isActive(vaultConfig.common.complianceProxy);
        // True when `vaultConfig.owner` points to a contract (Safe/multisig), not an EOA.
        if (h == keccak256("ownerIsMsig")) {
            address o = vaultConfig.owner;
            return o != address(0) && o != deployer() && o.code.length > 0;
        }
        return true;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  General Helpers
    // ═══════════════════════════════════════════════════════════════════

    function _collectVaults() internal view returns (address[] memory) {
        address[] memory addrs = new address[](vaultConfig.vaults.length);
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            addrs[i] = vaultConfig.vaults[i].addr;
        }
        return addrs;
    }

    function _collectComposers() internal view returns (address[] memory) {
        address[] memory addrs = new address[](vaultConfig.vaults.length);
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            addrs[i] = vaultConfig.vaults[i].composer;
        }
        return addrs;
    }

    function _toArray(address addr) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = addr;
    }

    function _tryReadString(string memory json, string memory key) internal pure returns (string memory) {
        try vm.parseJsonString(json, key) returns (string memory val) {
            return val;
        } catch {
            return "";
        }
    }

    function _enforcedOptionsMatch(address oft, uint32 eid, EnforcedOptionParam[] memory params)
        internal
        view
        returns (bool)
    {
        for (uint256 i = 0; i < params.length; i++) {
            (bool ok, bytes memory ret) =
                oft.staticcall(abi.encodeWithSignature("enforcedOptions(uint32,uint16)", eid, params[i].msgType));
            if (!ok) return false;
            bytes memory current = abi.decode(ret, (bytes));
            if (keccak256(current) != keccak256(params[i].options)) return false;
        }
        return true;
    }

    function _parseSteps() internal {
        try vm.envString("STEPS") returns (string memory stepsStr) {
            stepDeploy = _contains(stepsStr, "deploy");
            stepOperator = _contains(stepsStr, "operator");
            stepComposer = _contains(stepsStr, "composer");
            stepAuthority = _contains(stepsStr, "authority");
            stepL0 = _contains(stepsStr, "l0");
            stepShare = _contains(stepsStr, "share");
        } catch {
            stepDeploy = true;
            stepOperator = true;
            stepComposer = true;
            stepAuthority = true;
            stepL0 = true;
            stepShare = true;
        }
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    function _printSummary() internal view {
        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("Symbol:          ", vaultConfig.symbol);
        console.log("Chain:           ", vaultConfig.deployChainId);
        console.log("Vault Type:      ", vaultConfig.vaultType);
        console.log("Share:           ", vaultConfig.contracts.share);
        console.log("Accountant:      ", vaultConfig.contracts.accountant);
        console.log("RolesAuthority:  ", _resolveRolesAuthority());
        console.log("CommonAuthority: ", _resolveCommonRolesAuthority());
        console.log("PredicateProxy:  ", vaultConfig.common.predicateProxy);
        console.log("OperatorRegistry:", vaultConfig.common.operatorRegistry);
        console.log("RedeemOperator:  ", vaultConfig.common.redeemOperator);
        console.log("CCTPRelayer:     ", vaultConfig.common.cctpRelayer);
        console.log("Seizer:          ", vaultConfig.common.seizer);
        console.log("BlacklistHook:   ", vaultConfig.common.blacklistHook);
        console.log("NestAdapter:     ", vaultConfig.common.nestAdapter);
        console.log("NestBundler:     ", vaultConfig.common.nestBundler);
        console.log("NestUnlooper:    ", vaultConfig.common.nestUnlooper);
        console.log("ProtocolTimelock:", vaultConfig.common.protocolTimelock);
        console.log("AdminTimelock:   ", vaultConfig.common.adminTimelock);
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            console.log("---");
            console.log("  Asset:   ", vaultConfig.vaults[i].assetSymbol);
            console.log("  Vault:   ", vaultConfig.vaults[i].addr);
            console.log("  Composer:", vaultConfig.vaults[i].composer);
        }
        console.log("==========================");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Write Output — persist updated config back to script/deployment-config/
    // ═══════════════════════════════════════════════════════════════════

    function _writeOutput() internal {
        writeDeploymentOutput();
        writeCommonConfigIfChanged();
    }

    /// @dev Reads a uint from the raw vault JSON, defaulting to 0 when the key is absent.
    ///      Used for Hub-only accountant fee params that are not in the AccountantParams struct.
    function _tryReadUint(string memory key) internal view returns (uint256) {
        try vm.parseJsonUint(rawVaultConfigJson, key) returns (uint256 v) {
            return v;
        } catch {
            return 0;
        }
    }
}
