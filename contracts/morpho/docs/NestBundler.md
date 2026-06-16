# Nest Bundler -- Integrator Guide

The Nest Bundler system lets users atomically build, modify, and unwind leveraged positions on Morpho markets using Nest vault shares as collateral. A user only needs to know their **current position** and express their **target leverage** -- the bundler derives every intermediate action (borrow, repay, mint, redeem, supply, withdraw) and packages them into a single multicall.

The key insight: the Morpho market's **collateral token is the Nest vault's share token** (e.g. `nALPHA`). This is what makes the leverage loop possible -- depositing loan assets into the vault mints shares that serve as collateral for further borrowing.

## Architecture

```mermaid
graph TD
    User["User / Frontend"]
    NB["NestBundler<br/>(view + execute helper)"]
    NU["NestUnlooper<br/>(keeper-driven async)"]
    B3["Bundler3<br/>(multicall executor)"]
    NA["NestAdapter<br/>(Morpho + Vault adapter)"]
    M["Morpho<br/>(lending market)"]
    V["NestVault<br/>(ERC-4626 / ERC-7540)"]

    User -->|"1. getBundle / getBundleCalls"| NB
    User -->|"2. multicall(calls)"| B3
    User -->|"updateUnloopRequest"| NU
    Keeper -->|"execute"| NU
    NU -->|"multicall"| B3
    B3 -->|"dispatches"| NA
    NA -->|"borrow / repay / supply / withdraw"| M
    NA -->|"deposit / mint / redeem"| V
```

### Components

| Component | Role |
|-----------|------|
| **NestBundler** | User-facing view helper. Builds bundles from user intent and returns `Call[]` arrays ready for Bundler3. Can also execute directly via `getBundleAndExecute()`. |
| **NestUnlooper** | Keeper-only contract for async deleverage. Stores user unloop requests and executes them when called by an authorized keeper. |
| **Bundler3** | Morpho's generic multicall executor. Routes each `Call` to the target adapter. |
| **NestAdapter** | Bundler3 adapter implementing both Morpho market operations and Nest vault operations. |
| **Morpho** | Core lending market. Holds user positions (borrow + collateral). |
| **NestVault** | ERC-4626/ERC-7540 vault. Accepts loan token deposits, issues share tokens used as Morpho collateral. |

### API Layers

`NestBundler` exposes three layers:

1. **Bundle inspection:** `getBundle(...)`, `getSyncBundle(...)`, `getAsyncBundle(...)`
2. **Direct Bundler3 calldata:** `getBundleCalls(...)`, `getSyncBundleCalls(bundle)`, `getAsyncBundleCalls(bundle)`
3. **Wrapped execution:** `getBundleAndExecute(...)`

---

## Key Concepts

### Leverage

Leverage is expressed in **basis points** where `10,000 = 1x` (no leverage):

```
collateralValue = collateral * oraclePrice / ORACLE_PRICE_SCALE
equity          = collateralValue - loan
leverageBps     = collateralValue * 10,000 / equity
```

| leverageBps | Meaning |
|-------------|---------|
| `0` | Full exit (close Morpho position entirely) |
| `10,000` | 1x -- no debt, collateral = equity |
| `20,000` | 2x -- debt equals equity |
| `30,000` | 3x -- debt is 2x equity |

### Equity Preservation

When changing leverage, **equity is preserved**. The system computes new target loan and collateral amounts from the user's current equity and desired leverage:

```
targetCollateralValue = equity * targetLeverageBps / 10,000
targetCollateral      = targetCollateralValue * ORACLE_PRICE_SCALE / oraclePrice
targetLoan            = actualCollateralValue - equity
```

### Intent Modes

Users express intent in one of two modes:

| Mode | Use case | What you specify |
|------|----------|-----------------|
| **Target** | "I want to be at 2x leverage" | Absolute `Position{loan, collateral}` |
| **Delta** | "Borrow 100 more, supply 50 more collateral" | Incremental `MarketActions{borrow, repay, supplyCollateral, withdrawCollateral}` |

For most users, **Target mode** is the right choice. You specify your desired leverage and the system derives everything else.

> **Note:** `assetAllowance` and `shareAllowance` in `UserIntent` are **bundle-build caps**, not ERC20 approvals. They limit how much the bundler is allowed to derive as `pullAssets` / `pullShares` from the owner.

### Share Price Guards (Slippage Protection)

All prices are scaled by **1e27** (E27 fixed-point):

| Guard | Protects against |
|-------|-----------------|
| `minSharePriceE27` | Vault exit at too low a share price (redeem path) |
| `maxSharePriceE27` | Vault entry at too high a share price (deposit/mint path) |
| `maxRepaySharePriceE27` | Morpho repay at too high an interest-accrued share price |

---

## Flow 1: Sync Path (User Executes Directly)

This is the primary flow. The user builds a bundle, approves tokens, and executes through Bundler3.

### Setup: Owner is the executor

```mermaid
sequenceDiagram
    autonumber
    actor OwnerInitiator as Owner (= Initiator)
    participant NB as NestBundler
    participant A as NestAdapter
    participant M as Morpho
    participant V as NestVault
    participant Loan as LoanToken
    participant Coll as CollateralToken
    participant B3 as Bundler3

    rect rgb(236,247,255)
        Note over OwnerInitiator,A: Owner/initiator setup
        OwnerInitiator->>M: setAuthorization(A, true)
        opt route is requestAndRedeem
            OwnerInitiator->>V: setOperator(A, true)
        end
    end

    rect rgb(255,250,236)
        OwnerInitiator->>NB: getBundleCalls(intent, route, predicateMessage, vault, teller, owner, initiator=owner)
        NB-->>OwnerInitiator: calls[] + approvalTxs[]
    end

    rect rgb(240,255,240)
        opt approvalTxs contains loan approval
            OwnerInitiator->>Loan: approve(A, amount)
        end
        opt approvalTxs contains collateral approval
            OwnerInitiator->>Coll: approve(A, amount)
        end
        OwnerInitiator->>B3: multicall(calls)
    end
```

### Setup: Owner delegates to a different executor

```mermaid
sequenceDiagram
    autonumber
    actor Owner
    actor Initiator
    participant NB as NestBundler
    participant A as NestAdapter
    participant M as Morpho
    participant V as NestVault
    participant Loan as LoanToken
    participant Coll as CollateralToken
    participant B3 as Bundler3

    Note over Owner,Initiator: owner != initiator only works when the bundle does not pull owner balances, or when you are executing the async half of a split redeem flow.

    rect rgb(236,247,255)
        Note over Owner,A: Owner setup
        Owner->>M: setAuthorization(A, true)
        Owner->>M: setAuthorization(initiator, true)
        opt route is requestAndRedeem
            Owner->>V: setOperator(A, true)
        end
    end

    rect rgb(255,239,239)
        Note over Initiator,V: Initiator / controller setup
        Note over Initiator,V: The executor still needs whatever vault / solver capability gates the redeem selector(s).
    end

    rect rgb(255,250,236)
        Owner->>NB: getBundleCalls(intent, route, predicateMessage, vault, teller, owner, initiator)
        NB-->>Owner: calls[] + approvalTxs[]
    end

    rect rgb(240,255,240)
        opt approvalTxs contains owner-signed legacy loan approval
            Note over Owner,Loan: Legacy extra transfer is transferFrom(owner,...), so owner signs this approval.
            Owner->>Loan: approve(A, legacyRedeemTransferAllowance)
        end
        opt approvalTxs contains initiator-owned token approvals
            Initiator->>Loan: approve(A, amount)
            Initiator->>Coll: approve(A, amount)
        end
        Initiator->>B3: multicall(calls)
    end
```

### Detailed flow: Deposit / Leverage up

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant NB as NestBundler
    participant Build as BundleBuildLib
    participant B3 as Bundler3
    participant A as NestAdapter
    participant M as Morpho
    participant V as NestVault
    participant T as Teller
    participant Loan as LoanToken (pUSD)
    participant Coll as CollateralToken (NestShare)

    Note over User,NB: Assumes setup in SetupOwnerIsInitiator is already done.

    User->>NB: getBundleCalls(intent, deposit route, predicateMessage, vault, teller, owner=user, initiator=user)
    NB->>Build: getBundle(ctx, intent, route)
    Build-->>NB: Bundle(ma, va)
    NB-->>User: calls[] + approvalTxs[]

    opt approvalTxs contains loan approval
        User->>Loan: approve(A, loanApprovalAmount)
    end
    opt approvalTxs contains collateral approval
        User->>Coll: approve(A, collateralApprovalAmount)
    end

    User->>B3: multicall(calls)

    alt flashLoanAssets > 0
        B3->>A: morphoFlashLoan(pUSD, flashLoanAssets, callbackCalls)
        A->>M: flashLoan(pUSD, flashLoanAssets, data)
        M-->>A: onMorphoFlashLoan(data)
        A->>B3: reenter(callbackCalls)
    else flashLoanAssets == 0
        Note over B3: Execute callback calls directly
    end

    opt va.pullAssets > 0
        B3->>A: erc20TransferFrom(pUSD, A, pullAssets)
        A->>Loan: transferFrom(initiator, A, pullAssets)
    end
    opt va.pullShares > 0
        B3->>A: erc20TransferFrom(NestShare, A, pullShares)
        A->>Coll: transferFrom(initiator, A, pullShares)
    end

    opt va.deposit > 0
        alt route.legacyDeposit == true
            B3->>A: tellerPredicateDeposit(...)
            A->>Loan: approve(T.vault(), assets)
            A->>T: deposit(depositAsset, assets, minMint)
            T-->>Coll: mint shares to A
        else route.legacyDeposit == false
            B3->>A: nestPredicateMint(vault, shares, ..., receiver=A)
            A->>Loan: approve(V, assets)
            A->>V: mint(shares, receiver=A)
            V-->>Coll: mint shares to A
        end
    end

    opt ma.supplyCollateral > 0
        B3->>A: morphoSupplyCollateral(market, supplyCollateral, onBehalf=user)
        A->>Coll: approve(M, supplyCollateral)
        A->>M: supplyCollateral(...)
        M->>Coll: transferFrom(A, M, supplyCollateral)
    end

    opt ma.borrow > 0
        B3->>A: morphoBorrowOnBehalf(market, borrow, onBehalf=user, receiver=A)
        A->>M: borrow(...)
        M-->>Loan: transfer(borrow, A)
    end

    opt flashLoanAssets > 0
        M->>Loan: transferFrom(A, M, flashLoan + fee)
    end

    B3->>A: adapterSweep(market, receiver=user)
```

### Detailed flow: Instant Redeem

```mermaid
sequenceDiagram
    autonumber
    actor Owner
    actor Executor as Owner or Solver
    participant NB as NestBundler
    participant Build as BundleBuildLib
    participant B3 as Bundler3
    participant A as NestAdapter
    participant M as Morpho
    participant V as NestVault
    participant Loan as LoanToken (pUSD)
    participant Coll as CollateralToken (NestShare)

    Note over Owner,NB: Instant redeem is sync-only. Build the bundle with the real executor as initiator.
    Note over Owner,Executor: If executor != owner, owner must authorize executor on Morpho. The executor must have vault authority for instantRedeem, but the standard bundled instantRedeem path does not require user->adapter operator setup because the shares are redeemed from the adapter balance.

    Owner->>NB: getBundleCalls(intent, route.instantRedeem=true, predicateMessage, vault, teller, owner=owner, initiator=executor)
    NB->>Build: getBundle(ctx, intent, route)
    Build->>V: getInstantRedeemLiquidity()
    Build-->>NB: Bundle(ma.repay, ma.withdrawCollateral, va.redeem)
    NB-->>Owner: calls[] + approvalTxs[]

    opt approvalTxs contains ERC20 approvals
        Note over Owner,Executor: These only exist when the bundle pulls owner balances, which requires owner == executor.
        Executor->>Loan: approve(A, loanApprovalAmount)
        Executor->>Coll: approve(A, collateralApprovalAmount)
    end

    Executor->>B3: multicall(calls)

    alt flashLoanAssets > 0
        B3->>A: morphoFlashLoan(pUSD, flashLoanAssets, callbackCalls)
        A->>M: flashLoan(pUSD, flashLoanAssets, data)
        M-->>A: onMorphoFlashLoan(data)
        A->>B3: reenter(callbackCalls)
    else flashLoanAssets == 0
        Note over B3: Execute callback calls directly
    end

    B3->>A: morphoRepay(market, ma.repay, onBehalf=owner)
    A->>M: repay(...)

    B3->>A: morphoWithdrawCollateralOnBehalf(market, ma.withdrawCollateral, owner, receiver=A)
    A->>M: withdrawCollateral(...)
    M-->>Coll: transfer(withdrawCollateral, A)

    B3->>A: nestInstantRedeem(vault, va.redeem, minSharePrice, receiver=A, owner=A)
    A->>V: instantRedeem(va.redeem, receiver=A, owner=A)
    V-->>Loan: transfer(postFeeAssets, A)

    opt flashLoanAssets > 0
        M->>Loan: transferFrom(A, M, flashLoan + fee)
    end

    B3->>A: adapterSweep(market, receiver=owner)
    A-->>Owner: transfer residual loan/collateral
```

### Detailed flow: Redemption (all routes)

```mermaid
sequenceDiagram
    autonumber
    actor Owner as PositionOwner / AtomicQueueUser
    actor Executor as Owner or Solver
    participant Q as AtomicQueue
    participant S as AtomicSolverV3
    participant T as Teller
    participant NB as NestBundler
    participant Build as BundleBuildLib
    participant B3 as Bundler3
    participant A as NestAdapter
    participant M as Morpho
    participant V as NestVault
    participant Loan as LoanToken (pUSD)
    participant Coll as CollateralToken (NestShare)

    Note over Owner,NB: Assumes the route-specific setup is already done.
    Note over Owner,Executor: instantRedeem is sync-only. requestAndRedeem / legacyRedemption can also be split into sync + async bundle phases.

    Owner->>NB: getBundleCalls(intent, redeem route, predicateMessage, vault, teller, owner=owner, initiator=executor)
    NB->>Build: getBundle(ctx, intent, route)
    Build-->>NB: Bundle(ma.repay, ma.withdrawCollateral, va.redeem)
    NB-->>Owner: calls[] + approvalTxs[]

    alt route.legacyRedemption == false
        opt approvalTxs contains approvals
            Owner->>Loan: approve(A, amount)
            Owner->>Coll: approve(A, amount)
        end
        Executor->>B3: multicall(calls)
    else route.legacyRedemption == true
        Note over Owner,Q: Owner queues AtomicRequest with same account used as Morpho owner.
        Owner->>Coll: approve(Q, offerAmount)
        Owner->>Q: updateAtomicRequest(offer=NestShare, want=pUSD, price, amount, deadline)
        opt approvalTxs contains owner loan approval
            Owner->>Loan: approve(A, legacyRedeemTransferAllowance)
        end
        Executor->>B3: multicall(calls)
    end

    alt flashLoanAssets > 0
        B3->>A: morphoFlashLoan(pUSD, flashLoanAssets, callbackCalls)
        A->>M: flashLoan(pUSD, flashLoanAssets, data)
        M-->>A: onMorphoFlashLoan(data)
        A->>B3: reenter(callbackCalls)
    else flashLoanAssets == 0
        Note over B3: Execute callback calls directly
    end

    B3->>A: morphoRepay(market, ma.repay, onBehalf=owner)
    A->>M: repay(...)

    alt route.legacyRedemption == true
        B3->>A: morphoWithdrawCollateralOnBehalf(market, ma.withdrawCollateral, owner, receiver=owner)
        A->>M: withdrawCollateral(...)
        M-->>Coll: transfer(withdrawCollateral, owner)
    else route.legacyRedemption == false
        B3->>A: morphoWithdrawCollateralOnBehalf(market, ma.withdrawCollateral, owner, receiver=A)
        A->>M: withdrawCollateral(...)
        M-->>Coll: transfer(withdrawCollateral, A)
    end

    alt route.legacyRedemption == false
        alt route.instantRedeem == true
            B3->>A: nestInstantRedeem(vault, va.redeem, receiver=A, owner=A)
            A->>V: instantRedeem(va.redeem, receiver=A, owner=A)
            V-->>Loan: transfer(redeemedAssets, A)
        else route.instantRedeem == false
            B3->>A: nestRequestAndRedeem(vault, va.redeem, receiver=A, controller=owner, owner=A)
            A->>Coll: approve(V, va.redeem)
            A->>V: requestRedeem(va.redeem, controller=owner, owner=A)
            A->>V: fulfillRedeem(controller=owner, va.redeem)
            A->>V: redeem(va.redeem, receiver=A, controller=owner)
            V-->>Loan: transfer(redeemedAssets, A)
        end
    else route.legacyRedemption == true
        B3->>A: atomicSolverRedeemSolve(S, Q, T, market, owner, receiver=A, assets=va.redeem, minAssets=ma.withdrawCollateral)
        A->>Q: viewSolveMetaData(NestShare, pUSD, [owner])
        A->>S: redeemSolve(Q, offer=NestShare, want=pUSD, users=[owner], minAssets, assets)
        S->>Q: solve(...)
        Q->>Coll: transferFrom(owner, S, offerAmount)
        Q-->>S: finishSolve(...)
        S->>T: bulkWithdraw(pUSD, offerReceived, minimumAssetsOut, receiver=A)
        T->>V: redeem offer shares to vault assets
        V-->>Loan: transfer(assetsOut, A)
        S->>Loan: transferFrom(A, S, wantApprovalAmount)
        Q->>Loan: transferFrom(S, owner, assetsForWant)
        A->>Loan: transferFrom(owner, A, receivedAssets)
    end

    opt flashLoanAssets > 0
        M->>Loan: transferFrom(A, M, flashLoan + fee)
    end

    B3->>A: adapterSweep(market, receiver=owner)
```

### Detailed flow: Legacy Redeem (AtomicQueue)

```mermaid
sequenceDiagram
    autonumber
    actor Owner as Morpho Position Owner / AtomicQueue User
    actor Solver as Authorized Solver
    participant NB as NestBundler
    participant B3 as Bundler3
    participant A as NestAdapter
    participant M as Morpho
    participant S as AtomicSolverV3
    participant Q as AtomicQueue
    participant T as Teller
    participant V as NestVault
    participant Loan as LoanToken (pUSD)
    participant Coll as CollateralToken (NestShare)

    Note over Owner,NB: Legacy redemption path only (route.legacyRedemption=true).
    Note over Owner,Solver: The executor must be allowed to call AtomicSolverV3.redeemSolve. The atomic solver must be allowed to call teller bulkWithdraw.

    Owner->>NB: getBundleCalls(intent, route.legacyRedemption=true, predicateMessage, vault, teller, owner=owner, initiator=solver)
    NB-->>Owner: calls[] + approvalTxs[]

    Owner->>Coll: approve(Q, offerAmount)
    Owner->>Q: updateAtomicRequest(offer=NestShare, want=pUSD, atomicPrice, offerAmount, deadline)
    opt approvalTxs contains owner loan approval
        Owner->>Loan: approve(A, legacyRedeemTransferAllowance)
    end

    Note over A,S: Protocol setup: Adapter must have allowance set for the AtomicSolver on the loan token.

    Solver->>B3: multicall(calls)

    B3->>A: morphoFlashLoan(loanToken, flashLoanAssets, callbackData)
    A->>M: flashLoan(loanToken, flashLoanAssets, data)
    M-->>A: onMorphoFlashLoan(data)
    A->>B3: reenter(callbackBundle)

    B3->>A: morphoRepay(... onBehalf=owner, assets=repayAssets)
    A->>M: repay(...)

    B3->>A: morphoWithdrawCollateralOnBehalf(... onBehalf=owner, receiver=owner)
    A->>M: withdrawCollateral(...)
    M-->>Coll: transfer(withdrawCollateral, owner)

    B3->>A: atomicSolverRedeemSolve(S, Q, T, market, owner, receiver=A, assets, minAssets)
    A->>Q: viewSolveMetaData(offer, want, [owner])
    A->>S: redeemSolve(Q, offer, want, users=[owner], minAssets, assets, teller)

    S->>Q: solve(offer, want, users=[owner], runData, solver=this)
    Q->>Coll: transferFrom(owner, S, offerAmount)
    Q-->>S: finishSolve(...)
    S->>T: bulkWithdraw(want, offerReceived, minimumAssetsOut, receiver=A)
    T->>V: redeem offer shares

    S->>Loan: transferFrom(A, S, wantApprovalAmount)
    Q->>Loan: transferFrom(S, owner, wantAmount)
    A->>Loan: transferFrom(owner, A, receivedAssets)

    M->>Loan: transferFrom(A, M, flash-loan repayment)
    B3->>A: adapterSweep(market, receiver=owner)
```

### Step-by-step

1. **Build the intent.** Determine your target leverage and use `MorphoMarketLib.getTargetPosition()` to derive a `Position{loan, collateral}`. Construct a `UserIntent` with mode `Target`.

2. **Choose a route.** Set `RouteInput` flags:
   - `instantRedeem = true` -- single-tx redemption, requires vault liquidity
   - `legacyDeposit = true` -- use teller deposit path (required for current deployments, see [Deployment Constraints](#current-deployment-constraints))
   - `legacyRedemption = true` -- use AtomicQueue redemption (legacy vaults only)
   - All `false` -- uses ERC-7540 `requestAndRedeem` (default for new vaults)

3. **Get bundle calls.**
   ```solidity
   (Call[] memory bundleCalls, Call[] memory approveCalls) =
       nestBundler.getBundleCalls(intent, route, predicateMessage, vault, teller, owner, owner);
   ```

4. **Execute approval transactions.** Each `approveCalls[i]` is an ERC20 `approve` call. Execute them from the user's wallet.

5. **Execute the bundle.** Call `Bundler3.multicall(bundleCalls)` from the user's wallet.

### Alternative: `getBundleAndExecute()`

Users can call `NestBundler.getBundleAndExecute()` directly. This pulls tokens from the user, builds and executes the bundle internally, and sweeps leftovers back.

**Important:** When using this method, the Bundler3 `initiator()` is the **NestBundler contract** (not the user). This affects which address needs Morpho authorization and which vault / predicate authority checks key off `initiator()` (see [Authorizations](#authorizations--approvals)).

### Sync + Async split

When a bundle requires redemption that isn't instant (`route.instantRedeem = false` and `va.redeem > 0`), the bundle splits into two phases:

- **Sync phase** (`getSyncBundle` / `getSyncBundleCalls`): owner-funded actions that execute immediately (deposits, supply collateral, borrow, owner-funded repay).
- **Async phase** (`getAsyncBundle` / `getAsyncBundleCalls`): redeem-dependent actions for later execution by a solver/keeper.

Check `isSyncRedeem(bundle)` -- returns `true` when the entire bundle is sync-executable.

---

## Flow 2: Async Path (Keeper Executes via NestUnlooper)

For deleveraging when instant redemption is not available. The user registers intent, and an authorized keeper executes the unwind.

### Path A: Modern Unlooper (ERC-7540) -- Recommended

```mermaid
sequenceDiagram
    autonumber
    actor User as Position Owner
    actor Keeper as Authorized Keeper
    participant NU as NestUnlooper
    participant B3 as Bundler3
    participant A as NestAdapter
    participant M as Morpho
    participant V as NestVault
    participant Loan as LoanToken (pUSD)
    participant Coll as CollateralToken (NestShare)

    Note over User,NU: One-time setup: Owner must have called morpho.setAuthorization(NestAdapter, true) AND morpho.setAuthorization(NestUnlooper, true)

    User->>NU: updateUnloopRequest(market, leverageBps, minSharePriceE27, deadline)
    Note over NU: Request stored on-chain (keyed by user + marketId)

    Note over Keeper,NU: Keeper monitors UnloopRequestUpdated events

    Keeper->>NU: execute(market, vault, teller, user, useAtomicQueue=false)
    NU->>NU: Read stored request + current Morpho position
    NU->>NU: Derive target position (equity preserved, new leverage)
    NU->>NU: Build async bundle (repay, withdrawCollateral, redeem)

    NU->>B3: multicall(bundleCalls)

    alt flashLoanAssets > 0
        B3->>A: morphoFlashLoan(pUSD, flashLoanAssets, callbackCalls)
        A->>M: flashLoan(pUSD, flashLoanAssets, data)
        M-->>A: onMorphoFlashLoan(data)
        A->>B3: reenter(callbackCalls)
    else flashLoanAssets == 0
        Note over B3: Execute callback calls directly
    end

    B3->>A: morphoRepay(market, repayAmount, onBehalf=user)
    A->>M: repay(...)

    B3->>A: morphoWithdrawCollateralOnBehalf(market, withdrawAmount, user, receiver=A)
    A->>M: withdrawCollateral(...)
    M-->>Coll: transfer(withdrawAmount, A)

    B3->>A: nestRequestAndRedeem(vault, redeemShares, minSharePrice, receiver=A, controller=user, owner=A)
    A->>Coll: approve(V, redeemShares)
    A->>V: requestRedeem(redeemShares, controller=user, owner=A)
    A->>V: fulfillRedeem(controller=user, redeemShares)
    A->>V: redeem(redeemShares, receiver=A, controller=user)
    V-->>Loan: transfer(redeemedAssets, A)

    opt flashLoanAssets > 0
        M->>Loan: transferFrom(A, M, flashLoan + fee)
    end

    B3->>A: adapterSweep(market, receiver=user)
    A-->>User: transfer residual loan/collateral

    NU->>NU: Delete stored request
    NU-->>Keeper: Executed(user, marketId, repay, withdrawCollateral, redeem)
```

#### User steps

1. **Register intent:**
   ```solidity
   nestUnlooper.updateUnloopRequest(
       marketParams,       // Morpho market
       leverageBps,        // Target leverage (10,000 = 1x, 0 = full exit)
       minSharePriceE27,   // Slippage protection on vault exit
       deadline            // Unix timestamp expiration
   );
   ```

2. **Wait for keeper execution.** The keeper monitors for pending requests and calls `execute()`.

3. **Verify.** After execution, your Morpho position reflects the target leverage. The stored request is automatically deleted.

#### Constraints
- `leverageBps` must be **below** your current leverage (you can only deleverage via the unlooper)
- Position must not be underwater (`equity > 0`)
- `deadline` must be in the future

#### Managing requests
- **Update:** Call `updateUnloopRequest()` again to modify parameters
- **Cancel:** Call `clearUnloopRequest(marketParams)` to remove a pending request
- **Read:** Call `getUnloopRequest(user, marketParams)` to view a stored request

### Path B: Legacy AtomicQueue (Deprecated)

#### User steps

1. **Get the amounts to queue** by building the bundle and inspecting:
   - `bundle.ma.withdrawCollateral` → use as `offerAmount` (shares to offer)
   - The adapter approval amount must cover the **redeemed asset value** of the withdrawn collateral, not just `ma.repay`. Use `BundleCalldataLib.legacyRedeemRequestAmounts(bundle)` to get the correct `maxAssets` upper bound, or call `getBundleCalls()` and use the returned `approveCalls[]` directly.

2. **Queue redemption:**
   ```solidity
   (uint256 legacyRedeemMaxAssets,) = BundleCalldataLib.legacyRedeemRequestAmounts(bundle);
   uint256 adapterApproval = bundle.va.pullAssets + legacyRedeemMaxAssets;

   nTOKEN.approve(atomicQueue, offerAmount);
   atomicQueue.updateAtomicRequest(
       nTOKEN,           // offer token (vault shares)
       pUSD,             // want token (loan token)
       AtomicRequest({
           deadline: deadline,
           atomicPrice: atomicPrice,  // min price per share
           offerAmount: offerAmount,
           inSolve: false
       })
   );
   pUSD.approve(address(nestAdapter), adapterApproval);
   ```

3. **Wait for keeper** to call `NestUnlooper.execute(..., useAtomicQueue=true)`.

---

## Authorizations & Approvals

### One-time: Morpho Authorization

The user must authorize the appropriate contract to act on their Morpho position. This allows `borrow`, `repay`, `supplyCollateral`, and `withdrawCollateral` **on behalf of** the user.

| Execution method | Who to authorize | Call |
|-----------------|-----------------|------|
| `getBundleCalls()` + direct Bundler3 | **NestAdapter** | `morpho.setAuthorization(NEST_ADAPTER, true)` |
| `getBundleAndExecute()` | **NestAdapter** + **NestBundler** | `morpho.setAuthorization(NEST_ADAPTER, true)` + `morpho.setAuthorization(NEST_BUNDLER, true)` |
| Async (NestUnlooper) | **NestAdapter** + **NestUnlooper** | `morpho.setAuthorization(NEST_ADAPTER, true)` + `morpho.setAuthorization(NEST_UNLOOPER, true)` |
| Owner != Initiator | **NestAdapter** + **Initiator** | `morpho.setAuthorization(NEST_ADAPTER, true)` + `morpho.setAuthorization(initiator, true)` |

> Only needs to be done once per user per Morpho deployment.

### One-time: Vault Operator Setup

For bundled redeem paths, vault-operator setup is only needed when the final vault redeem runs against the user's controller balance.

| Redeem route | Required calls |
|-------------|----------------|
| `instantRedeem` | Not required in the standard bundled path (`owner = NEST_ADAPTER`) |
| `requestAndRedeem` | `vault.setOperator(NEST_ADAPTER, true)` |
| Owner != Initiator + `instantRedeem` | Not required solely for bundled instant redeem; executor still needs vault Authority for `instantRedeem` |
| Owner != Initiator + `requestAndRedeem` | `vault.setOperator(NEST_ADAPTER, true)` |
| `legacyRedemption` | Not required (AtomicQueue handles transfers) |

> Only needs to be done once per user per vault.

### Per-transaction: Token Approvals (Sync Path)

`getBundleCalls()` returns `approveCalls[]` encoding the exact approvals needed. Here is what they contain:

| Token | Spender | Amount | When needed |
|-------|---------|--------|-------------|
| Loan token (e.g. pUSD) | NestAdapter | `va.pullAssets` | User provides loan tokens (for deposit or direct repay) |
| Share token (e.g. nALPHA) | NestAdapter | `va.pullShares` | User provides existing shares (for collateral supply) |
| Loan token (e.g. pUSD) | NestAdapter | `+ legacyRedeemMaxAssets` | Additional allowance when `legacyRedemption = true` (added to `pullAssets`) |

When using `getBundleAndExecute()`, the user approves the **NestBundler** (not the adapter) for `pullAssets` and `pullShares`. The bundler handles adapter approvals internally.

> **Note:** `approveCalls` only contain ERC20 `approve(...)` payloads. They do NOT include Morpho authorization, vault operator setup, or role grants. Those are separate one-time setup steps.

### Modern Async Path (NestUnlooper): No User Token Approvals Needed

For the modern async path via NestUnlooper, the user does **not** need to approve any tokens. The keeper execution operates on the user's Morpho position directly (via the one-time Morpho authorization). Vault shares are withdrawn from Morpho collateral, not from the user's wallet.

> **Legacy exception:** The legacy AtomicQueue async path **does** require user token approvals — both `nTOKEN.approve(atomicQueue, offerAmount)` and `pUSD.approve(nestAdapter, adapterApproval)`. See [Path B: Legacy AtomicQueue](#path-b-legacy-atomicqueue-deprecated) for details.

### Vault-side Authorization (Protocol-level)

These are configured by the protocol team, not by users:

| Authorization | Purpose |
|--------------|---------|
| Predicate proxy authorized on vault for `deposit` / `mint` | Required for predicate-protected deposit paths |
| Initiator authorized for `instantRedeem` via vault Authority | Required for instant redemption via the adapter |
| Initiator authorized for `fulfillRedeem` via vault Authority | Required for ERC-7540 request-and-redeem flow |
| NestUnlooper's `execute` gated by `requiresAuth` | Only authorized keepers can trigger async execution |
| Solver must have `CAN_SOLVE_ROLE` (role `11`) | Required for legacy AtomicSolver execution |
| Vault has `TELLER_ROLE` (role `3`) to enter/exit shares | Deployment wiring, not an end-user action |

---

## Callback Execution Order

Inside a bundle, actions execute in this fixed order (zero-amount steps are skipped):

| # | Action | Direction |
|---|--------|-----------|
| 1 | `pullLoanAssets` | User wallet -> Adapter |
| 2 | `pullCollateralShares` | User wallet -> Adapter |
| 3 | `morphoRepay` | Adapter -> Morpho |
| 4 | `morphoWithdrawCollateral` | Morpho -> Adapter/Owner |
| 5 | `nestDeposit` / `nestMint` | Adapter -> Vault |
| 6 | `morphoSupplyCollateral` | Adapter -> Morpho |
| 7 | `morphoBorrow` | Morpho -> Adapter |
| 8 | `nestRedeem` | Vault -> Adapter |

When the user's provided assets (`pullAssets`) are insufficient to cover `repay + deposit`, the entire callback sequence is **wrapped in a Morpho flash loan**. The flash loan provides the missing loan tokens upfront and is repaid from borrowed or redeemed proceeds.

A final `adapterSweep` always runs after the callbacks to return any leftover tokens to the user.

---

## Integration Checklist

### Sync (instant leverage adjustment)

1. Identify your Morpho `MarketParams` and corresponding `NestVault`.
   - Verify: `market.collateralToken == vault.share()`
2. **One-time Morpho auth:** `morpho.setAuthorization(NEST_ADAPTER, true)`
3. **One-time vault operator (only for `requestAndRedeem` flows):** `vault.setOperator(NEST_ADAPTER, true)`
4. Determine target leverage (in bps) and compute target position:
   ```solidity
   PositionMetrics memory target = market.getTargetPosition(morpho, user, targetLeverageBps);
   ```
5. Build `UserIntent` with `mode = Target`, `target = target.position`, and appropriate price guards.
6. Call `nestBundler.getBundleCalls(intent, route, predMsg, vault, teller, user, user)`.
7. Execute returned `approveCalls[]` from user wallet.
8. Execute `Bundler3.multicall(bundleCalls)` from user wallet.

### Async (keeper-driven deleverage)

1. **One-time Morpho auth:** `morpho.setAuthorization(NEST_ADAPTER, true)` + `morpho.setAuthorization(NEST_UNLOOPER, true)`
2. User calls `nestUnlooper.updateUnloopRequest(marketParams, leverageBps, minSharePriceE27, deadline)`.
3. Keeper monitors for events / reads `getUnloopRequest()`.
4. Keeper calls `nestUnlooper.execute(marketParams, vault, teller, user, false)`.

---

## Keeper Operation Guide

### Monitoring Unloop Requests

- Listen for `UnloopRequestUpdated(user, marketId, leverageBps, minSharePriceE27, deadline)` events on `NestUnlooper`.
- Read pending requests via `getUnloopRequest(user, marketParams)`. A `deadline == 0` means no active request.
- Listen for `UnloopRequestCleared(user, marketId)` for user cancellations.

### Executing Unloop Requests

```solidity
nestUnlooper.execute(marketParams, vault, teller, user, useAtomicQueue);
```

- `useAtomicQueue = false` for modern unloop (reads stored request)
- `useAtomicQueue = true` for legacy AtomicQueue route (reads queue state)
- The call reverts if:
  - Request has expired (`block.timestamp > deadline`)
  - Position is underwater
  - Target leverage is not below current leverage
  - Caller is not authorized (`requiresAuth`)

### Monitoring AtomicQueue (Legacy)

- Use `AtomicQueue.viewSolveMetaData(collateralToken, loanToken, [user])` to read pending legacy requests.
- Execute via `nestUnlooper.execute(marketParams, vault, teller, user, true)`.

---

## Current Deployment Constraints

- Regular users should assume only **synchronous public flows** are available today.
- No Morpho market currently has a `NestVault` with `pUSD` as the vault asset, so user looping should use **`route.legacyDeposit = true`**.
- Modern vault deposit path (`route.legacyDeposit = false`) is unavailable until the authority configuration transaction is executed. Do not use the modern bundle deposit path (`nestPredicateMint(...)` in generated bundles, or direct `nestDeposit(...)` / `nestMint(...)`) or `getBundleAndExecute(...)` for modern deposit flows until then.
- Async redemption execution is solver-gated (`CAN_SOLVE_ROLE`, role `11`).

---

## Deployments

| Contract | Address |
|----------|---------|
| NestBundler | [`0x4ae3c62c5b4ca6eaa5d67345293d5c27c19802b4`](https://explorer.plume.org/address/0x4ae3c62c5b4ca6eaa5d67345293d5c27c19802b4) |
| NestAdapter | [`0x3CFcF73783D1AC0A486D1Fb8B1d248821b1d6aA6`](https://explorer.plume.org/address/0x3cfcf73783d1ac0a486d1fb8b1d248821b1d6aa6) |

---

## Types Reference

### UserIntent

```solidity
struct UserIntent {
    MarketParams market;           // Morpho market to act on
    uint256 assetAllowance;        // Max loan assets pullable from owner (type(uint256).max = unlimited)
    uint256 shareAllowance;        // Max collateral shares pullable from owner
    uint256 maxSharePriceE27;      // Max share price for deposit/mint (slippage guard)
    uint256 minSharePriceE27;      // Min share price for redeem (slippage guard)
    uint256 maxRepaySharePriceE27; // Max share price for Morpho repay
    PositionMode mode;             // Target or Delta
    Position target;               // Absolute position (when mode = Target)
    MarketActions delta;           // Incremental changes (when mode = Delta)
}
```

### UnloopRequest

```solidity
struct UnloopRequest {
    uint256 minSharePriceE27; // Min vault exit share price (1e27 scale)
    uint64 deadline;          // Unix timestamp expiration
    uint32 leverageBps;       // Target leverage (10,000 = 1x, 0 = full exit)
}
```

### Position & PositionMetrics

```solidity
struct Position {
    uint256 loan;       // Loan assets (debt) in Morpho
    uint256 collateral; // Collateral shares in Morpho
}

struct PositionMetrics {
    Position position;
    uint256 equity;       // collateralValue - loan
    uint256 leverageBps;  // collateralValue * 10,000 / equity
}
```

### RouteInput

```solidity
struct RouteInput {
    bool legacyRedemption; // Use AtomicQueue/AtomicSolver for redemption
    bool legacyDeposit;    // Use teller-based deposit path
    bool instantRedeem;    // Use instant redeem (requires vault liquidity)
}
```
