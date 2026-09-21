/**
 * Core split logic for Safe Transaction Builder batches, extracted so the
 * deploy wrapper and the standalone CLI can share it.
 *
 * Inputs are explicit absolute paths (not a chain-ambiguous staging dir).
 * Outputs are written to a per-chain, per-vault subdirectory.
 */

import * as fs from "fs";
import * as path from "path";

export type SafeTx = {
  to: string;
  value: string;
  data: string;
  operation: string;
};

export type SafeBatch = {
  chainId: number | string;
  createdAt?: number;
  meta: { name: string; description: string };
  transactions: SafeTx[];
  version: string;
};

// 4-byte selector -> short pretty name.
export const SELECTOR_NAMES: Record<string, string> = {
  "0x8929565f": "setBeforeTransferHook",
  "0x7d40583d": "setRoleCapability",
  "0xc6b0263e": "setPublicCapability",
  "0x67aff484": "setUserRole",
  "0x6c6b3e8e": "setEidToDomain",
  "0x9d28fb86": "setOperatorRegistry",
  "0xb98bd070": "setEnforcedOptions",
  "0x6dbd9f90": "setConfig",
  "0x9535ff30": "setSendLibrary",
  "0x6a14d715": "setReceiveLibrary",
  "0x9623609d": "upgradeAndCall",
  "0x48ea7127": "setAccountant",
  "0x4d8be07e": "setRateProviderData",
  "0x5cf65473": "setMaxRetryableValue",
  "0x79ba5097": "acceptOwnership",
  "0xe77b36b7": "setComposer",
  "0x714ccf7b": "setVault",
  "0x3400288b": "setPeer",
  "0x1b9b0742": "setVaultApproval",
  "0x55a2d64d": "removeChain",
  "0x1bb6134c": "resetHighWaterMark",
  "0x705e10e3": "setFee",
  "0x1e15d675": "setMaxFee",
  "0xc1cc8d7f": "updateManagementFee",
  "0x4b7ea49a": "updateManagementFee",
  "0x556d18df": "updatePerformanceFee",
  "0x7ae63cf1": "setMaxFeeBasisPoints",
  "0xd5960873": "setFinalityThreshold",
};

const CAPS_SELECTORS = new Set(["0x8929565f", "0x7d40583d"]);
const ROLES_SELECTORS = new Set(["0xc6b0263e", "0x67aff484"]);
const LZ_SELECTORS = new Set([
  "0x6c6b3e8e",
  "0x9d28fb86",
  "0xb98bd070",
  "0x6dbd9f90",
  "0x9535ff30",
  "0x6a14d715",
  "0xe77b36b7",
  "0x714ccf7b",
  "0x48ea7127",
  "0x4d8be07e",
  "0x1b9b0742",
  "0x7ae63cf1",
  "0xd5960873",
]);

// LZ EID -> human name for part titles.
const EID_NAMES: Record<number, string> = {
  30101: "Ethereum",
  30102: "BSC",
  30110: "Arbitrum",
  30168: "Solana",
  30184: "Base",
  30319: "World Chain",
  30370: "Plume",
  30383: "Plasma",
};

export function selector(data: string): string {
  return data.slice(0, 10).toLowerCase();
}

export function prettyFn(data: string): string {
  return SELECTOR_NAMES[selector(data)] ?? selector(data);
}

// Mirrors script/lib/Constants.sol.
const ROLE_NAMES: Record<number, string> = {
  0: "OWNER",
  1: "STRATEGIST",
  2: "MANAGER",
  3: "TELLER",
  4: "UPDATE_EXCHANGE_RATE",
  5: "SOLVER",
  6: "PAUSER",
  7: "PREDICATE_PROXY",
  8: "DEPOSITOR",
  10: "QUEUE",
  11: "CAN_SOLVE",
  12: "COMPOSER",
  13: "RELAYER",
  14: "KEEPER",
  15: "SEIZER",
};

function roleLabel(r: number): string {
  const name = ROLE_NAMES[r];
  return name ? `${r}/${name}` : `${r}`;
}

function shortAddr(addr: string): string {
  const a = addr.toLowerCase();
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

export type AddressLabels = Map<string, string>;

const ZERO = "0x0000000000000000000000000000000000000000";
const DEAD = "0x000000000000000000000000000000000000dead";

/** Renders `label(0xabcd…1234)` when the address is known, else short addr. */
function labelOrShort(addr: string, labels?: AddressLabels): string {
  const a = addr.toLowerCase();
  if (a === ZERO || a === DEAD) return shortAddr(addr);
  const label = labels?.get(a);
  return label ? `${label}(${shortAddr(addr)})` : shortAddr(addr);
}

/**
 * Builds an address→symbolic-name map from the vault's input JSON and the
 * chain's common config. Used by the Slack renderer to label `tx.to` and any
 * address arguments (proxy in `upgradeAndCall`, target/user in role txs).
 */
export function buildAddressLabels(
  repoRoot: string,
  chainId: number,
  vault: string,
): AddressLabels {
  const labels: AddressLabels = new Map();
  const add = (addr: unknown, label: string): void => {
    if (typeof addr !== "string") return;
    const a = addr.toLowerCase();
    if (!/^0x[0-9a-f]{40}$/.test(a)) return;
    if (a === ZERO || a === DEAD) return;
    if (!labels.has(a)) labels.set(a, label);
  };

  try {
    const cfg = JSON.parse(
      fs.readFileSync(
        path.join(
          repoRoot,
          "script",
          "deployment-config",
          "vaults",
          `${vault}.json`,
        ),
        "utf8",
      ),
    );
    add(cfg?.contracts?.share, "share");
    add(cfg?.contracts?.accountant, "accountant");
    add(cfg?.contracts?.rolesAuthority, "rolesAuthority");
    for (const v of (cfg?.contracts?.vaults ?? []) as Array<{
      assetSymbol?: string;
      address?: string;
      composer?: string;
      rateProvider?: string;
      legacyTeller?: string;
      chains?: number[];
    }>) {
      if (
        Array.isArray(v.chains) &&
        v.chains.length > 0 &&
        !v.chains.includes(chainId)
      )
        continue;
      const sym = v.assetSymbol ?? "?";
      add(v.address, `vault-${sym}`);
      add(v.composer, `composer-${sym}`);
      add(v.rateProvider, `rateProvider-${sym}`);
      add(v.legacyTeller, `legacyTeller-${sym}`);
    }
  } catch {}

  try {
    const common = JSON.parse(
      fs.readFileSync(
        path.join(
          repoRoot,
          "script",
          "deployment-config",
          "common",
          `${chainId}.json`,
        ),
        "utf8",
      ),
    );
    add(common.predicateProxy, "predicateProxy");
    add(common.operatorRegistry, "operatorRegistry");
    add(common.redeemOperator, "redeemOperator");
    add(common.cctpRelayer, "cctpRelayer");
    add(common.seizer, "shareSeizer");
    add(common.blacklistHook, "blacklistHook");
    add(common.commonRolesAuthority, "commonRolesAuthority");
    add(common.nestAdapter, "nestAdapter");
    add(common.nestBundler, "nestBundler");
    add(common.nestUnlooper, "nestUnlooper");
  } catch {}

  return labels;
}

function wordAt(body: string, i: number): string {
  return body.slice(i * 64, (i + 1) * 64);
}

function wordUint(body: string, i: number): number {
  return parseInt(wordAt(body, i), 16);
}

function wordAddr(body: string, i: number): string {
  return "0x" + wordAt(body, i).slice(24);
}

function wordBytes4(body: string, i: number): string {
  return "0x" + wordAt(body, i).slice(0, 8);
}

function wordBool(body: string, i: number): boolean {
  return wordUint(body, i) !== 0;
}

/** Decode common role/caps args into a short human-readable string. */
export function prettyArgs(tx: SafeTx, labels?: AddressLabels): string {
  const s = selector(tx.data);
  const body = tx.data.slice(10);
  try {
    switch (s) {
      case "0x7d40583d": {
        // setRoleCapability(uint8 role, address target, bytes4 sig, bool enabled)
        const role = wordUint(body, 0);
        const target = wordAddr(body, 1);
        const sig = wordBytes4(body, 2);
        const enabled = wordBool(body, 3);
        return `role=${roleLabel(role)} target=${labelOrShort(target, labels)} sig=${sig} enabled=${enabled}`;
      }
      case "0xc6b0263e": {
        // setPublicCapability(address target, bytes4 sig, bool enabled)
        const target = wordAddr(body, 0);
        const sig = wordBytes4(body, 1);
        const enabled = wordBool(body, 2);
        return `target=${labelOrShort(target, labels)} sig=${sig} enabled=${enabled}`;
      }
      case "0x67aff484": {
        // setUserRole(address user, uint8 role, bool enabled)
        const user = wordAddr(body, 0);
        const role = wordUint(body, 1);
        const enabled = wordBool(body, 2);
        return `user=${labelOrShort(user, labels)} role=${roleLabel(role)} enabled=${enabled}`;
      }
      case "0x3400288b": {
        // setPeer(uint32 eid, bytes32 peer)
        const eid = wordUint(body, 0);
        const peer = "0x" + wordAt(body, 1);
        return `eid=${eid} peer=${peer}`;
      }
      case "0x55a2d64d": {
        // removeChain(uint32 chainSelector)
        const eid = wordUint(body, 0);
        const name = EID_NAMES[eid];
        return name ? `eid=${eid} (${name})` : `eid=${eid}`;
      }
      case "0x9623609d": {
        // upgradeAndCall(ITransparentUpgradeableProxy proxy, address newImpl, bytes data)
        const proxy = wordAddr(body, 0);
        const newImpl = wordAddr(body, 1);
        return `proxy=${labelOrShort(proxy, labels)} newImpl=${shortAddr(newImpl)}`;
      }
      case "0x1bb6134c": {
        // resetHighWaterMark(uint96 newHWM)
        const hwm = BigInt("0x" + wordAt(body, 0)).toString();
        return `hwm=${hwm}`;
      }
      case "0x48ea7127": {
        // setAccountant(address)
        return `accountant=${labelOrShort(wordAddr(body, 0), labels)}`;
      }
      case "0x9d28fb86": {
        // setOperatorRegistry(address)
        return `operatorRegistry=${labelOrShort(wordAddr(body, 0), labels)}`;
      }
      case "0xe77b36b7": {
        // setComposer(address,bool) — composer registry
        return `composer=${labelOrShort(wordAddr(body, 0), labels)} enabled=${wordBool(body, 1)}`;
      }
      case "0x714ccf7b": {
        // setVault(address,bool)
        return `vault=${labelOrShort(wordAddr(body, 0), labels)} enabled=${wordBool(body, 1)}`;
      }
      case "0x1b9b0742": {
        // setVaultApproval(address target, bool approved)
        return `target=${labelOrShort(wordAddr(body, 0), labels)} approved=${wordBool(body, 1)}`;
      }
      case "0x705e10e3":
      case "0x1e15d675": {
        // setFee/setMaxFee(uint8 f, (uint32 rate, uint256 flat)) — Fee struct fields are
        // static, so they're inlined after the enum: [f][rate][flat].
        const FEE_NAMES = ["InstantRedemption", "Deposit", "Redemption"];
        const f = wordUint(body, 0);
        const rate = wordUint(body, 1);
        const flat = BigInt("0x" + wordAt(body, 2)).toString();
        return `fee=${FEE_NAMES[f] ?? f} rate=${rate} flat=${flat}`;
      }
      default:
        return "";
    }
  } catch {
    return "";
  }
}

function classify(data: string): "caps" | "roles" | "lz" | "unknown" {
  const s = selector(data);
  if (CAPS_SELECTORS.has(s)) return "caps";
  if (ROLES_SELECTORS.has(s)) return "roles";
  if (LZ_SELECTORS.has(s)) return "lz";
  return "unknown";
}

function extractEid(data: string): number | null {
  const body = data.slice(10);
  for (let i = 0; i + 64 <= body.length; i += 64) {
    const word = body.slice(i, i + 64);
    if (
      !word.startsWith(
        "000000000000000000000000000000000000000000000000000000000000",
      )
    )
      continue;
    const v = parseInt(word.slice(56), 16);
    if (v >= 30000 && v < 40000) return v;
  }
  return null;
}

function eidLabel(eid: number): string {
  return EID_NAMES[eid] ?? `eid=${eid}`;
}

export function readBatch(p: string): SafeBatch {
  const raw = fs.readFileSync(p, "utf8");
  const batch = JSON.parse(raw) as SafeBatch;
  // SafeBatchSerialize.sol occasionally emits `"transactions": "[{...}]"` stringified
  // when the batch is small; unwrap defensively.
  if (
    typeof (batch as unknown as { transactions: unknown }).transactions ===
    "string"
  ) {
    batch.transactions = JSON.parse(batch.transactions as unknown as string);
  }
  if (!Array.isArray(batch.transactions)) {
    throw new Error(`${p}: transactions is not an array after parse`);
  }
  return batch;
}

/**
 * Reads a forge batch, or returns an empty batch when the file is absent.
 * A script that queues zero txs writes no file (BaseConfigScript.writeMsigBatch
 * early-returns when `serializedTxs.length == 0`) — e.g. a fully idempotent
 * TransferOwnership where everything is already owned by the new owner. That is
 * a valid "nothing to do" outcome, not a failure, so treat the missing file as
 * an empty batch for this chain.
 */
export function readBatchOrEmpty(p: string, chainId: number): SafeBatch {
  if (!fs.existsSync(p)) {
    return {
      chainId: String(chainId),
      createdAt: Date.now(),
      meta: { name: "", description: "" },
      transactions: [],
      version: "1.0",
    };
  }
  return readBatch(p);
}

function writeBatch(p: string, batch: SafeBatch): void {
  fs.writeFileSync(p, JSON.stringify(batch, null, 2) + "\n", "utf8");
}

function makeBatch(source: SafeBatch, name: string, txs: SafeTx[]): SafeBatch {
  return {
    chainId: source.chainId,
    createdAt: Date.now(),
    meta: { name, description: "" },
    transactions: txs,
    version: source.version ?? "1.0",
  };
}

export type SplitSection = {
  slot: "1a" | "1b" | "2a" | "2b" | "3" | "4";
  file: string;
  title: string;
  batch: SafeBatch;
};

export type SplitResult = {
  outDir: string;
  sections: SplitSection[];
  eidsLabel: string;
  hasUpgrade: boolean;
};

export type SplitOptions = {
  deployPath: string;
  ownerPath: string;
  upgradePath?: string;
  feesPath?: string;
  chainId: number;
  vault: string;
  outDir: string;
};

/**
 * Split DeployAndSetup + TransferOwnership + (optional) Upgrade + (optional)
 * SetupFees batches into the ordered slots. Upgrade is optional: when the
 * Upgrade script queued no txs it writes no file, and part 2a carries only
 * vaultLzTxs + CCTP preamble. SetupFees is optional too — when the vault config
 * declares no non-zero fees the script writes no file and slot 4 is dropped.
 * Fees go LAST (slot 4): setFee/setMaxFee are owner/authority-gated, so they
 * must execute after part 1a/1b grant the roles and part 3 accepts ownership.
 */
export function splitBatches(opts: SplitOptions): SplitResult {
  const {
    deployPath,
    ownerPath,
    upgradePath,
    feesPath,
    chainId,
    vault,
    outDir,
  } = opts;

  const deploy = readBatchOrEmpty(deployPath, chainId);
  const owner = readBatchOrEmpty(ownerPath, chainId);
  const upgrade =
    upgradePath && fs.existsSync(upgradePath) ? readBatch(upgradePath) : null;
  const fees = feesPath && fs.existsSync(feesPath) ? readBatch(feesPath) : null;

  // Sanity: source batches must target the same chain.
  if (Number(deploy.chainId) !== chainId || Number(owner.chainId) !== chainId) {
    throw new Error(
      `chainId mismatch: deploy=${deploy.chainId} owner=${owner.chainId} expected=${chainId}`,
    );
  }
  if (upgrade && Number(upgrade.chainId) !== chainId) {
    throw new Error(
      `chainId mismatch: upgrade=${upgrade.chainId} expected=${chainId}`,
    );
  }
  if (fees && Number(fees.chainId) !== chainId) {
    throw new Error(
      `chainId mismatch: fees=${fees.chainId} expected=${chainId}`,
    );
  }

  const d = deploy.transactions;
  const capsTxs: SafeTx[] = [];
  const rolesTxs: SafeTx[] = [];
  const lzTxs: SafeTx[] = [];
  const unknownIdx: number[] = [];
  d.forEach((tx, i) => {
    switch (classify(tx.data)) {
      case "caps":
        capsTxs.push(tx);
        break;
      case "roles":
        rolesTxs.push(tx);
        break;
      case "lz":
        lzTxs.push(tx);
        break;
      default:
        unknownIdx.push(i);
        break;
    }
  });
  if (unknownIdx.length > 0) {
    throw new Error(
      `unknown selectors at indices ${unknownIdx.join(",")} in ${deployPath} — add to SELECTOR_NAMES + classify()`,
    );
  }

  const VAULT_DEP_SELECTORS = new Set([
    "0x9d28fb86",
    "0xb98bd070",
    "0xe77b36b7",
    "0x714ccf7b",
    "0x48ea7127",
    "0x4d8be07e",
    "0x1b9b0742",
    "0x7ae63cf1",
    "0xd5960873",
  ]);
  const ENDPOINT_SELECTORS = new Set([
    "0x6dbd9f90",
    "0x9535ff30",
    "0x6a14d715",
  ]);

  const vaultLzTxs: SafeTx[] = [];
  const endpointLzTxs: SafeTx[] = [];
  const eidSet = new Set<number>();
  for (const tx of lzTxs) {
    const s = selector(tx.data);
    const eid = extractEid(tx.data);
    if (eid !== null) eidSet.add(eid);
    if (s === "0x6c6b3e8e" || VAULT_DEP_SELECTORS.has(s)) {
      vaultLzTxs.push(tx);
    } else if (ENDPOINT_SELECTORS.has(s)) {
      endpointLzTxs.push(tx);
    } else {
      throw new Error(`unclassified LZ selector ${s}`);
    }
  }

  const rejoinedCount =
    capsTxs.length + rolesTxs.length + vaultLzTxs.length + endpointLzTxs.length;
  if (rejoinedCount !== d.length) {
    throw new Error(
      `round-trip count mismatch: classified=${rejoinedCount} vs source=${d.length}`,
    );
  }

  const upgradeTxs = upgrade ? upgrade.transactions : [];
  const part2aTxs = [...upgradeTxs, ...vaultLzTxs];
  const eidsLabel =
    [...eidSet]
      .sort((a, b) => a - b)
      .map(eidLabel)
      .join(", ") || "none";

  // Wipe stale outputs.
  if (fs.existsSync(outDir)) {
    for (const f of fs.readdirSync(outDir)) {
      if (f.endsWith(".json")) fs.unlinkSync(path.join(outDir, f));
    }
  }
  fs.mkdirSync(outDir, { recursive: true });

  const allSections: SplitSection[] = [
    {
      slot: "1a",
      file: "part-1a-authority-role-caps.json",
      title: `Part 1a — Authority: role capabilities (${vault})`,
      batch: makeBatch(
        deploy,
        `${vault} Part 1a — Authority role caps`,
        capsTxs,
      ),
    },
    {
      slot: "1b",
      file: "part-1b-authority-public-user-roles.json",
      title: `Part 1b — Authority: public capabilities + user roles (${vault})`,
      batch: makeBatch(
        deploy,
        `${vault} Part 1b — Public caps + user roles`,
        rolesTxs,
      ),
    },
    {
      slot: "2a",
      file: upgrade
        ? "part-2a-upgrade-and-vault-wiring.json"
        : "part-2a-vault-wiring.json",
      title: upgrade
        ? `Part 2a — Upgrade + vault rewiring (accountant, operator registry, enforced options, CCTP) (${vault})`
        : `Part 2a — Vault wiring (accountant, operator registry, enforced options, CCTP) (${vault})`,
      batch: makeBatch(
        upgrade ?? deploy,
        upgrade
          ? `${vault} Part 2a — Upgrade + vault wiring`
          : `${vault} Part 2a — Vault wiring`,
        part2aTxs,
      ),
    },
    {
      slot: "2b",
      file: "part-2b-lz-endpoint-config.json",
      title: `Part 2b — LayerZero endpoint config: DVN configs + send/receive libraries for ${eidsLabel} (${vault})`,
      batch: makeBatch(
        deploy,
        `${vault} Part 2b — LZ endpoint config`,
        endpointLzTxs,
      ),
    },
    {
      slot: "3",
      file: "part-3-accept-ownership.json",
      title: `Part 3 — Accept ownership (${vault})`,
      batch: makeBatch(
        owner,
        `${vault} Part 3 — Accept ownership`,
        owner.transactions,
      ),
    },
    {
      slot: "4",
      file: "part-4-fees.json",
      title: `Part 4 — Vault & accountant fees (${vault})`,
      batch: makeBatch(
        fees ?? deploy,
        `${vault} Part 4 — Fees`,
        fees ? fees.transactions : [],
      ),
    },
  ];

  const sections = allSections.filter((s) => s.batch.transactions.length > 0);

  for (const s of sections) {
    writeBatch(path.join(outDir, s.file), s.batch);
  }

  return { outDir, sections, eidsLabel, hasUpgrade: upgrade !== null };
}

/**
 * Resolve the three forge-output paths for a given vault-chain. Forge writes
 * to flat `script/output/msig/`; an older archive lived at
 * `script/output/msig/{vault}/` and is still checked per-file as a fallback.
 * Upgrade path is returned regardless of existence — caller checks.
 */
export function resolveBatchPaths(
  repoRoot: string,
  chainId: number,
  vault: string,
): {
  deployPath: string;
  upgradePath: string;
  ownerPath: string;
  feesPath: string;
} {
  const prefix = `${chainId}-${vault}`;
  return {
    deployPath: pickBatchPath(repoRoot, vault, `${prefix}-DeployAndSetup.json`),
    upgradePath: pickBatchPath(repoRoot, vault, `${prefix}-Upgrade-vault.json`),
    ownerPath: pickBatchPath(
      repoRoot,
      vault,
      `${prefix}-TransferOwnership-AcceptOwnership.json`,
    ),
    feesPath: pickBatchPath(repoRoot, vault, `${prefix}-SetupFees.json`),
  };
}

export function splitOutDir(
  repoRoot: string,
  chainId: number,
  vault: string,
): string {
  return path.join(
    repoRoot,
    "script",
    "output",
    "msig",
    "split",
    `${chainId}-${vault}`,
  );
}

/**
 * Prefer the flat path (where Forge's SafeBatchSerialize writes today); fall
 * back to the legacy per-vault subdir if that specific file exists there.
 */
function pickBatchPath(
  repoRoot: string,
  vault: string,
  filename: string,
): string {
  const flat = path.join(repoRoot, "script", "output", "msig");
  const flatPath = path.join(flat, filename);
  if (fs.existsSync(flatPath)) return flatPath;
  const subPath = path.join(flat, vault, filename);
  if (fs.existsSync(subPath)) return subPath;
  return flatPath;
}

// ─── Slack template ──────────────────────────────────────────────────

export type SlackSectionInput = {
  title: string;
  batch: SafeBatch;
  /** Real per-tx UI URL once proposed, or `<skipped>` / `<empty>`. */
  txUrl: string;
  /** Slot id ("1a" | "1b" | "2a" | "2b" | "3"), used to build the header narrative. */
  slot?: SplitSection["slot"];
  /** Shared Tenderly simulation URL covering the whole batch (one per slot). */
  simUrl?: string;
};

export function formatSlackSection(
  input: SlackSectionInput,
  labels?: AddressLabels,
): string {
  const { title, batch, txUrl, simUrl } = input;
  const lines = batch.transactions.map((tx, i) => {
    const args = prettyArgs(tx, labels);
    const suffix = args ? ` ${args}` : "";
    return `[${i}] ${prettyFn(tx.data)}${suffix} -> ${labelOrShort(tx.to, labels)}`;
  });
  return [
    `*${title}*`,
    "```",
    ...(lines.length > 0 ? lines : ["(empty)"]),
    "```",
    `Transaction: ${txUrl}`,
    `Simulation: ${simUrl ?? "<paste Tenderly / Den simulation URL>"}`,
  ].join("\n");
}

export type SlackTemplateInput = {
  chainName: string;
  vault: string;
  eidsLabel: string;
  sections: SlackSectionInput[];
  hasUpgrade: boolean;
  /**
   * When true, all sections execute as one Safe tx (one queue entry, one sim).
   * Template renders a single combined block listing every tx grouped by slot,
   * with a single Transaction / Simulation pair at the bottom.
   */
  merged?: boolean;
  /**
   * Address→symbolic-name lookup applied to `tx.to` and address arguments
   * (upgradeAndCall proxy, setRoleCapability target, setUserRole user, …).
   * Built via `buildAddressLabels(repoRoot, chainId, vault)`.
   */
  labels?: AddressLabels;
};

type BlurbCtx = { eidsLabel: string; hasUpgrade: boolean };

const SLOT_BLURBS: Record<
  NonNullable<SlackSectionInput["slot"]>,
  (ctx: BlurbCtx) => string
> = {
  "1a": () => "1a configures role capabilities on the RolesAuthority",
  "1b": () =>
    "1b configures public capabilities and user roles on the RolesAuthority",
  "2a": ({ hasUpgrade }) =>
    hasUpgrade
      ? "2a upgrades implementations and rewires vault-side state (accountant, operator registry, enforced options, CCTP domain mapping)"
      : "2a rewires vault-side state (accountant, operator registry, enforced options, CCTP domain mapping)",
  "2b": ({ eidsLabel }) =>
    `2b sets the LZ endpoint DVN configs and send/receive libraries for ${eidsLabel}`,
  "3": () => "3 accepts ownership on newly deployed proxies",
  "4": () =>
    "4 converges vault deposit/redemption/instant-redemption fees (and accountant management/performance fees)",
};

function buildNarrative(sections: SlackSectionInput[], ctx: BlurbCtx): string {
  const parts = sections
    .map((s) => (s.slot ? SLOT_BLURBS[s.slot](ctx) : null))
    .filter((x): x is string => x !== null);
  return parts.length > 0 ? parts.join(". ") + "." : "";
}

export function formatSlackTemplate(input: SlackTemplateInput): string {
  const { chainName, vault, eidsLabel, sections, hasUpgrade, merged, labels } =
    input;
  const headline = hasUpgrade
    ? `Deploy, Upgrade, Wiring & Accept Ownership for ${vault} on ${chainName}`
    : `Deploy, Wiring & Accept Ownership for ${vault} on ${chainName}`;
  const lines: string[] = [];
  lines.push(`:signed: @nestowners @Ruan`);
  lines.push(headline);
  lines.push("");

  const nonEmpty = sections.filter((s) => s.batch.transactions.length > 0);

  if (merged) {
    const totalTxs = nonEmpty.reduce(
      (n, s) => n + s.batch.transactions.length,
      0,
    );
    lines.push(
      `1 Safe tx (${totalTxs} inner calls) covering ${nonEmpty
        .map((s) => s.slot)
        .filter(Boolean)
        .join(" + ")}. ${buildNarrative(sections, { eidsLabel, hasUpgrade })}`,
    );
    lines.push("");
    lines.push("```");
    let idx = 0;
    for (const s of nonEmpty) {
      lines.push(`# ${s.title}`);
      for (const tx of s.batch.transactions) {
        const args = prettyArgs(tx, labels);
        const suffix = args ? ` ${args}` : "";
        lines.push(
          `[${idx}] ${prettyFn(tx.data)}${suffix} -> ${labelOrShort(tx.to, labels)}`,
        );
        idx += 1;
      }
    }
    lines.push("```");
    const first = nonEmpty[0];
    lines.push(`Transaction: ${first?.txUrl ?? "<none>"}`);
    lines.push(
      `Simulation: ${first?.simUrl ?? "<paste Tenderly / Den simulation URL>"}`,
    );
  } else {
    lines.push(
      `${sections.length} Safe batches that must execute in nonce order. ${buildNarrative(sections, { eidsLabel, hasUpgrade })}`,
    );
    lines.push("");
    for (const s of sections) {
      lines.push(formatSlackSection(s, labels));
      lines.push("");
    }
  }

  return lines.join("\n");
}
