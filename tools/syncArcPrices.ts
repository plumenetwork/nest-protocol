#!/usr/bin/env ts-node
import "dotenv/config";
import fs from "node:fs";
import path from "node:path";
import {
  createPublicClient,
  createWalletClient,
  http,
  parseAbi,
  formatUnits,
  encodeFunctionData,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

const ROOT = path.resolve(__dirname, "..");
const SYMBOLS = ["nOPAL", "nFALCON", "FACTOR"];
const IMPLEMENTATION_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
const ABI = parseAbi([
  "function accountant() view returns(address)",
  "function share() view returns(address)",
  "function symbol() view returns(string)",
  "function baseDecimals() view returns(uint8)",
  "function base() view returns(address)",
  "function owner() view returns(address)",
  "function getRateSafe() view returns(uint256)",
  "function getAccountantState() view returns ((address payoutAddress,uint128 feesOwedInBase,uint128 totalSharesLastUpdate,uint96 exchangeRate,uint32 allowedExchangeRateChangeUpper,uint32 allowedExchangeRateChangeLower,uint64 lastUpdateTimestamp,bool isPaused,uint32 minimumUpdateDelayInSeconds))",
  "function updateExchangeRate(uint96 newRate,uint128 totalShareSupply)",
]);
type State = {
  exchangeRate: bigint;
  allowedExchangeRateChangeUpper: number;
  allowedExchangeRateChangeLower: number;
  lastUpdateTimestamp: bigint;
  minimumUpdateDelayInSeconds: number;
  isPaused: boolean;
};
const read = (file: string) =>
  JSON.parse(fs.readFileSync(path.join(ROOT, file), "utf8"));
const same = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();

export function checkRateUpdate(state: State, rate: bigint, timestamp: bigint) {
  if (state.isPaused) throw new Error("Arc accountant is paused");
  if (rate <= 0n || rate >= 1n << 96n)
    throw new Error("Hub rate does not fit a nonzero uint96");
  if (state.exchangeRate === rate) return false;
  const readyAt =
    state.lastUpdateTimestamp + BigInt(state.minimumUpdateDelayInSeconds);
  if (timestamp < readyAt)
    throw new Error(`Update delay has not elapsed; ready at ${readyAt}`);
  const lower =
    (state.exchangeRate * BigInt(state.allowedExchangeRateChangeLower)) /
    1_000_000n;
  const upper =
    (state.exchangeRate * BigInt(state.allowedExchangeRateChangeUpper)) /
    1_000_000n;
  if (rate < lower || rate > upper)
    throw new Error(
      `Hub rate ${rate} is outside Arc bounds [${lower}, ${upper}]; no bounds are changed`,
    );
  return true;
}

/** Match the deployed Spoke implementation, excluding compiler-declared immutable slots only. */
export function assertSpokeCode(code: Hex, artifact: any) {
  const bytecode = artifact.deployedBytecode;
  const mask = (value: string) => {
    const bytes = Buffer.from(value.replace(/^0x/, ""), "hex");
    for (const entries of Object.values(bytecode.immutableReferences ?? {}) as {
      start: number;
      length: number;
    }[][])
      for (const { start, length } of entries)
        bytes.fill(0, start, start + length);
    return bytes.toString("hex");
  };
  if (!bytecode.object || code === "0x" || mask(code) !== mask(bytecode.object))
    throw new Error(
      "Arc implementation does not match the local NestSpokeAccountant artifact; check deployment/build before syncing",
    );
}

/** Preflight every vault before sending any transaction; each send waits for its receipt. */
export async function runSync<T>(
  items: T[],
  preflight: (item: T) => Promise<void>,
  send: (item: T) => Promise<void>,
  broadcast: boolean,
) {
  for (const item of items) await preflight(item);
  if (broadcast) for (const item of items) await send(item);
}

export async function main(args = process.argv.slice(2)) {
  if (args.includes("--help")) {
    console.log(
      "Usage: pnpm deploy:arc sync-prices [--broadcast]\nMirrors Plume hub getRateSafe() into the three Arc spoke accountants before ownership handoff. Default: simulate only. Requires PLUME_RPC_URL, ARC_RPC_URL and deployer PRIVATE_KEY.",
    );
    return;
  }
  if (args.length > 1 || args.some((a) => a !== "--broadcast"))
    throw new Error("Use sync-prices [--broadcast]");
  const broadcast = args.includes("--broadcast");
  for (const key of ["ARC_RPC_URL", "PLUME_RPC_URL", "PRIVATE_KEY"])
    if (!process.env[key]) throw new Error(`${key} is required`);
  const rawKey = process.env.PRIVATE_KEY!;
  const account = privateKeyToAccount(
    (rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`) as Hex,
  );
  const arc = createPublicClient({ transport: http(process.env.ARC_RPC_URL) });
  const hub = createPublicClient({
    transport: http(process.env.PLUME_RPC_URL),
  });
  if ((await arc.getChainId()) !== 5042 || (await hub.getChainId()) !== 98866)
    throw new Error("Expected Arc 5042 and Plume 98866 RPCs");
  const [arcBlock, hubBlock] = await Promise.all([
    arc.getBlock(),
    hub.getBlock(),
  ]);
  const artifact = read("out/NestSpokeAccountant.sol/NestSpokeAccountant.json");
  const report: any = {
    mode: broadcast ? "broadcast" : "simulation",
    arcBlock: arcBlock.number,
    hubBlock: hubBlock.number,
    deployer: account.address,
    vaults: [],
    complete: false,
  };
  const dir = path.join(ROOT, "generated/arc-price-sync");
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `${Date.now()}-${report.mode}.json`);
  const save = () =>
    fs.writeFileSync(
      file,
      JSON.stringify(
        report,
        (_, v) => (typeof v === "bigint" ? v.toString() : v),
        2,
      ) + "\n",
    );
  const wallet = createWalletClient({
    account,
    transport: http(process.env.ARC_RPC_URL),
  });
  const owned = async (address: Address, blockNumber?: bigint) => {
    // A nomination does not revoke the current owner's authority. Acceptance does.
    const owner = await arc.readContract({
      address,
      abi: ABI,
      functionName: "owner",
      blockNumber,
    });
    if (!same(owner, account.address))
      throw new Error(
        "Price sync requires the deployer to remain the current owner; pending nominations are allowed",
      );
  };
  const idle = async () => {
    const [latest, pending] = await Promise.all(
      ["latest", "pending"].map((blockTag) =>
        arc.getTransactionCount({
          address: account.address,
          blockTag: blockTag as "latest" | "pending",
        }),
      ),
    );
    if (latest !== pending)
      throw new Error(
        "Deployer has pending transactions; resolve them before price sync",
      );
    return latest;
  };
  await idle();
  try {
    await runSync(
      SYMBOLS,
      async (symbol) => {
        const config = read(`script/deployment-config/vaults/${symbol}.json`);
        if (
          config.accountantType !== "NestHubAccountant" ||
          (config.hubChainId || 98866) !== 98866 ||
          config.baseAssetSymbol !== "USDC"
        )
          throw new Error(
            `${symbol}: expected Plume hub / Arc spoke with USDC base`,
          );
        const output = read(`script/output/${symbol}/5042-${symbol}.json`);
        if (
          output.deployChainId !== 5042 ||
          output.contracts.vaults.length !== 1
        )
          throw new Error("Unexpected Arc deployment output");
        const { accountant, share } = output.contracts as {
          accountant: Address;
          share: Address;
        };
        // These deterministic vault addresses are deployed on both chains. Resolve and
        // validate their live bindings rather than assuming the accountant address.
        const vault = output.contracts.vaults[0].address as Address;
        const hubAccountant = await hub.readContract({
          address: vault,
          abi: ABI,
          functionName: "accountant",
          blockNumber: hubBlock.number,
        });
        for (const [client, blockNumber, expectedAccountant, chainId] of [
          [arc, arcBlock.number, accountant, 5042],
          [hub, hubBlock.number, hubAccountant, 98866],
        ] as const) {
          const [
            actualAccountant,
            vaultShare,
            accountantShare,
            tokenSymbol,
            decimals,
            base,
          ] = await Promise.all([
            client.readContract({
              address: vault,
              abi: ABI,
              functionName: "accountant",
              blockNumber,
            }),
            client.readContract({
              address: vault,
              abi: ABI,
              functionName: "share",
              blockNumber,
            }),
            client.readContract({
              address: expectedAccountant,
              abi: ABI,
              functionName: "share",
              blockNumber,
            }),
            client.readContract({
              address: share,
              abi: ABI,
              functionName: "symbol",
              blockNumber,
            }),
            client.readContract({
              address: expectedAccountant,
              abi: ABI,
              functionName: "baseDecimals",
              blockNumber,
            }),
            client.readContract({
              address: expectedAccountant,
              abi: ABI,
              functionName: "base",
              blockNumber,
            }),
          ]);
          if (
            !same(actualAccountant, expectedAccountant) ||
            !same(vaultShare, share) ||
            !same(accountantShare, share) ||
            tokenSymbol !== symbol ||
            decimals !== 6 ||
            !same(base, read(`config/assets/${chainId}.json`).USDC)
          )
            throw new Error(
              `${symbol}: chain ${chainId} vault/share/accountant/USDC binding mismatch`,
            );
        }
        await owned(accountant, arcBlock.number);
        const implSlot = await arc.getStorageAt({
          address: accountant,
          slot: IMPLEMENTATION_SLOT,
          blockNumber: arcBlock.number,
        });
        if (!implSlot) throw new Error("Missing accountant implementation");
        const implementation = `0x${implSlot.slice(-40)}` as Address;
        assertSpokeCode(
          (await arc.getCode({
            address: implementation,
            blockNumber: arcBlock.number,
          })) ?? "0x",
          artifact,
        );
        const rate = await hub.readContract({
          address: hubAccountant,
          abi: ABI,
          functionName: "getRateSafe",
          blockNumber: hubBlock.number,
        });
        const state = await arc.readContract({
          address: accountant,
          abi: ABI,
          functionName: "getAccountantState",
          blockNumber: arcBlock.number,
        });
        const needsUpdate = checkRateUpdate(state, rate, arcBlock.timestamp);
        if (needsUpdate)
          await arc.simulateContract({
            address: accountant,
            abi: ABI,
            functionName: "updateExchangeRate",
            args: [rate, 0n],
            account,
            blockNumber: arcBlock.number,
          });
        const entry = {
          symbol,
          vault,
          accountant,
          hubAccountant,
          implementation,
          before: state,
          rate,
          needsUpdate,
          data: encodeFunctionData({
            abi: ABI,
            functionName: "updateExchangeRate",
            args: [rate, 0n],
          }),
          status: needsUpdate ? "simulated" : "already synced",
        };
        report.vaults.push(entry);
        save();
        console.log(
          `${symbol}: ${formatUnits(state.exchangeRate, 6)} -> ${formatUnits(rate, 6)} USDC/share (${entry.status})`,
        );
      },
      async (symbol) => {
        const entry = report.vaults.find((v: any) => v.symbol === symbol);
        await owned(entry.accountant);
        const currentHubRate = await hub.readContract({
          address: entry.hubAccountant,
          abi: ABI,
          functionName: "getRateSafe",
        });
        if (currentHubRate !== entry.rate)
          throw new Error(
            `${symbol}: hub rate changed since simulation; rerun to refresh`,
          );
        const latestBlock = await arc.getBlock();
        const state = await arc.readContract({
          address: entry.accountant,
          abi: ABI,
          functionName: "getAccountantState",
          blockNumber: latestBlock.number,
        });
        if (!checkRateUpdate(state, entry.rate, latestBlock.timestamp)) {
          entry.status = "already synced";
          save();
          return;
        }
        if (
          state.exchangeRate !== entry.before.exchangeRate ||
          state.lastUpdateTimestamp !== entry.before.lastUpdateTimestamp
        )
          throw new Error(
            `${symbol}: Arc checkpoint changed since simulation; rerun to refresh`,
          );
        const { request } = await arc.simulateContract({
          address: entry.accountant,
          abi: ABI,
          functionName: "updateExchangeRate",
          args: [entry.rate, 0n],
          account,
        });
        const nonce = await idle();
        entry.status = "sending";
        entry.nonce = nonce;
        save();
        entry.transactionHash = await wallet.writeContract({
          ...request,
          chain: null,
          nonce,
        });
        entry.status = "submitted";
        save();
        console.log(`${symbol}: submitted ${entry.transactionHash}`);
        const receipt = await arc.waitForTransactionReceipt({
          hash: entry.transactionHash,
        });
        entry.receipt = receipt;
        save();
        if (receipt.status !== "success")
          throw new Error(`${symbol}: price update reverted`);
        const after = await arc.readContract({
          address: entry.accountant,
          abi: ABI,
          functionName: "getAccountantState",
          blockNumber: receipt.blockNumber,
        });
        if (
          after.exchangeRate !== entry.rate ||
          after.isPaused ||
          after.allowedExchangeRateChangeUpper !==
            state.allowedExchangeRateChangeUpper ||
          after.allowedExchangeRateChangeLower !==
            state.allowedExchangeRateChangeLower ||
          after.minimumUpdateDelayInSeconds !==
            state.minimumUpdateDelayInSeconds
        )
          throw new Error(
            `${symbol}: unexpected accountant state after update`,
          );
        entry.after = after;
        entry.status = "confirmed";
        save();
        console.log(
          `${symbol}: confirmed ${formatUnits(after.exchangeRate, 6)} USDC/share`,
        );
      },
      broadcast,
    );
    report.complete = true;
    save();
    console.log(
      `${broadcast ? "Price sync complete" : "All updates simulated; nothing broadcast"}. Report: ${file}`,
    );
  } catch (error) {
    // Avoid persisting RPC errors containing credential-bearing URLs.
    report.complete = false;
    save();
    throw error;
  }
}

if (require.main === module)
  main().catch((error) => {
    console.error(error.shortMessage ?? error.message);
    process.exitCode = 1;
  });
