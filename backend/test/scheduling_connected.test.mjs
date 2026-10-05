import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { randomUUID, createHmac } from "node:crypto";
import { PGlite } from "@electric-sql/pglite";
import express from "express";
import { registerScheduling } from "../scheduling/routes.mjs";
import { event, hash, secret, calendarFile } from "../scheduling/core.mjs";
import {
  providerCipher,
  providerSettings,
} from "../scheduling/provider_core.mjs";
import {
  calendarProvider,
  calendarWire,
} from "../scheduling/calendar_provider.mjs";
import {
  stripeSignature,
  stripeProvider,
  checkoutWire,
} from "../scheduling/stripe_provider.mjs";
import {
  normalizeSchedulingPlan,
  generateSchedulingAI,
} from "../scheduling/ai.mjs";
let db,
  server,
  base,
  service,
  host,
  other,
  third,
  modelCalls = 0,
  modelResult;
const env = {
  NODE_ENV: "test",
  KORLIX_SCHEDULING_TOKEN_KEY: Buffer.alloc(32, 9).toString("base64"),
  KORLIX_SCHEDULING_PUBLIC_URL: "https://example.test",
  KORLIX_SCHEDULING_GOOGLE_CLIENT_ID: "fixture-google",
  KORLIX_SCHEDULING_GOOGLE_CLIENT_SECRET: "fixture-secret",
  KORLIX_SCHEDULING_MICROSOFT_CLIENT_ID: "fixture-microsoft",
  KORLIX_SCHEDULING_MICROSOFT_CLIENT_SECRET: "fixture-secret",
  KORLIX_SCHEDULING_STRIPE_CLIENT_ID: "ca_fixture",
  KORLIX_SCHEDULING_STRIPE_SECRET_KEY: "sk_test_fixture",
  KORLIX_SCHEDULING_STRIPE_WEBHOOK_SECRET: "whsec_fixture",
  KORLIX_SCHEDULING_STRIPE_ENABLED: "true",
};
const settings = providerSettings(env, env.KORLIX_SCHEDULING_PUBLIC_URL),
  cipher = providerCipher(env);
const day = (n = 10) =>
  new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);
const time = (n = 10, h = 10) =>
  day(n) + `T${String(h).padStart(2, "0")}:00:00.000Z`;
const weekly = Array.from({ length: 7 }, (_, day) => ({
  day,
  windows: [[540, 1020]],
}));
const draft = (changes = {}) =>
  event({
    revision: 0,
    title: "Connected appointment",
    description: "Fixture only",
    kind: "one_to_one",
    duration_minutes: 30,
    interval_minutes: 30,
    buffer_before: 0,
    buffer_after: 0,
    notice_minutes: 0,
    horizon_days: 365,
    daily_limit: 40,
    capacity: 1,
    cancel_notice_minutes: 0,
    location_kind: "video",
    location_detail: "https://example.test/meeting",
    questions: [],
    color: "#72D6EB",
    ...changes,
  });
const rpc = async (name, args) =>
  (
    await db.query(
      `select ${name}(${Object.keys(args)
        .map((k, i) => k + "=> $" + (i + 1))
        .join(",")}) value`,
      Object.values(args),
    )
  ).rows[0].value;
const owner = (u, a, id = null, d = {}) =>
  rpc("korlix_schedule_owner_v1", {
    p_actor: u,
    p_action: a,
    p_id: id,
    p_data: d,
  });
const team = (u, a, id = null, d = {}) =>
  rpc("korlix_schedule_team_v2", {
    p_actor: u,
    p_action: a,
    p_id: id,
    p_data: d,
  });
const conn = (u, a, id = null, d = {}) =>
  rpc("korlix_schedule_connections_v2", {
    p_actor: u,
    p_action: a,
    p_id: id,
    p_data: d,
  });
const pub = (a, slug = null, d = {}) =>
  rpc("korlix_schedule_public_v1", { p_action: a, p_slug: slug, p_data: d });
const pay = (a, id = null, d = {}) =>
  rpc("korlix_schedule_payment_v2", { p_action: a, p_id: id, p_data: d });
async function user() {
  const id = randomUUID();
  await db.query("insert into auth.users values($1,now(),false)", [id]);
  await db.query("insert into user_profiles values($1,'basic',false)", [id]);
  await owner(id, "save_profile", null, {
    revision: 0,
    display_name: "Host " + id.slice(0, 4),
    timezone: "UTC",
    weekly,
    overrides: [],
  });
  return id;
}
async function create(u = host, changes = {}) {
  const e = await owner(u, "save_event", null, {
    ...draft(changes),
    slug: "test-" + secret().slice(0, 20),
  });
  return owner(u, "event_state", e.id, {
    revision: e.revision,
    state: "published",
    confirmed: true,
  });
}
async function context(e) {
  const c = { token_hash: hash(secret()), browser_hash: hash(secret()) };
  await pub("context", e.slug, c);
  return c;
}
async function book(e, start, extra = {}) {
  const raw = secret(),
    c = await context(e),
    body = {
      ...c,
      request_id: randomUUID(),
      request_hash: hash(secret()),
      manage_hash: hash(raw),
      sealed_manage_token: service.notifications.seal(
        raw,
        extra.request_id || "unused",
      ),
      starts_at: start,
      guest_name: "Fixture guest",
      guest_email: randomUUID() + "@example.test",
      guest_timezone: "UTC",
      answers: {},
      confirmed: true,
      ...extra,
    };
  body.sealed_manage_token = service.notifications.seal(raw, body.request_id);
  return { b: await pub("book", e.slug, body), body, raw };
}
async function connection(u = host, provider = "google", more = {}) {
  const remote =
    provider === "stripe"
      ? "acct_" + secret().slice(0, 15)
      : secret().slice(0, 16);
  const c = { owner_id: u, provider, remote_id: remote };
  const grant =
    provider === "stripe"
      ? { account_id: remote, livemode: false }
      : {
          access_token: "fixture-access",
          refresh_token: "fixture-refresh",
          expires_at: new Date(Date.now() + 86400000).toISOString(),
          scope:
            "openid email https://www.googleapis.com/auth/calendar.calendarlist.readonly https://www.googleapis.com/auth/calendar.events",
        };
  const r = await db.query(
    `insert into korlix_schedule_connections(owner_id,provider,remote_id,label,sealed_grant,config_hash,enabled,charges_enabled,livemode,calendars,busy_ids,write_id)values($1,$2,$3,'Fixture account',$4,$5,$6,$7,false,$8,$9,$10)returning *`,
    [
      u,
      provider,
      remote,
      cipher.seal(grant, `${u}:${provider}:${remote}`),
      settings.providers[provider].fingerprint,
      more.enabled ?? false,
      provider === "stripe",
      [{ id: "primary", name: "Primary", timezone: "UTC", writable: true }],
      more.busy_ids ?? [],
      more.write_id ?? null,
    ],
  );
  return r.rows[0];
}
async function cache(c, from, to, busy = []) {
  await db.query(
    "insert into korlix_schedule_calendar_windows(connection_id,revision,starts_at,ends_at,busy)values($1,$2,$3,$4,$5)",
    [c.id, c.revision, from, to, busy],
  );
}
async function http(path, body, u = host, expected = 200, headers = {}) {
  const r = await fetch(base + "/api/scheduling" + path, {
    method: body ? "POST" : "GET",
    headers: {
      "content-type": "application/json",
      authorization: u || "",
      ...headers,
    },
    redirect: "manual",
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const raw = await r.text();
  assert.equal(r.status, expected, raw);
  return {
    data: r.headers.get("content-type")?.includes("json")
      ? JSON.parse(raw)
      : raw,
    headers: r.headers,
  };
}
const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
let fetchCalls = [],
  sessions = new Map(),
  calendarEvents = [],
  refundCalls = 0;
async function fixtureFetch(url, options = {}) {
  const u = new URL(url);
  fetchCalls.push({
    url: u.href,
    method: options.method || "GET",
    body: options.body,
    headers: options.headers,
  });
  if (u.hostname === "connect.stripe.com" && u.pathname === "/oauth/token")
    return json({ stripe_user_id: "acct_oauthlegacy", scope: "read_write", livemode: false });
  if (u.pathname === "/v2/core/accounts/acct_oauthlegacy")
    return json({ error: { code: "v1_account_instead_of_v2_account" } }, 400);
  if (u.pathname === "/v1/accounts/acct_oauthlegacy")
    return json({ id: "acct_oauthlegacy", object: "account", business_profile: { name: "Legacy fixture" },
      controller: { stripe_dashboard: { type: "full" }, fees: { payer: "account" },
        losses: { payments: "stripe" }, requirement_collection: "stripe" },
      charges_enabled: true, payouts_enabled: true });
  if (u.hostname === "api.stripe.com" && u.pathname.startsWith("/v2/core/accounts/"))
    return json({
      id: u.pathname.split("/").at(-1), object: "v2.core.account", livemode: false,
      dashboard: "full", display_name: "Fixture business",
      defaults: {responsibilities: {fees_collector: "stripe", losses_collector: "stripe"}},
      configuration: {merchant: {capabilities: {
        card_payments: {status: "active"}, stripe_balance: {payouts: {status: "active"}},
      }}},
    });
  if (u.hostname === "oauth2.googleapis.com")
    return json({
      access_token: "fixture-access",
      refresh_token: "fixture-refresh",
      expires_in: 3600,
      token_type: "Bearer",
      scope:
        "openid email https://www.googleapis.com/auth/calendar.calendarlist.readonly https://www.googleapis.com/auth/calendar.events",
    });
  if (u.hostname === "openidconnect.googleapis.com")
    return json({
      sub: "google-fixture-user",
      email: "host@example.test",
      email_verified: true,
    });
  if (u.pathname.endsWith("/calendarList"))
    return json({
      items: [
        {
          id: "primary",
          summary: "Fixture calendar",
          timeZone: "UTC",
          accessRole: "owner",
          primary: true,
        },
      ],
    });
  if (
    u.hostname === "www.googleapis.com" &&
    u.pathname.endsWith("/events") &&
    (options.method || "GET") === "GET"
  )
    return json({ items: calendarEvents });
  if (
    u.hostname === "www.googleapis.com" &&
    u.pathname.endsWith("/events") &&
    options.method === "POST"
  )
    return json({ ...JSON.parse(options.body) });
  if (u.hostname === "www.googleapis.com" && options.method === "DELETE")
    return new Response(null, { status: 204 });
  if (u.hostname === "www.googleapis.com" && options.method === "PATCH")
    return json({ id: u.pathname.split("/").at(-1) });
  if (
    u.hostname === "api.stripe.com" &&
    u.pathname === "/v1/checkout/sessions" &&
    options.method === "POST"
  ) {
    const p = new URLSearchParams(options.body),
      booking = p.get("client_reference_id"),
      sid = "cs_test_" + booking.replaceAll("-", "");
    const existing = sessions.get(sid);
    const data = existing || {
      id: sid,
      client_reference_id: booking,
      metadata: { korlix_booking: booking },
      livemode: false,
      currency: "usd",
      amount_total: Number(p.get("line_items[0][price_data][unit_amount]")),
      mode: "payment",
      status: "open",
      payment_status: "unpaid",
      url: "https://checkout.stripe.com/c/pay/" + sid,
    };
    sessions.set(sid, data);
    return json(data);
  }
  if (
    u.hostname === "api.stripe.com" &&
    u.pathname.startsWith("/v1/checkout/sessions/")
  )
    return json(sessions.get(u.pathname.split("/").at(-1)));
  if (u.hostname === "api.stripe.com" && u.pathname === "/v1/refunds") {
    refundCalls++;
    const p = new URLSearchParams(options.body);
    return json({
      id: "re_fixture",
      payment_intent: p.get("payment_intent"),
      amount: Number(p.get("amount")),
      currency: "usd",
      status: "succeeded",
    });
  }
  throw Error("Unexpected fixture provider call " + u.href);
}
test.before(async () => {
  db = new PGlite();
  await db.exec(
    "create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,is_anonymous boolean);create table user_profiles(id uuid primary key,tier text,is_disabled boolean);grant usage on schema public,auth to service_role,anon,authenticated;grant select,insert,update on user_profiles,auth.users to service_role;",
  );
  for (const file of [
    "20260930152919_scheduling_engine.sql",
    "20260930163605_scheduling_connected.sql",
  ])
    await db.exec(
      await readFile(
        new URL("../../supabase/migrations/" + file, import.meta.url),
        "utf8",
      ),
    );
  await db.exec("set role service_role");
  host = await user();
  other = await user();
  third = await user();
  const app = express();
  app.use(
    express.json({
      verify: (q, r, b) => {
        q.korlixSchedulingRawBody = Buffer.from(b);
      },
    }),
  );
  service = registerScheduling(app, {
    database: {
      rpc: async (n, p) => {
        try {
          return { data: await rpc(n, p) };
        } catch (error) {
          return { error };
        }
      },
    },
    requireUser: async (q) =>
      [host, other, third].includes(q.headers.authorization)
        ? {
            id: q.headers.authorization,
            email: "host@example.test",
            email_confirmed_at: "2026-01-01",
            is_anonymous: false,
          }
        : null,
    environment: env,
    autoStartWorker: false,
    fetcher: fixtureFetch,
    generateAI: async () => {
      modelCalls++;
      return modelResult;
    },
  });
  server = app.listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  base = "http://127.0.0.1:" + server.address().port;
});
test.after(async () => {
  service?.connected.stop();
  service?.notifications.stop();
  server?.closeAllConnections();
  if (server) await new Promise((r) => server.close(r));
  await db?.close();
});
test("provider ciphertext is identity-bound and never accepts a changed owner or tampered grant", () => {
  const sealed = cipher.seal(
    { access_token: "private" },
    "owner:google:account",
  );
  assert.equal(
    cipher.open(sealed, "owner:google:account").access_token,
    "private",
  );
  assert.throws(() => cipher.open(sealed, "other:google:account"));
  assert.throws(() =>
    cipher.open(sealed.slice(0, -4) + "aaaa", "owner:google:account"),
  );
});
test("advanced database tables and functions are unavailable to browser roles", async () => {
  const rows = (
    await db.query(
      "select c.relname,c.relrowsecurity,has_table_privilege('anon',c.oid,'select') as a,has_table_privilege('authenticated',c.oid,'update') as b from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'korlix_schedule_%' and c.relkind='r'",
    )
  ).rows;
  assert(rows.length >= 16);
  for (const r of rows) {
    assert(r.relrowsecurity, r.relname);
    assert(!r.a && !r.b, r.relname);
  }
  const f = (
    await db.query(
      "select proname from pg_proc where proname like 'korlix_schedule_%_v2' and (prosecdef or has_function_privilege('anon',oid,'execute') or has_function_privilege('authenticated',oid,'execute'))",
    )
  ).rows;
  assert.deepEqual(f, []);
});
test("OAuth requires signed-in start, one-use handoff, same-browser state, and owner confirmation", async () => {
  await http("/connections/google/start", { confirmed: true }, null, 401);
  const { data: a } = await http("/connections/google/start", {
    confirmed: true,
  });
  const launch = new URL(a.url);
  const r = await http(
    launch.pathname.replace("/api/scheduling", "") + launch.search,
    null,
    null,
    303,
  );
  const browser = r.headers.get("set-cookie").split(";")[0],
    auth = new URL(r.headers.get("location"));
  assert(auth.searchParams.get("code_challenge"));
  assert.equal(auth.searchParams.get("code_challenge_method"), "S256");
  await http(
    launch.pathname.replace("/api/scheduling", "") + launch.search,
    null,
    null,
    400,
  );
  const cb =
    "/connect/google/callback?state=" +
    auth.searchParams.get("state") +
    "&code=fixture";
  await http(cb, null, null, 409);
  await http(cb, null, null, 200, { cookie: browser });
  await http(cb, null, null, 400, { cookie: browser });
  await http(
    "/connections/attempts/" + a.id + "/confirm",
    { confirmed: true },
    other,
    400,
  );
  await http(
    "/connections/attempts/" + a.id + "/confirm",
    { confirmed: false },
    host,
    400,
  );
  await http("/connections/attempts/" + a.id + "/confirm", { confirmed: true });
  const listing = (await http("/connections")).data;
  assert(
    listing.connections.some((c) => c.remote_id === "google-fixture-user"),
  );
  assert(!JSON.stringify(listing).includes("sealed_grant"));
  const c = listing.connections.find(
    (c) => c.remote_id === "google-fixture-user",
  );
  await http("/connections/" + c.id + "/calendars", {});
  await http(
    "/connections/" + c.id + "/settings",
    {
      confirmed: true,
      revision: c.revision,
      busy_ids: ["unknown"],
      write_id: null,
    },
    host,
    400,
  );
  await http("/connections/" + c.id + "/disconnect", { confirmed: true });
});
test("Stripe OAuth completes and requires owner confirmation while v2 compatibility is pending", async () => {
  const { data: attempt } = await http("/connections/stripe/start", { confirmed: true }, other);
  const launch = new URL(attempt.url);
  const started = await http(launch.pathname.replace("/api/scheduling", "") + launch.search, null, null, 303);
  const browser = started.headers.get("set-cookie").split(";")[0];
  const authorization = new URL(started.headers.get("location"));
  const callback = "/connect/stripe/callback?state=" + authorization.searchParams.get("state") + "&code=fixture-legacy";
  const result = await http(callback, null, null, 200, { cookie: browser });
  assert(result.data.includes("Account verified"));
  await http("/connections/attempts/" + attempt.id + "/confirm", { confirmed: true }, host, 400);
  await http("/connections/attempts/" + attempt.id + "/confirm", { confirmed: true }, other);
  const listing = (await http("/connections", null, other)).data;
  const connected = listing.connections.find((c) => c.remote_id === "acct_oauthlegacy");
  assert.equal(connected.state, "connected");
  assert.equal(connected.charges_enabled, false);
  assert.equal(connected.livemode, false);
  assert(!JSON.stringify(listing).includes("sealed_grant"));
  await http("/connections/" + connected.id + "/disconnect", { confirmed: true }, other);
});

test("calendar providers fail closed on incomplete pagination, bad times, and empty access tokens", async () => {
  const g = calendarProvider(settings.providers.google, {
    fetcher: async () => json({ items: [], nextPageToken: "repeat" }),
  });
  await assert.rejects(g.calendars({ access_token: "x" }), /completed/);
  const m = calendarProvider(settings.providers.microsoft, {
    fetcher: async () =>
      json({ value: [], "@odata.nextLink": "https://evil.example/me" }),
  });
  await assert.rejects(
    m.calendars({ access_token: "x" }),
    /invalid continuation/,
  );
  const bad = calendarProvider(settings.providers.google, {
    fetcher: async () =>
      json({ access_token: "", expires_in: 3600, token_type: "Bearer" }),
  });
  await assert.rejects(bad.exchange("x", "y"), /valid authorization/);
  const ms = calendarProvider(settings.providers.microsoft, {
    fetcher: async () =>
      json({
        value: [
          {
            id: "busy",
            showAs: "busy",
            start: { dateTime: time(5), timeZone: "UTC" },
            end: { dateTime: time(5, 11), timeZone: "UTC" },
          },
        ],
      }),
  });
  const busy = await ms.busy(
    { access_token: "x" },
    [{ id: "primary" }],
    time(5),
    time(6),
  );
  assert.equal(busy[0].starts_at, time(5));
});
test("enabled calendars need a fresh complete cache and busy events block the final booking", async () => {
  const u = await user(),
    e = await create(u),
    c = await connection(u, "google", { enabled: true, busy_ids: ["primary"] });
  const ctx = await context(e);
  assert.equal(
    (await pub("slots", e.slug, { ...ctx, date: day(15) })).slots.length,
    0,
  );
  await cache(c, time(15, 0), time(16, 0), [
    {
      calendar_id: "primary",
      remote_id: "busy",
      starts_at: time(15, 10),
      ends_at: time(15, 11),
    },
  ]);
  const slots = (await pub("slots", e.slug, { ...ctx, date: day(15) })).slots;
  assert(
    slots.some((s) => Date.parse(s.starts_at) === Date.parse(time(15, 12))),
  );
  assert(
    !slots.some((s) => Date.parse(s.starts_at) === Date.parse(time(15, 10))),
  );
  await assert.rejects(book(e, time(15, 10)), /no longer available/);
  await db.query(
    "update korlix_schedule_calendar_windows set checked_at=now()-interval '61 seconds' where connection_id=$1",
    [c.id],
  );
  await assert.rejects(book(e, time(15, 12)), /no longer available/);
});
test("only exact linked KORLIX mirrors are ignored; changed external events still block", async () => {
  const u = await user(),
    e = await create(u),
    c = await connection(u, "google", {
      enabled: true,
      busy_ids: ["primary"],
      write_id: "primary",
    });
  await cache(c, time(16, 0), time(17, 0));
  const { b } = await book(e, time(16));
  await db.query(
    "update korlix_schedule_calendar_links set provider_event_id='mirror' where booking_id=$1",
    [b.id],
  );
  await cache(c, time(16, 0), time(17, 0), [
    {
      calendar_id: "primary",
      remote_id: "mirror",
      starts_at: b.starts_at,
      ends_at: b.ends_at,
    },
  ]);
  assert.equal(
    (
      await db.query(
        "select korlix_schedule_calendar_available_v2($1,$2,$3) v",
        [u, b.starts_at, b.ends_at],
      )
    ).rows[0].v,
    true,
  );
  await cache(c, time(16, 0), time(17, 0), [
    {
      calendar_id: "primary",
      remote_id: "mirror",
      starts_at: b.starts_at,
      ends_at: time(16, 11),
    },
  ]);
  assert.equal(
    (
      await db.query(
        "select korlix_schedule_calendar_available_v2($1,$2,$3) v",
        [u, b.starts_at, b.ends_at],
      )
    ).rows[0].v,
    false,
  );
});
test("all-day events use calendar timezone and workers write no attendees or private management links", async () => {
  const u = await user(),
    c = await connection(u, "google", { enabled: true, busy_ids: ["primary"] });
  await cache(c, time(17, 0), time(19, 0), [
    {
      calendar_id: "primary",
      remote_id: "all-day",
      start_date: day(18),
      end_date: day(19),
      timezone: "America/New_York",
    },
  ]);
  assert.equal(
    (
      await db.query(
        "select korlix_schedule_calendar_available_v2($1,$2,$3) v",
        [u, time(18, 5), time(18, 6)],
      )
    ).rows[0].v,
    false,
  );
  for (const provider of ["google", "microsoft"]) {
    const wire = calendarWire(provider, {
      id: randomUUID(),
      booking: {
        id: randomUUID(),
        snapshot: {
          title: "Hello",
          location_detail: "https://example.test/meeting",
        },
        guest_name: "Fixture",
        guest_email: "fixture@example.test",
        starts_at: time(18),
        ends_at: time(18, 11),
      },
    });
    assert(!wire.attendees);
    assert(!JSON.stringify(wire).includes("/book/manage#"));
    assert(!JSON.stringify(wire).includes("sealed"));
  }
});
test("team invitations require consent; round-robin allocates hosts and blocks their other event types", async () => {
  const a = await user(),
    b = await user();
  const t = await team(a, "create", null, { name: "Fixture team" }),
    invite = hash(secret());
  await team(a, "invite", t.id, {
    confirmed: true,
    revision: t.revision,
    invite_hash: invite,
  });
  await assert.rejects(
    team(b, "join", null, { invite_hash: invite }),
    /confirm/,
  );
  await team(b, "join", null, { invite_hash: invite, confirmed: true });
  const e = await create(a, {
    routing_mode: "round_robin",
    team_id: t.id,
    host_ids: [a, b],
  });
  const one = await book(e, time(20));
  const two = await book(e, time(20));
  const rows = (
    await db.query(
      "select booking_id,host_id from korlix_schedule_booking_hosts where booking_id=any($1::uuid[])",
      [[one.b.id, two.b.id]],
    )
  ).rows;
  assert.equal(new Set(rows.map((r) => r.host_id)).size, 2);
  await assert.rejects(book(e, time(20)), /no longer available/);
  const personal = await create(b);
  await assert.rejects(book(personal, time(20)), /no longer available/);
  await assert.rejects(
    team(b, "invite", t.id, {
      confirmed: true,
      revision: 1,
      invite_hash: hash(secret()),
    }),
    /unavailable/,
  );
  await team(b, "leave", t.id, { confirmed: true });
  assert.equal(
    (await team(a, "list"))[0].members.find((m) => m.user_id === b).active,
    false,
  );
  assert((await owner(b, "dashboard")).bookings.length > 0);
});
test("collective appointments reserve every host, enforce shared availability, and reject cross-owner teams", async () => {
  const a = await user(),
    b = await user();
  const t = await team(a, "create", null, { name: "Panel" }),
    invite = hash(secret());
  await team(a, "invite", t.id, {
    confirmed: true,
    revision: 1,
    invite_hash: invite,
  });
  await team(b, "join", null, { confirmed: true, invite_hash: invite });
  await assert.rejects(
    create(b, { routing_mode: "collective", team_id: t.id, host_ids: [a, b] }),
    /own team/,
  );
  const e = await create(a, {
    routing_mode: "collective",
    team_id: t.id,
    host_ids: [a, b],
  });
  await owner(b, "add_block", null, {
    starts_at: time(21),
    ends_at: time(21, 11),
    label: "Unavailable",
  });
  await assert.rejects(book(e, time(21)), /no longer available/);
  const { b: booking } = await book(e, time(21, 12));
  assert.equal(
    (
      await db.query(
        "select count(*) n from korlix_schedule_booking_hosts where booking_id=$1",
        [booking.id],
      )
    ).rows[0].n,
    2,
  );
  await team(b, "leave", t.id, { confirmed: true });
  await assert.rejects(book(e, time(22)), /no longer available/);
});
async function paidFixture(n) {
  const u = await user(),
    c = await connection(u, "stripe", { enabled: true }),
    e = await create(u, {
      price_cents: 2500,
      refund_policy: "Full refund on request.",
    }),
    result = await book(e, time(n), { payments_ready: true });
  return { u, c, e, ...result };
}
test("payment holds reserve capacity, hide meeting links, and wait for provider verification", async () => {
  const { b, raw, e } = await paidFixture(25);
  assert.equal(b.state, "awaiting_payment");
  assert.equal(b.snapshot.location_detail, undefined);
  assert.throws(() => calendarFile(b), /confirmed appointment/);
  await assert.rejects(
    book(e, time(25), { payments_ready: true }),
    /no longer available/,
  );
  const before = fetchCalls.length;
  await http(
    "/manage/checkout",
    { booking_id: b.id, manage_token: raw, confirmed: false },
    null,
    400,
  );
  assert.equal(fetchCalls.length, before);
  await http(
    "/manage/checkout",
    { booking_id: b.id, manage_token: raw, confirmed: true },
    null,
  );
  const p = await pay("private", b.id);
  assert(p.checkout_id);
  assert.equal(
    (await pub("manage", null, { booking_id: b.id, manage_hash: hash(raw) }))
      .state,
    "awaiting_payment",
  );
  const calls = fetchCalls.filter((c) => c.url.endsWith("/checkout/sessions"));
  assert.equal(calls.at(-1).headers["Stripe-Account"], p.account_id);
  const wire = new URLSearchParams(calls.at(-1).body);
  assert(!wire.has("application_fee_amount"));
  assert(!wire.has("payment_intent_data[application_fee_amount]"));
  assert(![...wire.keys()].some(k => k.startsWith("payment_method_types")));
  assert.equal(wire.get("integration_identifier"), "korlix_2meetu_dzwqhxnr");
  assert(wire.get("success_url").includes("#" + b.id + "." + raw));
  const session = sessions.get(p.checkout_id);
  session.payment_status = "paid";
  session.status = "complete";
  session.payment_intent = "pi_paidfixture";
  await service.connected.reconcile(b.id);
  const confirmed = await pub("manage", null, {
    booking_id: b.id,
    manage_hash: hash(raw),
  });
  assert.equal(confirmed.state, "confirmed");
  assert.equal(confirmed.payment.state, "paid");
  assert.equal(
    confirmed.snapshot.location_detail,
    "https://example.test/meeting",
  );
});
test("payment verification rejects a wrong account, currency, amount, or mode; hold expiry frees the slot", async () => {
  const { b, e } = await paidFixture(26);
  const p = await pay("private", b.id);
  const valid = {
    account_id: p.account_id,
    checkout_id: null,
    livemode: false,
    amount_cents: 2500,
    currency: "usd",
    paid: true,
    payment_intent_id: "pi_fixture",
    calendars_checked: true,
  };
  for (const wrong of [
    { account_id: "acct_other" },
    { amount_cents: 2499 },
    { currency: "cad" },
    { livemode: true },
  ])
    await assert.rejects(
      pay("observe", b.id, { ...valid, ...wrong }),
      /did not match/,
    );
  await db.query(
    "update korlix_schedule_bookings set hold_expires_at=now()-interval '1 second' where id=$1",
    [b.id],
  );
  await book(e, time(26), { payments_ready: true });
  await pay("observe", b.id, valid);
  const failed = await pay("private", b.id);
  assert.equal(failed.booking.state, "payment_failed");
  assert.equal(failed.payment_state, "paid_unfulfilled");
  assert.equal(failed.refund_state, "required");
});
test("approved full refunds are organizer-only, idempotent, and provider-confirmed", async () => {
  const { b, u } = await paidFixture(27);
  await service.connected.ensureCheckout(b.id);
  let p = await pay("private", b.id);
  Object.assign(sessions.get(p.checkout_id), {
    payment_status: "paid",
    status: "complete",
    payment_intent: "pi_refundfixture",
  });
  await service.connected.reconcile(b.id);
  p = await pay("private", b.id);
  await assert.rejects(
    pay("refund_request", b.id, {
      actor: other,
      revision: p.booking.revision,
      confirmed: true,
    }),
    /Only the booking organizer/,
  );
  await assert.rejects(
    pay("refund_request", b.id, {
      actor: u,
      revision: p.booking.revision,
      confirmed: false,
    }),
    /Review/,
  );
  await pay("refund_request", b.id, {
    actor: u,
    revision: p.booking.revision,
    confirmed: true,
  });
  const job = await pay("refund_claim", b.id);
  assert.equal(await pay("refund_claim", b.id), null);
  const verified = await stripeProvider(settings.providers.stripe, {
    fetcher: fixtureFetch,
  }).refund(job);
  await pay("refund_finish", b.id, { ...verified, lease_id: job.lease_id });
  p = await pay("private", b.id);
  assert.equal(p.payment_state, "refunded");
  assert.equal(p.booking.state, "canceled");
  assert.equal(await pay("refund_claim", b.id), null);
  assert(refundCalls > 0);
});
test("Stripe signatures authenticate exact raw bytes and enforce replay time tolerance", () => {
  const raw = Buffer.from('{"id":"evt_fixture"}'),
    t = Math.floor(Date.now() / 1000),
    signature = createHmac("sha256", "key")
      .update(t + ".")
      .update(raw)
      .digest("hex");
  assert(stripeSignature(raw, `t=${t},v1=${signature}`, "key"));
  assert(
    !stripeSignature(
      Buffer.from('{ "id":"evt_fixture"}'),
      `t=${t},v1=${signature}`,
      "key",
    ),
  );
  assert(
    !stripeSignature(raw, `t=${t},v1=${signature}`, "key", Date.now() + 301000),
  );
  assert(!stripeSignature(raw, `t=${t},t=${t},v1=${signature}`, "key"));
});
test("pausing blocks paid bookings and checkout but preserves free bookings, signed confirmations and refunds", async () => {
  const open = await paidFixture(40);
  const unstarted = await paidFixture(41);
  await service.connected.ensureCheckout(open.b.id);
  const p = await pay("private", open.b.id);
  const app = express();
  app.use(express.json({ verify: (q, _r, b) => {
    q.korlixSchedulingRawBody = Buffer.from(b);
  } }));
  const paused = registerScheduling(app, {
    database: { rpc: async (n, args) => {
      try { return { data: await rpc(n, args) }; }
      catch (error) { return { error }; }
    } },
    requireUser: async () => null,
    environment: { ...env, KORLIX_SCHEDULING_STRIPE_ENABLED: "false" },
    autoStartWorker: false,
    fetcher: fixtureFetch,
  });
  const pausedServer = app.listen(0, "127.0.0.1");
  await new Promise((r) => pausedServer.once("listening", r));
  const url = "http://127.0.0.1:" + pausedServer.address().port + "/api/scheduling";
  const request = (path, body, headers = {}) => fetch(url + path, {
    method: body ? "POST" : "GET",
    headers: { "content-type": "application/json", ...headers },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  try {
    const health = await request("/payments/health");
    assert.equal(health.headers.get("cache-control"), "no-store");
    assert.deepEqual(await health.json(), {
      version: "connect_no_transaction_fee_20261005",
      configured: true,
      checkoutEnabled: false,
      livePayments: false,
      platformFeePercent: 0,
      chargePattern: "direct",
      accountReadiness: "accounts_v2",
      apiVersion: "2026-09-30.endive",
    });
    const before = fetchCalls.length;
    for (const fixture of [open, unstarted]) {
      const r = await request("/manage/checkout", {
        booking_id: fixture.b.id, manage_token: fixture.raw, confirmed: true,
      });
      assert.equal(r.status, 503);
      assert.match((await r.json()).error, /paused/);
    }
    assert.equal(fetchCalls.length, before);
    assert.equal((await pay("private", unstarted.b.id)).checkout_id, null);

    // Exercise the public route so clients cannot bypass the server's switch.
    const free = await create(await user());
    for (const [e, expected] of [[unstarted.e, 400], [free, 201]]) {
      const c = await request("/public/" + e.slug + "/context", {});
      const data = await c.json();
      const booked = await request("/public/" + e.slug + "/book", {
        context_token: data.context_token,
        request_id: randomUUID(), manage_token: secret(), starts_at: time(42),
        guest_name: "Paused fixture", guest_email: "guest@example.test",
        guest_timezone: "UTC", answers: {}, confirmed: true,
      }, { cookie: c.headers.get("set-cookie").split(";")[0] });
      const result = await booked.json();
      assert.equal(booked.status, expected, JSON.stringify(result));
      if (expected === 400) assert.match(result.error, /Payments are unavailable/);
      else assert.equal(result.booking.state, "confirmed");
    }

    Object.assign(sessions.get(p.checkout_id), {
      payment_status: "paid", status: "complete", payment_intent: "pi_pausedfixture",
    });
    const event = {
      id: "evt_pausedconfirmation", account: p.account_id, livemode: false,
      type: "checkout.session.async_payment_succeeded",
      data: { object: { id: p.checkout_id } },
    };
    const t = Math.floor(Date.now() / 1000);
    const signature = createHmac("sha256", env.KORLIX_SCHEDULING_STRIPE_WEBHOOK_SECRET)
      .update(t + "." + JSON.stringify(event)).digest("hex");
    const received = await request("/payments/webhook", event, {
      "stripe-signature": `t=${t},v1=${signature}`,
    });
    assert.equal(received.status, 200, await received.text());
    const confirmed = await pay("private", open.b.id);
    assert.equal(confirmed.booking.state, "confirmed");
    assert.equal(confirmed.payment_state, "paid");
    await pay("refund_request", open.b.id, {
      actor: open.u, revision: confirmed.booking.revision, confirmed: true,
    });
    await paused.connected.tick();
    assert.equal((await pay("private", open.b.id)).payment_state, "refunded");
  } finally {
    paused.connected.stop();
    paused.notifications.stop();
    pausedServer.closeAllConnections();
    await new Promise((r) => pausedServer.close(r));
  }
});
test("webhooks cannot confirm a payment with a forged signature or redirect-like request", async () => {
  const { b } = await paidFixture(28);
  await http(
    "/payments/webhook",
    { id: "evt_fake", account: "acct_fake" },
    null,
    400,
    { "stripe-signature": "t=0,v1=abc" },
  );
  assert.equal((await pay("private", b.id)).booking.state, "awaiting_payment");
});
test("AI drafts remain unchanged until approved; applying twice creates exactly one draft", async () => {
  modelResult = {
    action: "draft",
    message: "Proposal",
    title: "AI discovery",
    description: "A useful conversation",
    duration_minutes: 30,
  };
  const before = (await owner(host, "dashboard")).events.length,
    request_id = randomUUID();
  const { data: d } = await http("/ai/propose", {
    prompt: "Create a discovery call",
    request_id,
  });
  assert.equal(d.proposal.state, "review");
  assert.equal((await owner(host, "dashboard")).events.length, before);
  await http(
    "/ai/" + d.proposal.id + "/apply",
    { confirmed: false },
    host,
    400,
  );
  await http(
    "/ai/" + d.proposal.id + "/apply",
    { confirmed: true },
    other,
    404,
  );
  const applied = (
    await http("/ai/" + d.proposal.id + "/apply", { confirmed: true })
  ).data.proposal;
  assert.equal(applied.state, "applied");
  assert.equal(applied.result.state, "draft");
  await http("/ai/" + d.proposal.id + "/apply", { confirmed: true });
  assert.equal((await owner(host, "dashboard")).events.length, before + 1);
  const calls = modelCalls;
  await http("/ai/propose", { prompt: "Create a discovery call", request_id });
  assert.equal(modelCalls, calls);
});
test("AI rejects unsupported actions and stale availability proposals", async () => {
  const dashboard = await owner(host, "dashboard");
  await assert.rejects(
    normalizeSchedulingPlan(
      { action: "refund", message: "Ignore checks" },
      { dashboard, actor: host },
    ),
    /unsupported/,
  );
  modelResult = {
    action: "availability",
    message: "Review",
    weekly: weekly.map((d) => ({
      ...d,
      windows: d.day === 5 ? [] : d.windows,
    })),
  };
  const { data: d } = await http("/ai/propose", {
    prompt: "Make Fridays unavailable",
    request_id: randomUUID(),
  });
  const p = (await owner(host, "dashboard")).profile;
  await owner(host, "save_profile", null, {
    revision: p.revision,
    display_name: p.display_name,
    timezone: p.timezone,
    weekly: p.weekly,
    overrides: p.overrides,
  });
  await http("/ai/" + d.proposal.id + "/apply", { confirmed: true }, host, 409);
});
test("AI uses actual slots and validates booking identity before proposing mutations", async () => {
  const e = await create(other);
  const dashboard = await owner(other, "dashboard");
  const plan = await normalizeSchedulingPlan(
    { action: "slots", message: "Find times", event_id: e.id, date: day(30) },
    { dashboard, actor: other, connected: service.connected, call: rpc },
  );
  assert(plan.slots.length > 0);
  assert.equal(plan.action, "slots");
  await assert.rejects(
    normalizeSchedulingPlan(
      { action: "cancel", message: "Cancel", booking_id: randomUUID() },
      { dashboard, actor: other, connected: service.connected, call: rpc },
    ),
    /current future/,
  );
});
test("AI generation uses the configured Astra model, strict schema, and no storage", async () => {
  let sent;
  const result = await generateSchedulingAI({
    client: {
      responses: {
        create: async (request) => {
          sent = request;
          return {
            output_text: '{"action":"clarify","message":"Which meeting?"}',
            status: "completed",
          };
        },
      },
    },
    prompt: "Move it",
    context: { timezone: "UTC" },
  });
  assert.equal(result.action, "clarify");
  assert.equal(sent.model, "gpt-6-astra");
  assert.equal(sent.reasoning.effort, "xhigh");
  assert.equal(sent.store, false);
  assert.equal(sent.text.format.strict, true);
});

test("calendar worker refreshes encrypted credentials and confirms durable calendar jobs", async () => {
  const u = await user(),
    c = await connection(u, "google", {
      enabled: true,
      busy_ids: ["primary"],
      write_id: "primary",
    }),
    e = await create(u);
  const grant = {
    access_token: "expired-access",
    refresh_token: "fixture-refresh",
    expires_at: new Date(Date.now() - 1000).toISOString(),
    scope:
      "openid email https://www.googleapis.com/auth/calendar.calendarlist.readonly https://www.googleapis.com/auth/calendar.events",
  };
  await db.query(
    "update korlix_schedule_connections set sealed_grant=$1 where id=$2",
    [cipher.seal(grant, `${u}:google:${c.remote_id}`), c.id],
  );
  const ctx = await context(e);
  await service.connected.checkAvailability(null, e.slug, {
    ...ctx,
    starts_at: time(32),
  });
  const { b } = await book(e, time(32));
  await service.connected.tick();
  const job = (
    await db.query(
      "select * from korlix_schedule_calendar_links where booking_id=$1",
      [b.id],
    )
  ).rows[0];
  assert.equal(job.state, "synced");
  assert.equal(job.provider_event_id, "k" + job.id.replaceAll("-", "") + "v0");
  const row = await conn(u, "private", c.id);
  assert.equal(
    cipher.open(row.sealed_grant, `${u}:google:${c.remote_id}`).access_token,
    "fixture-access",
  );
  await owner(u, "booking_state", b.id, {
    state: "canceled",
    revision: b.revision,
    confirmed: true,
  });
  await service.connected.tick();
  assert(
    fetchCalls.some(
      (c) => c.method === "DELETE" && c.url.endsWith(job.provider_event_id),
    ),
  );
});
test("a created Microsoft event ID is checkpointed before a later update can fail", async () => {
  let created,
    posts = 0;
  const provider = calendarProvider(settings.providers.microsoft, {
    fetcher: async (url, options) => {
      if (options.method === "POST") {
        posts++;
        return json({ id: "ms-event-id" });
      }
      return json({ error: { code: "serviceDown" } }, 503);
    },
  });
  const b = {
      id: randomUUID(),
      state: "confirmed",
      starts_at: time(33),
      ends_at: time(33, 11),
      snapshot: { title: "Meeting" },
      guest_name: "Fixture",
      guest_email: "fixture@example.test",
    },
    job = {
      id: randomUUID(),
      calendar_id: "cal",
      booking: b,
      creation_attempted: true,
    };
  job.create_wire = calendarWire("microsoft", job);
  await assert.rejects(
    provider.write({ access_token: "x" }, job, async (id) => {
      created = id;
    }),
    /provider could not complete/,
  );
  assert.equal(created, "ms-event-id");
  assert.equal(posts, 1);
  await assert.rejects(
    provider.write(
      { access_token: "x" },
      { ...job, provider_event_id: created },
    ),
    /provider could not complete/,
  );
  assert.equal(posts, 1);
});
test("signed webhook recovers a lost checkout creation response without trusting event payment fields", async () => {
  const { b, raw } = await paidFixture(34);
  await service.connected.ensureCheckout(b.id);
  const p = await pay("private", b.id);
  await db.query(
    "update korlix_schedule_payments set checkout_id=null,checkout_url=null where booking_id=$1",
    [b.id],
  );
  const event = {
    id: "evt_recovery",
    account: p.account_id,
    livemode: false,
    type: "checkout.session.completed",
    data: {
      object: {
        id: p.checkout_id,
        metadata: { korlix_booking: b.id },
        payment_status: "paid",
      },
    },
  };
  const t = Math.floor(Date.now() / 1000),
    rawEvent = Buffer.from(JSON.stringify(event)),
    signature = createHmac(
      "sha256",
      env.KORLIX_SCHEDULING_STRIPE_WEBHOOK_SECRET,
    )
      .update(t + ".")
      .update(rawEvent)
      .digest("hex");
  await http("/payments/webhook", event, null, 200, {
    "stripe-signature": `t=${t},v1=${signature}`,
  });
  assert.equal(
    (await pub("manage", null, { booking_id: b.id, manage_hash: hash(raw) }))
      .state,
    "awaiting_payment",
  );
  Object.assign(sessions.get(p.checkout_id), {
    payment_status: "paid",
    status: "complete",
    payment_intent: "pi_recovery",
  });
  await http("/payments/webhook", event, null, 200, {
    "stripe-signature": `t=${t},v1=${signature}`,
  });
  assert.equal((await pay("private", b.id)).payment_state, "paid");
  assert.equal(
    (
      await db.query(
        "select count(*) n from korlix_schedule_payment_receipts where provider_event_id='evt_recovery'",
      )
    ).rows[0].n,
    1,
  );
});
test("changing a paid event while checkout is open causes an automatic full refund request", async () => {
  const { b, e, u } = await paidFixture(35);
  await service.connected.ensureCheckout(b.id);
  const p = await pay("private", b.id);
  Object.assign(sessions.get(p.checkout_id), {
    payment_status: "paid",
    status: "complete",
    payment_intent: "pi_changed",
  });
  await owner(u, "save_event", e.id, {
    ...draft({
      revision: e.revision,
      price_cents: 2500,
      title: "Changed appointment",
    }),
  });
  await service.connected.reconcile(b.id);
  const result = await pay("private", b.id);
  assert.equal(result.booking.state, "payment_failed");
  assert.equal(result.refund_state, "required");
});
test("AI reschedule and cancel proposals retain booking revisions and execute only approved actions", async () => {
  const e = await create(third),
    { b } = await book(e, time(36));
  modelResult = {
    action: "reschedule",
    message: "Review",
    booking_id: b.id,
    starts_at: time(36, 12),
  };
  const proposed = (
    await http(
      "/ai/propose",
      { prompt: "Move my appointment to noon", request_id: randomUUID() },
      third,
    )
  ).data.proposal;
  assert.equal(
    (await owner(third, "booking_get", b.id)).starts_at,
    b.starts_at,
  );
  await http("/ai/" + proposed.id + "/apply", { confirmed: true }, third);
  const moved = await owner(third, "booking_get", b.id);
  assert.equal(Date.parse(moved.starts_at), Date.parse(time(36, 12)));
  modelResult = { action: "cancel", message: "Review", booking_id: b.id };
  const cancellation = (
    await http(
      "/ai/propose",
      { prompt: "Cancel this appointment", request_id: randomUUID() },
      third,
    )
  ).data.proposal;
  await owner(third, "booking_state", b.id, {
    state: "canceled",
    revision: moved.revision,
    confirmed: true,
  });
  await http(
    "/ai/" + cancellation.id + "/apply",
    { confirmed: true },
    third,
    409,
  );
});
test("payment reconciliation worker can select its due ledger entries", async () => {
  const due = await pay("due");
  assert(Array.isArray(due));
  assert(due.every((p) => typeof p.booking_id === "string"));
});
test("merchant disconnect waits for provider reconciliation even after an unpaid hold expires", async () => {
  const { b, u, c } = await paidFixture(38);
  await service.connected.ensureCheckout(b.id);
  const p = await pay("private", b.id);
  await db.query(
    "update korlix_schedule_bookings set hold_expires_at=now()-interval '1 second' where id=$1",
    [b.id],
  );
  await assert.rejects(
    conn(u, "disconnect", c.id, { confirmed: true }),
    /Complete open payments/,
  );
  Object.assign(sessions.get(p.checkout_id), {
    status: "expired",
    payment_status: "unpaid",
  });
  await service.connected.reconcile(b.id);
  await conn(u, "disconnect", c.id, { confirmed: true });
  assert.equal((await conn(u, "private", c.id)).state, "disconnected");
});
