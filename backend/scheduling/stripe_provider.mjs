import { createHmac, timingSafeEqual } from "node:crypto";
import { providerRequest, ProviderError } from "./provider_core.mjs";
const account = (v) => typeof v === "string" && /^acct_[A-Za-z0-9]+$/.test(v);
const id = (v, prefix) =>
  typeof v === "string" && new RegExp("^" + prefix + "_[A-Za-z0-9_]+$").test(v);
export function stripeSignature(raw, header, key, now = Date.now()) {
  if (
    !Buffer.isBuffer(raw) ||
    raw.length > 1024 * 1024 ||
    !key ||
    typeof header !== "string"
  )
    return false;
  const parts = header.split(",").map((v) => v.split("=")),
    times = parts.filter((v) => v[0] === "t");
  if (
    times.length !== 1 ||
    !/^\d{10}$/.test(times[0][1]) ||
    Math.abs(now / 1000 - Number(times[0][1])) > 300
  )
    return false;
  const expected = createHmac("sha256", key)
    .update(times[0][1] + ".")
    .update(raw)
    .digest();
  return parts.some(
    ([k, v]) =>
      k === "v1" &&
      /^[a-f0-9]{64}$/.test(v) &&
      timingSafeEqual(Buffer.from(v, "hex"), expected),
  );
}
export function checkoutWire(pay, manageUrl) {
  const b = pay.booking;
  return new URLSearchParams({
    mode: "payment",
    "payment_method_types[0]": "card",
    customer_email: b.guest_email,
    client_reference_id: b.id,
    "metadata[korlix_booking]": b.id,
    "payment_intent_data[metadata][korlix_booking]": b.id,
    "line_items[0][quantity]": "1",
    "line_items[0][price_data][currency]": pay.currency,
    "line_items[0][price_data][unit_amount]": String(pay.amount_cents),
    "line_items[0][price_data][product_data][name]": String(
      b.snapshot.title,
    ).slice(0, 120),
    "custom_text[submit][message]": String(
      b.snapshot.refund_policy || "Contact your host for refunds.",
    ).slice(0, 1000),
    expires_at: String(Math.floor(Date.parse(pay.checkout_expires_at) / 1000)),
    success_url: manageUrl,
    cancel_url: manageUrl,
  }).toString();
}
export function stripeProvider(config, { fetcher = fetch } = {}) {
  const livemode = /^sk_live_/.test(config.key) || /^rk_live_/.test(config.key);
  async function api(path, accountId, { method = "GET", wire, key } = {}) {
    if (accountId && !account(accountId))
      throw new ProviderError("Invalid merchant account.");
    const { data } = await providerRequest(
      fetcher,
      "https://api.stripe.com/v1" + path,
      {
        method,
        headers: {
          Authorization: "Bearer " + config.key,
          "Stripe-Version": config.version,
          ...(accountId ? { "Stripe-Account": accountId } : {}),
          ...(wire
            ? { "Content-Type": "application/x-www-form-urlencoded" }
            : {}),
          ...(key ? { "Idempotency-Key": key } : {}),
        },
        ...(wire ? { body: wire } : {}),
      },
    );
    return data;
  }
  function session(s, pay) {
    if (
      !id(s.id, "cs") ||
      s.client_reference_id !== pay.booking_id ||
      s.metadata?.korlix_booking !== pay.booking_id ||
      s.mode !== "payment" ||
      s.livemode !== pay.livemode ||
      s.currency !== pay.currency ||
      s.amount_total !== pay.amount_cents ||
      !["open", "complete", "expired"].includes(s.status) ||
      !["paid", "unpaid", "no_payment_required"].includes(s.payment_status)
    )
      throw new ProviderError(
        "Payment verification did not match this appointment.",
        409,
      );
    if (s.url) {
      const u = new URL(s.url);
      if (
        u.origin !== "https://checkout.stripe.com" ||
        u.username ||
        u.password
      )
        throw new ProviderError("Stripe returned an invalid checkout link.");
    }
    return {
      checkout_id: s.id,
      checkout_url: s.url || null,
      account_id: pay.account_id,
      amount_cents: s.amount_total,
      currency: s.currency,
      livemode: s.livemode,
      paid: s.payment_status === "paid",
      expired: s.status === "expired",
      payment_intent_id:
        typeof s.payment_intent === "string"
          ? s.payment_intent
          : s.payment_intent?.id,
    };
  }
  return {
    livemode,
    authorizationUrl(state) {
      const u = new URL("https://connect.stripe.com/oauth/authorize");
      u.search = new URLSearchParams({
        response_type: "code",
        client_id: config.id,
        scope: "read_write",
        redirect_uri: config.callback,
        state,
      });
      return u.href;
    },
    async exchange(code) {
      const { data } = await providerRequest(
        fetcher,
        "https://connect.stripe.com/oauth/token",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/x-www-form-urlencoded",
            Authorization: "Bearer " + config.key,
          },
          body: new URLSearchParams({
            grant_type: "authorization_code",
            code,
          }).toString(),
        },
      );
      if (
        !account(data.stripe_user_id) ||
        data.scope !== "read_write" ||
        data.livemode !== livemode
      )
        throw new ProviderError(
          "Merchant authorization or test/live mode could not be verified.",
          409,
        );
      return { account_id: data.stripe_user_id, livemode: data.livemode };
    },
    async identity(grant) {
      if (!account(grant.account_id) || grant.livemode !== livemode)
        throw new ProviderError("Reconnect your merchant account.", 409);
      const a = await api("/accounts/" + grant.account_id);
      if (a.id !== grant.account_id || a.type !== "standard")
        throw new ProviderError(
          "Connect a Stripe Standard merchant account.",
          409,
        );
      return {
        id: a.id,
        label: String(
          a.business_profile?.name ||
            a.settings?.dashboard?.display_name ||
            a.email ||
            a.id,
        ).slice(0, 250),
        charges_enabled: a.charges_enabled === true,
        livemode,
      };
    },
    async checkout(pay, wire) {
      return session(
        await api("/checkout/sessions", pay.account_id, {
          method: "POST",
          wire,
          key: "korlix-scheduling-checkout-" + pay.booking_id,
        }),
        pay,
      );
    },
    async retrieve(pay) {
      if (!id(pay.checkout_id, "cs"))
        throw new ProviderError("Checkout is not ready yet.", 409);
      return session(
        await api("/checkout/sessions/" + pay.checkout_id, pay.account_id),
        pay,
      );
    },
    async refund(pay) {
      let r;
      if (pay.refund_id) {
        if (!id(pay.refund_id, "re"))
          throw new ProviderError("Refund reference could not be verified.");
        r = await api("/refunds/" + pay.refund_id, pay.account_id);
      } else {
        if (!id(pay.payment_intent_id, "pi"))
          throw new ProviderError("Payment reference could not be verified.");
        r = await api("/refunds", pay.account_id, {
          method: "POST",
          key: "korlix-scheduling-refund-" + pay.booking_id,
          wire: new URLSearchParams({
            payment_intent: pay.payment_intent_id,
            amount: String(pay.amount_cents),
            "metadata[korlix_booking]": pay.booking_id,
          }).toString(),
        });
      }
      if (
        !id(r.id, "re") ||
        r.payment_intent !== pay.payment_intent_id ||
        r.amount !== pay.amount_cents ||
        r.currency !== pay.currency ||
        ![
          "pending",
          "succeeded",
          "failed",
          "canceled",
          "requires_action",
        ].includes(r.status)
      )
        throw new ProviderError(
          "Refund verification did not match this booking.",
        );
      return {
        refund_id: r.id,
        state:
          r.status === "succeeded"
            ? "succeeded"
            : r.status === "pending"
              ? "pending"
              : "failed",
      };
    },
    async chargeRefund(event) {
      const ch = event.data?.object;
      if (!id(ch?.id, "ch") || !account(event.account))
        throw new ProviderError("Invalid payment event.", 400);
      const actual = await api("/charges/" + ch.id, event.account);
      return {
        account_id: event.account,
        payment_intent_id: actual.payment_intent,
        refunded_cents: actual.amount_refunded,
        currency: actual.currency,
        livemode: actual.livemode,
      };
    },
  };
}
