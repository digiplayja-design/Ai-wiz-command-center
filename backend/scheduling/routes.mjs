import express from "express";
import { schedulingNotifications } from "./notifications.mjs";
import { fileURLToPath } from "node:url";
import {
  SchedulingError,
  fail,
  hash,
  secret,
  token,
  uuid,
  text,
  integer,
  zone,
  date,
  instant,
  object,
  profile,
  event,
  booking,
  calendarFile,
  bookingCsv,
} from "./core.mjs";

export function registerScheduling(
  app,
  {
    database,
    requireUser,
    environment = process.env,
    now = Date.now,
    autoStartWorker = true,
    fetcher = fetch,
  } = {},
) {
  const base = "/api/scheduling",
    publicRoot = (
      environment.KORLIX_SCHEDULING_PUBLIC_URL ||
      "https://chee-chai-chee-backend.onrender.com"
    ).replace(/\/$/, "");
  const cookieName = "korlix_sched_browser",
    buckets = new Map(),
    salt = secret();
  const notifications = schedulingNotifications({
    database,
    environment,
    publicRoot,
    autoStart: autoStartWorker,
    fetcher,
  });
  const capability = {
    calendar_sync: false,
    automatic_email: notifications.ready,
    sms: false,
    payments: false,
    team_scheduling: false,
    booking_types: ["one_to_one", "group"],
    conflict_scope: "KORLIX bookings and manual time blocks",
  };
  async function call(name, args) {
    if (!database) fail("Scheduling is temporarily unavailable.", 503);
    const r = await database.rpc(name, args);
    if (r.error) {
      const status = {
        P0001: 400,
        23514: 400,
        23502: 400,
        22007: 400,
        22008: 400,
        "22P02": 400,
        P0002: 404,
        42501: 403,
        40001: 409,
        23505: 409,
        54000: 429,
      }[r.error.code];
      fail(
        ["P0001", "P0002", "42501", "40001", "54000"].includes(r.error.code)
          ? r.error.message
          : status === 409
            ? "This request is already being handled. Refresh before retrying."
            : status === 400
              ? "Review the scheduling fields."
              : "Scheduling could not confirm this request. Refresh before retrying.",
        status || 503,
      );
    }
    return r.data;
  }
  const ownerCall = (u, action, id = null, data = {}) =>
    call("korlix_schedule_owner_v1", {
      p_actor: u,
      p_action: action,
      p_id: id,
      p_data: data,
    });
  const publicCall = (action, slug = null, data = {}) =>
    call("korlix_schedule_public_v1", {
      p_action: action,
      p_slug: slug,
      p_data: data,
    });
  const headers = (r) =>
    r.set({
      "Cache-Control": "no-store",
      Pragma: "no-cache",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
    });
  function rate(key, limit) {
    const t = now(),
      bucket = buckets.get(key);
    if (!bucket || bucket.until < t) {
      if (buckets.size > 5000)
        for (const [k, v] of buckets) if (v.until < t) buckets.delete(k);
      if (buckets.size > 6000)
        fail("Scheduling is busy. Try again shortly.", 429);
      buckets.set(key, { count: 1, until: t + 60000 });
    } else if (++bucket.count > limit)
      fail("Too many requests. Try again shortly.", 429);
  }
  const route =
    (fn, owner = false) =>
    async (q, r) => {
      headers(r);
      try {
        if (
          q.method === "POST" &&
          (!q.body ||
            Array.isArray(q.body) ||
            JSON.stringify(q.body).length > 24000)
        )
          fail("Invalid scheduling request.");
        let user;
        if (owner) {
          try {
            user = await requireUser(q);
          } catch {}
          if (!user?.id || user.is_anonymous || !user.email_confirmed_at)
            fail(
              "Sign in with a verified KORLIX account to use Scheduling.",
              401,
            );
          rate("owner:" + user.id, 180);
        } else {
          rate(
            "public:" +
              hash(salt + (q.ip || q.socket?.remoteAddress || "unknown")),
            240,
          );
          if (q.method === "POST") {
            const origin = q.get("origin");
            const accepted = new Set([
              new URL(publicRoot).origin,
              "https://www.korlixdeveloper.com",
              "https://korlixdeveloper.com",
            ]);
            if (origin && !accepted.has(origin))
              fail("Open the original KORLIX booking page to continue.", 403);
            if (q.get("sec-fetch-site") === "cross-site" && !origin)
              fail("Open the original KORLIX booking page to continue.", 403);
          }
        }
        await fn(q, r, user);
      } catch (e) {
        r.status(e instanceof SchedulingError ? e.status : 503).json({
          error:
            e instanceof SchedulingError
              ? e.message
              : "Scheduling is temporarily unavailable. Refresh before retrying.",
        });
      }
    };
  const link = (e) => ({ ...e, url: `${publicRoot}/book/${e.slug}` });
  app.get(
    base,
    route(async (_q, r, u) => {
      const d = await ownerCall(u.id, "dashboard");
      r.json({
        ...d,
        events: d.events.map(link),
        capabilities: capability,
        timezones: ["UTC", ...Intl.supportedValuesOf("timeZone")],
      });
    }, true),
  );
  app.post(
    base + "/profile",
    route(
      async (q, r, u) =>
        r.json({
          profile: await ownerCall(u.id, "save_profile", null, profile(q.body)),
        }),
      true,
    ),
  );
  app.post(
    base + "/notifications",
    route(async (q, r, u) => {
      object(q.body, ["enabled", "reminder_minutes", "confirmed", "revision"]);
      if (q.body.enabled !== true && q.body.enabled !== false)
        fail("Choose an email setting.");
      if (q.body.enabled && !notifications.ready)
        fail("Booking email is not configured yet.", 503);
      const minutes = integer(q.body.reminder_minutes, 0, 1440);
      if (![0, 15, 30, 60, 1440].includes(minutes))
        fail("Choose a reminder time.");
      r.json(
        await ownerCall(u.id, "notifications", null, {
          enabled: q.body.enabled,
          reminder_minutes: minutes,
          confirmed: q.body.confirmed === true,
          revision: integer(q.body.revision, 1, 1e9),
          verified_email: u.email,
        }),
      );
    }, true),
  );
  app.post(
    base + "/events",
    route(async (q, r, u) => {
      const d = event(q.body);
      d.slug =
        (d.title
          .toLowerCase()
          .replace(/[^a-z0-9]+/g, "-")
          .replace(/^-|-$/g, "")
          .slice(0, 45) || "meeting") +
        "-" +
        secret().slice(0, 16);
      r.status(201).json({
        event: link(await ownerCall(u.id, "save_event", null, d)),
      });
    }, true),
  );
  app.post(
    base + "/events/:id",
    route(
      async (q, r, u) =>
        r.json({
          event: link(
            await ownerCall(
              u.id,
              "save_event",
              uuid(q.params.id),
              event(q.body),
            ),
          ),
        }),
      true,
    ),
  );
  app.post(
    base + "/events/:id/state",
    route(
      async (q, r, u) =>
        r.json({
          event: link(
            await ownerCall(u.id, "event_state", uuid(q.params.id), {
              state: q.body.state,
              revision: integer(q.body.revision, 1, 1e9),
              confirmed: q.body.confirmed === true,
            }),
          ),
        }),
      true,
    ),
  );
  app.post(
    base + "/blocks",
    route(async (q, r, u) => {
      r.status(201).json(
        await ownerCall(u.id, "add_block", null, {
          starts_at: instant(q.body.starts_at),
          ends_at: instant(q.body.ends_at),
          label: text(q.body.label, 120),
        }),
      );
    }, true),
  );
  app.post(
    base + "/blocks/:id/remove",
    route(async (q, r, u) => {
      r.json(
        await ownerCall(u.id, "remove_block", uuid(q.params.id), {
          confirmed: q.body.confirmed === true,
        }),
      );
    }, true),
  );
  app.post(
    base + "/bookings/:id/state",
    route(async (q, r, u) => {
      r.json({
        booking: await ownerCall(u.id, "booking_state", uuid(q.params.id), {
          state: q.body.state,
          revision: integer(q.body.revision, 1, 1e9),
          confirmed: q.body.confirmed === true,
        }),
      });
    }, true),
  );
  app.get(
    base + "/bookings/:id/calendar",
    route(async (q, r, u) => {
      r.json({
        filename: "KORLIX-appointment.ics",
        calendar: calendarFile(
          await ownerCall(u.id, "booking_get", uuid(q.params.id)),
        ),
      });
    }, true),
  );
  app.get(
    base + "/export",
    route(async (_q, r, u) => {
      r.json({
        filename: "KORLIX-Bookings.csv",
        csv: bookingCsv((await ownerCall(u.id, "dashboard")).bookings),
      });
    }, true),
  );
  function browser(q) {
    const raw = (q.get("cookie") || "")
      .split(";")
      .map((s) => s.trim())
      .find((s) => s.startsWith(cookieName + "="))
      ?.slice(cookieName.length + 1);
    return raw && /^[a-f0-9]{64}$/.test(raw) ? raw : null;
  }
  function context(q) {
    const b = browser(q);
    if (!b) fail("Allow this site’s booking cookie and reload the page.", 409);
    return {
      token_hash: hash(token(q.body.context_token)),
      browser_hash: hash(b),
    };
  }
  function slug(q) {
    const value = q.params.slug;
    if (!/^[a-z0-9][a-z0-9-]{5,79}$/.test(value))
      fail("Booking page not found.", 404);
    return value;
  }
  app.post(
    base + "/public/:slug/context",
    route(async (q, r) => {
      const b = browser(q) || secret(),
        c = secret();
      const d = await publicCall("context", slug(q), {
        browser_hash: hash(b),
        token_hash: hash(c),
      });
      r.cookie(cookieName, b, {
        httpOnly: true,
        secure: environment.NODE_ENV !== "test",
        sameSite: "lax",
        maxAge: 24 * 3600000,
        path: "/api/scheduling/public",
      });
      r.json({
        ...d,
        context_token: c,
        notifications: {
          email: d.email_enabled && notifications.ready,
          sms: false,
        },
        calendar_sync: false,
      });
    }),
  );
  app.post(
    base + "/public/:slug/slots",
    route(async (q, r) =>
      r.json(
        await publicCall("slots", slug(q), {
          ...context(q),
          date: date(q.body.date),
        }),
      ),
    ),
  );
  app.post(
    base + "/public/:slug/book",
    route(async (q, r) => {
      const d = booking(q.body);
      r.status(201).json({
        booking: await publicCall("book", slug(q), {
          ...d,
          ...context(q),
          sealed_manage_token: notifications.seal(
            q.body.manage_token,
            d.request_id,
          ),
        }),
      });
    }),
  );
  function manage(q) {
    return {
      booking_id: uuid(q.body.booking_id),
      manage_hash: hash(token(q.body.manage_token)),
    };
  }
  app.post(
    base + "/manage",
    route(async (q, r) =>
      r.json({ booking: await publicCall("manage", null, manage(q)) }),
    ),
  );
  app.post(
    base + "/manage/slots",
    route(async (q, r) =>
      r.json(
        await publicCall("manage_slots", null, {
          ...manage(q),
          date: date(q.body.date),
        }),
      ),
    ),
  );
  app.post(
    base + "/manage/calendar",
    route(async (q, r) =>
      r.json({
        filename: "KORLIX-appointment.ics",
        calendar: calendarFile(await publicCall("manage", null, manage(q))),
      }),
    ),
  );
  for (const action of ["cancel", "reschedule"])
    app.post(
      base + "/manage/" + action,
      route(async (q, r) =>
        r.json({
          booking: await publicCall(action, null, {
            ...manage(q),
            revision: integer(q.body.revision, 1, 1e9),
            confirmed: q.body.confirmed === true,
            ...(action === "reschedule"
              ? {
                  starts_at: instant(q.body.starts_at),
                  event_revision: integer(q.body.event_revision, 1, 1e9),
                }
              : {}),
          }),
        }),
      ),
    );
  const directory = fileURLToPath(new URL("./public/", import.meta.url));
  app.use(
    "/book/assets",
    express.static(directory, {
      index: false,
      fallthrough: false,
      maxAge: "1h",
      setHeaders: (r) =>
        r.set({
          "X-Content-Type-Options": "nosniff",
          "Referrer-Policy": "no-referrer",
        }),
    }),
  );
  app.get("/book/:slug", (_q, r) => {
    headers(r);
    r.set({
      "Content-Security-Policy":
        "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' https://www.korlixdeveloper.com; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'self' https://www.korlixdeveloper.com https://korlixdeveloper.com",
      "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
    });
    r.sendFile(directory + "index.html");
  });
  return { ownerCall, publicCall, notifications };
}
