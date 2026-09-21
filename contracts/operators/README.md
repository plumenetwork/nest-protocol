# Operators and Emergency Controls

[← Back to repository overview](../../README.md)

This document covers authority setup, ownership and timelock wiring, operator contracts, and emergency controls for the Nest vault system. The audience is protocol operators and security responders. For the complete access-control matrix, see [Roles and authorities](../auth/README.md). For a high-level protocol overview, see the [public architecture page](https://app.plume.org/docs/about/architecture).

## Related documentation

- [Security policy](https://app.plume.org/docs/security-and-compliance/security-policy) — public disclosure and response posture.
- [Roles and authorities](../auth/README.md) — canonical role, holder, capability, and public-capability reference.
- [Deployment guide](../../script/deploy/README.md) — deploy, upgrade, and role-revocation procedures.
- [Deployed contracts](https://app.plume.org/docs/developers/smart-contracts) — public address reference. Safe and timelock addresses live in `config/common/<chainId>.json` and `script/deployment-config/common/<chainId>.json`.
- [Compliance flow](../compliance/README.md) — predicate gating, blacklist, and seizure flows in detail.
- [Deposit and redeem flow](../README.md) — the vault functions that these roles protect.
- [oVault cross-chain flow](../integrations/ovault/README.md), [CCTP flow](../integrations/cctp/README.md), [Morpho integration](../integrations/morpho/README.md), [Pendle SY flow](../integrations/pendle/README.md) — flows that use the composer, relayer, keeper, and SY-owner controls.
- [Accountant fee spec](../accountant/README.md) — exchange-rate bounds and accountant pause behavior.

## Operator procedures

### Configure roles and capabilities

`script/setup/SetupAuthority.s.sol` applies `config/authority/authority.json` (vault authority) and `config/authority/common-authority.json` (common authority). It is idempotent: it skips grants and revokes that are already in the desired state. See [Roles and authorities](../auth/README.md) for the config schema and complete permission matrix.

1. Edit the authority JSON files, or edit the `roles` block of `script/deployment-config/vaults/<SYMBOL>.json`.
2. Run the script in the mode that matches current ownership:

```bash
# Deployer still owns the authorities — broadcast directly
VAULT_SYMBOL=nTEST forge script script/setup/SetupAuthority.s.sol --sig "runDirect()" --rpc-url $RPC --broadcast

# Safe owns the authorities — write a Safe batch only
VAULT_SYMBOL=nTEST forge script script/setup/SetupAuthority.s.sol --sig "runMsig()" --rpc-url $RPC --ffi

# Hybrid — broadcast what the deployer owns, queue the rest for the Safe
VAULT_SYMBOL=nTEST forge script script/setup/SetupAuthority.s.sol --sig "run()" --rpc-url $RPC --ffi --broadcast
```

3. For a Safe batch, propose and execute `script/output/msig/<chainId>-<SYMBOL>-SetupAuthority.json`.

Per-vault keeper assignment: add the keeper address to `roles.KEEPER_ROLE` in the vault config, then rerun `SetupAuthority`. The same pattern applies to `MANAGER_ROLE`, `UPDATE_EXCHANGE_RATE_ROLE`, and `CAN_SOLVE_ROLE`.

### Transfer ownership to the operational Safe

`script/setup/TransferOwnership.s.sol` moves ownership from the deployer EOA to a new owner, usually the operational Safe. It reads deployed addresses from `script/output/<SYMBOL>/<chainId>-<SYMBOL>.json`, not from the vault config.

1. Run phase 1 (deployer broadcast):

```bash
VAULT_SYMBOL=nFALCON NEW_OWNER=0x... forge script script/setup/TransferOwnership.s.sol \
  --sig "run()" --rpc-url $RPC --broadcast
# Optional: SCOPE=vault | common | all (default: all)
```

Phase 1 calls `transferOwnership` everywhere and migrates the deployer's roles to `NEW_OWNER`. `AuthUpgradeable` contracts only record a `pendingOwner`. `RolesAuthority` and `ProxyAdmin` contracts transfer immediately.

2. Execute phase 2: the new owner runs the generated Safe batch of `acceptOwnership()` calls from `script/output/msig/<chainId>-<SYMBOL>-TransferOwnership-AcceptOwnership.json`.

See the [deployment guide](../../script/deploy/README.md#ownership-transfer) for the full context in the deploy sequence.

### Deploy the two-tier timelock

**Warning:** the current `config/timelock/*.json` delays are test values: `protocol.delay` 30 seconds, `admin.delay` 60 seconds. The target production delays are 48 hours and 7 days. Do not route production ownership through the timelocks until the config carries production delays.

`script/deploy/DeployTimelock.s.sol` is chain-level. It reads only `CHAIN_ID`, `config/timelock/<chainId>.json`, and the chain common config. It never reads a vault config.

1. Set each tier's explicit `roles` in `config/timelock/<chainId>.json`. `admin.roles.admin` contains the admin timelock itself and the separate council Safe; `protocol.roles.admin` contains only the admin timelock. Council admins must differ from protocol proposers.
2. Run the deployment (direct broadcast only, because the CREATE3 salts embed the deployer):

```bash
CHAIN_ID=98866 forge script script/deploy/DeployTimelock.s.sol --sig "runDirect()" --rpc-url $RPC --broadcast
```

3. Confirm the recorded addresses in `script/deployment-config/common/<chainId>.json` (`adminTimelock`, `protocolTimelock`).

Timelock instances exist on Plume (98866) and on chains 1, 56, 480, 9745, and 43114, at one CREATE3 address per contract. The addresses live in `script/deployment-config/common/<chainId>.json` (`adminTimelock`, `protocolTimelock`).

**Reproducing the live addresses on a new chain.** A CREATE3 address depends only on the CreateX instance, the deployer EOA and the raw salt, so the same pair lands on the same address everywhere as long as those three match. The config is an object keyed by pair name: `{"general": {...}, "veto": {...}, "test": {...}}`. Each entry defines its own delays, roles, salts, and expected addresses. Pin these fields per pair in `config/timelock/<chainId>.json`:

- Each pair has `admin` and `protocol` objects, both with `address`, `salt`, `delay`, and `roles`.
- `address` pins the expected CREATE3 address, including before deployment. The script computes it before broadcast and rejects mismatches. `--sig "check()"` runs only preflight.
- `salt` is the raw deployer-bound CREATE3 salt; all tiers require it explicitly. The live general and veto pairs use different salts. See `config/timelock/5042.json` for the pinned values.
- `delay` is the constructor delay in seconds. Existing on-chain delays are preserved on reruns.
- `roles` contains explicit `admin`, `executor`, `proposer`, and `canceller` arrays. No role defaults are inferred. Zero in `executor` allows public execution; an empty executor list grants execution to nobody. Zero does not make proposer or canceller roles public.
- Proposers and cancellers are independent. A proposer only receives cancellation rights if also listed in `canceller`. Both tiers use temporary deployer administration to establish their configured roles, then remove that temporary access.
- Top-level keys identify each pair. `general` updates the chain common config; `veto` and `test` are independent named pairs. Named pair addresses live only in `config/timelock/<chainId>.json`; deployment checks these pinned addresses against CREATE3 and on-chain code. Object key order does not select the general pair.

Select one or more configured pairs with `TIMELOCK_PAIRS` (comma-separated, no spaces). Omit it to deploy all entries; unknown or repeated names fail before broadcast. `general` is optional. The same selection applies to `check()`.

```bash
# One pair
CHAIN_ID=5042 TIMELOCK_PAIRS=veto forge script script/deploy/DeployTimelock.s.sol --sig "runDirect()" --rpc-url "$ARC_RPC_URL" --broadcast
# Two pairs
CHAIN_ID=5042 TIMELOCK_PAIRS=general,veto forge script script/deploy/DeployTimelock.s.sol --sig "runDirect()" --rpc-url "$ARC_RPC_URL" --broadcast
# All configured pairs
CHAIN_ID=5042 forge script script/deploy/DeployTimelock.s.sol --sig "runDirect()" --rpc-url "$ARC_RPC_URL" --broadcast
```

Every pair is looked up at its computed CREATE3 addresses before deployment. Reruns reuse existing contracts, finish any pending deployer-admin handoff, and leave governance-updated delays alone. Partial runs use the same canonical config; there is no separate named-pair deployment record.

Vault ownership is configured by the top-level `owner` address in `script/deployment-config/vaults/<symbol>.json`. `roles` contains only RolesAuthority membership arrays. nBASIS's owner is the veto protocol timelock; nTEST retains its explicit deployer owner. No pair selector is needed. Every vault must explicitly set a non-zero `owner`; loading fails when it is missing or zero. Neither `common.protocolTimelock` nor a legacy `roles.owner` supplies a fallback. `commonOverrides` still controls per-vault common addresses when needed. Deploying a pair does not transfer existing vault ownership.

The artifact bundle exposes named definitions as `config.timelockPairs`. `config.timelock` remains the flat `general` definition per chain for compatibility with existing Mission Control consumers.

The [deployment inventory](../../docs/timelock-deployment-inventory.json) records observed code, live delays, and AT-to-PT admin linkage at fixed blocks across all nine EVM chains. Config delays remain bootstrap inputs, not a claim about current on-chain delays. General is deployed on Ethereum, BNB Chain, World Chain, Base, Plasma, Avalanche, and Plume; veto on Ethereum, BNB Chain, World Chain, Plasma, and Plume; test on Plume. None of these canonical addresses has code on Arbitrum or Arc at the recorded blocks. Arc retains all three definitions as deployment targets. World Chain's veto executors differ from the other veto pairs: both tiers have open execution only.

When the Nest CreateX instance (`common.createx`) has no code on the target chain, the script first reproduces it through the Arachnid CREATE2 factory from `config/createx/` (same salt and init code, same address). Both Safes referenced as role holders should already exist at their canonical addresses on the target chain; the preflight warns about role holders without code and refuses to run when a council admin has none.

```bash
# preflight only: computed vs expected addresses, no broadcast
CHAIN_ID=5042 forge script script/deploy/DeployTimelock.s.sol --sig "check()" --rpc-url $ARC_RPC_URL
```

### Route ownership through the protocol timelock

**Warning:** Verify the live timelock delay before transferring production ownership. Complete the production-delay update first. Read each target's current owner to select the transfer mode.

When `NEW_OWNER` is the protocol timelock, `TransferOwnership` automatically uses timelock mode. It detects `getMinDelay()`.

Set `NEW_OWNER_IS_TIMELOCK=true|false` to override the detection. In timelock mode:

1. Every `transferOwnership` routes directly (deployer-owned targets) or into a Safe batch (Safe-owned targets).
2. The two-step `acceptOwnership()` calls must run as the timelock. The script emits a `TransferOwnership-Schedule` batch and a `TransferOwnership-Execute` batch. The Safe signs the schedule batch now and runs the execute batch after the delay.
3. Operational roles migrate to the operational Safe, never to the timelock. Override the target with `ROLE_MIGRATION_TARGET`.

### Revoke a role

Follow the [role-revocation section of the deployment guide](../../script/deploy/README.md#revoking-roles). It covers the revoke config, automatic revocation, and manual `cast` commands.

`SetupAuthority` applies the declarative `revokeCapabilities` and `revokeRoleAssignments` blocks in the authority config files.

## Mechanics reference

### Ownership model

- Solmate `Auth` contracts (`RolesAuthority`, `OperatorRegistry`, `BlacklistHook`, `NestShareSeizer`, the legacy BoringVault share) transfer ownership in one step.
- `AuthUpgradeable` contracts use a two-step transfer. `transferOwnership` sets `pendingOwner`. The new owner calls `acceptOwnership`.
- Each transparent proxy has a `ProxyAdmin` (OZ `Ownable`, one step) that controls upgrades.
- The operational Safe per chain is `config/common/<chainId>.json` key `.common.multisig`.

### Two-tier timelock

`DeployTimelock.s.sol` deploys two OZ `TimelockController` instances per chain:

| Tier | Delay (config key) | Controlled by | Purpose |
|---|---|---|---|
| Protocol timelock (PT) | `protocol.delay` (test 30 s, production target 48 h) | Operational Safe is proposer and canceller, with open execution | Future owner of the privileged surfaces |
| Admin timelock (AT) | `admin.delay` (test 60 s, production target 7 d) | Separate council Safe is admin, proposer, and canceller, with open execution | Sole `DEFAULT_ADMIN` of PT, recovery and role-granting tier |

Key invariants, enforced by the script:

- `admin.delay > protocol.delay`. On an admin-tier compromise, the operational Safe schedules a defensive ownership transfer through PT and executes it before the attacker's AT operation lands. The gap is the detect-and-react budget.
- PT self-admin is stripped. Only AT can change PT roles. The operational Safe cannot remove the admin tier through the shorter delay.
- The deployer holds `DEFAULT_ADMIN` on PT only during deployment and then renounces it. Post-conditions verify this state.
- Accepted assumption: PT cancellers are the only defense that prevents a malicious operation after a single operational-Safe compromise. The current configs give protocol cancellation rights only to their main proposers; there are no additional partner cancellers.

### Operator contracts

- `OperatorRegistry` provides global ERC-7540 operator approvals. `setOperator` is public. `authorizeOperator` is owner-only under the current config.
- `NestVaultRedeemOperator` provides permissioned fulfill-and-redeem functions. Role 14 can call the redeem, fulfill, batch, and authorization functions.
- Each controller can set a per-vault receiver with `setReceiver`. Assets go to the controller by default.

## Security

### Emergency control surface

| Control | Call | Who can trigger | Effect | Residual activity | Reversal |
|---|---|---|---|---|---|
| Accountant pause | `NestAccountant.pause()` (also hub/spoke variants) | role 6, owner | Blocks deposit/mint, `instantRedeem`, `fulfillRedeem`, `claimFees`, and safe rate reads | Share transfers, OFT sends, and `requestRedeem` continue. `updateExchangeRate` continues. | `unpause()` — role 0, owner |
| Share freeze | `BlacklistHook.pause()` | role 6, owner | Blocks share transfers, burns, OFT sends, `requestRedeem`, and share-based redeem paths | Mints skip the hook. Pair with the accountant pause to stop deposits. | `unpause()` — role 0, owner |
| Compliance proxy pause | `NestVaultPredicateProxy.pause()` (V1) or `ComplianceProxy.pause()` (V2) | role 6, owner on the selected proxy's authority | Stops that proxy's deposit/mint routes; V2 also stops proxied request/instant-redemption routes | Adapter checks and direct vault routes continue. Pause each proxy used by the affected routes. | `unpause()` — role 0, owner |
| Address blacklist | `BlacklistHook.blacklist(address)` | role 15 (seizer contract), owner | Target cannot transfer, bridge, `requestRedeem`, or use share-based redeem paths | Incoming transfers continue. Deposit/mint stays possible unless the accountant is paused. | `unblacklist(address)` — roles 0 and 15, owner |
| Bridge-send disable | `RolesAuthority.setPublicCapability(vault, send-selector, false)` | authority owner (Safe) | Stops new `send` on the selected vault | In-flight LayerZero messages stay pending. This is a broad authority change. | Same call with `true` |
| Compose block | `NestVaultComposer.blockCompose(bytes32 guid)` | role 0, owner | Blocks one LayerZero compose GUID | Other compose messages are unaffected | `unblockCompose(bytes32)` — role 0, owner |
| CCTP composer disable | `NestCCTPRelayer.setComposer(address, false)` | owner (no role grant in config) | Rejects that composer's hook data; relays refund USDC to the source chain | In-flight burns can still relay as refunds | `setComposer(address, true)` |
| Share seizure | `NestShareSeizer.seize(...)` / `seizeAndRedeem(...)` | role 0 (common authority), owner | Moves shares to a recovery address, or burns them and pays assets out | Post-incident tool, not a pause | — |
| Pendle SY pause | `BoringVaultSY.pause()` | SY owner (`onlyOwner`) | Blocks Pendle SY wrap operations | — | `unpause()` — SY owner |

The accountant also carries a passive rate circuit breaker: `allowedExchangeRateChangeUpper`/`Lower` and `minimumUpdateDelayInSeconds` reject out-of-band `updateExchangeRate` calls. See [Accountant fee spec](../accountant/README.md).

### Off-chain levers

- Disable the Solana deposit action endpoints in the Nest APIs. Ask partners to disable theirs.
- Stop the issuance of predicate messages. Pair this with the predicate pause. Previously issued messages stay valid until expiry.
- Disable adapter and bundler partner routes. The predicate pause does not stop all adapter deposits.
- From the Safe, revoke a role or disable a capability per selector. Only the authority owner can do this.
- Notify bridge, DEX, and lending partners before a share freeze. The freeze breaks collateral transferability.

### Upgrade safety

**Warning:** A bad upgrade can remove or break the pause path. Thus, a pause is not a sufficient upgrade control.

Before execution, verify the storage layout and the exact bytecode of the new implementation. The `ProxyAdmin` or protocol timelock executes the upgrade.

## Code references

- `contracts/auth/README.md` — canonical authorization model and complete configured role table.
- `script/lib/Constants.sol` — role constants.
- `config/authority/authority.json`, `config/authority/common-authority.json` — capability and role wiring.
- `script/setup/SetupAuthority.s.sol` — applies the authority config with add-then-revoke ordering.
- `script/setup/TransferOwnership.s.sol` — two-phase and timelock-mode ownership transfer.
- `script/deploy/DeployTimelock.s.sol`, `config/timelock/<chainId>.json` — two-tier timelock deployment.
- `script/deploy/DeployOperator.s.sol` — deploys `OperatorRegistry` and `NestVaultRedeemOperator`.
- `contracts/auth/AuthUpgradeable.sol` — two-step ownable auth base with owner bypass.
- `contracts/operators/` — operator contracts.
- `contracts/compliance/` — `NestVaultPredicateProxy`, `BlacklistHook`, `NestShareSeizer`.
- `script/deploy/README.md` — [role reference](../../script/deploy/README.md#role-reference) and [revocation recipes](../../script/deploy/README.md#revoking-roles).
