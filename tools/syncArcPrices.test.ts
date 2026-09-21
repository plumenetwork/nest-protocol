import { test } from "node:test";
import assert from "node:assert/strict";
import { checkRateUpdate, assertSpokeCode, runSync } from "./syncArcPrices";

const state = {
  exchangeRate: 1_003_743n,
  allowedExchangeRateChangeUpper: 1_001_000,
  allowedExchangeRateChangeLower: 999_000,
  lastUpdateTimestamp: 1000n,
  minimumUpdateDelayInSeconds: 3600,
  isPaused: false,
};

test("mirror checks use Solidity floor rounding, allow decreases, and honor the update delay", () => {
  assert.equal(checkRateUpdate(state, 1_004_560n, 4600n), true);
  assert.equal(checkRateUpdate(state, 1_003_000n, 4600n), true);
  assert.equal(checkRateUpdate(state, 1_004_746n, 4600n), true);
  assert.equal(checkRateUpdate(state, 1_002_739n, 4600n), true);
  assert.throws(
    () => checkRateUpdate(state, 1_004_747n, 4600n),
    /outside Arc bounds/,
  );
  assert.throws(
    () => checkRateUpdate(state, 1_002_738n, 4600n),
    /outside Arc bounds/,
  );
  assert.throws(() => checkRateUpdate(state, 1_004_560n, 4599n), /delay/);
});

test("paused and invalid rates fail; equal rates need no timestamp update", () => {
  assert.equal(checkRateUpdate(state, state.exchangeRate, 1001n), false);
  assert.throws(
    () =>
      checkRateUpdate({ ...state, isPaused: true }, state.exchangeRate, 4600n),
    /paused/,
  );
  for (const rate of [0n, -1n, 1n << 96n])
    assert.throws(() => checkRateUpdate(state, rate, 4600n), /uint96/);
});

test("implementation matching tolerates only compiler declared immutable bytes", () => {
  const artifact = {
    deployedBytecode: {
      object: "0x60000061",
      immutableReferences: { a: [{ start: 1, length: 2 }] },
    },
  };
  assert.doesNotThrow(() => assertSpokeCode("0x60abcd61", artifact));
  assert.throws(
    () => assertSpokeCode("0x60abcd62", artifact),
    /does not match/,
  );
  assert.throws(
    () => assertSpokeCode("0x60abcd6100", artifact),
    /does not match/,
  );
});

test("all vaults preflight before any broadcast; failure and dry run never send", async () => {
  const order: string[] = [];
  const check = async (item: string) => {
    order.push(`check ${item}`);
  };
  const send = async (item: string) => {
    order.push(`send ${item}`);
  };
  await runSync(["a", "b"], check, send, true);
  assert.deepEqual(order, ["check a", "check b", "send a", "send b"]);
  order.length = 0;
  await runSync(["a", "b"], check, send, false);
  assert.deepEqual(order, ["check a", "check b"]);
  order.length = 0;
  await assert.rejects(
    runSync(
      ["a", "b"],
      async (item) => {
        if (item === "b") throw new Error("blocked");
        await check(item);
      },
      send,
      true,
    ),
    /blocked/,
  );
  assert.deepEqual(order, ["check a"]);
});
