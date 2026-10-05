// Separate, deliberately incomplete hosted acceptance staging entrypoint.
// It cannot create bookings, payments, refunds, or webhook receipts. Do not
// import this module from the production server or pass production env groups.
import assert from "node:assert/strict";
import { createHash, timingSafeEqual } from "node:crypto";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { providerRequest } from "../../scheduling/provider_core.mjs";
import { stripeProvider } from "../../scheduling/stripe_provider.mjs";

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
  // Webhooks are not implemented at this stage. A secret here must not imply
  // that a destination exists or that signed events will be handled.
  assert(!setting(env, "WEBHOOK_SECRET"), "Webhook support is not implemented in staging.");
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
  return Object.freeze({ database, key, tokenHash, origin: originUrl.origin, host: originUrl.host,
    expiresAt, bindingHash: digest(JSON.stringify(binding)) });
}

class StagingError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
const fail = (status, code) => { throw new StagingError(status, code); };

async function begin(client) {
  await client.query("BEGIN");
  await client.query("SET LOCAL search_path = pg_catalog, public");
  await client.query("SET LOCAL lock_timeout = '3s'");
  await client.query("SET LOCAL statement_timeout = '10s'");
  await client.query("SET LOCAL idle_in_transaction_session_timeout = '45s'");
  const lock = await client.query("SELECT pg_try_advisory_xact_lock(135792468, 246813579) AS locked");
  if (lock.rows[0]?.locked !== true) fail(409, "readiness_check_in_progress");
}

async function inspectDatabase(client) {
  const identity = await client.query("SELECT current_database() AS database, current_user AS owner");
  assert.equal(identity.rows[0]?.database, EXPECTED_DATABASE, "Dedicated database identity mismatch.");
  const unsafe = await client.query(`SELECT
    (SELECT count(*) FROM pg_namespace WHERE nspname !~ '^pg_' AND nspname NOT IN ('public','information_schema')) AS schemas,
    (SELECT count(*) FROM pg_extension WHERE extname <> 'plpgsql') AS extensions,
    (SELECT count(*) FROM pg_event_trigger) AS event_triggers,
    (SELECT count(*) FROM pg_largeobject_metadata) AS large_objects,
    (SELECT count(*) FROM pg_foreign_server) AS foreign_servers,
    (SELECT count(*) FROM pg_publication) AS publications,
    (SELECT count(oid) FROM pg_subscription WHERE subdbid=(SELECT oid FROM pg_database WHERE datname=current_database())) AS subscriptions`);
  assert(unsafe.rows[0] && Object.values(unsafe.rows[0]).every(v => Number(v) === 0), "Dedicated database contains unrelated objects.");
  const objects = await client.query(`SELECT d.classid::regclass::text AS catalog, d.objid::text AS id, d.objsubid AS subid
    FROM pg_depend d WHERE d.refclassid='pg_namespace'::regclass
    AND d.refobjid='public'::regnamespace ORDER BY d.classid,d.objid,d.objsubid`);
  return { owner: identity.rows[0].owner, objects: objects.rows };
}

const COLUMNS = [
  ["singleton", "boolean", true], ["format", "text", true], ["config_hash", "text", true],
  ["created_at", "timestamp with time zone", true], ["verified_at", "timestamp with time zone", false],
  ["evidence", "jsonb", false],
];

async function validateState(client, config, inspection) {
  const table = await client.query(`SELECT c.oid::text AS id,c.reltype::text AS type_id,t.typarray::text AS array_id,
    i.indexrelid::text AS index_id,c.relkind,c.relrowsecurity,pg_get_userbyid(c.relowner) AS owner
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_type t ON t.oid=c.reltype
    LEFT JOIN pg_index i ON i.indrelid=c.oid AND i.indisprimary
    WHERE n.nspname='public' AND c.relname='${TABLE}'`);
  const row = table.rows[0];
  assert(table.rows.length === 1 && row.relkind === "r" && row.relrowsecurity === false && row.owner === inspection.owner && row.index_id,
    "Dedicated database guard is invalid.");
  const allowed = new Set(["pg_class:" + row.id, "pg_class:" + row.index_id, "pg_type:" + row.type_id, "pg_type:" + row.array_id]);
  assert(inspection.objects.length > 0 && inspection.objects.every(o => o.subid === 0 && allowed.has(o.catalog + ":" + o.id)),
    "Dedicated database contains unrelated objects.");
  const shape = await client.query(`SELECT attname,format_type(atttypid,atttypmod) AS type,attnotnull
    FROM pg_attribute WHERE attrelid=$1::oid AND attnum>0 AND NOT attisdropped ORDER BY attnum`, [row.id]);
  assert.deepEqual(shape.rows.map(c => [c.attname, c.type, c.attnotnull]), COLUMNS, "Dedicated database guard shape mismatch.");
  const hooks = await client.query(`SELECT
    (SELECT count(*) FROM pg_trigger WHERE tgrelid=$1::oid AND NOT tgisinternal) AS triggers,
    (SELECT count(*) FROM pg_rewrite WHERE ev_class=$1::oid) AS rules,
    (SELECT count(*) FROM pg_attrdef WHERE adrelid=$1::oid) AS defaults,
    (SELECT count(*) FROM pg_class c, LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
      WHERE c.oid=$1::oid AND a.grantee<>c.relowner) AS foreign_grants`, [row.id]);
  assert(hooks.rows[0] && Object.values(hooks.rows[0]).every(v => Number(v) === 0), "Dedicated database guard has unexpected behavior.");
  const constraints = await client.query(`SELECT pg_get_constraintdef(oid) AS definition,convalidated,condeferrable,condeferred
    FROM pg_constraint WHERE conrelid=$1::oid AND contype<>'n'`, [row.id]);
  assert(constraints.rows.every(c => c.convalidated && !c.condeferrable && !c.condeferred), "Dedicated database guard constraints were changed.");
  assert.deepEqual(constraints.rows.map(c => c.definition).sort(), ["CHECK (singleton)",
    `CHECK ((format = '${FORMAT}'::text))`, "CHECK ((config_hash ~ '^[a-f0-9]{64}$'::text))", "PRIMARY KEY (singleton)"].sort(),
  "Dedicated database guard constraints were changed.");
  const state = await client.query(`SELECT singleton,format,config_hash,created_at,verified_at,evidence FROM public.${TABLE}`);
  assert(state.rows.length === 1 && state.rows[0].singleton === true && state.rows[0].format === FORMAT &&
    state.rows[0].config_hash === config.bindingHash, "Dedicated database belongs to another acceptance configuration.");
  return state.rows[0];
}

export async function bootstrapHostedAcceptanceDatabase(config, pool, { now = Date.now } = {}) {
  assert(config.database, "The dedicated database credential is required.");
  const client = await pool.connect();
  try {
    await begin(client);
    let inspection = await inspectDatabase(client);
    if (inspection.objects.length === 0) {
      await client.query(`CREATE TABLE public.${TABLE} (
        singleton boolean PRIMARY KEY CHECK(singleton),
        format text NOT NULL CHECK(format='${FORMAT}'),
        config_hash text NOT NULL CHECK(config_hash ~ '^[a-f0-9]{64}$'),
        created_at timestamptz NOT NULL, verified_at timestamptz, evidence jsonb
      )`);
      await client.query(`REVOKE ALL ON public.${TABLE} FROM PUBLIC`);
      await client.query(`INSERT INTO public.${TABLE}(singleton,format,config_hash,created_at) VALUES(true,$1,$2,$3)`,
        [FORMAT, config.bindingHash, new Date(now()).toISOString()]);
      inspection = await inspectDatabase(client);
    }
    const state = await validateState(client, config, inspection);
    await client.query("COMMIT");
    return { createdAt: new Date(state.created_at).toISOString(), lastVerifiedAt: state.verified_at ? new Date(state.verified_at).toISOString() : null };
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally { client.release(); }
}

const HEADERS = {
  "Cache-Control": "no-store", Pragma: "no-cache", "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff", "X-Robots-Tag": "noindex, nofollow, noarchive",
  "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
};

async function readEmptyJson(req) {
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
  if (!body || Array.isArray(body) || typeof body !== "object" || Object.keys(body).length) fail(400, "empty_json_object_required");
}

export async function createHostedAcceptanceServer(config, { pool, fetcher = fetch, now = Date.now } = {}) {
  let ownedPool = false, databaseReady = false, databaseState = null, identity = null, running = false;
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
    } catch { databaseReady = false; }
  }
  const health = () => ({ mode: "hosted-sandbox-acceptance-staging", stage: "identity-readiness-only", readiness: "blocked",
    checkoutEnabled: false, paymentsConnected: false, webhookEnabled: false, databaseReady,
    identityVerified: !!identity && now() < config.expiresAt, expired: now() >= config.expiresAt,
    blockedReasons: [!config.database ? "database_credential_missing" : !databaseReady ? "database_isolation_unverified" : null,
      !config.key ? "stripe_test_key_missing" : !identity ? "sandbox_identity_unverified" : null,
      now() >= config.expiresAt ? "acceptance_expired" : null, "payment_runtime_not_implemented"].filter(Boolean) });
  const status = () => ({ ...health(), expectedPlatform: EXPECTED_PLATFORM, expectedMerchant: EXPECTED_MERCHANT,
    database: databaseState, identity, expiresAt: new Date(config.expiresAt).toISOString() });
  async function verify() {
    if (!databaseReady || !pool) fail(503, "database_isolation_unverified");
    if (!config.key) fail(503, "stripe_test_key_missing");
    const client = await pool.connect();
    identity = null;
    try {
      await begin(client);
      try {
        const inspection = await inspectDatabase(client);
        await validateState(client, config, inspection);
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
  const server = createServer(async (req, res) => {
    try {
      if (!req.url.startsWith("/") || req.url.startsWith("//")) return send(res, 404, { error: "not_found" });
      const url = new URL(req.url, config.origin);
      if (url.search || url.hash) return send(res, 404, { error: "not_found" });
      if (req.method === "GET" && url.pathname === "/health") return send(res, 200, health());
      if (req.headers.host !== config.host || req.method !== "POST" || !["/acceptance/status", "/acceptance/verify"].includes(url.pathname))
        return send(res, 404, { error: "not_found" });
      if (limited(req)) return send(res, 429, { error: "rate_limited" });
      if (req.headers.origin || req.headers["sec-fetch-site"]) return send(res, 403, { error: "private_command_client_required" });
      const supplied = /^Bearer ([a-f0-9]{64})$/.exec(req.headers.authorization || "");
      if (!supplied || !timingSafeEqual(Buffer.from(digest(supplied[1]), "hex"), Buffer.from(config.tokenHash, "hex")))
        return send(res, 401, { error: "private_control_token_required" });
      if (now() >= config.expiresAt) return send(res, 410, { error: "acceptance_expired" });
      await readEmptyJson(req);
      if (url.pathname === "/acceptance/status") return send(res, 200, status());
      if (running) return send(res, 409, { error: "readiness_check_in_progress" });
      running = true;
      try { return send(res, 200, await verify()); }
      finally { running = false; }
    } catch (error) {
      if (!res.headersSent) send(res, error instanceof StagingError ? error.status : 503,
        { error: error instanceof StagingError ? error.code : "readiness_verification_failed" });
      else res.end();
    }
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  server.on("close", () => { if (ownedPool) void pool.end().catch(() => {}); });
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const config = hostedAcceptanceConfig(process.env);
    const server = await createHostedAcceptanceServer(config);
    const port = Number(process.env.PORT || 10000);
    assert(Number.isInteger(port) && port > 0 && port <= 65535, "Invalid service port.");
    server.listen(port, "0.0.0.0", () => console.log("Hosted sandbox acceptance staging ready; payment operations unavailable."));
    process.once("SIGTERM", () => { server.close(); server.closeAllConnections(); });
  } catch {
    console.error("Hosted acceptance staging configuration rejected; no configuration values displayed.");
    process.exitCode = 1;
  }
}
