# Upgrade contracts

Contract names stay the same as their default/deployed counterparts. Use fully qualified source paths or Solidity import aliases to select an implementation.

`compliance-proxy/NestVaultComposer.sol:NestVaultComposer` adds `initializeComplianceProxy()` with `reinitializer(3)` to the default composer without adding storage. `script/deploy/Upgrade.s.sol` deploys this implementation and invokes the function atomically through `ProxyAdmin.upgradeAndCall`. Fresh deployments use `contracts/integrations/ovault/NestVaultComposer.sol:NestVaultComposer`, whose normal initializer already sets the approval. Version 3 cannot be replayed; subsequent upgrades to the default implementation use the same compliance-proxy immutable and empty calldata.

`NestShareOFT.setNameAndSymbol` remains part of the default share contract.

## Recovered deployed sources

`deployed/` contains unchanged source files recovered from verified explorer submissions, only for implementations that actually consumed a reinitializer. [sources.json](deployed/sources.json) records their source hashes, implementation addresses, and initialization transactions.

| Source directory | Contract | Reinitializer used |
| --- | --- | --- |
| `plume-nbasis-composer` | `NestVaultComposer` | `reinitialize()` v2: approve the Predicate proxy |
| `plume-nscope-composer` | `NestVaultComposer` | `reinitialize()` v2: approve the vault to pull shares; same source used by nLCRD |
| `plume-ntest-composer` | `NestVaultComposer` | `reinitialize()` v2: approve the Predicate proxy in the async composer |
| `plume-naxi-share` | `NestShareOFT` | `reinitialize(string,string)` v2: reset metadata |
| `bsc-nwisdom-vault` | `NestVaultOFT` | `setAsset(address)` v2: correct the underlying asset |

These source snapshots retain their original imports and depend on the historical sources/compiler settings available from their verification submissions. Foundry excludes `deployed/` from the current build and formatter, and Solhint ignores it for linting and autofixes. `pnpm repo:check` validates every archived source path and SHA-256 digest against `sources.json` and rejects unlisted snapshots. The old implementations are preserved verbatim and cannot enter fresh deployment artifacts. They must be rebuilt with their original dependency trees, not today's contracts. The current compliance upgrade is compiled and tested normally.

nCLOA's metadata changes used the default `setNameAndSymbol` on Ethereum and Plume, so no separate migration contract is added for those calls. The on-chain accountant checks found initialization version 1; unmerged Git-only accountant reinitializers are not included.
