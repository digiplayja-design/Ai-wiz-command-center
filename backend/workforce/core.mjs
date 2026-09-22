import { randomUUID, createHash } from "node:crypto";

export class WorkforceError extends Error {
  constructor(message, status = 400, code = "WORKFORCE_INVALID") {
    super(message);
    Object.assign(this, { status, code });
  }
}
export function fail(message, status, code) {
  throw new WorkforceError(message, status, code);
}
export const id = (v) => {
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      String(v),
    )
  )
    fail("Choose a valid record.");
  return v;
};
export function text(v, max = 500, required = false) {
  if (v != null && typeof v !== "string") fail("Enter text in this field.");
  const s = (v || "").trim();
  if (s.length > max || (required && !s))
    fail(`Enter ${required ? "1–" : "at most "}${max} characters.`);
  return s;
}
export function integer(v, min, max) {
  if (!Number.isSafeInteger(v) || v < min || v > max)
    fail(`Enter a whole number from ${min} to ${max}.`);
  return v;
}
export const tokenHash = (v) =>
  createHash("sha256").update(String(v)).digest("hex");
export const requestId = () => randomUUID();
export const defaults = Object.freeze({
  require_selfie: false,
  require_location: false,
  hourly_updates: false,
  interval_minutes: 60,
  grace_minutes: 10,
  retention_days: 30,
  worksite: "Main worksite",
  latitude: null,
  longitude: null,
  radius_m: 200,
  daily_goal: 10,
  output_unit: "tasks",
});
export function policy(input = {}) {
  const p = { ...defaults, ...input };
  for (const k of ["require_selfie", "require_location", "hourly_updates"])
    if (typeof p[k] !== "boolean") fail("Choose a valid policy setting.");
  p.interval_minutes = integer(p.interval_minutes, 15, 240);
  p.grace_minutes = integer(p.grace_minutes, 0, 60);
  p.retention_days = integer(p.retention_days, 7, 90);
  p.radius_m = integer(p.radius_m, 50, 5000);
  p.daily_goal = integer(p.daily_goal, 1, 100000);
  p.worksite = text(p.worksite, 100, true);
  p.output_unit = text(p.output_unit, 40, true);
  for (const [k, max] of [
    ["latitude", 90],
    ["longitude", 180],
  ])
    if (
      p[k] !== null &&
      (typeof p[k] !== "number" ||
        !Number.isFinite(p[k]) ||
        Math.abs(p[k]) > max)
    )
      fail("Enter valid worksite coordinates.");
  if ((p.latitude === null) !== (p.longitude === null))
    fail("Provide both worksite coordinates.");
  return Object.fromEntries(Object.keys(defaults).map((k) => [k, p[k]]));
}
export function location(v, now = Date.now()) {
  if (v == null) return null;
  for (const [k, min, max] of [
    ["latitude", -90, 90],
    ["longitude", -180, 180],
    ["accuracy", 0, 100000],
  ])
    if (
      typeof v[k] !== "number" ||
      !Number.isFinite(v[k]) ||
      v[k] < min ||
      v[k] > max
    )
      fail("Location is unavailable. Try capturing it again.");
  const at = Date.parse(v.captured_at);
  if (!Number.isFinite(at) || Math.abs(now - at) > 180000)
    fail("Capture a fresh location before submitting.");
  return {
    latitude: v.latitude,
    longitude: v.longitude,
    accuracy: v.accuracy,
    captured_at: new Date(at).toISOString(),
  };
}
export function distanceMetres(a, b) {
  const rad = (v) => (v * Math.PI) / 180,
    dLat = rad(b.latitude - a.latitude),
    dLon = rad(b.longitude - a.longitude);
  const n =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.latitude)) *
      Math.cos(rad(b.latitude)) *
      Math.sin(dLon / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(n), Math.sqrt(Math.max(0, 1 - n)));
}
export function evidenceFlags(p, loc, hasPhoto) {
  const issues = [];
  if (p.require_selfie && !hasPhoto) issues.push("Selfie missing");
  if (p.require_location && !loc) issues.push("Location missing");
  if (loc && p.require_location && loc.accuracy > 100)
    issues.push("Location accuracy needs review");
  if (
    loc &&
    p.require_location &&
    p.latitude != null &&
    distanceMetres(p, loc) > p.radius_m + loc.accuracy
  )
    issues.push("Outside worksite area");
  return issues;
}
export function shiftSeconds(s, now = Date.now()) {
  const elapsed = Math.max(
    0,
    Math.floor(
      (Math.min(now, s.clock_out ? Date.parse(s.clock_out) : now) -
        Date.parse(s.segment_start)) /
        1000,
    ),
  );
  const raw = Math.max(
    0,
    Number(s.worked_seconds || 0) + (s.state === "working" ? elapsed : 0),
  );
  const breaks =
    Number(s.break_seconds || 0) + (s.state === "break" ? elapsed : 0);
  const adjusted =
    s.approved_start && s.approved_end
      ? Math.max(
          0,
          Math.round(
            (Date.parse(s.approved_end) - Date.parse(s.approved_start)) / 1000,
          ) -
            Number(s.approved_break_minutes || 0) * 60,
        )
      : null;
  return {
    worked_seconds: adjusted ?? raw,
    raw_worked_seconds: raw,
    break_seconds:
      adjusted == null ? breaks : Number(s.approved_break_minutes || 0) * 60,
  };
}
export function enrichSnapshot(data, now = Date.now()) {
  const shifts = (data.shifts || []).map((s) => {
    const times = shiftSeconds(s, now),
      p = s.policy_snapshot || defaults;
    const last = (data.updates || [])
      .filter((u) => u.shift_id === s.id)
      .reduce((n, u) => Math.max(n, u.worked_seconds_at_submit || 0), 0);
    return {
      ...s,
      ...times,
      update_due:
        p.hourly_updates &&
        s.state === "working" &&
        times.raw_worked_seconds - last >=
          (p.interval_minutes + p.grace_minutes) * 60,
      next_update_seconds: Math.max(
        0,
        p.interval_minutes * 60 - (times.raw_worked_seconds - last),
      ),
    };
  });
  const periodUpdates = (data.updates || []).filter(
    (u) =>
      !data.period_start ||
      (Date.parse(u.created_at) >= Date.parse(data.period_start) &&
        Date.parse(u.created_at) < Date.parse(data.period_end)),
  );
  const reportShifts = shifts.filter(
    (s) =>
      !data.period_start ||
      (Date.parse(s.approved_start || s.clock_in) <
        Date.parse(data.period_end) &&
        (s.approved_end || s.clock_out
          ? Date.parse(s.approved_end || s.clock_out)
          : now) > Date.parse(data.period_start)),
  );
  const units = {};
  for (const u of periodUpdates)
    units[u.output_unit] = (units[u.output_unit] || 0) + u.quantity;
  return {
    ...data,
    period_updates: periodUpdates,
    report_shifts: reportShifts,
    server_now: new Date(now).toISOString(),
    shifts,
    metrics: {
      working: shifts.filter((s) => s.state === "working").length,
      on_break: shifts.filter((s) => s.state === "break").length,
      updates_due: shifts.filter((s) => s.update_due).length,
      output: units,
      worked_seconds: reportShifts.reduce((n, s) => n + s.worked_seconds, 0),
    },
  };
}
export function csvCell(v) {
  const s = String(v ?? "");
  return (
    '"' +
    (/^(?:\s*[=+\-@]|[\t\r])/.test(s) ? "'" : "") +
    s.replaceAll('"', '""') +
    '"'
  );
}
export function timesheetCsv(data) {
  const names = new Map(
    (data.members || []).map((m) => [m.user_id, m.display_name]),
  );
  return [
    [
      "Employee",
      "Clock in (UTC)",
      "Clock out (UTC)",
      "Worked hours",
      "Break minutes",
      "Status",
      "Review",
      "Corrected",
    ]
      .map(csvCell)
      .join(","),
    ...(data.report_shifts || data.shifts).map((s) =>
      [
        names.get(s.user_id) || s.user_id,
        s.approved_start || s.clock_in,
        s.approved_end || s.clock_out,
        (s.worked_seconds / 3600).toFixed(2),
        Math.round(s.break_seconds / 60),
        s.state,
        s.review_status,
        !!s.approved_start,
      ]
        .map(csvCell)
        .join(","),
    ),
  ].join("\r\n");
}
export function dailyBrief(data) {
  const names = new Map(
    (data.members || []).map((m) => [m.user_id, m.display_name]),
  );
  return `${data.organization.name} — Workforce report\n${data.from} to ${data.to} (${data.organization.timezone})\n\n${(data.report_shifts || data.shifts).length} shifts • ${(data.metrics.worked_seconds / 3600).toFixed(1)} shift hours (full shifts overlapping report dates)\n${data.metrics.updates_due} hourly updates due\n\nRecorded work\n${(data.period_updates || data.updates).map((u) => `${names.get(u.user_id) || "Team member"}: ${u.quantity} ${u.output_unit}. ${u.summary}${u.blockers ? " Blocker: " + u.blockers : ""}`).join("\n") || "No work updates recorded."}\n\n${data.corrections.filter((c) => c.status === "pending").length} correction requests pending.\nWork quantities are employee-reported. Timesheets require manager review.`;
}
