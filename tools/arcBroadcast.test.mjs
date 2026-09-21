import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { createPublicClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  reconcileBroadcast,
  prepareResume,
  resumeBroadcast,
} from "./arcBroadcast.mjs";

const sender = "0x1111111111111111111111111111111111111111";
function fixture() {
  const planned = [10, 11, 12].map((nonce) => ({
    from: sender,
    to: sender,
    nonce: `0x${nonce.toString(16)}`,
    input: `0x${nonce}`,
    value: "0x0",
  }));
  const actual = planned
    .slice(0, 2)
    .map((tx, i) => ({ ...tx, hash: `hash${i}` }));
  const receipts = actual.map((tx) => ({
    transactionHash: tx.hash,
    blockNumber: "0x99",
    status: "0x1",
  }));
  const log = {
    chain: 5042,
    transactions: planned.map((transaction, i) => ({
      transaction,
      hash: i === 0 ? "hash1" : i === 1 ? "hash0" : null,
    })),
    pending: ["hash1", "hash0"],
    receipts: [],
  };
  const client = {
    getTransactionCount: async () => 12,
    request: async ({ method, params }) => {
      if (method === "eth_getTransactionReceipt")
        return receipts.find((r) => r.transactionHash === params[0]) ?? null;
      if (method === "eth_getBlockByNumber") return { transactions: actual };
      if (method === "eth_getTransactionByHash") return null;
      throw new Error(`Unexpected RPC ${method}`);
    },
  };
  return { log, client, actual, receipts };
}

test("resume repairs out-of-order hashes from exact on-chain nonce and payload, without mutating input", async () => {
  const { log, client } = fixture();
  const before = structuredClone(log);
  const result = await reconcileBroadcast(log, client, sender);
  assert.equal(result.confirmed, 2);
  assert.equal(result.remaining, 1);
  assert.equal(result.nextNonce, 12);
  assert.deepEqual(
    result.log.transactions.map((t) => t.hash),
    ["hash0", "hash1", null],
  );
  assert.deepEqual(result.log.pending, []);
  assert.equal(result.log.receipts.length, 2);
  assert.deepEqual(log, before);
});

test("resume recovers a missing saved hash only with exact block transaction and receipt evidence", async () => {
  const { log, client } = fixture();
  log.transactions[1].hash = null;
  log.pending = [];
  const result = await reconcileBroadcast(log, client, sender);
  assert.equal(result.confirmed, 2);
});

test("resume blocks a queued transaction outside the saved sequence", async () => {
  const f = fixture();
  f.log.pending.push("queued");
  const request = f.client.request;
  f.client.request = async (args) =>
    args.method === "eth_getTransactionByHash"
      ? { hash: "queued", from: sender, nonce: "0x7e", blockNumber: null }
      : request(args);
  await assert.rejects(
    reconcileBroadcast(f.log, f.client, sender),
    /nonce 126.*does not match/,
  );
});

test("resume associates a matching queued call by its actual nonce and rejects changed payloads", async () => {
  const f = fixture();
  f.log.pending.push("queued");
  const queued = {
    ...f.log.transactions[2].transaction,
    hash: "queued",
    blockNumber: null,
  };
  const request = f.client.request;
  f.client.request = async (args) =>
    args.method === "eth_getTransactionByHash" ? queued : request(args);
  const result = await reconcileBroadcast(f.log, f.client, sender);
  assert.equal(result.queued, 1);
  assert.equal(result.log.transactions[2].hash, "queued");
  assert.deepEqual(result.log.pending, ["queued"]);
  f.client.getTransactionCount = async ({ blockTag }) =>
    blockTag === "pending" ? 13 : 12;
  assert.equal((await reconcileBroadcast(f.log, f.client, sender)).queued, 1);
  queued.input = "0xffff";
  await assert.rejects(
    reconcileBroadcast(f.log, f.client, sender),
    /does not match/,
  );
});

test("resume rejects mismatched calls, missing evidence, failed receipts, nonce drift, wrong chain or sender", async () => {
  const changes = [
    (f) => {
      f.actual[0].input = "0xffff";
    },
    (f) => {
      f.actual[0].value = "0x1";
    },
    (f) => {
      f.actual.pop();
    },
    (f) => {
      f.receipts[0].status = "0x0";
    },
    (f) => {
      f.log.chain = 1;
    },
    (f) => {
      f.log.transactions[1].transaction.from = "other";
    },
    (f) => {
      f.log.transactions[1].transaction.nonce = "0xff";
    },
    (f) => {
      f.client.getTransactionCount = async () => 14;
    },
    (f) => {
      f.client.getTransactionCount = async ({ blockTag }) =>
        blockTag === "pending" ? 13 : 12;
    },
    (f) => {
      let calls = 0;
      f.client.getTransactionCount = async () => (++calls > 2 ? 13 : 12);
    },
  ];
  for (const change of changes) {
    const f = fixture();
    change(f);
    await assert.rejects(reconcileBroadcast(f.log, f.client, sender));
  }
});

test("resume preserves original log in a backup; failed validation leaves the file untouched", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "arc-resume-test-"));
  const file = path.join(dir, "run-latest.json");
  const f = fixture();
  const before = JSON.stringify(f.log);
  try {
    fs.writeFileSync(file, before);
    f.actual[0].input = "0xff";
    await assert.rejects(prepareResume(file, f.client, sender));
    assert.equal(fs.readFileSync(file, "utf8"), before);
    f.actual[0].input = "0x10";
    await prepareResume(file, f.client, sender);
    const backup = fs.readdirSync(dir).find((name) => name.endsWith(".bak"));
    assert.equal(fs.readFileSync(path.join(dir, backup), "utf8"), before);
    assert.equal(JSON.parse(fs.readFileSync(file)).receipts.length, 2);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("resume discovers matching queued hashes in timestamped logs of the same phase", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "arc-history-test-"));
  const file = path.join(dir, "run-latest.json");
  const f = fixture();
  const request = f.client.request;
  f.client.request = async (args) =>
    args.method === "eth_getTransactionByHash" &&
    args.params[0] === "historical"
      ? {
          ...f.log.transactions[2].transaction,
          hash: "historical",
          blockNumber: null,
        }
      : request(args);
  try {
    fs.writeFileSync(file, JSON.stringify(f.log));
    fs.writeFileSync(
      path.join(dir, "run-1234.json"),
      JSON.stringify({ chain: 5042, transactions: [{ hash: "historical" }] }),
    );
    fs.writeFileSync(path.join(dir, "other-1234.json"), "not this phase");
    const result = await prepareResume(file, f.client, sender);
    assert.equal(result.log.transactions[2].hash, "historical");
    assert.deepEqual(result.log.pending, ["historical"]);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test(
  "local Anvil recovery handles nonce gaps, interrupted submission, repeat resume and reverted calls",
  { timeout: 30000 },
  async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "arc-gap-test-"));
    const port = 19000 + Math.floor(Math.random() * 10000);
    const child = spawn(
      "anvil",
      ["--port", String(port), "--chain-id", "5042", "--no-mining", "--silent"],
      { stdio: "ignore" },
    );
    const client = createPublicClient({
      transport: http(`http://127.0.0.1:${port}`, { retryCount: 0 }),
    });
    // Synthetic test key; funded only in this isolated Anvil instance.
    const account = privateKeyToAccount(`0x${"01".repeat(32)}`);
    try {
      let ready = false;
      for (let i = 0; i < 100; i++) {
        try {
          if ((await client.getChainId()) === 5042) {
            ready = true;
            break;
          }
        } catch {}
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      assert.ok(ready, "Anvil starts");
      await client.request({
        method: "anvil_setBalance",
        params: [account.address, "0x56bc75e2d63100000"],
      });
      const target = "0x2222222222222222222222222222222222222222";
      const transactions = [0, 1, 2, 3].map((nonce) => ({
        hash: null,
        transaction: {
          from: account.address,
          to: target,
          nonce: `0x${nonce.toString(16)}`,
          chainId: "0x13b2",
          input: "0x",
          value: "0x1",
          gas: "0x5208",
        },
      }));
      const queuedRaw = await account.signTransaction({
        chainId: 5042,
        nonce: 2,
        to: target,
        value: 1n,
        gas: 21000n,
        type: "eip1559",
        maxFeePerGas: 10000000000n,
        maxPriorityFeePerGas: 1000000000n,
      });
      const queuedHash = await client.request({
        method: "eth_sendRawTransaction",
        params: [queuedRaw],
      });
      transactions[0].hash = queuedHash; // Reproduce Forge's misassociated hash.
      const file = path.join(dir, "run-latest.json");
      fs.writeFileSync(
        file,
        JSON.stringify({
          chain: 5042,
          transactions,
          receipts: [],
          pending: [queuedHash],
        }),
      );
      const sentNonces = [];
      const signer = {
        address: account.address,
        signTransaction: async (tx) => {
          sentNonces.push(tx.nonce);
          return account.signTransaction(tx);
        },
      };
      await resumeBroadcast(file, client, signer, {
        wait: async () => {
          await client.request({ method: "evm_mine" });
        },
      });
      assert.deepEqual(sentNonces, [0, 1, 3]);
      assert.equal(await client.getBalance({ address: target }), 4n);
      assert.equal(
        await client.getTransactionCount({ address: account.address }),
        4,
      );
      const saved = JSON.parse(fs.readFileSync(file));
      assert.equal(saved.receipts.length, 4);
      assert.deepEqual(saved.pending, []);
      assert.equal(saved.transactions[2].hash, queuedHash);
      // A second resume must not sign or send anything.
      await resumeBroadcast(file, client, signer);
      assert.deepEqual(sentNonces, [0, 1, 3]);

      const writeBatch = (nonces) =>
        fs.writeFileSync(
          file,
          JSON.stringify({
            chain: 5042,
            pending: [],
            receipts: [],
            transactions: nonces.map((nonce) => ({
              hash: null,
              transaction: {
                from: account.address,
                to: target,
                nonce: `0x${nonce.toString(16)}`,
                input: "0x",
                value: "0x1",
                gas: "0x186a0",
              },
            })),
          }),
        );
      const mine = {
        wait: async () => {
          await client.request({ method: "evm_mine" });
        },
      };

      // An older call with no hash in the log mines in a DIFFERENT block while
      // recovery is running. Locate it by historical nonce and continue once.
      writeBatch([4, 5, 6]);
      const hiddenRaw = await account.signTransaction({
        chainId: 5042,
        nonce: 5,
        to: target,
        value: 1n,
        gas: 100000n,
        type: "eip1559",
        maxFeePerGas: 10000000000n,
        maxPriorityFeePerGas: 1000000000n,
      });
      let revealed = false;
      const advancingClient = {
        ...client,
        request: async (args) => {
          const result = await client.request(args);
          if (
            !revealed &&
            args.method === "eth_getTransactionReceipt" &&
            result
          ) {
            revealed = true;
            await client.request({
              method: "eth_sendRawTransaction",
              params: [hiddenRaw],
            });
            await client.request({ method: "evm_mine" });
          }
          return result;
        },
      };
      await resumeBroadcast(file, advancingClient, signer, mine);
      assert.deepEqual(sentNonces, [0, 1, 3, 4, 6]);
      assert.equal(JSON.parse(fs.readFileSync(file)).receipts.length, 3);
      assert.equal(await client.getBalance({ address: target }), 7n);

      // RPC accepted a transaction, but the submission response was lost.
      // Its hash must already be saved, and the next resume must not sign it again.
      writeBatch([7, 8]);
      const interrupted = {
        ...client,
        request: async (args) => {
          const result = await client.request(args);
          if (args.method === "eth_sendRawTransaction") {
            const log = JSON.parse(fs.readFileSync(file));
            assert.equal(log.transactions[0].hash, result);
            assert.ok(log.pending.includes(result));
            throw new Error("Simulated lost submission response");
          }
          return result;
        },
      };
      await assert.rejects(
        resumeBroadcast(file, interrupted, signer, mine),
        /lost submission response/,
      );
      await client.request({ method: "evm_mine" });
      await resumeBroadcast(file, client, signer, mine);
      assert.deepEqual(sentNonces, [0, 1, 3, 4, 6, 7, 8]);
      assert.equal(await client.getBalance({ address: target }), 9n);

      // A reverted call is recorded and stops the sequence, including on retry.
      await client.request({
        method: "anvil_setCode",
        params: [target, "0x60006000fd"],
      });
      writeBatch([9, 10]);
      await assert.rejects(
        resumeBroadcast(file, client, signer, mine),
        /nonce 9 reverted/,
      );
      assert.deepEqual(sentNonces, [0, 1, 3, 4, 6, 7, 8, 9]);
      assert.equal(JSON.parse(fs.readFileSync(file)).receipts[0].status, "0x0");
      await assert.rejects(
        resumeBroadcast(file, client, signer, mine),
        /nonce 9 did not succeed/,
      );
      assert.deepEqual(sentNonces, [0, 1, 3, 4, 6, 7, 8, 9]);
    } finally {
      child.kill();
      fs.rmSync(dir, { recursive: true, force: true });
    }
  },
);
