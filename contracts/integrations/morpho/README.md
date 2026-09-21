# Morpho Leverage Integration

[← Back to repository overview](../../../README.md)

This document describes the Morpho leveraged-loop integration for Nest vaults. A Morpho market uses the vault share token as collateral and the vault asset as the loan token. A user deposits the loan token into the vault, supplies the minted share tokens as collateral, and borrows more loan tokens in one atomic bundle. This document is for operators who deploy and run the integration, and for engineers who need the exact mechanics. For a step-by-step integrator guide with sequence diagrams, read [NestBundler.md](docs/NestBundler.md).

## Related documentation

- [NestBundler integrator guide](docs/NestBundler.md) — bundle API layers, approval matrices, sequence diagrams. This document does not repeat that content.
- [Deposit and redeem flow](../../README.md) — the vault deposit and redemption paths the bundles reuse.
- [Compliance flow](../../compliance/README.md) — predicate gating semantics.
- [Roles and authorities](../../auth/README.md) — complete role, holder, and capability reference.
- [Operators guide](../../operators/README.md) — full emergency-control catalog.
- [Deployment guide](../../../script/deploy/README.md) — general deploy and Safe-batch workflow.
- [Deployed contracts](https://app.plume.org/docs/developers/smart-contracts) — deployed addresses.
- Public protocol overview: [Nest protocol](https://app.plume.org/docs/developers/nest-protocol) and [liquidity and redemptions](https://app.plume.org/docs/about/liquidity-and-redemptions).

## User flow

### One-time setup

Each route needs different one-time permissions from the position owner:

| Route | Morpho authorization | ERC20 approvals | Vault operator |
|---|---|---|---|
| Direct execution via `Bundler3.multicall` | Authorize `NestAdapter` | Loan token and share token to `NestAdapter`, sized to the bundle pulls | `vault.setOperator(NEST_ADAPTER, true)` for the async-redeem leg |
| Async unloop via `NestUnlooper` | Authorize `NestAdapter` and `NestUnlooper` | None | `vault.setOperator(NEST_ADAPTER, true)` |
| Legacy AtomicQueue unloop | Authorize `NestAdapter` and `NestUnlooper` | Share token to `AtomicQueue` for the offer amount, and loan token to `NestAdapter` for the solve proceeds | Not required |

The async unloop route needs no ERC20 approvals because it never pulls owner wallet balances.

### Increase leverage

1. Build the bundle with `NestBundler.getBundleCalls(...)`, or with the bundle CLI (see below).
2. Send the approval transactions that `getBundleCalls` returns.
3. Execute `Bundler3.multicall(bundleCalls)`.

The bundle flash-borrows the loan token and deposits it into the vault. It supplies the minted share tokens as collateral and borrows against them to repay the flash loan. The deposit leg is compliance-gated, so the bundle carries an opaque compliance proof for the initiator.

### Decrease leverage — instant

**Warning:** The vault must hold enough instant-redeem liquidity for the redeemed shares. The build reverts otherwise.

Set `route.instantRedeem = true` and execute the same three steps. The flash loan is repaid from `instantRedeem` proceeds in the same transaction.

### Decrease leverage — async unloop request

1. The user calls `NestUnlooper.updateUnloopRequest(marketParams, leverageBps, minSharePriceE27, deadline)`.
2. A keeper calls `NestUnlooper.execute(marketParams, vault, teller, user, false)`.
3. The contract re-validates the request, builds the bundle, and executes it through `Bundler3`.
4. On success the stored request is deleted and `Executed` is emitted.

The contract enforces these rules at store time. Execution re-checks all of them except the collateral rule:

- `leverageBps` is scaled by 1e4. `10_000` means 1x. Zero means a full Morpho exit.
- The target leverage must be below the current leverage. The unlooper never levers up.
- The position must hold collateral and must not be underwater.
- `deadline` must not have passed.

The user cancels with `clearUnloopRequest(marketParams)`. An expired request stays stored but cannot execute.

### Decrease leverage — legacy AtomicQueue

1. The user creates an AtomicQueue redeem request (share token offered, loan token wanted).
2. A keeper calls `NestUnlooper.execute(marketParams, vault, teller, user, true)`.

The unlooper derives the repay and collateral-withdraw amounts from live `AtomicQueue.viewSolveMetaData(...)`. Only the insufficient-balance flag (bit value `4`) is tolerated, because the bundle withdraws the missing collateral before the solve. Any other flag reverts with `InvalidAtomicQueueRequest`.

## Operator procedures

### Deploy the chain-wide contracts

Prerequisites:

- `config/morpho/<chainId>.json` exists with at least `morpho` and `bundler3` set.
- `config/common/<chainId>.json` has `createx`.
- `script/deployment-config/common/<chainId>.json` has `complianceProxy` set to the V2 `ComplianceProxy` (the `NestBundler` deploy reverts without it; the V1 `predicateProxy` no longer works for the modern deposit routes).
- `PRIVATE_KEY` is set to the canonical deployer key. CREATE3 salts embed the deployer address.

**Warning:** `needsDeploy()` returns false for any address that already has code. A redeploy therefore silently no-ops: the script logs the existing address and deploys nothing. Set `nestAdapter`, `nestBundler`, and `nestUnlooper` to `address(0)` in `script/deployment-config/common/<chainId>.json` before you redeploy them. The compliance refactor changed all three, so a migration redeploys the full set.

1. Null the stale addresses in the common config if this is a redeploy.
2. Run the deploy:

```bash
CHAIN_ID=98866 forge script script/deploy/DeployMorpho.s.sol \
  --sig "runDirect()" --rpc-url $RPC --broadcast --ffi
```

3. Check the `Morpho Deployment Summary` log and the diff of `script/deployment-config/common/<chainId>.json`. The script writes the new addresses there.

Direct broadcast only. `runMsig` is not supported because the CREATE3 salts embed the deployer EOA and CreateX deploys do not serialize into a Safe batch. The script is chain-level: it reads no vault config, only `CHAIN_ID`.

Current CREATE3 salts and constructor wiring:

| Contract | Salt | Constructor inputs |
|---|---|---|
| `NestAdapter` | `NestAdapter-v3` | `bundler3`, `morpho`, `wrappedNative` |
| `NestBundler` | `NestBundler-v4` | `morpho`, `bundler3`, `nestAdapter`, `complianceProxy`, `legacyPredicateProxy`, `atomicSolver`, `atomicQueue` |
| `NestUnlooper` | `NestUnlooper-v5` | `deployer` (owner), common authority, `morpho`, `bundler3`, `nestAdapter`, `atomicSolver`, `atomicQueue` |

The bundle libraries are inlined into these non-upgradeable contracts. A library change ships only through a salt bump and a redeploy. Keep the `NestAdapter` salt stable when possible: a new adapter address forces every user to re-authorize it on Morpho.

### Wire the roles

Run the authority setup per leveraged vault:

```bash
VAULT_SYMBOL=nALPHA forge script script/setup/SetupAuthority.s.sol \
  --sig "runMsig()" --rpc-url $RPC --ffi
```

The grants come from the declarative files `config/authority/authority.json` (vault authority) and `config/authority/common-authority.json` (common authority):

| Authority | Grant | Purpose |
|---|---|---|
| Vault | `nestAdapter` gets role 5 (`SOLVER`) | Role 5 can call `fulfillRedeem(address,uint256)` on the vault |
| Vault | `nestAdapter` gets role 8 (`DEPOSITOR`) | Role 8 can call `deposit(uint256,address)` and `mint(uint256,address)` on the vault |
| Vault | `nestAdapter` gets role 16 (`COMPLIANCE_PROXY`) | Role 16 can call the consuming `genericUserCheck` overloads on the compliance proxy |
| Vault | `nestUnlooper` gets role 5 (`SOLVER`) | The unlooper is the initiator of async unloop bundles |
| Common | Role 14 (`KEEPER`) capability on `NestUnlooper.execute((address,address,address,address,uint256),address,address,address,bool)` | Only keepers execute unloops |
| Common | `CAN_SOLVE_ROLE` addresses get role 14 | Keeper addresses come from the vault config `roles` block |

`SetupAuthority` also points the unlooper's authority at the common `RolesAuthority` and calls `NestUnlooper.setVaultApproval(target, true)` for the vault and its legacy tellers. `execute` rejects any vault or teller that is not on this allowlist.

Migrate `NestUnlooper` ownership to the multisig afterwards with `script/setup/TransferOwnership.s.sol` (see [Deployment guide](../../../script/deploy/README.md) for the command).

### Onboard a market

Add the market to `config/morpho/<chainId>.json` under `markets.<vaultSymbol>`:

| Key | Meaning |
|---|---|
| `collateralToken` | Vault share token address |
| `loanToken` | Vault asset address |
| `oracle` | Morpho oracle for the pair |
| `irm` | Interest-rate model |
| `lltv` | Liquidation LTV, WAD-scaled |
| `legacyTeller` | Teller for legacy deposit and AtomicQueue routes |

The chain-level keys are `morpho`, `bundler3`, `wrappedNative`, `atomicSolver`, `atomicQueue`, and `legacyPredicateProxy`. The build reverts unless `collateralToken == vault.share()` and `loanToken == vault.asset()`, so a misconfigured market cannot produce calldata.

### Build bundles from the CLI

The `tools/morpho/*.ts` scripts build bundles off-chain and print the decoded calls plus the final `multicall` calldata:

| Command | Route |
|---|---|
| `pnpm bundle:increase-leverage` | Leverage up |
| `pnpm bundle:position` | Auto-select increase or decrease from the target position |
| `pnpm bundle:decrease-instant` | Deleverage via `instantRedeem` |
| `pnpm bundle:decrease-redeem` | Deleverage via async redeem |
| `pnpm bundle:validate-invariant` | Check the equity invariant without generating calldata |

Each script takes `--config <file>`. The `package.json` defaults point at sample fixtures in `tools/morpho/fixtures/`. Copy one and edit the addresses, `marketParams`, and `targetPosition` for a real run. With `rpcUrl` set, the script reads the live position and market state from the chain.

### Execute an unloop (keeper runtime)

1. Confirm the stored request with `getUnloopRequest(user, marketParams)`, or confirm the AtomicQueue request for the legacy route.
2. Preview the calls with `getAsyncBundleCalls(marketParams, vault, teller, user, useAtomicQueue)`.
3. Call `execute(marketParams, vault, teller, user, useAtomicQueue)` from a keeper address.

The build reverts with a typed error when the request is expired, underwater, fee-infeasible, or too large for the current liquidity. A modern-route failure can fall back to the legacy AtomicQueue route, which tolerates underwater positions.

## Mechanics reference

The [NestBundler integrator guide](docs/NestBundler.md) contains the API, flow diagrams, approval rules, execution order, and type reference.

The contracts enforce these additional rules:

- The market tokens must match `vault.share()` and `vault.asset()`.
- `Target` and `Delta` intents are mutually exclusive.
- The builder rejects withdrawals, repayments, or owner pulls that exceed their limits.
- Instant and modern asynchronous routes can divide a large deleverage into at most 32 flash-loan loops.
- Each loop checks the LLTV, available liquidity, redemption fees, and the aggregate minimum share price.
- The legacy AtomicQueue route uses one transaction and reverts when Morpho has insufficient flash-loan liquidity.

Every `NestAdapter` entrypoint accepts calls only from `Bundler3`. It checks the transient initiator and the applicable on-chain authority.

`NestUnlooper` stores requests by user and market. It checks the deadline, position health, target leverage, fees, and vault allowlist at execution.

## Security

- Every adapter entrypoint is reachable only through `Bundler3`. The vault and Morpho on-behalf entrypoints re-check the initiator's on-chain authority per selector. Slippage guards (`minSharePriceE27`, `maxSharePriceE27`, `maxRepaySharePriceE27`) are enforced at execution time, not only at build time.
- `NestUnlooper.execute` is keeper-gated (role 14 on the common authority) and target-gated by the `approvedVault` allowlist. `setVaultApproval(target, false)` is an owner-level per-vault kill switch for keeper unloops.
- The unlooper is deleverage-only by design. It stores only targets below the current leverage and never builds a releveraging request.
- `NestAccountant.pause()` stops the vault legs the modern routes use (`deposit`, `mint`, `instantRedeem`, `fulfillRedeem`). No modern-route leverage change can execute while the accountant is paused. The legacy routes do not call these vault functions. Use a share freeze to stop their collateral movement.
- **Warning:** `ComplianceProxy.pause()` does not stop the adapter deposit paths. `genericUserCheck` is not pause-gated, and the adapter deposits into the vault directly. To stop adapter deposits, pause the accountant, revoke the adapter's `COMPLIANCE_PROXY_ROLE`, or revoke its deposit role grants on the vault authority.
- A share freeze (`BlacklistHook.pause()`) or a per-address blacklist blocks share-token transfers. This halts collateral supply and withdrawal in the Morpho market for the affected scope, including liquidations that move the share token. See [Operators guide](../../operators/README.md) for the full emergency-control catalog.
- Redeploys are the only upgrade path for the bundle libraries. Review the salt bump and constructor wiring before broadcast. See the [security policy](https://app.plume.org/docs/security-and-compliance/security-policy) and [audits](https://app.plume.org/docs/security-and-compliance/audits).

## Code references

| Path | Content |
|---|---|
| `contracts/integrations/morpho/NestAdapter.sol` | Bundler3 adapter: vault actions on the vendored `MorphoAdapter.sol` base |
| `contracts/integrations/morpho/NestBundler.sol` | User-facing bundle builder and executor |
| `contracts/integrations/morpho/NestUnlooper.sol` | Keeper-only async deleverage |
| `contracts/integrations/morpho/libraries/BundleBuildLib.sol` | Bundle derivation and validation |
| `contracts/integrations/morpho/libraries/BundleCalldataLib.sol` | Call encoding, looped deleverage |
| `contracts/integrations/morpho/libraries/MorphoMarketLib.sol` | Leverage and position math |
| `contracts/integrations/morpho/libraries/NestShareMathLib.sol`, `libraries/NestVaultLib.sol` | Share-price conversions and vault read helpers |
| `contracts/integrations/morpho/types/BundleTypes.sol`, `types/Errors.sol` | Structs and typed errors |
| `script/deploy/DeployMorpho.s.sol` | Chain-wide deploy (CREATE3) |
| `script/setup/SetupAuthority.s.sol` | Role wiring and unlooper vault approvals |
| `config/morpho/<chainId>.json` | Chain and market onboarding config |
| `config/authority/authority.json`, `config/authority/common-authority.json` | Declarative role grants |
| `tools/morpho/*.ts` | Off-chain bundle CLI |
