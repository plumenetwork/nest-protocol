/**
 * Safe Transaction Service URLs by chain, plus a local MultiSendCallOnly
 * override map for chains not covered by @safe-global/safe-deployments.
 */

export type SafeServiceEntry = {
  api: string;
  uiBase: string;
  slug: string;
  /**
   * When true, the wrapper proposes the 5 split slots as 5 separate Safe
   * transactions (one nonce each). When false, all non-empty slots are
   * concatenated in order (1a→1b→2a→2b→3) and proposed as a single
   * MultiSend — one nonce, atomic execution.
   *
   * Plume/Den currently needs the split; other chains tolerate the merged
   * single-tx form, which cuts signer load from 5 → 1 per migration.
   */
  splitBatches: boolean;
};

// Safe migrated per-chain hosts to a unified host under
// `api.safe.global/tx-service/<slug>/api`. @safe-global/api-kit appends
// `/v1/...` to this base, so the `/api` segment must be included here.
export const SAFE_TX_SERVICE: Record<number, SafeServiceEntry> = {
  1: {
    api: "https://api.safe.global/tx-service/eth/api",
    uiBase: "https://app.safe.global",
    slug: "eth",
    splitBatches: false,
  },
  56: {
    api: "https://api.safe.global/tx-service/bnb/api",
    uiBase: "https://app.safe.global",
    slug: "bnb",
    splitBatches: false,
  },
  42161: {
    api: "https://api.safe.global/tx-service/arb1/api",
    uiBase: "https://app.safe.global",
    slug: "arb1",
    splitBatches: false,
  },
  480: {
    api: "https://api.safe.global/tx-service/wc/api",
    uiBase: "https://app.safe.global",
    slug: "wc",
    splitBatches: false,
  },
  9745: {
    api: "https://api.safe.global/tx-service/plasma/api",
    uiBase: "https://app.safe.global",
    slug: "plasma",
    splitBatches: false,
  },
  // Safe chain registry: https://safe-config.safe.global/api/v1/chains/5042/
  5042: {
    api: "https://api.safe.global/tx-service/arc/api",
    uiBase: "https://app.safe.global",
    slug: "arc",
    splitBatches: false,
  },
  98866: {
    api: "https://safe-transaction-plume.onchainden.com/api",
    uiBase: "https://safe.onchainden.com",
    slug: "plume",
    splitBatches: true,
  },
};

// Only populated for chains where @safe-global/safe-deployments has no entry.
// The canonical MultiSendCallOnly v1.3.0 address is shared across most Safe
// deployments; fill in per-chain after confirming on-chain bytecode.
export const MULTISEND_CALL_ONLY_OVERRIDE: Record<number, `0x${string}`> = {
  98866: "0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761",
  5042: "0x40A2aCCbd92BCA938b02010E17A5b8929b49130D",
};

export function arcSafeService(env = process.env): SafeServiceEntry {
  const baseUrl = (name: string, fallback: string) => {
    const value = env[name]?.trim() || fallback;
    const url = new URL(value);
    if (
      url.protocol !== "https:" ||
      url.username ||
      url.password ||
      url.search ||
      url.hash
    )
      throw new Error(
        `${name} must be an HTTPS base URL without credentials, query or fragment`,
      );
    return value.replace(/\/$/, "");
  };
  const api = baseUrl("ARC_SAFE_TX_SERVICE_URL", SAFE_TX_SERVICE[5042].api);
  const uiBase = baseUrl("ARC_SAFE_UI_URL", SAFE_TX_SERVICE[5042].uiBase);
  const slug = env.ARC_SAFE_CHAIN_PREFIX?.trim() || "arc";
  if (!/^[a-zA-Z0-9-]+$/.test(slug))
    throw new Error("Invalid ARC_SAFE_CHAIN_PREFIX");
  return { api, uiBase, slug, splitBatches: false };
}

export function serviceFor(chainId: number): SafeServiceEntry {
  if (chainId === 5042) return arcSafeService();
  const entry = SAFE_TX_SERVICE[chainId];
  if (!entry) {
    throw new Error(
      `no Safe Transaction Service URL configured for chainId ${chainId}`,
    );
  }
  return entry;
}

/**
 * UI URL pointing directly at a queued multisig transaction.
 * Safe-global and Den share the same `/transactions/tx?safe=...&id=multisig_<safe>_<hash>` shape.
 */
export function uiUrlForTx(
  chainId: number,
  safe: string,
  safeTxHash: string,
): string {
  const { uiBase, slug } = serviceFor(chainId);
  return `${uiBase}/transactions/tx?safe=${slug}:${safe}&id=multisig_${safe}_${safeTxHash}`;
}

export function queueUrl(chainId: number, safe: string): string {
  const { uiBase, slug } = serviceFor(chainId);
  return `${uiBase}/transactions/queue?safe=${slug}:${safe}`;
}
