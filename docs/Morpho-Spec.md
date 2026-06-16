# Morpho Integration Spec

This document reflects the current implementation in:

- `contracts/morpho/NestAdapter.sol`
- `contracts/morpho/NestUnlooper.sol`
- `contracts/morpho/libraries/BundleBuildLib.sol`
- `contracts/morpho/libraries/BundleCalldataLib.sol`
- `contracts/morpho/libraries/MorphoMarketLib.sol`
- `contracts/morpho/libraries/NestVaultLib.sol`

## Overview

The Morpho integration builds and executes leveraged Morpho positions where the Morpho collateral token is the Nest vault share token and the Morpho loan token is the Nest vault asset. This spec covers bundle derivation, adapter execution, and keeper-driven async deleveraging. `NestBundler` wrapper entrypoints are intentionally out of scope.

The system supports three redemption routes:

- `instantRedeem`
- modern async redeem (`requestRedeem -> fulfillRedeem -> withdraw`)
- legacy AtomicQueue / AtomicSolver redemption

It also supports two deposit routes:

- modern predicate-gated vault mint
- legacy teller deposit

## Market and Position Model

### Required market / vault pairing

Bundle building requires:

- `market.collateralToken == vault.share()`
- `market.loanToken == vault.asset()`
- `morpho.market(market.id()).lastUpdate != 0`

If any of these fail, bundle derivation reverts before calldata is produced.

### Leverage

Leverage is expressed in basis points where `10_000 = 1x`:

```solidity
collateralValue = collateral * oraclePrice / ORACLE_PRICE_SCALE
equity          = max(collateralValue - loan, 0)
leverageBps     = collateralValue * 10_000 / equity
```

When `equity == 0`, `MorphoMarketLib.getLeverageMetrics` returns `type(uint256).max` leverage.

### Equity preservation

Target-leverage flows preserve equity. Given a current position and a desired leverage:

```solidity
targetCollateralValue = equity * targetLeverageBps / 10_000
targetCollateral      = targetCollateralValue * ORACLE_PRICE_SCALE / oraclePrice
targetLoan            = actualCollateralValue - equity
```

`targetLeverageBps == 0` means a full Morpho exit.

### Intent modes

The builder accepts two intent modes:

- `Target`: user supplies an absolute `Position { loan, collateral }`
- `Delta`: user supplies `MarketActions { borrow, repay, supplyCollateral, withdrawCollateral }`

Rules enforced by `BundleBuildLib`:

- target mode requires the delta struct to be all-zero
- delta mode requires the target struct to be all-zero
- delta mode cannot both borrow and repay
- delta mode cannot both supply and withdraw collateral
- delta repay cannot exceed current borrow
- delta collateral withdrawal cannot exceed current collateral

`assetAllowance` and `shareAllowance` are bundle-build caps, not ERC20 approvals. They limit how much owner inventory the builder is allowed to consume as `pullAssets` and `pullShares`.

## Bundle Derivation

### Owner inventory and mint sizing

The builder first uses owner-held vault shares to offset `ma.supplyCollateral`:

- `va.pullShares = min(ownerShareBalance, shareAllowance, ma.supplyCollateral)`
- `va.mint = ma.supplyCollateral - va.pullShares`

If new shares still need to be created:

- modern deposit path uses `vault.previewMint(va.mint)`
- legacy deposit path uses fee-free accountant-rate conversion with ceil rounding

That produces `va.deposit`, the loan-asset amount that must enter the vault.

### Required loan assets

`requiredLoanAssets` is always:

```solidity
requiredLoanAssets = ma.repay + va.deposit
```

The owner-funded portion depends on endogenous assets generated inside the bundle:

- if `ma.repay == 0`, Morpho borrow offsets the deposit leg
- if `ma.repay > 0`, vault exit proceeds offset repay first, then any remaining deposit need

For vault exits, the builder uses route-specific previews:

- legacy redemption: fee-free share-to-asset conversion
- `instantRedeem`: `vault.previewInstantRedeem(...)`
- modern async redeem: `vault.previewFulfillRedeem(...)`

The builder then derives:

- `requiredRepayLoanAssets`
- `requiredDepositLoanAssets`
- `va.pullAssets = requiredRepayLoanAssets + requiredDepositLoanAssets`

If `assetAllowance` is finite and below `va.pullAssets`, derivation reverts. It also reverts if the owner balance is below `va.pullAssets`.

### Owner vs initiator

If the bundle needs to pull either owner loan assets or owner shares, it requires:

```solidity
ctx.owner == ctx.initiator
```

This is why delegated execution only works for bundles that do not pull owner balances, or for the async half of a split redeem flow.

### Flash-loan sizing

Flash-loan need is:

```solidity
flashLoanAssets = max(requiredLoanAssets - va.pullAssets, 0)
```

If `flashLoanAssets == 0`, the callback bundle is executed directly. Otherwise the callback bundle is wrapped in `MorphoAdapter.morphoFlashLoan(...)`.

### Redeem sizing

Redeem sizing only matters when the bundle both repays and still needs flash-loaned loan assets.

- legacy redemption: `va.redeem = convertToShares(flashLoanAssets, ceil)`
- instant redeem: `va.redeem = vault.getMinRedeemShares(flashLoanAssets, Fees.InstantRedemption)`
- modern async redeem: `va.redeem = vault.getMinRedeemShares(flashLoanAssets, Fees.Redemption)`

Two additional constraints are enforced:

- instant redeem liquidity must cover `va.redeem`
- `va.redeem <= ma.withdrawCollateral`

That second check is important: fee-aware redeem sizing is not allowed to demand more shares than the bundle actually withdraws from Morpho.

### Route compatibility

The builder enforces:

- `legacyRedemption` and `instantRedeem` cannot both be `true`
- legacy deposit requires `predicateProxy` authority on `teller.deposit`
- modern deposit requires `predicateProxy` authority on `vault.mint`

### Split execution semantics

Non-instant redeem bundles can be split into:

- a sync portion with owner-funded work
- an async redeem-dependent portion

The split preserves the same underlying bundle math:

- the sync portion keeps owner-funded repay work
- the async portion removes owner pulls and keeps the redeem-dependent repay / withdraw / redeem legs

## Execution Model

### Callback order

`BundleCalldataLib` encodes calls in this order, skipping zero-amount steps:

1. `pullLoanAssets`
2. `pullCollateralShares`
3. `morphoRepay`
4. `morphoWithdrawCollateralOnBehalf`
5. deposit path
6. `morphoSupplyCollateral`
7. `morphoBorrowOnBehalf`
8. redeem path
9. `adapterSweep`

The top-level call sequence is either:

- callback bundle directly + `adapterSweep`, or
- `morphoFlashLoan(callbackBundle)` + `adapterSweep`

When a flash loan is used, the callback hash is set to `keccak256(abi.encode(callbackCalls))`.

### Deposit path selection

Bundled deposit path selection is:

- `legacyDeposit = true` -> `NestAdapter.tellerPredicateDeposit`
- otherwise -> `NestAdapter.nestPredicateMint`

The bundled path does not currently encode `nestPredicateDeposit`, `nestDeposit`, or `nestMint`.

### Redeem path selection

Bundled redeem path selection is:

- `instantRedeem = true` -> `NestAdapter.nestInstantRedeem`
- `legacyRedemption = true` -> `NestAdapter.atomicSolverRedeemSolve`
- otherwise -> `NestAdapter.nestRequestAndRedeem`

### Modern request-and-redeem flow

The current modern async redeem path is:

1. `requestRedeem(shares, controller, owner)`
2. `fulfillRedeem(controller, shares)`
3. `withdraw(assets, receiver, controller)`

It does not call `redeem(shares, receiver, controller)` in the bundled implementation.

## NestAdapter Behavior

### Predicate-gated deposit paths

`nestPredicateDeposit` and `nestPredicateMint` require all of:

- non-zero receiver
- `initiator()` authorized to call the relevant predicate-proxy selector
- `predicateProxy.genericUserCheckPredicate(initiator(), predicateMessage) == true`
- predicate proxy authorized on the vault for the corresponding selector

They approve the vault temporarily, execute the vault call, reset approval to zero, and enforce the `maxSharePriceE27` guard at execution time.

### Direct vault deposit paths

`nestDeposit` and `nestMint` skip predicate validation and instead require direct vault authority for `initiator()` on `deposit` / `mint`.

### Instant redeem

`nestInstantRedeem` requires:

- non-zero shares and receiver
- `owner` is the adapter, the current initiator, or a vault operator relationship exists
- `initiator()` has vault authority for `instantRedeem`

If `shares == type(uint256).max`, it uses:

```solidity
min(vault.balanceOf(owner), vault.getInstantRedeemLiquidity())
```

If `owner == address(this)`, the adapter temporarily approves vault shares to the vault around the call.

### Request-and-redeem

`nestRequestAndRedeem` requires:

- non-zero receiver
- `owner` is the adapter, the current initiator, or an authorized operator relationship exists
- `initiator()` has vault authority for `fulfillRedeem`

It then:

1. resolves `shares`
2. approves shares to the vault
3. calls `requestRedeem`
4. clears the share approval
5. calls `fulfillRedeem`
6. calls `withdraw(assets, receiver, controller)`

### AtomicQueue solve path

`atomicSolverRedeemSolve` re-reads the AtomicQueue metadata and requires:

- exactly one row
- matching `user`
- `flags == 0`
- non-zero `assetsToOffer`
- non-zero `assetsForWant`

It approves the solver temporarily, measures the user loan-token balance delta after solve, and then transfers the redeemed loan tokens from the user to the requested receiver.

### Morpho on-behalf operations

`morphoBorrowOnBehalf` and `morphoWithdrawCollateralOnBehalf` require Morpho authorization whenever `onBehalf != initiator()`.

`morphoRepay` supports full-debt repayment by encoding `shares = type(uint256).max`. In bundled full-exit target flows, calldata uses that mode only when `target.loan == 0` and the bundle is actually withdrawing collateral.

### Sweep behavior

`adapterSweep` only transfers the Morpho market loan token and collateral token. It is not a generic token rescue function.

## NestUnlooper

### Stored request

```solidity
struct UnloopRequest {
    uint256 minSharePriceE27;
    uint64 deadline;
    uint32 leverageBps;
}
```

Requests are keyed by `user` and `marketId`.

### Modern route

`updateUnloopRequest(...)` requires:

- `deadline >= block.timestamp`
- user currently has Morpho collateral
- position is not underwater
- `leverageBps < currentLeverageBps`

When building or executing the modern route, `NestUnlooper`:

- reloads the stored request
- rechecks expiry
- rechecks that the position is still above water
- rechecks that target leverage is still below current leverage
- derives the target position by preserving current equity
- builds an async bundle with `ctx.initiator = address(this)` and `ctx.controller = user`

After successful `execute(..., useAtomicQueue = false)`, the stored request is deleted.

### Legacy AtomicQueue route

The legacy route derives the async intent from live `AtomicQueue.viewSolveMetaData(...)`.

Current validation is:

- exactly one metadata row
- only flag `4` (`insufficient balance`) may be tolerated at build time
- all other flags cause `InvalidAtomicQueueRequest`
- `assetsToOffer` and `assetsForWant` must both be non-zero

Derived behavior:

- `intent.mode = Delta`
- `intent.minSharePriceE27 = ceil(assetsForWant * 1e27 / assetsToOffer)`
- `ma.repay = min(currentBorrow, assetsForWant)`
- `ma.withdrawCollateral = assetsToOffer`
- `va.redeem = ma.withdrawCollateral`

This path intentionally skips post-withdraw LLTV validation because the queue solve is expected to net-reduce the position.

## Approvals and Authorization

### Morpho authorization

One-time Morpho auth depends on the execution method:

| Method | Required authorization |
|---|---|
| direct `Bundler3.multicall` | user authorizes `NestAdapter` |
| async via `NestUnlooper` | user authorizes `NestAdapter` and `NestUnlooper` |
| `owner != initiator` direct execution | user authorizes `NestAdapter` and the external initiator |

### Vault operator setup

Vault operator setup is needed for bundled modern async redemption because the final step withdraws against the controller/owner balance:

- `requestAndRedeem` path: `vault.setOperator(NEST_ADAPTER, true)`
- bundled `instantRedeem`: not required in the standard path because the shares are redeemed from adapter balance
- legacy AtomicQueue redemption: not required

### ERC20 approvals

For direct adapter execution through Bundler3, the required ERC20 approvals are:

- loan token -> `NestAdapter` for `va.pullAssets`
- share token -> `NestAdapter` for `va.pullShares`
- legacy redemption extra loan-token allowance sized from bundle-derived solver limits

The async unlooper path does not pull owner wallet balances and therefore does not require per-execution ERC20 approvals from the user.

## Key Design Notes

1. Slippage checks are enforced at execution time, not only at build time.
2. Fee-aware redeem sizing is part of bundle derivation, not an execution-time afterthought.
3. The builder preserves owner inventory first, then uses vault minting only for the remaining collateral deficit.
4. Non-instant redeem bundles support sync / async splitting at the bundle level.
5. `NestUnlooper` is strictly deleveraging-only: it stores target leverage below the current leverage and never builds a releveraging async request.
