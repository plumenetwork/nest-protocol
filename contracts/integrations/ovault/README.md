# oVault Cross-Chain Flow

[← Back to repository overview](../../../README.md)

This document describes how Nest vault shares move between chains through LayerZero OFT and the oVault composer. Assets stay on the chain where the vault holds them. Only the share token bridges. This document is for operators and engineers who deploy, wire, and run the cross-chain layer. See the [public cross-chain page](https://app.plume.org/docs/about/cross-chain) for the high-level model.

## Related documentation

- [Cross-chain overview (public)](https://app.plume.org/docs/about/cross-chain) — high-level model.
- [Architecture (public)](https://app.plume.org/docs/about/architecture) — protocol structure.
- [Deployed contracts](https://app.plume.org/docs/developers/smart-contracts) — addresses.
- [CCTP flow](../cctp/README.md) — the asset leg for Solana deposits and redemptions.
- [Deposit and redeem flow](../../README.md) — vault-level deposit and redemption mechanics.
- [Compliance flow](../../compliance/README.md) — predicate checks and the blacklist hook.
- [Roles and authorities](../../auth/README.md) — the complete role, holder, and capability reference.
- [Operators guide](../../operators/README.md) — emergency procedures.
- [Deployment guide](../../../script/deploy/README.md#wiring-peers-across-chains) — deployment and peer wiring procedure.

## User flow

### Send shares between EVM chains

1. Call `quoteSend(sendParam, false)` on the local OApp to get the LayerZero fee.
2. Call `send(sendParam, fee, refundAddress)` on the local OApp. Attach the quoted fee as `msg.value`.
3. The OApp burns the shares on the source chain.
4. The configured DVNs verify the message. The executor delivers it.
5. The destination OApp mints the same number of shares to the recipient.

On `NestVaultOFT` chains, `send` has the `requiresAuth` modifier. The authority config makes it a public capability, so any user can call it.

### Deposit and redeem from Solana

The composer (`NestVaultComposer`) executes vault actions for users on chains without a vault. The asset leg uses CCTP. See [CCTP flow](../cctp/README.md).

Deposit path:

1. The user's USDC moves from Solana through CCTP to the vault chain.
2. The CCTP relayer calls the composer's restricted `depositAndSend(bytes32 depositor, ...)`.
3. The composer deposits through the compliance proxy and receives shares.
4. The composer sends the shares to the user's Solana account through the share OFT.

Redeem path:

1. The user sends shares from Solana to the composer with a compose message.
2. The LayerZero endpoint calls `lzCompose` on the composer.
3. The composer decodes a `RedeemType` from `SendParam.oftCmd` and routes the action:

| `RedeemType` | Action |
|---|---|
| `InstantRedeem` | Redeem now through `instantRedeem`. Send the assets back cross-chain. |
| `RequestRedeem` | Queue the shares in the async redemption book. |
| `UpdateRedeemRequest` | Reduce a pending request. Return the excess shares to the redeemer. |
| `FinishRedeem` | Redeem fulfilled shares. Send the assets cross-chain to the receiver. |

If the compose call fails and is not retryable, the composer refunds the tokens to the source chain. Retryable failures revert. The endpoint can retry them with more value. See [Compose message lifecycle](#compose-message-lifecycle).

## Operator procedures

### Deploy the composer

Run the composer deployment for one vault symbol on the vault chain:

```bash
VAULT_SYMBOL=nTEST forge script script/deploy/DeployComposer.s.sol --sig "runMsig()" --rpc-url $RPC --ffi
```

The script deploys one `NestVaultComposer` per vault entry that needs one. It also deploys `NestCCTPRelayer`, but only on chains with a CCTP config.

### Wire LayerZero peers (EVM)

Complete deployment on every chain in the vault's `peers` array. Then run `SetPeers` on each EVM chain, as described in the [deployment guide](../../../script/deploy/README.md#wiring-peers-across-chains):

```bash
VAULT_SYMBOL=nWISDOM CHAIN_ID=98866 forge script script/setup/SetPeers.s.sol \
    --sig "runMsig()" --rpc-url $RPC --ffi
```

`SetPeers` resolves the remote peer by the peer chain's `vaultType`, not the local one (see [OApp layouts](#oapp-layouts)):

- The peer chain is OFT (`NestVaultOFT`): pair with the peer's canonical vault. `baseAssetOverrides` selects the canonical asset.
- The peer chain is non-OFT (`NestVault`, for example World Chain 480): pair with the peer's share token.
- The peer chain is Solana (chain ID 101): pair with `oftStoreBytes32` from `deployments/solana-mainnet/<SYMBOL>-OFT.json`.

The script skips peer chains without an output file and skips peers that are not deployed. Run the script again after you deploy those chains. The script does not peer non-canonical vaults (for example a pUSD vault next to a canonical USDC vault).

### Verify LayerZero configuration

`SetupL0` is the idempotent LayerZero verifier. It walks every peer chain and queues only the transactions that differ from the on-chain state: `setDelegate`, `setPeer`, `setEnforcedOptions`, `setConfig` (required DVNs), `setSendLibrary`, and `setReceiveLibrary`.

```bash
VAULT_SYMBOL=nTEST forge script script/setup/SetupL0.s.sol --sig "runSourceMsig()" --rpc-url $RPC --ffi
```

`pnpm deploy` already runs this wiring as its LayerZero step. Run `SetupL0` alone only when the deployment ran with a `STEPS` value that excluded `l0`, or to audit drift.

Configuration files:

- `config/layerzero/<chainId>.json` — endpoint, libraries, executor, delegate, DVN triples, and enforced options. A zero `compose.gas` disables the compose option.
- `config/layerzero/vaults/<SYMBOL>.json` — the LayerZero omnigraph for one vault. Generate it. Do not edit it by hand:

```bash
VAULT_SYMBOL=<SYMBOL> pnpm gen:lz-config
```

### Chain decommissioning

`script/setup/DisablePeers.s.sol` severs every LayerZero link that touches a disabled chain. It queues `setPeer(eid, bytes32(0))` on this chain's canonical OApp. The disabled chains are hardcoded: BNB (56), World Chain (480), and Plasma (9745). Pass `EXTRA_DISABLED_CHAIN_IDS=<id,id>` to treat additional chains as disabled.

**Warning:** Run `DisablePeers` on BOTH endpoints of every link that touches a disabled chain — the disabled chains and the survivors. A one-sided cut leaves the reverse peer set, and an in-flight message can land on a chain that rejects its sender. That message becomes stuck.

**Ordering:** Run `DisablePeers` on every affected chain **before** removing the retired chain from the vault config's `peers` array — the script only visits chains it finds in config. If the chain was already removed, pass `EXTRA_DISABLED_CHAIN_IDS=<chainId>` so the script still visits it. To verify, re-run the script: every severed link must log `[SKIP] ... already zero`.

```bash
VAULT_SYMBOL=nALPHA CHAIN_ID=56 forge script script/setup/DisablePeers.s.sol \
    --sig "runMsig()" --rpc-url $BSC_RPC_URL --ffi
```

On a disabled chain, the script zeroes all peers. On a survivor chain, it zeroes only peers that point to disabled chains. The script also zeroes EVM-to-Solana links that touch a disabled chain. The Solana program stores its own peers in a PDA. Zero them separately with `lz:oft:solana:unsetpeers`.

### Composer runtime operations

All state-changing composer functions use `requiresAuth`. The authority config (`config/authority/authority.json`) grants them as follows. Role numbers come from `script/lib/Constants.sol`.

| Function | Caller | Purpose |
|---|---|---|
| `depositAndSend(uint256, SendParam, address)` | Public capability | Deposit assets, send shares cross-chain. |
| `redeemAndSend(uint256, SendParam, address)` | Public capability | Instant-redeem shares, send assets cross-chain. |
| `depositAndSend(bytes32, uint256, SendParam, address)` | Role 13 `RELAYER_ROLE` (the CCTP relayer) | Deposit for a named depositor. The `bytes32` depositor feeds predicate verification, not access control. |
| `redeemAndSend(bytes32, uint256, SendParam, address)` | Role 13 `RELAYER_ROLE` | Instant-redeem for a named redeemer. |
| `fulfillRedeem(uint32, bytes32, bytes32, uint256)` | Role 11 `CAN_SOLVE_ROLE` (also the redeem operator) | Fulfill a pending request for one (redeemer, receiver) pair. |
| `updateRequestRedeemAndSend(...)` | Role 14 `KEEPER_ROLE` | Reduce a pending request. Return the excess shares. |
| `finishRedeemAndSend(...)` | Role 14 `KEEPER_ROLE` | Claim fulfilled assets. Send them cross-chain. |
| `blockCompose(bytes32)` / `unblockCompose(bytes32)` | Role 0 `OWNER_ROLE` | Block or unblock one compose GUID. |
| `setMaxRetryableValue(uint256)` | Role 0 `OWNER_ROLE` | Set the retryable `minMsgValue` threshold. |
| `recover(address, uint256, bytes)` | Role 0 `OWNER_ROLE` | Recover stranded ETH or tokens through an arbitrary call. |

The composer itself holds role 12 `COMPOSER_ROLE` on the vault. That role grants the vault calls it needs: `fulfillRedeem`, `instantRedeem`, `requestRedeem`, `updateRedeem`, `redeem`, and `send`.

### Solana OFT operations

The Solana share token is an OFT program under `programs/oft/` (Anchor). Deployment artifacts live in `deployments/solana-mainnet/<SYMBOL>-OFT.json` (`programId`, `mint`, `oftStore`, `oftStoreBytes32`). The Hardhat task layer lives in `tasks/solana/` and `tasks/common/`.

| Task | Purpose |
|---|---|
| `lz:oft:solana:create` | Mint the SPL token and create the OFT store. With additional minters, it sets the mint authority to an SPL multisig. |
| `lz:oft:solana:init-config` | Initialize the Solana OFT accounts for each connection. |
| `lz:oapp:wire` | Wire peers and configs from `config/layerzero/vaults/<SYMBOL>.json`. Accepts `--multisig-key` to route Solana transactions through a multisig. |
| `lz:oft:solana:setdelegate` / `getdelegate` | Set or read the endpoint delegate. |
| `lz:oft:solana:setadmin` / `getadmin` | Set or read the OFT store admin. |
| `lz:oft:solana:setenforcedoptions` / `getenforceoptions` | Set or read enforced options. |
| `lz:oft:solana:get-rate-limits` | Read inbound and outbound rate limits. |
| `lz:oft:solana:update-metadata` | Update the token metadata. |
| `lz:oft:solana:unsetpeers` | Zero the Solana-side peers (the PDA leg of decommissioning). |
| `lz:oft:nest:deposit` / `redeem` / `request-redeem` / `instant-redeem` | Drive the user flows from Solana for testing and support. |
| `lz:oft:send` | Plain OFT share send between chains. |

`dist/nest-solana-deploy/` is a generated, runnable copy of this task layer. Do not edit it. The sources stay in `tasks/` and `script/`.

### pUSD bridge (non-base-asset OFT)

`script/deploy/DeployPusdBridge.s.sol` deploys a `NestVaultOFT` for a non-base asset (for example pUSD next to a canonical USDC vault) and wires one destination. It differs from the standard wiring. It writes a full custom ULN config with explicit confirmations (`CONFIRMATIONS`, default 5) and two required DVNs (LZ and Nethermind, no Canary). It queues `TELLER_ROLE` for the vault on the vault's RolesAuthority and transfers ownership to the multisig. It first sets the accountant's `RateProviderData` for the asset from the vault entry's reviewed `isPegged`/`rateProvider` values when no usable quote exists yet. Before peer wiring, it verifies over the destination chain's RPC (the `.rpc` env var in `config/common/<DEST_CHAIN_ID>.json`, e.g. `PLUME_RPC_URL`) that code exists at the same CREATE3 address and that the destination vault peers back to this chain. Env: `VAULT_SYMBOL`, `ASSET_SYMBOL`, `CHAIN_ID`, `DEST_CHAIN_ID`, `NEW_OWNER`, `CONFIRMATIONS`, `PRIVATE_KEY`, `SKIP_DEST_PREFLIGHT` (optional). `SKIP_DEST_PREFLIGHT=true` bypasses the remote checks for the first leg of a two-chain bootstrap; run the script on both chains, and do not enable public `send` until a run passes with the preflight on.

## Mechanics reference

### OApp layouts

Each chain runs one LayerZero OApp per vault symbol. The vault config field `vaultType` (in `script/deployment-config/vaults/<SYMBOL>.json`) selects the layout. The field `vaultTypeOverrides` changes the layout for specific chains.

| `vaultType` | OApp contract | Share token | Example |
|---|---|---|---|
| `NestVaultOFT` | The canonical vault (`NestVaultOFT`) | `NestShareOFT` (not an OApp) | Most chains |
| `NestVault` | The share token (`NestShareOFT`) | Same contract | World Chain (480) for nALPHA |

Both layouts burn shares on the source chain and mint shares on the destination chain. `NestVaultOFT._debit` calls `NestShareOFT.exit` with zero assets. `NestVaultOFT._credit` calls `NestShareOFT.enter` with zero assets.

### Compose message lifecycle

A compose message carries `abi.encode(SendParam, uint256 minMsgValue)`. `lzCompose` accepts calls only from the endpoint and only for the asset OFT or the share OFT as compose sender. It rejects blocked GUIDs. It then self-calls `handleAsyncCompose` inside `try/catch`:

- Success: emit `Sent(guid)`.
- Failure, retryable (`InsufficientMsgValue` and `minMsgValue <= maxRetryableValue`): revert. The endpoint keeps the compose message, and a retry with more value can succeed.
- Failure, not retryable: refund the tokens to the source chain and emit `Refunded(guid)`.

Asset-OFT compose messages route to `_depositAndSend`. Share-OFT compose messages route by `RedeemType` (one ABI-encoded word in `SendParam.oftCmd`). When the destination is the local chain (`dstEid == VAULT_EID()`), the composer settles locally without a LayerZero send.

### Async redemption bookkeeping

The composer tracks requests per `(redeemer, receiver)` pair and source endpoint: `pendingRedeem` and `claimableRedeem`, keyed by `keccak256(abi.encode(redeemer, receiver))`. The vault-side controller is always the composer itself. `fulfillRedeem` first absorbs any claimable balance that a direct `vault.fulfillRedeem` call created outside the composer, then fulfills only the remainder on the vault. `updateRequestRedeemAndSend` returns excess shares to the redeemer (the main account), never to the receiver token account. `finishRedeemAndSend` withdraws at the pair's recorded share-to-asset ratio and sends the assets through the asset OFT.

### Deposits and quotes

Composer deposits go through the public `ComplianceProxy.depositOnBehalf` entrypoint. The composer is the executing sender and the original source-chain account is passed as the `bytes32` depositor. Provider-specific compliance data arrives in `SendParam.oftCmd` and is forwarded opaquely to the proxy. See [Compliance architecture](../../compliance/docs/ComplianceProxy.md). `quoteSend` uses `previewInstantRedeem` on the redeem path, so the quote includes the instant redemption fee. It uses `previewDeposit` on the deposit path.

### DVN and library configuration

Standard routes require the three DVNs from the chain config triple (`lz`, `nethermind`, `canary`), sorted ascending. `SetupL0` pins `sendLib302` and `receiveLib302` explicitly, so a LayerZero default-library change cannot silently alter the security stack. Enforced options set message-type 1 (send) gas and message-type 2 (compose) gas per destination from the destination chain's config file.

## Security

See the [security policy (public)](https://app.plume.org/docs/security-and-compliance/security-policy) for the disclosure posture. The controls below are the cross-chain levers in this repo. [Operators guide](../../operators/README.md) has the full emergency table.

- **Share freeze.** `BlacklistHook.pause()` makes `beforeTransfer` revert. On chains where the share token has the hook, this stops transfers, burns, and outbound OFT sends. `NestVaultOFT._debit` also calls the hook. The hook does not block mints. Use the hook pause because an accountant pause does not stop OFT sends.
- **Per-address block.** `BlacklistHook.blacklist(address)` blocks one sender from transfers and bridges. `unblacklist(address)` reverses it. The authority config can grant each function to a different role. See [Compliance flow](../../compliance/README.md).
- **Per-vault send disable.** Call `RolesAuthority.setPublicCapability(vault, send.selector, false)` from the Safe. This stops new `send` calls on one `NestVaultOFT` vault. It is a manual authority change, not a dedicated pauser. It does not apply on chains where the share token is the OApp, because `NestShareOFT.send` is the standard public OFT entry point.
- **Surgical compose block.** `blockCompose(guid)` blocks one compose message. `unblockCompose(guid)` releases it. Other messages are not affected.
- **In-flight messages survive.** No pause or peer change recalls a message already in transit. `DisablePeers` on one side only can strand messages (see the warning above). Drain the pipeline before a cut-over.
- **Monitoring-worthy events.** Changes to peers (`setPeer`), delegates (`setDelegate`), DVN or library config (`setConfig`, `setSendLibrary`, `setReceiveLibrary`), enforced options, and the share hook alter the bridge trust assumptions. Treat them as alert-level events.
- **`recover` is powerful.** It executes an arbitrary call from the composer. It is owner-gated (role 0). Keep it Safe-only.

## Code references

- `contracts/NestShareOFT.sol` — share token, `enter`/`exit` mint-burn, transfer hook, and EIP-1271 signer.
- `contracts/NestVaultOFT.sol` — vault as OApp with `_debit`/`_credit` overrides.
- `contracts/NestVault.sol` — non-OFT vault variant (share token is the OApp).
- `contracts/integrations/ovault/NestVaultComposer.sol` — Nest composer: predicate deposits, async redeem entry points, admin levers.
- `contracts/vendor/ovault/VaultComposerAsyncUpgradeable.sol` — compose lifecycle, redeem bookkeeping, refund and retry logic.
- `contracts/vendor/ovault/VaultComposerSyncUpgradeable.sol` — base composer: deposit/redeem-and-send, local settlement.
- `contracts/compliance/hooks/BlacklistHook.sol` — pause and blacklist enforcement on share movement.
- `script/setup/SetupL0.s.sol`, `script/setup/SetPeers.s.sol`, `script/setup/DisablePeers.s.sol` — wiring, verification, decommissioning.
- `script/deploy/DeployComposer.s.sol`, `script/deploy/DeployPusdBridge.s.sol` — deployments.
- `config/layerzero/`, `config/authority/authority.json` — LayerZero and role configuration.
- `tasks/solana/`, `tasks/common/`, `programs/oft/`, `deployments/solana-mainnet/` — Solana task layer, program, artifacts.
