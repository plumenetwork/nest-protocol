# Predicate V2 (vendored)

This directory contains a vendored subset of `@predicate/contracts` **v2.2.3**. It matches upstream revision
[`6130aa4c`](https://github.com/PredicateLabs/predicate-contracts/tree/6130aa4c88a6b74f2ac3e3e9a8da9e731e600799).

The internal migration scope note records the review and is not in version control.

This repository vendors the files instead of installing them with npm. The V1 and V2 packages must compile together during the coexistence window.

V1 uses `@predicate/contracts#v1.0.12` and the `@predicate/` remapping. V2 uses the `@predicate-v2/` remapping in `foundry.toml`.

These files contain upstream source code from Predicate Labs under BUSL-1.1:

- `interfaces/IPredicateClient.sol`
- `interfaces/IPredicateRegistry.sol` — `Statement` / `Attestation` types + registry interface
- `mixins/PredicateClient.sol` — full client (function + args + value policies)

This copy does not include the upstream `BasicPredicateClient.sol` who-only client. That file requires Solidity 0.8.28, which this toolchain rejects.

Nest uses the full client because existing flows attest `deposit()`, `deposit(bytes32)`, and `accessCheck(...)` payloads.

## Regeneration

```sh
npm pack @predicate/contracts@2.2.3
tar xzf predicate-contracts-2.2.3.tgz
cp package/src/interfaces/{IPredicateClient,IPredicateRegistry}.sol contracts/vendor/predicate-v2/interfaces/
cp package/src/mixins/PredicateClient.sol contracts/vendor/predicate-v2/mixins/
forge fmt contracts/vendor/predicate-v2/
```

The files contain only whitespace changes from `forge fmt`. CI enforces `forge fmt --check` for the repository.

Do not edit the files. Update the version here and copy the upstream files again.
