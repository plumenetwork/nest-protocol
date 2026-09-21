# ComplianceProxy & Predicate V2 Hook

Architecture reference for `ComplianceProxy`. For the user-facing compliance flow and operator procedures, see [contracts/compliance/README.md](../README.md).

Provider-agnostic compliance layer for NestVault, built for the Predicate V1 → V2 migration
(PDE-327). The V1 stack (`NestVaultPredicateProxy` + `@predicate/contracts` v1.0.12) stays deployed
and untouched for the coexistence window; this stack runs in parallel at new addresses.

## Architecture

```
user / composer / integrator
        │  bytes complianceData
        ▼
ComplianceProxy ─────────────► IComplianceHook
  owns canonical payloads        checkCompliance(sender, payload, data)
  owns token flows
        │                                  │
        ▼                                  ▼
    NestVault                    PredicateV2Hook (RolesAuthority gated)
                                   decodes Attestation, builds Statement,
                                   validates via Predicate V2 Registry
```

Three design rules:

1. **Compliance data is opaque to the proxy.** Only the hook knows the provider's proof format.
   Upstream transports such as the CCTP relayer's `oftCmd` and the compliance proxy forward those
   bytes unchanged.
2. **The proxy owns the canonical policy payloads.** Direct flows use `deposit()`; on-behalf flows
   use `deposit(bytes32)`. The latter payload identifies the original depositor so the policy can
   screen both the executing sender and the original sender through the standard hook check.
3. **The hook is caller-gated.** Predicate's Registry marks attestation UUIDs as **spent** on
   successful validation. An open `checkCompliance` would let anyone replay an in-flight
   `(sender, payload, attestation)` tuple observed in the mempool and burn the UUID before the
   real transaction lands (a griefing DoS that V1 never allowed — V1 entrypoints hardcode
   `msg.sender`). The Predicate hook check is therefore `requiresAuth`, with a dedicated
   RolesAuthority role granted only to the compliance proxy.

## Contracts

| Contract | Kind | Purpose |
| --- | --- | --- |
| [`ComplianceProxy`](../ComplianceProxy.sol) | upgradeable (Auth + Pausable + transient reentrancy guard) | Typed deposit/mint/redeem entry, token flows, canonical payloads |
| [`PredicateV2Hook`](../hooks/PredicateV2Hook.sol) | upgradeable (ERC-7201 + `AuthUpgradeable`) | Predicate V2 `Attestation` validation against the Registry |
| [`IComplianceHook`](../interfaces/IComplianceHook.sol) | interface | Validator seam for direct and on-behalf operations; provider proof encoding remains opaque |
| [`IComplianceProxy`](../interfaces/IComplianceProxy.sol) | interface | Compiler-checked public surface of `ComplianceProxy` |
| [`contracts/vendor/predicate-v2/`](../../vendor/predicate-v2/README.md) | vendored | Predicate V2 client sources, pinned to npm v2.2.3 / upstream `6130aa4c` |

## Flows

### Deposit / mint (proxy-aware token handling)

Mirrors `NestVaultPredicateProxy` token handling: pull assets from sender → approve vault →
`vault.deposit` → reset allowance → emit `Deposit` (identical event shape, so indexers reuse the
V1 handler). Mint entrypoints use `previewMint` to calculate the assets before depositing them,
return the shares actually minted, and revert if that amount is below the requested shares.
`depositWithPermit2` and `depositOnBehalfWithPermit2` share the Permit2 pull + received-balance
check. In both Permit2 deposit paths, `msg.sender` owns and signs
for the supplied assets. Every state-changing user entrypoint is authority-gated; deployment grants
the action selectors public capabilities by default so dynamic relayers do not need a role, while
governance can revoke any selector later. Every path calls `checkCompliance`; on-behalf paths pass
the `deposit(bytes32)` payload so the policy can screen `msg.sender` and the encoded original depositor.
`mintOnBehalf` is public by default and retains a COMPOSER_ROLE grant so
configured composers remain authorized if governance later revokes its public capability.

### Redeem family

`requestRedeem` and `instantRedeem` first pull shares from `msg.sender` into the proxy, approve the
vault for the exact share amount, and call the standard vault entrypoint with
`owner = address(this)`. The Permit2 variants use the vault's canonical Permit2 contract with a
signature authorizing the compliance proxy as spender for the first transfer, then follow the same
standard vault path. The vault consumes the proxy's share allowance, and the proxy explicitly clears
it after the call. Instant-redemption assets still travel directly from the vault to the requested
receiver. Consequences:

- standard calls require share approval to the **proxy**, not the vault;
- users do not grant the upgradeable proxy a standing ERC-7540 operator approval;
- vault events report the proxy as owner, while proxy `RedeemRequest` and `InstantRedeem` events
  preserve the original owner and controller or receiver for indexers;
- the proxy still needs the vault capability required to call the standard redeem entrypoints.

`updateRedeem`, `withdraw`, and `redeem` are deliberately not proxied. Pending-request changes and
fulfilled-claim withdrawals remain direct vault or dedicated redeem-operator operations.

### Generic user check

The address overload, `genericUserCheck(address user, bytes complianceData)`, preserves V1
semantics: `user` is both the Predicate statement sender and the value encoded in the
`accessCheck(address)` payload.

The bytes32 overload accepts an explicit caller:
`genericUserCheck(address caller, bytes32 user, bytes complianceData)`. This validates the
attestation against the complete caller/user pair: `caller` is the Predicate statement sender and
`user` is encoded in the `accessCheck(bytes32)` payload. Both overloads require authority because
successful checks consume attestations. Deployment grants only `COMPLIANCE_PROXY_ROLE` to
the Nest adapter; arbitrary callers cannot burn a proof outside its Bundler3 flow.

## Predicate V2 specifics

- **Statement target = hook address.** The Predicate dashboard project must register the
  **PredicateV2Hook** address per chain; backend attestation requests use `to = hook`.
- **Policy ID = dashboard `verification_hash`.** Stored on-chain at deploy; policy edits happen
  in the dashboard without on-chain changes. `setPolicyID`/`setRegistry` are auth-gated;
  `setRegistry` re-registers the cached policy on the new registry (upstream mixin behavior).
- **`msg_value` is always 0** in statements (all flows are ERC20-only), so backend requests may
  omit/zero `msg_value`.
- **Registry address is deployment config.** Read `script/deployment-config/compliance/<chainId>-<symbol>.json` and verify the address against the dashboard before deployment.
- For V1/V2 attestation formats and API differences, see Predicate's
  [migration guide](https://docs.predicate.io/v2/applications/migration) /
  [essentials](https://docs.predicate.io/v2/essentials/overview).

## Deployment wiring (per chain)

1. Deploy `PredicateV2Hook` implementation + ERC1967/Transparent proxy,
   `initialize(owner, authority, registry, verificationHash)`.
2. Deploy `ComplianceProxy` implementation + ERC1967/Transparent proxy,
   `initialize(owner, hook)`.
3. Grant `COMPLIANCE_HOOK_ROLE` (role 9) the hook's `checkCompliance` capability, then assign that
   role to the compliance proxy.
   Without these grants every check reverts with `AUTH_UNAUTHORIZED()`, which is the safe failure mode.
4. Grant the proxy the same narrowly-scoped vault permissions as the V1 proxy
   (deposit/mint selectors) **plus** the standard `requestRedeem`/`instantRedeem` selectors. Users
   do not register the proxy as an ERC-7540 operator. V1 proxy permissions stay in place during
   coexistence.
5. Register the hook address in the Predicate dashboard project; verify on-chain
   `getPolicyID()` matches the project's verification hash.

`script/deploy/DeployComplianceProxy.s.sol` deploys this stack alongside V1, grants the new
proxy the narrow vault capabilities, authorizes it on the hook, and emits Transaction Builder
batches for the authority's governance path. A Safe owner receives a direct batch; a timelock
owner receives matching schedule and execute batches. Shared registry and API chain settings
live in `config/compliance/<chainId>.json` under `v2`. The dashboard policy comes from
`compliance.v2.verificationHash` in `script/deployment-config/vaults/<symbol>.json`.
Deployment addresses and activation settings live in
`script/deployment-config/compliance/<chainId>-<symbol>.json`.

For the nTEST direct-hook → proxy-hook migration:

1. Keep `activateHook: false` and run the deployment script. Execute the generated governance
   batches. The script deploys a new transparent hook proxy under the `PredicateV2HookProxy` salt,
   persists its address, grants its capabilities, and retains the direct hook as
   `legacyPredicateV2Hook`.
2. Register the newly printed **PredicateV2Hook** proxy address in the existing Application
   Compliance project. The hook proxy, not `ComplianceProxy`, is the Predicate client and statement
   target. Confirm `getPolicyID()` and `getRegistry()` on the new address.
3. Simulate the new hook's `checkCompliance` with `eth_call`, using `ComplianceProxy` as the call's
   `from` address. The attestation request uses `to` equal to the new hook proxy while the live
   `ComplianceProxy` still points to the legacy hook; simulation does not spend the UUID on-chain.
4. Set `activateHook: true`, rerun the deployment script, and execute the generated governance
   batch containing `ComplianceProxy.setComplianceHook(newHook)`. Verify the getter before sending
   deposits.
5. Exercise an end-to-end USDC deposit with `nest:predicate-v2:deposit`. The task requests an
   attestation with `to = PredicateV2Hook`, `chain = plume`, `data = deposit()`, and
   `msg_value = 0`, ABI-encodes it, and passes it to `ComplianceProxy.deposit`. Pass
   `--on-behalf <address|bytes32>` to route through `depositOnBehalf` with the
   `deposit(bytes32)` payload, or `--simulate` to `eth_call` the deposit without spending the UUID.
   `nest:predicate-v2:attest` only requests an attestation and simulates `checkCompliance` with
   `from = ComplianceProxy`; use it for step 3.
6. To roll back, call `ComplianceProxy.setComplianceHook(legacyPredicateV2Hook)` and point
   attestation requests back to the legacy target. Do not remove the legacy hook's caller
   capability until the rollback window closes.

```bash
CHAIN_ID=98866 forge script script/deploy/DeployComplianceProxy.s.sol \
  --sig "run(string)" "nTEST" --rpc-url "$PLUME_RPC_URL" --broadcast --verify --ffi

npx hardhat nest:predicate-v2:deposit --network plumephoenix \
  --compliance-proxy <COMPLIANCE_PROXY> \
  --predicate-hook <PREDICATE_V2_HOOK> \
  --vault 0x802E1f92A6890430bCF350Ad553C936fA425266c \
  --amount 1
```

### Testing every nTEST policy flow

The contract has more entrypoints than Predicate policy payloads. Permit2 and mint variants reuse
the same policy statement as their standard counterpart:

| ComplianceProxy entrypoint                                      | Predicate payload      | Test task                                                          |
| --------------------------------------------------------------- | ---------------------- | ------------------------------------------------------------------ |
| `deposit`, `depositWithPermit2`, `mint`                         | `deposit()`            | `nest:predicate-v2:deposit` / `attest --flow deposit`              |
| `depositOnBehalf`, `depositOnBehalfWithPermit2`, `mintOnBehalf` | `deposit(bytes32)`     | `nest:predicate-v2:deposit --on-behalf ...`                        |
| `genericUserCheck(address,bytes)`                               | `accessCheck(address)` | `nest:predicate-v2:access-check`                                   |
| `genericUserCheck(address,bytes32,bytes)`                       | `accessCheck(bytes32)` | `nest:predicate-v2:access-check --relayer ...`                     |
| `requestRedeem`, `requestRedeemWithPermit2`                     | `requestRedeem()`      | `nest:predicate-v2:request-redeem` / `attest --flow requestRedeem` |
| `instantRedeem`, `instantRedeemWithPermit2`                     | `instantRedeem()`      | `nest:predicate-v2:instant-redeem` / `attest --flow instantRedeem` |

Set `PREDICATE_API_KEY` and use `--vault nTEST`; the task resolves the current chain's vault,
ComplianceProxy, PredicateV2Hook, and Predicate API chain from deployment config. Negative checks
do not require control of the blocked address:

```bash
# Direct EVM user: test accessCheck(address).
pnpm hardhat nest:predicate-v2:access-check --network plumephoenix \
  --vault nTEST --initiator "$BLOCKED_EVM" --expect-rejected

# Relayed EVM or Solana user: test accessCheck(bytes32).
pnpm hardhat nest:predicate-v2:access-check --network plumephoenix \
  --vault nTEST --initiator "$BLOCKED_ORIGINAL_USER" \
  --relayer "$CLEAN_EVM_RELAYER" --expect-rejected

# Reverse the subjects to prove the relayer rule rejects independently.
pnpm hardhat nest:predicate-v2:access-check --network plumephoenix \
  --vault nTEST --initiator "$CLEAN_ORIGINAL_USER" \
  --relayer "$BLOCKED_EVM_RELAYER" --expect-rejected

# Test the direct redemption policies with a blocked EVM sender (no token movement).
pnpm hardhat nest:predicate-v2:attest --network plumephoenix \
  --vault nTEST --flow requestRedeem --sender "$BLOCKED_EVM" --expect-rejected
pnpm hardhat nest:predicate-v2:attest --network plumephoenix \
  --vault nTEST --flow instantRedeem --sender "$BLOCKED_EVM" --expect-rejected
```

For successful end-to-end redemption calls, the configured signer must hold nTEST shares. The
tasks approve the ComplianceProxy before requesting the short-lived attestation:

```bash
pnpm hardhat nest:predicate-v2:request-redeem --network plumephoenix \
  --vault nTEST --amount 0.1
pnpm hardhat nest:predicate-v2:instant-redeem --network plumephoenix \
  --vault nTEST --amount 0.1
```

Predicate calls the original account encoded in an on-behalf payload the `initiator`; it calls the
executing EVM address sent as API `from` the `relayer`. Direct flows have only one subject. The
`access-check` task uses those names explicitly and prints which overload it is testing.

Re-runs of the deploy script also converge existing proxies onto the current build: when a proxy's
implementation runtime code differs from the compilation, the script deploys a fresh implementation
and queues `ProxyAdmin.upgradeAndCall` in the governance batch.

The deploy script deliberately leaves the V1 proxy and existing direct vault capabilities in
place. Removing either is a separate cutover decision after the nTEST end-to-end check passes.

## Dropped: generic call forwarder

A `GenericComplianceProxy` (compliance-gated forwarder attesting over raw calldata, with a
`(target, selector)` allowlist) was prototyped and dropped: it can only serve token-neutral
flows (the redeem family), because ERC-4626 deposit/mint require the proxy to preview, pull,
approve and reset — impossible through pure calldata forwarding without new vault entrypoints.
A partial generic path wasn't worth a second proxy to operate.

## Tests

| Suite | Covers |
| --- | --- |
| `test/ComplianceProxy.t.sol` | all deposit/mint/request/instant-redeem entrypoints and Permit2 variants, public-by-default authority capabilities and revocation, restricted generic checks, payload+identity pinning, hook deny/revert propagation, pause on deposit, mint, request, and instant-redemption entrypoints, Permit2 happy/shortchange, hook swap, allowance reset (2:1-rate mock catches share/asset confusion) |
| `test/PredicateV2Hook.t.sol` | proxy initialization lock, upgrade state preservation, direct and on-behalf payload statement mapping, RolesAuthority caller gating, UUID replay, registry deny/revert, policy/registry admin |
| Mocks | `MockPredicateRegistry` (spent-UUID simulation), `MockComplianceHook`, `MockVaultMinimal` (2:1 rate, ERC-7540 surface), `MockPermit2Minimal` |

Fork tests against the live Predicate V2 Registry (the V2 counterpart of
`NestVaultPredicateProxyFork.t.sol`) are follow-up work, gated on dashboard/project access.
