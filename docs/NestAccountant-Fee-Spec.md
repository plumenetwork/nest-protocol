# NestAccountant Fee Spec

This document reflects the current fee behavior in `contracts/NestAccountant.sol` and the upgrade helper in `contracts/upgrades/NestAccountant.sol`.

## Overview

The backend submits a gross NAV-per-share update through `updateExchangeRate(uint96 newGrossRate)`.

The accountant then stores:

- `exchangeRate`: the net user-facing rate after management-fee accrual, performance-fee logic, and any reserve clawback bump,
- `feesOwedInBase`: immediately claimable fees, denominated in the accountant base asset,
- `totalReserve`: uncrystallized performance-fee holdback reserve, also denominated in the base asset.

Unlike older accountant designs, previously accrued fees and reserve are not subtracted from future gross-rate submissions. The submitted `newGrossRate` is the starting point for the current update's fee logic.

## Core State and Checkpoints

The main fee-related checkpoints are:

- `lastUpdateTimestamp`: last successful `updateExchangeRate` timestamp,
- `totalSharesLastUpdate`: share supply checkpoint used in management-fee accrual,
- `lastGrossRate`: last successfully accepted gross rate; used as the management-fee discount basis and to seed HWM when performance fees are enabled,
- `highWaterMark`: gross-rate HWM for performance fees,
- `clawbackReferenceRate`: separate reserve-clawback baseline,
- `hwmLastUpdateTimestamp`: timestamp from which hurdle growth accrues.

These checkpoints matter because management-fee logic and performance-fee logic do not use the same baseline.

## Core `updateExchangeRate` Flow

On each successful `updateExchangeRate(newGrossRate)` call:

1. check `minimumUpdateDelayInSeconds`,
2. read current share supply and `oneShare`,
3. crystallize matured reserve batches,
4. accrue management fees from `newGrossRate`,
5. either:
   - charge performance fees above the hurdle-adjusted HWM, or
   - run reserve clawback / recovery logic,
6. check the final net rate against the configured upper and lower bounds relative to the current stored net rate,
7. on success, checkpoint:
   - `lastUpdateTimestamp = block.timestamp`
   - `totalSharesLastUpdate = totalSupply()`
   - `lastGrossRate = newGrossRate`
   - `exchangeRate = newNetRate`

If the call reverts, none of the intermediate crystallization, fee accrual, clawback, or checkpoint mutations persist.

## Management Fee

Management fee is an annualized AUM fee.

- Cap: 20% (`1e6 = 100%`, so max value is `0.2e6`).

### `updateExchangeRate`

Management-fee accrual is time-proportional:

- `annualize(x, dt) = floor(x * dt / (1e6 * 365 days))`
- `rateBasis = min(lastGrossRate, newGrossRate)`
- `mgmtDiscountPerShare = annualize(rateBasis * managementFee, block.timestamp - lastUpdateTimestamp)`
- `postManagementFeeRate = saturatingSub(newGrossRate, mgmtDiscountPerShare)`

The base-denominated fee added to `feesOwedInBase` is:

- `shareSupplyBasis = min(totalSharesLastUpdate, currentTotalSupply)`
- `mgmtFeeBase = floor(mgmtDiscountPerShare * shareSupplyBasis / oneShare)`

Why the `min(...)` terms matter:

- `min(lastGrossRate, newGrossRate)` prevents charging the whole interval at a later, higher gross rate,
- `min(totalSharesLastUpdate, currentTotalSupply)` prevents charging management fees on shares minted after the interval started.

### `updateManagementFee`

When the management fee changes, the contract first accrues elapsed fees under the old fee using the stored checkpoints:

- `rateBasis = lastGrossRate`
- `shareSupplyBasis = min(totalSharesLastUpdate, currentTotalSupply)`

It then checkpoints:

- `lastUpdateTimestamp = block.timestamp`
- `totalSharesLastUpdate = currentTotalSupply`

and only after that stores the new `managementFee`.

Important behavior:

- if the old management fee is zero, the function still checkpoints time and supply so a later nonzero fee does not apply retroactively,
- `updateManagementFee` does not change `exchangeRate`, `lastGrossRate`, `highWaterMark`, or `clawbackReferenceRate`,
- because it does not fetch a fresh gross-rate checkpoint first, changing the management fee during a drawdown can overaccrue relative to a fresh `updateExchangeRate`.

## Performance Fee

Performance fee is charged on gains above the hurdle-adjusted high-water mark.

- Cap: 50% (`0.5e6`).

### Trigger Path

After management fees, the accountant computes:

- `postHurdleHWM = HWM + HWM * hurdleRate * (block.timestamp - hwmLastUpdateTimestamp) / (1e6 * 365 days)`

If `performanceFee == 0` or `newGrossRate <= postHurdleHWM`, no new performance fee is charged and the function falls into the no-fee / clawback path.

If `newGrossRate > postHurdleHWM`, the contract computes:

- `gainBase = (newGrossRate - postHurdleHWM) * totalShares / oneShare`
- `perfFeeBase = gainBase * performanceFee / 1e6`
- `perfFeePerShare = perfFeeBase * oneShare / totalShares`
- `netRate = saturatingSub(postManagementFeeRate, perfFeePerShare)`

If `perfFeeBase == 0` or `totalShares == 0`, the function returns without charging fees and without moving the HWM.

When a nonzero performance fee is charged:

- `highWaterMark = newGrossRate`
- `hwmLastUpdateTimestamp = block.timestamp`
- `clawbackReferenceRate = post-fee net rate`

### High-Water Mark

`highWaterMark` is tracked in gross terms.

- It is initialized to the starting exchange rate.
- It never decreases on drawdowns.
- A successful nonzero performance-fee charge moves it to the submitted gross rate.

`updatePerformanceFee(0 -> >0)`:

- resets `highWaterMark` to `lastGrossRate`,
- resets `hwmLastUpdateTimestamp`,
- resets `clawbackReferenceRate` to `lastGrossRate` only when reserve is zero.

That behavior prevents gains earned while performance fees were disabled from being retroactively taxed, while also preserving an existing clawback baseline when reserve already exists.

Other HWM behavior:

- `updatePerformanceFee(>0 -> >0)` leaves HWM unchanged,
- `updatePerformanceFee(>0 -> 0)` stops new performance-fee charging but does not clear `feesOwedInBase` or reserve state,
- `resetHighWaterMark(uint96)` can set HWM to any nonzero value and also resets `hwmLastUpdateTimestamp` and `clawbackReferenceRate`.

### Hurdle Rate

Hurdle rate is the annualized threshold before performance fees apply.

- Cap: 30% annualized (`0.3e6`).

Important behavior:

- hurdle accrual runs from `hwmLastUpdateTimestamp`, not from `lastUpdateTimestamp`,
- enabling performance fees or manually resetting HWM restarts the hurdle clock,
- `updateHurdleRate` first rolls accrued hurdle growth under the old hurdle rate into `highWaterMark`, then resets `hwmLastUpdateTimestamp`, then stores the new hurdle rate.

Performance fees apply only to the excess above the hurdle-adjusted HWM, not the full gain once the hurdle is crossed.

## Holdback Reserve

When a performance fee is charged and both of the following are true:

- `holdbackRate > 0`
- `crystallizationWindow > 0`

the contract splits performance fees into:

- immediate fees: `perfFeeBase - holdbackBase`
- reserve: `holdbackBase = floor(perfFeeBase * holdbackRate / 1e6)`

If either condition is false, the entire performance fee goes directly to `feesOwedInBase`.

- `holdbackRate` cap: 100% (`1e6`)

### Reserve Batching

Reserve amounts are stored as batches.

- if `epochsPerWindow == 0`, epoch merging is disabled, but holdback still works,
- otherwise `epochDuration = max(crystallizationWindow / epochsPerWindow, 1 day)`,
- new holdback is merged into the most recent batch when both contributions land in the same epoch.

Important batching nuance:

- when batches are merged, the batch timestamp is overwritten with the newest contribution timestamp,
- adding more holdback to an existing epoch batch can therefore delay crystallization for older amounts in that batch.

## Crystallization

Crystallization runs in three places:

- at the start of `updateExchangeRate`,
- at the start of `claimFees`,
- inside `updateCrystallizationWindow(0)`, after the new zero window is stored.

A batch crystallizes when:

- `batch.timestamp + crystallizationWindow <= block.timestamp`

Crystallization order is FIFO:

- oldest live batch first,
- crystallized amount leaves `totalReserve`,
- crystallized amount is added to `feesOwedInBase`.

Changing `crystallizationWindow` affects existing batches because crystallization always uses the current configured window.

- `crystallizationWindow` cap: 365 days
- `epochsPerWindow` cap: 52

## Clawback and Recovery

Reserve clawback is anchored to `clawbackReferenceRate`, not directly to the HWM.

After a successful performance-fee accrual:

- `clawbackReferenceRate = post-fee net rate`

In the no-new-fee path, the contract can do one of two things.

### Recovery ratchet

If:

- `newGrossRate >= highWaterMark`
- `clawbackReferenceRate < currentPostFeeRate`

then the contract ratchets `clawbackReferenceRate` back up to the current post-fee rate, without consuming reserve.

### Clawback

If:

- `newGrossRate < clawbackReferenceRate`
- `totalReserve > 0`
- `currentTotalSupply > 0`

then:

- `shortfallBase = floor((clawbackReferenceRate - newGrossRate) * totalShares / oneShare)`
- `clawback = min(shortfallBase, totalReserve)`
- `clawbackRate = floor(clawback * oneShare / totalShares)`

If `clawbackRate > 0`:

- reserve is consumed in LIFO order,
- `netRate += clawbackRate`,
- `clawbackReferenceRate = newGrossRate`

If `clawbackRate == 0`, reserve is left untouched.

Important clawback behavior:

- clawback compares against `clawbackReferenceRate`, not against the hurdle-adjusted HWM,
- clawback can still happen when `performanceFee == 0`,
- repeated flat-below-reference updates do not keep draining reserve unless the reference moves again,
- sub-threshold clawback that rounds to zero rate impact does not consume reserve.

## Claiming Fees

`claimFees(ERC20 feeAsset)` is only callable by `SHARE`.

Behavior:

1. revert if paused,
2. crystallize matured reserve first,
3. revert if `feesOwedInBase == 0`,
4. convert the owed base amount into `feeAsset` terms,
5. keep only the carried remainder, if any, in `feesOwedInBase`,
6. pull `feeAsset` from `SHARE` and send it to `payoutAddress`.

### Asset conversion rules

- If `feeAsset == base`, payout equals `feesOwedInBase`.
- If `feeAsset` is marked `isPeggedToBase`, only decimal conversion is applied.
- Otherwise:
  - first convert the base amount into `feeAsset` decimals,
  - then compute `floor(adjustedAmount * 10**feeAssetDecimals / rateProvider.getRate())`.

Important payout details:

- the payout source is `SHARE`, not the accountant,
- the accountant uses `transferFrom(SHARE, payoutAddress, amount)`, so the share-side setup must let it pull the payout asset,
- if decimal conversion truncates because `feeAssetDecimals < baseDecimals`, that decimal remainder is carried forward in `feesOwedInBase`,
- rounding loss from non-base rate conversion is floored into the payout amount and is not separately carried forward.

## Configuration and Safety Bounds

Current hard limits:

- `managementFee <= 20%`
- `performanceFee <= 50%`
- `hurdleRate <= 30% annualized`
- `holdbackRate <= 100%`
- `crystallizationWindow <= 365 days`
- `epochsPerWindow <= 52`
- `minimumUpdateDelayInSeconds <= 14 days`
- `allowedExchangeRateChangeUpper >= 1e6`
- `allowedExchangeRateChangeLower <= 1e6`

Pause behavior:

- `getRateSafe`, `getRateInQuoteSafe`, and `claimFees` revert while paused,
- `updateExchangeRate` remains callable and still enforces delay and bounds checks,
- unsafe getters such as `getRate()` remain callable.

## Upgrade / Reinitialize

`contracts/upgrades/NestAccountant.sol` adds `NestAccountantV2.reinitialize(...)`.

Its current behavior is:

- seed `highWaterMark` from the current stored `exchangeRate`,
- seed `lastGrossRate` from the current stored `exchangeRate`,
- set `hwmLastUpdateTimestamp = block.timestamp`,
- configure the performance-fee parameters through the current internal setters.

The goal is to avoid retroactively charging performance fees on pre-upgrade performance history.

## Practical Invariants

- `exchangeRate` is always the last successfully stored net rate.
- Failed `updateExchangeRate` calls do not change fee balances, reserve state, timestamps, or checkpoints.
- Management-fee discounting uses `lastGrossRate`, while reserve clawback uses `clawbackReferenceRate`.
- Crystallization order is FIFO and clawback order is LIFO.
- Deposit/redemption activity in the vault can change share supply between accountant updates, so management-fee accrual intentionally uses checkpointed supply rather than raw current supply for the entire elapsed interval.
- Fee changes are purely prospective. There is no retroactive fee checkpointing beyond the explicit old-fee accrual performed by `updateManagementFee`.
