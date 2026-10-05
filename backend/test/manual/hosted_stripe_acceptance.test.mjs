import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { request as httpRequest } from "node:http";
import {
  hostedAcceptanceConfig, bootstrapHostedAcceptanceDatabase, createHostedAcceptanceServer, hostedStartupDiagnostic,
  EXPECTED_DATABASE, EXPECTED_DATABASE_HOST, EXPECTED_PLATFORM, EXPECTED_MERCHANT,
} from "./hosted_stripe_acceptance.mjs";

// Offline boundary tests: the PG catalog and Stripe responses below are
// fixtures. They do not establish a real database bootstrap or provider call.
const NOW = Date.parse("2026-10-05T18:00:00.000Z");
const DAY = 86400000;
const token = "83d29710".repeat(8);
const sha = (value) => createHash("sha256").update(value).digest("hex");
const PREFIX = "KORLIX_HOSTED_ACCEPTANCE_";
const DSN = "postgresql://fixture_owner:fixture_password@dpg-db1svtm0tbcc73caq380-a:5432/korlix_2meetu_acceptance";
function environment(changes = {}) {
  return Object.fromEntries(Object.entries({
    MODE: "isolated-postgres-sandbox-v1", DATABASE_HOST: "dpg-db1svtm0tbcc73caq380-a",
    ORIGIN: "https://acceptance.example.test", TOKEN_HASH: sha(token),
    ENCRYPTION_KEY: "ab79d101c286fd54".repeat(4), EXPIRES_AT: new Date(NOW + DAY).toISOString(),
    ...changes,
  }).map(([key, value]) => [PREFIX + key, value]));
}
const configured = (changes = {}) => hostedAcceptanceConfig(environment(changes), NOW);
const json = (value, status = 200) => new Response(JSON.stringify(value), {
  status, headers: { "content-type": "application/json" },
});

test("startup diagnostics retain failure location and SQLSTATE without credentials or raw errors", async () => {
  const secret = "rk_test_fixture_secret_not_for_logs";
  const config = configured({ DATABASE_URL: DSN });
  const entries = [];
  const error = Object.assign(new Error("Could not connect " + DSN + " " + secret), { code: "42501", detail: secret });
  const server = await runningServer(config, { pool: { connect: async () => { throw error; } }, diagnostic: entry => entries.push(entry) });
  try {
    assert.equal((await server.request("/health", { method: "GET" })).data.databaseReady, false);
    assert.deepEqual(entries, [{ event: "hosted_acceptance_startup_blocked", stage: "database_bootstrap", code: "42501" }]);
    assert(!JSON.stringify(entries).includes(secret));
    assert(!JSON.stringify(entries).includes(DSN));
    assert.deepEqual(hostedStartupDiagnostic({ code: secret }, secret), {
      event: "hosted_acceptance_startup_blocked", stage: "startup", code: "startup_failed",
    });
  } finally { await server.close(); }
});
const merchant = (changes = {}) => ({
  id: EXPECTED_MERCHANT, object: "v2.core.account", livemode: false, dashboard: "full",
  defaults: { responsibilities: { fees_collector: "stripe", losses_collector: "stripe" } },
  configuration: { merchant: { capabilities: { card_payments: { status: "active" },
    stripe_balance: { payouts: { status: "active" } } } } }, ...changes,
});

// Models the safety-relevant catalog facts rather than executing SQL. Unknown
// queries fail so a new storage capability cannot silently pass these tests.
function fakePool(config, options = {}) {
  const state = { guard: options.existing === true,
    row: options.existing ? { singleton: true, format: "korlix-hosted-acceptance-staging-v1",
      config_hash: config.bindingHash, created_at: new Date(NOW).toISOString(), verified_at: null, evidence: null } : null };
  const queries = []; let connects = 0, releases = 0;
  return {
    state, queries, get connects() { return connects; }, get releases() { return releases; },
    async connect() {
      connects++;
      let before;
      return {
        async query(sql, args = []) {
          queries.push({ sql, args });
          const rows = (value) => ({ rows: value });
          if (sql === "BEGIN") { before = structuredClone(state); return rows([]); }
          if (sql === "ROLLBACK") { Object.assign(state, before); return rows([]); }
          if (sql === "COMMIT" || sql.startsWith("SET LOCAL ")) return rows([]);
          if (sql.includes("pg_try_advisory_xact_lock")) return rows([{ locked: options.locked !== false }]);
          if (sql.startsWith("SELECT current_database()")) return rows([{ database: options.database || EXPECTED_DATABASE, owner: "fixture_owner" }]);
          if (sql.includes("FROM pg_namespace WHERE")) return rows([{ schemas: 0, extensions: 0, event_triggers: 0, ...options.unsafe }]);
          if (sql.includes("FROM pg_depend")) {
            const objects = state.guard ? [{ catalog: "pg_class", id: "1", subid: 0 },
              { catalog: "pg_class", id: "2", subid: 0 }, { catalog: "pg_type", id: "3", subid: 0 },
              { catalog: "pg_type", id: "4", subid: 0 }] : [];
            return rows(options.foreignObjects ? [...objects, { catalog: "pg_class", id: "999", subid: 0 }] : objects);
          }
          if (sql.startsWith("CREATE TABLE")) { state.guard = true; return rows([]); }
          if (sql.startsWith("REVOKE ALL")) return rows([]);
          if (sql.startsWith("INSERT INTO")) {
            state.row = { singleton: true, format: args[0], config_hash: args[1], created_at: args[2], verified_at: null, evidence: null };
            return rows([]);
          }
          if (sql.includes("FROM pg_class c JOIN")) return rows(state.guard ? [{ id: "1", index_id: "2", type_id: "3", array_id: "4",
            relkind: "r", relrowsecurity: false, owner: "fixture_owner", ...options.table }] : []);
          if (sql.includes("FROM pg_attribute")) return rows([
            ["singleton", "boolean", true], ["format", "text", true], ["config_hash", "text", true],
            ["created_at", "timestamp with time zone", true], ["verified_at", "timestamp with time zone", false], ["evidence", "jsonb", false],
          ].map(([attname, type, attnotnull]) => ({ attname, type, attnotnull })));
          if (sql.includes("FROM pg_trigger")) return rows([{ triggers: 0, rules: 0, defaults: 0, ...options.hooks }]);
          if (sql.includes("FROM pg_constraint")) return rows((options.constraints || ["CHECK (singleton)",
            "CHECK ((format = 'korlix-hosted-acceptance-staging-v1'::text))",
            "CHECK ((config_hash ~ '^[a-f0-9]{64}$'::text))", "PRIMARY KEY (singleton)"])
            .map(definition => ({ definition, convalidated: true, condeferrable: false, condeferred: false })));
          if (sql.startsWith("SELECT singleton,")) return rows(state.row ? [{ ...state.row, ...options.row }] : []);
          if (sql.startsWith("UPDATE public.korlix_hosted_acceptance_state")) {
            assert.equal(args[2], state.row.config_hash);
            state.row.verified_at = args[0]; state.row.evidence = JSON.parse(args[1]);
            return { rows: [], rowCount: 1 };
          }
          assert.fail("Unexpected fixture database query: " + sql);
        },
        release() { releases++; },
      };
    },
  };
}
async function runningServer(config, options = {}) {
  const server = await createHostedAcceptanceServer(config, { now: () => NOW, ...options });
  server.listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  return {
    async request(path, { method = "POST", body = "{}", auth = true, headers = {} } = {}) {
      return new Promise((resolve, reject) => {
        const request = httpRequest(base + path, { method,
        headers: { host: config.host, "content-type": "application/json",
          ...(auth ? { authorization: "Bearer " + token } : {}), ...headers } }, (response) => {
          const chunks = [];
          response.on("data", chunk => chunks.push(chunk));
          response.on("end", () => {
            const text = Buffer.concat(chunks).toString("utf8");
            resolve({ status: response.statusCode, headers: new Headers(response.headers), text, data: /^application\/json/.test(response.headers["content-type"] || "") ? JSON.parse(text) : null });
          });
        });
        request.on("error", reject);
        request.end(method === "GET" ? undefined : body);
      });
    },
    async close() { server.closeAllConnections(); await new Promise((resolve) => server.close(resolve)); },
  };
}

test("configuration pins the dedicated database and sandbox; missing credentials stay explicitly blocked", () => {
  assert.equal(EXPECTED_DATABASE_HOST, "dpg-db1svtm0tbcc73caq380-a");
  assert.equal(EXPECTED_DATABASE, "korlix_2meetu_acceptance");
  assert.equal(EXPECTED_PLATFORM, "acct_1UN1QuLwavBaepoe");
  assert.equal(EXPECTED_MERCHANT, "acct_1UN1WiLwavcz7g46");
  const blank = configured(); assert.equal(blank.database, null); assert.equal(blank.key, null);
  assert.throws(() => hostedAcceptanceConfig({}, NOW));
  for (const change of [{ MODE: "true" }, { DATABASE_HOST: "production-db" }, { TOKEN_HASH: token.slice(1) },
    { ENCRYPTION_KEY: "a".repeat(64) }, { ENCRYPTION_KEY: token }, { ORIGIN: "http://acceptance.example.test" },
    { ORIGIN: "https://localhost" }, { EXPIRES_AT: new Date(NOW + 8 * DAY).toISOString() },
    { STRIPE_KEY: "sk_live_fixture" }, { WEBHOOK_SECRET: "whsec_fixture" }]) assert.throws(() => configured(change));
  const good = configured({ DATABASE_URL: DSN, STRIPE_KEY: "sk_test_fixture" });
  assert.deepEqual([good.database.host, good.database.database, good.database.port, good.database.ssl],
    [EXPECTED_DATABASE_HOST, EXPECTED_DATABASE, 5432, false]);
  assert(Object.isFrozen(good)); assert(Object.isFrozen(good.database));
});

test("database URLs and ambient credentials cannot redirect staging to other infrastructure", () => {
  for (const url of [DSN.replace(EXPECTED_DATABASE_HOST, "production.internal"), DSN.replace(EXPECTED_DATABASE, "postgres"),
    DSN.replace(":5432", ":6543"), DSN + "?sslmode=disable", DSN + "#suffix", DSN + "/",
    DSN.replace("fixture_owner:fixture_password@", ""), DSN.replace("postgresql:", "https:")])
    assert.throws(() => configured({ DATABASE_URL: url }), url);
  for (const [name, value] of Object.entries({ DATABASE_URL: DSN, SUPABASE_URL: "https://production.invalid",
    STRIPE_SECRET_KEY: "sk_test_unrelated", PGHOST: "production.internal", PGOPTIONS: "-c search_path=foreign_schema", RESEND_API_KEY: "fixture",
    KORLIX_SCHEDULING_STRIPE_SECRET_KEY: "sk_test_unrelated", KORLIX_WEB_STRIPE_ENABLED: "true" }))
    assert.throws(() => hostedAcceptanceConfig({ ...environment(), [name]: value }, NOW), name);
});

test("bootstrap creates only its guard, resumes its binding, and serializes through a database lock", async () => {
  const config = configured({ DATABASE_URL: DSN }), pool = fakePool(config);
  await bootstrapHostedAcceptanceDatabase(config, pool, { now: () => NOW });
  await bootstrapHostedAcceptanceDatabase(config, pool, { now: () => NOW });
  assert.equal(pool.queries.filter(q => q.sql.startsWith("CREATE TABLE")).length, 1);
  assert.equal(pool.queries.filter(q => q.sql.startsWith("INSERT INTO")).length, 1);
  assert.equal(pool.state.row.config_hash, config.bindingHash);
  assert(pool.queries.findIndex(q => q.sql.includes("pg_try_advisory_xact_lock")) < pool.queries.findIndex(q => q.sql.startsWith("CREATE TABLE")));
  assert.equal(pool.releases, 2);
  const locked = fakePool(config, { locked: false });
  await assert.rejects(bootstrapHostedAcceptanceDatabase(config, locked), /readiness_check_in_progress/);
  assert(!locked.queries.some(q => /^(CREATE|INSERT|UPDATE|REVOKE)/.test(q.sql)));
  assert(locked.queries.some(q => q.sql === "ROLLBACK")); assert.equal(locked.releases, 1);
});

test("bootstrap refuses foreign objects and mismatched sentinels without altering their schema", async () => {
  const config = configured({ DATABASE_URL: DSN });
  for (const options of [{ database: "production" }, { unsafe: { schemas: "1" } }, { unsafe: { extensions: "1" } },
    { foreignObjects: true }, { existing: true, foreignObjects: true },
    { existing: true, row: { config_hash: "f".repeat(64) } }, { existing: true, hooks: { triggers: "1" } },
    { existing: true, table: { owner: "other_owner" } }, { existing: true, hooks: { foreign_grants: 1 } },
    { existing: true, constraints: ["PRIMARY KEY (singleton)"] }]) {
    const pool = fakePool(config, options);
    await assert.rejects(bootstrapHostedAcceptanceDatabase(config, pool));
    assert(!pool.queries.some(q => /^(CREATE|INSERT|UPDATE|REVOKE|DROP|DELETE)/.test(q.sql)), JSON.stringify(options));
    assert(pool.queries.some(q => q.sql === "ROLLBACK")); assert.equal(pool.releases, 1);
  }
});

test("missing database or Stripe credentials leave payment and webhook runtime unavailable", async () => {
  for (const config of [configured(), configured({ DATABASE_URL: DSN })]) {
    let providerCalls = 0;
    const pool = fakePool(config), server = await runningServer(config, { pool, fetcher: () => { providerCalls++; assert.fail("Provider call before credentials"); } });
    try {
      const health = await server.request("/health", { method: "GET", auth: false });
      assert.equal(health.status, 200); assert.equal(health.data.readiness, "blocked");
      assert.equal(health.data.checkoutEnabled, false); assert.equal(health.data.paymentsConnected, false);
      assert.equal(health.data.webhookEnabled, false); assert.equal(health.data.identityVerified, false);
      assert(!health.text.includes(EXPECTED_MERCHANT)); assert(!health.text.includes(EXPECTED_PLATFORM));
      assert.equal((await server.request("/acceptance/verify")).status, 503);
      assert.equal(providerCalls, 0);
      if (!config.database) assert.equal(pool.connects, 0);
    } finally { await server.close(); }
  }
});

test("private operations reject browser requests, query tokens, malformed bodies and all payment routes", async () => {
  const server = await runningServer(configured());
  try {
    assert.equal((await server.request("/acceptance/status", { auth: false })).status, 401);
    assert.equal((await server.request("/acceptance/status", { headers: { authorization: "Bearer " + "0".repeat(64) } })).status, 401);
    for (const headers of [{ origin: "https://acceptance.example.test" }, { "sec-fetch-site": "same-origin" },
      { origin: "https://attacker.example.test" }]) assert.equal((await server.request("/acceptance/status", { headers })).status, 403);
    assert.equal((await server.request("/acceptance/status?token=" + token)).status, 404);
    assert.equal((await server.request("/acceptance/status", { headers: { host: "other.example.test" } })).status, 404);
    for (const body of ["[]", "null", "not-json", '{"confirmed":true}'])
      assert.equal((await server.request("/acceptance/verify", { body })).status, 400);
    assert.equal((await server.request("/acceptance/verify", { body: "x".repeat(4097) })).status, 413);
    for (const path of ["/acceptance/enable", "/acceptance/book", "/acceptance/checkout", "/acceptance/refund",
      "/acceptance/tick", "/api/scheduling/payments/webhook", "/api/scheduling/manage/checkout"])
      assert.equal((await server.request(path)).status, 404, path);
    const status = await server.request("/acceptance/status"); assert.equal(status.status, 200);
    assert.equal(status.headers.get("cache-control"), "no-store");
    assert.equal(status.headers.get("referrer-policy"), "no-referrer");
  } finally { await server.close(); }
});

test("readiness is serialized, performs only pinned identity reads, and never enables payments", async () => {
  const config = configured({ DATABASE_URL: DSN, STRIPE_KEY: "sk_test_fixture" }), pool = fakePool(config);
  const calls = []; let releasePlatform, entered;
  const started = new Promise(resolve => { entered = resolve; });
  const pause = new Promise(resolve => { releasePlatform = resolve; });
  const server = await runningServer(config, { pool, fetcher: async (url, options) => {
    calls.push({ url, options });
    if (calls.length === 1) { entered(); await pause; return json({ id: EXPECTED_PLATFORM, object: "account" }); }
    return json(merchant());
  } });
  try {
    assert.equal(calls.length, 0, "Startup must not read Stripe");
    const first = server.request("/acceptance/verify");
    await Promise.race([started, first.then(result => assert.fail("Verify ended before provider boundary: " + result.text))]);
    assert.equal((await server.request("/acceptance/verify")).status, 409);
    assert.equal(calls.length, 1);
    releasePlatform();
    const result = await first; assert.equal(result.status, 200);
    assert.equal(result.data.identityVerified, true); assert.equal(result.data.checkoutEnabled, false);
    assert.equal(result.data.paymentsConnected, false); assert.equal(result.data.webhookEnabled, false);
    assert.equal(result.data.readiness, "blocked");
    assert.equal(calls.length, 2);
    assert.equal(new URL(calls[0].url).pathname, "/v1/account");
    assert.equal(new URL(calls[1].url).pathname, "/v2/core/accounts/" + EXPECTED_MERCHANT);
    for (const { url, options } of calls) {
      assert.equal(new URL(url).origin, "https://api.stripe.com"); assert.equal(options.method || "GET", "GET");
      assert.equal(options.body, undefined); assert.equal(options.redirect, "error");
      const headers = new Headers(options.headers);
      assert.equal(headers.get("authorization"), "Bearer sk_test_fixture");
      assert.equal(headers.get("stripe-version"), "2026-09-30.endive"); assert.equal(headers.has("stripe-account"), false);
    }
    assert.equal(pool.state.row.evidence.platform, EXPECTED_PLATFORM);
    assert.equal(pool.state.row.evidence.merchant, EXPECTED_MERCHANT);
    assert.equal(pool.state.row.evidence.livemode, false);
  } finally { releasePlatform(); await server.close(); }
});

test("wrong provider identity or merchant readiness cannot create verified evidence", async () => {
  const cases = [
    { platform: { id: "acct_other", object: "account" }, expectedCalls: 1 },
    { platform: { id: EXPECTED_PLATFORM, object: "account", livemode: true }, expectedCalls: 1 },
    { merchant: merchant({ id: "acct_other" }), expectedCalls: 2 },
    { merchant: merchant({ defaults: { responsibilities: { fees_collector: "application", losses_collector: "stripe" } } }), expectedCalls: 2 },
    { merchant: merchant({ configuration: { merchant: { capabilities: { card_payments: { status: "pending" } } } } }), expectedCalls: 2 },
  ];
  for (const scenario of cases) {
    const config = configured({ DATABASE_URL: DSN, STRIPE_KEY: "sk_test_fixture" }), pool = fakePool(config); let calls = 0;
    const server = await runningServer(config, { pool, fetcher: async () => {
      calls++; return json(calls === 1 ? scenario.platform || { id: EXPECTED_PLATFORM, object: "account" } : scenario.merchant);
    } });
    try {
      assert.equal((await server.request("/acceptance/verify")).status, 503);
      assert.equal(calls, scenario.expectedCalls); assert.equal(pool.state.row.evidence, null);
      assert.equal((await server.request("/health", { method: "GET" })).data.identityVerified, false);
      assert(!pool.queries.some(q => q.sql.startsWith("UPDATE")));
    } finally { await server.close(); }
  }
});

test("expiry blocks private access and a verification that expires mid-flight cannot commit evidence", async () => {
  let clock = NOW;
  const config = configured({ DATABASE_URL: DSN, STRIPE_KEY: "sk_test_fixture" }), pool = fakePool(config); let calls = 0;
  const server = await runningServer(config, { pool, now: () => clock, fetcher: async () => {
    calls++;
    if (calls === 1) return json({ id: EXPECTED_PLATFORM, object: "account" });
    clock = config.expiresAt; return json(merchant());
  } });
  try {
    assert.equal((await server.request("/acceptance/verify")).status, 410);
    assert.equal(pool.state.row.evidence, null);
    assert(!pool.queries.some(q => q.sql.startsWith("UPDATE")));
    assert.equal((await server.request("/acceptance/status")).status, 410);
    assert.equal((await server.request("/acceptance/verify")).status, 410); assert.equal(calls, 2);
    const health = await server.request("/health", { method: "GET" }); assert.equal(health.status, 200);
    assert.equal(health.data.expired, true); assert.equal(health.data.identityVerified, false);
  } finally { await server.close(); }
});

test("upstream errors do not disclose credentials and failed database isolation prevents provider calls", async () => {
  const config = configured({ DATABASE_URL: DSN, STRIPE_KEY: "sk_test_sensitivefixture" });
  const pool = fakePool(config); let calls = 0;
  const server = await runningServer(config, { pool, fetcher: async () => {
    calls++; throw new Error(`private upstream failure ${config.key} ${DSN}`);
  } });
  try {
    const result = await server.request("/acceptance/verify"); assert.equal(result.status, 503);
    assert.equal(result.data.error, "readiness_verification_failed"); assert.equal(calls, 1);
    for (const secret of [config.key, DSN, "fixture_password", token]) assert(!result.text.includes(secret));
  } finally { await server.close(); }
  const blocked = await runningServer(config, { pool: fakePool(config, { foreignObjects: true }),
    fetcher: () => assert.fail("Unverified database must block provider access") });
  try {
    assert.equal((await blocked.request("/health", { method: "GET" })).data.databaseReady, false);
    assert.equal((await blocked.request("/acceptance/verify")).status, 503);
  } finally { await blocked.close(); }
});


test("payment runtime is explicit and exposes only its same-origin return shell when unconfigured", async () => {
  assert.throws(() => configured({ PAYMENT_RUNTIME: "true" }));
  assert.throws(() => configured({ WEBHOOK_ENDPOINT_ID: "we_fixture" }));
  const config = configured({ PAYMENT_RUNTIME: "scheduling-v2", WEBHOOK_SECRET: "whsec_fixture", WEBHOOK_ENDPOINT_ID: "we_fixture" });
  assert.equal(config.paymentRuntime, true);
  assert.equal(config.encryptionKey, "ab79d101c286fd54".repeat(4));
  const server = await runningServer(config, { fetcher: () => assert.fail("Unconfigured runtime must not contact Stripe") });
  try {
    const shell = await server.request("/book/manage", { method: "GET", auth: false });
    assert.equal(shell.status, 200);
    assert(shell.text.includes('/acceptance/assets/return.js'));
    assert.equal(shell.headers.get("cache-control"), "no-store");
    assert.equal(shell.headers.get("referrer-policy"), "no-referrer");
    assert(shell.headers.get("content-security-policy").includes("connect-src 'self'"));
    for (const path of ["/acceptance/assets/return.js", "/acceptance/assets/return.css"])
      assert.equal((await server.request(path, { method: "GET", auth: false })).status, 200);
    assert.equal((await server.request("/book/manage?token=" + token, { method: "GET", auth: false })).status, 404);
    assert.equal((await server.request("/book/manage", { method: "GET", headers: { host: "attacker.example" } })).status, 404);
    const body = JSON.stringify({ booking_id: "d8d5cac4-b461-43c0-8f06-07c38e1bce63", manage_token: "0".repeat(64) });
    for (const headers of [{}, { origin: "https://attacker.example" }, { origin: config.origin, "sec-fetch-site": "cross-site" }])
      assert.equal((await server.request("/acceptance/customer/status", { body, auth: false, headers })).status, 403);
    assert.equal((await server.request("/acceptance/customer/status", { body, auth: false, headers: { origin: config.origin } })).status, 503);
    assert.equal((await server.request("/acceptance/customer/status", { body: "{}", auth: false, headers: { origin: config.origin } })).status, 400);
    for (const command of ["enable", "pause", "book", "checkout", "refund", "tick"]) {
      assert.equal((await server.request("/acceptance/" + command, { auth: false })).status, 401);
      assert.equal((await server.request("/acceptance/" + command, { headers: { origin: config.origin } })).status, 403);
      assert.equal((await server.request("/acceptance/" + command)).status, 503);
    }
    const health = (await server.request("/health", { method: "GET", auth: false })).data;
    assert.equal(health.stage, "hosted-payment-runtime");
    assert.equal(health.checkoutEnabled, false);
    assert.equal(health.paymentsConnected, false);
    assert.equal(health.webhookEnabled, false);
    for (const value of [token, config.encryptionKey, config.webhook]) assert(!JSON.stringify(health).includes(value));
  } finally { await server.close(); }
});
