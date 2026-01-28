// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "script/vendor/@openzeppelin-4.9.6/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BoringVaultSY} from "contracts/BoringVaultSY.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Constants} from "script/Constants.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {SerializedTx, SafeTxUtil} from "script/SafeBatchSerialize.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {ICreateX} from "createx/ICreateX.sol";

struct NestConfig {
    string RPC;
    address accountant;
    address boringVault;
    uint256 chainid;
    address delegate;
    uint256 eid;
    address endpoint;
    address manager;
    address owner;
    address proxyAdmin;
    address receiveLib302;
    address rolesAuthority;
    address sendLib302;
    string symbol;
    address teller;
}

contract DeployBoringVaultSYSingle is Script, Constants {
    uint256 public oftDeployerPK = vm.envUint("PK_DEPLOYER");

    using stdJson for string;
    using Strings for uint256;

    NestConfig public broadcastConfig;
    NestConfig[] public broadcastConfigArray;
    NestConfig[] public nucleusConfigs;

    address public pendleProxyAdmin = 0xA28c08f165116587D4F3E708743B4dEe155c5E64;
    address public immutable pendlePauseController;

    string internal boringVaultSymbol;
    address internal asset;

    string public json;

    address public boringVaultSY;

    /// Custom base params
    ICreateX immutable CREATEX;

    SerializedTx[] public serializedTxs;

    string internal attempt;

    constructor() {
        if (block.chainid == 80094) {
            // berachain
            pendlePauseController = 0x830024529386a4A179BA6d1f31e8d49228674Cd0;
        } else {
            pendlePauseController = 0x2aD631F72fB16d91c4953A7f4260A97C2fE2f31e;
        }
        CREATEX = ICreateX(vm.envAddress("CREATEX"));

        if (address(CREATEX).code.length == 0) {
            revert("CREATEX Not Deployed on this chain. Use the DeployCustomCreatex script to deploy it");
        }
    }

    function setUp() public {
        string memory root = vm.projectRoot();

        string memory path = string.concat(root, "/script/NestConfig.json");
        json = vm.readFile(path);

        // nucleus vaults
        NestConfig[] memory _nucleusConfigs = abi.decode(json.parseRaw(".Nucleus"), (NestConfig[]));

        for (uint256 i = 0; i < _nucleusConfigs.length; i++) {
            NestConfig memory config_ = _nucleusConfigs[i];
            if (config_.chainid == block.chainid) {
                if (keccak256(abi.encodePacked(boringVaultSymbol)) == keccak256(abi.encodePacked(config_.symbol))) {
                    broadcastConfig = config_;
                }
                broadcastConfigArray.push(config_);
            }
            nucleusConfigs.push(config_);
        }
    }

    modifier broadcastAs(uint256 privateKey) {
        vm.startBroadcast(privateKey);
        _;
        vm.stopBroadcast();
    }

    function run() public {
        deployBoringVaultSY();
        postDeployBoringVaultSY();
    }

    function deployBoringVaultSY() public broadcastAs(oftDeployerPK) {
        address implementation =
            address(new BoringVaultSY(broadcastConfig.boringVault, pendlePauseController, asset, 0));

        bytes memory initializeArgs = abi.encodeWithSelector(
            BoringVaultSY.initialize.selector,
            broadcastConfig.accountant,
            string.concat("SY ", IERC20Metadata(broadcastConfig.boringVault).name()),
            string.concat("SY-", IERC20Metadata(broadcastConfig.boringVault).symbol()),
            pendlePauseController
        );

        string memory saltString = string.concat(broadcastConfig.symbol, attempt, " BoringVaultSY");
        bytes32 salt = generateCreate3Salt(vm.addr(oftDeployerPK), saltString);

        // Create Contract
        bytes memory creationCode = type(TransparentUpgradeableProxy).creationCode;
        boringVaultSY = address(
            TransparentUpgradeableProxy(
                payable(CREATEX.deployCreate3(
                        salt,
                        abi.encodePacked(creationCode, abi.encode(implementation, pendleProxyAdmin, initializeArgs))
                    ))
            )
        );
    }

    function postDeployBoringVaultSY() public {
        require(
            BoringVaultSY(payable(boringVaultSY)).owner() == pendlePauseController,
            "Owner of BoringVaultSY should be pendle pause controller"
        );
        require(
            keccak256(
                abi.encodePacked(
                    BoringVault(payable(address(BoringVaultSY(payable(boringVaultSY)).yieldToken()))).symbol()
                )
            ) == keccak256(abi.encodePacked(boringVaultSymbol)),
            "The BoringVault should be as expected"
        );
        vm.prank(pendleProxyAdmin);
        require(
            ITransparentUpgradeableProxy(boringVaultSY).admin() == pendleProxyAdmin,
            "ProxyAdmin of the BoringVaultSY should be PendleProxyAdmin"
        );
    }

    function filename() public view virtual returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/script/DeployBoringVaultSYSingleTxs/");

        string memory name = string.concat(broadcastConfig.chainid.toString(), "-BoringVaultSY-");
        name = string.concat(name, boringVaultSymbol);
        name = string.concat(name, getFileExtension());
        return string.concat(root, name);
    }

    function getFileExtension() internal view virtual returns (string memory) {
        return ".json";
    }

    function generateCreate3Salt(address broadcaster, string memory name) public pure returns (bytes32) {
        // hex"00 ensures address is deterministic across multi chain
        bytes32 generatedSalt = bytes32(abi.encodePacked(broadcaster, hex"00", stringHashToBytes11(name)));

        return generatedSalt;
    }

    function stringHashToBytes11(string memory name) internal pure returns (bytes11) {
        return bytes11(keccak256(bytes(name))); // first 11 bytes of the keccak256
    }
}
