// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {BaseConfigScript} from "script/lib/BaseConfigScript.sol";
import {ConfigReader} from "script/lib/ConfigReader.sol";
// Pendle SY checklist requires OZ 4.9.x semantics: the admin parameter is set as the proxy admin
// directly, with no auto-deployed ProxyAdmin (OZ 5.x deploys a fresh ProxyAdmin internally).
import {TransparentUpgradeableProxy} from "@openzeppelin-4.9.3/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BoringVaultSY} from "contracts/integrations/pendle/BoringVaultSY.sol";
import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {console} from "forge-std/console.sol";

/// @title  DeployBoringVaultSY
/// @notice Deploys a Pendle SY wrapper (BoringVaultSY) for a single Nest vault, per Pendle's SY
///         Deployment Checklist:
///           - TransparentUpgradeableProxy with Pendle's canonical ProxyAdmin as admin
///             (0xA28c08f165116587D4F3E708743B4dEe155c5E64) — do NOT deploy a new ProxyAdmin.
///           - Name: "SY " + yieldToken.name(); Symbol: "SY-" + yieldToken.symbol().
///           - Owner: Pendle pause controller (per-chain) so the SY can be paused in emergency.
///
///         Direct broadcast only — CREATE3 salts in BaseConfigScript embed the deployer EOA and
///         Safe batches cannot serialize CreateX deploys.
///
///         Usage:
///           VAULT_SYMBOL=nALPHA CHAIN_ID=1 \
///             forge script script/deploy/DeployBoringVaultSY.s.sol \
///             --sig "runDirect()" --rpc-url $RPC --broadcast --ffi
contract DeployBoringVaultSY is BaseConfigScript {
    /// @notice Pendle's canonical ProxyAdmin — required by the SY Deployment Checklist on every chain.
    address internal constant PENDLE_PROXY_ADMIN = 0xA28c08f165116587D4F3E708743B4dEe155c5E64;

    /// @notice Pendle's pause controller on Berachain (chain id 80094).
    address internal constant PENDLE_PAUSE_CONTROLLER_BERA = 0x830024529386a4A179BA6d1f31e8d49228674Cd0;

    /// @notice Pendle's pause controller on every other supported chain.
    address internal constant PENDLE_PAUSE_CONTROLLER_DEFAULT = 0x2aD631F72fB16d91c4953A7f4260A97C2fE2f31e;

    /// @dev EIP-1967 admin slot: bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1).
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address payable public boringVaultSY;
    address public implementation;

    function setUp() public {
        loadConfigs(vm.envString("VAULT_SYMBOL"));
    }

    function runDirect() external {
        _deploy();
        _postDeploy();
    }

    function _deploy() internal {
        address yieldToken = vaultConfig.contracts.share;
        address accountant = vaultConfig.contracts.accountant;
        require(isActive(yieldToken), "DeployBoringVaultSY: share (yieldToken) not deployed");
        require(isActive(accountant), "DeployBoringVaultSY: accountant not deployed");

        address baseAsset = ConfigReader.readAssetAddress(vaultConfig.deployChainId, vaultConfig.baseAssetSymbol);
        address pauseController = _pendlePauseController(vaultConfig.deployChainId);

        // Pendle checklist: "SY " + name() / "SY-" + symbol() of the yield token.
        string memory syName = string.concat("SY ", IERC20Metadata(yieldToken).name());
        string memory sySymbol = string.concat("SY-", IERC20Metadata(yieldToken).symbol());

        if (!needsDeploy(boringVaultSY)) {
            _logExists("BoringVaultSY", boringVaultSY);
            return;
        }

        vm.startBroadcast(deployerPrivateKey);

        implementation = address(new BoringVaultSY(yieldToken, pauseController, baseAsset, vaultConfig.minRate));

        bytes memory initData =
            abi.encodeWithSelector(BoringVaultSY.initialize.selector, accountant, syName, sySymbol, pauseController);

        bytes32 salt = generateCreate3Salt("BoringVaultSY");
        boringVaultSY = payable(CREATEX.deployCreate3(
                salt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(implementation, PENDLE_PROXY_ADMIN, initData)
                )
            ));

        vm.stopBroadcast();

        _logDeploy("BoringVaultSY", boringVaultSY);
        console.log("  implementation:        ", implementation);
        console.log("  yieldToken:            ", yieldToken);
        console.log("  asset:                 ", baseAsset);
        console.log("  accountant:            ", accountant);
        console.log("  name:                  ", syName);
        console.log("  symbol:                ", sySymbol);
        console.log("  owner (pauseController):", pauseController);
        console.log("  proxyAdmin (Pendle):    ", PENDLE_PROXY_ADMIN);
        console.log("  minRate:               ", vaultConfig.minRate);
    }

    function _postDeploy() internal view {
        address pauseController = _pendlePauseController(vaultConfig.deployChainId);

        require(
            BoringVaultSY(boringVaultSY).owner() == pauseController,
            "DeployBoringVaultSY: owner must be Pendle pause controller"
        );

        // EIP-1967 admin slot must hold Pendle's canonical ProxyAdmin.
        address proxyAdmin = address(uint160(uint256(vm.load(boringVaultSY, ADMIN_SLOT))));
        require(proxyAdmin == PENDLE_PROXY_ADMIN, "DeployBoringVaultSY: proxy admin must be Pendle ProxyAdmin");

        // yieldToken symbol must match the vault symbol from config (e.g. "nALPHA").
        address yieldToken = BoringVaultSY(boringVaultSY).yieldToken();
        require(
            keccak256(bytes(BoringVault(payable(yieldToken)).symbol())) == keccak256(bytes(vaultConfig.symbol)),
            "DeployBoringVaultSY: yieldToken symbol mismatch"
        );
    }

    function _pendlePauseController(uint256 chainId) internal pure returns (address) {
        if (chainId == 80094) return PENDLE_PAUSE_CONTROLLER_BERA; // Berachain
        return PENDLE_PAUSE_CONTROLLER_DEFAULT;
    }
}
