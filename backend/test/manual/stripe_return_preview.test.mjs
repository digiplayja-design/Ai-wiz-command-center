import test from "node:test";
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { readFile } from "node:fs/promises";
import { request } from "node:http";
import { previewConfig, createPreviewServer } from "./stripe_return_preview.mjs";

// This server displays a saved, synthetic sandbox result. These tests exercise
// its disclosure and mutation boundaries; they do not claim Stripe delivery or
// an actual customer's browser redirect.
const NOW = Date.parse("2026-10-05T15:00:00.000Z");
const ORIGIN = "https://test.example";
const BOOKING_ID = "12345678-1234-4234-8234-123456789abc";
const TOKEN = randomBytes(32).toString("hex");
const TOKEN_HASH = createHash("sha256").update(TOKEN).digest("hex");
const iso = (time) => new Date(time).toISOString();

function snapshot() {
  return {
    capturedAt: iso(NOW - 30 * 60000),
    booking: {
      id: BOOKING_ID, state: "canceled", revision: 3,
      guest_name: "Synthetic sandbox guest", guest_email: "sandbox-guest@example.test",
      guest_timezone: "UTC", starts_at: iso(NOW + 86400000), cancel_until: iso(NOW + 3600000),
      snapshot: {
        title: "Sandbox appointment", host_name: "Isolated sandbox host", duration_minutes: 30,
        refund_policy: "Full refund on request.", questions: [],
      },
      answers: {}, notifications: [],
      payment: {
        state: "refunded", refund_state: "succeeded", amount_cents: 100,
        currency: "usd", livemode: false,
      },
    },
  };
}
function environment(data = snapshot(), change = {}) {
  return {
    KORLIX_RETURN_PREVIEW: "refunded-sandbox-display-v1",
    KORLIX_RETURN_PREVIEW_DATA: JSON.stringify(data),
    KORLIX_RETURN_PREVIEW_TOKEN_HASH: TOKEN_HASH,
    KORLIX_RETURN_PREVIEW_EXPIRES_AT: iso(NOW + 3600000),
    KORLIX_RETURN_PREVIEW_ORIGIN: ORIGIN,
    ...change,
  };
}
const validBody = () => ({ booking_id: BOOKING_ID, manage_token: TOKEN });

async function fixture(t, { data = snapshot(), env = {}, initialNow = NOW } = {}) {
  let currentNow = initialNow;
  const config = previewConfig(environment(data, env), currentNow);
  const server = await createPreviewServer(config, { now: () => currentNow });
  assert.equal(server.listening, false, "The caller controls listener startup");
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  t.after(async () => {
    server.closeAllConnections();
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  });
  async function send(path, { method = "GET", body, raw, headers = {} } = {}) {
    const payload = raw ?? (body === undefined ? undefined : JSON.stringify(body));
    return new Promise((resolve, reject) => {
      const outgoing = request({
        hostname: "127.0.0.1", port: server.address().port, path, method,
        headers: {
          host: "test.example", origin: ORIGIN,
          ...(payload === undefined ? {} : { "content-type": "application/json", "content-length": Buffer.byteLength(payload) }),
          ...headers,
        },
      }, (response) => {
        const chunks = [];
        response.on("data", (chunk) => chunks.push(chunk));
        response.on("error", reject);
        response.on("end", () => resolve({ status: response.statusCode, headers: response.headers,
          text: Buffer.concat(chunks).toString("utf8") }));
      });
      outgoing.on("error", reject);
      outgoing.end(payload);
    });
  }
  return { send, setNow: (time) => { currentNow = time; } };
}
function assertPrivateHeaders(response) {
  assert.equal(response.headers["cache-control"], "no-store");
  assert.equal(response.headers["referrer-policy"], "no-referrer");
  assert.equal(response.headers["x-content-type-options"], "nosniff");
}

test("preview configuration requires its explicit mode, hash, bounded expiry and HTTPS origin", () => {
  assert.doesNotThrow(() => previewConfig(environment(), NOW));
  const capturedAt = Date.parse(snapshot().capturedAt);
  for (const change of [
    { KORLIX_RETURN_PREVIEW: "true" },
    { KORLIX_RETURN_PREVIEW_DATA: "not-json" },
    { KORLIX_RETURN_PREVIEW_TOKEN_HASH: TOKEN_HASH.slice(1) },
    { KORLIX_RETURN_PREVIEW_TOKEN_HASH: "g".repeat(64) },
    { KORLIX_RETURN_PREVIEW_EXPIRES_AT: "tomorrow" },
    { KORLIX_RETURN_PREVIEW_EXPIRES_AT: iso(capturedAt) },
    { KORLIX_RETURN_PREVIEW_EXPIRES_AT: iso(capturedAt + 7 * 86400000 + 1) },
    { KORLIX_RETURN_PREVIEW_ORIGIN: "http://test.example" },
    { KORLIX_RETURN_PREVIEW_ORIGIN: "https://user:password@test.example" },
  ]) assert.throws(() => previewConfig(environment(snapshot(), change), NOW), JSON.stringify(Object.keys(change)));
  const futureCapture = snapshot(); futureCapture.capturedAt = iso(NOW + 61000);
  assert.throws(() => previewConfig(environment(futureCapture), NOW));
  const renderEnv = environment(); delete renderEnv.KORLIX_RETURN_PREVIEW_ORIGIN;
  renderEnv.RENDER_EXTERNAL_URL = ORIGIN;
  assert.doesNotThrow(() => previewConfig(renderEnv, NOW));
});

test("preview configuration refuses payment, database and email credentials", () => {
  for (const [name, value] of Object.entries({
    STRIPE_SECRET_KEY: "sk_live_fixture_not_a_key",
    KORLIX_SCHEDULING_STRIPE_SECRET_KEY: "sk_test_fixture_not_a_key",
    SUPABASE_SERVICE_ROLE_KEY: "fixture-service-role-not-a-key",
    RESEND_API_KEY: "fixture-mail-key-not-a-key",
  })) assert.throws(() => previewConfig(environment(snapshot(), { [name]: value }), NOW), name);
});

test("preview accepts only the synthetic canceled, fully refunded USD1 test result", () => {
  const mutations = [
    (b) => { b.state = "confirmed"; },
    (b) => { b.payment.state = "paid"; },
    (b) => { b.payment.refund_state = "pending"; },
    (b) => { b.payment.livemode = true; },
    (b) => { b.payment.amount_cents = 101; },
    (b) => { b.payment.currency = "eur"; },
    (b) => { b.id = "not-a-booking-id"; },
    (b) => { b.revision = 1.5; },
    (b) => { b.guest_name = "Real customer"; },
    (b) => { b.guest_email = "customer@example.com"; },
    (b) => { b.snapshot.host_name = "Real host"; },
  ];
  for (const mutate of mutations) {
    const data = snapshot(); mutate(data.booking);
    assert.throws(() => previewConfig(environment(data), NOW));
  }
});

test("public health and return assets disclose no private result or credentials", async (t) => {
  const { send } = await fixture(t);
  const health = await send("/health");
  assert.equal(health.status, 200);
  const status = JSON.parse(health.text);
  assert.equal(status.mode, "saved-sandbox-return-display");
  assert.equal(status.checkoutEnabled, false);
  assert.equal(status.paymentsConnected, false);
  assert(Object.keys(status).every((key) => ["mode", "checkoutEnabled", "paymentsConnected", "expired"].includes(key)));
  if (Object.hasOwn(status, "expired")) assert.equal(status.expired, false);
  const page = await send("/book/manage");
  assert.equal(page.status, 200);
  assert.match(page.headers["content-type"], /text\/html/);
  assertPrivateHeaders(page);
  assert.match(page.text, /Saved sandbox result/);
  assert(page.text.includes(snapshot().capturedAt.slice(0, 10)), "The page distinguishes the capture date from current payment status");
  const csp = page.headers["content-security-policy"];
  for (const directive of ["script-src 'self'", "connect-src 'self'", "object-src 'none'"]) assert(csp.includes(directive));
  for (const response of [health, page]) {
    for (const privateValue of [TOKEN, TOKEN_HASH, BOOKING_ID, snapshot().booking.guest_email]) {
      assert(!response.text.includes(privateValue), "Public responses must not contain private link or result fields");
    }
  }
  for (const name of ["booking.js", "booking.css", "fonts.css"]) {
    const response = await send("/book/assets/" + name);
    assert.equal(response.status, 200, name);
    assertPrivateHeaders(response);
    const shipped = await readFile(new URL("../../scheduling/public/" + name, import.meta.url), "utf8");
    assert.equal(response.text, shipped, `Serve the shipped ${name} without a substitute implementation`);
  }
});

test("authorized private lookup returns only the normalized saved booking", async (t) => {
  const data = snapshot();
  Object.assign(data.booking, {
    event_slug: "private-host-slug", owner_id: "owner-private", manage_token: "private-token-sentinel",
    stripe_account_id: "acct_private", checkout_url: "https://checkout.stripe.com/private-sentinel",
  });
  Object.assign(data.booking.snapshot, { location_detail: "https://private.example.test/meeting", provider_id: "provider-private" });
  Object.assign(data.booking.payment, {
    checkout_url: "https://checkout.stripe.com/private-sentinel", checkout_id: "cs_test_private",
    payment_intent_id: "pi_private", refund_id: "re_private", account_id: "acct_private",
  });
  const { send } = await fixture(t, { data });
  const response = await send("/api/scheduling/manage", { method: "POST", body: validBody() });
  assert.equal(response.status, 200, response.text);
  assertPrivateHeaders(response);
  assert.deepEqual(JSON.parse(response.text), { booking: snapshot().booking });
  for (const hidden of [TOKEN, TOKEN_HASH, "private-sentinel", "owner-private", "cs_test_private", "pi_private", "acct_private", "provider-private"])
    assert(!response.text.includes(hidden));
});

test("private lookup rejects wrong identity, missing tokens and foreign origins", async (t) => {
  const { send } = await fixture(t);
  for (const body of [
    {}, { booking_id: BOOKING_ID },
    { booking_id: "87654321-4321-4321-8321-cba987654321", manage_token: TOKEN },
    { booking_id: BOOKING_ID, manage_token: "f".repeat(64) },
    { booking_id: BOOKING_ID, manage_token: TOKEN.slice(1) },
  ]) {
    const response = await send("/api/scheduling/manage", { method: "POST", body });
    assert([400, 404].includes(response.status), `Denied private lookup: ${response.status}`);
    assert(!response.text.includes(snapshot().booking.guest_email));
    assert(!response.text.includes(TOKEN));
  }
  const foreign = await send("/api/scheduling/manage", {
    method: "POST", body: validBody(), headers: { origin: "https://other.example" },
  });
  assert.equal(foreign.status, 403);
  assert(!foreign.text.includes(snapshot().booking.guest_email));
});

test("private lookup accepts only bounded JSON request bodies", async (t) => {
  const { send } = await fixture(t);
  const malformed = await send("/api/scheduling/manage", { method: "POST", raw: "{broken" });
  assert.equal(malformed.status, 400);
  for (const raw of ["null", "[]", '"not an object"']) {
    const response = await send("/api/scheduling/manage", { method: "POST", raw });
    assert([400, 404].includes(response.status), raw);
  }
  const oversized = await send("/api/scheduling/manage", { method: "POST", body: { ...validBody(), padding: "x".repeat(4096) } });
  assert.equal(oversized.status, 413);
  const wrongType = await send("/api/scheduling/manage", {
    method: "POST", body: validBody(), headers: { "content-type": "text/plain" },
  });
  assert([400, 415].includes(wrongType.status));
});

test("expired links stop serving private results while health survives restart", async (t) => {
  const { send, setNow } = await fixture(t);
  assert.equal((await send("/api/scheduling/manage", { method: "POST", body: validBody() })).status, 200);
  setNow(NOW + 3600001);
  const expired = await send("/api/scheduling/manage", { method: "POST", body: validBody() });
  assert.equal(expired.status, 410);
  assert(!expired.text.includes(snapshot().booking.guest_email));
  assert.equal((await send("/health")).status, 200);
  const restarted = await fixture(t, { initialNow: NOW + 3600001 });
  assert.equal((await restarted.send("/health")).status, 200);
  assert.equal((await restarted.send("/api/scheduling/manage", { method: "POST", body: validBody() })).status, 410);
});

test("preview has no checkout, webhook, refund or booking mutation routes", async (t) => {
  const { send } = await fixture(t);
  for (const path of [
    "/api/scheduling/manage/checkout", "/api/scheduling/payments/webhook",
    `/api/scheduling/bookings/${BOOKING_ID}/refund`, "/api/scheduling/manage/cancel",
    "/api/scheduling/manage/reschedule", "/api/scheduling/manage/calendar",
    "/api/scheduling/public/sandbox-booking/book", "/acceptance/enable",
  ]) {
    const response = await send(path, { method: "POST", body: { ...validBody(), confirmed: true, revision: 3 } });
    assert([404, 405].includes(response.status), `${path} must be unavailable: ${response.status}`);
  }
  for (const method of ["GET", "PUT", "DELETE"]) {
    const response = await send("/api/scheduling/manage", { method, ...(method === "GET" ? {} : { body: validBody() }) });
    assert([404, 405].includes(response.status), method);
  }
  const unchanged = await send("/api/scheduling/manage", { method: "POST", body: validBody() });
  assert.equal(unchanged.status, 200);
  assert.deepEqual(JSON.parse(unchanged.text), { booking: snapshot().booking });
});
