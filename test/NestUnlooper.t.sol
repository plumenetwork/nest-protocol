// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/ERC20Mock.sol";
import {ERC20MockWithPreview} from "./mock/morpho/ERC20MockWithPreview.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

import {Call} from "contracts/vendor/bundler3/interfaces/IBundler3.sol";
import {Id, IMorpho, Market, MarketParams, Position as MorphoPosition} from "@morpho/interfaces/IMorpho.sol";
import {MarketParamsLib} from "@morpho/libraries/MarketParamsLib.sol";

import {AtomicQueue} from "@boring-vault/src/atomic-queue/AtomicQueue.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/src/base/Roles/TellerWithMultiAssetSupport.sol";

import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {GeneralAdapter1} from "contracts/vendor/morpho/GeneralAdapter1.sol";
import {NestAdapter} from "contracts/morpho/NestAdapter.sol";
import {MorphoAdapter} from "contracts/morpho/MorphoAdapter.sol";
import {NestUnlooper} from "contracts/morpho/NestUnlooper.sol";
import {NestUnlooperErrors} from "contracts/morpho/types/Errors.sol";
import {Bundle} from "contracts/morpho/types/BundleTypes.sol";

contract MockMorphoForAsyncUnloop {
    mapping(bytes32 => MorphoPosition) internal _positions;
    mapping(bytes32 => Market) internal _markets;
    mapping(address => mapping(address => bool)) internal _authorized;

    function setPosition(Id id, address user, uint128 borrowShares, uint128 collateral) external {
        _positions[keccak256(abi.encode(id, user))] =
            MorphoPosition({supplyShares: 0, borrowShares: borrowShares, collateral: collateral});
    }

    function setMarket(Id id, Market memory market_) external {
        _markets[Id.unwrap(id)] = market_;
    }

    function setAuthorization(address authorizer, address authorized, bool allowed) external {
        _authorized[authorizer][authorized] = allowed;
    }

    function position(Id id, address user) external view returns (MorphoPosition memory) {
        return _positions[keccak256(abi.encode(id, user))];
    }

    function market(Id id) external view returns (Market memory) {
        return _markets[Id.unwrap(id)];
    }

    function isAuthorized(address authorizer, address authorized) external view returns (bool) {
        return _authorized[authorizer][authorized];
    }
}

contract MockBundler3Recorder {
    bytes internal _lastBundle;
    address public lastCaller;

    function multicall(Call[] calldata bundle) external payable {
        lastCaller = msg.sender;
        _lastBundle = abi.encode(bundle);
    }

    function getLastBundle() external view returns (Call[] memory bundle) {
        bundle = abi.decode(_lastBundle, (Call[]));
    }
}

contract MockTeller {}

contract NestUnlooperTest is Test {
    using MarketParamsLib for MarketParams;

    address internal constant ADAPTER = address(0xA11CE);
    address internal constant ATOMIC_SOLVER = address(0xB0B);
    address internal constant ACCOUNTANT = address(0xCA11);

    address internal user = makeAddr("user");
    address internal unauthorized = makeAddr("unauthorized");

    event Executed(
        address indexed user, bytes32 indexed marketId, uint256 repay, uint256 withdrawCollateral, uint256 redeem
    );
    event UnloopRequestUpdated(
        address indexed user, bytes32 indexed marketId, uint32 leverageBps, uint256 minSharePriceE27, uint64 deadline
    );
    event UnloopRequestCleared(address indexed user, bytes32 indexed marketId);

    ERC20Mock internal loanToken;
    ERC20Mock internal collateralToken;
    MockMorphoForAsyncUnloop internal morpho;
    MockBundler3Recorder internal bundler3;
    AtomicQueue internal atomicQueue;
    MockTeller internal tellerLike;
    NestUnlooper internal unlooper;
    INestVaultCore internal vault;

    MarketParams internal market;
    Id internal marketId;

    function setUp() external {
        loanToken = new ERC20Mock("pUSD", "pUSD");
        collateralToken = new ERC20MockWithPreview("nALPHA", "nALPHA", 2 ether);
        morpho = new MockMorphoForAsyncUnloop();
        bundler3 = new MockBundler3Recorder();
        atomicQueue = new AtomicQueue();
        tellerLike = new MockTeller();
        vault = INestVaultCore(address(collateralToken));

        market = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(0xC0FFEE),
            irm: address(0xD00D),
            lltv: 1e18
        });
        marketId = market.id();

        morpho.setMarket(
            marketId,
            Market({
                totalSupplyAssets: 1_000_000e18,
                totalSupplyShares: 0,
                totalBorrowAssets: 1e18,
                totalBorrowShares: 1e18,
                lastUpdate: uint128(block.timestamp),
                fee: 0
            })
        );
        morpho.setPosition(marketId, user, uint128(150 ether), uint128(200 ether));

        unlooper = new NestUnlooper(
            address(this),
            Authority(address(0)),
            address(morpho),
            address(bundler3),
            ADAPTER,
            ATOMIC_SOLVER,
            address(atomicQueue)
        );

        unlooper.setVaultApproval(address(collateralToken), true);
        unlooper.setVaultApproval(address(tellerLike), true);

        vm.mockCall(address(collateralToken), abi.encodeWithSignature("asset()"), abi.encode(address(loanToken)));
        vm.mockCall(address(collateralToken), abi.encodeWithSignature("share()"), abi.encode(address(collateralToken)));
        vm.mockCall(address(collateralToken), abi.encodeWithSignature("accountant()"), abi.encode(ACCOUNTANT));
        vm.mockCall(address(collateralToken), abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.mockCall(
            ACCOUNTANT, abi.encodeWithSignature("getRateInQuoteSafe(address)", address(loanToken)), abi.encode(2 ether)
        );
        vm.mockCall(market.oracle, abi.encodeWithSignature("price()"), abi.encode(uint256(1e36)));

        morpho.setAuthorization(user, address(unlooper), true);

        vm.startPrank(user);
        collateralToken.approve(address(atomicQueue), type(uint256).max);
        loanToken.approve(ADAPTER, type(uint256).max);
        vm.stopPrank();
    }

    function test_getAsyncBundle_derivesFromLiveQueueRequest() external {
        _updateRequest(uint96(50 ether), uint88(2 ether), uint64(block.timestamp + 1 days));

        Bundle memory bundle = unlooper.getAsyncBundle(market, vault, _teller(), user, true);

        assertEq(bundle.ma.withdrawCollateral, 50 ether, "withdraw collateral");
        assertEq(bundle.ma.repay, 100 ether, "repay");
        assertEq(bundle.va.redeem, 50 ether, "redeem");
        assertTrue(bundle.route.legacyRedemption, "atomic queue route");
        assertEq(bundle.ctx.owner, user, "owner");
        assertEq(address(bundle.ctx.vault), address(vault), "vault");
    }

    function test_getAsyncBundle_modernRoute_derivesTargetFromStoredLeverage() external {
        uint64 deadline = uint64(block.timestamp + 1 days);

        vm.prank(user);
        unlooper.updateUnloopRequest(market, 20_000, 0, deadline);

        NestUnlooper.UnloopRequest memory request = unlooper.getUnloopRequest(user, market);
        assertEq(request.leverageBps, 20_000, "stored leverage");

        Bundle memory bundle = unlooper.getAsyncBundle(market, vault, _teller(), user, false);
        assertFalse(bundle.route.legacyRedemption, "modern redemption route");
        assertApproxEqAbs(bundle.intent.target.loan, 50 ether, 2e8, "target borrow");
        assertApproxEqAbs(bundle.intent.target.collateral, 100 ether, 4e8, "target collateral");
        assertApproxEqAbs(bundle.ma.repay, 100 ether, 4e8, "repay");
        assertApproxEqAbs(bundle.ma.withdrawCollateral, 100 ether, 4e8, "withdraw collateral");
        assertApproxEqAbs(bundle.va.redeem, 50 ether, 4e8, "redeem shares");
    }

    function test_updateUnloopRequest_storesSlippageAndDeadline() external {
        uint64 deadline = uint64(block.timestamp + 1 days);

        vm.prank(user);
        unlooper.updateUnloopRequest(market, 20_000, 12e26, deadline);

        NestUnlooper.UnloopRequest memory request = unlooper.getUnloopRequest(user, market);
        assertEq(request.leverageBps, 20_000, "stored leverage");
        assertEq(request.minSharePriceE27, 12e26, "stored min share price");
        assertEq(request.deadline, deadline, "stored deadline");
    }

    function test_updateUnloopRequest_emitsUpdatedEvent() external {
        uint64 deadline = uint64(block.timestamp + 1 days);

        vm.expectEmit(true, true, false, true, address(unlooper));
        emit UnloopRequestUpdated(user, Id.unwrap(marketId), 20_000, 12e26, deadline);

        vm.prank(user);
        unlooper.updateUnloopRequest(market, 20_000, 12e26, deadline);
    }

    function test_updateUnloopRequest_zeroLeverageStoresFullExitRequest() external {
        uint64 deadline = uint64(block.timestamp + 1 days);

        vm.prank(user);
        unlooper.updateUnloopRequest(market, 0, 0, deadline);

        NestUnlooper.UnloopRequest memory request = unlooper.getUnloopRequest(user, market);
        assertEq(request.leverageBps, 0, "stored leverage");
        assertEq(request.deadline, deadline, "stored deadline");
    }

    function test_updateUnloopRequest_revertsWhenDeadlineIsZero() external {
        vm.warp(100);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NestUnlooperErrors.InvalidUnloopDeadline.selector, 0, block.timestamp));
        unlooper.updateUnloopRequest(market, 20_000, 0, 0);
    }

    function test_clearUnloopRequest_deletesStoredRequest() external {
        uint64 deadline = uint64(block.timestamp + 1 days);

        vm.prank(user);
        unlooper.updateUnloopRequest(market, 20_000, 0, deadline);

        vm.expectEmit(true, true, false, false, address(unlooper));
        emit UnloopRequestCleared(user, Id.unwrap(marketId));

        vm.prank(user);
        unlooper.clearUnloopRequest(market);

        NestUnlooper.UnloopRequest memory request = unlooper.getUnloopRequest(user, market);
        assertEq(request.leverageBps, 0, "cleared leverage");
        assertEq(request.minSharePriceE27, 0, "cleared min share price");
        assertEq(request.deadline, 0, "cleared deadline");
    }

    function test_getAsyncBundleCalls_modernRoute_skipsAtomicQueueAndUsesRequestAndRedeem() external {
        uint64 deadline = uint64(block.timestamp + 1 days);

        vm.prank(user);
        unlooper.updateUnloopRequest(market, 10_000, 0, deadline);

        Bundle memory bundle = unlooper.getAsyncBundle(market, vault, _teller(), user, false);
        Call[] memory calls = unlooper.getAsyncBundleCalls(market, vault, _teller(), user, false);
        assertEq(calls.length, 2, "top-level call count");
        assertEq(_selector(calls[0].data), GeneralAdapter1.morphoFlashLoan.selector, "flash loan selector");
        assertEq(_selector(calls[1].data), NestAdapter.adapterSweep.selector, "sweep selector");

        (address flashToken, uint256 flashAssets, bytes memory callbackData) =
            abi.decode(_args(calls[0].data), (address, uint256, bytes));
        assertEq(flashToken, address(loanToken), "flash token");
        assertEq(flashAssets, bundle.ma.repay, "flash amount");

        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
        assertEq(callbackBundle.length, 3, "callback length");
        assertEq(_selector(callbackBundle[0].data), GeneralAdapter1.morphoRepay.selector, "repay selector");
        assertEq(
            _selector(callbackBundle[1].data),
            MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector,
            "withdraw selector"
        );
        assertEq(_selector(callbackBundle[2].data), NestAdapter.nestRequestAndRedeem.selector, "redeem selector");

        (, uint256 withdrawAssets, address withdrawOnBehalf, address withdrawReceiver) =
            abi.decode(_args(callbackBundle[1].data), (MarketParams, uint256, address, address));
        assertEq(withdrawAssets, bundle.ma.withdrawCollateral, "withdraw assets");
        assertEq(withdrawOnBehalf, user, "withdraw owner");
        assertEq(withdrawReceiver, ADAPTER, "withdraw receiver");

        (, uint256 shares,, address receiver, address controller, address owner) =
            abi.decode(_args(callbackBundle[2].data), (INestVaultCore, uint256, uint256, address, address, address));
        assertEq(shares, bundle.va.redeem, "redeem shares");
        assertEq(receiver, ADAPTER, "redeem receiver");
        assertEq(controller, user, "controller");
        assertEq(owner, ADAPTER, "redeem owner");
    }

    function test_getAsyncBundle_modernRoute_usesStoredMinSharePrice() external {
        vm.prank(user);
        unlooper.updateUnloopRequest(market, 10_000, 12e26, uint64(block.timestamp + 1 days));

        Bundle memory bundle = unlooper.getAsyncBundle(market, vault, _teller(), user, false);
        assertEq(bundle.intent.minSharePriceE27, 12e26, "bundle min share price");

        Call[] memory calls = unlooper.getAsyncBundleCalls(market, vault, _teller(), user, false);
        (,, bytes memory callbackData) = abi.decode(_args(calls[0].data), (address, uint256, bytes));
        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
        (,, uint256 minSharePriceE27,,,) =
            abi.decode(_args(callbackBundle[2].data), (INestVaultCore, uint256, uint256, address, address, address));
        assertEq(minSharePriceE27, 12e26, "redeem min share price");
    }

    function test_getAsyncBundle_modernRoute_revertsWhenRequestNotSet() external {
        vm.expectRevert(
            abi.encodeWithSelector(NestUnlooperErrors.UnloopRequestNotSet.selector, user, Id.unwrap(marketId))
        );
        unlooper.getAsyncBundle(market, vault, _teller(), user, false);
    }

    function test_getAsyncBundle_modernRoute_revertsWhenStoredRequestExpired() external {
        uint64 deadline = uint64(block.timestamp + 1 hours);
        vm.prank(user);
        unlooper.updateUnloopRequest(market, 20_000, 0, deadline);

        vm.warp(deadline + 1);
        vm.expectRevert(
            abi.encodeWithSelector(NestUnlooperErrors.UnloopRequestExpired.selector, user, deadline, block.timestamp)
        );
        unlooper.getAsyncBundle(market, vault, _teller(), user, false);
    }

    function test_updateUnloopRequest_revertsWhenTargetNotBelowCurrent() external {
        uint64 deadline = uint64(block.timestamp + 1 days);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(NestUnlooperErrors.TargetLeverageNotBelowCurrent.selector, 40_000, 39_999)
        );
        unlooper.updateUnloopRequest(market, 40_000, 0, deadline);
    }

    function test_updateUnloopRequest_revertsWhenDeadlineAlreadyExpired() external {
        vm.warp(100);
        uint64 deadline = uint64(block.timestamp - 1);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(NestUnlooperErrors.InvalidUnloopDeadline.selector, deadline, block.timestamp)
        );
        unlooper.updateUnloopRequest(market, 20_000, 0, deadline);
    }

    function test_getAsyncBundle_modernRoute_revertsWhenStoredRequestIsNoLongerBelowCurrent() external {
        uint64 deadline = uint64(block.timestamp + 1 days);

        vm.prank(user);
        unlooper.updateUnloopRequest(market, 20_000, 0, deadline);

        morpho.setPosition(marketId, user, uint128(100 ether), uint128(200 ether));
        vm.expectRevert(
            abi.encodeWithSelector(NestUnlooperErrors.TargetLeverageNotBelowCurrent.selector, 20_000, 19_999)
        );
        unlooper.getAsyncBundle(market, vault, _teller(), user, false);
    }

    function test_getAsyncBundle_modernRoute_zeroLeverageBuildsFullExitTarget() external {
        uint64 deadline = uint64(block.timestamp + 1 days);

        vm.prank(user);
        unlooper.updateUnloopRequest(market, 0, 0, deadline);

        Bundle memory bundle = unlooper.getAsyncBundle(market, vault, _teller(), user, false);
        assertEq(bundle.intent.target.loan, 0, "target borrow");
        assertEq(bundle.intent.target.collateral, 0, "target collateral");
        assertApproxEqAbs(bundle.ma.repay, 150 ether, 4e8, "repay");
        assertEq(bundle.ma.withdrawCollateral, 200 ether, "withdraw collateral");
        assertApproxEqAbs(bundle.va.redeem, 75 ether, 4e8, "redeem shares");

        Call[] memory calls = unlooper.getAsyncBundleCalls(market, vault, _teller(), user, false);
        assertEq(calls.length, 2, "top-level call count");
        assertEq(_selector(calls[0].data), GeneralAdapter1.morphoFlashLoan.selector, "flash loan selector");
        assertEq(_selector(calls[1].data), NestAdapter.adapterSweep.selector, "sweep selector");

        (, uint256 flashAssets, bytes memory callbackData) = abi.decode(_args(calls[0].data), (address, uint256, bytes));
        assertEq(flashAssets, bundle.ma.repay, "flash amount");

        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
        assertEq(callbackBundle.length, 3, "callback length");
        assertEq(_selector(callbackBundle[0].data), GeneralAdapter1.morphoRepay.selector, "repay selector");
        assertEq(
            _selector(callbackBundle[1].data),
            MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector,
            "withdraw selector"
        );
        assertEq(_selector(callbackBundle[2].data), NestAdapter.nestRequestAndRedeem.selector, "redeem selector");
    }

    function test_getAsyncBundleCalls_modernRoute_zeroLeverageWithdrawsAllWhenBorrowIsZero() external {
        morpho.setPosition(marketId, user, 0, uint128(200 ether));
        uint64 deadline = uint64(block.timestamp + 1 days);

        vm.prank(user);
        unlooper.updateUnloopRequest(market, 0, 0, deadline);

        Bundle memory bundle = unlooper.getAsyncBundle(market, vault, _teller(), user, false);
        assertEq(bundle.intent.target.loan, 0, "target borrow");
        assertEq(bundle.intent.target.collateral, 0, "target collateral");
        assertEq(bundle.ma.repay, 0, "repay");
        assertEq(bundle.ma.withdrawCollateral, 200 ether, "withdraw collateral");
        assertEq(bundle.va.redeem, 0, "redeem");

        Call[] memory calls = unlooper.getAsyncBundleCalls(market, vault, _teller(), user, false);
        assertEq(calls.length, 2, "direct call count");
        assertEq(_selector(calls[0].data), MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector, "withdraw selector");
        assertEq(_selector(calls[1].data), NestAdapter.adapterSweep.selector, "sweep selector");

        (, uint256 withdrawAssets, address withdrawOnBehalf, address withdrawReceiver) =
            abi.decode(_args(calls[0].data), (MarketParams, uint256, address, address));
        assertEq(withdrawAssets, 200 ether, "withdraw assets");
        assertEq(withdrawOnBehalf, user, "withdraw owner");
        assertEq(withdrawReceiver, ADAPTER, "withdraw receiver");
    }

    function testFuzz_execute_acceptsValidRedemptionRequest(
        uint96 offerAmount,
        uint88 atomicPrice,
        uint128 borrowShares
    ) external {
        offerAmount = uint96(bound(offerAmount, 1 ether, 200 ether));
        atomicPrice = uint88(bound(atomicPrice, 1e17, 10 ether));
        borrowShares = uint128(bound(borrowShares, 0, 400 ether));

        _updateRequest(offerAmount, atomicPrice, uint64(block.timestamp + 1 days));
        morpho.setPosition(marketId, user, borrowShares, uint128(200 ether));

        Bundle memory bundle = unlooper.getAsyncBundle(market, vault, _teller(), user, true);
        uint256 assetsForWant = Math.mulDiv(uint256(offerAmount), uint256(atomicPrice), 1 ether, Math.Rounding.Floor);

        assertLe(bundle.ma.repay, assetsForWant, "repay capped by request");
        assertLe(bundle.ma.repay, 400 ether, "repay capped by borrow envelope");
        assertEq(bundle.ma.withdrawCollateral, offerAmount, "withdraw collateral");
        assertEq(bundle.va.redeem, offerAmount, "redeem");

        Call[] memory expected = unlooper.getAsyncBundleCalls(market, vault, _teller(), user, true);
        Call[] memory returned = unlooper.execute(market, vault, _teller(), user, true);
        Call[] memory recorded = bundler3.getLastBundle();

        assertEq(keccak256(abi.encode(returned)), keccak256(abi.encode(expected)), "returned calls");
        assertEq(keccak256(abi.encode(recorded)), keccak256(abi.encode(expected)), "recorded calls");
    }

    function test_execute_revertsWhenUnauthorizedKeeper() external {
        _updateRequest(uint96(50 ether), uint88(2 ether), uint64(block.timestamp + 1 days));

        vm.prank(unauthorized);
        vm.expectRevert(bytes("UNAUTHORIZED"));
        unlooper.execute(market, vault, _teller(), user, true);
    }

    function test_getAsyncBundleCalls_usesFullRequestWhenBorrowCoversWant() external {
        _updateRequest(uint96(50 ether), uint88(2 ether), uint64(block.timestamp + 1 days));

        Call[] memory calls = unlooper.getAsyncBundleCalls(market, vault, _teller(), user, true);
        assertEq(calls.length, 2, "top-level call count");
        assertEq(calls[0].to, ADAPTER, "flash loan target");
        assertEq(_selector(calls[0].data), GeneralAdapter1.morphoFlashLoan.selector, "flash loan selector");
        assertEq(calls[1].to, ADAPTER, "sweep target");
        assertEq(_selector(calls[1].data), NestAdapter.adapterSweep.selector, "sweep selector");

        (address flashToken, uint256 flashAssets, bytes memory callbackData) =
            abi.decode(_args(calls[0].data), (address, uint256, bytes));
        assertEq(flashToken, address(loanToken), "flash token");
        assertEq(flashAssets, 100 ether, "flash amount");

        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
        assertEq(callbackBundle.length, 3, "callback length");
        assertEq(_selector(callbackBundle[0].data), GeneralAdapter1.morphoRepay.selector, "repay selector");
        assertEq(
            _selector(callbackBundle[1].data),
            MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector,
            "withdraw selector"
        );
        assertEq(_selector(callbackBundle[2].data), NestAdapter.atomicSolverRedeemSolve.selector, "solve selector");

        (, uint256 repayAssets,,, address onBehalf,) =
            abi.decode(_args(callbackBundle[0].data), (MarketParams, uint256, uint256, uint256, address, bytes));
        assertEq(repayAssets, 100 ether, "repay assets");
        assertEq(onBehalf, user, "repay on behalf");

        (, uint256 withdrawAssets, address withdrawOnBehalf, address withdrawReceiver) =
            abi.decode(_args(callbackBundle[1].data), (MarketParams, uint256, address, address));
        assertEq(withdrawAssets, 50 ether, "withdraw assets");
        assertEq(withdrawOnBehalf, user, "withdraw owner");
        assertEq(withdrawReceiver, user, "withdraw receiver");

        (
            address solveOperator,
            address solveQueue,
            address solveTeller,,
            address solveUser,
            address solveReceiver,
            uint256 maxAssets,
            uint256 minimumAssetsOut
        ) = abi.decode(
            _args(callbackBundle[2].data), (address, address, address, MarketParams, address, address, uint256, uint256)
        );
        assertEq(solveOperator, ATOMIC_SOLVER, "solver");
        assertEq(solveQueue, address(atomicQueue), "queue");
        assertEq(solveTeller, address(tellerLike), "teller");
        assertEq(solveUser, user, "solve user");
        assertEq(solveReceiver, ADAPTER, "solve receiver");
        assertEq(maxAssets, 100 ether, "max assets");
        assertEq(minimumAssetsOut, 100 ether, "min assets out");
    }

    function test_execute_emitsRefactoredExecutedEvent() external {
        _updateRequest(uint96(50 ether), uint88(2 ether), uint64(block.timestamp + 1 days));

        vm.expectEmit(true, true, false, true, address(unlooper));
        emit Executed(user, Id.unwrap(marketId), 100 ether, 50 ether, 50 ether);

        unlooper.execute(market, vault, _teller(), user, true);
    }

    function test_getAsyncBundle_capsRepayAtCurrentBorrow() external {
        _updateRequest(uint96(50 ether), uint88(2 ether), uint64(block.timestamp + 1 days));
        morpho.setPosition(marketId, user, uint128(40 ether), uint128(200 ether));

        Bundle memory bundle = unlooper.getAsyncBundle(market, vault, _teller(), user, true);
        assertApproxEqAbs(bundle.ma.repay, 40 ether, 2e8, "repay capped at current borrow");
        assertEq(bundle.ma.withdrawCollateral, 50 ether, "withdraw collateral unchanged");

        Call[] memory calls = unlooper.getAsyncBundleCalls(market, vault, _teller(), user, true);
        (, uint256 flashAssets, bytes memory callbackData) = abi.decode(_args(calls[0].data), (address, uint256, bytes));
        assertEq(flashAssets, bundle.ma.repay, "flash amount matches repay");

        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
        (,,,,, address solveReceiver, uint256 maxAssets, uint256 minimumAssetsOut) = abi.decode(
            _args(callbackBundle[2].data), (address, address, address, MarketParams, address, address, uint256, uint256)
        );
        assertEq(solveReceiver, ADAPTER, "solve receiver");
        assertEq(maxAssets, 100 ether, "max assets");
        assertEq(minimumAssetsOut, 100 ether, "min assets out");
    }

    function test_getAsyncBundleCalls_skipsFlashLoanWhenBorrowIsZero() external {
        _updateRequest(uint96(50 ether), uint88(2 ether), uint64(block.timestamp + 1 days));
        morpho.setPosition(marketId, user, 0, uint128(200 ether));

        Bundle memory bundle = unlooper.getAsyncBundle(market, vault, _teller(), user, true);
        assertEq(bundle.ma.repay, 0, "repay");

        Call[] memory calls = unlooper.getAsyncBundleCalls(market, vault, _teller(), user, true);
        assertEq(calls.length, 3, "direct call count");
        assertEq(_selector(calls[0].data), MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector, "withdraw selector");
        assertEq(_selector(calls[1].data), NestAdapter.atomicSolverRedeemSolve.selector, "solve selector");
        assertEq(_selector(calls[2].data), NestAdapter.adapterSweep.selector, "sweep selector");

        (, uint256 withdrawAssets, address withdrawOnBehalf, address withdrawReceiver) =
            abi.decode(_args(calls[0].data), (MarketParams, uint256, address, address));
        assertEq(withdrawAssets, 50 ether, "withdraw assets");
        assertEq(withdrawOnBehalf, user, "withdraw owner");
        assertEq(withdrawReceiver, user, "withdraw receiver");

        (,,,, address solveUser, address solveReceiver, uint256 maxAssets, uint256 minimumAssetsOut) = abi.decode(
            _args(calls[1].data), (address, address, address, MarketParams, address, address, uint256, uint256)
        );
        assertEq(solveUser, user, "solve user");
        assertEq(solveReceiver, ADAPTER, "solve receiver");
        assertEq(maxAssets, 100 ether, "max assets");
        assertEq(minimumAssetsOut, 100 ether, "min assets out");
    }

    function test_execute_recordsSameBundleAsGetter() external {
        _updateRequest(uint96(50 ether), uint88(2 ether), uint64(block.timestamp + 1 days));

        Call[] memory expected = unlooper.getAsyncBundleCalls(market, vault, _teller(), user, true);
        Call[] memory returned = unlooper.execute(market, vault, _teller(), user, true);
        Call[] memory recorded = bundler3.getLastBundle();

        assertEq(bundler3.lastCaller(), address(unlooper), "bundler caller");
        assertEq(keccak256(abi.encode(returned)), keccak256(abi.encode(expected)), "returned calls");
        assertEq(keccak256(abi.encode(recorded)), keccak256(abi.encode(expected)), "recorded calls");
    }

    function test_execute_modernRoute_recordsSameBundleAsGetter() external {
        uint64 deadline = uint64(block.timestamp + 1 days);

        vm.prank(user);
        unlooper.updateUnloopRequest(market, 10_000, 0, deadline);

        Call[] memory expected = unlooper.getAsyncBundleCalls(market, vault, _teller(), user, false);
        Call[] memory returned = unlooper.execute(market, vault, _teller(), user, false);
        Call[] memory recorded = bundler3.getLastBundle();

        assertEq(bundler3.lastCaller(), address(unlooper), "bundler caller");
        assertEq(keccak256(abi.encode(returned)), keccak256(abi.encode(expected)), "returned calls");
        assertEq(keccak256(abi.encode(recorded)), keccak256(abi.encode(expected)), "recorded calls");
        assertEq(unlooper.getUnloopRequest(user, market).deadline, 0, "cleared leverage request");
    }

    function test_getAsyncBundle_revertsWhenAtomicQueueRequestExpired() external {
        _updateRequest(uint96(50 ether), uint88(2 ether), uint64(block.timestamp + 1 hours));

        // Warp past the deadline so the AtomicQueue sets the expired flag (bit 0).
        vm.warp(block.timestamp + 1 hours + 1);

        vm.expectRevert(
            abi.encodeWithSelector(NestUnlooperErrors.InvalidAtomicQueueRequest.selector, user, Id.unwrap(marketId))
        );
        unlooper.getAsyncBundle(market, vault, _teller(), user, true);
    }

    function test_getAsyncBundle_revertsWhenAtomicQueueApprovalRevoked() external {
        _updateRequest(uint96(50 ether), uint88(2 ether), uint64(block.timestamp + 1 days));

        // Revoke the user's approval so the AtomicQueue sets the missing-approval flag (bit 3).
        vm.prank(user);
        collateralToken.approve(address(atomicQueue), 0);

        vm.expectRevert(
            abi.encodeWithSelector(NestUnlooperErrors.InvalidAtomicQueueRequest.selector, user, Id.unwrap(marketId))
        );
        unlooper.getAsyncBundle(market, vault, _teller(), user, true);
    }

    function test_getAsyncBundle_allowsInsufficientBalanceFlag() external {
        _updateRequest(uint96(50 ether), uint88(2 ether), uint64(block.timestamp + 1 days));

        // User has zero collateral token balance, so flag 2 (insufficient balance) is set.
        // This flag is fixable mid-bundle via collateral withdrawal, so the bundle should build.
        assertEq(collateralToken.balanceOf(user), 0, "user has no tokens");

        Bundle memory bundle = unlooper.getAsyncBundle(market, vault, _teller(), user, true);
        assertEq(bundle.ma.withdrawCollateral, 50 ether, "withdraw collateral");
    }

    function _updateRequest(uint96 offerAmount, uint88 atomicPrice, uint64 deadline) internal {
        vm.prank(user);
        atomicQueue.updateAtomicRequest(
            ERC20(address(collateralToken)),
            ERC20(address(loanToken)),
            AtomicQueue.AtomicRequest({
                deadline: deadline, atomicPrice: atomicPrice, offerAmount: offerAmount, inSolve: false
            })
        );
    }

    function _teller() internal view returns (TellerWithMultiAssetSupport) {
        return TellerWithMultiAssetSupport(payable(address(tellerLike)));
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
