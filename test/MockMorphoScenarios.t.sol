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
            delta: MarketActions({borrow: 0, repay: 0, supplyCollateral: 0, withdrawCollateral: 0})
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
            delta: MarketActions({borrow: 0, repay: 0, supplyCollateral: 0, withdrawCollateral: 0})
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
            delta: MarketActions({borrow: 0, repay: 20, supplyCollateral: 0, withdrawCollateral: 20})
        });

        Bundle memory bundle = BundleBuildLib.getBundle(_context(), intent, _route());
        bundle.predicateMessage = _emptyPredicateMessage();

        // The bundle must flash-loan 20 assets, but rounding up redeem shares makes the vault leg worth 21.
        uint256 flashLoanAssets = _flashLoanAssets(bundle);
        uint256 redeemedAssets = bundle.va.redeem.convertToAssets(INestVaultCore(VAULT), Math.Rounding.Floor);

        assertEq(bundle.ma.repay, 20, "repay mismatch");
        assertEq(bundle.ma.withdrawCollateral, 20, "withdraw mismatch");
        assertEq(flashLoanAssets, 20, "flash loan mismatch");
        assertEq(bundle.va.redeem, 14, "redeem shares mismatch");
        assertEq(redeemedAssets, 21, "redeem assets mismatch");
        assertGt(redeemedAssets, flashLoanAssets, "redeem should over-deliver loan assets");

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
            delta: MarketActions({borrow: 0, repay: 0, supplyCollateral: 0, withdrawCollateral: 0})
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
                borrow: 0, repay: s.currentBorrow, supplyCollateral: 0, withdrawCollateral: s.currentCollateral
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
            expectedFlashLoan: 70,
            expectedRepay: 70,
            expectedBorrow: 0,
            expectedWithdrawCollateral: 100,
            expectedSupplyCollateral: 0,
            expectedDeposit: 0,
            expectedRedeem: 70,
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
            expectedFlashLoan: 70,
            expectedRepay: 70,
            expectedBorrow: 0,
            expectedWithdrawCollateral: 100,
            expectedSupplyCollateral: 0,
            expectedDeposit: 0,
            expectedRedeem: 70,
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
        uint256 requiredLoanAssets = bundle.ma.repay + bundle.va.deposit;
        if (bundle.va.pullAssets >= requiredLoanAssets) return 0;
        return requiredLoanAssets - bundle.va.pullAssets;
    }
}
