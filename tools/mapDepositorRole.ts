import "dotenv/config";

import { ethers } from "ethers";

const DEFAULT_AUTHORITY = "0xe072B192A9111fB7Aaf64B0a45243B05436E37A1";
const DEFAULT_ROLE_ID = 8;
const DEFAULT_ROLE_NAME = "DEPOSITOR_ROLE";

const ROLE_AUTHORITY_ABI = [
  "event UserRoleUpdated(address indexed user, uint8 indexed role, bool enabled)",
  "function doesUserHaveRole(address user, uint8 role) view returns (bool)",
];

type ChainName = "ethereum" | "plume";

type ChainConfig = {
  name: ChainName;
  rpcEnv: string;
};

type RoleEvent = {
  user: string;
  enabled: boolean;
  blockNumber: number;
  transactionHash: string;
  logIndex: number;
};

type RoleHolder = {
  user: string;
  lastUpdatedBlock: number;
  lastUpdatedTx: string;
};

type ChainResult = {
  chain: ChainName;
  authority: string;
  roleName: string;
  roleId: number;
  fromBlock: number;
  toBlock: number;
  eventCount: number;
  holders: RoleHolder[];
  disabledUsers: RoleHolder[];
};

type Args = {
  authority: string;
  roleId: number;
  roleName: string;
  chains: ChainName[];
  fromBlock?: number;
  toBlock?: number;
  ethereumFromBlock?: number;
  plumeFromBlock?: number;
  ethereumToBlock?: number;
  plumeToBlock?: number;
  querySize: number;
  maxLogRequests: number;
  ethereumLogSource: "auto" | "rpc" | "etherscan";
  includeDisabled: boolean;
  json: boolean;
  noVerify: boolean;
  quiet: boolean;
};

type EtherscanLog = {
  topics: string[];
  data: string;
  blockNumber: string;
  transactionHash: string;
  logIndex: string;
};

const CHAINS: Record<ChainName, ChainConfig> = {
  ethereum: { name: "ethereum", rpcEnv: "ETHEREUM_RPC_URL" },
  plume: { name: "plume", rpcEnv: "PLUME_RPC_URL" },
};

function usage(): string {
  return [
    "Usage:",
    "  pnpm exec ts-node tools/mapDepositorRole.ts [options]",
    "",
    "Options:",
    "  --authority <address>              RolesAuthority address",
    "  --role <uint8>                     Role id to map (default: 8)",
    "  --role-name <name>                 Display name (default: DEPOSITOR_ROLE)",
    "  --chain <ethereum,plume>           Chains to query (default: ethereum,plume)",
    "  --from-block <number>              Shared start block; defaults to discovered deployment block",
    "  --to-block <number>                Shared end block; defaults to latest",
    "  --ethereum-from-block <number>     Ethereum-specific start block",
    "  --plume-from-block <number>        Plume-specific start block",
    "  --ethereum-to-block <number>       Ethereum-specific end block",
    "  --plume-to-block <number>          Plume-specific end block",
    "  --query-size <number>              Initial eth_getLogs block span (default: 50000)",
    "  --max-log-requests <number>        Safety cap per chain (default: 2000)",
    "  --ethereum-log-source <source>     auto, rpc, or etherscan (default: auto)",
    "  --include-disabled                 Also print users whose latest role event is disabled",
    "  --json                             Print JSON instead of a human-readable report",
    "  --no-verify                        Skip doesUserHaveRole checks for event candidates",
    "  --quiet                            Suppress progress logs",
    "  --help                             Print this help",
    "",
    "Env:",
    "  ETHEREUM_RPC_URL and PLUME_RPC_URL are read from .env.",
    "  ETHERSCAN_KEY or ETHERSCAN_API_KEY enables the Ethereum Etherscan log source.",
    "  ROLES_AUTHORITY and DEPOSITOR_ROLE_ID can override the defaults.",
  ].join("\n");
}

function parseNumberFlag(name: string, value: string | undefined): number {
  if (!value) throw new Error(`Missing value for ${name}`);
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0)
    throw new Error(`${name} must be a non-negative integer`);
  return parsed;
}

function parseRoleId(value: string | undefined): number {
  const roleId = parseNumberFlag("--role", value);
  if (roleId > 255) throw new Error("--role must fit in uint8");
  return roleId;
}

function parseArgs(argv: string[]): Args {
  const roleIdFromEnv = process.env.DEPOSITOR_ROLE_ID
    ? parseRoleId(process.env.DEPOSITOR_ROLE_ID)
    : DEFAULT_ROLE_ID;
  const args: Args = {
    authority: process.env.ROLES_AUTHORITY ?? DEFAULT_AUTHORITY,
    roleId: roleIdFromEnv,
    roleName: process.env.ROLE_NAME ?? DEFAULT_ROLE_NAME,
    chains: ["ethereum", "plume"],
    querySize: 50_000,
    maxLogRequests: 2_000,
    ethereumLogSource: "auto",
    includeDisabled: false,
    json: false,
    noVerify: false,
    quiet: false,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--":
        break;
      case "--authority":
        args.authority = argv[++i];
        break;
      case "--role":
      case "--role-id":
        args.roleId = parseRoleId(argv[++i]);
        break;
      case "--role-name":
        args.roleName = argv[++i];
        break;
      case "--chain":
      case "--chains":
        args.chains = parseChains(argv[++i]);
        break;
      case "--from-block":
        args.fromBlock = parseNumberFlag(arg, argv[++i]);
        break;
      case "--to-block":
        args.toBlock = parseNumberFlag(arg, argv[++i]);
        break;
      case "--ethereum-from-block":
        args.ethereumFromBlock = parseNumberFlag(arg, argv[++i]);
        break;
      case "--plume-from-block":
        args.plumeFromBlock = parseNumberFlag(arg, argv[++i]);
        break;
      case "--ethereum-to-block":
        args.ethereumToBlock = parseNumberFlag(arg, argv[++i]);
        break;
      case "--plume-to-block":
        args.plumeToBlock = parseNumberFlag(arg, argv[++i]);
        break;
      case "--query-size":
        args.querySize = parseNumberFlag(arg, argv[++i]);
        if (args.querySize === 0)
          throw new Error("--query-size must be greater than zero");
        break;
      case "--max-log-requests":
        args.maxLogRequests = parseNumberFlag(arg, argv[++i]);
        if (args.maxLogRequests === 0)
          throw new Error("--max-log-requests must be greater than zero");
        break;
      case "--ethereum-log-source":
        args.ethereumLogSource = parseEthereumLogSource(argv[++i]);
        break;
      case "--include-disabled":
        args.includeDisabled = true;
        break;
      case "--json":
        args.json = true;
        break;
      case "--no-verify":
        args.noVerify = true;
        break;
      case "--quiet":
        args.quiet = true;
        break;
      case "--help":
      case "-h":
        console.log(usage());
        process.exit(0);
      default:
        throw new Error(`Unknown argument: ${arg}\n\n${usage()}`);
    }
  }

  args.authority = ethers.utils.getAddress(args.authority);
  return args;
}

function parseEthereumLogSource(
  value: string | undefined,
): Args["ethereumLogSource"] {
  if (value === "auto" || value === "rpc" || value === "etherscan")
    return value;
  throw new Error("--ethereum-log-source must be auto, rpc, or etherscan");
}

function parseChains(value: string | undefined): ChainName[] {
  if (!value) throw new Error("Missing value for --chain");
  const chains = value.split(",").map((chain) => chain.trim().toLowerCase());
  if (chains.length === 0)
    throw new Error("--chain must include at least one chain");

  return chains.map((chain) => {
    if (chain !== "ethereum" && chain !== "plume") {
      throw new Error(
        `Unsupported chain "${chain}". Supported chains: ethereum, plume`,
      );
    }
    return chain;
  });
}

function log(args: Args, message: string) {
  if (!args.quiet && !args.json) console.error(message);
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

function suggestedQuerySize(message: string): number | undefined {
  const decimalMatch = message.match(/up to a ([\d,]+) block range/i);
  if (decimalMatch) return Number(decimalMatch[1].replace(/,/g, ""));

  const hexRangeMatch = message.match(/\[0x([0-9a-f]+),\s*0x([0-9a-f]+)\]/i);
  if (!hexRangeMatch) return undefined;

  const start = parseInt(hexRangeMatch[1], 16);
  const end = parseInt(hexRangeMatch[2], 16);
  return end >= start ? end - start + 1 : undefined;
}

async function discoverDeploymentBlock(
  provider: ethers.providers.JsonRpcProvider,
  authority: string,
  latestBlock: number,
): Promise<number> {
  const latestCode = await provider.getCode(authority, latestBlock);
  if (latestCode === "0x")
    throw new Error(`No code found for ${authority} at block ${latestBlock}`);

  let low = 0;
  let high = latestBlock;

  while (low < high) {
    const mid = Math.floor((low + high) / 2);
    const code = await provider.getCode(authority, mid);
    if (code === "0x") low = mid + 1;
    else high = mid;
  }

  return low;
}

async function getRoleEvents(
  provider: ethers.providers.JsonRpcProvider,
  args: Args,
  chain: ChainName,
  fromBlock: number,
  toBlock: number,
): Promise<RoleEvent[]> {
  const iface = new ethers.utils.Interface(ROLE_AUTHORITY_ABI);
  const roleTopic = ethers.utils.hexZeroPad(
    ethers.utils.hexlify(args.roleId),
    32,
  );
  const filter = {
    address: args.authority,
    topics: [iface.getEventTopic("UserRoleUpdated"), null, roleTopic],
  };

  const events: RoleEvent[] = [];
  let start = fromBlock;
  let querySize = args.querySize;
  let requestCount = 0;

  while (start <= toBlock) {
    if (++requestCount > args.maxLogRequests) {
      throw new Error(
        `${chain} exceeded --max-log-requests (${args.maxLogRequests}) at block ${start}. ` +
          "Use a narrower --from-block, a larger --max-log-requests, or an RPC that supports larger eth_getLogs ranges.",
      );
    }

    const end = Math.min(start + querySize - 1, toBlock);

    try {
      const logs = await provider.getLogs({
        ...filter,
        fromBlock: start,
        toBlock: end,
      });
      for (const rawLog of logs) {
        const parsed = iface.parseLog(rawLog);
        events.push({
          user: ethers.utils.getAddress(parsed.args.user),
          enabled: parsed.args.enabled,
          blockNumber: rawLog.blockNumber,
          transactionHash: rawLog.transactionHash,
          logIndex: rawLog.logIndex,
        });
      }
      if (requestCount === 1 || requestCount % 25 === 0 || end === toBlock) {
        log(
          args,
          `${chain}: scanned ${start}-${end}, found ${events.length} ${args.roleName} events so far`,
        );
      }
      start = end + 1;
    } catch (error) {
      const message = errorMessage(error);
      const suggested = suggestedQuerySize(message);
      const nextQuerySize = suggested
        ? Math.min(querySize - 1, suggested)
        : Math.floor(querySize / 2);

      if (nextQuerySize >= 1 && nextQuerySize < querySize) {
        querySize = nextQuerySize;
        log(
          args,
          `${chain}: RPC rejected log range; retrying with query size ${querySize}`,
        );
        requestCount--;
        continue;
      }

      throw error;
    }
  }

  events.sort(
    (a, b) => a.blockNumber - b.blockNumber || a.logIndex - b.logIndex,
  );
  return events;
}

function etherscanApiKey(): string | undefined {
  return process.env.ETHERSCAN_KEY ?? process.env.ETHERSCAN_API_KEY;
}

function shouldUseEtherscan(args: Args, chain: ChainName): boolean {
  if (chain !== "ethereum") return false;
  if (args.ethereumLogSource === "rpc") return false;
  if (args.ethereumLogSource === "etherscan") return true;
  return Boolean(etherscanApiKey());
}

async function getRoleEventsViaEtherscan(
  args: Args,
  fromBlock: number,
  toBlock: number,
): Promise<RoleEvent[]> {
  const apiKey = etherscanApiKey();
  if (!apiKey)
    throw new Error(
      "ETHERSCAN_KEY or ETHERSCAN_API_KEY is required for --ethereum-log-source etherscan",
    );

  const iface = new ethers.utils.Interface(ROLE_AUTHORITY_ABI);
  const apiUrl =
    process.env.ETHERSCAN_API_URL ?? "https://api.etherscan.io/v2/api";
  const url = new URL(apiUrl);

  url.searchParams.set("chainid", "1");
  url.searchParams.set("module", "logs");
  url.searchParams.set("action", "getLogs");
  url.searchParams.set("fromBlock", String(fromBlock));
  url.searchParams.set("toBlock", String(toBlock));
  url.searchParams.set("address", args.authority);
  url.searchParams.set("topic0", iface.getEventTopic("UserRoleUpdated"));
  url.searchParams.set(
    "topic2",
    ethers.utils.hexZeroPad(ethers.utils.hexlify(args.roleId), 32),
  );
  url.searchParams.set("topic0_2_opr", "and");
  url.searchParams.set("apikey", apiKey);

  const response = await fetch(url);
  if (!response.ok)
    throw new Error(`Etherscan log query failed with HTTP ${response.status}`);

  const body = (await response.json()) as {
    status: string;
    message: string;
    result: EtherscanLog[] | string;
  };
  if (
    body.status === "0" &&
    typeof body.result === "string" &&
    body.result.toLowerCase().includes("no records")
  ) {
    return [];
  }
  if (!Array.isArray(body.result)) {
    throw new Error(
      `Etherscan log query failed: ${body.message}: ${body.result}`,
    );
  }

  return body.result
    .map((rawLog) => {
      const parsed = iface.parseLog({
        topics: rawLog.topics,
        data: rawLog.data,
      });
      return {
        user: ethers.utils.getAddress(parsed.args.user),
        enabled: parsed.args.enabled,
        blockNumber: ethers.BigNumber.from(rawLog.blockNumber).toNumber(),
        transactionHash: rawLog.transactionHash,
        logIndex: ethers.BigNumber.from(rawLog.logIndex).toNumber(),
      };
    })
    .sort((a, b) => a.blockNumber - b.blockNumber || a.logIndex - b.logIndex);
}

async function verifyCandidates(
  provider: ethers.providers.JsonRpcProvider,
  args: Args,
  candidates: Map<string, RoleEvent>,
): Promise<Map<string, RoleEvent>> {
  if (args.noVerify) return candidates;

  const contract = new ethers.Contract(
    args.authority,
    ROLE_AUTHORITY_ABI,
    provider,
  );
  const verified = new Map<string, RoleEvent>();

  for (const [user, event] of candidates) {
    const hasRole = await contract.doesUserHaveRole(user, args.roleId);
    if (hasRole) verified.set(user, event);
  }

  return verified;
}

function classifyEvents(events: RoleEvent[]) {
  const latestByUser = new Map<string, RoleEvent>();
  for (const event of events) latestByUser.set(event.user, event);

  const enabled = new Map<string, RoleEvent>();
  const disabled = new Map<string, RoleEvent>();

  for (const [user, event] of latestByUser) {
    if (event.enabled) enabled.set(user, event);
    else disabled.set(user, event);
  }

  return { enabled, disabled };
}

function toRoleHolders(eventsByUser: Map<string, RoleEvent>): RoleHolder[] {
  return [...eventsByUser.values()]
    .sort((a, b) => a.user.localeCompare(b.user))
    .map((event) => ({
      user: event.user,
      lastUpdatedBlock: event.blockNumber,
      lastUpdatedTx: event.transactionHash,
    }));
}

function chainSpecificBlock(
  args: Args,
  chain: ChainName,
  kind: "from" | "to",
): number | undefined {
  if (chain === "ethereum" && kind === "from")
    return args.ethereumFromBlock ?? args.fromBlock;
  if (chain === "ethereum" && kind === "to")
    return args.ethereumToBlock ?? args.toBlock;
  if (chain === "plume" && kind === "from")
    return args.plumeFromBlock ?? args.fromBlock;
  return args.plumeToBlock ?? args.toBlock;
}

async function mapChain(args: Args, chain: ChainName): Promise<ChainResult> {
  const config = CHAINS[chain];
  const rpcUrl = process.env[config.rpcEnv];
  if (!rpcUrl) throw new Error(`${config.rpcEnv} is not set`);

  const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
  const latestBlock = await provider.getBlockNumber();
  const toBlock = chainSpecificBlock(args, chain, "to") ?? latestBlock;
  const explicitFromBlock = chainSpecificBlock(args, chain, "from");

  if (toBlock > latestBlock) {
    throw new Error(
      `${chain} --to-block ${toBlock} is above latest block ${latestBlock}`,
    );
  }

  const fromBlock =
    explicitFromBlock ??
    (await discoverDeploymentBlock(provider, args.authority, toBlock));
  if (fromBlock > toBlock)
    throw new Error(
      `${chain} fromBlock ${fromBlock} is above toBlock ${toBlock}`,
    );

  log(
    args,
    `${chain}: mapping ${args.roleName} (${args.roleId}) from block ${fromBlock} to ${toBlock}`,
  );
  const useEtherscan = shouldUseEtherscan(args, chain);
  if (useEtherscan)
    log(args, `${chain}: using Etherscan for historical role logs`);
  const events = useEtherscan
    ? await getRoleEventsViaEtherscan(args, fromBlock, toBlock)
    : await getRoleEvents(provider, args, chain, fromBlock, toBlock);
  const { enabled, disabled } = classifyEvents(events);
  const verifiedEnabled = await verifyCandidates(provider, args, enabled);

  return {
    chain,
    authority: args.authority,
    roleName: args.roleName,
    roleId: args.roleId,
    fromBlock,
    toBlock,
    eventCount: events.length,
    holders: toRoleHolders(verifiedEnabled),
    disabledUsers: toRoleHolders(disabled),
  };
}

function printHuman(results: ChainResult[], includeDisabled: boolean) {
  for (const result of results) {
    console.log(`\n${result.chain}`);
    console.log(`  authority: ${result.authority}`);
    console.log(`  role: ${result.roleName} (${result.roleId})`);
    console.log(`  blocks: ${result.fromBlock} -> ${result.toBlock}`);
    console.log(`  matching role events: ${result.eventCount}`);
    console.log(`  current holders: ${result.holders.length}`);

    for (const holder of result.holders) {
      console.log(
        `    - ${holder.user} (last updated block ${holder.lastUpdatedBlock}, tx ${holder.lastUpdatedTx})`,
      );
    }

    if (includeDisabled && result.disabledUsers.length > 0) {
      console.log(`  disabled users: ${result.disabledUsers.length}`);
      for (const holder of result.disabledUsers) {
        console.log(
          `    - ${holder.user} (disabled at block ${holder.lastUpdatedBlock}, tx ${holder.lastUpdatedTx})`,
        );
      }
    }
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const results: ChainResult[] = [];

  for (const chain of args.chains) {
    results.push(await mapChain(args, chain));
  }

  if (args.json) {
    console.log(JSON.stringify(results, null, 2));
  } else {
    printHuman(results, args.includeDisabled);
  }
}

main().catch((error) => {
  console.error(errorMessage(error));
  process.exit(1);
});
