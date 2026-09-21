# solana-lz-abi

This directory contains ABI templates for the EVM legs of the Solana wire graph.
`script/solana-layerzero.config.ts` uses them in `ensureEvmDeploymentStub`.

LayerZero devtools resolves each EVM `OmniPointHardhat` through hardhat-deploy.
No compiled hardhat artifact has a vault symbol as its name.

Thus, devtools searches `deployments/<network>/*.json` and fails when no record
matches. Mission Control deployments do not have a committed deployment record.

Before graph resolution, the wire config writes a minimal `{ address, abi }`
record for each EVM peer chain. This record has the historical stub format.

- `NestShareOFT.json` — canonical OApp ABI for every non-OFT vault type
  (the wire target is `contracts.share`).
- `NestVaultOFT.json` — OApp ABI for `vaultType == "NestVaultOFT"` (the wire
  target is the canonical vault entry).

These files duplicate forge build output because some consumers do not have
forge. The published package and the offline verification harness cannot read
`out/` at runtime.

CI runs `pnpm lz-abi:check` after `forge build`. The check fails when the files
do not match `out/`.

Regenerate after ABI-affecting contract changes:

```sh
forge build
pnpm lz-abi:write
```

Devtools calls only the OApp surface. This surface includes `endpoint`,
`peers`/`setPeer`, `enforcedOptions`/`setEnforcedOptions`, `setDelegate`, and
`owner`.

A template can lag the deployed implementation if this surface does not change.
