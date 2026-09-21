import { test } from "node:test";
import assert from "node:assert/strict";
import {
  requireNominations,
  simulateAndSubmit,
  signerMessage,
} from "./proposeArc";
import { arcSafeService } from "./safeTxService";
import type { ProposeResult } from "./safePropose";
import { zeroAddress } from "viem";

const safe = "0x1111111111111111111111111111111111111111" as const;
const target = "0x2222222222222222222222222222222222222222" as const;
const url = "https://dashboard.tenderly.co/shared/simulation/test";
const prepared: ProposeResult = {
  safeTxHash: `0x${"ab".repeat(32)}`,
  uiUrl: "https://safe.example/transactions/tx?id=test",
  nonce: 3,
  proposed: false,
  proposerAddress: safe,
  multiSendAddress: target,
  safeVersion: "1.3.0",
  transactionData: {
    to: target,
    value: "0",
    data: "0x",
    operation: 1,
    safeTxGas: "0",
    baseGas: "0",
    gasPrice: "0",
    gasToken: zeroAddress,
    refundReceiver: zeroAddress,
    nonce: 3,
  },
};
const state = () => ({
  symbol: "nOPAL",
  safe,
  batchHash: `0x${"cd".repeat(32)}` as `0x${string}`,
  prepared,
  proposed: false,
  simulation: undefined as string | undefined,
});

test("Arc uses official Safe defaults and validates optional URL overrides", () => {
  assert.deepEqual(arcSafeService({}), {
    api: "https://api.safe.global/tx-service/arc/api",
    uiBase: "https://app.safe.global",
    slug: "arc",
    splitBatches: false,
  });
  const env = {
    ARC_SAFE_TX_SERVICE_URL: "https://tx.example/api/",
    ARC_SAFE_UI_URL: "https://safe.example/",
  };
  assert.deepEqual(arcSafeService(env), {
    api: "https://tx.example/api",
    uiBase: "https://safe.example",
    slug: "arc",
    splitBatches: false,
  });
  for (const value of [
    "http://tx.example/api",
    "https://user:secret@tx.example/api",
    "https://tx.example/api?key=secret",
  ])
    assert.throws(() =>
      arcSafeService({ ...env, ARC_SAFE_TX_SERVICE_URL: value }),
    );
});

test("acceptance requires actual Safe nomination, never a simulated or already-complete handoff", () => {
  requireNominations([{ to: target, owner: target, pendingOwner: safe }], safe);
  assert.throws(
    () =>
      requireNominations(
        [{ to: target, owner: target, pendingOwner: zeroAddress }],
        safe,
      ),
    /handoff first/,
  );
  assert.throws(
    () =>
      requireNominations(
        [{ to: target, owner: safe, pendingOwner: safe }],
        safe,
      ),
    /already Safe-owned/,
  );
});

test("failed or unavailable simulation cannot submit", async () => {
  for (const simulate of [
    async () => {
      throw new Error("reverted");
    },
    async () => "",
    async () => "https://wrong.example/",
  ]) {
    let submitted = false;
    await assert.rejects(
      simulateAndSubmit(
        state(),
        {
          simulate,
          save: () => {},
          submit: async () => {
            submitted = true;
            return prepared;
          },
        },
        false,
      ),
    );
    assert.equal(submitted, false);
  }
});

test("simulate/save precede submission; retry and dry-run do not duplicate a proposal", async () => {
  const journal = state();
  const order: string[] = [];
  const deps = {
    simulate: async () => {
      order.push("simulate");
      return url;
    },
    save: () =>
      order.push(journal.proposed ? "save-proposed" : "save-simulated"),
    submit: async () => {
      order.push("submit");
      return prepared;
    },
  };
  await simulateAndSubmit(journal, deps, false);
  assert.deepEqual(order, [
    "simulate",
    "save-simulated",
    "submit",
    "save-proposed",
  ]);
  order.length = 0;
  await simulateAndSubmit(journal, deps, false);
  assert.ok(!order.includes("submit"));
  order.length = 0;
  await simulateAndSubmit(state(), deps, true);
  assert.ok(!order.includes("submit"));
});

test("submission failures preserve simulation and do not claim successful proposal", async () => {
  const journal = state();
  await assert.rejects(
    simulateAndSubmit(
      journal,
      {
        simulate: async () => url,
        save: () => {},
        submit: async () => {
          throw new Error("service failed");
        },
      },
      false,
    ),
    /service failed/,
  );
  assert.equal(journal.proposed, false);
  assert.equal(journal.simulation, url);
});

test("signer message uses Markdown and final hash, nonce and real proposal/simulation links", () => {
  const journal = { ...state(), proposed: true, simulation: url };
  const message = signerMessage(
    journal,
    [{ to: target, data: "0x79ba5097", operation: "0", value: "0" }],
    ["nOPAL.share"],
    0,
  );
  for (const text of [
    "**Queue 1",
    prepared.safeTxHash,
    "nonce 3",
    `[View Safe transaction](${prepared.uiUrl})`,
    `[View Tenderly simulation](${url})`,
    "op=call value=0 sig=acceptOwnership()",
    "no target ownership overrides",
  ])
    assert.ok(message.includes(text));
  assert.ok(
    !signerMessage({ ...journal, proposed: false }, [], [], 0).includes(
      prepared.uiUrl,
    ),
  );
});
