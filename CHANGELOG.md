# Changelog

This changelog records notable production changes to Nest Protocol contracts.

Repository release versions and contract `version()` values are separate version spaces. A repository release can ship contracts with different version values. Published release entries use the public [`plumenetwork/nest-protocol`](https://github.com/plumenetwork/nest-protocol) tags as the source of truth. Contract-version tables track every production contract that exposes a string-returning `version()` function in the current repository. In older snapshots, a tracked contract that existed but did not yet expose that function appears as `0.0.0`. Version-history arrows include values introduced in internal development between public releases.

## Contract version history

| Contract                  | Version history                                   | Current |
| ------------------------- | ------------------------------------------------- | ------- |
| `NestVault`               | `0.0.1` -> `0.0.2` -> `1.1.0`                     | `1.1.0` |
| `NestVaultOFT`            | `0.0.1` -> `0.0.2` -> `1.1.0`                     | `1.1.0` |
| `NestShareOFT`            | `0.0.0` -> `1.0.0` -> `1.1.0` -> `1.2.0`          | `1.2.0` |
| `NestAccountant`          | `0.0.0` -> `1.1.0` -> `1.1.1`                     | `1.1.1` |
| `NestHubAccountant`       | `0.0.0` -> `1.0.0` -> `1.1.0`                     | `1.1.0` |
| `NestSpokeAccountant`     | `0.0.0` -> `1.0.0` -> `1.1.0`                     | `1.1.0` |
| `NestVaultComposer`       | `0.0.0` -> `1.0.0` -> `1.1.0` -> `1.2.0` -> `1.3.0` | `1.3.0` |
| `NestVaultPredicateProxy` | `0.0.0` -> `1.0.0`                                | `1.0.0` |
| `ComplianceProxy`         | `1.0.0`                                           | `1.0.0` |
| `PredicateV2Hook`         | `1.0.0`                                           | `1.0.0` |
| `NestVaultRedeemOperator` | `0.0.0` -> `1.0.0`                                | `1.0.0` |
| `NestCCTPRelayer`         | `0.0.0` -> `1.0.0`                                | `1.0.0` |
| `BoringVaultSY`           | `0.0.0` -> `2.0.0`                                | `2.0.0` |

The `NestVault` history follows its earlier `BoringVaultPeriphery` and `PlumeVault` names through the Git rename history.

## [v1.4.0] - 2026-09-21

Public tag: [`v1.4.0`](https://github.com/plumenetwork/nest-protocol/tree/v1.4.0).

### Contract versions

| Contract                  | `version()` |
| ------------------------- | ----------- |
| `NestVault`               | `1.1.0`     |
| `NestVaultOFT`            | `1.1.0`     |
| `NestShareOFT`            | `1.2.0`     |
| `NestAccountant`          | `1.1.1`     |
| `NestHubAccountant`       | `1.1.0`     |
| `NestSpokeAccountant`     | `1.1.0`     |
| `NestVaultComposer`       | `1.3.0`     |
| `NestVaultPredicateProxy` | `1.0.0`     |
| `ComplianceProxy`         | `1.0.0`     |
| `PredicateV2Hook`         | `1.0.0`     |
| `NestVaultRedeemOperator` | `1.0.0`     |
| `NestCCTPRelayer`         | `1.0.0`     |
| `BoringVaultSY`           | `2.0.0`     |

### Added

- Added the provider-independent `ComplianceProxy` and its `IComplianceProxy` and pluggable `IComplianceHook` interfaces for compliance-gated deposit, mint, and ERC-7540 redemption flows.
- Added the upgradeable `PredicateV2Hook`, with configurable registry and policy and authorized-caller gating to prevent third parties from consuming Predicate V2 attestations. The existing Predicate V1 proxy stays deployed and unchanged for legacy and direct integrations while Composer and modern Morpho routes migrate independently to `ComplianceProxy`.
- Vendored the Predicate V2.2.3 client interfaces and mixin used by `PredicateV2Hook`.
- Added Permit2 support for direct and on-behalf deposits and compliance-gated redemption, plus pause controls, to the new compliance entry point.
- Added compliance-gated `NestAdapter.nestComplianceInstantRedeem`, `nestComplianceRequestAndRedeem`, and `nestComplianceRequestRedeem` actions. Morpho bundles can select compliant instant or asynchronous redemptions through `RouteInput.compliantRedemption`.
- Added Ethereum CCTP domain `0` support and batched LayerZero EID-to-domain configuration.

### Changed

- Made `NestShareOFT.manage` payable and allowed the share contract to receive native currency for authorized calls. Updated its version from `1.1.0` to `1.2.0`.
- Updated `NestAccountant` and `NestShareSeizer` for the payable `NestShareOFT` type. Advanced the `NestAccountant` patch version from `1.1.0` to `1.1.1`.
- Changed `NestVaultComposer` deposits to use the vault-specific `ComplianceProxy` and forward `SendParam.oftCmd` opaquely as provider-specific compliance data. Moved the upgrade initializer into the same-named implementation under `contracts/upgrades/compliance-proxy/` to restore the asset allowance atomically and advanced the Composer version from `1.2.0` to `1.3.0`.
- Changed the modern Morpho adapter and bundle deposit and mint routes to validate opaque compliance data through `ComplianceProxy.genericUserCheck`. Legacy teller routes remain on Predicate V1 and decode their compliance bytes as `PredicateMessage`.
- Changed `NestHubAccountant.updateManagementFee` to accept only the new fee. It no longer requires the global share supply or accrues the previous fee during the change. It rejects unchanged fees and checkpoints older than `UPDATE_DELAY_CAP`, then advances `lastUpdateTimestamp` before applying the new fee. Fees accrued since the previous checkpoint are forfeited; operators should call `updateExchangeRate` immediately before changing the management fee to minimize that loss.
- Bound modern Morpho compliance checks to the Bundler3 initiator and an explicit `bytes32 onBehalf` identity. Checks also enforce the corresponding direct or on-behalf proxy selector permissions.
- Reorganized contract sources by responsibility: integrations moved under `contracts/integrations`, compliance code moved under `contracts/compliance`, third-party sources moved under `contracts/vendor`, and vault libraries were flattened under `contracts/libraries`.

### Fixed

- Forwarded shares minted by legacy Predicate teller deposits to the requested receiver instead of leaving them in the Morpho adapter.
- Supported CCTP token messengers without the fee-switch `getMinFeeAmount` method by treating a failed fee lookup as a zero minimum fee.
- Kept `NestCCTPRelayer.setComposer(composer, false)` callable when composer getters revert or its configuration no longer matches; validation now runs only when enabling a composer.
- Made unmapped CCTP destinations fail closed in sends and `getEidToDomain`, while `peers` returns zero for unmapped LayerZero peer probes.

### Breaking changes

- Changed `NestCCTPRelayer.setEidToDomain(uint32,uint32)` to `setEidToDomain(uint32[],uint32[])`. Update callers and selector-based permissions. Mapping storage now encodes each domain as `domain + 1`; existing relayer proxies must rewrite their mappings with the original domain values after upgrading, before resuming sends. Unconfigured `getEidToDomain` lookups now revert with `InvalidDestinationEID`.
- Changed `NestHubAccountant.updateManagementFee(uint32,uint128)` to `updateManagementFee(uint32)`. Update caller ABIs and selector-based permissions, and checkpoint the exchange rate before changing fees.
- Added explicit `bytes32 onBehalf` arguments to the modern compliant Morpho adapter actions and `compliantRedemption` to `RouteInput`, changing the adapter selectors and bundle tuple ABI. Update integration ABIs, encoded bundles, and authorizations together.
- Solidity import paths changed as part of the source reorganization. Runtime behavior was preserved by the move, but downstream source imports must use the new paths.
- `NestVaultComposer` no longer exposes `PREDICATE_PROXY` or supports deposits through `NestVaultPredicateProxy`. Existing Composer proxies must use `contracts/upgrades/compliance-proxy/NestVaultComposer.sol:NestVaultComposer`, configured with a `ComplianceProxy`, and call `initializeComplianceProxy()` atomically during the upgrade. The default composer exposes only its ordinary initializer.
- Renamed `NestAdapter.nestPredicateDeposit` and `nestPredicateMint` to `nestComplianceDeposit` and `nestComplianceMint`, replaced their `PredicateMessage` arguments with opaque `bytes complianceData`, changed the modern `NestBundler` APIs and bundle types accordingly, and replaced its `PREDICATE_PROXY` getter with `COMPLIANCE_PROXY`. The modern Morpho routes no longer support `NestVaultPredicateProxy`; existing callers must update their ABIs and reauthorize the newly deployed contracts.

## [v1.3.0] - 2026-07-06

Public tag: [`v1.3.0`](https://github.com/plumenetwork/nest-protocol/tree/v1.3.0).

### Contract versions

| Contract                  | `version()` |
| ------------------------- | ----------- |
| `NestVault`               | `1.1.0`     |
| `NestVaultOFT`            | `1.1.0`     |
| `NestShareOFT`            | `1.1.0`     |
| `NestAccountant`          | `1.1.0`     |
| `NestHubAccountant`       | `1.1.0`     |
| `NestSpokeAccountant`     | `1.1.0`     |
| `NestVaultComposer`       | `1.2.0`     |
| `NestVaultPredicateProxy` | `1.0.0`     |
| `NestVaultRedeemOperator` | `1.0.0`     |
| `NestCCTPRelayer`         | `1.0.0`     |
| `BoringVaultSY`           | `2.0.0`     |

### Added

- Added `version()` reporting to the production share, accountant, composer, predicate, operator, CCTP, and Pendle integration contracts.
- Added fee-accrual events for deposit, redemption, instant-redemption, management, and performance fees.
- Added accountant fee-waiver, reserve-waiver, rate-provider inspection, share-token inspection, performance checkpoint, reserve, and liability views.
- Added CCTP peer lookup by LayerZero endpoint ID.

### Changed

- Changed async OVault redemption accounting to track `(redeemer, receiver)` pairs and emit request, update, and fulfillment events with both identities.
- Added local OVault settlement without LayerZero fees and separated compose blocking into explicit block and unblock operations.
- Reworked hub-accountant management and performance fee accrual, high-water marks, crystallization, reserves, and fee carry handling.
- Added multi-loop Morpho deleveraging for liquidity-limited full exits, including peak-liquidity calculations and aggregate minimum-price checks.
- Embedded `BoringVaultSY` storage, made its maximum rate immutable, and moved it under the Pendle integration directory.

### Fixed

- Required Predicate Permit2 deposits to receive the requested token amount.
- Applied the configured transfer hook to `NestVaultOFT` debits.
- Tightened CCTP hook-data validation and rejected malformed receiver data.
- Prevented async redeem fulfillment from exceeding live pending shares or accepting an unexpected returned-share amount.
- Handled zero-supply and dust cases in management and performance fee accrual.
- Protected Morpho deleveraging against insufficient liquidity, excessive loop counts, zero-share repayments, LLTV breaches, buffer exhaustion, and underpriced aggregate redemptions.

### Breaking changes

- Async composer pending, claimable, and fulfillment interfaces now include the receiver identity.
- Replaced `BlacklistHook.setBlacklisted(account, bool)` with `blacklist(account)` and `unblacklist(account)`.
- Replaced `NestVaultComposer.setBlockCompose(guid, bool)` with `blockCompose(guid)` and `unblockCompose(guid)`.

## [v1.2.0] - 2026-06-16

Public tag: [`v1.2.0`](https://github.com/plumenetwork/nest-protocol/tree/v1.2.0).

### Contract versions

| Contract                  | `version()` |
| ------------------------- | ----------- |
| `NestVault`               | `0.0.2`     |
| `NestVaultOFT`            | `0.0.2`     |
| `NestShareOFT`            | `0.0.0`     |
| `NestAccountant`          | `0.0.0`     |
| `NestHubAccountant`       | `0.0.0`     |
| `NestSpokeAccountant`     | `0.0.0`     |
| `NestVaultComposer`       | `0.0.0`     |
| `NestVaultPredicateProxy` | `0.0.0`     |
| `NestVaultRedeemOperator` | `0.0.0`     |
| `NestCCTPRelayer`         | `0.0.0`     |
| `BoringVaultSY`           | `0.0.0`     |

### Added

- Added `NestHubAccountant` and `NestSpokeAccountant` for hub-and-spoke rate and fee accounting.
- Added EIP-1271 signature validation to `NestShareOFT`, with authorized signature checkers and a configurable strategist signer.
- Added the Morpho integration suite: `MorphoAdapter`, `NestAdapter`, `NestBundler`, `NestUnlooper`, and bundle construction and calldata libraries.
- Added deposit and redemption fee classes, flat-fee support, fee previews, and configurable fee caps.
- Added Predicate-compatible teller interfaces and Boring Vault, Bundler3, and Morpho integration interfaces.

### Changed

- Changed vaults to use a hub accountant and expanded fee configuration from a single rate to rate-and-flat-fee structures.
- Added fee-aware `previewDeposit`, `previewMint`, and `previewFulfillRedeem` calculations.
- Moved `NestAccountant` into the accountant module and separated hub and spoke accountant responsibilities.

### Breaking changes

- The vault fee ABI changed: `setFee` accepts a fee structure, while `fees` and `maxFees` return rate and flat-fee values.
- Accountant integrations must distinguish hub and spoke responsibilities when deploying or upgrading vaults.

## [v1.1.0] - 2026-04-27

Public tag: [`v1.1.0`](https://github.com/plumenetwork/nest-protocol/tree/v1.1.0).

### Contract versions

| Contract                  | `version()` |
| ------------------------- | ----------- |
| `NestVault`               | `0.0.2`     |
| `NestVaultOFT`            | `0.0.2`     |
| `NestShareOFT`            | `0.0.0`     |
| `NestAccountant`          | `0.0.0`     |
| `NestVaultComposer`       | `0.0.0`     |
| `NestVaultPredicateProxy` | `0.0.0`     |
| `NestVaultRedeemOperator` | `0.0.0`     |
| `NestCCTPRelayer`         | `0.0.0`     |
| `BoringVaultSY`           | `0.0.0`     |

### Added

- Added `NestVaultPermit2` for signature-based redemption requests and instant redemptions.
- Added `OperatorRegistry` and `NestVaultRedeemOperator` for delegated, batch, fulfill-and-redeem, and receiver-aware redemption workflows.
- Added `BlacklistHook` and `NestShareSeizer` for pausing transfers, blocking accounts, seizing shares, and seizing-and-redeeming shares.
- Added EIP-2612 permit support, governed name and symbol updates, and before-transfer hooks to `NestShareOFT`.
- Added asynchronous OVault composition, retry controls, and blocked-compose management.
- Added vault-level fee claiming and claimable-fee accounting.

### Changed

- Split vault accounting, administration, deposits, operators, redemptions, transfers, types, and validation into dedicated libraries.
- Replaced the accountant-with-rate-providers dependency with `NestAccountant` and added total-pending-share tracking.
- Extended CCTP relay and quote flows with extra LayerZero options.
- Added operator-registry configuration to vault initialization.

### Breaking changes

- `NestVault` and `NestVaultOFT` initializers require an operator-registry address.
- Renamed the vault accountant setter and getter from the accountant-with-rate-providers API to `setAccountant` and `accountant`.
- Changed Predicate generic-user identifiers from strings to `bytes32`.
- CCTP quote and relay callers must supply the new extra-options argument.

## [v1.0.0] - 2026-01-28

Public tag: [`v1.0.0`](https://github.com/plumenetwork/nest-protocol/tree/v1.0.0).

### Contract versions

| Contract                  | `version()` |
| ------------------------- | ----------- |
| `NestVault`               | `0.0.1`     |
| `NestVaultOFT`            | `0.0.1`     |
| `NestShareOFT`            | `0.0.0`     |
| `NestAccountant`          | `0.0.0`     |
| `NestVaultComposer`       | `0.0.0`     |
| `NestVaultPredicateProxy` | `0.0.0`     |
| `NestCCTPRelayer`         | `0.0.0`     |
| `BoringVaultSY`           | `0.0.0`     |

### Added

- Published the initial Nest Protocol contract source.
- Added `NestVault`, `NestVaultCore`, and `NestVaultOFT` for synchronous deposits, asynchronous redemptions, and omnichain vault operation.
- Added `NestShareOFT` as the LayerZero OFT and ERC-7575 share token.
- Added `NestAccountant` for exchange-rate bounds, management fees, and rate-provider conversion.
- Added `NestVaultPredicateProxy` for Predicate-gated vault access.
- Added `NestCCTPRelayer`, `NestVaultComposer`, and `BoringVaultSY` for CCTP, OVault, and Pendle integrations.

[v1.4.0]: https://github.com/plumenetwork/nest-protocol/compare/v1.3.0...v1.4.0
[v1.3.0]: https://github.com/plumenetwork/nest-protocol/compare/v1.2.0...v1.3.0
[v1.2.0]: https://github.com/plumenetwork/nest-protocol/compare/v1.1.0...v1.2.0
[v1.1.0]: https://github.com/plumenetwork/nest-protocol/tree/v1.1.0
[v1.0.0]: https://github.com/plumenetwork/nest-protocol/tree/v1.0.0
