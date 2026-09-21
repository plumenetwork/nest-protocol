import fs from "node:fs";
import path from "node:path";
import { createServer } from "node:http";
import { execFile, spawn } from "node:child_process";
import { keccak256 } from "viem";

export const DEPLOYMENT_PHASES = new Set([
  "bootstrap",
  "common",
  "compliance",
  "vault",
]);

export function verifierConfig(env) {
  const name = env.ARC_VERIFIER?.trim() || "blockscout";
  if (!["blockscout", "etherscan", "custom"].includes(name)) {
    throw new Error("ARC_VERIFIER must be blockscout, etherscan, or custom");
  }
  const url =
    env.ARC_VERIFIER_URL?.trim() ||
    (name === "blockscout" ? "https://explorer.arc.io/api/" : undefined);
  if (!url)
    throw new Error("ARC_VERIFIER_URL is required for a custom Arc explorer");
  const parsed = new URL(url);
  if (!["http:", "https:"].includes(parsed.protocol))
    throw new Error("ARC_VERIFIER_URL must be an HTTP(S) API URL");
  const configuredChain = parsed.searchParams.get("chainid");
  if (configuredChain && configuredChain !== "5042")
    throw new Error("Verifier URL chainid must be 5042");
  if (/testnet/i.test(parsed.hostname))
    throw new Error(
      "Arc 5042 requires the mainnet verifier, not a testnet explorer",
    );
  const key = env.ARC_VERIFIER_API_KEY?.trim();
  if (name !== "blockscout" && !key)
    throw new Error("ARC_VERIFIER_API_KEY is required for this verifier");
  return { name, url, key };
}

export function verifierArgs(config) {
  return ["--verifier", config.name, "--verifier-url", config.url];
}

export function phaseBroadcastRoot(root, phase, symbol) {
  return path.join(
    root,
    "broadcast",
    "arc",
    symbol ? `${phase}-${symbol}` : phase,
  );
}

export function completedTransactions(log) {
  if (Number(log.chain) !== 5042)
    throw new Error("Verification log is not for Arc 5042");
  if (log.pending?.length)
    throw new Error(
      "Broadcast has pending transactions; verification-only cannot resume a deployment",
    );
  if (!log.transactions?.length)
    throw new Error("No transactions in saved broadcast");
  const receipts = new Map(
    (log.receipts || []).map((r) => [r.transactionHash?.toLowerCase(), r]),
  );
  for (const tx of log.transactions) {
    const receipt = receipts.get(tx.hash?.toLowerCase());
    if (!receipt || BigInt(receipt.status ?? 0) !== 1n) {
      throw new Error(
        "Broadcast is incomplete or reverted; verification-only requires every transaction to have succeeded",
      );
    }
  }
  return log.transactions.map((tx) => tx.hash);
}

export async function assertCompletedBroadcast(file, client) {
  if (!fs.existsSync(file))
    throw new Error(`No saved live broadcast for this phase: ${file}`);
  const log = JSON.parse(fs.readFileSync(file, "utf8"));
  for (const hash of completedTransactions(log)) {
    const receipt = await client.getTransactionReceipt({ hash });
    if (receipt.status !== "success")
      throw new Error(`Transaction ${hash} did not succeed on Arc`);
  }
  return log;
}

/** CreateX uses the bundled 0.8.23 build, not the repository's 0.8.30 profile. */
export async function prepareCreateXProject(root, run) {
  const dir = path.join(root, "generated", "arc-verification", "createx");
  fs.mkdirSync(path.join(dir, "src"), { recursive: true });
  fs.copyFileSync(
    path.join(root, "node_modules/createx/src/CreateX.sol"),
    path.join(dir, "src/CreateX.sol"),
  );
  fs.writeFileSync(
    path.join(dir, "foundry.toml"),
    `[profile.default]
solc_version = '0.8.23'
src = 'src'
out = 'out'
libs = []
optimizer = true
optimizer_runs = 200
evm_version = 'shanghai'
via_ir = false
bytecode_hash = 'none'
cbor_metadata = false
[lint]
lint_on_build = false
`,
  );
  const result = await run(["build", "--root", dir], {
    FOUNDRY_PROFILE: "default",
  });
  if (result.status !== 0)
    throw new Error("Failed to compile the original CreateX build");
  const artifact = JSON.parse(
    fs.readFileSync(path.join(dir, "out/CreateX.sol/CreateX.json"), "utf8"),
  );
  const expected = JSON.parse(
    fs.readFileSync(path.join(root, "config/createx/deployment.json"), "utf8"),
  );
  const bundled = fs
    .readFileSync(path.join(root, "config/createx/initcode.hex"), "utf8")
    .trim();
  if (
    keccak256(artifact.bytecode.object) !== expected.initCodeHash ||
    artifact.bytecode.object.toLowerCase() !== bundled.toLowerCase()
  ) {
    throw new Error(
      "CreateX compiler output does not match the pinned deployment bytecode",
    );
  }
  return { dir, address: expected.address };
}

/** Serialize all calls, including status polls, and retry explicit explorer rate limits. */
export function rateLimitedRequest({
  request = (...args) => fetch(...args),
  intervalMs = 2000,
  backoffMs = 30000,
  maxRetries = 2,
  now = Date.now,
  wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  onRateLimit = (delay, attempt) =>
    console.warn(
      `Arc explorer rate limit: waiting ${Math.ceil(delay / 1000)}s before retry ${attempt}/${maxRetries}.`,
    ),
} = {}) {
  let queue = Promise.resolve();
  let nextRequestAt = 0;
  return (url, options) => {
    const run = async () => {
      for (let attempt = 0; ; attempt++) {
        if (nextRequestAt > now()) await wait(nextRequestAt - now());
        // Each retry gets its own timeout; time spent in the queue must not expire it.
        const response = await request(url, {
          ...options,
          signal: AbortSignal.timeout(120000),
        });
        nextRequestAt = now() + intervalMs;
        let message = "";
        if (response.status !== 429) {
          try {
            const body = await response.clone().json();
            if (String(body.status) === "0")
              message = `${body.message ?? ""} ${body.result ?? ""}`;
          } catch {
            /* Non-JSON failures pass through to the verifier. */
          }
        }
        if (
          response.status !== 429 &&
          !/too many requests|max rate limit|rate limit exceeded/i.test(message)
        )
          return response;
        const retryAfter = response.headers.get("retry-after");
        const retryDelay =
          retryAfter === null
            ? 0
            : /^\d+(?:\.\d+)?$/.test(retryAfter)
              ? Number(retryAfter) * 1000
              : Math.max(0, Date.parse(retryAfter) - now()) || 0;
        const delay = Math.max(
          intervalMs,
          backoffMs * 2 ** attempt,
          retryDelay,
        );
        nextRequestAt = now() + delay;
        if (attempt >= maxRetries) return response;
        onRateLimit(delay, attempt + 1);
        await response.arrayBuffer();
      }
    };
    const result = queue.then(run);
    queue = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  };
}

function verifierTiming(env, name, fallback) {
  if (!env[name]) return fallback;
  const value = Number(env[name]);
  if (!Number.isFinite(value) || value < 0 || value > 300000)
    throw new Error(`${name} must be milliseconds between 0 and 300000`);
  return value;
}

export class VerifierRateLimitError extends Error {
  constructor(status) {
    super(
      `Arc explorer is rate-limiting API requests (HTTP ${status}). Session expiry cannot be inferred from this response. Wait for the quota to recover, then retry the verification command; repeating login will not reset the quota. Nothing was broadcast.`,
    );
    this.name = "VerifierRateLimitError";
    this.code = "ARC_VERIFIER_RATE_LIMIT";
  }
}

function explorerRequester(env) {
  return rateLimitedRequest({
    intervalMs: verifierTiming(env, "ARC_VERIFIER_REQUEST_INTERVAL_MS", 2000),
    backoffMs: verifierTiming(env, "ARC_VERIFIER_BACKOFF_MS", 30000),
  });
}

/** Prove API access before any broadcast; do not follow login redirects with credentials. */
export async function checkVerifierAccess(
  config,
  headers = {},
  request = fetch,
) {
  const response = await request(config.url, {
    method: "POST",
    redirect: "manual",
    signal: AbortSignal.timeout(20000),
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      ...headers,
    },
    body: new URLSearchParams({
      module: "contract",
      action: "getabi",
      address: "0x000000000022D473030F116dDEE9F6B43aC78BA3",
      apikey: config.key || "",
    }),
  });
  const text = await response.text();
  if (response.status === 429)
    throw new VerifierRateLimitError(response.status);
  if (
    (response.status >= 300 && response.status < 400) ||
    /Cloudflare Access/i.test(text)
  ) {
    throw new Error(
      "Arc verifier is behind Cloudflare Access. Run pnpm deploy:arc login, complete the browser email-code login, then retry. Nothing was broadcast.",
    );
  }
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    throw new Error(
      `Arc verifier returned non-JSON (HTTP ${response.status}); check ARC_VERIFIER_URL and Cloudflare access. Nothing was broadcast.`,
    );
  }
  if (
    String(body.status) === "0" &&
    /too many requests|max rate limit|rate limit exceeded/i.test(
      `${body.message ?? ""} ${body.result ?? ""}`,
    )
  ) {
    throw new VerifierRateLimitError(response.status);
  }
  if (
    !response.ok ||
    !["0", "1"].includes(String(body.status)) ||
    /invalid.*(?:api.?key|token)|unauthorized|forbidden/i.test(
      `${body.message ?? ""} ${body.result ?? ""}`,
    )
  ) {
    throw new Error(
      `Arc verifier API preflight failed (HTTP ${response.status}); check the endpoint and credentials. Nothing was broadcast.`,
    );
  }
}

/** Forge lacks verifier-specific headers; use a temporary loopback relay for Cloudflare session/service-token auth. */
export async function openVerifier(config, env) {
  const id = env.ARC_CF_ACCESS_CLIENT_ID?.trim();
  const secret = env.ARC_CF_ACCESS_CLIENT_SECRET?.trim();
  if (!!id !== !!secret)
    throw new Error(
      "Both ARC_CF_ACCESS_CLIENT_ID and ARC_CF_ACCESS_CLIENT_SECRET are required",
    );
  const headers = id
    ? { "CF-Access-Client-Id": id, "CF-Access-Client-Secret": secret }
    : {};
  if (!id) {
    const token = await readAccessToken(config, env);
    if (token) headers["cf-access-token"] = token;
  }
  const request = explorerRequester(env);
  await checkVerifierAccess(config, headers, request);
  const upstream = new URL(config.url);
  const server = createServer(async (req, res) => {
    try {
      const incoming = new URL(req.url, "http://127.0.0.1");
      const target = new URL(upstream);
      target.pathname = incoming.pathname;
      for (const [key, value] of incoming.searchParams)
        target.searchParams.set(key, value);
      // Enforce the configured Arc key for GET polls as well as POST submissions.
      // Do not rely on a nested Forge verification job retaining its environment key.
      if (config.key) target.searchParams.set("apikey", config.key);
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      let body = Buffer.concat(chunks);
      const contentType =
        req.headers["content-type"] || "application/x-www-form-urlencoded";
      if (
        config.key &&
        contentType.includes("application/x-www-form-urlencoded") &&
        body.length
      ) {
        const form = new URLSearchParams(body.toString());
        form.set("apikey", config.key);
        body = Buffer.from(form.toString());
      }
      const response = await request(target, {
        method: req.method,
        redirect: "manual",
        signal: AbortSignal.timeout(120000),
        headers: {
          ...headers,
          "Content-Type": contentType,
          "Accept-Encoding": "identity",
        },
        ...(req.method !== "GET" && req.method !== "HEAD" ? { body } : {}),
      });
      res.writeHead(response.status, {
        "Content-Type": response.headers.get("content-type") || "text/plain",
        ...(response.headers.get("retry-after")
          ? { "Retry-After": response.headers.get("retry-after") }
          : {}),
      });
      res.end(Buffer.from(await response.arrayBuffer()));
    } catch {
      res.writeHead(502);
      res.end("Arc verifier relay failed");
    }
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const local = new URL(config.url);
  local.protocol = "http:";
  local.hostname = "127.0.0.1";
  local.port = String(server.address().port);
  return {
    config: { ...config, url: local.toString() },
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

/** Read cloudflared's existing application session without printing or persisting its JWT. */
export async function readAccessToken(config, env) {
  if (env.ARC_CF_ACCESS_TOKEN?.trim()) return env.ARC_CF_ACCESS_TOKEN.trim();
  return new Promise((resolve) => {
    execFile(
      "cloudflared",
      ["access", "token", "--app", new URL(config.url).origin],
      { env, timeout: 10000, maxBuffer: 1024 * 1024 },
      (error, stdout) => {
        const token = stdout?.trim();
        resolve(
          !error &&
            /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token)
            ? token
            : undefined,
        );
      },
    );
  });
}

export async function loginToExplorer(config, env) {
  console.log(
    "Complete the Cloudflare email-code login in the browser. No deployment is started.",
  );
  await new Promise((resolve, reject) => {
    // --quiet retains browser instructions but never prints the resulting JWT.
    const child = spawn(
      "cloudflared",
      ["access", "login", "--quiet", new URL(config.url).origin],
      { env, stdio: "inherit" },
    );
    child.once("error", () =>
      reject(
        new Error(
          "cloudflared is required; install it with brew install cloudflared",
        ),
      ),
    );
    child.once("close", (status) =>
      status === 0
        ? resolve()
        : reject(new Error("Cloudflare login did not complete")),
    );
  });
  const token = await readAccessToken(config, env);
  if (!token)
    throw new Error("No cached Cloudflare application token after login");
  console.log(
    "Cloudflare login completed and session cached. Checking explorer API access...",
  );
  try {
    await checkVerifierAccess(
      config,
      { "cf-access-token": token },
      explorerRequester(env),
    );
  } catch (error) {
    if (!(error instanceof VerifierRateLimitError)) throw error;
    console.warn(
      "Cloudflare session is cached, but explorer API access could not be confirmed because it is rate-limited. No deployment or verification was started. Wait, then retry your --verify-only command; you do not need to repeat login just because of HTTP 429.",
    );
    return;
  }
  console.log(
    "Arc explorer login and API check succeeded. Deployment commands will reuse the cached session.",
  );
}
