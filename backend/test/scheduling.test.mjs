import test from "node:test";
import { schedulingNotifications } from "../scheduling/notifications.mjs";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { PGlite } from "@electric-sql/pglite";
import express from "express";
import { registerScheduling } from "../scheduling/routes.mjs";
import {
  profile,
  event,
  hash,
  secret,
  calendarFile,
  bookingCsv,
} from "../scheduling/core.mjs";
let db, server, base, host, other, disabled;
const emailEnvironment = {
  NODE_ENV: "test",
  RESEND_API_KEY: "fixture-key-only",
  KORLIX_AGENT_EMAIL_FROM: "fixture@example.test",
  KORLIX_SCHEDULING_TOKEN_KEY: Buffer.alloc(32, 7).toString("base64"),
};
const queueDatabase = {
  rpc: async (name, p) => {
    try {
      return {
        data: (
          await db.query("select korlix_schedule_queue_v1($1,$2,$3,$4) value", [
            p.p_action,
            p.p_id,
            p.p_lease,
            p.p_data,
          ])
        ).rows[0].value,
      };
    } catch (error) {
      return { error };
    }
  },
};
const future = (days = 3) =>
  new Date(Date.now() + days * 86400000).toISOString().slice(0, 10);
const weekly = Array.from({ length: 7 }, (_, day) => ({
  day,
  windows: [[540, 1020]],
}));
const draft = (changes = {}) => ({
  revision: 0,
  title: "Discovery call",
  description: "A focused conversation",
  kind: "one_to_one",
  duration_minutes: 30,
  interval_minutes: 30,
  buffer_before: 0,
  buffer_after: 0,
  notice_minutes: 0,
  horizon_days: 365,
  daily_limit: 8,
  capacity: 1,
  cancel_notice_minutes: 0,
  location_kind: "video",
  location_detail: "https://meet.example.test/private-room",
  questions: [],
  color: "#72D6EB",
  ...changes,
});
async function rpc(name, args) {
  return (await db.query("select " + name + "($1,$2,$3,$4) value", args))
    .rows[0].value;
}
const owner = (u, a, id = null, data = {}) =>
  rpc("korlix_schedule_owner_v1", [u, a, id, data]);
const pub = async (a, slug = null, data = {}) =>
  (
    await db.query("select korlix_schedule_public_v1($1,$2,$3) value", [
      a,
      slug,
      data,
    ])
  ).rows[0].value;
async function user() {
  const id = randomUUID();
  await db.query("insert into auth.users values($1,now(),false)", [id]);
  await db.query("insert into user_profiles values($1,'basic',false)", [id]);
  await owner(id, "save_profile", null, {
    revision: 0,
    display_name: "Fixture host",
    timezone: "UTC",
    weekly,
    overrides: [],
  });
  return id;
}
async function create(u = host, changes = {}) {
  const e = await owner(u, "save_event", null, {
    ...draft(changes),
    slug: "fixture-" + secret().slice(0, 16),
  });
  return owner(u, "event_state", e.id, {
    revision: e.revision,
    state: "published",
    confirmed: true,
  });
}
async function context(e) {
  const data = { token_hash: hash(secret()), browser_hash: hash(secret()) };
  await pub("context", e.slug, data);
  return data;
}
async function slots(e, c, day = future()) {
  return (await pub("slots", e.slug, { ...c, date: day })).slots;
}
function body(c, start, changes = {}) {
  const raw = secret(),
    d = {
      ...c,
      request_id: randomUUID(),
      manage_hash: hash(raw),
      starts_at: start,
      guest_name: "Guest",
      guest_email: randomUUID() + "@example.test",
      guest_timezone: "UTC",
      answers: {},
      confirmed: true,
      ...changes,
    };
  return { raw, data: { ...d, request_hash: hash(JSON.stringify(d)) } };
}
async function reserve(e, start, c, changes = {}) {
  const data = body(c, start, changes);
  return { ...data, booking: await pub("book", e.slug, data.data) };
}
async function api(path = "", body, actor = host, expected = 200, cookie = "") {
  const r = await fetch(base + "/api/scheduling" + path, {
    method: body ? "POST" : "GET",
    headers: {
      Authorization: actor || "",
      "Content-Type": "application/json",
      ...(cookie ? { Cookie: cookie } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const data = await r.json();
  assert.equal(r.status, expected, JSON.stringify(data));
  assert.equal(r.headers.get("cache-control"), "no-store");
  return { data, cookie: r.headers.get("set-cookie")?.split(";")[0] };
}
test.before(async () => {
  db = new PGlite();
  await db.exec(
    "create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,is_anonymous boolean);create table user_profiles(id uuid primary key,tier text,is_disabled boolean);grant usage on schema public,auth to service_role,anon,authenticated;grant select,insert,update on user_profiles,auth.users to service_role;",
  );
  await db.exec(
    await readFile(
      new URL(
        "../../supabase/migrations/20260930152919_scheduling_engine.sql",
        import.meta.url,
      ),
      "utf8",
    ),
  );
  await db.exec("set role service_role");
  host = await user();
  other = await user();
  disabled = await user();
  await db.query("update user_profiles set is_disabled=true where id=$1", [
    disabled,
  ]);
  const app = express();
  app.use(express.json());
  registerScheduling(app, {
    database: {
      rpc: async (name, p) => {
        try {
          return {
            data:
              name === "korlix_schedule_owner_v1"
                ? await owner(p.p_actor, p.p_action, p.p_id, p.p_data)
                : await pub(p.p_action, p.p_slug, p.p_data),
          };
        } catch (error) {
          return { error };
        }
      },
    },
    requireUser: async (q) =>
      [host, other, disabled].includes(q.headers.authorization)
        ? {
            id: q.headers.authorization,
            email: q.headers.authorization + "@example.test",
            email_confirmed_at: "2026-01-01",
            is_anonymous: false,
          }
        : null,
    environment: emailEnvironment,
    autoStartWorker: false,
  });
  server = app.listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  base = "http://127.0.0.1:" + server.address().port;
});
test.after(async () => {
  server?.closeAllConnections();
  if (server) await new Promise((r) => server.close(r));
  await db?.close();
});
test("verified active hosts own their private schedule, with no browser database access", async () => {
  await api("", null, null, 401);
  await api("", null, disabled, 403);
  const e = await create();
  assert(!(await api("", null, other)).data.events.some((x) => x.id === e.id));
  await api(
    "/events/" + e.id + "/state",
    { state: "paused", confirmed: true, revision: e.revision },
    other,
    404,
  );
  await db.exec("reset role");
  try {
    for (const role of ["anon", "authenticated"]) {
      await db.exec("set role " + role);
      for (const t of [
        "profiles",
        "events",
        "blocks",
        "bookings",
        "contexts",
        "audit",
        "notifications",
      ])
        await assert.rejects(
          db.query("select * from korlix_schedule_" + t),
          /permission denied/,
        );
      await assert.rejects(owner(host, "dashboard"), /permission denied/);
      await assert.rejects(pub("context", e.slug, {}), /permission denied/);
      await db.exec("reset role");
    }
  } finally {
    await db.exec("set role service_role");
  }
});
test("availability and event fields reject invalid zones, windows, choices and unsafe meeting links", () => {
  assert.throws(() =>
    profile({
      revision: 0,
      display_name: "Host",
      timezone: "Wrong/Zone",
      weekly,
      overrides: [],
    }),
  );
  assert.throws(() =>
    profile({
      revision: 0,
      display_name: "Host",
      timezone: "UTC",
      weekly: weekly.map((w) => ({
        ...w,
        windows: [
          [600, 700],
          [650, 800],
        ],
      })),
      overrides: [],
    }),
  );
  assert.throws(() => event(draft({ location_detail: "javascript:alert(1)" })));
  assert.throws(() => event(draft({ duration_minutes: 31 })));
  assert.throws(() => event(draft({ capacity: 2 })));
  assert.throws(() => event(draft({ paid: true })));
});
test("same-host conflicts span event types, concurrent claims have one winner, and replay is stable", async () => {
  const u = await user(),
    e = await create(u),
    second = await create(u),
    c = await context(e),
    start = (await slots(e, c))[0].starts_at;
  const a = body(c, start),
    b = body(c, start);
  const results = await Promise.allSettled([
    pub("book", e.slug, a.data),
    pub("book", e.slug, b.data),
  ]);
  assert.equal(results.filter((x) => x.status === "fulfilled").length, 1);
  const winner = results[0].status === "fulfilled" ? a : b,
    first = results.find((x) => x.status === "fulfilled").value;
  assert.equal((await pub("book", e.slug, winner.data)).id, first.id);
  await assert.rejects(
    pub("book", e.slug, { ...winner.data, request_hash: hash("changed") }),
    /changed/,
  );
  assert(
    !(await slots(second, await context(second))).some(
      (s) => s.starts_at === start,
    ),
  );
  const text = JSON.stringify(first);
  for (const key of ["manage_hash", "request_hash", "owner_id", "token_hash"])
    assert(!text.includes(key));
});
test("group capacity is atomic and does not reveal other attendees", async () => {
  const u = await user(),
    e = await create(u, { kind: "group", capacity: 2 }),
    c = await context(e),
    start = (await slots(e, c))[0].starts_at;
  const first = await reserve(e, start, c);
  assert.equal(
    (await slots(e, c)).find((s) => s.starts_at === start).seats_left,
    1,
  );
  await reserve(e, start, c);
  assert(!(await slots(e, c)).some((s) => s.starts_at === start));
  await assert.rejects(reserve(e, start, c), /no longer available/);
  assert(
    !JSON.stringify(await slots(e, c)).includes(first.booking.guest_email),
  );
});
test("buffers, time blocks, date overrides and daily limits protect host time", async () => {
  const u = await user(),
    e = await create(u, { buffer_after: 30, daily_limit: 2 }),
    c = await context(e),
    list = await slots(e, c);
  await reserve(e, list[0].starts_at, c);
  assert(!(await slots(e, c)).some((s) => s.starts_at === list[1].starts_at));
  await owner(u, "add_block", null, {
    starts_at: list[2].starts_at,
    ends_at: list[3].ends_at,
    label: "Other appointment",
  });
  assert(!(await slots(e, c)).some((s) => s.starts_at === list[2].starts_at));
  const next = (await slots(e, c))[0];
  await reserve(e, next.starts_at, c);
  assert(
    !(await slots(e, c)).some((s) => s.starts_at.slice(0, 10) === future()),
  );
  const p = (await owner(u, "dashboard")).profile;
  await owner(u, "save_profile", null, {
    ...p,
    weekly,
    overrides: [{ date: future(4), windows: [] }],
    revision: p.revision,
  });
  const fresh = await context(e);
  assert(
    !(await slots(e, fresh, future(4))).some(
      (s) => s.starts_at.slice(0, 10) === future(4),
    ),
  );
});
test("stale publication contexts and disabled hosts cannot accept new bookings", async () => {
  const u = await user(),
    e = await create(u),
    c = await context(e),
    start = (await slots(e, c))[0].starts_at;
  await owner(u, "event_state", e.id, {
    revision: e.revision,
    state: "paused",
    confirmed: true,
  });
  await assert.rejects(reserve(e, start, c), /unavailable/);
  const paused = (await owner(u, "dashboard")).events[0];
  const live = await owner(u, "event_state", e.id, {
    revision: paused.revision,
    state: "published",
    confirmed: true,
  });
  await assert.rejects(reserve(e, start, c), /updated/);
  const fresh = await context(live);
  await db.query("update user_profiles set is_disabled=true where id=$1", [u]);
  await assert.rejects(reserve(live, start, fresh), /unavailable/);
});
test("private management tokens and revisions gate cancellation and atomic rescheduling", async () => {
  const u = await user(),
    e = await create(u),
    c = await context(e),
    list = await slots(e, c),
    r = await reserve(e, list[0].starts_at, c),
    auth = { booking_id: r.booking.id, manage_hash: hash(r.raw) };
  await assert.rejects(
    pub("manage", null, { ...auth, manage_hash: hash("wrong") }),
    /unavailable/,
  );
  const updated = await pub("reschedule", null, {
    ...auth,
    confirmed: true,
    revision: r.booking.revision,
    event_revision: e.revision,
    starts_at: list[2].starts_at,
  });
  assert.equal(Date.parse(updated.starts_at), Date.parse(list[2].starts_at));
  assert((await slots(e, c)).some((s) => s.starts_at === list[0].starts_at));
  await assert.rejects(
    pub("cancel", null, { ...auth, confirmed: true, revision: 1 }),
    /changed/,
  );
  await pub("cancel", null, {
    ...auth,
    confirmed: true,
    revision: updated.revision,
  });
  assert.equal((await pub("manage", null, auth)).state, "canceled");
  assert((await slots(e, c)).some((s) => s.starts_at === list[2].starts_at));
});
test("public HTTP booking requires a bound cookie, reviewed fields and questions", async () => {
  const e = await create(other, {
      questions: [
        {
          id: "topic",
          label: "Topic",
          kind: "choice",
          required: true,
          options: ["Sales", "Support"],
        },
      ],
    }),
    ctx = await api("/public/" + e.slug + "/context", {}, null),
    data = ctx.data,
    cookie = ctx.cookie;
  await api(
    "/public/" + e.slug + "/slots",
    { context_token: data.context_token, date: future() },
    null,
    409,
  );
  const available = (
    await api(
      "/public/" + e.slug + "/slots",
      { context_token: data.context_token, date: future() },
      null,
      200,
      cookie,
    )
  ).data.slots;
  const payload = {
    context_token: data.context_token,
    request_id: randomUUID(),
    manage_token: secret(),
    starts_at: available[0].starts_at,
    guest_name: "HTTP Guest",
    guest_email: "guest@example.test",
    guest_timezone: "UTC",
    answers: { topic: "Sales" },
    confirmed: true,
    website: "",
  };
  await api(
    "/public/" + e.slug + "/book",
    { ...payload, answers: { topic: "Tampered" } },
    null,
    400,
    cookie,
  );
  const booked = (
    await api("/public/" + e.slug + "/book", payload, null, 201, cookie)
  ).data.booking;
  assert.equal(booked.state, "confirmed");
  assert.equal(
    (await api("/public/" + e.slug + "/book", payload, null, 201, cookie)).data
      .booking.id,
    booked.id,
  );
  const forged = await fetch(
    base + "/api/scheduling/public/" + e.slug + "/context",
    {
      method: "POST",
      headers: {
        Origin: "https://evil.example",
        "Content-Type": "application/json",
      },
      body: "{}",
    },
  );
  assert.equal(forged.status, 403);
});
test("DST spring gaps, fall repeated hours and fractional zones produce unique real instants", async () => {
  const u = await user(),
    p = (await owner(u, "dashboard")).profile;
  await owner(u, "save_profile", null, {
    ...p,
    timezone: "America/New_York",
    weekly: weekly.map((w) => ({ ...w, windows: [[0, 240]] })),
    revision: p.revision,
  });
  const e = await create(u),
    fall = "2026-11-01",
    spring = "2027-03-14";
  for (const [day, expected] of [
    [fall, 10],
    [spring, 6],
  ]) {
    const rows = await db.query("select korlix_schedule_slots_v1($1,$2,1) s", [
      e.id,
      day,
    ]);
    assert.equal(rows.rows[0].s.length, expected);
    assert.equal(
      new Set(rows.rows[0].s.map((s) => s.starts_at)).size,
      expected,
    );
  }
  const narrow = (await owner(u, "dashboard")).profile;
  await owner(u, "save_profile", null, {
    ...narrow,
    weekly: weekly.map((w) => ({ ...w, windows: [[90, 150]] })),
    revision: narrow.revision,
  });
  const long = await create(u, { duration_minutes: 60 });
  const narrowSlots = (
    await db.query("select korlix_schedule_slots_v1($1,$2,1) s", [
      long.id,
      fall,
    ])
  ).rows[0].s;
  assert.equal(narrowSlots.length, 1);
  assert.equal(
    Date.parse(narrowSlots[0].starts_at),
    Date.parse("2026-11-01T06:30:00Z"),
  );
  const p2 = (await owner(u, "dashboard")).profile;
  await owner(u, "save_profile", null, {
    ...p2,
    timezone: "Asia/Kathmandu",
    weekly,
    revision: p2.revision,
  });
  const list = await slots(e, await context(e));
  assert.equal(new Date(list[0].starts_at).getUTCMinutes(), 15);
});
test("calendar and CSV exports escape injected content without sending invitations", () => {
  const b = {
    id: randomUUID(),
    revision: 2,
    state: "confirmed",
    starts_at: "2026-12-01T12:00:00Z",
    ends_at: "2026-12-01T12:30:00Z",
    snapshot: {
      title: "Hello\nATTENDEE:bad",
      description: "semi;comma,",
      host_name: "Host",
      location_detail: "Room",
    },
    guest_name: "=SUM(A1)",
    guest_email: "guest@example.test",
  };
  const ics = calendarFile(b);
  assert(ics.includes("SUMMARY:Hello\\nATTENDEE:bad"));
  assert(!ics.includes("\r\nATTENDEE:"));
  assert(!ics.includes("METHOD:REQUEST"));
  assert(bookingCsv([b]).includes("'=SUM(A1)"));
});

test("booking emails require host opt-in, bind the verified address, and preserve encrypted private links", async () => {
  const u = await user(),
    p = (await owner(u, "dashboard")).profile,
    e = await create(u);
  await owner(u, "notifications", null, {
    enabled: true,
    reminder_minutes: 60,
    verified_email: u + "@example.test",
    confirmed: true,
    revision: p.revision,
  });
  const c = await context(e),
    list = await slots(e, c),
    raw = body(c, list[0].starts_at);
  const service = schedulingNotifications({
    database: queueDatabase,
    environment: emailEnvironment,
    autoStart: false,
    publicRoot: "https://booking.example.test",
  });
  raw.data.sealed_manage_token = service.seal(raw.raw, raw.data.request_id);
  const booked = await pub("book", e.slug, raw.data);
  assert.equal(booked.notifications.length, 2);
  assert(!JSON.stringify(booked).includes("sealed_manage_token"));
  assert.equal(
    service.open(raw.data.sealed_manage_token, raw.data.request_id),
    raw.raw,
  );
  assert.throws(() => service.open(raw.data.sealed_manage_token, randomUUID()));
  await pub("book", e.slug, raw.data);
  assert.equal(
    (
      await db.query(
        "select count(*) n from korlix_schedule_notifications where booking_id=$1",
        [booked.id],
      )
    ).rows[0].n,
    3,
  );
  const deliveries = [];
  const worker = schedulingNotifications({
    database: queueDatabase,
    environment: emailEnvironment,
    autoStart: false,
    publicRoot: "https://booking.example.test",
    fetcher: async (url, options) => {
      assert.equal(url, "https://api.resend.com/emails");
      deliveries.push(options);
      return new Response(JSON.stringify({ id: randomUUID() }), {
        status: 200,
      });
    },
  });
  await worker.tick();
  assert.equal(deliveries.length, 2);
  const guest = deliveries
    .map((x) => JSON.parse(x.body))
    .find((x) => x.to[0] === booked.guest_email);
  assert(guest.text.includes(raw.raw));
  assert(guest.text.includes("/book/manage#" + booked.id));
  const stored = (
    await db.query(
      "select * from korlix_schedule_notifications where booking_id=$1",
      [booked.id],
    )
  ).rows;
  assert.equal(stored.filter((x) => x.state === "accepted").length, 2);
  assert(
    !JSON.stringify(stored).includes(raw.raw),
    "plain management token must never be stored",
  );
  const p2 = (await owner(u, "dashboard")).profile;
  await owner(u, "notifications", null, {
    enabled: false,
    reminder_minutes: 0,
    verified_email: u + "@example.test",
    confirmed: true,
    revision: p2.revision,
  });
  assert.equal(
    (
      await db.query(
        "select state from korlix_schedule_notifications where booking_id=$1 and kind='reminder'",
        [booked.id],
      )
    ).rows[0].state,
    "skipped",
  );
});

test("notification retries preserve exact provider payload and key; stale updates never send", async () => {
  const u = await user(),
    p = (await owner(u, "dashboard")).profile,
    e = await create(u);
  await owner(u, "notifications", null, {
    enabled: true,
    reminder_minutes: 60,
    verified_email: u + "@example.test",
    confirmed: true,
    revision: p.revision,
  });
  const c = await context(e),
    list = await slots(e, c),
    raw = body(c, list[0].starts_at),
    deliveries = [];
  const worker = schedulingNotifications({
    database: queueDatabase,
    environment: emailEnvironment,
    autoStart: false,
    publicRoot: "https://booking.example.test",
    fetcher: async (_url, options) => {
      deliveries.push(options);
      throw new Error("uncertain network response");
    },
  });
  raw.data.sealed_manage_token = worker.seal(raw.raw, raw.data.request_id);
  const booked = await pub("book", e.slug, raw.data);
  await worker.tick();
  assert.equal(deliveries.length, 2);
  await db.query(
    "update korlix_schedule_notifications set due_at=now()-interval '1 minute' where booking_id=$1 and kind='confirmation'",
    [booked.id],
  );
  await worker.tick();
  assert.equal(deliveries.length, 4);
  for (const d of deliveries.slice(0, 2)) {
    const replay = deliveries
      .slice(2)
      .find(
        (x) => x.headers["Idempotency-Key"] === d.headers["Idempotency-Key"],
      );
    assert.equal(replay.body, d.body);
  }
  await pub("cancel", null, {
    booking_id: booked.id,
    manage_hash: hash(raw.raw),
    revision: booked.revision,
    confirmed: true,
  });
  assert.equal(
    (
      await db.query(
        "select count(*) n from korlix_schedule_notifications where booking_id=$1 and kind in ('confirmation','reminder') and state='pending'",
        [booked.id],
      )
    ).rows[0].n,
    0,
  );
  await db.query(
    "update korlix_schedule_notifications set first_attempt_at=now()-interval '25 hours' where booking_id=$1 and kind='cancellation'",
    [booked.id],
  );
  await worker.tick();
  assert.equal(deliveries.length, 4);
  assert.equal(
    (
      await db.query(
        "select count(*) n from korlix_schedule_notifications where booking_id=$1 and state='uncertain'",
        [booked.id],
      )
    ).rows[0].n,
    2,
  );
});

test("HTTP email settings use verified identity and stale revisions cannot overwrite them", async () => {
  const p = (await owner(host, "dashboard")).profile;
  await api(
    "/notifications",
    {
      enabled: true,
      reminder_minutes: 60,
      confirmed: false,
      revision: p.revision,
    },
    host,
    400,
  );
  await api(
    "/notifications",
    {
      enabled: true,
      reminder_minutes: 60,
      confirmed: true,
      revision: p.revision,
    },
    host,
  );
  const current = (await owner(host, "dashboard")).profile;
  assert.equal(current.notification_email, host + "@example.test");
  assert.equal(current.notifications_enabled, true);
  await api(
    "/notifications",
    {
      enabled: false,
      reminder_minutes: 0,
      confirmed: true,
      revision: p.revision,
    },
    host,
    409,
  );
  await api(
    "/notifications",
    {
      enabled: false,
      reminder_minutes: 0,
      confirmed: true,
      revision: current.revision,
    },
    host,
  );
});
