#!/usr/bin/env ts-node
/**
 * Compute a vault's GLOBAL share supply = sum of the share token's totalSupply()
 * across every chain the vault is deployed on. This is the value updateExchangeRate expects
 * as TOTAL_SHARE_SUPPLY:
 * the on-chain accountant enforces `TOTAL_SHARE_SUPPLY >= local totalSupply()`,
 * so it must be the global cross-chain total, not any single chain's supply.
 *
 * The NestShare is a native (mint/burn) OFT, so global circulating supply is the
 * sum of each chain's locally-minted totalSupply().
 *
 * Deployed chains are the chains with a DeployAndSetup output snapshot at
 * script/output/<vault>/<chainId>-<vault>.json (same authoritative signal
 * setupFeesAll.ts uses — the config `chains`/`peers` arrays are the intended
 * peer set, not the deployed set). The share address is read per chain from that
 * snapshot's `contracts.share`.
 *
 * HARD-FAILS (non-zero exit) if ANY deployed chain's totalSupply cannot be read
 * — missing RPC env, unreachable RPC, non-contract address, or a reverting call.
 * A partial sum is never emitted: a silently-dropped chain would understate the
 * global total and make the accountant call revert (or, worse, under-accrue).
 *
 * On success the per-chain breakdown is printed to stderr and the bare global
 * total (decimal wei string) is printed as the only line on stdout, so it can be
 * captured directly:
 *
 *   TOTAL_SHARE_SUPPLY=$(ts-node tools/totalShareSupply.ts nOPAL)
 *
 * Usage:
 *   ts-node tools/totalShareSupply.ts <VAULT_SYMBOL> [--chain <id>]...
 *
 *   <VAULT_SYMBOL>  vault to total (falls back to env VAULT_SYMBOL).
 *   --chain <id>    restrict to one or more deployed chains (repeatable).
 *                   Default: every chain the vault is deployed on.
 */
import "dotenv/config";
import * as fs from "fs";
import * as path from "path";
import { createPublicClient, http, getAddress } from "viem";

const ERC20_TOTAL_SUPPLY_ABI = [
  {
    inputs: [],
    name: "totalSupply",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

type CommonConfig = {
  chainId: number;
  name: string;
  rpc: string;
};

function die(msg: string): never {
  console.error(`totalShareSupply: ${msg}`);
  process.exit(1);
}

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v || v.length === 0) die(`${name} is not set`);
  return v;
}

function loadCommon(repoRoot: string, chainId: number): CommonConfig {
  const file = path.join(repoRoot, "config", "common", `${chainId}.json`);
  if (!fs.existsSync(file)) die(`config/common/${chainId}.json not found`);
  return JSON.parse(fs.readFileSync(file, "utf8")) as CommonConfig;
}

/**
 * Chains a vault is actually deployed on = the chains with a DeployAndSetup
 * output snapshot at script/output/<vault>/<chainId>-<vault>.json.
 */
function vaultChains(repoRoot: string, vault: string): number[] {
  const dir = path.join(repoRoot, "script", "output", vault);
  if (!fs.existsSync(dir)) die(`no deployment outputs at script/output/${vault}`);
  const out: number[] = [];
  for (const f of fs.readdirSync(dir)) {
    const m = f.match(new RegExp(`^(\\d+)-${vault}\\.json$`));
    if (m) out.push(Number(m[1]));
  }
  return out.sort((a, b) => a - b);
}

/** Read the share token address from a chain's deployment snapshot. */
function shareAddress(
  repoRoot: string,
  vault: string,
  chainId: number,
): `0x${string}` {
  const file = path.join(
    repoRoot,
    "script",
    "output",
    vault,
    `${chainId}-${vault}.json`,
  );
  const snap = JSON.parse(fs.readFileSync(file, "utf8")) as {
    contracts?: { share?: string };
  };
  const share = snap.contracts?.share;
  if (!share || !/^0x[0-9a-fA-F]{40}$/.test(share))
    die(`missing/invalid contracts.share in ${chainId}-${vault}.json`);
  return getAddress(share);
}

function parseArgs(): { vault: string; chains: number[] | null } {
  const args = process.argv.slice(2);
  let vault: string | undefined;
  const chains: number[] = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--chain") {
      const id = Number(args[++i]);
      if (!Number.isFinite(id) || id <= 0) die(`invalid --chain: ${args[i]}`);
      chains.push(id);
    } else if (a.startsWith("--")) {
      die(`unknown arg: ${a}`);
    } else if (vault === undefined) {
      vault = a;
    } else {
      die(`unexpected arg: ${a}`);
    }
  }
  vault = vault ?? process.env.VAULT_SYMBOL;
  if (!vault) die("vault symbol required (positional arg or VAULT_SYMBOL env)");
  return { vault, chains: chains.length ? chains : null };
}

async function main(): Promise<void> {
  const repoRoot = path.resolve(__dirname, "..");
  const { vault, chains: filter } = parseArgs();

  let chainList = vaultChains(repoRoot, vault);
  if (filter) {
    for (const c of filter)
      if (!chainList.includes(c))
        die(`--chain ${c}: ${vault} not deployed there (no output snapshot)`);
    chainList = filter.sort((a, b) => a - b);
  }
  if (chainList.length === 0) die(`no deployed chains found for ${vault}`);

  console.error(
    `${vault}: summing share totalSupply across ${chainList.length} chain(s): ${chainList.join(", ")}`,
  );

  let total = 0n;
  for (const chainId of chainList) {
    const common = loadCommon(repoRoot, chainId);
    const rpcUrl = requireEnv(common.rpc); // dies if the chain's RPC env is unset
    const share = shareAddress(repoRoot, vault, chainId);
    const client = createPublicClient({ transport: http(rpcUrl) });

    let supply: bigint;
    try {
      supply = (await client.readContract({
        address: share,
        abi: ERC20_TOTAL_SUPPLY_ABI,
        functionName: "totalSupply",
      })) as bigint;
    } catch (e) {
      // Any unreadable chain aborts the whole run — never emit a partial sum.
      die(
        `totalSupply() failed on chain ${chainId} (${common.name}) at ${share}: ${
          e instanceof Error ? e.message : String(e)
        }`,
      );
    }

    total += supply;
    console.error(
      `  chain ${String(chainId).padEnd(6)} ${common.name.padEnd(12)} ${share}  ${supply.toString()}`,
    );
  }

  console.error(`  ${"".padEnd(6)} ${"TOTAL".padEnd(12)} ${"".padEnd(42)}  ${total.toString()}`);
  // Bare total on stdout — the only stdout line, for `$(...)` capture.
  process.stdout.write(`${total.toString()}\n`);
}

main().catch((err) => {
  console.error(err instanceof Error ? (err.stack ?? err.message) : err);
  process.exit(1);
});
