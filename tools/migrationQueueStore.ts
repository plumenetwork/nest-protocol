/**
 * Storage for deferred-propose migration batches.
 *
 * `pnpm deploy <vault> <chainId> --record-only` runs the forge deploy and
 * writes one manifest per chain under script/output/migrate-queue/<vault>/.
 * `pnpm queue <vault> [chainId]` later reads them back, proposes to each
 * chain's Safe, and prints the Slack template.
 *
 * The manifest is self-contained for the propose+Slack phase: it carries the
 * split slot batches plus the metadata (splitMode, eidsLabel, hasUpgrade) that
 * is otherwise computed from the raw forge output. Safe address, RPC, signer,
 * and address labels are re-derived at queue time from the repo + env.
 */
import * as fs from "fs";
import * as path from "path";

import type { SplitSection } from "./splitMsigBatchesLib";

export type QueueManifest = {
  version: 1;
  vault: string;
  chainId: number;
  chainName: string;
  safe: `0x${string}`;
  /** Effective split mode at record time (chain default or --split/--merge override). */
  splitMode: boolean;
  eidsLabel: string;
  hasUpgrade: boolean;
  /** ISO-8601 timestamp of the recording run. */
  recordedAt: string;
  sections: SplitSection[];
};

export function queueDir(repoRoot: string, vault: string): string {
  return path.join(repoRoot, "script", "output", "migrate-queue", vault);
}

export function manifestPath(
  repoRoot: string,
  vault: string,
  chainId: number,
): string {
  return path.join(queueDir(repoRoot, vault), `${chainId}.json`);
}

export function writeManifest(repoRoot: string, m: QueueManifest): string {
  const dir = queueDir(repoRoot, m.vault);
  fs.mkdirSync(dir, { recursive: true });
  const file = manifestPath(repoRoot, m.vault, m.chainId);
  fs.writeFileSync(file, `${JSON.stringify(m, null, 2)}\n`);
  return file;
}

export function readManifest(file: string): QueueManifest {
  const m = JSON.parse(fs.readFileSync(file, "utf8")) as QueueManifest;
  if (m.version !== 1) {
    throw new Error(
      `unsupported manifest version in ${file}: ${(m as { version?: unknown }).version}`,
    );
  }
  return m;
}

/** All recorded manifests for a vault, sorted by chainId ascending. */
export function listManifests(
  repoRoot: string,
  vault: string,
): QueueManifest[] {
  const dir = queueDir(repoRoot, vault);
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".json"))
    .map((f) => readManifest(path.join(dir, f)))
    .sort((a, b) => a.chainId - b.chainId);
}
