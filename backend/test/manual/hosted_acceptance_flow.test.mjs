import test from "node:test";
import assert from "node:assert/strict";
import { createHmac, randomUUID } from "node:crypto";
import { PGlite } from "@electric-sql/pglite";
import { bootstrapHostedAcceptanceDatabase } from "./hosted_acceptance_database.mjs";
import { createHostedAcceptanceFlow } from "./hosted_acceptance_flow.mjs";

const PLATFORM = "acct_1UN1QuLwavBaepoe", MERCHANT = "acct_1UN1WiLwavcz7g46";
const VERSION = "2026-09-30.endive", ORIGIN = "https://hosted.example.test";
const EVENTS = ["checkout.session.completed", "checkout.session.expired", "checkout.session.async_payment_succeeded",
  "checkout.session.async_payment_failed", "charge.refunded"];
const json = (value) => new Response(JSON.stringify(value), { headers: { "content-type": "application/json" } });

async function fixture(t, overrides = {}) {
  const db = new PGlite(); await db.waitReady; t.after(() => db.close());
  let clock = Date.now();
  const config = { paymentRuntime: true, bindingHash: "ac18b97f".repeat(8), database: { database: "korlix_2meetu_acceptance" },
    encryptionKey: "aabb1212".repeat(8), key: "rk_test_FixturePrivateKey", webhook: "whsec_FixtureSigningKey", endpointId: "we_fixture",
    origin: ORIGIN, expiresAt: clock + 86400000, ...overrides };
  const queries = [];
  const client = { async query(sql, values) {
    queries.push(sql);
    // The only PostgreSQL fixture substitution is the engine's database name.
    const executable = sql.replace(/^(\s*SELECT\s+)current_database\(\)(\s+AS\s+database\b)/i,
      "$1'korlix_2meetu_acceptance'::text$2");
    const result = values?.length ? await db.query(executable, values) : (await db.exec(executable)).at(-1) ?? { rows: [] };
    return { ...result, rowCount: result.affectedRows ?? result.rows?.length ?? 0 };
  }, release() {} };
  const pool = { connect: async () => client };
  await bootstrapHostedAcceptanceDatabase({ ...config, paymentRuntime: false }, pool, { now: () => clock });
  await bootstrapHostedAcceptanceDatabase(config, pool, { now: () => clock });
  const calls = [], sessions = new Map();
  const stripe = { paid: false, creates: 0, refunds: 0, loseCheckoutResponse: false, wrongPlatform: false, wrongEndpoint: false,
    merchantActive: true, holdRead: null, chargeWrong: false, hasPlatformFee: false };
  async function fetcher(url, options) {
    const u = new URL(url), headers = new Headers(options.headers), method = options.method || "GET";
    calls.push({ path: u.pathname, method, body: options.body, account: headers.get("stripe-account"), redirect: options.redirect });
    assert.equal(options.redirect, "error");
    assert.equal(headers.get("authorization"), "Bearer " + config.key);
    assert.equal(headers.get("stripe-version"), VERSION);
    if (u.pathname === "/v1/account") {
      if (stripe.holdRead) await stripe.holdRead;
      return json({ id: stripe.wrongPlatform ? "acct_foreign" : PLATFORM, object: "account", livemode: false });
    }
    if (u.pathname === "/v2/core/accounts/" + MERCHANT) return json({ id: MERCHANT, object: "v2.core.account", livemode: false, dashboard: "full",
      defaults: { responsibilities: { fees_collector: "stripe", losses_collector: "stripe" } },
      configuration: { merchant: { capabilities: { card_payments: { status: stripe.merchantActive ? "active" : "pending" },
        stripe_balance: { payouts: { status: "active" } } } } } });
    if (u.pathname === "/v1/webhook_endpoints/we_fixture") return json({ id: "we_fixture", object: "webhook_endpoint", livemode: false,
      status: "enabled", api_version: VERSION, url: stripe.wrongEndpoint ? ORIGIN + "/wrong" : ORIGIN + "/acceptance/payments/webhook",
      enabled_events: EVENTS }); // No connect field exists in Stripe's GET shape.
    assert.equal(headers.get("stripe-account"), MERCHANT);
    if (u.pathname === "/v1/checkout/sessions" && method === "POST") {
      const wire = new URLSearchParams(options.body), booking = wire.get("metadata[korlix_booking]");
      assert.equal(wire.get("line_items[0][price_data][unit_amount]"), "100");
      assert(![...wire.keys()].some((key) => /application_fee|transfer_data|on_behalf_of/.test(key)));
      const key = headers.get("idempotency-key");
      if (!sessions.has(key)) {
        stripe.creates++;
        sessions.set(key, { id: "cs_test_HostedFixture", object: "checkout.session", client_reference_id: booking,
          metadata: { korlix_booking: booking }, mode: "payment", livemode: false, currency: "usd", amount_total: 100,
          status: "open", payment_status: "unpaid", payment_intent: null, url: "https://checkout.stripe.com/c/pay/cs_test_HostedFixture" });
      }
      if (stripe.loseCheckoutResponse) { stripe.loseCheckoutResponse = false; throw Error("simulated response loss"); }
      return json(sessions.get(key));
    }
    if (u.pathname === "/v1/checkout/sessions/cs_test_HostedFixture") {
      const result = [...sessions.values()][0]; assert(result);
      return json({ ...result, status: stripe.paid ? "complete" : "open", payment_status: stripe.paid ? "paid" : "unpaid",
        payment_intent: stripe.paid ? "pi_HostedFixture" : null });
    }
    if (u.pathname === "/v1/refunds" && method === "POST") {
      const wire = new URLSearchParams(options.body);
      assert.equal(wire.get("payment_intent"), "pi_HostedFixture"); assert.equal(wire.get("amount"), "100");
      assert.equal(wire.size, 3); stripe.refunds++;
      return json({ id: "re_HostedFixture", payment_intent: "pi_HostedFixture", amount: 100, currency: "usd", status: "succeeded" });
    }
    if (u.pathname === "/v1/charges/ch_HostedFixture") return json({ id: "ch_HostedFixture", payment_intent: "pi_HostedFixture",
      amount: stripe.chargeWrong ? 200 : 100, amount_refunded: 100, currency: "usd", livemode: false });
    if (u.pathname === "/v1/payment_intents/pi_HostedFixture") return json({ id: "pi_HostedFixture", object: "payment_intent", livemode: false,
      amount: 100, currency: "usd", application_fee_amount: stripe.hasPlatformFee ? 1 : null, transfer_data: null, on_behalf_of: null,
      latest_charge: { id: "ch_HostedFixture", object: "charge", payment_intent: "pi_HostedFixture", livemode: false, amount: 100,
        currency: "usd", application_fee: stripe.hasPlatformFee ? "fee_fixture" : null,
        application_fee_amount: stripe.hasPlatformFee ? 1 : null, transfer_data: null } });
    throw Error("Unrecognized fake Stripe route: " + u.pathname);
  }
  let flow = await createHostedAcceptanceFlow(config, { pool, fetcher, now: () => clock });
  const signed = (type, object, changes = {}) => {
    const raw = Buffer.from(JSON.stringify({ id: "evt_" + type.replaceAll(".", ""), account: MERCHANT, livemode: false, type, data: { object }, ...changes }));
    const seconds = Math.floor(clock / 1000), sig = createHmac("sha256", config.webhook).update(seconds + ".").update(raw).digest("hex");
    return [raw, `t=${seconds},v1=${sig}`];
  };
  return { config, client, db, queries, pool, calls, stripe, signed, get flow() { return flow; },
    now: () => clock, setTime: (value) => { clock = value; },
    restart: async () => { await flow.close(); flow = await createHostedAcceptanceFlow(config, { pool, fetcher, now: () => clock }); } };
}

test("hosted one-run payment flow uses real PostgreSQL and signed provider fixtures", async (t) => {
  const f = await fixture(t); let booking, checkout, paidEvent;
  await t.test("starts paused without provider requests", async () => {
    const status = await f.flow.status(); assert.equal(status.enabled, false); assert.equal(status.booking, null);
    assert.equal(status.connectedDeliveryVerified, false); assert.equal(f.calls.length, 0);
    await assert.rejects(f.flow.book(), { code: "checkout_paused" });
  });
  await t.test("wrong identity or endpoint cannot enable writes", async () => {
    f.stripe.wrongPlatform = true; await assert.rejects(f.flow.enable(), { code: "platform_identity_mismatch" }); f.stripe.wrongPlatform = false;
    f.stripe.wrongEndpoint = true; await assert.rejects(f.flow.enable(), { code: "webhook_endpoint_mismatch" }); f.stripe.wrongEndpoint = false;
    assert.equal((await f.flow.status()).enabled, false); assert.equal(f.calls.filter((call) => call.method === "POST").length, 0);
  });
  await t.test("verified endpoint enables one synthetic booking with durable original expiry", async () => {
    const status = await f.flow.enable(); assert.equal(status.enabled, true); assert.equal(status.endpointConfigurationVerified, true);
    assert.equal(status.connectedDeliveryVerified, false);
    booking = await f.flow.book(); assert.equal(booking.bookingState, "awaiting_payment"); assert.equal(booking.amountCents, 100);
    assert.equal(booking.reused, false); assert.match(booking.returnUrl, /^https:\/\/hosted\.example\.test\/book\/manage#[a-f0-9-]+\.[a-f0-9]{64}$/);
    const ledger = (await f.client.query("SELECT b.created_at,b.hold_expires_at,p.checkout_expires_at FROM public.korlix_schedule_bookings b JOIN public.korlix_schedule_payments p ON p.booking_id=b.id")).rows[0];
    assert.equal(Date.parse(ledger.hold_expires_at) - Date.parse(ledger.created_at), 50 * 60000);
    assert(Date.parse(ledger.checkout_expires_at) - Date.parse(ledger.created_at) <= 40 * 60000);
  });
  await t.test("restarts reuse the booking, encrypted token, Checkout wire and idempotency key", async () => {
    await f.restart(); const again = await f.flow.book();
    assert.equal(again.bookingId, booking.bookingId); assert.equal(again.returnUrl, booking.returnUrl);
    assert.equal(again.holdExpiresAt, booking.holdExpiresAt); assert.equal(again.reused, true);
    f.stripe.loseCheckoutResponse = true; await assert.rejects(f.flow.checkout()); assert.equal(f.stripe.creates, 1);
    await f.restart(); checkout = await f.flow.checkout();
    assert.equal(f.stripe.creates, 1); assert.equal(checkout.returnUrl, booking.returnUrl);
    const posts = f.calls.filter((call) => call.path === "/v1/checkout/sessions");
    assert.equal(posts.length, 2); assert.equal(posts[0].body, posts[1].body);
    await f.flow.checkout(); assert.equal(f.calls.filter((call) => call.path === "/v1/checkout/sessions").length, 2);
  });
  await t.test("return page and tick read unpaid ledger without contacting Stripe", async () => {
    f.stripe.paid = true;
    const [id, manage] = new URL(booking.returnUrl).hash.slice(1).split(".");
    const before = f.calls.length;
    const dto = await f.flow.customerStatus({ booking_id: id, manage_token: manage });
    assert.equal(dto.booking.state, "awaiting_payment"); assert.equal(dto.payment.state, "unpaid");
    assert.equal(dto.booking.starts_at, new Date(dto.booking.starts_at).toISOString());
    await f.flow.tick(); assert.equal(f.calls.length, before);
    assert.doesNotMatch(JSON.stringify(dto), /sealed|grant|checkout|sandbox-guest|manage_token|request_id/);
    await assert.rejects(f.flow.customerStatus({ booking_id: id, manage_token: "af".repeat(32) }), { code: "booking_link_unavailable" });
    await assert.rejects(f.flow.customerStatus({ booking_id: randomUUID(), manage_token: manage }), { code: "booking_link_unavailable" });
  });
  await t.test("forged and cross-account or unrelated events cannot read providers or change ledger", async () => {
    const object = { id: checkout.checkoutId, livemode: false, metadata: { korlix_booking: booking.bookingId } };
    paidEvent = f.signed("checkout.session.completed", object);
    const before = f.calls.length;
    const queryCount = f.queries.length;
    await assert.rejects(f.flow.webhook(paidEvent[0], paidEvent[1] + "00"), { code: "invalid_webhook_signature" });
    await assert.rejects(f.flow.webhook(...f.signed("checkout.session.completed", object, { account: "acct_foreign" })), { code: "webhook_scope_mismatch" });
    assert.equal(f.queries.length, queryCount, "Invalid signatures and foreign accounts must not touch the database.");
    await assert.rejects(f.flow.webhook(...f.signed("checkout.session.completed", { ...object, id: "cs_test_Foreign" })), { code: "webhook_booking_mismatch" });
    assert.equal(f.calls.length, before); assert.equal((await f.flow.status()).booking.paymentState, "unpaid");
  });
  await t.test("valid signed merchant event independently reads Checkout and durably confirms once", async () => {
    assert.deepEqual(await f.flow.webhook(...paidEvent), { received: true });
    let status = await f.flow.status(); assert.equal(status.booking.paymentState, "paid"); assert.equal(status.booking.bookingState, "confirmed");
    assert.equal(status.connectedDeliveryVerified, true); assert.equal(status.receivedEvents.length, 1);
    const before = f.calls.length; await f.restart();
    assert.deepEqual(await f.flow.webhook(...paidEvent), { received: true, duplicate: true });
    assert.equal(f.calls.length, before); status = await f.flow.status(); assert.equal(status.receivedEvents.length, 1);
    assert.equal((await f.client.query("SELECT count(*)::int AS count FROM public.korlix_schedule_audit WHERE action='payment_confirmed'")).rows[0].count, 1);
  });
  await t.test("independent PaymentIntent and charge read verifies zero platform fees", async () => {
    assert.equal((await f.flow.feeProof()).platformFeePercent, 0);
    f.stripe.hasPlatformFee = true; await assert.rejects(f.flow.feeProof(), { code: "fee_verification_mismatch" });
    f.stripe.hasPlatformFee = false;
  });
  await t.test("pausing and expiry stop Checkout but permit a single full refund and signed refund proof", async () => {
    await f.flow.pause(); f.setTime(f.config.expiresAt + 1);
    await assert.rejects(f.flow.enable(), { code: "acceptance_expired" }); await assert.rejects(f.flow.book(), { code: "acceptance_expired" });
    await assert.rejects(f.flow.checkout(), { code: "acceptance_expired" });
    let status = await f.flow.refund(); assert.equal(status.booking.paymentState, "refunded"); assert.equal(status.booking.bookingState, "canceled");
    assert.equal(f.stripe.refunds, 1); await f.flow.refund(); await f.flow.tick(); assert.equal(f.stripe.refunds, 1);
    const event = f.signed("charge.refunded", { id: "ch_HostedFixture", payment_intent: "pi_HostedFixture", livemode: false });
    f.stripe.chargeWrong = true; await assert.rejects(f.flow.webhook(...event), { code: "webhook_verification_pending" });
    f.stripe.chargeWrong = false; assert.deepEqual(await f.flow.webhook(...event), { received: true });
    status = await f.flow.status(); assert.equal(status.receivedEvents.length, 2); assert.equal(status.enabled, false);
    const [id, manage] = new URL(booking.returnUrl).hash.slice(1).split(".");
    assert.equal((await f.flow.customerStatus({ booking_id: id, manage_token: manage })).payment.state, "refunded");
  });
});

test("identity-only staging remains inspectable and cannot enable Checkout without webhook config", async (t) => {
  const f = await fixture(t, { webhook: null, endpointId: null });
  assert.equal((await f.flow.status()).enabled, false);
  await assert.rejects(f.flow.enable(), { code: "webhook_configuration_required" });
  assert.equal(f.calls.length, 0);
});

test("signed webhook recovers an owned Checkout whose creation response was lost across restart", async (t) => {
  const f = await fixture(t); await f.flow.enable(); const booking = await f.flow.book();
  f.stripe.loseCheckoutResponse = true; await assert.rejects(f.flow.checkout());
  assert.equal((await f.flow.status()).booking.checkoutId, null);
  await f.restart(); f.stripe.paid = true;
  const object = { id: "cs_test_HostedFixture", livemode: false, metadata: { korlix_booking: randomUUID() } };
  const before = f.calls.length;
  await assert.rejects(f.flow.webhook(...f.signed("checkout.session.completed", object)), { code: "webhook_booking_mismatch" });
  assert.equal(f.calls.length, before);
  object.metadata.korlix_booking = booking.bookingId;
  assert.deepEqual(await f.flow.webhook(...f.signed("checkout.session.completed", object)), { received: true });
  const status = await f.flow.status();
  assert.equal(status.booking.checkoutId, object.id); assert.equal(status.booking.paymentState, "paid");
  assert.equal(status.booking.bookingState, "confirmed"); assert.equal(f.stripe.creates, 1);
});

test("concurrent private commands fail promptly while the locked command finishes", async (t) => {
  const f = await fixture(t); let release;
  f.stripe.holdRead = new Promise((resolve) => { release = resolve; });
  const enabling = f.flow.enable();
  await new Promise((resolve) => setImmediate(resolve));
  await assert.rejects(f.flow.status(), { code: "acceptance_busy" });
  const closing = f.flow.close();
  await assert.rejects(f.flow.status(), { code: "acceptance_closed" });
  release(); assert.equal((await enabling).enabled, true); await closing;
  assert.equal((await f.client.query("SELECT enabled FROM public.korlix_hosted_acceptance_run")).rows[0].enabled, true);
});

test("failed advisory unlock destroys the pooled session after a command error", async () => {
  let destroyed, releases = 0;
  const client = { async query(sql) {
    if (sql.includes("pg_try_advisory_lock")) return { rows: [{ locked: true }] };
    if (sql.includes("pg_advisory_unlock")) throw Error("connection interrupted");
    throw Error("catalog unavailable");
  }, release(error) { releases++; destroyed = error; } };
  const flow = await createHostedAcceptanceFlow({ paymentRuntime: true, encryptionKey: "ab".repeat(32), origin: ORIGIN,
    expiresAt: Date.now() + 60000 }, { pool: { connect: async () => client } });
  await assert.rejects(flow.status(), { code: "database_isolation_unverified" });
  assert.equal(releases, 1); assert(destroyed instanceof Error); await flow.close();
});
