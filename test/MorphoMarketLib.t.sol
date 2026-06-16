// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {Id, IMorpho, Market, MarketParams, Position as MorphoPosition} from "@morpho/interfaces/IMorpho.sol";
import {ORACLE_PRICE_SCALE} from "@morpho/libraries/ConstantsLib.sol";
import {MarketParamsLib} from "@morpho/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "@morpho/libraries/SharesMathLib.sol";

import {MorphoMarketLib} from "contracts/morpho/libraries/MorphoMarketLib.sol";
import {Position, PositionMetrics} from "contracts/morpho/types/BundleTypes.sol";

contract MockMorphoForMarketLib {
    mapping(bytes32 => MorphoPosition) internal _positions;
    mapping(bytes32 => Market) internal _markets;

    function setPosition(Id id, address user, uint128 borrowShares, uint128 collateral) external {
        _positions[keccak256(abi.encode(id, user))] =
            MorphoPosition({supplyShares: 0, borrowShares: borrowShares, collateral: collateral});
    }

    function setMarket(Id id, Market memory market_) external {
        _markets[Id.unwrap(id)] = market_;
    }

    function position(Id id, address user) external view returns (MorphoPosition memory) {
        return _positions[keccak256(abi.encode(id, user))];
    }

    function market(Id id) external view returns (Market memory) {
        return _markets[Id.unwrap(id)];
    }
}

contract MorphoMarketLibHarness {
    using MorphoMarketLib for MarketParams;

    function getCurrentPosition(MarketParams memory market, IMorpho morpho, address user)
        external
        view
        returns (PositionMetrics memory metrics)
    {
        return market.getCurrentPosition(morpho, user);
    }

    function getTargetPosition(MarketParams memory market, IMorpho morpho, address user, uint256 leverageBps)
        external
        view
        returns (PositionMetrics memory metrics)
    {
        return market.getTargetPosition(morpho, user, leverageBps);
    }

    function getLeverageMetrics(MarketParams memory market, IMorpho morpho, address user)
        external
        view
        returns (uint256 collateralPrice, uint256 collateralValue, uint256 equity, uint256 leverageBps)
    {
        return market.getLeverageMetrics(morpho, user);
    }

    function getLeverageMetrics(MarketParams memory market, Position memory position)
        external
        view
        returns (uint256 collateralPrice, uint256 collateralValue, uint256 equity, uint256 leverageBps)
    {
        return market.getLeverageMetrics(position);
    }
}

contract MorphoMarketLibTest is Test {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    address internal constant USER = address(0x1001);

    MockMorphoForMarketLib internal morpho;
    MorphoMarketLibHarness internal harness;

    MarketParams internal market;
    Id internal marketId;

    function setUp() external {
        morpho = new MockMorphoForMarketLib();
        harness = new MorphoMarketLibHarness();

        market = MarketParams({
            loanToken: address(0x2001),
            collateralToken: address(0x2002),
            oracle: address(0x2003),
            irm: address(0),
            lltv: 1e18
        });
        marketId = market.id();

        _setMarket(1e24, 1e24);
        vm.mockCall(market.oracle, abi.encodeWithSignature("price()"), abi.encode(uint256(ORACLE_PRICE_SCALE)));
    }

    function test_getCurrentPosition_convertsBorrowSharesAndReturnsCollateral() external {
        uint128 borrowShares = 4e18;
        uint128 collateral = 7e18;
        uint128 totalBorrowAssets = 3e24;
        uint128 totalBorrowShares = 2e24;

        morpho.setPosition(marketId, USER, borrowShares, collateral);
        morpho.setMarket(marketId, _market(totalBorrowAssets, totalBorrowShares));

        PositionMetrics memory metrics = harness.getCurrentPosition(market, IMorpho(address(morpho)), USER);
        uint256 expectedBorrowAssets = uint256(borrowShares).toAssetsUp(totalBorrowAssets, totalBorrowShares);
        (,, uint256 equity, uint256 leverageBps) = harness.getLeverageMetrics(market, metrics.position);

        assertEq(metrics.position.loan, expectedBorrowAssets, "borrow assets");
        assertEq(metrics.position.collateral, collateral, "collateral");
        assertEq(metrics.equity, equity, "equity");
        assertEq(metrics.leverageBps, leverageBps, "leverage");
    }

    function test_getLeverageMetrics_returnsHealthyMetrics() external view {
        Position memory position = Position({loan: 150 ether, collateral: 200 ether});

        (uint256 collateralPrice, uint256 collateralValue, uint256 equity, uint256 leverageBps) =
            harness.getLeverageMetrics(market, position);

        assertEq(collateralPrice, ORACLE_PRICE_SCALE, "price");
        assertEq(collateralValue, 200 ether, "collateral value");
        assertEq(equity, 50 ether, "equity");
        assertEq(leverageBps, 40_000, "leverage");
    }

    function test_getTargetPosition_matchesAsyncUnloopExample() external {
        morpho.setPosition(marketId, USER, uint128(50 ether), uint128(100 ether));

        PositionMetrics memory metrics = harness.getTargetPosition(market, IMorpho(address(morpho)), USER, 20_000);
        (,, uint256 equity,) = harness.getLeverageMetrics(market, IMorpho(address(morpho)), USER);

        assertEq(metrics.equity, equity, "equity");
        assertEq(metrics.leverageBps, 20_000, "target leverage");
        assertApproxEqAbs(metrics.position.loan, 50 ether, 100, "target borrow");
        assertApproxEqAbs(metrics.position.collateral, 100 ether, 100, "target collateral");
    }

    function test_getTargetPosition_returnsOneXTarget() external {
        morpho.setPosition(marketId, USER, 0, uint128(75 ether));

        PositionMetrics memory metrics = harness.getTargetPosition(market, IMorpho(address(morpho)), USER, 10_000);

        assertEq(metrics.position.loan, 0, "target borrow");
        assertEq(metrics.position.collateral, 75 ether, "target collateral");
    }

    function test_getTargetPosition_supportsSubOneXLeverage() external {
        morpho.setPosition(marketId, USER, 0, uint128(100 ether));

        PositionMetrics memory metrics = harness.getTargetPosition(market, IMorpho(address(morpho)), USER, 5_000);

        assertEq(metrics.position.loan, 0, "target borrow");
        assertEq(metrics.position.collateral, 50 ether, "target collateral");
    }

    function test_getTargetPosition_zeroLeverageReturnsFullExit() external {
        morpho.setPosition(marketId, USER, uint128(50 ether), uint128(100 ether));

        PositionMetrics memory metrics = harness.getTargetPosition(market, IMorpho(address(morpho)), USER, 0);
        (,, uint256 equity,) = harness.getLeverageMetrics(market, IMorpho(address(morpho)), USER);

        assertEq(metrics.equity, equity, "equity");
        assertEq(metrics.leverageBps, 0, "target leverage for full exit");
        assertEq(metrics.position.loan, 0, "target borrow");
        assertEq(metrics.position.collateral, 0, "target collateral");
    }

    function test_getTargetPosition_derivesTargetWithoutValidatingMarketLltv() external {
        market.lltv = 0.5e18;
        _setMarket(1e24, 1e24);
        morpho.setPosition(market.id(), USER, 0, uint128(100 ether));

        PositionMetrics memory metrics = harness.getTargetPosition(market, IMorpho(address(morpho)), USER, 30_000);

        assertEq(metrics.position.loan, 200 ether, "target borrow");
        assertEq(metrics.position.collateral, 300 ether, "target collateral");
    }

    function test_getLeverageMetrics_returnsMaxLeverageAtZeroEquity() external view {
        Position memory position = Position({loan: 100 ether, collateral: 100 ether});

        (, uint256 collateralValue, uint256 equity, uint256 leverageBps) = harness.getLeverageMetrics(market, position);

        assertEq(collateralValue, 100 ether, "collateral value");
        assertEq(equity, 0, "equity");
        assertEq(leverageBps, type(uint256).max, "max leverage");
    }

    function test_getLeverageMetrics_returnsMaxLeverageOnNegativeEquity() external view {
        Position memory position = Position({loan: 101 ether, collateral: 100 ether});

        (, uint256 collateralValue, uint256 equity, uint256 leverageBps) = harness.getLeverageMetrics(market, position);

        assertEq(collateralValue, 100 ether, "collateral value");
        assertEq(equity, 0, "equity saturates to zero");
        assertEq(leverageBps, type(uint256).max, "max leverage");
    }

    function _setMarket(uint128 totalBorrowAssets, uint128 totalBorrowShares) internal {
        morpho.setMarket(marketId, _market(totalBorrowAssets, totalBorrowShares));
    }

    function _market(uint128 totalBorrowAssets, uint128 totalBorrowShares)
        internal
        view
        returns (Market memory marketData)
    {
        marketData = Market({
            totalSupplyAssets: 0,
            totalSupplyShares: 0,
            totalBorrowAssets: totalBorrowAssets,
            totalBorrowShares: totalBorrowShares,
            lastUpdate: uint128(block.timestamp),
            fee: 0
        });
    }
}
