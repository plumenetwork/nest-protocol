# NestVault Deposit & Redeem Fee Specification

## Overview

NestVaultCore charges **combined flat + percentage fees** on three user-facing operations: **deposits**, **async redemptions** (fulfill flow), and **instant redemptions**. Each fee is configured as a `Fee` struct containing a percentage `rate` and a fixed `flat` amount, both denominated in the vault's base asset (e.g. USDC). Deposit and async redemption fees accumulate in per-type claimable balances. Instant redemption fees are forwarded directly to `NestShareOFT` instead of accruing as claimable vault fees.

These fees are independent of the NestAccountant's management and performance fees. The accountant fees operate on the exchange rate; the vault fees operate on the asset amounts flowing through deposit and redeem operations.

---

## Fee Structure

Each fee type is configured as a `Fee` struct:

```
struct Fee {
    uint32 rate;   // Percentage fee rate (1e6 = 100%, e.g. 5000 = 0.5%)
    uint256 flat;  // Flat fee in asset token smallest units (e.g. 100000 = $0.10 for 6-decimal USDC)
}
```

The total fee for an operation is: **`flat + floor(gross * rate / 1e6)`**, capped at the gross amount. If the flat fee alone exceeds the gross amount, the entire amount is taken as fee.

## Fee Types

| Enum Value | Operation | When Applied | Applied To |
|---|---|---|---|
| `Fees.Deposit` | `deposit` / `mint` | Before entering the share token | Deposited assets |
| `Fees.Redemption` | `fulfillRedeem` | After exiting the share token | Received assets |
| `Fees.InstantRedemption` | `instantRedeem` | After exiting the share token | Theoretical assets from rate conversion |

---

## Fee Mechanics

### 1. Deposit Fee

**Where:** `NestVaultDepositLogic.executeDeposit`

1. User transfers `_assets` of the base token to the vault.
2. The vault reads the active `Fee` config for `Fees.Deposit` and computes:
   - `feeAmount = calculateFee(_assets, feeConfig.rate, feeConfig.flat)`
   - `netAssets = _assets - feeAmount`
3. `feeAmount` is added to `claimableFees[Fees.Deposit]`.
4. Only `netAssets` is approved and forwarded to `NestShareOFT.enter()` - the share token mints shares proportional to the net amount.
5. The user receives fewer shares than they would at a zero-fee rate.

**Effect on preview functions:**
- `previewDeposit(_assets)` deducts the deposit fee (flat + percentage) from `_assets` before converting to shares.
- `previewMint(_shares)` reverse-engineers the gross asset amount needed to produce `_shares` after fees, using `calculatePreFeeAmount`.

### 2. Async Redemption Fee (Fulfill Flow)

**Where:** `NestVaultRedeemLogic.executeFulfillRedeem`

The async redeem flow has three stages:

1. **Request** (`requestRedeem`): User locks shares in the vault. No fee applied.
2. **Fulfill** (`fulfillRedeem`): An authorized caller processes the request:
   - Converts shares to gross assets at the current exchange rate (floor rounding).
   - Calls `NestShareOFT.exit()` to burn shares and receive assets.
   - Reads the active `Fee` config for `Fees.Redemption` and computes: `(netReceived, feeAmount) = calculatePostFeeAmounts(amountReceived, feeConfig.rate, feeConfig.flat)`.
   - If `netReceived == 0`, the transaction reverts with `ZeroAssets`.
   - If `feeConfig.flat > 0` and the flat component exceeds `20%` of the realized `amountReceived`, the transaction reverts with `InvalidFee`.
   - `feeAmount` is added to `claimableFees[Fees.Redemption]`.
   - `netReceived` is credited to the controller's `claimableRedeem` balance.
3. **Claim** (`withdraw` / `redeem`): User claims from their `claimableRedeem` balance. No additional fee applied.

**Key detail:** The fee is applied to the *actual amount received* from the share token exit, not the theoretical asset value. This means any rounding differences between the expected and actual exit amount are absorbed before the fee calculation.

**Effect on preview functions:**
- `previewFulfillRedeem(_shares)` applies the configured fee to the theoretical asset amount from the current rate conversion.
- It does **not** model the execution-time flat-fee ratio guard above, so small fulfills can preview a positive net amount and still revert with `InvalidFee`.

### 3. Instant Redemption Fee

**Where:** `NestVaultRedeemLogic.executeInstantRedeem`

1. User transfers shares to the vault.
2. Shares are converted to assets at the current exchange rate (floor rounding).
3. The vault reads the active `Fee` config for `Fees.InstantRedemption` and computes: `(expectedPostFeeAmount, _) = calculatePostFeeAmounts(_assets, feeConfig.rate, feeConfig.flat)`.
4. If `expectedPostFeeAmount == 0`, the transaction reverts with `ZeroAssets`.
5. Calls `NestShareOFT.exit()` to burn shares and receive assets.
6. Transfers exactly `expectedPostFeeAmount` to the receiver.
7. The difference between the actual received amount and the transferred amount is the fee: `feeAmount = amountReceived - expectedPostFeeAmount`.
8. `feeAmount` is transferred directly to `NestShareOFT`.

**Difference from async redemption:** The fee is computed on the *theoretical* asset value (from the exchange rate conversion), not the actual exit amount. Any rounding surplus from the exit goes to `NestShareOFT`, not to a claimable fee bucket.

---

## Fee Calculation Functions

All fee math lives in `NestVaultAccountingLogic`:

| Function | Purpose |
|---|---|
| `calculateFee(assets, feeRate, flatFee)` | Returns `min(assets, flatFee + floor(assets * feeRate / 1e6))`. If `flatFee >= assets`, returns `assets`. |
| `calculatePostFeeAmounts(assets, feeRate, flatFee)` | Returns `(assets - fee, fee)` where fee is from `calculateFee`. Short-circuits to `(assets, 0)` when both `feeRate` and `flatFee` are zero. |
| `calculatePreFeeAmount(postFeeAmount, feeRate, flatFee)` | Returns the minimum gross amount such that `gross - calculateFee(gross, feeRate, flatFee) >= postFeeAmount`. |

**`calculateFee` detail:** The flat fee and percentage fee are **additive on the same gross base**. The percentage is applied to the full gross amount, not to `gross - flatFee`. The result is capped at `assets` to prevent the fee from exceeding the input.

**`calculatePreFeeAmount` detail:** Adds `flatFee` to `postFeeAmount` to get the target before applying ceiling division for the percentage component: `gross = ceil((postFeeAmount + flatFee) * 1e6 / (1e6 - feeRate))`. Returns 0 when `postFeeAmount` is 0. This is used by `previewMint` to tell the user the exact deposit amount needed for a target share count.

---

## Fee Configuration

### Setting Fees

Authorized callers use `setFee(Fees _f, Fee calldata _fee)`:
- Both `_fee.rate` and `_fee.flat` are validated independently against `maxFees[_f]` - reverts if `_fee.rate > maxFees[_f].rate` or `_fee.flat > maxFees[_f].flat`.
- Takes effect immediately for all subsequent operations.
- No checkpointing or accrual of old fees before change (unlike the accountant's management fee).
- Emits `SetFee(_f, oldFee, newFee)` where `oldFee` and `newFee` are `Fee` structs.

### Fee Caps

Each fee type has a `maxFees` entry (also a `Fee` struct) that `setFee` validates against. The **percentage rate caps** for all three types are initialized to `20%` (`0.2e6`) in `__NestVaultCore_init_unchained`. The **flat fee caps** default to `0` (flat fees are disabled until `setMaxFee` raises the cap):

```
$.maxFees[Fees.InstantRedemption].rate = FEE_CAP;  // 0.2e6
$.maxFees[Fees.Deposit].rate           = FEE_CAP;  // 0.2e6
$.maxFees[Fees.Redemption].rate        = FEE_CAP;  // 0.2e6
// .flat fields default to 0
```

### Updating Fee Caps

Authorized callers use `setMaxFee(Fees _f, Fee calldata _maxFee)`:
- `_maxFee.rate` is validated against the compile-time `FEE_CAP` (`0.2e6`) - reverts if `_maxFee.rate > FEE_CAP`. The rate cap **cannot** be raised above 20%.
- `_maxFee.flat` has **no hardcoded upper bound** - it can be set to any `uint256` value.
- Both `_maxFee.rate` and `_maxFee.flat` must be **at or above** the currently active fee for that type - reverts if lowering either component below the active fee.
- Emits `SetMaxFee(_f, oldMaxFee, newMaxFee)`.

### Claiming Fees

`claimFee(Fees _f, address _receiver)` is only callable by `SHARE` (`NestShareOFT`), not by an arbitrary `requiresAuth` admin:
- Reverts if `_receiver` is `address(0)`.
- Reverts if `claimableFees[_f]` is zero (no-op claims are not allowed).
- Transfers the entire `claimableFees[_f]` balance to `_receiver`.
- Resets `claimableFees[_f]` to zero.
- Emits `FeeClaimed(_f, _receiver, amount)`.
- Protected by `nonReentrant`.

In practice, only `Fees.Deposit` and `Fees.Redemption` should accumulate claimable balances. `Fees.InstantRedemption` fees are routed directly to `NestShareOFT`.

---

## Interaction with NestAccountant Fees

The vault fees and accountant fees are **layered**, not alternatives:

1. **Accountant fees** (management + performance) are baked into the **exchange rate**. When a user deposits or redeems, the rate they get already reflects accountant fee deductions.
2. **Vault fees** are then applied on top, deducting from the asset amounts at deposit/redeem time.

For a deposit:
- User sends `X` assets.
- Vault deducts deposit fee: `netAssets = X - flat - floor(X * rate / 1e6)`.
- `netAssets` is converted to shares at the accountant's net exchange rate (which already has management/performance fees embedded).

For a redemption:
- Shares are converted to assets at the accountant's net exchange rate.
- Vault deducts redemption fee (flat + percentage) from the resulting asset amount.
- For instant redemptions, that fee is sent back to `NestShareOFT` rather than left in a claimable vault balance.

The total cost to the user is the combination of both fee layers.

---

## What Admin Can Do

| Action | Constraints |
|---|---|
| Set deposit fee | Rate cannot exceed `maxFees[Deposit].rate`; flat cannot exceed `maxFees[Deposit].flat` |
| Set redemption fee | Rate cannot exceed `maxFees[Redemption].rate`; flat cannot exceed `maxFees[Redemption].flat` |
| Set instant redemption fee | Rate cannot exceed `maxFees[InstantRedemption].rate`; flat cannot exceed `maxFees[InstantRedemption].flat` |
| Update max fee rate | Hardcoded ceiling: rate cannot exceed `FEE_CAP` (20%); cannot lower below active fee rate |
| Update max fee flat | No hardcoded ceiling for flat component; cannot lower below active flat fee |
| Set accountant | Must implement a compatible `getRateInQuoteSafe(ERC20)` interface; a paused revert is accepted during compatibility checks |

## What Admin Cannot Do

- Set a fee rate or flat amount above the current `maxFees` for that type (reverts).
- Set a max fee rate above `FEE_CAP` (20%) (reverts).
- Lower a max fee below the currently active fee for that type (reverts).
- Retroactively apply a fee change - fee changes take effect immediately and only affect future operations.
- Call `claimFee` directly on the vault - only `SHARE` can call it.
- Make an async `fulfillRedeem` succeed when the configured flat fee exceeds `20%` of the realized assets for that fulfill - it reverts with `InvalidFee`.
- Bypass the `requiresAuth` gate on `setFee`, `setMaxFee`, or `setAccountant`.

---

## Key Design Notes

1. **Flat and percentage fees are additive on the same base.** The percentage fee is computed on the full gross amount, not on `gross - flat`. This means the total fee is always `flat + floor(gross * rate / 1e6)`, capped at the gross amount.

2. **Deposit fee reduces shares minted, not assets held.** The vault retains the fee in its asset balance. The share token only sees the net amount.

3. **Redemption fee is applied post-exit.** The share token burns the full share count and returns assets. The vault then applies the fee to what the redeem path considers its fee base: actual received amounts for async fulfills, theoretical converted amounts for instant redeems.

4. **Async vs instant redemption fee asymmetry.** The async fee uses actual received amount as the base; the instant fee uses the theoretical amount from exchange rate conversion. Any rounding surplus from the exit in instant redemptions goes to `NestShareOFT` rather than the user.

5. **Both async and instant redemptions revert on zero post-fee amount.** If fees consume the entire amount, the transaction reverts with `ZeroAssets` rather than completing with a zero payout.

6. **No fee-on-fee.** Each operation applies exactly one fee type. Depositing applies only the deposit fee; redeeming applies only the applicable redemption fee. There is no compounding of vault-level fees.

7. **Vault fees are discrete, not streaming.** Unlike the accountant's management fee (which accrues continuously via the exchange rate), vault fees are only realized when an actual deposit or redeem transaction executes. Deposit and async redemption fees accrue in `claimableFees`; instant redemption fees are remitted immediately to `NestShareOFT`.

8. **Flat fee caps start at zero.** Until admin calls `setMaxFee` to raise the flat cap, no flat fees can be set. This preserves backward compatibility with deployments that only use percentage fees.

9. **Async fulfill has an extra flat-fee runtime guard.** Even if a redemption flat fee is within `maxFees`, `fulfillRedeem` still reverts when the flat component is more than `20%` of the realized assets for that specific fulfill. `previewFulfillRedeem` does not enforce that extra check.
