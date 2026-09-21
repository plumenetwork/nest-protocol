// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {ConfigReader, VaultEntry} from "script/lib/ConfigReader.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {NestAccountant} from "contracts/accountant/NestAccountant.sol";
import {NestVaultOFT} from "contracts/NestVaultOFT.sol";
import {NestVault} from "contracts/NestVault.sol";
import {NestVaultPredicateProxy} from "contracts/compliance/NestVaultPredicateProxy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {Auth} from "@solmate/auth/Auth.sol";
import {BlacklistHook} from "contracts/compliance/hooks/BlacklistHook.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {console} from "forge-std/console.sol";

/// @title  DeployVault
/// @notice Deploys the core vault stack: RolesAuthority, NestShareOFT, NestAccountant,
///         one vault per deposit asset (NestVaultOFT or NestVault), and PredicateProxy.
/// @dev    Each component is skipped if its address is non-zero in the vault config (already deployed).
///
///         Usage:
///           VAULT_SYMBOL=nTEST forge script script/deploy/DeployVault.s.sol --sig "runDirect()" --rpc-url $RPC --broadcast
///           VAULT_SYMBOL=nTEST forge script script/deploy/DeployVault.s.sol --sig "runMsig()" --rpc-url $RPC
///         runMsig() requires every component to already exist on-chain (existing-contracts-only,
///         as with DeployAndSetup.runMsig): deployments are never serialized into the Safe batch.
contract DeployVault is BaseConfigScript {
    function setUp() public {
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");
        loadConfigs(vaultSymbol);
        snapshotCommon();
    }

    function runDirect() external {
        _deploy(false);
    }

    function runMsig() external {
        _deploy(true);
        writeMsigBatch("DeployVault");
    }

    /// @dev Same salt DeployAndSetup uses for the chain-wide common RolesAuthority.
    string internal constant COMMON_AUTHORITY_SALT = "Nest RolesAuthority";

    function _deploy(bool _msigMode) internal directOrMsig(_msigMode) {
        // runMsig serializes config calls only: CREATE3/`new` deployments are simulated, never
        // broadcast, so a batch built against missing contracts would silently no-op on-chain.
        if (_msigMode) _requireDeployedForMsig();
        // 1a. RolesAuthority (vault-specific)
        address rolesAuth = _deployRolesAuthorityIfNeeded(
            "RolesAuthority", vaultConfig.contracts.share, vaultConfig.contracts.rolesAuthority, false
        );
        if (rolesAuth != address(0)) {
            console.log("RolesAuthority deployed:", rolesAuth);
        }

        // 1b. CommonRolesAuthority (for common contracts: operatorRegistry, redeemOperator, cctpRelayer, predicateProxy)
        address commonAuth = _deployRolesAuthorityIfNeeded(
            COMMON_AUTHORITY_SALT, vaultConfig.common.predicateProxy, vaultConfig.common.commonRolesAuthority, true
        );
        if (commonAuth != address(0)) {
            console.log("CommonRolesAuthority deployed:", commonAuth);
        }

        // 2. NestShareOFT
        if (needsDeploy(vaultConfig.contracts.share)) {
            vaultConfig.contracts.share = _deployShare();
            console.log("NestShareOFT deployed:", vaultConfig.contracts.share);
        }
        if (rolesAuth != address(0)) _wireAuthority(vaultConfig.contracts.share, rolesAuth);

        // 3. NestAccountant (uses base asset)
        if (needsDeploy(vaultConfig.contracts.accountant)) {
            _requireLegacyAccountantType();
            address baseAsset = ConfigReader.readAssetAddress(vaultConfig.deployChainId, vaultConfig.baseAssetSymbol);
            vaultConfig.contracts.accountant = _deployAccountant(baseAsset);
            console.log("NestAccountant deployed:", vaultConfig.contracts.accountant);
        }

        // 4. BlacklistHook
        if (needsDeploy(vaultConfig.common.blacklistHook)) {
            vaultConfig.common.blacklistHook = _deployBlacklistHook();
            console.log("BlacklistHook deployed:", vaultConfig.common.blacklistHook);
        }
        // Set hook on share if not already configured
        if (isActive(vaultConfig.common.blacklistHook) && isActive(vaultConfig.contracts.share)) {
            if (address(NestShareOFT(payable(vaultConfig.contracts.share)).hook()) != vaultConfig.common.blacklistHook)
            {
                execute(
                    vaultConfig.contracts.share,
                    abi.encodeCall(NestShareOFT.setBeforeTransferHook, (vaultConfig.common.blacklistHook)),
                    "setBeforeTransferHook"
                );
                console.log("  Hook set on share");
            }
        }

        // 5. One vault per deposit asset
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (!needsDeploy(ve.addr)) continue;

            address asset = ConfigReader.readAssetAddress(vaultConfig.deployChainId, ve.assetSymbol);
            vaultConfig.vaults[i].addr = _deployVault(asset, ve.assetSymbol);
            console.log("Vault deployed for", ve.assetSymbol, ":", vaultConfig.vaults[i].addr);
        }

        // 6. Set rate provider data for non-base deposit assets
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (keccak256(bytes(ve.assetSymbol)) == keccak256(bytes(vaultConfig.baseAssetSymbol))) continue;

            address asset = ConfigReader.readAssetAddress(vaultConfig.deployChainId, ve.assetSymbol);
            // Check if rate provider data is already set by trying getRateInQuote
            try NestAccountant(vaultConfig.contracts.accountant).getRateInQuote(ERC20(asset)) {
                console.log("  RateProvider already set for", ve.assetSymbol);
                continue;
            } catch {}
            execute(
                vaultConfig.contracts.accountant,
                abi.encodeCall(NestAccountant.setRateProviderData, (ERC20(asset), ve.isPegged, ve.rateProvider)),
                string.concat("setRateProviderData(", ve.assetSymbol, ")")
            );
            console.log("  RateProvider set for", ve.assetSymbol);
        }

        // 7. NestVaultPredicateProxy
        if (needsDeploy(vaultConfig.common.predicateProxy) && bytes(vaultConfig.compliance.v1.policyID).length > 0) {
            vaultConfig.common.predicateProxy = _deployPredicateProxy();
            console.log("PredicateProxy deployed:", vaultConfig.common.predicateProxy);
        }
        _recordCommonAuthority(commonAuth);

        // Summary
        console.log("=== Deployment Summary ===");
        console.log("Symbol:", vaultConfig.symbol);
        console.log("Share:", vaultConfig.contracts.share);
        console.log("Accountant:", vaultConfig.contracts.accountant);
        console.log("BlacklistHook:", vaultConfig.common.blacklistHook);
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            console.log("Vault", vaultConfig.vaults[i].assetSymbol, ":", vaultConfig.vaults[i].addr);
        }
        console.log("PredicateProxy:", vaultConfig.common.predicateProxy);
        console.log("==========================");
        // Msig deployments are simulation-only (W13): never persist from that mode.
        if (!msigMode) writeCommonConfigIfChanged();
    }

    // ─── Internal Deploy Functions ────────────────────────────────────

    /// @dev Multisig-mode precondition: every contract this run would touch must already exist.
    ///      Mirrors the DeployAndSetup.runMsig "existing contracts only" rule, enforced.
    function _requireDeployedForMsig() internal view {
        require(
            !needsDeploy(vaultConfig.contracts.share), "DeployVault: runMsig requires deployed share; use runDirect"
        );
        require(
            !needsDeploy(vaultConfig.contracts.accountant),
            "DeployVault: runMsig requires deployed accountant; use runDirect"
        );
        require(
            !needsDeploy(vaultConfig.common.blacklistHook),
            "DeployVault: runMsig requires deployed blacklistHook; use runDirect"
        );
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            require(
                !needsDeploy(vaultConfig.vaults[i].addr),
                string.concat("DeployVault: runMsig requires deployed vault-", vaultConfig.vaults[i].assetSymbol)
            );
        }
        if (bytes(vaultConfig.compliance.v1.policyID).length > 0) {
            require(
                !needsDeploy(vaultConfig.common.predicateProxy),
                "DeployVault: runMsig requires deployed predicateProxy; use runDirect"
            );
        }
    }

    /// @dev Deploys (or reuses) the RolesAuthority when the reference contract is fresh or unwired.
    ///      `known` (configured authority) wins when it has code; the common authority uses the same
    ///      chain-wide salt as DeployAndSetup so both flows resolve one address.
    function _deployRolesAuthorityIfNeeded(
        string memory saltName,
        address referenceContract,
        address known,
        bool commonSalt
    ) internal returns (address) {
        // Reference already wired (or disabled on this chain): nothing to do here.
        if (!needsDeploy(referenceContract)) {
            if (referenceContract.code.length == 0) return address(0); // disabled (DEAD)
            if (address(Auth(referenceContract).authority()) != address(0)) return address(0);
        }
        if (known.code.length > 0) return known;
        // Fresh chain, or an earlier partial run deployed the reference without wiring:
        // reuse the deterministic authority if it already exists, else deploy it.
        bytes32 salt = commonSalt ? generateCreate3SaltCommon(saltName) : generateCreate3Salt(saltName);
        address expected = _computeCreate3Address(salt);
        if (expected.code.length > 0) return expected;
        require(!msigMode, "DeployVault: RolesAuthority missing; runMsig cannot deploy it - use runDirect");
        return _deployRolesAuthority(salt);
    }

    /// @dev Sets `target.authority` when the deployer can; otherwise defer to SetupAuthority.
    function _wireAuthority(address target, address auth) internal {
        if (target.code.length > 0 && address(Auth(target).authority()) == auth) return;
        if (!msigMode && !_isOwner(target)) {
            console.log("  [DEFER] setAuthority (deployer is not owner):", target);
            return;
        }
        execute(target, abi.encodeCall(Auth.setAuthority, (Authority(auth))), "setAuthority");
    }

    /// @dev Records every newly materialized common authority, including predicate-less deployments.
    ///      PredicateProxy remains the on-chain derivation anchor when present, but persistence must
    ///      not depend on it: SetupAuthority otherwise cannot recover from a fresh or partial run.
    function _recordCommonAuthority(address commonAuth) internal {
        if (commonAuth == address(0)) return;
        // Never clobber a live canonical value (shared by every vault/script on the chain).
        if (vaultConfig.common.commonRolesAuthority.code.length == 0) {
            vaultConfig.common.commonRolesAuthority = commonAuth;
        }
        if (isActive(vaultConfig.common.predicateProxy)) {
            _wireAuthority(vaultConfig.common.predicateProxy, commonAuth);
        }
    }

    function _deployRolesAuthority(bytes32 salt) internal returns (address) {
        return CREATEX.deployCreate3(
            salt, abi.encodePacked(type(RolesAuthority).creationCode, abi.encode(deployer(), Authority(address(0))))
        );
    }

    function _deployBlacklistHook() internal returns (address) {
        bytes32 salt = generateCreate3SaltCommon("BlacklistHook");
        return CREATEX.deployCreate3(
            salt, abi.encodePacked(type(BlacklistHook).creationCode, abi.encode(deployer(), Authority(address(0))))
        );
    }

    function _deployShare() internal returns (address) {
        NestShareOFT implementation = new NestShareOFT(lzConfig.endpoint);

        bytes memory initData = abi.encodeWithSelector(
            NestShareOFT.initialize.selector, vaultConfig.name, vaultConfig.symbol, deployer(), deployer()
        );

        bytes32 salt = generateCreate3Salt("NestShareOFT");
        return CREATEX.deployCreate3(
            salt,
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(address(implementation), deployer(), initData)
            )
        );
    }

    /// @dev Legacy-only guard: this script deploys only the base NestAccountant at the shared
    ///      "NestAccountant" CREATE3 slot; Hub/Spoke configs must deploy via DeployAndSetup.
    function _requireLegacyAccountantType() internal view {
        string memory t = effectiveAccountantType();
        require(
            keccak256(bytes(t)) == keccak256("NestAccountant"),
            string.concat("DeployVault: accountantType resolves to ", t, " on this chain; use DeployAndSetup")
        );
    }

    function _deployAccountant(address asset) internal returns (address) {
        NestAccountant implementation = new NestAccountant(asset, vaultConfig.contracts.share);

        bytes memory initData = abi.encodeWithSelector(
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

        bytes32 salt = generateCreate3Salt("NestAccountant");
        return CREATEX.deployCreate3(
            salt,
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(address(implementation), deployer(), initData)
            )
        );
    }

    function _deployVault(address asset, string memory assetSymbol) internal returns (address) {
        if (isOFT()) {
            return _deployVaultOFT(asset, assetSymbol);
        } else {
            return _deployStandardVault(asset, assetSymbol);
        }
    }

    function _deployVaultOFT(address asset, string memory assetSymbol) internal returns (address) {
        address implementation =
            address(new NestVaultOFT(payable(vaultConfig.contracts.share), lzConfig.endpoint, commonConfig.permit2));

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
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode, abi.encode(implementation, deployer(), initData)
            )
        );
    }

    function _deployStandardVault(address asset, string memory assetSymbol) internal returns (address) {
        address implementation = address(new NestVault(payable(vaultConfig.contracts.share), commonConfig.permit2));

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
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode, abi.encode(implementation, deployer(), initData)
            )
        );
    }

    function _deployPredicateProxy() internal returns (address) {
        NestVaultPredicateProxy implementation = new NestVaultPredicateProxy();

        bytes memory initData = abi.encodeWithSelector(
            NestVaultPredicateProxy.initialize.selector,
            ConfigReader.resolvedOwner(vaultConfig),
            chainComplianceConfig.v1.serviceManager,
            vaultConfig.compliance.v1.policyID
        );

        bytes32 salt = generateCreate3SaltCommon("NestVaultPredicateProxy");
        return CREATEX.deployCreate3(
            salt,
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(address(implementation), deployer(), initData)
            )
        );
    }
}
