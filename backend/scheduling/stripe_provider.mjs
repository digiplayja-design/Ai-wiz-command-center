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
    integration_identifier: "korlix_2meetu_dzwqhxnr",
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
export function stripeProvider(config, { fetcher = fetch, requestTimeoutMs = 15000, diagnostic = (value) =>
  console.warn("[Scheduling Stripe] " + JSON.stringify(value)) } = {}) {
  const livemode = /^sk_live_/.test(config.key) || /^rk_live_/.test(config.key);
  async function request(stage, url, options) {
    try {
      return await providerRequest(fetcher, url, options, [], requestTimeoutMs);
    } catch (error) {
      // Deliberately omit provider messages and all request/response payloads.
      diagnostic({ stage, status: error.upstream?.status || 0,
        code: error.upstream?.code || "transport_error",
        requestId: error.upstream?.requestId });
      throw error;
    }
  }
  async function api(path, accountId, { method = "GET", wire, key } = {}) {
    if (accountId && !account(accountId))
      throw new ProviderError("Invalid merchant account.");
    const { data } = await request(
      path.startsWith("/v2/") ? "account_v2" : path.startsWith("/accounts/") ? "account_identity_v1" : "payment_api",
      "https://api.stripe.com" + (path.startsWith("/v2/") ? path : "/v1" + path),
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
  async function setupRequest(stage, path, body, key) {
    try {
      const { data } = await request(stage, "https://api.stripe.com" + path, {
        method: "POST",
        headers: {
          Authorization: "Bearer " + config.key,
          "Stripe-Version": config.version,
          "Content-Type": "application/json",
          ...(key ? { "Idempotency-Key": key } : {}),
        },
        body: JSON.stringify(body),
      });
      return data;
    } catch (error) {
      if ([401, 403].includes(error.upstream?.status))
        throw new ProviderError("Stripe merchant setup needs administrator permission. Your saved setup can be resumed once access is restored.", 503);
      throw error;
    }
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
    async createMerchant(setup) {
      const a = await setupRequest("merchant_create", "/v2/core/accounts", {
        contact_email: setup.contact_email,
        display_name: setup.display_name,
        identity: { country: setup.country },
        dashboard: "full",
        defaults: { responsibilities: { fees_collector: "stripe", losses_collector: "stripe" } },
        configuration: { merchant: { capabilities: { card_payments: { requested: true } } } },
        include: ["configuration.merchant", "defaults"],
        metadata: { korlix_setup: setup.id },
      }, "korlix-merchant-" + setup.id);
      if (!account(a.id) || a.object !== "v2.core.account" || a.livemode !== livemode ||
          a.dashboard !== "full" || a.defaults?.responsibilities?.fees_collector !== "stripe" ||
          a.defaults?.responsibilities?.losses_collector !== "stripe")
        throw new ProviderError("Stripe merchant creation could not be verified. Resume this saved setup before trying a different account.", 409);
      return { id: a.id, livemode };
    },
    async onboardingLink(accountId, { returnUrl, refreshUrl }) {
      if (!account(accountId)) throw new ProviderError("Invalid merchant account.", 409);
      const link = await setupRequest("merchant_onboarding_link", "/v2/core/account_links", {
        account: accountId,
        use_case: { type: "account_onboarding", account_onboarding: {
          return_url: returnUrl, refresh_url: refreshUrl,
          collection_options: { fields: "eventually_due" },
        } },
      });
      let url;
      try { url = new URL(link.url); } catch {}
      if (link.object !== "v2.core.account_link" || link.account !== accountId ||
          link.livemode !== livemode || !url || url.protocol !== "https:" ||
          !["connect.stripe.com", "accounts.stripe.com"].includes(url.hostname) ||
          url.username || url.password || url.port)
        throw new ProviderError("Stripe returned an invalid setup link. Resume setup to try again.", 409);
      return url.href;
    },
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
      const { data } = await request(
        "oauth_exchange",
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
    async identity(grant, { allowPendingCompatibility = false } = {}) {
      if (!account(grant.account_id) || grant.livemode !== livemode)
        throw new ProviderError("Reconnect your merchant account.", 409);
      const query = new URLSearchParams({
        "include[0]": "configuration.merchant",
        "include[1]": "defaults",
      });
      let a;
      try {
        a = await api("/v2/core/accounts/" + grant.account_id + "?" + query);
      } catch (error) {
        // OAuth can return an account that Stripe cannot yet expose through
        // v2. Verify its identity for owner confirmation without declaring
        // it payment-ready. Checkout never enables this compatibility path.
        if (!allowPendingCompatibility || error.upstream?.status !== 400 ||
            !["v1_account_instead_of_v2_account", "account_not_yet_compatible_with_v2"]
              .includes(error.upstream?.code)) throw error;
        const legacy = await api("/accounts/" + grant.account_id);
        if (legacy.id !== grant.account_id || legacy.object !== "account" ||
            legacy.controller?.stripe_dashboard?.type !== "full" ||
            legacy.controller?.fees?.payer !== "account" ||
            legacy.controller?.losses?.payments !== "stripe" ||
            legacy.controller?.requirement_collection !== "stripe")
          throw new ProviderError(
            "Connect an independent Stripe business account with Stripe-managed processing fees.", 409);
        return {
          id: legacy.id,
          label: String(legacy.business_profile?.name || legacy.company?.name || legacy.id).slice(0, 250),
          charges_enabled: false,
          card_payments_status: "pending_v2_verification",
          payouts_status: "pending_v2_verification",
          readiness_source: "v1_identity_only",
          livemode,
        };
      }
      if (
        a.id !== grant.account_id ||
        a.object !== "v2.core.account" ||
        a.livemode !== livemode ||
        a.dashboard !== "full" ||
        a.defaults?.responsibilities?.fees_collector !== "stripe" ||
        a.defaults?.responsibilities?.losses_collector !== "stripe"
      )
        throw new ProviderError(
          "Connect an independent Stripe business account with Stripe-managed processing fees.",
          409,
        );
      const capabilities = a.configuration?.merchant?.capabilities;
      const cards = capabilities?.card_payments?.status;
      const payouts = capabilities?.stripe_balance?.payouts?.status;
      return {
        id: a.id,
        label: String(
          a.display_name || a.defaults?.profile?.doing_business_as || a.id,
        ).slice(0, 250),
        // Keep the existing storage projection; decisions use v2 capabilities.
        charges_enabled: cards === "active" && payouts === "active",
        card_payments_status: cards || "unavailable",
        payouts_status: payouts || "unavailable",
        readiness_source: "accounts_v2",
        livemode,
      };
    },
    async checkout(pay, wire) {
      if (config.enabled !== true)
        throw new ProviderError(
          "New booking payments are temporarily paused.",
          503,
        );
      const payload = new URLSearchParams(wire);
      if (
        [...payload.keys()].some((k) =>
          /application_fee|transfer_data|on_behalf_of/.test(k),
        )
      )
        throw new ProviderError(
          "Booking payments must go directly to the business without a KORLIX transaction fee.",
          409,
        );
      // Recheck the actual merchant on every create/retry instead of trusting
      // the account's readiness snapshot from when it was first connected.
      const merchant = await this.identity({
        account_id: pay.account_id,
        livemode: pay.livemode,
      });
      if (!merchant.charges_enabled)
        throw new ProviderError(
          "The business must finish its Stripe payment and payout setup before accepting payments.",
          409,
        );
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
