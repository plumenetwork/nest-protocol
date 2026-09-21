# Nest signer-message grammar

- Version: `nest-signer-message/1`
- Status: normative
- Copies: `plume-hub:packages/safe-verify/GRAMMAR.md` (verifier), `nest-contracts:docs/signer-message-grammar.md` (generator)

This is the single normative description of the Slack message that accompanies a Nest Safe batch.
The generator writes it; the verifier reads it. Both repositories pin the SHA-256 of this file, so a
copy that drifts fails its own repository's check rather than being silently reinterpreted.

## 1. Version pragma

A canonical message declares its grammar on a line of its own:

```
grammar: nest-signer-message/1
```

- The pragma may appear anywhere in the message, including inside the batch code block.
- Two pragmas declaring different versions make the message ambiguous and are refused.
- A version this verifier does not implement is refused. It is never reinterpreted under an older
  grammar.
- A message with no pragma is a **legacy** message and is read under section 6.

## 2. Message shape

````
:signed: @nestowners
<VAULT> on <ChainName> (<chainId>) — <one sentence of intent>.

*Queue 1 — one Safe batch, op Safe (0xa08a…a982), <N> calls*
```
grammar: nest-signer-message/1
[0] <call line>
[1] <call line>
```
<execution note>
Expected SafeTxHash: 0x…
Transaction: <url>
Simulation: <url>
````

- The first prose line that is not an emoji header, a `*bold*` heading, or a `Key: value` metadata
  line is the **intent sentence**. It is preserved verbatim as untrusted advisory text: it is never
  parsed into a claim and never compared with the proposal.
- Call lines live inside fenced code blocks. A message must declare exactly one call list; two
  independent lists make it undecidable which one the proposal is.
- A fenced block that declares at least one call **is** the call list, and the only other lines it
  may contain are the `grammar:` pragma, blank separators, and whole-line `# …` notes. Any other line
  inside it is refused: a signer reads everything between the fences as the batch, so a line the
  parser skips is a hole in the declaration. A fenced block that declares no calls is not a call list
  and is left alone.
- `Expected SafeTxHash` is read by the proposal-hash layer, not by this grammar.

## 3. Call lines

```
[<index>] <name>(<arguments>) -> <label>(<address>) op=<call|delegatecall> value=<wei> sig=<name(type,type)>
```

- `<index>` runs `0…n-1` in order and must equal the call's position in the batch.
- A nested call — a MultiSend entry's own inner calls, or a timelock `scheduleBatch` /
  `executeBatch` payload — is written on an indented continuation line starting with `└`, `↳` or
  `\_`, carrying no index, and belongs to the nearest less-indented call above it.
- `op=`, `value=` and `sig=` are **mandatory** in this version and may appear in any order after the
  target. `operation=` is accepted as a spelling of `op=`, `signature=` as a spelling of `sig=`.
  `value` is decimal wei.
- Each of the three may be declared **once**. A repeated field is refused — aliases count as the same
  field, and two agreeing declarations are refused as well. A signer reads the whole line, so
  choosing between `value=0` and `value=1` would be the verifier deciding which of two visible claims
  counts.
- `sig=` is the selector's exact preimage, written in canonical ABI spelling
  (`setUserRole(address,uint8,bool)`). A function _name_ is not an identity: `foo(uint256)` and
  `foo(int256)` share it and differ only in the four bytes that decide which one runs, so the
  verifier derives the selector from `sig=` and compares it byte-for-byte with the proposal's. An
  elided list (`seize(...)`) or a type this grammar cannot name pins nothing and is refused. A
  `sig=` whose name disagrees with the head, or one written on an `UNKNOWN` line, makes the line
  self-contradictory and is refused.
- A call whose selector cannot be decoded is written `UNKNOWN 0x12345678 -> <target>`, carries
  `op=`/`value=` like any other call, and takes no `sig=`. This is always reported: a signer who was
  shown `UNKNOWN` was not told what the call does.
- A call that carries no calldata moves native value and nothing else. It has one reserved spelling,
  `nativeTransfer()`, so a message can neither invent a function for it nor hide calldata behind it.
  It takes **no arguments** and no `sig=`: there is no calldata for an argument to describe, so one
  written here could only be an invention. A `sig=` on this head is refused even when it spells the
  head back — the call invokes no function, so naming one is a claim about something that does not
  happen.
- A trailing `# …` note outside every bracket is a comment and is ignored.
- `-> <target>` is required. A call with no declared target cannot be checked against the proposal.

## 4. Argument values

Arguments are `name=value`, comma-separated at bracket depth zero. A `<n> calls` summary token on a
batching call is positional and is compared with the child count, not with an ABI argument.

| Form             | Example                         | Compared against                        |
| ---------------- | ------------------------------- | --------------------------------------- |
| labelled address | `newPT(0x8fAA…b23A)`            | `address`                               |
| full address     | `0x8fAA…` (40 hex)              | `address`                               |
| integer          | `28345500411741`                | `uintN` / `intN`                        |
| duration         | `30s`, `48h`, `172800`          | `uintN` (seconds)                       |
| role             | `15/SEIZER`, `15`               | `uintN`                                 |
| boolean          | `true`, `false`                 | `bool`                                  |
| hex              | `0x3f4ba83a`                    | `bytesN` / `bytes`                      |
| signature        | `pause()`, `blacklist(address)` | `bytes4` (selector)                     |
| string           | `"text"`                        | `string`                                |
| child count      | `4 calls`                       | number of declared and decoded children |

An elided signature such as `seize(...)` is **not** comparable: it is reported rather than guessed.

## 5. Address resolution

A shortened address (`0xAbCd…1234`) is a _query_, never an identity. It resolves only through
**exactly one** candidate in the universe of the proposal's own addresses plus the artifact
catalog's enumerated addresses, and when the message attaches a label that candidate's registry
label must agree. Zero candidates is unresolved, more than one is ambiguous, and a disagreeing label
is a label mismatch. All three are reported; none is narrowed to a plausible guess.

Uniqueness is decided by the number of distinct addresses the short form matches, **before** any
label is read. A label is written by the same message, so allowing it to choose between two real
candidates would let the message decide which address it abbreviated. Two matches are ambiguous even
when only one of them carries the declared label.

A fully written address is its own identity, but a label attached to it must still agree with the
catalog.

## 6. Legacy compatibility

A message with no pragma is read under these explicit defaults, and every defaulted field is marked
as assumed:

- `op` defaults to `call`.
- `value` defaults to `0`.
- `sig` has **no** default. A legacy message pins no selector, so every decodable legacy call carries
  a warning stating that an overload of the same name would read identically. A default here would
  be a guess about which function ran, so there is none.

Both defaults are compared with the proposal exactly like a declared value. A legacy message
therefore **mismatches** when the proposal executes a `delegatecall` or sends a non-zero value: the
message did not say so, and the signer was not told.

Legacy messages additionally tolerate spellings the canonical grammar does not require — aligned
whitespace, `#` notes, `role=15` without a name, `fn=pause()` for a `bytes4` selector, and arguments
renamed for readability. A renamed argument is compared by position and reported.

Reading a message as legacy is itself recorded as a warning, so a report never hides which grammar
produced its conclusions.

## 7. Comparison rules

The verifier compares the declarations with the exact decoded proposal, and with a declared Safe
Transaction Builder artifact when one is supplied:

- Call count and order must be exact, at every nesting level.
- Target, operation, and native value must be exact.
- The declared function name must be the decoded function name. A proposal call that could not be
  decoded cannot be compared and is reported.
- Every declared argument must equal the decoded argument, by name where the names match and by
  position otherwise, including amounts, roles, delays, predecessors, and salts.
- A decoded argument the message never mentions is a warning when the proposal leaves it at an empty
  default and a mismatch when the proposal sets it to anything else. The arguments that _are_ the
  nested calls — `multiSend`'s `transactions`, and `scheduleBatch` / `executeBatch`'s `targets`,
  `values` and `payloads` — are declared structurally by the `└` lines and are compared there.
- The declared function must be the decoded function _by selector_, derived from `sig=`, not by name.
- A declared Transaction Builder artifact is a third declaration. When it carries calldata the
  comparison is byte-exact. It never contributes proposal identity, a hash, or service confirmation.
- An artifact transaction may carry raw calldata and a builder method block at once. Then the two are
  declarations of one call and must agree exactly: the method's own signature must select the
  calldata, and decoding that calldata with the method's declared inputs must reproduce every value
  the builder shows. A pair that disagrees — or that cannot be decoded, which is not a proof either —
  drops the whole transaction. Otherwise the calldata would be compared while the values a signer
  reads in the builder UI went unchecked.
- An artifact transaction whose target, native value, operation, calldata or method types cannot be
  read contributes **no** declaration at all: it is reported and dropped, never defaulted. A native
  value or an operation that is simply _absent_ is unreadable in this sense — reading them as `0` and
  `call` would agree with a zero-value call proposal on two fields the artifact never declared, and
  the operation is the one that decides whose storage the payload writes. The legacy defaults in
  section 6 are for old signer messages only; an artifact never earns them. A `contractMethod` that is present but
  has no readable name and input list is likewise unreadable, and is not silently demoted to a
  raw-calldata transaction, which would skip the proof below. A defaulted
  field is a declaration nobody wrote, and comparing it with the proposal would manufacture agreement
  on exactly the field that was unreadable.
- An artifact written in the builder's method form pins a selector of its own: the declared input
  types are the signature's canonical preimage (`setUserRole` + `address,uint8,bool`), so the full
  signature is rebuilt from them and compared byte-for-byte, exactly like the message's `sig=`. A
  method whose input types cannot be spelled out canonically pins nothing and is refused rather than
  approximated.
- The message and a declared artifact are additionally compared with each other on every field both
  carry: order, count, target, operation, native value, the function identity — the message's `sig=`
  or `UNKNOWN` selector against the selector the artifact pins, whether that comes from its calldata
  or from its method form — and every argument both declare, value by value. The argument **counts**
  are compared first, including when one side declares none: a message showing `foo()` where the
  artifact declares `foo(x=1)` describes a different call. A message that pins no `sig=` cannot be
  checked against the artifact's selector at all, which is reported rather than passed.
- Builder input values are written as **strings**. `JSON.parse` rounds a bare number literal to a
  double before anything can read it, so `9007199254740993` arrives as `9007199254740992` and would
  compare equal to an amount nobody wrote; a number is accepted only inside the safe-integer range,
  where the parse is lossless, and every other representation — an unsafe or fractional number,
  `null`, an object, an array — is unreadable and drops the transaction.
- The dual-form proof compares each value **under its declared ABI type**. Two spellings are one
  value only where the type says so: integer form for the integer types, `true`/`false` casing for
  `bool`, hex casing for `address` and the `bytes` types. A `string` is a byte sequence and is
  compared exactly — `"0xab"` and `"0xAb"` are two different strings, and lowercasing anything
  hex-shaped would prove a builder UI against calldata carrying something else. The same holds for
  numeric-looking and boolean-looking strings. Arrays are compared element by element under the
  element type, except `string[]`, whose rendering cannot be split apart safely and is compared
  exactly. A value that cannot be read under its own declared type is a disagreement, not a pass.
- Artifact calldata that is non-empty but shorter than the four selector bytes pins **no** identity,
  and that is a mismatch, not an unchecked field: a payload the message describes as a function call
  cannot be one. Empty calldata has its own reserved spelling (`nativeTransfer()`); anything between
  the two is a call nobody can name, so the message and the artifact are reported as disagreeing
  rather than passing on the absence of something to compare.
