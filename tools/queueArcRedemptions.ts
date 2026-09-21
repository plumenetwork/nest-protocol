#!/usr/bin/env ts-node
/** Prepare/simulate the Arc public-redemption correction; --submit queues it without executing. */
import "dotenv/config";
import fs from "node:fs";
import path from "node:path";
import SafeApiKit from "@safe-global/api-kit";
import { getMultiSendCallOnlyDeployment } from "@safe-global/safe-deployments";
import {
  concatHex,
  createPublicClient,
  encodeAbiParameters,
  encodeFunctionData,
  hashTypedData,
  http,
  keccak256,
  pad,
  parseAbi,
  toFunctionSelector,
  toHex,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  isAuthorizedProposer,
  proposeBatch,
  type ProposeResult,
  type SafeTx,
} from "./safePropose";
import { serviceFor } from "./safeTxService";
import { encodeMultiSend } from "./tenderlySafeSim";
import { ABI as SAFE_ABI, TYPES, tenderly } from "./prepareArcAnnouncements";
import { simulateAndSubmit } from "./proposeArc";

const ROOT = path.resolve(__dirname, "..");
const CHAIN_ID = 5042;
export const SIGNATURES = [
  "requestRedeem(uint256,address,address)",
  "instantRedeem(uint256,address,address)",
  "requestRedeemWithPermit2(uint256,address,address,uint256,uint256,bytes)",
  "instantRedeemWithPermit2(uint256,address,address,uint256,uint256,bytes)",
] as const;
export const AUTH_ABI = parseAbi([
  "function authority() view returns(address)",
  "function owner() view returns(address)",
  "function isCapabilityPublic(address,bytes4) view returns(bool)",
  "function setPublicCapability(address target,bytes4 functionSig,bool enabled)",
]);
export type Vault = { symbol: string; vault: Address; authority: Address };
type Journal = {
  symbol: string;
  safe: Address;
  batchHash: Hex;
  prepared: ProposeResult;
  simulation?: string;
  proposed: boolean;
};
const equal = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();
const read = (file: string) => JSON.parse(fs.readFileSync(file, "utf8"));
function write(file: string, data: unknown) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(
    `${file}.tmp`,
    typeof data === "string"
      ? data
      : JSON.stringify(
          data,
          (_, v) => (typeof v === "bigint" ? String(v) : v),
          2,
        ) + "\n",
  );
  fs.renameSync(`${file}.tmp`, file);
}
function nonceNumber(value: unknown) {
  const nonce = Number(value);
  if (!Number.isSafeInteger(nonce) || nonce < 0)
    throw new Error("Invalid Safe nonce");
  return nonce;
}
export function loadVaults(root = ROOT): Vault[] {
  return ["nOPAL", "nFALCON", "FACTOR"].map((symbol) => {
    const config = read(
      path.join(root, `script/deployment-config/vaults/${symbol}.json`),
    );
    const vaults = config.contracts.vaults.filter((v: any) =>
      v.chains.includes(CHAIN_ID),
    );
    if (vaults.length !== 1 || vaults[0].assetSymbol !== "USDC")
      throw new Error(`Unexpected Arc vault configuration: ${symbol}`);
    return {
      symbol,
      vault: vaults[0].address,
      authority: config.contracts.rolesAuthority,
    };
  });
}
export function buildCalls(vaults: Vault[]): SafeTx[] {
  return vaults.flatMap((v) =>
    SIGNATURES.map((signature) => ({
      to: v.authority,
      operation: "0",
      value: "0",
      data: encodeFunctionData({
        abi: AUTH_ABI,
        functionName: "setPublicCapability",
        args: [v.vault, toFunctionSelector(signature), true],
      }),
    })),
  );
}
/** RolesAuthority inherits owner/authority slots 0/1; isCapabilityPublic is the nested mapping at slot 3. */
export function publicCapabilitySlot(vault: Address, signature: string): Hex {
  const outer = keccak256(
    encodeAbiParameters(
      [{ type: "address" }, { type: "uint256" }],
      [vault, 3n],
    ),
  );
  return keccak256(
    encodeAbiParameters(
      [{ type: "bytes4" }, { type: "bytes32" }],
      [toFunctionSelector(signature), outer],
    ),
  );
}
export function assertSimulation(result: any, vaults: Vault[]) {
  if (
    result.simulation?.status !== true ||
    result.transaction?.status === false ||
    result.transaction?.transaction_info?.call_trace?.output !==
      pad("0x01", { size: 32 })
  )
    throw new Error(
      "Safe simulation did not execute successfully and return true",
    );
  const raw = (result.transaction.transaction_info.state_diff ?? []).flatMap(
    (entry: any) => entry.raw ?? [],
  );
  for (const v of vaults) {
    const expected = SIGNATURES.map((s) => publicCapabilitySlot(v.vault, s));
    const changed = raw.filter((r: any) => equal(r.address, v.authority));
    if (
      changed.length !== expected.length ||
      changed.some((r: any) => !expected.includes(r.key))
    )
      throw new Error(`Unexpected authority storage changes: ${v.symbol}`);
    for (const slot of expected) {
      if (
        !changed.some(
          (r: any) =>
            r.key === slot &&
            BigInt(r.original) === 0n &&
            BigInt(r.dirty) === 1n,
        )
      )
        throw new Error(
          `Missing public redemption permission: ${v.symbol} ${slot}`,
        );
    }
  }
}
export function assertNonceAvailable(
  chainNonce: number,
  nextNonce: number,
  nonce: number,
  existing: any,
  queued: { safeTxHash: string }[],
  hash: string,
) {
  if (existing?.isExecuted || nonce < chainNonce)
    throw new Error("Safe transaction already executed or nonce consumed");
  if (
    (!existing && nonce < nextNonce) ||
    queued.some((t) => !equal(t.safeTxHash, hash))
  )
    throw new Error(
      "Safe nonce is occupied; use a new --dir to prepare a fresh transaction",
    );
}
export function signerMessage(vaults: Vault[], journal: Journal): string {
  const label = (name: string, address: string) =>
    `${name}(${address.slice(0, 8)}…${address.slice(-4)})`;
  const lines = vaults.flatMap((v, i) =>
    SIGNATURES.map(
      (s, j) =>
        `[${i * 4 + j}] setPublicCapability(target=${label(`${v.symbol}.vault`, v.vault)}, functionSig=${s}, enabled=true) -> ${label(`${v.symbol}.vaultAuthority`, v.authority)} op=call value=0 sig=setPublicCapability(address,bytes4,bool)`,
    ),
  );
  return `:signed: @nestowners
nOPAL, nFALCON and FACTOR on Arc (5042) — restore standard public redemptions; vault authorities remain owned by ${label("opSafe", journal.safe)}.

*Queue 1 — one Safe batch, op Safe (${journal.safe.slice(0, 8)}…${journal.safe.slice(-4)}), nonce ${journal.prepared.nonce}, ${lines.length} calls*
\`\`\`
grammar: nest-signer-message/1
${lines.join("\n")}
\`\`\`
Execute as one atomic Safe batch. Deposit/mint compliance remains enabled. Simulation uses live vault/authority state with an impersonated existing Safe owner and Safe threshold=1/nonce=${journal.prepared.nonce} overrides; queued proposals are not replayed. This validates the permission changes, not redemption payouts; instant redemptions still require liquidity.
Expected SafeTxHash: ${journal.prepared.safeTxHash}
Transaction: ${journal.proposed ? journal.prepared.uiUrl : "<paste Safe tx URL after --submit>"}
Simulation: ${journal.simulation ?? "<paste Tenderly simulation URL>"}
`;
}

export async function main() {
  const args = process.argv.slice(2);
  if (args.includes("--help")) {
    console.log(
      "Usage: pnpm queue:arc-redemptions [--submit] [--dir PATH]\nDefault: prepare, simulate and write slack.md. --submit also signs and queues the exact simulated Safe transaction. Never executes on-chain or posts Slack.\nRequired: ARC_RPC_URL, PRIVATE_KEY (or ARC_SAFE_PROPOSER_PRIVATE_KEY), TENDERLY_ACCOUNT, TENDERLY_PROJECT, TENDERLY_ACCESS_KEY.",
    );
    return;
  }
  let submit = false;
  let dir = path.join(ROOT, "generated/arc-public-redemptions/queue");
  for (let i = 0; i < args.length; ++i) {
    if (args[i] === "--submit") submit = true;
    else if (args[i] === "--dir" && args[i + 1])
      dir = path.resolve(ROOT, args[++i]);
    else throw new Error("Unknown argument; use --help");
  }
  const rpcUrl = process.env.ARC_RPC_URL;
  const rawKey =
    process.env.ARC_SAFE_PROPOSER_PRIVATE_KEY ?? process.env.PRIVATE_KEY;
  if (!rpcUrl || !rawKey)
    throw new Error("ARC_RPC_URL and a proposer private key are required");
  const signerKey = (rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`) as Hex;
  const proposer = privateKeyToAccount(signerKey).address;
  const client = createPublicClient({ transport: http(rpcUrl) });
  if ((await client.getChainId()) !== CHAIN_ID)
    throw new Error("RPC must target Arc 5042");
  const safe = read(path.join(ROOT, "config/common/5042.json")).common
    .multisig as Address;
  const owners = await client.readContract({
    address: safe,
    abi: SAFE_ABI,
    functionName: "getOwners",
  });
  if (
    !owners.some((o) => equal(o, proposer)) &&
    (await isAuthorizedProposer(CHAIN_ID, safe, proposer)) !== true
  )
    throw new Error("Proposer must be a Safe owner or registered Arc delegate");
  const vaults = loadVaults();
  const txs = buildCalls(vaults);
  const batchHash = keccak256(encodeMultiSend(txs));
  const api = new SafeApiKit({
    chainId: BigInt(CHAIN_ID),
    txServiceUrl: serviceFor(CHAIN_ID).api,
  });
  fs.mkdirSync(dir, { recursive: true });
  const lock = path.join(dir, ".queue.lock");
  const fd = fs.openSync(lock, "wx");
  try {
    const preflight = async () => {
      const block = await client.getBlockNumber();
      const states = [];
      for (const v of vaults) {
        const authority = await client.readContract({
          address: v.vault,
          abi: AUTH_ABI,
          functionName: "authority",
          blockNumber: block,
        });
        const owner = await client.readContract({
          address: v.authority,
          abi: AUTH_ABI,
          functionName: "owner",
          blockNumber: block,
        });
        if (!equal(authority, v.authority) || !equal(owner, safe))
          throw new Error(`Arc authority/owner mismatch: ${v.symbol}`);
        const signatures = [
          ...SIGNATURES,
          "deposit(uint256,address)",
          "mint(uint256,address)",
        ];
        const flags = await Promise.all(
          signatures.map((signature) =>
            client.readContract({
              address: v.authority,
              abi: AUTH_ABI,
              functionName: "isCapabilityPublic",
              args: [v.vault, toFunctionSelector(signature)],
              blockNumber: block,
            }),
          ),
        );
        if (flags.some(Boolean))
          throw new Error(
            `Permissions changed or already enabled: ${v.symbol}; review live state`,
          );
        states.push({ ...v, owner, signatures, publicAccess: flags });
      }
      return { block: String(block), states };
    };
    write(path.join(dir, "preflight.json"), await preflight());
    const journalFile = path.join(dir, "proposal.json");
    const previous: Journal | undefined = fs.existsSync(journalFile)
      ? read(journalFile)
      : undefined;
    if (
      previous &&
      (!equal(previous.safe, safe) || previous.batchHash !== batchHash)
    )
      throw new Error("Prepared batch changed; use a new --dir");
    const chainNonce = nonceNumber(
      await client.readContract({
        address: safe,
        abi: SAFE_ABI,
        functionName: "nonce",
      }),
    );
    const nextNonce = Math.max(
      chainNonce,
      nonceNumber(await api.getNextNonce(safe)),
    );
    const nonce = previous?.prepared.nonce ?? nextNonce;
    const prepared = await proposeBatch({
      chainId: CHAIN_ID,
      safe,
      txs,
      signerKey,
      rpcUrl,
      nonce,
      dryRun: true,
      expectedSafeTxHash: previous?.prepared.safeTxHash,
    });
    const tx = prepared.transactionData;
    const hashArgs = [
      tx.to as Address,
      BigInt(tx.value),
      tx.data as Hex,
      tx.operation,
      BigInt(tx.safeTxGas),
      BigInt(tx.baseGas),
      BigInt(tx.gasPrice),
      tx.gasToken as Address,
      tx.refundReceiver as Address,
      BigInt(tx.nonce),
    ] as const;
    const independentHash = hashTypedData({
      domain: { chainId: CHAIN_ID, verifyingContract: safe },
      types: TYPES,
      primaryType: "SafeTx",
      message: {
        to: hashArgs[0],
        value: hashArgs[1],
        data: hashArgs[2],
        operation: tx.operation,
        safeTxGas: hashArgs[4],
        baseGas: hashArgs[5],
        gasPrice: hashArgs[6],
        gasToken: hashArgs[7],
        refundReceiver: hashArgs[8],
        nonce: hashArgs[9],
      },
    });
    const onchainHash = await client.readContract({
      address: safe,
      abi: SAFE_ABI,
      functionName: "getTransactionHash",
      args: hashArgs,
    });
    if (
      !equal(independentHash, prepared.safeTxHash) ||
      !equal(onchainHash, independentHash)
    )
      throw new Error("SafeTxHash cross-check failed");
    const canonical = (
      getMultiSendCallOnlyDeployment({ version: "1.3.0" }) as any
    ).deployments.canonical;
    const multiSendCode = await client.getCode({
      address: prepared.multiSendAddress,
    });
    if (
      prepared.safeVersion !== "1.3.0" ||
      !multiSendCode ||
      keccak256(multiSendCode) !== canonical.codeHash
    )
      throw new Error("Unreviewed Safe/MultiSend deployment");
    const lookup = await fetch(
      `${serviceFor(CHAIN_ID).api}/v1/multisig-transactions/${prepared.safeTxHash}/`,
      { signal: AbortSignal.timeout(20000) },
    );
    if (!lookup.ok && lookup.status !== 404)
      throw new Error(`Safe proposal lookup failed: HTTP ${lookup.status}`);
    const existing = lookup.ok ? await lookup.json() : undefined;
    const queued = await api.getMultisigTransactions(safe, {
      nonce: String(nonce),
    });
    assertNonceAvailable(
      chainNonce,
      nextNonce,
      nonce,
      existing,
      queued.results,
      prepared.safeTxHash,
    );
    if (previous?.proposed && !existing)
      throw new Error("Previously submitted proposal missing from service");
    const journal: Journal = {
      symbol: "Arc public redemptions",
      safe,
      batchHash,
      prepared,
      proposed: !!existing,
    };
    const save = () => write(journalFile, journal);
    save();
    write(path.join(dir, "safe-batch.json"), {
      version: "1.0",
      chainId: "5042",
      createdAt: Date.now(),
      meta: { name: "Arc public redemptions", createdFromSafeAddress: safe },
      transactions: txs,
    });
    write(path.join(dir, "safe-transaction.json"), prepared);
    write(path.join(dir, "hash-verification.json"), {
      sdkHash: prepared.safeTxHash,
      independentHash,
      onchainHash,
    });
    write(
      path.join(dir, "address-book.json"),
      Object.fromEntries(
        vaults
          .flatMap((v) => [
            [`${v.symbol}.vault`, v.vault],
            [`${v.symbol}.vaultAuthority`, v.authority],
          ])
          .concat([["opSafe", safe]]),
      ),
    );
    await simulateAndSubmit(
      journal,
      {
        save,
        simulate: async () => {
          const state = await preflight();
          const signatures = concatHex([
            pad(owners[0], { size: 32 }),
            pad("0x00", { size: 32 }),
            "0x01",
          ]);
          const request = {
            network_id: "5042",
            block_number: Number(state.block),
            from: owners[0],
            to: safe,
            input: encodeFunctionData({
              abi: SAFE_ABI,
              functionName: "execTransaction",
              args: [...hashArgs.slice(0, 9), signatures] as [
                Address,
                bigint,
                Hex,
                number,
                bigint,
                bigint,
                bigint,
                Address,
                Address,
                Hex,
              ],
            }),
            value: "0",
            gas: 30000000,
            gas_price: "0",
            save: true,
            save_if_fails: true,
            state_objects: {
              [safe]: {
                storage: {
                  [pad("0x04", { size: 32 })]: pad("0x01", { size: 32 }),
                  [pad("0x05", { size: 32 })]: pad(toHex(nonce), { size: 32 }),
                },
              },
            },
          };
          write(path.join(dir, "simulation-request.json"), request);
          const result = await tenderly("simulate", request);
          write(path.join(dir, "simulation-response.json"), result);
          assertSimulation(result, vaults);
          const id = result.simulation?.id;
          if (typeof id !== "string" || !/^[a-zA-Z0-9-]+$/.test(id))
            throw new Error("Missing simulation ID");
          await tenderly(`simulations/${id}/share`, {});
          return `https://dashboard.tenderly.co/shared/simulation/${id}`;
        },
        submit: async () => {
          await preflight();
          const nowNonce = nonceNumber(
            await client.readContract({
              address: safe,
              abi: SAFE_ABI,
              functionName: "nonce",
            }),
          );
          const nowQueued = await api.getMultisigTransactions(safe, {
            nonce: String(nonce),
          });
          assertNonceAvailable(
            nowNonce,
            nonce,
            nonce,
            undefined,
            nowQueued.results,
            prepared.safeTxHash,
          );
          return proposeBatch({
            chainId: CHAIN_ID,
            safe,
            txs,
            signerKey,
            rpcUrl,
            nonce,
            expectedSafeTxHash: prepared.safeTxHash,
          });
        },
      },
      !submit,
    );
    write(path.join(dir, "slack.md"), signerMessage(vaults, journal));
    console.log(
      `${journal.proposed ? "Queued" : "Prepared (not queued)"}: Arc Safe nonce ${nonce}, ${txs.length} calls\nSafeTxHash: ${prepared.safeTxHash}\nTransaction: ${journal.proposed ? prepared.uiUrl : "run with --submit"}\nSimulation: ${journal.simulation}\nSlack: ${path.join(dir, "slack.md")}`,
    );
  } finally {
    fs.closeSync(fd);
    fs.rmSync(lock, { force: true });
  }
}
if (require.main === module)
  main().catch((e) => {
    console.error(e.shortMessage ?? e.message);
    process.exitCode = 1;
  });
