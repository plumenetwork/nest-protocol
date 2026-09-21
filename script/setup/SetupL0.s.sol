// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {
    ConfigReader,
    CommonConfig,
    LZConfig,
    DVNConfig,
    EnforcedOptionsConfig,
    VaultDeployConfig,
    VaultEntry
} from "script/lib/ConfigReader.sol";
import {SerializedTx, SafeTxUtil} from "script/lib/SafeBatchSerialize.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {
    IOAppOptionsType3,
    EnforcedOptionParam
} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import {
    SetConfigParam,
    IMessageLibManager
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {console} from "forge-std/console.sol";

/// @title  SetupL0
/// @notice Unified LayerZero verifier: for the local OApp (canonical vault if NestVaultOFT, else share),
///         walks every chain in vaultConfig.peers and queues only the txs that differ from on-chain
///         state — setPeer, setEnforcedOptions, setConfig (DVNs), setSendLibrary, setReceiveLibrary.
/// @dev    Peer resolution:
///           - Solana (chainId 101): reads `oftStoreBytes32` from deployments/solana-mainnet/{SYMBOL}-OFT.json.
///           - EVM: reads canonical vault (via baseAssetOverrides) or share addr from the peer chain's
///             output file (script/output/{SYMBOL}/{peerChainId}-{SYMBOL}.json).
///           - Peer chains whose output file is missing / canonical addr is zero are skipped.
///
///         Usage:
///           VAULT_SYMBOL=nTEST forge script script/setup/SetupL0.s.sol --sig "runSourceDirect()" --rpc-url $RPC --broadcast
///           (runSourceDirect requires the deployer EOA to be the current LZ delegate; otherwise use runSourceMsig/runSourceAuto)
///           VAULT_SYMBOL=nTEST forge script script/setup/SetupL0.s.sol --sig "runSourceMsig()" --rpc-url $RPC
contract SetupL0 is BaseConfigScript {
    using OptionsBuilder for bytes;
    using Strings for uint256;

    uint32 constant CONFIG_TYPE_ULN = 2;
    uint256 constant SOLANA_CHAIN_ID = 101;

    function setUp() public {
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");
        loadConfigs(vaultSymbol);
    }

    // ─── Entry Points ─────────────────────────────────────────────────

    function runSourceDirect() external {
        _setupSource(false);
    }

    function runSourceMsig() external {
        _setupSource(true);
        writeMsigBatch("SetupL0");
    }

    /// @notice Hybrid mode: each call routes per-target.
    ///           - target = endpoint  → broadcast if deployer EOA is the LZ delegate, else queue.
    ///           - target = OApp      → broadcast if deployer EOA is the OApp owner, else queue.
    ///         Lets us drain "EOA is delegate" cases via direct broadcast (setConfig /
    ///         setSendLibrary / setReceiveLibrary) while still queueing owner-gated OApp
    ///         calls (setPeer / setEnforcedOptions / setDelegate) to the Safe.
    function runSourceAuto() external {
        msigMode = false;
        hybridMode = true;
        vm.startBroadcast(deployerPrivateKey);
        _setupSourceBody();
        vm.stopBroadcast();
        if (serializedTxs.length > 0) writeMsigBatch("SetupL0");
    }

    // ─── Source Chain Setup ───────────────────────────────────────────

    function _setupSource(bool _msigMode) internal directOrMsig(_msigMode) {
        _setupSourceBody();
    }

    function _setupSourceBody() internal {
        address localOApp;
        if (isOFT()) {
            localOApp = _canonicalVaultAddr();
            if (localOApp == address(0) || localOApp.code.length == 0) {
                console.log("    [SKIP] canonical vault not deployed on this chain");
                return;
            }
            console.log("    Wiring canonical vault:", vaultConfig.baseAssetSymbol, localOApp);
        } else {
            localOApp = vaultConfig.contracts.share;
            if (localOApp == address(0) || localOApp.code.length == 0) {
                console.log("    [SKIP] share not deployed on this chain");
                return;
            }
            console.log("    Wiring share:", localOApp);
        }

        _currentLzOft = localOApp;

        // Direct mode broadcasts endpoint calls from the deployer EOA; fail fast before
        // any write if the EOA is not the LZ delegate (or the OApp itself).
        if (!msigMode && !hybridMode) {
            require(
                _isLzDelegate(),
                "SetupL0: deployer is not the LZ delegate for the local OApp; use runSourceMsig() or runSourceAuto()"
            );
        }

        // Endpoint setConfig/setSendLibrary/setReceiveLibrary require msg.sender == oapp
        // or msg.sender == delegates[oapp]. After ownership transfer the multisig owns the
        // OFT but isn't yet the endpoint delegate, so we queue setDelegate first — same
        // batch, MultiSend sequential, so subsequent endpoint calls pass auth.
        _setDelegateIfNeeded(localOApp);

        for (uint256 i = 0; i < vaultConfig.peers.length; i++) {
            uint256 peerChainId = vaultConfig.peers[i];
            if (peerChainId == vaultConfig.deployChainId) continue;

            bytes32 peerBytes = _resolvePeerBytes(peerChainId);
            if (peerBytes == bytes32(0)) {
                console.log("      [SKIP] no peer addr resolved for chain", peerChainId.toString());
                continue;
            }

            LZConfig memory peerLZ = ConfigReader.readLZConfig(peerChainId);

            _setPeerIfNeeded(localOApp, peerLZ.eid, peerBytes);
            _setEnforcedOptions(localOApp, peerChainId, peerLZ.eid);
            _setDVNs(localOApp, peerChainId);
            _setLibs(localOApp, peerLZ);
        }

        _currentLzOft = address(0);
    }

    // ─── Peer Resolution ──────────────────────────────────────────────

    /// @dev Peer-side OApp choice depends on the *peer* chain's vaultType, not local's.
    ///      If peer chain runs NestVaultOFT the OApp is the canonical vault; otherwise
    ///      (NestVault / NestShareOFT) the OApp is the share. Solves the case where
    ///      Plume runs vault-as-OFT but Worldchain runs share-as-OFT for the same vault.
    function _resolvePeerBytes(uint256 peerChainId) internal view returns (bytes32) {
        if (peerChainId == SOLANA_CHAIN_ID) return _solanaOftStore();

        (bool exists, VaultDeployConfig memory dst) = ConfigReader.tryReadOutputConfig(peerChainId, vaultConfig.symbol);
        if (!exists) return bytes32(0);

        if (_peerIsOFT(peerChainId)) {
            address dstVault = _findVaultByAsset(dst.vaults, _canonicalAssetFor(peerChainId));
            if (dstVault == address(0)) return bytes32(0);
            return _addressToBytes32(dstVault);
        }

        if (dst.contracts.share == address(0)) return bytes32(0);
        return _addressToBytes32(dst.contracts.share);
    }

    function _peerIsOFT(uint256 peerChainId) internal view returns (bool) {
        string memory peerType;
        try vm.parseJsonString(
            rawVaultConfigJson, string.concat(".vaultTypeOverrides.", peerChainId.toString())
        ) returns (
            string memory override_
        ) {
            peerType = override_;
        } catch {
            try vm.parseJsonString(rawVaultConfigJson, ".vaultType") returns (string memory base) {
                peerType = base;
            } catch {
                peerType = "";
            }
        }
        return ConfigReader.isOFT(peerType);
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

    /// @dev Resolves the canonical OApp address on the LOCAL chain by reading the per-chain
    ///      script/output file (authoritative deployment state) and applying baseAssetOverrides.
    ///      Mirrors _resolvePeerBytes so local + peer resolution agree on the same source.
    function _canonicalVaultAddr() internal view returns (address) {
        uint256 chainId = vaultConfig.deployChainId;
        (bool exists, VaultDeployConfig memory local) = ConfigReader.tryReadOutputConfig(chainId, vaultConfig.symbol);
        if (!exists) return address(0);
        return _findVaultByAsset(local.vaults, _canonicalAssetFor(chainId));
    }

    function _findVaultByAsset(VaultEntry[] memory vaults, string memory assetSymbol) internal pure returns (address) {
        bytes32 key = keccak256(bytes(assetSymbol));
        for (uint256 i = 0; i < vaults.length; i++) {
            if (keccak256(bytes(vaults[i].assetSymbol)) == key) return vaults[i].addr;
        }
        return address(0);
    }

    function _canonicalAssetFor(uint256 chainId) internal view returns (string memory) {
        try vm.parseJsonString(rawVaultConfigJson, string.concat(".baseAssetOverrides.", chainId.toString())) returns (
            string memory override_
        ) {
            return override_;
        } catch {
            return vm.parseJsonString(rawVaultConfigJson, ".baseAssetSymbol");
        }
    }

    // ─── Idempotent Setters ───────────────────────────────────────────

    /// @dev Ensures the principal that will execute endpoint calls is the LZ delegate.
    ///      In direct/hybrid mode the deployer EOA broadcasts endpoint calls — if it's already
    ///      the delegate, no change is needed. Otherwise we queue setDelegate(Safe) so the
    ///      multisig can run subsequent endpoint calls in the same batch.
    function _setDelegateIfNeeded(address oft) internal {
        address current = _readDelegate(oft);
        address target = commonConfig.multisig;
        string memory label = string.concat("setDelegate(", vm.toString(target), ")");
        if (current == target) {
            _logSkipped(label);
            return;
        }
        // The multisig should end up as the LZ delegate so it can run (and later govern) the
        // delegate-gated endpoint calls. setDelegate is owner-gated, so execute() queues it to
        // the Safe whenever the call routes to the multisig — pure msig mode, or hybrid where the
        // deployer is not the OApp owner — and broadcasts it inline otherwise. Queue it in every
        // such case (MultiSend runs it ahead of the delegate-gated setConfig/setLib calls). Skip
        // ONLY when it would broadcast inline while the deployer EOA is the current delegate:
        // that would strip the EOA's delegate before its own endpoint broadcasts in this run.
        bool willQueue = msigMode || (hybridMode && !_isOwner(oft));
        if (current == vm.addr(deployerPrivateKey) && !willQueue) {
            _logSkipped(
                string.concat("setDelegate(", vm.toString(current), ") - EOA stays delegate (inline broadcast)")
            );
            return;
        }
        execute(oft, abi.encodeCall(IOAppCore.setDelegate, (target)), label);
    }

    function _readDelegate(address oft) internal view returns (address) {
        (bool ok, bytes memory ret) = lzConfig.endpoint.staticcall(abi.encodeWithSignature("delegates(address)", oft));
        if (!ok || ret.length < 32) return address(0);
        return abi.decode(ret, (address));
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

    /// @dev Enforced options executed on dst chain; gas values come from dst config.
    ///      Skips msgType 2 (compose) when composeGas == 0 (used to disable compose for Solana).
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
        execute(
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

    /// @dev Idempotency check compares only the DVN fields against the merged on-chain
    ///      UlnConfig — non-DVN fields (confirmations, optional DVNs) are left unset in
    ///      the override (=0 → fall back to lib default), so we don't accidentally lock in
    ///      the current default values into custom storage.
    function _setConfigOnEndpoint(address endpoint, address oft, address lib, uint32 dstEid, address[] memory dvns)
        internal
    {
        UlnConfig memory current =
            abi.decode(IMessageLibManager(endpoint).getConfig(oft, lib, dstEid, CONFIG_TYPE_ULN), (UlnConfig));

        string memory label = string.concat(
            "setConfig(eid=", vm.toString(dstEid), ", lib=", vm.toString(lib), ", dvns=[", _formatDVNs(dvns), "])"
        );

        if (current.requiredDVNCount == uint8(dvns.length) && _addrArrEq(current.requiredDVNs, dvns)) {
            _logSkipped(label);
            return;
        }

        UlnConfig memory desired;
        desired.requiredDVNCount = uint8(dvns.length);
        desired.requiredDVNs = dvns;

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({eid: dstEid, configType: CONFIG_TYPE_ULN, config: abi.encode(desired)});

        execute(endpoint, abi.encodeCall(IMessageLibManager.setConfig, (oft, lib, params)), label);
    }

    function _addrArrEq(address[] memory a, address[] memory b) internal pure returns (bool) {
        if (a.length != b.length) return false;
        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    function _formatDVNs(address[] memory dvns) internal pure returns (string memory s) {
        for (uint256 i = 0; i < dvns.length; i++) {
            s = i == 0 ? vm.toString(dvns[i]) : string.concat(s, ",", vm.toString(dvns[i]));
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
        address currentLib = IMessageLibManager(lzConfig.endpoint).getSendLibrary(oft, peerLZ.eid);
        bool isDefaultSend = IMessageLibManager(lzConfig.endpoint).isDefaultSendLibrary(oft, peerLZ.eid);
        if (currentLib != lzConfig.sendLib302 || isDefaultSend) {
            execute(
                lzConfig.endpoint,
                abi.encodeCall(IMessageLibManager.setSendLibrary, (oft, peerLZ.eid, lzConfig.sendLib302)),
                string.concat("setSendLibrary(eid=", vm.toString(peerLZ.eid), ")")
            );
        } else {
            _logSkipped(string.concat("setSendLibrary(eid=", vm.toString(peerLZ.eid), ")"));
        }

        (address recvLib, bool isDefaultRecv) = IMessageLibManager(lzConfig.endpoint).getReceiveLibrary(oft, peerLZ.eid);
        if (recvLib != lzConfig.receiveLib302 || isDefaultRecv) {
            execute(
                lzConfig.endpoint,
                abi.encodeCall(IMessageLibManager.setReceiveLibrary, (oft, peerLZ.eid, lzConfig.receiveLib302, 0)),
                string.concat("setReceiveLibrary(eid=", vm.toString(peerLZ.eid), ")")
            );
        } else {
            _logSkipped(string.concat("setReceiveLibrary(eid=", vm.toString(peerLZ.eid), ")"));
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /// @dev Checks if enforced options for each msgType already match.
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
}
