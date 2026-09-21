import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

import { EndpointId } from "@layerzerolabs/lz-definitions";
import { ExecutorOptionType } from "@layerzerolabs/lz-v2-utilities";
import { generateConnectionsConfig } from "@layerzerolabs/metadata-tools";
import {
  OAppEnforcedOption,
  OmniPointHardhat,
} from "@layerzerolabs/toolbox-hardhat";

const SOLANA_CHAIN_ID = 101;

const CHAIN_TO_EID: Record<number, EndpointId> = {
  98866: EndpointId.PLUMEPHOENIX_V2_MAINNET,
  1: EndpointId.ETHEREUM_V2_MAINNET,
  42161: EndpointId.ARBITRUM_V2_MAINNET,
  9745: EndpointId.PLASMA_V2_MAINNET,
  56: EndpointId.BSC_V2_MAINNET,
  480: EndpointId.WORLDCHAIN_V2_MAINNET,
  8453: EndpointId.BASE_V2_MAINNET,
  101: EndpointId.SOLANA_V2_MAINNET,
  43114: EndpointId.AVALANCHE_V2_MAINNET,
};

function readJson(filePath: string) {
  const resolved = path.resolve(filePath);
  if (!existsSync(resolved)) {
    throw new Error(`File not found: ${resolved}`);
  }
  return JSON.parse(readFileSync(resolved, "utf-8"));
}

type OutputVault = { address: string; assetSymbol: string };
type OutputConfig = {
  baseAssetSymbol: string;
  vaultType: string;
  contracts: { share: string; vaults: OutputVault[] };
};

function readOutput(vaultSymbol: string, chainId: number): OutputConfig {
  const p = path.resolve(
    `script/output/${vaultSymbol}/${chainId}-${vaultSymbol}.json`,
  );
  if (!existsSync(p)) {
    throw new Error(`output file missing for chainId=${chainId}: ${p}`);
  }
  return JSON.parse(readFileSync(p, "utf-8")) as OutputConfig;
}

/// Mirrors SetPeers source-of-truth: post-deploy script/output/<vault>/<chainId>-<vault>.json.
/// vaultType=NestVaultOFT → canonical vault entry (assetSymbol==baseAssetSymbol); else → contracts.share.
function evmAddrForChain(vaultSymbol: string, chainId: number): string {
  const out = readOutput(vaultSymbol, chainId);
  const isOFT = out.vaultType === "NestVaultOFT";
  const addr = isOFT
    ? out.contracts.vaults.find((v) => v.assetSymbol === out.baseAssetSymbol)
        ?.address
    : out.contracts.share;
  if (!addr) {
    throw new Error(
      `no canonical OApp address in output for chainId=${chainId}`,
    );
  }
  if (/^0x0+$/i.test(addr)) {
    throw new Error(
      `chainId=${chainId} has zero address in script/output — vault not deployed there yet`,
    );
  }
  return addr;
}

// hardhat.config.ts network names by chain id — hardhat-deploy reads
// deployments/<network>/, so stubs must land under the exact network name the
// wire task connects with. A chain with no entry here has no hardhat network
// and cannot be wired at all.
const CHAIN_TO_NETWORK: Record<number, string> = {
  1: "ethereummainnet",
  56: "bnbmainnet",
  480: "worldchain",
  8453: "base",
  9745: "plasma-mainnet",
  43114: "avalanche",
  98866: "plumephoenix",
};

/**
 * Guarantee a hardhat-deploy artifact exists for one EVM leg of the wire graph.
 *
 * devtools resolves each EVM OmniPointHardhat through hardhat-deploy: there is
 * no compiled hardhat artifact named after the vault symbol, so it falls back
 * to an address lookup over deployments/<network>/*.json and asserts when
 * nothing matches ("Could not find a deployment for address …"). Vaults
 * deployed outside the forge flow have no committed artifact, so synthesize
 * the minimal { address, abi } record (the shape the historic hand-written
 * stubs used) from script/output + script/solana-lz-abi before the graph
 * resolves. An existing stub is left untouched — but its address must
 * byte-match the wire graph's (hardhat-deploy's lookup is an exact string
 * compare), and the folder's .chainId must match the chain, or wiring could
 * only fail or target the wrong OApp.
 */
export function ensureEvmDeploymentStub(
  vaultSymbol: string,
  chainId: number,
  address: string,
): void {
  const network = CHAIN_TO_NETWORK[chainId];
  if (!network) {
    throw new Error(
      `no hardhat network mapped for chainId=${chainId} — add it to CHAIN_TO_NETWORK ` +
        `(and to hardhat.config.ts networks)`,
    );
  }
  const dir = path.resolve("deployments", network);
  const stubPath = path.join(dir, `${vaultSymbol}.json`);
  const chainIdPath = path.join(dir, ".chainId");

  if (existsSync(chainIdPath)) {
    const found = readFileSync(chainIdPath, "utf-8").trim();
    if (found !== String(chainId)) {
      throw new Error(
        `${chainIdPath} holds chainId ${found} but network ${network} is chainId ${chainId} — ` +
          `deployments folder mismatch`,
      );
    }
  }

  if (existsSync(stubPath)) {
    const existing = readJson(stubPath);
    if (existing.address !== address) {
      throw new Error(
        `${stubPath} holds address ${existing.address}, but script/output resolves ${address} — ` +
          `stale deployment stub, refusing to wire a mismatched OApp`,
      );
    }
  } else {
    const isOFT = readOutput(vaultSymbol, chainId).vaultType === "NestVaultOFT";
    const abi = readJson(
      `script/solana-lz-abi/${isOFT ? "NestVaultOFT" : "NestShareOFT"}.json`,
    );
    mkdirSync(dir, { recursive: true });
    writeFileSync(stubPath, JSON.stringify({ address, abi }, null, 2) + "\n");
  }

  if (!existsSync(chainIdPath)) {
    writeFileSync(chainIdPath, String(chainId));
  }
}

const EVM_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
  {
    msgType: 1,
    optionType: ExecutorOptionType.LZ_RECEIVE,
    gas: 100_000,
    value: 0,
  },
  {
    msgType: 2,
    optionType: ExecutorOptionType.LZ_RECEIVE,
    gas: 350_000,
    value: 0,
  },
  {
    msgType: 2,
    optionType: ExecutorOptionType.COMPOSE,
    index: 0,
    gas: 350_000,
    value: 0,
  },
];

const CU_LIMIT = 200_000;
const SPL_TOKEN_ACCOUNT_RENT_VALUE = 2_039_280;

// LayerZero Labs executor on Solana mainnet (matches what metadata-tools picks).
const SOLANA_EXECUTOR = "AwrbHeCyniXaQhiJZkLhgWdUCteeWSGaSN1sTfLiY7xK";

const SOLANA_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
  {
    msgType: 1,
    optionType: ExecutorOptionType.LZ_RECEIVE,
    gas: CU_LIMIT,
    value: SPL_TOKEN_ACCOUNT_RENT_VALUE,
  },
];

// All env reads and file reads happen here, not at module load: hardhat.config.ts pulls this
// module in for every task (via tasks/evm/sendEvm.ts), and eager reads break tasks that run
// before the per-vault config/deployment files exist — e.g. create for a new vault, which is
// the very task that produces deployments/solana-mainnet/<symbol>-OFT.json.
export default async function () {
  const VAULT_SYMBOL = process.env.VAULT_SYMBOL;
  if (!VAULT_SYMBOL) {
    throw new Error(
      "VAULT_SYMBOL env var is required (e.g. VAULT_SYMBOL=nWISDOM)",
    );
  }

  const vaultConfig = readJson(
    `script/deployment-config/vaults/${VAULT_SYMBOL}.json`,
  );
  const solanaDeployment = readJson(
    `deployments/solana-mainnet/${VAULT_SYMBOL}-OFT.json`,
  );

  const peers: number[] = vaultConfig.peers ?? [];
  if (!peers.includes(SOLANA_CHAIN_ID)) {
    throw new Error(
      `vault ${VAULT_SYMBOL} has no Solana peer in vaults/${VAULT_SYMBOL}.json`,
    );
  }

  const solanaContract: OmniPointHardhat = {
    eid: EndpointId.SOLANA_V2_MAINNET,
    address: solanaDeployment.oftStore,
  };

  const evmChainIds = peers.filter((c) => c !== SOLANA_CHAIN_ID);
  const requestedEvmChainIds = process.env.EVM_CHAIN_IDS?.split(",").map(
    (value) => {
      const chainId = Number(value.trim());
      if (!Number.isSafeInteger(chainId) || chainId <= 0) {
        throw new Error(`invalid chain ID in EVM_CHAIN_IDS: ${value}`);
      }
      return chainId;
    },
  );

  if (requestedEvmChainIds?.length) {
    for (const chainId of requestedEvmChainIds) {
      if (!evmChainIds.includes(chainId)) {
        throw new Error(
          `EVM_CHAIN_IDS contains chainId=${chainId}, which is not an EVM peer for ${VAULT_SYMBOL}`,
        );
      }
    }
  }

  // Limit the generated graph when wiring a single new Solana pathway. Unset by default so the
  // canonical generated config continues to cover every configured EVM peer.
  const selectedEvmChainIds = requestedEvmChainIds?.length
    ? requestedEvmChainIds
    : evmChainIds;

  const evmContracts: OmniPointHardhat[] = selectedEvmChainIds.map(
    (chainId) => {
      const eid = CHAIN_TO_EID[chainId];
      if (!eid) throw new Error(`unknown chainId in peers: ${chainId}`);
      const address = evmAddrForChain(VAULT_SYMBOL, chainId);
      ensureEvmDeploymentStub(VAULT_SYMBOL, chainId, address);
      return {
        eid,
        contractName: VAULT_SYMBOL,
        address,
      };
    },
  );

  const tuples = evmContracts.map(
    (evm) =>
      [
        evm,
        solanaContract,
        [["LayerZero Labs", "Nethermind", "Canary"], []],
        [0, 0],
        [SOLANA_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
      ] as Parameters<typeof generateConnectionsConfig>[0][number],
  );

  const connections = await generateConnectionsConfig(tuples);

  // By default emit only Solana → EVM lanes (EVM → Solana and EVM ↔ EVM are wired by
  // deploy.ts; including them here would make wire propose EVM-side txs).
  // Set INCLUDE_ALL_ROUTES=1 to inspect every route for the vault.
  const includeAll = process.env.INCLUDE_ALL_ROUTES === "1";
  const filtered = includeAll
    ? connections
    : connections.filter((c) => c.from.eid === EndpointId.SOLANA_V2_MAINNET);

  // metadata-tools drops sendConfig and enforcedOptions from B→A side when
  // BToAConfirmations is falsy (0). We want conf=0 (= "use lib default") on Solana send,
  // so re-inject sendConfig (mirroring receiveConfig DVNs + Solana executor) and
  // enforcedOptions on Solana → EVM connections only.
  const patched = filtered.map((c) => {
    if (c.from.eid !== EndpointId.SOLANA_V2_MAINNET) return c;
    const cfg = c.config;
    if (!cfg) return c;
    const next = { ...cfg };
    if (!next.sendConfig && next.receiveConfig?.ulnConfig) {
      const recvUln = next.receiveConfig.ulnConfig;
      next.sendConfig = {
        executorConfig: { maxMessageSize: 10000, executor: SOLANA_EXECUTOR },
        ulnConfig: {
          confirmations: recvUln.confirmations,
          requiredDVNs: recvUln.requiredDVNs ?? [],
          requiredDVNCount: recvUln.requiredDVNCount,
          optionalDVNs: recvUln.optionalDVNs ?? [],
          optionalDVNThreshold: recvUln.optionalDVNThreshold ?? 0,
        },
      };
    }
    // from=Solana, to=EVM → enforcedOptions govern EVM lzReceive.
    if (!next.enforcedOptions || next.enforcedOptions.length === 0) {
      next.enforcedOptions = EVM_ENFORCED_OPTIONS;
    }
    return { ...c, config: next };
  });

  return {
    contracts: [
      ...evmContracts.map((c) => ({ contract: c })),
      { contract: solanaContract },
    ],
    connections: patched,
  };
}
