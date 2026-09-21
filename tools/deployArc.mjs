#!/usr/bin/env node
import "dotenv/config";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { createPublicClient, http, parseAbi } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { resumeBroadcast } from "./arcBroadcast.mjs";
import {
  DEPLOYMENT_PHASES,
  verifierConfig,
  verifierArgs,
  phaseBroadcastRoot,
  assertCompletedBroadcast,
  completedTransactions,
  prepareCreateXProject,
  openVerifier,
  loginToExplorer,
} from "./arcVerification.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (name) =>
  JSON.parse(fs.readFileSync(path.join(root, name), "utf8"));
const args = process.argv.slice(2);
const broadcast = args.includes("--broadcast");
const verifyOnly = args.includes("--verify-only");
const skipVerify = args.includes("--skip-verify");
const resume = args.includes("--resume");
const positional = args.filter((a) => !a.startsWith("--"));
const [phase, symbol] = positional;
const help = `Usage: pnpm deploy:arc <phase> [vault] [--broadcast | --verify-only] [--skip-verify] [--resume]

Phases, in order:
  login                       Browser email-code login for the protected explorer (no transactions)
  check                       Read-only Arc dependency checks
  bootstrap                   CreateX only
  common                      Shared authority, operators, blacklist hook, CCTP
  compliance                  Deploy and configure ComplianceProxy + PredicateV2Hook as deployer
  activate                    Verify shared V2 configuration and record addresses (no transactions)
  vault <nOPAL|nFALCON|FACTOR> Deploy vault stack, Composer, permissions and LZ source config
  sync-prices                 Mirror current Plume net rates to Arc accountants before handoff
  ownership <vault>           FINAL HANDOFF: transfer each vault to the configured multisig
  common-ownership            FINAL HANDOFF: transfer shared stack, including compliance, last

Default is Forge simulation. --broadcast deploys and verifies deployment phases.
--verify-only retries explorer verification from the completed phase broadcast; no redeployment.
--skip-verify explicitly disables verification for a broadcast.
--resume --broadcast reconciles and continues a saved common/compliance/vault deployment.
Broadcasts send one transaction at a time and wait for each receipt (--slow).
Verification defaults to Blockscout at https://explorer.arc.io/api/.
ARC_VERIFIER and ARC_VERIFIER_URL can override that explorer.
ARC_VERIFIER_API_KEY is optional for Blockscout, required for etherscan/custom.
Keep everything deployer-owned until all three vaults are configured.
Execute multisig acceptance batches only during final handoff, as described in
docs/arc-predicate-v2-deployment.md. This command does not submit Safe proposals.
Simulation restores canonical common addresses; candidate/output artifacts remain for review.`;

async function main() {
  if (phase === "sync-prices") {
    const child = spawn(
      process.execPath,
      [
        "--require",
        "ts-node/register",
        path.join(root, "tools/syncArcPrices.ts"),
        ...args.slice(1),
      ],
      { cwd: root, stdio: "inherit", env: process.env },
    );
    process.exitCode = await new Promise((resolve, reject) => {
      child.once("error", reject);
      child.once("exit", (code) => resolve(code ?? 1));
    });
    return;
  }
  if (args.includes("--help") || !phase) return console.log(help);
  if (
    args.some(
      (a) =>
        a.startsWith("--") &&
        !["--broadcast", "--verify-only", "--skip-verify", "--resume"].includes(
          a,
        ),
    )
  )
    throw new Error("Unknown flag");
  if (verifyOnly && (broadcast || skipVerify))
    throw new Error(
      "--verify-only cannot be combined with --broadcast or --skip-verify",
    );
  if (skipVerify && !broadcast)
    throw new Error("--skip-verify requires --broadcast");
  if (
    resume &&
    (!broadcast ||
      verifyOnly ||
      !["common", "compliance", "vault"].includes(phase))
  )
    throw new Error(
      "--resume requires --broadcast for common, compliance, or vault",
    );
  if ((verifyOnly || skipVerify) && !DEPLOYMENT_PHASES.has(phase))
    throw new Error(
      "Verification flags apply only to bootstrap, common, compliance, and vault",
    );
  if (phase === "login") {
    if (args.length !== 1) throw new Error("Usage: pnpm deploy:arc login");
    return loginToExplorer(verifierConfig(process.env), process.env);
  }
  const verification =
    DEPLOYMENT_PHASES.has(phase) && (verifyOnly || (broadcast && !skipVerify));
  const verifier = verification ? verifierConfig(process.env) : undefined;
  const vaultPhase = phase === "vault" || phase === "ownership";
  if (positional.length !== (vaultPhase ? 2 : 1)) throw new Error(help);
  if (vaultPhase && !["nOPAL", "nFALCON", "FACTOR"].includes(symbol))
    throw new Error("Unsupported Arc vault");
  const common = read("config/common/5042.json");
  const rpc = process.env[common.rpc];
  if (!rpc) throw new Error(`${common.rpc} is required`);
  const client = createPublicClient({ transport: http(rpc) });
  if ((await client.getChainId()) !== 5042)
    throw new Error("ARC_RPC_URL must target chain 5042");
  if (phase === "check") {
    if (broadcast) throw new Error("check is read-only");
    const lz = read("config/layerzero/5042.json");
    const cctp = read("config/cctp/5042.json");
    const targets = {
      Permit2: common.common.permit2,
      Safe: common.common.multisig,
      PredicateRegistry: read("config/compliance/5042.json").v2
        .predicateRegistry,
      USDC: read("config/assets/5042.json").USDC,
      endpoint: lz.endpoint,
      sendLib: lz.sendLib302,
      receiveLib: lz.receiveLib302,
      executor: lz.executor,
      ...lz.dvns["1"],
      messageTransmitter: cctp.messageTransmitter,
      tokenMessenger: cctp.tokenMessenger,
      tokenMinter: cctp.tokenMinter,
      CREATE2Factory: read("config/createx/deployment.json").factory,
    };
    for (const [name, address] of Object.entries(targets)) {
      const code = await client.getCode({ address });
      if (!code || code === "0x")
        throw new Error(`${name} has no code: ${address}`);
      console.log(`${name}: ${address} OK`);
    }
    for (const [address, signature, fn, expected] of [
      [lz.endpoint, "function eid() view returns (uint32)", "eid", lz.eid],
      [targets.USDC, "function decimals() view returns (uint8)", "decimals", 6],
      [
        cctp.messageTransmitter,
        "function localDomain() view returns (uint32)",
        "localDomain",
        cctp.domain,
      ],
    ]) {
      const actual = await client.readContract({
        address,
        abi: parseAbi([signature]),
        functionName: fn,
      });
      if (Number(actual) !== expected)
        throw new Error(`${fn}: expected ${expected}, got ${actual}`);
      console.log(`${fn}: ${actual} OK`);
    }
    console.log(
      `CreateX: ${(await client.getCode({ address: common.common.createx })) ? "deployed" : "bootstrap required"}`,
    );
    return;
  }
  const commands = {
    bootstrap: ["script/deploy/DeployTimelock.s.sol", "--sig", "runCreateX()"],
    common: ["script/deploy/DeployAndSetup.s.sol", "--sig", "runCommonV2()"],
    "common-ownership": [
      "script/setup/TransferOwnership.s.sol",
      "--sig",
      "run()",
    ],
    compliance: [
      "script/deploy/DeployComplianceProxy.s.sol",
      "--sig",
      "runDeployOnly()",
    ],
    activate: [
      "script/deploy/DeployComplianceProxy.s.sol",
      "--sig",
      "activateCommon()",
    ],
    vault: [
      "script/deploy/DeployAndSetup.s.sol",
      "--sig",
      "run(string)",
      symbol,
    ],
    ownership: ["script/setup/TransferOwnership.s.sol", "--sig", "run()"],
  };
  if (!commands[phase]) throw new Error(help);
  if (phase === "activate" && broadcast)
    throw new Error("activate only verifies state and writes local config");
  let deployer;
  if (!verifyOnly)
    try {
      const key = process.env.PRIVATE_KEY;
      deployer = privateKeyToAccount(
        key?.startsWith("0x") ? key : `0x${key}`,
      ).address;
    } catch {
      throw new Error(
        "A valid PRIVATE_KEY is required for the pinned CREATE3 deployer",
      );
    }
  if (
    !verifyOnly &&
    deployer.toLowerCase() !== "0xc28e1cdfb582953fef53f76c64426c2ac79c716e"
  ) {
    throw new Error(
      "PRIVATE_KEY must match the pinned CREATE3 deployer 0xc28e1cDfB582953fEf53f76C64426c2aC79C716e",
    );
  }
  const env = { ...process.env, CHAIN_ID: "5042" };
  const broadcastRoot = phaseBroadcastRoot(root, phase, symbol);
  env.FOUNDRY_BROADCAST = broadcastRoot;
  if (verifier) {
    // Pass credentials through the environment, never command-line output.
    env.ETHERSCAN_API_KEY = verifier.key || "";
    env.VERIFIER_API_KEY = verifier.key || "";
  }
  const runForge = (forgeArgs, extraEnv = {}) =>
    new Promise((resolve, reject) => {
      const child = spawn("forge", forgeArgs, {
        cwd: root,
        env: { ...env, ...extraEnv },
        stdio: "inherit",
      });
      child.once("error", reject);
      child.once("close", (status) => resolve({ status: status ?? 1 }));
    });
  const signature = commands[phase][2].split("(")[0];
  const logPath = path.join(
    broadcastRoot,
    path.basename(commands[phase][0]),
    "5042",
    `${signature}-latest.json`,
  );
  if (verifyOnly && phase !== "bootstrap")
    await assertCompletedBroadcast(logPath, client);
  if (
    broadcast &&
    !resume &&
    DEPLOYMENT_PHASES.has(phase) &&
    fs.existsSync(logPath)
  ) {
    try {
      completedTransactions(JSON.parse(fs.readFileSync(logPath, "utf8")));
    } catch {
      throw new Error(
        `Saved deployment is incomplete. Continue it with: pnpm deploy:arc ${phase}${symbol ? ` ${symbol}` : ""} --broadcast --resume${skipVerify ? " --skip-verify" : ""}`,
      );
    }
  }
  const createX =
    verification && phase === "bootstrap"
      ? await prepareCreateXProject(root, runForge)
      : undefined;
  if (verifyOnly) delete env.PRIVATE_KEY;

  // Do not inherit step/scope controls from another deployment session.
  for (const key of [
    "STEPS",
    "SCOPE",
    "VAULT_SYMBOL",
    "REFERENCE_CHAIN_ID",
    "TIMELOCK_PAIRS",
  ])
    delete env[key];
  if (phase === "ownership" || phase === "common-ownership") {
    env.VAULT_SYMBOL = symbol || "nCOMMON";
    env.SCOPE = phase === "ownership" ? "vault" : "common";
    env.NEW_OWNER = common.common.multisig;
    env.NEW_OWNER_IS_TIMELOCK = "false";
  }
  const canonical = path.join(
    root,
    "script/deployment-config/common/5042.json",
  );
  const before = fs.readFileSync(canonical);
  console.log(
    `Arc 5042: ${phase}${symbol ? ` ${symbol}` : ""} (${verifyOnly ? "verification only" : broadcast ? "broadcast" : "simulation/state check"})`,
  );
  let result;
  const connection = verifier ? await openVerifier(verifier, env) : undefined;
  const activeVerifier = connection?.config;
  try {
    if (resume) {
      const key = process.env.PRIVATE_KEY;
      await resumeBroadcast(
        logPath,
        client,
        privateKeyToAccount(key.startsWith("0x") ? key : `0x${key}`),
      );
      await assertCompletedBroadcast(logPath, client);
      delete env.PRIVATE_KEY;
    }
    if (resume && !verification) {
      result = { status: 0 };
    } else if (verifyOnly && phase === "bootstrap") {
      const code = await client.getCode({ address: createX.address });
      if (!code || code === "0x")
        throw new Error("CreateX is not deployed on Arc");
      result = { status: 0 };
    } else {
      // Verification-only requires all receipts; deployment resume reconciles the
      // mined prefix and finishes it before asking Forge to verify the receipts.
      result = await runForge([
        "script",
        ...commands[phase],
        "--rpc-url",
        rpc,
        ...(broadcast || verifyOnly ? ["--broadcast"] : []),
        ...(verifyOnly || resume ? ["--resume"] : []),
        ...(broadcast ? ["--slow"] : []),
        ...(verification && phase !== "bootstrap"
          ? ["--verify", ...verifierArgs(activeVerifier)]
          : []),
      ]);
    }
    if (result.status === 0 && createX) {
      result = await runForge(
        [
          "verify-contract",
          createX.address,
          "src/CreateX.sol:CreateX",
          "--root",
          createX.dir,
          "--chain",
          "5042",
          "--watch",
          ...verifierArgs(activeVerifier),
        ],
        { FOUNDRY_PROFILE: "default" },
      );
    }
    if (verification && result.status !== 0) {
      console.error(
        `Explorer verification/deployment did not complete. Check receipts before continuing. Retry verification only: pnpm deploy:arc ${phase}${symbol ? ` ${symbol}` : ""} --verify-only`,
      );
    }
  } finally {
    await connection?.close();
    if (!broadcast && phase !== "activate") fs.writeFileSync(canonical, before);
  }
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
}

main().catch((error) => {
  console.error(`deploy:arc: ${error.shortMessage || error.message}`);
  process.exitCode = 1;
});
