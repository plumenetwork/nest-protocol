#!/usr/bin/env ts-node
/**
 * CLI wrapper over tools/splitMsigBatchesLib.ts.
 *
 * Splits the Safe Transaction Builder batches emitted by Forge for a given
 * vault-chain into 5 upload-ready parts and prints a Slack template to
 * stdout. The chainId + vault pair resolves flat forge-output paths directly;
 * no per-vault staging directory is used.
 *
 * Usage: pnpm ts-node tools/splitMsigBatches.ts <VAULT_SYMBOL> <CHAIN_ID>
 * Example: pnpm ts-node tools/splitMsigBatches.ts nALPHA 42161
 */

import * as fs from "fs";
import * as path from "path";
import {
  formatSlackTemplate,
  resolveBatchPaths,
  splitBatches,
  splitOutDir,
  type SlackSectionInput,
} from "./splitMsigBatchesLib";
import { queueUrl } from "./safeTxService";

function loadCommon(
  repoRoot: string,
  chainId: number,
): { multisig: string; name: string } {
  const file = path.join(repoRoot, "config", "common", `${chainId}.json`);
  if (!fs.existsSync(file)) {
    throw new Error(`config/common/${chainId}.json not found`);
  }
  const json = JSON.parse(fs.readFileSync(file, "utf8")) as {
    name: string;
    common: { multisig: string };
  };
  return { multisig: json.common.multisig, name: json.name };
}

function main(): void {
  const vault = process.argv[2];
  const chainIdArg = process.argv[3];
  if (!vault || !chainIdArg) {
    console.error(
      "usage: pnpm ts-node tools/splitMsigBatches.ts <VAULT_SYMBOL> <CHAIN_ID>",
    );
    process.exit(1);
  }
  const chainId = Number(chainIdArg);
  if (!Number.isFinite(chainId) || chainId <= 0) {
    console.error(`invalid chainId: ${chainIdArg}`);
    process.exit(1);
  }

  const repoRoot = path.resolve(__dirname, "..");
  const { multisig, name: chainName } = loadCommon(repoRoot, chainId);
  const { deployPath, upgradePath, ownerPath, feesPath } = resolveBatchPaths(
    repoRoot,
    chainId,
    vault,
  );

  for (const p of [deployPath, ownerPath]) {
    if (!fs.existsSync(p)) {
      console.error(`required batch file missing: ${p}`);
      process.exit(1);
    }
  }

  const outDir = splitOutDir(repoRoot, chainId, vault);
  const { sections, eidsLabel, hasUpgrade } = splitBatches({
    deployPath,
    ownerPath,
    upgradePath: fs.existsSync(upgradePath) ? upgradePath : undefined,
    feesPath: fs.existsSync(feesPath) ? feesPath : undefined,
    chainId,
    vault,
    outDir,
  });

  console.log(`\nwrote ${sections.length} batches to ${outDir}`);
  for (const s of sections) {
    console.log(`  ${s.file}  (${s.batch.transactions.length} txs)`);
  }

  // No real tx URL yet — CLI mode keeps the legacy "paste after upload" UX.
  const queueFallback = `${queueUrl(chainId, multisig)}   <paste exact tx URL after upload>`;
  const slackSections: SlackSectionInput[] = sections.map((s) => ({
    title: s.title,
    batch: s.batch,
    txUrl: queueFallback,
    slot: s.slot,
  }));

  console.log("\n========== SLACK TEMPLATE ==========\n");
  console.log(
    formatSlackTemplate({
      chainName,
      vault,
      eidsLabel,
      sections: slackSections,
      hasUpgrade,
    }),
  );
  console.log(`\n==========  END  ==========\n`);
}

main();
