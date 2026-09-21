#!/usr/bin/env node
// Repository layout guard (pnpm repo:check). Fails when a versioned file
// violates the layout conventions in README.md (Repository structure):
// generated output or local-only material under version control, non-Solidity
// files in script/ outside the pinned Mission Control surfaces, or references
// to retired paths.

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const listed = execFileSync(
  "git",
  ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
  { cwd: root, encoding: "utf8" },
)
  .split("\0")
  .filter(Boolean)
  .filter((file) => fs.existsSync(path.join(root, file)));

// Directories that must never contain versioned files.
const forbiddenRoots = [
  "artifact/",
  "artifacts/",
  "audit/",
  "broadcast/",
  "dist/",
  "flattened_contracts/",
  "generated/",
  "local/",
  "script/output/",
  "scripts/",
];
const forbiddenFiles = new Set(["junk-id.json", "nestbundler.json"]);

// script/ is Solidity-only EXCEPT the surfaces shipped verbatim inside the
// published @plumenetwork/nest-solana-deploy package. Mission Control pins
// these repo-relative paths; move them only in lockstep with Mission Control.
const scriptNonSolAllowed = (file) =>
  file === "script/solana-layerzero.config.ts" ||
  file.startsWith("script/deployment-config/") ||
  file.startsWith("script/solana-lz-abi/");

// Path strings that must not reappear anywhere in versioned files.
const legacyReferences = [
  "ts-scripts/",
  "ts-node scripts/",
  "script/DeployNestOFTProtocol",
  "script/BaseL0Script",
];

const errors = [];

for (const file of listed) {
  if (
    forbiddenFiles.has(file) ||
    forbiddenRoots.some((prefix) => file.startsWith(prefix))
  ) {
    errors.push(`${file}: generated or local-only path must not be versioned`);
  }
  if (file.startsWith("ts-scripts/")) {
    errors.push(`${file}: ts-scripts/ is retired — reusable commands live in tools/`);
  }
  if (
    file.startsWith("script/") &&
    !file.endsWith(".sol") &&
    !file.endsWith(".md") &&
    !scriptNonSolAllowed(file)
  ) {
    errors.push(`${file}: script/ is reserved for Foundry Solidity`);
  }

  const fullPath = path.join(root, file);
  if (fs.statSync(fullPath).size > 2_000_000) continue;
  let content;
  try {
    content = fs.readFileSync(fullPath, "utf8");
  } catch {
    continue;
  }
  // .claude/ holds accumulated tool-permission entries, not path references.
  if (file !== "tools/check-repository-layout.mjs" && !file.startsWith(".claude/")) {
    for (const reference of legacyReferences) {
      if (content.includes(reference)) {
        errors.push(`${file}: contains legacy path "${reference}"`);
      }
    }
  }
}

for (const required of [
  "config",
  "deployments",
  "script/deployment-config",
  "script",
  "tasks",
  "tools",
]) {
  if (!fs.existsSync(path.join(root, required))) {
    errors.push(`${required}/: required repository seam is missing`);
  }
}

// Historical deployment sources are excluded from builds and formatters.
// Keep their exact bytes tied to the verified-source manifest instead.
const archivePrefix = "contracts/upgrades/deployed/";
const archiveRoot = path.join(root, archivePrefix);
const manifestPath = `${archivePrefix}sources.json`;
const archivedSources = new Set();
try {
  const manifest = JSON.parse(
    fs.readFileSync(path.join(root, manifestPath), "utf8"),
  );
  if (!Array.isArray(manifest)) throw new Error("expected an array");
  for (const entry of manifest) {
    const source = entry?.source;
    if (
      typeof source !== "string" ||
      !source.endsWith(".sol") ||
      source.includes("\\") ||
      source
        .split("/")
        .some((part) => part === "" || part === "." || part === "..")
    ) {
      errors.push(
        `${manifestPath}: invalid archived source path ${JSON.stringify(source)}`,
      );
      continue;
    }
    const file = `${archivePrefix}${source}`;
    if (archivedSources.has(file))
      errors.push(`${file}: duplicate archived source`);
    archivedSources.add(file);
    if (
      typeof entry.sourceSha256 !== "string" ||
      !/^[a-f0-9]{64}$/.test(entry.sourceSha256)
    ) {
      errors.push(`${file}: invalid sourceSha256`);
      continue;
    }
    try {
      const fullPath = path.join(archiveRoot, source);
      if (
        !fs.lstatSync(fullPath).isFile() ||
        !fs
          .realpathSync(fullPath)
          .startsWith(`${fs.realpathSync(archiveRoot)}${path.sep}`)
      ) {
        errors.push(
          `${file}: archived source must be a regular file inside ${archivePrefix}`,
        );
        continue;
      }
      const digest = createHash("sha256")
        .update(fs.readFileSync(fullPath))
        .digest("hex");
      if (digest !== entry.sourceSha256)
        errors.push(
          `${file}: SHA-256 mismatch (expected ${entry.sourceSha256}, got ${digest})`,
        );
    } catch (error) {
      errors.push(
        `${file}: cannot read archived source (${error.code ?? error.message})`,
      );
    }
  }
} catch (error) {
  errors.push(
    `${manifestPath}: invalid archive manifest (${error.code ?? error.message})`,
  );
}
for (const file of listed) {
  if (
    file.startsWith(archivePrefix) &&
    file.endsWith(".sol") &&
    !archivedSources.has(file)
  ) {
    errors.push(`${file}: missing from sources.json`);
  }
}

if (errors.length > 0) {
  console.error(errors.map((error) => `NOK ${error}`).join("\n"));
  process.exit(1);
}

console.log(`OK repository layout (${listed.length} versionable files checked)`);
console.log(
  `OK archived upgrade sources (${archivedSources.size} SHA-256 digests checked)`,
);
