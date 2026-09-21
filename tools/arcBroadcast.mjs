import fs from "node:fs";
import path from "node:path";
import { keccak256 } from "viem";

const same = (a, b) => a?.toLowerCase() === b?.toLowerCase();
const matches = (actual, planned) =>
  same(actual.from, planned.from) &&
  same(actual.to, planned.to) &&
  same(actual.input, planned.input) &&
  BigInt(actual.value ?? 0) === BigInt(planned.value ?? 0) &&
  BigInt(actual.nonce) === BigInt(planned.nonce);

/** Reconstruct only a proven successful prefix. Never infer execution from nonce alone. */
export async function reconcileBroadcast(
  log,
  client,
  sender,
  additionalHashes = [],
) {
  if (Number(log.chain) !== 5042 || !log.transactions?.length)
    throw new Error("Resume requires a saved Arc 5042 live broadcast");
  const txs = log.transactions;
  const first = Number(txs[0].transaction.nonce);
  for (const [i, tx] of txs.entries()) {
    if (
      !same(tx.transaction.from, sender) ||
      Number(tx.transaction.nonce) !== first + i ||
      (tx.transaction.chainId !== undefined &&
        Number(tx.transaction.chainId) !== 5042)
    )
      throw new Error(
        "Resume requires contiguous nonces from the pinned deployer",
      );
  }
  const latest = await client.getTransactionCount({
    address: sender,
    blockTag: "latest",
  });
  const pending = await client.getTransactionCount({
    address: sender,
    blockTag: "pending",
  });
  if (latest < first || latest > first + txs.length)
    throw new Error(
      "Deployer nonce is outside this saved broadcast; cannot resume",
    );
  const count = latest - first;
  const blocks = new Set();
  const queued = new Map();
  const knownHashes = new Set(
    [
      ...txs.map((tx) => tx.hash),
      ...(log.pending ?? []),
      ...(log.receipts ?? []).map((r) => r.transactionHash),
      ...additionalHashes,
    ].filter(Boolean),
  );
  for (const hash of knownHashes) {
    const receipt = await client.request({
      method: "eth_getTransactionReceipt",
      params: [hash],
    });
    if (receipt) blocks.add(receipt.blockNumber);
    else {
      const tx = await client.request({
        method: "eth_getTransactionByHash",
        params: [hash],
      });
      if (tx) {
        const nonce = Number(tx.nonce);
        const planned = txs[nonce - first]?.transaction;
        if (
          tx.blockNumber != null ||
          nonce < latest ||
          !planned ||
          !matches(tx, planned)
        )
          throw new Error(
            `Queued transaction ${hash} at nonce ${nonce} does not match a remaining saved call; refusing resume`,
          );
        if (queued.has(nonce) && !same(queued.get(nonce), hash))
          throw new Error(
            `Multiple queued transactions at nonce ${nonce}; refusing resume`,
          );
        queued.set(nonce, hash);
      }
    }
  }
  if (pending < latest || pending > first + txs.length)
    throw new Error(
      "Pending nonce is outside the saved sequence; refusing resume",
    );
  for (let nonce = latest; nonce < pending; nonce++) {
    if (!queued.has(nonce))
      throw new Error(
        `Unknown pending transaction at nonce ${nonce}; refusing resume`,
      );
  }
  const mined = new Map();
  const readBlock = async (block) => {
    const data = await client.request({
      method: "eth_getBlockByNumber",
      params: [block, true],
    });
    if (!data) throw new Error("Could not read a broadcast block");
    for (const tx of data.transactions) {
      if (same(tx.from, sender))
        mined.set(Number(tx.nonce), { ...tx, blockNumber: block });
    }
  };
  for (const block of blocks) await readBlock(block);
  // A submission can land even if Forge never saved its hash. Locate the block
  // by historical nonce, then verify the actual call and receipt below.
  const findMissing = async (nonce) => {
    let low = 0n;
    let high = BigInt(await client.request({ method: "eth_blockNumber" }));
    for (const [knownNonce, tx] of mined) {
      const block = BigInt(tx.blockNumber);
      if (knownNonce < nonce && block > low) low = block;
      if (knownNonce >= nonce && block < high) high = block;
    }
    while (low < high) {
      const mid = (low + high) / 2n;
      const nextNonce = await client.getTransactionCount({
        address: sender,
        blockNumber: mid,
      });
      if (nextNonce > nonce) high = mid;
      else low = mid + 1n;
    }
    await readBlock(`0x${low.toString(16)}`);
  };
  const repaired = structuredClone(log);
  repaired.receipts = [];
  repaired.pending = [];
  for (const [i, tx] of repaired.transactions.entries()) {
    if (i >= count) {
      tx.hash = queued.get(first + i) ?? null;
      if (tx.hash) repaired.pending.push(tx.hash);
      continue;
    }
    if (!mined.has(first + i)) await findMissing(first + i);
    const actual = mined.get(first + i);
    if (!actual || !matches(actual, tx.transaction))
      throw new Error(
        `Cannot prove saved transaction at nonce ${first + i} executed as intended; refusing resume`,
      );
    const receipt = await client.request({
      method: "eth_getTransactionReceipt",
      params: [actual.hash],
    });
    if (
      !receipt ||
      BigInt(receipt.status ?? 0) !== 1n ||
      !same(receipt.transactionHash, actual.hash)
    )
      throw new Error(
        `Transaction at nonce ${first + i} did not succeed; refusing resume`,
      );
    tx.hash = actual.hash;
    repaired.receipts.push(receipt);
  }
  if (
    (await client.getTransactionCount({
      address: sender,
      blockTag: "pending",
    })) !== pending ||
    (await client.getTransactionCount({
      address: sender,
      blockTag: "latest",
    })) !== latest
  )
    throw new Error(
      "Deployer nonce changed during reconciliation; stop other broadcasts and retry",
    );
  return {
    log: repaired,
    confirmed: count,
    remaining: txs.length - count,
    nextNonce: latest,
    queued: queued.size,
  };
}

export async function prepareResume(file, client, sender) {
  if (!fs.existsSync(file))
    throw new Error("No saved live broadcast to resume");
  const before = fs.readFileSync(file, "utf8");
  const result = await reconcileBroadcast(
    JSON.parse(before),
    client,
    sender,
    historicalHashes(file),
  );
  if (fs.readFileSync(file, "utf8") !== before)
    throw new Error("Broadcast log changed during reconciliation");
  const backup = `${file}.before-resume-${Date.now()}.bak`;
  fs.writeFileSync(backup, before, { flag: "wx", mode: 0o600 });
  fs.writeFileSync(file, `${JSON.stringify(result.log, null, 2)}\n`);
  console.log(
    `Resume checked: ${result.confirmed} confirmed, ${result.remaining} remaining (${result.queued} already queued); next nonce ${result.nextNonce}. Backup: ${backup}`,
  );
  return result;
}

export function historicalHashes(file) {
  const directory = path.dirname(file);
  const stem = path.basename(file).replace(/-latest\.json$/, "");
  const hashes = new Set();
  for (const name of fs.readdirSync(directory)) {
    const timestamp = name.slice(stem.length + 1, -5);
    if (
      !name.startsWith(`${stem}-`) ||
      !name.endsWith(".json") ||
      !/^\d+$/.test(timestamp)
    )
      continue;
    const log = JSON.parse(fs.readFileSync(path.join(directory, name), "utf8"));
    if (Number(log.chain) !== 5042) continue;
    for (const hash of [
      ...(log.transactions ?? []).map((tx) => tx.hash),
      ...(log.pending ?? []),
      ...(log.receipts ?? []).map((r) => r.transactionHash),
    ]) {
      if (hash) hashes.add(hash);
    }
  }
  return [...hashes];
}

/** Send the checked saved sequence in order, allowing queued calls to mine naturally. */
export async function resumeBroadcast(
  file,
  client,
  account,
  {
    wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    now = Date.now,
    timeoutMs = 180000,
  } = {},
) {
  if ((await client.getChainId()) !== 5042)
    throw new Error("Resume RPC must target Arc 5042");
  let { log, confirmed } = await prepareResume(file, client, account.address);
  let saved = fs.readFileSync(file, "utf8");
  const save = () => {
    if (fs.readFileSync(file, "utf8") !== saved)
      throw new Error(
        "Broadcast log changed; stop other deployment processes before resuming",
      );
    saved = `${JSON.stringify(log, null, 2)}\n`;
    const temporary = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(temporary, saved, { mode: 0o600 });
    fs.renameSync(temporary, file);
  };
  const extraHashes = historicalHashes(file);
  let nonceWaitDeadline;
  while (confirmed < log.transactions.length) {
    const tx = log.transactions[confirmed];
    const planned = tx.transaction;
    const nonce = Number(planned.nonce);
    if (!tx.hash) {
      const latest = await client.getTransactionCount({
        address: account.address,
        blockTag: "latest",
      });
      const pending = await client.getTransactionCount({
        address: account.address,
        blockTag: "pending",
      });
      if (latest > nonce) {
        console.log(
          `Resume: nonce advanced to ${latest}; checking calls that mined since the last receipt...`,
        );
        const result = await reconcileBroadcast(
          log,
          client,
          account.address,
          extraHashes,
        );
        log = result.log;
        confirmed = result.confirmed;
        save();
        nonceWaitDeadline = undefined;
        continue;
      }
      if (latest !== nonce || pending !== nonce) {
        nonceWaitDeadline ??= now() + timeoutMs;
        if (now() >= nonceWaitDeadline)
          throw new Error(
            `RPC nonce has not settled for ${nonce} (latest ${latest}, pending ${pending}); progress saved, retry --resume`,
          );
        console.log(
          `Resume: waiting for nonce ${nonce} (RPC latest ${latest}, pending ${pending})...`,
        );
        await wait(2000);
        continue;
      }
      nonceWaitDeadline = undefined;
      if (planned.type !== undefined && ![0, 2].includes(Number(planned.type)))
        throw new Error(`Unsupported saved transaction type at nonce ${nonce}`);
      const legacy = Number(planned.type) === 0;
      const fees = legacy
        ? { gasPrice: await client.getGasPrice() }
        : await client.estimateFeesPerGas();
      const serialized = await account.signTransaction({
        chainId: 5042,
        nonce,
        ...(planned.to ? { to: planned.to } : {}),
        data: planned.input ?? "0x",
        value: BigInt(planned.value ?? 0),
        gas: BigInt(planned.gas),
        ...(planned.accessList ? { accessList: planned.accessList } : {}),
        type: legacy ? "legacy" : "eip1559",
        ...fees,
      });
      // Persist the locally computed hash BEFORE sending: even an ambiguous RPC
      // error or interruption can then be reconciled without losing the tx identity.
      tx.hash = keccak256(serialized);
      log.pending.push(tx.hash);
      save();
      console.log(`Resume: sending nonce ${nonce} (${tx.hash})`);
      const returned = await client.request({
        method: "eth_sendRawTransaction",
        params: [serialized],
      });
      if (!same(returned, tx.hash))
        throw new Error(`RPC returned an unexpected hash at nonce ${nonce}`);
    } else {
      console.log(
        `Resume: waiting for existing transaction at nonce ${nonce} (${tx.hash})`,
      );
    }
    const deadline = now() + timeoutMs;
    let receipt;
    while (
      !(receipt = await client.request({
        method: "eth_getTransactionReceipt",
        params: [tx.hash],
      }))
    ) {
      if (now() >= deadline)
        throw new Error(
          `Timed out waiting for nonce ${nonce}; saved its hash. Retry --resume when the RPC is ready`,
        );
      await wait(2000);
    }
    const actual = await client.request({
      method: "eth_getTransactionByHash",
      params: [tx.hash],
    });
    if (
      !actual ||
      !matches(actual, planned) ||
      !same(receipt.transactionHash, tx.hash)
    )
      throw new Error(
        `Mined transaction at nonce ${nonce} does not match the saved call`,
      );
    log.receipts.push(receipt);
    log.pending = log.pending.filter((hash) => !same(hash, tx.hash));
    save();
    if (BigInt(receipt.status ?? 0) !== 1n)
      throw new Error(
        `Transaction at nonce ${nonce} reverted; stopped before the next call`,
      );
    console.log(
      `Resume: nonce ${nonce} confirmed (${log.receipts.length}/${log.transactions.length})`,
    );
    confirmed++;
  }
  console.log(
    `Arc deployment complete: ${log.receipts.length} successful transactions in this saved sequence.`,
  );
}
