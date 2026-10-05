// Isolated hosted acceptance only. No production entry point imports this module.
import { randomUUID } from "node:crypto";
import { booking, event, hash, secret, token, uuid } from "../../scheduling/core.mjs";
import { schedulingConnected } from "../../scheduling/connected.mjs";
import { schedulingNotifications } from "../../scheduling/notifications.mjs";
import { providerSettings } from "../../scheduling/provider_core.mjs";
import { stripeProvider, stripeSignature } from "../../scheduling/stripe_provider.mjs";
import { validateHostedAcceptanceDatabase } from "./hosted_acceptance_database.mjs";

const PLATFORM = "acct_1UN1QuLwavBaepoe", MERCHANT = "acct_1UN1WiLwavcz7g46";
const VERSION = "2026-09-30.endive", GUEST = "sandbox-guest@example.test";
const EVENTS = new Set(["checkout.session.completed", "checkout.session.expired",
  "checkout.session.async_payment_succeeded", "checkout.session.async_payment_failed", "charge.refunded"]);
const RPC = Object.freeze({
  korlix_schedule_owner_v1: ["p_actor", "p_action", "p_id", "p_data"],
  korlix_schedule_public_v1: ["p_action", "p_slug", "p_data"],
  korlix_schedule_payment_v2: ["p_action", "p_id", "p_data"],
  korlix_schedule_subjects_v2: ["p_actor", "p_slug", "p_data"],
});
function reject(code, status = 409) {
  const error = new Error(code); error.code = code; error.status = status; throw error;
}
function requireThat(condition, code, status) { if (!condition) reject(code, status); }

export async function createHostedAcceptanceFlow(config, { pool, fetcher = fetch, now = Date.now } = {}) {
  requireThat(config.paymentRuntime === true && pool && /^[a-f0-9]{64}$/.test(config.encryptionKey || ""), "payment_runtime_configuration", 503);
  const expiresAt = typeof config.expiresAt === "number" ? config.expiresAt : Date.parse(config.expiresAt);
  requireThat(Number.isFinite(expiresAt), "acceptance_expiry_configuration", 503);
  const environment = {
    NODE_ENV: "test", KORLIX_SCHEDULING_PUBLIC_URL: config.origin,
    KORLIX_SCHEDULING_TOKEN_KEY: Buffer.from(config.encryptionKey, "hex").toString("base64"),
    KORLIX_SCHEDULING_STRIPE_CLIENT_ID: "ca_hosted_acceptance_no_oauth",
    KORLIX_SCHEDULING_STRIPE_SECRET_KEY: config.key || "",
    KORLIX_SCHEDULING_STRIPE_WEBHOOK_SECRET: config.webhook || "",
    KORLIX_SCHEDULING_STRIPE_API_VERSION: VERSION,
    KORLIX_SCHEDULING_STRIPE_ENABLED: "false",
  };
  const settings = providerSettings(environment, config.origin), cipher = settings.cipher;
  let closed = false, running = false, client, run, connected, routes, candidate = null, commandFinished, completeCommand;
  let outboundCount = 0, readiness = null;
  async function call(name, args) {
    const keys = RPC[name];
    requireThat(client && keys && Object.keys(args).length === keys.length && keys.every((key) => Object.hasOwn(args, key)), "rpc_not_allowed", 503);
    return (await client.query(`SELECT public.${name}(${keys.map((key, i) => `${key}=>$${i + 1}`).join(",")}) AS value`, keys.map((key) => args[key]))).rows[0].value;
  }
  const owner = (action, id = null, data = {}) => call("korlix_schedule_owner_v1", { p_actor: run.host_id, p_action: action, p_id: id, p_data: data });
  const payment = (action, id = run.booking_id, data = {}) => call("korlix_schedule_payment_v2", { p_action: action, p_id: id, p_data: data });
  const publicCall = (action, slug = null, data = {}) => call("korlix_schedule_public_v1", { p_action: action, p_slug: slug, p_data: data });
  const database = { rpc: async (name, args) => { try { return { data: await call(name, args) }; } catch (error) { return { error }; } } };
  const notifications = schedulingNotifications({ database, environment, publicRoot: config.origin, autoStart: false });
  function active() { requireThat(now() < expiresAt, "acceptance_expired", 410); }
  async function pay() {
    requireThat(run.booking_id, "booking_not_created", 409);
    const p = await payment("private");
    requireThat(p.booking_id === run.booking_id && p.booking.owner_id === run.host_id && p.booking.event_id === run.event_id &&
      p.account_id === MERCHANT && p.amount_cents === 100 && p.currency === "usd" && p.livemode === false &&
      p.booking.guest_email === GUEST && p.connection.remote_id === MERCHANT && p.connection.owner_id === run.host_id,
    "booking_binding_mismatch", 503);
    return p;
  }
  async function guardedFetch(url, options = {}) {
    requireThat(client && run, "request_outside_command", 503);
    const u = new URL(url), headers = new Headers(options.headers), method = options.method || "GET";
    requireThat(u.origin === "https://api.stripe.com" && !u.username && !u.password && !u.hash &&
      /^(?:rk|sk)_test_[A-Za-z0-9]+$/.test(config.key || "") && headers.get("authorization") === "Bearer " + config.key &&
      headers.get("stripe-version") === VERSION && options.redirect !== "follow", "provider_request_not_allowed", 503);
    const account = headers.get("stripe-account");
    const identity = method === "GET" && !account && !options.body && (
      (u.pathname === "/v1/account" && !u.search) ||
      (u.pathname === "/v2/core/accounts/" + MERCHANT && u.searchParams.size === 2 &&
        u.searchParams.get("include[0]") === "configuration.merchant" && u.searchParams.get("include[1]") === "defaults") ||
      (config.endpointId && u.pathname === "/v1/webhook_endpoints/" + config.endpointId && !u.search));
    let p;
    if (!identity) {
      requireThat(account === MERCHANT, "provider_account_not_allowed", 503); p = await pay();
      if (method === "GET") {
        const feeRead = p.payment_intent_id && u.pathname === "/v1/payment_intents/" + p.payment_intent_id &&
          u.searchParams.size === 1 && u.searchParams.get("expand[]") === "latest_charge";
        requireThat(!options.body && (feeRead || !u.search && (
          (p.checkout_id && u.pathname === "/v1/checkout/sessions/" + p.checkout_id) ||
          (candidate?.type.startsWith("checkout.session.") && u.pathname === "/v1/checkout/sessions/" + candidate.object.id) ||
          (p.refund_id && u.pathname === "/v1/refunds/" + p.refund_id) ||
          (candidate?.type === "charge.refunded" && u.pathname === "/v1/charges/" + candidate.object.id && candidate.object.payment_intent === p.payment_intent_id)
        )), "provider_resource_not_owned", 503);
      } else {
        requireThat(method === "POST" && !u.search && typeof options.body === "string", "provider_write_not_allowed", 503);
        const body = new URLSearchParams(options.body);
        requireThat([...body.keys()].every((key) => body.getAll(key).length === 1 && !/application_fee|transfer_data|on_behalf_of/.test(key)) &&
          body.get("metadata[korlix_booking]") === run.booking_id, "provider_payment_scope", 503);
        if (u.pathname === "/v1/checkout/sessions") {
          active(); requireThat(run.enabled && p.payment_state === "unpaid" && p.booking.state === "awaiting_payment" && !p.checkout_id,
            "checkout_paused_or_finished", 409);
          const manage = notifications.open(p.booking.sealed_manage_token, p.booking.request_id);
          const returnUrl = config.origin + "/book/manage#" + run.booking_id + "." + manage;
          requireThat(headers.get("idempotency-key") === "korlix-scheduling-checkout-" + run.booking_id &&
            body.get("customer_email") === GUEST && body.get("client_reference_id") === run.booking_id &&
            body.get("payment_intent_data[metadata][korlix_booking]") === run.booking_id && body.get("mode") === "payment" &&
            body.get("line_items[0][quantity]") === "1" && body.get("line_items[0][price_data][currency]") === "usd" &&
            body.get("line_items[0][price_data][unit_amount]") === "100" &&
            body.get("expires_at") === String(Math.floor(Date.parse(p.checkout_expires_at) / 1000)) &&
            body.get("success_url") === returnUrl && body.get("cancel_url") === returnUrl &&
            options.body === cipher.open(p.checkout_wire, "checkout:" + run.booking_id), "checkout_wire_mismatch", 503);
        } else {
          requireThat(u.pathname === "/v1/refunds" && headers.get("idempotency-key") === "korlix-scheduling-refund-" + run.booking_id &&
            ["paid", "paid_unfulfilled"].includes(p.payment_state) && ["required", "sending", "pending"].includes(p.refund_state) &&
            body.size === 3 && body.get("payment_intent") === p.payment_intent_id && body.get("amount") === "100", "refund_scope_mismatch", 503);
        }
      }
    }
    outboundCount++;
    const response = await fetcher(url, { ...options, redirect: "error" });
    // The production refund event adapter reads the charge independently; bind its
    // response here too before the adapter can project the refund observation.
    if (response.ok && candidate?.type === "charge.refunded" && u.pathname.startsWith("/v1/charges/")) {
      const actual = await response.clone().json();
      requireThat(actual.id === candidate.object.id && actual.payment_intent === p.payment_intent_id && actual.livemode === false &&
        actual.currency === "usd" && actual.amount === 100 && actual.amount_refunded === 100, "refund_charge_mismatch", 409);
    }
    return response;
  }
  const provider = stripeProvider(settings.providers.stripe, { fetcher: guardedFetch, diagnostic: () => {} });
  function mount() {
    connected?.stop(); routes = new Map();
    connected = schedulingConnected({ app: { get: () => {}, post: (path, fn) => routes.set(path, fn) }, base: "",
      route: (fn) => fn, call, ownerCall: (_actor, ...args) => owner(...args), publicCall,
      environment: { ...environment, KORLIX_SCHEDULING_STRIPE_ENABLED: String(run.enabled) },
      publicRoot: config.origin, notifications, fetcher: guardedFetch, now, autoStart: false });
  }
  async function transaction(fn) {
    await client.query("BEGIN");
    try { const result = await fn(); await client.query("COMMIT"); return result; }
    catch (error) { await client.query("ROLLBACK").catch(() => {}); throw error; }
  }
  async function command(fn) {
    requireThat(!closed, "acceptance_closed", 503); requireThat(!running, "acceptance_busy", 409); running = true;
    commandFinished = new Promise((resolve) => { completeCommand = resolve; });
    let locked = false, current;
    try {
      current = await pool.connect(); client = current;
      locked = (await client.query("SELECT pg_try_advisory_lock(135792468,246813579) AS locked")).rows[0]?.locked === true;
      requireThat(locked, "acceptance_busy", 409);
      try { await validateHostedAcceptanceDatabase(client, config); }
      catch { reject("database_isolation_unverified", 503); }
      run = (await client.query("SELECT * FROM public.korlix_hosted_acceptance_run WHERE singleton=true")).rows[0];
      requireThat(run && run.run_id && run.host_id, "acceptance_run_missing", 503);
      // The single booking association is permanent. Foreign rows cannot expand
      // the payment adapter's scope, even if injected outside this process.
      const count = (await client.query("SELECT count(*)::int AS total FROM public.korlix_schedule_bookings")).rows[0].total;
      requireThat(count === (run.booking_id ? 1 : 0), "acceptance_booking_scope", 503);
      mount(); return await fn();
    } finally {
      connected?.stop(); candidate = null; run = null; client = null;
      let releaseError;
      if (locked) try {
        const released = await current.query("SELECT pg_advisory_unlock(135792468,246813579) AS unlocked");
        if (released.rows[0]?.unlocked !== true) releaseError = new Error("acceptance_unlock_failed");
      } catch (error) { releaseError = error; }
      // pg releases with an error destroy the session instead of returning a
      // possibly advisory-locked connection to the shared pool.
      try { current?.release(releaseError); } finally {
        running = false; completeCommand?.(); commandFinished = null; completeCommand = null;
      }
    }
  }
  async function read(path) {
    const response = await guardedFetch("https://api.stripe.com" + path, { headers: {
      Authorization: "Bearer " + config.key, "Stripe-Version": VERSION }, signal: AbortSignal.timeout(15000) });
    requireThat(response.ok, "provider_readiness_unavailable", 503); return response.json();
  }
  async function verifyIdentity(requireReady = true) {
    const platform = await read("/v1/account");
    requireThat(platform.object === "account" && platform.id === PLATFORM && platform.livemode !== true, "platform_identity_mismatch", 409);
    const merchant = await provider.identity({ account_id: MERCHANT, livemode: false });
    requireThat((!requireReady || merchant.charges_enabled) && merchant.readiness_source === "accounts_v2", "merchant_not_ready", 409);
    return merchant;
  }
  async function verify() {
    readiness = null;
    requireThat(/^whsec_[A-Za-z0-9]+$/.test(config.webhook || "") && /^we_[A-Za-z0-9]+$/.test(config.endpointId || ""), "webhook_configuration_required", 503);
    await verifyIdentity();
    const endpoint = await read("/v1/webhook_endpoints/" + config.endpointId);
    requireThat(endpoint.id === config.endpointId && endpoint.object === "webhook_endpoint" && endpoint.livemode === false &&
      endpoint.status === "enabled" && endpoint.api_version === VERSION && endpoint.url === config.origin + "/acceptance/payments/webhook" &&
      Array.isArray(endpoint.enabled_events) && endpoint.enabled_events.length === EVENTS.size && endpoint.enabled_events.every((name) => EVENTS.has(name)),
    "webhook_endpoint_mismatch", 409);
    // Stripe's retrieved endpoint object omits the creation-time connect flag.
    // Source routing is proven separately by an authenticated merchant event.
    readiness = { platform: PLATFORM, merchant: MERCHANT, livemode: false, endpointId: config.endpointId,
      endpointConfigurationVerified: true, checkedAt: new Date(now()).toISOString() };
    return readiness;
  }
  async function seed() {
    if (run.event_id) {
      // API key rotation changes the production adapter fingerprint. Rebind only
      // after fresh identity proof, preserving the exact authorized merchant.
      await client.query("UPDATE public.korlix_schedule_connections SET config_hash=$1 WHERE owner_id=$2 AND provider='stripe' AND remote_id=$3 AND livemode=false",
        [settings.providers.stripe.fingerprint, run.host_id, MERCHANT]); return;
    }
    await transaction(async () => {
      await owner("save_profile", null, { revision: 0, display_name: "Isolated sandbox host", timezone: "UTC",
        weekly: Array.from({ length: 7 }, (_, day) => ({ day, windows: [[540, 1020]] })), overrides: [] });
      await client.query("INSERT INTO public.korlix_schedule_connections(owner_id,provider,remote_id,label,sealed_grant,config_hash,enabled,charges_enabled,livemode) VALUES($1,'stripe',$2,'Isolated sandbox merchant',$3,$4,true,true,false)",
        [run.host_id, MERCHANT, cipher.seal({ account_id: MERCHANT, livemode: false }, `${run.host_id}:stripe:${MERCHANT}`), settings.providers.stripe.fingerprint]);
      const e = await owner("save_event", null, { ...event({ revision: 0, title: "Isolated sandbox acceptance — USD 1.00",
        description: "Synthetic hosted test appointment", kind: "one_to_one", duration_minutes: 30, interval_minutes: 30,
        buffer_before: 0, buffer_after: 0, notice_minutes: 0, horizon_days: 365, daily_limit: 40, capacity: 1,
        cancel_notice_minutes: 0, location_kind: "video", location_detail: "https://example.test/no-meeting", questions: [], color: "#72D6EB",
        price_cents: 100, refund_policy: "Synthetic sandbox payment; full refund during acceptance." }), slug: "sandbox-" + run.run_id });
      const published = await owner("event_state", e.id, { revision: e.revision, state: "published", confirmed: true });
      await client.query("UPDATE public.korlix_hosted_acceptance_run SET event_id=$1 WHERE singleton=true AND event_id IS NULL", [published.id]);
      run.event_id = published.id;
    });
  }
  function summary(p) {
    return { bookingId: p.booking_id, bookingState: p.booking.state, paymentState: p.payment_state, refundState: p.refund_state,
      checkoutId: p.checkout_id, paymentIntentId: p.payment_intent_id, refundId: p.refund_id, amountCents: p.amount_cents,
      currency: p.currency, livemode: p.livemode, holdExpiresAt: p.booking.hold_expires_at, checkoutExpiresAt: p.checkout_expires_at };
  }
  async function status() {
    const receivedEvents = (await client.query("SELECT provider_event_id,account_id,kind FROM public.korlix_schedule_payment_receipts ORDER BY received_at")).rows;
    return { isolated: true, runId: run.run_id, enabled: run.enabled, checkoutEnabled: run.enabled && now() < expiresAt,
      webhookConfigured: !!config.webhook && !!config.endpointId, readiness, expired: now() >= expiresAt,
      endpointConfigurationVerified: readiness?.endpointConfigurationVerified === true,
      connectedDeliveryVerified: receivedEvents.some((e) => e.account_id === MERCHANT && EVENTS.has(e.kind)),
      outboundCount, booking: run.booking_id ? summary(await pay()) : null,
      receivedEvents };
  }
  function privateReturn(p) {
    const manage = notifications.open(p.booking.sealed_manage_token, p.booking.request_id);
    return config.origin + "/book/manage#" + p.booking_id + "." + manage;
  }
  async function refundTick() {
    if (!run.booking_id) return;
    const p = await pay();
    if (!["required", "sending", "pending"].includes(p.refund_state)) return;
    // Refunds remain available after expiry or webhook disablement, while a
    // rotated credential must still prove the exact sandbox identities.
    await verifyIdentity(false);
    const claim = await payment("refund_claim");
    if (!claim) return;
    try { await payment("refund_finish", run.booking_id, { ...await provider.refund(claim), lease_id: claim.lease_id }); }
    catch (error) { await payment("refund_finish", run.booking_id, { lease_id: claim.lease_id, state: "pending" }); throw error; }
  }
  return {
    status: () => command(status),
    enable: () => command(async () => {
      active(); await verify(); await seed();
      await client.query("UPDATE public.korlix_hosted_acceptance_run SET enabled=true WHERE singleton=true"); run.enabled = true;
      return status();
    }),
    pause: () => command(async () => {
      await client.query("UPDATE public.korlix_hosted_acceptance_run SET enabled=false WHERE singleton=true"); run.enabled = false; return status();
    }),
    book: () => command(async () => {
      active(); requireThat(run.enabled, "checkout_paused", 409);
      if (run.booking_id) return { ...summary(await pay()), returnUrl: privateReturn(await pay()), reused: true };
      await verify(); requireThat(run.event_id, "acceptance_event_missing", 503);
      const slug = (await client.query("SELECT slug FROM public.korlix_schedule_events WHERE id=$1 AND owner_id=$2", [run.event_id, run.host_id])).rows[0]?.slug;
      requireThat(slug, "acceptance_event_missing", 503);
      await transaction(async () => {
        const manage = secret(), context = { browser_hash: hash(secret()), token_hash: hash(secret()) };
        await publicCall("context", slug, context);
        const starts = new Date(now()); starts.setUTCDate(starts.getUTCDate() + 2); starts.setUTCHours(12, 0, 0, 0);
        const data = booking({ request_id: randomUUID(), manage_token: manage, starts_at: starts.toISOString(), guest_name: "Synthetic sandbox guest",
          guest_email: GUEST, guest_timezone: "UTC", answers: {}, confirmed: true });
        await connected.checkAvailability(null, slug, { ...data, ...context });
        const b = await publicCall("book", slug, { ...data, ...context, payments_ready: true,
          sealed_manage_token: notifications.seal(manage, data.request_id) });
        await client.query("UPDATE public.korlix_hosted_acceptance_run SET booking_id=$1 WHERE singleton=true AND booking_id IS NULL", [b.id]);
        run.booking_id = b.id;
      });
      const p = await pay(); return { ...summary(p), returnUrl: privateReturn(p), reused: false };
    }),
    checkout: () => command(async () => {
      active(); requireThat(run.enabled, "checkout_paused", 409); await verify();
      await connected.ensureCheckout((await pay()).booking_id);
      const p = await pay(); requireThat(p.checkout_url && p.payment_state === "unpaid" && p.booking.state === "awaiting_payment" &&
        Date.parse(p.checkout_expires_at) > now() && Date.parse(p.booking.hold_expires_at) > now(), "checkout_unavailable", 409);
      return { bookingId: p.booking_id, checkoutUrl: p.checkout_url, checkoutId: p.checkout_id, returnUrl: privateReturn(p) };
    }),
    refund: () => command(async () => {
      const p = await pay();
      if (p.refund_state === "none") await payment("refund_request", run.booking_id, { actor: run.host_id, confirmed: true, revision: p.booking.revision });
      await refundTick(); return status();
    }),
    tick: () => command(async () => { await refundTick(); return status(); }),
    feeProof: () => command(async () => {
      const p = await pay(); requireThat(/^pi_[A-Za-z0-9]+$/.test(p.payment_intent_id || ""), "payment_not_confirmed", 409);
      await verifyIdentity(false);
      const response = await guardedFetch("https://api.stripe.com/v1/payment_intents/" + p.payment_intent_id + "?expand[]=latest_charge", {
        headers: { Authorization: "Bearer " + config.key, "Stripe-Version": VERSION, "Stripe-Account": MERCHANT },
        signal: AbortSignal.timeout(15000) });
      requireThat(response.ok, "fee_verification_unavailable", 503);
      const intent = await response.json(), charge = intent.latest_charge;
      requireThat(intent.id === p.payment_intent_id && intent.livemode === false && intent.amount === 100 && intent.currency === "usd" &&
        charge?.object === "charge" && charge.payment_intent === intent.id && charge.livemode === false && charge.amount === 100 && charge.currency === "usd" &&
        intent.application_fee_amount == null && intent.transfer_data == null && intent.on_behalf_of == null &&
        charge.application_fee === null && charge.application_fee_amount === null && charge.transfer_data == null,
      "fee_verification_mismatch", 409);
      return { merchant: MERCHANT, paymentIntentId: intent.id, chargeId: charge.id, amountCents: 100, currency: "usd", livemode: false,
        applicationFee: null, applicationFeeAmount: null, platformFeePercent: 0 };
    }),
    webhook: async (raw, signature) => {
      // Reject unauthenticated traffic before acquiring a database connection.
      requireThat(stripeSignature(raw, signature, config.webhook, now()), "invalid_webhook_signature", 400);
      let e; try { e = JSON.parse(raw.toString("utf8")); } catch { reject("invalid_webhook_payload", 400); }
      requireThat(/^evt_[A-Za-z0-9]+$/.test(e.id || "") && e.account === MERCHANT && e.livemode === false && EVENTS.has(e.type), "webhook_scope_mismatch", 400);
      return command(async () => {
      const p = await pay(), object = e.data?.object;
      if (e.type.startsWith("checkout.session.")) {
        requireThat(/^cs_test_[A-Za-z0-9]+$/.test(object?.id || "") && object.livemode === false &&
          (p.checkout_id === object.id || (!p.checkout_id && p.checkout_wire && object.metadata?.korlix_booking === run.booking_id)), "webhook_booking_mismatch", 400);
      } else requireThat(/^ch_[A-Za-z0-9]+$/.test(object?.id || "") && object.livemode === false &&
        p.payment_intent_id && object.payment_intent === p.payment_intent_id, "webhook_booking_mismatch", 400);
      if ((await client.query("SELECT 1 FROM public.korlix_schedule_payment_receipts WHERE provider_event_id=$1 AND account_id=$2", [e.id, MERCHANT])).rows.length)
        return { received: true, duplicate: true };
      candidate = { type: e.type, object };
      let statusCode = 200, result;
      const response = { set: () => response, status: (code) => { statusCode = code; return response; }, json: (value) => { result = value; return response; } };
      await routes.get("/payments/webhook")({ korlixSchedulingRawBody: raw, get: (name) => name === "stripe-signature" ? signature : undefined }, response);
      requireThat(statusCode === 200 && result?.received === true, "webhook_verification_pending", statusCode);
      return { received: true };
      });
    },
    customerStatus: (input) => command(async () => {
      let id, manageHash; try { id = uuid(input?.booking_id); manageHash = hash(token(input?.manage_token)); } catch { reject("booking_link_unavailable", 404); }
      requireThat(id === run.booking_id, "booking_link_unavailable", 404);
      // Production public RPC is a read-only ledger projection. Do not call
      // reconcilePublic here: a redirect or refresh is not webhook evidence.
      let b; try { b = await publicCall("manage", null, { booking_id: id, manage_hash: manageHash }); } catch { reject("booking_link_unavailable", 404); }
      requireThat(b.payment?.livemode === false && b.payment.amount_cents === 100 && b.payment.currency === "usd", "booking_binding_mismatch", 503);
      return { booking: { state: b.state, starts_at: new Date(b.starts_at).toISOString(), guest_timezone: "UTC",
        snapshot: { title: b.snapshot.title, host_name: b.snapshot.host_name, duration_minutes: b.snapshot.duration_minutes } },
      payment: { state: b.payment.state, amount_cents: 100, currency: "usd", livemode: false, refund_state: b.payment.refund_state } };
    }),
    close: async () => { closed = true; await commandFinished; connected?.stop(); notifications.stop(); },
  };
}
