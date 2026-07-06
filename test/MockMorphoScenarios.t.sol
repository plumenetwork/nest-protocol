// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Call} from "contracts/vendor/bundler3/interfaces/IBundler3.sol";
import {Id, IMorpho, Market, MarketParams, Position as MorphoPosition} from "@morpho/interfaces/IMorpho.sol";
import {ORACLE_PRICE_SCALE} from "@morpho/libraries/ConstantsLib.sol";
import {MarketParamsLib} from "@morpho/libraries/MarketParamsLib.sol";
import {PredicateMessage} from "@predicate/src/interfaces/IPredicateClient.sol";
import {GeneralAdapter1} from "contracts/vendor/morpho/GeneralAdapter1.sol";
import {NestAdapter} from "contracts/morpho/NestAdapter.sol";
import {MorphoAdapter} from "contracts/morpho/MorphoAdapter.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {BundleBuildLib} from "contracts/morpho/libraries/BundleBuildLib.sol";
import {BundleCalldataLib} from "contracts/morpho/libraries/BundleCalldataLib.sol";
import {NestShareMathLib} from "contracts/morpho/libraries/NestShareMathLib.sol";
import {
    Bundle,
    BundleContext,
    MarketActions,
    PositionMode,
    RouteInput,
    Position,
    UserIntent
} from "contracts/morpho/types/BundleTypes.sol";
import {NestBundleErrors} from "contracts/morpho/types/Errors.sol";

contract MockMorphoScenario {
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

    function position(Id id, address user) external view returns (MorphoPosition memory p) {
        return _positions[keccak256(abi.encode(id, user))];
    }

    function market(Id id) external view returns (Market memory m) {
        return _markets[Id.unwrap(id)];
    }
}

contract NestBundleHarness {
    function getTargetBundle(
        BundleContext memory context,
        UserIntent memory intent,
        RouteInput memory route,
        uint256 targetBorrow,
        uint256 targetCollateral
    ) external view returns (Bundle memory) {
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: targetBorrow, collateral: targetCollateral});
        return BundleBuildLib.getBundle(context, intent, route);
    }
}

contract MockMorphoScenarios is Test {
    using MarketParamsLib for MarketParams;
    using NestShareMathLib for uint256;

    struct Scenario {
        string name;
        uint256 currentCollateral;
        uint256 currentBorrow;
        uint256 targetCollateral;
        uint256 targetBorrow;
        uint256 extraLoanAssets;
        uint256 extraCollateral;
        uint256 expectedFlashLoan;
        uint256 expectedRepay;
        uint256 expectedBorrow;
        uint256 expectedWithdrawCollateral;
        uint256 expectedSupplyCollateral;
        uint256 expectedDeposit;
        uint256 expectedRedeem;
        bool shouldRevert;
        bytes revertData;
    }

    address internal constant OWNER = address(0x1001);
    address internal constant ADAPTER = address(0x2001);
    address internal constant BUNDLER = address(0x2002);
    address internal constant VAULT = address(0x2003);
    address internal constant TELLER = address(0x2004);
    address internal constant PREDICATE_PROXY = address(0x2005);
    address internal constant ATOMIC_SOLVER = address(0x2006);
    address internal constant ATOMIC_QUEUE = address(0x2007);
    address internal constant ACCOUNTANT = address(0x2008);

    MockMorphoScenario internal morpho;
    NestBundleHarness internal harness;
    MarketParams internal marketParams;
    Id internal marketId;

    function setUp() external {
        morpho = new MockMorphoScenario();
        harness = new NestBundleHarness();
        marketParams = _marketParams();
        marketId = marketParams.id();

        // 1:1 borrowShares <-> borrowAssets conversion for readable scenario values.
        morpho.setMarket(marketId, 1_000_000e18, 0, 1e18, 1e18, uint128(block.timestamp), 0);

        // 1:1 share <-> asset conversion for NestShareMathLib conversion calls.
        vm.mockCall(VAULT, abi.encodeWithSignature("asset()"), abi.encode(marketParams.loanToken));
        vm.mockCall(VAULT, abi.encodeWithSignature("share()"), abi.encode(marketParams.collateralToken));
        vm.mockCall(VAULT, abi.encodeWithSignature("accountant()"), abi.encode(ACCOUNTANT));
        vm.mockCall(VAULT, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.mockCall(
            marketParams.loanToken, abi.encodeWithSignature("balanceOf(address)", OWNER), abi.encode(uint256(1e18))
        );
        // Morpho holds ample loan-token liquidity so deleverage bundles flash-loan in a single shot
        // (the looped path only engages when repay exceeds Morpho's loan-token balance).
        vm.mockCall(
            marketParams.loanToken,
            abi.encodeWithSignature("balanceOf(address)", address(morpho)),
            abi.encode(type(uint256).max)
        );
        // Ample redeem buffer by default: `getInstantRedeemLiquidity` reads the asset held by the share token, and
        // the looped redeem-liquidity guard reads it for BOTH instant and async routes. Tests that exercise the
        // guard override this via `_setInstantRedeemLiquidity`.
        vm.mockCall(
            marketParams.loanToken,
            abi.encodeWithSignature("balanceOf(address)", marketParams.collateralToken),
            abi.encode(type(uint256).max)
        );
        vm.mockCall(
            marketParams.collateralToken,
            abi.encodeWithSignature("balanceOf(address)", OWNER),
            abi.encode(uint256(1e18))
        );
        vm.mockCall(
            ACCOUNTANT,
            abi.encodeWithSignature("getRateInQuoteSafe(address)", marketParams.loanToken),
            abi.encode(uint256(1e18))
        );
        vm.mockCall(marketParams.oracle, abi.encodeWithSignature("price()"), abi.encode(uint256(ORACLE_PRICE_SCALE)));

        // No-fee mocks for redemption fee types (InstantRedemption=0, Redemption=2).
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", 0), abi.encode(uint32(0), uint256(0)));
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", 2), abi.encode(uint32(0), uint256(0)));

        // Identity mock for zero-share preview calls hit by repay-only scenarios.
        vm.mockCall(
            VAULT, abi.encodeWithSignature("previewFulfillRedeem(uint256)", 0), abi.encode(uint256(0), uint256(0))
        );

        // Mock authority() on vault and canCall() on the authority so _canCall checks pass.
        address authority = address(0x2009);
        vm.mockCall(VAULT, abi.encodeWithSignature("authority()"), abi.encode(authority));
        vm.mockCall(authority, abi.encodeWithSignature("canCall(address,address,bytes4)"), abi.encode(true));
    }

    function test_importantScenarios_validateActionsAndCalls_withMockMorpho() external {
        Scenario[] memory scenarios = _importantScenarios();
        for (uint256 i; i < scenarios.length; ++i) {
            Scenario memory s = scenarios[i];
            _runScenario(s);
        }
    }

    function test_validateBundleInput_revertsWhenLegacyRedemptionAndInstantRedeemAreBothTrue() external {
        UserIntent memory intent = UserIntent({
            market: marketParams,
            assetAllowance: 0,
            shareAllowance: 0,
            maxSharePriceE27: 1,
            minSharePriceE27: 0,
            maxRepaySharePriceE27: type(uint256).max,
            mode: PositionMode.Target,
            target: Position({loan: 1, collateral: 1}),
            delta: MarketActions({borrow: 0, flashRepay: 0, repay: 0, supplyCollateral: 0, withdrawCollateral: 0})
        });
        RouteInput memory route = RouteInput({legacyRedemption: true, legacyDeposit: false, instantRedeem: true});

        vm.expectRevert(NestBundleErrors.LegacyRedemptionCannotUseInstantRedeem.selector);
        harness.getTargetBundle(_context(), intent, route, 0, 0);
    }

    function test_validateBundleInput_revertsWhenMinSharePriceExceedsMaxSharePrice() external {
        UserIntent memory intent = UserIntent({
            market: marketParams,
            assetAllowance: 0,
            shareAllowance: 0,
            maxSharePriceE27: 1,
            minSharePriceE27: 2,
            maxRepaySharePriceE27: type(uint256).max,
            mode: PositionMode.Target,
            target: Position({loan: 1, collateral: 1}),
            delta: MarketActions({borrow: 0, flashRepay: 0, repay: 0, supplyCollateral: 0, withdrawCollateral: 0})
        });

        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.MinSharePriceExceedsMaxSharePrice.selector, 2, 1));
        harness.getTargetBundle(_context(), intent, _route(), 0, 0);
    }

    function test_getBundleCalls_requestRedeemCanLeaveAdapterLoanSurplusWithoutSweep() external {
        // Set a non-integer share price so `convertToShares(..., Ceil)` can over-request shares.
        vm.mockCall(VAULT, abi.encodeWithSignature("decimals()"), abi.encode(uint8(1)));
        vm.mockCall(
            ACCOUNTANT,
            abi.encodeWithSignature("getRateInQuoteSafe(address)", marketParams.loanToken),
            abi.encode(uint256(15))
        );

        // Mock fee-aware previews at rate 15 / 10 = 1.5 assets per share.
        // previewFulfillRedeem(20) = (30, 0); previewFulfillRedeem(14) = (21, 0)
        vm.mockCall(
            VAULT, abi.encodeWithSignature("previewFulfillRedeem(uint256)", 20), abi.encode(uint256(30), uint256(0))
        );
        vm.mockCall(
            VAULT, abi.encodeWithSignature("previewFulfillRedeem(uint256)", 14), abi.encode(uint256(21), uint256(0))
        );

        // Fully deleverage: repay 20 and withdraw 20 shares of collateral.
        morpho.setPosition(marketId, OWNER, uint128(20), uint128(20));

        UserIntent memory intent = UserIntent({
            market: marketParams,
            assetAllowance: 0,
            shareAllowance: 0,
            maxSharePriceE27: 1,
            minSharePriceE27: 0,
            maxRepaySharePriceE27: type(uint256).max,
            mode: PositionMode.Delta,
            target: Position({loan: 0, collateral: 0}),
            delta: MarketActions({borrow: 0, flashRepay: 0, repay: 20, supplyCollateral: 0, withdrawCollateral: 20})
        });

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _route());
        bundle.predicateMessage = _emptyPredicateMessage();

        // The bundle must flash-loan 21 (20 + full-repay buffer); redeem shares round up to 14 (worth 21).
        uint256 flashLoanAssets = _flashLoanAssets(bundle);
        uint256 redeemedAssets = bundle.va.redeem.convertToAssets(INestVaultCore(VAULT), Math.Rounding.Floor);

        assertEq(bundle.ma.flashRepay, 21, "flashRepay (20 + full-repay buffer)");
        assertEq(bundle.ma.withdrawCollateral, 20, "withdraw mismatch");
        assertEq(flashLoanAssets, 21, "flash loan mismatch");
        assertEq(bundle.va.redeem, 14, "redeem shares mismatch");
        assertEq(redeemedAssets, 21, "redeem assets mismatch");
        assertGe(redeemedAssets, flashLoanAssets, "redeem should cover loan assets");

        // The callback still stops at request-and-redeem; any leftover loan assets are returned by the final sweep.
        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 2, "expected flash-loan wrapper plus sweep");
        assertEq(_selector(calls[0].data), GeneralAdapter1.morphoFlashLoan.selector, "outer selector mismatch");
        assertEq(_selector(calls[1].data), NestAdapter.adapterSweep.selector, "sweep selector mismatch");

        (,, bytes memory callbackData) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));

        assertEq(callbackBundle.length, 3, "unexpected callback length");
        assertEq(_selector(callbackBundle[0].data), GeneralAdapter1.morphoRepay.selector, "repay selector mismatch");
        assertEq(
            _selector(callbackBundle[1].data),
            MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector,
            "withdraw selector mismatch"
        );
        assertEq(
            _selector(callbackBundle[2].data), NestAdapter.nestRequestAndRedeem.selector, "redeem selector mismatch"
        );

        (,, uint256 minSharePriceE27, address receiver,, address owner) =
            abi.decode(_stripSelector(callbackBundle[2].data), (address, uint256, uint256, address, address, address));
        assertEq(minSharePriceE27, 0, "min share price mismatch");
        assertEq(receiver, ADAPTER, "redeem receiver mismatch");
        assertEq(owner, ADAPTER, "redeem owner mismatch");
    }

    function test_getBundleCalls_borrowCanLeaveMaterialAdapterLoanBalanceWithoutSweep() external {
        // This shape does not rely on rounding. The target explicitly borrows 10 more loan assets.
        morpho.setPosition(marketId, OWNER, uint128(20), uint128(100));

        UserIntent memory intent = UserIntent({
            market: marketParams,
            assetAllowance: 30,
            shareAllowance: 0,
            maxSharePriceE27: 1,
            minSharePriceE27: 0,
            maxRepaySharePriceE27: type(uint256).max,
            mode: PositionMode.Target,
            target: Position({loan: 30, collateral: 50}),
            delta: MarketActions({borrow: 0, flashRepay: 0, repay: 0, supplyCollateral: 0, withdrawCollateral: 0})
        });

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _route());
        bundle.predicateMessage = _emptyPredicateMessage();

        // There is no repay, deposit, or redeem leg here, so there is no rounding-based surplus to blame.
        assertEq(_flashLoanAssets(bundle), 0, "flash loan mismatch");
        assertEq(bundle.ma.repay, 0, "repay mismatch");
        assertEq(bundle.va.deposit, 0, "deposit mismatch");
        assertEq(bundle.va.redeem, 0, "redeem mismatch");
        assertEq(bundle.ma.withdrawCollateral, 50, "withdraw mismatch");
        assertEq(bundle.ma.borrow, 10, "borrow mismatch");

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 3, "unexpected direct call count");
        assertEq(
            _selector(calls[0].data),
            MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector,
            "withdraw selector mismatch"
        );
        assertEq(_selector(calls[1].data), MorphoAdapter.morphoBorrowOnBehalf.selector, "borrow selector mismatch");
        assertEq(_selector(calls[2].data), NestAdapter.adapterSweep.selector, "sweep selector mismatch");

        // The borrow proceeds are sent to the adapter and returned by the final sweep call.
        (, uint256 assets, uint256 shares, uint256 minSharePriceE27, address onBehalf, address receiver) =
            abi.decode(_stripSelector(calls[1].data), (MarketParams, uint256, uint256, uint256, address, address));
        assertEq(assets, 10, "borrow assets mismatch");
        assertEq(shares, 0, "borrow shares mismatch");
        assertEq(minSharePriceE27, 0, "min share price mismatch");
        assertEq(onBehalf, OWNER, "borrow owner mismatch");
        assertEq(receiver, ADAPTER, "borrow receiver mismatch");
    }

    function test_getBundleCalls_splitsDeleverageWhenLiquidityBelowRepay() external {
        // Full deleverage: repay 70, withdraw 100 collateral (1:1 rate, no fee).
        morpho.setPosition(marketId, OWNER, uint128(70), uint128(100));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(100)),
            abi.encode(uint256(100), uint256(0))
        );
        // Morpho holds only 40 of the 70 needed -> must split into two sequential flash loans.
        _setMorphoLoanLiquidity(40);

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), _fullExitDeltaIntent(70, 100), _route());
        bundle.predicateMessage = _emptyPredicateMessage();
        assertEq(bundle.ma.flashRepay, 71, "flashRepay (70 + full-repay buffer)");
        assertEq(_flashLoanAssets(bundle), 71, "flash total");

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 3, "two flash loans + sweep");
        assertEq(_selector(calls[0].data), GeneralAdapter1.morphoFlashLoan.selector, "chunk0 flash");
        assertEq(_selector(calls[1].data), GeneralAdapter1.morphoFlashLoan.selector, "chunk1 flash");
        assertEq(_selector(calls[2].data), NestAdapter.adapterSweep.selector, "sweep");

        // Chunk 0 flash-loans the initial liquidity; chunk 1 the remainder, restored by chunk 0's repay.
        (, uint256 flash0, bytes memory cb0Data) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        (, uint256 flash1, bytes memory cb1Data) = abi.decode(_stripSelector(calls[1].data), (address, uint256, bytes));
        assertEq(flash0, 40, "chunk0 flash == initial liquidity");
        assertEq(flash1, 31, "chunk1 flash == buffered remainder");
        assertEq(flash0 + flash1, 71, "chunks sum to buffered repay");

        // Chunk 0: intermediate, assets-based partial repay; withdraws exactly its redeem slice.
        (uint256 repay0, uint256 repayShares0, uint256 withdraw0, uint256 redeem0) = _decodeChunk(cb0Data);
        assertEq(repay0, 40, "chunk0 repay assets");
        assertEq(repayShares0, 0, "chunk0 repays by assets");
        assertEq(redeem0, 40, "chunk0 redeem (no fee, 1:1)");
        assertEq(withdraw0, 40, "chunk0 withdraw == redeem");

        // Chunk 1: final chunk of a full exit; clears the residual debt via shares=max and withdraws remaining
        // collateral. The Delta full exit is normalized to a Target full exit at build, so it uses shares=max.
        (uint256 repay1, uint256 repayShares1, uint256 withdraw1, uint256 redeem1) = _decodeChunk(cb1Data);
        assertEq(repay1, 0, "chunk1 full-exit repays by shares=max");
        assertEq(repayShares1, type(uint256).max, "chunk1 clears residual via shares=max");
        assertEq(redeem1, 31, "chunk1 redeem");
        assertEq(withdraw1, 60, "chunk1 withdraw == remaining target collateral");

        assertEq(withdraw0 + withdraw1, 100, "withdraws reconstruct target");
        assertEq(redeem0 + redeem1, 71, "redeems sum to buffered single-shot redeem");
    }

    function test_getBundleCalls_splitDeleverage_targetFullExitRunsExtraChunkWhenShareDustExceedsLiquidity() external {
        // Integer market chosen to force the exact edge with Morpho's virtual shares included:
        // - user owes ceil(10 * (10_000_000 + 1) / (1_000_000 + 1_000_000)) = 51 assets;
        // - first 17-asset intermediate repay burns floor(17 * 2_000_000 / 10_000_001) = 3 borrow shares;
        // - the linear remainder is now 34 and fits the grown liquidity, but `shares = max` would pull
        //   ceil(7 * 9_999_984 / 1_999_997) = 35 (36 with the full-repay buffer), which does NOT fit;
        // - so the builder emits one more intermediate chunk, then the final `shares = max` chunk.
        morpho.setMarket(marketId, 10_000_000, 0, 10_000_000, 1_000_000, uint128(block.timestamp), 0);
        morpho.setPosition(marketId, OWNER, uint128(10), uint128(100));
        vm.mockCall(
            VAULT, abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(100)), abi.encode(uint256(100), 0)
        );
        _setMorphoLoanLiquidity(17);

        UserIntent memory intent;
        intent.market = marketParams;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: 0, collateral: 0});

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _route());
        bundle.predicateMessage = _emptyPredicateMessage();
        assertEq(bundle.ma.flashRepay, 52, "linear full-exit flashRepay (51 + full-repay buffer)");

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 4, "extra dust chunk + final + sweep");

        (, uint256 flash0, bytes memory cb0Data) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        (, uint256 flash1, bytes memory cb1Data) = abi.decode(_stripSelector(calls[1].data), (address, uint256, bytes));
        (, uint256 flash2, bytes memory cb2Data) = abi.decode(_stripSelector(calls[2].data), (address, uint256, bytes));
        assertEq(flash0, 17, "chunk0 flash");
        assertEq(flash1, 34, "extra intermediate flash");
        assertEq(flash2, 6, "final shares=max flash (5 + full-repay buffer)");

        (uint256 repay0, uint256 repayShares0, uint256 withdraw0, uint256 redeem0) = _decodeChunk(cb0Data);
        (uint256 repay1, uint256 repayShares1, uint256 withdraw1, uint256 redeem1) = _decodeChunk(cb1Data);
        (uint256 repay2, uint256 repayShares2, uint256 withdraw2, uint256 redeem2) = _decodeChunk(cb2Data);

        assertEq(repay0, 17, "chunk0 asset repay");
        assertEq(repayShares0, 0, "chunk0 uses assets");
        assertEq(withdraw0, 17, "chunk0 withdraws redeem only");
        assertEq(redeem0, 17, "chunk0 redeem");

        assertEq(repay1, 34, "chunk1 asset repay");
        assertEq(repayShares1, 0, "chunk1 uses assets");
        assertEq(withdraw1, 34, "chunk1 withdraws redeem only");
        assertEq(redeem1, 34, "chunk1 redeem");

        assertEq(repay2, 0, "final uses shares=max");
        assertEq(repayShares2, type(uint256).max, "final clears residual shares");
        assertEq(withdraw2, 49, "final withdraws remaining collateral");
        assertEq(redeem2, 6, "final redeem covers buffered residual");
        assertEq(withdraw0 + withdraw1 + withdraw2, 100, "withdraws reconstruct target");
    }

    function test_getBundleCalls_splitDeleverage_redeemCoversRepayAfterProportionalFee() external {
        uint32 feeRate = 10_000; // 1% proportional redemption fee.
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", 2), abi.encode(feeRate, uint256(0)));

        morpho.setPosition(marketId, OWNER, uint128(70_000), uint128(100_000));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(100_000)),
            abi.encode(uint256(99_000), uint256(1_000))
        );
        _setMorphoLoanLiquidity(40_000);

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), _fullExitDeltaIntent(70_000, 100_000), _route());
        bundle.predicateMessage = _emptyPredicateMessage();

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 3, "two flash loans + sweep");

        (, uint256 flash0, bytes memory cb0Data) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        (, uint256 flash1, bytes memory cb1Data) = abi.decode(_stripSelector(calls[1].data), (address, uint256, bytes));
        assertEq(flash0, 40_000, "chunk0 flash");
        assertEq(flash1, 30_030, "chunk1 flash (residual + full-repay buffer)");

        (,,, uint256 redeem0) = _decodeChunk(cb0Data);
        (,,, uint256 redeem1) = _decodeChunk(cb1Data);

        // Fee-aware: each chunk redeems MORE shares than its repay, and the actual post-fee proceeds
        // (computed independently from the vault's fee model) still cover that chunk's flash-loan repayment.
        assertGt(redeem0, flash0, "chunk0 redeem inflated for fee");
        assertGt(redeem1, flash1, "chunk1 redeem inflated for fee");
        assertGe(_postFeeAssets(redeem0, feeRate, 0), flash0, "chunk0 post-fee covers repay");
        assertGe(_postFeeAssets(redeem1, feeRate, 0), flash1, "chunk1 post-fee covers repay");
        assertGe(
            _postFeeAssets(redeem0, feeRate, 0) + _postFeeAssets(redeem1, feeRate, 0),
            70_000,
            "post-fee proceeds cover total repay"
        );
    }

    function test_getBundleCalls_splitDeleverage_revertsWhenTailChunkTooSmallForFlatFee() external {
        uint256 flatFee = 10; // flat redemption fee; a tiny tail chunk cannot cover it within FEE_CAP.
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", 2), abi.encode(uint32(0), flatFee));

        morpho.setPosition(marketId, OWNER, uint128(70_000), uint128(100_000));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(100_000)),
            abi.encode(uint256(99_990), flatFee)
        );
        // Liquidity one short of the repay forces a 1-unit tail chunk whose flat fee exceeds FEE_CAP.
        _setMorphoLoanLiquidity(69_999);

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), _fullExitDeltaIntent(70_000, 100_000), _route());
        bundle.predicateMessage = _emptyPredicateMessage();

        // The buffered 2-unit tail chunk redeems 12 shares (2 + flat 10) at a 1:1 rate; its flat fee is 10/12 of
        // gross, far above FEE_CAP (20%), so the build reverts. External wrapper so `expectRevert` matches the
        // whole build (getBundleCalls is an internal library call).
        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.RedeemTooSmallForFlatFee.selector, 12, 12, 10));
        this.callGetBundleCalls(bundle);
    }

    function test_getBundleCalls_splitDeleverage_revertsWhenChunkBreachesLltv() external {
        // Near-LLTV position on an 80% LLTV market where the Morpho oracle values collateral at 1.2x the vault
        // redeem rate, plus a flat redemption fee. Single-shot would repay the full debt before withdrawing
        // (healthy final state), but the first chunk repays only its slice then withdraws fee-inflated
        // collateral, transiently pushing LTV above LLTV — Morpho would revert mid-multicall, so the build
        // must reject it up front.
        MarketParams memory mkt = _marketParams();
        mkt.lltv = 0.8e18;
        Id id = mkt.id();
        morpho.setMarket(id, 1_000_000e18, 0, 1e18, 1e18, uint128(block.timestamp), 0);
        morpho.setPosition(id, OWNER, uint128(190), uint128(201)); // collateralValue 241, maxBorrow 192 >= 190

        // Oracle values collateral at 1.2x; vault redeems 1:1; flat redemption fee of 10. Preview proceeds
        // cover the buffered repay (191), and the 201-share collateral covers the buffered redeem (191 + 10).
        vm.mockCall(mkt.oracle, abi.encodeWithSignature("price()"), abi.encode((ORACLE_PRICE_SCALE * 12) / 10));
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", 2), abi.encode(uint32(0), uint256(10)));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(201)),
            abi.encode(uint256(191), uint256(10))
        );
        _setMorphoLoanLiquidity(100); // forces 2 chunks: repay 100 then the buffered residual

        UserIntent memory intent;
        intent.market = mkt;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Delta;
        intent.delta =
            MarketActions({borrow: 0, flashRepay: 0, repay: 190, supplyCollateral: 0, withdrawCollateral: 201});

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _route());
        bundle.predicateMessage = _emptyPredicateMessage();

        // Chunk 0 repays 100, withdraws redeem(100)=110 collateral -> debt 90 vs maxBorrow floor(91*1.2*0.8)=87.
        vm.expectRevert(NestBundleErrors.LoopBreachesLltv.selector);
        this.callGetBundleCalls(bundle);
    }

    function test_getBundleCalls_splitDeleverage_fourChunksWhenLiquidityFarBelowRepay() external {
        // Full deleverage: repay 70 (+1 buffer), withdraw 100 (1:1 rate, no fee). Morpho holds only 10, and each
        // repay returns its assets so the loanable balance grows 10 -> 20 -> 40. The third chunk is clamped to 39
        // (leaving 1 asset of debt so the final `shares = max` chunk is never empty), then the buffered final
        // chunk clears the residual: 10/20/39/2.
        morpho.setPosition(marketId, OWNER, uint128(70), uint128(100));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(100)),
            abi.encode(uint256(100), uint256(0))
        );
        _setMorphoLoanLiquidity(10);

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), _fullExitDeltaIntent(70, 100), _route());
        bundle.predicateMessage = _emptyPredicateMessage();
        assertEq(bundle.ma.flashRepay, 71, "flashRepay (70 + full-repay buffer)");

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 5, "four flash loans + sweep");
        assertEq(_selector(calls[0].data), GeneralAdapter1.morphoFlashLoan.selector, "chunk0 flash");
        assertEq(_selector(calls[1].data), GeneralAdapter1.morphoFlashLoan.selector, "chunk1 flash");
        assertEq(_selector(calls[2].data), GeneralAdapter1.morphoFlashLoan.selector, "chunk2 flash");
        assertEq(_selector(calls[3].data), GeneralAdapter1.morphoFlashLoan.selector, "chunk3 flash");
        assertEq(_selector(calls[4].data), NestAdapter.adapterSweep.selector, "sweep");

        (, uint256 flash0, bytes memory cb0Data) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        (, uint256 flash1, bytes memory cb1Data) = abi.decode(_stripSelector(calls[1].data), (address, uint256, bytes));
        (, uint256 flash2, bytes memory cb2Data) = abi.decode(_stripSelector(calls[2].data), (address, uint256, bytes));
        (, uint256 flash3, bytes memory cb3Data) = abi.decode(_stripSelector(calls[3].data), (address, uint256, bytes));
        // Liquidity doubles per chunk as each repay is returned: 10, 20, then 39 (clamped), then the buffered tail.
        assertEq(flash0, 10, "chunk0 flash == initial liquidity");
        assertEq(flash1, 20, "chunk1 flash == grown liquidity");
        assertEq(flash2, 39, "chunk2 flash == residual minus 1 (clamped)");
        assertEq(flash3, 2, "final flash == 1 residual + full-repay buffer");
        assertEq(flash0 + flash1 + flash2 + flash3, 71, "chunks sum to buffered repay");

        (uint256 repay0, uint256 repayShares0, uint256 withdraw0, uint256 redeem0) = _decodeChunk(cb0Data);
        (uint256 repay1, uint256 repayShares1, uint256 withdraw1, uint256 redeem1) = _decodeChunk(cb1Data);
        (uint256 repay2, uint256 repayShares2, uint256 withdraw2, uint256 redeem2) = _decodeChunk(cb2Data);
        (uint256 repay3, uint256 repayShares3, uint256 withdraw3, uint256 redeem3) = _decodeChunk(cb3Data);

        // Chunks 0-2 are intermediate assets-based partial repays, each withdrawing only its redeem slice.
        assertEq(repay0, 10, "chunk0 repay assets");
        assertEq(repayShares0, 0, "chunk0 repays by assets");
        assertEq(redeem0, 10, "chunk0 redeem");
        assertEq(withdraw0, 10, "chunk0 withdraw == redeem slice");
        assertEq(repay1, 20, "chunk1 repay assets");
        assertEq(repayShares1, 0, "chunk1 repays by assets");
        assertEq(redeem1, 20, "chunk1 redeem");
        assertEq(withdraw1, 20, "chunk1 withdraw == redeem slice");
        assertEq(repay2, 39, "chunk2 repay assets");
        assertEq(repayShares2, 0, "chunk2 repays by assets");
        assertEq(redeem2, 39, "chunk2 redeem");
        assertEq(withdraw2, 39, "chunk2 withdraw == redeem slice");

        // Final chunk clears the residual debt via shares=max and withdraws all remaining collateral. The Delta
        // full exit is normalized to a Target full exit at build, so the final repay uses shares=max.
        assertEq(repay3, 0, "final chunk full-exit repays by shares=max");
        assertEq(repayShares3, type(uint256).max, "final chunk clears residual via shares=max");
        assertEq(redeem3, 2, "final chunk redeem == buffered residual");
        assertEq(withdraw3, 31, "final chunk withdraws remaining target collateral");

        assertEq(withdraw0 + withdraw1 + withdraw2 + withdraw3, 100, "withdraws reconstruct target");
        assertEq(redeem0 + redeem1 + redeem2 + redeem3, 71, "redeems sum to buffered single-shot redeem");
    }

    function test_getBundleCalls_splitDeleverage_revertsWhenExceedsMaxChunks() external {
        // Liquidity of 1 against a repay of 2^33. Each repay only doubles the loanable balance (1, 2, 4, ...),
        // so 32 chunks cover just 2^32 - 1 and a 33rd would be required -> exceeds MAX_DELEVERAGE_CHUNKS (32).
        uint256 repay = 1 << 33; // 8589934592
        uint256 bufferedRepay = repay.applyBuffer();
        // Collateral and proceeds cover the buffered repay/redeem so the build stays fully redeem-funded.
        morpho.setPosition(marketId, OWNER, uint128(repay), uint128(bufferedRepay));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", bufferedRepay),
            abi.encode(bufferedRepay, uint256(0))
        );
        _setMorphoLoanLiquidity(1);

        Bundle memory bundle =
            BundleBuildLib.getBundle(_context(), _fullExitDeltaIntent(repay, bufferedRepay), _route());
        bundle.predicateMessage = _emptyPredicateMessage();

        vm.expectRevert(NestBundleErrors.ExceedsMaxLoops.selector);
        this.callGetBundleCalls(bundle);
    }

    function test_getBundleCalls_splitDeleverage_partialExitFinalChunkRepaysByAssets() external {
        // Partial deleverage to a NON-zero target loan (40): repay 60, withdraw 80 (1:1, no fee). With only 30
        // liquidity it splits into two chunks (30/30). Because the target loan is non-zero, the final chunk is not
        // a full exit, so it repays by ASSETS (no shares=max) and the borrow-rounding buffer does not apply.
        morpho.setPosition(marketId, OWNER, uint128(100), uint128(200));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(80)),
            abi.encode(uint256(80), uint256(0))
        );
        _setMorphoLoanLiquidity(30);

        UserIntent memory intent;
        intent.market = marketParams;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: 40, collateral: 120});

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _route());
        bundle.predicateMessage = _emptyPredicateMessage();
        assertEq(bundle.ma.repay, 60, "repay");
        assertEq(bundle.ma.withdrawCollateral, 80, "withdraw");

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 3, "two flash loans + sweep");

        (, uint256 flash0, bytes memory cb0Data) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        (, uint256 flash1, bytes memory cb1Data) = abi.decode(_stripSelector(calls[1].data), (address, uint256, bytes));
        assertEq(flash0, 30, "chunk0 flash");
        assertEq(flash1, 30, "chunk1 flash");

        (uint256 repay0, uint256 repayShares0, uint256 withdraw0, uint256 redeem0) = _decodeChunk(cb0Data);
        (uint256 repay1, uint256 repayShares1, uint256 withdraw1, uint256 redeem1) = _decodeChunk(cb1Data);

        // Intermediate chunk: assets-based partial repay, withdraws only its redeem slice.
        assertEq(repay0, 30, "chunk0 repay assets");
        assertEq(repayShares0, 0, "chunk0 repays by assets");
        assertEq(redeem0, 30, "chunk0 redeem");
        assertEq(withdraw0, 30, "chunk0 withdraw == redeem slice");

        // Final chunk of a partial deleverage still repays by ASSETS (target loan != 0 -> no shares=max).
        assertEq(repay1, 30, "final chunk repay assets (not shares=max)");
        assertEq(repayShares1, 0, "final chunk does not use shares=max for partial exit");
        assertEq(redeem1, 30, "final chunk redeem");
        assertEq(withdraw1, 50, "final chunk withdraws remaining target collateral");

        assertEq(withdraw0 + withdraw1, 80, "withdraws reconstruct target");
        assertEq(redeem0 + redeem1, 60, "redeems sum to single-shot redeem");
    }

    function test_getBundleCalls_splitDeleverage_flatFeePullsExtraCollateralWhenLoopsExceedEquityHeadroom() external {
        // Case B: a flat redemption fee makes the looped path redeem MORE than the single-shot plan (one flat
        // fee per chunk). With the withdraw budget sized to the single-shot redeem (no equity headroom), the
        // summed per-chunk redeems exceed it. Rather than reverting (old behavior:
        // `InsufficientCollateralForRedeem(220, 210)`), the final loop now pulls the extra collateral needed to
        // fund the additional flat fee, leaving the user below target collateral by exactly that fee, and
        // re-checks LLTV on the resulting position.
        uint256 flatFee = 10;
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", 2), abi.encode(uint32(0), flatFee));

        // Position: loan 250, collateral 300. Target: loan 50, collateral 90 -> repay 200, withdraw 210.
        morpho.setPosition(marketId, OWNER, uint128(250), uint128(300));
        // Single-shot redeem of 210 shares nets 200 post-fee assets (210 gross - 10 flat).
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(210)),
            abi.encode(uint256(200), flatFee)
        );
        // Liquidity 100 forces two equal chunks (100, 100); each redeems 110 (100 repay + 10 flat) = 220 total.
        _setMorphoLoanLiquidity(100);

        UserIntent memory intent;
        intent.market = marketParams;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: 50, collateral: 90});

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _route());
        bundle.predicateMessage = _emptyPredicateMessage();
        assertEq(bundle.ma.repay, 200, "repay");
        assertEq(bundle.ma.withdrawCollateral, 210, "single-shot withdraw budget");
        assertEq(bundle.va.redeem, 210, "single-shot redeem (one flat fee), within budget so build passes");

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 3, "two flash loans + sweep (no revert)");

        (, uint256 flash0, bytes memory cb0Data) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        (, uint256 flash1, bytes memory cb1Data) = abi.decode(_stripSelector(calls[1].data), (address, uint256, bytes));
        assertEq(flash0, 100, "chunk0 flash == initial liquidity");
        assertEq(flash1, 100, "chunk1 flash == remainder");

        (uint256 repay0, uint256 repayShares0, uint256 withdraw0, uint256 redeem0) = _decodeChunk(cb0Data);
        (uint256 repay1, uint256 repayShares1, uint256 withdraw1, uint256 redeem1) = _decodeChunk(cb1Data);

        // Partial exit (target loan != 0): both chunks repay by assets, each redeem inflated by its own flat fee.
        assertEq(repay0, 100, "chunk0 repay assets");
        assertEq(repayShares0, 0, "chunk0 repays by assets");
        assertEq(redeem0, 110, "chunk0 redeem == repay + flat fee");
        assertEq(withdraw0, 110, "chunk0 withdraw == redeem slice");

        assertEq(repay1, 100, "chunk1 repay assets");
        assertEq(repayShares1, 0, "chunk1 repays by assets");
        assertEq(redeem1, 110, "chunk1 redeem == repay + flat fee");
        assertEq(withdraw1, 110, "chunk1 withdraw == redeem slice (no equity left)");

        // Looped redeems pay the flat fee twice: 220 > the single-shot 210.
        assertEq(redeem0 + redeem1, 220, "looped redeem exceeds single-shot by one flat fee");
        // The extra fee is funded from collateral: total withdrawn (220) is 10 above the planned 210.
        assertEq(withdraw0 + withdraw1, 220, "extra collateral pulled to fund the extra flat fee");
        // User ends 10 collateral below the 90 target -> final collateral 80, loan 50 (LTV 0.625 <= LLTV 1.0).
        assertEq(300 - (withdraw0 + withdraw1), 80, "final collateral = target - extra flat fee");
    }

    function test_getBundleCalls_splitDeleverage_revertsWhenChunkWouldBurnZeroBorrowShares() external {
        // Skewed market: borrow assets far exceed borrow shares, so one borrow share is worth ~1e6 assets. A
        // flash-loan chunk below that threshold burns 0 borrow shares on Morpho, which divides by zero in the
        // adapter's share-price check. The builder must reject it up front with a clean domain error.
        morpho.setMarket(marketId, 10_000_000, 0, 10_000_000, 1, uint128(block.timestamp), 0);
        morpho.setPosition(marketId, OWNER, uint128(1), uint128(11));
        // Proceeds and the 11-share collateral cover the buffered repay/redeem (11).
        vm.mockCall(
            VAULT, abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(11)), abi.encode(uint256(11), 0)
        );
        // Liquidity of 1 is far below one borrow-share's worth (~1e6), so the first chunk burns 0 shares.
        _setMorphoLoanLiquidity(1);

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), _fullExitDeltaIntent(10, 11), _route());
        bundle.predicateMessage = _emptyPredicateMessage();

        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.LoopRepayBurnsZeroShares.selector, 1, 10_000_000, 1));
        this.callGetBundleCalls(bundle);
    }

    function test_getBundleCalls_splitDeleverage_revertsCleanlyWhenCumulativeWithdrawExceedsCollateral() external {
        // A flat fee per loop inflates each chunk's redeem, so cumulative intermediate withdrawals can pass the
        // available collateral before the final loop. With the Morpho oracle valuing collateral above the vault
        // rate (so the mid-loop LLTV checks pass), the builder reaches that over-withdraw and must fail with a
        // clean InsufficientCollateralForRedeem instead of underflowing `position.collateral - redeemed`.
        uint256 flatFee = 10;
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", 2), abi.encode(uint32(0), flatFee));
        // Oracle values collateral at 2x so the intermediate LLTV checks stay healthy and don't fire first.
        vm.mockCall(marketParams.oracle, abi.encodeWithSignature("price()"), abi.encode(ORACLE_PRICE_SCALE * 2));

        // Full exit: loan 620, collateral 635. Liquidity 40 forces greedy loops [40,80,160,320,...]; with a flat
        // fee per loop the intermediate redeems are [50,90,170,330] and cumulate to 640 > 635 on the 4th.
        morpho.setPosition(marketId, OWNER, uint128(620), uint128(635));
        // Proceeds (625) and the 635-share collateral cover the buffered repay/redeem (621 / 631).
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(635)),
            abi.encode(uint256(625), flatFee)
        );
        _setMorphoLoanLiquidity(40);

        UserIntent memory intent;
        intent.market = marketParams;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: 0, collateral: 0});

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _route());
        bundle.predicateMessage = _emptyPredicateMessage();

        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.InsufficientCollateralForRedeem.selector, 640, 635));
        this.callGetBundleCalls(bundle);
    }

    function test_getBundleCalls_deltaFullExit_singleShotUsesSharesMax() external {
        // A Delta full exit (repay all debt, withdraw all collateral) is normalized to a Target full exit at
        // build time, so even the single-shot path (ample liquidity, no looping) clears the debt via shares=max
        // instead of an assets-based repay that could leave borrow-share rounding dust.
        morpho.setPosition(marketId, OWNER, uint128(70), uint128(100));
        vm.mockCall(
            VAULT, abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(100)), abi.encode(uint256(100), 0)
        );
        // Default Morpho liquidity is ample, so this stays a single flash loan (no looping).

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), _fullExitDeltaIntent(70, 100), _route());
        bundle.predicateMessage = _emptyPredicateMessage();
        // The build normalizes the Delta full exit into a Target full exit.
        assertEq(uint8(bundle.intent.mode), uint8(PositionMode.Target), "delta full exit normalized to target");
        assertEq(bundle.intent.target.loan, 0, "target loan zeroed");

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 2, "single flash loan + sweep (no looping)");
        assertEq(_selector(calls[0].data), GeneralAdapter1.morphoFlashLoan.selector, "flash loan");

        (,, bytes memory cbData) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        (uint256 repay, uint256 repayShares,,) = _decodeChunk(cbData);
        assertEq(repay, 0, "single-shot full exit repays by shares=max");
        assertEq(repayShares, type(uint256).max, "single-shot clears debt via shares=max");
    }

    function test_getBundle_fullExit_thinEquity_buildsWithoutPhantomOwnerTopUp() external {
        // V5 regression. Modern unloop (assetAllowance = 0) full exit of a near-100%-leveraged position:
        // debt 100_000, all-collateral redeem nets 100_050 -> lands in [D_actual, D_buffer=100_100). Pre-fix the
        // +10bps full-repay buffer made `requiredRepayLoanAssets = 100_100 - 100_050 = 50`, so the build reverted
        // `OwnerLoanAssetsBelowRequired(0, 50)` even though `shares = max` would clear the real debt with the buffer
        // surplus flash-borrowed then returned. Post-fix owner-funding is sized off the un-buffered debt, so no pull.
        morpho.setPosition(marketId, OWNER, uint128(100_000), uint128(100_050));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(100_050)),
            abi.encode(uint256(100_050), uint256(0))
        );

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), _fullExitDeltaIntent(100_000, 100_050), _route());

        assertEq(bundle.ma.flashRepay, 100_100, "flashRepay carries the +10bps buffer for flash sizing");
        assertEq(bundle.ma.withdrawCollateral, 100_050, "withdraws all collateral");
        assertEq(bundle.va.pullAssets, 0, "no phantom owner top-up (sized off un-buffered debt)");
        // Redeem is capped at the withdrawn collateral instead of reverting; `shares = max` clears the real debt
        // and the buffer surplus is returned, so redeeming all collateral suffices.
        assertEq(bundle.va.redeem, 100_050, "redeem capped at withdrawn collateral");
        assertEq(_flashLoanAssets(bundle), 100_100, "flash loan stays buffered for accrual headroom");
        assertLt(
            bundle.va.redeem,
            _flashLoanAssets(bundle),
            "thin equity: redeem under buffered flash, covered by shares=max"
        );
    }

    function test_getBundle_fullExit_underwater_stillRequiresRealOwnerFunds() external {
        // Contrast to the thin-equity case: all-collateral redeem (99_900) is below the REAL debt (100_000), so the
        // position genuinely cannot self-fund the exit. Owner funds are legitimately required. Post-fix the pull is
        // the real gap (100_000 - 99_900 = 100), not the buffer-inflated gap (100_100 - 99_900 = 200).
        morpho.setPosition(marketId, OWNER, uint128(100_000), uint128(99_900));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(99_900)),
            abi.encode(uint256(99_900), uint256(0))
        );

        UserIntent memory intent;
        intent.market = marketParams;
        intent.assetAllowance = 0;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;

        // External call via the harness so `expectRevert` pairs with it (getBundle is an internal lib call).
        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.OwnerLoanAssetsBelowRequired.selector, 0, 100));
        harness.getTargetBundle(_context(), intent, _route(), 0, 0);
    }

    function test_getBundle_fullExit_fatEquity_redeemNotCapped() external {
        // Fat equity (collateral redeem 200_000 >> buffered debt 100_100): no owner pull and the redeem is sized to
        // the buffered flash (100_100), well within the withdrawn collateral, so the full-exit cap does not bind.
        // Documents that the fix leaves the healthy path unchanged.
        morpho.setPosition(marketId, OWNER, uint128(100_000), uint128(200_000));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(200_000)),
            abi.encode(uint256(200_000), uint256(0))
        );

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), _fullExitDeltaIntent(100_000, 200_000), _route());

        assertEq(bundle.va.pullAssets, 0, "no owner pull");
        assertEq(bundle.va.redeem, 100_100, "redeem sized to buffered flash, not capped");
        assertLt(bundle.va.redeem, bundle.ma.withdrawCollateral, "cap does not bind for fat equity");
    }

    function test_getBundle_debtOnlyKeepCollateralClose_emitsNoFlashLoan() external {
        // NEST-53 regression. A debt-only full close that KEEPS collateral (target.loan = 0,
        // target.collateral = current) funds the repay itself with no flash loan, so it stays independent of
        // Morpho liquidity. The +10bps accrual buffer still applies on this path, but the owner funds it directly
        // (pullAssets == buffered repay) rather than flash-borrowing it, so no flash loan is emitted; the unused
        // surplus sweeps back. Buffer of 100 = 100 + ceil(100 * 10 / 10000) = 101.
        morpho.setPosition(marketId, OWNER, uint128(100), uint128(200));

        UserIntent memory intent;
        intent.market = marketParams;
        intent.assetAllowance = type(uint256).max;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: 0, collateral: 200}); // keep all collateral

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _route());

        assertEq(bundle.ma.repay, 100, "repay stays the full real debt");
        assertEq(bundle.ma.withdrawCollateral, 0, "keeps collateral");
        assertEq(bundle.ma.flashRepay, 101, "flashRepay carries the +10bps accrual buffer");
        assertEq(bundle.va.pullAssets, 101, "owner funds the buffered repay directly");
        assertEq(bundle.va.redeem, 0, "no redeem leg");
        assertEq(_flashLoanAssets(bundle), 0, "buffer is owner-funded, so close is independent of Morpho liquidity");

        // Drain Morpho's loan-token balance to 0: the close must still build with no flash loan dependency.
        _setMorphoLoanLiquidity(0);
        bundle = BundleBuildLib.getBundle(_context(), intent, _route());
        assertEq(_flashLoanAssets(bundle), 0, "still no flash loan even with Morpho liquidity drained");
    }

    function test_getBundleCalls_splitDeleverage_staleFullExitBundleStillProgresses() external {
        // Build a full-exit bundle while the owner owes 30 (so bundle.ma.repay = 30), then let the live debt grow
        // to 100 before encoding (a stale bundle). The full-exit planner must ignore the stale repay target and
        // chew through the live debt at full liquidity each loop, rather than stalling once `remaining` hits 0.
        morpho.setPosition(marketId, OWNER, uint128(30), uint128(200));
        vm.mockCall(
            VAULT, abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(200)), abi.encode(uint256(200), 0)
        );

        UserIntent memory intent;
        intent.market = marketParams;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: 0, collateral: 0});

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _route());
        bundle.predicateMessage = _emptyPredicateMessage();
        assertEq(bundle.ma.flashRepay, 31, "stale buffered flashRepay target captured at build");

        // Live debt grows to 100 after the bundle was built; liquidity is only 20.
        morpho.setPosition(marketId, OWNER, uint128(100), uint128(200));
        _setMorphoLoanLiquidity(20);

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 4, "three flash loans + sweep (clears live debt, not the stale 30)");

        (, uint256 flash0,) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        (, uint256 flash1,) = abi.decode(_stripSelector(calls[1].data), (address, uint256, bytes));
        (, uint256 flash2,) = abi.decode(_stripSelector(calls[2].data), (address, uint256, bytes));
        assertEq(flash0, 20, "chunk0 == initial liquidity");
        assertEq(flash1, 40, "chunk1 == grown liquidity");
        assertEq(flash2, 41, "final == buffered live residual");
        assertEq(flash0 + flash1 + flash2, 101, "chunks clear buffered live debt, not the stale 30");
    }

    function test_getBundleCalls_instantRedeem_splitsDeleverageWhenLiquidityBelowRepay() external {
        // Same full-exit deleverage as the async split test (repay 70, withdraw 100, 1:1, no fee), but on the
        // instant-redeem route. The loop must engage for instant redeem and each chunk's redeem leg must dispatch
        // to nestInstantRedeem (not nestRequestAndRedeem), reusing the async loop machinery unchanged.
        morpho.setPosition(marketId, OWNER, uint128(70), uint128(100));
        // Build sizes the instant withdraw leg from previewInstantRedeem and checks instant-redeem liquidity.
        vm.mockCall(
            VAULT, abi.encodeWithSignature("previewInstantRedeem(uint256)", uint256(100)), abi.encode(uint256(100), 0)
        );
        _setInstantRedeemLiquidity(type(uint256).max);
        // Morpho holds only 40 of the 70 needed -> must split into two sequential flash loans.
        _setMorphoLoanLiquidity(40);

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), _fullExitDeltaIntent(70, 100), _instantRoute());
        bundle.predicateMessage = _emptyPredicateMessage();
        assertEq(bundle.ma.flashRepay, 71, "flashRepay (70 + full-repay buffer)");
        assertEq(bundle.va.redeem, 71, "single-shot instant redeem (1:1, no fee)");
        assertEq(_flashLoanAssets(bundle), 71, "flash total");

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 3, "two flash loans + sweep");

        (, uint256 flash0, bytes memory cb0Data) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        (, uint256 flash1, bytes memory cb1Data) = abi.decode(_stripSelector(calls[1].data), (address, uint256, bytes));
        assertEq(flash0, 40, "chunk0 flash == initial liquidity");
        assertEq(flash1, 31, "chunk1 flash == buffered remainder");

        // The key assertion: each looped chunk redeems through the instant adapter leg, not the async one.
        assertEq(_chunkRedeemSelector(cb0Data), NestAdapter.nestInstantRedeem.selector, "chunk0 instant redeem leg");
        assertEq(_chunkRedeemSelector(cb1Data), NestAdapter.nestInstantRedeem.selector, "chunk1 instant redeem leg");

        (uint256 repay0, uint256 repayShares0, uint256 withdraw0, uint256 redeem0) = _decodeInstantChunk(cb0Data);
        (uint256 repay1, uint256 repayShares1, uint256 withdraw1, uint256 redeem1) = _decodeInstantChunk(cb1Data);

        // Chunk 0: intermediate, assets-based partial repay; withdraws exactly its redeem slice.
        assertEq(repay0, 40, "chunk0 repay assets");
        assertEq(repayShares0, 0, "chunk0 repays by assets");
        assertEq(redeem0, 40, "chunk0 redeem (no fee, 1:1)");
        assertEq(withdraw0, 40, "chunk0 withdraw == redeem");

        // Chunk 1: final chunk of a full exit; clears the residual debt via shares=max (Delta full exit is
        // normalized to a Target full exit at build), and withdraws the remaining collateral.
        assertEq(repay1, 0, "chunk1 full-exit repays by shares=max");
        assertEq(repayShares1, type(uint256).max, "chunk1 clears residual via shares=max");
        assertEq(redeem1, 31, "chunk1 redeem");
        assertEq(withdraw1, 60, "chunk1 withdraw == remaining target collateral");

        assertEq(withdraw0 + withdraw1, 100, "withdraws reconstruct target");
        assertEq(redeem0 + redeem1, 71, "redeems sum to buffered single-shot redeem");
    }

    function test_getBundleCalls_instantRedeem_splitUsesInstantFeeNotRedemptionFee() external {
        // Proves the looped path sizes each chunk against the INSTANT redemption fee (Fees enum 0), not the async
        // Redemption fee (enum 2). The instant fee is a flat 10; the async fee is left at 0. If the loop wrongly
        // used the async fee, each chunk would redeem 100 (its repay); using the instant fee it redeems 110.
        uint256 instantFlatFee = 10;
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", 0), abi.encode(uint32(0), instantFlatFee));
        // Async Redemption fee (enum 2) stays at the setUp default of zero.

        // Partial exit: loan 250, collateral 300 -> target loan 50, collateral 90 => repay 200, withdraw 210.
        morpho.setPosition(marketId, OWNER, uint128(250), uint128(300));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewInstantRedeem(uint256)", uint256(210)),
            abi.encode(uint256(200), instantFlatFee)
        );
        _setInstantRedeemLiquidity(type(uint256).max);
        // Liquidity 100 forces two equal chunks (100, 100); each redeems 110 (100 repay + 10 instant flat fee).
        _setMorphoLoanLiquidity(100);

        UserIntent memory intent;
        intent.market = marketParams;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: 50, collateral: 90});

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _instantRoute());
        bundle.predicateMessage = _emptyPredicateMessage();
        assertEq(bundle.ma.repay, 200, "repay");
        assertEq(bundle.va.redeem, 210, "single-shot instant redeem (one instant flat fee)");

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 3, "two flash loans + sweep");

        (,, bytes memory cb0Data) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        (,, bytes memory cb1Data) = abi.decode(_stripSelector(calls[1].data), (address, uint256, bytes));
        assertEq(_chunkRedeemSelector(cb0Data), NestAdapter.nestInstantRedeem.selector, "chunk0 instant redeem leg");
        assertEq(_chunkRedeemSelector(cb1Data), NestAdapter.nestInstantRedeem.selector, "chunk1 instant redeem leg");

        (, uint256 repayShares0, uint256 withdraw0, uint256 redeem0) = _decodeInstantChunk(cb0Data);
        (, uint256 repayShares1, uint256 withdraw1, uint256 redeem1) = _decodeInstantChunk(cb1Data);

        // Each chunk's redeem is inflated by the instant flat fee (110 = 100 repay + 10). If the loop used the
        // async Redemption fee (0), these would be 100. This is the discriminating assertion.
        assertEq(redeem0, 110, "chunk0 redeem == repay + instant flat fee");
        assertEq(redeem1, 110, "chunk1 redeem == repay + instant flat fee");
        // Partial exit (target loan != 0): both chunks repay by assets, no shares=max.
        assertEq(repayShares0, 0, "chunk0 repays by assets");
        assertEq(repayShares1, 0, "chunk1 repays by assets (partial exit, not shares=max)");
        // Extra flat fee funded from collateral: looped redeem 220 > single-shot 210.
        assertEq(redeem0 + redeem1, 220, "looped redeem pays the instant flat fee per chunk");
        assertEq(withdraw0 + withdraw1, 220, "extra collateral pulled to fund the extra instant flat fee");
    }

    function test_getBundle_instantRedeem_buildRejectsWhenInstantLiquidityBelowSingleShotRedeem() external {
        // The aggregate instant-redeem-liquidity check runs at BUILD time on the single-shot redeem, before any
        // looping decision (this reverts inside getBundle, never reaching getBundleCalls). So even when low Morpho
        // liquidity would trigger the loop, an instant redeem whose single-shot size exceeds the vault's
        // instant-redeem buffer is rejected up front rather than producing looped calls. The single-shot aggregate
        // is the binding instant constraint because instant recycles its fee back into the buffer each loop — see
        // test_getBundleCalls_instantRedeem_loopedNotRejectedByGrossSumBuffer.
        morpho.setPosition(marketId, OWNER, uint128(70), uint128(100));
        vm.mockCall(
            VAULT, abi.encodeWithSignature("previewInstantRedeem(uint256)", uint256(100)), abi.encode(uint256(100), 0)
        );
        // Instant-redeem buffer (50) is below the 71-share buffered redeem the full exit needs.
        _setInstantRedeemLiquidity(50);
        _setMorphoLoanLiquidity(40); // would otherwise force the loop

        UserIntent memory intent;
        intent.market = marketParams;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: 0, collateral: 0});

        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.InsufficientRedeemLiquidity.selector, 71, 50));
        harness.getTargetBundle(_context(), intent, _instantRoute(), 0, 0);
    }

    function test_getBundleCalls_instantRedeem_singleShotWhenLiquidityAmple() external {
        // With ample Morpho liquidity the instant route does NOT loop: one flash loan + sweep, with the redeem leg
        // dispatched to nestInstantRedeem and the full exit cleared via shares=max. Regression coverage that the
        // relaxed `_canLoop` gate does not perturb the single-shot instant path.
        morpho.setPosition(marketId, OWNER, uint128(70), uint128(100));
        vm.mockCall(
            VAULT, abi.encodeWithSignature("previewInstantRedeem(uint256)", uint256(100)), abi.encode(uint256(100), 0)
        );
        _setInstantRedeemLiquidity(type(uint256).max);
        // Default Morpho liquidity is ample (type(uint256).max), so no looping.

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), _fullExitDeltaIntent(70, 100), _instantRoute());
        bundle.predicateMessage = _emptyPredicateMessage();

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 2, "single flash loan + sweep (no looping)");
        assertEq(_selector(calls[0].data), GeneralAdapter1.morphoFlashLoan.selector, "flash loan");
        assertEq(_selector(calls[1].data), NestAdapter.adapterSweep.selector, "sweep");

        (,, bytes memory cbData) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        assertEq(_chunkRedeemSelector(cbData), NestAdapter.nestInstantRedeem.selector, "single-shot instant redeem leg");

        (uint256 repay, uint256 repayShares, uint256 withdraw, uint256 redeem) = _decodeInstantChunk(cbData);
        assertEq(repay, 0, "single-shot full exit repays by shares=max");
        assertEq(repayShares, type(uint256).max, "single-shot clears debt via shares=max");
        assertEq(redeem, 71, "single-shot instant redeem (buffered)");
        assertEq(withdraw, 100, "single-shot withdraws full collateral");
    }

    function test_getBundleCalls_instantRedeem_splitWithProportionalFee() external {
        // Instant route with a 1% PROPORTIONAL instant-redemption fee (Fees enum 0). Each looped chunk redeems more
        // shares than its repay, and the independently-computed post-fee proceeds still cover that chunk's flash
        // loan. Mirrors the async proportional-fee split test on the instant route + instant fee.
        uint32 feeRate = 10_000; // 1% proportional instant fee.
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", 0), abi.encode(feeRate, uint256(0)));

        morpho.setPosition(marketId, OWNER, uint128(70_000), uint128(100_000));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewInstantRedeem(uint256)", uint256(100_000)),
            abi.encode(uint256(99_000), uint256(1_000))
        );
        _setInstantRedeemLiquidity(type(uint256).max);
        _setMorphoLoanLiquidity(40_000);

        Bundle memory bundle =
            BundleBuildLib.getBundle(_context(), _fullExitDeltaIntent(70_000, 100_000), _instantRoute());
        bundle.predicateMessage = _emptyPredicateMessage();

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 3, "two flash loans + sweep");

        (, uint256 flash0, bytes memory cb0Data) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        (, uint256 flash1, bytes memory cb1Data) = abi.decode(_stripSelector(calls[1].data), (address, uint256, bytes));
        assertEq(flash0, 40_000, "chunk0 flash");
        assertEq(flash1, 30_030, "chunk1 flash (residual + full-repay buffer)");
        assertEq(_chunkRedeemSelector(cb0Data), NestAdapter.nestInstantRedeem.selector, "chunk0 instant redeem leg");
        assertEq(_chunkRedeemSelector(cb1Data), NestAdapter.nestInstantRedeem.selector, "chunk1 instant redeem leg");

        (,,, uint256 redeem0) = _decodeInstantChunk(cb0Data);
        (,,, uint256 redeem1) = _decodeInstantChunk(cb1Data);

        // Fee-aware: each chunk redeems MORE shares than its repay, and the post-fee proceeds (computed
        // independently from the vault's fee model) still cover that chunk's flash-loan repayment.
        assertGt(redeem0, flash0, "chunk0 redeem inflated for instant fee");
        assertGt(redeem1, flash1, "chunk1 redeem inflated for instant fee");
        assertGe(_postFeeAssets(redeem0, feeRate, 0), flash0, "chunk0 post-fee covers repay");
        assertGe(_postFeeAssets(redeem1, feeRate, 0), flash1, "chunk1 post-fee covers repay");
    }

    function test_getBundleCalls_instantRedeem_partialExitFinalChunkRepaysByAssets() external {
        // Instant route, partial deleverage to a NON-zero target loan (40): repay 60, withdraw 80 (1:1, no fee).
        // With only 30 liquidity it splits into two chunks; because the target loan is non-zero, the final chunk is
        // not a full exit, so it repays by ASSETS (no shares=max). Mirrors the async final-chunk-by-assets test.
        morpho.setPosition(marketId, OWNER, uint128(100), uint128(200));
        vm.mockCall(
            VAULT, abi.encodeWithSignature("previewInstantRedeem(uint256)", uint256(80)), abi.encode(uint256(80), 0)
        );
        _setInstantRedeemLiquidity(type(uint256).max);
        _setMorphoLoanLiquidity(30);

        UserIntent memory intent;
        intent.market = marketParams;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: 40, collateral: 120});

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _instantRoute());
        bundle.predicateMessage = _emptyPredicateMessage();
        assertEq(bundle.ma.repay, 60, "repay");

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 3, "two flash loans + sweep");

        (,, bytes memory cb0Data) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        (,, bytes memory cb1Data) = abi.decode(_stripSelector(calls[1].data), (address, uint256, bytes));
        assertEq(_chunkRedeemSelector(cb1Data), NestAdapter.nestInstantRedeem.selector, "final instant redeem leg");

        (uint256 repay0, uint256 repayShares0, uint256 withdraw0, uint256 redeem0) = _decodeInstantChunk(cb0Data);
        (uint256 repay1, uint256 repayShares1, uint256 withdraw1, uint256 redeem1) = _decodeInstantChunk(cb1Data);

        assertEq(repay0, 30, "chunk0 repay assets");
        assertEq(repayShares0, 0, "chunk0 repays by assets");
        assertEq(redeem0, 30, "chunk0 redeem");
        assertEq(withdraw0, 30, "chunk0 withdraw == redeem slice");

        // Final chunk of a partial deleverage repays by ASSETS (target loan != 0 -> no shares=max).
        assertEq(repay1, 30, "final chunk repay assets (not shares=max)");
        assertEq(repayShares1, 0, "final chunk does not use shares=max for partial exit");
        assertEq(redeem1, 30, "final chunk redeem");
        assertEq(withdraw1, 50, "final chunk withdraws remaining target collateral");
        assertEq(withdraw0 + withdraw1, 80, "withdraws reconstruct target");
        assertEq(redeem0 + redeem1, 60, "redeems sum to single-shot redeem");
    }

    function test_getBundleCalls_instantRedeem_acceptsTailChunkBelowAsyncFlatFeeCap() external {
        // Instant route, full exit, with a flat INSTANT redemption fee (enum 0). Liquidity one short of the repay
        // forces a tiny buffered tail chunk whose flat fee is far above the async FEE_CAP (20%) — runtime
        // executeInstantRedeem has no such cap (only rejects zero post-fee), so the looped builder must accept it.
        // The same shape on the async route reverts: see splitDeleverage_revertsWhenTailChunkTooSmallForFlatFee.
        uint256 flatFee = 10;
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", 0), abi.encode(uint32(0), flatFee));

        morpho.setPosition(marketId, OWNER, uint128(70_000), uint128(100_000));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewInstantRedeem(uint256)", uint256(100_000)),
            abi.encode(uint256(99_990), flatFee)
        );
        _setInstantRedeemLiquidity(type(uint256).max);
        _setMorphoLoanLiquidity(69_999);

        Bundle memory bundle =
            BundleBuildLib.getBundle(_context(), _fullExitDeltaIntent(70_000, 100_000), _instantRoute());
        bundle.predicateMessage = _emptyPredicateMessage();

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 3, "two flash loans + sweep");

        (, uint256 flash1, bytes memory cb1Data) = abi.decode(_stripSelector(calls[1].data), (address, uint256, bytes));
        assertEq(_chunkRedeemSelector(cb1Data), NestAdapter.nestInstantRedeem.selector, "tail chunk instant redeem leg");

        // Buffered 2-unit tail redeems 12 shares (2 + flat 10) at 1:1: flat fee is 10/12 of gross, >> FEE_CAP,
        // yet post-fee proceeds (2) still cover the tail repay — exactly the runtime-accept condition.
        (,,, uint256 redeem1) = _decodeInstantChunk(cb1Data);
        assertEq(flash1, 2, "tail flash (residual + full-repay buffer)");
        assertEq(redeem1, 12, "tail redeem grossed up for flat fee");
        assertGe(_postFeeAssets(redeem1, 0, flatFee), flash1, "tail post-fee covers repay");
    }

    function test_getBundleCalls_instantRedeem_fourChunksWhenLiquidityFarBelowRepay() external {
        // Instant route, full exit, Morpho holds only 10 against a buffered 71 repay; each repay returns its assets
        // so the loanable balance grows 10 -> 20 -> 40. The third chunk is clamped to 39 (leaving 1 asset of debt
        // for the final `shares = max` chunk), then the buffered final chunk clears the residual: 10/20/39/2. All
        // four redeem via the instant leg.
        morpho.setPosition(marketId, OWNER, uint128(70), uint128(100));
        vm.mockCall(
            VAULT, abi.encodeWithSignature("previewInstantRedeem(uint256)", uint256(100)), abi.encode(uint256(100), 0)
        );
        _setInstantRedeemLiquidity(type(uint256).max);
        _setMorphoLoanLiquidity(10);

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), _fullExitDeltaIntent(70, 100), _instantRoute());
        bundle.predicateMessage = _emptyPredicateMessage();

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 5, "four flash loans + sweep");

        (, uint256 flash0, bytes memory cb0Data) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        (, uint256 flash1, bytes memory cb1Data) = abi.decode(_stripSelector(calls[1].data), (address, uint256, bytes));
        (, uint256 flash2, bytes memory cb2Data) = abi.decode(_stripSelector(calls[2].data), (address, uint256, bytes));
        (, uint256 flash3, bytes memory cb3Data) = abi.decode(_stripSelector(calls[3].data), (address, uint256, bytes));
        assertEq(flash0, 10, "chunk0 flash == initial liquidity");
        assertEq(flash1, 20, "chunk1 flash == grown liquidity");
        assertEq(flash2, 39, "chunk2 flash == residual minus 1 (clamped)");
        assertEq(flash3, 2, "final flash == 1 residual + full-repay buffer");
        assertEq(_chunkRedeemSelector(cb0Data), NestAdapter.nestInstantRedeem.selector, "chunk0 instant redeem leg");
        assertEq(_chunkRedeemSelector(cb1Data), NestAdapter.nestInstantRedeem.selector, "chunk1 instant redeem leg");
        assertEq(_chunkRedeemSelector(cb2Data), NestAdapter.nestInstantRedeem.selector, "chunk2 instant redeem leg");
        assertEq(_chunkRedeemSelector(cb3Data), NestAdapter.nestInstantRedeem.selector, "chunk3 instant redeem leg");

        (,,, uint256 redeem0) = _decodeInstantChunk(cb0Data);
        (,,, uint256 redeem1) = _decodeInstantChunk(cb1Data);
        (,,, uint256 redeem2) = _decodeInstantChunk(cb2Data);
        (uint256 repay3, uint256 repayShares3,, uint256 redeem3) = _decodeInstantChunk(cb3Data);
        assertEq(redeem0 + redeem1 + redeem2 + redeem3, 71, "redeems sum to buffered single-shot redeem");
        assertEq(repay3, 0, "final chunk full-exit repays by shares=max");
        assertEq(repayShares3, type(uint256).max, "final chunk clears residual via shares=max");
    }

    function test_getBundleCalls_instantRedeem_loopedNotRejectedByGrossSumBuffer() external {
        // Instant redeem returns its fee to the share-token buffer each loop (executeInstantRedeem), so the buffer
        // only NET-drains by post-fee assets and the peak requirement equals the single-shot redeem that
        // BundleBuildLib already validated. The looped gross SUM (220, one flat fee per chunk) is therefore NOT the
        // binding constraint: with a buffer (215) that covers the single-shot aggregate (210) but is below the gross
        // sum, the instant bundle must still build (the gross-sum guard applies to async only, where fees are not
        // recycled to the buffer). Mirrors test_getBundleCalls_asyncRedeem_loopedRedeemSumExceedsBuffer, which
        // reverts under the same numbers.
        uint256 instantFlatFee = 10;
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", 0), abi.encode(uint32(0), instantFlatFee));

        morpho.setPosition(marketId, OWNER, uint128(250), uint128(300));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewInstantRedeem(uint256)", uint256(210)),
            abi.encode(uint256(200), instantFlatFee)
        );
        // Buffer 215: covers the single-shot aggregate (210) but is below the looped gross sum (220).
        _setInstantRedeemLiquidity(215);
        _setMorphoLoanLiquidity(100); // two chunks, each redeeming 110 -> 220 gross total

        UserIntent memory intent;
        intent.market = marketParams;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: 50, collateral: 90});

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _instantRoute());
        bundle.predicateMessage = _emptyPredicateMessage();
        assertEq(bundle.va.redeem, 210, "single-shot redeem passes build against buffer 215");

        // The looped instant build succeeds despite gross sum 220 > buffer 215: instant is not gated by the
        // gross-sum guard, and the per-loop fee recycling keeps the real peak (~210) within the buffer.
        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        assertEq(calls.length, 3, "two flash loans + sweep (instant looped, not rejected)");

        (,, bytes memory cb0Data) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        (,, bytes memory cb1Data) = abi.decode(_stripSelector(calls[1].data), (address, uint256, bytes));
        assertEq(_chunkRedeemSelector(cb0Data), NestAdapter.nestInstantRedeem.selector, "chunk0 instant redeem leg");
        (,,, uint256 redeem0) = _decodeInstantChunk(cb0Data);
        (,,, uint256 redeem1) = _decodeInstantChunk(cb1Data);
        assertEq(redeem0 + redeem1, 220, "looped gross sum exceeds buffer yet instant is allowed");
    }

    function test_getBundleCalls_instantRedeem_loopedPeakDrawExceedsBuffer_reverts() external {
        // V9 regression. With a fractional rate and zero fee there is no fee recycling, so per-chunk ceil rounding
        // makes the summed gross strictly exceed the single-shot gross. The single-shot build check passes, but the
        // looped peak draw exhausts the buffer mid-execution. The peak-aware instant guard must catch this at build.
        //
        // rate = 1.5 assets/share, zero instant fee (default). repay 60 splits at liquidity 35 into chunks [35, 25]:
        //   single-shot redeem = ceil(60/1.5) = 40 shares; gross = floor(40*1.5) = 60  -> fits buffer 60 (passes build)
        //   chunk0 redeem = ceil(35/1.5) = 24; gross = floor(24*1.5) = 36
        //   chunk1 redeem = ceil(25/1.5) = 17; gross = floor(17*1.5) = 25
        //   peak draw (zero fee, nothing recycles) = 36 + 25 = 61 > buffer 60  -> revert
        vm.mockCall(
            ACCOUNTANT,
            abi.encodeWithSignature("getRateInQuoteSafe(address)", marketParams.loanToken),
            abi.encode(uint256(1.5e18))
        );
        morpho.setPosition(marketId, OWNER, uint128(100), uint128(200));
        vm.mockCall(
            VAULT, abi.encodeWithSignature("previewInstantRedeem(uint256)", uint256(80)), abi.encode(uint256(120), 0)
        );
        // Buffer 60 assets: single-shot redeem (40 shares = 60 assets) fits, but the looped peak (61) does not.
        _setInstantRedeemLiquidity(60);
        _setMorphoLoanLiquidity(35); // uneven chunks [35, 25]

        UserIntent memory intent;
        intent.market = marketParams;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: 40, collateral: 120});

        // Build succeeds: the single-shot instant redeem (40 shares) is within the buffer's liquidity (40 shares).
        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _instantRoute());
        bundle.predicateMessage = _emptyPredicateMessage();
        assertEq(bundle.va.redeem, 40, "single-shot instant redeem passes build against buffer");

        // Looped peak draw 61 > buffer 60: the peak-aware guard rejects at build instead of reverting mid-execution.
        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.InsufficientRedeemLiquidity.selector, 61, 60));
        this.callGetBundleCalls(bundle);
    }

    function test_getBundleCalls_asyncRedeem_loopedRedeemSumExceedsBuffer() external {
        // The looped redeem-liquidity guard is route-agnostic: modern async redeems draw from the SAME share-token
        // buffer as instant (both go through safeExit -> exit). Async single-shot never build-checks that buffer, so
        // without the guard a looped async redeem whose summed redeem exceeds the buffer would revert at execution.
        // Here a flat Redemption fee (enum 2) makes the looped sum (220) exceed both the single-shot aggregate (210)
        // and a buffer of 215, and the builder rejects up front with InsufficientRedeemLiquidity.
        uint256 redemptionFlatFee = 10;
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", 2), abi.encode(uint32(0), redemptionFlatFee));

        morpho.setPosition(marketId, OWNER, uint128(250), uint128(300));
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", uint256(210)),
            abi.encode(uint256(200), redemptionFlatFee)
        );
        // Buffer 215: covers the single-shot aggregate (210) but is below the looped sum (220).
        _setInstantRedeemLiquidity(215);
        _setMorphoLoanLiquidity(100); // two chunks, each redeeming 110 -> 220 total

        UserIntent memory intent;
        intent.market = marketParams;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
        intent.target = Position({loan: 50, collateral: 90});

        // Build succeeds (async never checks the buffer; single-shot va.redeem 210 within the flat-fee cap).
        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _route());
        bundle.predicateMessage = _emptyPredicateMessage();
        assertEq(bundle.va.redeem, 210, "single-shot async redeem (one flat fee)");

        vm.expectRevert(abi.encodeWithSelector(NestBundleErrors.InsufficientRedeemLiquidity.selector, 220, 215));
        this.callGetBundleCalls(bundle);
    }

    /// @dev External wrapper around the internal library call so `vm.expectRevert` can match it.
    function callGetBundleCalls(Bundle memory bundle) external view returns (Call[] memory) {
        return BundleCalldataLib.getBundleCalls(bundle);
    }

    function _runScenario(Scenario memory s) internal {
        morpho.setPosition(marketId, OWNER, uint128(s.currentBorrow), uint128(s.currentCollateral));

        // Mock fee-aware redemption previews for 1:1 no-fee deleverage flows.
        if (s.expectedWithdrawCollateral > 0) {
            vm.mockCall(
                VAULT,
                abi.encodeWithSignature("previewFulfillRedeem(uint256)", s.expectedWithdrawCollateral),
                abi.encode(s.expectedWithdrawCollateral, uint256(0))
            );
        }
        if (s.expectedRedeem > 0) {
            vm.mockCall(
                VAULT,
                abi.encodeWithSignature("previewFulfillRedeem(uint256)", s.expectedRedeem),
                abi.encode(s.expectedRedeem, uint256(0))
            );
        }
        // Mock fee-aware mint preview for 1:1 no-fee leverage flows.
        if (s.expectedDeposit > 0) {
            vm.mockCall(
                VAULT, abi.encodeWithSignature("previewMint(uint256)", s.expectedDeposit), abi.encode(s.expectedDeposit)
            );
        }

        UserIntent memory intent;
        intent.market = marketParams;
        intent.assetAllowance = s.extraLoanAssets;
        intent.shareAllowance = s.extraCollateral;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;

        // Zero target vectors cannot encode target-mode disambiguation, so use equivalent delta mode.
        if (s.targetBorrow == 0 && s.targetCollateral == 0) {
            intent.mode = PositionMode.Delta;
            intent.delta = MarketActions({
                borrow: 0,
                repay: s.currentBorrow,
                flashRepay: 0,
                supplyCollateral: 0,
                withdrawCollateral: s.currentCollateral
            });
        } else {
            intent.mode = PositionMode.Target;
            intent.target = Position({loan: s.targetBorrow, collateral: s.targetCollateral});
        }
        if (s.shouldRevert) {
            vm.expectRevert(s.revertData);
            harness.getTargetBundle(_context(), intent, _route(), s.targetBorrow, s.targetCollateral);
            return;
        }

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _route());
        bundle.predicateMessage = _emptyPredicateMessage();
        _assertActions(s, bundle);

        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);
        _logScenarioCalls(s, bundle, calls);
        _assertCallsMatchNonZeroActions(s.name, bundle, calls);
    }

    // function _logBalances(BundleContext memory context) internal view {
    //     address owner = context.owner;
    //     address adapter = context.adapter;
    //     console.log("owner pUSD balance: ", _balanceOf(marketParams.loanToken, owner));
    //     console.log("owner collateral balance: ", _balanceOf(marketParams.collateralToken, owner));
    //     console.log("adapter pUSD balance: ", _balanceOf(marketParams.loanToken, adapter));
    //     console.log("adapter collateral balance: ", _balanceOf(marketParams.collateralToken, adapter));
    // }

    function _logScenarioCalls(Scenario memory s, Bundle memory bundle, Call[] memory calls) internal pure {
        console.log("================================");
        console.log(string.concat("scenario: ", s.name));
        console.log(_positionLine("current", s.currentBorrow, s.currentCollateral));

        if (bundle.intent.mode == PositionMode.Target) {
            console.log(_positionLine("target", bundle.intent.target.loan, bundle.intent.target.collateral));
        } else {
            console.log(_deltaLine(bundle.intent.delta));
        }

        uint256 lineIndex;
        if (calls.length != 0 && _selector(calls[0].data) == GeneralAdapter1.morphoFlashLoan.selector) {
            console.log(_callSummary(lineIndex++, calls[0], bundle));
            (,, bytes memory callbackData) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));

            Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
            for (uint256 i; i < callbackBundle.length; ++i) {
                console.log(_callSummary(lineIndex++, callbackBundle[i], bundle));
            }

            for (uint256 i = 1; i < calls.length; ++i) {
                console.log(_callSummary(lineIndex++, calls[i], bundle));
            }
        } else {
            for (uint256 i; i < calls.length; ++i) {
                console.log(_callSummary(lineIndex++, calls[i], bundle));
            }
        }

        (uint256 finalLoan, uint256 finalCollateral) = _finalPosition(s, bundle);
        console.log(_positionLine("final", finalLoan, finalCollateral));
    }

    function _callSummary(uint256 idx, Call memory call_, Bundle memory bundle) internal pure returns (string memory) {
        string memory prefix = string.concat(Strings.toString(idx), " - ");
        bytes4 sel = _selector(call_.data);

        if (sel == GeneralAdapter1.morphoFlashLoan.selector) {
            (, uint256 assets,) = abi.decode(_stripSelector(call_.data), (address, uint256, bytes));
            return _appendUintField(string.concat(prefix, "morphoFlashLoan"), "assets", assets);
        }

        if (sel == GeneralAdapter1.erc20TransferFrom.selector) {
            (address token,, uint256 amount) = abi.decode(_stripSelector(call_.data), (address, address, uint256));
            string memory tokenKind =
                _tokenKind(token, bundle.intent.market.loanToken, bundle.intent.market.collateralToken);
            return _appendUintField(string.concat(prefix, "erc20TransferFrom ", tokenKind), "amount", amount);
        }

        if (sel == GeneralAdapter1.morphoRepay.selector) {
            (, uint256 assets, uint256 shares,,,) =
                abi.decode(_stripSelector(call_.data), (MarketParams, uint256, uint256, uint256, address, bytes));
            string memory line = string.concat(prefix, "morphoRepay");
            line = _appendIfNonZero(line, "assets", assets);
            line = _appendIfNonZero(line, "shares", shares);
            return line;
        }

        if (sel == MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector) {
            (, uint256 assets,,) = abi.decode(_stripSelector(call_.data), (MarketParams, uint256, address, address));
            return _appendUintField(string.concat(prefix, "morphoWithdrawCollateralOnBehalf"), "assets", assets);
        }

        if (sel == NestAdapter.nestPredicateMint.selector) {
            (,, uint256 shares,,,) =
                abi.decode(_stripSelector(call_.data), (address, address, uint256, uint256, address, PredicateMessage));
            return _appendUintField(string.concat(prefix, "nestPredicateMint"), "shares", shares);
        }

        if (sel == NestAdapter.nestPredicateDeposit.selector) {
            (,, uint256 assets,,,) =
                abi.decode(_stripSelector(call_.data), (address, address, uint256, uint256, address, PredicateMessage));
            return _appendUintField(string.concat(prefix, "nestPredicateDeposit"), "assets", assets);
        }

        if (sel == NestAdapter.tellerPredicateDeposit.selector) {
            (,, uint256 assets, uint256 minimumMint,,,) = abi.decode(
                _stripSelector(call_.data), (address, address, uint256, uint256, address, address, PredicateMessage)
            );
            string memory line = _appendUintField(string.concat(prefix, "tellerPredicateDeposit"), "assets", assets);
            return _appendIfNonZero(line, "minimumMint", minimumMint);
        }

        if (sel == GeneralAdapter1.morphoSupplyCollateral.selector) {
            (, uint256 assets,,) = abi.decode(_stripSelector(call_.data), (MarketParams, uint256, address, bytes));
            return _appendUintField(string.concat(prefix, "morphoSupplyCollateral"), "assets", assets);
        }

        if (sel == MorphoAdapter.morphoBorrowOnBehalf.selector) {
            (, uint256 assets, uint256 shares,,,) =
                abi.decode(_stripSelector(call_.data), (MarketParams, uint256, uint256, uint256, address, address));
            string memory line = string.concat(prefix, "morphoBorrowOnBehalf");
            line = _appendIfNonZero(line, "assets", assets);
            line = _appendIfNonZero(line, "shares", shares);
            return line;
        }

        if (sel == NestAdapter.nestRequestAndRedeem.selector) {
            (, uint256 shares,,,,) =
                abi.decode(_stripSelector(call_.data), (address, uint256, uint256, address, address, address));
            return _appendUintField(string.concat(prefix, "nestRequestAndRedeem"), "shares", shares);
        }

        if (sel == NestAdapter.nestInstantRedeem.selector) {
            (, uint256 shares,,,) =
                abi.decode(_stripSelector(call_.data), (address, uint256, uint256, address, address));
            return _appendUintField(string.concat(prefix, "nestInstantRedeem"), "shares", shares);
        }

        if (sel == NestAdapter.atomicSolverRedeemSolve.selector) {
            (,,,,,, uint256 assets, uint256 minAssets) = abi.decode(
                _stripSelector(call_.data),
                (address, address, address, MarketParams, address, address, uint256, uint256)
            );
            string memory line = _appendUintField(string.concat(prefix, "atomicSolverRedeemSolve"), "assets", assets);
            return _appendIfNonZero(line, "minAssets", minAssets);
        }

        if (sel == NestAdapter.adapterSweep.selector) {
            return string.concat(prefix, "adapterSweep");
        }

        return string.concat(prefix, "unknownSelector");
    }

    function _positionLine(string memory label, uint256 loan, uint256 collateral)
        internal
        pure
        returns (string memory)
    {
        return string.concat(label, ": loan ", Strings.toString(loan), " collateral ", Strings.toString(collateral));
    }

    function _deltaLine(MarketActions memory delta) internal pure returns (string memory line) {
        line = "delta:";
        line = _appendIfNonZero(line, "borrow", delta.borrow);
        line = _appendIfNonZero(line, "repay", delta.repay);
        line = _appendIfNonZero(line, "supplyCollateral", delta.supplyCollateral);
        line = _appendIfNonZero(line, "withdrawCollateral", delta.withdrawCollateral);
    }

    function _finalPosition(Scenario memory s, Bundle memory bundle) internal pure returns (uint256, uint256) {
        if (bundle.intent.mode == PositionMode.Target) {
            return (bundle.intent.target.loan, bundle.intent.target.collateral);
        }

        MarketActions memory d = bundle.intent.delta;
        uint256 loanBeforeRepay = s.currentBorrow + d.borrow;
        uint256 collateralBeforeWithdraw = s.currentCollateral + d.supplyCollateral;

        uint256 finalLoan = d.repay > loanBeforeRepay ? 0 : loanBeforeRepay - d.repay;
        uint256 finalCollateral =
            d.withdrawCollateral > collateralBeforeWithdraw ? 0 : collateralBeforeWithdraw - d.withdrawCollateral;

        return (finalLoan, finalCollateral);
    }

    function _tokenKind(address token, address loanToken, address collateralToken)
        internal
        pure
        returns (string memory)
    {
        if (token == loanToken) return "asset";
        if (token == collateralToken) return "share";
        return "token";
    }

    function _appendIfNonZero(string memory line, string memory label, uint256 value)
        internal
        pure
        returns (string memory)
    {
        if (value == 0) return line;
        return _appendUintField(line, label, value);
    }

    function _appendUintField(string memory line, string memory label, uint256 value)
        internal
        pure
        returns (string memory)
    {
        return string.concat(line, " ", label, " ", Strings.toString(value));
    }

    function _assertActions(Scenario memory s, Bundle memory bundle) internal pure {
        assertEq(_flashLoanAssets(bundle), s.expectedFlashLoan, string.concat(s.name, " market.flashLoan mismatch"));
        assertEq(bundle.ma.repay, s.expectedRepay, string.concat(s.name, " market.repay mismatch"));
        assertEq(bundle.ma.borrow, s.expectedBorrow, string.concat(s.name, " market.borrow mismatch"));
        assertEq(
            bundle.ma.withdrawCollateral,
            s.expectedWithdrawCollateral,
            string.concat(s.name, " market.withdrawCollateral mismatch")
        );
        assertEq(
            bundle.ma.supplyCollateral,
            s.expectedSupplyCollateral,
            string.concat(s.name, " market.supplyCollateral mismatch")
        );
        assertEq(bundle.va.deposit, s.expectedDeposit, string.concat(s.name, " vault.deposit mismatch"));
        assertEq(bundle.va.redeem, s.expectedRedeem, string.concat(s.name, " vault.redeem mismatch"));
    }

    function _assertCallsMatchNonZeroActions(string memory scenarioName, Bundle memory bundle, Call[] memory calls)
        internal
        view
    {
        bytes4[] memory expectedSelectors = _expectedActionSelectors(bundle);

        if (_flashLoanAssets(bundle) == 0) {
            assertEq(
                calls.length, expectedSelectors.length + 1, string.concat(scenarioName, " direct calls length mismatch")
            );
            for (uint256 i; i < expectedSelectors.length; ++i) {
                assertEq(
                    _selector(calls[i].data),
                    expectedSelectors[i],
                    string.concat(scenarioName, " direct call selector mismatch")
                );
            }
            assertEq(
                _selector(calls[expectedSelectors.length].data),
                NestAdapter.adapterSweep.selector,
                string.concat(scenarioName, " direct sweep selector mismatch")
            );
            return;
        }

        assertEq(calls.length, 2, string.concat(scenarioName, " flashloan outer calls length mismatch"));
        assertEq(
            _selector(calls[0].data),
            GeneralAdapter1.morphoFlashLoan.selector,
            string.concat(scenarioName, " outer call is not morphoFlashLoan")
        );
        assertEq(
            _selector(calls[1].data),
            NestAdapter.adapterSweep.selector,
            string.concat(scenarioName, " outer sweep selector mismatch")
        );

        (address flashToken, uint256 flashAssets, bytes memory callbackData) =
            abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        assertEq(flashToken, marketParams.loanToken, string.concat(scenarioName, " flashloan token mismatch"));
        assertEq(flashAssets, _flashLoanAssets(bundle), string.concat(scenarioName, " flashloan assets mismatch"));
        assertEq(calls[0].callbackHash, keccak256(callbackData), string.concat(scenarioName, " callback hash mismatch"));

        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
        assertEq(
            callbackBundle.length,
            expectedSelectors.length,
            string.concat(scenarioName, " callback calls length mismatch")
        );

        for (uint256 i; i < expectedSelectors.length; ++i) {
            assertEq(
                _selector(callbackBundle[i].data),
                expectedSelectors[i],
                string.concat(scenarioName, " callback selector mismatch")
            );
        }
    }

    function _expectedActionSelectors(Bundle memory bundle) internal pure returns (bytes4[] memory selectors) {
        uint256 callbackLength = _countTrue(bundle.va.pullAssets != 0) + _countTrue(bundle.va.pullShares != 0)
            + _countTrue(bundle.ma.repay != 0) + _countTrue(bundle.ma.withdrawCollateral != 0)
            + _countTrue(bundle.va.deposit != 0) + _countTrue(bundle.ma.supplyCollateral != 0)
            + _countTrue(bundle.ma.borrow != 0) + _countTrue(bundle.va.redeem != 0);

        selectors = new bytes4[](callbackLength);
        uint256 i;

        if (bundle.va.pullAssets != 0) {
            selectors[i++] = GeneralAdapter1.erc20TransferFrom.selector;
        }
        if (bundle.va.pullShares != 0) {
            selectors[i++] = GeneralAdapter1.erc20TransferFrom.selector;
        }
        if (bundle.ma.repay != 0) {
            selectors[i++] = GeneralAdapter1.morphoRepay.selector;
        }
        if (bundle.ma.withdrawCollateral != 0) {
            selectors[i++] = MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector;
        }
        if (bundle.va.deposit != 0) {
            selectors[i++] = bundle.route.legacyDeposit
                ? NestAdapter.tellerPredicateDeposit.selector
                : NestAdapter.nestPredicateMint.selector;
        }
        if (bundle.ma.supplyCollateral != 0) {
            selectors[i++] = GeneralAdapter1.morphoSupplyCollateral.selector;
        }
        if (bundle.ma.borrow != 0) {
            selectors[i++] = MorphoAdapter.morphoBorrowOnBehalf.selector;
        }
        if (bundle.va.redeem != 0) {
            if (bundle.route.instantRedeem) {
                selectors[i++] = NestAdapter.nestInstantRedeem.selector;
            } else {
                selectors[i++] = bundle.route.legacyRedemption
                    ? NestAdapter.atomicSolverRedeemSolve.selector
                    : NestAdapter.nestRequestAndRedeem.selector;
            }
        }
    }

    function _route() internal pure returns (RouteInput memory route) {
        route.legacyRedemption = false;
        route.legacyDeposit = false;
        route.instantRedeem = false;
    }

    /// @dev Modern instant-redeem route: deleverage funded by the vault's instant-redeem buffer.
    function _instantRoute() internal pure returns (RouteInput memory route) {
        route.legacyRedemption = false;
        route.legacyDeposit = false;
        route.instantRedeem = true;
    }

    function _context() internal view returns (BundleContext memory context) {
        context.morpho = IMorpho(address(morpho));
        context.adapter = ADAPTER;
        context.bundler = BUNDLER;
        context.vault = INestVaultCore(VAULT);
        context.teller = TELLER;
        context.predicateProxy = PREDICATE_PROXY;
        context.atomicSolver = ATOMIC_SOLVER;
        context.atomicQueue = ATOMIC_QUEUE;
        context.owner = OWNER;
        context.initiator = OWNER;
    }

    function _emptyPredicateMessage() internal pure returns (PredicateMessage memory predicateMessage) {
        predicateMessage = PredicateMessage({
            taskId: "", expireByTime: type(uint256).max, signerAddresses: new address[](0), signatures: new bytes[](0)
        });
    }

    function _marketParams() internal pure returns (MarketParams memory market) {
        market.loanToken = address(0x3001);
        market.collateralToken = address(0x3002);
        market.oracle = address(0x3003);
        market.irm = address(0x3004);
        market.lltv = 1e18;
    }

    function _importantScenarios() internal pure returns (Scenario[] memory scenarios) {
        scenarios = new Scenario[](12);

        scenarios[0] = Scenario({
            name: "decreaseColl_decreaseBorrow_increaseLev_extraAssets",
            currentCollateral: 100,
            currentBorrow: 40,
            targetCollateral: 50,
            targetBorrow: 30,
            extraLoanAssets: 20,
            extraCollateral: 0,
            expectedFlashLoan: 10,
            expectedRepay: 10,
            expectedBorrow: 0,
            expectedWithdrawCollateral: 50,
            expectedSupplyCollateral: 0,
            expectedDeposit: 0,
            expectedRedeem: 10,
            shouldRevert: false,
            revertData: bytes("")
        });

        scenarios[1] = Scenario({
            name: "decreaseColl_decreaseBorrow_increaseLev_extraShares",
            currentCollateral: 100,
            currentBorrow: 40,
            targetCollateral: 50,
            targetBorrow: 30,
            extraLoanAssets: 0,
            extraCollateral: 20,
            expectedFlashLoan: 10,
            expectedRepay: 10,
            expectedBorrow: 0,
            expectedWithdrawCollateral: 50,
            expectedSupplyCollateral: 0,
            expectedDeposit: 0,
            expectedRedeem: 10,
            shouldRevert: false,
            revertData: bytes("")
        });

        scenarios[2] = Scenario({
            name: "decreaseColl_decreaseBorrow_decreaseLev_extraShares",
            currentCollateral: 100,
            currentBorrow: 70,
            targetCollateral: 0,
            targetBorrow: 0,
            extraLoanAssets: 0,
            extraCollateral: 20,
            expectedFlashLoan: 71, // 70 + full-repay buffer
            expectedRepay: 70, // real debt; buffer lives in expectedFlashLoan
            expectedBorrow: 0,
            expectedWithdrawCollateral: 100,
            expectedSupplyCollateral: 0,
            expectedDeposit: 0,
            expectedRedeem: 71,
            shouldRevert: false,
            revertData: bytes("")
        });

        scenarios[3] = Scenario({
            name: "decreaseColl_decreaseBorrow_decreaseLev_extraAssets",
            currentCollateral: 100,
            currentBorrow: 70,
            targetCollateral: 0,
            targetBorrow: 0,
            extraLoanAssets: 20,
            extraCollateral: 0,
            expectedFlashLoan: 71, // 70 + full-repay buffer
            expectedRepay: 70, // real debt; buffer lives in expectedFlashLoan
            expectedBorrow: 0,
            expectedWithdrawCollateral: 100,
            expectedSupplyCollateral: 0,
            expectedDeposit: 0,
            expectedRedeem: 71,
            shouldRevert: false,
            revertData: bytes("")
        });

        scenarios[4] = Scenario({
            name: "increaseColl_increaseBorrow_increaseLev_extraAssets",
            currentCollateral: 20,
            currentBorrow: 10,
            targetCollateral: 100,
            targetBorrow: 70,
            extraLoanAssets: 20,
            extraCollateral: 0,
            expectedFlashLoan: 60,
            expectedRepay: 0,
            expectedBorrow: 60,
            expectedWithdrawCollateral: 0,
            expectedSupplyCollateral: 80,
            expectedDeposit: 80,
            expectedRedeem: 0,
            shouldRevert: false,
            revertData: bytes("")
        });

        scenarios[5] = Scenario({
            name: "increaseColl_increaseBorrow_increaseLev_extraShares",
            currentCollateral: 20,
            currentBorrow: 10,
            targetCollateral: 100,
            targetBorrow: 70,
            extraLoanAssets: 0,
            extraCollateral: 20,
            expectedFlashLoan: 60,
            expectedRepay: 0,
            expectedBorrow: 60,
            expectedWithdrawCollateral: 0,
            expectedSupplyCollateral: 80,
            expectedDeposit: 60,
            expectedRedeem: 0,
            shouldRevert: false,
            revertData: bytes("")
        });

        scenarios[6] = Scenario({
            name: "increaseColl_increaseBorrow_decreaseLev_extraAssets",
            currentCollateral: 20,
            currentBorrow: 10,
            targetCollateral: 100,
            targetBorrow: 20,
            extraLoanAssets: 70,
            extraCollateral: 0,
            expectedFlashLoan: 10,
            expectedRepay: 0,
            expectedBorrow: 10,
            expectedWithdrawCollateral: 0,
            expectedSupplyCollateral: 80,
            expectedDeposit: 80,
            expectedRedeem: 0,
            shouldRevert: false,
            revertData: bytes("")
        });

        scenarios[7] = Scenario({
            name: "increaseColl_increaseBorrow_decreaseLev_extraShares",
            currentCollateral: 20,
            currentBorrow: 10,
            targetCollateral: 100,
            targetBorrow: 20,
            extraLoanAssets: 0,
            extraCollateral: 70,
            expectedFlashLoan: 10,
            expectedRepay: 0,
            expectedBorrow: 10,
            expectedWithdrawCollateral: 0,
            expectedSupplyCollateral: 80,
            expectedDeposit: 10,
            expectedRedeem: 0,
            shouldRevert: false,
            revertData: bytes("")
        });

        scenarios[8] = Scenario({
            name: "increaseColl_decreaseBorrow_decreaseLev_extraAssets",
            currentCollateral: 80,
            currentBorrow: 40,
            targetCollateral: 100,
            targetBorrow: 20,
            extraLoanAssets: 40,
            extraCollateral: 0,
            expectedFlashLoan: 0,
            expectedRepay: 20,
            expectedBorrow: 0,
            expectedWithdrawCollateral: 0,
            expectedSupplyCollateral: 20,
            expectedDeposit: 20,
            expectedRedeem: 0,
            shouldRevert: false,
            revertData: bytes("")
        });

        scenarios[9] = Scenario({
            name: "increaseColl_decreaseBorrow_decreaseLev_extraShares",
            currentCollateral: 80,
            currentBorrow: 40,
            targetCollateral: 100,
            targetBorrow: 20,
            extraLoanAssets: 0,
            extraCollateral: 40,
            expectedFlashLoan: 0,
            expectedRepay: 0,
            expectedBorrow: 0,
            expectedWithdrawCollateral: 0,
            expectedSupplyCollateral: 0,
            expectedDeposit: 0,
            expectedRedeem: 0,
            shouldRevert: true,
            revertData: abi.encodeWithSelector(NestBundleErrors.OwnerLoanAssetsBelowRequired.selector, 0, 20)
        });

        scenarios[10] = Scenario({
            name: "decreaseColl_increaseBorrow_increaseLev_extraAssetsNotUsed",
            currentCollateral: 100,
            currentBorrow: 20,
            targetCollateral: 50,
            targetBorrow: 30,
            extraLoanAssets: 30,
            extraCollateral: 0,
            expectedFlashLoan: 0,
            expectedRepay: 0,
            expectedBorrow: 10,
            expectedWithdrawCollateral: 50,
            expectedSupplyCollateral: 0,
            expectedDeposit: 0,
            expectedRedeem: 0,
            shouldRevert: false,
            revertData: bytes("")
        });

        scenarios[11] = Scenario({
            name: "decreaseColl_increaseBorrow_increaseLev_extraSharesNotUsed",
            currentCollateral: 100,
            currentBorrow: 20,
            targetCollateral: 50,
            targetBorrow: 30,
            extraLoanAssets: 0,
            extraCollateral: 20,
            expectedFlashLoan: 0,
            expectedRepay: 0,
            expectedBorrow: 10,
            expectedWithdrawCollateral: 50,
            expectedSupplyCollateral: 0,
            expectedDeposit: 0,
            expectedRedeem: 0,
            shouldRevert: false,
            revertData: bytes("")
        });
    }

    function _countTrue(bool x) internal pure returns (uint256) {
        return x ? 1 : 0;
    }

    /// @dev Builds a full-exit delta intent (repay all borrow, withdraw all collateral) for split tests.
    function _fullExitDeltaIntent(uint256 borrow, uint256 collateral) internal view returns (UserIntent memory intent) {
        intent.market = marketParams;
        intent.assetAllowance = 0;
        intent.shareAllowance = 0;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Delta;
        intent.delta = MarketActions({
            borrow: 0, flashRepay: 0, repay: borrow, supplyCollateral: 0, withdrawCollateral: collateral
        });
    }

    /// @dev Overrides Morpho's mocked loan-token balance, the ceiling read when chunking flash loans.
    function _setMorphoLoanLiquidity(uint256 amount) internal {
        vm.mockCall(
            marketParams.loanToken, abi.encodeWithSignature("balanceOf(address)", address(morpho)), abi.encode(amount)
        );
    }

    /// @dev Sets the vault's instant-redeem liquidity (shares). `getInstantRedeemLiquidity` reads it as
    ///      `ERC20(asset).balanceOf(share)` converted at the vault rate, so at the 1:1 mocked rate the share
    ///      buffer equals `amount`. `vault.share()` is mocked to the collateral token in `setUp`.
    function _setInstantRedeemLiquidity(uint256 amount) internal {
        vm.mockCall(
            marketParams.loanToken,
            abi.encodeWithSignature("balanceOf(address)", marketParams.collateralToken),
            abi.encode(amount)
        );
    }

    /// @dev Like `_decodeChunk`, but the redeem leg is `nestInstantRedeem` (5 args, no controller) rather than
    ///      `nestRequestAndRedeem` (6 args). Used by the instant-redeem looped-deleverage tests.
    function _decodeInstantChunk(bytes memory callbackData)
        internal
        pure
        returns (uint256 repayAssets, uint256 repayShares, uint256 withdrawCollateral, uint256 redeemShares)
    {
        Call[] memory cb = abi.decode(callbackData, (Call[]));
        (, repayAssets, repayShares,,,) =
            abi.decode(_stripSelector(cb[0].data), (MarketParams, uint256, uint256, uint256, address, bytes));
        (, withdrawCollateral,,) = abi.decode(_stripSelector(cb[1].data), (MarketParams, uint256, address, address));
        (, redeemShares,,,) = abi.decode(_stripSelector(cb[2].data), (address, uint256, uint256, address, address));
    }

    /// @dev Returns the selector of a flash-loan chunk's redeem leg (the 3rd callback call), so tests can prove
    ///      the looped path dispatched to the instant vs async redeem adapter.
    function _chunkRedeemSelector(bytes memory callbackData) internal pure returns (bytes4) {
        Call[] memory cb = abi.decode(callbackData, (Call[]));
        return _selector(cb[2].data);
    }

    /// @dev Decodes a single flash-loan chunk's callback into (repay assets, repay shares, withdraw, redeem).
    function _decodeChunk(bytes memory callbackData)
        internal
        pure
        returns (uint256 repayAssets, uint256 repayShares, uint256 withdrawCollateral, uint256 redeemShares)
    {
        Call[] memory cb = abi.decode(callbackData, (Call[]));
        (, repayAssets, repayShares,,,) =
            abi.decode(_stripSelector(cb[0].data), (MarketParams, uint256, uint256, uint256, address, bytes));
        (, withdrawCollateral,,) = abi.decode(_stripSelector(cb[1].data), (MarketParams, uint256, address, address));
        (, redeemShares,,,,) =
            abi.decode(_stripSelector(cb[2].data), (address, uint256, uint256, address, address, address));
    }

    /// @dev Independent reimplementation of the vault's post-fee redemption proceeds at a 1:1 share/asset rate:
    ///      `postFee = gross - flatFee - floor(gross * feeRate / 1e6)`.
    function _postFeeAssets(uint256 grossAssets, uint32 feeRate, uint256 flatFee) internal pure returns (uint256) {
        uint256 fee = flatFee + Math.mulDiv(grossAssets, feeRate, 1e6, Math.Rounding.Floor);
        return grossAssets > fee ? grossAssets - fee : 0;
    }

    function _selector(bytes memory data) internal pure returns (bytes4 sel) {
        require(data.length >= 4, "invalid data");
        assembly {
            sel := mload(add(data, 0x20))
        }
    }

    function _stripSelector(bytes memory data) internal pure returns (bytes memory stripped) {
        uint256 length = data.length;
        require(length >= 4, "invalid data");

        stripped = new bytes(length - 4);
        for (uint256 i; i < length - 4; ++i) {
            stripped[i] = data[i + 4];
        }
    }

    function _flashLoanAssets(Bundle memory bundle) internal pure returns (uint256) {
        uint256 requiredLoanAssets = bundle.ma.flashRepay + bundle.va.deposit;
        if (bundle.va.pullAssets >= requiredLoanAssets) return 0;
        return requiredLoanAssets - bundle.va.pullAssets;
    }
}
