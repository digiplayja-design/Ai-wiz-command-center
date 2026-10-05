import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { request } from "node:http";
import { PGlite } from "@electric-sql/pglite";
import {
  hostedAcceptanceConfig, bootstrapHostedAcceptanceDatabase, createHostedAcceptanceServer,
  EXPECTED_DATABASE, EXPECTED_DATABASE_HOST, EXPECTED_PLATFORM, EXPECTED_MERCHANT,
} from "./hosted_stripe_acceptance.mjs";
import {
  HOSTED_ACCEPTANCE_RETURN_CSS_PATH, HOSTED_ACCEPTANCE_RETURN_JS_PATH,
  HOSTED_ACCEPTANCE_RETURN_CSS, HOSTED_ACCEPTANCE_RETURN_JS,
} from "./hosted_acceptance_return.mjs";

// Actual HTTP + actual embedded PostgreSQL bootstrap and migrations. The only
// database query substitution is current_database(): the embedded engine's
// fixed database name cannot match Render's isolated database name. Stripe
// responses are offline fixtures; the fetch stub refuses all provider writes.
const NOW = Date.parse("2026-10-05T23:30:00.000Z");
const ORIGIN = "https://hosted-http.example.test";
const CONTROL_TOKEN = "751ba9c2".repeat(8);
const TEST_KEY = "rk_test_HostedHttpFixture";
const VERSION = "2026-09-30.endive";
const BAD_LINK = { booking_id: "12345678-1234-4234-8234-123456789abc", manage_token: "aa".repeat(32) };

async function fixture(t) {
  const env = {
    KORLIX_HOSTED_ACCEPTANCE_MODE: "isolated-postgres-sandbox-v1",
    KORLIX_HOSTED_ACCEPTANCE_DATABASE_HOST: EXPECTED_DATABASE_HOST,
    KORLIX_HOSTED_ACCEPTANCE_DATABASE_URL: `postgresql://fixture_owner:fixture_password@${EXPECTED_DATABASE_HOST}/${EXPECTED_DATABASE}`,
    KORLIX_HOSTED_ACCEPTANCE_STRIPE_KEY: TEST_KEY,
    KORLIX_HOSTED_ACCEPTANCE_ORIGIN: ORIGIN,
    KORLIX_HOSTED_ACCEPTANCE_TOKEN_HASH: createHash("sha256").update(CONTROL_TOKEN).digest("hex"),
    KORLIX_HOSTED_ACCEPTANCE_ENCRYPTION_KEY: "ab791d01c286fd54".repeat(4),
    KORLIX_HOSTED_ACCEPTANCE_EXPIRES_AT: new Date(NOW + 86400000).toISOString(),
  };
  const stageOne = hostedAcceptanceConfig(env, NOW);
  const config = hostedAcceptanceConfig({ ...env, KORLIX_HOSTED_ACCEPTANCE_PAYMENT_RUNTIME: "scheduling-v2" }, NOW);
  assert.equal(config.bindingHash, stageOne.bindingHash, "Runtime upgrade retains the original isolated binding");
  const db = new PGlite(); await db.waitReady;
  let server;
  t.after(async () => {
    if (server?.listening) {
      server.closeAllConnections();
      await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    }
    await db.close();
  });
  const queries = [];
  const client = {
    async query(sql, values) {
      queries.push(sql);
      const executable = sql.replace(/^(\s*SELECT\s+)current_database\(\)(\s+AS\s+database\b)/i,
        `$1'${EXPECTED_DATABASE}'::text$2`);
      const result = values?.length ? await db.query(executable, values) : (await db.exec(executable)).at(-1) ?? { rows: [] };
      return { ...result, rowCount: result.affectedRows ?? result.rows?.length ?? 0 };
    },
    release() {},
  };
  const pool = { async connect() { return client; } };
  await bootstrapHostedAcceptanceDatabase(stageOne, pool, { now: () => NOW });
  assert.deepEqual((await client.query("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename")).rows,
    [{ tablename: "korlix_hosted_acceptance_state" }]);
  const providerCalls = [];
  const fetcher = async (url, options = {}) => {
    const parsed = new URL(url), method = options.method ?? "GET", headers = new Headers(options.headers);
    providerCalls.push({ path: parsed.pathname, method });
    assert.equal(parsed.origin, "https://api.stripe.com");
    assert.equal(method, "GET", "This fixture must never make a provider write");
    assert.equal(options.body, undefined);
    assert.equal(options.redirect, "error");
    assert.equal(headers.get("authorization"), "Bearer " + TEST_KEY);
    assert.equal(headers.get("stripe-version"), VERSION);
    assert.equal(headers.get("stripe-account"), null);
    let data;
    if (parsed.pathname === "/v1/account") {
      assert.equal(parsed.search, "");
      data = { id: EXPECTED_PLATFORM, object: "account", livemode: false };
    } else {
      assert.equal(parsed.pathname, "/v2/core/accounts/" + EXPECTED_MERCHANT);
      assert.equal(parsed.searchParams.get("include[0]"), "configuration.merchant");
      assert.equal(parsed.searchParams.get("include[1]"), "defaults");
      assert.equal(parsed.searchParams.size, 2);
      data = {
        id: EXPECTED_MERCHANT, object: "v2.core.account", livemode: false, dashboard: "full",
        defaults: { responsibilities: { fees_collector: "stripe", losses_collector: "stripe" } },
        configuration: { merchant: { capabilities: { card_payments: { status: "active" },
          stripe_balance: { payouts: { status: "active" } } } } },
      };
    }
    return new Response(JSON.stringify(data), { headers: { "content-type": "application/json" } });
  };
  server = await createHostedAcceptanceServer(config, { pool, fetcher, now: () => NOW });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const send = (path, { method = "POST", body = {}, auth = true, headers = {} } = {}) => new Promise((resolve, reject) => {
    const outgoing = request({ hostname: "127.0.0.1", port: server.address().port, method, path,
      headers: { host: config.host, "content-type": "application/json",
        ...(auth ? { authorization: "Bearer " + CONTROL_TOKEN } : {}), ...headers },
    }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("error", reject);
      response.on("end", () => {
        const text = Buffer.concat(chunks).toString("utf8");
        resolve({ status: response.statusCode, headers: response.headers, text,
          data: /^application\/json/.test(response.headers["content-type"] || "") ? JSON.parse(text) : null });
      });
    });
    outgoing.on("error", reject);
    outgoing.end(method === "GET" ? undefined : typeof body === "string" ? body : JSON.stringify(body));
  });
  return { config, client, queries, providerCalls, send };
}

test("stage-two HTTP integration upgrades an isolated PostgreSQL ledger and preserves paused payment boundaries", async (t) => {
  const f = await fixture(t);
  await t.test("bootstrap initializes the payment ledger without enabling checkout or calling Stripe", async () => {
    const status = await f.send("/acceptance/status");
    assert.equal(status.status, 200);
    assert.equal(status.data.stage, "hosted-payment-runtime");
    assert.equal(status.data.databaseReady, true);
    assert.equal(status.data.flow.enabled, false);
    assert.equal(status.data.flow.booking, null);
    assert.equal(status.data.checkoutEnabled, false);
    assert.equal(status.data.paymentsConnected, false);
    assert.equal(status.data.webhookEnabled, false);
    assert.equal(f.providerCalls.length, 0);
    assert.equal((await f.client.query("SELECT count(*)::int AS count FROM public.korlix_hosted_acceptance_run")).rows[0].count, 1);
    assert.equal((await f.client.query("SELECT count(*)::int AS count FROM public.korlix_schedule_bookings")).rows[0].count, 0);
  });

  await t.test("public shell and static assets match exports and enforce credential-free browser policy", async () => {
    for (const [path, contentType, exact] of [
      ["/book/manage", "text/html", null],
      [HOSTED_ACCEPTANCE_RETURN_CSS_PATH, "text/css", HOSTED_ACCEPTANCE_RETURN_CSS],
      [HOSTED_ACCEPTANCE_RETURN_JS_PATH, "text/javascript", HOSTED_ACCEPTANCE_RETURN_JS],
    ]) {
      const response = await f.send(path, { method: "GET", auth: false });
      assert.equal(response.status, 200, path);
      assert(response.headers["content-type"].startsWith(contentType));
      assert.equal(response.headers["cache-control"], "no-store");
      assert.equal(response.headers["referrer-policy"], "no-referrer");
      for (const directive of ["default-src 'none'", "script-src 'self'", "style-src 'self'", "connect-src 'self'", "frame-ancestors 'none'", "base-uri 'none'", "form-action 'none'"])
        assert(response.headers["content-security-policy"].includes(directive), path + " " + directive);
      if (exact !== null) assert.equal(response.text, exact);
      else assert.match(response.text, /Checking your appointment/);
      for (const value of [CONTROL_TOKEN, TEST_KEY, f.config.encryptionKey, BAD_LINK.manage_token])
        assert(!response.text.includes(value));
    }
    assert.equal(f.providerCalls.length, 0);
    for (const path of ["/book/manage?token=not-allowed", "/acceptance/customer/status?token=not-allowed"])
      assert.equal((await f.send(path, { method: "GET", auth: false })).status, 404);
    assert.equal((await f.send("/book/manage", { method: "GET", auth: false, headers: { host: "foreign.example.test" } })).status, 404);
  });

  await t.test("customer status requires same origin and cannot read Stripe for invalid private links", async () => {
    const before = f.providerCalls.length;
    const missingOrigin = await f.send("/acceptance/customer/status", { auth: false, body: BAD_LINK });
    assert.equal(missingOrigin.status, 403);
    assert.equal(missingOrigin.data.error, "same_origin_required");
    const crossOrigin = await f.send("/acceptance/customer/status", { auth: false, body: BAD_LINK,
      headers: { origin: "https://foreign.example.test" } });
    assert.equal(crossOrigin.status, 403);
    for (const body of [BAD_LINK, { ...BAD_LINK, manage_token: "invalid" }, { ...BAD_LINK, booking_id: "invalid" }]) {
      const response = await f.send("/acceptance/customer/status", { auth: false, body, headers: { origin: ORIGIN, "sec-fetch-site": "same-origin" } });
      assert.equal(response.status, 404);
      assert.equal(response.data.error, "booking_link_unavailable");
      assert(!response.text.includes(body.manage_token));
    }
    assert.equal(f.providerCalls.length, before);
  });

  await t.test("an invalid webhook signature is rejected before database and provider work", async () => {
    const beforeQueries = f.queries.length, beforeProvider = f.providerCalls.length;
    const response = await f.send("/acceptance/payments/webhook", { auth: false,
      headers: { "stripe-signature": `t=${Math.floor(NOW / 1000)},v1=${"0".repeat(64)}` },
      body: { id: "evt_InvalidHttpFixture", account: EXPECTED_MERCHANT, livemode: false,
        type: "checkout.session.completed", data: { object: { id: "cs_test_InvalidHttpFixture" } } },
    });
    assert.equal(response.status, 400);
    assert.equal(response.data.error, "invalid_webhook_signature");
    assert.equal(f.queries.length, beforeQueries);
    assert.equal(f.providerCalls.length, beforeProvider);
  });

  await t.test("private checkout requires private authentication and remains paused", async () => {
    const unauthenticated = await f.send("/acceptance/checkout", { auth: false });
    assert.equal(unauthenticated.status, 401);
    assert.equal(unauthenticated.data.error, "private_control_token_required");
    const browser = await f.send("/acceptance/checkout", { headers: { origin: ORIGIN } });
    assert.equal(browser.status, 403);
    assert.equal(browser.data.error, "private_command_client_required");
    const paused = await f.send("/acceptance/checkout");
    assert.equal(paused.status, 409);
    assert.equal(paused.data.error, "checkout_paused");
    const enable = await f.send("/acceptance/enable");
    assert.equal(enable.status, 503);
    assert.equal(enable.data.error, "webhook_configuration_required");
    assert.equal(f.providerCalls.length, 0);
  });

  await t.test("identity verification remains read-only and does not enable the payment runtime", async () => {
    const response = await f.send("/acceptance/verify");
    assert.equal(response.status, 200);
    assert.equal(response.data.databaseReady, true);
    assert.equal(response.data.identityVerified, true);
    assert.equal(response.data.checkoutEnabled, false);
    assert.deepEqual(f.providerCalls, [
      { path: "/v1/account", method: "GET" },
      { path: "/v2/core/accounts/" + EXPECTED_MERCHANT, method: "GET" },
    ]);
    const status = await f.send("/acceptance/status");
    assert.equal(status.data.flow.enabled, false);
    assert.equal(status.data.flow.booking, null);
    assert.equal(status.data.checkoutEnabled, false);
    assert.equal((await f.client.query("SELECT count(*)::int AS count FROM public.korlix_schedule_bookings")).rows[0].count, 0);
    assert.equal((await f.client.query("SELECT count(*)::int AS count FROM public.korlix_schedule_payments")).rows[0].count, 0);
    assert.equal((await f.client.query("SELECT count(*)::int AS count FROM public.korlix_schedule_payment_receipts")).rows[0].count, 0);
  });
});
