# NestAccountant Fee Spec

[← Back to repository overview](../../README.md)

This document specifies the accountant layer of a Nest vault: exchange-rate updates, management fees, performance fees, the holdback reserve, and clawback. It covers `NestHubAccountant` (fee logic, hub chain) and `NestSpokeAccountant` (rate mirror, spoke chains). Operators use it for the rate-update and fee procedures. Engineers use it as the mechanics reference.

## Related documentation

Public documentation:

- [Vault operations and valuation](https://app.plume.org/docs/about/vault-operations-and-valuation) — how vault NAV and APY are presented to users.
- [Architecture](https://app.plume.org/docs/about/architecture) — protocol overview.
- [Cross-chain](https://app.plume.org/docs/about/cross-chain) — high-level omnichain design and cross-chain share transfers.
- [Smart contracts](https://app.plume.org/docs/developers/smart-contracts) — public contract addresses.

Repo documentation:

- [Vault operation fees](../README.md#fees) — vault-level deposit and redemption fees. Those fees are separate from accountant fees.
- [Deposit and redeem flow](../README.md) — how the vault consumes the rate.
- [Compliance flow](../compliance/README.md) — the share-freeze lever (`BlacklistHook.pause`) and the blacklist controls.
- [Roles and authorities](../auth/README.md) — complete role, holder, and capability reference.
- [Operators guide](../operators/README.md) — operational procedures and the emergency-control table.
- [oVault cross-chain flow](../integrations/ovault/README.md) — cross-chain share transfers that move supply between chains.
- [Deployment guide](../../script/deploy/README.md) — migration pipeline that runs `SetupFees`.

## User flow

A holder does not interact with the accountant directly. The accountant sets the share price the vault uses.

1. The holder deposits into the vault. The vault prices the shares with the stored net rate.
2. The strategy earns yield. A keeper posts a new rate to the hub accountant.
3. The accountant deducts accrued fees from the posted rate and stores the net rate.
4. The holder redeems at the current net rate. Vault-level redemption fees, if any, apply on top ([vault operation fees](../README.md#fees)).

When the net rate can move down:

- The strategy NAV falls. The lower bound limits the step per update.
- Accrued fees exceed the gain in a rate update.

When the net rate can move up beyond the NAV:

- After a drawdown, clawback returns the holdback reserve to holders as a rate credit.

While the accountant is paused, deposits and safe-rate paths revert. Balances do not change. See [Security](#security).

## Operator procedures

### Post a rate update (keeper, routine)

The keeper account holds `UPDATE_EXCHANGE_RATE_ROLE` (role 4). Role holders per vault are in `roles.UPDATE_EXCHANGE_RATE_ROLE` of `script/deployment-config/vaults/<symbol>.json`.

**Warning:** the posted rate must be net of all outstanding fee liabilities: `feesOwedInBase`, the management-fee carry, and the holdback reserve. Read them with `feeLiabilities()`. A gross rate double-charges holders.

1. Compute the global share supply (see the next procedure).
2. Call `updateExchangeRate(newRate, totalShareSupply)` on the hub accountant.
3. Read the stored net rate from the hub with `getRate()`.
4. Call `updateExchangeRate(netRate, 0)` on each spoke accountant. The spoke ignores the supply argument.
5. Respect `minimumUpdateDelayInSeconds` between updates on each accountant.

Current config values (`accountantParams` in each vault config):

| Key | Current value | Meaning |
|---|---|---|
| `minimumUpdateDelayInSeconds` | `3600` (every config with `accountantParams`) | Minimum 1 hour between updates |
| `allowedExchangeRateChangeUpper` | `1000500` (most) or `1001000` (6 vaults) | Max +0.05% or +0.1% per update |
| `allowedExchangeRateChangeLower` | `999500` (most) or `999000` (6 vaults) | Max −0.05% or −0.1% per update |

### Respond to a `RateOutOfBounds` revert

A post outside the bounds reverts with `RateOutOfBounds`. Nothing changes on-chain: no fees, no checkpoints, no rate.

1. Verify the NAV input and the fee-liability netting.
2. If the posted rate was wrong, correct it and post again.
3. If the move is genuine but larger than the bound, choose one path:
   - Step the rate over several updates, each inside the bound and after the delay.
   - Have the owner Safe widen the bound with `updateUpper` or `updateLower`, post, then restore the bound.

### Compute the global share supply

The hub accountant needs the total share supply across every chain. It rejects a value below the local supply (`TotalSupplyBelowLocal`).

```bash
TOTAL_SHARE_SUPPLY=$(ts-node tools/totalShareSupply.ts <VAULT_SYMBOL>)
```

The tool sums the share token's `totalSupply()` on every deployed chain. Deployed chains are the chains with a snapshot at `script/output/<vault>/<chainId>-<vault>.json`. The tool hard-fails if any chain is unreadable. It never emits a partial sum.

**Warning:** shares in flight between chains are burned at the source and not yet minted at the destination. The per-chain sum misses them. Add the in-flight amount, or run during a quiet period. This correction is off-chain by design.

### Configure fees (`SetupFees`)

`script/setup/SetupFees.s.sol` applies `accountantParams` (management fee, performance fee, hurdle rate, optional high-water-mark pin) and `vaultFees` from the vault config. It is idempotent: it skips values already on-chain.

**Warning:** Call `updateExchangeRate` immediately before changing the management fee. The setter advances the
timestamp without accruing the preceding interval, so any fees since the last rate update are forfeited. The call
reverts when the checkpoint is older than the 14-day `UPDATE_DELAY_CAP` or the new fee equals the current fee.

**Warning:** Call `updateExchangeRate` immediately before changing the performance fee, and execute the queued fee
batch promptly after a rate post: the new fee applies to all gains since the last checkpoint. `SetupFees` never posts
a rate. It skips `updatePerformanceFee` when `lastGrossRate` is still `0` (post-migration; the enable would revert
`InvalidRate`) or when the checkpoint is older than `minimumUpdateDelayInSeconds`. Sequence: upgrade executed → keeper
posts a rate → run the fee step → Safe executes the fee batch promptly. On Plume the accountant owner is the protocol
timelock, so the fee batch executes only after the timelock delay; keep the keeper posting on its normal cadence so the
checkpoint is recent at execution time.

```bash
VAULT_SYMBOL=<symbol> CHAIN_ID=<id> \
  forge script script/setup/SetupFees.s.sol --sig "runDirect()" --rpc-url $RPC --broadcast
```

- Use `--sig "runMsig()"` to write a Safe batch instead of broadcasting.
- Run the accountant-fee pass against the hub chain. Spoke accountants hold no fee state; the script logs and skips accountant fees off-hub, and defers them (log + skip) while the hub proxy still runs the legacy implementation — execute the upgrade, then rerun.
- In the `pnpm deploy` pipeline, queued fee calls land in batch slot 4 and execute after ownership acceptance ([Deployment guide](../../script/deploy/README.md)).
- The script queues `resetHighWaterMark` only for an explicit non-zero `accountantParams.highWaterMark`. Enabling a performance fee already seeds the HWM.
- `updateHurdleRate` reverts with `SameValue` on a no-op, so the script checks the current value first.

### Claim fees

`claimFees(feeAsset)` is callable only by the share token (`SHARE`). The operational path goes through `NestShareOFT.manage` (`MANAGER_ROLE`, role 2):

1. Approve the accountant to pull `feeAsset` from the share token (via `manage`, once per asset).
2. Call `share.manage(accountant, abi.encodeCall(claimFees, (feeAsset)), 0)`.
3. The accountant crystallizes matured reserve, converts the owed base amount, and pulls `feeAsset` from the share token to `payoutAddress`.

The owner Safe changes the payout target with `updatePayoutAddress`.

### Audit posted rates

```bash
ts-node tools/fetchPriceUpdates.ts --accountant <name-or-address> --from <block|unix|ISO-date>
```

The tool prints every `ExchangeRateUpdated` event per accountant over the range. A name works only for vaults in the built-in `KNOWN` map. An address always works. Use the tool to reconcile the posted history against the strategy NAV feed.

## Mechanics reference

### Contract roster

| Contract | Where | Behavior |
|---|---|---|
| `NestHubAccountant` | Hub chain (Plume, 98866) | Full fee logic: management, performance, holdback, clawback |
| `NestSpokeAccountant` | Spoke chains | Stores the hub-computed net rate, with bounds and delay but no fee accrual |
| `NestAccountant` | Legacy deployments | Management fee only, with single-argument `updateExchangeRate(uint96)` |

`accountantType` in the vault config selects the roster. `"NestHubAccountant"` deploys the hub on `hubChainId` (default 98866) and spokes elsewhere. An absent field defaults to the legacy `NestAccountant` on every chain.

### Core state (hub)

- `exchangeRate` — last stored net rate. All vault pricing reads it.
- `lastGrossRate` — last accepted posted rate. Basis for management-fee discounting and HWM seeding.
- `lastUpdateTimestamp`, `totalSharesLastUpdate` — accrual checkpoints.
- `feesOwedInBase` — claimable fees, in base-asset units.
- `managementFeeCarry` — accrued but unrealized management fee, scaled by `1e6 * 365 days`.
- `highWaterMark` — gross-rate HWM for performance fees.
- `clawbackReferenceRate` — separate clawback baseline. Not the HWM.
- `hwmLastUpdateTimestamp` — start of hurdle accrual.
- `totalReserve` plus batches — holdback reserve, in base-asset units.

Management fees and performance fees use different baselines.

### `updateExchangeRate(postedRate, totalShareSupply)` flow

1. Reject if `totalShareSupply` is below the local share supply (`TotalSupplyBelowLocal`).
2. Reject if `minimumUpdateDelayInSeconds` has not passed (`MinimumUpdateDelayNotPassed`).
3. Crystallize matured reserve batches into `feesOwedInBase`.
4. Accrue the management fee from the posted rate.
5. Either charge a performance fee above the hurdle-adjusted HWM, or run recovery or clawback.
6. Reject if the final net rate breaks the bounds against the current stored net rate (`RateOutOfBounds`).
7. Checkpoint: `lastUpdateTimestamp`, `totalSharesLastUpdate`, `lastGrossRate = postedRate`, `exchangeRate = netRate`.

A revert rolls back the entire update.

### Management fee

Annualized AUM fee. Cap 20% (`0.2e6`, where `1e6` = 100%). Accrual per update:

```text
rateBasis   = min(lastGrossRate, postedRate)
supplyBasis = min(totalSharesLastUpdate, totalShareSupply)
dt          = block.timestamp - lastUpdateTimestamp

accrued     = managementFeeCarry + (rateBasis * managementFee * dt) * supplyBasis / oneShare
rateHaircut = floor(accrued / (1e6 * 365 days)) * oneShare / totalShareSupply   // floored
mgmtFeeBase = floor(rateHaircut * totalShareSupply / oneShare)
```

If `mgmtFeeBase > 0`, the contract realizes the fee. It subtracts `rateHaircut` from the posted rate (saturating). It adds `mgmtFeeBase` to `feesOwedInBase` and keeps only the remainder in `managementFeeCarry`. Otherwise it stores the whole `accrued` in the carry and changes nothing else.

Why this shape:

- The fee is re-derived from the floored haircut. The booked fee always equals the reduction holders bear.
- The carry preserves sub-unit accrual. Total fees do not depend on update cadence.
- `min(lastGrossRate, postedRate)` avoids charging the whole interval at a later, higher rate.
- `min(totalSharesLastUpdate, totalShareSupply)` avoids charging on shares minted mid-interval.
- `managementFeeCarry` holds the accrual until a haircut of one rate unit is representable. With a large share supply the carry can exceed `1e6 * 365 days` before realization.

### `updateManagementFee(newFee)`

The function does not accrue management fees. It requires `lastUpdateTimestamp` to be no more than the 14-day
`UPDATE_DELAY_CAP` old, sets `lastUpdateTimestamp = block.timestamp`, then stores the new fee. Management fees
between the preceding checkpoint and the fee change are intentionally forfeited. Reapplying the current fee reverts
with `SameValue` without advancing the timestamp.

The setter does not change `totalSharesLastUpdate`, `feesOwedInBase`, `managementFeeCarry`, `exchangeRate`,
`lastGrossRate`, `highWaterMark`, or `clawbackReferenceRate`. The exchange-rate delay, supply validation, and rate
bounds do not apply because no rate update occurs.

Call `updateExchangeRate` immediately before changing the management fee to minimize forfeited fees and refresh the
global supply checkpoint. A checkpoint exactly `UPDATE_DELAY_CAP` old is accepted; an older checkpoint reverts with
`UpdateDelayTooLarge`.

### Performance fee, HWM, and hurdle

Cap 50% (`0.5e6`). Hurdle cap 30% annualized (`0.3e6`). The fee applies only to the excess above the hurdle-adjusted HWM:

```text
postHurdleHWM   = HWM + HWM * hurdleRate * (now - hwmLastUpdateTimestamp) / (1e6 * 365 days)
gainBase        = (postedRate - postHurdleHWM) * supply / oneShare
perfFeeBase     = gainBase * performanceFee / 1e6
perfFeePerShare = perfFeeBase * oneShare / supply
perfFeeBase     = perfFeePerShare * supply / oneShare        // re-derived from the floored haircut
netRate         = postManagementFeeRate - perfFeePerShare    // saturating
```

If `performanceFee == 0` or `postedRate <= postHurdleHWM`, the flow falls into recovery/clawback below. If `perfFeeBase` or `perfFeePerShare` floors to zero, the contract charges nothing and the HWM does not move. The dust gain stays captured for later. When the contract charges a nonzero fee: `highWaterMark = postedRate`, `hwmLastUpdateTimestamp = now`, `clawbackReferenceRate = netRate`.

At zero total supply, the contract crystallizes the whole reserve into `feesOwedInBase`. It sets new anchors for the HWM, hurdle clock, and clawback reference.

Stale state must not tax the next depositor cohort.

HWM administration:

- `updatePerformanceFee(0 -> >0)` ratchets the HWM up to `lastGrossRate` (never down), resets the hurdle clock, and re-seeds `clawbackReferenceRate` only when the reserve is empty. Gains earned while fees were disabled are not retroactively taxed.
- `updatePerformanceFee(>0 -> 0)` stops new charges. It clears no owed fees and no reserve.
- `resetHighWaterMark(v)` sets the HWM to any nonzero value and resets the hurdle clock and clawback reference.
- `updateHurdleRate` first rolls hurdle growth accrued under the old rate into the HWM, then resets the hurdle clock. It reverts with `SameValue` on a no-op.

### Holdback reserve

When a performance fee is charged and both `holdbackRate > 0` and `crystallizationWindow > 0`, the fee splits: `holdbackBase = floor(perfFeeBase * holdbackRate / 1e6)` goes to the reserve, the rest to `feesOwedInBase`. If either condition is false, the whole fee is immediate. `holdbackRate` cap 100% (`1e6`).

Reserve batching:

- Epoch duration = `crystallizationWindow / epochsPerWindow`, floored at 1 day. `epochsPerWindow == 0` collapses to a single epoch, so batches merge across the whole window. Cap 52.
- A new holdback merges into the newest batch when both land in the same epoch. The merge overwrites the batch timestamp with the newest contribution, which can delay crystallization of older amounts in that batch.

### Crystallization

A batch crystallizes when `batch.timestamp + crystallizationWindow <= now`. Crystallization is FIFO: the amount leaves `totalReserve` and joins `feesOwedInBase`. It runs at the start of `updateExchangeRate` and `claimFees`, inside `updateCrystallizationWindow(0)` when the old window was non-zero, and fully (all batches) on a zero-supply update. Maturity always uses the current configured window, so a window change affects existing batches. Window cap 365 days.

### Clawback and recovery

Both run in the no-new-fee path and anchor to `clawbackReferenceRate`:

- Recovery: if `postedRate >= highWaterMark` and the reference is below the current post-fee rate, the reference ratchets up. No reserve moves.
- Clawback: if `postedRate < clawbackReferenceRate` and `totalReserve > 0`:

```text
shortfallBase = (clawbackReferenceRate - postedRate) * supply / oneShare
clawback      = min(shortfallBase, totalReserve)
clawbackRate  = clawback * oneShare / supply
```

If `clawbackRate > 0`, the contract removes the base equivalent of `clawbackRate` (rounded up) from the reserve, newest batches first (LIFO). The net rate gains `clawbackRate`, and the reference moves to `postedRate`. Clawback works with `performanceFee == 0`. Repeated flat updates below the reference do not keep draining reserve. A shortfall that floors to zero rate impact consumes nothing.

### Fee waivers

- `waiveFees(amount)` forfeits accrued fees to holders. It draws from `managementFeeCarry` first, then `feesOwedInBase`. The stored rate is not retroactively adjusted.
- `waiveReserve(amount)` removes reserve newest-batch-first without a rate credit and without crystallization.

Both are `requiresAuth` with no wired role capability, so only the owner Safe can call them.

### `claimFees` conversion rules

- `feeAsset == base`: payout equals `feesOwedInBase`, no remainder.
- `feeAsset` pegged to base: decimal conversion only. A truncated decimal remainder stays in `feesOwedInBase`.
- Otherwise: decimal conversion, then `floor(adjusted * 10**feeAssetDecimals / rateProvider.getRate())`. Rate-conversion rounding is floored into the payout, not carried.

The payout source is the share token, not the accountant: `transferFrom(SHARE, payoutAddress, amount)`.

### Hard caps and invariants

| Parameter | Cap |
|---|---|
| `managementFee` | 20% (`0.2e6`) |
| `performanceFee` | 50% (`0.5e6`) |
| `hurdleRate` | 30% annualized (`0.3e6`) |
| `holdbackRate` | 100% (`1e6`) |
| `crystallizationWindow` | 365 days |
| `epochsPerWindow` | 52 |
| `minimumUpdateDelayInSeconds` | 14 days |
| `allowedExchangeRateChangeUpper` | `>= 1e6` |
| `allowedExchangeRateChangeLower` | `<= 1e6` |

Invariants:

- `exchangeRate` is always the last successfully stored net rate.
- A failed `updateExchangeRate` changes no fee balance, reserve, timestamp, or checkpoint.
- A rate reduction and a booked fee always occur together. The unrealized fraction stays in `managementFeeCarry`.
- Crystallization is FIFO. Clawback is LIFO.
- Management-fee changes are prospective. `updateManagementFee` forfeits uncheckpointed management fees from the preceding
  interval and starts the new fee at the current timestamp.
- The posted rate is net of `feesOwedInBase`, the carry, and the reserve. `feeLiabilities()` exposes all three.

## Security

This section documents the controls and the current state only.

**Rate-bounds circuit breaker (passive).** `allowedExchangeRateChangeUpper/Lower` limit each accepted rate change. An out-of-bounds update reverts with `RateOutOfBounds`. An update before `minimumUpdateDelayInSeconds` has elapsed reverts with `MinimumUpdateDelayNotPassed`. Both leave the stored rate unchanged.

**Pause.** `pause()` blocks `getRateSafe`, `getRateInQuoteSafe`, and `claimFees`. Vault paths that price through the safe getters stop: deposits, mints, `instantRedeem`, `fulfillRedeem`. `updateExchangeRate` stays callable and still enforces delay and bounds. Unsafe getters (`getRate`, `getRateInQuote`) stay callable. This pause does not block share transfers or `requestRedeem` — see [Compliance flow](../compliance/README.md) for the share-freeze lever (`BlacklistHook.pause`).

**Pause scope is per chain, by design.** A hub pause does not propagate. Pause the hub accountant and each spoke accountant separately. The keeper coordinates this off-chain.

**Authority wiring** (`config/authority/authority.json`, role numbers in `script/lib/Constants.sol`):

| Call | Caller |
|---|---|
| `updateExchangeRate` (both overloads) | Role 4 `UPDATE_EXCHANGE_RATE_ROLE` |
| `pause()` | Role 6 `PAUSER_ROLE` |
| `unpause()` | Role 0 `OWNER_ROLE` |
| `increaseTotalPendingShares` / `decreaseTotalPendingShares` | Role 3 `TELLER_ROLE` (held by the vault) |
| `claimFees` | Share token only (`msg.sender == SHARE`) |
| Fee, bound, delay, payout, and rate-provider setters, plus `waiveFees` and `waiveReserve` | Owner Safe (`requiresAuth`, no role capability wired) |

## Code references

- `contracts/accountant/NestHubAccountant.sol` — hub fee logic (this spec's primary subject).
- `contracts/accountant/NestSpokeAccountant.sol` — spoke rate mirror.
- `contracts/accountant/NestAccountant.sol` — legacy accountant, management fee only.
- `script/setup/SetupFees.s.sol` — fee configuration script.
- `script/deployment-config/vaults/<symbol>.json` — `accountantParams`, `vaultFees`, `roles`.
- `script/lib/ConfigReader.sol` — `accountantType` / `hubChainId` resolution.
- `config/authority/authority.json` — role-to-capability wiring.
- `tools/totalShareSupply.ts` — global share-supply input.
- `tools/fetchPriceUpdates.ts` — posted-rate history audit.
