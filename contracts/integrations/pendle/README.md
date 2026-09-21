# Pendle SY Flow

[← Back to repository overview](../../../README.md)

`BoringVaultSY` wraps one Nest vault share token as a Pendle Standardized Yield (SY) token.
The SY token lets Pendle build PT/YT markets on top of a Nest vault.
Users wrap and unwrap share tokens 1:1.
The SY exchange rate comes from the vault's `NestAccountant`.
This document is for operators who deploy the SY wrapper and for engineers who review its mechanics.

## Related documentation

Public documentation (app.plume.org/docs):

* [Vault operations and valuation](https://app.plume.org/docs/about/vault-operations-and-valuation) — how the protocol produces the vault exchange rate.
* [Liquidity and redemptions](https://app.plume.org/docs/about/liquidity-and-redemptions) — how a user gets or exits share tokens.
* [Smart contracts](https://app.plume.org/docs/developers/smart-contracts) — public contract addresses.
* [Nest protocol (developers)](https://app.plume.org/docs/developers/nest-protocol) — protocol overview.

Repo documentation:

* [Accountant fee spec](../../accountant/README.md) — accountant rate and fee mechanics.
* [Deposit and redeem flow](../../README.md) — how a user deposits into the vault and redeems share tokens.
* [Roles and authorities](../../auth/README.md) — complete role, holder, and capability reference.
* [Operators guide](../../operators/README.md) — the emergency-control table.
* [Deployment guide](../../../script/deploy/README.md) — the general deploy framework, config layout, and role wiring.

## User flow

Pendle users usually interact with the SY token through Pendle's router and PT/YT markets, which are out of scope here.
The direct SY flow is:

1. Get share tokens (for example `nBASIS`). See [Liquidity and redemptions](https://app.plume.org/docs/about/liquidity-and-redemptions).
2. Approve the SY contract to spend the share tokens.
3. Call `deposit(receiver, tokenIn, amountTokenToDeposit, minSharesOut)`. `tokenIn` must be the share token. The contract mints SY tokens 1:1.
4. Hold the SY token. Its value tracks the accountant rate. The SY balance stays constant while the `exchangeRate()` value changes.
5. Call `redeem(receiver, amountSharesToRedeem, tokenOut, minTokenOut, burnFromInternalBalance)` to exit. `tokenOut` must be the share token. The contract burns SY tokens and returns share tokens 1:1.

`getTokensIn()` and `getTokensOut()` return only the share token address. The SY contract does not handle the vault's base asset.

### How the SY rate tracks the accountant

`exchangeRate()` reads the vault's base-asset rate from `accountant.getRateInQuoteSafe(asset)` on every call.

### Merkl rewards

The SY contract can hold Merkl (Angle distributor) reward claims.
`claimOffchainRewards(...)` claims the rewards from the distributor and forwards them to a receiver.
Only the `offchainRewardManager` address can call it.
The deploy script sets `offchainRewardManager` to Pendle's pause controller, so Pendle operates reward claims.
The standard SY reward interface (`claimRewards`, `getRewardTokens`, `accruedRewards`) returns empty values. Rewards flow only through the Merkl path.

## Operator procedures

### Deploy the SY wrapper

**Warning:** This deployment does not follow the Nest standard proxy pattern.
It follows Pendle's SY Deployment Checklist instead.
The proxy admin is Pendle's canonical `ProxyAdmin`, and the owner is Pendle's pause controller.
Do not deploy a new `ProxyAdmin` for the SY proxy.

Prerequisites:

* The vault share token and the accountant are deployed on the target chain.
* The vault config file `script/deployment-config/vaults/<SYMBOL>.json` has `contracts.share`, `contracts.accountant`, and `vaultParams.minRate` set.
* The base-asset address for the chain exists in `config/assets/<chainId>.json` under `baseAssetSymbol` (or the per-chain `baseAssetOverrides` symbol).

Run the deployment:

```bash
VAULT_SYMBOL=nBASIS CHAIN_ID=1 PRIVATE_KEY=$DEPLOYER_KEY \
  forge script script/deploy/DeployBoringVaultSY.s.sol \
  --sig "runDirect()" --rpc-url $RPC --broadcast --ffi
```

The script supports only a direct broadcast from the deployer EOA.
The CREATE3 salt embeds the deployer address, and Safe batches cannot serialize CreateX deploys.

The script deploys:

1. A `BoringVaultSY` implementation with `(yieldToken, pauseController, baseAsset, minRate)`.
2. A `TransparentUpgradeableProxy` (OpenZeppelin 4.9.x) through CREATE3, with Pendle's canonical `ProxyAdmin` as the admin.

The Pendle checklist requires the OpenZeppelin 4.9.x proxy.
OpenZeppelin 5.x proxies deploy a fresh `ProxyAdmin` internally, which the Pendle checklist forbids.

Fixed parameters (from the Pendle checklist, hard-coded in the script):

| Parameter | Value |
|---|---|
| Proxy admin | `0xA28c08f165116587D4F3E708743B4dEe155c5E64` (Pendle canonical, every chain) |
| Owner / pause controller | `0x2aD631F72fB16d91c4953A7f4260A97C2fE2f31e` (default) |
| Owner / pause controller on Berachain (80094) | `0x830024529386a4A179BA6d1f31e8d49228674Cd0` |
| Token name | `"SY " + yieldToken.name()` |
| Token symbol | `"SY-" + yieldToken.symbol()` |

The script asserts after the deploy:

* The proxy owner equals the Pendle pause controller for the chain.
* The EIP-1967 admin slot holds Pendle's canonical `ProxyAdmin`.
* The `yieldToken` symbol equals `symbol` in the vault config.

Publish the new address on [Deployed contracts](https://app.plume.org/docs/developers/smart-contracts) through the docs team.
That section lists the current deployed instance (the nBASIS SY on Ethereum).

### Change the accountant

**Warning:** `setAccountant` is `onlyOwner`, and the owner is Pendle's pause controller — not the Nest Safe.
Nest cannot change the SY accountant alone.
Coordinate with Pendle for any accountant change, pause, unpause, or proxy upgrade.

`setAccountant(_accountant)` validates the new accountant before it accepts it:

* The address is not zero (`ZeroAddress`).
* `accountant.share()` equals the wrapped share token (`IncompatibleAccountant`).
* `getRateInQuoteSafe(asset)` returns a nonzero rate (`InvalidRate`) inside `[MIN_RATE, MAX_RATE]` (`RateOutOfBounds`).

### Test

```bash
forge test --mc BoringVaultSY -vv
```

The suite runs Pendle's vendored `SYTest` harness on an Ethereum fork.
Set `ETHEREUM_RPC_URL`. The `foundry.toml` file maps it to the `ethereum` fork alias.

## Mechanics reference

### 1:1 wrap

`_deposit`, `_redeem`, `_previewDeposit`, and `_previewRedeem` all return the input amount unchanged.
The SY token has the same decimals as the share token.
The share token is itself the yield-bearing unit, so no conversion happens on wrap or unwrap.

### Exchange rate

```
exchangeRate() = floor(1e18 * accountant.getRateInQuoteSafe(asset) / ONE_SHARE)
```

* `ONE_SHARE` = `10 ** shareToken.decimals()`, set in the constructor.
* The accountant returns the rate in base-asset units per share.
* The result is an 18-decimal fixed-point rate, as Pendle requires.

Every rate read passes `_getValidatedRate()`:

* A zero rate reverts with `InvalidRate`.
* A rate below `MIN_RATE` or above `MAX_RATE` reverts with `RateOutOfBounds`.

`MIN_RATE` and `MAX_RATE` are immutable:

* `MIN_RATE` comes from `vaultParams.minRate` in the vault config. The constructor requires it to be below `10 ** asset.decimals()` (one base-asset unit).
* `MAX_RATE = floor(uint128.max * ONE_SHARE / 1e18)`. This caps `exchangeRate()` at `uint128.max`, which Pendle's `_pyIndexCurrent()` requires when it stores the PY index.

### Storage and upgradability

The contract uses ERC-7201 namespaced storage (`plumenetwork.storage.BoringVaultSY`) for the accountant reference.
`asset`, `MIN_RATE`, `MAX_RATE`, `ONE_SHARE`, `yieldToken`, and `offchainRewardManager` are immutables.
A proxy upgrade to a new implementation, with new constructor arguments, is the only way to change them.
`version()` returns `"2.0.0"`.
Pendle's `ProxyAdmin` holds the upgrade authority.

### Merkl claim mechanics

`claimOffchainRewards(tokenReceiver, users, tokens, amounts, proofs)`:

1. Requires `msg.sender == offchainRewardManager`.
2. Requires every `users[i]` to be the SY contract itself.
3. Calls `claim(...)` on the Angle distributor (`0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae`, same address on every chain).
4. Measures the balance delta per token and transfers the claimed amount to `tokenReceiver`.

The vendored `MerklRewardAbstract__NoStorage` variant holds no storage, so it is safe under the SY proxy layout.

## Security

**Warning:** Pendle — not Nest — holds the SY pause, the SY ownership, and the SY upgrade authority.
Nest's emergency levers act on the accountant and the share token, one layer below.

| Control | Holder | Effect on the SY |
|---|---|---|
| `BoringVaultSY.pause()` | Pendle pause controller (owner) | Blocks SY mint, burn, and transfer. `deposit` and `redeem` stop. `exchangeRate()` still reads. |
| `NestAccountant.pause()` | Nest (via `RolesAuthority`) | `getRateInQuoteSafe` reverts, so `exchangeRate()` reverts. Pendle operations that read the rate fail. Wrapped share tokens stay in the SY contract. |
| SY rate bounds (`MIN_RATE` / `MAX_RATE`) | Immutable | `exchangeRate()` reverts with `RateOutOfBounds` on an extreme accountant rate. |
| Accountant update bounds | Nest | `allowedExchangeRateChangeUpper/Lower` plus `minimumUpdateDelayInSeconds` reject out-of-band rate posts upstream of the SY. See [Accountant fee spec](../../accountant/README.md). |
| Share-token controls (share freeze, blacklist) | Nest | Act on the share token in the SY contract and can stop redemptions. See [Deployment guide](../../../script/deploy/README.md) for the role wiring. |
| Proxy upgrade | Pendle `ProxyAdmin` | Pendle can replace the SY implementation. |

The accountant pause is Nest's fastest lever against the SY: it makes the SY rate unreadable without touching Pendle-owned controls.

## Code references

* `contracts/integrations/pendle/BoringVaultSY.sol` — the SY wrapper.
* `contracts/vendor/pendle/SYBaseUpgV2.sol` — vendored Pendle SY base (deposit/redeem entry points, pause).
* `contracts/vendor/pendle/MerklRewardAbstract__NoStorage.sol` — vendored Merkl claim helper.
* `contracts/vendor/pendle/interfaces/IAngleDistributor.sol` — distributor interface.
* `contracts/accountant/NestAccountant.sol` — rate source (`getRateInQuoteSafe`, `share`).
* `script/deploy/DeployBoringVaultSY.s.sol` — deploy script (Pendle checklist).
* `script/deployment-config/vaults/<SYMBOL>.json` — `contracts.share`, `contracts.accountant`, `vaultParams.minRate`.
* `config/assets/<chainId>.json` — base-asset addresses per chain.
* `test/BoringVaultSY.t.sol` — fork test suite on Pendle's `SYTest` harness.
