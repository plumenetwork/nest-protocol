// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/ERC20Mock.sol";

import {Bundler3} from "contracts/vendor/bundler3/Bundler3.sol";
import {Call} from "contracts/vendor/bundler3/interfaces/IBundler3.sol";
import {ErrorsLib} from "contracts/vendor/bundler3/libraries/ErrorsLib.sol";

import {NestAdapter} from "contracts/integrations/morpho/NestAdapter.sol";
import {MorphoAdapter} from "contracts/integrations/morpho/MorphoAdapter.sol";
import {ITellerPredicateProxy} from "contracts/compliance/interfaces/ITellerPredicateProxy.sol";
import {IComplianceProxy} from "contracts/compliance/interfaces/IComplianceProxy.sol";
import {PredicateMessage} from "@predicate/src/interfaces/IPredicateClient.sol";
import {MockComplianceProxyMinimal} from "test/mock/MockComplianceProxyMinimal.sol";
import {MockLegacyPredicateProxyMinimal} from "test/mock/MockLegacyPredicateProxyMinimal.sol";
import {MockLegacyTellerMinimal} from "test/mock/MockLegacyTellerMinimal.sol";
import {MockMorphoCore} from "test/mock/morpho/MockMorphoCore.sol";
import {MockNestVaultCore} from "test/mock/morpho/MockNestVaultCore.sol";
import {MockVaultAwareShare} from "test/mock/morpho/MockVaultAwareShare.sol";
import {MockAuthority} from "test/mock/MockAuthority.sol";
import {MockBoringVault} from "test/mock/MockBoringVault.sol";
import {MarketParams} from "@morpho/interfaces/IMorpho.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {CrossChainTellerBase} from "@boring-vault/src/base/Roles/CrossChain/CrossChainTellerBase.sol";

contract NestAdapterTest is Test {
    uint256 internal constant MAX_SHARE_PRICE_E27 = type(uint256).max;
    uint256 internal constant MIN_SHARE_PRICE_E27 = 0;

    Bundler3 internal bundler3;
    NestAdapter internal adapter;
    ERC20Mock internal asset;
    MockVaultAwareShare internal share;
    MockNestVaultCore internal mockVault;
    INestVaultCore internal vault;
    MockComplianceProxyMinimal internal complianceProxy;
    MockLegacyPredicateProxyMinimal internal legacyPredicateProxy;
    MockLegacyTellerMinimal internal legacyTellerMock;
    MockBoringVault internal legacyVault;
    MockMorphoCore internal morpho;
    MockAuthority internal authority;
    CrossChainTellerBase internal legacyTeller;

    address internal user = makeAddr("user");
    address internal other = makeAddr("other");
    address internal solver = makeAddr("solver");
    address internal wrappedNative = address(0x1234);

    function setUp() public {
        bundler3 = new Bundler3();
        morpho = new MockMorphoCore();
        adapter = new NestAdapter(address(bundler3), address(morpho), wrappedNative);

        asset = new ERC20Mock("pUSD", "pUSD");
        share = new MockVaultAwareShare("nTOKEN", "nTOKEN");
        mockVault = new MockNestVaultCore(address(asset), address(share));
        vault = INestVaultCore(address(mockVault));

        authority = new MockAuthority(true);
        mockVault.setAuthority(Authority(address(authority)));
        complianceProxy = new MockComplianceProxyMinimal();
        complianceProxy.setAuthority(Authority(address(authority)));
        legacyPredicateProxy = new MockLegacyPredicateProxyMinimal();
        legacyPredicateProxy.setAuthority(Authority(address(authority)));
        legacyVault = new MockBoringVault("Legacy Vault", "LEGACY", 18);
        legacyTellerMock = new MockLegacyTellerMinimal(address(legacyVault));
        legacyTellerMock.setAuthority(Authority(address(authority)));
        legacyTeller = CrossChainTellerBase(payable(address(legacyTellerMock)));

        // Seed liquidity for redemptions.
        asset.mint(address(mockVault), 1_000_000 ether);

        // Seed user shares for redeem tests and seed vault shares for deposit minting.
        share.mint(user, 1_000_000 ether);
        share.mint(address(mockVault), 1_000_000 ether);
        vm.prank(user);
        share.approve(address(mockVault), type(uint256).max);
    }

    function test_directCall_revertsUnauthorizedSender() public {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        adapter.nestDeposit(vault, 1 ether, MAX_SHARE_PRICE_E27, user);
    }

    function test_nestDeposit_singleCallBundle() public {
        uint256 amount = 10 ether;
        asset.mint(address(adapter), amount);
        uint256 userSharesBefore = share.balanceOf(user);

        Call[] memory bundle =
            _singleCall(abi.encodeCall(adapter.nestDeposit, (vault, amount, MAX_SHARE_PRICE_E27, user)));

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(share.balanceOf(user), userSharesBefore + amount, "shares minted to user");
        assertEq(asset.balanceOf(address(adapter)), 0, "no residual assets on adapter");
        assertEq(share.balanceOf(address(adapter)), 0, "no residual shares on adapter");
        assertEq(asset.balanceOf(address(bundler3)), 0, "no residual assets on bundler");
        assertEq(share.balanceOf(address(bundler3)), 0, "no residual shares on bundler");
    }

    function test_nestDeposit_allowsArbitraryReceiver() public {
        uint256 amount = 3 ether;
        asset.mint(address(adapter), amount);
        uint256 otherSharesBefore = share.balanceOf(other);

        Call[] memory bundle =
            _singleCall(abi.encodeCall(adapter.nestDeposit, (vault, amount, MAX_SHARE_PRICE_E27, other)));

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(share.balanceOf(other), otherSharesBefore + amount, "shares minted to custom receiver");
    }

    function test_nestMint_singleCallBundle() public {
        uint256 sharesToMint = 8 ether;
        asset.mint(address(adapter), sharesToMint);
        uint256 userSharesBefore = share.balanceOf(user);

        Call[] memory bundle =
            _singleCall(abi.encodeCall(adapter.nestMint, (vault, sharesToMint, MAX_SHARE_PRICE_E27, user)));

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(share.balanceOf(user), userSharesBefore + sharesToMint, "shares minted to user");
        assertEq(mockVault.mintCalls(), 1, "vault mint should be called once");
        assertEq(asset.balanceOf(address(adapter)), 0, "no residual assets on adapter");
        assertEq(share.balanceOf(address(adapter)), 0, "no residual shares on adapter");
        assertEq(asset.balanceOf(address(bundler3)), 0, "no residual assets on bundler");
        assertEq(share.balanceOf(address(bundler3)), 0, "no residual shares on bundler");
    }

    function test_nestMint_maxSharesRevertsWhenPreviewDepositResolvesToZero() public {
        uint256 adapterAssets = 1 ether;
        asset.mint(address(adapter), adapterAssets);
        vm.mockCall(
            address(mockVault), abi.encodeWithSignature("previewDeposit(uint256)", adapterAssets), abi.encode(0)
        );

        Call[] memory bundle =
            _singleCall(abi.encodeCall(adapter.nestMint, (vault, type(uint256).max, MAX_SHARE_PRICE_E27, user)));

        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_nestComplianceDeposit_singleCallBundle() public {
        uint256 amount = 6 ether;
        bytes32 onBehalf = bytes32(uint256(uint160(other)));
        asset.mint(address(adapter), amount);
        uint256 userSharesBefore = share.balanceOf(user);

        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestComplianceDeposit,
                (
                    IComplianceProxy(address(complianceProxy)),
                    vault,
                    amount,
                    MAX_SHARE_PRICE_E27,
                    user,
                    onBehalf,
                    bytes("")
                )
            )
        );

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(share.balanceOf(user), userSharesBefore + amount, "shares minted to user");
        assertEq(complianceProxy.genericUserCheckCalls(), 1, "compliance check should be called once");
        assertEq(complianceProxy.lastCheckedCaller(), user, "Bundler3 initiator should be checked as caller");
        assertEq(complianceProxy.lastCheckedOnBehalf(), onBehalf, "onBehalf user should be checked");
        assertEq(mockVault.depositCalls(), 1, "vault deposit should be called once");
        assertEq(asset.balanceOf(address(adapter)), 0, "no residual assets on adapter");
        assertEq(share.balanceOf(address(adapter)), 0, "no residual shares on adapter");
        assertEq(asset.balanceOf(address(bundler3)), 0, "no residual assets on bundler");
        assertEq(share.balanceOf(address(bundler3)), 0, "no residual shares on bundler");
    }

    function test_nestComplianceDeposit_onBehalfUsesOnBehalfSelector() public {
        uint256 amount = 6 ether;
        bytes32 onBehalf = bytes32(uint256(uint160(other)));
        asset.mint(address(adapter), amount);
        vm.mockCall(
            address(authority),
            abi.encodeCall(Authority.canCall, (user, address(complianceProxy), IComplianceProxy.deposit.selector)),
            abi.encode(false)
        );
        vm.mockCall(
            address(authority),
            abi.encodeCall(
                Authority.canCall, (user, address(complianceProxy), IComplianceProxy.depositOnBehalf.selector)
            ),
            abi.encode(true)
        );

        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestComplianceDeposit,
                (
                    IComplianceProxy(address(complianceProxy)),
                    vault,
                    amount,
                    MAX_SHARE_PRICE_E27,
                    user,
                    onBehalf,
                    bytes("")
                )
            )
        );

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(mockVault.depositCalls(), 1, "vault deposit should be called once");
    }

    function test_nestComplianceMint_bindsInitiatorAndOnBehalf() public {
        uint256 sharesToMint = 6 ether;
        bytes32 onBehalf = bytes32(uint256(uint160(other)));
        asset.mint(address(adapter), sharesToMint);

        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestComplianceMint,
                (
                    IComplianceProxy(address(complianceProxy)),
                    vault,
                    sharesToMint,
                    MAX_SHARE_PRICE_E27,
                    user,
                    onBehalf,
                    bytes("")
                )
            )
        );

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(complianceProxy.genericUserCheckCalls(), 1, "compliance check should be called once");
        assertEq(complianceProxy.lastCheckedCaller(), user, "Bundler3 initiator should be checked as caller");
        assertEq(complianceProxy.lastCheckedOnBehalf(), onBehalf, "onBehalf user should be checked");
        assertEq(mockVault.mintCalls(), 1, "vault mint should be called once");
    }

    function test_nestComplianceMint_onBehalfUsesOnBehalfSelector() public {
        uint256 sharesToMint = 6 ether;
        bytes32 onBehalf = bytes32(uint256(uint160(other)));
        asset.mint(address(adapter), sharesToMint);
        vm.mockCall(
            address(authority),
            abi.encodeCall(Authority.canCall, (user, address(complianceProxy), IComplianceProxy.mint.selector)),
            abi.encode(false)
        );
        vm.mockCall(
            address(authority),
            abi.encodeCall(Authority.canCall, (user, address(complianceProxy), IComplianceProxy.mintOnBehalf.selector)),
            abi.encode(true)
        );

        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestComplianceMint,
                (
                    IComplianceProxy(address(complianceProxy)),
                    vault,
                    sharesToMint,
                    MAX_SHARE_PRICE_E27,
                    user,
                    onBehalf,
                    bytes("")
                )
            )
        );

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(mockVault.mintCalls(), 1, "vault mint should be called once");
    }

    function test_nestComplianceMint_zeroSharesRevertsWithZeroShares() public {
        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestComplianceMint,
                (IComplianceProxy(address(complianceProxy)), vault, 0, MAX_SHARE_PRICE_E27, user, bytes32(0), bytes(""))
            )
        );

        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_nestComplianceMint_maxSharesRevertsWhenPreviewDepositResolvesToZero() public {
        uint256 adapterAssets = 1 ether;
        asset.mint(address(adapter), adapterAssets);
        vm.mockCall(
            address(mockVault), abi.encodeWithSignature("previewDeposit(uint256)", adapterAssets), abi.encode(0)
        );

        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestComplianceMint,
                (
                    IComplianceProxy(address(complianceProxy)),
                    vault,
                    type(uint256).max,
                    MAX_SHARE_PRICE_E27,
                    user,
                    bytes32(0),
                    bytes("")
                )
            )
        );

        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_nestComplianceDeposit_sameOnBehalfUsesRegularCheck() public {
        uint256 amount = 6 ether;
        bytes32 onBehalf = bytes32(uint256(uint160(user)));
        asset.mint(address(adapter), amount);
        vm.mockCall(
            address(authority),
            abi.encodeCall(Authority.canCall, (user, address(complianceProxy), IComplianceProxy.deposit.selector)),
            abi.encode(true)
        );
        vm.mockCall(
            address(authority),
            abi.encodeCall(
                Authority.canCall, (user, address(complianceProxy), IComplianceProxy.depositOnBehalf.selector)
            ),
            abi.encode(false)
        );

        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestComplianceDeposit,
                (
                    IComplianceProxy(address(complianceProxy)),
                    vault,
                    amount,
                    MAX_SHARE_PRICE_E27,
                    user,
                    onBehalf,
                    bytes("")
                )
            )
        );

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(complianceProxy.genericUserCheckCalls(), 1, "compliance check should be called once");
        assertEq(complianceProxy.lastCheckedUser(), user, "initiator should use the regular check");
        assertEq(complianceProxy.lastCheckedCaller(), address(0), "pair check should not be used");
        assertEq(mockVault.depositCalls(), 1, "vault deposit should be called once");
    }

    function test_nestComplianceMint_zeroOnBehalfUsesRegularCheck() public {
        uint256 sharesToMint = 6 ether;
        asset.mint(address(adapter), sharesToMint);
        vm.mockCall(
            address(authority),
            abi.encodeCall(Authority.canCall, (user, address(complianceProxy), IComplianceProxy.mint.selector)),
            abi.encode(true)
        );
        vm.mockCall(
            address(authority),
            abi.encodeCall(Authority.canCall, (user, address(complianceProxy), IComplianceProxy.mintOnBehalf.selector)),
            abi.encode(false)
        );

        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestComplianceMint,
                (
                    IComplianceProxy(address(complianceProxy)),
                    vault,
                    sharesToMint,
                    MAX_SHARE_PRICE_E27,
                    user,
                    bytes32(0),
                    bytes("")
                )
            )
        );

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(complianceProxy.genericUserCheckCalls(), 1, "compliance check should be called once");
        assertEq(complianceProxy.lastCheckedUser(), user, "zero onBehalf should use the regular check");
        assertEq(complianceProxy.lastCheckedCaller(), address(0), "pair check should not be used");
        assertEq(mockVault.mintCalls(), 1, "vault mint should be called once");
    }

    function test_erc4626DepositSelector_revertsAsMissingFunction() public {
        asset.mint(address(adapter), 1 ether);

        bytes memory callData = abi.encodeWithSignature(
            "erc4626Deposit(address,uint256,uint256,address)", address(vault), 1 ether, MAX_SHARE_PRICE_E27, user
        );
        Call[] memory bundle = _singleCall(callData);

        vm.expectRevert();
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_erc4626MintSelector_revertsAsMissingFunction() public {
        bytes memory callData = abi.encodeWithSignature(
            "erc4626Mint(address,uint256,uint256,address)", address(vault), 1 ether, MAX_SHARE_PRICE_E27, user
        );
        Call[] memory bundle = _singleCall(callData);

        vm.expectRevert();
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_tellerPredicateDeposit_singleCallBundle() public {
        uint256 amount = 6 ether;
        asset.mint(address(adapter), amount);
        uint256 userSharesBefore = legacyVault.balanceOf(user);

        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.tellerPredicateDeposit,
                (
                    ITellerPredicateProxy(address(legacyPredicateProxy)),
                    ERC20(address(asset)),
                    amount,
                    amount,
                    user,
                    legacyTeller,
                    _emptyPredicateMessage()
                )
            )
        );

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(legacyPredicateProxy.depositCalls(), 0, "legacy predicate proxy deposit should not be called");
        assertEq(legacyTellerMock.depositCalls(), 1, "teller deposit should be called once");
        assertEq(legacyVault.balanceOf(user), userSharesBefore + amount, "shares forwarded to receiver");
        assertEq(legacyVault.balanceOf(address(adapter)), 0, "no residual shares on adapter");
        assertEq(asset.balanceOf(address(adapter)), 0, "no residual assets on adapter");
        assertEq(asset.balanceOf(address(legacyVault)), amount, "assets should be transferred to vault");
    }

    function test_nestInstantRedeem_singleCallBundle() public {
        uint256 sharesToRedeem = 7 ether;
        uint256 userAssetsBefore = asset.balanceOf(user);

        Call[] memory bundle = _singleCall(
            abi.encodeCall(adapter.nestInstantRedeem, (vault, sharesToRedeem, MIN_SHARE_PRICE_E27, user, user))
        );

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(asset.balanceOf(user), userAssetsBefore + sharesToRedeem, "assets received");
        assertEq(mockVault.instantRedeemCalls(), 1, "instant redeem called once");
        assertEq(asset.balanceOf(address(adapter)), 0, "no residual assets on adapter");
        assertEq(share.balanceOf(address(adapter)), 0, "no residual shares on adapter");
        assertEq(asset.balanceOf(address(bundler3)), 0, "no residual assets on bundler");
        assertEq(share.balanceOf(address(bundler3)), 0, "no residual shares on bundler");
    }

    function test_nestComplianceInstantRedeem_checksInitiatorAndOwner() public {
        uint256 sharesToRedeem = 7 ether;
        uint256 userAssetsBefore = asset.balanceOf(user);
        vm.prank(user);
        mockVault.setOperator(solver, true);

        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestComplianceInstantRedeem,
                (
                    IComplianceProxy(address(complianceProxy)),
                    vault,
                    sharesToRedeem,
                    MIN_SHARE_PRICE_E27,
                    user,
                    user,
                    bytes32(uint256(uint160(user))),
                    bytes("")
                )
            )
        );

        vm.prank(solver);
        bundler3.multicall(bundle);

        assertEq(complianceProxy.genericUserCheckCalls(), 1, "compliance check should be called once");
        assertEq(complianceProxy.lastCheckedCaller(), solver, "Bundler3 initiator should be checked as caller");
        assertEq(
            complianceProxy.lastCheckedOnBehalf(),
            bytes32(uint256(uint160(user))),
            "share owner should be checked as onBehalf"
        );
        assertEq(mockVault.instantRedeemCalls(), 1, "instant redeem called once");
        assertEq(asset.balanceOf(user), userAssetsBefore + sharesToRedeem, "assets received");
    }

    function test_nestComplianceInstantRedeem_revertsWhenComplianceFails() public {
        complianceProxy.setComplianceAuthorized(false);
        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestComplianceInstantRedeem,
                (
                    IComplianceProxy(address(complianceProxy)),
                    vault,
                    1 ether,
                    MIN_SHARE_PRICE_E27,
                    user,
                    user,
                    bytes32(uint256(uint160(user))),
                    bytes("")
                )
            )
        );

        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(mockVault.instantRedeemCalls(), 0, "vault should not be called");
    }

    function test_nestInstantRedeem_allowsArbitraryReceiver() public {
        uint256 sharesToRedeem = 5 ether;
        uint256 otherAssetsBefore = asset.balanceOf(other);

        Call[] memory bundle = _singleCall(
            abi.encodeCall(adapter.nestInstantRedeem, (vault, sharesToRedeem, MIN_SHARE_PRICE_E27, other, user))
        );

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(asset.balanceOf(other), otherAssetsBefore + sharesToRedeem, "assets received by custom receiver");
    }

    function test_nestRequestAndRedeem_singleCallBundle() public {
        uint256 sharesToRedeem = 9 ether;
        uint256 userAssetsBefore = asset.balanceOf(user);

        Call[] memory bundle = _singleCall(
            abi.encodeCall(adapter.nestRequestAndRedeem, (vault, sharesToRedeem, MIN_SHARE_PRICE_E27, user, user, user))
        );

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(asset.balanceOf(user), userAssetsBefore + sharesToRedeem, "assets received");
        assertEq(mockVault.requestRedeemCalls(), 1, "request redeem called once");
        assertEq(mockVault.fulfillRedeemCalls(), 1, "fulfill redeem called once");
        assertEq(mockVault.withdrawCalls(), 1, "withdraw called once");
        assertEq(mockVault.pending(user), 0, "no pending shares");
        assertEq(mockVault.claimable(user), 0, "no claimable shares");
        assertEq(asset.balanceOf(address(adapter)), 0, "no residual assets on adapter");
        assertEq(share.balanceOf(address(adapter)), 0, "no residual shares on adapter");
        assertEq(asset.balanceOf(address(bundler3)), 0, "no residual assets on bundler");
        assertEq(share.balanceOf(address(bundler3)), 0, "no residual shares on bundler");
    }

    function test_nestComplianceRequestAndRedeem_checksInitiatorAndOnBehalf() public {
        uint256 sharesToRedeem = 9 ether;
        uint256 userAssetsBefore = asset.balanceOf(user);
        bytes32 onBehalf = bytes32(uint256(uint160(user)));
        share.mint(address(adapter), sharesToRedeem);

        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestComplianceRequestAndRedeem,
                (
                    IComplianceProxy(address(complianceProxy)),
                    vault,
                    sharesToRedeem,
                    MIN_SHARE_PRICE_E27,
                    user,
                    user,
                    address(adapter),
                    onBehalf,
                    bytes("")
                )
            )
        );

        vm.prank(solver);
        bundler3.multicall(bundle);

        assertEq(complianceProxy.genericUserCheckCalls(), 1, "compliance check should be called once");
        assertEq(complianceProxy.lastCheckedCaller(), solver, "Bundler3 initiator should be checked as caller");
        assertEq(complianceProxy.lastCheckedOnBehalf(), onBehalf, "bundle owner should be checked as onBehalf");
        assertEq(mockVault.requestRedeemCalls(), 1, "request redeem called once");
        assertEq(mockVault.fulfillRedeemCalls(), 1, "fulfill redeem called once");
        assertEq(mockVault.withdrawCalls(), 1, "withdraw called once");
        assertEq(asset.balanceOf(user), userAssetsBefore + sharesToRedeem, "assets received");
    }

    function test_nestComplianceRequestAndRedeem_revertsWhenInitiatorCannotFulfill() public {
        vm.mockCall(
            address(authority),
            abi.encodeWithSignature(
                "canCall(address,address,bytes4)", solver, address(vault), vault.fulfillRedeem.selector
            ),
            abi.encode(false)
        );

        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestComplianceRequestAndRedeem,
                (
                    IComplianceProxy(address(complianceProxy)),
                    vault,
                    1 ether,
                    MIN_SHARE_PRICE_E27,
                    user,
                    user,
                    address(adapter),
                    bytes32(uint256(uint160(user))),
                    bytes("")
                )
            )
        );

        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        vm.prank(solver);
        bundler3.multicall(bundle);

        assertEq(complianceProxy.genericUserCheckCalls(), 0, "compliance proof should not be consumed");
        assertEq(mockVault.requestRedeemCalls(), 0, "vault should not be called");
    }

    function test_nestComplianceRequestRedeem_checksExplicitOnBehalfWhenAdapterOwnsShares() public {
        uint256 sharesToRedeem = 9 ether;
        bytes32 onBehalf = bytes32(uint256(uint160(user)));
        share.mint(address(adapter), sharesToRedeem);
        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestComplianceRequestRedeem,
                (
                    IComplianceProxy(address(complianceProxy)),
                    vault,
                    sharesToRedeem,
                    user,
                    address(adapter),
                    onBehalf,
                    bytes("")
                )
            )
        );

        vm.prank(solver);
        bundler3.multicall(bundle);

        assertEq(complianceProxy.genericUserCheckCalls(), 1, "compliance check should be called once");
        assertEq(complianceProxy.lastCheckedCaller(), solver, "Bundler3 initiator should be checked as caller");
        assertEq(complianceProxy.lastCheckedOnBehalf(), onBehalf, "represented user should be checked as onBehalf");
        assertEq(mockVault.requestRedeemCalls(), 1, "request redeem called once");
        assertEq(mockVault.pending(user), sharesToRedeem, "shares should be pending");
        assertEq(share.balanceOf(address(adapter)), 0, "adapter shares should be requested");
    }

    function test_nestComplianceRequestRedeem_revertsWhenComplianceFails() public {
        complianceProxy.setComplianceAuthorized(false);
        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestComplianceRequestRedeem,
                (
                    IComplianceProxy(address(complianceProxy)),
                    vault,
                    1 ether,
                    user,
                    user,
                    bytes32(uint256(uint160(user))),
                    bytes("")
                )
            )
        );

        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(mockVault.requestRedeemCalls(), 0, "vault should not be called");
    }

    function test_nestRedeem_singleCallBundle() public {
        uint256 sharesToRedeem = 4 ether;
        uint256 userAssetsBefore = asset.balanceOf(user);
        _prefillClaimable(user, user, sharesToRedeem);

        Call[] memory bundle =
            _singleCall(abi.encodeCall(adapter.nestRedeem, (vault, sharesToRedeem, MIN_SHARE_PRICE_E27, user, user)));

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(asset.balanceOf(user), userAssetsBefore + sharesToRedeem, "assets received");
        assertEq(mockVault.redeemCalls(), 1, "redeem called once");
        assertEq(mockVault.claimable(user), 0, "claimable consumed");
    }

    function test_nestWithdraw_singleCallBundle() public {
        uint256 assetsToWithdraw = 4 ether;
        uint256 userAssetsBefore = asset.balanceOf(user);
        _prefillClaimable(user, user, assetsToWithdraw);

        Call[] memory bundle = _singleCall(
            abi.encodeCall(adapter.nestWithdraw, (vault, assetsToWithdraw, MIN_SHARE_PRICE_E27, user, user))
        );

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(asset.balanceOf(user), userAssetsBefore + assetsToWithdraw, "assets received");
        assertEq(mockVault.withdrawCalls(), 1, "withdraw called once");
        assertEq(mockVault.claimable(user), 0, "claimable consumed");
    }

    function test_nestWithdraw_revertsWhenZeroAmount() public {
        Call[] memory bundle =
            _singleCall(abi.encodeCall(adapter.nestWithdraw, (vault, 0, MIN_SHARE_PRICE_E27, user, user)));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_nestRedeem_allowsArbitraryReceiver() public {
        uint256 sharesToRedeem = 3 ether;
        uint256 otherAssetsBefore = asset.balanceOf(other);
        _prefillClaimable(user, user, sharesToRedeem);

        Call[] memory bundle =
            _singleCall(abi.encodeCall(adapter.nestRedeem, (vault, sharesToRedeem, MIN_SHARE_PRICE_E27, other, user)));

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(asset.balanceOf(other), otherAssetsBefore + sharesToRedeem, "assets received by custom receiver");
    }

    function test_nestInstantRedeem_revertsWhenInitiatorMismatch() public {
        Call[] memory bundle =
            _singleCall(abi.encodeCall(adapter.nestInstantRedeem, (vault, 1 ether, MIN_SHARE_PRICE_E27, user, other)));

        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_nestInstantRedeem_operatorInitiator_allowsDifferentOwner() public {
        uint256 sharesToRedeem = 1 ether;
        uint256 otherAssetsBefore = asset.balanceOf(other);

        vm.prank(user);
        mockVault.setOperator(solver, true);

        Call[] memory bundle = _singleCall(
            abi.encodeCall(adapter.nestInstantRedeem, (vault, sharesToRedeem, MIN_SHARE_PRICE_E27, other, user))
        );

        vm.prank(solver);
        bundler3.multicall(bundle);

        assertEq(
            asset.balanceOf(other), otherAssetsBefore + sharesToRedeem, "operator flow should allow external owner"
        );
    }

    function test_nestRequestAndRedeem_revertsWhenInitiatorMismatch() public {
        Call[] memory bundle = _singleCall(
            abi.encodeCall(adapter.nestRequestAndRedeem, (vault, 1 ether, MIN_SHARE_PRICE_E27, user, user, other))
        );

        vm.expectRevert(ErrorsLib.UnexpectedOwner.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_nestRequestAndRedeem_operatorInitiator_allowsDifferentOwner() public {
        uint256 sharesToRedeem = 1 ether;
        uint256 otherAssetsBefore = asset.balanceOf(other);

        vm.prank(user);
        mockVault.setOperator(solver, true);

        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.nestRequestAndRedeem, (vault, sharesToRedeem, MIN_SHARE_PRICE_E27, other, user, user)
            )
        );

        vm.prank(solver);
        bundler3.multicall(bundle);

        assertEq(
            asset.balanceOf(other), otherAssetsBefore + sharesToRedeem, "operator flow should allow external owner"
        );
    }

    function test_nestDeposit_revertsWhenZeroReceiver() public {
        Call[] memory bundle =
            _singleCall(abi.encodeCall(adapter.nestDeposit, (vault, 1 ether, MAX_SHARE_PRICE_E27, address(0))));

        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_tellerPredicateDeposit_revertsWhenZeroReceiver() public {
        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.tellerPredicateDeposit,
                (
                    ITellerPredicateProxy(address(legacyPredicateProxy)),
                    ERC20(address(asset)),
                    1 ether,
                    0,
                    address(0),
                    legacyTeller,
                    _emptyPredicateMessage()
                )
            )
        );

        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_tellerPredicateDeposit_revertsWhenInitiatorPredicateUnauthorized() public {
        asset.mint(address(adapter), 1 ether);
        legacyPredicateProxy.setPredicateAuthorized(false);

        Call[] memory bundle = _singleCall(
            abi.encodeCall(
                adapter.tellerPredicateDeposit,
                (
                    ITellerPredicateProxy(address(legacyPredicateProxy)),
                    ERC20(address(asset)),
                    1 ether,
                    0,
                    user,
                    legacyTeller,
                    _emptyPredicateMessage()
                )
            )
        );

        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_nestInstantRedeem_revertsWhenZeroReceiver() public {
        Call[] memory bundle = _singleCall(
            abi.encodeCall(adapter.nestInstantRedeem, (vault, 1 ether, MIN_SHARE_PRICE_E27, address(0), user))
        );

        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_nestRequestAndRedeem_revertsWhenZeroReceiver() public {
        Call[] memory bundle = _singleCall(
            abi.encodeCall(adapter.nestRequestAndRedeem, (vault, 1 ether, MIN_SHARE_PRICE_E27, address(0), user, user))
        );

        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_nestRedeem_revertsWhenZeroReceiver() public {
        Call[] memory bundle =
            _singleCall(abi.encodeCall(adapter.nestRedeem, (vault, 1 ether, MIN_SHARE_PRICE_E27, address(0), user)));

        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_nestWithdraw_revertsWhenZeroReceiver() public {
        Call[] memory bundle =
            _singleCall(abi.encodeCall(adapter.nestWithdraw, (vault, 1 ether, MIN_SHARE_PRICE_E27, address(0), user)));

        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_nestDeposit_revertsWhenZeroAmount() public {
        Call[] memory bundle = _singleCall(abi.encodeCall(adapter.nestDeposit, (vault, 0, MAX_SHARE_PRICE_E27, user)));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_nestInstantRedeem_revertsWhenZeroShares() public {
        Call[] memory bundle =
            _singleCall(abi.encodeCall(adapter.nestInstantRedeem, (vault, 0, MIN_SHARE_PRICE_E27, user, user)));

        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_nestRedeem_revertsWhenZeroShares() public {
        Call[] memory bundle =
            _singleCall(abi.encodeCall(adapter.nestRedeem, (vault, 0, MIN_SHARE_PRICE_E27, user, user)));

        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        vm.prank(user);
        bundler3.multicall(bundle);
    }

    function test_morphoWithdrawCollateral_allowsSolverInitiator() public {
        MarketParams memory params = _marketParams();
        Call[] memory bundle =
            _singleCall(abi.encodeCall(MorphoAdapter.morphoWithdrawCollateralOnBehalf, (params, 1 ether, user, user)));

        vm.prank(solver);
        bundler3.multicall(bundle);

        assertEq(morpho.withdrawCollateralCalls(), 1, "withdraw collateral should be forwarded to Morpho");
        assertEq(morpho.lastWithdrawAssets(), 1 ether, "unexpected forwarded assets");
        assertEq(morpho.lastOnBehalf(), user, "unexpected forwarded onBehalf");
        assertEq(morpho.lastReceiver(), user, "unexpected forwarded receiver");
    }

    function _prefillClaimable(address controller, address owner, uint256 shares_) internal {
        vm.prank(owner);
        mockVault.requestRedeem(shares_, controller, owner);
        mockVault.fulfillRedeem(controller, shares_);
    }

    function _singleCall(bytes memory data) internal view returns (Call[] memory bundle) {
        bundle = new Call[](1);
        bundle[0] = Call({to: address(adapter), data: data, value: 0, skipRevert: false, callbackHash: bytes32(0)});
    }

    function _marketParams() internal view returns (MarketParams memory) {
        return MarketParams({
            loanToken: address(asset),
            collateralToken: address(share),
            oracle: address(0x1111111111111111111111111111111111111111),
            irm: address(0x2222222222222222222222222222222222222222),
            lltv: 860_000_000_000_000_000
        });
    }

    function _emptyPredicateMessage() internal pure returns (PredicateMessage memory message) {
        message = PredicateMessage({
            taskId: "", expireByTime: type(uint256).max, signerAddresses: new address[](0), signatures: new bytes[](0)
        });
    }
}
