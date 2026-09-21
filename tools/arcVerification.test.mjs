import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  verifierConfig,
  verifierArgs,
  phaseBroadcastRoot,
  completedTransactions,
  assertCompletedBroadcast,
  checkVerifierAccess,
  loginToExplorer,
  VerifierRateLimitError,
} from "./arcVerification.mjs";

const hash = `0x${"12".repeat(32)}`;
const complete = () => ({
  chain: 5042,
  pending: [],
  transactions: [{ hash }],
  receipts: [{ transactionHash: hash, status: "0x1" }],
});

test("Arc defaults to its Blockscout API; credentials never enter CLI arguments", () => {
  const config = verifierConfig({ ARC_VERIFIER_API_KEY: "secret" });
  assert.equal(config.name, "blockscout");
  assert.equal(config.url, "https://explorer.arc.io/api/");
  assert.equal(config.key, "secret");
  assert.ok(!verifierArgs(config).includes("secret"));
  assert.equal(
    verifierConfig({ ARC_VERIFIER_URL: "https://custom.example/api" }).url,
    "https://custom.example/api",
  );
});

test("rejects wrong-chain/testnet endpoints and missing custom-verifier credentials", () => {
  for (const env of [
    { ARC_VERIFIER_URL: "https://testnet.arcscan.app/api/" },
    { ARC_VERIFIER_URL: "https://api.example/api?chainid=5042002" },
    { ARC_VERIFIER_URL: "file:///tmp/api" },
    {
      ARC_VERIFIER: "etherscan",
      ARC_VERIFIER_URL: "https://api.example/api?chainid=5042",
    },
    { ARC_VERIFIER: "unknown" },
  ])
    assert.throws(() => verifierConfig(env));
});

test("each vault and phase has an isolated broadcast log root", () => {
  const paths = [
    phaseBroadcastRoot("/repo", "common"),
    ...["nOPAL", "nFALCON", "FACTOR"].map((v) =>
      phaseBroadcastRoot("/repo", "vault", v),
    ),
  ];
  assert.equal(new Set(paths).size, 4);
});

test("verification-only rejects partial, pending, failed or wrong-chain runs", () => {
  assert.deepEqual(completedTransactions(complete()), [hash]);
  for (const log of [
    { ...complete(), chain: 1 },
    { ...complete(), pending: [hash] },
    { ...complete(), receipts: [] },
    { ...complete(), transactions: [{ hash: null }] },
    { ...complete(), receipts: [{ transactionHash: hash, status: "0x0" }] },
    { ...complete(), transactions: [] },
  ])
    assert.throws(() => completedTransactions(log));
});

test("verification-only independently checks live transaction receipts", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "arc-verification-test-"));
  const file = path.join(dir, "run.json");
  fs.writeFileSync(file, JSON.stringify(complete()));
  try {
    let calls = 0;
    await assertCompletedBroadcast(file, {
      getTransactionReceipt: async ({ hash: requested }) => {
        assert.equal(requested, hash);
        calls++;
        return { status: "success" };
      },
    });
    assert.equal(calls, 1);
    await assert.rejects(
      assertCompletedBroadcast(file, {
        getTransactionReceipt: async () => ({ status: "reverted" }),
      }),
    );
    await assert.rejects(
      assertCompletedBroadcast(file, {
        getTransactionReceipt: async () => {
          throw new Error("not mined");
        },
      }),
    );
    await assert.rejects(
      assertCompletedBroadcast(path.join(dir, "missing.json"), {}),
    );
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("CLI rejects unsafe/inapplicable verification flags before any RPC or Forge call", () => {
  for (const args of [
    ["vault", "nOPAL", "--broadcast", "--verify-only"],
    ["vault", "nOPAL", "--verify-only", "--skip-verify"],
    ["common", "--skip-verify"],
    ["activate", "--verify-only"],
    ["vault", "nOPAL", "--resume"],
    ["activate", "--broadcast", "--resume"],
    ["vault", "nOPAL", "--verify-only", "--resume"],
    ["ownership", "nOPAL", "--broadcast", "--skip-verify"],
  ]) {
    const result = spawnSync(
      process.execPath,
      ["tools/deployArc.mjs", ...args],
      {
        encoding: "utf8",
        env: { ...process.env, ARC_RPC_URL: "http://127.0.0.1:1" },
      },
    );
    assert.equal(result.status, 1);
    assert.match(
      result.stderr,
      /cannot be combined|requires --broadcast|apply only/,
    );
  }
});

test("API preflight rejects Cloudflare login and bad API credentials", async () => {
  const { checkVerifierAccess } = await import("./arcVerification.mjs");
  const config = verifierConfig({});
  for (const response of [
    new Response("", { status: 302 }),
    new Response("<title>Sign in ・ Cloudflare Access</title>"),
    new Response("<html>not an API</html>"),
    Response.json({ status: "0", result: "Invalid API key" }),
    Response.json({ unexpected: true }),
  ])
    await assert.rejects(checkVerifierAccess(config, {}, async () => response));
  await checkVerifierAccess(config, {}, async () =>
    Response.json({ status: "1", result: "[]" }),
  );
});

test("preflight distinguishes HTTP and JSON rate limits from expired credentials", async () => {
  for (const response of [
    new Response("Too many requests", { status: 429 }),
    Response.json({ status: "0", message: "Too many requests", result: null }),
  ]) {
    await assert.rejects(
      checkVerifierAccess(verifierConfig({}), {}, async () => response),
      (error) =>
        error instanceof VerifierRateLimitError &&
        error.code === "ARC_VERIFIER_RATE_LIMIT",
    );
  }
});

test("login retries rate limits, preserves cached login on exhaustion, and rejects real auth failures", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "arc-login-test-"));
  const originalFetch = global.fetch;
  const originalLog = console.log;
  const originalWarn = console.warn;
  const messages = [];
  fs.writeFileSync(
    path.join(dir, "cloudflared"),
    '#!/bin/sh\ncase "$1 $2" in\n"access login") exit 0 ;;\n"access token") printf "header.payload.signature" ;;\n*) exit 1 ;;\nesac\n',
    { mode: 0o700 },
  );
  const env = {
    PATH: dir,
    ARC_VERIFIER_REQUEST_INTERVAL_MS: "0",
    ARC_VERIFIER_BACKOFF_MS: "0",
  };
  try {
    console.log = console.warn = (message) => messages.push(message);
    let calls = 0;
    global.fetch = async (_url, options) => {
      assert.equal(
        options.headers["cf-access-token"],
        "header.payload.signature",
      );
      calls++;
      return new Response("Too many requests", { status: 429 });
    };
    await loginToExplorer(verifierConfig({}), env);
    assert.equal(calls, 3);
    assert.ok(
      messages.some(
        (message) =>
          message.includes("session is cached") &&
          message.includes("could not be confirmed"),
      ),
    );
    assert.ok(
      !messages.some((message) => message.includes("API check succeeded")),
    );

    messages.length = 0;
    calls = 0;
    global.fetch = async () =>
      ++calls === 1
        ? Response.json({ status: "0", result: "Max rate limit reached" })
        : Response.json({ status: "1", result: "[]" });
    await loginToExplorer(verifierConfig({}), env);
    assert.equal(calls, 2);
    assert.ok(
      messages.some((message) => message.includes("API check succeeded")),
    );

    global.fetch = async () => new Response("", { status: 302 });
    await assert.rejects(
      loginToExplorer(verifierConfig({}), env),
      /behind Cloudflare Access/,
    );
    global.fetch = async () =>
      Response.json({ status: "0", result: "Invalid API key" });
    await assert.rejects(
      loginToExplorer(verifierConfig({}), env),
      /check the endpoint and credentials/,
    );
  } finally {
    global.fetch = originalFetch;
    console.log = originalLog;
    console.warn = originalWarn;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("Cloudflare service credentials reach only the configured explorer through a loopback relay", async () => {
  const { openVerifier } = await import("./arcVerification.mjs");
  const originalFetch = global.fetch;
  let calls = 0;
  let connection;
  global.fetch = async (url, options) => {
    if (new URL(url).hostname !== "explorer.example")
      return originalFetch(url, options);
    calls++;
    assert.equal(options.headers["CF-Access-Client-Id"], "client");
    assert.equal(options.headers["CF-Access-Client-Secret"], "secret");
    assert.equal(options.redirect, "manual");
    return Response.json({
      status: "1",
      result: calls === 1 ? "[]" : "verified",
    });
  };
  try {
    connection = await openVerifier(
      {
        name: "blockscout",
        url: "https://explorer.example/api/",
        key: "api-key",
      },
      {
        ARC_CF_ACCESS_CLIENT_ID: "client",
        ARC_CF_ACCESS_CLIENT_SECRET: "secret",
      },
    );
    assert.equal(new URL(connection.config.url).hostname, "127.0.0.1");
    const response = await originalFetch(connection.config.url, {
      method: "POST",
      body: "action=verifysourcecode",
    });
    assert.equal((await response.json()).result, "verified");
    assert.equal(calls, 2);
  } finally {
    await connection?.close();
    global.fetch = originalFetch;
  }
});

test("browser session JWT is reused through the relay without a service token", async () => {
  const { openVerifier } = await import("./arcVerification.mjs");
  const originalFetch = global.fetch;
  let connection;
  let calls = 0;
  global.fetch = async (url, options) => {
    if (new URL(url).hostname !== "explorer.example")
      return originalFetch(url, options);
    calls++;
    assert.equal(
      options.headers["cf-access-token"],
      "header.payload.signature",
    );
    assert.equal(options.headers["CF-Access-Client-Secret"], undefined);
    return Response.json({ status: "1", result: "ok" });
  };
  try {
    connection = await openVerifier(
      { name: "blockscout", url: "https://explorer.example/api/" },
      { ARC_CF_ACCESS_TOKEN: "header.payload.signature" },
    );
    const response = await originalFetch(connection.config.url);
    assert.equal(response.status, 200);
    assert.equal(calls, 2);
  } finally {
    await connection?.close();
    global.fetch = originalFetch;
  }
});

test("cached browser token is read from cloudflared; malformed output is ignored", async () => {
  const { readAccessToken } = await import("./arcVerification.mjs");
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "arc-cloudflared-test-"));
  const command = path.join(dir, "cloudflared");
  const config = { url: "https://explorer.arc.io/api/" };
  try {
    fs.writeFileSync(
      command,
      '#!/bin/sh\n[ "$1 $2 $3 $4" = "access token --app https://explorer.arc.io" ] || exit 1\nprintf "header.payload.signature"\n',
      { mode: 0o700 },
    );
    assert.equal(
      await readAccessToken(config, { PATH: dir }),
      "header.payload.signature",
    );
    fs.writeFileSync(command, '#!/bin/sh\nprintf "Please log in"\n');
    assert.equal(await readAccessToken(config, { PATH: dir }), undefined);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("rate-limit scheduler serializes bursts and preserves successful/pending responses", async () => {
  const { rateLimitedRequest } = await import("./arcVerification.mjs");
  let clock = 0;
  const starts = [];
  const request = rateLimitedRequest({
    intervalMs: 2000,
    now: () => clock,
    wait: async (ms) => {
      clock += ms;
    },
    request: async () => {
      starts.push(clock);
      return Response.json({ status: "1", result: "Pending in queue" });
    },
  });
  const responses = await Promise.all([
    request("https://example/api"),
    request("https://example/api"),
    request("https://example/api"),
  ]);
  assert.deepEqual(starts, [0, 2000, 4000]);
  assert.equal((await responses[0].json()).result, "Pending in queue");
});

test("HTTP-200 Blockscout throttling is retried with exponential shared cooldown", async () => {
  const { rateLimitedRequest } = await import("./arcVerification.mjs");
  let clock = 0,
    calls = 0;
  const starts = [],
    notices = [];
  const request = rateLimitedRequest({
    intervalMs: 2000,
    backoffMs: 30000,
    now: () => clock,
    wait: async (ms) => {
      clock += ms;
    },
    onRateLimit: (delay, attempt) => notices.push([delay, attempt]),
    request: async () => {
      starts.push(clock);
      calls++;
      return Response.json(
        calls <= 2
          ? {
              status: "0",
              message: "Too many requests. Increase limits now",
              result: null,
            }
          : { status: "1", result: "Pass - Verified" },
      );
    },
  });
  const [first, second] = await Promise.all([
    request("https://example/api"),
    request("https://example/api"),
  ]);
  assert.equal((await first.json()).result, "Pass - Verified");
  assert.equal(second.status, 200);
  assert.deepEqual(starts, [0, 30000, 90000, 92000]);
  assert.deepEqual(notices, [
    [30000, 1],
    [60000, 2],
  ]);
});

test("HTTP 429 respects Retry-After and exhausts retries without reporting success", async () => {
  const { rateLimitedRequest } = await import("./arcVerification.mjs");
  let clock = 0,
    calls = 0;
  const request = rateLimitedRequest({
    intervalMs: 2000,
    backoffMs: 30000,
    maxRetries: 1,
    now: () => clock,
    wait: async (ms) => {
      clock += ms;
    },
    onRateLimit: () => {},
    request: async () => {
      calls++;
      return new Response("limited", {
        status: 429,
        headers: { "Retry-After": "75" },
      });
    },
  });
  const response = await request("https://example/api");
  assert.equal(response.status, 429);
  assert.equal(await response.text(), "limited");
  assert.equal(clock, 75000);
  assert.equal(calls, 2);
});

test("ordinary verification failures and network errors are not retried or mislabeled as rate limits", async () => {
  const { rateLimitedRequest } = await import("./arcVerification.mjs");
  let calls = 0;
  const request = rateLimitedRequest({
    intervalMs: 0,
    request: async () => {
      calls++;
      if (calls === 1) throw new Error("network failed");
      return Response.json({
        status: "0",
        message: "NOTOK",
        result: "Bytecode mismatch",
      });
    },
  });
  await assert.rejects(request("https://example/api"), /network failed/);
  assert.equal(
    (await (await request("https://example/api")).json()).result,
    "Bytecode mismatch",
  );
  assert.equal(calls, 2);
});

test("the relay attaches the Arc API key to submissions and polls even if Forge omits or overrides it", async () => {
  const { openVerifier } = await import("./arcVerification.mjs");
  const originalFetch = global.fetch;
  let connection,
    calls = 0;
  global.fetch = async (url, options) => {
    if (new URL(url).hostname !== "explorer.example")
      return originalFetch(url, options);
    calls++;
    if (calls > 1)
      assert.equal(new URL(url).searchParams.get("apikey"), "arc-key");
    if (options.method === "POST")
      assert.equal(
        new URLSearchParams(String(options.body)).get("apikey"),
        "arc-key",
      );
    return Response.json({ status: "1", result: "ok" });
  };
  try {
    connection = await openVerifier(
      {
        name: "blockscout",
        url: "https://explorer.example/api/",
        key: "arc-key",
      },
      {
        ARC_CF_ACCESS_TOKEN: "header.payload.signature",
        ARC_VERIFIER_REQUEST_INTERVAL_MS: "0",
      },
    );
    await originalFetch(connection.config.url, {
      method: "POST",
      body: new URLSearchParams({
        action: "verifysourcecode",
        apikey: "wrong",
      }),
    });
    await originalFetch(
      connection.config.url + "?action=checkverifystatus&apikey=wrong",
    );
    assert.equal(calls, 3);
  } finally {
    await connection?.close();
    global.fetch = originalFetch;
  }
});
