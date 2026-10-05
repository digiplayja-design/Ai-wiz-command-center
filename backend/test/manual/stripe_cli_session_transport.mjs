// Test harness transport only. Browser session tokens stay inside Stripe CLI.
import { execFile } from "node:child_process";
import { isAbsolute } from "node:path";

const CLI = "/workspace/scratch/3f6fe4659caf/bin/stripe";
const failure = () => new Error("Stripe CLI acceptance request could not be verified.");
const check = (condition) => { if (!condition) throw failure(); };
const cleanEnvironment = (environment) => ({ ...Object.fromEntries(
  // Keep the trusted execution runtime's networking configuration: managed
  // workspaces can require an egress proxy and its CA. Stripe-specific auth,
  // socket, endpoint, or mode overrides remain excluded.
  ["HOME", "PATH", "USER", "LOGNAME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "LANG", "LC_ALL", "TMPDIR",
    "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "all_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR"]
    .filter((key) => typeof environment[key] === "string").map((key) => [key, environment[key]])),
  // Fixed CLI controls avoid its deferred update/telemetry requests consuming
  // the provider's timeout after the actual Stripe API response has arrived.
  STRIPE_NO_AUTO_UPDATE: "1", DO_NOT_TRACK: "1" });

function execute(file, args, options) {
  return new Promise((resolve) => {
    execFile(file, args, { ...options, encoding: "utf8", windowsHide: true, shell: false }, (error, stdout, stderr) => {
      // Never include the child error, raw streams, or argv in an exception.
      resolve({ exitCode: error ? (typeof error.code === "number" ? error.code : -1) : 0,
        failed: Boolean(error?.killed || error?.name === "AbortError" || (error && typeof error.code !== "number")), stdout, stderr });
    });
  });
}

export function verifyCliIdentity(result, expectedContext) {
  check(result.exitCode === 0 && !result.failed);
  let identity; try { identity = JSON.parse(result.stdout); } catch { throw failure(); }
  check(identity.account_id === expectedContext && identity.mode === "test" && Array.isArray(identity.authorized_accounts));
  check(identity.authorized_accounts.some((account) => account.id === expectedContext && Array.isArray(account.modes) && account.modes.includes("test")));
  check(identity.expires_at === undefined || (Number.isInteger(identity.expires_at) && identity.expires_at > Date.now() / 1000));
  return { context: expectedContext, mode: "test" };
}

// CLI v1.53 verbose output writes request/response headers to stderr, JSON to
// stdout. An HTTP 4xx may exit zero. The final response status is authoritative.
export function parseCliResponse(result, expected) {
  check(!result.failed && typeof result.stdout === "string" && typeof result.stderr === "string");
  const lines = result.stderr.split(/\r?\n/);
  const starts = lines.map((line, i) => /^> (GET|POST) https:\/\/api\.stripe\.com\//.test(line) ? i : -1).filter((i) => i >= 0);
  check(starts.length > 0);
  const start = starts.at(-1), request = /^> (GET|POST) (https:\/\/api\.stripe\.com\/\S+)$/.exec(lines[start]);
  check(request && request[1] === expected.method);
  const actualUrl = new URL(request[2]);
  check(actualUrl.pathname === expected.path);
  const canonical = (params) => JSON.stringify([...params].sort(([ak, av], [bk, bv]) => ak.localeCompare(bk) || av.localeCompare(bv)));
  check(canonical(actualUrl.searchParams) === canonical(expected.query));
  const statusIndex = lines.findIndex((line, i) => i > start && /^< HTTP [1-5]\d\d$/.test(line));
  check(statusIndex > start);
  check(!lines.slice(statusIndex + 1).some((line) => /^< HTTP /.test(line)));
  const headers = new Map();
  for (const line of lines.slice(start + 1, statusIndex)) {
    const match = /^> ([A-Za-z-]+): ?(.*)$/.exec(line);
    if (match) { const name = match[1].toLowerCase(); check(!headers.has(name)); headers.set(name, match[2]); }
  }
  check(headers.get("stripe-livemode") === "false" && headers.get("stripe-version") === expected.version);
  if (expected.merchant) {
    check(headers.get("stripe-account") === expected.context + "/" + expected.merchant && !headers.has("stripe-context"));
  } else check(headers.get("stripe-context") === expected.context && !headers.has("stripe-account"));
  const status = Number(lines[statusIndex].slice(7));
  check(status >= 200 && status <= 599);
  const requestIds = lines.slice(statusIndex + 1).map((line) => /^< Request-Id: (req_[A-Za-z0-9]+)$/i.exec(line)?.[1]).filter(Boolean);
  check(requestIds.length === 1);
  let body;
  let decoded; try { decoded = JSON.parse(result.stdout); } catch { throw failure(); }
  check(decoded && typeof decoded === "object");
  if (status >= 200 && status < 300) {
    check(result.exitCode === 0);
    check(!Object.hasOwn(decoded, "error"));
    body = decoded;
  } else {
    // Do not retain provider messages that might echo inputs or credentials.
    const code = decoded.error?.code || decoded.error;
    body = { error: { code: typeof code === "string" && /^[a-z][a-z0-9_]{0,100}$/.test(code) ? code : "cli_http_error",
      message: "Stripe rejected the isolated acceptance request." } };
  }
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "request-id": requestIds[0] } });
}

export function createCliSessionFetch({ configPath, expectedContext, expectedPlatform, merchant, marker, childEnvironment = process.env, runner = execute }) {
  check(isAbsolute(configPath || "") && /^[A-Za-z][A-Za-z0-9_]{5,199}$/.test(expectedContext || ""));
  check(/^acct_[A-Za-z0-9]+$/.test(expectedPlatform || "") && /^acct_[A-Za-z0-9]+$/.test(merchant || ""));
  check(marker === "manual-cli-session:" + expectedContext);
  const env = cleanEnvironment(childEnvironment);
  const prefix = ["--config", configPath, "--color", "off", "--log-level", "error"];
  return async function cliSessionFetch(url, options = {}) {
    try {
      const parsed = new URL(url), method = options.method || "GET", headers = new Headers(options.headers);
      check(parsed.origin === "https://api.stripe.com" && !parsed.username && !parsed.password && !parsed.hash);
      check(headers.get("authorization") === "Bearer " + marker);
      check([...headers.keys()].every((name) => ["authorization", "stripe-account", "stripe-version", "idempotency-key", "content-type"].includes(name)));
      const account = headers.get("stripe-account"), version = headers.get("stripe-version");
      check(/^\d{4}-\d{2}-\d{2}\.[a-z]+$/.test(version || ""));
      const platformRead = method === "GET" && !account && ["/v1/account", "/v1/webhook_endpoints", "/v2/core/accounts/" + merchant].includes(parsed.pathname);
      const paymentRead = method === "GET" && account === merchant && /^\/v1\/(checkout\/sessions\/cs_[A-Za-z0-9_]+|refunds\/re_[A-Za-z0-9_]+|charges\/ch_[A-Za-z0-9_]+|payment_intents\/pi_[A-Za-z0-9_]+)$/.test(parsed.pathname);
      const paymentWrite = method === "POST" && account === merchant && ["/v1/checkout/sessions", "/v1/refunds"].includes(parsed.pathname);
      check(platformRead || paymentRead || paymentWrite);
      const v2Get = method === "GET" && parsed.pathname.startsWith("/v2/");
      const args = [...prefix, method.toLowerCase(), parsed.pathname + (v2Get ? parsed.search : ""), "--show-headers", "--stripe-version", version,
        "--request-header", "Stripe-Livemode: false"];
      // Explicit custom headers run AFTER the CLI's credential-derived headers.
      // This pins the sandbox even if its global active context changes after
      // whoami. --stripe-account first removes Stripe-Context for direct charges.
      if (account) args.push("--stripe-account", merchant, "--request-header", "Stripe-Account: " + expectedContext + "/" + merchant);
      else args.push("--request-header", "Stripe-Context: " + expectedContext);
      const params = method === "GET" ? parsed.searchParams : new URLSearchParams(options.body);
      check(method === "GET" ? !options.body : !parsed.search && typeof options.body === "string" && headers.get("content-type") === "application/x-www-form-urlencoded");
      // v2 GET explicitly merges the path query in CLI BuildDataForV2Request;
      // it accepts only JSON --data, so preserve its query in the path instead.
      // v1 GET replaces path queries and needs individual form parameters.
      for (const [key, value] of params) { check(!/[\r\n\0]/.test(key)); if (!v2Get) args.push("--data", key + "=" + value); }
      const idempotency = headers.get("idempotency-key");
      if (paymentWrite) { check(/^korlix-scheduling-(checkout|refund)-[a-f0-9-]{36}$/.test(idempotency || "")); args.push("--idempotency", idempotency); }
      else check(!idempotency);
      if (options.signal?.aborted) throw failure();
      const runOptions = { env, timeout: 15000, maxBuffer: 4 * 1024 * 1024, signal: options.signal };
      verifyCliIdentity(await runner(CLI, [...prefix, "whoami", "--format", "json"], runOptions), expectedContext);
      if (options.signal?.aborted) throw failure();
      const response = parseCliResponse(await runner(CLI, args, runOptions), {
        method, path: parsed.pathname, query: method === "GET" ? parsed.searchParams : new URLSearchParams(),
        version, context: expectedContext, merchant: account });
      // The harness separately verifies this API identity against expectedPlatform.
      return response;
    } catch { throw failure(); }
  };
}
