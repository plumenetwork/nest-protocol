import "dotenv/config";

import { ethers } from "ethers";

/**
 * Fetch all price update events (`ExchangeRateUpdated`) for one or more Nest
 * vaults over a period of time, directly from an RPC node.
 *
 * The price of a Nest vault share is set on its accountant contract. This
 * script resolves the accountant from each vault, queries the accountants'
 * `ExchangeRateUpdated(uint96 oldRate, uint96 newRate, uint64 currentTime)`
 * logs over the requested block range and prints them grouped by accountant.
 *
 * Multiple accountants are queried in a SINGLE pass: `eth_getLogs` accepts an
 * array of addresses, so scanning N accountants costs the same number of RPC
 * calls as scanning one.
 *
 * Usage:
 *   ts-node tools/fetchPriceUpdates.ts \
 *     --vault 0xVault1 --vault 0xVault2 \
 *     --from <block|ISO date|unix> --to <block|ISO date|unix|latest>
 *
 * Flags (--vault / --accountant repeatable, or comma-separated):
 *   --vault <address>       Vault address; its accountant is resolved on-chain.
 *   --accountant <address>  Accountant address, used directly.
 *   --from <value>          Start: block number, unix timestamp, or ISO date.
 *   --to <value>            End: same forms, or "latest" (default).
 *   --rpc <url>             RPC URL. Default: $RPC_URL_PLUME_MAINNET.
 *   --chunk <number>        eth_getLogs block span per request (default 10000).
 *   --json                  Emit raw JSON instead of a table.
 */

const DEFAULT_RPC =
  process.env.RPC_URL_PLUME_MAINNET ||
  "https://rpc.plume.org/9ocEJBtuXXFqdmBNiYp3YF7opa7AdTnm9";
// Initial eth_getLogs span: attempt the whole range in one call. fetchLogs()
// auto-halves on a range/result-limit error, so this is just a starting point.
const DEFAULT_CHUNK = Number.MAX_SAFE_INTEGER;

// uint96 fixed-point rate is scaled by 1e6 on the Nest accountants (one share
// price unit per 1e6). Used only for human-readable output.
const RATE_DECIMALS = 6;

// Known Nest vaults on Plume mainnet, keyed by name. Pass a name to
// --accountant (e.g. --accountant nALPHA) to skip address lookup; the matching
// vault address is attached to every event for that accountant.
const KNOWN: Record<string, { vault: string; accountant: string }> = {
  nALPHA: {
    vault: "0x593ccca4c4bf58b7526a4c164ceef4003c6388db",
    accountant: "0xe0CF451d6E373FF04e8eE3c50340F18AFa6421E1",
  },
  nTBILL: {
    vault: "0xe72fe64840f4ef80e3ec73a1c749491b5c938cb9",
    accountant: "0x0b738cd187872b265a689e8e4130c336e76892ec",
  },
  nBASIS: {
    vault: "0x11113Ff3a60C2450F4b22515cB760417259eE94B",
    accountant: "0xa67d20A49e6Fe68Cf97E556DB6b2f5DE1dF4dC2f",
  },
  nOPAL: {
    vault: "0x119Dd7dAFf816f29D7eE47596ae5E4bdC4299165",
    accountant: "0x2Ed2f77a961fc92F73D1087786099c39C894Ed1D",
  },
  nWISDOM: {
    vault: "0x29bF22381A5811deC89dC7b46A5Ce57aD02c0240",
    accountant: "0x5f57AE7Bf41806b2c8F5ddBf1E6a09D7a6D916f6",
  },
};

const VAULT_ABI = ["function accountant() view returns (address)"];
const ACCOUNTANT_ABI = [
  "event ExchangeRateUpdated(uint96 oldRate, uint96 newRate, uint64 currentTime)",
];

type Args = {
  vaults: string[];
  accountants: string[];
  from?: string;
  to?: string;
  rpc: string;
  chunk: number;
  json: boolean;
};

type PriceUpdate = {
  vault: string | null; // vault address if the accountant is in KNOWN, else null
  name: string | null; // vault name if known
  accountant: string;
  blockNumber: number;
  txHash: string;
  logIndex: number;
  oldRate: string;
  newRate: string;
  // Unix timestamp the rate was set — emitted in the event as uint64(block.timestamp).
  currentTime: number;
};

/** Split a repeatable flag value on commas, trim, drop empties. */
function splitAddresses(value: string): string[] {
  return value
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

function parseArgs(argv: string[]): Args {
  const args: Args = {
    vaults: [],
    accountants: [],
    rpc: DEFAULT_RPC,
    chunk: DEFAULT_CHUNK,
    json: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    switch (flag) {
      case "--vault":
        args.vaults.push(...splitAddresses(argv[++i]));
        break;
      case "--accountant":
        args.accountants.push(...splitAddresses(argv[++i]));
        break;
      case "--from":
        args.from = argv[++i];
        break;
      case "--to":
        args.to = argv[++i];
        break;
      case "--rpc":
        args.rpc = argv[++i];
        break;
      case "--chunk":
        args.chunk = Number(argv[++i]);
        break;
      case "--json":
        args.json = true;
        break;
      case "--help":
      case "-h":
        printHelpAndExit();
        break;
      default:
        throw new Error(`Unknown flag: ${flag}`);
    }
  }
  if (args.vaults.length === 0 && args.accountants.length === 0)
    throw new Error("Provide at least one --vault or --accountant address.");
  if (!args.from)
    throw new Error(
      "Provide --from <block|unix|ISO date>. Refusing to scan from block 0.",
    );
  if (!Number.isFinite(args.chunk) || args.chunk <= 0)
    throw new Error("--chunk must be a positive number.");
  return args;
}

function printHelpAndExit(): never {
  console.log(
    [
      "Fetch ExchangeRateUpdated (price update) events for Nest vaults.",
      "",
      "  --vault <address>       Vault address (repeatable / comma-separated).",
      "  --accountant <address>  Accountant address (repeatable / comma-separated).",
      "  --from <value>          Block number, unix timestamp, or ISO date.",
      "  --to <value>            Same forms, or 'latest' (default).",
      "  --rpc <url>             RPC URL (default $RPC_URL_PLUME_MAINNET).",
      "  --chunk <number>        Block span per eth_getLogs call (default 10000).",
      "  --json                  Emit raw JSON.",
    ].join("\n"),
  );
  process.exit(0);
}

/** Tell apart a block number from a timestamp/date. */
function looksLikeBlock(value: string): boolean {
  // Plume block numbers are well below 1e9; unix timestamps are ~1.7e9.
  return /^\d+$/.test(value) && Number(value) < 1_000_000_000;
}

function toUnix(value: string): number {
  if (/^\d+$/.test(value)) return Number(value);
  const ms = Date.parse(value);
  if (Number.isNaN(ms)) throw new Error(`Cannot parse date/timestamp: ${value}`);
  return Math.floor(ms / 1000);
}

/** Binary-search the first block with timestamp >= target. */
async function blockForTimestamp(
  provider: ethers.providers.JsonRpcProvider,
  targetUnix: number,
  latest: number,
): Promise<number> {
  let lo = 1;
  let hi = latest;
  const earliest = await provider.getBlock(lo);
  if (earliest.timestamp >= targetUnix) return lo;
  const head = await provider.getBlock(hi);
  if (head.timestamp < targetUnix) return hi;

  while (lo < hi) {
    const mid = Math.floor((lo + hi) / 2);
    const block = await provider.getBlock(mid);
    if (block.timestamp < targetUnix) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}

/** Resolve a --from/--to value into a block number. */
async function resolveBlock(
  provider: ethers.providers.JsonRpcProvider,
  value: string | undefined,
  fallback: number,
  latest: number,
): Promise<number> {
  if (value === undefined || value === "latest") return fallback;
  if (looksLikeBlock(value)) return Number(value);
  return blockForTimestamp(provider, toUnix(value), latest);
}

/** Raw log shape as returned by the `eth_getLogs` JSON-RPC method. */
type RawLog = {
  address: string;
  topics: string[];
  data: string;
  blockNumber: string;
  transactionHash: string;
  logIndex: string;
};

/** Does this RPC error look like a range / result-count cap we can retry? */
function isRangeLimitError(err: unknown): boolean {
  const msg = (err instanceof Error ? err.message : String(err)).toLowerCase();
  return (
    msg.includes("range") ||
    msg.includes("too many") ||
    msg.includes("limit") ||
    msg.includes("exceed") ||
    msg.includes("more than") ||
    msg.includes("response size")
  );
}

/**
 * One pass over the range, filtering on all accountants at once.
 *
 * ethers v5's `provider.getLogs` only accepts a single address, so we call
 * `eth_getLogs` directly — the JSON-RPC method does accept an address array.
 *
 * `chunk` is the *initial* block span to attempt. If the RPC rejects a span
 * with a range/result-limit error, the span is halved and retried, so the
 * caller never has to guess the provider's cap.
 */
async function fetchLogs(
  provider: ethers.providers.JsonRpcProvider,
  accountants: string[],
  fromBlock: number,
  toBlock: number,
  chunk: number,
): Promise<RawLog[]> {
  const iface = new ethers.utils.Interface(ACCOUNTANT_ABI);
  const topic = iface.getEventTopic("ExchangeRateUpdated");
  const logs: RawLog[] = [];

  let span = Math.max(1, Math.min(chunk, toBlock - fromBlock + 1));
  let start = fromBlock;
  while (start <= toBlock) {
    const end = Math.min(start + span - 1, toBlock);
    process.stderr.write(`  scanning blocks ${start} -> ${end} (span ${span})   \r`);
    try {
      const batch: RawLog[] = await provider.send("eth_getLogs", [
        {
          address: accountants, // array filter -> one call covers all accountants
          topics: [topic],
          fromBlock: ethers.utils.hexValue(start),
          toBlock: ethers.utils.hexValue(end),
        },
      ]);
      logs.push(...batch);
      start = end + 1;
    } catch (err) {
      if (span > 1 && isRangeLimitError(err)) {
        span = Math.floor(span / 2); // RPC rejected the span — back off and retry
        process.stderr.write(`\n  RPC limit hit, retrying with span ${span}\n`);
        continue;
      }
      throw err;
    }
  }
  process.stderr.write("\n");
  return logs;
}

function formatRate(raw: string): string {
  return ethers.utils.formatUnits(ethers.BigNumber.from(raw), RATE_DECIMALS);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const provider = new ethers.providers.JsonRpcProvider(args.rpc);

  // Resolve every vault to its accountant; merge with directly-given ones.
  const accountantSet = new Map<string, string>(); // lower-case -> checksum
  const addAccountant = (addr: string) =>
    accountantSet.set(addr.toLowerCase(), ethers.utils.getAddress(addr));

  for (const token of args.accountants) {
    // A token is either a vault name (KNOWN) or a raw accountant address.
    addAccountant(KNOWN[token]?.accountant ?? token);
  }
  for (const vaultAddr of args.vaults) {
    const vault = new ethers.Contract(vaultAddr, VAULT_ABI, provider);
    const acc: string = await vault.accountant();
    console.error(`Vault ${vaultAddr} -> accountant ${acc}`);
    addAccountant(acc);
  }
  const accountants = [...accountantSet.values()];

  const latest = await provider.getBlockNumber();
  const fromBlock = await resolveBlock(provider, args.from, 0, latest);
  const toBlock = await resolveBlock(provider, args.to, latest, latest);
  if (fromBlock > toBlock)
    throw new Error(`fromBlock ${fromBlock} is above toBlock ${toBlock}`);

  console.error(
    `Fetching price updates for ${accountants.length} accountant(s) ` +
      `from block ${fromBlock} to ${toBlock} ` +
      `(${toBlock - fromBlock + 1} blocks)`,
  );

  // Reverse map: accountant address (lower-case) -> vault name + address.
  const knownByAccountant = new Map<string, { name: string; vault: string }>();
  for (const [name, info] of Object.entries(KNOWN))
    knownByAccountant.set(info.accountant.toLowerCase(), {
      name,
      vault: ethers.utils.getAddress(info.vault),
    });

  const iface = new ethers.utils.Interface(ACCOUNTANT_ABI);
  const rawLogs = await fetchLogs(provider, accountants, fromBlock, toBlock, args.chunk);

  // No block lookups needed: the event's `currentTime` field is the block
  // timestamp the rate was set (uint64(block.timestamp), see NestAccountant).
  const updates: PriceUpdate[] = rawLogs.map((log) => {
    const parsed = iface.parseLog({ topics: log.topics, data: log.data });
    const accountant = ethers.utils.getAddress(log.address);
    const known = knownByAccountant.get(accountant.toLowerCase());
    return {
      vault: known?.vault ?? null,
      name: known?.name ?? null,
      accountant,
      blockNumber: Number(log.blockNumber),
      txHash: log.transactionHash,
      logIndex: Number(log.logIndex),
      oldRate: parsed.args.oldRate.toString(),
      newRate: parsed.args.newRate.toString(),
      currentTime: Number(parsed.args.currentTime),
    };
  });
  updates.sort((a, b) =>
    a.blockNumber === b.blockNumber
      ? a.logIndex - b.logIndex
      : a.blockNumber - b.blockNumber,
  );

  if (args.json) {
    console.log(
      JSON.stringify({ accountants, fromBlock, toBlock, updates }, null, 2),
    );
    return;
  }

  // Group output by accountant.
  for (const acc of accountants) {
    const rows = updates.filter((u) => u.accountant === acc);
    const known = knownByAccountant.get(acc.toLowerCase());
    const label = known
      ? `${known.name}  vault ${known.vault}  accountant ${acc}`
      : `accountant ${acc}`;
    console.log(`\n=== ${label} — ${rows.length} price update(s) ===\n`);
    for (const u of rows) {
      const date = new Date(u.currentTime * 1000).toISOString();
      console.log(
        `block ${u.blockNumber}  ${date}\n` +
          `  ${formatRate(u.oldRate)} -> ${formatRate(u.newRate)}` +
          `  (raw ${u.oldRate} -> ${u.newRate})\n` +
          `  tx ${u.txHash}\n`,
      );
    }
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
