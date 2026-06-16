// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {Id, Market, MarketParams, Position} from "@morpho/interfaces/IMorpho.sol";
import {ORACLE_PRICE_SCALE} from "@morpho/libraries/ConstantsLib.sol";
import {MarketParamsLib} from "@morpho/libraries/MarketParamsLib.sol";
import {Call} from "contracts/vendor/bundler3/interfaces/IBundler3.sol";
import {PredicateMessage} from "@predicate/src/interfaces/IPredicateClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {NestBundler} from "contracts/morpho/NestBundler.sol";
import {Bundle, PositionMode, RouteInput, UserIntent} from "contracts/morpho/types/BundleTypes.sol";
import {NestBundleErrors} from "contracts/morpho/types/Errors.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";

contract MockMorphoForNestBundler {
    mapping(bytes32 => Position) internal _positions;
    mapping(bytes32 => Market) internal _markets;

    function setPosition(Id id, address user, uint128 borrowShares, uint128 collateral) external {
        _positions[keccak256(abi.encode(id, user))] =
            Position({supplyShares: 0, borrowShares: borrowShares, collateral: collateral});
    }

    function setMarket(Id id, Market memory market_) external {
        _markets[Id.unwrap(id)] = market_;
    }

    function position(Id id, address user) external view returns (Position memory) {
        return _positions[keccak256(abi.encode(id, user))];
    }

    function market(Id id) external view returns (Market memory) {
        return _markets[Id.unwrap(id)];
    }
}

contract MockBundler3Noop {
    function multicall(Call[] calldata) external payable {}
}

contract NestBundlerTest is Test {
    using MarketParamsLib for MarketParams;

    address internal constant VAULT = address(0x1001);
    address internal constant TELLER = address(0x1002);
    address internal constant ADAPTER = address(0x1003);
    address internal constant PREDICATE_PROXY = address(0x1004);
    address internal constant LEGACY_PREDICATE_PROXY = address(0x1005);
    address internal constant ATOMIC_SOLVER = address(0x1006);
    address internal constant ATOMIC_QUEUE = address(0x1007);
    address internal constant ACCOUNTANT = address(0x1008);

    address internal constant LOAN_TOKEN = address(0x2001);
    address internal constant COLLATERAL_TOKEN = address(0x2002);

    address internal user = makeAddr("user");
    address internal solver = makeAddr("solver");

    NestBundler internal bundler;
    MockMorphoForNestBundler internal morpho;
    MockBundler3Noop internal bundler3;

    MarketParams internal market;
    Id internal marketId;

    function setUp() external {
        morpho = new MockMorphoForNestBundler();
        bundler3 = new MockBundler3Noop();

        market = MarketParams({
            loanToken: LOAN_TOKEN,
            collateralToken: COLLATERAL_TOKEN,
            oracle: address(0x3001),
            irm: address(0),
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

        bundler = new NestBundler(
            address(morpho),
            address(bundler3),
            ADAPTER,
            PREDICATE_PROXY,
            LEGACY_PREDICATE_PROXY,
            ATOMIC_SOLVER,
            ATOMIC_QUEUE
        );

        _mockVaultAndTokenState(user, 0, 0);
    }

    function test_getBundle_revertsWhenMarketCollateralDoesNotMatchVaultShare() external {
        address wrongShareToken = address(0xDEAD);
        vm.mockCall(VAULT, abi.encodeWithSignature("share()"), abi.encode(wrongShareToken));

        vm.expectRevert(
            abi.encodeWithSelector(
                NestBundleErrors.MarketCollateralMustEqualVaultShare.selector, COLLATERAL_TOKEN, wrongShareToken
            )
        );
        bundler.getBundle(
            _targetIntent(0, 1), _route(), _emptyPredicateMessage(), INestVaultCore(VAULT), TELLER, user, user
        );
    }

    function test_getBundle_revertsWhenMarketLoanTokenDoesNotMatchVaultAsset() external {
        address wrongAsset = address(0xBEEF);
        vm.mockCall(VAULT, abi.encodeWithSignature("asset()"), abi.encode(wrongAsset));

        vm.expectRevert(
            abi.encodeWithSelector(NestBundleErrors.MarketLoanTokenMustEqualVaultAsset.selector, LOAN_TOKEN, wrongAsset)
        );
        bundler.getBundle(
            _targetIntent(0, 1), _route(), _emptyPredicateMessage(), INestVaultCore(VAULT), TELLER, user, user
        );
    }

    function test_getBundleAndExecuteDelta_usesMsgSenderAsOwner() external {
        UserIntent memory intent = _deltaIntent(0, 0, 0, 1);
        morpho.setPosition(marketId, user, 0, 1);

        vm.prank(user);
        Call[] memory calls =
            bundler.getBundleAndExecute(intent, _route(), _emptyPredicateMessage(), INestVaultCore(VAULT), TELLER);

        assertEq(calls.length, 2, "withdraw-only delta should build withdraw + sweep");
    }

    function test_getBundleCalls_returnsNoApprovals_whenNoPulls() external {
        UserIntent memory intent = _deltaIntent(0, 0, 0, 1);
        morpho.setPosition(marketId, user, 0, 1);

        (Call[] memory calls, Call[] memory approvalTxs) = bundler.getBundleCalls(
            intent, _route(), _emptyPredicateMessage(), INestVaultCore(VAULT), TELLER, user, user
        );

        assertEq(calls.length, 2, "withdraw-only delta should build withdraw + sweep");
        assertEq(approvalTxs.length, 0, "no pull path should not require approvals");
    }

    function test_getBundleCalls_returnsCollateralApproval_whenPullSharesIsNonZero() external {
        _mockVaultAndTokenState(user, 0, 2);
        morpho.setPosition(marketId, user, 0, 0);
        UserIntent memory intent = _targetIntent(0, 2);

        (Call[] memory calls, Call[] memory approvalTxs) = bundler.getBundleCalls(
            intent, _route(), _emptyPredicateMessage(), INestVaultCore(VAULT), TELLER, user, user
        );

        assertEq(calls.length, 3, "expected pullShares + supplyCollateral + sweep");
        assertEq(approvalTxs.length, 1, "expected one collateral approval");
        assertEq(approvalTxs[0].to, COLLATERAL_TOKEN, "approval target token mismatch");
        assertEq(approvalTxs[0].value, 0, "approval value should be zero");
        assertEq(approvalTxs[0].data, abi.encodeCall(IERC20.approve, (ADAPTER, 2)), "approval calldata mismatch");
    }

    function test_getBundleCalls_returnsBoundedLoanApproval_whenLegacyRedemptionNeedsTransferFrom() external {
        _mockVaultAndTokenState(user, 0, 0, 2e18);
        _mockPreviewFulfillRedeem(10, 20, 0);
        _mockPreviewFulfillRedeem(5, 10, 0);
        morpho.setPosition(marketId, user, 10, 10);

        UserIntent memory intent = _targetIntent(0, 0);
        RouteInput memory route = _route();
        route.legacyRedemption = true;

        (Call[] memory calls, Call[] memory approvalTxs) =
            bundler.getBundleCalls(intent, route, _emptyPredicateMessage(), INestVaultCore(VAULT), TELLER, user, user);

        assertEq(calls.length, 2, "expected flash-loan wrapped callback bundle + sweep");
        assertEq(approvalTxs.length, 1, "legacy redemption should include loan approval");
        assertEq(approvalTxs[0].to, LOAN_TOKEN, "approval target token mismatch");
        assertEq(approvalTxs[0].value, 0, "approval value should be zero");
        assertEq(
            approvalTxs[0].data, abi.encodeCall(IERC20.approve, (ADAPTER, 20)), "legacy approval calldata mismatch"
        );
    }

    function test_getBundleCalls_legacyRedeemSolveUsesBundleDerivedLimits() external {
        _mockVaultAndTokenState(user, 0, 0, 2e18);
        _mockPreviewFulfillRedeem(10, 20, 0);
        _mockPreviewFulfillRedeem(5, 10, 0);
        morpho.setPosition(marketId, user, 10, 10);

        UserIntent memory intent = _targetIntent(0, 0);
        intent.maxSharePriceE27 = type(uint256).max;
        intent.minSharePriceE27 = 15e26;

        RouteInput memory route = _route();
        route.legacyRedemption = true;

        (Call[] memory calls,) =
            bundler.getBundleCalls(intent, route, _emptyPredicateMessage(), INestVaultCore(VAULT), TELLER, user, user);

        assertEq(calls.length, 2, "expected flash-loan wrapped callback bundle + sweep");
        (,, bytes memory callbackData) = abi.decode(_stripSelector(calls[0].data), (address, uint256, bytes));
        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));

        assertEq(callbackBundle.length, 3, "legacy callback bundle length");
        assertEq(
            _selector(callbackBundle[2].data),
            bytes4(
                keccak256(
                    "atomicSolverRedeemSolve(address,address,address,(address,address,address,address,uint256),address,address,uint256,uint256)"
                )
            )
        );

        (,,,,,, uint256 maxAssets, uint256 minimumAssetsOut) = abi.decode(
            _stripSelector(callbackBundle[2].data),
            (address, address, address, MarketParams, address, address, uint256, uint256)
        );

        assertEq(maxAssets, 20, "legacy maxAssets should follow withdrawCollateral asset value");
        assertEq(minimumAssetsOut, 8, "legacy minimumAssetsOut should follow bundle redeem shares");
    }

    function test_getSyncBundleCalls_and_getAsyncBundleCalls_splitOwnerFundedRepayFromAsyncRedeem() external {
        _mockVaultAndTokenState(user, 30, 0);
        _mockPreviewFulfillRedeem(50, 50, 0);
        morpho.setPosition(marketId, user, 100, 100);

        UserIntent memory intent = _targetIntent(20, 50);
        Bundle memory syncBaseBundle =
            bundler.getSyncBundle(intent, _route(), _emptyPredicateMessage(), INestVaultCore(VAULT), TELLER, user);
        Bundle memory asyncBaseBundle = bundler.getAsyncBundle(
            intent, _route(), _emptyPredicateMessage(), INestVaultCore(VAULT), TELLER, user, solver
        );

        (Call[] memory syncCalls, Call[] memory syncApprovalTxs) = bundler.getSyncBundleCalls(syncBaseBundle);
        Call[] memory asyncCalls = bundler.getAsyncBundleCalls(asyncBaseBundle);

        assertEq(syncCalls.length, 3, "sync should contain pull + repay + sweep");
        assertEq(_selector(syncCalls[0].data), bytes4(keccak256("erc20TransferFrom(address,address,uint256)")));
        assertEq(
            _selector(syncCalls[1].data),
            bytes4(
                keccak256(
                    "morphoRepay((address,address,address,address,uint256),uint256,uint256,uint256,address,bytes)"
                )
            )
        );
        assertEq(
            _selector(syncCalls[2].data),
            bytes4(keccak256("adapterSweep((address,address,address,address,uint256),address)"))
        );

        assertEq(syncApprovalTxs.length, 1, "sync should require one approval");
        assertEq(syncApprovalTxs[0].to, LOAN_TOKEN, "sync approval token mismatch");
        assertEq(syncApprovalTxs[0].data, abi.encodeCall(IERC20.approve, (ADAPTER, 30)), "sync approval amount");

        assertEq(asyncCalls.length, 2, "async should be flash-loan wrapped + sweep");
        assertEq(_selector(asyncCalls[0].data), bytes4(keccak256("morphoFlashLoan(address,uint256,bytes)")));
        assertEq(
            _selector(asyncCalls[1].data),
            bytes4(keccak256("adapterSweep((address,address,address,address,uint256),address)"))
        );

        (,, bytes memory callbackData) = abi.decode(_stripSelector(asyncCalls[0].data), (address, uint256, bytes));
        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));

        assertEq(callbackBundle.length, 3, "async callback length");
        assertEq(
            _selector(callbackBundle[0].data),
            bytes4(
                keccak256(
                    "morphoRepay((address,address,address,address,uint256),uint256,uint256,uint256,address,bytes)"
                )
            )
        );
        assertEq(
            _selector(callbackBundle[1].data),
            bytes4(
                keccak256(
                    "morphoWithdrawCollateralOnBehalf((address,address,address,address,uint256),uint256,address,address)"
                )
            )
        );
        assertEq(
            _selector(callbackBundle[2].data),
            bytes4(keccak256("nestRequestAndRedeem(address,uint256,uint256,address,address,address)"))
        );

        (,, uint256 minSharePriceE27, address receiver, address controller, address owner) =
            abi.decode(_stripSelector(callbackBundle[2].data), (address, uint256, uint256, address, address, address));
        assertEq(minSharePriceE27, 0, "min share price mismatch");
        assertEq(receiver, ADAPTER, "async receiver mismatch");
        assertEq(controller, user, "async controller should follow owner");
        assertEq(owner, ADAPTER, "async redeem owner should be the adapter");
    }

    function test_getSyncBundleCalls_returnsEmpty_whenNoImmediateWorkExists() external {
        _mockVaultAndTokenState(user, 0, 0);
        _mockPreviewFulfillRedeem(50, 50, 0);
        morpho.setPosition(marketId, user, 100, 100);

        UserIntent memory intent = _targetIntent(50, 50);
        Bundle memory syncBaseBundle =
            bundler.getSyncBundle(intent, _route(), _emptyPredicateMessage(), INestVaultCore(VAULT), TELLER, user);
        Bundle memory asyncBaseBundle = bundler.getAsyncBundle(
            intent, _route(), _emptyPredicateMessage(), INestVaultCore(VAULT), TELLER, user, solver
        );

        (Call[] memory syncCalls, Call[] memory syncApprovalTxs) = bundler.getSyncBundleCalls(syncBaseBundle);
        Call[] memory asyncCalls = bundler.getAsyncBundleCalls(asyncBaseBundle);

        assertEq(syncCalls.length, 0, "sync phase should be empty");
        assertEq(syncApprovalTxs.length, 0, "sync approvals should be empty");
        assertEq(asyncCalls.length, 2, "async should contain the full redeem flow + sweep");
    }

    function _intent() internal view returns (UserIntent memory intent) {
        intent.market = market;
        intent.assetAllowance = type(uint256).max;
        intent.shareAllowance = type(uint256).max;
        intent.maxSharePriceE27 = 1;
        intent.minSharePriceE27 = 0;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
    }

    function _targetIntent(uint256 targetBorrow, uint256 targetCollateral)
        internal
        view
        returns (UserIntent memory intent)
    {
        intent = _intent();
        intent.target.loan = targetBorrow;
        intent.target.collateral = targetCollateral;
    }

    function _deltaIntent(uint256 borrow, uint256 repay, uint256 supplyCollateral, uint256 withdrawCollateral)
        internal
        view
        returns (UserIntent memory intent)
    {
        intent = _intent();
        intent.mode = PositionMode.Delta;
        intent.delta.borrow = borrow;
        intent.delta.repay = repay;
        intent.delta.supplyCollateral = supplyCollateral;
        intent.delta.withdrawCollateral = withdrawCollateral;
    }

    function _route() internal pure returns (RouteInput memory route) {
        route.legacyRedemption = false;
        route.legacyDeposit = false;
        route.instantRedeem = false;
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

    function _mockVaultAndTokenState(address owner, uint256 loanOwnerBalance, uint256 collateralOwnerBalance) internal {
        _mockVaultAndTokenState(owner, loanOwnerBalance, collateralOwnerBalance, 1e18);
    }

    function _mockVaultAndTokenState(
        address owner,
        uint256 loanOwnerBalance,
        uint256 collateralOwnerBalance,
        uint256 sharePrice
    ) internal {
        vm.mockCall(VAULT, abi.encodeWithSignature("asset()"), abi.encode(LOAN_TOKEN));
        vm.mockCall(VAULT, abi.encodeWithSignature("share()"), abi.encode(COLLATERAL_TOKEN));
        vm.mockCall(VAULT, abi.encodeWithSignature("accountant()"), abi.encode(ACCOUNTANT));
        vm.mockCall(VAULT, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.mockCall(
            ACCOUNTANT, abi.encodeWithSignature("getRateInQuoteSafe(address)", LOAN_TOKEN), abi.encode(sharePrice)
        );
        vm.mockCall(market.oracle, abi.encodeWithSignature("price()"), abi.encode(uint256(ORACLE_PRICE_SCALE)));
        vm.mockCall(COLLATERAL_TOKEN, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));

        // No-fee mocks for redemption fee types (InstantRedemption=0, Redemption=2).
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", 0), abi.encode(uint32(0), uint256(0)));
        vm.mockCall(VAULT, abi.encodeWithSignature("fees(uint8)", 2), abi.encode(uint32(0), uint256(0)));

        vm.mockCall(LOAN_TOKEN, abi.encodeWithSignature("balanceOf(address)", owner), abi.encode(loanOwnerBalance));
        vm.mockCall(
            COLLATERAL_TOKEN, abi.encodeWithSignature("balanceOf(address)", owner), abi.encode(collateralOwnerBalance)
        );

        vm.mockCall(LOAN_TOKEN, abi.encodeWithSignature("balanceOf(address)", address(bundler)), abi.encode(uint256(0)));
        vm.mockCall(
            COLLATERAL_TOKEN, abi.encodeWithSignature("balanceOf(address)", address(bundler)), abi.encode(uint256(0))
        );
    }

    function _mockPreviewFulfillRedeem(uint256 shares, uint256 postFeeAssets, uint256 feeAmount) internal {
        vm.mockCall(
            VAULT,
            abi.encodeWithSignature("previewFulfillRedeem(uint256)", shares),
            abi.encode(postFeeAssets, feeAmount)
        );
    }
}
