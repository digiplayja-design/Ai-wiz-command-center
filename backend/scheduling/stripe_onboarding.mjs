import { fail, hash, secret, text, token, uuid } from "./core.mjs";

const applicationUrl = "https://www.korlixdeveloper.com/app/";
const retryWindowMs = 29 * 86400000;

// Creating a merchant and connecting it are deliberately separate owner actions.
// Persist the immutable request before Stripe I/O so uncertain responses can be
// retried with the same idempotency key without creating another merchant.
export function stripeOnboarding({
  app, base, route, call, config, adapter, cipher, publicRoot,
  enabled, now = Date.now,
}) {
  const context = { config_hash: config.fingerprint, livemode: adapter.livemode };
  const setup = (actor, action, id = null, data = {}) =>
    call("korlix_schedule_stripe_setup_v1", {
      p_actor: actor, p_action: action, p_id: id, p_data: { ...context, ...data },
    });
  const status = actor => setup(actor, "status");
  function available() {
    if (!enabled) fail("Stripe business setup needs administrator configuration.", 503);
  }
  function consent(body) {
    if (body.confirmed !== true) fail("Confirm that you want to set up your Stripe business account.");
  }
  async function own(actor, id) {
    const s = await setup(actor, "private", uuid(id));
    if (s.config_hash !== context.config_hash || s.livemode !== context.livemode)
      fail("The payment configuration changed. Review merchant setup with your administrator.", 409);
    return s;
  }
  async function open(actor, saved) {
    let s = saved;
    if (!s.account_id) {
      const createdAt = Date.parse(s.created_at);
      if (!Number.isFinite(createdAt) || now() - createdAt >= retryWindowMs)
        fail("Merchant setup needs administrator recovery before retrying.", 409);
      const merchant = await adapter.createMerchant(s);
      s = await setup(actor, "created", s.id, { account_id: merchant.id });
    }
    const url = await adapter.onboardingLink(s.account_id, {
      returnUrl: publicRoot + base + "/stripe/merchant-setup/return",
      refreshUrl: publicRoot + base + "/stripe/merchant-setup/refresh",
    });
    return { setup: await status(actor), url };
  }
  async function identity(s) {
    if (!s.account_id) fail("Continue Stripe setup before reviewing the merchant.", 409);
    const verified = await adapter.identity({ account_id: s.account_id, livemode: s.livemode });
    if (verified.id !== s.account_id || verified.livemode !== s.livemode ||
        verified.readiness_source !== "accounts_v2")
      fail("Merchant identity could not be verified. Review Stripe setup again.", 409);
    return verified;
  }

  app.post(base + "/stripe/merchant-setup/start", route(async (q, r, u) => {
    available();
    consent(q.body);
    const previous = await status(u.id);
    if (previous) return r.json(await open(u.id, await own(u.id, previous.id)));
    const country = text(q.body.country, 2).toUpperCase();
    if (country !== "US") fail("Guided Stripe setup currently supports United States businesses. Your setup has not been created.");
    const email = text(u.email, 254);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
      fail("Your KORLIX account needs a verified contact email.", 409);
    const s = await setup(u.id, "prepare", null, {
      confirmed: true, country, display_name: text(q.body.display_name, 120), contact_email: email,
    });
    r.json(await open(u.id, s));
  }, true));

  app.post(base + "/stripe/merchant-setup/:id/resume", route(async (q, r, u) => {
    available();
    consent(q.body);
    r.json(await open(u.id, await own(u.id, q.params.id)));
  }, true));

  app.get(base + "/stripe/merchant-setup/:id/review", route(async (q, r, u) => {
    available();
    const s = await own(u.id, q.params.id);
    const verified = await identity(s);
    const reviewToken = secret();
    const reviewed = await setup(u.id, "review", s.id, {
      account_id: s.account_id, review_hash: hash(reviewToken),
    });
    const { id, label, livemode, charges_enabled, card_payments_status, payouts_status } = verified;
    r.json({ setup: await status(u.id),
      identity: { id, label, livemode, charges_enabled, card_payments_status, payouts_status },
      replaces_existing: reviewed.replaces_existing, review_token: reviewToken });
  }, true));

  app.post(base + "/stripe/merchant-setup/:id/confirm", route(async (q, r, u) => {
    available();
    consent(q.body);
    const s = await own(u.id, q.params.id);
    const reviewHash = hash(token(q.body.review_token));
    if (s.review_hash !== reviewHash || !s.review_expires_at ||
        Date.parse(s.review_expires_at) <= now())
      fail("The merchant review expired or your connection changed. Review again.", 409);
    const verified = await identity(s);
    r.json(await setup(u.id, "confirm", s.id, {
      confirmed: true, review_hash: reviewHash, account_id: s.account_id, identity: verified,
      sealed_grant: cipher.seal({ account_id: s.account_id, livemode: s.livemode },
        `${u.id}:stripe:${s.account_id}`),
    }));
  }, true));

  // Stripe may revisit a single-use link's refresh URL. Never mint a fresh
  // capability from a public callback: the owner resumes from their signed-in UI.
  for (const action of ["return", "refresh"]) {
    app.get(base + "/stripe/merchant-setup/" + action, route(async (_q, r) => {
      const heading = action === "return" ? "Review your Stripe setup" : "Continue your Stripe setup";
      const instruction = action === "return"
        ? "Open 2MEETU → Connections → Review and confirm business. We will check your current Stripe status before you confirm the connection."
        : "Open 2MEETU → Connections → Continue Stripe setup to get a fresh secure link for the same business account.";
      r.set("Content-Security-Policy", "default-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'")
        .type("html").send(`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KORLIX 2MEETU Stripe setup</title><body><main><h1>${heading}</h1><p>${instruction}</p><p>Returning from Stripe does not confirm payment readiness or change your saved merchant connection.</p><p><a href="${applicationUrl}">Return to KORLIX 2MEETU</a></p></main></body></html>`);
    }));
  }
  return { status };
}
