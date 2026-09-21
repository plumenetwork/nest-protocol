# Nest Protocol

Nest is Plume's real-world asset protocol. It gives onchain access to real-world yield through structured Vaults.

This repository contains the Nest smart contracts and their operational tooling. The vault stack complies with ERC-4626, ERC-7540, and ERC-7575. It standardizes synchronous and asynchronous deposits and redemptions. Shares move across chains through LayerZero OFT. Assets stay on their origin chain.

The stack has two operating modes:

- **Existing BoringVault deployments.** `NestVaultOFT` is the entry point. It pairs with `NestShareOFT` to bridge shares over LayerZero OFT. The legacy BoringVault stays on one chain. Users move shares across chains.
- **New deployments.** `NestVault` is the entry point. It speaks to `NestShareOFT`, a refined BoringVault replacement with native cross-chain shares.

Compliance and integrations:

- **KYC gating.** V1 deployments use `NestVaultPredicateProxy`. V2 deployments use `ComplianceProxy` with a provider-specific hook. See [Compliance flow](contracts/compliance/README.md).
- **Pendle Finance.** `BoringVaultSY` wraps Nest vault shares as Pendle SY tokens. It reads the accountant rate and supports Merkl reward claims.
- **BoringVault.** This repository uses the BoringVault accountant and rate-provider contracts. It does not ship the base BoringVault.

For protocol documentation, see [app.plume.org/docs](https://app.plume.org/docs/).

## Repository structure

| Path | Contents |
| --- | --- |
| `contracts/` | Production Solidity contracts |
| `script/` | Foundry deployment scripts (`deploy/`, `setup/`, `simulate/`, `dev/`, shared code in `lib/`) |
| `programs/` | Solana OFT program (Anchor) |
| `tools/` | Standalone TypeScript, JavaScript, and shell commands |
| `tasks/` | Hardhat task registrations (LayerZero and Solana operations) |
| `config/` | Reviewed protocol configuration |
| `deployments/` | Published deployment records |
| `audits/` | Final audit reports |
| `test/` | Foundry and Jest tests |

## Quickstart

Install the dependencies:

```bash
pnpm install
```

Build the contracts:

```bash
forge build
```

Run the tests:

```bash
forge test               # Foundry tests
pnpm test:solana         # Jest tests for the Solana task layer
```

## Deployment tooling

Deployments read reviewed inputs and write their run output to ignored directories:

1. Edit the deployment inputs in `script/deployment-config/vaults/<SYMBOL>.json` and `script/deployment-config/common/<chainId>.json`.
2. Run the Foundry scripts in `script/deploy/` and `script/setup/`.
3. The scripts write Safe batches and deployment records to `script/output/`. This directory is not versioned.
4. Review the output. Promote values that must persist into `script/deployment-config/`, `config/`, or `deployments/`.

[Deployment guide](script/deploy/README.md) describes the full procedure.

## Published packages

CI publishes two npm packages to GitHub Packages on each push to `main` or `develop`:

- **`@plumenetwork/nest-artifacts`** — contract ABIs, creation bytecode, per-chain configuration, and a source-verification surface. Built by `tools/build-artifact-bundle.mjs` after `forge build`.
- **`@plumenetwork/nest-solana-deploy`** — the runnable Solana LayerZero task layer. Built by `tools/build-solana-deploy-package.mjs`.

Mission Control consumes both packages. It pins the repo-relative paths of the files inside `nest-solana-deploy` and verifies that the repo path equals the package path. Do not move these without a matching Mission Control change:

- `hardhat.config.ts`, `tsconfig.json`
- `tasks/**`
- `script/solana-layerzero.config.ts`
- `script/deployment-config/vaults/`
- `script/solana-lz-abi/`
- `deployments/solana-mainnet/`, `deployments/plumephoenix/`
- `tools/build-solana-deploy-package.mjs` (the builder path that Mission Control invokes)
- `script/output/` (ignored runtime handoff path, never committed)

## Documentation

**Vault core**

- [contracts/README.md](contracts/README.md) — deposit, redemption, and vault-fee flow, user and operator side.
- [contracts/auth/README.md](contracts/auth/README.md) — authorization model, roles, holders, and capabilities.
- [contracts/accountant/README.md](contracts/accountant/README.md) — exchange rate, management fee, performance fee.
- [contracts/compliance/README.md](contracts/compliance/README.md) — KYC gating, transfer restrictions, seizure.

**Integrations**

- [contracts/integrations/morpho/README.md](contracts/integrations/morpho/README.md) — leveraged-loop integration.
- [contracts/integrations/pendle/README.md](contracts/integrations/pendle/README.md) — Pendle SY wrapper.
- [contracts/integrations/cctp/README.md](contracts/integrations/cctp/README.md) — Circle CCTP cross-chain USDC relay.
- [contracts/integrations/ovault/README.md](contracts/integrations/ovault/README.md) — LayerZero OFT cross-chain shares.

**Operations**

- [Operators guide](contracts/operators/README.md) — authority setup, timelocks, and the emergency-control table.
- [Deployment guide](script/deploy/README.md) — deploy, test, upgrade, and role-revocation procedures.
- [Deployed contracts](https://app.plume.org/docs/developers/smart-contracts) — contract addresses per chain and vault (public docs).
- [audits/](audits) — final audit reports.

**Release history**

- [CHANGELOG.md](CHANGELOG.md) — contract version history.
