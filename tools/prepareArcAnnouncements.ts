#!/usr/bin/env ts-node
/** Read live Arc state, prepare unsigned Safe batches, simulate prerequisites + execution, and write Slack drafts. */
import "dotenv/config";
import fs from "node:fs";
import path from "node:path";
import {
  createPublicClient,
  http,
  parseAbi,
  encodeFunctionData,
  hashTypedData,
  keccak256,
  pad,
  toHex,
  concatHex,
  zeroAddress,
  type Address,
  type Hex,
} from "viem";
import { getMultiSendCallOnlyDeployment } from "@safe-global/safe-deployments";
import { encodeMultiSend } from "./tenderlySafeSim";
import type { SafeTx } from "./safePropose";

const ROOT = path.resolve(__dirname, "..");
export const ABI = parseAbi([
  "function owner() view returns(address)",
  "function pendingOwner() view returns(address)",
  "function getOwners() view returns(address[])",
  "function nonce() view returns(uint256)",
  "function VERSION() view returns(string)",
  "function complianceHook() view returns(address)",
  "function transferOwnership(address newOwner)",
  "function acceptOwnership()",
  "function getTransactionHash(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 _nonce) view returns(bytes32)",
  "function execTransaction(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,bytes signatures) payable returns(bool)",
]);
export const TYPES = {
  SafeTx: [
    { name: "to", type: "address" },
    { name: "value", type: "uint256" },
    { name: "data", type: "bytes" },
    { name: "operation", type: "uint8" },
    { name: "safeTxGas", type: "uint256" },
    { name: "baseGas", type: "uint256" },
    { name: "gasPrice", type: "uint256" },
    { name: "gasToken", type: "address" },
    { name: "refundReceiver", type: "address" },
    { name: "nonce", type: "uint256" },
  ],
} as const;
const read = (file: string) =>
  JSON.parse(fs.readFileSync(path.resolve(ROOT, file), "utf8"));
const write = (file: string, data: unknown) => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(
    file,
    typeof data === "string"
      ? data
      : JSON.stringify(
          data,
          (_, v) => (typeof v === "bigint" ? String(v) : v),
          2,
        ) + "\n",
  );
};
const equal = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();
const label = (name: string, a: string) =>
  `${name}(${a.slice(0, 8)}…${a.slice(-4)})`;

export function validateAcceptanceBatch(
  batch: any,
  targets: Address[],
): SafeTx[] {
  if (
    Number(batch.chainId) !== 5042 ||
    batch.transactions?.length !== targets.length
  )
    throw new Error("Unexpected Arc acceptance batch");
  const data = encodeFunctionData({
    abi: ABI,
    functionName: "acceptOwnership",
  });
  return batch.transactions.map((tx: SafeTx, i: number) => {
    if (
      !equal(tx.to, targets[i]) ||
      tx.data !== data ||
      Number(tx.operation) !== 0 ||
      BigInt(tx.value) !== 0n
    )
      throw new Error(`Unexpected acceptance call ${i}`);
    return { ...tx, operation: "0", value: "0" };
  });
}

export async function tenderly(route: string, body: unknown) {
  const {
    TENDERLY_ACCOUNT: account,
    TENDERLY_PROJECT: project,
    TENDERLY_ACCESS_KEY: key,
  } = process.env;
  if (!account || !project || !key)
    throw new Error(
      "TENDERLY_ACCOUNT, TENDERLY_PROJECT and TENDERLY_ACCESS_KEY are required",
    );
  const response = await fetch(
    `https://api.tenderly.co/api/v1/account/${account}/project/${project}/${route}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Access-Key": key },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(120000),
    },
  );
  if (!response.ok)
    throw new Error(`Tenderly ${route}: HTTP ${response.status}`);
  const text = await response.text();
  return text ? JSON.parse(text) : {};
}

export function assertAcceptanceResult(
  result: any,
  targets: Address[],
  safe: Address,
) {
  if (
    result.transaction?.transaction_info?.call_trace?.output !==
    pad("0x01", { size: 32 })
  )
    throw new Error("Safe execution did not return true");
  const raw = (result.transaction.transaction_info.state_diff ?? []).flatMap(
    (entry: any) => entry.raw ?? [],
  );
  const ownerSlot =
    "0x341f7c713c76cb881fd7047f7cccebe3fe10eddfc5e20fe83ee7e0b505e8ea00";
  const pendingSlot = toHex(BigInt(ownerSlot) + 2n, { size: 32 });
  for (const target of targets) {
    const changed = (slot: string, value: string) =>
      raw.some(
        (r: any) =>
          equal(r.address, target) && r.key === slot && equal(r.dirty, value),
      );
    if (
      !changed(ownerSlot, pad(safe, { size: 32 })) ||
      !changed(pendingSlot, pad("0x00", { size: 32 }))
    )
      throw new Error(
        `Simulation did not transfer ownership and clear pendingOwner for ${target}`,
      );
  }
}

export async function main() {
  const args = process.argv.slice(2);
  if (args.length && (args.length !== 2 || args[0] !== "--dir"))
    throw new Error("Usage: pnpm prepare:arc-announcements [--dir path]");
  const dir = path.resolve(
    ROOT,
    args[1] ?? "generated/arc-deployment-2026-09-11",
  );
  const rpc = process.env.ARC_RPC_URL;
  if (!rpc) throw new Error("ARC_RPC_URL is required");
  const client = createPublicClient({ transport: http(rpc) });
  if ((await client.getChainId()) !== 5042)
    throw new Error("RPC must target Arc 5042");
  const block = await client.getBlockNumber();
  const safe = read("config/common/5042.json").common.multisig as Address;
  const deployer = "0xc28e1cDfB582953fEf53f76C64426c2aC79C716e" as Address;
  const common = read("script/deployment-config/common/5042.json");
  const hook = await client.readContract({
    address: common.complianceProxy,
    abi: ABI,
    functionName: "complianceHook",
    blockNumber: block,
  });
  const owners = await client.readContract({
    address: safe,
    abi: ABI,
    functionName: "getOwners",
    blockNumber: block,
  });
  const baseNonce = Number(
    await client.readContract({
      address: safe,
      abi: ABI,
      functionName: "nonce",
      blockNumber: block,
    }),
  );
  const version = await client.readContract({
    address: safe,
    abi: ABI,
    functionName: "VERSION",
    blockNumber: block,
  });
  if (version !== "1.3.0")
    throw new Error(`Unreviewed Safe version ${version}`);
  const deployment = getMultiSendCallOnlyDeployment({ version: "1.3.0" })!;
  const multiSend = deployment.defaultAddress as Address;
  const code = await client.getCode({ address: multiSend, blockNumber: block });
  const expectedCodeHash = (deployment as any).deployments.canonical.codeHash;
  if (!code || keccak256(code) !== expectedCodeHash)
    throw new Error(
      "Arc MultiSendCallOnly runtime differs from canonical Safe deployment",
    );

  const catalog: Record<string, Address> = {};
  const groups: { symbol: string; names: string[]; targets: Address[] }[] = [];
  for (const symbol of ["nOPAL", "nFALCON", "FACTOR"]) {
    const output = read(`script/output/${symbol}/5042-${symbol}.json`);
    if (output.deployChainId !== 5042 || output.contracts.vaults.length !== 1)
      throw new Error("Unexpected vault output");
    const c = output.contracts;
    for (const [name, address] of Object.entries({
      share: c.share,
      accountant: c.accountant,
      vault: c.vaults[0].address,
      composer: c.vaults[0].composer,
      rolesAuthority: c.rolesAuthority,
    }))
      catalog[`${symbol}.${name}`] = address as Address;
    const names = ["share", "accountant", "vault", "composer"].map(
      (n) => `${symbol}.${n}`,
    );
    groups.push({ symbol, names, targets: names.map((n) => catalog[n]) });
  }
  for (const [name, address] of Object.entries({
    ...common,
    predicateV2Hook: hook,
  })) {
    if (
      typeof address === "string" &&
      /^0x[0-9a-f]{40}$/i.test(address) &&
      address !== zeroAddress
    )
      catalog[`common.${name}`] = address as Address;
  }
  const commonNames = [
    "complianceProxy",
    "predicateV2Hook",
    "redeemOperator",
    "cctpRelayer",
  ].map((n) => `common.${n}`);
  groups.push({
    symbol: "nCOMMON",
    names: commonNames,
    targets: commonNames.map((n) => catalog[n]),
  });

  const addresses: any[] = [];
  for (const [name, address] of Object.entries(catalog)) {
    if (!(await client.getCode({ address, blockNumber: block })))
      throw new Error(`No code at ${name}`);
    const owner = await client.readContract({
      address,
      abi: ABI,
      functionName: "owner",
      blockNumber: block,
    });
    addresses.push({
      name,
      address,
      owner,
      explorer: `https://explorer.arc.io/address/${address}`,
    });
  }
  write(path.join(dir, "addresses.json"), {
    chainId: 5042,
    block,
    safe,
    deployer,
    addresses,
  });
  const ownershipNote = addresses.every((a) => equal(a.owner, deployer))
    ? "Ownership remains with the deployer while configuration is finalized."
    : "Ownership handoff is in progress; review the current owner snapshot in addresses.json and complete the remaining Safe acceptances.";
  const addressText = `:rocket: **Nest deployed on Arc (5042)**\n\nnOPAL, nFALCON and FACTOR are deployed with PredicateV2 compliance through ComplianceProxy + PredicateV2Hook.\n\n${groups
    .slice(0, 3)
    .map(
      (g) =>
        `**${g.symbol}**\n\n${addresses
          .filter((a) => a.name.startsWith(g.symbol + "."))
          .map(
            (a) => `- ${a.name.split(".")[1]}: [${a.address}](${a.explorer})`,
          )
          .join("\n")}`,
    )
    .join("\n\n")}\n\n**Shared infrastructure**\n\n${addresses
    .filter((a) => a.name.startsWith("common."))
    .map((a) => `- ${a.name.split(".")[1]}: [${a.address}](${a.explorer})`)
    .join(
      "\n",
    )}\n\n${ownershipNote} Final handoff is to the operational Safe ${safe}; no timelock is used for this rollout. The four Safe acceptance batches follow the deployer handoff transactions. This announcement does not imply that user deposits/redemptions or cross-chain routes are live.\n`;
  if (addresses.some((a) => !equal(a.owner, deployer) && !equal(a.owner, safe)))
    throw new Error(
      "Ownership state changed; update deployment announcement before regenerating",
    );
  write(path.join(dir, "slack-addresses.md"), addressText);

  const summary: any[] = [];
  for (const [index, g] of groups.entries()) {
    const batch = read(
      `script/output/msig/5042-${g.symbol}-TransferOwnership-AcceptOwnership.json`,
    );
    const txs = validateAcceptanceBatch(batch, g.targets);
    const nonce = baseNonce + index;
    const tx = {
      to: multiSend,
      value: 0n,
      data: encodeMultiSend(txs),
      operation: 1,
      safeTxGas: 0n,
      baseGas: 0n,
      gasPrice: 0n,
      gasToken: zeroAddress,
      refundReceiver: zeroAddress,
      nonce: BigInt(nonce),
    };
    const hash = hashTypedData({
      domain: { chainId: 5042, verifyingContract: safe },
      types: TYPES,
      primaryType: "SafeTx",
      message: tx,
    });
    const onchainHash = await client.readContract({
      address: safe,
      abi: ABI,
      functionName: "getTransactionHash",
      blockNumber: block,
      args: [
        tx.to,
        tx.value,
        tx.data,
        tx.operation,
        tx.safeTxGas,
        tx.baseGas,
        tx.gasPrice,
        tx.gasToken,
        tx.refundReceiver,
        tx.nonce,
      ],
    });
    if (hash !== onchainHash)
      throw new Error("Independent SafeTxHash check failed");
    const signatures = concatHex([
      pad(owners[0], { size: 32 }),
      pad("0x00", { size: 32 }),
      "0x01",
    ]);
    const input = encodeFunctionData({
      abi: ABI,
      functionName: "execTransaction",
      args: [
        tx.to,
        tx.value,
        tx.data,
        tx.operation,
        tx.safeTxGas,
        tx.baseGas,
        tx.gasPrice,
        tx.gasToken,
        tx.refundReceiver,
        signatures,
      ],
    });
    const prerequisite: any[] = [];
    const state: any[] = [];
    for (const to of g.targets) {
      const owner = await client.readContract({
        address: to,
        abi: ABI,
        functionName: "owner",
        blockNumber: block,
      });
      const pendingOwner = await client.readContract({
        address: to,
        abi: ABI,
        functionName: "pendingOwner",
        blockNumber: block,
      });
      state.push({ to, owner, pendingOwner });
      if (equal(pendingOwner, safe)) continue;
      if (!equal(owner, deployer) || pendingOwner !== zeroAddress)
        throw new Error(`Unexpected ownership at ${to}`);
      prerequisite.push({
        from: deployer,
        to,
        input: encodeFunctionData({
          abi: ABI,
          functionName: "transferOwnership",
          args: [safe],
        }),
      });
    }
    const simulations = [
      ...prerequisite,
      { from: owners[0], to: safe, input },
    ].map((t) => ({
      network_id: "5042",
      block_number: Number(block),
      simulation_type: "full",
      save: true,
      save_if_fails: true,
      value: "0",
      gas: 30000000,
      gas_price: "0",
      ...t,
    }));
    (simulations[0] as any).state_objects = {
      [safe]: {
        storage: {
          [pad("0x04", { size: 32 })]: pad("0x01", { size: 32 }),
          [pad("0x05", { size: 32 })]: pad(toHex(nonce), { size: 32 }),
        },
      },
    };
    const batchDir = path.join(dir, g.symbol);
    write(path.join(batchDir, "safe-batch.json"), {
      ...batch,
      createdAt: Date.now(),
      meta: {
        ...batch.meta,
        name: `Arc ${g.symbol} ownership acceptance`,
        createdFromSafeAddress: safe,
      },
      transactions: txs,
    });
    write(path.join(batchDir, "safe-transaction.json"), {
      chainId: 5042,
      safe,
      safeTxHash: hash,
      transactionData: tx,
      status: "unsigned draft; nonce is not reserved in a transaction service",
    });
    write(path.join(batchDir, "simulation-request.json"), { simulations });
    console.log(
      `${g.symbol}: simulating ${prerequisite.length} deployer nominations + exact Safe batch (draft nonce ${nonce})`,
    );
    const result: any = await tenderly("simulate-bundle", { simulations });
    write(path.join(batchDir, "simulation-response.json"), result);
    const results = result.simulation_results;
    if (
      !Array.isArray(results) ||
      results.length !== simulations.length ||
      results.some(
        (r: any) =>
          r.simulation?.status !== true || r.transaction?.status === false,
      )
    )
      throw new Error(
        `${g.symbol}: simulation bundle failed; inspect saved response`,
      );
    const last = results.at(-1);
    assertAcceptanceResult(last, g.targets, safe);
    const links: string[] = [];
    for (const r of results) {
      const id = r.simulation.id;
      await tenderly(`simulations/${id}/share`, {});
      links.push(`https://dashboard.tenderly.co/shared/simulation/${id}`);
    }
    const simulation = links.at(-1)!;
    const message = `:signed: @nestowners\n${g.symbol === "nCOMMON" ? "Shared PredicateV2 infrastructure" : g.symbol} on Arc (5042) — complete ownership acceptance into ${label("opSafe", safe)} after the deployer handoff.\n\n**Queue ${index + 1} — one Safe batch, op Safe (${safe.slice(0, 8)}…${safe.slice(-4)}), draft nonce ${nonce}, ${txs.length} calls**\n\n\`\`\`\ngrammar: nest-signer-message/1\n${txs.map((t, i) => `[${i}] acceptOwnership() -> ${label(g.names[i], t.to)} op=call value=0 sig=acceptOwnership()`).join("\n")}\n\`\`\`\n\nExecute only after the deployer handoff has nominated this Safe on all four targets${g.symbol === "nCOMMON" ? "; accept shared infrastructure last" : ""}. Simulation includes ${prerequisite.length} prerequisite deployer nominations that have NOT been broadcast, then this exact Safe batch, with Safe threshold=1 and nonce=${nonce} overrides and an impersonated existing owner. One-step authority/ProxyAdmin handoffs are separate deployer actions and are not exercised by this acceptance simulation.\n\nDraft nonce is not reserved; refresh the hash and simulation if the proposal uses a different nonce or payload.\n\nExpected SafeTxHash: ${hash}\n\nTransaction: Not proposed — unsigned draft\n\nSimulation: [View Tenderly simulation](${simulation})\n`;
    write(path.join(batchDir, "slack.md"), message);
    write(path.join(batchDir, "simulation-summary.json"), {
      success: true,
      block,
      chainId: 5042,
      safe,
      nonce,
      safeTxHash: hash,
      simulation,
      prerequisiteSimulations: links.slice(0, -1),
      stateBefore: state,
      overrides: { threshold: 1, nonce },
      prerequisitesBroadcast: false,
    });
    summary.push({
      symbol: g.symbol,
      nonce,
      safeTxHash: hash,
      simulation,
      slack: path.relative(ROOT, path.join(batchDir, "slack.md")),
    });
    console.log(`${g.symbol}: PASS ${simulation}`);
  }
  write(path.join(dir, "summary.json"), {
    block,
    chainId: 5042,
    safe,
    baseNonce,
    proposed: false,
    batches: summary,
  });
  write(
    path.join(dir, "slack-all.md"),
    [
      addressText,
      ...groups.map((g) =>
        fs.readFileSync(path.join(dir, g.symbol, "slack.md"), "utf8"),
      ),
    ].join("\n\n---\n\n"),
  );
  console.log(
    `Prepared five Slack messages in ${dir}. No proposals or on-chain transactions were sent.`,
  );
}
if (require.main === module)
  main().catch((e) => {
    console.error(e.shortMessage ?? e.message);
    process.exitCode = 1;
  });
