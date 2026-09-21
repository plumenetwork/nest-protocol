import { test } from "node:test";
import assert from "node:assert/strict";
import { decodeFunctionData, pad, type Address } from "viem";
import {
  AUTH_ABI,
  SIGNATURES,
  assertNonceAvailable,
  assertSimulation,
  buildCalls,
  loadVaults,
  publicCapabilitySlot,
  signerMessage,
} from "./queueArcRedemptions";
import type { ProposeResult } from "./safePropose";

const vaults = loadVaults();
const safe = "0xa08A0Dc480BD60d1d56C8Eec6c722125eAfEa982" as Address;
const prepared = {
  nonce: 7,
  safeTxHash: `0x${"ab".repeat(32)}`,
  uiUrl: "https://app.safe.global/transactions/tx?safe=arc:test",
} as ProposeResult;

test("batch enables exactly the four standard redemption selectors on each Arc vault", () => {
  assert.deepEqual(
    vaults.map((v) => v.symbol),
    ["nOPAL", "nFALCON", "FACTOR"],
  );
  const calls = buildCalls(vaults);
  assert.equal(calls.length, 12);
  // Selector values are pinned independently of the generator's signature list.
  const expected = ["0x7d41c86e", "0x77a84317", "0x33c1d930", "0x62b4aab0"];
  for (const [i, call] of calls.entries()) {
    assert.equal(call.to, vaults[Math.floor(i / 4)].authority);
    assert.equal(call.value, "0");
    assert.equal(call.operation, "0");
    const decoded = decodeFunctionData({
      abi: AUTH_ABI,
      data: call.data as `0x${string}`,
    });
    assert.equal(decoded.functionName, "setPublicCapability");
    if (decoded.functionName !== "setPublicCapability")
      throw new Error("Wrong method");
    assert.equal(
      decoded.args[0].toLowerCase(),
      vaults[Math.floor(i / 4)].vault.toLowerCase(),
    );
    assert.equal(decoded.args[1], expected[i % 4]);
    assert.equal(decoded.args[2], true);
  }
});

function simulation() {
  return {
    simulation: { status: true },
    transaction: {
      status: true,
      transaction_info: {
        call_trace: { output: pad("0x01", { size: 32 }) },
        state_diff: vaults.map((v) => ({
          raw: SIGNATURES.map((s) => ({
            address: v.authority,
            key: publicCapabilitySlot(v.vault, s),
            original: pad("0x00", { size: 32 }),
            dirty: pad("0x01", { size: 32 }),
          })),
        })),
      },
    },
  };
}
test("simulation requires Safe success and all 12 storage grants", () => {
  assert.doesNotThrow(() => assertSimulation(simulation(), vaults));
  const missing = simulation();
  missing.transaction.transaction_info.state_diff[0].raw.pop();
  assert.throws(() => assertSimulation(missing, vaults), /storage changes/);
  const falseReturn = simulation();
  falseReturn.transaction.transaction_info.call_trace.output = pad("0x00", {
    size: 32,
  });
  assert.throws(() => assertSimulation(falseReturn, vaults), /return true/);
  const failed = simulation();
  failed.simulation.status = false;
  assert.throws(() => assertSimulation(failed, vaults), /successfully/);
  const unchanged = simulation();
  unchanged.transaction.transaction_info.state_diff[0].raw[0].dirty = pad(
    "0x00",
    { size: 32 },
  );
  assert.throws(() => assertSimulation(unchanged, vaults), /Missing public/);
  const extra = simulation();
  extra.transaction.transaction_info.state_diff[0].raw.push({
    address: vaults[0].authority,
    key: publicCapabilitySlot(vaults[0].vault, "deposit(uint256,address)"),
    original: pad("0x00", { size: 32 }),
    dirty: pad("0x01", { size: 32 }),
  });
  assert.throws(() => assertSimulation(extra, vaults), /Unexpected authority/);
});
test("nonce protection rejects consumed, competing and stale preparations but permits exact retries", () => {
  const hash = prepared.safeTxHash;
  assert.doesNotThrow(() => assertNonceAvailable(3, 7, 7, undefined, [], hash));
  assert.doesNotThrow(() =>
    assertNonceAvailable(
      3,
      8,
      7,
      { isExecuted: false },
      [{ safeTxHash: hash }],
      hash,
    ),
  );
  assert.throws(
    () => assertNonceAvailable(8, 8, 7, undefined, [], hash),
    /consumed/,
  );
  assert.throws(
    () => assertNonceAvailable(3, 8, 7, undefined, [], hash),
    /occupied/,
  );
  assert.throws(
    () =>
      assertNonceAvailable(
        3,
        7,
        7,
        undefined,
        [{ safeTxHash: `0x${"cd".repeat(32)}` }],
        hash,
      ),
    /occupied/,
  );
  assert.throws(
    () => assertNonceAvailable(3, 7, 7, { isExecuted: true }, [], hash),
    /executed/,
  );
});
test("signer message declares every selector, target, operation and value with the reviewed hash", () => {
  const journal = {
    symbol: "Arc public redemptions",
    safe,
    batchHash: `0x${"cd".repeat(32)}` as `0x${string}`,
    prepared,
    proposed: false,
    simulation: "https://dashboard.tenderly.co/shared/simulation/test",
  };
  const message = signerMessage(vaults, journal);
  assert.ok(message.startsWith(":signed: @nestowners\n"));
  assert.equal(message.match(/grammar: nest-signer-message\/1/g)?.length, 1);
  assert.equal(
    message.match(
      /op=call value=0 sig=setPublicCapability\(address,bytes4,bool\)/g,
    )?.length,
    12,
  );
  for (const signature of SIGNATURES)
    assert.equal(message.split(`functionSig=${signature},`).length - 1, 3);
  assert.ok(message.includes(`Expected SafeTxHash: ${prepared.safeTxHash}`));
  assert.ok(message.includes("<paste Safe tx URL after --submit>"));
  assert.ok(!message.includes("acceptOwnership"));
  assert.ok(
    signerMessage(vaults, { ...journal, proposed: true }).includes(
      `Transaction: ${prepared.uiUrl}`,
    ),
  );
});
