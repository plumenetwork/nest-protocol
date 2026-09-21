/**
 * Safe propose client: wraps @safe-global/api-kit + @safe-global/protocol-kit.
 * Encodes a Safe-Tx-Builder batch via the Safe-version-specific MultiSend
 * contract, signs EIP-712 with the proposer EOA, and POSTs to the chain's Safe
 * Transaction Service.
 *
 * Dry-run mode returns the computed safeTxHash + nonce without any API write.
 */

import SafeApiKit from "@safe-global/api-kit";
import Safe from "@safe-global/protocol-kit";
import {
  OperationType,
  type MetaTransactionData,
} from "@safe-global/types-kit";
import { privateKeyToAccount } from "viem/accounts";
import {
  MULTISEND_CALL_ONLY_OVERRIDE,
  serviceFor,
  uiUrlForTx,
} from "./safeTxService";

export type SafeTx = {
  to: string;
  value: string;
  data: string;
  operation: string;
};

export type ProposeResult = {
  transactionData: SafeTransactionData;
  safeTxHash: string;
  uiUrl: string;
  nonce: number;
  proposed: boolean;
  proposerAddress: `0x${string}`;
  multiSendAddress: `0x${string}`;
  safeVersion: string;
};

export type SafeTransactionData = {
  to: string;
  value: string;
  data: string;
  operation: number;
  safeTxGas: string;
  baseGas: string;
  gasPrice: string;
  gasToken: string;
  refundReceiver: string;
  nonce: number;
};

export type ProposeOptions = {
  chainId: number;
  safe: `0x${string}`;
  txs: SafeTx[];
  signerKey: `0x${string}`;
  rpcUrl: string;
  dryRun?: boolean;
  /**
   * Force a specific Safe nonce instead of the service-derived next nonce.
   * Used to REPLACE an already-queued tx: propose at the same nonce so the
   * Safe service lists this as a competing candidate at that slot.
   */
  nonce?: number;
  /** Refuse to sign if rebuilding differs from the reviewed/simulated transaction. */
  expectedSafeTxHash?: string;
};

function customContractNetworks(chainId: number):
  | Record<
      string,
      {
        multiSendCallOnlyAddress: `0x${string}`;
        multiSendAddress: `0x${string}`;
      }
    >
  | undefined {
  const multiSendAddress = MULTISEND_CALL_ONLY_OVERRIDE[chainId];
  if (!multiSendAddress) return undefined;

  return {
    [chainId.toString()]: {
      multiSendCallOnlyAddress: multiSendAddress,
      multiSendAddress,
    },
  };
}

function toMetaTx(t: SafeTx): MetaTransactionData {
  return {
    to: t.to,
    value: t.value,
    data: t.data,
    operation:
      t.operation === "1" || Number(t.operation) === 1
        ? OperationType.DelegateCall
        : OperationType.Call,
  };
}

export async function proposeBatch(
  opts: ProposeOptions,
): Promise<ProposeResult> {
  const { chainId, safe, txs, signerKey, rpcUrl, dryRun = false, nonce } = opts;
  if (txs.length === 0) {
    throw new Error("proposeBatch called with empty tx array");
  }

  const proposerAddress = privateKeyToAccount(signerKey).address;
  const { api: txServiceUrl } = serviceFor(chainId);
  const contractNetworks = customContractNetworks(chainId);

  const protocolKit = await Safe.init({
    provider: rpcUrl,
    signer: signerKey,
    safeAddress: safe,
    contractNetworks: contractNetworks as never,
  });
  const onlyCalls = txs.every((tx) => Number(tx.operation) !== 1);
  const multiSendAddress = (
    onlyCalls
      ? protocolKit.getMultiSendCallOnlyAddress()
      : protocolKit.getMultiSendAddress()
  ) as `0x${string}`;
  const safeVersion = protocolKit.getContractVersion();

  const apiKit = new SafeApiKit({
    chainId: BigInt(chainId),
    txServiceUrl,
  });

  // Prefer the service-side nonce (accounts for pending queued txs). Falls
  // back to the on-chain nonce when the service errors (fork mode, freshly
  // registered Safe, or backend 5xx — Plasma's list endpoint currently 500s).
  // Safe when the Safe has no pending queued txs; on real prod runs the
  // downstream POST /multisig-transactions/ is a separate endpoint and
  // typically works even when the GET list query is broken.
  let nextNonce: number;
  if (nonce !== undefined) {
    nextNonce = nonce;
  } else {
    try {
      nextNonce = Number(await apiKit.getNextNonce(safe));
    } catch (err) {
      nextNonce = Number(await protocolKit.getNonce());
      const msg = err instanceof Error ? err.message : String(err);
      console.warn(
        `  warning: Safe tx-service nonce lookup failed (${msg}); using on-chain nonce ${nextNonce}`,
      );
    }
  }

  const safeTx = await protocolKit.createTransaction({
    transactions: txs.map(toMetaTx),
    onlyCalls,
    options: { nonce: nextNonce },
  });

  const safeTxHash = await protocolKit.getTransactionHash(safeTx);
  if (
    opts.expectedSafeTxHash &&
    safeTxHash.toLowerCase() !== opts.expectedSafeTxHash.toLowerCase()
  ) {
    throw new Error(
      "Safe transaction changed after simulation; refusing to sign",
    );
  }
  const uiUrl = uiUrlForTx(chainId, safe, safeTxHash);

  if (dryRun) {
    return {
      transactionData: safeTx.data,
      safeTxHash,
      uiUrl,
      nonce: nextNonce,
      proposed: false,
      proposerAddress,
      multiSendAddress,
      safeVersion,
    };
  }

  const signature = await protocolKit.signHash(safeTxHash);

  await apiKit.proposeTransaction({
    safeAddress: safe,
    safeTransactionData: safeTx.data,
    safeTxHash,
    senderAddress: proposerAddress,
    senderSignature: signature.data,
  });

  return {
    transactionData: safeTx.data,
    safeTxHash,
    uiUrl,
    nonce: nextNonce,
    proposed: true,
    proposerAddress,
    multiSendAddress,
    safeVersion,
  };
}

/**
 * Preflight: checks whether the proposer address is a Safe owner or a
 * registered delegate. Returns true if authorized via either path. On API
 * failure, returns `null` and the caller decides (we warn and continue).
 */
export async function isAuthorizedProposer(
  chainId: number,
  safe: `0x${string}`,
  proposer: `0x${string}`,
): Promise<boolean | null> {
  const { api: txServiceUrl } = serviceFor(chainId);
  const apiKit = new SafeApiKit({ chainId: BigInt(chainId), txServiceUrl });
  try {
    const info = await apiKit.getSafeInfo(safe);
    const lower = proposer.toLowerCase();
    if (info.owners.some((o) => o.toLowerCase() === lower)) return true;
    const dels = await apiKit.getSafeDelegates({ safeAddress: safe });
    if (dels.results.some((d) => d.delegate.toLowerCase() === lower))
      return true;
    return false;
  } catch {
    return null;
  }
}

/**
 * Fetch one Safe owner. Tries Safe Tx Service first; falls back to reading
 * `Safe.getOwners()` on-chain via the RPC. Used as the impersonated caller
 * for Tenderly simulations (msg.sender == owner + v=1 sig = pre-approved).
 */
export async function getSafeOwner(
  chainId: number,
  safe: `0x${string}`,
  rpcUrl?: string,
): Promise<`0x${string}` | null> {
  const { api: txServiceUrl } = serviceFor(chainId);
  const apiKit = new SafeApiKit({ chainId: BigInt(chainId), txServiceUrl });
  try {
    const info = await apiKit.getSafeInfo(safe);
    const first = info.owners[0];
    if (first) return first as `0x${string}`;
  } catch {
    // fall through
  }

  if (!rpcUrl) {
    console.warn(`  [getSafeOwner] no rpcUrl passed — cannot fallback`);
    return null;
  }
  try {
    // Safe.getOwners() — selector 0xa0e67e2b, returns address[]
    const body = {
      jsonrpc: "2.0",
      id: 1,
      method: "eth_call",
      params: [{ to: safe, data: "0xa0e67e2b" }, "latest"],
    };
    const res = await fetch(rpcUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      console.warn(`  [getSafeOwner] rpc HTTP ${res.status}`);
      return null;
    }
    const json = (await res.json()) as {
      result?: string;
      error?: { message?: string };
    };
    if (json.error) {
      console.warn(
        `  [getSafeOwner] rpc error: ${json.error.message ?? "unknown"}`,
      );
      return null;
    }
    const hex = json.result;
    if (!hex || hex.length < 2 + 64 * 3) {
      console.warn(`  [getSafeOwner] short result: ${hex ?? "<null>"}`);
      return null;
    }
    const firstWord = hex.slice(2 + 64 * 2, 2 + 64 * 3);
    return `0x${firstWord.slice(24)}` as `0x${string}`;
  } catch (err) {
    console.warn(
      `  [getSafeOwner] rpc fallback threw: ${err instanceof Error ? err.message : String(err)}`,
    );
    return null;
  }
}
