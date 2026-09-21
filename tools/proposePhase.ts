/**
 * Shared propose + Slack phase for vault-chain migrations.
 *
 * Given the split slot sections for one vault on one chain, this proposes each
 * non-empty slot to the chain's Safe Transaction Service (split mode) or a
 * single merged MultiSend (merge mode), simulates via Tenderly against the live
 * nonce, and prints the Slack template.
 *
 * Used by both `deploy.ts` (inline, right after deploy) and `queueMigration.ts`
 * (deferred, from a recorded manifest) so the two paths stay byte-for-byte
 * identical.
 */
import { promptToContinue } from "@layerzerolabs/io-devtools";

import {
  buildAddressLabels,
  formatSlackTemplate,
  prettyFn,
  type SafeTx,
  type SlackSectionInput,
  type SplitSection,
} from "./splitMsigBatchesLib";
import { proposeBatch } from "./safePropose";
import { serviceFor } from "./safeTxService";
import { simulateSafeExec, type SafeSimResult } from "./tenderlySafeSim";

export type ProposePhaseInput = {
  repoRoot: string;
  chainId: number;
  vault: string;
  chainName: string;
  safe: `0x${string}`;
  rpcUrl: string;
  signerKey: `0x${string}`;
  /** Safe owner used to impersonate in the Tenderly sim; null skips sim. */
  safeOwner: `0x${string}` | null;
  sections: SplitSection[];
  eidsLabel: string;
  hasUpgrade: boolean;
  splitMode: boolean;
  /** When true, compute hashes + sim but never write to the Safe service. */
  safeDryRun: boolean;
  /** Label for dry-run/fork messaging; defaults to "dry-run" when safeDryRun. */
  dryRunTag: "dry-run" | "fork" | null;
  /**
   * Force the base Safe nonce instead of the service-derived next nonce, to
   * REPLACE already-queued txs. Merged mode uses this nonce directly; split
   * mode assigns base + i to each successive non-empty slot.
   */
  nonceOverride?: number;
};

function summarizeSelectors(
  txs: SafeTx[],
): Map<string, { count: number; to: Set<string> }> {
  const m = new Map<string, { count: number; to: Set<string> }>();
  for (const tx of txs) {
    const name = prettyFn(tx.data);
    if (!m.has(name)) m.set(name, { count: 0, to: new Set() });
    const entry = m.get(name)!;
    entry.count += 1;
    entry.to.add(tx.to);
  }
  return m;
}

function shortAddr(a: string): string {
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

/**
 * Prints the per-slot selector breakdown of what would be proposed, without
 * proposing or touching the network. Used by `deploy --record-only` so the
 * recorded batches are reviewable up front; the live propose flow prints the
 * richer per-slot summary (with nonce/hash) via `printBatchSummary`.
 */
export function printQueuedSummary(sections: SplitSection[]): void {
  const nonEmpty = sections.filter((s) => s.batch.transactions.length > 0);
  const total = nonEmpty.reduce((n, s) => n + s.batch.transactions.length, 0);
  const line = "─".repeat(62);
  console.log(`\n${line}`);
  console.log(`Queued to propose — ${nonEmpty.length} slot(s), ${total} txs`);
  console.log(line);
  for (const s of sections) {
    const count = s.batch.transactions.length;
    if (count === 0) {
      console.log(`  [${s.slot}] ${s.title} — empty`);
      continue;
    }
    console.log(`  [${s.slot}] ${s.title} — ${count} txs`);
    const summary = summarizeSelectors(s.batch.transactions);
    const nameWidth = Math.max(
      ...Array.from(summary.keys()).map((n) => n.length),
      4,
    );
    for (const [name, { count: c, to }] of summary) {
      const toList = [...to].map(shortAddr).join(", ");
      console.log(
        `      ${name.padEnd(nameWidth)}  × ${String(c).padStart(3)}  →  ${toList}`,
      );
    }
  }
  console.log(line);
}

function printBatchSummary(
  section: SplitSection,
  safe: string,
  slug: string,
  nonce: number,
  safeTxHash: string,
  safeVersion: string,
  multiSendAddress: string,
): void {
  const line = "─".repeat(62);
  console.log(`\n${line}`);
  console.log(`${section.title} — ${section.batch.transactions.length} txs`);
  console.log(line);
  const summary = summarizeSelectors(section.batch.transactions);
  const nameWidth = Math.max(
    ...Array.from(summary.keys()).map((n) => n.length),
    4,
  );
  for (const [name, { count, to }] of summary) {
    const toList = [...to].map(shortAddr).join(", ");
    console.log(
      `  ${name.padEnd(nameWidth)}  × ${String(count).padStart(3)}  →  ${toList}`,
    );
  }
  console.log(`Safe:           ${slug}:${safe}`);
  console.log(`Safe version:   ${safeVersion}`);
  console.log(`MultiSend:      ${multiSendAddress}`);
  console.log(`Service nonce:  ${nonce}`);
  console.log(`safeTxHash:     ${safeTxHash}`);
}

export async function runProposePhase(
  input: ProposePhaseInput,
): Promise<{ aborted: boolean }> {
  const {
    repoRoot,
    chainId,
    vault,
    chainName,
    safe,
    rpcUrl,
    signerKey,
    safeOwner,
    sections,
    eidsLabel,
    hasUpgrade,
    splitMode,
    safeDryRun,
    nonceOverride,
  } = input;
  const tag = input.dryRunTag ?? "dry-run";
  const { slug } = serviceFor(chainId);

  type Outcome = {
    section: SplitSection;
    txUrl: string;
    status: "proposed" | "skipped" | "empty";
    simUrl?: string;
  };
  const outcomes: Outcome[] = [];
  let aborted = false;

  async function simAndLog(
    txs: SafeTx[],
    nonce: number,
    multiSendAddress: `0x${string}`,
  ): Promise<SafeSimResult | null> {
    if (txs.length === 0) return null;
    if (!safeOwner) {
      console.log(
        `  tenderly: skipped (could not fetch a Safe owner for impersonation)`,
      );
      return null;
    }
    const sim = await simulateSafeExec({
      chainId,
      safe,
      multiSendAddress,
      txs,
      ownerAddress: safeOwner,
      safeNonce: nonce,
    });
    if (sim === null) {
      console.log(
        `  tenderly: skipped (TENDERLY_ACCESS_KEY / TENDERLY_ACCOUNT / TENDERLY_PROJECT not set)`,
      );
      return null;
    }
    if (sim.success) {
      console.log(`  tenderly: OK — ${sim.url}`);
    } else {
      console.error(`  tenderly: FAILED — ${sim.errorMessage ?? "unknown"}`);
      if (sim.url) console.error(`    ${sim.url}`);
    }
    return sim;
  }

  if (splitMode) {
    // 5-slot flow: one propose per non-empty slot (Plume / Den).
    if (nonceOverride !== undefined) {
      console.log(
        `  nonce override: split mode assigns ${nonceOverride}, ${nonceOverride + 1}, … to each successive non-empty slot.`,
      );
    }
    let nonEmptyIdx = 0;
    for (const section of sections) {
      if (aborted) {
        outcomes.push({ section, txUrl: "<skipped>", status: "skipped" });
        continue;
      }
      if (section.batch.transactions.length === 0) {
        console.log(`\n${section.title} — empty, nothing to propose`);
        outcomes.push({ section, txUrl: "<empty>", status: "empty" });
        continue;
      }

      const slotNonce =
        nonceOverride !== undefined ? nonceOverride + nonEmptyIdx : undefined;
      nonEmptyIdx += 1;

      const result = await proposeBatch({
        chainId,
        safe,
        txs: section.batch.transactions,
        signerKey,
        rpcUrl,
        dryRun: true,
        nonce: slotNonce,
      });

      printBatchSummary(
        section,
        safe,
        slug,
        result.nonce,
        result.safeTxHash,
        result.safeVersion,
        result.multiSendAddress,
      );
      const sim = await simAndLog(
        section.batch.transactions,
        result.nonce,
        result.multiSendAddress,
      );
      const simUrl = sim?.url;

      if (safeDryRun) {
        console.log(
          `(${tag}) would propose — hash is advisory and may drift if a new pending tx lands before the real run.`,
        );
        outcomes.push({
          section,
          txUrl: `<${tag}> ${result.uiUrl}`,
          status: "proposed",
          simUrl,
        });
        continue;
      }

      const go = await promptToContinue(
        `Propose batch ${section.slot}?`,
        false,
      );
      if (!go) {
        console.log(
          `skipped ${section.slot}; aborting remaining batches to preserve nonce ordering.`,
        );
        outcomes.push({
          section,
          txUrl: "<skipped>",
          status: "skipped",
          simUrl,
        });
        aborted = true;
        continue;
      }

      try {
        const proposed = await proposeBatch({
          chainId,
          safe,
          txs: section.batch.transactions,
          signerKey,
          rpcUrl,
          dryRun: false,
          nonce: slotNonce,
        });
        console.log(`proposed ${section.slot}: ${proposed.uiUrl}`);
        outcomes.push({
          section,
          txUrl: proposed.uiUrl,
          status: "proposed",
          simUrl,
        });
      } catch (err) {
        console.error(
          `proposeTransaction failed for ${section.slot}: ${err instanceof Error ? err.message : String(err)}`,
        );
        console.error(
          `aborting remaining batches (no nonce consumed for this slot).`,
        );
        outcomes.push({
          section,
          txUrl: "<failed>",
          status: "skipped",
          simUrl,
        });
        aborted = true;
      }
    }
  } else {
    // Merged flow: concat all non-empty slots into one MultiSend, one nonce,
    // one prompt. Ordering inside MultiSend matches 1a→1b→2a→2b→3 so
    // dependency chain (roleCaps before userRoles, upgradeAndCall before
    // post-upgrade config, etc.) is preserved atomically.
    const nonEmpty = sections.filter((s) => s.batch.transactions.length > 0);
    const empty = sections.filter((s) => s.batch.transactions.length === 0);
    for (const section of empty) {
      console.log(`\n${section.title} — empty, skipped`);
      outcomes.push({ section, txUrl: "<empty>", status: "empty" });
    }

    if (nonEmpty.length === 0) {
      console.log(`\nall slots empty — nothing to propose`);
    } else {
      const mergedTxs: SafeTx[] = nonEmpty.flatMap((s) => s.batch.transactions);
      const mergedTitle = `Full migration (${vault} on ${chainName}) — ${nonEmpty.map((s) => s.slot).join(" + ")}`;

      const dry = await proposeBatch({
        chainId,
        safe,
        txs: mergedTxs,
        signerKey,
        rpcUrl,
        dryRun: true,
        nonce: nonceOverride,
      });

      const line = "─".repeat(62);
      console.log(
        `\n${line}\n${mergedTitle} — ${mergedTxs.length} txs\n${line}`,
      );
      for (const section of nonEmpty) {
        console.log(
          `  [${section.slot}] ${section.batch.transactions.length} txs`,
        );
      }
      console.log(`Safe:           ${slug}:${safe}`);
      console.log(`Safe version:   ${dry.safeVersion}`);
      console.log(`MultiSend:      ${dry.multiSendAddress}`);
      console.log(`Service nonce:  ${dry.nonce}`);
      console.log(`safeTxHash:     ${dry.safeTxHash}`);

      // Single sim of the merged batch as a Safe.execTransaction call —
      // delegatecalls MultiSend in the Safe's own context, so msg.sender of
      // every inner call = Safe (matches real execution). One shared URL
      // shows the full call tree and is reused for every slot in Slack.
      const mergedSim = await simAndLog(
        mergedTxs,
        dry.nonce,
        dry.multiSendAddress,
      );
      const mergedSimUrl = mergedSim?.url;

      let txUrl: string;
      if (safeDryRun) {
        console.log(
          `(${tag}) would propose merged batch — hash is advisory and may drift before real run.`,
        );
        txUrl = `<${tag}> ${dry.uiUrl}`;
      } else {
        const go = await promptToContinue(
          `Propose merged migration (${nonEmpty.length} slots, 1 tx)?`,
          false,
        );
        if (!go) {
          console.log(`skipped merged migration.`);
          txUrl = "<skipped>";
          aborted = true;
        } else {
          try {
            const proposed = await proposeBatch({
              chainId,
              safe,
              txs: mergedTxs,
              signerKey,
              rpcUrl,
              dryRun: false,
              nonce: nonceOverride,
            });
            console.log(`proposed merged migration: ${proposed.uiUrl}`);
            txUrl = proposed.uiUrl;
          } catch (err) {
            console.error(
              `proposeTransaction failed: ${err instanceof Error ? err.message : String(err)}`,
            );
            txUrl = "<failed>";
            aborted = true;
          }
        }
      }

      // All non-empty slots share the merged tx URL and the single sim URL;
      // empties keep "<empty>".
      for (const section of nonEmpty) {
        outcomes.push({
          section,
          txUrl,
          status: txUrl.startsWith("<") ? "skipped" : "proposed",
          simUrl: mergedSimUrl,
        });
      }
    }
  }

  // Re-sort outcomes into canonical slot order for the Slack template.
  const slotOrder: Record<string, number> = {
    "1a": 0,
    "1b": 1,
    "2a": 2,
    "2b": 3,
    "3": 4,
    "4": 5,
  };
  outcomes.sort(
    (a, b) => slotOrder[a.section.slot] - slotOrder[b.section.slot],
  );

  const slackSections: SlackSectionInput[] = outcomes.map((o) => ({
    title: o.section.title,
    batch: o.section.batch,
    txUrl: o.txUrl,
    simUrl: o.simUrl,
    slot: o.section.slot,
  }));

  const labels = buildAddressLabels(repoRoot, chainId, vault);
  console.log("\n========== SLACK TEMPLATE ==========\n");
  console.log(
    formatSlackTemplate({
      chainName,
      vault,
      eidsLabel,
      sections: slackSections,
      hasUpgrade,
      merged: !splitMode,
      labels,
    }),
  );
  console.log(`\n==========  END  ==========\n`);

  return { aborted };
}
