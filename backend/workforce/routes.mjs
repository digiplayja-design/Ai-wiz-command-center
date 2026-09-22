import { randomBytes, randomUUID } from "node:crypto";
import {
  WorkforceError,
  fail,
  id,
  text,
  integer,
  policy,
  location,
  evidenceFlags,
  enrichSnapshot,
  timesheetCsv,
  dailyBrief,
  tokenHash,
} from "./core.mjs";
import { createWorkforceStore } from "./store.mjs";
import {
  createKorlixAgentEmailDraftService,
  createKorlixAgentEmailSupabaseStore,
} from "../korlix_agent_email_routes.mjs";
import { korlixAgentEmailNovaBinding } from "../korlix_agent_email.mjs";

const timestamp = (v) => {
  const n = Date.parse(v);
  if (!Number.isFinite(n)) fail("Enter a valid date and time.");
  return new Date(n).toISOString();
};
function payload(action, p = {}) {
  switch (action) {
    case "policy":
      return {
        version: integer(p.version, 1, 2147483646),
        policy: policy(p.policy),
      };
    case "invite": {
      const email = text(p.email, 254, true).toLowerCase();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
        fail("Enter the employee’s email address.");
      if (!["manager", "employee"].includes(p.role))
        fail("Choose employee or manager.");
      return {
        email,
        display_name: text(p.display_name, 100, true),
        role: p.role,
      };
    }
    case "member":
      if (
        !["manager", "employee"].includes(p.role) ||
        typeof p.active !== "boolean"
      )
        fail("Choose valid member settings.");
      return {
        user_id: id(p.user_id),
        version: integer(p.version, 1, 2147483646),
        role: p.role,
        active: p.active,
        team: text(p.team, 100),
        policy_override:
          p.policy_override == null ? null : policy(p.policy_override),
      };
    case "update":
      return {
        request_id: id(p.request_id),
        shift_id: id(p.shift_id),
        summary: text(p.summary, 2000, true),
        blockers: text(p.blockers, 1000),
        project: text(p.project, 100),
        quantity: integer(p.quantity, 0, 100000),
      };
    case "correction":
      return {
        shift_id: p.shift_id ? id(p.shift_id) : null,
        proposed_start: timestamp(p.proposed_start),
        proposed_end: timestamp(p.proposed_end),
        break_minutes: integer(p.break_minutes, 0, 1439),
        reason: text(p.reason, 1000, true),
      };
    case "review_correction":
      if (!["approved", "rejected"].includes(p.decision))
        fail("Choose approve or reject.");
      return {
        id: id(p.id),
        decision: p.decision,
        review_note: text(p.review_note, 1000, true),
      };
    case "approve_shift":
    case "cancel_schedule":
      return { id: id(p.id), version: integer(p.version, 1, 2147483646) };
    case "revoke_invite":
      return { id: id(p.id) };
    case "schedule":
      return {
        user_id: id(p.user_id),
        starts_at: timestamp(p.starts_at),
        ends_at: timestamp(p.ends_at),
        worksite: text(p.worksite, 100, true),
        notes: text(p.notes, 1000),
      };
    default:
      fail("Choose a supported Workforce action.");
  }
}
export function registerWorkforce(
  app,
  {
    database,
    requireUser,
    loadAgentProfile,
    environment = process.env,
    store,
    emailService,
    now = Date.now,
    normalizePhoto,
  } = {},
) {
  const persistence =
      store || (database ? createWorkforceStore(database) : null),
    limits = new Map();
  const binding = korlixAgentEmailNovaBinding(environment);
  const email =
    emailService ||
    (database
      ? createKorlixAgentEmailDraftService({
          environment,
          store: createKorlixAgentEmailSupabaseStore(database),
          loadAgentProfile,
          providerSendPathImplemented: true,
          autopilotExecutionImplemented: true,
          webhookEventsImplemented: true,
        })
      : null);
  const wrap = (fn) => async (req, res) => {
    res.set("Cache-Control", "no-store");
    try {
      let user;
      try {
        user = await requireUser(req);
      } catch {
        fail("Sign in to use Workforce.", 401, "WORKFORCE_AUTH_REQUIRED");
      }
      if (!user?.id)
        fail("Sign in to use Workforce.", 401, "WORKFORCE_AUTH_REQUIRED");
      if (!persistence)
        fail("Workforce is not configured.", 503, "WORKFORCE_UNAVAILABLE");
      if (req.method !== "GET") {
        const current = limits.get(user.id) || { at: now(), n: 0 };
        if (now() - current.at > 60000) {
          current.at = now();
          current.n = 0;
        }
        if (++current.n > 60)
          fail(
            "Please wait a moment before trying again.",
            429,
            "WORKFORCE_RATE_LIMIT",
          );
        if (limits.size > 10000)
          for (const [key, v] of limits)
            if (now() - v.at > 60000) limits.delete(key);
        limits.set(user.id, current);
      }
      await fn(req, res, user);
    } catch (e) {
      const known =
        e instanceof WorkforceError || e.code?.startsWith("agent_email_");
      res
        .status(known ? e.status || e.statusCode || 400 : 503)
        .json({
          error: known
            ? e.message
            : "Workforce could not complete this request. Please retry.",
          code: known ? e.code : "WORKFORCE_UNAVAILABLE",
        });
    }
  };
  const run = (u, a, o, p) => persistence.command(u.id, u.email || "", a, o, p);
  const snapshot = async (u, o, q = {}) => {
    for (const k of ["from", "to"])
      if (q[k] && !/^\d{4}-\d{2}-\d{2}$/.test(q[k]))
        fail("Choose valid report dates.");
    const data = enrichSnapshot(
      await run(u, "snapshot", o, { from: q.from || null, to: q.to || null }),
      now(),
    );
    data.email_agent_id =
      binding.configured && binding.ownerUid === u.id ? binding.agentId : null;
    data.outbound_calling_enabled = false;
    return data;
  };
  const base = "/api/workforce";
  app.get(
    base + "/workspaces",
    wrap(async (req, res, u) => res.json(await run(u, "workspaces", null, {}))),
  );
  app.post(
    base + "/workspaces",
    wrap(async (req, res, u) =>
      res
        .status(201)
        .json(
          await run(u, "create", null, {
            name: text(req.body?.name, 100, true),
            display_name: text(req.body?.display_name, 100, true),
            timezone: text(req.body?.timezone, 80, true),
          }),
        ),
    ),
  );
  app.post(
    base + "/accept-invite",
    wrap(async (req, res, u) => {
      if (!u.email_confirmed_at && !u.confirmed_at)
        fail(
          "Verify your account email before joining a workspace.",
          403,
          "WORKFORCE_EMAIL_UNVERIFIED",
        );
      const token = text(req.body?.token, 128, true);
      if (!/^[a-zA-Z0-9_-]{32,128}$/.test(token))
        fail("Enter a valid invitation code.");
      res.json(await run(u, "accept", null, { token_hash: tokenHash(token) }));
    }),
  );
  app.get(
    base + "/:org",
    wrap(async (req, res, u) =>
      res.json(await snapshot(u, id(req.params.org), req.query)),
    ),
  );
  app.get(
    base + "/:org/audit",
    wrap(async (req, res, u) =>
      res.json(await run(u, "audit", id(req.params.org), {})),
    ),
  );
  app.post(
    base + "/:org/commands",
    wrap(async (req, res, u) => {
      const action = req.body?.action,
        p = payload(action, req.body?.payload),
        org = id(req.params.org);
      let token;
      if (action === "invite") {
        token = randomBytes(32).toString("base64url");
        p.token_hash = tokenHash(token);
      }
      const result = await run(u, action, org, p);
      res.json(
        token ? { ...result, invitation_code: token, sent: false } : result,
      );
    }),
  );
  app.post(
    base + "/:org/punch",
    wrap(async (req, res, u) => {
      const org = id(req.params.org),
        p = req.body || {},
        action = p.action;
      if (
        !["clock_in", "start_break", "end_break", "clock_out"].includes(action)
      )
        fail("Choose a valid attendance action.");
      const data = await snapshot(u, org),
        active = data.shifts.find(
          (s) => s.user_id === u.id && s.state !== "ended",
        );
      const pol =
        action === "clock_in"
          ? data.policy
          : active?.policy_snapshot || data.policy;
      const request_id = id(p.request_id),
        exception_reason = text(p.exception_reason, 1000),
        client_time = timestamp(p.client_time);
      if (action !== "clock_in") integer(p.version, 1, 2147483646);
      const capture = action === "clock_in" || action === "clock_out";
      const loc = capture ? location(p.location, now()) : null;
      let bytes = null,
        path = null;
      if (capture && p.selfie) {
        if (p.capture_confirmed !== true)
          fail("Review the attendance photo before submitting.");
        if (
          typeof p.selfie !== "string" ||
          p.selfie.length > 2800000 ||
          !/^[A-Za-z0-9+/]+={0,2}$/.test(p.selfie)
        )
          fail("Choose an attendance photo smaller than 2 MB.");
        const input = Buffer.from(p.selfie, "base64");
        if (normalizePhoto) bytes = await normalizePhoto(input);
        else {
          const { default: sharp } = await import("sharp");
          try {
            bytes = await sharp(input, {
              limitInputPixels: 20000000,
              failOn: "error",
            })
              .rotate()
              .resize(800, 800, { fit: "inside", withoutEnlargement: true })
              .jpeg({ quality: 75 })
              .toBuffer();
          } catch {
            fail("The attendance photo could not be read.");
          }
        }
        if (bytes.length > 524288)
          fail("The attendance photo is too large. Retake it.");
      }
      const flags = capture ? evidenceFlags(pol, loc, !!bytes) : [];
      if (Math.abs(now() - Date.parse(client_time)) > 180000)
        flags.push("Device timestamp differs from server time");
      if (flags.length && action === "clock_in" && exception_reason.length < 5)
        fail(
          "Retake the required evidence or explain the exception for manager review.",
          400,
          "WORKFORCE_EVIDENCE_REQUIRED",
        );
      // Clock-out is always recordable: missing evidence is flagged for review, not lost work time.
      if (bytes) {
        path = `${org}/${u.id}/${randomUUID()}.jpg`;
        await persistence.upload(path, bytes);
      }
      try {
        const result = await run(u, action, org, {
          request_id,
          version: p.version || 1,
          policy_version: data.organization.version,
          member_version: data.member.version,
          client_time,
          location: loc,
          photo_path: path,
          flags,
          exception_reason,
        });
        if (result.replayed && path)
          await persistence.remove(path).catch(() => {});
        res.json(result);
      } catch (e) {
        if (path && e instanceof WorkforceError && e.status < 500)
          await persistence.remove(path).catch(() => {});
        throw e;
      }
    }),
  );
  app.get(
    base + "/:org/photos/:event",
    wrap(async (req, res, u) => {
      const result = await run(u, "evidence", id(req.params.org), {
        id: id(req.params.event),
      });
      res.set("Content-Type", "image/jpeg");
      res.set("X-Content-Type-Options", "nosniff");
      res.send(await persistence.photo(result.path));
    }),
  );
  app.get(
    base + "/:org/export",
    wrap(async (req, res, u) => {
      const data = await snapshot(u, id(req.params.org), req.query);
      res.set("Content-Type", "text/csv; charset=utf-8");
      res.set(
        "Content-Disposition",
        'attachment; filename="korlix-timesheets.csv"',
      );
      res.send(timesheetCsv(data));
    }),
  );
  app.get(
    base + "/:org/brief",
    wrap(async (req, res, u) => {
      const data = await snapshot(u, id(req.params.org), req.query);
      if (data.member.role === "employee")
        fail("Manager access required.", 403, "WORKFORCE_ROLE_REQUIRED");
      res.json({
        text: dailyBrief(data),
        sent: false,
        outbound_calling_enabled: false,
      });
    }),
  );
  app.get(
    base + "/:org/email-recipients",
    wrap(async (req, res, u) => {
      const data = await snapshot(u, id(req.params.org));
      if (data.member.role !== "owner")
        fail(
          "Workspace owner access required.",
          403,
          "WORKFORCE_ROLE_REQUIRED",
        );
      if (!email || !data.email_agent_id)
        fail(
          "Connect this owner’s NOVA Email Center first.",
          409,
          "WORKFORCE_EMAIL_UNAVAILABLE",
        );
      res.json(
        await email.listRecipients({
          userId: u.id,
          agentId: data.email_agent_id,
          limit: 100,
        }),
      );
    }),
  );
  app.post(
    base + "/:org/email-draft",
    wrap(async (req, res, u) => {
      const data = await snapshot(u, id(req.params.org), req.body || {});
      if (data.member.role !== "owner")
        fail(
          "Workspace owner access required.",
          403,
          "WORKFORCE_ROLE_REQUIRED",
        );
      if (req.body?.confirmed !== true)
        fail("Review the report and destination before preparing an email.");
      if (!email || !data.email_agent_id)
        fail(
          "Connect this owner’s NOVA Email Center first.",
          409,
          "WORKFORCE_EMAIL_UNAVAILABLE",
        );
      const result = await email.createDraft({
        userId: u.id,
        agentId: data.email_agent_id,
        body: {
          recipientId: id(req.body.recipient_id),
          subject: `${data.organization.name} — Workforce report`,
          textBody: dailyBrief(data),
          marketing: false,
          idempotencyKey: "workforce:" + id(req.body.request_id),
        },
      });
      res.json({ ...result, sent: false });
    }),
  );
  const purgeTimer =
    database && !store
      ? setInterval(() => persistence.purge().catch(() => {}), 3600000)
      : null;
  purgeTimer?.unref?.();
  return { close: () => clearInterval(purgeTimer) };
}
