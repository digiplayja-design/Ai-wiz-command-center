// Separate hosted sandbox acceptance entrypoint. Production never imports
// this module. A durable, single synthetic booking is available only with an
// explicit runtime opt-in; do not attach production credentials or env groups.
import assert from "node:assert/strict";
import { createHash, timingSafeEqual } from "node:crypto";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { providerRequest } from "../../scheduling/provider_core.mjs";
import { stripeProvider } from "../../scheduling/stripe_provider.mjs";
import {
  beginHostedAcceptanceTransaction as begin,
  validateHostedAcceptanceDatabase,
  bootstrapHostedAcceptanceDatabase,
} from "./hosted_acceptance_database.mjs";
export { bootstrapHostedAcceptanceDatabase } from "./hosted_acceptance_database.mjs";

export const EXPECTED_DATABASE = "korlix_2meetu_acceptance";
export const EXPECTED_DATABASE_HOST = "dpg-db1svtm0tbcc73caq380-a";
export const EXPECTED_PLATFORM = "acct_1UN1QuLwavBaepoe";
export const EXPECTED_MERCHANT = "acct_1UN1WiLwavcz7g46";
const MODE = "isolated-postgres-sandbox-v1";
const FORMAT = "korlix-hosted-acceptance-staging-v1";
const TABLE = "korlix_hosted_acceptance_state";
const VERSION = "2026-09-30.endive";
const WEEK = 7 * 24 * 60 * 60 * 1000;
const digest = (value) => createHash("sha256").update(value).digest("hex");
const setting = (env, name) => env["KORLIX_HOSTED_ACCEPTANCE_" + name];
const iso = (value) => typeof value === "string" && /^\d{4}-\d\d-\d\dT/.test(value) && Number.isFinite(Date.parse(value));

export function hostedAcceptanceConfig(env = {}, now = Date.now()) {
  assert.equal(setting(env, "MODE"), MODE, "Explicit hosted acceptance staging opt-in is required.");
  // These names are rejected, not copied into the scheduling/provider runtime.
  for (const [name, value] of Object.entries(env)) {
    if (!value || name.startsWith("KORLIX_HOSTED_ACCEPTANCE_")) continue;
    assert(!/^PG[A-Z0-9_]+$/i.test(name) && !/(?:STRIPE.*(?:KEY|SECRET)|SUPABASE|DATABASE_URL|RESEND|SMTP|SENDGRID|SCHEDULING_TOKEN_KEY)/i.test(name),
      "Production or unrelated service credentials must not be attached to this service.");
    assert(!(/^KORLIX_(?:SCHEDULING|WEB|DIRECTORY)_STRIPE_ENABLED$/.test(name) && value !== "false"),
      "Production checkout flags must not be enabled.");
  }
  assert.equal(setting(env, "DATABASE_HOST"), EXPECTED_DATABASE_HOST, "Use the exact dedicated acceptance database host.");
  const originUrl = new URL(setting(env, "ORIGIN") || env.RENDER_EXTERNAL_URL || "");
  assert(originUrl.protocol === "https:" && !originUrl.username && !originUrl.password &&
    originUrl.pathname === "/" && !originUrl.search && !originUrl.hash && !originUrl.port &&
    !["localhost", "127.0.0.1", "[::1]"].includes(originUrl.hostname), "A public HTTPS service origin is required.");
  const tokenHash = setting(env, "TOKEN_HASH") || "";
  const encryptionKey = setting(env, "ENCRYPTION_KEY") || "";
  assert.match(tokenHash, /^[a-f0-9]{64}$/, "Supply a SHA256 control-token hash.");
  assert.match(encryptionKey, /^[a-f0-9]{64}$/, "Supply a fresh 32-byte encryption key encoded as hex.");
  assert(!/^([a-f0-9])\1{63}$/.test(encryptionKey) && tokenHash !== encryptionKey && tokenHash !== digest(encryptionKey),
    "The private control token and encryption key must be distinct.");
  const expires = setting(env, "EXPIRES_AT");
  assert(iso(expires), "An explicit acceptance expiry is required.");
  const expiresAt = Date.parse(expires);
  assert(expiresAt <= now + WEEK, "Acceptance expiry must be within seven days.");
  const key = setting(env, "STRIPE_KEY") || null;
  assert(key === null || /^(?:sk|rk)_test_[A-Za-z0-9]+$/.test(key), "Only a dedicated sandbox test API key is accepted.");
  const runtime = setting(env, "PAYMENT_RUNTIME");
  assert(!runtime || runtime === "scheduling-v2", "Use the explicit scheduling-v2 runtime opt-in.");
  const paymentRuntime = runtime === "scheduling-v2";
  const webhook = setting(env, "WEBHOOK_SECRET") || null;
  const endpointId = setting(env, "WEBHOOK_ENDPOINT_ID") || null;
  assert(!webhook || (paymentRuntime && /^whsec_[A-Za-z0-9]+$/.test(webhook)), "A sandbox webhook secret requires the payment runtime.");
  assert(!endpointId || (paymentRuntime && /^we_[A-Za-z0-9]+$/.test(endpointId)), "Use the sandbox webhook endpoint ID.");
  let database = null;
  const dsn = setting(env, "DATABASE_URL");
  if (dsn) {
    const url = new URL(dsn);
    assert(["postgres:", "postgresql:"].includes(url.protocol) && url.hostname === EXPECTED_DATABASE_HOST &&
      (!url.port || url.port === "5432") && url.pathname === "/" + EXPECTED_DATABASE &&
      !url.search && !url.hash && !!url.username && !!url.password, "Use only the exact dedicated internal database connection URL.");
    const user = decodeURIComponent(url.username), password = decodeURIComponent(url.password);
    assert(/^[A-Za-z_][A-Za-z0-9_]{0,62}$/.test(user) && !/[\x00-\x1f\x7f]/.test(password), "Invalid dedicated database credentials.");
    // Render's private same-region connection is pinned above. Do not apply
    // this no-TLS setting to an external connection or a different database.
    database = Object.freeze({ host: EXPECTED_DATABASE_HOST, port: 5432, database: EXPECTED_DATABASE,
      user, password, ssl: false, max: 2, connectionTimeoutMillis: 5000,
      idleTimeoutMillis: 10000, query_timeout: 10000, application_name: "korlix-hosted-acceptance-staging" });
  }
  const binding = { format: FORMAT, database: EXPECTED_DATABASE, host: EXPECTED_DATABASE_HOST,
    platform: EXPECTED_PLATFORM, merchant: EXPECTED_MERCHANT, origin: originUrl.origin,
    encryptionKeyHash: digest(encryptionKey) };
  return Object.freeze({ database, key, tokenHash, encryptionKey, paymentRuntime, webhook, endpointId, origin: originUrl.origin, host: originUrl.host,
    expiresAt, bindingHash: digest(JSON.stringify(binding)) });
}

class StagingError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
const fail = (status, code) => { throw new StagingError(status, code); };

const HEADERS = {
  "Cache-Control": "no-store", Pragma: "no-cache", "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff", "X-Robots-Tag": "noindex, nofollow, noarchive",
  "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
};

async function readJson(req) {
  if (!/^application\/json(?:\s*;|$)/i.test(req.headers["content-type"] || "")) fail(400, "json_required");
  if (Number(req.headers["content-length"]) > 4096) fail(413, "request_too_large");
  const chunks = []; let length = 0;
  for await (const chunk of req) {
    length += chunk.length;
    if (length > 4096) fail(413, "request_too_large");
    chunks.push(chunk);
  }
  let body;
  try { body = JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { fail(400, "invalid_json"); }
  if (!body || Array.isArray(body) || typeof body !== "object") fail(400, "json_object_required");
  return body;
}
async function readEmptyJson(req) {
  if (Object.keys(await readJson(req)).length) fail(400, "empty_json_object_required");
}
async function readWebhook(req) {
  if (!/^application\/json(?:\s*;|$)/i.test(req.headers["content-type"] || "")) fail(400, "json_required");
  if (Number(req.headers["content-length"]) > 1048576) fail(413, "request_too_large");
  const chunks = []; let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 1048576) fail(413, "request_too_large");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

export async function createHostedAcceptanceServer(config, { pool, fetcher = fetch, now = Date.now } = {}) {
  let ownedPool = false, databaseReady = false, databaseState = null, identity = null, running = false;
  let flow = null, view = null, flowState = null;
  if (config.paymentRuntime) view = await import("./hosted_acceptance_return.mjs");
  if (config.database) {
    try {
      if (!pool) {
        const require = createRequire(new URL("./hosted-runtime/package.json", import.meta.url));
        const { Pool } = require("pg");
        pool = new Pool(config.database); ownedPool = true;
        pool.on("error", () => { databaseReady = false; identity = null; });
      }
      databaseState = await bootstrapHostedAcceptanceDatabase(config, pool, { now });
      databaseReady = true;
      if (config.paymentRuntime) {
        const { createHostedAcceptanceFlow } = await import("./hosted_acceptance_flow.mjs");
        flow = await createHostedAcceptanceFlow(config, { pool, fetcher, now });
        flowState = await flow.status();
      }
    } catch { databaseReady = false; }
  }
  const health = () => {
    const expired = now() >= config.expiresAt;
    const identityVerified = (!!identity || !!flowState?.readiness) && !expired;
    const operational = !!flow && databaseReady && !!config.key && !!config.webhook && !!config.endpointId;
    const paymentsConnected = operational && identityVerified && flowState?.endpointConfigurationVerified === true;
    const blockedReasons = [
      !config.database ? "database_credential_missing" : !databaseReady ? "database_isolation_unverified" : null,
      !config.key ? "stripe_test_key_missing" : !identityVerified ? "sandbox_identity_unverified" : null,
      expired ? "acceptance_expired" : null,
      !config.paymentRuntime ? "payment_runtime_not_enabled" : !flow ? "payment_runtime_unavailable" : null,
      config.paymentRuntime && !config.webhook ? "webhook_signing_secret_missing" : null,
      config.paymentRuntime && !config.endpointId ? "webhook_endpoint_id_missing" : null,
      config.paymentRuntime && config.endpointId && !flowState?.endpointConfigurationVerified ? "webhook_endpoint_unverified" : null,
      config.paymentRuntime && !flowState?.enabled ? "sandbox_checkout_paused" : null,
    ].filter(Boolean);
    return { mode: "hosted-sandbox-acceptance-staging",
      stage: config.paymentRuntime ? "hosted-payment-runtime" : "identity-readiness-only",
      readiness: blockedReasons.length ? "blocked" : "ready",
      checkoutEnabled: paymentsConnected && !!flowState?.enabled && !expired,
      paymentsConnected, webhookEnabled: operational, databaseReady, identityVerified, expired, blockedReasons };
  };
  const status = () => ({ ...health(), expectedPlatform: EXPECTED_PLATFORM, expectedMerchant: EXPECTED_MERCHANT,
    database: databaseState, identity, ...(config.paymentRuntime ? { flow: flowState } : {}), expiresAt: new Date(config.expiresAt).toISOString() });
  async function verify() {
    if (!databaseReady || !pool) fail(503, "database_isolation_unverified");
    if (!config.key) fail(503, "stripe_test_key_missing");
    identity = null;
    const client = await pool.connect();
    try {
      await begin(client);
      try {
        await validateHostedAcceptanceDatabase(client, config);
      } catch (error) {
        databaseReady = false;
        throw error;
      }
      const guardedFetch = (url, options = {}) => {
        const u = new URL(url), headers = new Headers(options.headers);
        assert(u.origin === "https://api.stripe.com" && !u.username && !u.password && !u.hash && (options.method || "GET") === "GET" && !options.body,
          "Only read-only Stripe identity requests are implemented.");
        assert.equal(headers.get("authorization"), "Bearer " + config.key);
        assert.equal(headers.get("stripe-version"), VERSION);
        assert(!headers.has("stripe-account"), "Identity requests must use the isolated platform context.");
        const platform = u.pathname === "/v1/account" && !u.search;
        const merchant = u.pathname === "/v2/core/accounts/" + EXPECTED_MERCHANT &&
          u.searchParams.size === 2 && u.searchParams.get("include[0]") === "configuration.merchant" && u.searchParams.get("include[1]") === "defaults";
        assert(platform || merchant, "Unexpected Stripe identity request.");
        return fetcher(url, { ...options, redirect: "error" });
      };
      const platform = await providerRequest(guardedFetch, "https://api.stripe.com/v1/account", {
        method: "GET", headers: { Authorization: "Bearer " + config.key, "Stripe-Version": VERSION },
      }, [], 10000);
      assert(platform.data.object === "account" && platform.data.id === EXPECTED_PLATFORM && platform.data.livemode !== true,
        "Isolated sandbox platform identity mismatch.");
      const adapter = stripeProvider({ key: config.key, version: VERSION, enabled: false },
        { fetcher: guardedFetch, requestTimeoutMs: 10000, diagnostic: () => {} });
      const merchant = await adapter.identity({ account_id: EXPECTED_MERCHANT, livemode: false });
      assert(merchant.id === EXPECTED_MERCHANT && merchant.readiness_source === "accounts_v2" && merchant.livemode === false && merchant.charges_enabled === true,
        "Isolated sandbox merchant identity or capabilities mismatch.");
      if (now() >= config.expiresAt) fail(410, "acceptance_expired");
      const checkedAt = new Date(now()).toISOString();
      const evidence = { platform: EXPECTED_PLATFORM, merchant: EXPECTED_MERCHANT, livemode: false,
        source: "accounts_v2", cardPayments: merchant.card_payments_status, payouts: merchant.payouts_status, checkedAt };
      await client.query(`UPDATE public.${TABLE} SET verified_at=$1,evidence=$2::jsonb WHERE singleton=true AND config_hash=$3`,
        [checkedAt, JSON.stringify(evidence), config.bindingHash]);
      await client.query("COMMIT");
      identity = evidence;
      databaseState = { ...databaseState, lastVerifiedAt: checkedAt };
      return status();
    } catch (error) {
      await client.query("ROLLBACK").catch(() => {});
      throw error;
    } finally { client.release(); }
  }
  const send = (res, statusCode, body) => {
    res.writeHead(statusCode, { ...HEADERS, "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify(body));
  };
  const buckets = new Map();
  const limited = (req) => {
    const key = req.socket.remoteAddress || "unknown", time = now();
    for (const [k, value] of buckets) if (value.until <= time) buckets.delete(k);
    if (buckets.size >= 1024 && !buckets.has(key)) return true;
    const bucket = buckets.get(key) || { until: time + 60000, count: 0 };
    buckets.set(key, bucket); return ++bucket.count > 30;
  };
  const staticSend = (res, type, content) => {
    res.writeHead(200, { ...HEADERS, "Content-Type": type,
      "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'" });
    res.end(content);
  };
  const commands = new Set(["status", "verify", ...(config.paymentRuntime ? ["enable", "pause", "book", "checkout", "refund", "tick", "fee-proof"] : [])]);
  const server = createServer(async (req, res) => {
    let operation = "request";
    try {
      if (!req.url.startsWith("/") || req.url.startsWith("//")) return send(res, 404, { error: "not_found" });
      const url = new URL(req.url, config.origin);
      if (url.search || url.hash) return send(res, 404, { error: "not_found" });
      if (req.method === "GET" && url.pathname === "/health") return send(res, 200, health());
      if (req.headers.host !== config.host) return send(res, 404, { error: "not_found" });
      if (view && req.method === "GET") {
        if (url.pathname === "/book/manage") return staticSend(res, "text/html; charset=utf-8", view.renderHostedAcceptanceShell());
        if (url.pathname === view.HOSTED_ACCEPTANCE_RETURN_CSS_PATH) return staticSend(res, "text/css; charset=utf-8", view.HOSTED_ACCEPTANCE_RETURN_CSS);
        if (url.pathname === view.HOSTED_ACCEPTANCE_RETURN_JS_PATH) return staticSend(res, "text/javascript; charset=utf-8", view.HOSTED_ACCEPTANCE_RETURN_JS);
      }
      if (req.method !== "POST") return send(res, 404, { error: "not_found" });
      if (config.paymentRuntime && url.pathname === "/acceptance/payments/webhook") {
        operation = "webhook";
        if (!flow || !databaseReady) fail(503, "payment_runtime_unavailable");
        const raw = await readWebhook(req);
        const result = await flow.webhook(raw, req.headers["stripe-signature"] || "");
        return send(res, 200, result);
      }
      if (config.paymentRuntime && url.pathname === "/acceptance/customer/status") {
        operation = "customer_status";
        if (limited(req)) fail(429, "rate_limited");
        if (req.headers.origin !== config.origin ||
            (req.headers["sec-fetch-site"] && req.headers["sec-fetch-site"] !== "same-origin"))
          fail(403, "same_origin_required");
        const body = await readJson(req);
        if (Object.keys(body).sort().join(",") !== "booking_id,manage_token" ||
            typeof body.booking_id !== "string" || typeof body.manage_token !== "string") fail(400, "invalid_booking_link");
        if (!flow || !databaseReady) fail(503, "payment_runtime_unavailable");
        const dto = await flow.customerStatus(body);
        return send(res, 200, { html: view.renderHostedAcceptancePage({ ...dto, refreshPath: "/book/manage" }) });
      }
      operation = url.pathname.slice("/acceptance/".length);
      if (!url.pathname.startsWith("/acceptance/") || !commands.has(operation)) return send(res, 404, { error: "not_found" });
      if (limited(req)) return send(res, 429, { error: "rate_limited" });
      if (req.headers.origin || req.headers["sec-fetch-site"]) return send(res, 403, { error: "private_command_client_required" });
      const supplied = /^Bearer ([a-f0-9]{64})$/.exec(req.headers.authorization || "");
      if (!supplied || !timingSafeEqual(Buffer.from(digest(supplied[1]), "hex"), Buffer.from(config.tokenHash, "hex")))
        return send(res, 401, { error: "private_control_token_required" });
      // Expiry stops new checkouts. Existing signed events, ledger reads and
      // explicit full refunds can still settle the single owned test booking.
      if (now() >= config.expiresAt && (!config.paymentRuntime || !["status", "pause", "refund", "tick", "fee-proof"].includes(operation)))
        return send(res, 410, { error: "acceptance_expired" });
      await readEmptyJson(req);
      if (running) return send(res, 409, { error: "readiness_check_in_progress" });
      running = true;
      try {
        if (operation === "status") {
          if (flow) flowState = await flow.status();
          return send(res, 200, status());
        }
        if (operation === "verify") return send(res, 200, await verify());
        if (!flow || !databaseReady) fail(503, "payment_runtime_unavailable");
        flowState = null;
        const result = await flow[operation === "fee-proof" ? "feeProof" : operation]();
        try { flowState = await flow.status(); } catch { /* A status refresh must not undo a successful command response. */ }
        return send(res, 200, result);
      } finally { running = false; }
    } catch (error) {
      if (["database_isolation_unverified", "acceptance_run_missing", "acceptance_booking_scope", "booking_binding_mismatch"].includes(error.code)) {
        databaseReady = false; identity = null; flowState = null;
      }
      const typed = (operation !== "verify" || error instanceof StagingError || error.code === "readiness_check_in_progress") && Number.isInteger(error.status) && error.status >= 400 && error.status <= 599 &&
        typeof error.code === "string" && /^[a-z][a-z0-9_]{0,79}$/.test(error.code);
      if (!res.headersSent) send(res, typed ? error.status : 503,
        { error: typed ? error.code : operation === "verify" ? "readiness_verification_failed" : "acceptance_operation_failed" });
      else res.end();
    }
  });
  server.requestTimeout = 30000;
  server.headersTimeout = 10000;
  server.on("close", () => {
    void (async () => { if (flow) await flow.close(); if (ownedPool) await pool.end(); })().catch(() => {});
  });
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const config = hostedAcceptanceConfig(process.env);
    const server = await createHostedAcceptanceServer(config);
    const port = Number(process.env.PORT || 10000);
    assert(Number.isInteger(port) && port > 0 && port <= 65535, "Invalid service port.");
    server.listen(port, "0.0.0.0", () => console.log("Hosted sandbox acceptance ready; private controls enforce the durable payment gate."));
    process.once("SIGTERM", () => { server.close(); server.closeAllConnections(); });
  } catch {
    console.error("Hosted acceptance staging configuration rejected; no configuration values displayed.");
    process.exitCode = 1;
  }
}
