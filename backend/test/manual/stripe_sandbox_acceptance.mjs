// Manual, isolated provider acceptance. This file is never imported by production.
import assert from "node:assert/strict";
import { randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import express from "express";
import { PGlite } from "@electric-sql/pglite";
import { registerScheduling } from "../../scheduling/routes.mjs";
import { event, secret } from "../../scheduling/core.mjs";
import { providerCipher, providerSettings } from "../../scheduling/provider_core.mjs";
import { stripeProvider } from "../../scheduling/stripe_provider.mjs";

const PUBLIC_ORIGIN = "https://korlix-acceptance.invalid";
const EVENTS = new Set(["checkout.session.completed", "checkout.session.expired",
  "checkout.session.async_payment_succeeded", "checkout.session.async_payment_failed", "charge.refunded"]);
const ATTACHED_PLATFORM_IDS = new Set(["acct_1UMs8D22E1oIiTRb", "acct_1UMI5OLx6hd5l5Vo"]);
const account = (value) => /^acct_[A-Za-z0-9]+$/.test(value || "");
const safeEqual = (a, b) => typeof a === "string" && typeof b === "string" &&
  Buffer.byteLength(a) === Buffer.byteLength(b) && timingSafeEqual(Buffer.from(a), Buffer.from(b));
const privateWrite = (path, value) => writeFile(path, JSON.stringify(value), { mode: 0o600 });

export function acceptanceConfig(input = {}) {
  assert.equal(input.KORLIX_ACCEPTANCE_RUN, "isolated-stripe-sandbox", "Explicit isolated acceptance opt-in is required.");
  const key = input.KORLIX_ACCEPTANCE_STRIPE_SECRET_KEY || "";
  assert.match(key, /^(?:sk|rk|rkcs)_test_[A-Za-z0-9]+$/, "A dedicated acceptance test API key is required.");
  const webhook = input.KORLIX_ACCEPTANCE_WEBHOOK_SECRET || "";
  assert.match(webhook, /^whsec_[A-Za-z0-9]+$/, "A CLI acceptance signing secret is required.");
  const platform = input.KORLIX_ACCEPTANCE_PLATFORM_ID;
  const merchant = input.KORLIX_ACCEPTANCE_MERCHANT_ID;
  assert(account(platform) && account(merchant) && platform !== merchant, "Supply distinct expected sandbox platform and merchant IDs.");
  assert(!ATTACHED_PLATFORM_IDS.has(platform) && !ATTACHED_PLATFORM_IDS.has(merchant), "The live account and production-attached sandbox cannot be used by this harness.");
  const port = Number(input.KORLIX_ACCEPTANCE_PORT ?? 8787);
  assert(Number.isInteger(port) && (port === 0 || (port >= 1024 && port <= 65535)), "Use a loopback port from 1024 through 65535, or 0 for a free port.");
  return { key, webhook, platform, merchant, port };
}

export async function createAcceptanceHarness({ environment = {}, fetcher = fetch, resumeDirectory } = {}) {
  const config = acceptanceConfig(environment); // Validate before disk, network, or database work.
  const directory = resumeDirectory ? resolve(resumeDirectory) : await mkdtemp(join(tmpdir(), "korlix-stripe-acceptance-"));
  let state;
  if (resumeDirectory) {
    state = JSON.parse(await readFile(join(directory, "private-state.json"), "utf8"));
    assert.equal(state.format, "isolated-stripe-acceptance-v1");
    assert.equal(state.platform, config.platform, "Resume sandbox mismatch.");
    assert.equal(state.merchant, config.merchant, "Resume merchant mismatch.");
  } else {
    state = { format: "isolated-stripe-acceptance-v1", platform: config.platform, merchant: config.merchant,
      host: randomUUID(), encryptionKey: randomBytes(32).toString("base64"),
      controlToken: secret(), bookings: {}, eventId: null, slug: null };
    await privateWrite(join(directory, "private-state.json"), state);
  }
  const save = () => privateWrite(join(directory, "private-state.json"), state);
  const db = new PGlite(join(directory, "database"));
  const rpc = async (name, args) => (await db.query(
    `select ${name}(${Object.keys(args).map((key, i) => key + "=>$" + (i + 1)).join(",")}) value`, Object.values(args))).rows[0].value;
  const owner = (action, id = null, data = {}) => rpc("korlix_schedule_owner_v1", { p_actor: state.host, p_action: action, p_id: id, p_data: data });
  const payment = (action, id = null, data = {}) => rpc("korlix_schedule_payment_v2", { p_action: action, p_id: id, p_data: data });
  const database = { rpc: async (name, args) => {
    assert(/^korlix_schedule_[a-z_]+_v[12]$/.test(name), "Only local scheduling RPCs are allowed.");
    try { return { data: await rpc(name, args) }; } catch (error) { return { error }; }
  } };
  try {
    if (!resumeDirectory) {
      await db.exec("create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,is_anonymous boolean);create table user_profiles(id uuid primary key,tier text,is_disabled boolean);grant usage on schema public,auth to service_role,anon,authenticated;grant select,insert,update on user_profiles,auth.users to service_role;");
      for (const name of ["20260930152919_scheduling_engine.sql", "20260930163605_scheduling_connected.sql"])
        await db.exec(await readFile(new URL("../../../supabase/migrations/" + name, import.meta.url), "utf8"));
    }
    await db.exec("set role service_role");
    if (!resumeDirectory) {
      await db.query("insert into auth.users values($1,now(),false)", [state.host]);
      await db.query("insert into user_profiles values($1,'basic',false)", [state.host]);
      await owner("save_profile", null, { revision: 0, display_name: "Isolated sandbox host", timezone: "UTC",
        weekly: Array.from({ length: 7 }, (_, day) => ({ day, windows: [[540, 1020]] })), overrides: [] });
    }
  } catch (error) { await db.close(); throw error; }

  // Construct a new environment. Never copy process.env into scheduling.
  const env = { NODE_ENV: "test", KORLIX_SCHEDULING_PUBLIC_URL: PUBLIC_ORIGIN,
    KORLIX_SCHEDULING_TOKEN_KEY: state.encryptionKey,
    KORLIX_SCHEDULING_STRIPE_CLIENT_ID: "ca_local_acceptance_no_oauth",
    KORLIX_SCHEDULING_STRIPE_SECRET_KEY: config.key,
    KORLIX_SCHEDULING_STRIPE_WEBHOOK_SECRET: config.webhook,
    KORLIX_SCHEDULING_STRIPE_ENABLED: "false" };
  const settings = providerSettings(env, PUBLIC_ORIGIN);
  const cipher = providerCipher(env);
  let outboundCount = 0;
  async function guardedFetch(url, options = {}) {
    const u = new URL(url);
    assert.equal(u.origin, "https://api.stripe.com", "Only the Stripe API is allowed.");
    const headers = new Headers(options.headers);
    assert.equal(headers.get("authorization"), "Bearer " + config.key);
    const merchant = headers.get("stripe-account");
    const method = options.method || "GET";
    const platformRead = ["/v1/account", "/v1/webhook_endpoints"].includes(u.pathname) && method === "GET" && !merchant;
    const merchantRead = u.pathname === "/v2/core/accounts/" + config.merchant && method === "GET" && !merchant;
    const paymentRead = method === "GET" && /^\/v1\/(checkout\/sessions\/cs_[A-Za-z0-9_]+|refunds\/re_[A-Za-z0-9_]+|charges\/ch_[A-Za-z0-9_]+|payment_intents\/pi_[A-Za-z0-9_]+)$/.test(u.pathname);
    const paymentWrite = method === "POST" && ["/v1/checkout/sessions", "/v1/refunds"].includes(u.pathname);
    assert(platformRead || merchantRead || ((paymentRead || paymentWrite) && merchant === config.merchant), "Request is outside the allowlisted acceptance scope.");
    if (paymentWrite) {
      const body = new URLSearchParams(options.body);
      const booking = body.get("metadata[korlix_booking]");
      assert(Object.hasOwn(state.bookings, booking || ""), "Payment writes require this harness's local booking.");
      if (u.pathname === "/v1/checkout/sessions") {
        assert.equal(body.get("customer_email"), "sandbox-guest@example.test");
        assert.equal(body.get("line_items[0][price_data][unit_amount]"), "100");
        for (const key of ["success_url", "cancel_url"]) assert.equal(new URL(body.get(key)).origin, PUBLIC_ORIGIN);
      }
    }
    outboundCount++;
    return fetcher(url, { ...options, redirect: "error" });
  }
  const provider = stripeProvider(settings.providers.stripe, { fetcher: guardedFetch, diagnostic: () => {} });
  let readiness = null;
  async function verify() {
    const response = await guardedFetch("https://api.stripe.com/v1/account", {
      headers: { Authorization: "Bearer " + config.key, "Stripe-Version": settings.providers.stripe.version }, signal: AbortSignal.timeout(15000) });
    assert.equal(response.status, 200, "Sandbox platform identity lookup failed.");
    const identity = await response.json();
    assert(identity.object === "account" && identity.id === config.platform && identity.livemode !== true, "Sandbox platform identity mismatch.");
    const endpointResponse = await guardedFetch("https://api.stripe.com/v1/webhook_endpoints?limit=100", {
      headers: { Authorization: "Bearer " + config.key, "Stripe-Version": settings.providers.stripe.version }, signal: AbortSignal.timeout(15000) });
    assert.equal(endpointResponse.status, 200, "Sandbox webhook isolation lookup failed.");
    const endpoints = await endpointResponse.json();
    // Fresh sandbox only: fail closed if pagination or any enabled persisted
    // destination might also receive these local-test payment events.
    assert(endpoints.object === "list" && endpoints.has_more === false && Array.isArray(endpoints.data) &&
      endpoints.data.every((endpoint) => endpoint.object === "webhook_endpoint" && endpoint.status === "disabled" && endpoint.livemode === false),
    "Isolated acceptance requires no enabled persisted webhook endpoints; do not change production endpoints to pass this check.");
    const merchant = await provider.identity({ account_id: config.merchant, livemode: false });
    assert.equal(merchant.readiness_source, "accounts_v2");
    assert.equal(merchant.charges_enabled, true, "Sandbox merchant card payments and payouts must both be active.");
    readiness = { platform: config.platform, merchant: merchant.id, livemode: false,
      source: merchant.readiness_source, cards: merchant.card_payments_status, payouts: merchant.payouts_status,
      persistedWebhooksEnabled: 0, checkedAt: new Date().toISOString() };
    return readiness;
  }

  let service, application, enabled = false, server, base;
  const outer = express();
  outer.disable("x-powered-by");
  outer.use((q, r, next) => {
    // Loopback binding alone does not block browser-driven requests. Require a
    // private control token and reject browser origins on every local command.
    r.set("Cache-Control", "no-store");
    if (q.headers.origin || q.headers["sec-fetch-site"]) return r.status(403).json({ error: "Use the local command client." });
    const host = q.headers.host || "";
    if (!/^(127\.0\.0\.1|localhost)(:\d+)?$/.test(host)) return r.status(403).json({ error: "Loopback host required." });
    const webhook = q.method === "POST" && q.path === "/api/scheduling/payments/webhook";
    if (!webhook && !safeEqual(q.headers.authorization, "Bearer " + state.controlToken)) return r.status(401).json({ error: "Local control token required." });
    next();
  });
  outer.use(express.json({ limit: "1mb", verify: (q, _r, bytes) => { q.korlixSchedulingRawBody = Buffer.from(bytes); } }));
  let lastDelivery = null;
  outer.post("/api/scheduling/payments/webhook", (q, r, next) => {
    if (q.body?.account !== config.merchant || q.body?.livemode !== false || !EVENTS.has(q.body?.type))
      return r.status(400).json({ error: "Event is outside this sandbox merchant acceptance run." });
    // Preserve exact bytes/header locally for a duplicate-delivery check.
    const candidate = { raw: q.korlixSchedulingRawBody, signature: q.get("stripe-signature"), id: q.body.id };
    r.on("finish", () => { if (r.statusCode === 200) lastDelivery = candidate; });
    next();
  });
  function mount(active) {
    service?.connected.stop(); service?.notifications.stop();
    application = express();
    service = registerScheduling(application, { database, environment: { ...env, KORLIX_SCHEDULING_STRIPE_ENABLED: String(active) },
      requireUser: async (q) => safeEqual(q.headers.authorization, "Bearer " + state.controlToken)
        ? { id: state.host, email: "sandbox-host@example.test", email_confirmed_at: "2026-01-01", is_anonymous: false } : null,
      autoStartWorker: false, fetcher: guardedFetch });
    enabled = active;
  }
  mount(false);
  async function local(path, body) {
    const r = await fetch(base + "/api/scheduling" + path, { method: body ? "POST" : "GET",
      headers: { "content-type": "application/json", authorization: "Bearer " + state.controlToken },
      ...(body ? { body: JSON.stringify(body) } : {}) });
    const data = await r.json();
    assert(r.ok, `Local scheduling route failed (${r.status}): ${data.error || "unknown error"}`);
    return { data, cookie: r.headers.get("set-cookie")?.split(";")[0] };
  }
  async function seed() {
    if (state.eventId) return;
    await verify();
    const grant = { account_id: config.merchant, livemode: false };
    await db.query("insert into korlix_schedule_connections(owner_id,provider,remote_id,label,sealed_grant,config_hash,enabled,charges_enabled,livemode)values($1,'stripe',$2,'Isolated sandbox merchant',$3,$4,true,true,false)",
      [state.host, config.merchant, cipher.seal(grant, `${state.host}:stripe:${config.merchant}`), settings.providers.stripe.fingerprint]);
    const e = await owner("save_event", null, { ...event({ revision: 0, title: "Isolated sandbox acceptance — USD 1.00",
      description: "Synthetic local test appointment", kind: "one_to_one", duration_minutes: 30, interval_minutes: 30,
      buffer_before: 0, buffer_after: 0, notice_minutes: 0, horizon_days: 365, daily_limit: 40, capacity: 1,
      cancel_notice_minutes: 0, location_kind: "video", location_detail: "https://example.test/no-meeting",
      questions: [], color: "#72D6EB", price_cents: 100, refund_policy: "Synthetic sandbox payment; full refund during acceptance." }),
      slug: "sandbox-" + secret().slice(0, 20) });
    const published = await owner("event_state", e.id, { revision: e.revision, state: "published", confirmed: true });
    state.eventId = published.id; state.slug = published.slug; await save();
  }
  const known = (id) => { assert(Object.hasOwn(state.bookings, id || ""), "Choose a booking from this local run."); return state.bookings[id]; };
  async function status() {
    const bookings = [];
    for (const id of Object.keys(state.bookings)) {
      const p = await payment("private", id);
      bookings.push({ id, bookingState: p.booking.state, paymentState: p.payment_state, refundState: p.refund_state,
        checkoutId: p.checkout_id, paymentIntentId: p.payment_intent_id, refundId: p.refund_id,
        amountCents: p.amount_cents, currency: p.currency, livemode: p.livemode });
    }
    return { isolated: true, checkoutEnabled: enabled, readiness, outboundCount, bookings,
      receivedEvents: (await db.query("select provider_event_id,account_id,kind from korlix_schedule_payment_receipts order by received_at")).rows };
  }
  let commandRunning = false;
  outer.all("/acceptance/:command", async (q, r) => {
    if (commandRunning) return r.status(409).json({ error: "An acceptance command is already running." });
    commandRunning = true;
    try {
      const command = q.params.command;
      if (command === "status" && q.method === "GET") return r.json(await status());
      assert.equal(q.method, "POST", "Use POST for acceptance commands.");
      if (["enable", "book", "checkout", "refund"].includes(command)) assert.equal(q.body?.confirmed, true, "Explicit confirmed:true is required.");
      if (command === "verify") return r.json(await verify());
      if (command === "enable") { await verify(); await seed(); mount(true); return r.json({ checkoutEnabled: true, isolated: true }); }
      if (command === "pause") { mount(false); return r.json({ checkoutEnabled: false }); }
      if (command === "book") {
        assert(enabled, "Local checkout is paused."); await verify();
        const context = await local("/public/" + state.slug + "/context", {});
        const start = new Date(); start.setUTCDate(start.getUTCDate() + 2 + Object.keys(state.bookings).length); start.setUTCHours(12, 0, 0, 0);
        const manage = secret();
        const response = await fetch(base + "/api/scheduling/public/" + state.slug + "/book", { method: "POST",
          headers: { "content-type": "application/json", authorization: "Bearer " + state.controlToken, cookie: context.cookie },
          body: JSON.stringify({ context_token: context.data.context_token, request_id: randomUUID(), manage_token: manage,
            starts_at: start.toISOString(), guest_name: "Synthetic sandbox guest", guest_email: "sandbox-guest@example.test",
            guest_timezone: "UTC", answers: {}, confirmed: true }) });
        const result = await response.json(); assert.equal(response.status, 201, result.error || "Local booking failed.");
        const id = result.booking.id; state.bookings[id] = { manage }; await save();
        return r.json({ bookingId: id, bookingState: result.booking.state, amountCents: 100 });
      }
      if (command === "checkout") {
        const id = q.body.bookingId; const booking = known(id); await verify();
        await local("/manage/checkout", { booking_id: id, manage_token: booking.manage, confirmed: true });
        const p = await payment("private", id);
        assert.equal(p.livemode, false); return r.json({ bookingId: id, checkoutUrl: p.checkout_url, checkoutId: p.checkout_id,
          note: "The reserved local return URL will not load on an iPad; signed webhook confirmation is checked here." });
      }
      if (command === "reconcile") { known(q.body.bookingId); await service.connected.reconcile(q.body.bookingId); return r.json(await status()); }
      if (command === "refund") {
        const id = q.body.bookingId; known(id); const p = await payment("private", id);
        await local("/bookings/" + id + "/refund", { confirmed: true, revision: p.booking.revision });
        await service.connected.tick(); return r.json(await status());
      }
      if (command === "tick") { await service.connected.tick(); return r.json(await status()); }
      if (command === "duplicate") {
        assert(lastDelivery, "No successful signed webhook delivery has been observed.");
        const before = await status();
        const response = await fetch(base + "/api/scheduling/payments/webhook", { method: "POST", headers: {
          "content-type": "application/json", "stripe-signature": lastDelivery.signature }, body: lastDelivery.raw });
        assert.equal(response.status, 200, "Replay must occur within Stripe's five-minute signature window.");
        const after = await status(); assert.deepEqual(after.bookings, before.bookings); assert.deepEqual(after.receivedEvents, before.receivedEvents);
        return r.json({ duplicateDeliveryIdempotent: true, eventId: lastDelivery.id });
      }
      if (command === "fee-proof") {
        const id = q.body.bookingId; known(id); const p = await payment("private", id);
        assert(/^pi_[A-Za-z0-9_]+$/.test(p.payment_intent_id || ""), "Payment confirmation is required first.");
        const response = await guardedFetch("https://api.stripe.com/v1/payment_intents/" + p.payment_intent_id + "?expand[]=latest_charge", {
          headers: { Authorization: "Bearer " + config.key, "Stripe-Version": settings.providers.stripe.version, "Stripe-Account": config.merchant }, signal: AbortSignal.timeout(15000) });
        assert.equal(response.status, 200); const intent = await response.json(); const charge = intent.latest_charge;
        assert.equal(intent.livemode, false); assert.equal(charge?.livemode, false); assert.equal(charge?.amount, 100);
        assert.equal(charge?.application_fee, null); assert.equal(charge?.application_fee_amount, null);
        return r.json({ connectedAccount: config.merchant, paymentIntentId: intent.id, chargeId: charge.id,
          livemode: false, amountCents: charge.amount, applicationFee: charge.application_fee, applicationFeeAmount: charge.application_fee_amount });
      }
      throw new Error("Unknown acceptance command.");
    } catch (error) {
      // Assertion text is ours; upstream provider messages/payloads and keys are never returned.
      r.status(400).json({ error: error.name === "AssertionError" ? error.message.split("\n")[0] : "Acceptance operation failed; inspect safe local state before retrying." });
    } finally { commandRunning = false; }
  });
  outer.use((q, r, next) => application(q, r, next));
  server = outer.listen(config.port, "127.0.0.1");
  await new Promise((done, reject) => { server.once("listening", done); server.once("error", reject); });
  base = "http://127.0.0.1:" + server.address().port;
  const tokenFile = join(directory, "control-token"); await writeFile(tokenFile, state.controlToken, { mode: 0o600 });
  return { base, directory, tokenFile, controlToken: state.controlToken,
    async close() { service.connected.stop(); service.notifications.stop(); server.closeAllConnections(); await new Promise((done) => server.close(done)); await db.close(); } };
}

const invoked = process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
if (invoked) {
  const args = process.argv.slice(2);
  if (args[0] !== "--serve") {
    console.log("Manual harness only. No network calls made. Read docs/STRIPE_SANDBOX_LOCAL_ACCEPTANCE.md and use --serve with acceptance-only environment variables.");
  } else {
    try {
      assert(args.length === 1 || (args.length === 3 && args[1] === "--resume"), "Use --serve [--resume DIRECTORY].");
      const harness = await createAcceptanceHarness({ environment: process.env, resumeDirectory: args[2] });
      console.log(JSON.stringify({ localApi: harness.base, directory: harness.directory, controlTokenFile: harness.tokenFile,
        checkoutEnabled: false, networkRequestsMade: 0 }));
      for (const signal of ["SIGINT", "SIGTERM"]) process.once(signal, () => { void harness.close().then(() => process.exit(0)); });
    } catch { console.error("Acceptance startup rejected. Check the dedicated test-only configuration and resume directory; no credentials are displayed."); process.exitCode = 1; }
  }
}
