#!/usr/bin/env node
// Build @plumenetwork/nest-solana-deploy — the runnable Solana LayerZero task
// layer as a publishable npm package (GitHub Packages), Milestone 1 of the
// Mission Control runner-package migration.
//
// Ships SOURCE + COMMITTED STATE ONLY (no node_modules, no contracts, no
// forge/foundry, no compiled output): hardhat.config.ts, tsconfig.json, the
// entire tasks/ tree (tasks/index.ts imports every task file at config load —
// shipping a subset would fork the authored source), the Solana LayerZero
// config, committed vault configs, and committed deployment records. Task
// sources stay authored once in their current locations; this script derives
// the package at build time. Dependency-free (Node built-ins only).
//
//   node tools/build-solana-deploy-package.mjs        → dist/nest-solana-deploy/
//
// LOCATION IS PINNED. Mission Control's verification harness
// (verify-solana-package.mjs) invokes this exact repo-relative path, and its
// parity checks assume every packaged file keeps its repo-relative location
// (repo path == package path). Move it only in lockstep with a Mission
// Control change.
//
// Guarantees, enforced fail-loud (a half package silently breaks the Mission
// Control runner — never publishable):
//   - whitelist-driven copy; unexpected files/subdirs/extensions are FATAL
//   - .env* is refused everywhere, and the finished dist tree is re-scanned
//   - symlinks and special files are refused
//   - dependencies are the closure of hardhat.config.ts + tasks/** +
//     script/solana-layerzero.config.ts (see ALLOWLIST below), pinned to the
//     EXACT versions resolved in pnpm-lock.yaml — reproducible resolution
//   - the @solana/web3.js / ethers / hardhat-deploy overrides ship in all
//     three notations (npm overrides / yarn resolutions / pnpm.overrides);
//     they only take effect when the package directory is the INSTALL ROOT,
//     which is how the Mission Control runner scaffold consumes it
//   - provenance.json embeds the exact source commit, ref and build time
//
import {
  readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync,
  copyFileSync, lstatSync, rmSync,
} from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { execSync } from 'node:child_process';

const ROOT = process.cwd();
const DIST = join(ROOT, 'dist', 'nest-solana-deploy');
const PKG_NAME = '@plumenetwork/nest-solana-deploy';

const fail = (msg) => { console.error(`[solana-pkg] FATAL ${msg}`); process.exit(1); };

// ─── Runtime dependency allowlist ────────────────────────────────────────────
// The import closure of hardhat.config.ts + tasks/** + the Solana LZ config
// (traced in Mission Control's S01 closure spike). NAMES only — the authored
// ranges live in this repo's package.json and the exact pins come from
// pnpm-lock.yaml, so the package tracks the repo without re-authoring versions
// here. Adding an import to the task layer without extending this list fails
// the build below (untraced dependency = unresolvable at runtime).
const ALLOWLIST = [
  '@coral-xyz/anchor',                    // deep import …/dist/cjs/utils/bytes/bs58 (tasks/common/types.ts)
  '@layerzerolabs/devtools',
  '@layerzerolabs/devtools-evm-hardhat',
  '@layerzerolabs/devtools-solana',
  '@layerzerolabs/io-devtools',
  '@layerzerolabs/lz-definitions',
  '@layerzerolabs/lz-solana-sdk-v2',      // subpath import …/umi (tasks/common/utils.ts)
  '@layerzerolabs/lz-v2-utilities',
  '@layerzerolabs/metadata-tools',
  '@layerzerolabs/oft-v2-solana-sdk',
  '@layerzerolabs/protocol-devtools',
  '@layerzerolabs/toolbox-hardhat',
  '@layerzerolabs/ua-devtools',
  '@layerzerolabs/ua-devtools-evm',
  '@layerzerolabs/ua-devtools-evm-hardhat',
  '@layerzerolabs/ua-devtools-solana',
  '@metaplex-foundation/mpl-token-metadata',
  '@metaplex-foundation/mpl-toolbox',
  '@metaplex-foundation/umi',
  '@metaplex-foundation/umi-bundle-defaults',
  '@metaplex-foundation/umi-eddsa-web3js',
  '@metaplex-foundation/umi-web3js-adapters',
  '@nomicfoundation/hardhat-ethers',
  '@nomiclabs/hardhat-ethers',
  '@nomiclabs/hardhat-waffle',            // ethereum-waffle peer is lazy — never touched by the six tasks
  '@safe-global/safe-core-sdk-types',     // NOT imported by the task layer: @safe-global/protocol-kit@1.3.0
                                          // (transitive of @layerzerolabs/devtools-evm-hardhat) requires it at
                                          // load time without declaring it; the root repo compensates with this
                                          // direct dep, and the package manifest must carry the same compensation
                                          // or hardhat dies on MODULE_NOT_FOUND under pnpm's isolated linker (S15)
  '@solana-developers/helpers',
  '@solana/spl-token',
  '@solana/web3.js',                      // authored ~1.95.8 but overridden to ^1.98.0 repo-wide
  'bs58',
  'dotenv',
  'ethers',
  'exponential-backoff',
  'hardhat',
  'hardhat-contract-sizer',
  'hardhat-deploy',
  'hardhat-deploy-ethers',
  'ts-node',
  'typescript',
];

// The six Hardhat task invocations Mission Control whitelists (task ids
// verbatim from MC src/app/api/solana/run/route.ts). Their defining files must
// exist in the finished package or the runner is dead on arrival.
const SUPPORTED_TASKS = [
  'lz:oft:solana:create',
  'lz:oft:solana:init-config',
  'lz:oapp:wire',
  'lz:oft:solana:update-metadata',
  'lz:oft:solana:setdelegate',
  'lz:oft:solana:setadmin',
];
const REQUIRED_TASK_FILES = [
  'tasks/index.ts',
  'tasks/solana/index.ts',
  'tasks/common/wire.ts',
  'tasks/solana/createOFT.ts',
  'tasks/solana/initConfig.ts',
  'tasks/solana/updateMetadata.ts',
  'tasks/solana/setDelegate.ts',
  'tasks/solana/setAdmin.ts',
];

// ─── File whitelist ──────────────────────────────────────────────────────────
// Everything the six tasks load or read at runtime, nothing else. Deliberately
// excluded: contracts/, script/**/*.sol, script/vendor/, test/, tools/,
// programs/, and Anchor/Cargo/foundry files.
const VERBATIM_FILES = [
  'LICENSE',
  'hardhat.config.ts',                 // entry point; imports ./tasks/index
  'tsconfig.json',                     // hardhat self-registers ts-node against it
  'script/solana-layerzero.config.ts', // SOLANA_OAPP_CONFIG — also imported by tasks/evm/sendEvm.ts
];
const DIR_RULES = [
  // tasks/index.ts imports the ENTIRE tree at config load — ship all of it.
  { dir: 'tasks', ext: ['.ts'], recursive: true },
  // Per-vault LayerZero configs read via VAULT_SYMBOL (+ vault-chains/peers maps).
  { dir: 'script/deployment-config/vaults', ext: ['.json'], recursive: false },
  // Solana OFT create outputs — getSolanaDeployment reads these; also the
  // programId echo source for MC's scanCheckoutOftProgramId.
  { dir: 'deployments/solana-mainnet', ext: ['.json'], recursive: false },
  // hardhat-deploy lookup fallback records; .chainId marks the dir valid for
  // hardhat-deploy's reader.
  { dir: 'deployments/plumephoenix', ext: ['.json'], extraFiles: ['.chainId'], recursive: false },
  // ABI templates for the hardhat-deploy stubs the wire config synthesizes per
  // EVM leg (ensureEvmDeploymentStub) — without them wire fails on any vault
  // that has no committed deployment record.
  { dir: 'script/solana-lz-abi', ext: ['.json'], extraFiles: ['README.md'], recursive: false },
];
// OS junk that may appear locally — skipped silently, never packaged.
const SKIP_NAMES = new Set(['.DS_Store']);

const isEnvName = (name) => name === '.env' || name.startsWith('.env.');

// ─── Provenance (exact source sha / ref / build time) ────────────────────────
const sh = (c) => execSync(c).toString().trim();
const sha = (process.env.GITHUB_SHA || sh('git rev-parse HEAD')).toLowerCase();
const ref = process.env.GITHUB_REF_NAME || sh('git rev-parse --abbrev-ref HEAD');
const builtAt = new Date().toISOString();
const shortSha = sha.slice(0, 7);
if (!/^[0-9a-f]{40}$/.test(sha)) fail(`source commit is not a 40-hex sha: "${sha}"`);

const safeRef = ref.replace(/[^a-zA-Z0-9-]/g, '-');
const version = process.env.PKG_VERSION || `0.0.0-${safeRef}.${shortSha}`;

// ─── Dependency + override resolution (reproducible) ─────────────────────────
const rootPkg = JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf8'));
const lockText = readFileSync(join(ROOT, 'pnpm-lock.yaml'), 'utf8');

// Minimal parser for the three pnpm-lock.yaml (v9) blocks we need: `settings:`,
// `overrides:`, and the root importer's dependencies/devDependencies entries
// ({ name → { specifier, version } }). Anything unrecognized is ignored.
function parsePnpmLock(text) {
  const settings = {};
  const overrides = {};
  const importer = {};
  let section = null;
  let inRootImporter = false;
  let inDepBlock = false;
  let current = null;
  for (const raw of text.split(/\r?\n/)) {
    if (!raw.trim() || raw.trim().startsWith('#')) continue;
    const indent = raw.length - raw.trimStart().length;
    const line = raw.trim();
    if (indent === 0) {
      section = line.replace(/:.*$/, '');
      inRootImporter = false; inDepBlock = false; current = null;
      continue;
    }
    if (section === 'settings' && indent === 2) {
      const m = line.match(/^([A-Za-z]+):\s*(.+)$/);
      if (m) settings[m[1]] = m[2] === 'true' ? true : m[2] === 'false' ? false : m[2];
    } else if (section === 'overrides' && indent === 2) {
      const m = line.match(/^'?([^':]+)'?:\s*(.+)$/);
      if (m) overrides[m[1]] = m[2];
    } else if (section === 'importers') {
      if (indent === 2) { inRootImporter = line === '.:'; inDepBlock = false; current = null; continue; }
      if (!inRootImporter) continue;
      if (indent === 4) { inDepBlock = line === 'dependencies:' || line === 'devDependencies:'; current = null; continue; }
      if (!inDepBlock) continue;
      if (indent === 6 && line.endsWith(':')) {
        current = line.slice(0, -1).replace(/^'(.*)'$/, '$1');
        importer[current] = importer[current] ?? {};
      } else if (indent === 8 && current) {
        const m = line.match(/^(specifier|version):\s*(.+)$/);
        if (m) importer[current][m[1]] = m[2];
      }
    }
  }
  return { settings, overrides, importer };
}
const lock = parsePnpmLock(lockText);

// The three critical transitives-pins must agree everywhere they are declared:
// npm `overrides`, yarn `resolutions`, `pnpm.overrides`, and the lockfile's
// applied overrides. Divergence means the reference resolution is ambiguous.
const canon = (o) => JSON.stringify(Object.fromEntries(Object.entries(o ?? {}).sort()));
const authoredOverrides = rootPkg.pnpm?.overrides ?? {};
const problems = [];
if (Object.keys(authoredOverrides).length === 0) problems.push('package.json pnpm.overrides is missing/empty');
for (const [label, o] of [
  ['package.json overrides', rootPkg.overrides],
  ['package.json resolutions', rootPkg.resolutions],
  ['pnpm-lock.yaml overrides', lock.overrides],
]) {
  if (canon(o) !== canon(authoredOverrides)) {
    problems.push(`${label} disagrees with package.json pnpm.overrides: ${canon(o)} vs ${canon(authoredOverrides)}`);
  }
}

// Exact-pin every allowlisted dependency from the lockfile. The lockfile
// records the override range as the importer specifier for overridden
// packages, so expected specifier = override ?? authored range; a mismatch
// means pnpm-lock.yaml is out of sync with package.json.
const authoredRanges = {};
const dependencies = {};
for (const name of [...ALLOWLIST].sort()) {
  const authored = rootPkg.devDependencies?.[name] ?? rootPkg.dependencies?.[name];
  if (!authored) { problems.push(`"${name}" is not declared in package.json (dependencies/devDependencies)`); continue; }
  const entry = lock.importer[name];
  if (!entry?.version) { problems.push(`"${name}" has no resolved version in pnpm-lock.yaml's root importer`); continue; }
  const expectedSpecifier = authoredOverrides[name] ?? authored;
  if (entry.specifier !== expectedSpecifier) {
    problems.push(`"${name}": lockfile specifier "${entry.specifier}" != expected "${expectedSpecifier}" — is pnpm-lock.yaml out of sync?`);
  }
  const exact = entry.version.split('(')[0];
  if (!/^\d+\.\d+\.\d+(-[\w.-]+)?$/.test(exact)) {
    problems.push(`"${name}": resolved version "${exact}" is not a plain semver version (github:/link: specifiers must never ship)`);
  }
  authoredRanges[name] = authored;
  dependencies[name] = exact;
}

// The shipped override values are the EXACT versions the reference graph
// resolved (npm rejects an override that conflicts with a direct dependency
// spec, and exact values reproduce the reference resolution for every
// transitive too). The authored ranges remain the recorded invariant in
// mcRunner.requiredOverrides; each exact pin must still satisfy its authored
// caret range or the lockfile has drifted somewhere unreviewed.
const caretSatisfied = (range, exact) => {
  const r = range.match(/^\^(\d+)\.(\d+)\.(\d+)$/);
  const e = exact.match(/^(\d+)\.(\d+)\.(\d+)/);
  if (!r || !e) return false;
  const [maj, min, pat] = r.slice(1).map(Number);
  const [emaj, emin, epat] = e.slice(1).map(Number);
  if (emaj !== maj) return false;
  if (maj > 0) return emin > min || (emin === min && epat >= pat);
  if (emin !== min) return false; // ^0.y.z pins the minor
  return epat >= pat;
};
const appliedOverrides = {};
for (const [name, range] of Object.entries(authoredOverrides).sort()) {
  const exact = dependencies[name];
  if (!exact) { problems.push(`override target "${name}" is not an allowlisted direct dependency`); continue; }
  if (!caretSatisfied(range, exact)) {
    problems.push(`override "${name}": resolved ${exact} does not satisfy the authored range ${range}`);
  }
  appliedOverrides[name] = exact;
}
if (problems.length) {
  fail(`dependency/override resolution failed:\n${problems.map((p) => `  - ${p}`).join('\n')}`);
}

// ─── Assemble dist/nest-solana-deploy ────────────────────────────────────────
rmSync(DIST, { recursive: true, force: true });
mkdirSync(DIST, { recursive: true });

let fileCount = 0;
let byteCount = 0;
function copyOne(rel) {
  const src = join(ROOT, rel);
  if (!existsSync(src)) fail(`required file missing: ${rel}`);
  const st = lstatSync(src);
  if (st.isSymbolicLink()) fail(`refusing symlink: ${rel}`);
  if (!st.isFile()) fail(`refusing non-regular file: ${rel}`);
  if (isEnvName(basename(rel))) fail(`refusing to package env file: ${rel}`);
  const dst = join(DIST, rel);
  mkdirSync(dirname(dst), { recursive: true });
  copyFileSync(src, dst);
  fileCount += 1;
  byteCount += st.size;
}

for (const rel of VERBATIM_FILES) copyOne(rel);

for (const rule of DIR_RULES) {
  if (!existsSync(join(ROOT, rule.dir))) fail(`required directory missing: ${rule.dir}`);
  let copiedFromDir = 0;
  const walk = (relDir) => {
    const entries = readdirSync(join(ROOT, relDir), { withFileTypes: true })
      .sort((a, b) => a.name.localeCompare(b.name));
    for (const e of entries) {
      const rel = `${relDir}/${e.name}`;
      if (SKIP_NAMES.has(e.name)) continue;
      if (isEnvName(e.name)) fail(`refusing to package env file: ${rel}`);
      if (e.isSymbolicLink()) fail(`refusing symlink: ${rel}`);
      if (e.isDirectory()) {
        if (!rule.recursive) fail(`unexpected subdirectory in flat directory: ${rel}`);
        walk(rel);
        continue;
      }
      if (!e.isFile()) fail(`refusing non-regular file: ${rel}`);
      const allowed = rule.ext.some((x) => e.name.endsWith(x)) || (rule.extraFiles ?? []).includes(e.name);
      // Unknown file types are a conscious-review event, not a silent skip:
      // either extend the whitelist or remove the file.
      if (!allowed) fail(`unexpected file ${rel} (allowed here: ${[...rule.ext, ...(rule.extraFiles ?? [])].join(', ')})`);
      copyOne(rel);
      copiedFromDir += 1;
    }
  };
  walk(rule.dir);
  if (copiedFromDir === 0) fail(`directory produced no files: ${rule.dir}`);
}

for (const rel of REQUIRED_TASK_FILES) {
  if (!existsSync(join(DIST, rel))) fail(`whitelisted task source missing from package: ${rel}`);
}

// Base is a configured production peer. Keep its endpoint, hardhat-deploy
// directory, and Hardhat RPC network in the published package as one atomic
// capability: omitting any one of them makes Solana graph loading fail for
// every vault whose peer list includes chain 8453.
const solanaConfigText = readFileSync(join(DIST, 'script/solana-layerzero.config.ts'), 'utf8');
const hardhatConfigText = readFileSync(join(DIST, 'hardhat.config.ts'), 'utf8');
const requiredBaseIntegration = [
  {
    label: 'CHAIN_TO_EID maps Base chain 8453',
    text: solanaConfigText,
    pattern: /const CHAIN_TO_EID[^]*?\{[^}]*8453:\s*EndpointId\.BASE_V2_MAINNET,/,
  },
  {
    label: 'CHAIN_TO_NETWORK maps Base chain 8453',
    text: solanaConfigText,
    pattern: /const CHAIN_TO_NETWORK[^]*?\{[^}]*8453:\s*["']base["'],/,
  },
  {
    label: 'hardhat.config.ts defines the Base network with BASE_RPC_URL',
    text: hardhatConfigText,
    pattern: /base:\s*\{\s*eid:\s*EndpointId\.BASE_V2_MAINNET,\s*url:\s*process\.env\.BASE_RPC_URL\b/,
  },
];
for (const { label, text, pattern } of requiredBaseIntegration) {
  if (!pattern.test(text)) fail(`required Base integration missing: ${label}`);
}

// Final contamination sweep over the finished tree — belt and braces on top of
// the copy-time refusals.
const distScan = (dir) => {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) { distScan(join(dir, e.name)); continue; }
    if (isEnvName(e.name)) fail(`env file leaked into dist: ${join(dir, e.name)}`);
  }
};
distScan(DIST);

// ─── Generated files: provenance.json, package.json, README.md ───────────────
writeFileSync(join(DIST, 'provenance.json'), JSON.stringify({
  name: PKG_NAME,
  version,
  sha,
  ref,
  builtAt,
}, null, 2) + '\n');

writeFileSync(join(DIST, 'package.json'), JSON.stringify({
  name: PKG_NAME,
  version,
  description: `Runnable nest-contracts Solana LayerZero task layer (${ref} @ ${shortSha})`,
  files: [
    'hardhat.config.ts',
    'tsconfig.json',
    'tasks',
    'script',
    'deployments',
    'provenance.json',
  ],
  dependencies,
  // Force the reference resolution for the three critical transitives, pinned
  // exact (npm requires override == direct-dep spec; exact values also freeze
  // every transitive copy). These apply ONLY when this package directory is
  // the install root (a published package's overrides are ignored when it is
  // installed as a dependency) — which is exactly how the Mission Control
  // runner scaffold must consume it.
  overrides: appliedOverrides,
  resolutions: appliedOverrides,
  pnpm: { overrides: appliedOverrides },
  packageManager: rootPkg.packageManager,
  engines: rootPkg.engines,
  publishConfig: { registry: 'https://npm.pkg.github.com' },
  repository: { type: 'git', url: 'git+https://github.com/plumenetwork/nest-contracts.git' },
  mcRunner: {
    schema: 1,
    supportedTasks: SUPPORTED_TASKS,
    // The authored invariant (ranges): any future install/root manifest must
    // force at least these. `overrides` above are the exact pins applied here.
    requiredOverrides: authoredOverrides,
    // Ranges authored in nest-contracts package.json at the source commit —
    // lets offline parity gates diff pin provenance without the repo.
    authoredRanges,
    installerConstraints: {
      packageManager: rootPkg.packageManager,
      node: rootPkg.engines?.node,
      // The reference repo has no .npmrc; its resolution = pnpm defaults plus
      // these recorded lockfile settings. The runner install must match.
      lockfileSettings: lock.settings,
      note: 'install this package as the ROOT of its own tree (never under another app\'s node_modules); overrides above are inert otherwise',
    },
  },
}, null, 2) + '\n');

writeFileSync(join(DIST, 'README.md'), [
  `# ${PKG_NAME}`,
  '',
  `Runnable Solana LayerZero task layer extracted verbatim from nest-contracts`,
  `\`${ref}\` @ \`${sha}\` (built ${builtAt}). Generated by`,
  '`tools/build-solana-deploy-package.mjs` — do not edit the published tree.',
  '',
  '- Sources of truth stay in nest-contracts; this package is a build product.',
  '- `provenance.json` carries `{ sha, ref, builtAt }` for offline commit gates.',
  '- Install as the ROOT of its own tree, then run `node_modules/.bin/hardhat`',
  '  with `cwd` at the package directory. Never install under another app\'s',
  '  `node_modules` — the version overrides only apply at an install root.',
  `- Supported task surface: ${SUPPORTED_TASKS.map((t) => `\`${t}\``).join(', ')}.`,
  '',
].join('\n'));

console.log(
  `[solana-pkg] ${fileCount} files (${(byteCount / 1024).toFixed(0)} KiB) + package.json/provenance.json/README.md\n` +
  `[solana-pkg] ${Object.keys(dependencies).length} exact-pinned dependencies, overrides: ${Object.entries(appliedOverrides).map(([k, v]) => `${k}@${v}`).join(', ')}\n` +
  `[solana-pkg] ${PKG_NAME}@${version} from ${ref} @ ${shortSha}`,
);
