// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/src/base/Roles/TellerWithMultiAssetSupport.sol";
import {AtomicQueue} from "@boring-vault/src/atomic-queue/AtomicQueue.sol";

import {Call, IBundler3} from "contracts/vendor/bundler3/interfaces/IBundler3.sol";
import {NestVault} from "contracts/NestVault.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {NestAdapter} from "contracts/morpho/NestAdapter.sol";
import {MorphoAdapter} from "contracts/morpho/MorphoAdapter.sol";
import {NestBundler} from "contracts/morpho/NestBundler.sol";
import {NestVaultPredicateProxy, PredicateMessage} from "contracts/NestVaultPredicateProxy.sol";
import {BundleCalldataLib} from "contracts/morpho/libraries/BundleCalldataLib.sol";
import {GeneralAdapter1} from "contracts/vendor/morpho/GeneralAdapter1.sol";
import {IPredicateManager} from "@predicate/src/interfaces/IPredicateManager.sol";
import {
    Bundle,
    MarketActions,
    PositionMode,
    RouteInput,
    Position,
    UserIntent
} from "contracts/morpho/types/BundleTypes.sol";
import {NestBundleErrors} from "contracts/morpho/types/Errors.sol";
import {IMorpho, Id, Market, MarketParams, Position as MorphoPosition} from "@morpho/interfaces/IMorpho.sol";
import {IOracle} from "@morpho/interfaces/IOracle.sol";
import {ORACLE_PRICE_SCALE} from "@morpho/libraries/ConstantsLib.sol";
import {MathLib} from "@morpho/libraries/MathLib.sol";
import {MarketParamsLib} from "@morpho/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "@morpho/libraries/SharesMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {NestShareMathLib} from "contracts/morpho/libraries/NestShareMathLib.sol";

contract NestBundlerIntegrationTest is Test {
    using MathLib for uint256;
    using MarketParamsLib for MarketParams;
    using NestShareMathLib for uint256;
    using SharesMathLib for uint256;

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
    string internal constant POLICY_ID = "TEST_POLICY_ID";

    address internal constant ATOMIC_SOLVER = 0x77fb098A1C28a5b50BFAdb69Ca1bEE515a7FC974;
    address internal constant ATOMIC_QUEUE = 0x220dc6d4569C1F406D532f9633D5Be5Bc86e8264;
    // Reference: production NestVaultPredicateProxy; tests deploy a local proxy for deterministic predicate checks.
    address internal constant PROD_NEST_VAULT_PREDICATE_PROXY = 0xfC0c4222B3A0c9B060C0B959DEc62442036b9035;
    bytes4 internal constant PREDICATE_VALIDATE_SIGNATURES_SELECTOR = IPredicateManager.validateSignatures.selector;
    // Reference: legacy teller predicate proxy.
    address internal constant PROD_LEGACY_TELLER_PREDICATE_PROXY = 0x6104fe10ca937a086ba7AdbD0910A4733d380cB6;

    address internal proxyAdmin = makeAddr("proxyAdmin");
    address internal user = makeAddr("user");
    address internal solver = makeAddr("solver");

    IMorpho internal morpho;
    IBundler3 internal bundler3;
    NestAdapter internal nestAdapter;
    NestBundler internal nestBundler;
    NestVaultPredicateProxy internal predicateProxy;
    TellerWithMultiAssetSupport internal teller;
    NestVault internal forkVault;
    MarketParams internal marketParams;
    uint256 internal seedShares;

    uint256 internal baselineBundlerPusd;
    uint256 internal baselineBundlerNalpha;

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
        _deployPredicateProxy();
        _deployForkNestVault();

        nestBundler = new NestBundler(
            MORPHO,
            BUNDLER3,
            address(nestAdapter),
            address(predicateProxy),
            PROD_LEGACY_TELLER_PREDICATE_PROXY,
            ATOMIC_SOLVER,
            ATOMIC_QUEUE
        );
        _mockAtomicSolverAuthority();

        _seedUserAndApprove();

        // Instant redeem liquidity is represented as nALPHA balance held by the pUSD contract.
        deal(NALPHA, PUSD, 1_000 * UNIT, true);

        baselineBundlerPusd = ERC20(PUSD).balanceOf(BUNDLER3);
        baselineBundlerNalpha = ERC20(NALPHA).balanceOf(BUNDLER3);
    }

    function test_integration_fuzz_fork_routeMatrix(uint256 initialLoan, uint256 initialCollateral, uint256, uint256)
        public
    {
        uint256 ownerAvailableAssets = ERC20(PUSD).balanceOf(user);
        uint256 maxFundableCollateral =
            seedShares + IERC4626(address(forkVault)).previewDeposit(ownerAvailableAssets * 2);
        uint256 maxInitialBorrow = _maxBorrowForCollateral(maxFundableCollateral);
        uint256 initialLoanUpper = ownerAvailableAssets < maxInitialBorrow ? ownerAvailableAssets : maxInitialBorrow;
        uint256 minTargetCollateral = _minCollateralForBorrow(UNIT + 1);

        initialLoan = bound(initialLoan, 2 * UNIT, initialLoanUpper);

        uint256 minInitialCollateral = _minCollateralForBorrow(initialLoan + 1);
        uint256 minHalfStepCollateral = 2 * minTargetCollateral;
        if (minInitialCollateral < minHalfStepCollateral) minInitialCollateral = minHalfStepCollateral;

        initialCollateral = bound(
            initialCollateral,
            minInitialCollateral,
            seedShares + IERC4626(address(forkVault)).previewDeposit(ownerAvailableAssets + initialLoan)
        );

        assertGe(
            _maxBorrowForCollateral(initialCollateral),
            initialLoan + 1,
            "initial position exceeds executable lltv tolerance"
        );

        // execute initial position
        (uint256 currentBorrow, uint256 currentCollateral) = _executePosition(initialLoan, initialCollateral);

        // set a taget position that requires vault redemption
        uint256 reducedCollateral = currentCollateral / 2;
        uint256 targetBorrow = currentBorrow / 2;
        uint256 maxSafeTargetBorrow = _maxBorrowForCollateral(reducedCollateral);
        if (maxSafeTargetBorrow != 0) maxSafeTargetBorrow -= 1;
        if (targetBorrow > maxSafeTargetBorrow) targetBorrow = maxSafeTargetBorrow;
        UserIntent memory intent =
            _getTargetIntent(type(uint256).max, type(uint256).max, targetBorrow, reducedCollateral);

        PredicateMessage memory emptyMsg = _getEmptyPredicateMessage();

        // execute the target position with all route combinations possible
        for (uint8 flags; flags < 8; ++flags) {
            uint256 snapshotId = vm.snapshotState();
            // get every possible combination of legacyRedemption, legacyDeposit, and instantRedeem flags
            RouteInput memory route = _getRoute(flags & 1 != 0, flags & 2 != 0, flags & 4 != 0);

            // not possible to instant redeem and use legacy redemption in the same route
            if (route.legacyRedemption && route.instantRedeem) {
                vm.expectRevert(NestBundleErrors.LegacyRedemptionCannotUseInstantRedeem.selector);
                nestBundler.getBundle(
                    intent, route, emptyMsg, INestVaultCore(address(forkVault)), address(teller), user, user
                );
                vm.revertToState(snapshotId);
                continue;
            }

            if (route.instantRedeem) {
                Bundle memory bundle = nestBundler.getBundle(
                    intent, route, emptyMsg, INestVaultCore(address(forkVault)), address(teller), user, user
                );
                Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);

                vm.prank(user);
                bundler3.multicall(calls);
            } else {
                Bundle memory syncBundle = nestBundler.getSyncBundle(
                    intent, route, emptyMsg, INestVaultCore(address(forkVault)), address(teller), user
                );
                Bundle memory asyncBundle = nestBundler.getAsyncBundle(
                    intent, route, emptyMsg, INestVaultCore(address(forkVault)), address(teller), user, solver
                );

                if (_hasBundleActions(syncBundle)) {
                    Call[] memory syncCalls = BundleCalldataLib.getBundleCalls(syncBundle);
                    vm.prank(user);
                    bundler3.multicall(syncCalls);
                }

                if (_hasBundleActions(asyncBundle)) {
                    if (route.legacyRedemption) _setUpLegacyAtomicRequestForBundle(asyncBundle);

                    Call[] memory asyncCalls = BundleCalldataLib.getBundleCalls(asyncBundle);
                    vm.prank(solver);
                    bundler3.multicall(asyncCalls);
                }
            }

            _assertPosition(user, targetBorrow, reducedCollateral);
            _assertNoResidualTokens();

            vm.revertToState(snapshotId);
        }
    }

    function _assertPosition(address _user, uint256 expectedLoan, uint256 expectedCollateral) internal view {
        (uint256 borrow, uint256 collateral) = _getPosition(_user);
        assertEq(collateral, expectedCollateral, "collateral mismatch");
        assertGe(borrow, expectedLoan, "missing borrow shares");
        assertLe(borrow - expectedLoan, 1, "borrow rounding drift");
    }

    function _executePosition(uint256 targetBorrow, uint256 targetCollateral)
        internal
        returns (uint256 loan, uint256 collateral)
    {
        Bundle memory bundle = nestBundler.getBundle(
            _getTargetIntent(type(uint256).max, seedShares, targetBorrow, targetCollateral),
            _getRoute(false, false, false),
            _getEmptyPredicateMessage(),
            INestVaultCore(address(forkVault)),
            address(teller),
            user,
            user
        );
        Call[] memory calls = BundleCalldataLib.getBundleCalls(bundle);

        vm.prank(user);
        bundler3.multicall(calls);

        _assertPosition(user, targetBorrow, targetCollateral);
        _assertNoResidualTokens();

        (loan, collateral) = _getPosition(user);
        assertApproxEqAbs(loan, targetBorrow, 1, "borrow should stay within rounding tolerance");
        assertEq(collateral, targetCollateral, "collateral should be non-zero");
    }

    function _deployPredicateProxy() internal {
        predicateProxy = NestVaultPredicateProxy(PROD_NEST_VAULT_PREDICATE_PROXY);
        assertGt(address(predicateProxy).code.length, 0, "prod predicate proxy not deployed");

        address predicateManager = predicateProxy.getPredicateManager();
        vm.mockCall(predicateManager, abi.encodeWithSelector(PREDICATE_VALIDATE_SIGNATURES_SELECTOR), abi.encode(true));

        address proxyAuthority = address(predicateProxy.authority());
        vm.mockCall(proxyAuthority, abi.encodeWithSelector(Authority.canCall.selector), abi.encode(true));
    }

    function _mockAtomicSolverAuthority() internal {
        address solverAuthority = address(Auth(ATOMIC_SOLVER).authority());
        vm.mockCall(solverAuthority, abi.encodeWithSelector(Authority.canCall.selector), abi.encode(true));
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
        if (address(predicateProxy) != PROD_NEST_VAULT_PREDICATE_PROXY) {
            predicateProxy.setAuthority(Authority(address(rolesAuthority)));
        }

        address rolesOwner = rolesAuthority.owner();
        vm.startPrank(rolesOwner);
        rolesAuthority.setPublicCapability(NALPHA, BoringVault.enter.selector, true);
        rolesAuthority.setPublicCapability(NALPHA, BoringVault.exit.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), IERC4626.deposit.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), IERC4626.mint.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), INestVaultCore.instantRedeem.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), INestVaultCore.requestRedeem.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), INestVaultCore.redeem.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), INestVaultCore.fulfillRedeem.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), INestVaultCore.updateRedeem.selector, true);
        rolesAuthority.setPublicCapability(address(forkVault), IERC4626.withdraw.selector, true);
        if (address(predicateProxy) != PROD_NEST_VAULT_PREDICATE_PROXY) {
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
                bytes4(
                    keccak256("deposit(address,uint256,address,address,bytes32,(string,uint256,address[],bytes[]))")
                ),
                true
            );
            rolesAuthority.setUserRole(address(nestAdapter), predicateProxyAdapterRole, true);
        }
        vm.stopPrank();

        assertEq(INestVaultCore(address(forkVault)).asset(), PUSD, "forkVault asset mismatch");
        assertEq(INestVaultCore(address(forkVault)).share(), NALPHA, "forkVault share mismatch");
    }

    function _seedUserAndApprove() internal {
        deal(PUSD, user, USER_INITIAL_PUSD, true);

        vm.startPrank(user);
        ERC20(PUSD).approve(address(forkVault), type(uint256).max);
        ERC20(PUSD).approve(address(nestAdapter), type(uint256).max);
        ERC20(PUSD).approve(address(nestBundler), type(uint256).max);
        ERC20(NALPHA).approve(address(nestAdapter), type(uint256).max);
        ERC20(NALPHA).approve(address(nestBundler), type(uint256).max);
        ERC20(NALPHA).approve(address(forkVault), type(uint256).max);
        INestVaultCore(address(forkVault)).setOperator(address(nestAdapter), true);
        INestVaultCore(address(forkVault)).setOperator(address(nestBundler), true);
        INestVaultCore(address(forkVault)).setOperator(solver, true);
        morpho.setAuthorization(address(nestAdapter), true);
        morpho.setAuthorization(address(nestBundler), true);
        morpho.setAuthorization(solver, true);
        seedShares = INestVaultCore(address(forkVault)).deposit(USER_SEED_DEPOSIT_ASSETS, user);
        vm.stopPrank();

        vm.prank(solver);
        INestVaultCore(address(forkVault)).setOperator(address(nestAdapter), true);

        assertGt(seedShares, 0, "seed deposit minted no shares");
    }

    function _setUpLegacyAtomicRequestForBundle(Bundle memory bundle) internal {
        uint256 offerAmount = bundle.ma.withdrawCollateral;
        uint256 assetsForWant = offerAmount.convertToAssets(INestVaultCore(address(forkVault)), Math.Rounding.Floor);
        uint256 atomicPrice = assetsForWant * UNIT / offerAmount;
        assertGt(atomicPrice, 0, "atomic price should be non-zero");
        assertLe(offerAmount, type(uint96).max, "offer amount overflow");
        assertLe(atomicPrice, type(uint88).max, "atomic price overflow");

        vm.startPrank(user);
        ERC20(NALPHA).approve(ATOMIC_QUEUE, offerAmount);
        ERC20(PUSD).approve(address(nestAdapter), assetsForWant);
        AtomicQueue.AtomicRequest memory atomicRequest = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 1 days),
            atomicPrice: uint88(atomicPrice),
            offerAmount: uint96(offerAmount),
            inSolve: false
        });
        AtomicQueue(ATOMIC_QUEUE).updateAtomicRequest(ERC20(NALPHA), ERC20(PUSD), atomicRequest);
        vm.stopPrank();
    }

    function _getTargetIntent(
        uint256 assetAllowance,
        uint256 shareAllowance,
        uint256 targetBorrow,
        uint256 targetCollateral
    ) internal view returns (UserIntent memory intent) {
        intent = UserIntent({
            market: marketParams,
            assetAllowance: assetAllowance,
            shareAllowance: shareAllowance,
            maxSharePriceE27: type(uint256).max,
            minSharePriceE27: 0,
            maxRepaySharePriceE27: type(uint256).max,
            mode: PositionMode.Target,
            target: Position({loan: targetBorrow, collateral: targetCollateral}),
            delta: MarketActions({borrow: 0, repay: 0, supplyCollateral: 0, withdrawCollateral: 0})
        });
    }

    function _getRoute(bool legacyRedemption, bool legacyDeposit, bool instantRedeem)
        internal
        pure
        returns (RouteInput memory route)
    {
        route = RouteInput({
            legacyRedemption: legacyRedemption, legacyDeposit: legacyDeposit, instantRedeem: instantRedeem
        });
    }

    function _getEmptyPredicateMessage() internal pure returns (PredicateMessage memory predicateMessage) {
        predicateMessage = PredicateMessage({
            taskId: "", expireByTime: type(uint256).max, signerAddresses: new address[](0), signatures: new bytes[](0)
        });
    }

    function _getPosition(address owner) internal view returns (uint256 borrowAssets, uint256 collateral) {
        Id id = marketParams.id();
        MorphoPosition memory position = morpho.position(id, owner);
        Market memory market = morpho.market(id);
        borrowAssets = uint256(position.borrowShares).toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
        collateral = uint256(position.collateral);
    }

    function _getSelector(bytes memory data) private pure returns (bytes4 sel) {
        assembly {
            sel := mload(add(data, 0x20))
        }
    }

    function _getArgs(bytes memory data) private pure returns (bytes memory out) {
        uint256 length = data.length - 4;
        out = new bytes(length);
        for (uint256 i; i < length; ++i) {
            out[i] = data[i + 4];
        }
    }

    function _assertNoResidualTokens() internal view {
        assertEq(ERC20(PUSD).balanceOf(address(nestAdapter)), 0, "nestAdapter residual pUSD");
        assertEq(ERC20(NALPHA).balanceOf(address(nestAdapter)), 0, "nestAdapter residual nALPHA");

        assertEq(ERC20(PUSD).balanceOf(BUNDLER3), baselineBundlerPusd, "bundler residual pUSD delta");
        assertEq(ERC20(NALPHA).balanceOf(BUNDLER3), baselineBundlerNalpha, "bundler residual nALPHA delta");

        assertEq(ERC20(PUSD).balanceOf(address(nestAdapter)), 0, "bundler residual pUSD delta");
        assertEq(ERC20(NALPHA).balanceOf(address(nestAdapter)), 0, "bundler residual nALPHA delta");
    }

    function _hasBundleActions(Bundle memory bundle) internal pure returns (bool) {
        return bundle.ma.borrow != 0 || bundle.ma.repay != 0 || bundle.ma.supplyCollateral != 0
            || bundle.ma.withdrawCollateral != 0 || bundle.va.mint != 0 || bundle.va.deposit != 0
            || bundle.va.redeem != 0 || bundle.va.pullAssets != 0 || bundle.va.pullShares != 0;
    }

    function _maxBorrowForCollateral(uint256 collateral) internal view returns (uint256) {
        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        return collateral.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(marketParams.lltv);
    }

    function _minCollateralForBorrow(uint256 borrow) internal view returns (uint256) {
        if (borrow == 0) return 0;

        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 collateralAssetsNeeded = borrow.wDivUp(marketParams.lltv);
        return collateralAssetsNeeded.mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);
    }
}
