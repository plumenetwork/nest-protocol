import { test } from "node:test";
import assert from "node:assert/strict";
import { pad, toHex, type Address } from "viem";
import {
  validateAcceptanceBatch,
  assertAcceptanceResult,
} from "./prepareArcAnnouncements";

const target = "0x1111111111111111111111111111111111111111" as Address;
const safe = "0x2222222222222222222222222222222222222222" as Address;
test("acceptance messages reject changed targets, selectors, call modes, value, chain and count", () => {
  const batch = {
    chainId: 5042,
    transactions: [
      { to: target, data: "0x79ba5097", operation: "0", value: "0" },
    ],
  };
  assert.equal(validateAcceptanceBatch(batch, [target]).length, 1);
  for (const patch of [
    { to: safe },
    { data: "0x" },
    { operation: "1" },
    { value: "1" },
  ])
    assert.throws(() =>
      validateAcceptanceBatch(
        { ...batch, transactions: [{ ...batch.transactions[0], ...patch }] },
        [target],
      ),
    );
  assert.throws(() =>
    validateAcceptanceBatch({ ...batch, chainId: 1 }, [target]),
  );
  assert.throws(() =>
    validateAcceptanceBatch({ ...batch, transactions: [] }, [target]),
  );
});

test("simulation success requires Safe true plus owner and cleared pendingOwner on every target", () => {
  const slot =
    "0x341f7c713c76cb881fd7047f7cccebe3fe10eddfc5e20fe83ee7e0b505e8ea00";
  const result = {
    transaction: {
      transaction_info: {
        call_trace: { output: pad("0x01", { size: 32 }) },
        state_diff: [
          {
            raw: [
              { address: target, key: slot, dirty: pad(safe, { size: 32 }) },
              {
                address: target,
                key: toHex(BigInt(slot) + 2n, { size: 32 }),
                dirty: pad("0x00", { size: 32 }),
              },
            ],
          },
        ],
      },
    },
  };
  assertAcceptanceResult(result, [target], safe);
  const notCleared = structuredClone(result);
  notCleared.transaction.transaction_info.state_diff[0].raw.pop();
  assert.throws(
    () => assertAcceptanceResult(notCleared, [target], safe),
    /clear pendingOwner/,
  );
  const unsuccessful = structuredClone(result);
  unsuccessful.transaction.transaction_info.call_trace.output = pad("0x00", {
    size: 32,
  });
  assert.throws(
    () => assertAcceptanceResult(unsuccessful, [target], safe),
    /return true/,
  );
  assert.throws(
    () => assertAcceptanceResult(result, [target, safe], safe),
    /clear pendingOwner/,
  );
});
