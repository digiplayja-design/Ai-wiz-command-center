import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import express from "express";
import { PGlite } from "@electric-sql/pglite";
import { registerScheduling } from "../scheduling/routes.mjs";
import { event, hash, secret } from "../scheduling/core.mjs";
import { schedulingContext, schedulingLocalTime } from "../scheduling/ai.mjs";
import {
  providerCipher,
  providerSettings,
} from "../scheduling/provider_core.mjs";

let db, server, base, service, modelResult, modelContext;
let calendarFailure = false,
  calendarEvents = [],
  providerCalls = [];
const users = new Map();
const env = {
  NODE_ENV: "test",
  KORLIX_SCHEDULING_PUBLIC_URL: "https://example.test",
  KORLIX_SCHEDULING_TOKEN_KEY: Buffer.alloc(32, 7).toString("base64"),
  KORLIX_SCHEDULING_GOOGLE_CLIENT_ID: "fixture-id",
  KORLIX_SCHEDULING_GOOGLE_CLIENT_SECRET: "fixture-secret",
};
const settings = providerSettings(env, env.KORLIX_SCHEDULING_PUBLIC_URL);
const cipher = providerCipher(env);
const weekly = Array.from({ length: 7 }, (_, day) => ({
  day,
  windows: [[540, 1020]],
}));
const day = (n = 10) =>
  new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);
const at = (n = 10, h = 10) =>
  day(n) + `T${String(h).padStart(2, "0")}:00:00.000Z`;
const rpc = async (name, args) =>
  (
    await db.query(
      `select ${name}(${Object.keys(args)
        .map((key, i) => key + "=>$" + (i + 1))
        .join(",")}) value`,
      Object.values(args),
    )
  ).rows[0].value;
const owner = (id, action, target = null, data = {}) =>
  rpc("korlix_schedule_owner_v1", {
    p_actor: id,
    p_action: action,
    p_id: target,
    p_data: data,
  });
async function user({ profile = true, ...claims } = {}) {
  const id = randomUUID();
  await db.query("insert into auth.users values($1,now(),false)", [id]);
  await db.query("insert into user_profiles values($1,'basic',false)", [id]);
  users.set(id, {
    id,
    email_confirmed_at: "2026-01-01",
    is_anonymous: false,
    ...claims,
  });
  if (profile)
    await owner(id, "save_profile", null, {
      revision: 0,
      display_name: "Fixture host",
      timezone: "UTC",
      weekly,
      overrides: [],
    });
  return id;
}
async function create(id, published = true) {
  const e = await owner(id, "save_event", null, {
    ...event({
      revision: 0,
      title: "Private appointment",
      description: "DESCRIPTION_PRIVATE",
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
      location_kind: "custom",
      location_detail: "LOCATION_PRIVATE",
      questions: [],
      color: "#72D6EB",
    }),
    slug: "voice-" + secret().slice(0, 20),
  });
  return published
    ? owner(id, "event_state", e.id, {
        revision: e.revision,
        state: "published",
        confirmed: true,
      })
    : e;
}
async function book(e, starts_at) {
  const capability = {
    token_hash: hash(secret()),
    browser_hash: hash(secret()),
  };
  await rpc("korlix_schedule_public_v1", {
    p_action: "context",
    p_slug: e.slug,
    p_data: capability,
  });
  return rpc("korlix_schedule_public_v1", {
    p_action: "book",
    p_slug: e.slug,
    p_data: {
      ...capability,
      request_id: randomUUID(),
      request_hash: hash(secret()),
      manage_hash: hash(secret()),
      starts_at,
      guest_name: "Fixture guest",
      guest_email: "GUEST_PRIVATE@example.test",
      guest_timezone: "UTC",
      answers: {},
      confirmed: true,
    },
  });
}
async function connect(id) {
  const remote = "fixture-" + secret().slice(0, 10);
  await db.query(
    "insert into korlix_schedule_connections(owner_id,provider,remote_id,label,sealed_grant,config_hash,enabled,calendars,busy_ids) values($1,'google',$2,'PRIVATE_CONNECTION',$3,$4,true,$5,$6)",
    [
      id,
      remote,
      cipher.seal(
        {
          access_token: "PRIVATE_ACCESS_TOKEN",
          refresh_token: "PRIVATE_REFRESH_TOKEN",
          expires_at: new Date(Date.now() + 86400000).toISOString(),
          scope:
            "openid email https://www.googleapis.com/auth/calendar.calendarlist.readonly https://www.googleapis.com/auth/calendar.events",
        },
        `${id}:google:${remote}`,
      ),
      settings.providers.google.fingerprint,
      [
        {
          id: "primary",
          name: "PRIVATE_CALENDAR",
          timezone: "UTC",
          writable: true,
        },
      ],
      ["primary"],
    ],
  );
}
async function http(path, id, body, status = 200) {
  const response = await fetch(base + "/api/scheduling" + path, {
    method: body === undefined ? "GET" : "POST",
    headers: { authorization: id || "", "content-type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const data = await response.json();
  assert.equal(response.status, status, JSON.stringify(data));
  assert.equal(response.headers.get("cache-control"), "no-store");
  return data;
}
async function scheduleSnapshot() {
  const result = {};
  for (const table of [
    "profiles",
    "events",
    "bookings",
    "audit",
    "notifications",
    "calendar_links",
    "ai_plans",
  ])
    result[table] = (
      await db.query(
        `select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]') data from korlix_schedule_${table} t`,
      )
    ).rows[0].data;
  return result;
}
test.before(async () => {
  db = new PGlite();
  await db.exec(
    "create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,is_anonymous boolean);create table user_profiles(id uuid primary key,tier text,is_disabled boolean);grant usage on schema public,auth to service_role,anon,authenticated;grant select,insert,update on user_profiles,auth.users to service_role;",
  );
  for (const name of [
    "20260930152919_scheduling_engine.sql",
    "20260930163605_scheduling_connected.sql",
  ])
    await db.exec(
      await readFile(
        new URL("../../supabase/migrations/" + name, import.meta.url),
        "utf8",
      ),
    );
  await db.exec("set role service_role");
  const app = express();
  app.use(express.json());
  service = registerScheduling(app, {
    database: {
      rpc: async (name, args) => {
        try {
          return { data: await rpc(name, args) };
        } catch (error) {
          return { error };
        }
      },
    },
    requireUser: async (q) => users.get(q.headers.authorization),
    environment: env,
    autoStartWorker: false,
    fetcher: async (url, options = {}) => {
      const target = new URL(url);
      providerCalls.push({ url: target.href, method: options.method || "GET" });
      assert.equal(
        options.method || "GET",
        "GET",
        "Voice reads must not write to a provider",
      );
      assert.equal(target.hostname, "www.googleapis.com");
      assert(target.pathname.endsWith("/events"));
      return new Response(
        JSON.stringify(
          calendarFailure
            ? { error: "unavailable" }
            : { items: calendarEvents },
        ),
        { status: calendarFailure ? 503 : 200 },
      );
    },
    generateAI: async ({ context }) => {
      modelContext = context;
      return modelResult;
    },
  });
  server = app.listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  base = "http://127.0.0.1:" + server.address().port;
});
test.after(async () => {
  service?.connected.stop();
  service?.notifications.stop();
  server?.closeAllConnections();
  if (server) await new Promise((resolve) => server.close(resolve));
  await db?.close();
});

test("voice reads require verified active accounts and expose a safe first-run state", async () => {
  for (const id of [
    null,
    await user({ is_anonymous: true }),
    await user({ email_confirmed_at: null }),
  ]) {
    await http("/voice/context", id, undefined, 401);
    await http(
      "/voice/slots",
      id,
      { event_id: randomUUID(), date: day() },
      401,
    );
  }
  const disabled = await user();
  await db.query("update user_profiles set is_disabled=true where id=$1", [
    disabled,
  ]);
  await http("/voice/context", disabled, undefined, 403);
  const empty = await user({ profile: false });
  const firstRun = await http("/voice/context", empty);
  assert.deepEqual(firstRun, {
    now: firstRun.now,
    timezone: null,
    profile_ready: false,
    weekly: [],
    events: [],
    bookings: [],
    truncated: false,
  });
  await http(
    "/voice/slots",
    empty,
    { event_id: randomUUID(), date: day() },
    409,
  );
});

test("context is owner-isolated, redacted, chronological and does not write scheduling records", async () => {
  const host = await user(),
    other = await user();
  const e = await create(host),
    foreign = await create(other);
  const later = await book(e, at(12)),
    earlier = await book(e, at(10));
  await book(foreign, at(11));
  await connect(host);
  const before = await scheduleSnapshot(),
    calls = providerCalls.length;
  const context = await http("/voice/context", host);
  assert.equal(context.profile_ready, true);
  assert.equal(context.timezone, "UTC");
  assert.deepEqual(
    context.events.map((x) => x.id),
    [e.id],
  );
  assert.deepEqual(
    context.bookings.map((x) => x.id),
    [earlier.id, later.id],
  );
  assert(context.bookings[0].starts_local.includes("GMT"));
  const serialized = JSON.stringify(context);
  for (const privateValue of [
    "PRIVATE",
    foreign.id,
    "manage_hash",
    "guest_email",
    "answers",
    "owner_id",
    "sealed",
    "request_id",
  ])
    assert(!serialized.includes(privateValue), privateValue);
  assert.deepEqual(await scheduleSnapshot(), before);
  assert.equal(providerCalls.length, calls);
});

test("context bounds and flags incomplete results, with host-local DST offsets", () => {
  const now = Date.parse("2026-10-01T00:00:00Z");
  const bookings = Array.from({ length: 102 }, (_, i) => ({
    id: randomUUID(),
    state: "confirmed",
    starts_at: new Date(now + (103 - i) * 3600000).toISOString(),
    ends_at: new Date(now + (103 - i) * 3600000 + 1800000).toISOString(),
    snapshot: { title: "Meeting" },
    guest_name: "Guest",
  }));
  const dashboard = {
    profile: { timezone: "America/New_York", weekly },
    events: Array.from({ length: 101 }, () => ({ id: randomUUID() })),
    bookings,
  };
  const context = schedulingContext(dashboard, () => now);
  assert.equal(context.events.length, 100);
  assert.equal(context.bookings.length, 100);
  assert.equal(context.truncated, true);
  assert(
    Date.parse(context.bookings[0].starts_at) <
      Date.parse(context.bookings[99].starts_at),
  );
  const capped = schedulingContext(
    { ...dashboard, events: [], bookings: [bookings[0]], booking_limit: 1 },
    () => now,
  );
  assert.equal(capped.truncated, true);
  assert.match(
    schedulingLocalTime("2026-11-01T05:30:00Z", "America/New_York"),
    /1:30 AM GMT-04:00/,
  );
  assert.match(
    schedulingLocalTime("2026-11-01T06:30:00Z", "America/New_York"),
    /1:30 AM GMT-05:00/,
  );
  assert.deepEqual(
    schedulingContext(
      {
        ...dashboard,
        bookings: [
          { ...bookings[0], state: "canceled" },
          { ...bookings[1], starts_at: "2026-09-30T00:00:00Z" },
        ],
      },
      () => now,
    ).bookings,
    [],
  );
});

test("voice slots reject another host's event, unpublished events and unexpected fields", async () => {
  const host = await user(),
    other = await user();
  const own = await create(host),
    unpublished = await create(host, false),
    foreign = await create(other);
  for (const event_id of [foreign.id, unpublished.id, randomUUID()])
    await http("/voice/slots", host, { event_id, date: day() }, 400);
  await http(
    "/voice/slots",
    host,
    { event_id: own.id, date: "2026-02-30" },
    400,
  );
  await http(
    "/voice/slots",
    host,
    { event_id: own.id, date: day(), action: "cancel", confirmed: true },
    400,
  );
  await http(
    "/voice/slots",
    host,
    { event_id: own.id, date: day(), owner_id: other },
    400,
  );
});

test("voice slots honor bookings and fresh provider busy times without booking writes", async () => {
  const host = await user(),
    e = await create(host);
  await book(e, at(20, 10));
  await connect(host);
  calendarEvents = [
    {
      id: "busy_fixture",
      status: "confirmed",
      start: { dateTime: at(20, 11) },
      end: { dateTime: at(20, 12) },
    },
  ];
  const before = await scheduleSnapshot(),
    calls = providerCalls.length;
  const result = await http("/voice/slots", host, {
    event_id: e.id,
    date: day(20),
  });
  assert.equal(result.action, "slots");
  assert.equal(result.event_id, e.id);
  assert.equal(result.title, e.title);
  assert(result.slots.length > 0);
  assert(
    !result.slots.some(
      (s) => Date.parse(s.starts_at) === Date.parse(at(20, 10)),
    ),
  );
  assert(
    !result.slots.some(
      (s) =>
        Date.parse(s.starts_at) >= Date.parse(at(20, 11)) &&
        Date.parse(s.starts_at) < Date.parse(at(20, 12)),
    ),
  );
  assert(result.slots.every((s) => s.starts_local && s.ends_local));
  assert(providerCalls.length > calls);
  assert.deepEqual(await scheduleSnapshot(), before);
  calendarFailure = true;
  try {
    await http("/voice/slots", host, { event_id: e.id, date: day(21) }, 503);
  } finally {
    calendarFailure = false;
    calendarEvents = [];
  }
  assert.deepEqual(await scheduleSnapshot(), before);
});

test("canonical proposals remain owner-bound, review-only until confirmed and idempotent", async () => {
  const host = await user(),
    other = await user(),
    e = await create(host);
  const b = await book(e, at(30, 10));
  modelResult = {
    action: "reschedule",
    message: "Proposal",
    booking_id: b.id,
    starts_at: at(30, 12),
  };
  const { proposal } = await http("/ai/propose", host, {
    request_id: randomUUID(),
    prompt: "Move my appointment to noon",
  });
  assert.equal(proposal.state, "review");
  assert.equal(proposal.plan.title, e.title);
  assert.equal(
    proposal.plan.old_starts_local,
    schedulingLocalTime(b.starts_at, "UTC"),
  );
  assert.equal(
    proposal.plan.old_ends_local,
    schedulingLocalTime(b.ends_at, "UTC"),
  );
  assert.equal(
    proposal.plan.starts_local,
    schedulingLocalTime(at(30, 12), "UTC"),
  );
  assert.equal(
    proposal.plan.ends_local,
    schedulingLocalTime(proposal.plan.ends_at, "UTC"),
  );
  assert.equal(
    Date.parse(proposal.plan.ends_at) - Date.parse(proposal.plan.starts_at),
    1800000,
  );
  assert(!JSON.stringify(modelContext).includes("PRIVATE"));
  assert.equal(
    Date.parse((await owner(host, "booking_get", b.id)).starts_at),
    Date.parse(b.starts_at),
  );
  await http("/ai/" + proposal.id + "/apply", host, { confirmed: false }, 400);
  await http("/ai/" + proposal.id + "/apply", other, { confirmed: true }, 404);
  const first = await http("/ai/" + proposal.id + "/apply", host, {
    confirmed: true,
  });
  const repeat = await http("/ai/" + proposal.id + "/apply", host, {
    confirmed: true,
  });
  assert.deepEqual(repeat, first);
  assert.equal(
    Date.parse((await owner(host, "booking_get", b.id)).starts_at),
    Date.parse(at(30, 12)),
  );
  modelResult = { action: "cancel", message: "Proposal", booking_id: b.id };
  const cancellation = (
    await http("/ai/propose", host, {
      request_id: randomUUID(),
      prompt: "Cancel this appointment",
    })
  ).proposal;
  assert.equal(cancellation.plan.title, e.title);
  assert.equal(
    cancellation.plan.old_starts_local,
    schedulingLocalTime(at(30, 12), "UTC"),
  );
  assert.equal((await owner(host, "booking_get", b.id)).state, "confirmed");
});

test("team participants can read their appointment but cannot prepare organizer changes", async () => {
  const organizer = await user(),
    participant = await user(),
    e = await create(organizer);
  const b = await book(e, at(35));
  await db.query(
    "insert into korlix_schedule_booking_hosts(booking_id,host_id) values($1,$2)",
    [b.id, participant],
  );
  const context = await http("/voice/context", participant);
  assert.equal(context.bookings[0].id, b.id);
  assert.equal(context.bookings[0].is_organizer, false);
  modelResult = { action: "cancel", message: "Proposal", booking_id: b.id };
  const rejected = await http(
    "/ai/propose",
    participant,
    { request_id: randomUUID(), prompt: "Cancel my team appointment" },
    400,
  );
  assert.match(rejected.error, /Only the booking organizer/);
  assert.equal((await http("/voice/context", participant)).profile_ready, true);
  assert.equal(
    (await owner(organizer, "booking_get", b.id)).state,
    "confirmed",
  );
});

test("voice context shares the owner request limit without changing schedules", async () => {
  const host = await user();
  const before = await scheduleSnapshot();
  for (let i = 0; i < 180; i++) await http("/voice/context", host);
  await http("/voice/context", host, undefined, 429);
  await http(
    "/voice/slots",
    host,
    { event_id: randomUUID(), date: day() },
    429,
  );
  assert.deepEqual(await scheduleSnapshot(), before);
});

test("rescheduling uses the current host timezone after a timezone change", async () => {
  const host = await user(),
    e = await create(host),
    b = await book(e, at(40, 10));
  const { profile } = await owner(host, "dashboard");
  await owner(host, "save_profile", null, {
    revision: profile.revision,
    display_name: profile.display_name,
    timezone: "America/Los_Angeles",
    weekly: weekly.map((w) => ({ day: w.day, windows: [[1020, 1260]] })),
    overrides: [],
  });
  // 01:00 UTC is on the previous host-local date, which may differ from the
  // original booking snapshot's UTC timezone.
  modelResult = {
    action: "reschedule",
    message: "Proposal",
    booking_id: b.id,
    starts_at: at(41, 1),
  };
  const { proposal } = await http("/ai/propose", host, {
    request_id: randomUUID(),
    prompt: "Move my appointment to the selected local evening slot",
  });
  assert.equal(proposal.plan.timezone, "America/Los_Angeles");
  assert.equal(
    proposal.plan.starts_local,
    schedulingLocalTime(at(41, 1), "America/Los_Angeles"),
  );
  assert.equal(proposal.state, "review");
});
