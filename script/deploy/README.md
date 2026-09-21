# Nest Contracts: Deployment, Testing, Upgrade & Role Revocation Guide

[← Back to repository overview](../../README.md)

## Table of Contents

- [Prerequisites](#prerequisites)
- [Configuration Setup](#configuration-setup)
- [Migrating a Vault (one command)](#migrating-a-vault-one-command)
- [Deploying a New Vault](#deploying-a-new-vault)
- [Deploying Predicate V2 Before Activation](#deploying-predicate-v2-before-activation)
- [Testing](#testing)
- [Upgrading Contracts](#upgrading-contracts)
- [Revoking Roles](#revoking-roles)
- [Role reference](#role-reference)

---

## Prerequisites

### Tools

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- [pnpm](https://pnpm.io/) v10.25+
- Node.js v20.19.5+

### Install Dependencies

```bash
pnpm install
```

### FFI Requirement

Safe batch generation uses Foundry's JSON writer and does not require `--ffi`.
Commands that invoke other external helpers may still require the flag.

### Environment Variables

Create a `.env` file at the project root with these variables:

```bash
# RPC endpoints (match config/common/<chainId>.json)
ETHEREUM_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/<key>
PLUME_RPC_URL=https://rpc.plume.org
PLASMA_RPC_URL=https://plasma-mainnet.g.alchemy.com/v2/<key>
WORLDCHAIN_RPC_URL=https://worldchain-mainnet.g.alchemy.com/v2/<key>
BSC_RPC_URL=https://bnb-mainnet.g.alchemy.com/v2/<key>
ARBITRUM_RPC_URL=https://arb-mainnet.g.alchemy.com/v2/<key>

# Deployer private key (also used as Safe proposer EOA by `pnpm deploy`)
PRIVATE_KEY=0x...

# Etherscan-compatible API keys per chain — required for `--verify` during
# `pnpm deploy`. For Etherscan V2 chains (1/56/42161/480), use an
# Etherscan API key, not the old explorer-specific BscScan/Arbiscan key.
ETHERSCAN_API_KEY_1=...
ETHERSCAN_API_KEY_56=...
ETHERSCAN_API_KEY_42161=...
ETHERSCAN_API_KEY_480=...
ETHERSCAN_API_KEY_9745=...

# Optional per-chain verifier override. The wrapper defaults 1/56/42161/480
# to https://api.etherscan.io/v2/api?chainid=<CHAIN_ID>.
# ETHERSCAN_VERIFIER_URL_56=https://api.etherscan.io/v2/api?chainid=56

# Verifier URL for Plasma (Blockscout vs. Routescan); confirm before first use.
PLASMA_VERIFIER_URL=https://.../api

# Plume uses Blockscout verification.
PLUME_VERIFIER_URL=https://.../api/
PLUME_VERIFIER_API_KEY=...

# Optional: Tenderly bundle simulations per proposed batch. All three must be
# set together; absent => pnpm deploy prints `tenderly: skipped`.
TENDERLY_ACCESS_KEY=...
TENDERLY_ACCOUNT=<org-slug>
TENDERLY_PROJECT=<project-slug>
```

The `createx`, `permit2`, and multisig for each chain come from `config/common/<chainId>.json`. Shared compliance settings come from `config/compliance/<chainId>.json`.

### Supported Chains

| Chain ID | Name       | RPC Env Var           |
|----------|------------|-----------------------|
| 1        | Ethereum   | `ETHEREUM_RPC_URL`    |
| 56       | BSC        | `BSC_RPC_URL`         |
| 480      | World Chain| `WORLDCHAIN_RPC_URL`  |
| 9745     | Plasma     | `PLASMA_RPC_URL`      |
| 42161    | Arbitrum   | `ARBITRUM_RPC_URL`    |
| 98866    | Plume      | `PLUME_RPC_URL`       |
| 5042     | Arc        | `ARC_RPC_URL`         |

Arc (5042) uses `pnpm deploy:arc <phase>` for the fresh PredicateV2-only shared stack and the nOPAL, nFALCON, and FACTOR vaults; run it without arguments to list the ordered phases. The generic `pnpm deploy` still requires a Safe Transaction Service mapping. Arc deployment broadcasts automatically request Blockscout verification using `ARC_VERIFIER_URL` and `ARC_VERIFIER_API_KEY`. Retry a completed phase with `--verify-only`.

---

## Migrating a Vault (one command)

Prepare the configs and `.env` first. Then run `pnpm deploy <VAULT_SYMBOL> <CHAIN_ID>`. The command runs the complete migration for the vault on that chain, from start to end:

1. `forge script … DeployAndSetup.s.sol --broadcast --verify --ffi`
2. `forge script … Upgrade.s.sol --broadcast --verify --ffi` — this step runs only when you pass `--run-upgrade`.
3. `forge script … TransferOwnership.s.sol --broadcast --verify --ffi` with `NEW_OWNER=<config/common/<chainId>.json:.common.multisig>`
4. `forge script … SetupFees.s.sol --sig run() --broadcast --ffi`

`owner` does not select the `NEW_OWNER` used by step 3. It supplies the initial owner when a
new PredicateProxy is initialized (and resolves the authority config's symbolic `owner` user).
Every vault must set a non-zero top-level `owner`. Other freshly deployed surfaces start under
the deployer and are handed off separately by `TransferOwnership`. The wrapper above continues to
pass the operational Safe as `NEW_OWNER`; use the explicit timelock ownership workflow when the
protocol timelock is the intended whole-stack owner.

The fee step reads `vaultFees` and `accountantParams` from the vault config. It sets management, performance, hurdle, and active vault fees.

- The step changes `maxFee` only when the config contains `vaultMaxFees.<type>`.
- A nonzero flat fee needs a `vaultMaxFees` entry because its default cap is zero.
- If the cap is too low, the step skips `setFee` and prints a warning.
- Mixed-direction cap changes are rejected; split into two runs.
- The deployer sets fees directly on vaults that it owns.
- The step queues fees in slot 4 for vaults that the multisig owns.
- The step skips zero fees and does not write an empty batch.
- **Launch gate.** A newly deployed vault receives every configured non-zero active fee before
  the authority step can open user entrypoints; if an active fee exceeds the fresh vault's default
  cap, add a sufficient `vaultMaxFees` entry, otherwise the deployment fails closed instead of
  launching at zero fees. For vaults that were already live, DeployAndSetup retries and standalone
  SetupAuthority runs only print a `[LAUNCH GATE] fee mismatch` warning: those fees converge in the
  SetupFees step (slot 4), so do not route users until it executes. Assets listed under the chain's
  `skipFeeAssetSymbols` or in `SKIP_FEE_ASSET_SYMBOLS` are exempt from the gate.
- With `--run-upgrade`, `FEE_FORCE_SETFEE=true` applies the fees after the upgrade. Force mode
  never changes caps: `setMaxFee` is deferred to a later state-aware run, so a target whose flat
  fee exceeds the post-upgrade cap needs that follow-up run.
- With `--run-upgrade`, accountant fees (management/performance/hurdle/HWM) are deferred while the accountant still runs the legacy implementation: execute the upgrade batch, then rerun the deploy (or SetupFees.s.sol) to queue them.
- The step never posts a rate. It skips a performance-fee change when `lastGrossRate` is `0` (post-migration; the enable would revert) or when the last checkpoint is older than `minimumUpdateDelayInSeconds`. Sequence: upgrade executed, keeper posts a rate, rerun the fee step, Safe executes the fee batch promptly. On Plume the accountant owner is the protocol timelock, so the fee batch executes only after the timelock delay.

**Upgrade behavior.** Pass `--run-upgrade` to upgrade existing proxies. The wrapper excludes proxies deployed by the same migration and records their addresses in `script/output/migrate-state/` for retries.

5. The wrapper splits the resulting Safe Transaction Builder batches into the ordered slots (1a, 1b, 2a, 2b, 3, 4). Slot 4 holds the fees and executes last, so the multisig owns the vault before `setFee`.
6. The wrapper proposes the batches to the chain's Safe Transaction Service, with `PRIVATE_KEY` as the proposer EOA. The `splitBatches` flag in [`tools/safeTxService.ts`](../../tools/safeTxService.ts) controls two modes:
   - **`splitBatches: true`** (Plume): the wrapper proposes each non-empty slot separately. This gives up to 6 separate Safe transactions, each with its own nonce and prompt. If you decline one transaction mid-chain, the wrapper aborts the rest.
   - **`splitBatches: false`** (Ethereum / BSC / Arbitrum / World Chain / Plasma): the wrapper concatenates all non-empty slots in order (1a→1b→2a→2b→3→4) into one MultiSend. This gives a single Safe transaction, with one nonce and one prompt. The order inside the MultiSend keeps the dependency chain (role caps → user roles → wiring → accept ownership → fees) atomic.
7. The wrapper prints a Slack-ready template that contains the real per-tx UI URLs. In merge mode, all slots point to the same URL.

```bash
# Full migration
pnpm deploy nALPHA 42161

# Dry run — forge without --broadcast/--verify, no Safe API writes. Still --ffi.
pnpm deploy nALPHA 42161 --dry-run

# Resume after DeployAndSetup broadcast succeeded but verification failed.
pnpm deploy nALPHA 42161 --skip-upgrade

# Existing deployment where you intentionally want to upgrade implementations.
pnpm deploy nALPHA 42161 --run-upgrade
```

If you decline one batch, the wrapper aborts the remaining batches. The Safe service claims nonces at propose time, so a skipped middle batch breaks the nonce order. Run the command again from scratch. DeployAndSetup is idempotent because of CREATE3 and its on-chain code-existence predicate.

The wrapper writes the split outputs to `script/output/msig/split/<chainId>-<vault>/`, so concurrent chains do not collide.

> **Proposer authorization:** The address of `PRIVATE_KEY` must be a Safe owner or a registered delegate. The preflight checks both options through the Safe API. If the address is neither, the preflight warns but does not abort.
>
> **Standalone `SetupL0` is not part of the wrapper.** `DeployAndSetup` runs step 5 (LayerZero wiring) by default. The splitter puts its LZ transactions into parts 2a/2b. Run `SetupL0.runSourceMsig()` manually only when you ran `DeployAndSetup` with a `STEPS` value that excludes `l0`.

#### Deployment State Detection

For each chain, the wrapper probes the on-chain bytecode at the accountant address and the chain-specific vault addresses from the vault config. It also checks for `script/output/<VAULT>/<chainId>-<VAULT>.json`. The result, `existing` or `new-chain`, is informational and does not select the upgrade mode.

#### Per-chain vault type overrides

Some chains run a non-OFT vault variant. For example, World Chain's USDC uses `NestVault` instead of `NestVaultOFT`. Set the override for each chain in the vault config:

```json
{
  "symbol": "nALPHA",
  "vaultType": "NestVaultOFT",
  "vaultTypeOverrides": {
    "480": "NestVault"
  },
  ...
}
```

`DeployAndSetup` and `Upgrade` use the chain-specific vault type for implementation selection and OFT wiring.

### Wiring Peers Across Chains

Complete deployment on every chain in the vault's `peers` array. Then run `SetPeers` on each EVM chain:

```bash
VAULT_SYMBOL=<SYMBOL> CHAIN_ID=<chainId> forge script script/setup/SetPeers.s.sol \
  --sig "runMsig()" --rpc-url "$RPC" --ffi
```

Review and execute the generated Safe batch before you enable cross-chain transfers. The script skips peers that already match the configuration.
For deployer-owned OApps, use `runDirect()` with `--broadcast`. Use `runHybrid()` with `--broadcast` when ownership differs between targets.

`SetPeers` configures the EVM side of Solana links. Configure the Solana side with the tasks listed in the [Solana OFT operations reference](../../contracts/integrations/ovault/README.md#solana-oft-operations).

---

## Configuration Setup

Before you deploy, create the config files. These files define the vault parameters, the chain infrastructure, and the role assignments.

### 1. Vault Configuration

Create `script/deployment-config/vaults/<SYMBOL>.json`:

```json
{
  "symbol": "nTEST",
  "name": "Nest Test Vault",
  "baseAssetSymbol": "USDC",
  "vaultType": "NestVaultOFT",

  "contracts": {
    "share": "0x0000000000000000000000000000000000000000",
    "accountant": "0x0000000000000000000000000000000000000000",
    "rolesAuthority": "0x0000000000000000000000000000000000000000",
    "vaults": [
      {
        "address": "0x0000000000000000000000000000000000000000",
        "assetSymbol": "USDC",
        "composer": "0x0000000000000000000000000000000000000000",
        "isPegged": true,
        "rateProvider": "0x0000000000000000000000000000000000000000"
      }
    ]
  },

  "common": {
    "predicateProxy": "0x0000000000000000000000000000000000000000",
    "operatorRegistry": "0x0000000000000000000000000000000000000000",
    "redeemOperator": "0x0000000000000000000000000000000000000000",
    "cctpRelayer": "0x0000000000000000000000000000000000000000",
    "seizer": "0x0000000000000000000000000000000000000000",
    "blacklistHook": "0x0000000000000000000000000000000000000000",
    "commonRolesAuthority": "0x0000000000000000000000000000000000000000"
  },

  "accountantParams": {
    "totalSharesLastUpdate": 0,
    "payoutAddress": "0x...",
    "startingExchangeRate": 1000000,
    "allowedExchangeRateChangeUpper": 1000500,
    "allowedExchangeRateChangeLower": 999500,
    "minimumUpdateDelayInSeconds": 3600,
    "managementFee": 0
  },

  "vaultParams": {
    "minRate": 1
  },

  "compliance": {
    "v1": {
      "policyID": "x-nest-prod-005"
    },
    "v2": {
      "verificationHash": ""
    }
  },

  "composerParams": {
    "maxRetryableValue": 0
  },

  "roles": {
    "owner": "0x...",
    "KEEPER_ROLE": ["0x..."],
    "UPDATE_EXCHANGE_RATE_ROLE": ["0x..."],
    "MANAGER_ROLE": ["0x..."],
    "CAN_SOLVE_ROLE": ["0x..."]
  },

  "peers": [98866, 1]
}
```

When `script/deployment-config/common/<chainId>.json` exists, it is the canonical source for the shared contract addresses. It takes precedence over the inline `common` block in the vault config. The inline block is fallback/output data. Do not use it as the primary place to edit the shared infrastructure.

**Key fields:**

| Field | Description |
|-------|-------------|
| `symbol` | Vault identifier (e.g., `nFALCON`, `nOPAL`) |
| `vaultType` | `"NestVault"` (single-chain) or `"NestVaultOFT"` (cross-chain via LayerZero) |
| `contracts.vaults[].chains` | Array of chain IDs on which to deploy each vault entry (e.g., USDC on all chains, pUSD only on Plume) |
| `contracts.*` | Set these to the zero address (`"0x0000...0000"`) for a fresh deployment. The script deploys the contracts and fills the addresses in |
| `common.*` | Fallback/output data for the shared infrastructure. In normal operation, edit `script/deployment-config/common/<chainId>.json`. That file overrides the inline `common` block when it exists |
| `peers` | Chain IDs for LayerZero cross-chain connectivity |
| `accountantParams.startingExchangeRate` | Exchange rate in hub base-asset decimals (e.g. `1000000` = 1.0 for a 6-decimal asset like USDC) |
| `baseAssetOverrides.<chainId>` | Chain-specific base asset symbol; the loader automatically rescales the starting rate from the hub asset's decimals to this asset's decimals |
| `compliance.v1.policyID` | Vault's V1 Predicate policy ID |
| `compliance.v2.verificationHash` | Vault's V2 dashboard policy identifier; empty until configured |
| `compliance.v2Only` | Optional. `true` deploys this vault on the shared `ComplianceProxy` only: no V1 `PredicateProxy` deployment, wiring, or role 7 grant, and `deposit`/`mint` stay gated to the shared proxy. Needs `complianceProxy` in `script/deployment-config/common/<chainId>.json` (recorded by `DeployComplianceProxy.activateCommon`) or a `commonOverrides.complianceProxy`. Chains with `v2Only: true` in `config/compliance/<chainId>.json` force this for every vault |
| `owner` | Required non-zero initial PredicateProxy owner and symbolic `owner` user. Missing or zero fails config loading; there is no common-timelock or legacy `roles.owner` fallback. It does not replace the later `TransferOwnership.NEW_OWNER`. `roles.OWNER_ROLE` / `roles.PAUSER_ROLE` arrays hold the operational Safe(s) granted roles 0/6 |

### 2. Common Chain Configuration

Each chain needs a static chain config at `config/common/<chainId>.json`:

```json
{
  "chainId": 98866,
  "name": "plume",
  "rpc": "PLUME_RPC_URL",
  "isEvm": true,
  "common": {
    "permit2": "0x000000000022D473030F116dDEE9F6B43aC78BA3",
    "createx": "0x1077f8ea07EA34D9F23BC39256BF234665FB391f",
    "multisig": "0x..."
  }
}
```

The chain config stores chain metadata and static infrastructure: the RPC env var name, `permit2`, `createx`, and the multisig.

Shared compliance settings live in `config/compliance/<chainId>.json`:

```json
{
  "chainId": 98866,
  "v1": {
    "serviceManager": "0xdeaf0225C4D31E8a2C99893aB95bAB1790B8A687",
    "defaultPolicyID": "x-nest-prod-006"
  },
  "v2": {
    "apiChain": "plume",
    "predicateRegistry": "0xe15a8Ca5BD8464283818088c1760d8f23B6a216E"
  }
}
```

`v1.defaultPolicyID` is retained as a reference; deployment uses the vault's `compliance.v1.policyID`. The V2 deployer reads the vault's `compliance.v2.verificationHash`. Empty V2 API names and zero registries mean the chain's V2 provider settings have not been configured.

`v2Only: true` in the chain file forces every vault on that chain onto the shared V2 stack and rejects a configured V1 proxy; `DeployAndSetup.runCommonV2` bootstraps the shared operators and authority on such a chain. A single vault opts in on any chain with `compliance.v2Only: true` in its vault config: the chain's V1 proxy stays in place for the other vaults, and that vault's run neither wires it nor grants it.

V2 registry addresses follow Predicate's [Supported Blockchains](https://docs.predicate.io/v2/applications/quickstart#supported-blockchains), and API names follow its [Attestation API](https://docs.predicate.io/api-reference/v2/endpoint/attestation#supported-chains). Ethereum, Base, Arbitrum, Plume, BSC, Plasma, and World use `0xe15a8Ca5BD8464283818088c1760d8f23B6a216E`. Arc and Avalanche are absent from those lists, so their V2 settings remain unset.

V2 deployment addresses, legacy rollback addresses, and `activateHook` remain in `script/deployment-config/compliance/<chainId>-<symbol>.json`. Deployment outputs use the versioned `compliance` block; older outputs with `predicateParams` remain readable.

### 3. Common Contract Addresses

The common address file at `script/deployment-config/common/<chainId>.json` stores the addresses of the deployed shared contracts:

```json
{
  "chainId": 98866,
  "predicateProxy": "0x...",
  "operatorRegistry": "0x...",
  "redeemOperator": "0x...",
  "cctpRelayer": "0x...",
  "seizer": "0x...",
  "blacklistHook": "0x...",
  "commonRolesAuthority": "0x..."
}
```

The deploy scripts read this file first. If the file does not exist, they fall back to the inline `common` block in the vault config.

### 4. Asset Addresses

Put the token addresses for each chain in `config/assets/<chainId>.json`:

```json
{
  "USDC": "0x...",
  "pUSD": "0x..."
}
```

### 5. LayerZero Configuration

Put the cross-chain settings in `config/layerzero/<chainId>.json`:

```json
{
  "chainId": 98866,
  "eid": 30370,
  "endpoint": "0x...",
  "sendLib302": "0x...",
  "receiveLib302": "0x...",
  "executor": "0x...",
  "delegate": "0x...",
  "dvns": {
    "1": { "lz": "0x...", "nethermind": "0x...", "canary": "0x..." }
  },
  "enforcedOptions": {
    "receive": { "gas": 200000, "msgValue": 0 },
    "send": { "gas": 200000, "msgValue": 0 },
    "compose": { "gas": 250000, "msgValue": 0 }
  }
}
```

### 6. Authority Configuration

Two files under `config/authority/` define the role-based access control:

- [**`authority.json`**](../../config/authority/authority.json) - Vault-specific roles (who can call share, accountant, vault, composer)
- [**`common-authority.json`**](../../config/authority/common-authority.json) - Shared infrastructure roles (who can call predicateProxy, redeemOperator, etc.)

All vaults share these files. You rarely need to change them. See [Roles and authorities](../../contracts/auth/README.md) for the complete role and capability matrix.

---

## Deploying a New Vault

### One-Shot Deployment (Recommended)

`DeployAndSetup` does the deployment and the setup. It deploys the contracts, configures the authority, sets up LayerZero, and writes the deployment output. When shared addresses change, it also updates the common address file.

#### Hybrid Mode (auto-detects ownership)

```bash
forge script script/deploy/DeployAndSetup.s.sol \
  --sig "run(string)" "nTEST" \
  --rpc-url $PLUME_RPC_URL \
  --ffi \
  --broadcast
```

The script detects automatically whether the deployer can execute each setup call:

- **Deployer is owner/delegate**: the script executes the call directly through a broadcast
- **Deployer is not owner/delegate**: the script queues the call into a Safe batch JSON

Fresh CREATE3 deployments always come from the broadcasting EOA, in all modes. You cannot batch them into a Safe transaction.

#### Direct Mode (deployer executes everything)

```bash
CHAIN_ID=98866 VAULT_SYMBOL=nTEST forge script script/deploy/DeployAndSetup.s.sol \
  --sig "runDirect()" \
  --rpc-url $PLUME_RPC_URL \
  --ffi \
  --broadcast
```

Direct Mode runs that include the `authority` step require the deployer to own the PredicateProxy (or be authorised for `setAuthority` by its current Authority), unless the proxy is already wired to the configured common RolesAuthority; deploy-only Direct Mode runs are allowed. Production configs set a Safe as owner, so use Hybrid Mode for wiring.

#### Multisig Mode (existing contracts only)

```bash
CHAIN_ID=98866 VAULT_SYMBOL=nTEST STEPS=authority,l0,share forge script script/deploy/DeployAndSetup.s.sol \
  --sig "runMsig()" \
  --rpc-url $PLUME_RPC_URL \
  --ffi
```

Output: `script/output/msig/<chainId>-<symbol>-DeployAndSetup.json`

Use `runMsig()` only when every contract that the selected steps touch already exists on-chain. The script does not serialize CREATE3 deployments into the Safe batch. Thus fresh deployments must use hybrid mode or direct mode.

### Selective Step Execution

Use the `STEPS` env var to run only specific phases:

```bash
STEPS=deploy,authority forge script script/deploy/DeployAndSetup.s.sol \
  --sig "run(string)" "nTEST" \
  --rpc-url $PLUME_RPC_URL \
  --ffi \
  --broadcast
```

Available steps:

| Step | What It Does |
|------|--------------|
| `deploy` | Deploy authorities, share, accountant, predicateProxy, blacklistHook, and vaults |
| `operator` | Deploy OperatorRegistry, RedeemOperator, Seizer |
| `composer` | Deploy CCTP relayer and vault composers |
| `authority` | Configure RolesAuthority (roles + capabilities) |
| `l0` | Configure LayerZero peers, DVNs, libraries, enforced options |
| `share` | Set share vault references and hooks |

Default (no `STEPS`): all steps run.

### Simulating a Safe Batch

Before you import a batch into the Safe UI, simulate the batch on a fork:

```bash
TX_FILE=98866-nTEST-DeployAndSetup forge script script/simulate/SimulateMsigTx.s.sol -vvv
```

The script forks the chain and impersonates the multisig. It replays every transaction to verify that each one succeeds.

### Post-Deployment: Update Config

The script writes the vault-specific deployed addresses to `script/output/<symbol>/<chainId>-<symbol>.json`. If you want future runs to treat those contracts as already deployed, copy the addresses that you want to keep back into `script/deployment-config/vaults/<symbol>.json`.

When the shared infrastructure changes, `DeployAndSetup` also writes the common address file at `script/deployment-config/common/<chainId>.json`. Per-vault `commonOverrides` are never written back: the file keeps the chain-level values plus whatever the run itself deployed.

### Cross-Chain Address Verification

When you deploy the same vault on multiple chains (through CREATE3), set `REFERENCE_CHAIN_ID`. The script then verifies that the addresses match the first deployment:

```bash
CHAIN_ID=1 REFERENCE_CHAIN_ID=98866 forge script script/deploy/DeployAndSetup.s.sol \
  --sig "run(string)" "nTEST" \
  --rpc-url $ETHEREUM_RPC_URL \
  --ffi \
  --broadcast
```

### Ownership Transfer

After deployment, transfer the deployer-owned surfaces to an explicit `NEW_OWNER` (the standard
wrapper uses the operational multisig). This handoff is independent of `owner`, which may
already own a newly initialized PredicateProxy:

```bash
CHAIN_ID=98866 VAULT_SYMBOL=nTEST NEW_OWNER=0x... forge script script/setup/TransferOwnership.s.sol \
  --sig "run()" \
  --rpc-url $PLUME_RPC_URL \
  --ffi \
  --broadcast
```

`TransferOwnership` reads the deployed addresses from `script/output/<symbol>/<chainId>-<symbol>.json`. It does not read them from the vault config. The vault/common RolesAuthority comes from that output (`contracts.rolesAuthority`) and the chain common config (`commonRolesAuthority`) and is cross-checked against the live `share.authority()` / `predicateProxy.authority()`; if they disagree (a `setAuthority` is still queued in a Safe batch) the script stops — set `ALLOW_AUTHORITY_MISMATCH=true` to hand off the configured authority anyway.

The transfer has two phases:

1. **Phase 1 (broadcast)**: The deployer calls `transferOwnership()` on all contracts.
   - AuthUpgradeable contracts use a two-step transfer (the call sets `pendingOwner`)
   - RolesAuthority and ProxyAdmin use an immediate transfer
2. **Phase 2 (Safe batch)**: The script generates an `acceptOwnership()` batch. The new owner executes this batch.

Output: `script/output/msig/<chainId>-<symbol>-TransferOwnership-AcceptOwnership.json`

Use `SCOPE` to limit the transfer:

```bash
SCOPE=vault    # Only vault-specific contracts
SCOPE=common   # Only shared infrastructure
SCOPE=all      # Everything (default)
```

---

## Deploying Predicate V2 Before Activation

Use `DeployComplianceProxy.s.sol` with `--sig "runDeployOnly()"` to deploy the shared
hook and compliance proxy for a chain. It reads the policy from
`script/deployment-config/vaults/nCOMMON.json` (`compliance.v2.verificationHash`),
uses the existing contract interfaces, and attaches the chain's common authority.
The hook initializes with it; the ComplianceProxy initializes with the deployer as
owner, who directly calls `setAuthority` and starts the existing two-step ownership
transfer. The multisig batch includes `acceptOwnership` and configures roles and
capabilities on the authority; it does not contain `setAuthority` calls. Fresh hooks initialize the configured policy; existing
hooks with a different policy receive a queued `setPolicyID` call. The batch grants
no vault roles. It configures the proxy's public entrypoints, restricted hook/integration
access, and admin capabilities. The existing `run(string)`
entrypoint retains its separate vault-specific deployment and wiring flow.

Once the governance batch has executed, `--sig "activateCommon()"` re-verifies the deployed
stack without sending transactions and records `complianceProxy` in
`script/deployment-config/common/<chainId>.json`. It runs on any chain: a chain that still
has a V1 proxy keeps it, and individual vaults opt into the recorded stack with
`compliance.v2Only`.

Use `--sig "runMigration()"` to combine that deployment with the canonical CCTP
relayer implementation deployment/queued upgrade and new parallel leverage contracts
(`NestAdapter`, `NestBundler`, `NestUnlooper`) wherever the chain has the corresponding
config. The new periphery uses the staged ComplianceProxy. Governance calls share
one batch, including the relayer upgrade and domain remap. Active common config,
existing periphery, vault permissions and composers remain unchanged. Morpho core
and Bundler3 are reused; leverage config currently exists for Plume and Ethereum.

---

## Testing

`pnpm test` runs the Foundry and Solana task suites. Fork tests require RPC environment variables. See the [CI workflow](../../.github/workflows/test.yml) for the complete validation sequence.

### Focused Local Checks

```bash
forge fmt --check
forge build contracts --sizes
forge build test
forge test --mc AuthUpgradeable
forge test --fork-url $ETHEREUM_RPC_URL --mc '^Nest'
forge test --mc BoringVaultSY -vv
```

Set `ETHEREUM_RPC_URL` for the forked test suites.

### Fork Test a Deployment

`DeploymentFork.t.sol` validates a deployed vault end-to-end on a fork:

```bash
# Test against deployment output (post-deploy)
CHAIN_ID=1 VAULT_SYMBOL=nFALCON forge test --match-contract DeploymentForkTest -vvv

# Test against input config (pre-deploy)
CHAIN_ID=1 VAULT_SYMBOL=nFALCON USE_OUTPUT=false forge test --match-contract DeploymentForkTest -vvv
```

---

## Upgrading Contracts

Upgrades use the TransparentUpgradeableProxy pattern. The `Upgrade.s.sol` script:

1. Deploys new implementation contracts
2. Calls `ProxyAdmin.upgradeAndCall(proxy, newImpl, initData)` for each proxy

In `runMsig()`, the EOA deploys implementations and executes deployer-owned configuration calls. The script queues the remaining calls for the Safe. Include `--broadcast` to deploy the implementations before the Safe executes the batch.

Composer upgrades use `contracts/upgrades/compliance-proxy/NestVaultComposer.sol:NestVaultComposer` and atomically call `initializeComplianceProxy()` (version 3). Fresh deployments use the default composer in `contracts/integrations/ovault/`. The current composer upgrade step cannot be replayed after version 3; subsequent upgrades to the default implementation use the same compliance proxy and empty calldata. See [Upgrade contracts](../../contracts/upgrades/README.md).

### Upgrade Vault-Specific Contracts

Upgrades: NestShareOFT, NestAccountant, vaults, composers.

```bash
# Direct execution
CHAIN_ID=1 CONTRACT=vault VAULT_SYMBOL=nFALCON forge script script/deploy/Upgrade.s.sol \
  --sig "runDirect()" \
  --rpc-url $ETHEREUM_RPC_URL \
  --ffi \
  --broadcast

# Generate Safe batch
CHAIN_ID=1 CONTRACT=vault VAULT_SYMBOL=nFALCON forge script script/deploy/Upgrade.s.sol \
  --sig "runMsig()" \
  --rpc-url $ETHEREUM_RPC_URL \
  --ffi --broadcast
```

**Safety checks:** Pending redemptions are permitted only when the accountant preserves its storage layout and global pending counter. Otherwise, fulfill or cancel them before the upgrade. See the [vault upgrade pre-flight](../../contracts/README.md#upgrade-pre-flight-zero-pending-redemptions).

Before switching to `NestSpokeAccountant`, claim all `feesOwedInBase` through `share.manage`. See [Claim fees](../../contracts/accountant/README.md#claim-fees). `FORCE=true` bypasses both checks.

**Post-upgrade config**: The script automatically calls `setOperatorRegistry`, `setMaxRetryableValue`, and `setBeforeTransferHook` on the upgraded contracts.

### Upgrade Common (Chain-Shared) Contracts

Upgrades: NestVaultPredicateProxy, NestCCTPRelayer, NestVaultRedeemOperator.

```bash
# Direct execution
CONTRACT=common CHAIN_ID=98866 forge script script/deploy/Upgrade.s.sol \
  --sig "runDirect()" \
  --rpc-url $PLUME_RPC_URL \
  --ffi \
  --broadcast

# Generate Safe batch
CONTRACT=common CHAIN_ID=98866 forge script script/deploy/Upgrade.s.sol \
  --sig "runMsig()" \
  --rpc-url $PLUME_RPC_URL \
  --ffi --broadcast
```

### Upgrade a Vault-Scoped CCTP Relayer

Some vaults override the chain's common relayer. Use the relayer-only scope to resolve that
address from `commonOverrides.cctpRelayer` without upgrading the production common contracts:

```bash
# nTEST's current relayer and ProxyAdmin are owned by its legacy deployer EOA, so use that key.
CONTRACT=cctpRelayer CHAIN_ID=98866 VAULT_SYMBOL=nTEST \
  forge script script/deploy/Upgrade.s.sol \
  --sig "runDirect()" \
  --rpc-url $PLUME_RPC_URL \
  --ffi \
  --broadcast
```

The scope upgrades only the resolved nTEST relayer, then calls `setEidToDomain` with every
currently mapped candidate EID. If ownership later moves to a Safe, `runMsig()` writes
`script/output/msig/98866-nTEST-Upgrade-cctpRelayer.json`; both calls are then in the same Safe
batch, so a failed remap reverts the proxy upgrade as well.

### Custom Initialization Data

Pass custom `initData` for `upgradeAndCall` through an environment variable:

```bash
CHAIN_ID=1 INIT_DATA=0x... CONTRACT=vault VAULT_SYMBOL=nFALCON forge script script/deploy/Upgrade.s.sol \
  --sig "runMsig()" \
  --rpc-url $ETHEREUM_RPC_URL \
  --ffi --broadcast
```

### Simulate Before Executing

Always simulate the upgrade batch before you import it into Safe:

```bash
# Vault scope
TX_FILE=98866-nFALCON-Upgrade-vault forge script script/simulate/SimulateMsigTx.s.sol -vvv

# Common scope
TX_FILE=98866-Upgrade-common forge script script/simulate/SimulateMsigTx.s.sol -vvv

# Vault-scoped CCTP relayer
TX_FILE=98866-nTEST-Upgrade-cctpRelayer forge script script/simulate/SimulateMsigTx.s.sol -vvv
```

---

## Revoking Roles

When you redeploy contracts (e.g., a new composer or redeem operator), the old contract addresses keep their roles on the RolesAuthority. You must revoke these stale permissions.

### How Revocation Works

The system uses two `RolesAuthority` instances:

- **Vault authority**: governs vault-specific contracts (share, accountant, vaults, composers)
- **Common authority**: governs shared infrastructure (predicateProxy, redeemOperator, cctpRelayer, etc.)

Revocation calls `RolesAuthority.setUserRole(address, role, false)` to remove a user's role.

### Automatic Revocation via DeployAndSetup

`DeployAndSetup` can revoke stale roles automatically when vault or composer addresses change. To do this, it compares the current vault config against a **revoke config**. The revoke config is a snapshot of the previous deployment.

Important: the scripts load the shared contract addresses canonically from `script/deployment-config/common/<chainId>.json`. After you update that file, nothing keeps the previous common addresses automatically. Thus do not rely on automatic revocation for old `predicateProxy`, `redeemOperator`, `cctpRelayer`, or `seizer` addresses after you change the common address file.

#### Step 1: Create the Revoke Config

Before you redeploy vaults or composers, save the current vault deployment state as a revoke config:

```bash
mkdir -p script/deployment-config/revoke
cp script/deployment-config/vaults/nFALCON.json \
   script/deployment-config/revoke/98866-nFALCON.json
```

The filename format is `<chainId>-<symbol>.json`. The revoke config keeps the old vault and composer addresses for the comparison during the next run. The `revoke/` directory is not versioned. Create it locally for the run that needs it.

#### Step 2: Update the Vault Config

For vault or composer redeploys, edit `script/deployment-config/vaults/nFALCON.json`. Set the target addresses back to `address(0)`.

For shared infrastructure redeploys, update `script/deployment-config/common/<chainId>.json`. Plan to revoke the old common-contract roles manually after the deployment.

#### Step 3: Run DeployAndSetup

```bash
forge script script/deploy/DeployAndSetup.s.sol \
  --sig "run(string)" "nFALCON" \
  --rpc-url $PLUME_RPC_URL \
  --ffi \
  --broadcast
```

The `_revokeOldRoles()` function in `DeployAndSetup` does these steps:

1. Reads the revoke config from `script/deployment-config/revoke/<chainId>-<symbol>.json`
2. Compares each old address against the new address
3. For each changed contract, checks if the old address still holds the role on-chain
4. If yes, revokes the role with a call to `setUserRole(oldAddress, role, false)`

#### What Gets Revoked Automatically

| Old Contract | Role Revoked | Authority |
|-------------|-------------|-----------|
| Composer | 12 (COMPOSER_ROLE) | Vault + Common |
| Vault | 3 (TELLER_ROLE) | Vault |

For old common contracts, use manual revocation after deployment:

| Old Contract | Role Revoked | Authority |
|-------------|-------------|-----------|
| CCTP Relayer | 13 (RELAYER_ROLE) | Vault |
| Redeem Operator | 11 (CAN_SOLVE_ROLE) | Vault |
| Seizer | 15 (SEIZER_ROLE) | Vault |
| Predicate Proxy | 7 (PREDICATE_PROXY_ROLE) | Vault |

### Manual Revocation with `cast`

For targeted revocation without redeployment, use `cast` or a custom script to call:

```solidity
RolesAuthority.setUserRole(address user, uint8 role, bool enabled)
```

Example with `cast`:

```bash
# Revoke COMPOSER_ROLE (12) from old composer on vault authority
cast send <ROLES_AUTHORITY_ADDR> \
  "setUserRole(address,uint8,bool)" \
  <OLD_COMPOSER_ADDR> 12 false \
  --rpc-url $PLUME_RPC_URL \
  --private-key $PRIVATE_KEY

# Revoke a capability (function-level permission)
cast send <ROLES_AUTHORITY_ADDR> \
  "setRoleCapability(uint8,address,bytes4,bool)" \
  12 <TARGET_CONTRACT> 0x12345678 false \
  --rpc-url $PLUME_RPC_URL \
  --private-key $PRIVATE_KEY
```

### Revoking User Roles (e.g., Removing a Keeper)

To remove an address from a named role (e.g., remove a keeper or solver):

```bash
# Revoke KEEPER_ROLE (14) from an address
cast send <ROLES_AUTHORITY_ADDR> \
  "setUserRole(address,uint8,bool)" \
  <ADDRESS_TO_REVOKE> 14 false \
  --rpc-url $PLUME_RPC_URL \
  --private-key $PRIVATE_KEY
```

> **Note**: Only the RolesAuthority owner can call `setUserRole` and `setRoleCapability`. After the ownership transfer, send these calls through the Safe multisig.

### Verifying Revocation

Check if an address still holds a role:

```bash
cast call <ROLES_AUTHORITY_ADDR> \
  "doesUserHaveRole(address,uint8)(bool)" \
  <ADDRESS> <ROLE_ID> \
  --rpc-url $PLUME_RPC_URL
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `FFI is not enabled` | A script invoked an external helper | Add `--ffi` if that helper is required; Safe batch JSON generation does not need it |
| `EvmError: Revert` on CREATE3 deploy | Salt collision — contract already deployed at that address | Check if the contract already exists on-chain. If you redeploy, zero out the address in the vault config |
| `Missing RPC for chain <id>` | RPC env var not set or misnamed | Verify the env var name matches `config/common/<chainId>.json` `"rpc"` field |
| `You are using a deprecated V1 endpoint` during verification | Foundry used an old explorer URL such as `api.bscscan.com/api` | Use Etherscan V2: `--verifier-url "https://api.etherscan.io/v2/api?chainid=<CHAIN_ID>"` with an Etherscan API key |
| Plume verification uses the wrong verifier | Plume verification goes through Blockscout, not Etherscan | Use `--verify --verifier-url $PLUME_VERIFIER_URL --etherscan-api-key $PLUME_VERIFIER_API_KEY --verifier blockscout` |
| Script reads stale addresses | Vault config not updated after a previous deployment | Copy latest addresses from `script/output/<symbol>/` back into the vault config |
| `Ownable: caller is not the owner` | Ownership already transferred to multisig | Use `runMsig()` to generate a Safe batch instead of `runDirect()` |
| Revocation missed for old common contracts | Canonical common config was updated before saving a revoke snapshot | Manually revoke old roles with `cast` (see [Manual Revocation](#manual-revocation-with-cast)) |

---

## Role reference

See [Roles and authorities](../../contracts/auth/README.md) for the canonical role tables and dual-authority model.
