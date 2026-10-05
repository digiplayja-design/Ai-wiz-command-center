import test from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { rm } from "node:fs/promises";
import { acceptanceConfig, createAcceptanceHarness } from "./stripe_sandbox_acceptance.mjs";

const env = { KORLIX_ACCEPTANCE_RUN: "isolated-stripe-sandbox", KORLIX_ACCEPTANCE_STRIPE_SECRET_KEY: "sk_test_fixture",
  KORLIX_ACCEPTANCE_WEBHOOK_SECRET: "whsec_fixture", KORLIX_ACCEPTANCE_PLATFORM_ID: "acct_fixtureplatform",
  KORLIX_ACCEPTANCE_MERCHANT_ID: "acct_fixturemerchant", KORLIX_ACCEPTANCE_PORT: "0" };
const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });

test("acceptance config rejects ambient production settings, live keys and attached sandboxes", () => {
  assert.throws(() => acceptanceConfig({ KORLIX_SCHEDULING_STRIPE_SECRET_KEY: "sk_test_fixture" }));
  for (const change of [{ KORLIX_ACCEPTANCE_RUN: "true" }, { KORLIX_ACCEPTANCE_STRIPE_SECRET_KEY: "sk_live_fixture" },
    { KORLIX_ACCEPTANCE_PLATFORM_ID: "acct_1UMI5OLx6hd5l5Vo" }, { KORLIX_ACCEPTANCE_MERCHANT_ID: "acct_fixtureplatform" },
    { KORLIX_ACCEPTANCE_PORT: "443" }]) assert.throws(() => acceptanceConfig({ ...env, ...change }));
  assert.equal(acceptanceConfig(env).port, 0);
});

test("isolated harness verifies identities, blocks pauses, processes signed payment and refund without production calls", async () => {
  const requests = [], sessions = new Map(); let platformMismatch = true, copiedEndpoint = true, capabilitiesActive = false;
  const fetcher = async (url, options) => {
    const u = new URL(url); requests.push({ path: u.pathname, method: options.method || "GET" });
    if (u.pathname === "/v1/account") return json({ id: platformMismatch ? "acct_wrong" : env.KORLIX_ACCEPTANCE_PLATFORM_ID, object: "account" });
    if (u.pathname === "/v1/webhook_endpoints") return json({ object: "list", has_more: false, data: copiedEndpoint
      ? [{ object: "webhook_endpoint", status: "enabled", livemode: false }] : [] });
    if (u.pathname.startsWith("/v2/core/accounts/")) return json({ id: env.KORLIX_ACCEPTANCE_MERCHANT_ID, object: "v2.core.account", livemode: false,
      dashboard: "full", defaults: { responsibilities: { fees_collector: "stripe", losses_collector: "stripe" } },
      configuration: { merchant: { capabilities: { card_payments: { status: capabilitiesActive ? "active" : "pending" }, stripe_balance: { payouts: { status: "active" } } } } } });
    if (u.pathname === "/v1/checkout/sessions" && options.method === "POST") {
      const wire = new URLSearchParams(options.body); const id = "cs_test_fixture" + sessions.size;
      const session = { id, client_reference_id: wire.get("client_reference_id"), metadata: { korlix_booking: wire.get("metadata[korlix_booking]") },
        mode: "payment", livemode: false, currency: "usd", amount_total: 100, status: "open", payment_status: "unpaid", url: "https://checkout.stripe.com/c/pay/" + id };
      assert.match(wire.get("success_url"), /^https:\/\/korlix-acceptance\.invalid\//);
      sessions.set(id, session); return json(session);
    }
    if (u.pathname.startsWith("/v1/checkout/sessions/")) return json(sessions.get(u.pathname.split("/").at(-1)));
    if (u.pathname === "/v1/refunds") return json({ id: "re_fixture", payment_intent: "pi_fixture", amount: 100, currency: "usd", status: "succeeded" });
    if (u.pathname === "/v1/payment_intents/pi_fixture") return json({ id: "pi_fixture", livemode: false,
      latest_charge: { id: "ch_fixture", livemode: false, amount: 100, application_fee: null, application_fee_amount: null } });
    throw new Error("Unexpected fixture request.");
  };
  let harness = await createAcceptanceHarness({ environment: { ...env, SUPABASE_URL: "https://production.invalid", RESEND_API_KEY: "must-not-copy" }, fetcher });
  const directory = harness.directory;
  const command = async (name, body, expected = 200) => {
    const response = await fetch(harness.base + "/acceptance/" + name, { method: body ? "POST" : "GET",
      headers: { "content-type": "application/json", authorization: "Bearer " + harness.controlToken },
      ...(body ? { body: JSON.stringify(body) } : {}) });
    const data = await response.json(); assert.equal(response.status, expected, JSON.stringify(data)); return data;
  };
  try {
    assert.equal(requests.length, 0, "Startup must not perform provider calls.");
    assert.equal((await command("status")).checkoutEnabled, false);
    const denied = await fetch(harness.base + "/acceptance/status"); assert.equal(denied.status, 401);
    const browser = await fetch(harness.base + "/acceptance/status", { headers: { origin: "https://example.test", authorization: "Bearer " + harness.controlToken } }); assert.equal(browser.status, 403);
    await command("enable", { confirmed: true }, 400);
    assert(!requests.some((r) => r.method === "POST"), "Wrong platform must block every Stripe write.");
    platformMismatch = false;
    await command("enable", { confirmed: true }, 400);
    assert(!requests.some((r) => r.method === "POST"), "Copied enabled webhook must block every Stripe write.");
    copiedEndpoint = false;
    await command("enable", { confirmed: true }, 400);
    assert(!requests.some((r) => r.method === "POST"), "Pending capability must block every Stripe write.");
    capabilitiesActive = true;
    await command("enable", { confirmed: true });
    const booking = await command("book", { confirmed: true });
    await command("pause", {});
    await command("checkout", { bookingId: booking.bookingId, confirmed: true }, 400);
    assert(!requests.some((r) => r.method === "POST"));
    await command("enable", { confirmed: true });
    const checkout = await command("checkout", { bookingId: booking.bookingId, confirmed: true });
    await command("pause", {});
    Object.assign(sessions.get(checkout.checkoutId), { status: "complete", payment_status: "paid", payment_intent: "pi_fixture" });
    const event = { id: "evt_fixture", account: env.KORLIX_ACCEPTANCE_MERCHANT_ID, livemode: false,
      type: "checkout.session.completed", data: { object: { id: checkout.checkoutId } } };
    const raw = JSON.stringify(event), t = Math.floor(Date.now() / 1000);
    const signature = createHmac("sha256", env.KORLIX_ACCEPTANCE_WEBHOOK_SECRET).update(t + "." + raw).digest("hex");
    const send = (sig) => fetch(harness.base + "/api/scheduling/payments/webhook", { method: "POST", headers: { "content-type": "application/json", "stripe-signature": sig }, body: raw });
    assert.equal((await send("invalid")).status, 400);
    const signed = await send(`t=${t},v1=${signature}`); assert.equal(signed.status, 200, await signed.text());
    const paid = await command("status"); assert.equal(paid.bookings[0].paymentState, "paid"); assert.equal(paid.receivedEvents.length, 1);
    assert.equal((await command("duplicate", {})).duplicateDeliveryIdempotent, true);
    assert.equal((await command("fee-proof", { bookingId: booking.bookingId })).applicationFee, null);
    const refund = await command("refund", { bookingId: booking.bookingId, confirmed: true }); assert.equal(refund.bookings[0].paymentState, "refunded");
    assert.equal(requests.filter((r) => r.path === "/v1/refunds").length, 1);
    await harness.close();
    harness = await createAcceptanceHarness({ environment: env, fetcher, resumeDirectory: directory });
    assert.equal((await command("status")).bookings[0].paymentState, "refunded");
    assert.equal((await command("status")).checkoutEnabled, false);
  } finally { await harness.close(); await rm(directory, { recursive: true, force: true }); }
});
