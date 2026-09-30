import { createHash, randomBytes } from "node:crypto";

export class SchedulingError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}
export const fail = (message, status = 400) => {
  throw new SchedulingError(message, status);
};
export const hash = (value) => createHash("sha256").update(value).digest("hex");
export const secret = () => randomBytes(32).toString("hex");
export function uuid(value) {
  if (
    typeof value !== "string" ||
    !/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(
      value,
    )
  )
    fail("Invalid scheduling identifier.");
  return value.toLowerCase();
}
export function token(value) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value))
    fail("Reload your booking page to start a secure session.", 409);
  return value;
}
export function text(value, max = 100, required = true) {
  if (
    typeof value !== "string" ||
    value.length > max ||
    /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(value) ||
    (required && !value.trim())
  )
    fail("Review the text fields and their length.");
  return value.trim();
}
export function integer(value, min, max) {
  if (!Number.isSafeInteger(value) || value < min || value > max)
    fail(`Enter a whole number between ${min} and ${max}.`);
  return value;
}
export function zone(value) {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value }).format();
  } catch {
    fail("Choose a valid time zone.");
  }
  return text(value, 100);
}
export function date(value) {
  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(value) ||
    !Number.isFinite(Date.parse(value + "T00:00:00Z")) ||
    new Date(value + "T00:00:00Z").toISOString().slice(0, 10) !== value
  )
    fail("Choose a valid date.");
  return value;
}
export function instant(value) {
  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$/.test(
      value,
    ) ||
    !Number.isFinite(Date.parse(value))
  )
    fail("Choose a valid appointment time.");
  return new Date(value).toISOString();
}
export function object(value) {
  if (!value || typeof value !== "object" || Array.isArray(value))
    fail("Invalid scheduling request.");
  return value;
}
function keys(body, allowed) {
  object(body);
  if (Object.keys(body).some((k) => !allowed.includes(k)))
    fail("Unsupported scheduling field.");
}
function windows(value) {
  if (!Array.isArray(value) || value.length > 8)
    fail("Use up to eight time windows per day.");
  let end = 0;
  return value.map((w) => {
    if (!Array.isArray(w) || w.length !== 2) fail("Review your time windows.");
    const start = integer(w[0], 0, 1435),
      next = integer(w[1], 5, 1440);
    if (start < end || next <= start || start % 5 || next % 5)
      fail("Use ordered, non-overlapping time windows in five-minute steps.");
    end = next;
    return [start, next];
  });
}
export function profile(body) {
  keys(body, ["revision", "display_name", "timezone", "weekly", "overrides"]);
  if (
    !Array.isArray(body.weekly) ||
    body.weekly.length !== 7 ||
    new Set(body.weekly.map((w) => w.day)).size !== 7
  )
    fail("Set availability for each weekday.");
  if (!Array.isArray(body.overrides) || body.overrides.length > 60)
    fail("Use at most 60 date overrides.");
  const overrides = body.overrides.map((o) => ({
    date: date(o.date),
    windows: windows(o.windows),
  }));
  if (new Set(overrides.map((o) => o.date)).size !== overrides.length)
    fail("Use each override date once.");
  return {
    revision: integer(body.revision, 0, 1000000000),
    display_name: text(body.display_name),
    timezone: zone(body.timezone),
    weekly: body.weekly.map((w) => ({
      day: integer(w.day, 0, 6),
      windows: windows(w.windows),
    })),
    overrides,
  };
}
export function event(body) {
  const allowed = [
    "revision",
    "title",
    "description",
    "kind",
    "duration_minutes",
    "interval_minutes",
    "buffer_before",
    "buffer_after",
    "notice_minutes",
    "horizon_days",
    "daily_limit",
    "capacity",
    "cancel_notice_minutes",
    "location_kind",
    "location_detail",
    "questions",
    "color",
    "routing_mode",
    "team_id",
    "host_ids",
    "price_cents",
    "currency",
    "refund_policy",
  ];
  keys(body, allowed);
  const result = {
    revision: integer(body.revision, 0, 1000000000),
    title: text(body.title, 120),
    description: text(body.description, 2000, false),
    kind: body.kind,
    duration_minutes: integer(body.duration_minutes, 5, 480),
    interval_minutes: integer(body.interval_minutes, 5, 120),
    buffer_before: integer(body.buffer_before, 0, 120),
    buffer_after: integer(body.buffer_after, 0, 120),
    notice_minutes: integer(body.notice_minutes, 0, 10080),
    horizon_days: integer(body.horizon_days, 1, 365),
    daily_limit: integer(body.daily_limit, 1, 100),
    capacity: integer(body.capacity, 1, 100),
    cancel_notice_minutes: integer(body.cancel_notice_minutes, 0, 10080),
    location_kind: body.location_kind,
    location_detail: text(body.location_detail, 500, false),
    color: body.color,
  };
  result.routing_mode = body.routing_mode ?? "single";
  if (!["single", "round_robin", "collective"].includes(result.routing_mode))
    fail("Choose a supported host assignment.");
  result.team_id = result.routing_mode === "single" ? null : uuid(body.team_id);
  if (
    body.host_ids !== undefined &&
    (!Array.isArray(body.host_ids) || body.host_ids.length > 20)
  )
    fail("Choose up to twenty hosts.");
  result.host_ids =
    result.routing_mode === "single"
      ? []
      : [...new Set((body.host_ids || []).map(uuid))];
  if (
    result.routing_mode !== "single" &&
    (result.kind !== "one_to_one" || result.host_ids.length === 0)
  )
    fail("Choose active hosts for a one-to-one team event.");
  result.price_cents = integer(body.price_cents ?? 0, 0, 1000000);
  if (result.price_cents > 0 && result.price_cents < 50)
    fail("Paid bookings must cost at least $0.50 USD.");
  if (body.currency !== undefined && body.currency !== "usd")
    fail("Booking payments currently use USD.");
  result.currency = "usd";
  result.refund_policy = text(
    body.refund_policy ?? "Contact your host to request a refund.",
    1000,
  );
  if (
    !["one_to_one", "group"].includes(result.kind) ||
    (result.kind === "one_to_one" && result.capacity !== 1) ||
    result.duration_minutes % 5 ||
    result.interval_minutes % 5
  )
    fail("Review the meeting type, duration, interval and capacity.");
  if (
    !["video", "phone", "in_person", "custom"].includes(result.location_kind) ||
    !/^#[a-f\d]{6}$/i.test(result.color)
  )
    fail("Review the location and accent color.");
  if (result.location_kind === "video" && result.location_detail) {
    let url;
    try {
      url = new URL(result.location_detail);
    } catch {
      fail("Enter a complete HTTPS meeting link.");
    }
    if (url.protocol !== "https:" || url.username || url.password)
      fail("Use a secure HTTPS meeting link.");
  }
  if (!Array.isArray(body.questions) || body.questions.length > 6)
    fail("Use up to six booking questions.");
  result.questions = body.questions.map((q) => {
    keys(q, ["id", "label", "kind", "required", "options"]);
    if (
      !/^[a-z][a-z0-9_]{0,30}$/.test(q.id) ||
      !["text", "choice"].includes(q.kind) ||
      typeof q.required !== "boolean"
    )
      fail("Review the booking questions.");
    let options = [];
    if (q.kind === "choice") {
      if (
        !Array.isArray(q.options) ||
        q.options.length < 2 ||
        q.options.length > 12
      )
        fail("Use 2 to 12 choices.");
      options = q.options.map((o) => text(o, 100));
      if (new Set(options).size !== options.length)
        fail("Use distinct choices.");
    }
    return {
      id: q.id,
      label: text(q.label, 200),
      kind: q.kind,
      required: q.required,
      options,
    };
  });
  if (
    new Set(result.questions.map((q) => q.id)).size !== result.questions.length
  )
    fail("Use distinct question identifiers.");
  return result;
}
export function booking(body) {
  keys(body, [
    "context_token",
    "request_id",
    "manage_token",
    "starts_at",
    "guest_name",
    "guest_email",
    "guest_timezone",
    "answers",
    "confirmed",
    "website",
  ]);
  if (body.confirmed !== true || body.website)
    fail("Review and confirm your booking.");
  const email = text(body.guest_email, 254).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
    fail("Enter a valid email address.");
  const answers = {};
  for (const [key, value] of Object.entries(object(body.answers))) {
    if (!/^[a-z][a-z0-9_]{0,30}$/.test(key)) fail("Review your answers.");
    answers[key] = text(value, 1000, false);
  }
  if (Object.keys(answers).length > 6) fail("Review your answers.");
  const result = {
    request_id: uuid(body.request_id),
    manage_hash: hash(token(body.manage_token)),
    starts_at: instant(body.starts_at),
    guest_name: text(body.guest_name),
    guest_email: email,
    guest_timezone: zone(body.guest_timezone),
    answers: Object.fromEntries(
      Object.entries(answers).sort(([a], [b]) => a.localeCompare(b)),
    ),
    confirmed: true,
  };
  return { ...result, request_hash: hash(JSON.stringify(result)) };
}
const escapeICS = (value) =>
  String(value ?? "")
    .replace(/\\/g, "\\\\")
    .replace(/\r?\n/g, "\\n")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/[\x00-\x08\x0b-\x1f]/g, "");
const utcICS = (value) =>
  new Date(value).toISOString().replace(/[-:]/g, "").slice(0, 15) + "Z";
function fold(line) {
  const chunks = [];
  let part = "",
    bytes = 0;
  for (const c of line) {
    const n = Buffer.byteLength(c);
    if (bytes + n > 73) {
      chunks.push(part);
      part = " " + c;
      bytes = 1 + n;
    } else {
      part += c;
      bytes += n;
    }
  }
  chunks.push(part);
  return chunks.join("\r\n");
}
export function calendarFile(b, now = new Date()) {
  if (["awaiting_payment", "payment_failed"].includes(b.state))
    fail("A confirmed appointment is required for a calendar file.", 409);
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//KORLIX//Scheduling//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "BEGIN:VEVENT",
    `UID:${b.id}@korlixdeveloper.com`,
    `DTSTAMP:${utcICS(now)}`,
    `DTSTART:${utcICS(b.starts_at)}`,
    `DTEND:${utcICS(b.ends_at)}`,
    `SEQUENCE:${b.revision}`,
    `STATUS:${b.state === "canceled" ? "CANCELLED" : "CONFIRMED"}`,
    `SUMMARY:${escapeICS(b.snapshot.title)}`,
    `DESCRIPTION:${escapeICS(b.snapshot.description + "\nHost: " + b.snapshot.host_name)}`,
    `LOCATION:${escapeICS(b.snapshot.location_detail)}`,
    "END:VEVENT",
    "END:VCALENDAR",
  ];
  return lines.map(fold).join("\r\n") + "\r\n";
}
export function bookingCsv(items) {
  const cell = (v) =>
    '"' +
    (/^[\s]*[=+\-@]/.test(String(v ?? "")) ? "'" : "") +
    String(v ?? "").replace(/"/g, '""') +
    '"';
  return (
    "\uFEFF" +
    [
      [
        "Meeting",
        "Guest",
        "Email",
        "Start UTC",
        "End UTC",
        "Guest time zone",
        "Status",
      ],
      ...items.map((b) => [
        b.snapshot.title,
        b.guest_name,
        b.guest_email,
        b.starts_at,
        b.ends_at,
        b.guest_timezone,
        b.state,
      ]),
    ]
      .map((r) => r.map(cell).join(","))
      .join("\r\n")
  );
}
