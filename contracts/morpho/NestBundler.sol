// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {PredicateMessage} from "@predicate/src/interfaces/IPredicateClient.sol";
import {IMorpho} from "@morpho/interfaces/IMorpho.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";

import {Call, IBundler3} from "contracts/vendor/bundler3/interfaces/IBundler3.sol";
import {ErrorsLib} from "contracts/vendor/bundler3/libraries/ErrorsLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BundleBuildLib} from "contracts/morpho/libraries/BundleBuildLib.sol";
import {BundleCalldataLib} from "contracts/morpho/libraries/BundleCalldataLib.sol";
import {Bundle, BundleContext, RouteInput, UserIntent} from "contracts/morpho/types/BundleTypes.sol";

/// @title NestBundler
/// @notice User-facing helper for building Nest+Morpho bundles and executing them through Bundler3.
/// @dev When executing through this contract, Bundler3 `initiator()` is this contract address.
contract NestBundler {
    using BundleBuildLib for BundleContext;
    using BundleBuildLib for Bundle;
    using BundleCalldataLib for Bundle;
    using SafeERC20 for IERC20;

    /// @notice Morpho core used to read positions and market state.
    IMorpho public immutable MORPHO;
    /// @notice Bundler3 entrypoint used to execute generated multicalls.
    IBundler3 public immutable BUNDLER3;
    /// @notice Nest adapter used by bundle calldata.
    address public immutable ADAPTER;
    /// @notice Predicate proxy used for predicate-protected deposit paths.
    address public immutable PREDICATE_PROXY;
    /// @notice Legacy predicate proxy used for legacy deposit paths.
    address public immutable LEGACY_PREDICATE_PROXY;
    /// @notice Atomic solver used for async redeem fulfillment.
    address public immutable ATOMIC_SOLVER;
    /// @notice Atomic queue used by async redeem routes.
    address public immutable ATOMIC_QUEUE;

    /// @notice Creates a new Nest bundler wrapper around Bundler3.
    /// @param morpho Morpho core address.
    /// @param bundler3 Bundler3 address used for multicall execution.
    /// @param adapter Nest adapter used by generated bundleCalls.
    /// @param predicateProxy Predicate proxy used in predicate deposit paths.
    /// @param atomicSolver Atomic solver used by async redeem paths.
    /// @param atomicQueue Atomic queue used by async redeem paths.
    constructor(
        address morpho,
        address bundler3,
        address adapter,
        address predicateProxy,
        address legacyPredicateProxy,
        address atomicSolver,
        address atomicQueue
    ) {
        require(
            morpho != address(0) && bundler3 != address(0) && adapter != address(0) && predicateProxy != address(0)
                && legacyPredicateProxy != address(0) && atomicSolver != address(0) && atomicQueue != address(0),
            ErrorsLib.ZeroAddress()
        );

        MORPHO = IMorpho(morpho);
        BUNDLER3 = IBundler3(bundler3);
        ADAPTER = adapter;
        PREDICATE_PROXY = predicateProxy;
        LEGACY_PREDICATE_PROXY = legacyPredicateProxy;
        ATOMIC_SOLVER = atomicSolver;
        ATOMIC_QUEUE = atomicQueue;
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Builds a full bundle for a user intent and route selection.
    /// @param intent User intent describing target/delta and limits.
    /// @param route Route flags selecting deposit/redeem paths.
    /// @param predicateMessage Predicate payload passed to predicate-aware adapter bundleCalls.
    /// @param vault Nest vault used for share conversions and redemptions.
    /// @param teller Legacy teller used by legacy deposit paths.
    /// @param owner Owner used for position and balance checks.
    /// @param initiator Logical initiator used during bundle derivation.
    /// @return bundle Fully derived bundle payload.
    function getBundle(
        UserIntent calldata intent,
        RouteInput calldata route,
        PredicateMessage calldata predicateMessage,
        INestVaultCore vault,
        address teller,
        address owner,
        address initiator
    ) external view returns (Bundle memory bundle) {
        bundle = _getBundle(intent, route, predicateMessage, vault, teller, owner, initiator);
    }

    /// @notice Builds only the immediately executable sync portion of a bundle.
    /// @dev The sync phase is always derived with `owner` as initiator so owner-funded pulls can execute now.
    /// @param intent User intent describing target/delta and limits.
    /// @param route Route flags selecting deposit/redeem paths.
    /// @param predicateMessage Predicate payload passed to predicate-aware adapter bundleCalls.
    /// @param vault Nest vault used for share conversions and redemptions.
    /// @param teller Legacy teller used by legacy deposit paths.
    /// @param owner Owner used for position and balance checks.
    /// @return syncBundle Owner-executable phase that can run immediately.
    function getSyncBundle(
        UserIntent calldata intent,
        RouteInput calldata route,
        PredicateMessage calldata predicateMessage,
        INestVaultCore vault,
        address teller,
        address owner
    ) external view returns (Bundle memory syncBundle) {
        Bundle memory bundle = _getBundle(intent, route, predicateMessage, vault, teller, owner, owner);
        syncBundle = bundle.getSyncBundle();
    }

    /// @notice Builds only the async, redeem-dependent portion of a bundle.
    /// @dev The async phase is derived with `initiator` and excludes any owner-sync work.
    /// @param intent User intent describing target/delta and limits.
    /// @param route Route flags selecting deposit/redeem paths.
    /// @param predicateMessage Predicate payload passed to predicate-aware adapter bundleCalls.
    /// @param vault Nest vault used for share conversions and redemptions.
    /// @param teller Legacy teller used by legacy deposit paths.
    /// @param owner Owner used for position and balance checks.
    /// @param initiator Logical initiator expected to execute the async phase.
    /// @return asyncBundle Redeem-dependent phase intended for later execution.
    function getAsyncBundle(
        UserIntent calldata intent,
        RouteInput calldata route,
        PredicateMessage calldata predicateMessage,
        INestVaultCore vault,
        address teller,
        address owner,
        address initiator
    ) external view returns (Bundle memory asyncBundle) {
        Bundle memory bundle = _getBundle(intent, route, predicateMessage, vault, teller, owner, owner);
        asyncBundle = bundle.getAsyncBundle();
        asyncBundle.ctx.initiator = initiator;
    }

    /// @notice Builds Bundler3 bundleCalls and required ERC20 approval txs for direct execution.
    /// @param intent User intent describing target/delta and limits.
    /// @param route Route flags selecting deposit/redeem paths.
    /// @param predicateMessage Predicate payload passed to predicate-aware adapter bundleCalls.
    /// @param vault Nest vault used for share conversions and redemptions.
    /// @param teller Legacy teller used by legacy deposit paths.
    /// @param owner Owner used for position and balance checks.
    /// @param initiator Logical initiator used during bundle derivation.
    /// @return bundleCalls Bundler3 call array ready for `multicall`.
    /// @return approveCalls Ordered approval txs required before `Bundler3.multicall`.
    ///                    These approveCalls are for direct Bundler3 path (`initiator` -> `ADAPTER` allowances).
    function getBundleCalls(
        UserIntent calldata intent,
        RouteInput calldata route,
        PredicateMessage calldata predicateMessage,
        INestVaultCore vault,
        address teller,
        address owner,
        address initiator
    ) external view returns (Call[] memory bundleCalls, Call[] memory approveCalls) {
        Bundle memory bundle = _getBundle(intent, route, predicateMessage, vault, teller, owner, initiator);
        (bundleCalls, approveCalls) = _getBundleCallsAndApprovals(bundle);
    }

    /// @notice Builds direct-execution bundleCalls and approval txs for the sync portion only.
    /// @dev Empty sync phases return zero-length `bundleCalls` and `approveCalls`.
    /// @param bundle Fully derived bundle payload.
    /// @return bundleCalls Bundler3 bundleCalls executable immediately by the owner.
    /// @return approveCalls ERC20 approveCalls required before `bundleCalls`.
    function getSyncBundleCalls(Bundle memory bundle)
        external
        view
        returns (Call[] memory bundleCalls, Call[] memory approveCalls)
    {
        Bundle memory syncBundle = bundle.getSyncBundle();
        (bundleCalls, approveCalls) = _getBundleCallsAndApprovals(syncBundle);
    }

    /// @notice Builds direct-execution bundleCalls and approval txs for the async portion only.
    /// @dev Empty async phases return zero-length `bundleCalls` and `approveCalls`.
    /// @param bundle Fully derived bundle payload.
    /// @return bundleCalls Bundler3 bundleCalls that remain for the async executor.
    function getAsyncBundleCalls(Bundle memory bundle) external view returns (Call[] memory bundleCalls) {
        Bundle memory asyncBundle = bundle.getAsyncBundle();
        (bundleCalls,) = _getBundleCallsAndApprovals(asyncBundle);
    }

    /// @notice Returns whether a bundle contains only sync-executable actions.
    function isSyncRedeem(Bundle memory bundle) external pure returns (bool) {
        return bundle.isSyncRedeem();
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Builds and executes a bundle immediately for `msg.sender`.
    /// @param intent User intent describing target/delta and limits.
    /// @param route Route flags selecting deposit/redeem paths.
    /// @param predicateMessage Predicate payload passed to predicate-aware adapter bundleCalls.
    /// @param vault Nest vault used for share conversions and redemptions.
    /// @param teller Legacy teller used by legacy deposit paths.
    /// @return bundleCalls Bundler3 call array that was executed.
    function getBundleAndExecute(
        UserIntent calldata intent,
        RouteInput calldata route,
        PredicateMessage calldata predicateMessage,
        INestVaultCore vault,
        address teller
    ) external returns (Call[] memory bundleCalls) {
        address owner = msg.sender;

        // Build with owner as initiator so owner-funded pull legs are derived correctly.
        Bundle memory bundle = _getBundle(intent, route, predicateMessage, vault, teller, owner, owner);
        bundleCalls = _executeBundle(bundle, owner);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Pulls owner funds, executes Bundler3 multicall, and returns leftovers to owner.
    /// @param bundle Bundle payload to execute.
    /// @param owner Owner whose balances are pulled and swept.
    /// @return bundleCalls Bundler3 call array that was executed.
    function _executeBundle(Bundle memory bundle, address owner) internal returns (Call[] memory bundleCalls) {
        address loanToken = bundle.intent.market.loanToken;
        address collateralToken = bundle.intent.market.collateralToken;
        uint256 pullAssets = bundle.va.pullAssets;
        uint256 pullShares = bundle.va.pullShares;

        // Track baseline balances to sweep any execution leftovers back to owner.
        uint256 loanBalanceBefore = IERC20(loanToken).balanceOf(address(this));
        uint256 collateralBalanceBefore = IERC20(collateralToken).balanceOf(address(this));

        // Pull tokens from this owner to this contract.
        if (pullAssets != 0) {
            IERC20(loanToken).safeTransferFrom(owner, address(this), pullAssets);
            IERC20(loanToken).forceApprove(ADAPTER, pullAssets);
        }
        if (pullShares != 0) {
            IERC20(collateralToken).safeTransferFrom(owner, address(this), pullShares);
            IERC20(collateralToken).forceApprove(ADAPTER, pullShares);
        }

        // Real execution initiator is this contract because it bundleCalls Bundler3.
        bundle.ctx.initiator = address(this);
        bundleCalls = bundle.getBundleCalls();
        BUNDLER3.multicall(bundleCalls);

        // Reset approveCalls.
        if (pullAssets != 0) IERC20(loanToken).forceApprove(ADAPTER, 0);
        if (pullShares != 0) IERC20(collateralToken).forceApprove(ADAPTER, 0);

        // Sweep any leftover tokens back to owner.
        uint256 loanBalanceAfter = IERC20(loanToken).balanceOf(address(this));
        if (loanBalanceAfter > loanBalanceBefore) {
            IERC20(loanToken).safeTransfer(owner, loanBalanceAfter - loanBalanceBefore);
        }
        uint256 collateralBalanceAfter = IERC20(collateralToken).balanceOf(address(this));
        if (collateralBalanceAfter > collateralBalanceBefore) {
            IERC20(collateralToken).safeTransfer(owner, collateralBalanceAfter - collateralBalanceBefore);
        }
    }

    /// @dev Builds a bundle and attaches the provided predicate message.
    /// @param intent User intent describing target/delta and limits.
    /// @param route Route flags selecting deposit/redeem paths.
    /// @param predicateMessage Predicate payload passed to predicate-aware adapter bundleCalls.
    /// @param vault Nest vault used for share conversions and redemptions.
    /// @param teller Legacy teller used by legacy deposit paths.
    /// @param owner Owner used for position and balance checks.
    /// @param initiator Logical initiator used during bundle derivation.
    /// @return bundle Fully derived bundle payload.
    function _getBundle(
        UserIntent memory intent,
        RouteInput memory route,
        PredicateMessage calldata predicateMessage,
        INestVaultCore vault,
        address teller,
        address owner,
        address initiator
    ) internal view returns (Bundle memory bundle) {
        BundleContext memory ctx = _bundleContext(route, vault, teller, owner, initiator);
        bundle = ctx.getBundle(intent, route);
        bundle.predicateMessage = predicateMessage;
    }

    /// @dev Assembles bundle context from explicit vault and routing parameters.
    /// @param vault Nest vault used for share conversions and redemptions.
    /// @param teller Legacy teller used by legacy deposit paths.
    /// @param owner Owner used for position and balance checks.
    /// @param initiator Logical initiator used during bundle derivation.
    /// @return ctx Fully populated bundle context.
    function _bundleContext(
        RouteInput memory route,
        INestVaultCore vault,
        address teller,
        address owner,
        address initiator
    ) internal view returns (BundleContext memory ctx) {
        ctx = BundleContext({
            morpho: MORPHO,
            vault: vault,
            adapter: ADAPTER,
            bundler: address(BUNDLER3),
            teller: teller,
            predicateProxy: route.legacyDeposit ? LEGACY_PREDICATE_PROXY : PREDICATE_PROXY,
            atomicSolver: ATOMIC_SOLVER,
            atomicQueue: ATOMIC_QUEUE,
            owner: owner,
            initiator: initiator,
            controller: owner
        });
    }

    /// @dev Builds direct user tx sequence approveCalls for the provided bundle.
    /// @param bundle Bundle payload used to derive approval requirements.
    /// @return approveCalls Ordered approval tx sequence for off-chain execution.
    function _getApprovalTxs(Bundle memory bundle) internal view returns (Call[] memory approveCalls) {
        address loanToken = bundle.intent.market.loanToken;
        address collateralToken = bundle.intent.market.collateralToken;

        uint256 loanApprovalAmount = bundle.va.pullAssets;
        uint256 collateralApprovalAmount = bundle.va.pullShares;

        // Legacy atomic solve can transfer redeemed loan assets from owner via adapter transferFrom.
        // Add this upper-bound amount on top of regular pullAssets allowance.
        if (bundle.route.legacyRedemption && bundle.va.redeem != 0) {
            (uint256 legacyRedeemMaxAssets,) = BundleCalldataLib.legacyRedeemRequestAmounts(bundle);
            loanApprovalAmount += legacyRedeemMaxAssets;
        }

        uint256 txCount;
        if (loanApprovalAmount != 0) txCount++;
        if (collateralApprovalAmount != 0) txCount++;

        approveCalls = new Call[](txCount);
        uint256 i;

        if (loanApprovalAmount != 0) {
            Call memory call;
            call.to = loanToken;
            call.data = abi.encodeCall(IERC20.approve, (ADAPTER, loanApprovalAmount));
            approveCalls[i++] = call;
        }
        if (collateralApprovalAmount != 0) {
            Call memory call;
            call.to = collateralToken;
            call.data = abi.encodeCall(IERC20.approve, (ADAPTER, collateralApprovalAmount));
            approveCalls[i++] = call;
        }
    }

    /// @dev Returns call data and approval txs for a single bundle, leaving empty phases empty.
    function _getBundleCallsAndApprovals(Bundle memory bundle)
        internal
        view
        returns (Call[] memory bundleCalls, Call[] memory approveCalls)
    {
        if (!bundle.hasActions()) return (new Call[](0), new Call[](0));
        bundleCalls = bundle.getBundleCalls();
        approveCalls = _getApprovalTxs(bundle);
    }
}
