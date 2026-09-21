#!/usr/bin/env ts-node
/** Propose Arc ownership acceptances only after real deployer nominations. Never executes Safe transactions. */
import "dotenv/config";
import fs from "node:fs";
import path from "node:path";
import SafeApiKit from "@safe-global/api-kit";
import {
  createPublicClient,
  http,
  hashTypedData,
  encodeFunctionData,
  concatHex,
  pad,
  toHex,
  keccak256,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { getMultiSendCallOnlyDeployment } from "@safe-global/safe-deployments";
import {
  proposeBatch,
  isAuthorizedProposer,
  type ProposeResult,
  type SafeTx,
} from "./safePropose";
import { serviceFor } from "./safeTxService";
import { encodeMultiSend } from "./tenderlySafeSim";
import {
  ABI,
  TYPES,
  tenderly,
  validateAcceptanceBatch,
  assertAcceptanceResult,
} from "./prepareArcAnnouncements";

const ROOT = path.resolve(__dirname, "..");
const SYMBOLS = ["nOPAL", "nFALCON", "FACTOR", "nCOMMON"];
const read = (f: string) => JSON.parse(fs.readFileSync(f, "utf8"));
const write = (f: string, data: unknown) => {
  fs.mkdirSync(path.dirname(f), { recursive: true });
  const text =
    typeof data === "string"
      ? data
      : JSON.stringify(
          data,
          (_, v) => (typeof v === "bigint" ? String(v) : v),
          2,
        ) + "\n";
  fs.writeFileSync(`${f}.tmp`, text);
  fs.renameSync(`${f}.tmp`, f);
};
const equal = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();
const number = (n: unknown) => {
  const v = Number(n);
  if (!Number.isSafeInteger(v) || v < 0) throw new Error("Invalid Safe nonce");
  return v;
};
type Journal = {
  symbol: string;
  safe: Address;
  batchHash: Hex;
  prepared: ProposeResult;
  simulation?: string;
  proposed: boolean;
  executed?: boolean;
};

export function requireNominations(
  states: { to: string; pendingOwner: string; owner: string }[],
  safe: string,
) {
  for (const state of states) {
    if (equal(state.owner, safe))
      throw new Error(
        `${state.to} is already Safe-owned; do not propose acceptOwnership again`,
      );
    if (!equal(state.pendingOwner, safe))
      throw new Error(
        `${state.to} has not nominated the Arc Safe. Broadcast the deployer ownership handoff first.`,
      );
  }
}

export async function simulateAndSubmit(
  journal: Journal,
  deps: {
    simulate: () => Promise<string>;
    submit: () => Promise<ProposeResult>;
    save: () => void;
  },
  dryRun: boolean,
) {
  journal.simulation = await deps.simulate();
  if (
    !journal.simulation.startsWith(
      "https://dashboard.tenderly.co/shared/simulation/",
    )
  )
    throw new Error("No successful shared simulation");
  deps.save();
  if (!dryRun && !journal.proposed) {
    const result = await deps.submit();
    if (!equal(result.safeTxHash, journal.prepared.safeTxHash))
      throw new Error("Submitted SafeTxHash mismatch");
    journal.proposed = true;
    deps.save();
  }
}

export function signerMessage(
  j: Journal,
  txs: SafeTx[],
  names: string[],
  index: number,
) {
  const label = (n: string, a: string) =>
    `${n}(${a.slice(0, 8)}…${a.slice(-4)})`;
  return `:signed: @nestowners\n${j.symbol === "nCOMMON" ? "Shared PredicateV2 infrastructure" : j.symbol} on Arc (5042) — complete ownership acceptance into ${label("opSafe", j.safe)}.\n\n**Queue ${index + 1} — one Safe batch, nonce ${j.prepared.nonce}, ${txs.length} calls**\n\n\`\`\`\ngrammar: nest-signer-message/1\n${txs.map((t, i) => `[${i}] acceptOwnership() -> ${label(names[i], t.to)} op=call value=0 sig=acceptOwnership()`).join("\n")}\n\`\`\`\n\nThe deployer nominations were checked on Arc. Execute as one atomic Safe batch${j.symbol === "nCOMMON" ? "; accept shared infrastructure last" : ""}. Simulation uses live target ownership state, an impersonated existing Safe owner and Safe threshold=1/nonce=${j.prepared.nonce} overrides; no target ownership overrides or simulated deployer nominations. Other queued Safe proposals are not replayed.\n\nExpected SafeTxHash: ${j.prepared.safeTxHash}\n\nTransaction: ${j.proposed ? `[View Safe transaction](${j.prepared.uiUrl})` : "Not proposed — dry run"}\n\nSimulation: [View Tenderly simulation](${j.simulation})\n`;
}

export async function main() {
  const args = process.argv.slice(2);
  if (args.includes("--help")) {
    console.log(
      "Usage: pnpm propose:arc [nOPAL|nFALCON|FACTOR|nCOMMON] [--dry-run] [--dir path]\nDefault: propose all four acceptance batches after real ownership nominations. Never executes on-chain.",
    );
    return;
  }
  let dryRun = false;
  let dir = path.join(ROOT, "generated/arc-deployment-2026-09-11");
  let symbol: string | undefined;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--dry-run") dryRun = true;
    else if (a === "--dir" && args[i + 1]) dir = path.resolve(ROOT, args[++i]);
    else if (SYMBOLS.includes(a) && !symbol) symbol = a;
    else throw new Error("Unknown argument; use --help");
  }
  const service = serviceFor(5042);
  const rpcUrl = process.env.ARC_RPC_URL;
  if (!rpcUrl) throw new Error("ARC_RPC_URL is required");
  const rawKey =
    process.env.ARC_SAFE_PROPOSER_PRIVATE_KEY ?? process.env.PRIVATE_KEY;
  if (!rawKey)
    throw new Error("ARC_SAFE_PROPOSER_PRIVATE_KEY or PRIVATE_KEY is required");
  const signerKey = (rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`) as Hex;
  const proposer = privateKeyToAccount(signerKey).address;
  const client = createPublicClient({ transport: http(rpcUrl) });
  if ((await client.getChainId()) !== 5042)
    throw new Error("RPC must target Arc 5042");
  const safe = read(path.join(ROOT, "config/common/5042.json")).common
    .multisig as Address;
  const owners = await client.readContract({
    address: safe,
    abi: ABI,
    functionName: "getOwners",
  });
  if (
    !owners.some((o) => equal(o, proposer)) &&
    (await isAuthorizedProposer(5042, safe, proposer)) !== true
  )
    throw new Error(
      "Proposer key must be a Safe owner or registered Arc Safe delegate",
    );
  const api = new SafeApiKit({ chainId: 5042n, txServiceUrl: service.api });
  const common = read(
    path.join(ROOT, "script/deployment-config/common/5042.json"),
  );
  const hook = await client.readContract({
    address: common.complianceProxy,
    abi: ABI,
    functionName: "complianceHook",
  });
  const groups = (symbol ? [symbol] : SYMBOLS).map((s) => {
    let targets: Address[];
    let names: string[];
    if (s === "nCOMMON") {
      targets = [
        common.complianceProxy,
        hook,
        common.redeemOperator,
        common.cctpRelayer,
      ];
      names = [
        "complianceProxy",
        "predicateV2Hook",
        "redeemOperator",
        "cctpRelayer",
      ].map((n) => `common.${n}`);
    } else {
      const output = read(path.join(ROOT, `script/output/${s}/5042-${s}.json`));
      const c = output.contracts;
      if (output.deployChainId !== 5042 || c.vaults.length !== 1)
        throw new Error("Unexpected deployment output");
      targets = [
        c.share,
        c.accountant,
        c.vaults[0].address,
        c.vaults[0].composer,
      ];
      names = ["share", "accountant", "vault", "composer"].map(
        (n) => `${s}.${n}`,
      );
    }
    const batch = read(
      path.join(
        ROOT,
        `script/output/msig/5042-${s}-TransferOwnership-AcceptOwnership.json`,
      ),
    );
    return {
      symbol: s,
      targets,
      names,
      batch,
      txs: validateAcceptanceBatch(batch, targets),
    };
  });
  const states = async (targets: Address[]) =>
    Promise.all(
      targets.map(async (to) => ({
        to,
        owner: await client.readContract({
          address: to,
          abi: ABI,
          functionName: "owner",
        }),
        pendingOwner: await client.readContract({
          address: to,
          abi: ABI,
          functionName: "pendingOwner",
        }),
      })),
    );
  // Check every requested handoff before proposing any batch.
  for (const g of groups) requireNominations(await states(g.targets), safe);
  const chainNonce = number(
    await client.readContract({
      address: safe,
      abi: ABI,
      functionName: "nonce",
    }),
  );
  let nextNonce = Math.max(chainNonce, number(await api.getNextNonce(safe)));
  fs.mkdirSync(dir, { recursive: true });
  const lock = path.join(dir, ".arc-proposal.lock");
  const fd = fs.openSync(lock, "wx");
  fs.writeFileSync(fd, String(process.pid));
  try {
    const preparedGroups = [];
    for (const g of groups) {
      const batchDir = path.join(dir, g.symbol);
      const journalPath = path.join(batchDir, "proposal.json");
      const previous: Journal | undefined = fs.existsSync(journalPath)
        ? read(journalPath)
        : undefined;
      const batchHash = keccak256(encodeMultiSend(g.txs));
      if (
        previous &&
        (!equal(previous.safe, safe) ||
          previous.symbol !== g.symbol ||
          previous.batchHash !== batchHash)
      )
        throw new Error(
          "Batch changed since proposal preparation; use a new --dir",
        );
      const nonce = previous?.prepared.nonce ?? nextNonce;
      const prepared = await proposeBatch({
        chainId: 5042,
        safe,
        txs: g.txs,
        signerKey,
        rpcUrl,
        nonce,
        dryRun: true,
        expectedSafeTxHash: previous?.prepared.safeTxHash,
      });
      const tx = prepared.transactionData;
      const message = {
        to: tx.to as Address,
        value: BigInt(tx.value),
        data: tx.data as Hex,
        operation: tx.operation,
        safeTxGas: BigInt(tx.safeTxGas),
        baseGas: BigInt(tx.baseGas),
        gasPrice: BigInt(tx.gasPrice),
        gasToken: tx.gasToken as Address,
        refundReceiver: tx.refundReceiver as Address,
        nonce: BigInt(tx.nonce),
      };
      const independentHash = hashTypedData({
        domain: { chainId: 5042, verifyingContract: safe },
        types: TYPES,
        primaryType: "SafeTx",
        message,
      });
      const onchainHash = await client.readContract({
        address: safe,
        abi: ABI,
        functionName: "getTransactionHash",
        args: [
          message.to,
          message.value,
          message.data,
          message.operation,
          message.safeTxGas,
          message.baseGas,
          message.gasPrice,
          message.gasToken,
          message.refundReceiver,
          message.nonce,
        ],
      });
      if (
        !equal(prepared.safeTxHash, independentHash) ||
        !equal(onchainHash, independentHash)
      )
        throw new Error("SafeTxHash cross-check failed");
      const canonical = (
        getMultiSendCallOnlyDeployment({ version: "1.3.0" }) as any
      ).deployments.canonical;
      const code = await client.getCode({ address: prepared.multiSendAddress });
      if (
        prepared.safeVersion !== "1.3.0" ||
        !code ||
        keccak256(code) !== canonical.codeHash
      )
        throw new Error("Unreviewed Safe/MultiSend version or bytecode");
      const response = await fetch(
        `${service.api}/v1/multisig-transactions/${prepared.safeTxHash}/`,
        { signal: AbortSignal.timeout(20000) },
      );
      if (!response.ok && response.status !== 404)
        throw new Error(`Proposal lookup failed: HTTP ${response.status}`);
      const existing = response.ok
        ? ((await response.json()) as any)
        : undefined;
      if (existing?.isExecuted)
        throw new Error(
          "Proposal already executed; review current ownership and the saved message",
        );
      if (!existing && (nonce < nextNonce || nonce < chainNonce))
        throw new Error(
          `Saved nonce ${nonce} is no longer free; use a new --dir to select fresh nonces`,
        );
      if (previous?.proposed && !existing)
        throw new Error(
          "Previously submitted proposal is missing from service; refusing to duplicate it",
        );
      const journal: Journal = {
        symbol: g.symbol,
        safe,
        batchHash,
        prepared,
        simulation: previous?.simulation,
        proposed: !!existing,
      };
      const save = () => write(journalPath, journal);
      save();
      write(path.join(batchDir, "safe-batch.json"), g.batch);
      write(path.join(batchDir, "safe-transaction.json"), prepared);
      write(path.join(batchDir, "hash-verification.json"), {
        sdkHash: prepared.safeTxHash,
        independentHash,
        onchainHash,
      });
      preparedGroups.push({ ...g, batchDir, journal, save });
      nextNonce = Math.max(nextNonce, nonce + 1);
    }
    for (const g of preparedGroups) {
      await simulateAndSubmit(
        g.journal,
        {
          save: g.save,
          simulate: async () => {
            requireNominations(await states(g.targets), safe);
            const tx = g.journal.prepared.transactionData;
            const signatures = concatHex([
              pad(owners[0], { size: 32 }),
              pad("0x00", { size: 32 }),
              "0x01",
            ]);
            const input = encodeFunctionData({
              abi: ABI,
              functionName: "execTransaction",
              args: [
                tx.to as Address,
                BigInt(tx.value),
                tx.data as Hex,
                tx.operation,
                BigInt(tx.safeTxGas),
                BigInt(tx.baseGas),
                BigInt(tx.gasPrice),
                tx.gasToken as Address,
                tx.refundReceiver as Address,
                signatures,
              ],
            });
            const request = {
              network_id: "5042",
              from: owners[0],
              to: safe,
              input,
              value: "0",
              gas: 30000000,
              gas_price: "0",
              save: true,
              save_if_fails: true,
              state_objects: {
                [safe]: {
                  storage: {
                    [pad("0x04", { size: 32 })]: pad("0x01", { size: 32 }),
                    [pad("0x05", { size: 32 })]: pad(toHex(tx.nonce), {
                      size: 32,
                    }),
                  },
                },
              },
            };
            const result: any = await tenderly("simulate", request);
            write(
              path.join(g.batchDir, "proposal-simulation-response.json"),
              result,
            );
            if (
              result.simulation?.status !== true ||
              result.transaction?.status === false
            )
              throw new Error("Safe simulation reverted");
            assertAcceptanceResult(result, g.targets, safe);
            const id = result.simulation.id;
            await tenderly(`simulations/${id}/share`, {});
            return `https://dashboard.tenderly.co/shared/simulation/${id}`;
          },
          submit: async () => {
            requireNominations(await states(g.targets), safe);
            // Check this nonce has not acquired a competing proposal during simulation.
            const queued = await api.getMultisigTransactions(safe, {
              nonce: String(g.journal.prepared.nonce),
            });
            if (
              queued.results.some(
                (t) => !equal(t.safeTxHash, g.journal.prepared.safeTxHash),
              )
            )
              throw new Error(
                "Safe nonce acquired a competing proposal; refusing submission",
              );
            if (
              number(
                await client.readContract({
                  address: safe,
                  abi: ABI,
                  functionName: "nonce",
                }),
              ) > g.journal.prepared.nonce
            )
              throw new Error("Safe nonce advanced before submission");
            return proposeBatch({
              chainId: 5042,
              safe,
              txs: g.txs,
              signerKey,
              rpcUrl,
              nonce: g.journal.prepared.nonce,
              expectedSafeTxHash: g.journal.prepared.safeTxHash,
            });
          },
        },
        dryRun,
      );
      write(
        path.join(g.batchDir, "slack.md"),
        signerMessage(g.journal, g.txs, g.names, SYMBOLS.indexOf(g.symbol)),
      );
      console.log(
        `${g.symbol}: ${g.journal.proposed ? "proposed" : "dry run"} nonce ${g.journal.prepared.nonce}\nTransaction: ${g.journal.proposed ? g.journal.prepared.uiUrl : "not submitted"}\nSimulation: ${g.journal.simulation}`,
      );
    }
    write(
      path.join(dir, "proposal-summary.json"),
      preparedGroups.map((g) => g.journal),
    );
    write(
      path.join(dir, "slack-batches.md"),
      preparedGroups
        .map((g) => fs.readFileSync(path.join(g.batchDir, "slack.md"), "utf8"))
        .join("\n\n---\n\n"),
    );
    const messages = [
      path.join(dir, "slack-addresses.md"),
      ...SYMBOLS.map((s) => path.join(dir, s, "slack.md")),
    ]
      .filter((file) => fs.existsSync(file))
      .map((file) => fs.readFileSync(file, "utf8"));
    write(path.join(dir, "slack-all.md"), messages.join("\n\n---\n\n"));
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
