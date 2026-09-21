// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {ConfigReader, LZConfig, VaultDeployConfig, VaultEntry} from "script/lib/ConfigReader.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {console} from "forge-std/console.sol";

/// @title  DisablePeers
/// @notice Inverse of SetPeers: severs every LayerZero link that touches a "disabled" chain by
///         queueing setPeer(eid, bytes32(0)) on this chain's canonical OApp.
/// @dev    Disabled chains are BNB (56), World (480) and Plasma (9745). A link is severed when
///         EITHER endpoint is disabled, so to fully unbridge those chains run this on every chain
///         in the vault's peer list — both the disabled chains and the survivors (Plume/Ethereum):
///           - run on a disabled chain (e.g. 56) -> zeroes ALL its peers (Plume/Eth/Solana/others)
///           - run on a survivor (e.g. 98866/1)  -> zeroes only its peers TO disabled chains
///         Both directions of each link are zeroed this way, so no in-flight message can land on a
///         chain whose inbound peer was removed (LZ rejects mismatched senders -> stuck funds).
///
///         OApp resolution mirrors SetPeers:
///           - OFT src  (NestVaultOFT) -> canonical vault on this chain (by base asset, w/ overrides)
///           - non-OFT  (NestVault)    -> share (e.g. World Chain via vaultTypeOverrides)
///
///         Solana (101) is a *target* eid on the EVM OApps, so this DOES zero the EVM side of any
///         EVM<->Solana link to a disabled chain. The Solana program's own peers (the reverse leg)
///         live in a PDA and must be zeroed separately via tasks/solana/*.
///
///         Idempotent: skips OApps with no code and peers already at bytes32(0).
///         EXTRA_DISABLED_CHAIN_IDS (optional, comma-separated chain ids): extra chains treated
///         as disabled and visited even if already removed from the config's peers list.
///         Ordering: run this script on every affected chain BEFORE removing a chain from config.
///         Output: script/output/msig/<chainId>-<symbol>-DisablePeers.json
///
///         Usage (per chain, dry-run writes the batch without broadcasting):
///           VAULT_SYMBOL=nALPHA CHAIN_ID=56 forge script script/setup/DisablePeers.s.sol \
///               --sig "runMsig()" --rpc-url $BSC_RPC_URL --ffi
contract DisablePeers is BaseConfigScript {
    using Strings for uint256;

    uint256 constant SOLANA_CHAIN_ID = 101;

    /// @dev EXTRA_DISABLED_CHAIN_IDS (comma-separated): treated as disabled AND visited even
    ///      when no longer in vaultConfig.peers. Run this script BEFORE removing chains from config.
    uint256[] internal extraDisabledChainIds;

    function setUp() public {
        loadConfigs(vm.envString("VAULT_SYMBOL"));
        _loadExtraDisabledChainIds();
    }

    /// @dev Strict parse: envOr would swallow a malformed list ("56;480", "56,abc") as "no extras",
    ///      silently skipping the retired chain. Unset/empty keeps the empty default.
    function _loadExtraDisabledChainIds() internal {
        try vm.envString("EXTRA_DISABLED_CHAIN_IDS") returns (string memory raw) {
            if (bytes(raw).length == 0) return;
            extraDisabledChainIds = vm.envUint("EXTRA_DISABLED_CHAIN_IDS", ",");
            for (uint256 i = 0; i < extraDisabledChainIds.length; i++) {
                console.log("    extra disabled chain:", extraDisabledChainIds[i]);
            }
        } catch {}
    }

    /// @dev Chains whose bridging is being torn down. Any link with an endpoint here is severed.
    function _isDisabledChain(uint256 chainId) internal view returns (bool) {
        if (chainId == 56 || chainId == 480 || chainId == 9745) return true;
        for (uint256 i = 0; i < extraDisabledChainIds.length; i++) {
            if (extraDisabledChainIds[i] == chainId) return true;
        }
        return false;
    }

    function runDirect() external {
        _run(false);
    }

    function runMsig() external {
        _run(true);
        writeMsigBatch("DisablePeers");
    }

    /// @notice Hybrid: broadcasts on OApps the deployer owns, queues the rest into the Safe batch.
    function runHybrid() external {
        hybridMode = true;
        verbose = true;
        vm.startBroadcast(deployerPrivateKey);
        _disable();
        vm.stopBroadcast();
        writeMsigBatch("DisablePeers");
    }

    function _run(bool _msigMode) internal directOrMsig(_msigMode) {
        _disable();
    }

    function _disable() internal {
        address srcOApp = _srcOApp();
        if (srcOApp == address(0) || srcOApp.code.length == 0) {
            console.log("    [SKIP] no canonical OApp deployed on this chain for", vaultConfig.symbol);
            return;
        }

        uint256 srcChainId = vaultConfig.deployChainId;
        bool srcDisabled = _isDisabledChain(srcChainId);
        _currentLzOft = srcOApp;
        console.log("    Disabling peers on OApp:", srcOApp);

        for (uint256 i = 0; i < vaultConfig.peers.length; i++) {
            uint256 peerChainId = vaultConfig.peers[i];
            if (peerChainId == srcChainId) continue;
            // Only sever links that touch a disabled chain; leave the survivor triangle intact.
            if (!srcDisabled && !_isDisabledChain(peerChainId)) continue;

            uint32 eid = ConfigReader.readLZConfig(peerChainId).eid;
            _zeroPeerIfNeeded(srcOApp, eid, peerChainId);
        }

        // Chains removed from config peers are invisible to the loop above; visit the
        // env-supplied extras so their stale peers still get zeroed.
        for (uint256 i = 0; i < extraDisabledChainIds.length; i++) {
            uint256 chainId = extraDisabledChainIds[i];
            if (chainId == srcChainId || _isConfigPeer(chainId)) continue;
            _zeroPeerIfNeeded(srcOApp, ConfigReader.readLZConfig(chainId).eid, chainId);
        }

        _currentLzOft = address(0);
    }

    function _isConfigPeer(uint256 chainId) internal view returns (bool) {
        for (uint256 i = 0; i < vaultConfig.peers.length; i++) {
            if (vaultConfig.peers[i] == chainId) return true;
        }
        return false;
    }

    /// @dev Source OApp on this chain: canonical vault for OFT, share otherwise (mirrors SetPeers).
    function _srcOApp() internal view returns (address) {
        if (isOFT()) {
            (bool exists, VaultDeployConfig memory src) =
                ConfigReader.tryReadOutputConfig(vaultConfig.deployChainId, vaultConfig.symbol);
            if (!exists) return address(0);
            return _findVaultByAsset(src.vaults, vaultConfig.baseAssetSymbol);
        }
        return vaultConfig.contracts.share;
    }

    function _zeroPeerIfNeeded(address oApp, uint32 eid, uint256 peerChainId) internal {
        bytes32 current = IOAppCore(oApp).peers(eid);
        string memory label =
            string.concat("setPeer(eid=", uint256(eid).toString(), " [chain ", peerChainId.toString(), "], peer=0)");
        if (current == bytes32(0)) {
            _logSkipped(string.concat(label, " already zero"));
            return;
        }
        execute(
            oApp,
            abi.encodeCall(IOAppCore.setPeer, (eid, bytes32(0))),
            string.concat(label, " [was ", vm.toString(current), "]")
        );
    }

    function _findVaultByAsset(VaultEntry[] memory vaults, string memory assetSymbol) internal pure returns (address) {
        bytes32 key = keccak256(bytes(assetSymbol));
        for (uint256 i = 0; i < vaults.length; i++) {
            if (keccak256(bytes(vaults[i].assetSymbol)) == key) return vaults[i].addr;
        }
        return address(0);
    }
}
