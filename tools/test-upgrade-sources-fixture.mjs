#!/usr/bin/env node
// Exercise the real repository gate without modifying the deployed snapshots.
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const checker = fileURLToPath(
  new URL("./check-repository-layout.mjs", import.meta.url),
);
const root = fs.mkdtempSync(path.join(tmpdir(), "nest-upgrade-sources-"));
const archive = path.join(root, "contracts/upgrades/deployed");
const source = "fixture/NestVaultComposer.sol";
const contents = "// Historical source bytes, including this newline.\n";
const entry = {
  source,
  sourceSha256: createHash("sha256").update(contents).digest("hex"),
};
const manifest = (entries) =>
  fs.writeFileSync(path.join(archive, "sources.json"), JSON.stringify(entries));
const check = (expectedError) => {
  const result = spawnSync(process.execPath, [checker], {
    cwd: root,
    encoding: "utf8",
  });
  if (expectedError) {
    assert.equal(
      result.status,
      1,
      `expected rejection, got:\n${result.stdout}${result.stderr}`,
    );
    assert.match(result.stderr, expectedError);
  } else {
    assert.equal(result.status, 0, result.stderr);
  }
};

try {
  execFileSync("git", ["init", "--quiet"], { cwd: root });
  for (const dir of [
    "config",
    "deployments",
    "script/deployment-config",
    "tasks",
    "tools",
    "contracts/upgrades/deployed/fixture",
  ]) {
    fs.mkdirSync(path.join(root, dir), { recursive: true });
  }
  fs.writeFileSync(path.join(archive, source), contents);
  manifest([entry]);
  check();

  fs.appendFileSync(path.join(archive, source), "// Accidental edit\n");
  check(/NestVaultComposer\.sol: SHA-256 mismatch/);
  fs.writeFileSync(path.join(archive, source), contents);

  manifest([{ ...entry, sourceSha256: "0".repeat(64) }]);
  check(/SHA-256 mismatch/);
  manifest([{ ...entry, sourceSha256: "invalid" }]);
  check(/invalid sourceSha256/);

  manifest([entry, { ...entry, source: "missing.sol" }]);
  check(/missing\.sol: cannot read archived source/);
  manifest([entry, { ...entry, source: "../outside.sol" }]);
  check(/invalid archived source path/);
  fs.writeFileSync(path.join(root, "outside.sol"), contents);
  fs.symlinkSync(
    path.join(root, "outside.sol"),
    path.join(archive, "escape.sol"),
  );
  manifest([entry, { ...entry, source: "escape.sol" }]);
  check(/escape\.sol: archived source must be a regular file inside/);
  fs.unlinkSync(path.join(archive, "escape.sol"));

  manifest([entry, entry]);
  check(/duplicate archived source/);
  manifest([]);
  check(/NestVaultComposer\.sol: missing from sources\.json/);
  fs.writeFileSync(path.join(archive, "sources.json"), "{");
  check(/sources\.json: invalid archive manifest/);
  manifest({});
  check(/sources\.json: invalid archive manifest/);
  fs.unlinkSync(path.join(archive, "sources.json"));
  check(/sources\.json: invalid archive manifest/);

  console.log(
    "OK upgrade-source integrity fixture (valid archive and 11 rejection cases)",
  );
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
