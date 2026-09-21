// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {NestVaultComposerNestShareOFTTestBase} from "test/NestVaultComposer.t.sol";
import {NestVaultComposer} from "contracts/integrations/ovault/NestVaultComposer.sol";
import {NestVaultComposer as NestVaultComposerUpgrade} from "contracts/upgrades/compliance-proxy/NestVaultComposer.sol";
import {ComplianceProxy} from "contracts/compliance/ComplianceProxy.sol";
import {IComplianceHook} from "contracts/compliance/interfaces/IComplianceHook.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

contract NestVaultComposerUpgradeTest is NestVaultComposerNestShareOFTTestBase {
    bytes32 private constant ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
    bytes32 private constant IMPLEMENTATION_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    ComplianceProxy private nextComplianceProxy;
    NestVaultComposerUpgrade private implementation;
    ProxyAdmin private admin;

    function setUp() public override {
        super.setUp();
        nextComplianceProxy = ComplianceProxy(
            _deployContractAndProxy(
                type(ComplianceProxy).creationCode,
                "",
                abi.encodeCall(ComplianceProxy.initialize, (address(this), IComplianceHook(address(complianceHook))))
            )
        );
        nextComplianceProxy.setAuthority(Authority(address(mockAuthority)));
        implementation = new NestVaultComposerUpgrade(address(nextComplianceProxy));
        admin = ProxyAdmin(address(uint160(uint256(vm.load(address(composer), ADMIN_SLOT)))));
    }

    function _upgrade(address target, bytes memory data) private {
        vm.prank(proxyAdmin);
        admin.upgradeAndCall(ITransparentUpgradeableProxy(address(composer)), target, data);
    }

    function _migrate() private {
        _upgrade(address(implementation), abi.encodeCall(NestVaultComposerUpgrade.initializeComplianceProxy, ()));
    }

    function test_upgradeFromVersionOne_restoresApprovalAndPreservesState() public {
        _assertMigration(1);
    }

    function test_upgradeFromVersionTwo_restoresApprovalAndPreservesState() public {
        // nTEST consumed v2 in transaction 0xe7384062308feda5f87b7888aba684717fa45e793d57667f95f10c3eff464863.
        // Its recovered source is under contracts/upgrades/deployed/plume-ntest-composer/.
        vm.store(address(composer), INITIALIZABLE_STORAGE, bytes32(uint256(2)));
        _assertMigration(2);
    }

    function _assertMigration(uint64 previousVersion) private {
        composer.setMaxRetryableValue(123);
        composer.transferOwnership(userB);
        asset.mint(address(composer), 456);
        assertEq(uint256(vm.load(address(composer), INITIALIZABLE_STORAGE)), previousVersion);
        assertEq(asset.allowance(address(composer), address(nextComplianceProxy)), 0);

        vm.record();
        _migrate();
        (, bytes32[] memory writes) = vm.accesses(address(composer));
        // No composer/auth/bookkeeping storage may be rewritten by this migration.
        for (uint256 i; i < writes.length; ++i) {
            assertTrue(writes[i] == INITIALIZABLE_STORAGE || writes[i] == IMPLEMENTATION_SLOT);
        }

        assertEq(uint256(vm.load(address(composer), INITIALIZABLE_STORAGE)), 3);
        assertEq(address(composer.COMPLIANCE_PROXY()), address(nextComplianceProxy));
        assertEq(asset.allowance(address(composer), address(nextComplianceProxy)), type(uint256).max);
        assertEq(asset.allowance(address(composer), address(complianceProxy)), type(uint256).max);
        assertEq(asset.allowance(address(composer), address(vault)), type(uint256).max);
        assertEq(asset.allowance(address(composer), address(assetOFT)), type(uint256).max);
        assertEq(asset.balanceOf(address(composer)), 456);
        assertEq(composer.owner(), address(this));
        assertEq(address(composer.authority()), address(mockAuthority));
        assertEq(composer.pendingOwner(), userB);
        assertEq(composer.maxRetryableValue(), 123);
        assertEq(address(composer.VAULT()), address(vault));
        assertEq(composer.ASSET_OFT(), address(assetOFT));
        assertEq(composer.SHARE_OFT(), address(shareOFT));
    }

    function test_migrationCannotBeReplayed() public {
        _migrate();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        NestVaultComposerUpgrade(payable(address(composer))).initializeComplianceProxy();
    }

    function test_implementationInitializersAreDisabled() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initializeComplianceProxy();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(address(this), address(vault), address(assetOFT), address(shareOFT), 0);
    }

    function test_approvalFailureRollsBackImplementationAndVersion() public {
        bytes32 oldImplementation = vm.load(address(composer), IMPLEMENTATION_SLOT);
        vm.mockCallRevert(address(asset), abi.encodeWithSelector(IERC20.approve.selector), bytes("approval failed"));
        vm.expectRevert(bytes("approval failed"));
        _migrate();

        assertEq(vm.load(address(composer), IMPLEMENTATION_SLOT), oldImplementation);
        assertEq(uint256(vm.load(address(composer), INITIALIZABLE_STORAGE)), 1);
        assertEq(asset.allowance(address(composer), address(nextComplianceProxy)), 0);
    }

    function test_defaultImplementationRetainsApprovalAfterMigration() public {
        _migrate();
        _upgrade(address(new NestVaultComposer(address(nextComplianceProxy))), "");

        (bool success,) = address(composer).call(abi.encodeCall(NestVaultComposerUpgrade.initializeComplianceProxy, ()));
        assertFalse(success);
        assertEq(uint256(vm.load(address(composer), INITIALIZABLE_STORAGE)), 3);
        assertEq(asset.allowance(address(composer), address(nextComplianceProxy)), type(uint256).max);

        uint256 amount = 1e6;
        asset.mint(userA, amount);
        vm.prank(userA);
        asset.approve(address(composer), amount);
        SendParam memory sendParam = SendParam({
            dstEid: composer.VAULT_EID(),
            to: addressToBytes32(userB),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: _complianceData()
        });
        uint256 expectedShares = vault.previewDeposit(amount);
        vm.prank(userA);
        composer.depositAndSend(addressToBytes32(userA), amount, sendParam, userA);
        assertEq(shareOFT.balanceOf(userB), expectedShares);
        assertEq(complianceHook.lastSender(), address(composer));
    }
}
