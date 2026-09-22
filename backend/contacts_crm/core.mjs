import crypto from "node:crypto";
export const CATEGORIES = [
  "friend",
  "family",
  "customer",
  "unknown",
  "lead",
  "partner",
  "vendor",
];
export const SOURCES = ["manual", "phone", "email", "facebook", "spreadsheet", "funnel"];
export class ContactError extends Error {
  constructor(message, status = 400, code = "CONTACT_INVALID") {
    super(message);
    this.status = status;
    this.code = code;
  }
}
export function fail(message, status, code) {
  throw new ContactError(message, status, code);
}
const clean = (v, n) =>
  String(v ?? "")
    .trim()
    .replace(/\0/g, "")
    .slice(0, n);
export function normalizeContact(raw, { imported = false } = {}) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw))
    fail("A contact record is required.");
  const name = clean(raw.name, 160),
    email = clean(raw.email, 254).toLowerCase(),
    phone = clean(raw.phone, 60);
  if (!name) fail("Enter a contact name.");
  if (email && !/^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$/.test(email))
    fail("Enter a valid email address.");
  if (
    phone &&
    (!/^[+\d().\s-]+$/.test(phone) ||
      phone.replace(/\D/g, "").length < 7 ||
      phone.replace(/\D/g, "").length > 15)
  )
    fail("Enter a valid phone number, including country code for Nova calls.");
  const category = clean(raw.category || "unknown", 30).toLowerCase();
  if (!CATEGORIES.includes(category))
    fail("Choose a valid relationship status.");
  const source = SOURCES.includes(raw.source) ? raw.source : "manual";
  const emailPermission = imported
    ? "none"
    : clean(raw.email_permission || "none", 30);
  const callPermission = imported
    ? "none"
    : clean(raw.call_permission || "none", 30);
  if (
    !["none", "transactional", "marketing", "blocked"].includes(
      emailPermission,
    ) ||
    !["none", "allowed", "blocked"].includes(callPermission)
  )
    fail("Choose valid contact permissions.");
  const consentAt =
    !imported && raw.consent_at ? new Date(raw.consent_at) : null;
  if (consentAt && !Number.isFinite(consentAt.getTime()))
    fail("Choose a valid consent date.");
  if (emailPermission === "marketing" && !consentAt)
    fail("Record the marketing permission date.");
  const followup = clean(raw.follow_up_on, 10) || null;
  if (
    followup &&
    (!/^\d{4}-\d{2}-\d{2}$/.test(followup) ||
      !Number.isFinite(Date.parse(followup)) ||
      new Date(followup).toISOString().slice(0, 10) !== followup)
  )
    fail("Choose a valid follow-up date.");
  const tags = Array.isArray(raw.tags)
    ? [...new Set(raw.tags.map((x) => clean(x, 32)).filter(Boolean))].slice(
        0,
        12,
      )
    : [];
  return {
    name,
    email: email || null,
    phone: phone || null,
    phone_key: phone ? phone.replace(/\D/g, "") : null,
    category,
    source,
    company: clean(raw.company, 160),
    notes: clean(raw.notes, 4000),
    tags,
    favorite: !imported && raw.favorite === true,
    follow_up_on: followup,
    email_permission: emailPermission,
    call_permission: callPermission,
    consent_at: imported ? null : consentAt?.toISOString() || null,
    do_not_contact: imported ? false : raw.do_not_contact === true,
    call_brief: clean(raw.call_brief, 2000),
  };
}
export const validId = (id) => {
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      String(id),
    )
  )
    fail("Contact not found.", 404, "CONTACT_NOT_FOUND");
  return id;
};
export function validateQuery(query = {}) {
  const category = String(query.category || "");
  if (category && !CATEGORIES.includes(category))
    fail("Unknown status filter.");
  const source = String(query.source || "");
  if (source && !SOURCES.includes(source)) fail("Unknown source filter.");
  const segment = String(query.segment || "");
  if (
    ![
      "",
      "favorites",
      "follow_up",
      "missing_details",
      "email_ready",
      "call_ready",
    ].includes(segment)
  )
    fail("Unknown contact filter.");
  const limit = Number(query.limit ?? 50),
    offset = Number(query.offset ?? 0);
  if (
    !Number.isInteger(limit) ||
    limit < 1 ||
    limit > 200 ||
    !Number.isInteger(offset) ||
    offset < 0 ||
    offset > 100000
  )
    fail("Invalid page.");
  const q = clean(query.q, 100)
    .replace(/[^\p{L}\p{N}@+ ._-]/gu, "")
    .replace(/[%_]/g, " ");
  return {
    category,
    source,
    segment,
    limit,
    offset,
    q,
    sort: ["name", "updated_at", "follow_up_on"].includes(query.sort)
      ? query.sort
      : "name",
  };
}
export const fingerprint = (c) =>
  crypto
    .createHash("sha256")
    .update(JSON.stringify([c.name, c.email, c.phone_key, c.source]))
    .digest("hex");
export function csvEscape(v) {
  const s = String(v ?? "");
  return (
    '"' + (/^[\s]*[=+@-]/.test(s) ? "'" + s : s).replaceAll('"', '""') + '"'
  );
}
