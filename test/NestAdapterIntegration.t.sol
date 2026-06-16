// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {AtomicQueue} from "@boring-vault/src/atomic-queue/AtomicQueue.sol";
import {AtomicSolverV3} from "contracts/vendor/boring-vault/AtomicSolverV3.sol";
import {CrossChainTellerBase} from "@boring-vault/src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/src/base/Roles/TellerWithMultiAssetSupport.sol";

import {Call, IBundler3} from "contracts/vendor/bundler3/interfaces/IBundler3.sol";
import {ErrorsLib} from "contracts/vendor/bundler3/libraries/ErrorsLib.sol";
import {NestVault} from "contracts/NestVault.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {NestAdapter} from "contracts/morpho/NestAdapter.sol";
import {MorphoAdapter} from "contracts/morpho/MorphoAdapter.sol";
import {NestUnlooper} from "contracts/morpho/NestUnlooper.sol";
import {ITellerPredicateProxy} from "contracts/interfaces/ITellerPredicateProxy.sol";
import {NestVaultPredicateProxy, PredicateMessage} from "contracts/NestVaultPredicateProxy.sol";
import {BundleBuildLib} from "contracts/morpho/libraries/BundleBuildLib.sol";
import {BundleCalldataLib} from "contracts/morpho/libraries/BundleCalldataLib.sol";
import {
    Bundle,
    BundleContext,
    MarketActions,
    PositionMode,
    RouteInput,
    Position,
    UserIntent
} from "contracts/morpho/types/BundleTypes.sol";
import {NestShareMathLib} from "contracts/morpho/libraries/NestShareMathLib.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MockServiceManager} from "test/mock/MockServiceManager.sol";

import {IOracle} from "@morpho/interfaces/IOracle.sol";
import {IMorpho, Id, Market, MarketParams, Position as MorphoPosition} from "@morpho/interfaces/IMorpho.sol";
import {ORACLE_PRICE_SCALE} from "@morpho/libraries/ConstantsLib.sol";
import {MarketParamsLib} from "@morpho/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "@morpho/libraries/SharesMathLib.sol";

interface INestAdapterInheritedMorphoActions {
    function morphoRepay(
        MarketParams calldata marketParams,
        uint256 assets,
        uint256 shares,
        uint256 maxSharePriceE27,
        address onBehalf,
        bytes calldata data
    ) external;

    function morphoWithdrawCollateral(MarketParams calldata marketParams, uint256 assets, address receiver) external;

    function morphoFlashLoan(address token, uint256 assets, bytes calldata data) external;
}

contract MockInitiatorAuthority is Authority {
    mapping(address caller => mapping(address target => mapping(bytes4 selector => bool allowed))) internal _canCall;
    mapping(address initiator => mapping(address target => mapping(bytes4 selector => bool allowed))) internal
        _initiatorCanCall;

    function setCanCall(address caller, address target, bytes4 selector, bool allowed) external {
        _canCall[caller][target][selector] = allowed;
    }

    function canCall(address caller, address target, bytes4 selector) external view returns (bool) {
        return _canCall[caller][target][selector];
    }
}

contract NestAdapterIntegrationTest is Test {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;
    using NestShareMathLib for uint256;

    string internal constant PLUME_RPC_ENV = "PLUME_RPC_URL";

    address internal constant MORPHO = 0x42b18785CE0Aed7BF7Ca43a39471ED4C0A3e0bB5;
    address internal constant BUNDLER3 = 0x5437C8788f4CFbaA55be6FBf30379bc7dd7f69C3;

    address internal constant NALPHA = 0x593cCcA4c4bf58b7526a4C164cEEf4003C6388db;
    address internal constant PUSD = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;
    address internal constant NALPHA_ACCOUNTANT = 0xe0CF451d6E373FF04e8eE3c50340F18AFa6421E1;
    address internal constant WRAPPED_NATIVE_PLACEHOLDER = 0x0000000000000000000000000000000000000001;
    address internal constant TELLER_WITH_MULTI_ASSET_SUPPORT = 0xc9F6a492Fb1D623690Dc065BBcEd6DfB4a324A35;

    address internal constant NALPHA_PUSD_MARKET_ORACLE = 0x7824e4B3E21678f143Ce22308ADfd48d1D3160FB;
    address internal constant NALPHA_PUSD_MARKET_IRM = 0x7420302Ddd469031Cd2282cd64225cCd46F581eA;
    uint256 internal constant NALPHA_PUSD_LLTV = 860_000_000_000_000_000;
    bytes32 internal constant NALPHA_PUSD_MARKET_ID =
        0x7a96549cae736c913d12c78ee4c155c2d2f874031fce5acdd07bdbf23d7644c7;

    uint256 internal constant UNIT = 1e6;
    uint256 internal constant USER_INITIAL_PUSD = 500 * UNIT;
    uint256 internal constant USER_SEED_DEPOSIT_ASSETS = 100 * UNIT;
    uint256 internal constant FLASH_LOAN_ASSETS = 50 * UNIT;
    uint256 internal constant PARTIAL_REPAY_ASSETS = 20 * UNIT;
    uint256 internal constant PARTIAL_WITHDRAW_COLLATERAL = 20 * UNIT;
    uint256 internal constant ATOMIC_NET_COLLATERAL_TO_USER = 10 * UNIT;
    uint256 internal constant MOCK_TELLER_INITIAL_PUSD = 1_000_000 * UNIT;
    uint8 internal constant QUEUE_FLAG_INSUFFICIENT_BALANCE = 1 << 2;
    string internal constant POLICY_ID = "TEST_POLICY_ID";
    address internal constant OLD_TELLER_PREDICATE_PROXY = 0x6104fe10ca937a086ba7AdbD0910A4733d380cB6;

    address internal proxyAdmin = makeAddr("proxyAdmin");
    address internal user = makeAddr("user");
    address internal solver = makeAddr("solver");

    IMorpho internal morpho;
    IBundler3 internal bundler3;
    NestAdapter internal nestAdapter;
    NestVaultPredicateProxy internal predicateProxy;
    MockServiceManager internal serviceManager;
    AtomicQueue internal atomicQueue;
    AtomicSolverV3 internal atomicSolver;
    NestUnlooper internal nestUnlooper;
    MockInitiatorAuthority internal solverAuthority;
    TellerWithMultiAssetSupport internal teller;
    NestVault internal forkVault;
    MarketParams internal marketParams;
    uint256 internal seedShares;

    uint256 internal baselineBundlerPusd;
    uint256 internal baselineBundlerNalpha;

    struct LegacyRequestPlan {
        bool executable;
        uint256 offerAmount;
        uint256 assetsForWant;
        uint256 currentBorrow;
        uint256 currentCollateral;
        uint256 targetBorrow;
        uint256 targetCollateral;
    }

    function setUp() public {
        string memory rpcUrl = vm.envOr(PLUME_RPC_ENV, string("https://rpc.plume.org"));
        vm.createSelectFork(rpcUrl);

        morpho = IMorpho(MORPHO);
        bundler3 = IBundler3(BUNDLER3);
        teller = TellerWithMultiAssetSupport(TELLER_WITH_MULTI_ASSET_SUPPORT);

        marketParams = MarketParams({
            loanToken: PUSD,
            collateralToken: NALPHA,
            oracle: NALPHA_PUSD_MARKET_ORACLE,
            irm: NALPHA_PUSD_MARKET_IRM,
            lltv: NALPHA_PUSD_LLTV
        });

        Id marketId = marketParams.id();
        assertEq(Id.unwrap(marketId), NALPHA_PUSD_MARKET_ID, "market id mismatch");
        Market memory market = morpho.market(marketId);
        assertGt(market.totalSupplyAssets, 0, "nALPHA/pUSD market not found");

        nestAdapter = new NestAdapter(BUNDLER3, MORPHO, WRAPPED_NATIVE_PLACEHOLDER);
        assertEq(address(nestAdapter.MORPHO()), MORPHO, "NestAdapter MORPHO mismatch");
        assertEq(nestAdapter.BUNDLER3(), BUNDLER3, "NestAdapter BUNDLER3 mismatch");
        _deployPredicateProxy();
        _deployAtomicQueueAndSolver();
        _deployNestUnlooper();
        _deployForkNestVault();
        nestUnlooper.setVaultApproval(address(forkVault), true);
        nestUnlooper.setVaultApproval(address(teller), true);
        _seedUserAndApprove();

        baselineBundlerPusd = ERC20(PUSD).balanceOf(BUNDLER3);
        baselineBundlerNalpha = ERC20(NALPHA).balanceOf(BUNDLER3);
    }

    function test_integration_fork_liveMorpho_increaseThenDecreaseInstant() public {
        uint256 flashDepositShares = INestVaultCore(address(forkVault)).previewDeposit(FLASH_LOAN_ASSETS);
        uint256 flashDepositAssets = INestVaultCore(address(forkVault)).previewMint(flashDepositShares);
        uint256 supplyCollateralAssets = seedShares + flashDepositShares;

        (uint256 borrowBeforeIncrease, uint256 collateralBeforeIncrease) = _currentBorrowAssetsAndCollateral(user);
        Call[] memory increaseBundle = _buildBundle({
            initiator: user,
            owner: user,
            targetBorrow: borrowBeforeIncrease + flashDepositAssets,
            targetCollateral: collateralBeforeIncrease + supplyCollateralAssets,
            instantRedeem: false,
            legacyRedemption: false,
            extraDepositLoanAssets: 0,
            extraRepayLoanAssets: 0,
            extraCollateral: seedShares
        });
        vm.prank(user);
        bundler3.multicall(increaseBundle);

        Id id = marketParams.id();
        MorphoPosition memory positionAfterIncrease = morpho.position(id, user);
        assertGt(positionAfterIncrease.collateral, 0, "missing collateral after increase");
        assertGt(uint256(positionAfterIncrease.borrowShares), 0, "missing borrow shares after increase");

        Market memory marketAfterIncrease = morpho.market(id);
        uint256 borrowAssetsAfterIncrease = uint256(positionAfterIncrease.borrowShares)
            .toAssetsUp(marketAfterIncrease.totalBorrowAssets, marketAfterIncrease.totalBorrowShares);
        assertApproxEqAbs(borrowAssetsAfterIncrease, flashDepositAssets, 2, "borrow assets mismatch after increase");

        _seedInstantRedeemLiquidity(FLASH_LOAN_ASSETS);

        uint256 repayAssets = PARTIAL_REPAY_ASSETS;
        uint256 withdrawCollateralAssets = PARTIAL_WITHDRAW_COLLATERAL;

        (uint256 borrowBeforeDecrease, uint256 collateralBeforeDecrease) = _currentBorrowAssetsAndCollateral(user);

        Call[] memory decreaseBundle = _buildBundle({
            initiator: user,
            owner: user,
            targetBorrow: borrowBeforeDecrease - repayAssets,
            targetCollateral: collateralBeforeDecrease - withdrawCollateralAssets,
            instantRedeem: true,
            legacyRedemption: false,
            extraDepositLoanAssets: 0,
            extraRepayLoanAssets: 0,
            extraCollateral: 0
        });
        (,, bytes memory callbackData) = abi.decode(_args(decreaseBundle[0].data), (address, uint256, bytes));
        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
        assertEq(_selector(callbackBundle[1].data), MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector);
        assertEq(_selector(callbackBundle[2].data), NestAdapter.nestInstantRedeem.selector);

        vm.prank(user);
        bundler3.multicall(decreaseBundle);

        MorphoPosition memory positionAfterDecrease = morpho.position(id, user);
        assertLt(
            uint256(positionAfterDecrease.borrowShares),
            uint256(positionAfterIncrease.borrowShares),
            "borrow should decrease"
        );
        assertLt(
            uint256(positionAfterDecrease.collateral),
            uint256(positionAfterIncrease.collateral),
            "collateral should decrease"
        );

        _assertNoAdapterResidualDelta();
    }

    function test_integration_fork_liveMorpho_increaseThenDecreaseRedeem_solverPath() public {
        uint256 flashDepositShares = INestVaultCore(address(forkVault)).previewDeposit(FLASH_LOAN_ASSETS);
        uint256 flashDepositAssets = INestVaultCore(address(forkVault)).previewMint(flashDepositShares);
        uint256 supplyCollateralAssets = seedShares + flashDepositShares;

        (uint256 borrowBeforeIncrease, uint256 collateralBeforeIncrease) = _currentBorrowAssetsAndCollateral(user);
        Call[] memory increaseBundle = _buildBundle({
            initiator: user,
            owner: user,
            targetBorrow: borrowBeforeIncrease + flashDepositAssets,
            targetCollateral: collateralBeforeIncrease + supplyCollateralAssets,
            instantRedeem: false,
            legacyRedemption: false,
            extraDepositLoanAssets: 0,
            extraRepayLoanAssets: 0,
            extraCollateral: seedShares
        });
        vm.prank(user);
        bundler3.multicall(increaseBundle);

        Id id = marketParams.id();
        MorphoPosition memory positionAfterIncrease = morpho.position(id, user);
        assertGt(positionAfterIncrease.collateral, 0, "missing collateral after increase");
        assertGt(uint256(positionAfterIncrease.borrowShares), 0, "missing borrow shares after increase");

        _seedInstantRedeemLiquidity(FLASH_LOAN_ASSETS);

        uint256 repayAssets = PARTIAL_REPAY_ASSETS;
        uint256 withdrawCollateralAssets = PARTIAL_WITHDRAW_COLLATERAL;

        (uint256 borrowBeforeDecrease, uint256 collateralBeforeDecrease) = _currentBorrowAssetsAndCollateral(user);

        Call[] memory decreaseBundle = _buildBundle({
            initiator: solver,
            owner: user,
            targetBorrow: borrowBeforeDecrease - repayAssets,
            targetCollateral: collateralBeforeDecrease - withdrawCollateralAssets,
            instantRedeem: true,
            legacyRedemption: false,
            extraDepositLoanAssets: 0,
            extraRepayLoanAssets: 0,
            extraCollateral: 0
        });
        (,, bytes memory callbackData) = abi.decode(_args(decreaseBundle[0].data), (address, uint256, bytes));
        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
        assertEq(_selector(callbackBundle[1].data), MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector);
        assertEq(_selector(callbackBundle[2].data), NestAdapter.nestInstantRedeem.selector);

        vm.prank(solver);
        bundler3.multicall(decreaseBundle);

        MorphoPosition memory positionAfterDecrease = morpho.position(id, user);
        assertLt(
            uint256(positionAfterDecrease.borrowShares),
            uint256(positionAfterIncrease.borrowShares),
            "borrow should decrease"
        );
        assertLt(
            uint256(positionAfterDecrease.collateral),
            uint256(positionAfterIncrease.collateral),
            "collateral should decrease"
        );

        _assertNoAdapterResidualDelta();
    }

    function test_integration_fork_liveMorpho_atomicQueueAsyncRedeem_solverPath() public {
        uint256 flashDepositShares = INestVaultCore(address(forkVault)).previewDeposit(FLASH_LOAN_ASSETS);
        uint256 flashDepositAssets = INestVaultCore(address(forkVault)).previewMint(flashDepositShares);
        uint256 supplyCollateralAssets = seedShares + flashDepositShares;

        (uint256 borrowBeforeIncrease, uint256 collateralBeforeIncrease) = _currentBorrowAssetsAndCollateral(user);
        Call[] memory increaseBundle = _buildBundle({
            initiator: user,
            owner: user,
            targetBorrow: borrowBeforeIncrease + flashDepositAssets,
            targetCollateral: collateralBeforeIncrease + supplyCollateralAssets,
            instantRedeem: false,
            legacyRedemption: false,
            extraDepositLoanAssets: 0,
            extraRepayLoanAssets: 0,
            extraCollateral: seedShares
        });
        vm.prank(user);
        bundler3.multicall(increaseBundle);

        Id id = marketParams.id();
        MorphoPosition memory positionAfterIncrease = morpho.position(id, user);
        assertGt(positionAfterIncrease.collateral, 0, "missing collateral after increase");
        assertGt(uint256(positionAfterIncrease.borrowShares), 0, "missing borrow shares after increase");

        uint256 queueOfferShares;
        vm.startPrank(user);
        queueOfferShares = INestVaultCore(address(forkVault)).deposit(PARTIAL_REPAY_ASSETS, user);
        assertGt(queueOfferShares, 0, "queue offer shares should be nonzero");

        uint256 atomicPrice = teller.accountant().getRateInQuote(ERC20(PUSD));
        assertGt(atomicPrice, 0, "atomic price should be nonzero");
        assertLe(atomicPrice, type(uint88).max, "atomic price overflow");

        ERC20(NALPHA).approve(address(atomicQueue), type(uint256).max);
        ERC20(PUSD).approve(address(nestAdapter), type(uint256).max);

        AtomicQueue.AtomicRequest memory atomicRequest = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 1 days),
            atomicPrice: uint88(atomicPrice),
            offerAmount: uint96(queueOfferShares),
            inSolve: false
        });
        atomicQueue.updateAtomicRequest(ERC20(NALPHA), ERC20(PUSD), atomicRequest);
        vm.stopPrank();

        AtomicQueue.AtomicRequest memory requestBefore =
            atomicQueue.getUserAtomicRequest(user, ERC20(NALPHA), ERC20(PUSD));
        assertEq(requestBefore.offerAmount, queueOfferShares, "atomic request offer mismatch");

        uint256 repayAssets = uint256(requestBefore.atomicPrice) * queueOfferShares / UNIT;
        uint256 withdrawCollateralAssets = queueOfferShares + ATOMIC_NET_COLLATERAL_TO_USER;

        Call[] memory callbackBundle = new Call[](4);
        callbackBundle[0] = _call({
            to: address(nestAdapter),
            data: abi.encodeCall(
                INestAdapterInheritedMorphoActions.morphoRepay,
                (marketParams, repayAssets, 0, type(uint256).max, user, bytes(""))
            ),
            callbackHash: bytes32(0)
        });
        callbackBundle[1] = _call({
            to: address(nestAdapter),
            data: abi.encodeCall(
                MorphoAdapter.morphoWithdrawCollateralOnBehalf,
                (marketParams, withdrawCollateralAssets, user, address(nestAdapter))
            ),
            callbackHash: bytes32(0)
        });
        callbackBundle[2] = _call({
            to: address(nestAdapter),
            data: abi.encodeCall(
                NestAdapter.atomicSolverRedeemSolve,
                (atomicSolver, atomicQueue, teller, marketParams, user, address(nestAdapter), repayAssets, repayAssets)
            ),
            callbackHash: bytes32(0)
        });
        callbackBundle[3] = _call({
            to: address(nestAdapter),
            data: abi.encodeWithSignature("erc20Transfer(address,address,uint256)", NALPHA, user, type(uint256).max),
            callbackHash: bytes32(0)
        });

        bytes memory callbackData = abi.encode(callbackBundle);
        Call[] memory bundle = new Call[](1);
        bundle[0] = _call({
            to: address(nestAdapter),
            data: abi.encodeCall(INestAdapterInheritedMorphoActions.morphoFlashLoan, (PUSD, repayAssets, callbackData)),
            callbackHash: keccak256(callbackData)
        });

        (,, bytes memory decodedCallbackData) = abi.decode(_args(bundle[0].data), (address, uint256, bytes));
        Call[] memory decodedCallbackBundle = abi.decode(decodedCallbackData, (Call[]));
        assertEq(decodedCallbackBundle.length, 4, "atomic callback length mismatch");
        assertEq(_selector(decodedCallbackBundle[0].data), INestAdapterInheritedMorphoActions.morphoRepay.selector);
        assertEq(_selector(decodedCallbackBundle[1].data), MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector);
        assertEq(_selector(decodedCallbackBundle[2].data), NestAdapter.atomicSolverRedeemSolve.selector);
        assertEq(_selector(decodedCallbackBundle[3].data), bytes4(keccak256("erc20Transfer(address,address,uint256)")));

        uint256 userNalphaBeforeSolve = ERC20(NALPHA).balanceOf(user);
        uint256 userPusdBeforeSolve = ERC20(PUSD).balanceOf(user);

        vm.prank(solver);
        bundler3.multicall(bundle);

        MorphoPosition memory positionAfterDecrease = morpho.position(id, user);
        assertLt(
            uint256(positionAfterDecrease.borrowShares),
            uint256(positionAfterIncrease.borrowShares),
            "borrow should decrease"
        );
        assertLt(
            uint256(positionAfterDecrease.collateral),
            uint256(positionAfterIncrease.collateral),
            "collateral should decrease"
        );
        assertEq(
            uint256(positionAfterIncrease.collateral) - uint256(positionAfterDecrease.collateral),
            withdrawCollateralAssets,
            "collateral decrease mismatch"
        );

        assertEq(ERC20(PUSD).balanceOf(user), userPusdBeforeSolve, "user pUSD should net to zero");
        assertEq(
            ERC20(NALPHA).balanceOf(user),
            userNalphaBeforeSolve + ATOMIC_NET_COLLATERAL_TO_USER,
            "user nALPHA net delta mismatch"
        );

        AtomicQueue.AtomicRequest memory requestAfter =
            atomicQueue.getUserAtomicRequest(user, ERC20(NALPHA), ERC20(PUSD));
        assertEq(requestAfter.offerAmount, 0, "atomic request should be consumed");
        assertFalse(requestAfter.inSolve, "atomic request should not remain in solve");
        assertEq(
            ERC20(PUSD).allowance(address(nestAdapter), address(atomicSolver)),
            0,
            "adapter atomic solver allowance should reset"
        );

        _assertNoAdapterResidualDelta();
    }

    function test_integration_fork_liveMorpho_atomicRequestDriven_legacyAsync_partialDeleverage_withBorrowAccrual()
        public
    {
        _openLeveragedPositionForRequestDriven();

        uint256 queueOfferShares = _quoteQueueOfferShares(PARTIAL_REPAY_ASSETS);
        _queueAtomicRequestFromUser(queueOfferShares, UNIT * 8 / 10);

        (uint256 borrowBeforeAccrual,) = _currentBorrowAssetsAndCollateral(user);
        vm.warp(block.timestamp + 1 days);
        morpho.accrueInterest(marketParams);
        (uint256 borrowAfterAccrual,) = _currentBorrowAssetsAndCollateral(user);
        assertGt(borrowAfterAccrual, borrowBeforeAccrual, "borrow should accrue");

        LegacyRequestPlan memory plan = _planLegacyBundleFromAtomicRequest(user);
        assertTrue(plan.executable, "request plan should be executable");
        assertLt(plan.assetsForWant, plan.currentBorrow, "expected partial deleverage");

        Call[] memory bundle = _buildLegacyBundleFromRequestPlan(plan, user);
        (,, bytes memory callbackData) = abi.decode(_args(bundle[0].data), (address, uint256, bytes));
        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
        assertEq(callbackBundle.length, 3, "legacy callback length mismatch");
        assertEq(_selector(callbackBundle[0].data), INestAdapterInheritedMorphoActions.morphoRepay.selector);
        assertEq(_selector(callbackBundle[1].data), MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector);
        assertEq(_selector(callbackBundle[2].data), NestAdapter.atomicSolverRedeemSolve.selector);

        Call[] memory bundleWithSweeps = _appendAdapterSweeps(bundle, user);

        vm.prank(solver);
        bundler3.multicall(bundleWithSweeps);

        (uint256 borrowAfterSolve, uint256 collateralAfterSolve) = _currentBorrowAssetsAndCollateral(user);
        assertLt(borrowAfterSolve, plan.currentBorrow, "borrow should decrease");
        assertGt(borrowAfterSolve, 0, "borrow should remain after partial deleverage");
        assertLt(collateralAfterSolve, plan.currentCollateral, "collateral should decrease");

        AtomicQueue.AtomicRequest memory requestAfter =
            atomicQueue.getUserAtomicRequest(user, ERC20(NALPHA), ERC20(PUSD));
        assertEq(requestAfter.offerAmount, 0, "atomic request should be consumed");
        assertFalse(requestAfter.inSolve, "atomic request should not remain in solve");

        _assertNoAdapterResidualDelta();
    }

    function test_integration_fork_liveMorpho_atomicRequestDriven_legacyAsync_oversizedRequest_skipsAndKeepsRequest()
        public
    {
        _openLeveragedPositionForRequestDriven();

        uint256 queueOfferShares = _quoteQueueOfferShares(30 * UNIT);
        _queueAtomicRequestFromUser(queueOfferShares, 2 * UNIT);

        LegacyRequestPlan memory plan = _planLegacyBundleFromAtomicRequest(user);
        assertFalse(plan.executable, "oversized request should be skipped");
        assertGt(plan.assetsForWant, plan.currentBorrow, "request should exceed current borrow");

        (uint256 borrowBefore, uint256 collateralBefore) = _currentBorrowAssetsAndCollateral(user);
        AtomicQueue.AtomicRequest memory requestBefore =
            atomicQueue.getUserAtomicRequest(user, ERC20(NALPHA), ERC20(PUSD));

        (uint256 borrowAfter, uint256 collateralAfter) = _currentBorrowAssetsAndCollateral(user);
        assertEq(borrowAfter, borrowBefore, "borrow should remain unchanged");
        assertEq(collateralAfter, collateralBefore, "collateral should remain unchanged");

        AtomicQueue.AtomicRequest memory requestAfter =
            atomicQueue.getUserAtomicRequest(user, ERC20(NALPHA), ERC20(PUSD));
        assertEq(requestAfter.offerAmount, requestBefore.offerAmount, "request should remain queued");
        assertFalse(requestAfter.inSolve, "request should not enter solve");

        _assertNoAdapterResidualDelta();
    }

    function test_integration_fork_liveMorpho_atomicRequestDriven_legacyAsync_surplusSweptBackToUser() public {
        _openLeveragedPositionForRequestDriven();

        uint256 queueOfferShares = _quoteQueueOfferShares(PARTIAL_REPAY_ASSETS);
        _queueAtomicRequestFromUser(queueOfferShares, UNIT / 2);

        LegacyRequestPlan memory plan = _planLegacyBundleFromAtomicRequest(user);
        assertTrue(plan.executable, "request plan should be executable");
        assertLt(plan.assetsForWant, plan.offerAmount, "expected surplus redemption path");

        uint256 userPusdBeforeSolve = ERC20(PUSD).balanceOf(user);

        Call[] memory bundle = _buildLegacyBundleFromRequestPlan(plan, user);
        Call[] memory bundleWithSweeps = _appendAdapterSweeps(bundle, user);

        vm.prank(solver);
        bundler3.multicall(bundleWithSweeps);

        uint256 userPusdAfterSolve = ERC20(PUSD).balanceOf(user);
        assertGt(userPusdAfterSolve, userPusdBeforeSolve, "user should receive swept pUSD surplus");

        AtomicQueue.AtomicRequest memory requestAfter =
            atomicQueue.getUserAtomicRequest(user, ERC20(NALPHA), ERC20(PUSD));
        assertEq(requestAfter.offerAmount, 0, "atomic request should be consumed");
        assertFalse(requestAfter.inSolve, "atomic request should not remain in solve");

        _assertNoAdapterResidualDelta();
    }

    function test_integration_fork_liveMorpho_nestUnlooper_executesValidAtomicRequest() public {
        _assertNestUnlooperExecutes(PARTIAL_REPAY_ASSETS, UNIT / 2, true);
    }

    function test_integration_fork_liveMorpho_nestUnlooper_validRequestSweep() public {
        uint256[] memory requestAssets = new uint256[](2);
        requestAssets[0] = 5 * UNIT;
        requestAssets[1] = 30 * UNIT;

        uint256[] memory atomicPrices = new uint256[](3);
        atomicPrices[0] = UNIT / 2;
        atomicPrices[1] = UNIT * 8 / 10;
        atomicPrices[2] = UNIT;

        uint256 baseSnapshot = vm.snapshotState();

        for (uint256 i; i < requestAssets.length; ++i) {
            for (uint256 j; j < atomicPrices.length; ++j) {
                vm.revertToState(baseSnapshot);
                baseSnapshot = vm.snapshotState();

                _assertNestUnlooperExecutes(requestAssets[i], atomicPrices[j], false);
            }
        }
    }

    function test_integration_fork_liveMorpho_nestUnlooper_modernAsyncRedeem_targetLeverage() public {
        _openLeveragedPositionForRequestDriven();
        uint64 deadline = uint64(block.timestamp + 1 days);

        vm.prank(user);
        morpho.setAuthorization(address(nestUnlooper), true);

        uint16 targetLeverageBps = uint16(_midTargetLeverageBps(user));
        vm.prank(user);
        nestUnlooper.updateUnloopRequest(marketParams, targetLeverageBps, 0, deadline);

        NestUnlooper.UnloopRequest memory storedRequest = nestUnlooper.getUnloopRequest(user, marketParams);
        assertEq(storedRequest.leverageBps, targetLeverageBps, "stored request leverage mismatch");
        assertEq(storedRequest.deadline, deadline, "stored request deadline mismatch");

        Bundle memory expectedBundle =
            nestUnlooper.getAsyncBundle(marketParams, INestVaultCore(address(forkVault)), teller, user, false);
        assertFalse(expectedBundle.route.legacyRedemption, "expected modern route");
        assertGt(expectedBundle.ma.repay, 0, "expected repay");
        assertGt(expectedBundle.ma.withdrawCollateral, 0, "expected collateral withdrawal");
        assertGt(expectedBundle.va.redeem, 0, "expected vault redeem");

        Call[] memory expectedCalls =
            nestUnlooper.getAsyncBundleCalls(marketParams, INestVaultCore(address(forkVault)), teller, user, false);
        assertEq(expectedCalls.length, 2, "top-level call count");
        assertEq(_selector(expectedCalls[0].data), INestAdapterInheritedMorphoActions.morphoFlashLoan.selector);
        assertEq(_selector(expectedCalls[1].data), NestAdapter.adapterSweep.selector);

        (,, bytes memory callbackData) = abi.decode(_args(expectedCalls[0].data), (address, uint256, bytes));
        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
        assertEq(callbackBundle.length, 3, "callback length mismatch");
        assertEq(_selector(callbackBundle[0].data), INestAdapterInheritedMorphoActions.morphoRepay.selector);
        assertEq(_selector(callbackBundle[1].data), MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector);
        assertEq(_selector(callbackBundle[2].data), NestAdapter.nestRequestAndRedeem.selector);

        (, uint256 withdrawAssets, address withdrawOnBehalf, address withdrawReceiver) =
            abi.decode(_args(callbackBundle[1].data), (MarketParams, uint256, address, address));
        assertEq(withdrawAssets, expectedBundle.ma.withdrawCollateral, "withdraw amount mismatch");
        assertEq(withdrawOnBehalf, user, "withdraw owner mismatch");
        assertEq(withdrawReceiver, address(nestAdapter), "withdraw receiver mismatch");

        (uint256 borrowBefore, uint256 collateralBefore) = _currentBorrowAssetsAndCollateral(user);

        Call[] memory returned =
            nestUnlooper.execute(marketParams, INestVaultCore(address(forkVault)), teller, user, false);
        assertEq(keccak256(abi.encode(returned)), keccak256(abi.encode(expectedCalls)), "returned calls mismatch");
        assertEq(nestUnlooper.getUnloopRequest(user, marketParams).deadline, 0, "stored request should clear");

        (uint256 borrowAfter, uint256 collateralAfter) = _currentBorrowAssetsAndCollateral(user);
        assertLt(borrowAfter, borrowBefore, "borrow should decrease");
        assertLt(collateralAfter, collateralBefore, "collateral should decrease");
        assertApproxEqAbs(borrowAfter, expectedBundle.intent.target.loan, 2, "borrow target mismatch");
        assertEq(collateralAfter, expectedBundle.intent.target.collateral, "collateral target mismatch");

        AtomicQueue.AtomicRequest memory requestAfter =
            atomicQueue.getUserAtomicRequest(user, ERC20(NALPHA), ERC20(PUSD));
        assertEq(requestAfter.offerAmount, 0, "modern route should not consume queue request");
        assertFalse(requestAfter.inSolve, "modern route should not touch queue solve state");

        _assertNoAdapterResidualDelta();
    }

    function test_integration_fork_liveMorpho_nestUnlooper_modernAsyncRedeem_fullExit() public {
        _openLeveragedPositionForRequestDriven();
        uint64 deadline = uint64(block.timestamp + 1 days);

        vm.prank(user);
        morpho.setAuthorization(address(nestUnlooper), true);

        vm.prank(user);
        nestUnlooper.updateUnloopRequest(marketParams, 0, 0, deadline);

        NestUnlooper.UnloopRequest memory storedRequest = nestUnlooper.getUnloopRequest(user, marketParams);
        assertEq(storedRequest.leverageBps, 0, "stored request leverage mismatch");
        assertEq(storedRequest.deadline, deadline, "stored request deadline mismatch");

        Bundle memory expectedBundle =
            nestUnlooper.getAsyncBundle(marketParams, INestVaultCore(address(forkVault)), teller, user, false);
        assertFalse(expectedBundle.route.legacyRedemption, "expected modern route");
        assertEq(expectedBundle.intent.target.loan, 0, "expected zero borrow target");
        assertEq(expectedBundle.intent.target.collateral, 0, "expected zero collateral target");
        assertGt(expectedBundle.ma.repay, 0, "expected repay");
        assertGt(expectedBundle.ma.withdrawCollateral, 0, "expected collateral withdrawal");
        assertGt(expectedBundle.va.redeem, 0, "expected vault redeem");

        Call[] memory expectedCalls =
            nestUnlooper.getAsyncBundleCalls(marketParams, INestVaultCore(address(forkVault)), teller, user, false);
        assertEq(expectedCalls.length, 2, "top-level call count");
        assertEq(_selector(expectedCalls[0].data), INestAdapterInheritedMorphoActions.morphoFlashLoan.selector);
        assertEq(_selector(expectedCalls[1].data), NestAdapter.adapterSweep.selector);

        (,, bytes memory callbackData) = abi.decode(_args(expectedCalls[0].data), (address, uint256, bytes));
        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
        assertEq(callbackBundle.length, 3, "callback length mismatch");
        assertEq(_selector(callbackBundle[0].data), INestAdapterInheritedMorphoActions.morphoRepay.selector);
        assertEq(_selector(callbackBundle[1].data), MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector);
        assertEq(_selector(callbackBundle[2].data), NestAdapter.nestRequestAndRedeem.selector);

        (, uint256 withdrawAssets, address withdrawOnBehalf, address withdrawReceiver) =
            abi.decode(_args(callbackBundle[1].data), (MarketParams, uint256, address, address));
        assertEq(withdrawAssets, expectedBundle.ma.withdrawCollateral, "withdraw amount mismatch");
        assertEq(withdrawOnBehalf, user, "withdraw owner mismatch");
        assertEq(withdrawReceiver, address(nestAdapter), "withdraw receiver mismatch");

        (uint256 borrowBefore, uint256 collateralBefore) = _currentBorrowAssetsAndCollateral(user);

        Call[] memory returned =
            nestUnlooper.execute(marketParams, INestVaultCore(address(forkVault)), teller, user, false);
        assertEq(keccak256(abi.encode(returned)), keccak256(abi.encode(expectedCalls)), "returned calls mismatch");
        assertEq(nestUnlooper.getUnloopRequest(user, marketParams).deadline, 0, "stored request should clear");

        (uint256 borrowAfter, uint256 collateralAfter) = _currentBorrowAssetsAndCollateral(user);
        assertLt(borrowAfter, borrowBefore, "borrow should decrease");
        assertLt(collateralAfter, collateralBefore, "collateral should decrease");
        assertApproxEqAbs(borrowAfter, expectedBundle.intent.target.loan, 2, "borrow target mismatch");
        assertEq(collateralAfter, expectedBundle.intent.target.collateral, "collateral target mismatch");

        AtomicQueue.AtomicRequest memory requestAfter =
            atomicQueue.getUserAtomicRequest(user, ERC20(NALPHA), ERC20(PUSD));
        assertEq(requestAfter.offerAmount, 0, "modern route should not consume queue request");
        assertFalse(requestAfter.inSolve, "modern route should not touch queue solve state");

        _assertNoAdapterResidualDelta();
    }

    function test_integration_fork_tellerPredicateDeposit_oldProxy_revertsUnauthorizedInitiatorPredicate() public {
        uint256 depositAssets = UNIT;
        PredicateMessage memory predicateMsg = _emptyPredicateMessage();
        vm.mockCall(
            OLD_TELLER_PREDICATE_PROXY,
            abi.encodeCall(ITellerPredicateProxy.genericUserCheckPredicate, (user, predicateMsg)),
            abi.encode(false)
        );

        Call[] memory increaseBundle = new Call[](2);
        increaseBundle[0] = _call({
            to: address(nestAdapter),
            data: abi.encodeWithSignature(
                "erc20TransferFrom(address,address,uint256)", PUSD, address(nestAdapter), depositAssets
            ),
            callbackHash: bytes32(0)
        });
        increaseBundle[1] = _call({
            to: address(nestAdapter),
            data: abi.encodeCall(
                NestAdapter.tellerPredicateDeposit,
                (
                    ITellerPredicateProxy(OLD_TELLER_PREDICATE_PROXY),
                    ERC20(PUSD),
                    depositAssets,
                    0,
                    user,
                    CrossChainTellerBase(payable(address(teller))),
                    predicateMsg
                )
            ),
            callbackHash: bytes32(0)
        });

        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        vm.prank(user);
        bundler3.multicall(increaseBundle);
    }

    function test_integration_fork_tellerPredicateDeposit_oldProxy_succeeds() public {
        uint256 depositAssets = UNIT;
        PredicateMessage memory predicateMsg = _emptyPredicateMessage();

        vm.mockCall(
            OLD_TELLER_PREDICATE_PROXY,
            abi.encodeCall(ITellerPredicateProxy.genericUserCheckPredicate, (user, predicateMsg)),
            abi.encode(true)
        );

        uint256 userPusdBefore = ERC20(PUSD).balanceOf(user);
        uint256 adapterPusdBefore = ERC20(PUSD).balanceOf(address(nestAdapter));

        Call[] memory increaseBundle = new Call[](2);
        increaseBundle[0] = _call({
            to: address(nestAdapter),
            data: abi.encodeWithSignature(
                "erc20TransferFrom(address,address,uint256)", PUSD, address(nestAdapter), depositAssets
            ),
            callbackHash: bytes32(0)
        });
        increaseBundle[1] = _call({
            to: address(nestAdapter),
            data: abi.encodeCall(
                NestAdapter.tellerPredicateDeposit,
                (
                    ITellerPredicateProxy(OLD_TELLER_PREDICATE_PROXY),
                    ERC20(PUSD),
                    depositAssets,
                    0,
                    user,
                    CrossChainTellerBase(payable(address(teller))),
                    predicateMsg
                )
            ),
            callbackHash: bytes32(0)
        });

        vm.prank(user);
        bundler3.multicall(increaseBundle);

        assertEq(ERC20(PUSD).balanceOf(user), userPusdBefore - depositAssets, "user pUSD delta mismatch");
        assertEq(ERC20(PUSD).balanceOf(address(nestAdapter)), adapterPusdBefore, "adapter pUSD delta mismatch");
        assertEq(
            ERC20(PUSD).allowance(address(nestAdapter), address(teller.vault())),
            0,
            "teller vault allowance should be reset"
        );
    }

    function _openLeveragedPositionForRequestDriven() internal {
        uint256 flashDepositShares = INestVaultCore(address(forkVault)).previewDeposit(FLASH_LOAN_ASSETS);
        uint256 flashDepositAssets = INestVaultCore(address(forkVault)).previewMint(flashDepositShares);
        uint256 supplyCollateralAssets = seedShares + flashDepositShares;

        (uint256 borrowBeforeIncrease, uint256 collateralBeforeIncrease) = _currentBorrowAssetsAndCollateral(user);
        Call[] memory increaseBundle = _buildBundle({
            initiator: user,
            owner: user,
            targetBorrow: borrowBeforeIncrease + flashDepositAssets,
            targetCollateral: collateralBeforeIncrease + supplyCollateralAssets,
            instantRedeem: false,
            legacyRedemption: false,
            extraDepositLoanAssets: 0,
            extraRepayLoanAssets: 0,
            extraCollateral: seedShares
        });
        vm.prank(user);
        bundler3.multicall(increaseBundle);

        Id id = marketParams.id();
        MorphoPosition memory positionAfterIncrease = morpho.position(id, user);
        assertGt(positionAfterIncrease.collateral, 0, "missing collateral after increase");
        assertGt(uint256(positionAfterIncrease.borrowShares), 0, "missing borrow shares after increase");
    }

    function _quoteQueueOfferShares(uint256 depositAssets) internal view returns (uint256 queueOfferShares) {
        queueOfferShares = INestVaultCore(address(forkVault)).previewDeposit(depositAssets);
        assertGt(queueOfferShares, 0, "queue offer shares should be nonzero");
    }

    function _queueAtomicRequestFromUser(uint256 offerAmount, uint256 atomicPrice) internal {
        assertLe(offerAmount, type(uint96).max, "offer amount overflow");
        assertLe(atomicPrice, type(uint88).max, "atomic price overflow");

        vm.startPrank(user);
        ERC20(NALPHA).approve(address(atomicQueue), type(uint256).max);
        ERC20(PUSD).approve(address(nestAdapter), type(uint256).max);

        AtomicQueue.AtomicRequest memory atomicRequest = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 7 days),
            atomicPrice: uint88(atomicPrice),
            offerAmount: uint96(offerAmount),
            inSolve: false
        });
        atomicQueue.updateAtomicRequest(ERC20(NALPHA), ERC20(PUSD), atomicRequest);
        vm.stopPrank();
    }

    function _atomicRequestAssetsForWant(AtomicQueue.AtomicRequest memory request) internal view returns (uint256) {
        uint256 offerScale = 10 ** uint256(ERC20(NALPHA).decimals());
        return uint256(request.atomicPrice) * uint256(request.offerAmount) / offerScale;
    }

    function _planLegacyBundleFromAtomicRequest(address owner) internal view returns (LegacyRequestPlan memory plan) {
        AtomicQueue.AtomicRequest memory request = atomicQueue.getUserAtomicRequest(owner, ERC20(NALPHA), ERC20(PUSD));
        plan.offerAmount = uint256(request.offerAmount);
        plan.assetsForWant = _atomicRequestAssetsForWant(request);
        (plan.currentBorrow, plan.currentCollateral) = _currentBorrowAssetsAndCollateral(owner);

        if (!_isLegacyAtomicRequestConfigured(owner, request)) return plan;
        if (plan.assetsForWant > plan.currentBorrow) return plan;
        if (plan.offerAmount > plan.currentCollateral) return plan;

        uint256 repayAssetsForBundle =
            plan.assetsForWant.convertToAssets(INestVaultCore(address(forkVault)), Math.Rounding.Ceil);
        if (repayAssetsForBundle > plan.currentBorrow) return plan;

        plan.executable = true;
        plan.targetBorrow = plan.currentBorrow - repayAssetsForBundle;
        plan.targetCollateral = plan.currentCollateral - plan.offerAmount;
    }

    function _isLegacyAtomicRequestConfigured(address owner, AtomicQueue.AtomicRequest memory request)
        internal
        view
        returns (bool)
    {
        if (request.deadline < block.timestamp) return false;
        if (request.inSolve) return false;
        if (request.offerAmount == 0) return false;
        if (request.atomicPrice == 0) return false;
        if (ERC20(NALPHA).allowance(owner, address(atomicQueue)) < uint256(request.offerAmount)) return false;

        return ERC20(PUSD).allowance(owner, address(nestAdapter)) != 0;
    }

    function _buildLegacyBundleFromRequestPlan(LegacyRequestPlan memory plan, address owner)
        internal
        view
        returns (Call[] memory calls)
    {
        require(plan.executable, "request plan not executable");
        uint256 repayAssets = plan.currentBorrow - plan.targetBorrow;
        uint256 withdrawCollateralLoanAssets =
            plan.offerAmount.convertToAssets(INestVaultCore(address(forkVault)), Math.Rounding.Floor);
        uint256 extraRepayLoanAssets =
            repayAssets > withdrawCollateralLoanAssets ? repayAssets - withdrawCollateralLoanAssets : 0;

        calls = _buildBundle({
            initiator: solver,
            owner: owner,
            targetBorrow: plan.targetBorrow,
            targetCollateral: plan.targetCollateral,
            instantRedeem: false,
            legacyRedemption: true,
            extraDepositLoanAssets: 0,
            extraRepayLoanAssets: extraRepayLoanAssets,
            extraCollateral: 0
        });
    }

    function _appendAdapterSweeps(Call[] memory bundle, address receiver) internal view returns (Call[] memory out) {
        out = new Call[](bundle.length + 2);
        for (uint256 i; i < bundle.length; ++i) {
            out[i] = bundle[i];
        }
        out[bundle.length] = _call({
            to: address(nestAdapter),
            data: abi.encodeWithSignature(
                "erc20Transfer(address,address,uint256)", NALPHA, receiver, type(uint256).max
            ),
            callbackHash: bytes32(0)
        });
        out[bundle.length + 1] = _call({
            to: address(nestAdapter),
            data: abi.encodeWithSignature("erc20Transfer(address,address,uint256)", PUSD, receiver, type(uint256).max),
            callbackHash: bytes32(0)
        });
    }

    function _assertNestUnlooperExecutes(uint256 requestAssets, uint256 atomicPrice, bool expectStrictSurplus)
        internal
    {
        _openLeveragedPositionForRequestDriven();

        uint256 queueOfferShares = _quoteQueueOfferShares(requestAssets);
        _queueAtomicRequestFromUser(queueOfferShares, atomicPrice);

        vm.prank(user);
        morpho.setAuthorization(address(nestUnlooper), true);

        address[] memory users = new address[](1);
        users[0] = user;
        (AtomicQueue.SolveMetaData[] memory metaData,,) =
            atomicQueue.viewSolveMetaData(ERC20(NALPHA), ERC20(PUSD), users);
        assertEq(metaData.length, 1, "solve metadata length mismatch");
        assertEq(metaData[0].flags, QUEUE_FLAG_INSUFFICIENT_BALANCE, "expected insufficient-balance-only flag");
        assertEq(metaData[0].assetsToOffer, queueOfferShares, "solve metadata offer mismatch");

        Call[] memory expected =
            nestUnlooper.getAsyncBundleCalls(marketParams, INestVaultCore(address(forkVault)), teller, user, true);
        assertEq(expected.length, 2, "top-level call count");
        assertEq(_selector(expected[0].data), INestAdapterInheritedMorphoActions.morphoFlashLoan.selector);
        assertEq(_selector(expected[1].data), NestAdapter.adapterSweep.selector);

        (,, bytes memory callbackData) = abi.decode(_args(expected[0].data), (address, uint256, bytes));
        Call[] memory callbackBundle = abi.decode(callbackData, (Call[]));
        assertEq(callbackBundle.length, 3, "callback length mismatch");
        assertEq(_selector(callbackBundle[0].data), INestAdapterInheritedMorphoActions.morphoRepay.selector);
        assertEq(_selector(callbackBundle[1].data), MorphoAdapter.morphoWithdrawCollateralOnBehalf.selector);
        assertEq(_selector(callbackBundle[2].data), NestAdapter.atomicSolverRedeemSolve.selector);

        (uint256 borrowBefore, uint256 collateralBefore) = _currentBorrowAssetsAndCollateral(user);
        uint256 userPusdBefore = ERC20(PUSD).balanceOf(user);

        Call[] memory returned =
            nestUnlooper.execute(marketParams, INestVaultCore(address(forkVault)), teller, user, true);
        assertEq(keccak256(abi.encode(returned)), keccak256(abi.encode(expected)), "returned calls mismatch");

        (uint256 borrowAfter, uint256 collateralAfter) = _currentBorrowAssetsAndCollateral(user);
        assertLt(borrowAfter, borrowBefore, "borrow should decrease");
        assertEq(collateralBefore - collateralAfter, queueOfferShares, "collateral decrease mismatch");
        if (expectStrictSurplus) {
            assertGt(ERC20(PUSD).balanceOf(user), userPusdBefore, "user should receive swept pUSD surplus");
        } else {
            assertGe(ERC20(PUSD).balanceOf(user), userPusdBefore, "user pUSD balance should not decrease");
        }

        AtomicQueue.AtomicRequest memory requestAfter =
            atomicQueue.getUserAtomicRequest(user, ERC20(NALPHA), ERC20(PUSD));
        assertEq(requestAfter.offerAmount, 0, "atomic request should be consumed");
        assertFalse(requestAfter.inSolve, "atomic request should not remain in solve");
        assertEq(
            ERC20(PUSD).allowance(address(nestAdapter), address(atomicSolver)),
            0,
            "adapter atomic solver allowance should reset"
        );

        _assertNoAdapterResidualDelta();
    }

    function _deployAtomicQueueAndSolver() internal {
        solverAuthority = new MockInitiatorAuthority();
        atomicQueue = new AtomicQueue();
        atomicSolver = new AtomicSolverV3(address(this), Authority(address(solverAuthority)));

        deal(PUSD, address(teller), MOCK_TELLER_INITIAL_PUSD, true);

        solverAuthority.setCanCall(
            address(nestAdapter), address(atomicSolver), AtomicSolverV3.redeemSolve.selector, true
        );
        solverAuthority.setCanCall(
            address(atomicQueue), address(atomicSolver), AtomicSolverV3.finishSolve.selector, true
        );
        solverAuthority.setCanCall(solver, address(atomicSolver), AtomicSolverV3.redeemSolve.selector, true);

        RolesAuthority rolesAuthority = RolesAuthority(address(teller.authority()));
        address rolesOwner = rolesAuthority.owner();
        vm.startPrank(rolesOwner);
        uint8 solverRole = 1;
        rolesAuthority.setRoleCapability(solverRole, address(teller), teller.bulkWithdraw.selector, true);
        rolesAuthority.setUserRole(address(atomicSolver), solverRole, true);
        vm.stopPrank();

        assertTrue(
            rolesAuthority.canCall(address(atomicSolver), address(teller), teller.bulkWithdraw.selector),
            "atomic solver should be authorized for bulkWithdraw"
        );
        assertFalse(
            rolesAuthority.canCall(solver, address(teller), teller.bulkWithdraw.selector),
            "solver wallet should not be authorized for bulkWithdraw"
        );
    }

    function _deployNestUnlooper() internal {
        nestUnlooper = new NestUnlooper(
            address(this),
            Authority(address(0)),
            MORPHO,
            BUNDLER3,
            address(nestAdapter),
            address(atomicSolver),
            address(atomicQueue)
        );

        solverAuthority.setCanCall(
            address(nestUnlooper), address(atomicSolver), AtomicSolverV3.redeemSolve.selector, true
        );
    }

    function _deployPredicateProxy() internal {
        serviceManager = new MockServiceManager();
        serviceManager.setIsVerified(true);

        NestVaultPredicateProxy implementation = new NestVaultPredicateProxy();
        address proxy = address(
            new TransparentUpgradeableProxy(
                address(implementation),
                proxyAdmin,
                abi.encodeWithSelector(
                    NestVaultPredicateProxy.initialize.selector, address(this), address(serviceManager), POLICY_ID
                )
            )
        );
        predicateProxy = NestVaultPredicateProxy(proxy);
    }

    function _deployForkNestVault() internal {
        NestVault implementation = new NestVault(payable(NALPHA), 0x000000000022D473030F116dDEE9F6B43aC78BA3);
        address proxy = address(
            new TransparentUpgradeableProxy(
                address(implementation),
                proxyAdmin,
                abi.encodeCall(NestVault.initialize, (NALPHA_ACCOUNTANT, PUSD, address(this), 1, address(0)))
            )
        );
        forkVault = NestVault(payable(proxy));

        RolesAuthority rolesAuthority = RolesAuthority(address(BoringVault(payable(NALPHA)).authority()));
        forkVault.setAuthority(Authority(address(rolesAuthority)));
        predicateProxy.setAuthority(Authority(address(rolesAuthority)));

        address rolesOwner = rolesAuthority.owner();
        vm.startPrank(rolesOwner);
        rolesAuthority.setPublicCapability(NALPHA, BoringVault.enter.selector, true);
        rolesAuthority.setPublicCapability(NALPHA, BoringVault.exit.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), IERC4626.deposit.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), IERC4626.mint.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), INestVaultCore.instantRedeem.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), INestVaultCore.requestRedeem.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), INestVaultCore.redeem.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), IERC4626.withdraw.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), INestVaultCore.fulfillRedeem.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), INestVaultCore.updateRedeem.selector, true);
        rolesAuthority.setPublicCapability(
            address(predicateProxy),
            bytes4(keccak256("deposit(address,uint256,address,address,(string,uint256,address[],bytes[]))")),
            true
        );
        rolesAuthority.setPublicCapability(
            address(predicateProxy),
            bytes4(keccak256("mint(address,uint256,address,address,(string,uint256,address[],bytes[]))")),
            true
        );
        uint8 predicateProxyAdapterRole = 7;
        rolesAuthority.setRoleCapability(
            predicateProxyAdapterRole,
            address(predicateProxy),
            bytes4(keccak256("deposit(address,uint256,address,address,bytes32,(string,uint256,address[],bytes[]))")),
            true
        );
        rolesAuthority.setUserRole(address(nestAdapter), predicateProxyAdapterRole, true);
        vm.stopPrank();

        assertEq(INestVaultCore(address(forkVault)).asset(), PUSD, "forkVault asset mismatch");
        assertEq(INestVaultCore(address(forkVault)).share(), NALPHA, "forkVault share mismatch");
    }

    function _seedUserAndApprove() internal {
        deal(PUSD, user, USER_INITIAL_PUSD, true);
        deal(PUSD, solver, USER_INITIAL_PUSD, true);

        vm.startPrank(user);
        ERC20(PUSD).approve(address(forkVault), type(uint256).max);
        ERC20(PUSD).approve(address(nestAdapter), type(uint256).max);
        ERC20(NALPHA).approve(address(nestAdapter), type(uint256).max);
        ERC20(NALPHA).approve(address(forkVault), type(uint256).max);
        INestVaultCore(address(forkVault)).setOperator(address(nestAdapter), true);
        INestVaultCore(address(forkVault)).setOperator(solver, true);
        morpho.setAuthorization(address(nestAdapter), true);
        morpho.setAuthorization(solver, true);
        seedShares = INestVaultCore(address(forkVault)).deposit(USER_SEED_DEPOSIT_ASSETS, user);
        vm.stopPrank();

        // vm.prank(solver);
        // ERC20(PUSD).approve(address(nestAdapter), type(uint256).max);

        assertGt(seedShares, 0, "seed deposit minted no shares");
    }

    function _buildBundle(
        address initiator,
        address owner,
        uint256 targetBorrow,
        uint256 targetCollateral,
        bool instantRedeem,
        bool legacyRedemption,
        uint256 extraDepositLoanAssets,
        uint256 extraRepayLoanAssets,
        uint256 extraCollateral
    ) internal view returns (Call[] memory calls) {
        BundleContext memory context = BundleContext({
            morpho: morpho,
            adapter: address(nestAdapter),
            bundler: BUNDLER3,
            vault: INestVaultCore(address(forkVault)),
            teller: address(teller),
            predicateProxy: address(predicateProxy),
            atomicSolver: address(atomicSolver),
            atomicQueue: address(atomicQueue),
            owner: owner,
            initiator: initiator,
            controller: owner
        });

        uint256 assetAllowance = extraDepositLoanAssets == 0 && extraRepayLoanAssets == 0
            ? type(uint256).max
            : extraDepositLoanAssets + extraRepayLoanAssets;
        UserIntent memory intent = UserIntent({
            market: marketParams,
            assetAllowance: assetAllowance,
            shareAllowance: extraCollateral,
            maxSharePriceE27: type(uint256).max,
            minSharePriceE27: 0,
            maxRepaySharePriceE27: type(uint256).max,
            mode: PositionMode.Target,
            target: Position({loan: targetBorrow, collateral: targetCollateral}),
            delta: MarketActions({borrow: 0, repay: 0, supplyCollateral: 0, withdrawCollateral: 0})
        });
        RouteInput memory route =
            RouteInput({legacyRedemption: legacyRedemption, legacyDeposit: false, instantRedeem: instantRedeem});

        Bundle memory bundle = BundleBuildLib.getBundle(context, intent, route);
        bundle.predicateMessage = _emptyPredicateMessage();
        calls = BundleCalldataLib.getBundleCalls(bundle);
    }

    function _currentBorrowAssetsAndCollateral(address owner)
        internal
        view
        returns (uint256 borrowAssets, uint256 collateral)
    {
        Id id = marketParams.id();
        MorphoPosition memory position = morpho.position(id, owner);
        Market memory market = morpho.market(id);
        borrowAssets = uint256(position.borrowShares).toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
        collateral = uint256(position.collateral);
    }

    function _currentLeverageBps(address owner) internal view returns (uint256 leverageBps) {
        (uint256 borrowAssets, uint256 collateral) = _currentBorrowAssetsAndCollateral(owner);
        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 collateralValue = Math.mulDiv(collateral, collateralPrice, ORACLE_PRICE_SCALE, Math.Rounding.Floor);
        leverageBps = Math.mulDiv(collateralValue, 10_000, collateralValue - borrowAssets, Math.Rounding.Floor);
    }

    function _midTargetLeverageBps(address owner) internal view returns (uint256 targetLeverageBps) {
        uint256 currentLeverageBps = _currentLeverageBps(owner);
        assertGt(currentLeverageBps, 10_001, "position should be leveraged above 1x");

        uint256 delta = currentLeverageBps - 10_000;
        targetLeverageBps = 10_000 + Math.max(delta / 2, 1);
        if (targetLeverageBps >= currentLeverageBps) targetLeverageBps = currentLeverageBps - 1;
    }

    function _seedInstantRedeemLiquidity(uint256 assets) internal {
        vm.startPrank(user);
        uint256 shares = INestVaultCore(address(forkVault)).deposit(assets, user);
        ERC20(NALPHA).transfer(PUSD, shares);
        vm.stopPrank();
    }

    function _selector(bytes memory data) private pure returns (bytes4 sel) {
        assembly {
            sel := mload(add(data, 0x20))
        }
    }

    function _args(bytes memory data) private pure returns (bytes memory out) {
        uint256 length = data.length - 4;
        out = new bytes(length);
        for (uint256 i; i < length; ++i) {
            out[i] = data[i + 4];
        }
    }

    function _call(address to, bytes memory data, bytes32 callbackHash) private pure returns (Call memory) {
        return Call({to: to, data: data, value: 0, skipRevert: false, callbackHash: callbackHash});
    }

    function _emptyPredicateMessage() private pure returns (PredicateMessage memory predicateMessage) {
        predicateMessage = PredicateMessage({
            taskId: "", expireByTime: type(uint256).max, signerAddresses: new address[](0), signatures: new bytes[](0)
        });
    }

    function _assertNoAdapterResidualDelta() internal view {
        assertEq(ERC20(PUSD).balanceOf(address(nestAdapter)), 0, "nestAdapter residual pUSD");
        assertEq(ERC20(NALPHA).balanceOf(address(nestAdapter)), 0, "nestAdapter residual nALPHA");

        assertEq(ERC20(PUSD).balanceOf(BUNDLER3), baselineBundlerPusd, "bundler residual pUSD delta");
        assertEq(ERC20(NALPHA).balanceOf(BUNDLER3), baselineBundlerNalpha, "bundler residual nALPHA delta");
    }
}
