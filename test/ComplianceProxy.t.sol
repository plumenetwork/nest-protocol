// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {ISignatureTransfer} from "@uniswap/permit2/interfaces/ISignatureTransfer.sol";

import {AuthUpgradeable} from "contracts/auth/AuthUpgradeable.sol";
import {ComplianceProxy} from "contracts/compliance/ComplianceProxy.sol";
import {IComplianceHook} from "contracts/compliance/interfaces/IComplianceHook.sol";
import {NestVault} from "contracts/NestVault.sol";
import {MockComplianceHook} from "test/mock/MockComplianceHook.sol";
import {MockPermit2Minimal} from "test/mock/MockPermit2Minimal.sol";
import {MockVaultMinimal} from "test/mock/MockVaultMinimal.sol";

contract ComplianceProxyTest is Test {
    uint8 internal constant COMPOSER_ROLE = 1;
    uint8 internal constant USER_CHECKER_ROLE = 2;

    event Deposit(
        address indexed receiver,
        address indexed depositAsset,
        uint256 depositAmount,
        uint256 shareAmount,
        uint256 depositTimestamp,
        address vault
    );

    event RedeemRequest(
        address indexed owner,
        address indexed controller,
        uint256 shareAmount,
        uint256 requestId,
        uint256 requestTimestamp,
        address vault
    );

    event InstantRedeem(
        address indexed owner,
        address indexed receiver,
        uint256 shareAmount,
        uint256 postFeeAmount,
        uint256 feeAmount,
        uint256 redeemTimestamp,
        address vault
    );

    event ComplianceHookUpdated(address indexed oldHook, address indexed newHook);

    MockERC20 internal asset;
    MockVaultMinimal internal vault;
    MockComplianceHook internal hook;
    ComplianceProxy internal proxy;
    RolesAuthority internal authority;

    address internal owner = makeAddr("owner");
    address internal user = makeAddr("user");
    address internal recipient = makeAddr("recipient");
    address internal composer = makeAddr("composer");
    address internal stranger = makeAddr("stranger");

    bytes internal complianceData = abi.encode("attestation-bytes");

    function setUp() public {
        asset = new MockERC20("Mock USD", "mUSD", 6);
        vault = new MockVaultMinimal(ERC20(address(asset)));
        hook = new MockComplianceHook();

        ComplianceProxy _implementation = new ComplianceProxy();
        proxy = ComplianceProxy(
            address(
                new TransparentUpgradeableProxy(
                    address(_implementation),
                    owner,
                    abi.encodeCall(ComplianceProxy.initialize, (owner, IComplianceHook(address(hook))))
                )
            )
        );

        // User entrypoints are public by default but remain revocable per selector.
        // Attestation-only checks stay restricted to trusted integration callers.
        authority = new RolesAuthority(owner, Authority(address(0)));
        vm.startPrank(owner);
        authority.setRoleCapability(COMPOSER_ROLE, address(proxy), ComplianceProxy.mintOnBehalf.selector, true);
        authority.setUserRole(composer, COMPOSER_ROLE, true);
        authority.setRoleCapability(
            USER_CHECKER_ROLE, address(proxy), bytes4(keccak256("genericUserCheck(address,bytes)")), true
        );
        authority.setRoleCapability(
            USER_CHECKER_ROLE, address(proxy), bytes4(keccak256("genericUserCheck(address,bytes32,bytes)")), true
        );
        authority.setUserRole(composer, USER_CHECKER_ROLE, true);
        _setPublicUserCapabilities(true);
        proxy.setAuthority(authority);
        vm.stopPrank();

        asset.mint(user, 1_000e6);
        asset.mint(composer, 1_000e6);
        vm.prank(user);
        asset.approve(address(proxy), type(uint256).max);
        vm.prank(composer);
        asset.approve(address(proxy), type(uint256).max);
    }

    function _vault() internal view returns (NestVault) {
        return NestVault(address(vault));
    }

    function _setPublicUserCapabilities(bool _enabled) internal {
        authority.setPublicCapability(address(proxy), ComplianceProxy.deposit.selector, _enabled);
        authority.setPublicCapability(address(proxy), ComplianceProxy.depositWithPermit2.selector, _enabled);
        authority.setPublicCapability(address(proxy), ComplianceProxy.depositOnBehalf.selector, _enabled);
        authority.setPublicCapability(address(proxy), ComplianceProxy.depositOnBehalfWithPermit2.selector, _enabled);
        authority.setPublicCapability(address(proxy), ComplianceProxy.mint.selector, _enabled);
        authority.setPublicCapability(address(proxy), ComplianceProxy.mintOnBehalf.selector, _enabled);
        authority.setPublicCapability(address(proxy), ComplianceProxy.requestRedeem.selector, _enabled);
        authority.setPublicCapability(address(proxy), ComplianceProxy.requestRedeemWithPermit2.selector, _enabled);
        authority.setPublicCapability(address(proxy), ComplianceProxy.instantRedeem.selector, _enabled);
        authority.setPublicCapability(address(proxy), ComplianceProxy.instantRedeemWithPermit2.selector, _enabled);
    }

    // ========================================= INITIALIZE =========================================

    function test_initialize_reverts_on_zero_owner_or_hook() public {
        ComplianceProxy _implementation = new ComplianceProxy();

        vm.expectRevert(ComplianceProxy.ComplianceProxy__ZeroAddress.selector);
        new TransparentUpgradeableProxy(
            address(_implementation),
            owner,
            abi.encodeCall(ComplianceProxy.initialize, (address(0), IComplianceHook(address(hook))))
        );

        vm.expectRevert(ComplianceProxy.ComplianceProxy__ZeroAddress.selector);
        new TransparentUpgradeableProxy(
            address(_implementation),
            owner,
            abi.encodeCall(ComplianceProxy.initialize, (owner, IComplianceHook(address(0))))
        );
    }

    function test_initialize_cannot_run_twice() public {
        vm.expectRevert();
        proxy.initialize(owner, IComplianceHook(address(hook)));
    }

    function test_version() public view {
        assertEq(proxy.version(), "1.0.0");
    }

    // ========================================= DEPOSIT =========================================

    function test_deposit_mints_shares_and_consults_hook() public {
        // MockVaultMinimal converts at 2 assets per share
        vm.expectEmit(true, true, false, true, address(proxy));
        emit Deposit(recipient, address(asset), 100e6, 50e6, block.timestamp, address(vault));

        vm.prank(user);
        uint256 _shares = proxy.deposit(ERC20(address(asset)), 100e6, recipient, _vault(), complianceData);

        assertEq(_shares, 50e6);
        assertEq(vault.share().balanceOf(recipient), 50e6);
        assertEq(asset.balanceOf(address(vault)), 100e6);
        assertEq(asset.balanceOf(user), 900e6);
        assertEq(asset.allowance(address(proxy), address(vault)), 0);

        assertEq(hook.checkCalls(), 1);
        assertEq(hook.lastSender(), user);
        assertEq(hook.lastPayload(), abi.encodeWithSignature("deposit()"));
        assertEq(hook.lastComplianceData(), complianceData);
    }

    function test_all_deposit_and_mint_entrypoints_revert_when_hook_denies() public {
        hook.setAuthorized(false);
        MockPermit2Minimal _permit2 = new MockPermit2Minimal();

        vm.startPrank(user);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__UnauthorizedTransaction.selector);
        proxy.deposit(ERC20(address(asset)), 100e6, recipient, _vault(), complianceData);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__UnauthorizedTransaction.selector);
        proxy.mint(ERC20(address(asset)), 50e6, recipient, _vault(), complianceData);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__UnauthorizedTransaction.selector);
        proxy.depositWithPermit2(
            ERC20(address(asset)),
            100e6,
            recipient,
            _vault(),
            ISignatureTransfer(address(_permit2)),
            0,
            block.timestamp + 100,
            hex"",
            complianceData
        );
        vm.stopPrank();

        vm.startPrank(composer);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__UnauthorizedTransaction.selector);
        proxy.depositOnBehalf(_vault(), ERC20(address(asset)), 100e6, recipient, bytes32("x"), complianceData);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__UnauthorizedTransaction.selector);
        proxy.depositOnBehalfWithPermit2(
            _vault(),
            ERC20(address(asset)),
            100e6,
            recipient,
            bytes32("x"),
            ISignatureTransfer(address(_permit2)),
            0,
            block.timestamp + 100,
            hex"",
            complianceData
        );
        vm.expectRevert(ComplianceProxy.ComplianceProxy__UnauthorizedTransaction.selector);
        proxy.mintOnBehalf(ERC20(address(asset)), 50e6, recipient, _vault(), bytes32("x"), complianceData);
        vm.stopPrank();
    }

    function test_deposit_propagates_hook_revert() public {
        hook.setShouldRevert(true);
        vm.prank(user);
        vm.expectRevert("MockComplianceHook: revert");
        proxy.deposit(ERC20(address(asset)), 100e6, recipient, _vault(), complianceData);
    }

    function test_all_deposit_and_mint_entrypoints_revert_when_paused() public {
        vm.prank(owner);
        proxy.pause();
        MockPermit2Minimal _permit2 = new MockPermit2Minimal();

        vm.startPrank(user);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        proxy.deposit(ERC20(address(asset)), 100e6, recipient, _vault(), complianceData);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        proxy.mint(ERC20(address(asset)), 50e6, recipient, _vault(), complianceData);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        proxy.depositWithPermit2(
            ERC20(address(asset)),
            100e6,
            recipient,
            _vault(),
            ISignatureTransfer(address(_permit2)),
            0,
            block.timestamp + 100,
            hex"",
            complianceData
        );
        vm.stopPrank();

        vm.startPrank(composer);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        proxy.depositOnBehalf(_vault(), ERC20(address(asset)), 100e6, recipient, bytes32("x"), complianceData);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        proxy.depositOnBehalfWithPermit2(
            _vault(),
            ERC20(address(asset)),
            100e6,
            recipient,
            bytes32("x"),
            ISignatureTransfer(address(_permit2)),
            0,
            block.timestamp + 100,
            hex"",
            complianceData
        );
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        proxy.mintOnBehalf(ERC20(address(asset)), 50e6, recipient, _vault(), bytes32("x"), complianceData);
        vm.stopPrank();
    }

    // ========================================= ON-BEHALF DEPOSIT =========================================

    function test_depositOnBehalf_is_public_and_forwards_compliance_data() public {
        bytes32 _depositor = bytes32(uint256(uint160(makeAddr("original-depositor"))));
        asset.mint(stranger, 50e6);
        vm.prank(stranger);
        asset.approve(address(proxy), 50e6);

        vm.prank(stranger);
        uint256 _shares =
            proxy.depositOnBehalf(_vault(), ERC20(address(asset)), 50e6, recipient, _depositor, complianceData);

        assertEq(_shares, 25e6);
        assertEq(hook.lastSender(), stranger);
        assertEq(hook.lastPayload(), abi.encodeWithSignature("deposit(bytes32)", _depositor));
        assertEq(hook.lastComplianceData(), complianceData);
    }

    function test_depositOnBehalfWithPermit2_mints_shares_and_checks_both_identities() public {
        bytes32 _depositor = bytes32(uint256(uint160(makeAddr("original-depositor"))));
        MockPermit2Minimal _permit2 = new MockPermit2Minimal();
        asset.mint(stranger, 50e6);
        vm.prank(stranger);
        asset.approve(address(_permit2), 50e6);

        vm.prank(stranger);
        uint256 _shares = proxy.depositOnBehalfWithPermit2(
            _vault(),
            ERC20(address(asset)),
            50e6,
            recipient,
            _depositor,
            ISignatureTransfer(address(_permit2)),
            7,
            block.timestamp + 100,
            hex"1234",
            complianceData
        );

        assertEq(_shares, 25e6);
        assertEq(vault.share().balanceOf(recipient), 25e6);
        assertEq(asset.allowance(address(proxy), address(vault)), 0);
        assertEq(hook.lastSender(), stranger);
        assertEq(hook.lastPayload(), abi.encodeWithSignature("deposit(bytes32)", _depositor));
        assertEq(hook.lastComplianceData(), complianceData);
    }

    function test_depositOnBehalfWithPermit2_reverts_on_shortchanged_transfer() public {
        MockPermit2Minimal _permit2 = new MockPermit2Minimal();
        _permit2.setShortchangeBy(1);
        vm.prank(stranger);
        asset.approve(address(_permit2), 50e6);
        asset.mint(stranger, 50e6);

        vm.prank(stranger);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__InsufficientPermit2Transfer.selector);
        proxy.depositOnBehalfWithPermit2(
            _vault(),
            ERC20(address(asset)),
            50e6,
            recipient,
            bytes32("depositor"),
            ISignatureTransfer(address(_permit2)),
            7,
            block.timestamp + 100,
            hex"1234",
            complianceData
        );
    }

    // ========================================= MINT =========================================

    function test_mint_deposits_previewed_assets_and_consults_hook() public {
        // minting 100e6 shares costs 200e6 assets at the 2:1 rate
        vm.expectEmit(true, true, false, true, address(proxy));
        emit Deposit(recipient, address(asset), 200e6, 100e6, block.timestamp, address(vault));

        vm.prank(user);
        uint256 _actualShares = proxy.mint(ERC20(address(asset)), 100e6, recipient, _vault(), complianceData);

        assertEq(_actualShares, 100e6);
        assertEq(vault.share().balanceOf(recipient), 100e6);
        assertEq(asset.balanceOf(user), 800e6);
        assertEq(asset.allowance(address(proxy), address(vault)), 0);
        assertEq(vault.depositCalls(), 1);
        assertEq(vault.mintCalls(), 0);
        assertEq(hook.lastSender(), user);
        assertEq(hook.lastPayload(), abi.encodeWithSignature("deposit()"));
    }

    function test_mintOnBehalf_public_capability_can_be_revoked_without_blocking_role() public {
        bytes32 _depositor = bytes32("abc");

        vm.prank(owner);
        authority.setPublicCapability(address(proxy), ComplianceProxy.mintOnBehalf.selector, false);

        vm.prank(stranger);
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        proxy.mintOnBehalf(ERC20(address(asset)), 10e6, recipient, _vault(), _depositor, complianceData);

        vm.prank(composer);
        uint256 _actualShares =
            proxy.mintOnBehalf(ERC20(address(asset)), 10e6, recipient, _vault(), _depositor, complianceData);

        assertEq(_actualShares, 10e6);
        assertEq(vault.depositCalls(), 1);
        assertEq(vault.mintCalls(), 0);
        assertEq(hook.lastSender(), composer);
        assertEq(hook.lastPayload(), abi.encodeWithSignature("deposit(bytes32)", _depositor));
        assertEq(hook.lastComplianceData(), complianceData);
    }

    function test_mint_reverts_when_deposit_returns_fewer_shares_than_requested() public {
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(MockVaultMinimal.deposit.selector, 200e6, recipient),
            abi.encode(99e6)
        );

        vm.prank(user);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__InsufficientShares.selector);
        proxy.mint(ERC20(address(asset)), 100e6, recipient, _vault(), complianceData);
    }

    function test_mintOnBehalf_reverts_when_deposit_returns_fewer_shares_than_requested() public {
        bytes32 _depositor = bytes32("abc");
        vm.mockCall(
            address(vault), abi.encodeWithSelector(MockVaultMinimal.deposit.selector, 20e6, recipient), abi.encode(9e6)
        );

        vm.prank(composer);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__InsufficientShares.selector);
        proxy.mintOnBehalf(ERC20(address(asset)), 10e6, recipient, _vault(), _depositor, complianceData);
    }

    // ========================================= PERMIT2 =========================================

    function test_depositWithPermit2_mints_shares() public {
        MockPermit2Minimal _permit2 = new MockPermit2Minimal();
        vm.prank(user);
        asset.approve(address(_permit2), type(uint256).max);

        vm.prank(user);
        uint256 _shares = proxy.depositWithPermit2(
            ERC20(address(asset)),
            100e6,
            recipient,
            _vault(),
            ISignatureTransfer(address(_permit2)),
            0,
            block.timestamp + 100,
            hex"",
            complianceData
        );

        assertEq(_shares, 50e6);
        assertEq(vault.share().balanceOf(recipient), 50e6);
        assertEq(asset.allowance(address(proxy), address(vault)), 0);
        assertEq(hook.lastSender(), user);
        assertEq(hook.lastPayload(), abi.encodeWithSignature("deposit()"));
        assertEq(hook.lastComplianceData(), complianceData);
    }

    function test_depositWithPermit2_reverts_on_shortchanged_transfer() public {
        MockPermit2Minimal _permit2 = new MockPermit2Minimal();
        _permit2.setShortchangeBy(1);
        vm.prank(user);
        asset.approve(address(_permit2), type(uint256).max);

        vm.prank(user);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__InsufficientPermit2Transfer.selector);
        proxy.depositWithPermit2(
            ERC20(address(asset)),
            100e6,
            recipient,
            _vault(),
            ISignatureTransfer(address(_permit2)),
            0,
            block.timestamp + 100,
            hex"",
            complianceData
        );
    }

    // ========================================= REDEEM =========================================

    function _fundVaultAndShares() internal {
        // The user grants only a transfer allowance to the compliance proxy. The proxy must not
        // require a standing ERC-7540 operator approval from the user.
        MockERC20 _share = vault.share();
        _share.mint(user, 500e6);
        vm.prank(user);
        _share.approve(address(proxy), 100e6);
        asset.mint(address(vault), 500e6);
    }

    function _fundVaultAndSharesWithPermit2() internal returns (MockPermit2Minimal _permit2) {
        _permit2 = new MockPermit2Minimal();
        vault.setPermit2(ISignatureTransfer(address(_permit2)));
        MockERC20 _share = vault.share();
        _share.mint(user, 500e6);
        vm.prank(user);
        _share.approve(address(_permit2), type(uint256).max);
        asset.mint(address(vault), 500e6);
    }

    function test_requestRedeem_pulls_shares_and_uses_proxy_as_vault_owner() public {
        _fundVaultAndShares();

        // distinct controller so a controller/owner argument swap cannot pass unnoticed
        vm.expectEmit(true, true, false, true, address(proxy));
        emit RedeemRequest(user, recipient, 100e6, 0, block.timestamp, address(vault));
        vm.prank(user);
        uint256 _requestId = proxy.requestRedeem(100e6, recipient, _vault(), complianceData);

        assertEq(_requestId, 0);
        assertEq(vault.lastCaller(), address(proxy));
        assertEq(vault.lastOwnerOrController(), address(proxy));
        assertEq(vault.lastReceiver(), recipient);
        assertEq(vault.lastAmount(), 100e6);
        assertEq(vault.share().balanceOf(user), 400e6);
        assertEq(vault.share().balanceOf(address(proxy)), 0);
        assertEq(vault.share().allowance(user, address(proxy)), 0);
        assertEq(vault.share().allowance(user, address(vault)), 0);
        assertEq(vault.share().allowance(address(proxy), address(vault)), 0);
        assertEq(hook.lastSender(), user);
        assertEq(hook.lastPayload(), abi.encodeWithSignature("requestRedeem()"));
        assertEq(hook.lastComplianceData(), complianceData);
    }

    function test_instantRedeem_pulls_shares_and_uses_proxy_as_vault_owner() public {
        _fundVaultAndShares();

        vm.expectEmit(true, true, false, true, address(proxy));
        emit InstantRedeem(user, recipient, 100e6, 200e6 - 1, 1, block.timestamp, address(vault));
        vm.prank(user);
        (uint256 _postFee, uint256 _fee) = proxy.instantRedeem(100e6, recipient, _vault(), complianceData);

        assertEq(_postFee, 200e6 - 1);
        assertEq(_fee, 1);
        assertEq(asset.balanceOf(recipient), 200e6 - 1);
        assertEq(asset.balanceOf(address(proxy)), 0);
        assertEq(vault.lastCaller(), address(proxy));
        assertEq(vault.lastOwnerOrController(), address(proxy));
        assertEq(vault.share().balanceOf(address(proxy)), 0);
        assertEq(vault.share().allowance(user, address(proxy)), 0);
        assertEq(vault.share().allowance(user, address(vault)), 0);
        assertEq(vault.share().allowance(address(proxy), address(vault)), 0);
        assertEq(hook.lastSender(), user);
        assertEq(hook.lastPayload(), abi.encodeWithSignature("instantRedeem()"));
    }

    function test_requestRedeemWithPermit2_pulls_shares_and_uses_proxy_as_vault_owner() public {
        _fundVaultAndSharesWithPermit2();

        vm.expectEmit(true, true, false, true, address(proxy));
        emit RedeemRequest(user, recipient, 100e6, 0, block.timestamp, address(vault));
        vm.prank(user);
        uint256 _requestId = proxy.requestRedeemWithPermit2(
            100e6, recipient, _vault(), 11, block.timestamp + 100, hex"1234", complianceData
        );

        assertEq(_requestId, 0);
        assertEq(vault.lastCaller(), address(proxy));
        assertEq(vault.lastOwnerOrController(), address(proxy));
        assertEq(vault.lastReceiver(), recipient);
        assertEq(vault.share().balanceOf(user), 400e6);
        assertEq(vault.share().balanceOf(address(proxy)), 0);
        assertEq(vault.share().allowance(address(proxy), address(vault)), 0);
        assertEq(hook.lastSender(), user);
        assertEq(hook.lastPayload(), abi.encodeWithSignature("requestRedeem()"));
    }

    function test_requestRedeemWithPermit2_reverts_on_shortchanged_share_transfer() public {
        MockPermit2Minimal _permit2 = _fundVaultAndSharesWithPermit2();
        _permit2.setShortchangeBy(1);

        vm.prank(user);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__InsufficientPermit2Transfer.selector);
        proxy.requestRedeemWithPermit2(100e6, recipient, _vault(), 11, block.timestamp + 100, hex"1234", complianceData);
    }

    function test_instantRedeemWithPermit2_pulls_shares_and_uses_proxy_as_vault_owner() public {
        _fundVaultAndSharesWithPermit2();

        vm.expectEmit(true, true, false, true, address(proxy));
        emit InstantRedeem(user, recipient, 100e6, 200e6 - 1, 1, block.timestamp, address(vault));
        vm.prank(user);
        (uint256 _postFee, uint256 _fee) = proxy.instantRedeemWithPermit2(
            100e6, recipient, _vault(), 12, block.timestamp + 100, hex"1234", complianceData
        );

        assertEq(_postFee, 200e6 - 1);
        assertEq(_fee, 1);
        assertEq(asset.balanceOf(recipient), 200e6 - 1);
        assertEq(vault.lastCaller(), address(proxy));
        assertEq(vault.lastOwnerOrController(), address(proxy));
        assertEq(vault.share().balanceOf(address(proxy)), 0);
        assertEq(vault.share().allowance(address(proxy), address(vault)), 0);
        assertEq(hook.lastSender(), user);
        assertEq(hook.lastPayload(), abi.encodeWithSignature("instantRedeem()"));
    }

    function test_redeem_flows_revert_when_hook_denies() public {
        _fundVaultAndShares();
        hook.setAuthorized(false);

        vm.startPrank(user);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__UnauthorizedTransaction.selector);
        proxy.requestRedeem(100e6, user, _vault(), complianceData);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__UnauthorizedTransaction.selector);
        proxy.instantRedeem(100e6, recipient, _vault(), complianceData);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__UnauthorizedTransaction.selector);
        proxy.requestRedeemWithPermit2(100e6, user, _vault(), 1, block.timestamp + 100, hex"", complianceData);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__UnauthorizedTransaction.selector);
        proxy.instantRedeemWithPermit2(100e6, recipient, _vault(), 2, block.timestamp + 100, hex"", complianceData);
        vm.stopPrank();
    }

    function test_redeem_flows_revert_when_paused() public {
        _fundVaultAndShares();
        vm.prank(owner);
        proxy.pause();

        vm.startPrank(user);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        proxy.requestRedeem(100e6, user, _vault(), complianceData);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        proxy.instantRedeem(100e6, recipient, _vault(), complianceData);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        proxy.requestRedeemWithPermit2(100e6, user, _vault(), 1, block.timestamp + 100, hex"", complianceData);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        proxy.instantRedeemWithPermit2(100e6, recipient, _vault(), 2, block.timestamp + 100, hex"", complianceData);
        vm.stopPrank();
    }

    // ========================================= GENERIC USER CHECK =========================================

    function test_genericUserCheck_address_forwards_user_as_sender() public {
        vm.prank(composer);
        bool _ok = proxy.genericUserCheck(user, complianceData);

        assertTrue(_ok);
        assertEq(hook.lastSender(), user);
        assertEq(hook.lastPayload(), abi.encodeWithSignature("accessCheck(address)", user));

        hook.setAuthorized(false);
        vm.prank(composer);
        assertFalse(proxy.genericUserCheck(user, complianceData));
    }

    function test_genericUserCheck_bytes32_forwards_explicit_caller_as_sender() public {
        bytes32 _user = bytes32("solana-user");
        vm.prank(composer);
        bool _ok = proxy.genericUserCheck(composer, _user, complianceData);

        assertTrue(_ok);
        assertEq(hook.lastSender(), composer);
        assertEq(hook.lastPayload(), abi.encodeWithSignature("accessCheck(bytes32)", _user));
    }

    function test_genericUserCheck_reverts_for_unauthorized_caller_without_spending_proof() public {
        vm.prank(stranger);
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        proxy.genericUserCheck(user, complianceData);

        assertEq(hook.checkCalls(), 0);
    }

    function test_public_user_capability_can_be_revoked() public {
        vm.prank(owner);
        authority.setPublicCapability(address(proxy), ComplianceProxy.deposit.selector, false);

        vm.prank(user);
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        proxy.deposit(ERC20(address(asset)), 100e6, recipient, _vault(), complianceData);

        assertEq(hook.checkCalls(), 0);
    }

    // ========================================= ADMIN =========================================

    function test_setComplianceHook_swaps_hook() public {
        MockComplianceHook _newHook = new MockComplianceHook();

        vm.expectEmit(true, true, false, true, address(proxy));
        emit ComplianceHookUpdated(address(hook), address(_newHook));

        vm.prank(owner);
        proxy.setComplianceHook(IComplianceHook(address(_newHook)));
        assertEq(address(proxy.complianceHook()), address(_newHook));

        vm.prank(user);
        proxy.deposit(ERC20(address(asset)), 100e6, recipient, _vault(), complianceData);
        assertEq(_newHook.checkCalls(), 1);
        assertEq(hook.checkCalls(), 0);
    }

    function test_setComplianceHook_reverts_on_zero_address() public {
        vm.prank(owner);
        vm.expectRevert(ComplianceProxy.ComplianceProxy__ZeroAddress.selector);
        proxy.setComplianceHook(IComplianceHook(address(0)));
    }

    function test_setComplianceHook_reverts_for_stranger() public {
        vm.prank(stranger);
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        proxy.setComplianceHook(IComplianceHook(address(1)));
    }

    function test_pause_unpause_gated_and_effective() public {
        vm.prank(stranger);
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        proxy.pause();

        vm.prank(owner);
        proxy.pause();

        vm.prank(stranger);
        vm.expectRevert(AuthUpgradeable.AUTH_UNAUTHORIZED.selector);
        proxy.unpause();

        vm.prank(owner);
        proxy.unpause();

        vm.prank(user);
        proxy.deposit(ERC20(address(asset)), 100e6, recipient, _vault(), complianceData);
        assertEq(vault.share().balanceOf(recipient), 50e6);
    }
}
