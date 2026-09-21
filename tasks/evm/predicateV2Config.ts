import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

type VaultEntry = {
  assetSymbol?: string;
  chains?: number[];
  address?: string;
};

type VaultConfig = {
  symbol?: string;
  baseAssetSymbol?: string;
  baseAssetOverrides?: Record<string, string>;
  contracts?: { vaults?: VaultEntry[] };
};

type ComplianceConfig = {
  symbol?: string;
  chainId?: number;
  predicateV2Hook?: string;
  complianceProxy?: string;
};

type ChainComplianceConfig = {
  chainId?: number;
  v2?: { apiChain?: string };
};

export type PredicateV2Deployment = {
  symbol: string;
  chainId: number;
  assetSymbol: string;
  vaultAddress: string;
  complianceProxy: string;
  predicateHook: string;
  apiChain: string;
};

function readJson<T>(file: string, label: string): T {
  if (!existsSync(file)) throw new Error(`${label} not found: ${file}`);
  return JSON.parse(readFileSync(file, "utf8")) as T;
}

/** Resolves a vault symbol against the deployment configs for the active chain. */
export function resolvePredicateV2Deployment(
  repoRoot: string,
  symbol: string,
  chainId: number,
): PredicateV2Deployment {
  if (!/^[A-Za-z0-9_-]+$/.test(symbol)) {
    throw new Error(`Invalid vault symbol: ${symbol}`);
  }

  const vaultConfig = readJson<VaultConfig>(
    path.join(
      repoRoot,
      "script",
      "deployment-config",
      "vaults",
      `${symbol}.json`,
    ),
    `Vault config for ${symbol}`,
  );
  if (vaultConfig.symbol && vaultConfig.symbol !== symbol) {
    throw new Error(
      `Vault config symbol mismatch: expected ${symbol}, received ${vaultConfig.symbol}`,
    );
  }

  const assetSymbol =
    vaultConfig.baseAssetOverrides?.[String(chainId)] ??
    vaultConfig.baseAssetSymbol;
  if (!assetSymbol) {
    throw new Error(`Vault config for ${symbol} has no base asset`);
  }

  const vault = vaultConfig.contracts?.vaults?.find(
    (entry) =>
      entry.assetSymbol === assetSymbol &&
      (!entry.chains ||
        entry.chains.length === 0 ||
        entry.chains.includes(chainId)),
  );
  if (!vault?.address) {
    throw new Error(
      `Vault ${symbol} has no ${assetSymbol} deployment configured for chain ${chainId}`,
    );
  }

  const complianceConfig = readJson<ComplianceConfig>(
    path.join(
      repoRoot,
      "script",
      "deployment-config",
      "compliance",
      `${chainId}-${symbol}.json`,
    ),
    `Predicate V2 compliance config for ${symbol} on chain ${chainId}`,
  );
  if (complianceConfig.symbol && complianceConfig.symbol !== symbol) {
    throw new Error(
      `Compliance config symbol mismatch: expected ${symbol}, received ${complianceConfig.symbol}`,
    );
  }
  if (
    complianceConfig.chainId != null &&
    complianceConfig.chainId !== chainId
  ) {
    throw new Error(
      `Compliance config chain mismatch: expected ${chainId}, received ${complianceConfig.chainId}`,
    );
  }
  if (!complianceConfig.complianceProxy) {
    throw new Error(`Compliance config for ${symbol} has no complianceProxy`);
  }
  if (!complianceConfig.predicateV2Hook) {
    throw new Error(`Compliance config for ${symbol} has no predicateV2Hook`);
  }
  const chainComplianceConfig = readJson<ChainComplianceConfig>(
    path.join(repoRoot, "config", "compliance", `${chainId}.json`),
    `Common compliance config for chain ${chainId}`,
  );
  if (chainComplianceConfig.chainId !== chainId) {
    throw new Error(
      `Common compliance config chain mismatch: expected ${chainId}, received ${chainComplianceConfig.chainId}`,
    );
  }
  if (!chainComplianceConfig.v2?.apiChain) {
    throw new Error(
      `Common compliance config for chain ${chainId} has no v2.apiChain`,
    );
  }

  return {
    symbol,
    chainId,
    assetSymbol,
    vaultAddress: vault.address,
    complianceProxy: complianceConfig.complianceProxy,
    predicateHook: complianceConfig.predicateV2Hook,
    apiChain: chainComplianceConfig.v2.apiChain,
  };
}
