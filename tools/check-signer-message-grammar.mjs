#!/usr/bin/env node
// Pin check for the shared signer-message grammar.
//
// The generator (.agents signer-slack-msg skill) and the verifier
// (plume-hub:packages/safe-verify) must agree on exactly one grammar. Both
// repositories carry a byte-identical copy of docs/signer-message-grammar.md and
// pin its SHA-256; a copy that drifts on either side fails its own check instead
// of being silently reinterpreted.
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

const SKILL_PATH = ".agents/skills/signer-slack-msg/SKILL.md";
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

const skillPath = join(ROOT, SKILL_PATH);
if (!existsSync(skillPath)) {
  faults.push(`${SKILL_PATH} is missing`);
} else {
  const text = readFileSync(skillPath, "utf8");
  if (!text.includes(GRAMMAR_VERSION))
    faults.push(`${SKILL_PATH} does not pin ${GRAMMAR_VERSION}`);
  if (!text.includes("grammar: " + GRAMMAR_VERSION))
    faults.push(`${SKILL_PATH} does not show the grammar pragma`);
  if (!text.includes("op=call value=0"))
    faults.push(
      `${SKILL_PATH} does not require explicit op=/value= on every call`,
    );

  // Every example call line is itself an instruction: an incomplete one teaches the generator to
  // emit a message the canonical parser rejects. Each is checked for the mandatory modifiers.
  const lines = text.split("\n");
  lines.forEach((line, position) => {
    const call = /^\s*(?:\[\d+\]|└─?|↳|\\_)\s*(.+)$/.exec(line);
    if (!call) return;
    const body = call[1].replace(/\s+#.*$/, "");
    const where = `${SKILL_PATH}:${position + 1}`;
    // `[1] …` is an elision inside the shape template, not a declared call. Only a bare ellipsis
    // qualifies; anything else must be a complete call line, arrow included.
    if (/^(?:…|\.{3})$/.test(body.trim())) return;
    if (!body.includes("->")) {
      faults.push(`${where} example call line declares no -> <target>`);
      return;
    }
    if (!/\bop=(call|delegatecall)\b/.test(body))
      faults.push(`${where} example call line declares no op=`);
    if (!/\bvalue=\S+/.test(body))
      faults.push(`${where} example call line declares no value=`);

    const isUnknown = /\bUNKNOWN\s+0x[0-9a-fA-F]{8}\b/.test(body);
    const isNativeTransfer = /\bnativeTransfer\(\s*\)/.test(body);
    const hasSignature = /\bsig=\S/.test(body);
    if (!isUnknown && !isNativeTransfer && !hasSignature) {
      faults.push(
        `${where} example call line declares no sig=<name(type,type)>`,
      );
    }
    if ((isUnknown || isNativeTransfer) && hasSignature) {
      faults.push(
        `${where} example call line declares sig= on a call that pins no signature`,
      );
    }
  });

  // A parenthesised role gloss is opaque to the verifier; the documented form is `15/SEIZER`.
  if (/\brole=\d+\s*\(/.test(text))
    faults.push(
      `${SKILL_PATH} shows the opaque \`role=<n> (name)\` form instead of <n>/<NAME>`,
    );
}

if (faults.length) {
  console.error(
    `[signer-grammar] FATAL ${faults.length} problem(s):\n` +
      faults.map((s) => `  - ${s}`).join("\n"),
  );
  process.exit(1);
}

console.log(
  `[signer-grammar] ${GRAMMAR_VERSION} pinned; ${GRAMMAR_REFERENCE_PATH} sha256 ${GRAMMAR_REFERENCE_SHA256}; generator skill agrees`,
);
