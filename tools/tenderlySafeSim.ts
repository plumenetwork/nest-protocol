/**
 * Tenderly simulation of a Safe batch *as a single execTransaction call*,
 * using state overrides to bypass signature verification. One simulation →
 * one shared URL that shows the full call tree Safe → MultiSend → inner txs.
 *
 * State overrides (matches what Safe's own "simulate" UI uses):
 *   slot 4 (threshold) → 1
 *   slot 5 (nonce)     → the Safe-tx nonce we're executing
 *
 * Signature uses the "pre-approved" form (v=1, r=owner address). Combined
 * with `from = ownerAddress`, Safe.checkNSignatures treats this as approved
 * without needing an ECDSA sig or a populated approvedHashes slot — per the
 * `msg.sender == currentOwner` branch of checkNSignatures.
 */

import {
  concatHex,
  encodeFunctionData,
  encodePacked,
  pad,
  toHex,
  type Hex,
} from "viem";

import type { SafeTx } from "./splitMsigBatchesLib";
import type { SafeTransactionData } from "./safePropose";

// MultiSendCallOnly.multiSend(bytes)
const MULTI_SEND_ABI = [
  {
    type: "function",
    name: "multiSend",
    inputs: [{ type: "bytes", name: "transactions" }],
    outputs: [],
    stateMutability: "payable",
  },
] as const;

// Safe v1.3+ execTransaction
const SAFE_EXEC_ABI = [
  {
    type: "function",
    name: "execTransaction",
    inputs: [
      { type: "address", name: "to" },
      { type: "uint256", name: "value" },
      { type: "bytes", name: "data" },
      { type: "uint8", name: "operation" },
      { type: "uint256", name: "safeTxGas" },
      { type: "uint256", name: "baseGas" },
      { type: "uint256", name: "gasPrice" },
      { type: "address", name: "gasToken" },
      { type: "address", name: "refundReceiver" },
      { type: "bytes", name: "signatures" },
    ],
    outputs: [{ type: "bool" }],
    stateMutability: "payable",
  },
] as const;

export type SafeSimResult = {
  success: boolean;
  url: string;
  errorMessage?: string;
};

export type SafeSimOptions = {
  chainId: number;
  safe: `0x${string}`;
  multiSendAddress: `0x${string}`;
  txs: SafeTx[];
  ownerAddress: `0x${string}`;
  safeNonce: number;
  /** When supplied, simulate the exact SDK envelope rather than reconstructing it. */
  transactionData?: SafeTransactionData;
};

function tenderlyConfig(): {
  accessKey: string;
  account: string;
  project: string;
} | null {
  const accessKey = process.env.TENDERLY_ACCESS_KEY?.trim();
  const account = process.env.TENDERLY_ACCOUNT?.trim();
  const project = process.env.TENDERLY_PROJECT?.trim();
  if (!accessKey || !account || !project) return null;
  return { accessKey, account, project };
}

/** Pack an array of Safe txs into MultiSend.multiSend(bytes) calldata. */
export function encodeMultiSend(txs: SafeTx[]): Hex {
  const packed = concatHex(
    txs.map((t) => {
      const op = Number(t.operation) === 1 ? 1 : 0;
      const dataBytes = (t.data.length - 2) / 2;
      return encodePacked(
        ["uint8", "address", "uint256", "uint256", "bytes"],
        [
          op,
          t.to as `0x${string}`,
          BigInt(t.value),
          BigInt(dataBytes),
          t.data as Hex,
        ],
      );
    }),
  );
  return encodeFunctionData({
    abi: MULTI_SEND_ABI,
    functionName: "multiSend",
    args: [packed],
  });
}

/** Pre-approved Safe signature: r = owner, s = 0, v = 1. Exactly 65 bytes. */
function preApprovedSignature(owner: `0x${string}`): Hex {
  const r = pad(owner, { size: 32 });
  const s = `0x${"00".repeat(32)}` as Hex;
  const v = "0x01";
  return concatHex([r, s, v]);
}

/**
 * Simulate the Safe's execTransaction of a MultiSend bundle on Tenderly.
 * Returns null when TENDERLY_* env is not configured.
 */
export async function simulateSafeExec(
  opts: SafeSimOptions,
): Promise<SafeSimResult | null> {
  const cfg = tenderlyConfig();
  if (!cfg) return null;
  if (opts.txs.length === 0) return { success: true, url: "<no-txs>" };

  const multiSendCalldata = encodeMultiSend(opts.txs);
  const signatures = preApprovedSignature(opts.ownerAddress);
  const tx = opts.transactionData;
  if (tx && tx.nonce !== opts.safeNonce)
    throw new Error("simulation nonce mismatch");

  const execInput = encodeFunctionData({
    abi: SAFE_EXEC_ABI,
    functionName: "execTransaction",
    args: [
      (tx?.to ?? opts.multiSendAddress) as Hex,
      BigInt(tx?.value ?? 0),
      (tx?.data ?? multiSendCalldata) as Hex,
      tx?.operation ?? 1,
      BigInt(tx?.safeTxGas ?? 0),
      BigInt(tx?.baseGas ?? 0),
      BigInt(tx?.gasPrice ?? 0),
      (tx?.gasToken ?? "0x0000000000000000000000000000000000000000") as Hex,
      (tx?.refundReceiver ??
        "0x0000000000000000000000000000000000000000") as Hex,
      signatures,
    ],
  });

  // Storage overrides (decoded form — Tenderly accepts `decoded: false` raw).
  const slotThreshold = pad("0x04", { size: 32 });
  const slotNonce = pad("0x05", { size: 32 });
  const valOne = pad("0x01", { size: 32 });
  const valNonce = pad(toHex(BigInt(opts.safeNonce)), { size: 32 });

  const body = {
    network_id: String(opts.chainId),
    from: opts.ownerAddress,
    to: opts.safe,
    input: execInput,
    value: 0,
    gas: 30_000_000,
    gas_price: "0",
    save: true,
    save_if_fails: true,
    state_objects: {
      [opts.safe]: {
        storage: {
          [slotThreshold]: valOne,
          [slotNonce]: valNonce,
        },
      },
    },
  };

  const url = `https://api.tenderly.co/api/v1/account/${cfg.account}/project/${cfg.project}/simulate`;

  let res: Response;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Access-Key": cfg.accessKey,
      },
      body: JSON.stringify(body),
    });
  } catch (err) {
    return {
      success: false,
      url: "",
      errorMessage: `network: ${err instanceof Error ? err.message : String(err)}`,
    };
  }

  if (!res.ok) {
    const text = await res.text().catch(() => "");
    return {
      success: false,
      url: "",
      errorMessage: `HTTP ${res.status}: ${text.slice(0, 400)}`,
    };
  }

  const data = (await res.json()) as {
    simulation?: { id?: string; status?: boolean; error_message?: string };
    transaction?: { status?: boolean; error_message?: string };
  };
  const id = data.simulation?.id;
  if (!id) {
    return {
      success: false,
      url: "",
      errorMessage: "no simulation.id in response",
    };
  }

  // Share it so the URL is public.
  const shareResponse = await fetch(
    `https://api.tenderly.co/api/v1/account/${cfg.account}/project/${cfg.project}/simulations/${id}/share`,
    { method: "POST", headers: { "X-Access-Key": cfg.accessKey } },
  ).catch(() => null);
  if (!shareResponse?.ok) {
    return {
      success: false,
      url: "",
      errorMessage: `simulation ${id}: sharing failed (${shareResponse?.status ?? "network error"})`,
    };
  }

  const shared = `https://dashboard.tenderly.co/shared/simulation/${id}`;
  const reverted =
    data.simulation?.status === false ||
    data.transaction?.status === false ||
    (data.simulation?.status !== true && data.transaction?.status !== true);
  if (reverted) {
    return {
      success: false,
      url: shared,
      errorMessage:
        data.simulation?.error_message ??
        data.transaction?.error_message ??
        "reverted",
    };
  }

  return { success: true, url: shared };
}
