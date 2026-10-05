import test from "node:test";
import assert from "node:assert/strict";
import { providerSettings } from "../scheduling/provider_core.mjs";
import { checkoutWire, stripeProvider } from "../scheduling/stripe_provider.mjs";

const env = {
  KORLIX_SCHEDULING_TOKEN_KEY: Buffer.alloc(32, 9).toString("base64"),
  KORLIX_SCHEDULING_STRIPE_CLIENT_ID: "ca_fixture",
  KORLIX_SCHEDULING_STRIPE_SECRET_KEY: "sk_test_fixture",
  KORLIX_SCHEDULING_STRIPE_WEBHOOK_SECRET: "whsec_fixture",
};
const config = (flag) => providerSettings({
  ...env, KORLIX_SCHEDULING_STRIPE_ENABLED: flag,
}, "https://example.test").providers.stripe;
const pay = {
  booking_id: "fixturebooking",
  account_id: "acct_fixture",
  livemode: false,
  currency: "usd",
  amount_cents: 2500,
  checkout_expires_at: new Date(Date.now() + 40 * 60000).toISOString(),
  booking: {
    id: "fixturebooking",
    guest_email: "guest@example.test",
    snapshot: { title: "Appointment" },
  },
};
const merchant = () => ({
  id: pay.account_id,
  object: "v2.core.account",
  livemode: false,
  dashboard: "full",
  defaults: {
    responsibilities: { fees_collector: "stripe", losses_collector: "stripe" },
  },
  configuration: {
    merchant: {
      capabilities: {
        card_payments: { status: "active" },
        stripe_balance: { payouts: { status: "active" } },
      },
    },
  },
});
const wire = () => checkoutWire(pay, "https://example.test/book/manage");
const response = (value) => new Response(JSON.stringify(value), {
  headers: { "content-type": "application/json" },
});

test("Stripe payment activation is explicit and does not invalidate saved grants", async () => {
  for (const flag of [undefined, "false", "TRUE", "1", "", true]) {
    const c = config(flag);
    assert.equal(c.ready, true);
    assert.equal(c.enabled, false);
    assert.equal(c.fingerprint, config("true").fingerprint);
    const adapter = stripeProvider(c, {
      fetcher: () => assert.fail("Paused checkout must not call Stripe"),
    });
    await assert.rejects(adapter.checkout(pay, wire()), { status: 503 });
  }
  assert.equal(config("true").enabled, true);
});

test("merchant identity rejects incompatible Accounts v2 responsibility, dashboard, account and mode", async () => {
  const incompatible = [
    (a) => { a.id = "acct_other"; },
    (a) => { a.object = "account"; },
    (a) => { a.livemode = true; },
    (a) => { a.dashboard = "express"; },
    (a) => { a.defaults.responsibilities.fees_collector = "application"; },
    (a) => { a.defaults.responsibilities.losses_collector = "application"; },
    (a) => { delete a.defaults; },
  ];
  for (const change of incompatible) {
    const a = merchant();
    change(a);
    const adapter = stripeProvider(config("true"), {
      fetcher: async (url, options) => {
        assert.equal(options.method, "GET");
        assert(new URL(url).pathname.startsWith("/v2/core/accounts/"));
        return response(a);
      },
    });
    await assert.rejects(adapter.checkout(pay, wire()), { status: 409 });
  }
});

test("checkout freshly checks both payment and payout capabilities and fails closed", async () => {
  for (const change of [
    (a) => { a.configuration.merchant.capabilities.card_payments.status = "pending"; },
    (a) => { a.configuration.merchant.capabilities.stripe_balance.payouts.status = "restricted"; },
    (a) => { delete a.configuration; },
  ]) {
    const a = merchant();
    change(a);
    let reads = 0;
    const adapter = stripeProvider(config("true"), {
      fetcher: async (_url, options) => {
        assert.equal(options.method, "GET", "Unready merchants cannot create charges");
        reads++;
        return response(a);
      },
    });
    await assert.rejects(adapter.checkout(pay, wire()), { status: 409 });
    assert.equal(reads, 1);
  }
});

test("checkout rejects platform fees and transfer routing before making a provider call", async () => {
  const adapter = stripeProvider(config("true"), {
    fetcher: () => assert.fail("Invalid fee model must not reach Stripe"),
  });
  for (const field of [
    "application_fee_amount",
    "payment_intent_data[application_fee_amount]",
    "payment_intent_data[transfer_data][destination]",
    "payment_intent_data[on_behalf_of]",
  ]) {
    const payload = new URLSearchParams(wire());
    payload.set(field, "123");
    await assert.rejects(adapter.checkout(pay, payload.toString()), { status: 409 });
  }
});

test("direct checkout uses the verified merchant, dynamic methods and an idempotent request", async () => {
  const calls = [];
  const adapter = stripeProvider(config("true"), {
    fetcher: async (url, options) => {
      calls.push({ url: new URL(url), ...options });
      if (options.method === "GET") return response(merchant());
      return response({
        id: "cs_test_fixture",
        client_reference_id: pay.booking_id,
        metadata: { korlix_booking: pay.booking_id },
        livemode: false,
        currency: "usd",
        amount_total: 2500,
        mode: "payment",
        status: "open",
        payment_status: "unpaid",
        url: "https://checkout.stripe.com/c/pay/cs_test_fixture",
      });
    },
  });
  assert.equal((await adapter.checkout(pay, wire())).account_id, pay.account_id);
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[0].url.searchParams.getAll("include[0]"), ["configuration.merchant"]);
  assert.equal(calls[0].url.searchParams.get("include[1]"), "defaults");
  assert.equal(calls[0].headers["Stripe-Account"], undefined);
  assert.equal(calls[1].url.pathname, "/v1/checkout/sessions");
  assert.equal(calls[1].headers["Stripe-Account"], pay.account_id);
  assert.equal(calls[1].headers["Idempotency-Key"], "korlix-scheduling-checkout-" + pay.booking_id);
  const payload = new URLSearchParams(calls[1].body);
  assert(![...payload.keys()].some((k) => /application_fee|transfer_data|payment_method_types/.test(k)));
  assert.equal(payload.get("integration_identifier"), "korlix_2meetu_dzwqhxnr");
});
