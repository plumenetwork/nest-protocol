// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IOracle} from "@morpho/interfaces/IOracle.sol";
import {IMorpho, MarketParams, Position as MorphoPosition} from "@morpho/interfaces/IMorpho.sol";
import {ORACLE_PRICE_SCALE} from "@morpho/libraries/ConstantsLib.sol";
import {MarketParamsLib} from "@morpho/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "@morpho/libraries/periphery/MorphoBalancesLib.sol";
import {SharesMathLib} from "@morpho/libraries/SharesMathLib.sol";

import {Position, PositionMetrics} from "contracts/morpho/types/BundleTypes.sol";

/// @title MorphoMarketLib
/// @notice Helpers for reading Morpho positions and deriving leverage-based targets.
library MorphoMarketLib {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;
    using Math for uint256;

    /// @notice Basis-point scale where `10_000 = 1x`.
    uint256 internal constant LEVERAGE_ONE = 10_000;

    /// @notice Returns the current Morpho loan/collateral position for a user.
    function getPosition(MarketParams memory market, IMorpho morpho, address user)
        internal
        view
        returns (Position memory position)
    {
        position = _getPosition(market, morpho, user);
    }

    /// @notice Returns the current position together with its derived equity and leverage.
    function getCurrentPosition(MarketParams memory market, IMorpho morpho, address user)
        internal
        view
        returns (PositionMetrics memory metrics)
    {
        metrics.position = _getPosition(market, morpho, user);
        (,, metrics.equity, metrics.leverageBps) = getLeverageMetrics(market, metrics.position);
    }

    /// @notice Derives a target Morpho position from final equity and leverage.
    /// @dev `10_000 = 1x`, sub-1x values reduce Morpho exposure, and `0` fully exits the Morpho position.
    function getTargetPosition(MarketParams memory market, IMorpho morpho, address user, uint256 targetLeverageBps)
        internal
        view
        returns (PositionMetrics memory metrics)
    {
        PositionMetrics memory currentMetrics = getCurrentPosition(market, morpho, user);
        metrics = getTargetPosition(market, currentMetrics, targetLeverageBps);
    }

    /// @notice Derives a target Morpho position from the live position and requested leverage.
    /// @dev `10_000 = 1x`, sub-1x values reduce Morpho exposure, and `0` fully exits the Morpho position.
    ///      LLTV validation is enforced by bundle-building flows that consume this target.
    function getTargetPosition(
        MarketParams memory market,
        PositionMetrics memory currentMetrics,
        uint256 targetLeverageBps
    ) internal view returns (PositionMetrics memory metrics) {
        metrics.equity = currentMetrics.equity;
        metrics.leverageBps = targetLeverageBps;

        if (targetLeverageBps == 0) return metrics;

        uint256 collateralPrice = IOracle(market.oracle).price();
        uint256 targetCollateralValue = metrics.equity.mulDiv(targetLeverageBps, LEVERAGE_ONE, Math.Rounding.Floor);
        uint256 targetCollateral =
            targetCollateralValue.mulDiv(ORACLE_PRICE_SCALE, collateralPrice, Math.Rounding.Floor);
        uint256 actualCollateralValue =
            targetCollateral.mulDiv(collateralPrice, ORACLE_PRICE_SCALE, Math.Rounding.Floor);

        metrics.position.loan = actualCollateralValue.saturatingSub(metrics.equity);
        metrics.position.collateral = targetCollateral;
    }

    /// @notice Derives a target Morpho position from the live position and requested leverage.
    /// @dev `10_000 = 1x`, sub-1x values reduce Morpho exposure, and `0` fully exits the Morpho position.
    ///      LLTV validation is enforced by bundle-building flows that consume this target.
    function getTargetPosition(MarketParams memory market, Position memory currentPosition, uint256 targetLeverageBps)
        internal
        view
        returns (PositionMetrics memory metrics)
    {
        PositionMetrics memory currentMetrics;
        currentMetrics.position = currentPosition;
        (,, currentMetrics.equity, currentMetrics.leverageBps) = getLeverageMetrics(market, currentPosition);
        metrics = getTargetPosition(market, currentMetrics, targetLeverageBps);
    }

    /// @notice Returns live leverage metrics for a user in a market.
    function getLeverageMetrics(MarketParams memory market, IMorpho morpho, address user)
        internal
        view
        returns (uint256 collateralPrice, uint256 collateralValue, uint256 equity, uint256 leverageBps)
    {
        Position memory position = _getPosition(market, morpho, user);
        return getLeverageMetrics(market, position);
    }

    /// @dev Reads the raw Morpho borrow and collateral amounts for a user.
    function _getPosition(MarketParams memory market, IMorpho morpho, address user)
        private
        view
        returns (Position memory position)
    {
        MorphoPosition memory morphoPosition = morpho.position(market.id(), user);
        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) =
            MorphoBalancesLib.expectedMarketBalances(morpho, market);

        position.loan = uint256(morphoPosition.borrowShares).toAssetsUp(totalBorrowAssets, totalBorrowShares);
        position.collateral = uint256(morphoPosition.collateral);
    }

    /// @notice Computes collateral value, equity, and leverage for a position snapshot.
    /// @dev Returns `equity = 0` and `leverageBps = type(uint256).max` for underwater positions
    ///      (collateral value < debt).  Callers that need to reject underwater state should check
    ///      for `equity == 0 && position.loan > 0` and revert with a domain-appropriate error.
    function getLeverageMetrics(MarketParams memory market, Position memory position)
        internal
        view
        returns (uint256 collateralPrice, uint256 collateralValue, uint256 equity, uint256 leverageBps)
    {
        collateralPrice = IOracle(market.oracle).price();
        collateralValue = position.collateral.mulDiv(collateralPrice, ORACLE_PRICE_SCALE, Math.Rounding.Floor);

        equity = collateralValue.saturatingSub(position.loan);
        if (equity == 0) {
            leverageBps = type(uint256).max;
            return (collateralPrice, collateralValue, equity, leverageBps);
        }

        leverageBps = collateralValue.mulDiv(LEVERAGE_ONE, equity, Math.Rounding.Floor);
    }

    /// @notice Converts collateral units to loan-asset value using the Morpho oracle price.
    /// @param market Morpho market whose oracle provides the collateral price.
    /// @param collateral Amount of collateral units to convert.
    /// @return assets Loan-asset value of `collateral` according to the Morpho oracle (rounded down).
    function convertToAssets(MarketParams memory market, uint256 collateral) internal view returns (uint256 assets) {
        uint256 collateralPrice = IOracle(market.oracle).price();
        assets = collateral.mulDiv(collateralPrice, ORACLE_PRICE_SCALE, Math.Rounding.Floor);
    }

    /// @notice Converts loan-asset value to collateral units using the Morpho oracle price.
    /// @param market Morpho market whose oracle provides the collateral price.
    /// @param assets Loan-asset amount to convert.
    /// @return collateral Collateral units equivalent to `assets` according to the Morpho oracle (rounded down).
    function convertToShares(MarketParams memory market, uint256 assets) internal view returns (uint256 collateral) {
        uint256 collateralPrice = IOracle(market.oracle).price();
        collateral = assets.mulDiv(ORACLE_PRICE_SCALE, collateralPrice, Math.Rounding.Floor);
    }
}
