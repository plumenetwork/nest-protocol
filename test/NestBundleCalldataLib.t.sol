// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {Call} from "contracts/vendor/bundler3/interfaces/IBundler3.sol";
import {IMorpho, MarketParams} from "@morpho/interfaces/IMorpho.sol";
import {PredicateMessage} from "@predicate/src/interfaces/IPredicateClient.sol";
import {GeneralAdapter1} from "contracts/vendor/morpho/GeneralAdapter1.sol";
import {NestAdapter} from "contracts/morpho/NestAdapter.sol";
import {MorphoAdapter} from "contracts/morpho/MorphoAdapter.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {
    Bundle,
    BundleContext,
    MarketActions,
    PositionMode,
    RouteInput,
    Position,
    UserIntent
} from "contracts/morpho/types/BundleTypes.sol";
import {BundleCalldataLib} from "contracts/morpho/libraries/BundleCalldataLib.sol";

contract NestBundleCalldataHarness {
    function getBundleCalls(Bundle memory bundle) external view returns (Call[] memory calls) {
        return BundleCalldataLib.getBundleCalls(bundle);
    }

    function nestDeposit(Bundle memory bundle) external pure returns (Call memory) {
        return BundleCalldataLib.nestDeposit(bundle);
    }

    function morphoWithdrawCollateralOnBehalf(Bundle memory bundle) external pure returns (Call memory) {
        return BundleCalldataLib.morphoWithdrawCollateralOnBehalf(bundle);
    }

    function nestRedeem(Bundle memory bundle) external view returns (Call memory) {
        return BundleCalldataLib.nestRedeem(bundle);
    }

    function morphoRepay(Bundle memory bundle) external pure returns (Call memory) {
        return BundleCalldataLib.morphoRepay(bundle);
    }
}

contract BundleCalldataLibTest is Test {
    address internal constant ADAPTER = address(0x2001);
    address internal constant BUNDLER = address(0x2002);
    address internal constant VAULT = address(0x2003);
    address internal constant TELLER = address(0x2004);
    address internal constant PREDICATE_PROXY = address(0x2005);
    address internal constant ATOMIC_SOLVER = address(0x2006);
    address internal constant ATOMIC_QUEUE = address(0x2007);

    address internal constant OWNER = address(0x1001);
    address internal constant ALT_INITIATOR = address(0x1002);

    NestBundleCalldataHarness internal harness;

    function setUp() external {
        harness = new NestBundleCalldataHarness();
    }

    function test_getBundleCalls_returnsEmptyWhenNoActions() external view {
        Bundle memory bundle = _bundle();
        Call[] memory calls = harness.getBundleCalls(bundle);
        assertEq(calls.length, 0);
    }

    function test_getBundleCalls_withoutFlashLoan_returnsOrderedCallbackCalls() external view {
        Bundle memory bundle = _bundle();
        bundle.va.pullAssets = 8;
        bundle.va.pullShares = 2;
        bundle.ma.repay = 3;
        bundle.ma.withdrawCollateral = 4;
        bundle.va.deposit = 5;
        bundle.ma.supplyCollateral = 6;
        bundle.ma.borrow = 7;
        bundle.va.redeem = 8;

        Call[] memory calls = harness.getBundleCalls(bundle);
        assertEq(calls.length, 9);

        assertEq(_selector(calls[0].data), GeneralAdapter1.erc20TransferFrom.selector);
        assertEq(_selector(calls[1].data), GeneralAdapter1.erc20TransferFrom.selector);
        assertEq(_selector(calls[2].data), GeneralAdapter1.morphoRepay.selector);
        assertEq(_selector(calls[3].data), MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector);
        assertEq(_selector(calls[4].data), NestAdapter.nestPredicateMint.selector);
        assertEq(_selector(calls[5].data), GeneralAdapter1.morphoSupplyCollateral.selector);
        assertEq(_selector(calls[6].data), MorphoAdapter.morphoBorrowOnBehalf.selector);
        assertEq(_selector(calls[7].data), NestAdapter.nestRequestAndRedeem.selector);
        assertEq(_selector(calls[8].data), NestAdapter.adapterSweep.selector);
    }

    function test_getBundleCalls_withFlashLoan_wrapsCallbackBundle() external view {
        Bundle memory bundle = _bundle();
        bundle.va.deposit = 10;
        bundle.ma.borrow = 5;

        Call[] memory calls = harness.getBundleCalls(bundle);
        assertEq(calls.length, 2);
        assertEq(_selector(calls[0].data), GeneralAdapter1.morphoFlashLoan.selector);
        assertEq(_selector(calls[1].data), NestAdapter.adapterSweep.selector);

        (address token, uint256 assets, bytes memory callbackData) =
            abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        assertEq(token, bundle.intent.market.loanToken);
        assertEq(assets, 10);
        assertEq(calls[0].callbackHash, keccak256(callbackData));

        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
        assertEq(callbackBundle.length, 2);
        assertEq(_selector(callbackBundle[0].data), NestAdapter.nestPredicateMint.selector);
        assertEq(_selector(callbackBundle[1].data), MorphoAdapter.morphoBorrowOnBehalf.selector);
    }

    function test_nestDeposit_routesByLegacyDepositFlag() external view {
        Bundle memory bundle = _bundle();

        Call memory modernRoute = harness.nestDeposit(bundle);
        assertEq(_selector(modernRoute.data), NestAdapter.nestPredicateMint.selector);

        bundle.route.legacyDeposit = true;
        Call memory legacyRoute = harness.nestDeposit(bundle);
        assertEq(_selector(legacyRoute.data), NestAdapter.tellerPredicateDeposit.selector);
    }

    function test_nestDeposit_legacyFractionalRate_usesPlannedMintForMinimumMint() external view {
        Bundle memory bundle = _bundle();
        bundle.route.legacyDeposit = true;
        bundle.va.mint = 3;
        bundle.va.deposit = 5;
        bundle.intent.maxSharePriceE27 = 1.5e27;

        Call memory legacyRoute = harness.nestDeposit(bundle);
        (
            address predicateProxy,
            address asset,
            uint256 assets,
            uint256 minimumMint,
            address receiver,
            address teller,
        ) = abi.decode(
            _stripSelector(legacyRoute.data), (address, address, uint256, uint256, address, address, PredicateMessage)
        );

        uint256 doubleRoundedMinimumMint =
            Math.mulDiv(bundle.va.deposit, 1e27, bundle.intent.maxSharePriceE27, Math.Rounding.Ceil);

        assertEq(predicateProxy, PREDICATE_PROXY);
        assertEq(asset, bundle.intent.market.loanToken);
        assertEq(assets, 5);
        assertEq(doubleRoundedMinimumMint, 4, "fractional legacy route previously double-rounded to D + 1");
        assertEq(minimumMint, bundle.va.mint, "legacy teller must enforce the planned share target");
        assertEq(receiver, ADAPTER);
        assertEq(teller, TELLER);
    }

    function test_morphoWithdrawCollateralOnBehalf_setsReceiverByLegacyFlag() external view {
        Bundle memory bundle = _bundle();
        bundle.ma.withdrawCollateral = 55;

        Call memory modernRoute = harness.morphoWithdrawCollateralOnBehalf(bundle);
        (MarketParams memory marketA, uint256 assetsA, address ownerA, address receiverA) =
            abi.decode(_stripSelector(modernRoute.data), (MarketParams, uint256, address, address));
        assertEq(marketA.loanToken, bundle.intent.market.loanToken);
        assertEq(assetsA, 55);
        assertEq(ownerA, OWNER);
        assertEq(receiverA, ADAPTER);

        bundle.route.legacyRedemption = true;
        Call memory legacyRoute = harness.morphoWithdrawCollateralOnBehalf(bundle);
        (,, address ownerB, address receiverB) =
            abi.decode(_stripSelector(legacyRoute.data), (MarketParams, uint256, address, address));
        assertEq(ownerB, OWNER);
        assertEq(receiverB, OWNER);

        bundle.va.redeem = 1;
        Call memory legacyRedeemRoute = harness.morphoWithdrawCollateralOnBehalf(bundle);
        (,, address ownerC, address receiverC) =
            abi.decode(_stripSelector(legacyRedeemRoute.data), (MarketParams, uint256, address, address));
        assertEq(ownerC, OWNER);
        assertEq(receiverC, OWNER);
    }

    function test_getBundleCalls_legacyWithoutRedeemKeepsWithdrawReceiverAtOwner() external view {
        Bundle memory bundle = _bundle();
        bundle.route.legacyRedemption = true;
        bundle.ma.withdrawCollateral = 21;

        Call[] memory calls = harness.getBundleCalls(bundle);
        assertEq(calls.length, 2);
        assertEq(_selector(calls[0].data), MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector);
        assertEq(_selector(calls[1].data), NestAdapter.adapterSweep.selector);

        (,, address owner, address receiver) =
            abi.decode(_stripSelector(calls[0].data), (MarketParams, uint256, address, address));
        assertEq(owner, OWNER);
        assertEq(receiver, OWNER);
    }

    function test_nestRedeem_routesByRedeemFlags() external {
        Bundle memory bundle = _bundle();
        bundle.va.redeem = 1;

        Call memory asyncRoute = harness.nestRedeem(bundle);
        assertEq(_selector(asyncRoute.data), NestAdapter.nestRequestAndRedeem.selector);

        address accountant = address(0x2100);
        vm.mockCall(VAULT, abi.encodeWithSignature("asset()"), abi.encode(bundle.intent.market.loanToken));
        vm.mockCall(VAULT, abi.encodeWithSignature("accountant()"), abi.encode(accountant));
        vm.mockCall(VAULT, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.mockCall(
            accountant,
            abi.encodeWithSignature("getRateInQuoteSafe(address)", bundle.intent.market.loanToken),
            abi.encode(uint256(1e18))
        );

        bundle.route.legacyRedemption = true;
        Call memory legacyRoute = harness.nestRedeem(bundle);
        assertEq(_selector(legacyRoute.data), NestAdapter.atomicSolverRedeemSolve.selector);

        bundle.route.instantRedeem = true;
        Call memory instantRoute = harness.nestRedeem(bundle);
        assertEq(_selector(instantRoute.data), NestAdapter.nestInstantRedeem.selector);
    }

    function test_morphoRepay_fullExitUnsplit_usesSharesMax() external view {
        Bundle memory bundle = _bundle();
        bundle.ma.repay = 50;
        bundle.ma.withdrawCollateral = 100;

        Call memory call = harness.morphoRepay(bundle);

        (, uint256 repayAssets, uint256 repayShares,,,) =
            abi.decode(_stripSelector(call.data), (MarketParams, uint256, uint256, uint256, address, bytes));

        assertEq(repayAssets, 0, "unsplit full-exit should zero repayAssets");
        assertEq(repayShares, type(uint256).max, "unsplit full-exit should use shares max");
    }

    function test_morphoRepay_syncSplitFullExit_usesAssetBasedRepay() external view {
        Bundle memory bundle = _bundle();
        bundle.ma.repay = 30;
        bundle.ma.withdrawCollateral = 0; // zeroed by getSyncBundle

        Call memory call = harness.morphoRepay(bundle);

        (, uint256 repayAssets, uint256 repayShares,,,) =
            abi.decode(_stripSelector(call.data), (MarketParams, uint256, uint256, uint256, address, bytes));

        assertEq(repayAssets, 30, "sync-split should use asset-based repay");
        assertEq(repayShares, 0, "sync-split should not use shares");
    }

    function test_morphoRepay_asyncSplitFullExit_usesSharesMax() external view {
        Bundle memory bundle = _bundle();
        bundle.ma.repay = 70;
        bundle.ma.withdrawCollateral = 100; // preserved by getAsyncBundle

        Call memory call = harness.morphoRepay(bundle);

        (, uint256 repayAssets, uint256 repayShares,,,) =
            abi.decode(_stripSelector(call.data), (MarketParams, uint256, uint256, uint256, address, bytes));

        assertEq(repayAssets, 0, "async full-exit should zero repayAssets");
        assertEq(repayShares, type(uint256).max, "async full-exit should use shares max");
    }

    function _bundle() internal pure returns (Bundle memory bundle) {
        bundle.ctx = BundleContext({
            morpho: IMorpho(address(0x1111)),
            vault: INestVaultCore(address(VAULT)),
            adapter: ADAPTER,
            bundler: BUNDLER,
            teller: TELLER,
            predicateProxy: PREDICATE_PROXY,
            atomicSolver: ATOMIC_SOLVER,
            atomicQueue: ATOMIC_QUEUE,
            owner: OWNER,
            initiator: OWNER,
            controller: OWNER
        });

        bundle.intent = UserIntent({
            market: _market(),
            assetAllowance: 0,
            shareAllowance: 0,
            maxSharePriceE27: 1,
            minSharePriceE27: 0,
            maxRepaySharePriceE27: type(uint256).max,
            mode: PositionMode.Target,
            target: Position({loan: 0, collateral: 0}),
            delta: MarketActions({borrow: 0, repay: 0, supplyCollateral: 0, withdrawCollateral: 0})
        });
        bundle.route = RouteInput({legacyRedemption: false, legacyDeposit: false, instantRedeem: false});
        bundle.predicateMessage = _emptyPredicateMessage();
    }

    function _market() internal pure returns (MarketParams memory market) {
        market.loanToken = address(0x3001);
        market.collateralToken = address(0x3002);
        market.oracle = address(0x3003);
        market.irm = address(0x3004);
        market.lltv = 1e18;
    }

    function _emptyPredicateMessage() internal pure returns (PredicateMessage memory predicateMessage) {
        predicateMessage = PredicateMessage({
            taskId: "", expireByTime: type(uint256).max, signerAddresses: new address[](0), signatures: new bytes[](0)
        });
    }

    function _selector(bytes memory data) internal pure returns (bytes4 sel) {
        require(data.length >= 4, "invalid data");
        assembly {
            sel := mload(add(data, 0x20))
        }
    }

    function _stripSelector(bytes memory data) internal pure returns (bytes memory stripped) {
        require(data.length >= 4, "invalid data");

        stripped = new bytes(data.length - 4);
        for (uint256 i; i < data.length - 4; ++i) {
            stripped[i] = data[i + 4];
        }
    }
}
