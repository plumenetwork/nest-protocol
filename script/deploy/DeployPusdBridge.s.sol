// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {ConfigReader, LZConfig, DVNConfig} from "script/lib/ConfigReader.sol";
import {NestVaultOFT} from "contracts/NestVaultOFT.sol";
import {NestAccountant} from "contracts/accountant/NestAccountant.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {
    SetConfigParam,
    IMessageLibManager
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {SerializedTx} from "script/lib/SafeBatchSerialize.sol";
import {console} from "forge-std/console.sol";

interface IAuthUpgradeable {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function acceptOwnership() external;
}

interface IOwnable {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

/// @title  DeployPusdBridge
/// @notice Minimal: deploy a non-base-asset NestVaultOFT, wire LZ peer + ULN config (custom
///         confirmations + required DVNs = LZ + Nethermind) for one destination chain, queue
///         TELLER_ROLE on the vault RolesAuthority, transfer ownership (vault + ProxyAdmin) to
///         msig, and queue acceptOwnership for msig execution.
/// @dev    Env:
///           VAULT_SYMBOL    — e.g. "nALPHA"
///           ASSET_SYMBOL    — e.g. "pUSD"
///           CHAIN_ID        — source chain id (overrides JSON deployChainId)
///           DEST_CHAIN_ID   — destination chain id (peer)
///           NEW_OWNER       — msig to receive vault ownership
///           CONFIRMATIONS   — optional, default 5
///           PRIVATE_KEY     — deployer key
///
///         Usage:
///           VAULT_SYMBOL=nALPHA ASSET_SYMBOL=pUSD CHAIN_ID=1 DEST_CHAIN_ID=98866 \
///             NEW_OWNER=0x... \
///             forge script script/deploy/DeployPusdBridge.s.sol \
///             --sig "run()" --rpc-url $ETHEREUM_RPC_URL --broadcast
contract DeployPusdBridge is BaseConfigScript {
    uint32 constant CONFIG_TYPE_ULN = 2;
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function setUp() public {
        string memory vaultSymbol = vm.envString("VAULT_SYMBOL");
        loadConfigs(vaultSymbol);
    }

    function run() external {
        string memory assetSymbol = vm.envString("ASSET_SYMBOL");
        uint256 destChainId = vm.envUint("DEST_CHAIN_ID");
        uint64 confirmations = uint64(vm.envOr("CONFIRMATIONS", uint256(5)));
        address newOwner = vm.envAddress("NEW_OWNER");
        require(newOwner != address(0), "NEW_OWNER is zero");

        address asset = ConfigReader.readAssetAddress(vaultConfig.deployChainId, assetSymbol);

        hybridMode = true;
        vm.startBroadcast(deployerPrivateKey);

        address vault = _deployVaultIfNeeded(asset, assetSymbol);
        _currentLzOft = vault;

        _ensureRateProviderData(asset, assetSymbol);

        LZConfig memory destLZ = ConfigReader.readLZConfig(destChainId);

        // setPeer (same address on dest via CREATE3)
        bytes32 peer = bytes32(uint256(uint160(vault)));
        _preflightDestReady(vault, destChainId, peer);
        if (IOAppCore(vault).peers(destLZ.eid) != peer) {
            execute(vault, abi.encodeCall(IOAppCore.setPeer, (destLZ.eid, peer)), "setPeer");
        } else {
            console.log("    [SKIP] setPeer");
        }

        // Custom ULN config: 5 conf, required = [lz, nethermind] sorted ascending
        address[] memory dvns = _sortedRequiredDVNs(destChainId);
        UlnConfig memory uln = UlnConfig({
            confirmations: confirmations,
            requiredDVNCount: uint8(dvns.length),
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: dvns,
            optionalDVNs: new address[](0)
        });
        bytes memory desired = abi.encode(uln);

        _setUlnConfig(vault, lzConfig.sendLib302, destLZ.eid, desired, "sendLib");
        _setUlnConfig(vault, lzConfig.receiveLib302, destLZ.eid, desired, "receiveLib");

        address auth = vaultConfig.contracts.rolesAuthority;
        require(auth != address(0), "rolesAuthority not set in vault config");

        // Wire vault.authority -> nALPHA RolesAuthority (deployer is owner, broadcast direct)
        _setAuthorityOnVault(vault, auth);

        // Queue TELLER_ROLE on vault — RolesAuthority is msig-owned
        if (!RolesAuthority(auth).doesUserHaveRole(vault, TELLER_ROLE)) {
            execute(
                auth,
                abi.encodeCall(RolesAuthority.setUserRole, (vault, TELLER_ROLE, true)),
                "setUserRole(vault, TELLER_ROLE, true)"
            );
        } else {
            console.log("    [SKIP] setUserRole(TELLER_ROLE) - already granted");
        }

        // Transfer vault ownership (two-step) + ProxyAdmin ownership (one-step) to msig
        _transferVaultOwnership(vault, newOwner);
        _transferProxyAdminOwnership(vault, newOwner);

        // Queue acceptOwnership for msig
        _queueAcceptOwnership(vault, newOwner);

        vm.stopBroadcast();

        _currentLzOft = address(0);
        writeMsigBatch("DeployPusdBridge");

        console.log("=== Summary ===");
        console.log("Vault:", vault);
        console.log("Source chain:", vaultConfig.deployChainId);
        console.log("Dest chain:", destChainId);
        console.log("Dest eid:", destLZ.eid);
        console.log("Confirmations:", confirmations);
        console.log("Required DVNs:");
        for (uint256 i = 0; i < dvns.length; i++) {
            console.log("  ", dvns[i]);
        }
    }

    function _deployVaultIfNeeded(address asset, string memory assetSymbol) internal returns (address) {
        // If config already has a deployed vault for this asset on this chain, reuse it
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            if (keccak256(bytes(vaultConfig.vaults[i].assetSymbol)) == keccak256(bytes(assetSymbol))) {
                address existing = vaultConfig.vaults[i].addr;
                if (existing != address(0) && existing.code.length > 0) {
                    console.log("    [EXISTS] Vault:", existing);
                    return existing;
                }
                break;
            }
        }

        NestVaultOFT impl =
            new NestVaultOFT(payable(vaultConfig.contracts.share), lzConfig.endpoint, commonConfig.permit2);
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
        address vault = CREATEX.deployCreate3(
            salt,
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode, abi.encode(address(impl), deployer(), initData)
            )
        );
        console.log("    [DEPLOY] Vault:", vault);
        return vault;
    }

    /// @dev Non-base vault flows (deposit/redeem/previews/totalAssets) revert until the accountant
    ///      has RateProviderData for the asset. Set it from the reviewed vault entry, or fail fast.
    function _ensureRateProviderData(address asset, string memory assetSymbol) internal {
        try NestAccountant(vaultConfig.contracts.accountant).getRateInQuote(ERC20(asset)) returns (uint256) {
            console.log("    [SKIP] setRateProviderData - quote already usable");
            return;
        } catch {}
        bool found;
        bool isPegged;
        address rateProvider;
        for (uint256 i = 0; i < vaultConfig.vaults.length; i++) {
            if (keccak256(bytes(vaultConfig.vaults[i].assetSymbol)) == keccak256(bytes(assetSymbol))) {
                (found, isPegged, rateProvider) =
                (true, vaultConfig.vaults[i].isPegged, vaultConfig.vaults[i].rateProvider);
                break;
            }
        }
        require(
            found && (isPegged || rateProvider != address(0)),
            "DeployPusdBridge: accountant.getRateInQuote(asset) reverts and the vault config entry has no isPegged/rateProvider. Add them to contracts.vaults[] for this asset and re-run, or have the accountant owner call setRateProviderData before enabling vault flows."
        );
        execute(
            vaultConfig.contracts.accountant,
            abi.encodeCall(NestAccountant.setRateProviderData, (ERC20(asset), isPegged, rateProvider)),
            string.concat("setRateProviderData(", assetSymbol, ")")
        );
    }

    function _sortedRequiredDVNs(uint256 destChainId) internal view returns (address[] memory) {
        DVNConfig memory dvn = ConfigReader.readDVNs(vaultConfig.deployChainId, destChainId);
        require(dvn.lz != address(0), "missing lz DVN");
        require(dvn.nethermind != address(0), "missing nethermind DVN");
        address[] memory arr = new address[](2);
        if (dvn.lz < dvn.nethermind) {
            arr[0] = dvn.lz;
            arr[1] = dvn.nethermind;
        } else {
            arr[0] = dvn.nethermind;
            arr[1] = dvn.lz;
        }
        return arr;
    }

    /// @dev Same-address peer is intentional (CREATE3); verify the destination leg is real before
    ///      wiring. SKIP_DEST_PREFLIGHT=true bypasses for the first leg of the two-chain bootstrap.
    function _preflightDestReady(address vault, uint256 destChainId, bytes32 expectedPeer) internal {
        if (vm.envOr("SKIP_DEST_PREFLIGHT", false)) {
            console.log("    [WARN] SKIP_DEST_PREFLIGHT=true - destination code/reverse peer NOT verified.");
            console.log("           Run DeployPusdBridge on the destination chain before enabling public send.");
            return;
        }
        string memory destRpc = vm.envString(ConfigReader.readCommonConfig(destChainId).rpcEnvVar);
        bytes memory code = vm.rpc(destRpc, "eth_getCode", string.concat('["', vm.toString(vault), '","latest"]'));
        require(
            code.length > 0,
            "DeployPusdBridge: no code at vault address on DEST_CHAIN_ID; deploy the destination leg first, or set SKIP_DEST_PREFLIGHT=true for the bootstrap run and re-run with the check on afterwards"
        );
        bytes memory callData = abi.encodeWithSelector(IOAppCore.peers.selector, lzConfig.eid);
        bytes memory ret = vm.rpc(
            destRpc,
            "eth_call",
            string.concat('[{"to":"', vm.toString(vault), '","data":"', vm.toString(callData), '"},"latest"]')
        );
        require(
            ret.length == 32 && bytes32(ret) == expectedPeer,
            "DeployPusdBridge: destination vault does not peer back to this chain; run DeployPusdBridge there with mirrored CHAIN_ID/DEST_CHAIN_ID, or set SKIP_DEST_PREFLIGHT=true"
        );
        console.log("    [OK] destination code + reverse peer verified");
    }

    function _setAuthorityOnVault(address vault, address rolesAuth) internal {
        Authority current = Auth(vault).authority();
        if (address(current) == rolesAuth) {
            console.log("    [SKIP] vault.setAuthority - already wired");
            return;
        }
        Auth(vault).setAuthority(Authority(rolesAuth));
        console.log("    [BROADCAST] vault.setAuthority ->", rolesAuth);
    }

    function _transferVaultOwnership(address vault, address newOwner) internal {
        IAuthUpgradeable v = IAuthUpgradeable(vault);
        if (v.owner() == newOwner) {
            console.log("    [SKIP] vault.transferOwnership - already owned by msig");
            return;
        }
        if (v.pendingOwner() == newOwner) {
            console.log("    [SKIP] vault.transferOwnership - pendingOwner already msig");
            return;
        }
        v.transferOwnership(newOwner);
        console.log("    [BROADCAST] vault.transferOwnership ->", newOwner);
    }

    function _transferProxyAdminOwnership(address proxy, address newOwner) internal {
        address admin = address(uint160(uint256(vm.load(proxy, ADMIN_SLOT))));
        if (admin == address(0)) {
            console.log("    [SKIP] ProxyAdmin - none found");
            return;
        }
        address current = IOwnable(admin).owner();
        if (current == newOwner) {
            console.log("    [SKIP] proxyAdmin.transferOwnership - already owned by msig");
            return;
        }
        IOwnable(admin).transferOwnership(newOwner);
        require(IOwnable(admin).owner() == newOwner, "ProxyAdmin transfer failed");
        console.log("    [BROADCAST] proxyAdmin.transferOwnership ->", newOwner);
    }

    function _queueAcceptOwnership(address vault, address newOwner) internal {
        if (IAuthUpgradeable(vault).owner() == newOwner) {
            console.log("    [SKIP] queue acceptOwnership - already owned by msig");
            return;
        }
        // Force-queue: vault.owner is still deployer post-transferOwnership (two-step),
        // so execute() would broadcast and revert (msg.sender != pendingOwner). Push direct.
        serializedTxs.push(
            SerializedTx({
                name: "acceptOwnership", to: vault, value: 0, data: abi.encodeCall(IAuthUpgradeable.acceptOwnership, ())
            })
        );
    }

    function _setUlnConfig(address oft, address lib, uint32 dstEid, bytes memory desired, string memory libName)
        internal
    {
        bytes memory current = IMessageLibManager(lzConfig.endpoint).getConfig(oft, lib, dstEid, CONFIG_TYPE_ULN);
        if (keccak256(current) == keccak256(desired)) {
            console.log(string.concat("    [SKIP] setConfig(", libName, ")"));
            return;
        }
        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({eid: dstEid, configType: CONFIG_TYPE_ULN, config: desired});
        execute(
            lzConfig.endpoint,
            abi.encodeCall(IMessageLibManager.setConfig, (oft, lib, params)),
            string.concat("setConfig(", libName, ")")
        );
    }
}
