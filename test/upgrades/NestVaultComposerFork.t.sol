// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {NestVaultComposer} from "contracts/integrations/ovault/NestVaultComposer.sol";
import {NestVaultComposer as NestVaultComposerUpgrade} from "contracts/upgrades/compliance-proxy/NestVaultComposer.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev RUN_COMPOSER_UPGRADE_FORK_TEST=true PLUME_RPC_URL=... forge test --match-contract NestVaultComposerForkTest
contract NestVaultComposerForkTest is Test {
    bytes32 private constant ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
    bytes32 private constant IMPLEMENTATION_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
    bytes32 private constant INITIALIZABLE_SLOT = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
    bytes32 private constant SYNC_SLOT = 0xc537560042629e8880bf5e9fca9de99531ceefbe83dcee9e2560a43447673800;
    bytes32 private constant ASYNC_SLOT = 0x675d05f61eb76f02999633de01879883f3d5f70be938ea35e43653caafefd900;
    bytes32 private constant AUTH_SLOT = 0x341f7c713c76cb881fd7047f7cccebe3fe10eddfc5e20fe83ee7e0b505e8ea00;
    address private constant COMPOSER = 0x1daF84Ae51CcD1D9cdeDfF31e689cD2aA7579034;
    address private constant SYNC_COMPOSER = 0xEe47001b301557186DBfb9999Aa219846BBf188D;
    address private constant COMPLIANCE_PROXY = 0xF325E0f939963b42A22538B98b30E1CAeB2C37bA;

    function setUp() public {
        if (!vm.envOr("RUN_COMPOSER_UPGRADE_FORK_TEST", false)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(vm.envString("PLUME_RPC_URL"), 93_294_861);
    }

    function test_liveNtestVersionTwoUpgradesAtomicallyToComplianceProxy() public {
        NestVaultComposer composer = NestVaultComposer(payable(COMPOSER));
        assertEq(composer.version(), "1.2.0");
        _migrate(COMPOSER);

        IERC20 asset = IERC20(composer.ASSET_ERC20());
        ProxyAdmin admin = ProxyAdmin(address(uint160(uint256(vm.load(COMPOSER, ADMIN_SLOT)))));
        address adminOwner = admin.owner();
        NestVaultComposer defaultImplementation = new NestVaultComposer(COMPLIANCE_PROXY);
        vm.prank(adminOwner);
        admin.upgradeAndCall(ITransparentUpgradeableProxy(COMPOSER), address(defaultImplementation), "");
        assertEq(asset.allowance(COMPOSER, COMPLIANCE_PROXY), type(uint256).max);
        (bool success,) = COMPOSER.call(abi.encodeCall(NestVaultComposerUpgrade.initializeComplianceProxy, ()));
        assertFalse(success);
    }

    function test_liveNscopeSyncVersionTwoPreservesLayoutAndApprovals() public {
        // This is the verified synchronous implementation archived under deployed/plume-nscope-composer/.
        // It consumed reinitializer(2) to approve vault shares and has no version() getter.
        assertEq(
            address(uint160(uint256(vm.load(SYNC_COMPOSER, IMPLEMENTATION_SLOT)))),
            0xaba875937AfC7e681b04bf9D5f2F398dEa3d414d
        );
        (bool hasVersion,) = SYNC_COMPOSER.staticcall(abi.encodeWithSignature("version()"));
        assertFalse(hasVersion);
        NestVaultComposer composer = NestVaultComposer(payable(SYNC_COMPOSER));
        bytes32 configBefore = _configurationHash(composer);
        bytes32 storageBefore = _storageHash(SYNC_COMPOSER);
        IERC20 asset = IERC20(composer.ASSET_ERC20());
        IERC20 share = IERC20(composer.SHARE_ERC20());
        address vault = address(composer.VAULT());
        uint256 vaultAllowance = asset.allowance(SYNC_COMPOSER, vault);
        uint256 oftAllowance = asset.allowance(SYNC_COMPOSER, composer.ASSET_OFT());
        assertEq(share.allowance(SYNC_COMPOSER, vault), type(uint256).max);
        for (uint256 i; i < 8; ++i) {
            assertEq(vm.load(SYNC_COMPOSER, bytes32(uint256(ASYNC_SLOT) + i)), bytes32(0));
        }

        _migrate(SYNC_COMPOSER);

        assertEq(_configurationHash(composer), configBefore, "sync/auth getters changed");
        assertEq(_storageHash(SYNC_COMPOSER), storageBefore, "sync/auth/async storage changed");
        assertEq(asset.allowance(SYNC_COMPOSER, vault), vaultAllowance);
        assertEq(asset.allowance(SYNC_COMPOSER, composer.ASSET_OFT()), oftAllowance);
        assertEq(share.allowance(SYNC_COMPOSER, vault), type(uint256).max);
        assertEq(composer.totalPendingSharesSum(), 0);
        assertEq(composer.totalFulfilledAssetsSum(), 0);
        assertEq(composer.maxRetryableValue(), 0);
    }

    function _configurationHash(NestVaultComposer composer) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                composer.owner(),
                composer.authority(),
                composer.pendingOwner(),
                composer.VAULT(),
                composer.ASSET_OFT(),
                composer.ASSET_ERC20(),
                composer.SHARE_OFT(),
                composer.SHARE_ERC20(),
                composer.ENDPOINT(),
                composer.VAULT_EID()
            )
        );
    }

    function _storageHash(address proxy) private view returns (bytes32) {
        bytes32[18] memory slots;
        for (uint256 i; i < 7; ++i) {
            slots[i] = vm.load(proxy, bytes32(uint256(SYNC_SLOT) + i));
        }
        for (uint256 i; i < 3; ++i) {
            slots[7 + i] = vm.load(proxy, bytes32(uint256(AUTH_SLOT) + i));
        }
        for (uint256 i; i < 8; ++i) {
            slots[10 + i] = vm.load(proxy, bytes32(uint256(ASYNC_SLOT) + i));
        }
        return keccak256(abi.encode(slots));
    }

    function _migrate(address proxy) private {
        NestVaultComposer composer = NestVaultComposer(payable(proxy));
        assertEq(uint256(vm.load(proxy, INITIALIZABLE_SLOT)), 2);
        assertGt(COMPLIANCE_PROXY.code.length, 0);
        IERC20 asset = IERC20(composer.ASSET_ERC20());
        assertEq(asset.allowance(proxy, COMPLIANCE_PROXY), 0);

        ProxyAdmin admin = ProxyAdmin(address(uint160(uint256(vm.load(proxy, ADMIN_SLOT)))));
        address adminOwner = admin.owner();
        NestVaultComposerUpgrade implementation = new NestVaultComposerUpgrade(COMPLIANCE_PROXY);
        vm.record();
        vm.prank(adminOwner);
        admin.upgradeAndCall(
            ITransparentUpgradeableProxy(proxy),
            address(implementation),
            abi.encodeCall(NestVaultComposerUpgrade.initializeComplianceProxy, ())
        );
        (, bytes32[] memory writes) = vm.accesses(proxy);
        for (uint256 i; i < writes.length; ++i) {
            assertTrue(writes[i] == INITIALIZABLE_SLOT || writes[i] == IMPLEMENTATION_SLOT);
        }
        assertEq(composer.version(), "1.3.0");
        assertEq(uint256(vm.load(proxy, INITIALIZABLE_SLOT)), 3);
        assertEq(address(composer.COMPLIANCE_PROXY()), COMPLIANCE_PROXY);
        assertEq(asset.allowance(proxy, COMPLIANCE_PROXY), type(uint256).max);
    }
}
