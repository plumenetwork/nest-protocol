#!/usr/bin/env ts-node
/**
 * Deferred Safe-propose for recorded vault migrations.
 *
 * Consumes the manifests written by `pnpm deploy <vault> <chainId> --record-only`
 * (under script/output/migrate-queue/<vault>/<chainId>.json), and for each
 * recorded chain proposes the batches to that chain's Safe Transaction Service
 * and prints the Slack template. Tenderly simulation runs against the live nonce
 * at propose time, same as `pnpm deploy`.
 *
 * Usage: pnpm queue <VAULT_SYMBOL> [CHAIN_ID] [--dry-run] [--split | --merge] [--nonce N]
 *
 * With no CHAIN_ID, every recorded chain for the vault is proposed in ascending
 * chainId order (prompting per chain, and per slot in split mode). A declined or
 * failed chain does not block the remaining chains; the process exits non-zero
 * if any chain had skipped/failed slots.
 *
 * --dry-run  Compute hashes + simulate, but never write to the Safe service.
 * --split / --merge
 *            Override the recorded split mode for this run.
 * --nonce N  Propose at Safe nonce N instead of the service-derived next nonce,
 *            to REPLACE an already-queued tx at that slot. Requires an explicit
 *            CHAIN_ID (nonce is per-chain). In split mode the successive
 *            non-empty slots take N, N+1, ….
 */
import "dotenv/config";
import * as fs from "fs";
import * as path from "path";
import { privateKeyToAccount } from "viem/accounts";

import { getSafeOwner, isAuthorizedProposer } from "./safePropose";
import { SAFE_TX_SERVICE } from "./safeTxService";
import { runProposePhase } from "./proposePhase";
import {
  listManifests,
  manifestPath,
  readManifest,
  type QueueManifest,
} from "./migrationQueueStore";

type CommonConfig = {
  chainId: number;
  name: string;
  rpc: string;
  common: { multisig: `0x${string}` };
};

function die(msg: string): never {
  console.error(`queue: ${msg}`);
  process.exit(1);
}

function parseArgs(): {
  vault: string;
  chainId: number | undefined;
  dryRun: boolean;
  splitOverride: boolean | undefined;
  nonce: number | undefined;
} {
  const raw = process.argv.slice(2);
  const positional: string[] = [];
  const flags: string[] = [];
  let nonce: number | undefined;
  for (let i = 0; i < raw.length; i++) {
    const a = raw[i];
    if (a === "--nonce" || a.startsWith("--nonce=")) {
      const val = a.startsWith("--nonce=") ? a.slice("--nonce=".length) : raw[++i];
      if (val === undefined) die("--nonce requires a value");
      const n = Number(val);
      if (!Number.isInteger(n) || n < 0) die(`invalid --nonce: ${val}`);
      nonce = n;
      continue;
    }
    if (a.startsWith("--")) flags.push(a);
    else positional.push(a);
  }
  if (positional.length < 1 || positional.length > 2) {
    die(
      "usage: pnpm queue <VAULT_SYMBOL> [CHAIN_ID] [--dry-run] [--split | --merge] [--nonce N]",
    );
  }
  const allowedFlags = new Set(["--dry-run", "--split", "--merge"]);
  for (const flag of flags) {
    if (!allowedFlags.has(flag)) die(`unknown flag: ${flag}`);
  }
  const vault = positional[0];
  let chainId: number | undefined;
  if (positional.length === 2) {
    chainId = Number(positional[1]);
    if (!Number.isFinite(chainId) || chainId <= 0)
      die(`invalid chainId: ${positional[1]}`);
  }
  const split = flags.includes("--split");
  const merge = flags.includes("--merge");
  if (split && merge) die("--split and --merge are mutually exclusive");
  const splitOverride = split ? true : merge ? false : undefined;
  if (nonce !== undefined && chainId === undefined) {
    die("--nonce requires an explicit CHAIN_ID (nonce is per-chain)");
  }
  return {
    vault,
    chainId,
    dryRun: flags.includes("--dry-run"),
    splitOverride,
    nonce,
  };
}

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v || v.length === 0) die(`${name} is not set`);
  return v;
}

function privateKeyFromEnv(): `0x${string}` {
  const raw = requireEnv("PRIVATE_KEY").trim();
  const hex = raw.startsWith("0x") ? raw : `0x${raw}`;
  if (!/^0x[0-9a-fA-F]{64}$/.test(hex))
    die("PRIVATE_KEY is not a 32-byte hex string");
  return hex as `0x${string}`;
}

function loadCommon(repoRoot: string, chainId: number): CommonConfig {
  const file = path.join(repoRoot, "config", "common", `${chainId}.json`);
  if (!fs.existsSync(file)) die(`config/common/${chainId}.json not found`);
  return JSON.parse(fs.readFileSync(file, "utf8")) as CommonConfig;
}

async function proposeOne(
  repoRoot: string,
  m: QueueManifest,
  dryRun: boolean,
  splitOverride: boolean | undefined,
  nonceOverride: number | undefined,
): Promise<{ aborted: boolean }> {
  const common = loadCommon(repoRoot, m.chainId);
  const safe = m.safe;
  const rpcUrl = requireEnv(common.rpc);
  const signerKey = privateKeyFromEnv();
  const proposerAddress = privateKeyToAccount(signerKey).address;

  const modeTag = dryRun ? " [DRY RUN]" : "";
  console.log(
    `\nqueue ${m.vault} @ chainId=${m.chainId} (${m.chainName})${modeTag}`,
  );
  console.log(`  safe:     ${safe}`);
  console.log(`  proposer: ${proposerAddress}`);
  console.log(`  recorded: ${m.recordedAt}`);
  if (safe.toLowerCase() !== common.common.multisig.toLowerCase()) {
    console.warn(
      `  warning: recorded safe ${safe} differs from config/common/${m.chainId}.json multisig ${common.common.multisig}. Using recorded safe.`,
    );
  }

  const [auth, safeOwner] = await Promise.all([
    isAuthorizedProposer(m.chainId, safe, proposerAddress),
    getSafeOwner(m.chainId, safe, rpcUrl),
  ]);
  if (auth === false) {
    console.warn(
      `  warning: proposer ${proposerAddress} is neither an owner nor a registered delegate on this Safe. Continuing — the service may reject propose().`,
    );
  } else if (auth === null) {
    console.warn(
      `  warning: could not verify proposer authorization via Safe API. Continuing.`,
    );
  }

  const splitMode = splitOverride ?? m.splitMode;
  if (splitOverride !== undefined && splitOverride !== m.splitMode) {
    console.log(
      `  msig:     ${splitMode ? "split" : "merged"} (overriding recorded mode)`,
    );
  } else {
    console.log(`  msig:     ${splitMode ? "split" : "merged"} (recorded)`);
  }

  return runProposePhase({
    repoRoot,
    chainId: m.chainId,
    vault: m.vault,
    chainName: m.chainName,
    safe,
    rpcUrl,
    signerKey,
    safeOwner,
    sections: m.sections,
    eidsLabel: m.eidsLabel,
    hasUpgrade: m.hasUpgrade,
    splitMode,
    safeDryRun: dryRun,
    dryRunTag: dryRun ? "dry-run" : null,
    nonceOverride,
  });
}

async function main(): Promise<void> {
  const { vault, chainId, dryRun, splitOverride, nonce } = parseArgs();
  const repoRoot = path.resolve(__dirname, "..");

  const manifests =
    chainId !== undefined
      ? [
          (() => {
            const p = manifestPath(repoRoot, vault, chainId);
            if (!fs.existsSync(p))
              die(
                `no recorded manifest: ${p}\n  record it first: pnpm deploy ${vault} ${chainId} --record-only`,
              );
            return readManifest(p);
          })(),
        ]
      : listManifests(repoRoot, vault);

  if (manifests.length === 0) {
    die(
      `no recorded manifests under script/output/migrate-queue/${vault}/\n  record first: pnpm deploy ${vault} <chainId> --record-only`,
    );
  }

  for (const m of manifests) {
    if (!SAFE_TX_SERVICE[m.chainId]) {
      die(`chainId ${m.chainId} not configured in tools/safeTxService.ts`);
    }
  }

  console.log(
    `queue ${vault}: ${manifests.length} chain(s) → ${manifests.map((m) => m.chainId).join(", ")}${dryRun ? " [DRY RUN]" : ""}`,
  );

  let anyAborted = false;
  for (const m of manifests) {
    const { aborted } = await proposeOne(repoRoot, m, dryRun, splitOverride, nonce);
    if (aborted) {
      anyAborted = true;
      console.warn(
        `queue: chain ${m.chainId} had skipped/failed slots; continuing to next chain.`,
      );
    }
  }

  if (anyAborted) process.exit(1);
}

main().catch((err) => {
  console.error(err instanceof Error ? (err.stack ?? err.message) : err);
  process.exit(1);
});
