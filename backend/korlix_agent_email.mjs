import crypto from "node:crypto";

export const KORLIX_AGENT_EMAIL_TOOL_ID = "agent_email";
export const KORLIX_AGENT_EMAIL_MODES = Object.freeze([
  "draft_only",
  "approval_required",
  "autopilot",
]);

const TRUE_VALUES = new Set(["1", "true", "yes", "on", "enabled"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const AGENT_ID = /^[a-z][a-z0-9_]{0,95}$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const TIME = /^(?:[01]\d|2[0-3]):[0-5]\d$/;

export class KorlixAgentEmailError extends Error {
  constructor(message, { code = "agent_email_error", statusCode = 400, cause } = {}) {
    super(String(message || "Agent Email request failed."), { cause });
    this.name = "KorlixAgentEmailError";
    this.code = String(code || "agent_email_error");
    this.statusCode = Number.isInteger(statusCode) ? statusCode : 400;
  }
}

function line(value, maximum = 500) {
  return String(value ?? "")
    .replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, Math.max(1, Number(maximum) || 500));
}

function block(value, maximum = 40000) {
  return String(value ?? "")
    .replace(/\r\n?/g, "\n")
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, " ")
    .trim()
    .slice(0, Math.max(1, Number(maximum) || 40000));
}

function objectValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function envText(environment, name) {
  return line(environment?.[name], 500);
}

function envFlag(environment, name, fallback = false) {
  const value = envText(environment, name).toLowerCase();
  return value ? TRUE_VALUES.has(value) : fallback;
}

function boundedInteger(value, fallback, minimum, maximum) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed)
    ? Math.min(maximum, Math.max(minimum, parsed))
    : fallback;
}

function fail(message, code, statusCode = 400) {
  throw new KorlixAgentEmailError(message, { code, statusCode });
}

function requireConfirmation(source, message, code) {
  if (source.confirmed !== true && source.approved !== true) fail(message, code);
}

export function korlixAgentEmailUserId(value) {
  const id = line(typeof value === "string" ? value : value?.id, 80);
  if (!UUID.test(id)) {
    fail("A valid signed-in KORLIX user is required.", "agent_email_sign_in_required", 401);
  }
  return id.toLowerCase();
}

export function korlixAgentEmailAgentId(value) {
  const id = line(value, 96).toLowerCase();
  if (!AGENT_ID.test(id)) {
    fail("A valid KORLIX Agent Hub agent is required.", "agent_email_agent_id_invalid");
  }
  return id;
}

export function korlixAgentEmailAddress(value) {
  const email = line(value, 254).toLowerCase();
  if (!EMAIL.test(email)) {
    fail("Enter a valid approved recipient email address.", "agent_email_recipient_invalid");
  }
  return email;
}

export function korlixAgentEmailNovaBinding(environment = process.env) {
  const ownerUid = envText(environment, "KORLIX_VAPI_NOVA_OWNER_UID");
  const agentId = envText(environment, "KORLIX_VAPI_NOVA_AGENT_ID").toLowerCase();
  const assistantId =
    envText(environment, "KORLIX_VAPI_NOVA_ASSISTANT_ID") ||
    envText(environment, "VAPI_NOVA_ASSISTANT_ID");

  return Object.freeze({
    ownerUid,
    agentId,
    assistantId,
    configured: Boolean(UUID.test(ownerUid) && AGENT_ID.test(agentId) && assistantId),
  });
}

export function korlixAgentEmailIsExistingNova({
  environment = process.env,
  userId,
  agentId,
} = {}) {
  const binding = korlixAgentEmailNovaBinding(environment);
  return binding.configured &&
    binding.ownerUid.toLowerCase() === korlixAgentEmailUserId(userId) &&
    binding.agentId === korlixAgentEmailAgentId(agentId);
}

export function korlixAgentEmailStatus({
  environment = process.env,
  userId,
  agentId,
  toolIds = [],
  settings = null,
} = {}) {
  const sameNova = korlixAgentEmailIsExistingNova({ environment, userId, agentId });
  const saved = objectValue(settings);
  const mode = KORLIX_AGENT_EMAIL_MODES.includes(saved.mode)
    ? saved.mode
    : "draft_only";
  const featureEnabled = envFlag(environment, "KORLIX_AGENT_EMAIL_ENABLED", false);
  const emergencyPaused = envFlag(
    environment,
    "KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE",
    true,
  );
  const providerConfigured = Boolean(
    envText(environment, "RESEND_API_KEY") &&
    envText(environment, "KORLIX_AGENT_EMAIL_FROM"),
  );
  const toolAuthorized = Array.isArray(toolIds) && toolIds.includes(KORLIX_AGENT_EMAIL_TOOL_ID);
  const settingsEnabled = saved.enabled === true;
  const settingsPaused = saved.paused !== false;
  const sendBoundary = sameNova && featureEnabled && !emergencyPaused &&
    providerConfigured && toolAuthorized && settingsEnabled && !settingsPaused;

  return Object.freeze({
    sameNova,
    featureEnabled,
    emergencyPaused,
    providerConfigured,
    toolAuthorized,
    settingsEnabled,
    settingsPaused,
    mode,
    canDraft: sameNova && settingsEnabled && toolAuthorized,
    canSend: sendBoundary && mode !== "draft_only",
    canAutopilot: sendBoundary && mode === "autopilot",
  });
}

export function korlixAgentEmailSettingsInput(body, environment = process.env) {
  const source = objectValue(body);
  requireConfirmation(
    source,
    "Confirm Nova's Agent Email settings before saving them.",
    "agent_email_settings_confirmation_required",
  );

  const mode = line(source.mode || "draft_only", 40).toLowerCase();
  if (!KORLIX_AGENT_EMAIL_MODES.includes(mode)) {
    fail("Choose Draft Only, Approval Required, or Approved Autopilot.", "agent_email_mode_invalid");
  }

  const maximum = boundedInteger(
    environment?.KORLIX_AGENT_EMAIL_MAX_DAILY_CAP,
    20,
    1,
    100,
  );
  const start = line(source.sendWindowStart ?? source.send_window_start ?? "09:00", 5);
  const end = line(source.sendWindowEnd ?? source.send_window_end ?? "17:00", 5);
  if (!TIME.test(start) || !TIME.test(end)) {
    fail("Email sending windows must use 24-hour HH:MM time.", "agent_email_send_window_invalid");
  }

  return Object.freeze({
    mode,
    enabled: source.enabled === true,
    paused: source.paused !== false,
    dailySendCap: boundedInteger(
      source.dailySendCap ?? source.daily_send_cap,
      5,
      1,
      maximum,
    ),
    timezone: line(source.timezone || "UTC", 80) || "UTC",
    sendWindowStart: start,
    sendWindowEnd: end,
    maxFollowUps: boundedInteger(
      source.maxFollowUps ?? source.max_follow_ups,
      0,
      0,
      5,
    ),
    marketingEnabled: source.marketingEnabled === true,
  });
}

export function korlixAgentEmailRecipientInput(body) {
  const source = objectValue(body);
  requireConfirmation(
    source,
    "Confirm this recipient before Nova may save the address.",
    "agent_email_recipient_confirmation_required",
  );

  const approvalSource = line(
    source.approvalSource ?? source.approval_source ?? "manual_user_entry",
    80,
  ).toLowerCase();
  if (!["manual_user_entry", "user_confirmed"].includes(approvalSource)) {
    fail(
      "Recipients must be entered or confirmed by the signed-in user.",
      "agent_email_recipient_source_prohibited",
    );
  }

  const consentScope = line(
    source.consentScope ?? source.consent_scope ?? "transactional",
    40,
  ).toLowerCase();
  if (!["transactional", "marketing"].includes(consentScope)) {
    fail("Recipient consent scope is invalid.", "agent_email_consent_scope_invalid");
  }

  const consentAt = line(source.consentAt ?? source.consent_at, 80);
  const parsedConsent = consentAt ? Date.parse(consentAt) : Number.NaN;
  if (consentScope === "marketing" && !Number.isFinite(parsedConsent)) {
    fail("Marketing recipients require a recorded consent date.", "agent_email_marketing_consent_required");
  }

  return Object.freeze({
    email: korlixAgentEmailAddress(source.email),
    displayName: line(source.displayName ?? source.display_name, 120),
    approvalSource,
    consentScope,
    consentAt: Number.isFinite(parsedConsent)
      ? new Date(parsedConsent).toISOString()
      : null,
  });
}

export function korlixAgentEmailDraftInput(body) {
  const source = objectValue(body);
  const recipientId = line(source.recipientId ?? source.recipient_id, 80);
  const subject = line(source.subject, 200);
  const textBody = block(source.textBody ?? source.text_body ?? source.body, 40000);
  const idempotencyKey = line(
    source.idempotencyKey ?? source.idempotency_key,
    200,
  );

  if (!UUID.test(recipientId)) fail("Choose an approved recipient first.", "agent_email_recipient_id_required");
  if (!subject) fail("Enter an email subject.", "agent_email_subject_required");
  if (!textBody) fail("Enter the email message.", "agent_email_body_required");
  if (!idempotencyKey) {
    fail(
      "An idempotency key is required to prevent duplicate email.",
      "agent_email_idempotency_key_required",
    );
  }

  const marketing = source.marketing === true;
  const unsubscribeUrl = line(source.unsubscribeUrl ?? source.unsubscribe_url, 1000);
  const physicalAddress = line(source.physicalAddress ?? source.physical_address, 500);
  if (marketing && (!unsubscribeUrl || !physicalAddress)) {
    fail(
      "Marketing email requires an unsubscribe link and physical address.",
      "agent_email_marketing_footer_required",
    );
  }

  return Object.freeze({
    recipientId: recipientId.toLowerCase(),
    subject,
    textBody,
    idempotencyKey,
    marketing,
    unsubscribeUrl: unsubscribeUrl || null,
    physicalAddress: physicalAddress || null,
    scheduledAt: line(source.scheduledAt ?? source.scheduled_at, 80) || null,
  });
}

export function korlixAgentEmailIdempotencyKey({
  userId,
  agentId,
  messageId = crypto.randomUUID(),
} = {}) {
  return [
    "korlix-agent-email",
    korlixAgentEmailUserId(userId),
    korlixAgentEmailAgentId(agentId),
    line(messageId, 100),
  ].join(":");
}
