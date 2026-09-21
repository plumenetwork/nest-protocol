---
name: signer-slack-msg
description: Write the Slack message that accompanies a Safe msig batch for Nest signers — max-decoded call list, intent-first one-line description, expected SafeTxHash, and Transaction/Simulation placeholders. Use when generating slack.md for any msig batch artifact.
---

# Signer Slack message

Audience: Safe signers reviewing before signing. The decoded calls ARE the documentation — the prose states INTENT only, never re-explains individual calls. Follow the curated style of `generated/nBASIS-timelock-migration-v2/56/slack.md` and nCREDIT v2 equivalents.

**Grammar version: `nest-signer-message/1`.** The normative specification is [`docs/signer-message-grammar.md`](../../../docs/signer-message-grammar.md); SafeVerify (`plume-hub:packages/safe-verify/GRAMMAR.md`) reads a byte-identical copy, and both repositories pin its SHA-256. Generated messages MUST declare the pragma and MUST carry an explicit `op=`, `value=` and `sig=` on every call — a message without `op=`/`value=` is parsed under legacy defaults (`op=call value=0`) and mismatches whenever the batch actually delegatecalls or sends value, and one without `sig=` pins no selector, so an overload of the same name reads identically. `sig=` is the canonical ABI signature (`setUserRole(address,uint8,bool)`); the verifier derives its selector and compares it byte-for-byte. Run `pnpm check:signer-grammar` after editing either file.

## Structure (exactly this shape)

````
:signed: @nestowners
<VAULT> on <ChainName> (<chainId>) — <one sentence of intent, ≤2 lines>.

*Queue 1 — one Safe batch, op Safe (0xa08a…a982), <N> calls*
```
grammar: nest-signer-message/1
[0] <fn>(<argName>=<label>(<0xshort…addr>), …) -> <targetLabel>(<0xshort…addr>) op=call value=0 sig=<fn>(<type>,<type>)
[1] …
[k] scheduleBatch(<n> calls, predecessor=0x…, salt=0x…, delay=30s) -> newPT(0x8faa…b23a) op=call value=0 sig=scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)
       └ acceptOwnership() -> accountant(0x5127…8910) op=call value=0 sig=acceptOwnership()
       └ acceptOwnership() -> composer(0x…) op=call value=0 sig=acceptOwnership()
```
<1-2 sentence execution note: what executes now vs what is permissionless later.>
Expected SafeTxHash: <0x… computed from the exact final Safe transaction, including its nonce>
Transaction: <paste Safe tx URL>
Simulation: <paste Tenderly / Den simulation URL>
````

## Rules

- **Intent-first description**: what this batch achieves + where ownership lands. Example: "combined vault implementation upgrade (upgradeAndCall to freshly-deployed impls) + hook/seizer swap to common v2, all surfaces handed to the new Protocol Timelock 0x8fAA…b23A; final call schedules the acceptOwnership batch (executes permissionlessly ≥30s later)." Do NOT enumerate what the calls do — they're listed below.
- **Max decode every call**: function name + named args + symbolic labels for every address (`share`, `vaultAuthority`, `newHook`, `oldSharedSeizer`, `newPT`, `opSafe`, `accountant`, `composer`, `proxyAdmin(share)` …). Address format: `label(0xAbCd…1234)` — first 6 + last 4 hex chars.
- **Nested timelock calls**: `scheduleBatch`/`executeBatch` show inner calls indented with `└`, each decoded the same way.
- Unknown selector: NEVER leave raw calldata silently — decode via `cast 4byte`/ABI and add the label; if genuinely unresolvable, write a complete canonical line whose advisory sits in a `#` comment (the only form the parser ignores) and which carries no `sig=`, because the selector is already stated: `[i] UNKNOWN 0x12345678 -> target(0x…) op=call value=0  # ⚠ decode before signing`.
- Role numbers get meaning inline once, in the documented `<number>/<NAME>` form the parser compares as a number: `role=15/SEIZER`. A parenthesised gloss (`15 (seizer)`) is opaque to the verifier and is reported as uncomparable.
- A call that carries no calldata is written `[i] nativeTransfer() -> recipient(0x…) op=call value=<wei>` — reserved spelling, no arguments, no `sig=`.
- Companion permissionless artifact (accept-execute.json) gets one line in the execution note — not a separate Queue section — since signers don't sign it.
- **Expected SafeTxHash is mandatory**: compute it independently from the exact signer-ready Safe transaction, including the Safe address, chain ID, final nonce, target, value, calldata, operation, and Safe gas/refund fields. Recompute it after any payload or nonce change. A signer-ready message must contain the full `0x` hash, never a placeholder; signers use it as the out-of-band value against which the transaction presented by the signing workflow is verified.
- `Transaction:`/`Simulation:` stay as `<paste …>` placeholders; the proposal workflow fills them after proposing and simulating the exact transaction.
- No @Ruan unless the batch needs council; default header exactly `:signed: @nestowners`.
- Keep total message paste-ready: no markdown headers, use Slack `*bold*` and triple-backtick blocks as shown.
