#!/usr/bin/env node
// Pin check for the shared signer-message grammar.
//
// The public grammar reference must match the verifier copy in
// plume-hub:packages/safe-verify. Both repositories pin its SHA-256; a copy that
// drifts on either side fails its own check instead of being silently reinterpreted.
//
//   node tools/check-signer-message-grammar.mjs
//
import { createHash } from "node:crypto";
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const ROOT = process.cwd();

export const GRAMMAR_VERSION = "nest-signer-message/1";
export const GRAMMAR_REFERENCE_PATH = "docs/signer-message-grammar.md";
// Must equal GRAMMAR_REFERENCE_SHA256 in plume-hub:packages/safe-verify/src/grammar/version.ts.
export const GRAMMAR_REFERENCE_SHA256 =
  "d5e4d18e0d558ece88c16bd2489a4a79c687736f1a9a3ac815f6f1088f496e55";

const faults = [];

const referencePath = join(ROOT, GRAMMAR_REFERENCE_PATH);
if (!existsSync(referencePath)) {
  faults.push(`${GRAMMAR_REFERENCE_PATH} is missing`);
} else {
  const reference = readFileSync(referencePath);
  const digest = createHash("sha256").update(reference).digest("hex");
  if (digest !== GRAMMAR_REFERENCE_SHA256) {
    faults.push(
      `${GRAMMAR_REFERENCE_PATH} sha256 is ${digest}, pinned ${GRAMMAR_REFERENCE_SHA256}\n` +
        "    the verifier copy (plume-hub:packages/safe-verify/GRAMMAR.md) must be updated to the same bytes " +
        "and both pins bumped together",
    );
  }
  const text = reference.toString("utf8");
  if (!text.includes(`Version: \`${GRAMMAR_VERSION}\``)) {
    faults.push(
      `${GRAMMAR_REFERENCE_PATH} does not declare Version: \`${GRAMMAR_VERSION}\``,
    );
  }
}

if (faults.length) {
  console.error(
    `[signer-grammar] FATAL ${faults.length} problem(s):\n` +
      faults.map((s) => `  - ${s}`).join("\n"),
  );
  process.exit(1);
}

console.log(
  `[signer-grammar] ${GRAMMAR_VERSION} pinned; ${GRAMMAR_REFERENCE_PATH} sha256 ${GRAMMAR_REFERENCE_SHA256}`,
);
