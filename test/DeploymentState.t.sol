// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {
    ConfigReader,
    CommonConfig,
    LZConfig,
    CCTPConfig,
    DVNConfig,
    EnforcedOptionsConfig,
    VaultDeployConfig,
    VaultContracts,
    CommonContracts,
    VaultEntry,
    VaultRoles
} from "script/lib/ConfigReader.sol";
import {Constants} from "script/lib/Constants.sol";

// Contracts
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {NestAccountant} from "contracts/accountant/NestAccountant.sol";
import {NestVault} from "contracts/NestVault.sol";
import {NestVaultPredicateProxy} from "contracts/compliance/NestVaultPredicateProxy.sol";
import {NestCCTPRelayer} from "contracts/integrations/cctp/NestCCTPRelayer.sol";
import {NestVaultComposer} from "contracts/integrations/ovault/NestVaultComposer.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";
import {NestVaultRedeemOperator} from "contracts/operators/NestVaultRedeemOperator.sol";
import {NestShareSeizer} from "contracts/compliance/NestShareSeizer.sol";
import {BlacklistHook} from "contracts/compliance/hooks/BlacklistHook.sol";
import {AuthUpgradeable} from "contracts/auth/AuthUpgradeable.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";

// LayerZero
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {IMessageLibManager} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

/// @title  DeploymentStateTest
/// @notice Read-only fork test that asserts deployed contract state matches config.
///         Unlike DeploymentFork (which exercises flows), this test reads on-chain state
///         without mutations and fails hard when expected components are missing.
/// @dev    Usage:
///           VAULT_SYMBOL=nTEST forge test --match-contract DeploymentStateTest -vvv
///         Optionally set USE_OUTPUT=false to read input config instead of deployment output.
contract DeploymentStateTest is Test, Constants {
    // ─── Config ──────────────────────────────────────────────────────
    VaultDeployConfig internal vaultConfig;
    CommonConfig internal commonConfig;
    LZConfig internal lzConfig;

    // ─── Contracts ───────────────────────────────────────────────────
    NestShareOFT internal share;
    NestAccountant internal accountant;
    RolesAuthority internal rolesAuthority;
    RolesAuthority internal commonRolesAuthority;

    // Per-asset arrays
    address[] internal vaultAddrs;
    address[] internal composerAddrs;
    address[] internal assetAddrs;

    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    // ─── Setup ───────────────────────────────────────────────────────

    function setUp() public {
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");

        uint256 chainId = vm.envUint("CHAIN_ID");
        bool useOutput = _envBoolOr("USE_OUTPUT", true);
        if (useOutput) {
            vaultConfig = ConfigReader.readOutputConfig(chainId, vaultSymbol);
            vaultConfig.deployChainId = chainId;
        } else {
            vaultConfig = ConfigReader.readVaultConfig(vaultSymbol);
            vaultConfig = ConfigReader.resolveConfigForChain(vaultConfig, chainId);
        }
        commonConfig = ConfigReader.readCommonConfig(chainId);
        lzConfig = ConfigReader.readLZConfig(chainId);

        // Fork
        try vm.activeFork() {}
        catch {
            string memory rpcUrl = vm.envString(commonConfig.rpcEnvVar);
            vm.createSelectFork(rpcUrl);
        }

        // Bind contracts
        share = NestShareOFT(payable(vaultConfig.contracts.share));
        accountant = NestAccountant(vaultConfig.contracts.accountant);
        rolesAuthority = RolesAuthority(address(Auth(vaultConfig.contracts.share).authority()));

        if (ConfigReader.isActive(vaultConfig.common.predicateProxy)) {
            commonRolesAuthority = RolesAuthority(address(Auth(vaultConfig.common.predicateProxy).authority()));
        }

        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            address assetAddr = ConfigReader.readAssetAddress(chainId, ve.assetSymbol);
            assetAddrs.push(assetAddr);
            vaultAddrs.push(ve.addr);
            composerAddrs.push(ve.composer);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //                  CORE CONTRACT EXISTENCE
    // ═══════════════════════════════════════════════════════════════════

    function test_state_coreContractsExist() public view {
        assertTrue(vaultConfig.contracts.share != address(0), "share address is zero");
        assertTrue(address(share).code.length > 0, "share has no code");

        assertTrue(vaultConfig.contracts.accountant != address(0), "accountant address is zero");
        assertTrue(address(accountant).code.length > 0, "accountant has no code");

        assertGt(vaultConfig.vaults.length, 0, "no vaults configured");
        for (uint256 i = 0; i < vaultAddrs.length; i++) {
            assertTrue(vaultAddrs[i] != address(0), "vault address is zero");
            assertTrue(vaultAddrs[i].code.length > 0, "vault has no code");
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //                  SHARE VAULT MAPPINGS
    // ═══════════════════════════════════════════════════════════════════

    function test_state_shareVaultMappings() public view {
        if (_isOFT()) return; // OFT vaults don't use share.vault()

        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (ve.addr == address(0)) continue;

            address asset = assetAddrs[i];
            address mappedVault = share.vault(asset);

            assertEq(mappedVault, ve.addr, string.concat("share.vault(", ve.assetSymbol, ") mismatch"));
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //                  OWNERSHIP VERIFICATION
    // ═══════════════════════════════════════════════════════════════════

    function test_state_ownership_share() public view {
        address expectedOwner = _expectedOwner();

        address shareOwner = AuthUpgradeable(address(share)).owner();
        assertEq(shareOwner, expectedOwner, "share: owner mismatch");

        address sharePending = AuthUpgradeable(address(share)).pendingOwner();
        assertEq(sharePending, address(0), "share: pendingOwner should be zero");
    }

    function test_state_ownership_accountant() public view {
        address expectedOwner = _expectedOwner();

        address accOwner = AuthUpgradeable(address(accountant)).owner();
        assertEq(accOwner, expectedOwner, "accountant: owner mismatch");

        address accPending = AuthUpgradeable(address(accountant)).pendingOwner();
        assertEq(accPending, address(0), "accountant: pendingOwner should be zero");
    }

    function test_state_ownership_vaultsAndComposers() public view {
        address expectedOwner = _expectedOwner();

        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];

            if (ConfigReader.isActive(ve.addr)) {
                address vOwner = AuthUpgradeable(ve.addr).owner();
                assertEq(vOwner, expectedOwner, string.concat("vault[", ve.assetSymbol, "]: owner mismatch"));

                address vPending = AuthUpgradeable(ve.addr).pendingOwner();
                assertEq(
                    vPending, address(0), string.concat("vault[", ve.assetSymbol, "]: pendingOwner should be zero")
                );
            }

            if (ConfigReader.isActive(ve.composer)) {
                address cOwner = AuthUpgradeable(ve.composer).owner();
                assertEq(cOwner, expectedOwner, string.concat("composer[", ve.assetSymbol, "]: owner mismatch"));

                address cPending = AuthUpgradeable(ve.composer).pendingOwner();
                assertEq(
                    cPending, address(0), string.concat("composer[", ve.assetSymbol, "]: pendingOwner should be zero")
                );
            }
        }
    }

    function test_state_ownership_common() public view {
        address expectedOwner = _expectedOwner();

        if (ConfigReader.isActive(vaultConfig.common.predicateProxy)) {
            address o = AuthUpgradeable(vaultConfig.common.predicateProxy).owner();
            assertEq(o, expectedOwner, "predicateProxy: owner mismatch");
            address p = AuthUpgradeable(vaultConfig.common.predicateProxy).pendingOwner();
            assertEq(p, address(0), "predicateProxy: pendingOwner should be zero");
        }

        if (ConfigReader.isActive(vaultConfig.common.redeemOperator)) {
            address o = AuthUpgradeable(vaultConfig.common.redeemOperator).owner();
            assertEq(o, expectedOwner, "redeemOperator: owner mismatch");
            address p = AuthUpgradeable(vaultConfig.common.redeemOperator).pendingOwner();
            assertEq(p, address(0), "redeemOperator: pendingOwner should be zero");
        }

        if (ConfigReader.isActive(vaultConfig.common.cctpRelayer)) {
            address o = AuthUpgradeable(vaultConfig.common.cctpRelayer).owner();
            assertEq(o, expectedOwner, "cctpRelayer: owner mismatch");
            address p = AuthUpgradeable(vaultConfig.common.cctpRelayer).pendingOwner();
            assertEq(p, address(0), "cctpRelayer: pendingOwner should be zero");
        }
    }

    function test_state_ownership_solmateAuth() public view {
        address expectedOwner = _expectedOwner();

        // Vault RolesAuthority
        assertEq(Auth(address(rolesAuthority)).owner(), expectedOwner, "rolesAuthority: owner mismatch");

        // Common RolesAuthority
        if (address(commonRolesAuthority) != address(0)) {
            assertEq(Auth(address(commonRolesAuthority)).owner(), expectedOwner, "commonRolesAuthority: owner mismatch");
        }

        // OperatorRegistry, Seizer, BlacklistHook are Solmate Auth (one-step)
        if (ConfigReader.isActive(vaultConfig.common.operatorRegistry)) {
            assertEq(
                Auth(vaultConfig.common.operatorRegistry).owner(), expectedOwner, "operatorRegistry: owner mismatch"
            );
        }
        if (ConfigReader.isActive(vaultConfig.common.seizer)) {
            assertEq(Auth(vaultConfig.common.seizer).owner(), expectedOwner, "seizer: owner mismatch");
        }
        if (ConfigReader.isActive(vaultConfig.common.blacklistHook)) {
            assertEq(Auth(vaultConfig.common.blacklistHook).owner(), expectedOwner, "blacklistHook: owner mismatch");
        }
    }

    function test_state_ownership_proxyAdmins() public view {
        address expectedOwner = _expectedOwner();

        // Share proxy admin
        _assertProxyAdminOwner(address(share), expectedOwner, "share");
        _assertProxyAdminOwner(address(accountant), expectedOwner, "accountant");

        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (ConfigReader.isActive(ve.addr)) {
                _assertProxyAdminOwner(ve.addr, expectedOwner, string.concat("vault[", ve.assetSymbol, "]"));
            }
            if (ConfigReader.isActive(ve.composer)) {
                _assertProxyAdminOwner(ve.composer, expectedOwner, string.concat("composer[", ve.assetSymbol, "]"));
            }
        }

        if (ConfigReader.isActive(vaultConfig.common.predicateProxy)) {
            _assertProxyAdminOwner(vaultConfig.common.predicateProxy, expectedOwner, "predicateProxy");
        }
        if (ConfigReader.isActive(vaultConfig.common.redeemOperator)) {
            _assertProxyAdminOwner(vaultConfig.common.redeemOperator, expectedOwner, "redeemOperator");
        }
        if (ConfigReader.isActive(vaultConfig.common.cctpRelayer)) {
            _assertProxyAdminOwner(vaultConfig.common.cctpRelayer, expectedOwner, "cctpRelayer");
        }
        if (ConfigReader.isActive(vaultConfig.common.operatorRegistry)) {
            _assertProxyAdminOwner(vaultConfig.common.operatorRegistry, expectedOwner, "operatorRegistry");
        }
        if (ConfigReader.isActive(vaultConfig.common.seizer)) {
            _assertProxyAdminOwner(vaultConfig.common.seizer, expectedOwner, "seizer");
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //                  AUTHORITY WIRING
    // ═══════════════════════════════════════════════════════════════════

    function test_state_authoritySet() public view {
        // Vault-scoped contracts share the same vault RolesAuthority
        assertEq(address(Auth(address(share)).authority()), address(rolesAuthority), "share: wrong authority");
        assertEq(address(Auth(address(accountant)).authority()), address(rolesAuthority), "accountant: wrong authority");

        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            VaultEntry memory ve = vaultConfig.vaults[i];
            if (ConfigReader.isActive(ve.addr)) {
                assertEq(
                    address(Auth(ve.addr).authority()),
                    address(rolesAuthority),
                    string.concat("vault[", ve.assetSymbol, "]: wrong authority")
                );
            }
            if (ConfigReader.isActive(ve.composer)) {
                assertEq(
                    address(Auth(ve.composer).authority()),
                    address(rolesAuthority),
                    string.concat("composer[", ve.assetSymbol, "]: wrong authority")
                );
            }
        }

        // Common contracts should use commonRolesAuthority
        if (address(commonRolesAuthority) != address(0)) {
            if (ConfigReader.isActive(vaultConfig.common.predicateProxy)) {
                assertEq(
                    address(Auth(vaultConfig.common.predicateProxy).authority()),
                    address(commonRolesAuthority),
                    "predicateProxy: wrong authority"
                );
            }
            if (ConfigReader.isActive(vaultConfig.common.redeemOperator)) {
                assertEq(
                    address(Auth(vaultConfig.common.redeemOperator).authority()),
                    address(commonRolesAuthority),
                    "redeemOperator: wrong authority"
                );
            }
            if (ConfigReader.isActive(vaultConfig.common.cctpRelayer)) {
                assertEq(
                    address(Auth(vaultConfig.common.cctpRelayer).authority()),
                    address(commonRolesAuthority),
                    "cctpRelayer: wrong authority"
                );
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //                  CCTP RELAYER STATE
    // ═══════════════════════════════════════════════════════════════════

    function test_state_cctpRelayer_composersApproved() public view {
        if (!ConfigReader.isActive(vaultConfig.common.cctpRelayer)) return;

        NestCCTPRelayer relayer = NestCCTPRelayer(payable(vaultConfig.common.cctpRelayer));

        uint256 checked;
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            address composer = vaultConfig.vaults[i].composer;
            if (!ConfigReader.isActive(composer)) continue;
            checked++;
            assertTrue(
                relayer.isComposer(composer),
                string.concat("cctpRelayer: composer[", vaultConfig.vaults[i].assetSymbol, "] not approved")
            );
        }
        // If there are composers, at least one must be approved
        if (composerAddrs.length > 0) {
            assertGt(checked, 0, "cctpRelayer: no composers were checked");
        }
    }

    function test_state_cctpRelayer_eidToDomain() public view {
        if (!ConfigReader.isActive(vaultConfig.common.cctpRelayer)) return;

        NestCCTPRelayer relayer = NestCCTPRelayer(payable(vaultConfig.common.cctpRelayer));

        for (uint256 i = 0; i < vaultConfig.peers.length; i++) {
            uint256 peerChainId = vaultConfig.peers[i];
            if (peerChainId == vaultConfig.deployChainId) continue;

            (bool hasCCTP, CCTPConfig memory peerCCTP) = ConfigReader.tryReadCCTPConfig(peerChainId);
            if (!hasCCTP) continue;

            LZConfig memory peerLZ = ConfigReader.readLZConfig(peerChainId);

            uint32 domain = relayer.getEidToDomain(peerLZ.eid);
            assertEq(
                domain,
                peerCCTP.domain,
                string.concat("cctpRelayer: eidToDomain mismatch for peer chain ", vm.toString(peerChainId))
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //                  LAYERZERO PEER CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════

    function test_state_lz_peers() public view {
        if (vaultConfig.peers.length == 0) return;

        if (_isOFT()) {
            // OFT vaults: each vault has its own peer config
            for (uint256 v = 0; v < vaultConfig.vaults.length; v++) {
                address vault = vaultConfig.vaults[v].addr;
                if (!ConfigReader.isActive(vault)) continue;

                for (uint256 i = 0; i < vaultConfig.peers.length; i++) {
                    uint256 peerChainId = vaultConfig.peers[i];
                    if (peerChainId == vaultConfig.deployChainId) continue;

                    LZConfig memory peerLZ = ConfigReader.readLZConfig(peerChainId);
                    bytes32 peer = IOAppCore(vault).peers(peerLZ.eid);
                    bytes32 expected = bytes32(uint256(uint160(vault)));

                    assertEq(
                        peer,
                        expected,
                        string.concat(
                            "lz: vault[",
                            vaultConfig.vaults[v].assetSymbol,
                            "] peer mismatch for eid ",
                            vm.toString(peerLZ.eid)
                        )
                    );
                }
            }
        } else {
            // Non-OFT: share OFT has peers
            for (uint256 i = 0; i < vaultConfig.peers.length; i++) {
                uint256 peerChainId = vaultConfig.peers[i];
                if (peerChainId == vaultConfig.deployChainId) continue;

                LZConfig memory peerLZ = ConfigReader.readLZConfig(peerChainId);
                bytes32 peer = IOAppCore(address(share)).peers(peerLZ.eid);
                bytes32 expected = bytes32(uint256(uint160(address(share))));

                assertEq(peer, expected, string.concat("lz: share peer mismatch for eid ", vm.toString(peerLZ.eid)));
            }
        }
    }

    function test_state_lz_sendLibraries() public view {
        if (vaultConfig.peers.length == 0) return;

        address[] memory ofts = _getLzOFTs();
        for (uint256 o = 0; o < ofts.length; o++) {
            if (!ConfigReader.isActive(ofts[o])) continue;
            for (uint256 i = 0; i < vaultConfig.peers.length; i++) {
                uint256 peerChainId = vaultConfig.peers[i];
                if (peerChainId == vaultConfig.deployChainId) continue;

                LZConfig memory peerLZ = ConfigReader.readLZConfig(peerChainId);
                address lib = IMessageLibManager(lzConfig.endpoint).getSendLibrary(ofts[o], peerLZ.eid);
                bool isDefault = IMessageLibManager(lzConfig.endpoint).isDefaultSendLibrary(ofts[o], peerLZ.eid);

                assertEq(
                    lib, lzConfig.sendLib302, string.concat("lz: sendLib mismatch for eid ", vm.toString(peerLZ.eid))
                );
                assertFalse(isDefault, string.concat("lz: sendLib still default for eid ", vm.toString(peerLZ.eid)));
            }
        }
    }

    function test_state_lz_receiveLibraries() public view {
        if (vaultConfig.peers.length == 0) return;

        address[] memory ofts = _getLzOFTs();
        for (uint256 o = 0; o < ofts.length; o++) {
            if (!ConfigReader.isActive(ofts[o])) continue;
            for (uint256 i = 0; i < vaultConfig.peers.length; i++) {
                uint256 peerChainId = vaultConfig.peers[i];
                if (peerChainId == vaultConfig.deployChainId) continue;

                LZConfig memory peerLZ = ConfigReader.readLZConfig(peerChainId);
                (address lib, bool isDefault) =
                    IMessageLibManager(lzConfig.endpoint).getReceiveLibrary(ofts[o], peerLZ.eid);

                assertEq(
                    lib, lzConfig.receiveLib302, string.concat("lz: recvLib mismatch for eid ", vm.toString(peerLZ.eid))
                );
                assertFalse(isDefault, string.concat("lz: recvLib still default for eid ", vm.toString(peerLZ.eid)));
            }
        }
    }

    function test_state_lz_dvns() public view {
        if (vaultConfig.peers.length == 0) return;

        address[] memory ofts = _getLzOFTs();
        for (uint256 o = 0; o < ofts.length; o++) {
            if (!ConfigReader.isActive(ofts[o])) continue;
            for (uint256 i = 0; i < vaultConfig.peers.length; i++) {
                uint256 peerChainId = vaultConfig.peers[i];
                if (peerChainId == vaultConfig.deployChainId) continue;

                DVNConfig memory dvn = ConfigReader.readDVNs(vaultConfig.deployChainId, peerChainId);
                uint256 expectedCount;
                if (dvn.lz != address(0)) expectedCount++;
                if (dvn.nethermind != address(0)) expectedCount++;
                if (dvn.canary != address(0)) expectedCount++;
                if (expectedCount == 0) continue;

                LZConfig memory peerLZ = ConfigReader.readLZConfig(peerChainId);

                // Check send lib DVN config
                bytes memory sendCfg = IMessageLibManager(lzConfig.endpoint)
                    .getConfig(
                        ofts[o],
                        lzConfig.sendLib302,
                        peerLZ.eid,
                        2 // CONFIG_TYPE_ULN
                    );
                _assertDVNConfig(
                    sendCfg, dvn, string.concat("lz: sendLib DVN mismatch for eid ", vm.toString(peerLZ.eid))
                );

                // Check receive lib DVN config
                bytes memory recvCfg =
                    IMessageLibManager(lzConfig.endpoint).getConfig(ofts[o], lzConfig.receiveLib302, peerLZ.eid, 2);
                _assertDVNConfig(
                    recvCfg, dvn, string.concat("lz: recvLib DVN mismatch for eid ", vm.toString(peerLZ.eid))
                );
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //                  ROLE ASSIGNMENTS
    // ═══════════════════════════════════════════════════════════════════

    function test_state_roles_vaultAuthority() public view {
        // Vaults should have TELLER_ROLE
        for (uint256 i = 0; i < vaultAddrs.length; i++) {
            if (!ConfigReader.isActive(vaultAddrs[i])) continue;
            assertTrue(
                rolesAuthority.doesUserHaveRole(vaultAddrs[i], TELLER_ROLE),
                string.concat("role: vault[", vaultConfig.vaults[i].assetSymbol, "] missing TELLER_ROLE")
            );
        }

        // Composers should have COMPOSER_ROLE
        for (uint256 i = 0; i < composerAddrs.length; i++) {
            if (!ConfigReader.isActive(composerAddrs[i])) continue;
            assertTrue(
                rolesAuthority.doesUserHaveRole(composerAddrs[i], COMPOSER_ROLE),
                string.concat("role: composer[", vaultConfig.vaults[i].assetSymbol, "] missing COMPOSER_ROLE")
            );
        }

        // PredicateProxy should have PREDICATE_PROXY_ROLE
        if (ConfigReader.isActive(vaultConfig.common.predicateProxy)) {
            assertTrue(
                rolesAuthority.doesUserHaveRole(vaultConfig.common.predicateProxy, PREDICATE_PROXY_ROLE),
                "role: predicateProxy missing PREDICATE_PROXY_ROLE"
            );
        }

        // Accountant keepers
        for (uint256 i = 0; i < vaultConfig.roles.UPDATE_EXCHANGE_RATE_ROLE.length; i++) {
            assertTrue(
                rolesAuthority.doesUserHaveRole(
                    vaultConfig.roles.UPDATE_EXCHANGE_RATE_ROLE[i], UPDATE_EXCHANGE_RATE_ROLE
                ),
                "role: accountant keeper missing UPDATE_EXCHANGE_RATE_ROLE"
            );
        }

        // Managers
        for (uint256 i = 0; i < vaultConfig.roles.MANAGER_ROLE.length; i++) {
            assertTrue(
                rolesAuthority.doesUserHaveRole(vaultConfig.roles.MANAGER_ROLE[i], MANAGER_ROLE),
                "role: manager missing MANAGER_ROLE"
            );
        }

        // Crosschain keepers
        for (uint256 i = 0; i < vaultConfig.roles.KEEPER_ROLE.length; i++) {
            assertTrue(
                rolesAuthority.doesUserHaveRole(vaultConfig.roles.KEEPER_ROLE[i], KEEPER_ROLE),
                "role: crosschain keeper missing KEEPER_ROLE"
            );
        }

        // CAN_SOLVE keepers
        for (uint256 i = 0; i < vaultConfig.roles.CAN_SOLVE_ROLE.length; i++) {
            assertTrue(
                rolesAuthority.doesUserHaveRole(vaultConfig.roles.CAN_SOLVE_ROLE[i], CAN_SOLVE_ROLE),
                "role: redeem keeper missing CAN_SOLVE_ROLE"
            );
        }
    }

    function test_state_roles_commonAuthority() public view {
        if (address(commonRolesAuthority) == address(0)) return;

        // Keepers on common authority should have KEEPER_ROLE
        for (uint256 i = 0; i < vaultConfig.roles.CAN_SOLVE_ROLE.length; i++) {
            assertTrue(
                commonRolesAuthority.doesUserHaveRole(vaultConfig.roles.CAN_SOLVE_ROLE[i], KEEPER_ROLE),
                "commonRole: redeem keeper missing KEEPER_ROLE on common authority"
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //                  HOOK WIRING
    // ═══════════════════════════════════════════════════════════════════

    function test_state_shareHook() public view {
        if (!ConfigReader.isActive(vaultConfig.common.blacklistHook)) return;

        address hook = address(share.hook());
        assertEq(hook, vaultConfig.common.blacklistHook, "share: hook mismatch with blacklistHook config");
    }

    // ═══════════════════════════════════════════════════════════════════
    //                          HELPERS
    // ═══════════════════════════════════════════════════════════════════

    function _isOFT() internal view returns (bool) {
        return keccak256(bytes(vaultConfig.vaultType)) == keccak256("NestVaultOFT");
    }

    /// @dev Expected contract owner: required explicit top-level `.owner`.
    function _expectedOwner() internal view returns (address) {
        return ConfigReader.resolvedOwner(vaultConfig);
    }

    /// @dev Returns the OFT addresses that should have LZ config: share for non-OFT, vaults for OFT.
    function _getLzOFTs() internal view returns (address[] memory) {
        if (_isOFT()) {
            return vaultAddrs;
        } else {
            address[] memory arr = new address[](1);
            arr[0] = address(share);
            return arr;
        }
    }

    function _getProxyAdmin(address proxy) internal view returns (address) {
        bytes32 adminSlot = vm.load(proxy, ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }

    function _assertProxyAdminOwner(address proxy, address expectedOwner, string memory label) internal view {
        address proxyAdmin = _getProxyAdmin(proxy);
        if (proxyAdmin == address(0)) return; // not a proxy

        (bool ok, bytes memory ret) = proxyAdmin.staticcall(abi.encodeWithSignature("owner()"));
        if (!ok) return;

        address adminOwner = abi.decode(ret, (address));
        assertEq(adminOwner, expectedOwner, string.concat(label, ": proxyAdmin owner mismatch"));
    }

    function _assertDVNConfig(bytes memory ulnConfigBytes, DVNConfig memory dvn, string memory label) internal pure {
        // Decode the UlnConfig — only check requiredDVNCount and requiredDVNs
        // UlnConfig has: confirmations, requiredDVNCount, optionalDVNCount, optionalDVNThreshold, requiredDVNs, optionalDVNs
        // But abi.decode of the full struct is complex — just check the required count from encoded bytes
        uint256 expectedCount;
        if (dvn.lz != address(0)) expectedCount++;
        if (dvn.nethermind != address(0)) expectedCount++;
        if (dvn.canary != address(0)) expectedCount++;

        // Build expected UlnConfig for comparison
        address[] memory dvns = new address[](expectedCount);
        uint256 idx;
        if (dvn.lz != address(0)) dvns[idx++] = dvn.lz;
        if (dvn.nethermind != address(0)) dvns[idx++] = dvn.nethermind;
        if (dvn.canary != address(0)) dvns[idx++] = dvn.canary;
        for (uint256 i = 1; i < expectedCount; i++) {
            for (uint256 j = i; j > 0 && dvns[j - 1] > dvns[j]; j--) {
                (dvns[j - 1], dvns[j]) = (dvns[j], dvns[j - 1]);
            }
        }

        // Decode the on-chain UlnConfig
        (
            uint64 confirmations,
            uint8 requiredDVNCount,
            uint8 optionalDVNCount,
            uint8 optionalDVNThreshold,
            address[] memory requiredDVNs,
            address[] memory optionalDVNs
        ) = abi.decode(ulnConfigBytes, (uint64, uint8, uint8, uint8, address[], address[]));

        // Silence unused variable warnings
        confirmations;
        optionalDVNCount;
        optionalDVNThreshold;
        optionalDVNs;

        assertEq(requiredDVNCount, expectedCount, string.concat(label, ": requiredDVNCount"));

        for (uint256 i = 0; i < expectedCount; i++) {
            assertEq(requiredDVNs[i], dvns[i], string.concat(label, ": DVN address mismatch"));
        }
    }

    function _envBoolOr(string memory key, bool defaultValue) internal view returns (bool) {
        try vm.envBool(key) returns (bool val) {
            return val;
        } catch {
            return defaultValue;
        }
    }
}
