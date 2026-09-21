# Compliance Flow

[← Back to repository overview](../../README.md)

This document describes KYC deposit gates, transfer restrictions, and share seizure. It is the operational reference for engineers and operators.

Two KYC stacks exist during the Predicate V1 → V2 migration (PDE-327):

- **V1:** `NestVaultPredicateProxy` validates a per-transaction Predicate attestation, then deposits into the vault.
- **V2:** `ComplianceProxy` + `IComplianceHook` validate provider-agnostic compliance data.

## Related documentation

Public policy and overview:

- [AML](https://app.plume.org/docs/security-and-compliance/aml) — the AML program.
- [Geographic restrictions](https://app.plume.org/docs/security-and-compliance/geographic-restrictions) — restricted jurisdictions.
- [Security policy](https://app.plume.org/docs/security-and-compliance/security-policy) — public security posture.
- [Flow of funds](https://app.plume.org/docs/security-and-compliance/flow-of-funds) — where user assets move.
- [Smart contracts](https://app.plume.org/docs/developers/smart-contracts) — public contract addresses.

Repo:

- [`contracts/compliance/docs/ComplianceProxy.md`](docs/ComplianceProxy.md) — V2 architecture reference (design rules, payloads, V2 deployment wiring).
- [Deposit and redeem flow](../README.md) — the vault flows that these controls gate.
- [Roles and authorities](../auth/README.md) — complete role, holder, and capability reference.
- [Operators guide](../operators/README.md) — full emergency-control table.
- [Morpho integration](../integrations/morpho/README.md) — the `NestAdapter` paths that check the predicate but bypass the proxy.
- [Deployment guide](../../script/deploy/README.md) — full deploy procedure and authority semantics.

## User flow

### KYC-gated deposit (V1)

The predicate proxy is not an on-chain allowlist. Each deposit transaction needs a fresh attestation from the Predicate API. The flow for an EVM depositor:

1. The client sends a task request to the Predicate API (`POST https://api.predicate.io/v1/task`). The payload contains `from` (the user), `chain_id`, `to` (the predicate proxy address), `data` (the ABI-encoded canonical payload `deposit()`), and `msg_value: "0"`. See `tasks/evm/deposit.ts` for the reference client.
2. The API screens the user and returns `is_compliant` plus the signed task fields: `task_id`, `expiry_block`, `signers`, `signature`.
3. The client packs these fields into a `PredicateMessage` struct.
4. The user approves the predicate proxy to spend the deposit asset. The `depositWithPermit2` variant replaces this approval with a Permit2 signature.
5. The user calls `deposit(asset, amount, recipient, vault, predicateMessage)` on `NestVaultPredicateProxy`.
6. The proxy validates the message against the Predicate service manager. A message that fails validation reverts with `NestPredicateProxyPredicateUnauthorizedTransaction`.
7. The proxy pulls the assets from the user, calls `vault.deposit`, and the vault mints shares to the recipient. The proxy emits a `Deposit` event.

The `mint` entrypoint works the same way but takes a share amount and uses `vault.previewMint` to compute the required assets.

In the V1 flow, cross-chain and non-EVM depositors do not call the proxy directly. The vault composer (role 12) calls the restricted `deposit(..., bytes32 _depositor, ...)` and `mint(..., bytes32 _depositor, ...)` overloads. The `bytes32` depositor field carries a non-EVM address, and the Predicate API issues the attestation against the payload `deposit(bytes32)` for that depositor.

The gate holds because `vault.deposit` and `vault.mint` are not public when a predicate proxy is configured. Only role 7 (`PREDICATE_PROXY_ROLE`, held by the proxy) and role 8 (`DEPOSITOR_ROLE`) can call them (`config/authority/authority.json`).

For V2, the current composer calls `ComplianceProxy.depositOnBehalf` with opaque `bytes complianceData`. See the [V2 API reference](docs/ComplianceProxy.md#flows) for payloads, approvals, and entrypoints.

### Transfer restrictions

Every share movement with a non-zero `from` address passes `BlacklistHook.beforeTransfer(from)`. The share token (`NestShareOFT`) enforces this in its `_update` override. The hook reverts when the hook is paused or when `from` is blacklisted. This blocks:

- share transfers,
- share burns, including the burn side of an OFT cross-chain send,
- `requestRedeem` (the vault pulls shares from the owner) and every share-moving redeem path.

Mints pass, because a mint has `from == address(0)`.

## Operator procedures

### Deploy the V1 compliance contracts

`DeployAndSetup` deploys the compliance contracts as shared ("common") contracts, one set per chain. The steps that matter here:

| `STEPS` value | Compliance effect |
|---|---|
| `deploy` | Deploys `NestVaultPredicateProxy` when `compliance.v1.policyID` is set, deploys `BlacklistHook`, and calls `setBeforeTransferHook(blacklistHook)` |
| `operator` | Deploys `NestShareSeizer` |
| `authority` | Grants the roles and capabilities listed in the mechanics section |

When the live share implementation does not expose `hook()` yet, the `deploy` step defers `setBeforeTransferHook` to `Upgrade.s.sol`.

Run the full pipeline, or select steps:

```bash
STEPS=deploy,operator,authority forge script script/deploy/DeployAndSetup.s.sol \
  --sig "run(string)" "nTEST" \
  --rpc-url $PLUME_RPC_URL \
  --ffi \
  --broadcast
```

See [Deployment guide](../../script/deploy/README.md) for modes (direct, hybrid, Safe), simulation, and ownership transfer. `TransferOwnership` moves the predicate proxy, the blacklist hook, and the seizer to the multisig.

### Configure the Predicate policy

| Config path | Key | Meaning |
|---|---|---|
| `config/compliance/<chainId>.json` | `.v1.serviceManager` | Predicate service-manager address, passed to `initialize` |
| `config/compliance/<chainId>.json` | `.v1.defaultPolicyID` | Chain default policy ID (`ConfigReader` loads this reference value, but no deploy script uses it) |
| `script/deployment-config/vaults/<symbol>.json` | `.compliance.v1.policyID` | Policy ID used at proxy deployment |
| `config/compliance/<chainId>.json` | `.v2.predicateRegistry`, `.v2.apiChain` | Shared V2 registry address and Predicate API chain name |
| `script/deployment-config/vaults/<symbol>.json` | `.compliance.v2.verificationHash` | V2 dashboard policy identifier; empty until configured |

V2 deployed addresses and activation settings live in `script/deployment-config/compliance/<chainId>-<symbol>.json`.

The proxy is one shared contract per chain, so it stores one policy ID. Every vault config on a chain must carry the same `compliance.v1.policyID`.

To change the live policy, call `setPolicy(string)` on the proxy. The call is auth-gated. Under the current authority config, only the contract owner can call it. `setPredicateManager(address)` follows the same rule.

### Run a gated test deposit

**Warning:** This task moves real funds on mainnet. Use a small amount.

1. Set `PREDICATE_API_KEY` in the environment.
2. Run the Hardhat task:

```bash
npx hardhat nest:predicate:deposit \
  --vault <vault-address> \
  --amount 1.0 \
  --network plumephoenix
```

The task fetches the attestation, approves the proxy, deposits, and prints the minted shares. Pass `--predicate-proxy` to override the default proxy address. Current addresses are in `script/deployment-config/common/<chainId>.json` and on [Deployed contracts](https://app.plume.org/docs/developers/smart-contracts).

### Pause and unpause

**Warning:** Read the Security section before you pause. Each pause has residual activity that needs paired actions.

- `NestVaultPredicateProxy.pause()` — role 6 (`PAUSER_ROLE`). `unpause()` — role 0 (`OWNER_ROLE`).
- `BlacklistHook.pause()` — role 6. `unpause()` — role 0. Pausers cannot unpause. The old role-6 `unpause` grant is revoked.

### Blacklist and unblacklist an address

- `BlacklistHook.blacklist(address)` and `unblacklist(address)` are separate one-way setters with separate selectors, so grants can be asymmetric.
- Live grants (`config/authority/common-authority.json`): the seizer contract (role 15) holds `blacklist` and `unblacklist` for its auto-toggle. Role 0 holds `unblacklist`. The contract owner (multisig) can call both.
- **Planned, not live:** a keeper grant for the one-way `blacklist(address)` setter, with `unblacklist` kept owner-only. No such grant exists in the config today.

### Seize shares

Seizure is a post-incident and compliance tool. The approval process is off-chain: the owner Safe decides and executes the seizure. On-chain, the common authority grants `seize` and `seizeAndRedeem` to role 0 (`OWNER_ROLE`).

1. Confirm the wiring: call `canSeize(share)` on `NestShareSeizer`. It returns `true` only when the hook is set and the seizer can call `blacklist`, `enter`, and `exit`.
2. Queue the call through the Safe:
   - `seize(share, from, to, shareAmount)` moves shares from `from` to a recovery address.
   - `seizeAndRedeem(vault, from, to, shareAmount)` burns the shares and pays out assets at the current vault rate.
3. Verify the `SharesSeized` or `SharesSeizedAndRedeemed` event and the final blacklist state of `from`.

## Mechanics reference

### V1 predicate proxy

- The proxy encodes a canonical payload and hashes it in `_authorizeTransaction`. The payload binds the attestation to the policy and sender.
- Public entrypoints use `deposit()`. Restricted overloads use `deposit(bytes32 depositor)`.
- `mint` authorizes against the same `deposit()` payload as `deposit`.
- `depositWithPermit2` pulls tokens through Permit2 `SignatureTransfer` and checks the received balance, which protects against fee-on-transfer shortfalls.
- `genericUserCheckPredicate(address|bytes32)` validates the `accessCheck(address)` / `accessCheck(bytes32)` payload without token movement. It has no pause modifier. The adapter uses the separate legacy teller proxy for V1 teller deposits; modern vault routes use V2 `genericUserCheck`.
- The proxy resets the vault allowance to zero after each deposit.
- The proxy is upgradeable through `TransparentUpgradeableProxy`. `Upgrade.s.sol` with `CONTRACT=common` covers it.

### Blacklist hook

- `NestShareOFT.setBeforeTransferHook(hook)` installs the hook. The setter is auth-gated. A zero-address hook disables the check.
- The hook checks only `from`. The hook does not block incoming transfers to a blacklisted address.
- State is two flags: `isPaused` (global) and `isBlacklisted[account]` (per address).

### Seizer

- `seize`: temporarily unblacklists `from`, burns the shares from `from` via `share.exit` (zero assets), mints the same amount to `to` via `share.enter`, then re-blacklists `from`. No allowance is needed.
- `seizeAndRedeem`: computes assets with `vault.convertToAssets(shareAmount)`, then `share.exit(to, asset, assetAmount, from, shareAmount)` burns the shares and pays the assets to `to`.
- The seizer lifts the blacklist during the seizure, so the hook check passes. It always re-blacklists the target after the seizure, whatever the prior state.

### Role and capability wiring

Vault authority (`config/authority/authority.json`):

| Role | Holder | Capability |
|---|---|---|
| 7 (`PREDICATE_PROXY_ROLE`) | `predicateProxy` | `vault.deposit`, `vault.mint` |
| 15 (`SEIZER_ROLE`) | `shareSeizer` | `share.enter`, `share.exit` |
| — (public) | everyone, only when no predicate proxy is configured | `vault.deposit`, `vault.mint` |

Common authority (`config/authority/common-authority.json`):

| Role | Holder | Capability |
|---|---|---|
| 12 (`COMPOSER_ROLE`) | `composer` | restricted `deposit(bytes32)` / `mint(bytes32)` overloads on `predicateProxy` |
| 6 (`PAUSER_ROLE`) | pauser accounts | `pause()` on `predicateProxy` and `blacklistHook` |
| 0 (`OWNER_ROLE`) | owner accounts | `unpause()` on both, `blacklistHook.unblacklist`, `shareSeizer.seize` / `seizeAndRedeem` |
| 15 (`SEIZER_ROLE`) | `shareSeizer` | `blacklistHook.blacklist`, `blacklistHook.unblacklist` |

`script/lib/Constants.sol` defines role numbers 0 through 16. Role 9
(`COMPLIANCE_HOOK_ROLE`) is reserved for V2 compliance proxies calling the Predicate V2 hook;
role 16 (`COMPLIANCE_PROXY_ROLE`) restricts consuming standalone user checks to the Nest adapter.

## Security

Emergency capabilities and their limits. Pair the levers. No lever is complete alone.

### Compliance proxy pause scope

`NestVaultPredicateProxy.pause()` stops V1 proxy deposit/mint entrypoints, including the overloads used by V1 composers.
`ComplianceProxy.pause()` stops V2 proxy deposit/mint and proxied request/instant-redemption entrypoints, including deposits from the current composer.
Each pause affects only the selected proxy. Neither proxy's standalone user checks are pause-gated.

Modern `NestAdapter` routes call V2 `genericUserCheck`, then call the vault directly. A proxy pause therefore leaves these routes available.
See [Morpho integration](../integrations/morpho/README.md#security) for the accountant and role controls that stop adapter deposits.

**Warning:** Pair a compliance proxy pause with an off-chain stop. Disable the deposit API routes and ask partners to disable theirs.

Also stop issuing new predicate messages. Previously issued messages stay valid until expiry.

### Share freeze scope

`BlacklistHook.pause()` freezes all outgoing share movement: transfers, burns, OFT sends, `requestRedeem`, and DEX or lending collateral movement. Residuals:

- The freeze does not block mints (`from == address(0)`). Pair it with an accountant pause to stop deposits.
- The freeze does not recall in-flight LayerZero messages.

**Warning:** Notify bridge, DEX, and lending partners before a share freeze. Collateral transferability breaks for every holder.

### Blacklist scope

A blacklisted address cannot transfer, bridge, request a redeem, or move shares as collateral. Incoming transfers can still arrive.

The address can also deposit for new shares unless the deposit path is stopped. The one-way keeper `blacklist` grant is not live.

The owner Safe is the fast path to blacklist one address. A seizure also blacklists the address as a side effect.

### Seizure posture

Seizure is owner-gated on-chain and Safe-approved off-chain. It is a post-incident and regulatory-compliance tool, not a routine operation. `canSeize` gives a non-mutating preflight. For the policy context, see the public [AML](https://app.plume.org/docs/security-and-compliance/aml) and [geographic restrictions](https://app.plume.org/docs/security-and-compliance/geographic-restrictions) pages.

## Code references

| Path | Content |
|---|---|
| `contracts/compliance/NestVaultPredicateProxy.sol` | V1 predicate proxy |
| `contracts/compliance/ComplianceProxy.sol` | V2 compliance proxy |
| `contracts/compliance/hooks/PredicateV2Hook.sol` | V2 Predicate validator hook |
| `contracts/compliance/hooks/BlacklistHook.sol` | Before-transfer pause + blacklist hook |
| `contracts/compliance/NestShareSeizer.sol` | Share seizure tool |
| `contracts/compliance/docs/ComplianceProxy.md` | V2 architecture reference |
| `contracts/compliance/interfaces/` | `IComplianceProxy`, `IComplianceHook`, `INestVaultPredicateProxy`, `ITellerPredicateProxy` |
| `contracts/NestShareOFT.sol` | Hook installation (`setBeforeTransferHook`) and `_update` enforcement |
| `tasks/evm/deposit.ts` | Reference Predicate API client + gated deposit task |
| `script/deploy/DeployAndSetup.s.sol`, `script/deploy/DeployVault.s.sol`, `script/deploy/DeployOperator.s.sol` | Deployment of proxy, hook, seizer |
| `config/common/<chainId>.json`, `script/deployment-config/vaults/<symbol>.json` | Predicate config keys |
| `config/authority/authority.json`, `config/authority/common-authority.json` | Role and capability wiring |
| `test/ComplianceProxy.t.sol`, `test/PredicateV2Hook.t.sol`, `test/NestShareSeizer.t.sol`, `test/NestVaultPredicateProxyFork.t.sol` | Test coverage |
