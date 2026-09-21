#!/usr/bin/env ts-node
/**
 * Propose the pinned parallel Composer V2 schedule to the nTEST proposer Safe.
 * The ComplianceProxy operation is already executed on-chain. This script never
 * consumes either the completed ComplianceProxy schedule or the Composer upgrade.
 *
 * Local validation only:
 *   pnpm queue:ntest-compliance --check
 *
 * Read-only RPC and proposer authorization preflight:
 *   pnpm queue:ntest-compliance --preflight
 *
 * Submit one Safe transaction containing the Composer V2 scheduleBatch call:
 *   pnpm queue:ntest-compliance --submit
 */
import "dotenv/config";
import * as fs from "fs";
import * as path from "path";
import {
  createPublicClient,
  decodeFunctionData,
  http,
  keccak256,
  parseAbi,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

import { isAuthorizedProposer, proposeBatch, type SafeTx } from "./safePropose";

const CHAIN_ID = 98866;
const SAFE = "0xA8FCCF45A12F4b9BaaD683c0388A78BB902d737D" as const;
const TIMELOCK = "0xA0B8fd3Dade4e52425199Aa8c09ca835a55Ad056" as const;
const ROLES_AUTHORITY = "0x9995311BF7Bf8675eeA58258bcf3f99bcFC18478" as const;
const PREDICATE_V2_HOOK = "0xe1CD2F46B5aC47F5c65158a53116A0f413f4Ce4f" as const;
const COMPLIANCE_PROXY = "0xF325E0f939963b42A22538B98b30E1CAeB2C37bA" as const;
const CCTP_RELAYER = "0x45bD35BEb70a3F0937f9701fE49AC1842dCc97b3" as const;
const COMPOSER_V1 = "0x1daF84Ae51CcD1D9cdeDfF31e689cD2aA7579034" as const;
const COMPOSER_V1_IMPLEMENTATION =
  "0x66098f4e21adbeebde27f388cf16267cf3c15950" as const;
const COMPOSER_V2 = "0x4e6A52b0d22E333C01e71ed574DB6cE2b20CC0a1" as const;
const EXPECTED_DELAY = 60n;
const COMPLETED_COMPLIANCE_OPERATION_ID =
  "0xe1008ebf548e2f2d2a90d9a9b6d2e0ce2ecd87e7ebd45e742c3b5866e037c9d2";
const ZERO_BYTES32 = `0x${"00".repeat(32)}`;
const ERC1967_IMPLEMENTATION_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

const BATCHES = [
  {
    filename: "98866-nTEST-DeployPredicateV2Composer-Schedule.json",
    label: "parallel Composer V2",
    calldataHash:
      "0xe12fa9053628cecd9f638d920b73cf7088c84a669b995366d43f3ce0ef888902",
    salt: "0x9fa85661d4ea1948aa1e28fcc7d75df48d9c48de11a3fa4e17d6aba288a36676",
    callCount: 18,
    allowedTargets: [ROLES_AUTHORITY, CCTP_RELAYER, COMPOSER_V2],
  },
] as const;

const FORBIDDEN_ADDRESSES = {
  wrongCommonSafe: "0xa08A0Dc480BD60d1d56C8Eec6c722125eAfEa982",
  oldComplianceProxy: "0xdC13A73A3a04822Ad7FB1832F77a58df387349A2",
  liveComposerV1: COMPOSER_V1,
  liveComposerProxyAdmin: "0x36524b4c4F37195AcED4BfC99c1Df3Dc90d11c4E",
  morphoAdapter: "0xB2886ad7c88a0D1731D0Ea6c1A40F71D2fA5E186",
  abandonedUnlooper: "0x245Ea9153a1913bb8790fb1e0471c6561fd27cF2",
} as const;

const TIMELOCK_ABI = parseAbi([
  "function scheduleBatch(address[] targets,uint256[] values,bytes[] payloads,bytes32 predecessor,bytes32 salt,uint256 delay)",
  "function getMinDelay() view returns (uint256)",
  "function isOperationDone(bytes32 id) view returns (bool)",
]);
const RELAYER_ABI = parseAbi([
  "function isComposer(address composer) view returns (bool)",
  "function setComposer(address composer,bool enabled)",
]);
const COMPOSER_ABI = parseAbi([
  "function COMPLIANCE_PROXY() view returns (address)",
  "function ASSET_OFT() view returns (address)",
]);

type BatchFile = {
  chainId: number;
  transactions: SafeTx[];
};

type ValidatedBatch = {
  transaction: SafeTx;
  label: string;
  innerCallCount: number;
  salt: Hex;
  calldataHash: Hex;
};

function die(message: string): never {
  throw new Error(`queue:ntest-compliance: ${message}`);
}

function sameAddress(a: string, b: string): boolean {
  return a.toLowerCase() === b.toLowerCase();
}

function requireEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) die(`${name} is not set`);
  return value;
}

function privateKeyFromEnv(): `0x${string}` {
  const raw = requireEnv("PRIVATE_KEY");
  const key = raw.startsWith("0x") ? raw : `0x${raw}`;
  if (!/^0x[0-9a-fA-F]{64}$/.test(key)) {
    die("PRIVATE_KEY is not a 32-byte hex string");
  }
  return key as `0x${string}`;
}

function parseMode(): "check" | "preflight" | "submit" {
  const args = process.argv.slice(2);
  if (
    args.length !== 1 ||
    !["--check", "--preflight", "--submit"].includes(args[0])
  ) {
    die("usage: pnpm queue:ntest-compliance --check | --preflight | --submit");
  }
  if (args[0] === "--submit") return "submit";
  if (args[0] === "--preflight") return "preflight";
  return "check";
}

function validateBatch(
  repoRoot: string,
  expected: (typeof BATCHES)[number],
): ValidatedBatch {
  const batchPath = path.join(
    repoRoot,
    "script",
    "output",
    "msig",
    expected.filename,
  );
  if (!fs.existsSync(batchPath)) die(`batch not found: ${batchPath}`);

  const batch = JSON.parse(fs.readFileSync(batchPath, "utf8")) as BatchFile;
  if (batch.chainId !== CHAIN_ID) {
    die(
      `${expected.label} batch chainId is ${batch.chainId}; expected ${CHAIN_ID}`,
    );
  }
  if (!Array.isArray(batch.transactions) || batch.transactions.length !== 1) {
    die(`${expected.label} batch must contain exactly one Safe transaction`);
  }

  const transaction = batch.transactions[0];
  if (!sameAddress(transaction.to, TIMELOCK)) {
    die(`${expected.label} target is ${transaction.to}; expected ${TIMELOCK}`);
  }
  if (transaction.value !== "0" || transaction.operation !== "0") {
    die(`${expected.label} transaction must be a zero-value CALL`);
  }
  if (!/^0x[0-9a-fA-F]+$/.test(transaction.data)) {
    die(`${expected.label} calldata is not valid hex`);
  }

  const data = transaction.data as Hex;
  const calldataHash = keccak256(data);
  if (calldataHash !== expected.calldataHash) {
    die(
      `${expected.label} calldata changed: hash ${calldataHash}; expected ${expected.calldataHash}`,
    );
  }
  if (data.toLowerCase().includes("9623609d")) {
    die(`${expected.label} contains forbidden upgradeAndCall calldata`);
  }
  for (const [label, address] of Object.entries(FORBIDDEN_ADDRESSES)) {
    if (data.toLowerCase().includes(address.slice(2).toLowerCase())) {
      die(`${expected.label} contains forbidden ${label} address ${address}`);
    }
  }

  const decoded = decodeFunctionData({ abi: TIMELOCK_ABI, data });
  if (decoded.functionName !== "scheduleBatch") {
    die(
      `${expected.label} calls ${decoded.functionName}; expected scheduleBatch`,
    );
  }
  const [targets, values, payloads, predecessor, salt, delay] = decoded.args;
  if (
    targets.length !== expected.callCount ||
    targets.length !== values.length ||
    targets.length !== payloads.length
  ) {
    die(
      `${expected.label} inner lengths are targets=${targets.length}, values=${values.length}, payloads=${payloads.length}`,
    );
  }
  if (values.some((value) => value !== 0n)) {
    die(`${expected.label} contains a non-zero inner value`);
  }
  if (predecessor !== ZERO_BYTES32) {
    die(`${expected.label} has unexpected predecessor ${predecessor}`);
  }
  if (salt !== expected.salt)
    die(`${expected.label} has unexpected salt ${salt}`);
  if (delay !== EXPECTED_DELAY) {
    die(`${expected.label} delay is ${delay}; expected ${EXPECTED_DELAY}`);
  }

  const expectedTargets = new Set(
    expected.allowedTargets.map((address) => address.toLowerCase()),
  );
  const actualTargets = new Set(targets.map((target) => target.toLowerCase()));
  if (
    actualTargets.size !== expectedTargets.size ||
    [...actualTargets].some((target) => !expectedTargets.has(target))
  ) {
    die(
      `${expected.label} has unexpected inner targets: ${[...actualTargets].join(", ")}`,
    );
  }

  const allowedAuthoritySelectors = new Set([
    "0x67aff484", // setUserRole(address,uint8,bool)
    "0x7d40583d", // setRoleCapability(uint8,address,bytes4,bool)
    "0xc6b0263e", // setPublicCapability(address,bytes4,bool)
  ]);
  targets.forEach((target, index) => {
    const payload = payloads[index];
    const selector = payload.slice(0, 10).toLowerCase();
    if (sameAddress(target, ROLES_AUTHORITY)) {
      if (!allowedAuthoritySelectors.has(selector)) {
        die(`${expected.label} has unexpected authority selector ${selector}`);
      }
      return;
    }
    if (
      [PREDICATE_V2_HOOK, COMPLIANCE_PROXY, COMPOSER_V2].some((address) =>
        sameAddress(target, address),
      )
    ) {
      if (payload.toLowerCase() !== "0x79ba5097") {
        die(
          `${expected.label} non-authority ownership call is not acceptOwnership()`,
        );
      }
      return;
    }
    if (sameAddress(target, CCTP_RELAYER)) {
      const relayerCall = decodeFunctionData({
        abi: RELAYER_ABI,
        data: payload,
      });
      if (
        relayerCall.functionName !== "setComposer" ||
        !sameAddress(relayerCall.args[0], COMPOSER_V2) ||
        relayerCall.args[1] !== true
      ) {
        die(`${expected.label} relayer call is not setComposer(V2,true)`);
      }
      return;
    }
    die(`${expected.label} has unhandled target ${target}`);
  });

  return {
    transaction,
    label: expected.label,
    innerCallCount: targets.length,
    salt: salt as Hex,
    calldataHash,
  };
}

function implementationFromSlot(slot: Hex): Address {
  return `0x${slot.slice(-40)}` as Address;
}

async function validateOnChain(rpcUrl: string): Promise<void> {
  const client = createPublicClient({ transport: http(rpcUrl) });
  const addresses: Address[] = [
    SAFE,
    TIMELOCK,
    ROLES_AUTHORITY,
    PREDICATE_V2_HOOK,
    COMPLIANCE_PROXY,
    CCTP_RELAYER,
    COMPOSER_V1,
    COMPOSER_V2,
  ];
  const [
    rpcChainId,
    minDelay,
    complianceOperationDone,
    composerV1Enabled,
    composerV2Enabled,
    composerV1ImplementationSlot,
    composerV2ComplianceProxy,
    composerV2AssetOft,
    ...bytecodes
  ] = await Promise.all([
    client.getChainId(),
    client.readContract({
      address: TIMELOCK,
      abi: TIMELOCK_ABI,
      functionName: "getMinDelay",
    }),
    client.readContract({
      address: TIMELOCK,
      abi: TIMELOCK_ABI,
      functionName: "isOperationDone",
      args: [COMPLETED_COMPLIANCE_OPERATION_ID],
    }),
    client.readContract({
      address: CCTP_RELAYER,
      abi: RELAYER_ABI,
      functionName: "isComposer",
      args: [COMPOSER_V1],
    }),
    client.readContract({
      address: CCTP_RELAYER,
      abi: RELAYER_ABI,
      functionName: "isComposer",
      args: [COMPOSER_V2],
    }),
    client.getStorageAt({
      address: COMPOSER_V1,
      slot: ERC1967_IMPLEMENTATION_SLOT,
    }),
    client.readContract({
      address: COMPOSER_V2,
      abi: COMPOSER_ABI,
      functionName: "COMPLIANCE_PROXY",
    }),
    client.readContract({
      address: COMPOSER_V2,
      abi: COMPOSER_ABI,
      functionName: "ASSET_OFT",
    }),
    ...addresses.map((address) => client.getBytecode({ address })),
  ]);

  if (rpcChainId !== CHAIN_ID) {
    die(`PLUME_RPC_URL is on chainId ${rpcChainId}; expected ${CHAIN_ID}`);
  }
  if (minDelay !== EXPECTED_DELAY) {
    die(`timelock delay is ${minDelay}; expected ${EXPECTED_DELAY}`);
  }
  if (!complianceOperationDone) {
    die("the prerequisite ComplianceProxy timelock operation is not complete");
  }
  addresses.forEach((address, index) => {
    const code = bytecodes[index];
    if (!code || code === "0x") die(`no contract code at ${address}`);
  });
  if (!composerV1Enabled)
    die("Composer V1 is no longer enabled on the nTEST relayer");
  if (composerV2Enabled)
    die("Composer V2 is already enabled; do not queue this schedule again");
  if (!composerV1ImplementationSlot)
    die("could not read Composer V1 implementation slot");
  const composerV1Implementation = implementationFromSlot(
    composerV1ImplementationSlot,
  );
  if (!sameAddress(composerV1Implementation, COMPOSER_V1_IMPLEMENTATION)) {
    die(
      `Composer V1 implementation changed to ${composerV1Implementation}; expected untouched ${COMPOSER_V1_IMPLEMENTATION}`,
    );
  }
  if (!sameAddress(composerV2ComplianceProxy, COMPLIANCE_PROXY)) {
    die(
      `Composer V2 points to unexpected ComplianceProxy ${composerV2ComplianceProxy}`,
    );
  }
  if (!sameAddress(composerV2AssetOft, CCTP_RELAYER)) {
    die(`Composer V2 points to unexpected asset OFT ${composerV2AssetOft}`);
  }
}

async function main(): Promise<void> {
  const mode = parseMode();
  const repoRoot = path.resolve(__dirname, "..");
  const batches = BATCHES.map((batch) => validateBatch(repoRoot, batch));

  console.log("nTEST parallel Composer V2 schedule validated");
  console.log(`  chainId:       ${CHAIN_ID}`);
  console.log(`  proposer Safe: ${SAFE}`);
  console.log(`  timelock:      ${TIMELOCK}`);
  console.log(`  Composer V1:   ${COMPOSER_V1} (untouched)`);
  console.log(`  Composer V2:   ${COMPOSER_V2} (new proxy)`);
  for (const batch of batches) {
    console.log(
      `  schedule:      ${batch.label}: ${batch.innerCallCount} calls, hash ${batch.calldataHash}`,
    );
  }

  if (mode === "check") {
    console.log("  result:        local check only; nothing was submitted");
    return;
  }

  const rpcUrl = requireEnv("PLUME_RPC_URL");
  const signerKey = privateKeyFromEnv();
  const proposerAddress = privateKeyToAccount(signerKey).address;
  await validateOnChain(rpcUrl);

  const authorized = await isAuthorizedProposer(
    CHAIN_ID,
    SAFE,
    proposerAddress,
  );
  if (authorized !== true) {
    const reason =
      authorized === false
        ? "is not an owner or registered delegate"
        : "authorization could not be verified";
    die(`proposer ${proposerAddress} ${reason} for nTEST Safe ${SAFE}`);
  }

  if (mode === "preflight") {
    console.log(`  proposer:      ${proposerAddress}`);
    console.log(
      "  result:        on-chain preflight passed; nothing was submitted",
    );
    return;
  }

  console.log(`  proposer:      ${proposerAddress}`);
  console.log(
    "  submitting one Safe proposal with exactly one scheduleBatch call...",
  );
  const result = await proposeBatch({
    chainId: CHAIN_ID,
    safe: SAFE,
    txs: batches.map((batch) => batch.transaction),
    signerKey,
    rpcUrl,
  });

  console.log(`  nonce:         ${result.nonce}`);
  console.log(`  Safe tx hash:  ${result.safeTxHash}`);
  console.log(`  queued:        ${result.uiUrl}`);
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
});
