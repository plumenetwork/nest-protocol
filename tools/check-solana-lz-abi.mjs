#!/usr/bin/env node
// Drift guard for script/solana-lz-abi/ (pnpm lz-abi:check / lz-abi:write).
//
// The committed ABI templates duplicate forge build output by necessity: the
// published @plumenetwork/nest-solana-deploy package and Mission Control's
// offline verification harness consume them where no forge toolchain exists,
// so they cannot read out/ at runtime. This check makes the duplication safe —
// CI regenerates the templates from out/ after forge build and fails on drift.
//
//   node tools/check-solana-lz-abi.mjs          → diff committed vs out/, exit 1 on drift
//   node tools/check-solana-lz-abi.mjs --write  → regenerate the committed templates

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const ROOT = process.cwd();
const TEMPLATES = ["NestShareOFT", "NestVaultOFT"];
const write = process.argv.includes("--write");

let drift = false;
for (const name of TEMPLATES) {
  const artifact = join(ROOT, "out", `${name}.sol`, `${name}.json`);
  if (!existsSync(artifact)) {
    console.error(`NOK ${artifact} missing — run \`forge build\` first`);
    process.exit(1);
  }
  const rendered =
    JSON.stringify(JSON.parse(readFileSync(artifact, "utf8")).abi, null, 2) + "\n";
  const committedPath = join(ROOT, "script", "solana-lz-abi", `${name}.json`);
  if (write) {
    writeFileSync(committedPath, rendered);
    console.log(`OK wrote ${committedPath}`);
    continue;
  }
  const committed = existsSync(committedPath) ? readFileSync(committedPath, "utf8") : "";
  if (committed !== rendered) {
    console.error(
      `NOK script/solana-lz-abi/${name}.json drifted from forge output — run \`pnpm lz-abi:write\``,
    );
    drift = true;
  }
}

if (drift) process.exit(1);
if (!write) console.log("OK script/solana-lz-abi matches forge build output");
