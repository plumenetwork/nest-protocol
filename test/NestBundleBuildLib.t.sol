// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {Call} from "contracts/vendor/bundler3/interfaces/IBundler3.sol";
import {Id, IMorpho, Market, MarketParams, Position as MorphoPosition} from "@morpho/interfaces/IMorpho.sol";
import {ORACLE_PRICE_SCALE} from "@morpho/libraries/ConstantsLib.sol";
import {MarketParamsLib} from "@morpho/libraries/MarketParamsLib.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {BundleBuildLib} from "contracts/morpho/libraries/BundleBuildLib.sol";
import {BundleCalldataLib} from "contracts/morpho/libraries/BundleCalldataLib.sol";
import {MorphoAdapter} from "contracts/morpho/MorphoAdapter.sol";
import {NestAdapter} from "contracts/morpho/NestAdapter.sol";
import {NestBundleErrors} from "contracts/morpho/types/Errors.sol";
import {GeneralAdapter1} from "contracts/vendor/morpho/GeneralAdapter1.sol";
import {
    UserIntent,
    Bundle,
    BundleContext,
    PositionMode,
    MarketActions,
    RouteInput,
    Position,
    VaultActions
} from "contracts/morpho/types/BundleTypes.sol";

contract MockMorphoBundleUnit {
    mapping(bytes32 => MorphoPosition) internal _positions;
    mapping(bytes32 => Market) internal _markets;

    function setPosition(Id id, address user, uint128 borrowShares, uint128 collateral) external {
        _positions[keccak256(abi.encode(id, user))] =
            MorphoPosition({supplyShares: 0, borrowShares: borrowShares, collateral: collateral});
    }

    function setMarket(
        Id id,
        uint128 totalSupplyAssets,
        uint128 totalSupplyShares,
        uint128 totalBorrowAssets,
        uint128 totalBorrowShares,
        uint128 lastUpdate,
        uint128 fee
    ) external {
        _markets[Id.unwrap(id)] = Market({
            totalSupplyAssets: totalSupplyAssets,
            totalSupplyShares: totalSupplyShares,
            totalBorrowAssets: totalBorrowAssets,
            totalBorrowShares: totalBorrowShares,
            lastUpdate: lastUpdate,
            fee: fee
        });
    }

    function position(Id id, address user) external view returns (MorphoPosition memory) {
        return _positions[keccak256(abi.encode(id, user))];
    }

    function market(Id id) external view returns (Market memory) {
        return _markets[Id.unwrap(id)];
    }
}

contract BundleBuildLibHarness {
    using BundleCalldataLib for Bundle;

    function getTargetBundle(
        BundleContext memory ctx,
        UserIntent memory intent,
        RouteInput memory route,
        uint256 targetBorrow,
        uint256 targetCollateral
    ) external view returns (Bundle memory) {
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: targetBorrow, collateral: targetCollateral});
        return BundleBuildLib.getBundle(ctx, intent, route);
    }

    function getDeltaBundle(
        BundleContext memory ctx,
        UserIntent memory intent,
        RouteInput memory route,
        uint256 borrow,
        uint256 repay,
        uint256 supplyCollateral,
        uint256 withdrawCollateral
    ) external view returns (Bundle memory) {
        intent.mode = PositionMode.Delta;
        intent.delta = MarketActions({
            borrow: borrow, repay: repay, supplyCollateral: supplyCollateral, withdrawCollateral: withdrawCollateral
        });
        return BundleBuildLib.getBundle(ctx, intent, route);
    }

    function getAsyncBundle(BundleContext memory ctx, UserIntent memory intent, bool useAtomicQueue)
        external
        view
        returns (Bundle memory)
    {
        return BundleBuildLib.getAsyncBundle(ctx, intent, useAtomicQueue);
    }

    function getSyncSplit(Bundle memory bundle) external pure returns (Bundle memory) {
        return BundleBuildLib.getSyncBundle(bundle);
    }

    function getAsyncSplit(Bundle memory bundle) external pure returns (Bundle memory) {
        return BundleBuildLib.getAsyncBundle(bundle);
    }

    function splitBundleSequentially(Bundle memory bundle)
        external
        pure
        returns (Bundle memory postSplitBundle, Bundle memory syncBundle, Bundle memory asyncBundle)
    {
        syncBundle = BundleBuildLib.getSyncBundle(bundle);
        asyncBundle = BundleBuildLib.getAsyncBundle(bundle);
        postSplitBundle = bundle;
    }

    function getBundleCalls(Bundle memory bundle) external view returns (Call[] memory) {
        return bundle.getBundleCalls();
    }

    function getRequiredLoanAssets(
        BundleContext memory ctx,
        MarketActions memory ma,
        VaultActions memory va,
        RouteInput memory route
    )
        external
        view
        returns (uint256 requiredLoanAssets, uint256 requiredDepositLoanAssets, uint256 requiredRepayLoanAssets)
    {
        return BundleBuildLib.getRequiredLoanAssets(ctx, ma, va, route);
    }

    function getCurrentPosition(BundleContext memory ctx, MarketParams memory market, address owner)
        external
        view
        returns (uint256 borrow, uint256 collateral)
    {
        return BundleBuildLib.getCurrentPosition(ctx, market, owner);
    }
}

contract BundleBuildLibTest is Test {
    using MarketParamsLib for MarketParams;

    address internal constant OWNER = address(0x1001);
    address internal constant ALT_INITIATOR = address(0x1002);

    address internal constant ADAPTER = address(0x2001);
    address internal constant BUNDLER = address(0x2002);
    address internal constant VAULT = address(0x2003);
    address internal constant TELLER = address(0x2004);
    address internal constant PREDICATE_PROXY = address(0x2005);
    address internal constant ATOMIC_SOLVER = address(0x2006);
    address internal constant ATOMIC_QUEUE = address(0x2007);
    address internal constant ACCOUNTANT = address(0x2008);
    address internal constant VAULT_AUTHORITY = address(0x2009);

    MockMorphoBundleUnit internal morpho;
    BundleBuildLibHarness internal harness;

    MarketParams internal market;
    Id internal marketId;

    function setUp() external {
        morpho = new MockMorphoBundleUnit();
        harness = new BundleBuildLibHarness();

        market = _marketParams();
        marketId = market.id();

        // 1:1 borrowShares <-> borrowAssets conversion.
        morpho.setMarket(marketId, 1_000_000e18, 0, 1e18, 1e18, uint128(block.timestamp), 0);

        // 1:1 share <-> asset conversion.
        vm.mockCall(VAULT, abi.encodeWithSignature("asset()"), abi.encode(market.loanToken));
        vm.mockCall(VAULT, abi.encodeWithSignature("share()"), abi.encode(market.collateralToken));
        vm.mockCall(VAULT, abi.encodeWithSignature("accountant()"), abi.encode(ACCOUNTANT));
        vm.mockCall(VAULT, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.mockCall(VAULT, abi.encodeWithSignature("authority()"), abi.encode(VAULT_AUTHORITY));
        vm.mockCall(
            ACCOUNTANT,
            abi.encodeWithSignature("getRateInQuoteSafe(address)", market.loanToken),
            abi.encode(uint256(1e18))
        );
        vm.mockCall(
            VAULT_AUTHORITY,
            abi.encodeWithSignature(
                "canCall(address,address,bytes4)", PREDICATE_PROXY, VAULT, bytes4(keccak256("mint(uint256,address)"))
            ),
            abi.encode(true)
        );
        vm.mockCall(market.oracle, abi.encodeWithSignature("price()"), abi.encode(uint256(ORACLE_PRICE_SCALE)));

        _setOwnerBalances(1_000_000e18, 1_000_000e18);
        _setInstantRedeemLiquidity(1_000_000e18);

        // Default no-fee mocks for redemption fee queries and preview calls.
        _mockFees(0, 0, 0);
        _mockFees(1, 0, 0);
        _mockFees(2, 0, 0);
        _mockPreviewFulfillRedeem(0, 0, 0);
    }

    function test_getCurrentPosition_readsBorrowAndCollateral() external {
        _setPosition(40, 120);

        (uint256 borrow, uint256 collateral) = harness.getCurrentPosition(_context(OWNER, OWNER), market, OWNER);
        assertEq(borrow, 40);
        assertEq(collateral, 120);
    }

    function test_getRequiredLoanAssets_noRepayUsesBorrowToOffsetDeposit() external view {
        MarketActions memory ma = MarketActions({repay: 0, borrow: 60, withdrawCollateral: 0, supplyCollateral: 0});
        VaultActions memory va =
            VaultActions({mint: 0, deposit: 50, redeem: 0, withdraw: 0, pullAssets: 0, pullShares: 0});

        (uint256 requiredLoanAssets, uint256 requiredDepositLoanAssets, uint256 requiredRepayLoanAssets) =
            harness.getRequiredLoanAssets(_context(OWNER, OWNER), ma, va, _route());

        assertEq(requiredLoanAssets, 50);
        assertEq(requiredDepositLoanAssets, 0);
        assertEq(requiredRepayLoanAssets, 0);
    }

    function test_getRequiredLoanAssets_withRepayAndLowWithdrawCollateralReturnsBothRequirements() external {
        MarketActions memory ma = MarketActions({repay: 40, borrow: 0, withdrawCollateral: 10, supplyCollateral: 0});
        VaultActions memory va =
            VaultActions({mint: 0, deposit: 20, redeem: 0, withdraw: 0, pullAssets: 0, pullShares: 0});

        // Mock previewFulfillRedeem for the expected withdrawCollateral amount (no fee, 1:1).
        _mockPreviewFulfillRedeem(10, 10, 0);

        (uint256 requiredLoanAssets, uint256 requiredDepositLoanAssets, uint256 requiredRepayLoanAssets) =
            harness.getRequiredLoanAssets(_context(OWNER, OWNER), ma, va, _route());

        assertEq(requiredLoanAssets, 60);
        assertEq(requiredDepositLoanAssets, 20);
        assertEq(requiredRepayLoanAssets, 30);
    }

    function test_getTargetBundle_buildsExpectedActionsAndVaultLegs() external {
        _setPosition(10, 20);
        _setOwnerBalances(1_000_000e18, 30);

        UserIntent memory intent = _intent();
        intent.shareAllowance = 20;
        _mockPreviewMint(60, 60);

        Bundle memory bundle = harness.getTargetBundle(_context(OWNER, OWNER), intent, _route(), 70, 100);

        assertEq(bundle.ma.borrow, 60);
        assertEq(bundle.ma.repay, 0);
        assertEq(bundle.ma.supplyCollateral, 80);
        assertEq(bundle.ma.withdrawCollateral, 0);
        assertEq(_flashLoanAssets(bundle), 60);

        assertEq(bundle.va.pullShares, 20);
        assertEq(bundle.va.mint, 60);
        assertEq(bundle.va.deposit, 60);
        assertEq(bundle.va.pullAssets, 0);
        assertEq(bundle.va.redeem, 0);
    }

    function test_getAsyncBundle_atomicQueue_usesLegacyRouteAndWithdrawSizedRedeem() external {
        _setPosition(20, 100);

        UserIntent memory intent = _intent();
        intent.maxSharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Delta;
        intent.delta = MarketActions({borrow: 0, repay: 20, supplyCollateral: 0, withdrawCollateral: 50});

        Bundle memory bundle = harness.getAsyncBundle(_context(OWNER, ALT_INITIATOR), intent, true);

        assertTrue(bundle.route.legacyRedemption);
        assertEq(bundle.ma.borrow, 0);
        assertEq(bundle.ma.repay, 20);
        assertEq(bundle.ma.supplyCollateral, 0);
        assertEq(bundle.ma.withdrawCollateral, 50);
        assertEq(bundle.va.redeem, 50);

        Call[] memory calls = harness.getBundleCalls(bundle);
        assertEq(calls.length, 2);
        assertEq(_selector(calls[0].data), GeneralAdapter1.morphoFlashLoan.selector);
        assertEq(_selector(calls[1].data), NestAdapter.adapterSweep.selector);

        (, uint256 flashAssets, bytes memory callbackData) = abi.decode(_args(calls[0].data), (address, uint256, bytes));
        assertEq(flashAssets, 20);

        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
        assertEq(callbackBundle.length, 3);
        assertEq(_selector(callbackBundle[0].data), GeneralAdapter1.morphoRepay.selector);
        assertEq(_selector(callbackBundle[1].data), MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector);
        assertEq(_selector(callbackBundle[2].data), NestAdapter.atomicSolverRedeemSolve.selector);
    }

    function test_getAsyncBundle_modernRoute_matchesGetBundle() external {
        _setPosition(40, 100);

        // Mock no-fee async redemption previews for the deleverage flow.
        _mockPreviewFulfillRedeem(50, 50, 0);
        _mockPreviewFulfillRedeem(10, 10, 0);

        UserIntent memory intent = _intent();
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: 30, collateral: 50});

        Bundle memory expected = harness.getTargetBundle(_context(OWNER, OWNER), _intent(), _route(), 30, 50);
        Bundle memory actual = harness.getAsyncBundle(_context(OWNER, OWNER), intent, false);

        assertEq(keccak256(abi.encode(actual)), keccak256(abi.encode(expected)));
    }

    function test_getTargetBundle_revertsWhenOwnerDiffersFromInitiatorAndPullSharesNeeded() external {
        _setPosition(10, 20);
        _setOwnerBalances(1_000_000e18, 30);

        UserIntent memory intent = _intent();
        intent.shareAllowance = 20;
        _mockPreviewMint(60, 60);

        vm.expectRevert(
            abi.encodeWithSelector(
                NestBundleErrors.OwnerMustBeInitiatorWhenPullingBalances.selector, OWNER, ALT_INITIATOR
            )
        );
        harness.getTargetBundle(_context(OWNER, ALT_INITIATOR), intent, _route(), 70, 100);
    }

    function test_getTargetBundle_revertsWhenAssetAllowanceBelowRequired() external {
        _setPosition(40, 80);
        _setOwnerBalances(1_000_000e18, 0);
        _mockPreviewMint(20, 20);

        UserIntent memory intent = _intent();
        intent.assetAllowance = 39;

        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.OwnerLoanAssetsBelowRequired.selector, 39, 40));
        harness.getTargetBundle(_context(OWNER, OWNER), intent, _route(), 20, 100);
    }

    function test_getTargetBundle_revertsWhenOwnerLoanAssetBalanceIsInsufficient() external {
        _setPosition(40, 80);
        _setOwnerBalances(39, 0);
        _mockPreviewMint(20, 20);

        UserIntent memory intent = _intent();
        intent.assetAllowance = type(uint256).max;

        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.InsufficientOwnerLoanAssets.selector, 39, 40));
        harness.getTargetBundle(_context(OWNER, OWNER), intent, _route(), 20, 100);
    }

    function test_getTargetBundle_revertsWhenMarketLoanTokenDoesNotMatchVaultAsset() external {
        address wrongAsset = address(0xDEAD);
        vm.mockCall(VAULT, abi.encodeWithSignature("asset()"), abi.encode(wrongAsset));

        vm.expectRevert(
            abi.encodeWithSelector(
                NestBundleErrors.MarketLoanTokenMustEqualVaultAsset.selector, market.loanToken, wrongAsset
            )
        );
        harness.getTargetBundle(_context(OWNER, OWNER), _intent(), _route(), 0, 1);
    }

    function test_getTargetBundle_pullsRequiredOwnerAssetsWhenAllowanceIsMax() external {
        _setPosition(40, 80);
        _setOwnerBalances(1_000_000e18, 0);
        _mockPreviewMint(20, 20);

        UserIntent memory intent = _intent();
        intent.assetAllowance = type(uint256).max;

        Bundle memory bundle = harness.getTargetBundle(_context(OWNER, OWNER), intent, _route(), 20, 100);

        assertEq(bundle.ma.repay, 20);
        assertEq(bundle.ma.supplyCollateral, 20);
        assertEq(bundle.va.deposit, 20);
        assertEq(bundle.va.pullAssets, 40);
        assertEq(_flashLoanAssets(bundle), 0);
        assertEq(bundle.va.redeem, 0);
    }

    function test_getTargetBundle_setsRedeemFromFlashLoanWhenRepaying() external {
        _setPosition(40, 100);
        _setOwnerBalances(0, 0);

        // Mock no-fee async redemption previews for the deleverage flow.
        _mockPreviewFulfillRedeem(50, 50, 0);
        _mockPreviewFulfillRedeem(10, 10, 0);

        Bundle memory bundle = harness.getTargetBundle(_context(OWNER, OWNER), _intent(), _route(), 30, 50);

        assertEq(bundle.ma.repay, 10);
        assertEq(bundle.ma.withdrawCollateral, 50);
        assertEq(bundle.va.pullAssets, 0);
        assertEq(_flashLoanAssets(bundle), 10);
        assertEq(bundle.va.redeem, 10);
    }

    function test_getTargetBundle_revertsWhenInstantRedeemLiquidityIsInsufficient() external {
        _setPosition(40, 100);
        _setOwnerBalances(0, 0);
        _setInstantRedeemLiquidity(9);

        // Mock previewInstantRedeem for getRequiredLoanAssets (withdrawCollateral=50) and _buildBundle inflation (redeem=10).
        _mockPreviewInstantRedeem(50, 50, 0);
        _mockPreviewInstantRedeem(10, 10, 0);

        RouteInput memory route = _route();
        route.instantRedeem = true;

        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.InsufficientInstantRedeemLiquidity.selector, 10, 9));
        harness.getTargetBundle(_context(OWNER, OWNER), _intent(), route, 30, 50);
    }

    function test_getTargetBundle_allowsLegacyDepositWhenPredicateProxyIsCompatible() external {
        _setPosition(10, 20);
        _mockPreviewMint(80, 80);
        address tellerAuthority = address(0x4001);
        RouteInput memory route = _route();
        route.legacyDeposit = true;
        UserIntent memory intent = _intent();
        intent.assetAllowance = type(uint256).max;

        vm.mockCall(TELLER, abi.encodeWithSignature("authority()"), abi.encode(tellerAuthority));
        vm.mockCall(
            tellerAuthority,
            abi.encodeWithSignature(
                "canCall(address,address,bytes4)",
                PREDICATE_PROXY,
                TELLER,
                bytes4(keccak256("deposit(address,uint256,uint256)"))
            ),
            abi.encode(true)
        );

        Bundle memory bundle = harness.getTargetBundle(_context(OWNER, OWNER), intent, route, 70, 100);
        assertTrue(bundle.route.legacyDeposit);
    }

    function test_getTargetBundle_legacyDeposit_fractionalRate_usesFeeFreeAssetSizing() external {
        _setPosition(0, 0);
        address tellerAuthority = address(0x4003);
        RouteInput memory route = _route();
        route.legacyDeposit = true;
        UserIntent memory intent = _intent();
        intent.assetAllowance = type(uint256).max;

        vm.mockCall(
            ACCOUNTANT,
            abi.encodeWithSignature("getRateInQuoteSafe(address)", market.loanToken),
            abi.encode(uint256(1.5e18))
        );
        _mockPreviewMint(3, 6);
        vm.mockCall(TELLER, abi.encodeWithSignature("authority()"), abi.encode(tellerAuthority));
        vm.mockCall(
            tellerAuthority,
            abi.encodeWithSignature(
                "canCall(address,address,bytes4)",
                PREDICATE_PROXY,
                TELLER,
                bytes4(keccak256("deposit(address,uint256,uint256)"))
            ),
            abi.encode(true)
        );

        Bundle memory bundle = harness.getTargetBundle(_context(OWNER, OWNER), intent, route, 0, 3);

        assertEq(bundle.va.mint, 3, "mint target mismatch");
        assertEq(bundle.va.deposit, 5, "legacy teller should use fee-free asset sizing");
    }

    function test_getTargetBundle_revertsWhenLegacyDepositPredicateProxyIsIncompatible() external {
        _setPosition(10, 20);
        _mockPreviewMint(80, 80);
        address tellerAuthority = address(0x4002);
        RouteInput memory route = _route();
        route.legacyDeposit = true;
        UserIntent memory intent = _intent();
        intent.assetAllowance = type(uint256).max;

        vm.mockCall(TELLER, abi.encodeWithSignature("authority()"), abi.encode(tellerAuthority));
        vm.mockCall(
            tellerAuthority,
            abi.encodeWithSignature(
                "canCall(address,address,bytes4)",
                PREDICATE_PROXY,
                TELLER,
                bytes4(keccak256("deposit(address,uint256,uint256)"))
            ),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.IncompatibleContext.selector, PREDICATE_PROXY, TELLER));
        harness.getTargetBundle(_context(OWNER, OWNER), intent, route, 70, 100);
    }

    function test_getDeltaBundle_revertsWhenRepayExceedsCurrentBorrow() external {
        _setPosition(10, 10);

        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.RepayExceedsCurrentBorrow.selector, 11, 10));
        harness.getDeltaBundle(_context(OWNER, OWNER), _intent(), _route(), 0, 11, 0, 0);
    }

    function test_getDeltaBundle_revertsWhenWithdrawExceedsCurrentCollateral() external {
        _setPosition(10, 10);

        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.WithdrawExceedsCurrentCollateral.selector, 11, 10));
        harness.getDeltaBundle(_context(OWNER, OWNER), _intent(), _route(), 0, 0, 0, 11);
    }

    function test_getDeltaBundle_revertsWhenTargetLtvExceedsLimit() external {
        _setPosition(0, 10);

        UserIntent memory intent = _intent();
        intent.market.lltv = 0.5e18;
        morpho.setMarket(intent.market.id(), 1_000_000e18, 0, 1e18, 1e18, uint128(block.timestamp), 0);

        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.TargetLtvExceedsMarketMax.selector, 10, 0));
        harness.getDeltaBundle(_context(OWNER, OWNER), intent, _route(), 10, 0, 0, 0);
    }

    function test_getDeltaBundle_setsRequestedMarketActionsOnSuccess() external {
        _setPosition(10, 20);
        _setOwnerBalances(1_000_000e18, 0);
        _mockPreviewMint(5, 5);

        Bundle memory bundle = harness.getDeltaBundle(_context(OWNER, OWNER), _intent(), _route(), 12, 0, 5, 0);

        assertEq(bundle.ma.borrow, 12);
        assertEq(bundle.ma.repay, 0);
        assertEq(bundle.ma.supplyCollateral, 5);
        assertEq(bundle.ma.withdrawCollateral, 0);
        assertEq(bundle.va.mint, 5);
        assertEq(bundle.va.deposit, 5);
        assertEq(_flashLoanAssets(bundle), 5);
    }

    function _context(address owner, address initiator) internal view returns (BundleContext memory ctx) {
        ctx.morpho = IMorpho(address(morpho));
        ctx.adapter = ADAPTER;
        ctx.bundler = BUNDLER;
        ctx.vault = INestVaultCore(VAULT);
        ctx.teller = TELLER;
        ctx.predicateProxy = PREDICATE_PROXY;
        ctx.atomicSolver = ATOMIC_SOLVER;
        ctx.atomicQueue = ATOMIC_QUEUE;
        ctx.owner = owner;
        ctx.initiator = initiator;
        ctx.controller = owner;
    }

    function _intent() internal view returns (UserIntent memory intent) {
        intent.market = market;
        intent.assetAllowance = 0;
        intent.shareAllowance = 0;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
    }

    function _route() internal pure returns (RouteInput memory route) {
        route.legacyRedemption = false;
        route.legacyDeposit = false;
        route.instantRedeem = false;
    }

    function _marketParams() internal pure returns (MarketParams memory m) {
        m.loanToken = address(0x3001);
        m.collateralToken = address(0x3002);
        m.oracle = address(0x3003);
        m.irm = address(0x3004);
        m.lltv = 1e18;
    }

    function _setPosition(uint256 borrow, uint256 collateral) internal {
        morpho.setPosition(marketId, OWNER, uint128(borrow), uint128(collateral));
    }

    function _setOwnerBalances(uint256 loanAssetBalance, uint256 collateralShareBalance) internal {
        vm.mockCall(
            market.loanToken, abi.encodeWithSignature("balanceOf(address)", OWNER), abi.encode(loanAssetBalance)
        );
        vm.mockCall(
            market.collateralToken,
            abi.encodeWithSignature("balanceOf(address)", OWNER),
            abi.encode(collateralShareBalance)
        );
    }

    function _mockFees(uint8 feeType, uint32 rate, uint256 flat) internal {
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", feeType), abi.encode(rate, flat));
    }

    function _mockPreviewMint(uint256 shares, uint256 assets) internal {
        vm.mockCall(VAULT, abi.encodeWithSignature("previewMint(uint256)", shares), abi.encode(assets));
    }

    function _mockPreviewFulfillRedeem(uint256 shares, uint256 postFeeAssets, uint256 feeAmount) internal {
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", shares),
            abi.encode(postFeeAssets, feeAmount)
        );
    }

    function _mockPreviewInstantRedeem(uint256 shares, uint256 postFeeAssets, uint256 feeAmount) internal {
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewInstantRedeem(uint256)", shares),
            abi.encode(postFeeAssets, feeAmount)
        );
    }

    function _setInstantRedeemLiquidity(uint256 liquidity) internal {
        vm.mockCall(
            market.loanToken,
            abi.encodeWithSignature("balanceOf(address)", market.collateralToken),
            abi.encode(liquidity)
        );
    }

    function _flashLoanAssets(Bundle memory bundle) internal pure returns (uint256) {
        uint256 requiredLoanAssets = bundle.ma.repay + bundle.va.deposit;
        if (bundle.va.pullAssets >= requiredLoanAssets) return 0;
        return requiredLoanAssets - bundle.va.pullAssets;
    }

    // --- Deposit Fee Tests ---

    function test_getTargetBundle_depositFee_inflatesDepositAndFlashLoan() external {
        _setPosition(0, 0);
        UserIntent memory intent = _intent();
        intent.assetAllowance = type(uint256).max;

        // Mock previewMint to return 2% more than the raw conversion (simulating a 2% deposit fee).
        // mint = 100, raw convertToAssets = 100 (1:1 rate), previewMint = 103 (fee-inclusive).
        _mockPreviewMint(100, 103);

        Bundle memory bundle = harness.getTargetBundle(_context(OWNER, OWNER), intent, _route(), 50, 100);

        assertEq(bundle.va.mint, 100);
        assertEq(bundle.va.deposit, 103, "deposit should include fee");
        // requiredDepositLoanAssets = 103 - 50 (borrow) = 53
        assertEq(bundle.va.pullAssets, 53, "owner pull should cover fee-inflated deposit minus borrow");
        assertEq(_flashLoanAssets(bundle), 50);
    }

    // --- Oracle vs Nest Rate Divergence Tests ---

    function test_getTargetBundle_nestRateOneAboveOracle_depositCostsMore() external {
        // Nest: 1 share = (1e18 + 1) / 1e18 assets.  Oracle: 1:1 (ORACLE_PRICE_SCALE).
        // The vault values shares 1 wei higher per 1e18 than the oracle does.
        vm.mockCall(
            ACCOUNTANT,
            abi.encodeWithSignature("getRateInQuoteSafe(address)", market.loanToken),
            abi.encode(uint256(1e18 + 1))
        );

        _setPosition(0, 0);
        // previewMint with rate (1e18+1)/1e18 and no fee = ceil(100e18 * (1e18+1) / 1e18) = 100e18 + 100
        _mockPreviewMint(100e18, 100e18 + 100);
        UserIntent memory intent = _intent();
        intent.assetAllowance = type(uint256).max;

        Bundle memory bundle = harness.getTargetBundle(_context(OWNER, OWNER), intent, _route(), 50e18, 100e18);

        // mint = 100e18 shares.
        // deposit = ceil(100e18 * (1e18 + 1) / 1e18) = 100e18 + 100 (exact, no remainder).
        // At 1:1 nest rate, deposit would be exactly 100e18.
        assertEq(bundle.va.mint, 100e18);
        assertEq(bundle.va.deposit, 100e18 + 100);
        assertEq(bundle.ma.borrow, 50e18);
        // Extra 100 wei flows through to pullAssets.
        assertEq(bundle.va.pullAssets, 50e18 + 100);
    }

    function test_getTargetBundle_nestRateOneAboveOracle_fewerRedeemSharesOnDeleverage() external {
        // Nest rate 1 wei above 1:1 → each share redeems for slightly more assets,
        // so fewer shares are needed to cover the flash-loan repayment.
        vm.mockCall(
            ACCOUNTANT,
            abi.encodeWithSignature("getRateInQuoteSafe(address)", market.loanToken),
            abi.encode(uint256(1e18 + 1))
        );

        // Use large market totals so Morpho's virtual shares/assets offset is negligible
        // and borrowShares → borrowAssets conversion is effectively 1:1.
        morpho.setMarket(marketId, 1_000_000e18, 0, 1_000_000_000e18, 1_000_000_000e18, uint128(block.timestamp), 0);
        _setPosition(40e18, 100e18);
        _setOwnerBalances(0, 0);

        // Mock no-fee async redemption previews at rate (1e18 + 1).
        // previewFulfillRedeem(50e18) = floor(50e18 * (1e18 + 1) / 1e18) = 50e18 + 50.
        _mockPreviewFulfillRedeem(50e18, 50e18 + 50, 0);
        // previewFulfillRedeem(10e18 - 9) = floor((10e18 - 9) * (1e18 + 1) / 1e18) = 10e18 + 1.
        _mockPreviewFulfillRedeem(10e18 - 9, 10e18 + 1, 0);

        Bundle memory bundle = harness.getTargetBundle(_context(OWNER, OWNER), _intent(), _route(), 30e18, 50e18);

        assertEq(bundle.ma.repay, 10e18);
        assertEq(bundle.ma.withdrawCollateral, 50e18);

        // flashLoanAssets = 10e18.
        // redeem = ceil(10e18 * 1e18 / (1e18 + 1)) = 10e18 - 9.
        // At 1:1 nest rate, redeem would be exactly 10e18.
        assertEq(bundle.va.redeem, 10e18 - 9);
    }

    function test_getTargetBundle_oracleOneAboveNestRate_passesLtvBoundary() external {
        // Oracle overvalues collateral by 1 wei per 1e18 relative to the vault accountant.
        // A borrow of 90e18 + 1 passes the oracle-based LTV check but would fail at 1:1.
        uint256 oraclePrice = ORACLE_PRICE_SCALE + 1e18;
        vm.mockCall(market.oracle, abi.encodeWithSignature("price()"), abi.encode(oraclePrice));

        _setPosition(0, 0);
        _mockPreviewMint(100e18, 100e18);
        UserIntent memory intent = _intent();
        intent.market.lltv = 0.9e18;
        intent.assetAllowance = type(uint256).max;
        Id newId = MarketParamsLib.id(intent.market);
        morpho.setMarket(newId, 1_000_000e18, 0, 1e18, 1e18, uint128(block.timestamp), 0);

        // Oracle: collateralValue = 100e18 + 100, maxBorrow = 90e18 + 90.
        // Nest: deposit = 100e18 (1:1).  90e18 + 1 < 90e18 + 90 → passes.
        Bundle memory bundle = harness.getTargetBundle(_context(OWNER, OWNER), intent, _route(), 90e18 + 1, 100e18);

        assertEq(bundle.ma.borrow, 90e18 + 1);
        assertEq(bundle.va.deposit, 100e18);
    }

    function test_getTargetBundle_oracleOneBelowNestRate_passesWithSafeBorrow() external {
        // Oracle undervalues collateral by 1 wei per 1e18 relative to the vault accountant.
        // Borrow stays safely under the reduced maxBorrow, so LTV check passes.
        uint256 oraclePrice = ORACLE_PRICE_SCALE - 1e18;
        vm.mockCall(market.oracle, abi.encodeWithSignature("price()"), abi.encode(oraclePrice));

        _setPosition(0, 0);
        _mockPreviewMint(100e18, 100e18);
        UserIntent memory intent = _intent();
        intent.market.lltv = 0.9e18;
        intent.assetAllowance = type(uint256).max;
        Id newId = MarketParamsLib.id(intent.market);
        morpho.setMarket(newId, 1_000_000e18, 0, 1e18, 1e18, uint128(block.timestamp), 0);

        // Oracle: collateralValue = 100e18 - 100, maxBorrow = 90e18 - 90.
        // Borrow 89e18 < 90e18 - 90 → passes despite oracle underpricing.
        // Deposit uses nest rate (1:1), unaffected by oracle.
        Bundle memory bundle = harness.getTargetBundle(_context(OWNER, OWNER), intent, _route(), 89e18, 100e18);

        assertEq(bundle.ma.borrow, 89e18);
        assertEq(bundle.va.deposit, 100e18);
        assertEq(bundle.va.pullAssets, 11e18);
    }

    function _selector(bytes memory data) internal pure returns (bytes4 selector_) {
        assembly {
            selector_ := mload(add(data, 32))
        }
    }

    function _args(bytes memory data) internal pure returns (bytes memory args_) {
        uint256 len = data.length - 4;
        args_ = new bytes(len);
        for (uint256 i; i < len; ++i) {
            args_[i] = data[i + 4];
        }
    }
}
