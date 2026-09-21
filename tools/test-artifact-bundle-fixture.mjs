#!/usr/bin/env node
// S09 build fixture for build-artifact-bundle.mjs — proves the published
// bundle's `solanaDeployments` surface without forge or a network:
//
//   1. `{SYMBOL}-OFT.json` files land SYMBOL-keyed (`nELIXIR-OFT.json` → `nELIXIR`),
//   2. the create task's generic `OFT.json` keeps its basename (`OFT`),
//   3. deployment payloads pass through verbatim (Mission Control consumes the
//      map exactly as its local-checkout route serves it),
//   4. a malformed deployment file fails the build loudly, naming the file —
//      never a silently half-published bundle,
//   5. the required signer-message grammar is copied with matching metadata.
//
// Runs the REAL builder in a throwaway root. The builder's required-artifact
// list is discovered from its own "FATAL missing artifacts" output (never
// duplicated here), then satisfied with minimal fake forge artifacts that also
// carry enough solc metadata for the verify.json surface.
//
//   node tools/test-artifact-bundle-fixture.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const BUILDER = fileURLToPath(new URL('./build-artifact-bundle.mjs', import.meta.url));
const ROOT = mkdtempSync(join(tmpdir(), 'nest-bundle-fixture-'));
const GRAMMAR_TEXT = '# fixture signer-message grammar\n';

const runBuilder = () =>
  spawnSync(process.execPath, [BUILDER], {
    cwd: ROOT,
    encoding: 'utf8',
    env: {
      ...process.env,
      GITHUB_SHA: 'f'.repeat(40),
      GITHUB_REF_NAME: 'develop',
      PKG_VERSION: '0.0.0-fixture.1',
    },
  });

/** Minimal forge artifact satisfying both the bundle and verify.json builds. */
function writeArtifact(name, sourcePath = name === 'NestVaultComposer'
  ? 'contracts/integrations/ovault/NestVaultComposer.sol'
  : 'src/Fixture.sol') {
  const dir = join(ROOT, 'out', `${name}.sol`);
  mkdirSync(dir, { recursive: true });
  mkdirSync(dirname(join(ROOT, sourcePath)), { recursive: true });
  writeFileSync(join(ROOT, sourcePath), '// fixture source\n');
  writeFileSync(
    join(dir, `${name}.json`),
    JSON.stringify({
      abi: [],
      bytecode: { object: '0x60', linkReferences: {} },
      deployedBytecode: { object: '0x60' },
      methodIdentifiers: {},
      metadata: {
        compiler: { version: '0.8.25+commit.b61c2a91' },
        settings: { compilationTarget: { [sourcePath]: name }, optimizer: { enabled: true, runs: 200 } },
        sources: { [sourcePath]: { keccak256: '0x00' } },
      },
    }),
  );
}

const solDep = (mint) => ({
  programId: 'ChEfPd3RzLeYiRwp1K9evimmaFSd6DV1S4Mv5q5Aj1th',
  mint,
  mintAuthority: `${mint}-authority`,
  escrow: `${mint}-escrow`,
  oftStore: `${mint}-store`,
});

try {
  writeFileSync(join(ROOT, 'license.md'), readFileSync(new URL('../license.md', import.meta.url)));
  // ── fixture root: shared verify source + grammar + Solana deployments ─────
  mkdirSync(join(ROOT, 'src'), { recursive: true });
  writeFileSync(join(ROOT, 'src', 'Fixture.sol'), '// fixture source\n');
  mkdirSync(join(ROOT, 'docs'), { recursive: true });
  writeFileSync(join(ROOT, 'docs', 'signer-message-grammar.md'), GRAMMAR_TEXT);
  const depDir = join(ROOT, 'deployments', 'solana-mainnet');
  mkdirSync(depDir, { recursive: true });
  writeFileSync(join(depDir, 'nELIXIR-OFT.json'), JSON.stringify(solDep('MintElixir')));
  writeFileSync(join(depDir, 'nBASIS-OFT.json'), JSON.stringify(solDep('MintBasis')));
  writeFileSync(join(depDir, 'OFT.json'), JSON.stringify(solDep('MintGeneric')));
  writeFileSync(join(depDir, 'README.md'), 'not json — must be ignored\n');

  // ── discover + satisfy the builder's required artifact list ────────────────
  let run = runBuilder();
  for (let i = 0; run.status !== 0 && i < 3; i++) {
    const missing = run.stderr.match(/FATAL missing artifacts: ([^\n]+)/)?.[1];
    assert.ok(missing, `expected a missing-artifacts report, got:\n${run.stderr || run.stdout}`);
    for (const name of missing.split(',').map((s) => s.trim()).filter(Boolean)) writeArtifact(name);
    run = runBuilder();
  }
  assert.equal(run.status, 0, `builder failed:\n${run.stderr || run.stdout}`);

  // ── the published surface ──────────────────────────────────────────────────
  const bundle = JSON.parse(readFileSync(join(ROOT, 'dist', 'nest-artifacts', 'bundle.json'), 'utf8'));
  assert.deepEqual(
    bundle.solanaDeployments,
    { nELIXIR: solDep('MintElixir'), nBASIS: solDep('MintBasis'), OFT: solDep('MintGeneric') },
    'solanaDeployments must be SYMBOL-keyed with the generic OFT preserved, payloads verbatim',
  );
  assert.equal('nELIXIR-OFT' in bundle.solanaDeployments, false, 'file-keyed entry leaked into the bundle');
  assert.equal(bundle.commitHash, 'f'.repeat(40));
  assert.deepEqual(bundle.signerMessageGrammar, {
    version: 'nest-signer-message/1',
    file: 'signer-message-grammar.md',
    sourcePath: 'docs/signer-message-grammar.md',
    sha256: createHash('sha256').update(GRAMMAR_TEXT).digest('hex'),
    commitHash: 'f'.repeat(40),
  });
  assert.equal(
    readFileSync(join(ROOT, 'dist', 'nest-artifacts', 'signer-message-grammar.md'), 'utf8'),
    GRAMMAR_TEXT,
    'published grammar must match the required source bytes',
  );

  // A same-named migration artifact must never replace the default composer.
  writeArtifact('NestVaultComposer', 'contracts/upgrades/compliance-proxy/NestVaultComposer.sol');
  const migration = runBuilder();
  assert.equal(migration.status, 1);
  assert.match(migration.stderr, /NestVaultComposer artifact is not the default deployment implementation/);
  writeArtifact('NestVaultComposer');

  // ── malformed deployment file → loud, named failure ────────────────────────
  writeFileSync(join(depDir, 'BAD-OFT.json'), '{nope');
  const bad = runBuilder();
  assert.notEqual(bad.status, 0, 'a malformed deployment file must fail the build');
  assert.match(
    bad.stderr,
    /malformed JSON in deployments\/solana-mainnet\/BAD-OFT\.json/,
    `failure must name the malformed file, got:\n${bad.stderr}`,
  );

  console.log('[fixture] PASS build-artifact-bundle solanaDeployments surface');
} finally {
  rmSync(ROOT, { recursive: true, force: true });
}
