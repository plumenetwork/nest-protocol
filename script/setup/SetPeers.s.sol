// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {ConfigReader, LZConfig, VaultDeployConfig, VaultEntry} from "script/lib/ConfigReader.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {console} from "forge-std/console.sol";

/// @title  SetPeers
/// @notice Wires LayerZero peers between a source chain and every peer chain listed in the vault config.
/// @dev    Run after DeployAndSetup has completed on every chain in `peers` (DVNs/libs/enforced options
///         are configured by DeployAndSetup; peers are wired here from the populated output files).
///
///         Peering rules:
///           - Src side iterates its own canonical OApp: share (non-OFT src) or canonical vault (OFT src).
///           - Peer side resolves by the peer chain's vaultType (with vaultTypeOverrides[peerChainId]):
///               * peer is OFT      → peer's canonical vault (by baseAsset, optionally overridden).
///               * peer is non-OFT  → peer's share.
///             This asymmetry matters when worldchain (NestVault) peers to OFT chains — its share
///             must pair with their vault-OApp, not their share.
///           - Non-canonical vaults (e.g. pUSD alongside a canonical USDC) are not peered.
///           - Peer chains whose output file is missing, or whose resolved peer is not deployed,
///             are skipped (run SetPeers again once those chains are deployed).
///
///         Usage:
///           VAULT_SYMBOL=nWISDOM CHAIN_ID=98866 forge script script/setup/SetPeers.s.sol \
///               --sig "runDirect()" --rpc-url $RPC --broadcast
///           VAULT_SYMBOL=nWISDOM CHAIN_ID=98866 forge script script/setup/SetPeers.s.sol \
///               --sig "runMsig()" --rpc-url $RPC
contract SetPeers is BaseConfigScript {
    using Strings for uint256;

    uint256 constant SOLANA_CHAIN_ID = 101;

    function setUp() public {
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");
        loadConfigs(vaultSymbol);
    }

    function runDirect() external {
        _run(false);
    }

    function runMsig() external {
        _run(true);
        writeMsigBatch("SetPeers");
    }

    /// @notice Hybrid entry point: broadcasts setPeer txs on OApps the deployer owns,
    ///         queues the rest into the Safe batch.
    function runHybrid() external {
        hybridMode = true;
        verbose = true;
        vm.startBroadcast(deployerPrivateKey);
        if (isOFT()) {
            _setVaultPeers();
        } else {
            _setSharePeers();
        }
        vm.stopBroadcast();
        writeMsigBatch("SetPeers");
    }

    function _run(bool _msigMode) internal directOrMsig(_msigMode) {
        if (isOFT()) {
            _setVaultPeers();
        } else {
            _setSharePeers();
        }
    }

    function _setSharePeers() internal {
        address srcShare = vaultConfig.contracts.share;
        if (srcShare == address(0) || srcShare.code.length == 0) return;

        _currentLzOft = srcShare;
        console.log("    Peering share:", srcShare);
        _wireAll(srcShare);
        _currentLzOft = address(0);
    }

    function _setVaultPeers() internal {
        (bool exists, VaultDeployConfig memory src) =
            ConfigReader.tryReadOutputConfig(vaultConfig.deployChainId, vaultConfig.symbol);
        address srcVault = exists ? _findVaultByAsset(src.vaults, vaultConfig.baseAssetSymbol) : address(0);
        if (srcVault == address(0) || srcVault.code.length == 0) {
            console.log("    [SKIP] no canonical vault on src chain for asset:", vaultConfig.baseAssetSymbol);
            return;
        }

        _currentLzOft = srcVault;
        console.log("    Peering vault:", vaultConfig.baseAssetSymbol, srcVault);
        _wireAll(srcVault);
        _currentLzOft = address(0);
    }

    function _wireAll(address srcOApp) internal {
        for (uint256 i = 0; i < vaultConfig.peers.length; i++) {
            uint256 peerChainId = vaultConfig.peers[i];
            if (peerChainId == vaultConfig.deployChainId) continue;

            bytes32 peerBytes = _resolvePeerBytes(peerChainId);
            if (peerBytes == bytes32(0)) {
                console.log("      [SKIP] no peer resolved for chain", peerChainId.toString());
                continue;
            }

            LZConfig memory peerLZ = ConfigReader.readLZConfig(peerChainId);
            _setPeerIfNeeded(srcOApp, peerLZ.eid, peerBytes);
        }
    }

    /// @dev Resolves peer bytes32 by the peer chain's vaultType (with vaultTypeOverrides applied):
    ///      OFT peer → peer's canonical vault; non-OFT peer → peer's share.
    function _resolvePeerBytes(uint256 peerChainId) internal view returns (bytes32) {
        if (peerChainId == SOLANA_CHAIN_ID) return _solanaOftStore();

        (bool exists, VaultDeployConfig memory dst) = ConfigReader.tryReadOutputConfig(peerChainId, vaultConfig.symbol);
        if (!exists) return bytes32(0);

        if (ConfigReader.isOFT(_peerVaultType(peerChainId))) {
            address dstVault = _findVaultByAsset(dst.vaults, _canonicalAssetFor(peerChainId));
            if (dstVault == address(0)) return bytes32(0);
            return _addressToBytes32(dstVault);
        }

        if (dst.contracts.share == address(0)) return bytes32(0);
        return _addressToBytes32(dst.contracts.share);
    }

    /// @dev Peer's vaultType = vaultTypeOverrides[peerChainId] ?? vaultType (from vault config JSON).
    function _peerVaultType(uint256 chainId) internal view returns (string memory) {
        try vm.parseJsonString(rawVaultConfigJson, string.concat(".vaultTypeOverrides.", chainId.toString())) returns (
            string memory override_
        ) {
            return override_;
        } catch {
            return vm.parseJsonString(rawVaultConfigJson, ".vaultType");
        }
    }

    function _solanaOftStore() internal view returns (bytes32) {
        string memory path =
            string.concat(vm.projectRoot(), "/deployments/solana-mainnet/", vaultConfig.symbol, "-OFT.json");
        try vm.readFile(path) returns (string memory json) {
            try vm.parseJsonBytes32(json, ".oftStoreBytes32") returns (bytes32 b) {
                return b;
            } catch {
                return bytes32(0);
            }
        } catch {
            return bytes32(0);
        }
    }

    function _findVaultByAsset(VaultEntry[] memory vaults, string memory assetSymbol) internal pure returns (address) {
        bytes32 key = keccak256(bytes(assetSymbol));
        for (uint256 i = 0; i < vaults.length; i++) {
            if (keccak256(bytes(vaults[i].assetSymbol)) == key) return vaults[i].addr;
        }
        return address(0);
    }

    /// @dev Canonical asset for `chainId` = baseAssetOverrides[chainId] ?? baseAssetSymbol (raw, pre-override).
    function _canonicalAssetFor(uint256 chainId) internal view returns (string memory) {
        try vm.parseJsonString(rawVaultConfigJson, string.concat(".baseAssetOverrides.", chainId.toString())) returns (
            string memory override_
        ) {
            return override_;
        } catch {
            return vm.parseJsonString(rawVaultConfigJson, ".baseAssetSymbol");
        }
    }

    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function _setPeerIfNeeded(address oft, uint32 eid, bytes32 expected) internal {
        bytes32 current = IOAppCore(oft).peers(eid);
        string memory label =
            string.concat("setPeer(eid=", uint256(eid).toString(), ", peer=", vm.toString(expected), ")");
        if (current == expected) {
            _logSkipped(label);
            return;
        }
        execute(oft, abi.encodeCall(IOAppCore.setPeer, (eid, expected)), label);
    }
}
