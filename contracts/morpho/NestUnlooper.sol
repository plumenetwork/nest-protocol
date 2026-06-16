// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Call, IBundler3} from "contracts/vendor/bundler3/interfaces/IBundler3.sol";

import {Id, IMorpho, MarketParams} from "@morpho/interfaces/IMorpho.sol";
import {MarketParamsLib} from "@morpho/libraries/MarketParamsLib.sol";

import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {NestAdapter} from "contracts/morpho/NestAdapter.sol";
import {BundleBuildLib} from "contracts/morpho/libraries/BundleBuildLib.sol";
import {BundleCalldataLib} from "contracts/morpho/libraries/BundleCalldataLib.sol";
import {MorphoMarketLib} from "contracts/morpho/libraries/MorphoMarketLib.sol";
import {NestShareMathLib} from "contracts/morpho/libraries/NestShareMathLib.sol";
import {NestUnlooperErrors} from "contracts/morpho/types/Errors.sol";
import {
    Bundle,
    BundleContext,
    MarketActions,
    Position,
    PositionMetrics,
    PositionMode,
    UserIntent
} from "contracts/morpho/types/BundleTypes.sol";

import {AtomicQueue} from "@boring-vault/src/atomic-queue/AtomicQueue.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/src/base/Roles/TellerWithMultiAssetSupport.sol";

/// @title NestUnlooper
/// @notice Keeper-only unlooper that unwinds a Morpho position through either the legacy AtomicQueue route
///         or a modern target-leverage async redeem route.
/// @dev The legacy route tolerates the AtomicQueue "insufficient balance" flag because it withdraws the
///      required collateral from Morpho before invoking the queue solve.
contract NestUnlooper is Auth {
    using BundleBuildLib for BundleContext;
    using MorphoMarketLib for MarketParams;
    using MarketParamsLib for MarketParams;
    using BundleCalldataLib for Bundle;
    using NestShareMathLib for uint256;

    /// @notice Fee-rate denominator matching `NestVaultAccountingLogic.FEE_DENOMINATOR`.
    uint256 private constant FEE_DENOMINATOR = 1_000_000;
    /// @notice Leverage basis-point scale matching `MorphoMarketLib.LEVERAGE_ONE`.
    uint256 private constant LEVERAGE_ONE = 10_000;

    /// @notice Stored modern async-unloop request where `10_000 = 1x` and `0` fully exits the Morpho position.
    struct UnloopRequest {
        /// @notice Minimum accepted vault exit share price, scaled by 1e27.
        uint256 minSharePriceE27;
        /// @notice Latest timestamp at which the request can be executed.
        uint64 deadline;
        /// @notice Target leverage scaled by 1e4 where `10_000 = 1x`.
        uint32 leverageBps;
    }

    /// @notice Morpho core used to read and rebalance positions.
    IMorpho public immutable MORPHO;
    /// @notice Bundler3 instance used to execute derived multicalls.
    IBundler3 public immutable BUNDLER3;
    /// @notice Nest adapter used by encoded bundle calls.
    NestAdapter public immutable NEST_ADAPTER;
    /// @notice Atomic solver used by legacy AtomicQueue unloops.
    address public immutable ATOMIC_SOLVER;
    /// @notice Atomic queue used to inspect and solve legacy async redeems.
    AtomicQueue public immutable ATOMIC_QUEUE;

    /// @notice Stored modern async-unloop requests keyed by user and Morpho market id.
    mapping(address user => mapping(bytes32 marketId => UnloopRequest request)) internal unloopRequest;

    /// @notice Approved vaults and tellers that `execute` may target.
    mapping(address target => bool approved) public approvedVault;

    /// @notice Emitted when an address's approval status changes.
    /// @param target Vault or teller address.
    /// @param approved New approval status.
    event VaultApprovalSet(address indexed target, bool approved);

    /// @notice Emitted when a user stores or updates a modern async-unloop request.
    /// @param user Position owner.
    /// @param marketId Morpho market id.
    /// @param leverageBps Target leverage scaled by 1e4 where `10_000 = 1x`.
    /// @param minSharePriceE27 Minimum accepted vault exit share price, scaled by 1e27.
    /// @param deadline Latest timestamp at which the request can execute.
    event UnloopRequestUpdated(
        address indexed user, bytes32 indexed marketId, uint32 leverageBps, uint256 minSharePriceE27, uint64 deadline
    );

    /// @notice Emitted when a user's stored async-unloop request is deleted.
    /// @param user Position owner.
    /// @param marketId Morpho market id.
    event UnloopRequestCleared(address indexed user, bytes32 indexed marketId);

    /// @notice Emitted after an async unloop bundle executes.
    /// @param user Position owner.
    /// @param marketId Morpho market id.
    /// @param repay Loan assets repaid on Morpho.
    /// @param withdrawCollateral Collateral shares withdrawn from Morpho.
    /// @param redeem Vault shares redeemed or withdrawn.
    event Executed(
        address indexed user, bytes32 indexed marketId, uint256 repay, uint256 withdrawCollateral, uint256 redeem
    );

    /// @notice Creates a new keeper-only Nest unlooper.
    /// @param owner_ Initial auth owner.
    /// @param authority_ Optional external authority.
    /// @param morpho Morpho core address.
    /// @param bundler3 Bundler3 address used for execution.
    /// @param nestAdapter Nest adapter used by generated calls.
    /// @param atomicSolver Atomic solver used by legacy unloops.
    /// @param atomicQueue Atomic queue used by legacy unloops.
    constructor(
        address owner_,
        Authority authority_,
        address morpho,
        address bundler3,
        address nestAdapter,
        address atomicSolver,
        address atomicQueue
    ) Auth(owner_, authority_) {
        MORPHO = IMorpho(morpho);
        BUNDLER3 = IBundler3(bundler3);
        NEST_ADAPTER = NestAdapter(payable(nestAdapter));
        ATOMIC_SOLVER = atomicSolver;
        ATOMIC_QUEUE = AtomicQueue(atomicQueue);
    }

    /// @notice Sets whether an address (vault or teller) is approved for use in `execute`.
    /// @param target Address to approve or revoke.
    /// @param approved Whether the address is approved.
    function setVaultApproval(address target, bool approved) external requiresAuth {
        approvedVault[target] = approved;
        emit VaultApprovalSet(target, approved);
    }

    /// @notice Stores a modern async-unloop request. A zero storage deadline means the request is unset, while
    ///         `0` leverage means a full Morpho exit instead of an unset request.
    function updateUnloopRequest(
        MarketParams calldata marketParams,
        uint32 leverageBps,
        uint256 minSharePriceE27,
        uint64 deadline
    ) external {
        if (deadline < block.timestamp) {
            revert NestUnlooperErrors.InvalidUnloopDeadline(deadline, block.timestamp);
        }

        bytes32 marketId = Id.unwrap(marketParams.id());

        PositionMetrics memory current = marketParams.getCurrentPosition(MORPHO, msg.sender);
        if (current.position.collateral == 0) {
            revert NestUnlooperErrors.NoPositionToUnloop();
        }
        if (current.equity == 0 && current.position.loan > 0) {
            revert NestUnlooperErrors.PositionUnderwater(msg.sender, marketId);
        }
        if (leverageBps >= current.leverageBps) {
            revert NestUnlooperErrors.TargetLeverageNotBelowCurrent(leverageBps, current.leverageBps);
        }
        UnloopRequest storage request = unloopRequest[msg.sender][marketId];
        request.minSharePriceE27 = minSharePriceE27;
        request.deadline = deadline;
        request.leverageBps = leverageBps;

        emit UnloopRequestUpdated(msg.sender, marketId, leverageBps, minSharePriceE27, deadline);
    }

    /// @notice Clears any stored modern async-unloop request for the caller.
    function clearUnloopRequest(MarketParams calldata marketParams) external {
        bytes32 marketId = Id.unwrap(marketParams.id());
        delete unloopRequest[msg.sender][marketId];

        emit UnloopRequestCleared(msg.sender, marketId);
    }

    /// @notice Returns the stored modern async-unloop request for a user and market.
    /// @param user Position owner.
    /// @param marketParams Morpho market identifying the request.
    /// @return request Stored request data, or zeroed values if unset.
    function getUnloopRequest(address user, MarketParams calldata marketParams)
        external
        view
        returns (UnloopRequest memory request)
    {
        request = unloopRequest[user][Id.unwrap(marketParams.id())];
    }

    /// @notice Builds the async unloop bundle from live AtomicQueue and Morpho state.
    /// @param marketParams Morpho market identifying the position.
    /// @param vault Nest vault used for share conversions and vault-side actions.
    /// @param teller Teller used by the AtomicSolver for share redemption.
    /// @param user Position owner whose AtomicQueue request drives the unloop.
    /// @param useAtomicQueue Whether to use the AtomicQueue redemption route.
    /// @return bundle Fully populated bundle ready for calldata encoding.
    function getAsyncBundle(
        MarketParams calldata marketParams,
        INestVaultCore vault,
        TellerWithMultiAssetSupport teller,
        address user,
        bool useAtomicQueue
    ) external view returns (Bundle memory bundle) {
        bundle = _getAsyncBundle(marketParams, vault, address(teller), user, useAtomicQueue);
    }

    /// @notice Builds and encodes the async unloop bundle as Bundler3 calls.
    /// @param marketParams Morpho market identifying the position.
    /// @param vault Nest vault used for share conversions and vault-side actions.
    /// @param teller Teller used by the AtomicSolver for share redemption.
    /// @param user Position owner whose AtomicQueue request drives the unloop.
    /// @param useAtomicQueue Whether to use the AtomicQueue redemption route.
    /// @return calls Bundler3 call array ready for multicall.
    function getAsyncBundleCalls(
        MarketParams calldata marketParams,
        INestVaultCore vault,
        TellerWithMultiAssetSupport teller,
        address user,
        bool useAtomicQueue
    ) external view returns (Call[] memory calls) {
        Bundle memory bundle = _getAsyncBundle(marketParams, vault, address(teller), user, useAtomicQueue);
        calls = bundle.getBundleCalls();
    }

    /// @notice Builds, encodes, and executes the async unloop bundle via Bundler3.
    /// @param marketParams Morpho market identifying the position.
    /// @param vault Nest vault used for share conversions and vault-side actions.
    /// @param teller Teller used by the AtomicSolver for share redemption.
    /// @param user Position owner whose AtomicQueue request drives the unloop.
    /// @param useAtomicQueue Whether to use the AtomicQueue redemption route.
    /// @return calls Bundler3 call array that was executed.
    function execute(
        MarketParams calldata marketParams,
        INestVaultCore vault,
        TellerWithMultiAssetSupport teller,
        address user,
        bool useAtomicQueue
    ) external requiresAuth returns (Call[] memory calls) {
        if (address(vault) != address(0) && !approvedVault[address(vault)]) {
            revert NestUnlooperErrors.VaultNotApproved(address(vault));
        }
        if (address(teller) != address(0) && !approvedVault[address(teller)]) {
            revert NestUnlooperErrors.TellerNotApproved(address(teller));
        }
        calls = _execute(marketParams, vault, address(teller), user, useAtomicQueue);
    }

    /// @dev Builds and executes the async bundle, clearing stored modern requests after success.
    function _execute(
        MarketParams memory marketParams,
        INestVaultCore vault,
        address teller,
        address user,
        bool useAtomicQueue
    ) internal returns (Call[] memory calls) {
        Bundle memory bundle = _getAsyncBundle(marketParams, vault, teller, user, useAtomicQueue);
        calls = bundle.getBundleCalls();

        BUNDLER3.multicall(calls);

        if (!useAtomicQueue) delete unloopRequest[user][Id.unwrap(marketParams.id())];

        emit Executed(
            user, Id.unwrap(marketParams.id()), bundle.ma.repay, bundle.ma.withdrawCollateral, bundle.va.redeem
        );
    }

    /// @dev Builds the async bundle context and intent for either legacy or modern unloop paths.
    function _getAsyncBundle(
        MarketParams memory marketParams,
        INestVaultCore vault,
        address teller,
        address user,
        bool useAtomicQueue
    ) internal view returns (Bundle memory bundle) {
        UserIntent memory intent = useAtomicQueue
            ? _getAtomicQueueAsyncIntent(marketParams, user)
            : _getNestVaultAsyncIntent(marketParams, user, vault);
        BundleContext memory ctx = _bundleContext(vault, teller, user);
        bundle = ctx.getAsyncBundle(intent, useAtomicQueue);
    }

    /// @dev Reads AtomicQueue and Morpho state and derives the legacy async intent.
    function _getAtomicQueueAsyncIntent(MarketParams memory marketParams, address user)
        internal
        view
        returns (UserIntent memory intent)
    {
        uint256 assetsToOffer;
        uint256 assetsForWant;
        bytes32 marketId = Id.unwrap(marketParams.id());
        {
            address[] memory users = new address[](1);
            users[0] = user;
            (AtomicQueue.SolveMetaData[] memory metaData,,) = ATOMIC_QUEUE.viewSolveMetaData(
                ERC20(marketParams.collateralToken), ERC20(marketParams.loanToken), users
            );
            if (metaData.length != 1) revert NestUnlooperErrors.InvalidAtomicQueueRequest(user, marketId);
            // Only flag 2 (insufficient balance) is fixable mid-bundle via collateral withdrawal.
            // Flags 0 (expired), 1 (zero offer), 3 (no approval) guarantee a revert at solve time.
            if (metaData[0].flags & ~uint8(4) != 0) {
                revert NestUnlooperErrors.InvalidAtomicQueueRequest(user, marketId);
            }
            assetsToOffer = metaData[0].assetsToOffer;
            assetsForWant = metaData[0].assetsForWant;
            if (assetsToOffer == 0 || assetsForWant == 0) {
                revert NestUnlooperErrors.InvalidAtomicQueueRequest(user, marketId);
            }
        }

        intent.market = marketParams;
        intent.maxSharePriceE27 = type(uint256).max;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.minSharePriceE27 = Math.mulDiv(assetsForWant, 1e27, assetsToOffer, Math.Rounding.Ceil);
        intent.mode = PositionMode.Delta;

        Position memory currentPosition = marketParams.getPosition(MORPHO, user);
        MarketActions memory ma;
        ma.repay = Math.min(currentPosition.loan, assetsForWant);
        ma.withdrawCollateral = assetsToOffer;

        intent.delta = ma;
    }

    /// @dev Reads the stored modern request and derives the target-position async intent.
    ///      For partial deleverages (leverageBps > 0) with non-zero redemption fees, the preserved
    ///      equity is reduced so that post-fee redeem proceeds fully cover the loan repayment.
    ///      Reverts with `PositionUnderwater` if the position's collateral value has fallen below its
    ///      debt since the request was stored.  Callers should use `clearUnloopRequest` to clean up
    ///      stuck requests, or fall back to the legacy AtomicQueue route which tolerates underwater state.
    function _getNestVaultAsyncIntent(MarketParams memory marketParams, address user, INestVaultCore vault)
        internal
        view
        returns (UserIntent memory intent)
    {
        bytes32 marketId = Id.unwrap(marketParams.id());
        UnloopRequest memory request = unloopRequest[user][marketId];
        if (request.deadline == 0) revert NestUnlooperErrors.UnloopRequestNotSet(user, marketId);
        uint32 leverageBps = request.leverageBps;
        if (block.timestamp > request.deadline) {
            revert NestUnlooperErrors.UnloopRequestExpired(user, request.deadline, block.timestamp);
        }

        PositionMetrics memory current = marketParams.getCurrentPosition(MORPHO, user);
        if (current.equity == 0 && current.position.loan > 0) {
            revert NestUnlooperErrors.PositionUnderwater(user, marketId);
        }
        if (leverageBps >= current.leverageBps) {
            revert NestUnlooperErrors.TargetLeverageNotBelowCurrent(leverageBps, current.leverageBps);
        }

        // Fee-adjust equity for partial deleverages so post-fee redeem proceeds cover the repay.
        if (leverageBps > 0) {
            (uint32 feeRate, uint256 flatFee) = vault.fees(NestVaultCoreTypes.Fees.Redemption);
            if (feeRate > 0 || flatFee > 0) {
                uint256 collateralValue = current.equity + current.position.loan;
                uint256 feeCost =
                    Math.mulDiv(collateralValue, uint256(feeRate), FEE_DENOMINATOR, Math.Rounding.Ceil) + flatFee;
                uint256 leverageFee =
                    Math.mulDiv(uint256(leverageBps), uint256(feeRate), FEE_DENOMINATOR, Math.Rounding.Floor);
                if (current.equity <= feeCost || leverageFee >= LEVERAGE_ONE) {
                    revert NestUnlooperErrors.UnloopFeeInfeasible(user, marketId);
                }
                current.equity = (current.equity - feeCost) * LEVERAGE_ONE / (LEVERAGE_ONE - leverageFee);
            }
        }

        PositionMetrics memory target = marketParams.getTargetPosition(current, leverageBps);

        intent.market = marketParams;
        intent.assetAllowance = 0;
        intent.shareAllowance = 0;
        intent.maxSharePriceE27 = type(uint256).max;
        intent.minSharePriceE27 = request.minSharePriceE27;
        intent.maxRepaySharePriceE27 = type(uint256).max;
        intent.mode = PositionMode.Target;
        intent.target = target.position;
    }

    /// @dev Assembles the bundle context used by async bundle building.
    function _bundleContext(INestVaultCore vault, address teller, address user)
        internal
        view
        returns (BundleContext memory ctx)
    {
        ctx = BundleContext({
            morpho: MORPHO,
            vault: vault,
            adapter: address(NEST_ADAPTER),
            bundler: address(BUNDLER3),
            teller: teller,
            predicateProxy: address(1),
            atomicSolver: ATOMIC_SOLVER,
            atomicQueue: address(ATOMIC_QUEUE),
            owner: user,
            initiator: address(this),
            controller: user
        });
    }
}
