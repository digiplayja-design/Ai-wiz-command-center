import test from "node:test";
import assert from "node:assert/strict";
import { providerRequest, providerSettings } from "../scheduling/provider_core.mjs";
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

test("provider request timeout is bounded and custom Stripe budgets actually cancel slow transports", async () => {
  let calls = 0, aborted = 0;
  const delayed = async (_url, { signal }) => new Promise((resolve, reject) => {
    calls++;
    const abort = () => { aborted++; clearTimeout(timer); reject(new Error("Fixture transport aborted.")); };
    const timer = setTimeout(() => { signal.removeEventListener("abort", abort); resolve(response(merchant())); }, 40);
    if (signal.aborted) abort(); else signal.addEventListener("abort", abort, { once: true });
  });
  for (const invalid of [0, -1, 60001, 1.5, "45000", NaN, Infinity])
    await assert.rejects(providerRequest(delayed, "https://example.test", {}, [], invalid), RangeError);
  assert.equal(calls, 0, "Invalid budgets must fail before fetching.");
  const ordinary = stripeProvider(config("false"), { fetcher: delayed, diagnostic: () => {} });
  assert.equal((await ordinary.identity({ account_id: pay.account_id, livemode: false })).charges_enabled, true);
  const short = stripeProvider(config("false"), { fetcher: delayed, requestTimeoutMs: 5, diagnostic: () => {} });
  await assert.rejects(short.identity({ account_id: pay.account_id, livemode: false }), /could not be confirmed/);
  assert.equal(aborted, 1);
  const longer = stripeProvider(config("false"), { fetcher: delayed, requestTimeoutMs: 500, diagnostic: () => {} });
  assert.equal((await longer.identity({ account_id: pay.account_id, livemode: false })).charges_enabled, true);
  assert.equal(aborted, 1);
});

test("Stripe diagnostics identify the failed phase without exposing provider secrets", async () => {
  for (const phase of ["oauth_exchange", "account_v2"]) {
    const records = [];
    const adapter = stripeProvider(config("false"), {
      diagnostic: (value) => records.push(value),
      fetcher: async () => new Response(JSON.stringify(phase === "oauth_exchange"
        ? { error: "invalid_grant", error_description: "ac_private sk_test_private" }
        : { error: { code: "account_not_yet_compatible_with_v2", message: "private user@example.test" } }), {
        status: 400, headers: { "request-id": "req_fixture", "content-type": "application/json" },
      }),
    });
    await assert.rejects(phase === "oauth_exchange"
      ? adapter.exchange("ac_private")
      : adapter.identity({ account_id: "acct_fixture", livemode: false }));
    assert.deepEqual(records, [{ stage: phase, status: 400,
      code: phase === "oauth_exchange" ? "invalid_grant" : "account_not_yet_compatible_with_v2",
      requestId: "req_fixture" }]);
    assert(!JSON.stringify(records).includes("private"));
  }
});

test("Stripe diagnostics discard malformed provider codes and request IDs", async () => {
  const records = [];
  const adapter = stripeProvider(config("false"), {
    diagnostic: (value) => records.push(value),
    fetcher: async () => new Response(JSON.stringify({ error: { code: "customer@example.test" } }), {
      status: 400, headers: { "request-id": "https://example.test/?secret=private" },
    }),
  });
  await assert.rejects(adapter.identity({ account_id: "acct_fixture", livemode: false }));
  assert.deepEqual(records, [{ stage: "account_v2", status: 400, code: "unclassified", requestId: undefined }]);
});

const legacyMerchant = () => ({
  id: pay.account_id, object: "account",
  business_profile: { name: "Sandbox business" },
  controller: { stripe_dashboard: { type: "full" }, fees: { payer: "account" },
    losses: { payments: "stripe" }, requirement_collection: "stripe" },
  charges_enabled: true, payouts_enabled: true,
  capabilities: { card_payments: "active" },
});
const v2Failure = (code, status = 400) => new Response(JSON.stringify({ error: { code } }), { status });

test("OAuth can verify a v1 account identity without granting payment readiness", async () => {
  for (const code of ["v1_account_instead_of_v2_account", "account_not_yet_compatible_with_v2"]) {
    const calls = [];
    const adapter = stripeProvider(config("false"), {
      diagnostic: () => {},
      fetcher: async (url, options) => {
        calls.push(new URL(url).pathname);
        assert.equal(options.method, "GET");
        assert.equal(options.headers["Stripe-Account"], undefined);
        return calls.length === 1 ? v2Failure(code) : response(legacyMerchant());
      },
    });
    const identity = await adapter.identity({ account_id: pay.account_id, livemode: false }, { allowPendingCompatibility: true });
    assert.equal(identity.id, pay.account_id);
    assert.equal(identity.livemode, false);
    assert.equal(identity.charges_enabled, false, "Legacy active flags cannot authorize checkout");
    assert.equal(identity.readiness_source, "v1_identity_only");
    assert.equal(identity.card_payments_status, "pending_v2_verification");
    assert.deepEqual(calls, ["/v2/core/accounts/" + pay.account_id, "/v1/accounts/" + pay.account_id]);
  }
});

test("OAuth identity compatibility rejects the wrong account and platform-controlled responsibilities", async () => {
  for (const change of [
    (a) => { a.id = "acct_other"; },
    (a) => { a.object = "other"; },
    (a) => { a.controller.stripe_dashboard.type = "express"; },
    (a) => { a.controller.fees.payer = "application"; },
    (a) => { a.controller.losses.payments = "application"; },
    (a) => { delete a.controller; },
  ]) {
    const legacy = legacyMerchant(); change(legacy);
    const adapter = stripeProvider(config("false"), {
      diagnostic: () => {},
      fetcher: async (url) => new URL(url).pathname.startsWith("/v2/")
        ? v2Failure("v1_account_instead_of_v2_account") : response(legacy),
    });
    await assert.rejects(adapter.identity({ account_id: pay.account_id, livemode: false },
      { allowPendingCompatibility: true }), { status: 409 });
  }
});

test("compatibility does not bypass authorization failures or permit checkout without v2 readiness", async () => {
  for (const code of ["accounts_v2_access_blocked", "not_found", "api_key_expired"]) {
    let calls = 0;
    const adapter = stripeProvider(config("false"), {
      diagnostic: () => {}, fetcher: async () => { calls++; return v2Failure(code); },
    });
    await assert.rejects(adapter.identity({ account_id: pay.account_id, livemode: false },
      { allowPendingCompatibility: true }));
    assert.equal(calls, 1);
  }
  let calls = 0;
  const adapter = stripeProvider(config("true"), {
    diagnostic: () => {},
    fetcher: async (_url, options) => {
      calls++;
      assert.equal(options.method, "GET", "Unverified accounts cannot create payments");
      return v2Failure("v1_account_instead_of_v2_account");
    },
  });
  await assert.rejects(adapter.checkout(pay, wire()));
  assert.equal(calls, 1);
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
