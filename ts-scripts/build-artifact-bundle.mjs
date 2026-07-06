#!/usr/bin/env node
// Build a slim artifact + config bundle for Mission Control to consume.
//
// Reads compiled Foundry artifacts from out/ plus the canonical config JSON,
// and writes dist/nest-artifacts/ — a publishable npm package (GitHub Packages).
// Mission Control fetches this per branch (dist-tags main/develop) to get real
// creation bytecode + ABIs + per-chain config + the commit it was built from.
//
// Dependency-free (Node built-ins only). Run AFTER `forge build`.
//   node ts-scripts/build-artifact-bundle.mjs
//
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from 'node:fs';
import { join, basename } from 'node:path';
import { execSync } from 'node:child_process';

const ROOT = process.cwd();
const OUT = join(ROOT, 'out');
const DIST = join(ROOT, 'dist', 'nest-artifacts');

// Contracts MC needs ABI + creation bytecode for (deploy / upgrade / wiring).
// NOTE: RolesAuthority (solmate) and TransparentUpgradeableProxy/ProxyAdmin
// (vendored OZ 4.9.3) only land in out/ when the DEPLOY SCRIPT compiles — the
// workflow must `forge build script/deploy/DeployAndSetup.s.sol` in addition
// to `forge build contracts` or they are missing from the bundle.
// (`CommonRolesAuthority` is NOT a contract — it is a second RolesAuthority
// instance — so it is deliberately absent here.)
const CONTRACTS = [
  'NestShareOFT', 'NestVaultOFT', 'NestVault', 'NestVaultCore',
  'NestHubAccountant', 'NestSpokeAccountant', 'NestAccountant',
  'NestVaultComposer', 'NestCCTPRelayer', 'NestVaultPredicateProxy',
  'NestVaultRedeemOperator', 'OperatorRegistry', 'NestUnlooper',
  'BlacklistHook', 'NestShareSeizer',
  'RolesAuthority',
  'TransparentUpgradeableProxy', 'ProxyAdmin',
  // NestVault(OFT) external linked libraries — MC deploys these and links
  // their addresses into the impl bytecode at broadcast time, exactly like a
  // forge script run. Shipped with `linkReferences` (offsets) below.
  'NestVaultCoreValidationLogic', 'NestVaultTransferLogic',
  'NestVaultAdminLogic', 'NestVaultDepositLogic',
  'NestVaultOperatorLogic', 'NestVaultRedeemLogic',
];

function findArtifact(name) {
  const direct = join(OUT, `${name}.sol`, `${name}.json`);
  if (existsSync(direct)) return direct;
  if (!existsSync(OUT)) return null;
  for (const dir of readdirSync(OUT)) {
    const p = join(OUT, dir, `${name}.json`);
    if (existsSync(p)) return p;
  }
  return null;
}

// Full solc metadata for an artifact. Foundry inlines it as an object here, but
// the format is config-dependent (older/other setups emit a JSON string), so
// handle both. Returns null when absent/unparseable — callers degrade per-field.
function parseMetadata(j) {
  try {
    return typeof j.metadata === 'string' ? JSON.parse(j.metadata) : (j.metadata ?? null);
  } catch {
    return null;
  }
}

const contracts = {};
// Parsed solc metadata per component — reused below to build verify.json (the
// explorer source-verification surface) without re-reading out/.
const metaByName = {};
const missing = [];
for (const name of CONTRACTS) {
  const p = findArtifact(name);
  if (!p) { missing.push(name); continue; }
  const j = JSON.parse(readFileSync(p, 'utf8'));
  const meta = parseMetadata(j);
  metaByName[name] = meta;
  const linkRefs = j.bytecode?.linkReferences ?? {};
  const hasUnlinkedLibs = Object.keys(linkRefs).length > 0;
  contracts[name] = {
    abi: j.abi,
    creationCode: j.bytecode?.object ?? '0x',
    runtimeCode: j.deployedBytecode?.object ?? '0x',
    methodIdentifiers: j.methodIdentifiers ?? {},
    compiler: meta?.compiler?.version,
    hasUnlinkedLibs,
    // Placeholder offsets so MC can deploy the libraries and LINK the
    // creation code at broadcast time (forge's auto-link analogue).
    ...(hasUnlinkedLibs ? { linkReferences: linkRefs } : {}),
  };
}

// A half bundle silently breaks Mission Control deploys ("artifact missing").
// Publishing one is never acceptable — fail the workflow instead.
if (missing.length) {
  console.error(
    `[bundle] FATAL missing artifacts: ${missing.join(', ')}\n` +
    '[bundle] did the workflow run `forge build contracts` AND `forge build script/deploy/DeployAndSetup.s.sol`?',
  );
  process.exit(1);
}

// Read a directory of *.json into { basenameNoExt: parsedJSON }.
function readJsonDir(rel) {
  const dir = join(ROOT, rel);
  const out = {};
  if (!existsSync(dir)) return out;
  for (const f of readdirSync(dir)) {
    if (f.endsWith('.json')) out[basename(f, '.json')] = JSON.parse(readFileSync(join(dir, f), 'utf8'));
  }
  return out;
}

const config = {
  common: readJsonDir('config/common'),
  layerzero: readJsonDir('config/layerzero'),
  cctp: readJsonDir('config/cctp'),
  assets: readJsonDir('config/assets'),
  authority: readJsonDir('config/authority'),
  // Morpho protocol singletons (config/morpho/{chainId}.json — the Deploy-new
  // ctor inputs) and the timelock/owners-multisig config. Both exist in-repo
  // (Plume 98866 has morpho; timelock covers 5 chains) but were omitted, so
  // Mission Control's package mode read `morphoBundled:false` (every chain
  // "unconfigured", the manual-Morpho card shown even for Plume) and degraded
  // the owners-multisig preset. MC consumes `config.morpho`/`config.timelock`
  // verbatim; `morphoBundled` flips true once `config.morpho` is present.
  morpho: readJsonDir('config/morpho'),
  timelock: readJsonDir('config/timelock'),
};
const vaults = readJsonDir('script/deployment-config/vaults');

// Deploy-time common maps (script/deployment-config/common{,-test}) keyed by
// chainId — the ONLY source of the per-chain Morpho periphery trio
// (nestAdapter / nestBundler / nestUnlooper) plus protocolTimelock etc. Without
// these, Mission Control's package mode shows those three as "not configured in
// nest-contracts" even though they exist on-chain (e.g. Plume 98866). MC's
// route + resolveCommonSource consume `deploymentCommon[chainId]` verbatim.
// `common-test` (F10.2) is absent today → `{}`; harmless + future-proof.
const deploymentCommon = readJsonDir('script/deployment-config/common');
const deploymentCommonTest = readJsonDir('script/deployment-config/common-test');

// Solana OFT create-task outputs (deployments/solana-mainnet) — the offline
// proof `lz:oft:solana:create` ran for a vault. Keyed by VAULT SYMBOL
// (`{SYMBOL}-OFT.json` → `SYMBOL`; the create task's generic `OFT.json` keeps
// its basename), matching the shape Mission Control's local-checkout route
// serves — MC passes the published bundle's map through verbatim.
const solanaDeployments = {};
for (const [base, dep] of Object.entries(readJsonDir('deployments/solana-mainnet'))) {
  solanaDeployments[base.endsWith('-OFT') ? base.slice(0, -'-OFT'.length) : base] = dep;
}

const sh = (c) => execSync(c).toString().trim();
const commitHash = process.env.GITHUB_SHA || sh('git rev-parse HEAD');
const branch = process.env.GITHUB_REF_NAME || sh('git rev-parse --abbrev-ref HEAD');
const builtAt = new Date().toISOString();
const shortSha = commitHash.slice(0, 7);

const bundle = { schema: 1, branch, commitHash, builtAt, contracts, config, vaults, deploymentCommon, deploymentCommonTest, solanaDeployments };

mkdirSync(DIST, { recursive: true });
writeFileSync(join(DIST, 'bundle.json'), JSON.stringify(bundle));
writeFileSync(join(DIST, 'index.js'), "module.exports = require('./bundle.json');\n");
writeFileSync(join(DIST, 'index.d.ts'), 'declare const bundle: any;\nexport = bundle;\n');

// ─── verify.json — explorer SOURCE-verification surface (F20) ────────────────
// A SEPARATE file next to bundle.json (the sync payload stays slim; MC fetches
// this lazily). MC's /api/verify rebuilds each artifact's solc standard-json
// input from THIS instead of a local checkout — the only way source
// verification can run in prod, where Vercel has no nest-contracts checkout.
// Everything comes from the artifact `metadata` parsed above plus the source
// files on disk (forge just compiled them; submodules + node_modules are
// present at the exact build commit in CI).
//
//   { schema, commitHash,
//     meta:    { [artifact]: { compilerVersion, settings, compilationTarget, sourcePaths } },
//     sources: { [path]: content } }   // deduped union across every component
//
// `settings` is the metadata solc settings verbatim (optimizer / evmVersion /
// viaIR / remappings / metadata.bytecodeHash); MC drops `compilationTarget`
// from it and injects outputSelection, exactly as buildStandardJson does today.
// `compilationTarget` is surfaced separately because MC needs every LINKED
// LIBRARY's own target to map that library's deployed address into settings.
const verifyMeta = {};
const verifySources = {};
const verifyFaults = [];
for (const name of CONTRACTS) {
  const meta = metaByName[name];
  if (!meta) { verifyFaults.push(`${name}: artifact carries no metadata`); continue; }
  const settings = meta.settings ?? {};
  const compilationTarget = settings.compilationTarget ?? {};
  const sourcePaths = Object.keys(meta.sources ?? {});
  if (!meta.compiler?.version) verifyFaults.push(`${name}: metadata has no compiler version`);
  if (Object.keys(compilationTarget).length === 0) verifyFaults.push(`${name}: metadata has no compilationTarget`);
  if (sourcePaths.length === 0) verifyFaults.push(`${name}: metadata lists no sources`);
  for (const rel of sourcePaths) {
    if (rel in verifySources) continue; // shared across components — store once
    if (rel.startsWith('/') || rel.split('/').includes('..')) {
      verifyFaults.push(`${name}: refusing source path outside the checkout "${rel}"`);
      continue;
    }
    try {
      verifySources[rel] = readFileSync(join(ROOT, rel), 'utf8');
    } catch {
      verifyFaults.push(`${name}: source "${rel}" unreadable — checked out at the build commit?`);
    }
  }
  verifyMeta[name] = { compilerVersion: meta.compiler?.version, settings, compilationTarget, sourcePaths };
}

// A half verify surface silently fails explorer verification (missing / wrong
// sources) — as unacceptable as a half artifact bundle. Fail the workflow.
if (verifyFaults.length) {
  console.error(
    `[bundle] FATAL verify.json build found ${verifyFaults.length} problem(s):\n` +
    verifyFaults.map((s) => `  - ${s}`).join('\n') +
    '\n[bundle] are the forge lib/ submodules AND node_modules present at the build commit?',
  );
  process.exit(1);
}

const verifyJson = JSON.stringify({ schema: 1, commitHash, meta: verifyMeta, sources: verifySources });
writeFileSync(join(DIST, 'verify.json'), verifyJson);
console.log(
  `[bundle] verify.json: ${Object.keys(verifyMeta).length} components, ` +
  `${Object.keys(verifySources).length} unique sources, ` +
  `${(Buffer.byteLength(verifyJson) / 1024 / 1024).toFixed(2)} MB`,
);

const safeBranch = branch.replace(/[^a-zA-Z0-9-]/g, '-');
const version = process.env.PKG_VERSION || `0.0.0-${safeBranch}.${shortSha}`;
writeFileSync(join(DIST, 'package.json'), JSON.stringify({
  name: '@plumenetwork/nest-artifacts',
  version,
  description: `Slim Nest contract artifacts + config (branch ${branch} @ ${shortSha})`,
  main: 'index.js',
  types: 'index.d.ts',
  files: ['bundle.json', 'verify.json', 'index.js', 'index.d.ts'],
  publishConfig: { registry: 'https://npm.pkg.github.com' },
  repository: { type: 'git', url: 'git+https://github.com/plumenetwork/nest-contracts.git' },
}, null, 2) + '\n');

console.log(
  `[bundle] ${Object.keys(contracts).length} contracts, ${Object.keys(vaults).length} vaults, ` +
  `commit ${shortSha}, version ${version}` +
  (missing.length ? `\n[bundle] WARNING missing artifacts (run forge build?): ${missing.join(', ')}` : ''),
);
