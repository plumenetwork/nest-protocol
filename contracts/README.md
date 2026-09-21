# Deposit and Redeem Flow

[← Back to repository overview](../README.md)

This document describes the deposit and redemption lifecycle of a Nest vault. It covers the user flow, the operator procedures, and the contract mechanics. The audience is the operations team and integrators who run or debug these flows. For the public policy on redemption timing and availability, see the [liquidity and redemptions](https://app.plume.org/docs/about/liquidity-and-redemptions) page.

## Related documentation

Public documentation:

- [Liquidity and redemptions](https://app.plume.org/docs/about/liquidity-and-redemptions) — user-facing redemption policy.
- [Vault operations and valuation](https://app.plume.org/docs/about/vault-operations-and-valuation) — how the exchange rate is set.
- [Flow of funds](https://app.plume.org/docs/security-and-compliance/flow-of-funds) — where deposited assets go.
- [Smart contracts](https://app.plume.org/docs/developers/smart-contracts) — public contract addresses.

Repository documentation:

- [Compliance flow](compliance/README.md) — the compliance proxy and deposit gating.
- [Accountant fee spec](accountant/README.md) — accountant fees and the posted rate.
- [oVault cross-chain flow](integrations/ovault/README.md) — cross-chain deposits and redemptions through the composer.
- [Morpho integration](integrations/morpho/README.md) — the Morpho integration and the legacy redemption route.
- [Roles and authorities](auth/README.md) — complete role, holder, and capability reference.
- [Operators guide](operators/README.md) — setup procedures and emergency controls.
- [Deployment guide](../script/deploy/README.md) — deploy and upgrade procedures.
- [Upgrade contracts](upgrades/README.md) — current migration implementation and recovered deployed reinitializers.

## User flow

### Deposit

The following procedure uses the V1 proxy, `NestVaultPredicateProxy`. For V2 deposits through `ComplianceProxy`, see the [compliance API reference](compliance/docs/ComplianceProxy.md#deposit--mint-proxy-aware-token-handling).

1. Obtain a predicate authorization message from the Nest application or API.
2. Approve the asset token for the compliance proxy.
3. Call `deposit(asset, amount, recipient, vault, predicateMessage)` on the compliance proxy.

The vault then does this:

1. The vault pulls the assets and deducts the deposit fee.
2. The vault sends the net assets into the share token with `NestShareOFT.enter`.
3. The share token mints shares to the recipient at the accountant exchange rate.

On the vault itself, `deposit` and `mint` are role-gated when a compliance proxy is configured. Only the compliance proxy (role 7) and `DEPOSITOR_ROLE` holders (role 8) can call them. When no compliance proxy is configured, `deposit` and `mint` are public capabilities.

### Async redemption (ERC-7540)

The vault implements the `IERC7540Redeem` asynchronous redemption standard. All requests use request ID `0` and aggregate per controller.

1. Approve the share token for the vault.
2. Call `requestRedeem(shares, controller, owner)`. The vault locks the shares.
3. Wait until an operator fulfills the request. Track state with `pendingRedeemRequest(0, controller)` and `claimableRedeemRequest(0, controller)`.
4. Call `redeem(shares, receiver, controller)` or `withdraw(assets, receiver, controller)` to claim the assets.

Fulfillment is a permissioned step. `fulfillRedeem(controller, shares)` converts the locked shares to assets at the current rate, deducts the redemption fee, and credits the controller's claimable balance. The operator can fulfill fewer shares than are pending.

A controller can reduce or cancel a pending request with `updateRedeem(newShares, controller, receiver)`. The difference in shares returns to the receiver. The new amount cannot exceed the current pending amount.

### Instant redemption

`instantRedeem(shares, receiver, owner)` redeems shares in one transaction against the asset buffer that the share token holds. The instant redemption fee applies, and the fee amount flows back to the share token for the benefit of remaining holders. Instant liquidity is not guaranteed. The [public policy page](https://app.plume.org/docs/about/liquidity-and-redemptions) describes availability.

1. Approve the share token for the vault.
2. Call `instantRedeem(shares, receiver, owner)`. Use `previewInstantRedeem(shares)` first to see the post-fee amount.

The call reverts when the share token does not hold enough assets. The Morpho integration computes the current bound with `NestVaultLib.getInstantRedeemLiquidity` — the asset balance of the share token converted to shares at the current rate.

### Operator approvals

A controller can let another address act on its redemption requests. Three mechanisms exist:

- Per vault: the controller calls `setOperator(operator, true)` on the vault.
- Per vault, by signature: anyone submits an EIP-712 authorization to `authorizeOperator` on the vault. The controller signs the message off-chain.
- Global: the controller calls `setOperator(operator, true)` on the `OperatorRegistry`. Every vault that references the registry accepts the approval.

The vault accepts a caller when the per-vault mapping or the registry approves it.

## Operator procedures

### Fulfill redemptions

The standard path runs through `NestVaultRedeemOperator`. The solver account (role 14 on the common authority) calls one of:

- `fulfillAndRedeem((vault, controller, shares))` — fulfill and claim in one call.
- `fulfillAndRedeemAll(vault, controller)` — fulfill and claim all pending shares.
- `batchFulfillAndRedeem(requests[])` — process many controllers in one transaction.
- `redeem` / `redeemAll` / `batchRedeem` — claim already-fulfilled balances only.

The operator sends the assets to the receiver that the controller set with `setReceiver(vault, receiver)`. When no receiver is set, the assets go to the controller. The controller must approve the `NestVaultRedeemOperator` contract as its operator. `authorizeAsOperator` submits the controller's EIP-712 signature to the vault.

A solver account with role 11 on the vault authority can also call `vault.fulfillRedeem(controller, shares)` directly. Cross-chain redemptions run through the composer. See [oVault cross-chain flow](integrations/ovault/README.md).

### Provide redemption liquidity

`fulfillRedeem` and `instantRedeem` pull assets out of the share token with `NestShareOFT.exit`. The share token must hold enough of the asset token before fulfillment. The manager (role 2, `MANAGER_ROLE`) moves assets into the share token with `manage` calls. Deposit inflows also accumulate there.

### Deploy and wire the operator contracts

Run these when a vault symbol lacks an operator registry or a redeem operator:

```bash
VAULT_SYMBOL=<symbol> forge script script/deploy/DeployOperator.s.sol \
  --sig "runDirect()" --rpc-url $RPC --broadcast
```

Then apply the role wiring from the authority config files:

```bash
VAULT_SYMBOL=<symbol> forge script script/setup/SetupAuthority.s.sol \
  --sig "runDirect()" --rpc-url $RPC --broadcast
```

Use the `runMsig()` variants when the multisig owns the authorities. See [Deployment guide](../script/deploy/README.md).

### Upgrade pre-flight: zero pending redemptions

`script/deploy/Upgrade.s.sol` checks `totalPendingShares()` on every vault before it executes a vault-scope upgrade. Fulfill or cancel all pending redemptions before you run a vault-scope upgrade. The script permits pending shares only when the target accountant preserves the storage layout and its global pending counter covers the vaults' pending sum. Otherwise the upgrade would strand the pending requests: fulfillment would underflow the reset counter.

**Warning:** `FORCE=true` skips this check. Use it only when you have confirmed the accountant storage layout by hand.

### Indexer validation

`script/dev/RunIndexingTestTxs.s.sol` walks every active vault of a symbol through the full lifecycle (deposit → `requestRedeem` → `fulfillRedeem` → `redeem` → `instantRedeem`) so backend indexers observe each event variant.

```bash
VAULT_SYMBOL=<symbol> CHAIN_ID=<chainId> forge script script/dev/RunIndexingTestTxs.s.sol \
  --sig "runDirect()" --rpc-url $RPC --broadcast
```

Optional environment variables: `NUM_ITERATIONS` (default 1) and `DEPOSIT_AMOUNT` (default 10000000, in asset units). The deployer must hold `deposit` access and `CAN_SOLVE_ROLE` on the target vaults.

## Mechanics reference

### Redemption state machine

| Stage | Function | Caller | Effect |
|---|---|---|---|
| Request | `requestRedeem(shares, controller, owner)` | owner or approved operator (public capability) | Shares move from the owner to the vault. `pendingRedeem[controller]` and `totalPendingShares` increase. The accountant's global counter increases via `increaseTotalPendingShares`. |
| Reduce / cancel | `updateRedeem(newShares, controller, receiver)` | controller or operator | Pending shares decrease to `newShares`. The difference returns to the receiver. |
| Fulfill | `fulfillRedeem(controller, shares)` | role 11 / 12 / 5 | Shares convert to assets at the validated rate (floor). The share token burns the shares and moves the gross assets to the vault. The redemption fee is deducted from the actual received amount. Net assets and shares credit `claimableRedeem[controller]`. |
| Claim | `redeem(shares, receiver, controller)` or `withdraw(assets, receiver, controller)` | controller or operator (public capability) | Pays out proportionally from the claimable balances. No further fee. |

Claims pay from a fixed asset/share snapshot, so a later rate change does not affect a fulfilled request. A claim that computes a zero payout reverts with `ERC7540ZeroPayout`, except a full claim of the remaining balance.

### Rate validation

Every conversion calls `_getValidatedRate`, which reads `accountant.getRateInQuoteSafe(asset)`. The call reverts with `InvalidRate` on a zero rate, and with `RateOutOfBounds` when the rate is below the vault `minRate` or above `UPPER_BOUND_RATE_CAP` (1e30). The accountant nets its own fees into the posted rate. See [Accountant fee spec](accountant/README.md).

### Fees

Nest has two fee layers. Accountant management and performance fees are reflected in the exchange rate before the vault converts between assets and shares. Vault fees then apply to individual deposits, async-redemption fulfillments, and instant redemptions. Deposit and async-redemption fees accrue in the vault for later collection; instant-redemption fees return directly to the share token.

Vault fee targets live under `vaultFees` in `script/deployment-config/vaults/<symbol>.json`; optional `vaultMaxFees` entries change their on-chain caps. `script/setup/SetupFees.s.sol` applies both vault and accountant fee configuration. An all-zero vault fee is treated as absent rather than as an instruction to clear an existing fee, and flat fees require an explicit nonzero flat cap. The contract NatSpec is authoritative for fee math, guards, events, and authorization rules. See the [accountant fee spec](accountant/README.md) for the exchange-rate layer and the [deployment guide](../script/deploy/README.md#migrating-a-vault-one-command) for setup behavior.

### Views and previews

- `pendingRedeemRequest(0, controller)` / `claimableRedeemRequest(0, controller)` — request state.
- `maxWithdraw(controller)` / `maxRedeem(controller)` — claimable assets / shares.
- `previewFulfillRedeem(shares)` / `previewInstantRedeem(shares)` — post-fee amounts at the current rate. They do not model the execution-time flat-fee guard.
- `previewWithdraw` / `previewRedeem` — always revert with `ERC7540AsyncFlow`. The asynchronous standard forbids synchronous redeem previews.
- `totalPendingShares()` — the vault-level pending total, used by the upgrade pre-flight.

### Permit2 variants

`NestVaultPermit2` adds `requestRedeemWithPermit2` and `instantRedeemWithPermit2`. They replace the share approval with a Permit2 signature transfer. The compliance proxy offers `depositWithPermit2` on the deposit side.

### Accountant pending-share sync

`requestRedeem`, `updateRedeem`, and `fulfillRedeem` mirror the pending delta to the accountant (`increaseTotalPendingShares` / `decreaseTotalPendingShares`). The accountant uses the global counter in its supply accounting. The sync tolerates a legacy accountant. The vault skips the sync when the selector does not exist. A real revert bubbles up.

### Legacy redemption stack

The BoringVault `AtomicQueue` / `AtomicSolverV3` contracts remain only as vendor copies for the legacy redemption route of the Morpho integration ([Morpho integration](integrations/morpho/README.md)). Their addresses live under the `atomicQueue` and `atomicSolver` keys in `config/morpho/<chainId>.json`. They are not part of the native flow.

## Security

This section lists the emergency controls that touch this flow, at the capability level. [Operators guide](operators/README.md) holds the full emergency table.

| Control | Blocks | Continues |
|---|---|---|
| Accountant pause (`pause()`, role 6, and `unpause()`, role 0) | `deposit`, `mint`, `fulfillRedeem`, `instantRedeem` — the rate read reverts with `Paused` | `requestRedeem`, `updateRedeem`, claims of already-fulfilled requests (`redeem` / `withdraw`), share transfers |
| Share-transfer pause (`BlacklistHook.pause()`, role 6) | all share movement: `requestRedeem`, `instantRedeem`, the share return in `updateRedeem`, and the burn inside `fulfillRedeem` | mints (deposits), claims of already-fulfilled requests |
| Address blacklist (`BlacklistHook.blacklist(address)`, role 15) | the listed sender cannot transfer shares, call `requestRedeem`, or call `instantRedeem` | incoming transfers to the listed address, claims of already-fulfilled requests, deposits |

Pause the accountant and the `BlacklistHook` together to stop the full flow. The blacklist and seizure details belong to [Compliance flow](compliance/README.md).

Passive guards: the vault-side rate bounds (`minRate`, `UPPER_BOUND_RATE_CAP`) and the accountant's posted-rate bounds reject an out-of-band exchange rate. The fee guards (`ZeroAssets`, `InvalidFee`) stop payouts that fees would consume. The upgrade pre-flight above is the operational guard against stranded pending redemptions.

## Code references

- `contracts/NestVaultCore.sol` — vault entry points, rate validation, previews.
- `contracts/libraries/NestVaultDepositLogic.sol` — deposit execution and deposit fee.
- `contracts/libraries/NestVaultRedeemLogic.sol` — request, fulfill, instant, update, claim logic.
- `contracts/libraries/NestVaultCoreValidationLogic.sol` — caller and parameter validation.
- `contracts/libraries/NestVaultTransferLogic.sol` — balance-checked transfers, `safeEnter` / `safeExit`.
- `contracts/NestVaultPermit2.sol` — Permit2 redemption variants.
- `contracts/operators/NestVaultRedeemOperator.sol` — permissioned fulfill-and-redeem operator.
- `contracts/operators/OperatorRegistry.sol` — global ERC-7540 operator approvals.
- `contracts/interfaces/IERC7540.sol` — the async redemption interface.
- `config/authority/authority.json`, `config/authority/common-authority.json` — capability wiring.
- `script/deploy/DeployOperator.s.sol`, `script/setup/SetupAuthority.s.sol` — operator deploy and role setup.
- `script/deploy/Upgrade.s.sol` — upgrade path with the pending-redemption pre-flight.
- `script/dev/RunIndexingTestTxs.s.sol` — lifecycle walker for indexer validation.
