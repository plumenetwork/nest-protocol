// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {Constants} from "script/Constants.sol";
import {L0Constants, L0Config, NestVaultConfig, NestShareConfig} from "script/L0Constants.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    EnforcedOptionParam,
    IOAppOptionsType3
} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {SerializedTx, SafeTxUtil} from "script/SafeBatchSerialize.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {NestVaultOFT} from "contracts/NestVaultOFT.sol";
import {NestVault} from "contracts/NestVault.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    SetConfigParam,
    IMessageLibManager
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

abstract contract BaseL0Script is Script, L0Constants {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    uint256 public oftDeployerPK = vm.envUint("PRIVATE_KEY");
    uint256 public configDeployerPK = vm.envUint("PRIVATE_KEY");

    L0Config[] public proxyConfigs;
    L0Config[] public evmConfigs;
    L0Config[] public nonEvmConfigs;
    L0Config[] public allConfigs; // proxy and non-evm configs
    L0Config public broadcastConfig; // config of actively-connected (broadcasting) chain
    L0Config public simulateConfig; // Config of the simulated chain

    // assume we're deploying to mainnet unless the broadcastConfig is set to a testnet
    bool public isMainnet = true;

    /// @dev alphabetical order as json is read in by keys alphabetically.
    struct NonEvmPeer {
        bytes32 addressBytes32;
        uint32 eid;
        string oftStore;
        string symbol;
    }
    NonEvmPeer[] internal _nonEvmPeersArrays;

    function nonEvmPeersArrays() public view returns (NonEvmPeer[] memory) {
        return _nonEvmPeersArrays;
    }

    // Deployed NestVaultOFTs
    address[] public nestVaultOFTs;

    // Deployed NestShareOFTs
    address[] public nestShareOFTs;

    // temporary storage
    EnforcedOptionParam[] public enforcedOptionParams;
    SerializedTx[] public serializedTxs;

    string public json;

    function version() public pure virtual returns (uint256, uint256, uint256) {
        return (1, 3, 2);
    }

    modifier broadcastAs(uint256 privateKey) {
        vm.startBroadcast(privateKey);
        _;
        vm.stopBroadcast();
    }

    modifier simulateAndWriteTxs(L0Config memory _simulateConfig) virtual {
        // Clear out any previous txs
        delete enforcedOptionParams;
        delete serializedTxs;

        // store for later referencing
        simulateConfig = _simulateConfig;

        // Use the correct OFT addresses given the chain we're simulating
        _populateConnectedOfts();

        // Simulate fork as delegate (aka msig) as we're crafting txs within the modified function
        vm.createSelectFork(_simulateConfig.RPC);
        vm.startPrank(_simulateConfig.delegate);
        _;
        vm.stopPrank();

        // serialized txs were pushed within the modified function- write to storage
        if (serializedTxs.length > 0) {
            new SafeTxUtil().writeTxs(serializedTxs, filename());
        }
    }

    // Configure destination OFT addresses as they may be different per chain
    // `connectedOfts` is used within DeployNestOFTProtocol.setupDestination()
    function _populateConnectedOfts() public virtual {
        isMainnet ? _validateAndPopulateMainnetOfts() : _validateAndPopulateTestnetOfts();
    }

    function _validateAndPopulateMainnetOfts() internal virtual;

    function _validateAndPopulateTestnetOfts() internal virtual {
        revert("validate and populate testnet Ofts not implemented");
    }

    function filename() public view virtual returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/script/DeployNestOFTProtocol/txs/");

        string memory name = string.concat(broadcastConfig.chainid.toString(), "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, getFileExtension());
        return string.concat(root, name);
    }

    function getFileExtension() internal view virtual returns (string memory) {
        return ".json";
    }

    function setUp() public virtual {
        // Set constants based on deployment chain id
        loadJsonConfig();
    }

    function loadJsonConfig() public virtual {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/L0Config.json");
        json = vm.readFile(path);

        loadL0Config();
        loadNonEvmPeers();
    }

    function loadL0Config() internal virtual {
        loadProxyConfigs();
        loadNonEvmConfigs();
    }

    function loadProxyConfigs() internal virtual {
        // Struct fields are in alphabetical order matching JSON keys,
        // so we can use the simple approach like frax-oft-upgradeable
        proxyConfigs = abi.decode(json.parseRaw(".Proxy"), (L0Config[]));

        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid == block.chainid) {
                broadcastConfig = proxyConfigs[i];
            }
            allConfigs.push(proxyConfigs[i]);
            evmConfigs.push(proxyConfigs[i]);
        }
    }

    function loadNonEvmConfigs() internal virtual {
        // Non-EVM configs use the same simple approach
        nonEvmConfigs = abi.decode(json.parseRaw(".Non-EVM"), (L0Config[]));

        for (uint256 i = 0; i < nonEvmConfigs.length; i++) {
            allConfigs.push(nonEvmConfigs[i]);
        }
    }

    function loadNonEvmPeers() internal virtual {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/NonEvmPeers.json");
        string memory peersJson = vm.readFile(path);

        NonEvmPeer[] memory nonEvmPeers = abi.decode(vm.parseJson(peersJson, ".Peers"), (NonEvmPeer[]));

        for (uint256 i = 0; i < nonEvmPeers.length; i++) {
            _nonEvmPeersArrays.push(nonEvmPeers[i]);
        }
    }

    function isStringEqual(string memory _a, string memory _b) public pure returns (bool) {
        return keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }

    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
