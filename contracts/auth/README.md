# Roles and Authorities

[← Back to repository overview](../../README.md)

This document is the repository reference for Nest contract authorization. The configured selectors and symbolic assignments live in the [vault authority config](../../config/authority/authority.json) and [common authority config](../../config/authority/common-authority.json). The addresses behind role-list names live in each [vault deployment config](../../script/deployment-config/vaults/).

## Authorization model

Protected contracts inherit Solmate `Auth` or [`AuthUpgradeable`](AuthUpgradeable.sol). A function guarded by `requiresAuth` accepts a call when any of these conditions is true:

1. The contract's `RolesAuthority` exposes the selector as a public capability.
2. The caller holds a role that has the selector as a capability for the target.
3. The caller is the contract owner.

The owner bypass is independent of role 0 (`OWNER_ROLE`): an `Auth.owner()` can call every protected function on that contract even without a role assignment.

Two `RolesAuthority` instances split the permission surface:

| Authority | Address source | Governs | Capability config |
|---|---|---|---|
| Vault authority | `share.authority()` | share token, accountant, vaults, composers; V2 compliance proxy and hook after V2 setup | [`authority.json`](../../config/authority/authority.json) |
| Common authority | `predicateProxy.authority()` | predicate proxy, operator registry, redeem operator, CCTP relayer, blacklist hook, share seizer, Nest unlooper | [`common-authority.json`](../../config/authority/common-authority.json) |

Role IDs are scoped to an authority. A role with the same ID can therefore have different capabilities in the two tables below. Role names come from [`script/lib/Constants.sol`](../../script/lib/Constants.sol).

## Configured roles

The “Who has it” column describes the desired symbolic `roleAssignments` entries in the authority configs. Contract names resolve to addresses in the selected vault config. Role-list names are intended to resolve to addresses under `roles`; the exact holders can vary by vault and chain.

Entries with a deployment condition are applied only when the referenced integration is active on that chain.

### Vault authority

Source: [`config/authority/authority.json`](../../config/authority/authority.json)

| Role | Who has it | Capabilities |
|---|---|---|
| 0 `OWNER_ROLE` | `OWNER_ROLE` addresses, normally the operational Safe | `accountant.unpause`; `composer.blockCompose`, `unblockCompose`, `setMaxRetryableValue`, and `recover` |
| 2 `MANAGER_ROLE` | Addresses in `roles.MANAGER_ROLE` | Single and batch `share.manage` |
| 3 `TELLER_ROLE` | Every configured vault contract | `share.enter` and `share.exit`; `accountant.increaseTotalPendingShares` and `decreaseTotalPendingShares` |
| 4 `UPDATE_EXCHANGE_RATE_ROLE` | Addresses in `roles.UPDATE_EXCHANGE_RATE_ROLE` | Both `accountant.updateExchangeRate` overloads |
| 5 `SOLVER_ROLE` | `nestAdapter` and `nestUnlooper`, when deployed | `vault.fulfillRedeem` |
| 6 `PAUSER_ROLE` | Addresses in `roles.PAUSER_ROLE` | `accountant.pause` |
| 7 `PREDICATE_PROXY_ROLE` | `predicateProxy`, when deployed | `vault.deposit` and `vault.mint` |
| 8 `DEPOSITOR_ROLE` | `nestAdapter`, when deployed, and addresses in `roles.DEPOSITOR_ROLE` | `vault.deposit` and `vault.mint` |
| 16 `COMPLIANCE_PROXY_ROLE` | `nestAdapter`, when deployed | Both consuming `complianceProxy.genericUserCheck` overloads |
| 11 `CAN_SOLVE_ROLE` | Addresses in `roles.CAN_SOLVE_ROLE`; `redeemOperator`, when deployed | `vault.fulfillRedeem`; `composer.fulfillRedeem` |
| 12 `COMPOSER_ROLE` | Every configured composer | `vault.requestRedeem`, `fulfillRedeem`, `instantRedeem`, `updateRedeem`, `redeem`, and `send` |
| 13 `RELAYER_ROLE` | `cctpRelayer`, when deployed | Composer `depositAndSend` and `redeemAndSend` relayer overloads |
| 14 `KEEPER_ROLE` | Addresses in `roles.KEEPER_ROLE`, when a composer exists | `composer.updateRequestRedeemAndSend` and `finishRedeemAndSend` |
| 15 `SEIZER_ROLE` | `shareSeizer`, when deployed | `share.enter` and `share.exit` |

### Common authority

Source: [`config/authority/common-authority.json`](../../config/authority/common-authority.json)

| Role | Who has it | Capabilities |
|---|---|---|
| 0 `OWNER_ROLE` | `OWNER_ROLE` addresses, normally the operational Safe | `shareSeizer.seize` and `seizeAndRedeem`; `blacklistHook.unpause` and `unblacklist`; `predicateProxy.unpause` |
| 6 `PAUSER_ROLE` | Addresses in `roles.PAUSER_ROLE` | `blacklistHook.pause`; `predicateProxy.pause` |
| 12 `COMPOSER_ROLE` | Every configured composer | Predicate-proxy `deposit` and `mint`; `cctpRelayer.send` |
| 14 `KEEPER_ROLE` | Addresses in `roles.CAN_SOLVE_ROLE` when the redeem operator or Nest unlooper exists | `redeemOperator.redeem`, `fulfillAndRedeem`, `redeemAll`, `fulfillAndRedeemAll`, `batchRedeem`, `batchFulfillAndRedeem`, and `authorizeAsOperator`; `nestUnlooper.execute` |
| 15 `SEIZER_ROLE` | `shareSeizer`, when deployed | `blacklistHook.blacklist` and `unblacklist` |

`STRATEGIST_ROLE` (1) and `QUEUE_ROLE` (10) are reserved constants with no capabilities or assignments in either authority config. Role 9 (`COMPLIANCE_HOOK_ROLE`) is configured by the V2 deployment script described below.

### V2 compliance deployment grants

[`DeployComplianceProxy.s.sol`](../../script/deploy/DeployComplianceProxy.s.sol) binds the V2 proxy and hook to the vault authority. It also applies these grants:

| Role | Holder | Capability |
|---|---|---|
| 0 `OWNER_ROLE` | Existing role holders | `complianceProxy.unpause`, `setComplianceHook`; `predicateV2Hook.setPolicyID`, `setRegistry` |
| 6 `PAUSER_ROLE` | Existing role holders | `complianceProxy.pause` |
| 7 `PREDICATE_PROXY_ROLE` | Adds `complianceProxy` | Vault `deposit`, `mint`, `requestRedeem`, and `instantRedeem` |
| 9 `COMPLIANCE_HOOK_ROLE` | `complianceProxy` | `predicateV2Hook.checkCompliance` |
| 12 `COMPOSER_ROLE` | Configured composers | `complianceProxy.mintOnBehalf`, including when its public capability is revoked |

The script also applies the proxy's public capabilities and the adapter's role-16 user checks listed in this reference.

## Public capabilities

Public capabilities require no role, although each function's own validation and approval checks still apply.

| Authority | Target | Public capabilities | Condition |
|---|---|---|---|
| Vault | `vault` | `instantRedeem`, `instantRedeemWithPermit2`, `requestRedeem`, `requestRedeemWithPermit2`, `updateRedeem`, `redeem`, `withdraw`, `send` | Always |
| Vault | `vault` | `deposit`, `mint` | No predicate proxy is deployed |
| Vault | `complianceProxy` | Deposit, mint, request-redeem, and instant-redeem families, including Permit2 and on-behalf variants | Compliance proxy is deployed |
| Vault | `composer` | User-facing `depositAndSend` and `redeemAndSend` overloads | Composer is deployed |
| Common | `operatorRegistry` | `setOperator` | Operator registry is deployed |

## Configuration and application

[`SetupAuthority.s.sol`](../../script/setup/SetupAuthority.s.sol) applies both authority files and is idempotent. The JSON schema is:

- `capabilities`: role-to-target selector grants.
- `publicCapabilities`: selectors callable without a role.
- `roleAssignments`: symbolic or literal holders assigned to a role.
- `conditionalOn`: skips an entry when an optional integration is absent; `noPredicateProxy` is the inverse condition used for public deposits.
- `revokeCapabilities` and `revokeRoleAssignments`: declarative removals, processed after additions.

Revocation entries remove obsolete wiring and are therefore not listed as active capabilities above.

`SetupAuthority` resolves role-list names, including `OWNER_ROLE`, `PAUSER_ROLE`, and `DEPOSITOR_ROLE`, and accepts literal addresses for users and targets. Contract ownership is configured separately by the top-level `owner`; `roles.OWNER_ROLE` assigns role 0 without transferring ownership.

The authority configs define the shared permission model. Per-vault holder lists and contract addresses come from `script/deployment-config/vaults/<symbol>.json`. An entry in configuration describes desired wiring; verify the deployed `RolesAuthority` state when auditing a live vault.

For applying or revoking this wiring, see the [operators guide](../operators/README.md#configure-roles-and-capabilities) and [deployment guide](../../script/deploy/README.md#revoking-roles).

## Code references

- [`AuthUpgradeable.sol`](AuthUpgradeable.sol) — upgradeable authorization base and owner bypass.
- [`Constants.sol`](../../script/lib/Constants.sol) — role IDs and names.
- [`authority.json`](../../config/authority/authority.json) — vault-authority capabilities, public capabilities, assignments, and revocations.
- [`common-authority.json`](../../config/authority/common-authority.json) — common-authority capabilities, public capabilities, assignments, and revocations.
- [`SetupAuthority.s.sol`](../../script/setup/SetupAuthority.s.sol) — config resolution and on-chain application.
