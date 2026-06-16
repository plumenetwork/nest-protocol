// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IMorpho, MarketParams} from "@morpho/interfaces/IMorpho.sol";
import {PredicateMessage} from "@predicate/src/interfaces/IPredicateClient.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";

/// @notice Market-side actions derived for a bundle.
struct MarketActions {
    /// @notice Loan-asset amount to borrow from Morpho.
    uint256 borrow;
    /// @notice Loan-asset amount to repay into Morpho.
    uint256 repay;
    /// @notice Collateral shares to supply to Morpho.
    uint256 supplyCollateral;
    /// @notice Collateral shares to withdraw from Morpho.
    uint256 withdrawCollateral;
}

/// @notice Vault-side actions required to source or sink collateral and loan assets.
struct VaultActions {
    /// @notice Shares to mint from the vault.
    uint256 mint;
    /// @notice Assets to deposit into the vault.
    uint256 deposit;
    /// @notice Shares to redeem from the vault.
    uint256 redeem;
    /// @notice Exact loan-asset minimum for legacy AtomicQueue redemptions (avoids E27 round-trip).
    uint256 withdraw;
    /// @notice Loan assets to pull from the owner via `transferFrom`.
    uint256 pullAssets;
    /// @notice Collateral shares to pull from the owner via `transferFrom`.
    uint256 pullShares;
}

/// @notice Runtime addresses and contracts used during bundle build/encoding.
/// @dev Derived from user inputs and bundler contract configuration.
struct BundleContext {
    /// @notice Morpho core contract.
    IMorpho morpho;
    /// @notice Nest vault used for share/asset conversions and redemptions.
    INestVaultCore vault;
    /// @notice Adapter executed by the bundler.
    address adapter;
    /// @notice Bundler contract that dispatches calls.
    address bundler;
    /// @notice Teller used for legacy deposit/redeem flows.
    address teller;
    /// @notice Predicate proxy used for predicate deposit/mint.
    address predicateProxy;
    /// @notice Atomic solver used for legacy redemption solves.
    address atomicSolver;
    /// @notice Atomic queue used by the solver.
    address atomicQueue;
    /// @notice Position owner in Morpho and vault.
    address owner;
    /// @notice Real transaction executor used by adapter and Morpho auth checks.
    address initiator;
    /// @notice ERC-7540 controller used for async redeem request/fulfill/redeem state.
    address controller;
}

/// @notice User-supplied market config, allowances, and price guards.
struct Position {
    /// @notice Desired final loan position in loan assets.
    uint256 loan;
    /// @notice Desired final collateral in shares.
    uint256 collateral;
}

/// @notice Target position plus leverage metrics derived from the source position used to build it.
struct PositionMetrics {
    /// @notice Derived target position in loan assets and collateral shares.
    Position position;
    /// @notice Equity preserved while re-levering into `position`.
    uint256 equity;
    /// @notice Leverage of the source position used to derive `position`.
    uint256 leverageBps;
}

/// @notice Intent mode selecting target-based or delta-based bundle derivation.
enum PositionMode {
    Target,
    Delta
}

/// @notice User-supplied market config, allowances, and price guards.
struct UserIntent {
    /// @notice Morpho market to act on.
    MarketParams market;
    /// @notice Max loan assets pullable from owner; `type(uint256).max` means unlimited.
    uint256 assetAllowance;
    /// @notice Max collateral shares pullable from owner; `type(uint256).max` means unlimited.
    uint256 shareAllowance;
    /// @notice Max accepted share price for mint/deposit paths (E27 fixed-point).
    uint256 maxSharePriceE27;
    /// @notice Min accepted share price for redeem paths (E27 fixed-point).
    uint256 minSharePriceE27;
    /// @notice Max accepted repay share price for Morpho repay (E27 fixed-point).
    uint256 maxRepaySharePriceE27;
    /// @notice Position derivation mode.
    PositionMode mode;
    /// @notice Target-based position request. All-zero when using delta mode.
    Position target;
    /// @notice Delta-based action request. All-zero when using target mode.
    MarketActions delta;
}

/// @notice Routing flags selecting legacy/predicate/instant redemption paths.
struct RouteInput {
    /// @notice Use legacy redemption through atomic solver.
    bool legacyRedemption;
    /// @notice Use legacy teller deposit path.
    bool legacyDeposit;
    /// @notice Use instant redeem path instead of request-and-redeem.
    bool instantRedeem;
}

/// @notice Fully derived bundle input consumed by calldata builders.
struct Bundle {
    /// @notice Runtime context contracts and addresses.
    BundleContext ctx;
    /// @notice User intent and safety limits.
    UserIntent intent;
    /// @notice Route selection flags.
    RouteInput route;
    /// @notice Predicate message forwarded to predicate-aware calls.
    PredicateMessage predicateMessage;
    /// @notice Derived Morpho-side actions.
    MarketActions ma;
    /// @notice Derived vault-side actions.
    VaultActions va;
}
