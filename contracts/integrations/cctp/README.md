# CCTP Flow

[← Back to repository overview](../../../README.md)

This document describes the Circle CCTP V2 integration for Nest vaults. `NestCCTPRelayer` receives a CCTP burn message with a hook payload. The hook drives `NestVaultComposer.depositAndSend`, so USDC from another chain lands in a Nest vault in one flow. The primary use is Solana deposits that settle on Plume. This document is for operators who deploy, configure, and run the relayer. For the high-level cross-chain story, see the [public cross-chain page](https://app.plume.org/docs/about/cross-chain).

## Related documentation

- [Cross-chain overview (public)](https://app.plume.org/docs/about/cross-chain)
- [Flow of funds (public)](https://app.plume.org/docs/security-and-compliance/flow-of-funds)
- [Contract addresses (public)](https://app.plume.org/docs/developers/smart-contracts)
- [oVault cross-chain flow](../ovault/README.md) — the composer and LayerZero share-token transport
- [Compliance flow](../../compliance/README.md) — the predicate check that gates the deposit hook
- [Deposit and redeem flow](../../README.md) — vault deposit and redeem mechanics
- [Roles and authorities](../../auth/README.md) — the complete role, holder, and capability reference
- [Operators guide](../../operators/README.md) — the full emergency-control table
- [Deployment guide](../../../script/deploy/README.md) — deploy steps, Safe batches, role revocation

## User flow

A deposit from a CCTP source chain (example: Solana) moves as follows:

1. The user approves the deposit in the source-chain app.
2. The source-chain program calls CCTP `depositForBurnWithHook`. The burn sets the relayer as `mintRecipient` and attaches a hook payload that names the composer.
3. Circle's attestation service signs the burn message. This step is off-chain.
4. The Nest relay service fetches the message and the attestation from Circle's API.
5. The relay service calls `quoteRelay` on the relayer, then calls `relay` with the quoted native fee as `msg.value`.
6. The relayer receives the minted USDC through the CCTP `MessageTransmitter`, then executes the hook.
7. The hook calls `NestVaultComposer.depositAndSend`. The composer runs the predicate compliance check, deposits the USDC into the vault, and sends the share tokens over LayerZero to the destination in `SendParam`.
8. If the hook fails with invalid hook data, the relayer burns the USDC back to the source chain. The refund goes to the refund recipient named in the hook payload.

The user sees one action: USDC leaves the source chain, and share tokens arrive at the destination address.

## Operator procedures

### Configure a chain

Each CCTP-enabled chain needs three config files:

| File                              | Keys the CCTP flow uses                                                                                   |
| --------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `config/cctp/<chainId>.json`      | `messageTransmitter`, `tokenMessenger`, `tokenMinter`, `domain`, optional `maxFeeBasisPoints`, `finalityThreshold` |
| `config/layerzero/<chainId>.json` | `endpoint`, `eid`                                                                                         |
| `config/assets/<chainId>.json`    | the `USDC` address                                                                                        |

The deploy and wire steps skip a chain that has no `config/cctp/<chainId>.json` file.

### Deploy the relayer and composers

The relayer is a chain-shared contract behind a `TransparentUpgradeableProxy`. Deploy it with the `composer` step of `DeployAndSetup`:

```bash
STEPS=composer,authority forge script script/deploy/DeployAndSetup.s.sol \
  --sig "run(string)" "nTEST" \
  --rpc-url $RPC --ffi --broadcast
```

`script/deploy/DeployComposer.s.sol` is the standalone variant (`VAULT_SYMBOL=nTEST`, `runDirect()`). It deploys the relayer and the composers only. It does not wire them. The wiring runs in the later `authority` step (`_wireRelayer`), which consumes the deployment addresses recorded under `script/output/<symbol>/<chainId>-<symbol>.json`:

1. Calls `setComposer(composer, true)` for each deployed composer.
2. Calls `setEidToDomain(eids, domains)` for peer chains that have CCTP config files.

The deploy records the relayer in `script/deployment-config/common/<chainId>.json` and records both relayer and composer addresses in the standard output artifact. `runMsig()` is only valid when no raw deployment remains; it fails fast otherwise. Public addresses: [Deployed contracts](https://app.plume.org/docs/developers/smart-contracts).

### Set the runtime parameters

**Warning:** both values default to zero, and with `maxFeeBasisPoints` at zero `send` reverts when the token messenger requires a nonzero fee. `DeployAndSetup` sets them idempotently only when `config/cctp/<chainId>.json` defines the optional `maxFeeBasisPoints` (1..1000) / `finalityThreshold` (`1000` or `2000`) keys, and prints a `[WARN]` otherwise. The live Plume relayer runs `2` bps / `1000` (Fast); commit those keys once the artifact bundle consumer tolerates them.

Without the keys, set both values after the first deploy:

```bash
cast send $CCTP_RELAYER "setFinalityThreshold(uint32)" 1000 --rpc-url $RPC
cast send $CCTP_RELAYER "setMaxFeeBasisPoints(uint256)" 2 --rpc-url $RPC
```

### Chains without Circle's fee switch

`getMinFeeAmount` exists only on the fee-switch build of `TokenMessengerV2`. Circle's [fee guide](https://developers.circle.com/cctp/concepts/fees) states that calling it on the older build "results in an error" and links build `7d70310` for legacy deployments and `2f9a2ba` for the fee-switch deployment. As observed onchain on 2026-08-27, one proxy address (`0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d`) fronts build `7d70310` (`0x555e2725…`) on Ethereum, Avalanche, Base and World Chain, and build `2f9a2ba` (`0x1CCafDFF…`) on Plume and Sei. Circle's support table lists Sei alone, though Plume had the identical implementation at that snapshot.

`BaseCCTPRelayer.getMinFeeAmount` staticcalls the messenger and returns a zero floor when the legacy build does not implement the function. The fee-switch build also returns zero when its configured `minFee` is zero. Refunds, `setMaxFeeBasisPoints` and `send` therefore work on both builds, and the floor starts applying by itself once Circle upgrades a chain. Check which build a chain runs with:

```bash
cast storage 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d \
  0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc --rpc-url $RPC
```

`DeployAndSetup` still skips the fee cap with a `[WARN]` in one case: a pre-fee-switch messenger fronted by a relayer impl that predates this fallback, where `setMaxFeeBasisPoints` would revert. Upgrade the relayer first.

Circle documents `1000` as Fast transfer (confirmed, pre-finality) and `2000` as Standard transfer (finalized) in its [technical guide](https://developers.circle.com/cctp/references/technical-guide). Fees are denominated in basis points; see Circle's [fee guide](https://developers.circle.com/cctp/concepts/fees). The relayer rejects a cap above its hard limit of `1000` bps or below the token messenger's current minimum fee rate.

### Relay a message

The relay caller passes the burn message, the Circle attestation, and provider-specific compliance data:

1. Fetch the message and attestation from Circle's attestation API.
2. Quote the LayerZero fee: `quoteRelay(message, complianceData, extraOptions)`.
3. Call `relay{value: fee.nativeFee}(message, attestation, complianceData, extraOptions, forceRefund)` with `forceRefund = false`.

A four-argument overload `relay(message, attestation, data, forceRefund)` exists for callers without `extraOptions`. The relayer controls `extraOptions`. These options replace `sendParam.extraOptions` from the user.

If the hook fails for a reason other than invalid hook data, the relay reverts. Inspect the revert reason.

**Warning:** a forced refund abandons the deposit. The relayer burns the USDC back to the source chain. To refund the user anyway, repeat the call with `forceRefund = true`.

### Test a Solana deposit through Predicate V2

`nest:predicate-v2:solana-deposit` implements the CCTP burn used by plume-hub's
`packages/nest-sdk-node/src/actions/mintNestToSolanaNode.ts` (reference commit
`ed9912e890e6c620246b2f336bc536da0f9ab4a6`). Use this task for USDC deposits;
`lz:oft:nest:deposit` is the older OFT transport task.

The route resolves `composerV2`, `complianceProxy`, and `predicateV2Hook` from
`script/deployment-config/compliance/98866-<symbol>.json`, `v2.apiChain` from
`config/compliance/98866.json`, and the vault's effective `commonOverrides.cctpRelayer`.
For nTEST this selects the parallel V2
composer and the legacy nTEST CCTP relayer, not the chain-wide relayer. The task
checks the live route, permissions, approvals, pause state, and Solana OFT peer.

Configure `PLUME_RPC_URL`, `SOLANA_RPC_URL`, `PREDICATE_API_KEY`, and
`SOLANA_KEYPAIR_PATH` (or `SOLANA_PRIVATE_KEY`, as with the other Solana tasks).
The CLI wallet owns the USDC and pays transaction fees, ATA rent, and CCTP event
rent; plume-hub's keeper signature is not required here. The lookup table defaults
to plume-hub's CCTP table; override it with `--lookup-table` if needed.

```bash
# Simulate the Solana burn and check the exact composer/owner Predicate policy.
pnpm hardhat nest:predicate-v2:solana-deposit --network plumephoenix \
  --vault nTEST --amount 1 --finality fast

# Submit the burn; save the printed Solana signature.
pnpm hardhat nest:predicate-v2:solana-deposit --network plumephoenix \
  --vault nTEST --amount 1 --finality fast --broadcast

# Once Circle attests the burn, simulate the Plume relay.
pnpm hardhat nest:predicate-v2:solana-deposit --network plumephoenix \
  --vault nTEST --solana-tx <BURN_SIGNATURE>

# Submit the relay with an authorized EVM PRIVATE_KEY.
pnpm hardhat nest:predicate-v2:solana-deposit --network plumephoenix \
  --vault nTEST --solana-tx <BURN_SIGNATURE> --broadcast
```

Both phases simulate by default; `--broadcast` submits only the selected phase.
Relay simulation defaults to the relayer owner's address, or `--relay-from`.
Broadcast uses `PRIVATE_KEY` and checks that its address can call `relay`.
If Circle is pending, rerun with the **same `--solana-tx`**; do not repeat the burn.
The task does not change the production relay service or its Predicate version.

The hook still calls `ComposerV2.depositAndSend(bytes32,...)`; that composer calls
`ComplianceProxy.depositOnBehalf`. Its refund recipient is the owner's **USDC ATA**,
while `SendParam.to` is the **owner wallet** for OFT share delivery. The hook amount
is `burnAmount - maxFee`; the relayer deposits the actual net amount received.
`--amount` and `--max-fee` use human USDC units; fees default to Circle's current
quote, rounded up. `--min-shares` is an optional minimum in **raw share units**.

The relay reads the depositor from the signed CCTP message, requests a fresh V2
attestation with `from = ComposerV2`, `to = PredicateV2Hook`,
`data = deposit(bytes32 depositor)`, and passes its ABI-encoded `Attestation` as
the relay's `data` argument. The relayer injects that proof into `oftCmd`.
The pre-burn proof is only checked with `eth_call` and is not reused after waiting
for Circle. A successful Plume receipt is checked for `HookRelayed`; Solana share
arrival can then be followed using the printed LayerZero link.

### Recover residual funds

Excess LayerZero fee refunds accrue to the relayer, not to the relay caller. The executed hook spends the full USDC received, so USDC dust is not expected. Sweep residual funds with:

```bash
cast send $CCTP_RELAYER "recoverToken(address,address,uint256)" <token> <to> <amount> --rpc-url $RPC
```

Pass the zero address as `<token>` to recover native tokens. `recoverToken` is auth-gated.

### Upgrade

Upgrade the relayer with the `common` scope of `Upgrade.s.sol`:

```bash
CONTRACT=common CHAIN_ID=98866 forge script script/deploy/Upgrade.s.sol \
  --sig "runDirect()" --rpc-url $RPC --broadcast
```

An upgrade keeps the proxy address. After a relayer redeploy (new address), revoke role 13 from the old address manually. See [Deployment guide](../../../script/deploy/README.md) for the revocation procedure.

## Mechanics reference

### Contracts

- `BaseCCTPRelayer` — receive-and-validate core: message validation, hook execution with try/catch, refund, `recoverToken`.
- `NestCCTPRelayer` — extends the base with the Nest hook format, the composer allowlist, and an `IOFT` surface over CCTP.

Both use solmate-style `requiresAuth`. The authority is the chain's `CommonRolesAuthority`.

### Hook payload

The source chain encodes the hook payload as:

```
20 bytes  composer address
 4 bytes  function selector
   bytes  abi.encode(bytes32 refundRecipient, uint256 assetAmount, SendParam sendParam, address refundAddress)
```

The minimum length is 472 bytes (`MIN_HOOK_DATA_LENGTH`). `refundRecipient` is `bytes32` so that non-EVM source addresses (Solana) can receive refunds.

Before execution, the relayer rewrites the payload. It does not trust the user-supplied values:

| Field | Rewritten to |
|---|---|
| first argument | the burn-message sender, as the depositor for the compliance check |
| `assetAmount` | the USDC amount actually received, net of CCTP fees |
| `sendParam.oftCmd` | the `_data` argument of `relay` (opaque compliance data) |
| `sendParam.extraOptions` | the `_extraOptions` argument of `relay` |
| `refundAddress` | the relayer itself, so excess fees stay recoverable |

Validation rejects the hook when one of these conditions applies:

- The payload is shorter than 472 bytes.
- The composer is not on the `isComposer` allowlist.
- The selector is not `depositAndSend(bytes32,uint256,SendParam,address)`.
- `assetAmount` exceeds the USDC received.

Only the deposit selector passes. The CCTP hook path does not execute `redeemAndSend`.

### Relay outcome matrix

| Hook result | `forceRefund` | Outcome |
|---|---|---|
| success | any | `HookRelayed`, then share tokens sent to destination |
| fails with `InvalidHookData` | any | `HookFailed` + `Refunded`, then USDC burned back to the source chain |
| fails with any other error | `false` | whole relay reverts and message stays relayable |
| fails with any other error | `true` | `HookFailed` + `Refunded` |

The refund burns the USDC to the source domain of the message. The recipient is the `refundRecipient` from the hook payload. Refunds always use finality threshold `2000` and the token messenger's minimum fee. Unspent `msg.value` returns to the relay caller.

### `send` — the OFT surface

The relayer implements `IOFT`, so the composer can treat it as the asset OFT on the redeem path. `send(SendParam, MessagingFee, address)`:

1. Maps `sendParam.dstEid` to a CCTP domain through `eidToDomain`. Storage holds `domain + 1`, leaving raw zero as the unmapped sentinel while supporting Ethereum domain `0`.
2. Pulls `amountLD` USDC from the caller.
3. Burns it through CCTP `depositForBurn` toward `sendParam.to`, with `maxFee` capped by `maxFeeBasisPoints` and the configured `finalityThreshold`.

`peers(eid)` resolves through CCTP's own remote-token-messenger registry, so the relayer needs no LayerZero peer wiring.

### eid-to-domain map (committed config)

| Chain | Chain id | LayerZero eid | CCTP domain in config |
|---|---|---|---|
| Ethereum | 1 | 30101 | 0 |
| Avalanche | 43114 | 30106 | 1 |
| Base | 8453 | 30184 | 6 |
| World Chain | 480 | 30319 | 14 |
| Plume | 98866 | 30370 | 22 |

The relayer encodes every configured domain as `domain + 1`. `getEidToDomain` returns the decoded CCTP domain and reverts with `InvalidDestinationEID` when the raw mapping value is zero.

**Upgrade behavior:** existing relayers store raw domains. `Upgrade.s.sol` reads the currently mapped CCTP EIDs, upgrades the proxy, then calls the authenticated `setEidToDomain` array setter with their corrected domain values. This includes Solana EID `30168`, whose existing raw domain is preserved because it has no EVM CCTP config file.

Solana uses repo chain id `101` (eid `30168`) and has no `config/cctp/101.json`, so the wire step does not set its mapping. Set any Solana entry in `eidToDomain` directly with `setEidToDomain([eid], [domain])`.

### Roles

| Holder | Role | Authority | Grants |
|---|---|---|---|
| relayer | 13 (`RELAYER_ROLE`) | vault `RolesAuthority` | `depositAndSend(bytes32,…)` and `redeemAndSend(bytes32,…)` on the composer |
| composer | 12 (`COMPOSER_ROLE`) | common `RolesAuthority` | `send(…)` on the relayer |

The V2 compliance deployment also grants the composer role 12 on the compliance proxy's authority for `mintOnBehalf`. Composer deposits use the public, compliance-gated `depositOnBehalf` entrypoint.

Role numbers come from `script/lib/Constants.sol`. The wiring comes from `config/authority/authority.json` and `config/authority/common-authority.json`. The committed common-authority config defines no capability for `relay`, `recoverToken`, or the setters. Under solmate auth, only the relayer's owner can call them today.

## Security

Capabilities relevant to this flow. See the [operators guide](../../operators/README.md) for all emergency controls. See the [security policy](https://app.plume.org/docs/security-and-compliance/security-policy) for public posture.

- **Per-path kill switch.** `setComposer(composer, false)` removes the composer from the allowlist and zeroes the relayer's USDC approval to it. Every relay toward that composer then fails hook validation with `InvalidHookData` and takes the refund path. In-flight burns become refunds.
- **Finality threshold.** `setFinalityThreshold` below `2000` accepts pre-finalized burns (fast transfer) for `send`. Monitor changes to this value. Refunds ignore it and always use `2000`.
- **Fee cap.** `maxFeeBasisPoints` has a hard cap of `1000` bps. `getMaxFeeAmount` rejects a cap below the token messenger's minimum fee.
- **Refunds limit stuck funds.** Invalid hook data refunds automatically. Any other hook failure reverts the whole relay, so the message stays relayable. An operator can force a refund with `forceRefund`. This action abandons the deposit.
- **Upstream pauses stop relays.** Pausing the composer's configured compliance proxy or the accountant makes the deposit fail. The relay reverts, and the message remains relayable. An operator can force a refund instead. See [Compliance flow](../../compliance/README.md).
- **Owner-gated recovery.** `recoverToken` and all setters are auth-gated. The committed config permits only the owner to call them.
- **Untrusted payload hardening.** The relayer replaces the depositor, amount, and refund address before execution. A crafted payload cannot change these values.

## Code references

- `contracts/integrations/cctp/NestCCTPRelayer.sol` — Nest hook format, allowlist, IOFT surface
- `contracts/integrations/cctp/BaseCCTPRelayer.sol` — relay core, refund, recovery
- `contracts/integrations/cctp/types/Errors.sol`, `types/Constants.sol`
- `contracts/vendor/cctp/` — Circle message libraries and interfaces
- `contracts/integrations/ovault/NestVaultComposer.sol` — the hook target
- `script/deploy/DeployComposer.s.sol` — standalone deploy
- `script/deploy/DeployAndSetup.s.sol` — `composer` step (deploy) and `authority` step (`_wireRelayer`)
- `script/deploy/Upgrade.s.sol` — `CONTRACT=common` scope
- `config/cctp/<chainId>.json` — Circle contract addresses and domain per chain
- `script/deployment-config/common/<chainId>.json` — deployed `cctpRelayer` address
- `test/NestCCTPRelayer.t.sol` — relay, refund, and composer tests
