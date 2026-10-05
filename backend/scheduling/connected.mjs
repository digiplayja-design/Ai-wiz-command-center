import { randomUUID } from "node:crypto";
import {
  fail,
  hash,
  secret,
  token,
  uuid,
  text,
  integer,
  date,
  instant,
} from "./core.mjs";
import {
  providerSettings,
  ProviderError,
  challenge,
} from "./provider_core.mjs";
import { calendarProvider, calendarWire } from "./calendar_provider.mjs";
import {
  stripeProvider,
  stripeSignature,
  checkoutWire,
} from "./stripe_provider.mjs";

const binding = (c) => `${c.owner_id}:${c.provider}:${c.remote_id}`;
const html =
  '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KORLIX 2MEETU connection</title><body><main><h1>Account verified</h1><p>Return to KORLIX 2MEETU → Connections. Refresh, review the account, then confirm the connection.</p><p>You can close this tab.</p></main></body></html>';
export function schedulingConnected({
  app,
  base,
  route,
  call,
  ownerCall,
  publicCall,
  environment,
  publicRoot,
  notifications,
  fetcher = fetch,
  now = Date.now,
  autoStart = true,
}) {
  const { cipher, providers } = providerSettings(environment, publicRoot),
    adapters = Object.fromEntries(
      Object.entries(providers).map(([name, config]) => [
        name,
        name === "stripe"
          ? stripeProvider(config, { fetcher })
          : calendarProvider(config, { fetcher, now }),
      ]),
    );
  const paymentsConfigured = providers.stripe.ready && !!providers.stripe.webhook;
  const paymentsReady = paymentsConfigured && providers.stripe.enabled;
  const capabilities = {
    calendar_sync: providers.google.ready || providers.microsoft.ready,
    payments: paymentsReady,
    payment_configuration_ready: paymentsConfigured,
    platform_fee_percent: 0,
    team_scheduling: true,
    providers: Object.fromEntries(
      Object.entries(providers).map(([name, c]) => [
        name,
        {
          configured: c.ready && (name !== "stripe" || paymentsConfigured),
          callback: c.callback,
        },
      ]),
    ),
    conflict_scope:
      "KORLIX bookings, manual blocks, and calendars enabled by each host",
  };
  const connection = (actor, action, id = null, data = {}) =>
    call("korlix_schedule_connections_v2", {
      p_actor: actor,
      p_action: action,
      p_id: id,
      p_data: data,
    });
  const oauth = (action, id = null, data = {}) =>
    call("korlix_schedule_oauth_v2", {
      p_action: action,
      p_id: id,
      p_data: data,
    });
  const sync = (action, id, data = {}) =>
    call("korlix_schedule_calendar_sync_v2", {
      p_action: action,
      p_id: id,
      p_data: data,
    });
  const payment = (action, id = null, data = {}) =>
    call("korlix_schedule_payment_v2", {
      p_action: action,
      p_id: id,
      p_data: data,
    });
  const team = (actor, action, id = null, data = {}) =>
    call("korlix_schedule_team_v2", {
      p_actor: actor,
      p_action: action,
      p_id: id,
      p_data: data,
    });
  const queue = (action, job = null, data = {}) =>
    call("korlix_schedule_calendar_queue_v2", {
      p_action: action,
      p_id: job?.id || null,
      p_lease: job?.lease_id || null,
      p_data: data,
    });
  function configured(name) {
    if (
      !Object.hasOwn(providers, name) ||
      !providers[name].ready ||
      (name === "stripe" && !paymentsConfigured)
    )
      fail(
        "This provider needs administrator setup before it can be connected.",
        503,
      );
    return providers[name];
  }
  function checkConfig(c) {
    const config = configured(c.provider);
    if (c.state !== "connected" || c.config_hash !== config.fingerprint)
      throw new ProviderError(
        "Reconnect this account to restore access.",
        409,
        "reconnect_required",
      );
    return config;
  }
  function cookie(q, name) {
    return (q.get("cookie") || "")
      .split(";")
      .map((v) => v.trim())
      .find((v) => v.startsWith(name + "="))
      ?.slice(name.length + 1);
  }
  const cookieName = (p) => "korlix_sched_connect_" + p;
  async function withCalendar(id, fn) {
    const c = await sync("claim", id),
      lease = { lease_id: c.lease_id, revision: c.revision };
    try {
      checkConfig(c);
      let grant = cipher.open(c.sealed_grant, binding(c));
      if (!Number.isFinite(Date.parse(grant.expires_at)))
        throw new ProviderError("Reconnect this calendar.", 409);
      if (Date.parse(grant.expires_at) < now() + 60000) {
        grant = await adapters[c.provider].refresh(grant);
        await sync("token", id, {
          ...lease,
          sealed_grant: cipher.seal(grant, binding(c)),
        });
      }
      return await fn(c, grant, adapters[c.provider], lease);
    } finally {
      await sync("release", id, lease).catch(() => {});
    }
  }
  const inFlight = new Map();
  async function refresh(subject, { date: day, starts_at: start } = {}) {
    if (subject.replay) return;
    const point = start
      ? Date.parse(instant(start))
      : Date.parse(date(day) + "T00:00:00Z");
    if (
      !Number.isFinite(point) ||
      point < now() - 3 * 86400000 ||
      point > now() + 368 * 86400000
    )
      fail("Choose a date within the booking window.");
    const from = new Date(
        point - (start ? 3 * 3600000 : 2 * 86400000),
      ).toISOString(),
      to = new Date(
        point + (start ? 12 * 3600000 : 9 * 86400000),
      ).toISOString();
    // Coalesce identical simultaneous reads in this process; database leases protect other instances.
    const results = await Promise.allSettled(
      (subject.connections || []).map((c) => {
        const key = c.id + ":" + c.revision + ":" + from + ":" + to;
        if (inFlight.has(key)) return inFlight.get(key);
        const work = withCalendar(
          c.id,
          async (current, grant, provider, lease) => {
            const calendars = current.calendars.filter((cal) =>
              current.busy_ids.includes(cal.id),
            );
            if (calendars.length !== current.busy_ids.length)
              throw new ProviderError(
                "A selected calendar is unavailable. Ask the host to refresh calendar settings.",
                409,
              );
            const busy = await provider.busy(grant, calendars, from, to);
            await sync("cache", c.id, { ...lease, from, to, busy });
          },
        ).finally(() => inFlight.delete(key));
        inFlight.set(key, work);
        return work;
      }),
    );
    const failure = results.find((r) => r.status === "rejected");
    if (failure) throw failure.reason;
  }
  async function checkAvailability(actor, slug, data) {
    const subject = await call("korlix_schedule_subjects_v2", {
      p_actor: actor,
      p_slug: slug,
      p_data: data,
    });
    await refresh(subject, data);
    return subject;
  }
  async function dashboard(actor) {
    const [connections, teams] = await Promise.all([
      connection(actor, "list"),
      team(actor, "list"),
    ]);
    return { ...connections, teams };
  }
  app.get(base + "/payments/health", (_q, r) => {
    r.set("Cache-Control", "no-store").json({
      version: "connect_no_transaction_fee_20261005",
      configured: paymentsConfigured,
      checkoutEnabled: paymentsReady,
      livePayments: adapters.stripe.livemode,
      platformFeePercent: 0,
      chargePattern: "direct",
      accountReadiness: "accounts_v2",
      apiVersion: providers.stripe.version,
    });
  });
  app.get(
    base + "/connections",
    route(
      async (q, r, u) =>
        r.json({
          ...(await connection(u.id, "list")),
          providers: capabilities.providers,
        }),
      true,
    ),
  );
  app.post(
    base + "/connections/:provider/start",
    route(async (q, r, u) => {
      const c = configured(q.params.provider);
      if (q.body.confirmed !== true) fail("Confirm the account connection.");
      const id = randomUUID(),
        ticket = secret(),
        state = secret(),
        verifier = secret();
      await connection(u.id, "start", id, {
        provider: c.name,
        ticket_hash: hash(ticket),
        state_hash: hash(state),
        sealed_secrets: cipher.seal({ state, verifier }, id),
        config_hash: c.fingerprint,
      });
      r.json({
        id,
        url:
          publicRoot + base + "/connect/" + c.name + "/launch?ticket=" + ticket,
      });
    }, true),
  );
  app.get(
    base + "/connect/:provider/launch",
    route(async (q, r) => {
      const c = configured(q.params.provider),
        browser = secret();
      const attempt = await oauth("launch", null, {
        provider: c.name,
        ticket_hash: hash(token(q.query.ticket)),
        browser_hash: hash(browser),
      });
      if (attempt.config_hash !== c.fingerprint)
        fail("Connection settings changed. Start again.", 409);
      const secrets = cipher.open(attempt.sealed_secrets, attempt.id);
      r.cookie(cookieName(c.name), browser, {
        httpOnly: true,
        secure: true,
        sameSite: "lax",
        maxAge: 600000,
        path: base + "/connect/" + c.name,
      });
      r.redirect(
        303,
        adapters[c.name].authorizationUrl(
          secrets.state,
          challenge(secrets.verifier),
        ),
      );
    }),
  );
  app.get(
    base + "/connect/:provider/callback",
    route(async (q, r) => {
      const c = configured(q.params.provider),
        browser = token(cookie(q, cookieName(c.name))),
        state = token(q.query.state);
      const attempt = await oauth("claim", null, {
        provider: c.name,
        state_hash: hash(state),
        browser_hash: hash(browser),
      });
      r.clearCookie(cookieName(c.name), {
        httpOnly: true,
        secure: true,
        sameSite: "lax",
        path: base + "/connect/" + c.name,
      });
      if (q.query.error)
        fail(
          "Authorization was not completed. Return to KORLIX and start again.",
          409,
        );
      if (attempt.config_hash !== c.fingerprint)
        fail("Connection settings changed. Start again.", 409);
      const secrets = cipher.open(attempt.sealed_secrets, attempt.id),
        code = text(q.query.code, 4000);
      const grant = await adapters[c.name].exchange(code, secrets.verifier),
        identity = await adapters[c.name].identity(grant);
      await oauth("complete", attempt.id, {
        config_hash: c.fingerprint,
        sealed_grant: cipher.seal(grant, attempt.id),
        identity,
      });
      r.set(
        "Content-Security-Policy",
        "default-src 'none'; base-uri 'none'; frame-ancestors 'none'",
      )
        .type("html")
        .send(html);
    }),
  );
  app.post(
    base + "/connections/attempts/:id/confirm",
    route(async (q, r, u) => {
      if (q.body.confirmed !== true) fail("Review and confirm this account.");
      const a = await connection(u.id, "ready", uuid(q.params.id)),
        c = configured(a.provider);
      if (a.config_hash !== c.fingerprint)
        fail("Connection settings changed. Start again.", 409);
      const grant = cipher.open(a.sealed_grant, a.id),
        identity = await adapters[a.provider].identity(grant);
      if (identity.id !== a.identity.id)
        fail("The connected account changed. Start again.", 409);
      r.json(
        await connection(u.id, "finish", a.id, {
          confirmed: true,
          config_hash: c.fingerprint,
          sealed_grant: cipher.seal(
            grant,
            binding({
              owner_id: u.id,
              provider: a.provider,
              remote_id: identity.id,
            }),
          ),
        }),
      );
    }, true),
  );
  app.post(
    base + "/connections/:id/calendars",
    route(async (q, r, u) => {
      const c = await connection(u.id, "private", uuid(q.params.id));
      if (c.provider === "stripe") fail("Choose a calendar connection.");
      const calendars = await withCalendar(
        c.id,
        async (current, grant, provider) => {
          const list = await provider.calendars(grant);
          await connection(u.id, "calendar_list", c.id, {
            revision: current.revision,
            calendars: list,
          });
          return list;
        },
      );
      r.json({ calendars });
    }, true),
  );
  app.post(
    base + "/connections/:id/settings",
    route(async (q, r, u) => {
      if (!Array.isArray(q.body.busy_ids) || q.body.busy_ids.length > 5)
        fail("Choose up to five calendars.");
      r.json(
        await connection(u.id, "settings", uuid(q.params.id), {
          confirmed: q.body.confirmed === true,
          revision: integer(q.body.revision, 1, 1e9),
          busy_ids: q.body.busy_ids.map((id) => text(id, 2000)),
          write_id: q.body.write_id ? text(q.body.write_id, 2000) : null,
        }),
      );
    }, true),
  );
  app.post(
    base + "/connections/:id/disconnect",
    route(
      async (q, r, u) =>
        r.json(
          await connection(u.id, "disconnect", uuid(q.params.id), {
            confirmed: q.body.confirmed === true,
          }),
        ),
      true,
    ),
  );
  app.get(
    base + "/teams",
    route(async (q, r, u) => r.json({ teams: await team(u.id, "list") }), true),
  );
  app.post(
    base + "/teams",
    route(
      async (q, r, u) =>
        r.status(201).json({
          team: await team(u.id, "create", null, {
            name: text(q.body.name, 100),
          }),
        }),
      true,
    ),
  );
  for (const action of ["preview_join", "join"])
    app.post(
      base + "/teams/" + action,
      route(
        async (q, r, u) =>
          r.json(
            await team(u.id, action, null, {
              invite_hash: hash(token(q.body.invite)),
              confirmed: q.body.confirmed === true,
            }),
          ),
        true,
      ),
    );
  app.post(
    base + "/teams/:id/invite",
    route(async (q, r, u) => {
      const invite = secret();
      await team(u.id, "invite", uuid(q.params.id), {
        confirmed: q.body.confirmed === true,
        revision: integer(q.body.revision, 1, 1e9),
        invite_hash: hash(invite),
      });
      r.json({ invite, expires_days: 7 });
    }, true),
  );
  for (const action of ["leave", "remove"])
    app.post(
      base + "/teams/:id/" + action,
      route(
        async (q, r, u) =>
          r.json(
            await team(u.id, action, uuid(q.params.id), {
              confirmed: q.body.confirmed === true,
              ...(action === "remove" ? { user_id: uuid(q.body.user_id) } : {}),
            }),
          ),
        true,
      ),
    );
  async function ensureCheckout(id) {
    if (!paymentsReady) fail("New booking payments are temporarily paused.", 503);
    const p = await payment("private", id);
    checkConfig(p.connection);
    if (p.booking.state !== "awaiting_payment" || p.checkout_id) return;
    if (Date.parse(p.checkout_expires_at) <= now()) return;
    if (
      !p.checkout_wire &&
      Date.parse(p.checkout_expires_at) < now() + 31 * 60000
    )
      throw new ProviderError(
        "This checkout could not be started in time. Cancel this hold and choose a new time.",
        409,
      );
    const manage = notifications.open(
        p.booking.sealed_manage_token,
        p.booking.request_id,
      ),
      url = publicRoot + "/book/manage#" + p.booking_id + "." + manage;
    const sealed = await payment("checkout_wire", id, {
      wire: cipher.seal(checkoutWire(p, url), "checkout:" + id),
    });
    const verified = await adapters.stripe.checkout(
      p,
      cipher.open(sealed, "checkout:" + id),
    );
    await payment("checkout_saved", id, verified);
  }
  async function reconcile(id) {
    if (!paymentsConfigured) return;
    const p = await payment("private", id);
    checkConfig(p.connection);
    if (p.payment_state !== "unpaid") return;
    if (!p.checkout_id) {
      if (Date.parse(p.booking.hold_expires_at) <= now())
        await payment("observe", id, {
          account_id: p.account_id,
          checkout_id: null,
          livemode: p.livemode,
          amount_cents: p.amount_cents,
          currency: p.currency,
          paid: false,
          expired: true,
        });
      return;
    }
    const verified = await adapters.stripe.retrieve(p);
    let checked = !verified.paid;
    if (
      verified.paid &&
      p.booking.state === "awaiting_payment" &&
      Date.parse(p.booking.hold_expires_at) > now()
    ) {
      try {
        await checkAvailability(p.booking.owner_id, null, {
          booking_id: id,
          starts_at: p.booking.starts_at,
        });
        checked = true;
      } catch {}
    }
    await payment("observe", id, { ...verified, calendars_checked: checked });
  }
  async function reconcilePublic(data) {
    const b = await publicCall("manage", null, data);
    if (b.payment && b.payment.state === "unpaid") {
      try {
        await reconcile(b.id);
      } catch {
        /* Return known state; no redirect is proof of payment. */
      }
    }
    return publicCall("manage", null, data);
  }
  app.post(
    base + "/manage/checkout",
    route(async (q, r) => {
      const data = {
        booking_id: uuid(q.body.booking_id),
        manage_hash: hash(token(q.body.manage_token)),
      };
      const b = await publicCall("manage", null, data);
      if (q.body.confirmed !== true || b.state !== "awaiting_payment")
        fail("Review this booking before opening checkout.");
      await ensureCheckout(b.id);
      r.json({ booking: await publicCall("manage", null, data) });
    }),
  );
  app.post(
    base + "/bookings/:id/refund",
    route(
      async (q, r, u) =>
        r.json({
          booking: await payment("refund_request", uuid(q.params.id), {
            actor: u.id,
            confirmed: q.body.confirmed === true,
            revision: integer(q.body.revision, 1, 1e9),
          }),
        }),
      true,
    ),
  );
  // Signature authentication replaces browser-origin authentication on Stripe callbacks.
  app.post(base + "/payments/webhook", async (q, r) => {
    r.set("Cache-Control", "no-store");
    if (
      !paymentsConfigured ||
      !stripeSignature(
        q.korlixSchedulingRawBody,
        q.get("stripe-signature"),
        providers.stripe.webhook,
        now(),
      )
    )
      return r.status(400).json({ error: "Invalid payment signature." });
    try {
      const e = JSON.parse(q.korlixSchedulingRawBody.toString("utf8"));
      if (
        !/^evt_[A-Za-z0-9]+$/.test(e.id) ||
        !/^acct_[A-Za-z0-9]+$/.test(e.account) ||
        e.livemode !== adapters.stripe.livemode
      )
        return r
          .status(400)
          .json({ error: "Invalid connected-account event." });
      if (
        [
          "checkout.session.completed",
          "checkout.session.expired",
          "checkout.session.async_payment_succeeded",
          "checkout.session.async_payment_failed",
        ].includes(e.type)
      ) {
        const found = await payment("lookup", null, {
          account_id: e.account,
          checkout_id: e.data?.object?.id,
        });
        if (found) await reconcile(found.booking_id);
        else if (e.data?.object?.metadata?.korlix_booking) {
          // Recover a lost creation response using a signed event plus an independent Stripe read.
          const id = uuid(e.data.object.metadata.korlix_booking),
            p = await payment("private", id);
          checkConfig(p.connection);
          if (p.account_id !== e.account)
            throw new ProviderError("Payment account mismatch.", 409);
          const verified = await adapters.stripe.retrieve({
            ...p,
            checkout_id: e.data.object.id,
          });
          await payment("checkout_saved", id, verified);
          await reconcile(id);
        }
      } else if (e.type === "charge.refunded") {
        const v = await adapters.stripe.chargeRefund(e),
          found = await payment("lookup", null, v);
        if (found) {
          const p = await payment("private", found.booking_id);
          if (
            v.currency === p.currency &&
            v.livemode === p.livemode &&
            v.refunded_cents === p.amount_cents
          )
            await payment("refund_observed", found.booking_id, v);
        }
      }
      await payment("event_received", null, {
        event_id: e.id,
        account_id: e.account,
        kind: e.type,
      });
      r.json({ received: true });
    } catch {
      r.status(503).json({
        error: "Payment verification is pending. Retry shortly.",
      });
    }
  });
  let working = false,
    timer;
  async function tick() {
    if (working) return;
    working = true;
    try {
      if (capabilities.calendar_sync)
        for (let n = 0; n < 6; n++) {
          const job = await queue("claim");
          if (!job) break;
          let created = job.provider_event_id;
          try {
            await withCalendar(
              job.connection_id,
              async (c, grant, provider) => {
                const prepared = await queue("prepare", job, {
                  wire: calendarWire(c.provider, job),
                });
                if (!prepared) return;
                const result = await provider.write(
                  grant,
                  { ...job, ...prepared },
                  async (eventId) => {
                    created = eventId;
                    await queue("created", job, { event_id: eventId });
                  },
                );
                await queue("finish", job, {
                  state: "synced",
                  revision: prepared.booking.revision,
                  event_id: result.event_id,
                  deleted: result.deleted === true,
                });
              },
            );
          } catch {
            await queue("finish", job, {
              state: "pending",
              event_id: created,
            }).catch(() => {});
          }
        }
      if (paymentsConfigured)
        for (const due of await payment("due")) {
          try {
            await reconcile(due.booking_id);
            const p = await payment("refund_claim", due.booking_id);
            if (p) {
              checkConfig(p.connection);
              try {
                const result = await adapters.stripe.refund(p);
                await payment("refund_finish", due.booking_id, {
                  ...result,
                  lease_id: p.lease_id,
                });
              } catch {
                await payment("refund_finish", due.booking_id, {
                  lease_id: p.lease_id,
                  state: "pending",
                });
              }
            }
          } catch {
            /* Durable ledger retries without logging customer data. */
          }
        }
    } catch {
      console.warn("[Scheduling] Connected-service worker will retry.");
    } finally {
      working = false;
    }
  }
  if (autoStart && (capabilities.calendar_sync || paymentsConfigured)) {
    timer = setInterval(() => {
      void tick();
    }, 30000);
    timer.unref?.();
  }
  if (autoStart)
    console.info(
      `[Scheduling] Provider setup: google=${providers.google.ready}; microsoft=${providers.microsoft.ready}; stripe=${paymentsConfigured}; checkout=${paymentsReady}.`,
    );
  // Optional, read-only sandbox diagnostic. Never sends a payment request,
  // modifies a connection, or runs with a live key or enabled checkout.
  const probeAccount = environment.KORLIX_SCHEDULING_STRIPE_PROBE_ACCOUNT;
  if (autoStart && paymentsConfigured && !providers.stripe.enabled &&
      /^(sk|rk)_test_/.test(providers.stripe.key) &&
      /^acct_[A-Za-z0-9]+$/.test(probeAccount || "")) {
    void adapters.stripe.identity({ account_id: probeAccount, livemode: false })
      .then((identity) => console.info("[Scheduling Stripe] " + JSON.stringify({
        stage: "sandbox_readiness_probe", verified: true,
        cardPayments: identity.card_payments_status,
        payouts: identity.payouts_status,
      })))
      .catch(() => console.warn("[Scheduling Stripe] " + JSON.stringify({
        stage: "sandbox_readiness_probe", verified: false,
      })));
  }
  return {
    capabilities,
    paymentsReady,
    paymentsConfigured,
    checkAvailability,
    refresh,
    dashboard,
    reconcilePublic,
    ensureCheckout,
    reconcile,
    tick,
    stop: () => clearInterval(timer),
    withCalendar,
    providers,
  };
}
