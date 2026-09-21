#!/usr/bin/env ts-node
/**
 * Vault-chain deployment orchestrator.
 *
 * Runs the standard forge scripts (DeployAndSetup, Upgrade, TransferOwnership,
 * SetupFees), splits the resulting Safe Transaction Builder batches into the
 * ordered slots (1a, 1b, 2a, 2b, 3, 4), and for each non-empty slot prompts the
 * user to review and propose the batch to the chain's Safe Transaction Service
 * using the proposer EOA from PRIVATE_KEY.
 *
 * Usage: pnpm deploy <VAULT_SYMBOL> <CHAIN_ID> [--dry-run | --fork] [--run-upgrade | --skip-upgrade] [--split | --merge]
 *
 * --dry-run  forge runs without --broadcast / --verify; no Safe API writes.
 *            Useful when on-chain state already has the proxies the downstream
 *            scripts read.
 * --fork     forge broadcasts to whatever RPC is configured (point it at an
 *            anvil fork in .env); Safe propose is dry. Lets the full forge-script
 *            chain run against fork state, including fresh-chain deploys.
 * --run-upgrade
 *            Also run Upgrade.s.sol for an already-deployed chain. This is
 *            opt-in; code at share/vault addresses is not enough to imply an
 *            upgrade should happen.
 * --skip-upgrade
 *            Explicitly skip Upgrade.s.sol. This is the default and is useful
 *            when resuming after deploy succeeded but verification/propose failed.
 * --split    Force one Safe propose per non-empty slot (one nonce each).
 *            Overrides the chain's default in tools/safeTxService.ts.
 * --merge    Force a single MultiSend Safe propose for all non-empty slots
 *            (1 nonce, atomic). Overrides the chain's default.
 * --record-only
 *            Run the forge deploy + split as usual, then record the batches to
 *            script/output/migrate-queue/<vault>/<chainId>.json instead of
 *            proposing. Propose them later with `pnpm queue <vault> [chainId]`.
 */

import "dotenv/config";
import { spawn } from "child_process";
import * as fs from "fs";
import * as path from "path";
import { privateKeyToAccount } from "viem/accounts";

import {
  resolveBatchPaths,
  splitBatches,
  splitOutDir,
} from "./splitMsigBatchesLib";
import { getSafeOwner, isAuthorizedProposer } from "./safePropose";
import { SAFE_TX_SERVICE, serviceFor } from "./safeTxService";
import { runProposePhase, printQueuedSummary } from "./proposePhase";
import { writeManifest } from "./migrationQueueStore";

type CommonConfig = {
  chainId: number;
  name: string;
  rpc: string;
  common: { multisig: `0x${string}` };
};

function die(msg: string): never {
  console.error(`deploy: ${msg}`);
  process.exit(1);
}

function parseArgs(): {
  vault: string;
  chainId: number;
  dryRun: boolean;
  fork: boolean;
  runUpgrade: boolean;
  skipUpgrade: boolean;
  splitOverride: boolean | undefined;
  recordOnly: boolean;
} {
  const args = process.argv.slice(2);
  const flags = args.filter((a) => a.startsWith("--"));
  const positional = args.filter((a) => !a.startsWith("--"));
  if (positional.length !== 2) {
    die(
      "usage: pnpm deploy <VAULT_SYMBOL> <CHAIN_ID> [--dry-run | --fork] [--run-upgrade | --skip-upgrade] [--split | --merge] [--record-only]",
    );
  }
  const allowedFlags = new Set([
    "--dry-run",
    "--fork",
    "--run-upgrade",
    "--skip-upgrade",
    "--split",
    "--merge",
    "--record-only",
  ]);
  for (const flag of flags) {
    if (!allowedFlags.has(flag)) die(`unknown flag: ${flag}`);
  }
  const vault = positional[0];
  const chainId = Number(positional[1]);
  if (!Number.isFinite(chainId) || chainId <= 0)
    die(`invalid chainId: ${positional[1]}`);
  const dryRun = flags.includes("--dry-run");
  const fork = flags.includes("--fork");
  const runUpgrade = flags.includes("--run-upgrade");
  const skipUpgrade = flags.includes("--skip-upgrade");
  const split = flags.includes("--split");
  const merge = flags.includes("--merge");
  const recordOnly = flags.includes("--record-only");
  if (dryRun && fork) die("--dry-run and --fork are mutually exclusive");
  if (runUpgrade && skipUpgrade)
    die("--run-upgrade and --skip-upgrade are mutually exclusive");
  if (split && merge) die("--split and --merge are mutually exclusive");
  const splitOverride = split ? true : merge ? false : undefined;
  return {
    vault,
    chainId,
    dryRun,
    fork,
    runUpgrade,
    skipUpgrade,
    splitOverride,
    recordOnly,
  };
}

function loadCommon(repoRoot: string, chainId: number): CommonConfig {
  const file = path.join(repoRoot, "config", "common", `${chainId}.json`);
  if (!fs.existsSync(file)) die(`config/common/${chainId}.json not found`);
  return JSON.parse(fs.readFileSync(file, "utf8")) as CommonConfig;
}

/** Prints the deployed addresses recorded in the DeployAndSetup output config. */
function printDeployedSummary(
  outputPath: string,
  vault: string,
  chainId: number,
): void {
  if (!fs.existsSync(outputPath)) {
    console.log(`\ndeployed: (no output file at ${outputPath})`);
    return;
  }
  const out = JSON.parse(fs.readFileSync(outputPath, "utf8")) as {
    contracts?: {
      share?: string;
      accountant?: string;
      rolesAuthority?: string;
      vaults?: Array<{
        assetSymbol?: string;
        address?: string;
        composer?: string;
      }>;
    };
  };
  const c = out.contracts ?? {};
  const line = "─".repeat(62);
  console.log(`\n${line}`);
  console.log(`Deployed (${vault} @ ${chainId})`);
  console.log(line);
  console.log(`  share:          ${c.share ?? "-"}`);
  console.log(`  accountant:     ${c.accountant ?? "-"}`);
  console.log(`  rolesAuthority: ${c.rolesAuthority ?? "-"}`);
  for (const v of c.vaults ?? []) {
    console.log(
      `  vault[${v.assetSymbol ?? "?"}]: ${v.address ?? "-"}  composer ${v.composer ?? "-"}`,
    );
  }
}

type VaultInputConfig = {
  contracts?: {
    share?: string;
    accountant?: string;
    rolesAuthority?: string;
    vaults?: Array<{ address?: string; chains?: number[]; composer?: string }>;
  };
};

const ERC1967_ADMIN_SLOT =
  "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";

function isAddress(a?: string): a is `0x${string}` {
  return (
    !!a &&
    /^0x[0-9a-fA-F]{40}$/.test(a) &&
    a.toLowerCase() !== "0x0000000000000000000000000000000000000000" &&
    a.toLowerCase() !== "0x000000000000000000000000000000000000dead"
  );
}

function uniqAddresses(addrs: string[]): `0x${string}`[] {
  const seen = new Set<string>();
  const out: `0x${string}`[] = [];
  for (const a of addrs) {
    if (!isAddress(a)) continue;
    const key = a.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(a as `0x${string}`);
  }
  return out;
}

function loadVaultInput(repoRoot: string, vault: string): VaultInputConfig {
  const file = path.join(
    repoRoot,
    "script",
    "deployment-config",
    "vaults",
    `${vault}.json`,
  );
  return JSON.parse(fs.readFileSync(file, "utf8")) as VaultInputConfig;
}

function resolveUpgradeCandidateAddresses(
  repoRoot: string,
  vault: string,
  chainId: number,
): `0x${string}`[] {
  const cfg = loadVaultInput(repoRoot, vault);
  const addrs: string[] = [];
  addrs.push(cfg.contracts?.share ?? "");
  addrs.push(cfg.contracts?.accountant ?? "");
  for (const v of cfg.contracts?.vaults ?? []) {
    if (v.chains && !v.chains.includes(chainId)) continue;
    addrs.push(v.address ?? "");
    addrs.push(v.composer ?? "");
  }
  return uniqAddresses(addrs);
}

function freshStatePath(
  repoRoot: string,
  chainId: number,
  vault: string,
): string {
  return path.join(
    repoRoot,
    "script",
    "output",
    "migrate-state",
    `${chainId}-${vault}-fresh.json`,
  );
}

function loadFreshDeploymentExclusions(
  repoRoot: string,
  chainId: number,
  vault: string,
): Set<string> {
  const file = freshStatePath(repoRoot, chainId, vault);
  if (!fs.existsSync(file)) return new Set();
  const json = JSON.parse(fs.readFileSync(file, "utf8")) as {
    addresses?: string[];
  };
  return new Set(
    (json.addresses ?? []).filter(isAddress).map((a) => a.toLowerCase()),
  );
}

function writeFreshDeploymentExclusions(
  repoRoot: string,
  chainId: number,
  vault: string,
  addresses: `0x${string}`[],
): void {
  if (addresses.length === 0) return;
  const file = freshStatePath(repoRoot, chainId, vault);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(
    file,
    `${JSON.stringify({ chainId, vault, createdAt: Date.now(), addresses }, null, 2)}\n`,
  );
  console.log(`  upgrade:  cached freshly deployed proxies → ${file}`);
}

function clearFreshDeploymentExclusions(
  repoRoot: string,
  chainId: number,
  vault: string,
): void {
  const file = freshStatePath(repoRoot, chainId, vault);
  if (fs.existsSync(file)) fs.unlinkSync(file);
}

async function resolveProbeAddresses(
  repoRoot: string,
  vault: string,
  chainId: number,
): Promise<string[]> {
  const cfg = loadVaultInput(repoRoot, vault);
  const addrs: string[] = [];
  const push = (a?: string) => {
    if (
      a &&
      /^0x[0-9a-fA-F]{40}$/.test(a) &&
      a !== "0x0000000000000000000000000000000000000000"
    )
      addrs.push(a);
  };
  // The share can be an existing BoringVault/share token and is not a
  // reliable signal that this chain's Nest vault/accountant should be upgraded.
  push(cfg.contracts?.accountant);
  for (const v of cfg.contracts?.vaults ?? []) {
    if (v.chains && !v.chains.includes(chainId)) continue;
    push(v.address);
    push(v.composer);
  }
  return addrs;
}

async function anyAddressHasCode(
  rpcUrl: string,
  addrs: string[],
): Promise<boolean> {
  for (const a of addrs) {
    try {
      const res = await fetch(rpcUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "eth_getCode",
          params: [a, "latest"],
        }),
      });
      if (!res.ok) continue;
      const json = (await res.json()) as { result?: string };
      if (json.result && json.result !== "0x" && json.result.length > 2)
        return true;
    } catch {
      // fall through to next addr
    }
  }
  return false;
}

async function rpcResult<T>(
  rpcUrl: string,
  method: string,
  params: unknown[],
): Promise<T | undefined> {
  try {
    const res = await fetch(rpcUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    });
    if (!res.ok) return undefined;
    const json = (await res.json()) as { result?: T };
    return json.result;
  } catch {
    return undefined;
  }
}

async function hasCode(rpcUrl: string, addr: string): Promise<boolean> {
  const code = await rpcResult<string>(rpcUrl, "eth_getCode", [addr, "latest"]);
  return !!code && code !== "0x" && code.length > 2;
}

async function isProxy(rpcUrl: string, addr: string): Promise<boolean> {
  if (!(await hasCode(rpcUrl, addr))) return false;
  const adminSlot = await rpcResult<string>(rpcUrl, "eth_getStorageAt", [
    addr,
    ERC1967_ADMIN_SLOT,
    "latest",
  ]);
  if (!adminSlot || adminSlot === "0x") return false;
  return BigInt(adminSlot) !== 0n;
}

async function resolvePreExistingUpgradeTargets(
  repoRoot: string,
  vault: string,
  chainId: number,
  rpcUrl: string,
): Promise<`0x${string}`[]> {
  const freshExclusions = loadFreshDeploymentExclusions(
    repoRoot,
    chainId,
    vault,
  );
  const candidates = resolveUpgradeCandidateAddresses(repoRoot, vault, chainId);
  const targets: `0x${string}`[] = [];
  for (const addr of candidates) {
    if (freshExclusions.has(addr.toLowerCase())) continue;
    if (await isProxy(rpcUrl, addr)) targets.push(addr);
  }
  if (freshExclusions.size > 0) {
    console.log(
      `  upgrade:  excluding ${freshExclusions.size} freshly deployed cached proxy address(es)`,
    );
  }
  return targets;
}

async function cacheFreshDeploymentTargets(
  repoRoot: string,
  vault: string,
  chainId: number,
  rpcUrl: string,
  snapshotExistedBeforeRun: boolean,
  preExistingTargets: `0x${string}`[],
): Promise<void> {
  if (snapshotExistedBeforeRun) return;
  const outputFile = path.join(
    repoRoot,
    "script",
    "output",
    vault,
    `${chainId}-${vault}.json`,
  );
  if (!fs.existsSync(outputFile)) return;
  const preExisting = new Set(preExistingTargets.map((a) => a.toLowerCase()));
  const output = JSON.parse(
    fs.readFileSync(outputFile, "utf8"),
  ) as VaultInputConfig;
  const addrs = uniqAddresses([
    output.contracts?.share ?? "",
    output.contracts?.accountant ?? "",
    ...(output.contracts?.vaults ?? []).flatMap((v) => [
      v.address ?? "",
      v.composer ?? "",
    ]),
  ]);
  const fresh: `0x${string}`[] = [];
  for (const addr of addrs) {
    if (preExisting.has(addr.toLowerCase())) continue;
    if (await isProxy(rpcUrl, addr)) fresh.push(addr);
  }
  writeFreshDeploymentExclusions(repoRoot, chainId, vault, fresh);
}

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v || v.length === 0) die(`${name} is not set`);
  return v;
}

function privateKeyFromEnv(): `0x${string}` {
  const raw = requireEnv("PRIVATE_KEY").trim();
  const hex = raw.startsWith("0x") ? raw : `0x${raw}`;
  if (!/^0x[0-9a-fA-F]{64}$/.test(hex))
    die("PRIVATE_KEY is not a 32-byte hex string");
  return hex as `0x${string}`;
}

type ForgeStep = {
  label: string;
  scriptPath: string;
  sig: string;
  /** Positional args passed after --sig, in order. Typed strings for `run(string)`. */
  sigArgs?: string[];
  env: Record<string, string>;
};

function envValue(name: string): string | undefined {
  const value = process.env[name]?.trim();
  return value && value.length > 0 ? value : undefined;
}

function defaultVerifierUrl(chainId: number): string | undefined {
  switch (chainId) {
    case 1:
    case 56:
    case 480:
    case 42161:
      return `https://api.etherscan.io/v2/api?chainid=${chainId}`;
    default:
      return undefined;
  }
}

type ForgeVerifierConfig = {
  name: "etherscan" | "blockscout";
  apiKeyEnv: string;
  apiKey: string | undefined;
  urlEnv?: string;
  url?: string;
};

function resolveVerifierConfig(chainId: number): ForgeVerifierConfig {
  if (chainId === 98866) {
    return {
      name: "blockscout",
      apiKeyEnv: "PLUME_VERIFIER_API_KEY",
      apiKey: envValue("PLUME_VERIFIER_API_KEY"),
      urlEnv: "PLUME_VERIFIER_URL",
      url: envValue("PLUME_VERIFIER_URL"),
    };
  }

  if (chainId === 9745) {
    // Plasma's canonical explorer (plasmascan.to) is served by Etherscan's V2
    // multichain API, which uses the single unified Etherscan key across every
    // chain. Routescan is a separate indexer whose verifications never surface
    // on plasmascan, so always target Etherscan V2 here.
    return {
      name: "etherscan",
      apiKeyEnv: "ETHERSCAN_API_KEY_1",
      apiKey: envValue("ETHERSCAN_API_KEY_1"),
      url: "https://api.etherscan.io/v2/api?chainid=9745",
    };
  }

  return {
    name: "etherscan",
    apiKeyEnv: `ETHERSCAN_API_KEY_${chainId}`,
    apiKey: envValue(`ETHERSCAN_API_KEY_${chainId}`),
    url:
      envValue(`ETHERSCAN_VERIFIER_URL_${chainId}`) ??
      envValue(`VERIFIER_URL_${chainId}`) ??
      defaultVerifierUrl(chainId),
  };
}

function missingVerifierEnv(verifier: ForgeVerifierConfig): string[] {
  const missing: string[] = [];
  if (!verifier.apiKey) missing.push(verifier.apiKeyEnv);
  if (verifier.urlEnv && !verifier.url) missing.push(verifier.urlEnv);
  return missing;
}

type ForgeRunResult = {
  status: number;
  /** forge reported the on-chain broadcast itself completed. */
  broadcastSucceeded: boolean;
  /** Non-zero exit was caused only by explorer verification, not the broadcast. */
  verifyOnlyFailure: boolean;
};

async function runForge(
  repoRoot: string,
  step: ForgeStep,
  rpcUrl: string,
  dryRun: boolean,
  fork: boolean,
  verifier: ForgeVerifierConfig,
): Promise<ForgeRunResult> {
  const args = [
    "script",
    step.scriptPath,
    "--rpc-url",
    rpcUrl,
    "--ffi",
    "--sig",
    step.sig,
    ...(step.sigArgs ?? []),
  ];
  if (!dryRun) {
    args.push("--broadcast");
    // Only verify on real runs; fork mode points at anvil so there's no
    // explorer to verify against.
    if (!fork && missingVerifierEnv(verifier).length === 0 && verifier.apiKey) {
      args.push("--verify");
      if (verifier.url) args.push("--verifier-url", verifier.url);
      args.push(
        "--etherscan-api-key",
        verifier.apiKey,
        "--verifier",
        verifier.name,
      );
    }
  }

  console.log(`\n── ${step.label} ──`);
  console.log(`forge ${args.join(" ")}`);

  // spawn (not spawnSync) so output streams live to the terminal while we keep
  // a copy. forge exits non-zero when explorer verification fails even though
  // the broadcast already landed on-chain; we need the text to tell the two
  // apart and avoid aborting the pipeline over a cosmetic verification miss.
  let captured = "";
  const status = await new Promise<number>((resolve) => {
    const child = spawn("forge", args, {
      cwd: repoRoot,
      env: { ...process.env, ...step.env },
      stdio: ["inherit", "pipe", "pipe"],
    });
    const tee = (chunk: Buffer, out: NodeJS.WritableStream) => {
      const text = chunk.toString();
      captured += text;
      out.write(text);
    };
    child.stdout?.on("data", (c: Buffer) => tee(c, process.stdout));
    child.stderr?.on("data", (c: Buffer) => tee(c, process.stderr));
    child.on("error", (err) => {
      captured += String(err);
      resolve(1);
    });
    child.on("close", (code) => resolve(code ?? 1));
  });

  const broadcastSucceeded = captured.includes(
    "ONCHAIN EXECUTION COMPLETE & SUCCESSFUL",
  );
  const verificationFailed =
    /not all\s*\(\d+\s*\/\s*\d+\)\s*contracts were verified|failed to verify contract/i.test(
      captured,
    );
  return {
    status,
    broadcastSucceeded,
    verifyOnlyFailure: status !== 0 && broadcastSucceeded && verificationFailed,
  };
}

/// Prints a resume hint for steps that deployed on-chain but failed to verify.
function printUnverifiedSummary(
  steps: ForgeStep[],
  rpcUrl: string,
  verifier: ForgeVerifierConfig,
): void {
  if (steps.length === 0) return;
  const keyRef = verifier.apiKey ? `$${verifier.apiKeyEnv}` : "<api-key>";
  const verifyFlags = [
    "--resume",
    "--verify",
    "--verifier",
    verifier.name,
    ...(verifier.url ? ["--verifier-url", verifier.url] : []),
    "--etherscan-api-key",
    keyRef,
  ].join(" ");
  console.warn(
    `\n⚠ ${steps.length} step(s) deployed on-chain but did not fully verify on the explorer.`,
  );
  console.warn(
    `  The migration completed regardless. Re-attempt verification (no redeploy) with:`,
  );
  for (const s of steps) {
    const sigArgs = (s.sigArgs ?? []).join(" ");
    console.warn(
      `    forge script ${s.scriptPath} --rpc-url ${rpcUrl} --ffi --sig ${s.sig}${sigArgs ? ` ${sigArgs}` : ""} ${verifyFlags}`,
    );
  }
}

async function main(): Promise<void> {
  const {
    vault,
    chainId,
    dryRun,
    fork,
    runUpgrade: runUpgradeFlag,
    splitOverride,
    recordOnly,
  } = parseArgs();
  // Both modes skip real Safe propose. `fork` additionally broadcasts forge
  // txs to the configured RPC (which the user points at anvil).
  const safeDryRun = dryRun || fork;
  const repoRoot = path.resolve(__dirname, "..");

  if (!SAFE_TX_SERVICE[chainId]) {
    die(`chainId ${chainId} not configured in tools/safeTxService.ts`);
  }
  const vaultCfg = path.join(
    repoRoot,
    "script",
    "deployment-config",
    "vaults",
    `${vault}.json`,
  );
  if (!fs.existsSync(vaultCfg)) die(`vault config not found: ${vaultCfg}`);

  const common = loadCommon(repoRoot, chainId);
  const safe = common.common.multisig;
  const chainName = common.name;
  const rpcEnv = fork ? "FORK_RPC_URL" : common.rpc;
  const rpcUrl = requireEnv(rpcEnv);

  const signerKey = privateKeyFromEnv();
  const proposerAddress = privateKeyToAccount(signerKey).address;

  const modeTag = dryRun ? " [DRY RUN]" : fork ? " [FORK]" : "";
  console.log(`deploy ${vault} @ chainId=${chainId} (${chainName})${modeTag}`);
  console.log(`  safe:     ${safe}`);
  console.log(`  proposer: ${proposerAddress}`);

  const [auth, safeOwner] = await Promise.all([
    isAuthorizedProposer(chainId, safe, proposerAddress),
    getSafeOwner(chainId, safe, rpcUrl),
  ]);
  if (auth === false) {
    console.warn(
      `  warning: proposer ${proposerAddress} is neither an owner nor a registered delegate on this Safe. Continuing — the service may reject propose().`,
    );
  } else if (auth === null) {
    console.warn(
      `  warning: could not verify proposer authorization via Safe API. Continuing.`,
    );
  }

  const verifier = resolveVerifierConfig(chainId);
  const missingVerifier = missingVerifierEnv(verifier);
  if (!dryRun && !fork && missingVerifier.length > 0) {
    console.warn(
      `  warning: ${missingVerifier.join(", ")} not set — forge will run without --verify.`,
    );
  } else if (!dryRun && !fork) {
    console.log(
      `  verifier: ${verifier.name}${verifier.url ? ` ${verifier.url}` : ""}`,
    );
  }

  // Deployment-state detection is informational. Upgrade is intentionally
  // opt-in because existing share/vault/accountant bytecode can also mean:
  // - the share is an existing BoringVault/share token,
  // - the previous migration run deployed successfully but failed later, or
  // - the chain has already been migrated and only ownership/Safe proposal is pending.
  const probeAddrs = await resolveProbeAddresses(repoRoot, vault, chainId);
  const hasChainContractCode = await anyAddressHasCode(rpcUrl, probeAddrs);
  const outputPath = path.join(
    repoRoot,
    "script",
    "output",
    vault,
    `${chainId}-${vault}.json`,
  );
  const snapshotExists = fs.existsSync(outputPath);
  const preExistingUpgradeTargets = await resolvePreExistingUpgradeTargets(
    repoRoot,
    vault,
    chainId,
    rpcUrl,
  );
  const mode =
    hasChainContractCode || snapshotExists ? "existing" : "new-chain";
  const modeReason = hasChainContractCode
    ? "on-chain accountant/vault code detected"
    : snapshotExists
      ? "output snapshot present"
      : "no accountant/vault contracts detected";
  console.log(`  mode:     ${mode} (${modeReason})`);
  const runUpgrade = runUpgradeFlag && preExistingUpgradeTargets.length > 0;
  if (runUpgradeFlag) {
    if (preExistingUpgradeTargets.length === 0) {
      console.log(
        `  upgrade:  no pre-existing upgradeable proxies found; skipped`,
      );
    } else {
      console.log(
        `  upgrade:  enabled for ${preExistingUpgradeTargets.length} pre-existing proxy/proxies (--run-upgrade)`,
      );
    }
  } else {
    console.log(`  upgrade:  skipped (default; pass --run-upgrade to upgrade)`);
  }

  const commonEnv = { CHAIN_ID: String(chainId), VAULT_SYMBOL: vault };
  const steps: ForgeStep[] = [];
  // Upgrade runs FIRST when there are pre-existing proxies to upgrade.
  // DeployAndSetup deploys NestVaultComposer whose initializer calls
  // vault.token() / IERC7575(vault).share(); on a chain where the vault
  // is still on a stale (pre-OFT) impl, those selectors don't exist and
  // composer init reverts. Upgrading the vault impl first gives composer
  // init a working target.
  if (runUpgrade) {
    steps.push({
      label: "Upgrade (vault scope)",
      scriptPath: "script/deploy/Upgrade.s.sol",
      sig: "runMsig()",
      env: {
        ...commonEnv,
        CONTRACT: "vault",
        UPGRADE_TARGETS: preExistingUpgradeTargets.join(","),
      },
    });
  }
  // `run(string)` is the hybrid entry: broadcasts deployer-owned calls
  // (CREATE3 deploys) AND queues multisig-owned setup. `runMsig()` only
  // simulates + queues — fork/testnet deploys require the hybrid path.
  steps.push({
    label: "DeployAndSetup",
    scriptPath: "script/deploy/DeployAndSetup.s.sol",
    sig: "run(string)",
    sigArgs: [vault],
    env: { ...commonEnv },
  });
  steps.push({
    label: "TransferOwnership",
    scriptPath: "script/setup/TransferOwnership.s.sol",
    sig: "run()",
    env: { ...commonEnv, NEW_OWNER: safe },
  });
  // SetupFees queues setFee/setMaxFee (+ accountant management/performance fees)
  // It self-skips zero-fee targets and writes no batch file when nothing is
  // queued, so it's safe to run unconditionally — vaults with no configured fees
  // produce no slot-4 section. run() is HYBRID (same routing as DeployAndSetup /
  // TransferOwnership): the deployer broadcasts setFee directly on any vault it
  // still owns — e.g. a freshly deployed vault whose ownership transfer hasn't
  // been accepted yet — and only queues fees for vaults already owned by the
  // msig. Queued fees go to slot 4, executed after accept-ownership; a queued fee
  // therefore only targets a vault the msig already owns from a prior migration,
  // so the owner/authority gate on setFee is satisfied. When upgrading a pre-Fee
  // impl, FEE_FORCE_SETFEE skips the on-chain fees() idempotency read (which
  // reverts on the stale impl) and relies on the upgrade in slot 2a executing
  // before these fees in nonce/MultiSend order.
  //
  // SetupFees only ever sets the active fee and never touches maxFee unless the
  // config carries an explicit `vaultMaxFees.<type>` block, so a target fee within
  // the existing cap (e.g. 1500 under a freshly deployed vault's 20% FEE_CAP) leaves
  // maxFee untouched — deploy never lowers a cap to pin maxFee == fee.
  steps.push({
    label: "SetupFees",
    scriptPath: "script/setup/SetupFees.s.sol",
    sig: "run()",
    env: {
      ...commonEnv,
      ...(runUpgrade ? { FEE_FORCE_SETFEE: "true" } : {}),
    },
  });

  // Clear batch files from a previous run before regenerating. A forge step that
  // queues zero txs writes no file (writeMsigBatch early-returns on an empty
  // batch), so a stale file from an earlier invocation would otherwise be picked
  // up by the splitter. This bites SetupFees in particular: when the deployer
  // broadcasts every fee directly (or they're already set), nothing is queued —
  // but a prior run's fee batch would still surface as slot 4.
  const staleBatchNames = [
    `${chainId}-${vault}-DeployAndSetup.json`,
    `${chainId}-${vault}-TransferOwnership-AcceptOwnership.json`,
    `${chainId}-${vault}-SetupFees.json`,
    ...(runUpgrade ? [`${chainId}-${vault}-Upgrade-vault.json`] : []),
  ];
  for (const name of staleBatchNames) {
    for (const dir of [
      path.join(repoRoot, "script", "output", "msig"),
      path.join(repoRoot, "script", "output", "msig", vault),
    ]) {
      const p = path.join(dir, name);
      if (fs.existsSync(p)) fs.rmSync(p);
    }
  }

  const unverifiedSteps: ForgeStep[] = [];
  for (const step of steps) {
    const result = await runForge(
      repoRoot,
      step,
      rpcUrl,
      dryRun,
      fork,
      verifier,
    );
    if (step.label === "DeployAndSetup") {
      await cacheFreshDeploymentTargets(
        repoRoot,
        vault,
        chainId,
        rpcUrl,
        snapshotExists,
        preExistingUpgradeTargets,
      );
    }
    if (result.status !== 0) {
      // Explorer verification failing does NOT mean the deploy failed — the
      // contracts are on-chain. Don't abort: later steps depend on this one's
      // broadcast, and split/record still need to run. Collect the step and
      // surface a resume hint at the end.
      if (result.verifyOnlyFailure) {
        console.warn(
          `\n⚠ deploy: step "${step.label}" deployed on-chain but explorer verification was incomplete — continuing.`,
        );
        unverifiedSteps.push(step);
        continue;
      }
      die(`forge step "${step.label}" exited with code ${result.status}`);
    }
  }

  const { deployPath, upgradePath, ownerPath, feesPath } = resolveBatchPaths(
    repoRoot,
    chainId,
    vault,
  );
  // A forge step that queues zero txs writes no batch file (e.g. a fully
  // idempotent TransferOwnership where everything is already owned). That's a
  // valid "nothing to do" outcome — the step already exited 0 above, so a
  // missing file here is not a failure. splitBatches treats absence as empty.
  for (const p of [deployPath, ownerPath]) {
    if (!fs.existsSync(p)) {
      console.warn(`deploy: no batch written (zero queued txs): ${p}`);
    }
  }

  const outDir = splitOutDir(repoRoot, chainId, vault);
  const { sections, eidsLabel, hasUpgrade } = splitBatches({
    deployPath,
    ownerPath,
    upgradePath:
      runUpgrade && fs.existsSync(upgradePath) ? upgradePath : undefined,
    feesPath: fs.existsSync(feesPath) ? feesPath : undefined,
    chainId,
    vault,
    outDir,
  });

  console.log(`\nsplit → ${outDir}`);
  for (const s of sections) {
    console.log(`  ${s.file}  (${s.batch.transactions.length} txs)`);
  }

  const service = serviceFor(chainId);
  const splitMode = splitOverride ?? service.splitBatches;
  if (splitOverride !== undefined && splitOverride !== service.splitBatches) {
    console.log(
      `  msig:     ${splitMode ? "split" : "merged"} (overriding chain default via --${splitMode ? "split" : "merge"})`,
    );
  } else {
    console.log(
      `  msig:     ${splitMode ? "split" : "merged"} (chain default)`,
    );
  }

  if (recordOnly) {
    const manifestFile = writeManifest(repoRoot, {
      version: 1,
      vault,
      chainId,
      chainName,
      safe,
      splitMode,
      eidsLabel,
      hasUpgrade,
      recordedAt: new Date().toISOString(),
      sections,
    });
    printDeployedSummary(outputPath, vault, chainId);
    printQueuedSummary(sections);
    console.log(`\nrecorded → ${manifestFile}`);
    console.log(`  propose later with: pnpm queue ${vault} ${chainId}`);
    // Deploy + record succeeded; drop fresh-deployment upgrade exclusions so a
    // later real run isn't filtered. Skip in dry-run/fork (no broadcast).
    if (!safeDryRun) clearFreshDeploymentExclusions(repoRoot, chainId, vault);
    printUnverifiedSummary(unverifiedSteps, rpcUrl, verifier);
    return;
  }

  const { aborted } = await runProposePhase({
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
    dryRunTag: dryRun ? "dry-run" : fork ? "fork" : null,
  });

  if (!aborted && !safeDryRun) {
    clearFreshDeploymentExclusions(repoRoot, chainId, vault);
  }

  printUnverifiedSummary(unverifiedSteps, rpcUrl, verifier);

  if (aborted) process.exit(1);
}

main().catch((err) => {
  console.error(err instanceof Error ? (err.stack ?? err.message) : err);
  process.exit(1);
});
