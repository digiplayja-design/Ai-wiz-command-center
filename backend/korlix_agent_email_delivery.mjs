import crypto from "node:crypto";

import {
  KORLIX_AGENT_EMAIL_TOOL_ID,
  KorlixAgentEmailError,
  korlixAgentEmailAddress,
  korlixAgentEmailAgentId,
  korlixAgentEmailIsExistingNova,
  korlixAgentEmailNovaBinding,
  korlixAgentEmailStatus,
  korlixAgentEmailUserId,
} from "./korlix_agent_email.mjs";

import {
  createKorlixAgentEmailSupabaseStore,
} from "./korlix_agent_email_routes.mjs";

const PREFIX = "/api/live-convo/agents/:agentId/email";

export const KORLIX_AGENT_EMAIL_DELIVERY_ROUTES = Object.freeze({
  deliveryStatus: `${PREFIX}/delivery/status`,
  sendDraft: `${PREFIX}/drafts/:messageId/send`,
  events: `${PREFIX}/events`,
  rules: `${PREFIX}/rules`,
  rule: `${PREFIX}/rules/:ruleId`,
  resendWebhook: "/api/agent-email/resend/webhook",
  autopilotRun: "/api/internal/agent-email/autopilot/run",
});

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TRIGGER_KEY = /^[a-z][a-z0-9_.:-]{0,119}$/;
const VARIABLE_KEY = /^[A-Za-z][A-Za-z0-9_]{0,63}$/;
const TRUE_VALUES = new Set(["1", "true", "yes", "on", "enabled"]);
const SENDABLE_STATUSES = new Set(["approved", "failed"]);
const PROVIDER_IDEMPOTENCY_SAFE_RETRY_MILLISECONDS =
  23 * 60 * 60 * 1000;
const TERMINAL_FAILURE_EVENTS = new Set([
  "email.bounced",
  "email.complained",
  "email.failed",
  "email.suppressed",
]);
const DELIVERY_EVENTS = new Set([
  "email.sent",
  "email.delivered",
  "email.delivery_delayed",
  "email.opened",
  "email.clicked",
  ...TERMINAL_FAILURE_EVENTS,
]);
const PROTECTED_RULE_FIELDS = new Set([
  "name",
  "triggerKey",
  "trigger_key",
  "recipientIds",
  "recipient_ids",
  "subjectTemplate",
  "subject_template",
  "textTemplate",
  "text_template",
  "htmlTemplate",
  "html_template",
  "marketing",
  "maxSendsPerDay",
  "max_sends_per_day",
  "sendMode",
  "send_mode",
  "allowedDays",
  "allowed_days",
]);

function objectValue(value) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value
    : {};
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

function envText(environment, name, maximum = 1000) {
  return line(environment?.[name], maximum);
}

function envFlag(environment, name, fallback = false) {
  const value = envText(environment, name, 40).toLowerCase();
  return value ? TRUE_VALUES.has(value) : fallback;
}

function boundedInteger(value, fallback, minimum, maximum) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed)
    ? Math.min(maximum, Math.max(minimum, parsed))
    : fallback;
}

function fail(message, code, statusCode = 400, cause) {
  throw new KorlixAgentEmailError(message, {
    code,
    statusCode,
    cause,
  });
}

function requireConfirmation(body, message, code) {
  const source = objectValue(body);
  if (source.confirmed !== true && source.approved !== true) {
    fail(message, code);
  }
}

function uuid(value, code, message) {
  const normalized = line(value, 80).toLowerCase();
  if (!UUID.test(normalized)) {
    fail(message, code);
  }
  return normalized;
}

function safeHash(value) {
  return crypto
    .createHash("sha256")
    .update(String(value ?? ""))
    .digest("hex");
}

function constantTimeEqual(left, right) {
  const a = Buffer.from(String(left ?? ""), "utf8");
  const b = Buffer.from(String(right ?? ""), "utf8");
  return a.length > 0 && a.length === b.length && crypto.timingSafeEqual(a, b);
}

function header(request, name) {
  const lower = String(name).toLowerCase();
  const headers = request?.headers ?? {};
  const key = Object.keys(headers).find((item) => item.toLowerCase() === lower);
  let value = headers[lower] ?? headers[name] ?? (key ? headers[key] : undefined);

  if (value == null && typeof request?.get === "function") {
    value = request.get(name);
  }

  if (Array.isArray(value)) {
    value = value[0];
  }

  return line(value, 2000);
}

function databaseError(error, operation) {
  if (error instanceof KorlixAgentEmailError) {
    return error;
  }

  const code = line(error?.code, 80).toUpperCase();
  const detail = [
    error?.message,
    error?.details,
    error?.hint,
    error,
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  const migrationMissing =
    code === "42P01" ||
    code === "PGRST204" ||
    code === "PGRST205" ||
    detail.includes("could not find the table") ||
    detail.includes("schema cache") ||
    detail.includes("does not exist") ||
    (detail.includes("relation") && detail.includes("not found"));

  return new KorlixAgentEmailError(
    migrationMissing
      ? "The Agent Email database migration has not been applied yet."
      : `KORLIX could not complete the ${
          line(operation, 160) || "Agent Email database request"
        }.`,
    {
      code: migrationMissing
        ? "agent_email_persistence_not_ready"
        : "agent_email_persistence_failed",
      statusCode: migrationMissing ? 503 : 500,
      cause: error,
    },
  );
}

function settingsForPolicy(row) {
  return {
    enabled: row?.enabled === true,
    paused: row ? row.emergency_paused !== false : true,
    mode: line(row?.operating_mode, 40).toLowerCase() || "draft_only",
  };
}

function settingsPublicView(row) {
  const metadata = objectValue(row?.metadata);
  return Object.freeze({
    id: line(row?.id, 80) || null,
    agentId: line(row?.agent_id, 96).toLowerCase() || null,
    provider: line(row?.provider, 40).toLowerCase() || "resend",
    enabled: row?.enabled === true,
    mode: line(row?.operating_mode, 40).toLowerCase() || "draft_only",
    paused: row ? row.emergency_paused !== false : true,
    dailySendCap: boundedInteger(row?.daily_send_cap, 5, 1, 500),
    fromName: line(row?.from_name, 160),
    fromEmail: line(row?.from_email, 320).toLowerCase(),
    replyToEmail: line(row?.reply_to_email, 320).toLowerCase(),
    physicalAddress: line(row?.physical_address, 500),
    timezone: line(row?.timezone, 80) || "UTC",
    sendWindowStart:
      line(metadata.sendWindowStart ?? metadata.send_window_start, 5) ||
      "09:00",
    sendWindowEnd:
      line(metadata.sendWindowEnd ?? metadata.send_window_end, 5) ||
      "17:00",
    maxFollowUps: boundedInteger(
      metadata.maxFollowUps ?? metadata.max_follow_ups,
      0,
      0,
      5,
    ),
    marketingEnabled:
      metadata.marketingEnabled === true ||
      metadata.marketing_enabled === true,
    createdAt: row?.created_at ?? null,
    updatedAt: row?.updated_at ?? null,
  });
}

function recipientPublicView(row) {
  if (!row) return null;
  return Object.freeze({
    id: line(row.id, 80),
    agentId: line(row.agent_id, 96).toLowerCase(),
    email: line(row.email, 320).toLowerCase(),
    displayName: line(row.display_name, 160),
    consentStatus: line(row.consent_status, 80).toLowerCase(),
    consentAt: row.consent_recorded_at ?? null,
    unsubscribedAt: row.unsubscribed_at ?? null,
    suppressedAt: row.suppressed_at ?? null,
    suppressionReason: line(row.suppression_reason, 500) || null,
    active: row.active !== false,
    updatedAt: row.updated_at ?? null,
  });
}

function messagePublicView(row) {
  if (!row) return null;
  const metadata = objectValue(row.metadata);
  const status = line(row.status, 40).toLowerCase() || "draft";
  return Object.freeze({
    id: line(row.id, 80),
    agentId: line(row.agent_id, 96).toLowerCase(),
    recipientId: line(row.recipient_id, 80) || null,
    ruleId: line(row.rule_id, 80) || null,
    toEmail: line(row.to_email, 320).toLowerCase(),
    subject: line(row.subject, 240),
    textBody: String(row.text_body ?? ""),
    htmlBody: String(row.html_body ?? ""),
    messageKind: line(row.message_kind, 40).toLowerCase() || "transactional",
    status,
    authorizationType:
      line(row.authorization_type, 60).toLowerCase() || "none",
    authorizedAt: row.authorized_at ?? null,
    authorizedBy: line(row.authorized_by, 80) || null,
    provider: line(row.provider, 40).toLowerCase() || "resend",
    providerMessageId: line(row.provider_message_id, 240) || null,
    scheduledAt: row.scheduled_at ?? null,
    lastAttemptAt: row.last_attempt_at ?? null,
    attemptCount: Math.max(0, Number(row.attempt_count) || 0),
    sentAt: row.sent_at ?? null,
    failureCode: line(row.failure_code, 120) || null,
    failureMessage: line(row.failure_message, 600) || null,
    deliveryStatus: line(metadata.deliveryStatus, 80) || null,
    deliveredAt: metadata.deliveredAt ?? null,
    sent: status === "sent",
    createdAt: row.created_at ?? null,
    updatedAt: row.updated_at ?? null,
  });
}

function rulePublicView(row) {
  if (!row) return null;
  const scope = objectValue(row.recipient_scope);
  const metadata = objectValue(row.metadata);
  return Object.freeze({
    id: line(row.id, 80),
    agentId: line(row.agent_id, 96).toLowerCase(),
    name: line(row.name, 200),
    enabled: row.enabled === true,
    sendMode: line(row.send_mode, 40).toLowerCase() || "draft_only",
    triggerKey: line(row.trigger_key, 120).toLowerCase(),
    recipientIds: Array.isArray(scope.recipientIds)
      ? scope.recipientIds.map((value) => line(value, 80).toLowerCase())
      : [],
    subjectTemplate: line(row.subject_template, 240),
    textTemplate: String(row.text_template ?? ""),
    htmlTemplate: String(row.html_template ?? ""),
    marketing: row.marketing === true,
    maxSendsPerDay: boundedInteger(row.max_sends_per_day, 1, 1, 500),
    preapproved: Boolean(row.preapproved_at && row.preapproved_by),
    preapprovedAt: row.preapproved_at ?? null,
    preapprovedBy: line(row.preapproved_by, 80) || null,
    approvalVersion: Math.max(1, Number(row.approval_version) || 1),
    allowedDays: Array.isArray(metadata.allowedDays)
      ? metadata.allowedDays
      : [0, 1, 2, 3, 4, 5, 6],
    createdAt: row.created_at ?? null,
    updatedAt: row.updated_at ?? null,
  });
}

function eventPublicView(row) {
  return Object.freeze({
    id: line(row?.id, 80) || null,
    messageId: line(row?.message_id, 80) || null,
    eventType: line(row?.event_type, 100),
    provider: line(row?.provider, 40).toLowerCase() || "resend",
    providerEventId: line(row?.provider_event_id, 240) || null,
    eventAt: row?.event_at ?? null,
    details: objectValue(row?.details),
    createdAt: row?.created_at ?? null,
  });
}

function recipientAllowed(row, marketing) {
  if (!row) {
    fail(
      "The selected approved recipient was not found.",
      "agent_email_recipient_not_found",
      404,
    );
  }

  const status = line(row.consent_status, 80).toLowerCase();
  if (
    row.active === false ||
    status === "unsubscribed" ||
    status === "suppressed"
  ) {
    fail(
      "Nova cannot email an unsubscribed or suppressed recipient.",
      "agent_email_recipient_blocked",
      409,
    );
  }

  if (marketing && status !== "marketing_opt_in") {
    fail(
      "Marketing email requires recorded recipient opt-in.",
      "agent_email_marketing_consent_required",
      409,
    );
  }

  return row;
}

function parseClock(value, fallback) {
  const text = line(value || fallback, 5);
  if (!/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(text)) {
    fail(
      "Agent Email send windows must use 24-hour HH:MM time.",
      "agent_email_send_window_invalid",
      500,
    );
  }
  const [hour, minute] = text.split(":").map(Number);
  return { text, minuteOfDay: hour * 60 + minute };
}

function zonedParts(date, timeZone) {
  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
      weekday: "short",
    }).formatToParts(date);
    const map = Object.fromEntries(parts.map((part) => [part.type, part.value]));
    const weekday = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].indexOf(
      map.weekday,
    );
    return {
      year: Number(map.year),
      month: Number(map.month),
      day: Number(map.day),
      hour: Number(map.hour),
      minute: Number(map.minute),
      second: Number(map.second),
      weekday,
    };
  } catch (error) {
    fail(
      "Nova's Agent Email timezone is invalid.",
      "agent_email_timezone_invalid",
      500,
      error,
    );
  }
}

function timezoneOffsetMilliseconds(date, timeZone) {
  const parts = zonedParts(date, timeZone);
  const representedAsUtc = Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second,
  );
  return representedAsUtc - date.getTime();
}

function zonedDayStart(date, timeZone) {
  const parts = zonedParts(date, timeZone);
  let candidate = new Date(Date.UTC(parts.year, parts.month - 1, parts.day));
  for (let index = 0; index < 3; index += 1) {
    candidate = new Date(
      Date.UTC(parts.year, parts.month - 1, parts.day) -
        timezoneOffsetMilliseconds(candidate, timeZone),
    );
  }
  return candidate.toISOString();
}

function withinSendWindow(date, settingsRow, allowedDays = null) {
  const metadata = objectValue(settingsRow?.metadata);
  const timeZone = line(settingsRow?.timezone, 80) || "UTC";
  const parts = zonedParts(date, timeZone);
  const start = parseClock(
    metadata.sendWindowStart ?? metadata.send_window_start,
    "09:00",
  );
  const end = parseClock(
    metadata.sendWindowEnd ?? metadata.send_window_end,
    "17:00",
  );
  const days = Array.isArray(allowedDays)
    ? new Set(allowedDays.map(Number))
    : new Set([0, 1, 2, 3, 4, 5, 6]);

  if (!days.has(parts.weekday)) {
    return false;
  }

  const current = parts.hour * 60 + parts.minute;
  return start.minuteOfDay <= end.minuteOfDay
    ? current >= start.minuteOfDay && current <= end.minuteOfDay
    : current >= start.minuteOfDay || current <= end.minuteOfDay;
}

function htmlEscape(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function approvedHttpsUrl(value, code, message) {
  const candidate = line(value, 1000);
  let url;

  try {
    url = new URL(candidate);
  } catch (error) {
    fail(message, code, 409, error);
  }

  if (url.protocol !== "https:" || !url.hostname) {
    fail(message, code, 409);
  }

  url.hash = "";
  return url.toString();
}

function normalizeVariables(value) {
  const source = objectValue(value);
  const result = {};
  for (const [key, raw] of Object.entries(source).slice(0, 50)) {
    if (!VARIABLE_KEY.test(key)) {
      fail(
        "Autopilot variables must use simple letter, number, and underscore names.",
        "agent_email_autopilot_variable_invalid",
      );
    }
    result[key] = block(raw, 4000);
  }
  return result;
}

export function korlixAgentEmailRenderTemplate(
  template,
  variables,
  { html = false } = {},
) {
  const source = block(template, 40000);
  const values = normalizeVariables(variables);
  const unresolved = new Set();
  const rendered = source.replace(/{{\s*([A-Za-z][A-Za-z0-9_]{0,63})\s*}}/g, (
    _match,
    key,
  ) => {
    if (!Object.hasOwn(values, key)) {
      unresolved.add(key);
      return "";
    }
    return html ? htmlEscape(values[key]) : values[key];
  });

  if (unresolved.size) {
    fail(
      `Autopilot is missing approved variables: ${[...unresolved].join(", ")}.`,
      "agent_email_autopilot_variables_missing",
      409,
    );
  }

  return rendered;
}

function marketingText(message) {
  if (message.message_kind !== "marketing") {
    return String(message.text_body ?? "");
  }
  return [
    String(message.text_body ?? ""),
    "",
    `Unsubscribe: ${line(message.unsubscribe_url_snapshot, 1000)}`,
    line(message.physical_address_snapshot, 500),
  ]
    .filter((item, index) => index === 0 || item)
    .join("\n");
}

function marketingHtml(message) {
  const base = String(message.html_body ?? "").trim();
  if (message.message_kind !== "marketing") {
    return base;
  }
  const unsubscribeUrl = line(message.unsubscribe_url_snapshot, 1000);
  const address = line(message.physical_address_snapshot, 500);
  const footer = [
    "<hr>",
    "<p style=\"font-size:12px;color:#666\">",
    `<a href=\"${htmlEscape(unsubscribeUrl)}\">Unsubscribe</a><br>`,
    htmlEscape(address),
    "</p>",
  ].join("");
  return `${base || `<p>${htmlEscape(String(message.text_body ?? "")).replaceAll("\n", "<br>")}</p>`}${footer}`;
}

function providerIdempotencyKey(messageId) {
  return `korlix-agent-email/${uuid(
    messageId,
    "agent_email_message_id_invalid",
    "Choose a valid Nova email record.",
  )}`;
}

export function createKorlixAgentEmailResendProvider({
  environment = process.env,
  fetchImpl = globalThis.fetch,
  endpoint = "https://api.resend.com/emails",
  timeoutMilliseconds = 15000,
} = {}) {
  if (typeof fetchImpl !== "function") {
    fail(
      "The Resend network service is unavailable.",
      "agent_email_resend_fetch_unavailable",
      503,
    );
  }

  const url = new URL(endpoint);
  if (url.protocol !== "https:" || url.hostname !== "api.resend.com") {
    fail(
      "The Resend API endpoint is not approved.",
      "agent_email_resend_endpoint_invalid",
      500,
    );
  }

  return Object.freeze({
    async send({ message, settings }) {
      const apiKey = envText(environment, "RESEND_API_KEY", 1000);
      const from = envText(environment, "KORLIX_AGENT_EMAIL_FROM", 500);
      if (!apiKey || !from) {
        fail(
          "Resend and Nova's approved From address must be configured before sending.",
          "agent_email_provider_not_configured",
          503,
        );
      }

      const replyTo =
        line(settings?.reply_to_email, 320).toLowerCase() ||
        envText(environment, "KORLIX_AGENT_EMAIL_REPLY_TO", 320).toLowerCase();
      if (replyTo) {
        korlixAgentEmailAddress(replyTo);
      }

      const payload = {
        from,
        to: [korlixAgentEmailAddress(message.to_email)],
        subject: line(message.subject, 200),
        text: marketingText(message),
      };
      const html = marketingHtml(message);
      if (html) payload.html = html;
      if (replyTo) payload.reply_to = replyTo;

      const controller = new AbortController();
      const timer = setTimeout(
        () => controller.abort(),
        Math.max(1000, Number(timeoutMilliseconds) || 15000),
      );

      let response;
      try {
        response = await fetchImpl(url.toString(), {
          method: "POST",
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
            "Idempotency-Key": providerIdempotencyKey(message.id),
          },
          body: JSON.stringify(payload),
          signal: controller.signal,
        });
      } catch (error) {
        fail(
          "Resend could not be reached. The same message can be retried safely.",
          error?.name === "AbortError"
            ? "agent_email_resend_timeout"
            : "agent_email_resend_network_error",
          503,
          error,
        );
      } finally {
        clearTimeout(timer);
      }

      let body;
      try {
        body = await response.json();
      } catch {
        body = {};
      }

      if (!response.ok) {
        const providerCode = line(body?.name ?? body?.code, 120).toLowerCase();
        const providerMessage = line(body?.message, 600);
        const retryable =
          response.status === 429 ||
          response.status >= 500 ||
          providerCode === "concurrent_idempotent_requests";
        fail(
          retryable
            ? "Resend temporarily rejected the email. It can be retried safely."
            : providerMessage || "Resend rejected the email request.",
          providerCode
            ? `agent_email_resend_${providerCode.replace(/[^a-z0-9_]+/g, "_")}`
            : "agent_email_resend_rejected",
          retryable ? 503 : response.status === 409 ? 409 : 422,
        );
      }

      const providerMessageId = line(body?.id, 240);
      if (!providerMessageId) {
        fail(
          "Resend accepted the request without returning a message ID.",
          "agent_email_resend_message_id_missing",
          503,
        );
      }

      return Object.freeze({
        provider: "resend",
        providerMessageId,
        idempotencyKey: providerIdempotencyKey(message.id),
      });
    },
  });
}

function webhookHeader(headers, name) {
  const source = objectValue(headers);
  const lower = name.toLowerCase();
  const alternative = lower.replace(/^svix-/, "webhook-");
  const key = Object.keys(source).find((item) => {
    const normalized = item.toLowerCase();
    return normalized === lower || normalized === alternative;
  });
  const value = source[lower] ?? source[alternative] ?? (key ? source[key] : "");
  return Array.isArray(value) ? line(value[0], 4000) : line(value, 4000);
}

export function verifyKorlixAgentEmailResendWebhook({
  rawBody,
  headers,
  secret,
  now = () => new Date(),
  toleranceSeconds = 300,
} = {}) {
  const payload = Buffer.isBuffer(rawBody)
    ? rawBody.toString("utf8")
    : String(rawBody ?? "");
  if (!payload || Buffer.byteLength(payload, "utf8") > 2_000_000) {
    fail(
      "The Resend webhook payload is missing or too large.",
      "agent_email_webhook_payload_invalid",
      400,
    );
  }

  const signingSecret = line(secret, 1000);
  if (!signingSecret.startsWith("whsec_")) {
    fail(
      "The Resend webhook signing secret is not configured.",
      "agent_email_webhook_secret_not_configured",
      503,
    );
  }

  const messageId = webhookHeader(headers, "svix-id");
  const timestampText = webhookHeader(headers, "svix-timestamp");
  const signatures = webhookHeader(headers, "svix-signature");
  const timestamp = Number.parseInt(timestampText, 10);
  if (!messageId || !Number.isFinite(timestamp) || !signatures) {
    fail(
      "The Resend webhook signature headers are incomplete.",
      "agent_email_webhook_signature_headers_missing",
      401,
    );
  }

  const currentSeconds = Math.floor(new Date(now()).getTime() / 1000);
  if (
    !Number.isFinite(currentSeconds) ||
    Math.abs(currentSeconds - timestamp) >
      Math.max(60, Number(toleranceSeconds) || 300)
  ) {
    fail(
      "The Resend webhook timestamp is outside the accepted window.",
      "agent_email_webhook_timestamp_invalid",
      401,
    );
  }

  const encodedSecret = signingSecret.slice("whsec_".length);
  const secretBytes = Buffer.from(encodedSecret, "base64");
  if (!secretBytes.length) {
    fail(
      "The Resend webhook signing secret is invalid.",
      "agent_email_webhook_secret_invalid",
      503,
    );
  }

  const expected = crypto
    .createHmac("sha256", secretBytes)
    .update(`${messageId}.${timestampText}.${payload}`)
    .digest("base64");
  const verified = signatures
    .split(/\s+/)
    .filter(Boolean)
    .some((entry) => {
      const [version, signature] = entry.split(",", 2);
      return version === "v1" && signature && constantTimeEqual(signature, expected);
    });

  if (!verified) {
    fail(
      "The Resend webhook signature is invalid.",
      "agent_email_webhook_signature_invalid",
      401,
    );
  }

  let event;
  try {
    event = JSON.parse(payload);
  } catch (error) {
    fail(
      "The Resend webhook payload is not valid JSON.",
      "agent_email_webhook_json_invalid",
      400,
      error,
    );
  }

  return Object.freeze({
    providerEventId: messageId,
    event,
  });
}

function ruleRecipientIds(row) {
  const scope = objectValue(row?.recipient_scope);
  const values = Array.isArray(scope.recipientIds) ? scope.recipientIds : [];
  return [...new Set(values.map((value) => uuid(
    value,
    "agent_email_rule_recipient_id_invalid",
    "Autopilot rules require valid approved recipient IDs.",
  )))];
}

function allowedDaysInput(value, fallback = [0, 1, 2, 3, 4, 5, 6]) {
  const safeFallback = Array.isArray(fallback)
    ? fallback
    : [0, 1, 2, 3, 4, 5, 6];
  const source = Array.isArray(value) ? value : safeFallback;
  const days = [...new Set(source.map((item) => Number(item)))];
  if (!days.length || days.some((day) => !Number.isInteger(day) || day < 0 || day > 6)) {
    fail(
      "Autopilot allowed days must be integers from 0 through 6.",
      "agent_email_rule_allowed_days_invalid",
    );
  }
  return days.sort((a, b) => a - b);
}

function protectedRuleChange(body) {
  return Object.keys(objectValue(body)).some((key) => PROTECTED_RULE_FIELDS.has(key));
}

function normalizeTriggerKey(value) {
  const key = line(value, 120).toLowerCase();
  if (!TRIGGER_KEY.test(key)) {
    fail(
      "Enter a stable Autopilot trigger key using lowercase letters, numbers, dots, colons, underscores, or hyphens.",
      "agent_email_rule_trigger_key_invalid",
    );
  }
  return key;
}

function internalSecretAuthorized(request, environment) {
  const expected = envText(environment, "KORLIX_AGENT_EMAIL_AUTOPILOT_SECRET", 1000);
  if (!expected) {
    fail(
      "The Agent Email Autopilot secret is not configured.",
      "agent_email_autopilot_secret_not_configured",
      503,
    );
  }
  const authorization = header(request, "authorization");
  const supplied = authorization.toLowerCase().startsWith("bearer ")
    ? authorization.slice(7).trim()
    : header(request, "x-korlix-agent-email-secret");
  if (!constantTimeEqual(supplied, expected)) {
    fail(
      "Agent Email Autopilot authentication failed.",
      "agent_email_autopilot_authentication_required",
      401,
    );
  }
  return true;
}

export function createKorlixAgentEmailDeliveryService({
  environment = process.env,
  store,
  loadAgentProfile,
  provider = null,
  now = () => new Date(),
  randomUUID = () => crypto.randomUUID(),
} = {}) {
  if (!store) {
    fail(
      "The Agent Email persistence service is unavailable.",
      "agent_email_database_unavailable",
      503,
    );
  }
  if (typeof loadAgentProfile !== "function") {
    fail(
      "The KORLIX Agent Hub profile loader is unavailable.",
      "agent_email_agent_loader_unavailable",
      503,
    );
  }
  const resend = provider ?? createKorlixAgentEmailResendProvider({ environment });

  async function context({ userId, agentId }) {
    const safeUserId = korlixAgentEmailUserId(userId);
    const safeAgentId = korlixAgentEmailAgentId(agentId);
    const binding = korlixAgentEmailNovaBinding(environment);

    if (!binding.configured) {
      fail(
        "Nova's approved KORLIX Agent Hub binding is not configured.",
        "agent_email_nova_binding_not_configured",
        503,
      );
    }
    if (!korlixAgentEmailIsExistingNova({
      environment,
      userId: safeUserId,
      agentId: safeAgentId,
    })) {
      fail(
        "Agent Email is available only for the existing approved Nova profile.",
        "agent_email_existing_nova_required",
        403,
      );
    }

    let profile;
    try {
      profile = await loadAgentProfile({
        client: store.client,
        userId: safeUserId,
        agentId: safeAgentId,
      });
    } catch (error) {
      throw databaseError(error, "load Nova's Agent Hub profile");
    }

    const profileId = profile
      ? korlixAgentEmailAgentId(profile.id ?? profile.agent_id)
      : "";
    const toolIds = Array.isArray(profile?.toolIds)
      ? profile.toolIds
      : Array.isArray(profile?.tool_ids)
        ? profile.tool_ids
        : [];
    if (
      !profile ||
      profileId !== safeAgentId ||
      profile.isCustom !== true ||
      profile.active === false
    ) {
      fail(
        "Agent Email requires the active custom Nova Agent Hub profile.",
        "agent_email_custom_active_nova_required",
        403,
      );
    }
    if (!toolIds.includes(KORLIX_AGENT_EMAIL_TOOL_ID)) {
      fail(
        "Nova is not authorized to use the Agent Email tool.",
        "agent_email_tool_not_authorized",
        403,
      );
    }

    return Object.freeze({
      userId: safeUserId,
      agentId: safeAgentId,
      binding,
      profile,
      toolIds,
    });
  }

  async function settingsRequired(identity, { autopilot = false } = {}) {
    const row = await store.getSettings(identity.userId, identity.agentId);
    if (!row) {
      fail(
        "Save Nova's Agent Email settings before sending.",
        "agent_email_settings_required",
        409,
      );
    }
    const status = korlixAgentEmailStatus({
      environment,
      userId: identity.userId,
      agentId: identity.agentId,
      toolIds: identity.toolIds,
      settings: settingsForPolicy(row),
    });
    const sendRuntimeEnabled = envFlag(
      environment,
      "KORLIX_AGENT_EMAIL_SEND_ENABLED",
      false,
    );
    const autopilotRuntimeEnabled = envFlag(
      environment,
      "KORLIX_AGENT_EMAIL_AUTOPILOT_ENABLED",
      false,
    );

    if (!sendRuntimeEnabled || !status.canSend) {
      fail(
        "Nova's Agent Email send runtime is disabled or paused.",
        "agent_email_send_runtime_disabled",
        409,
      );
    }
    if (autopilot && (!autopilotRuntimeEnabled || !status.canAutopilot)) {
      fail(
        "Nova's Agent Email Autopilot runtime is disabled or paused.",
        "agent_email_autopilot_runtime_disabled",
        409,
      );
    }
    if (!envText(environment, "KORLIX_AGENT_EMAIL_FROM", 500)) {
      fail(
        "Nova's approved server-controlled From address is not configured.",
        "agent_email_from_not_configured",
        503,
      );
    }

    return Object.freeze({
      row,
      status,
      sendRuntimeEnabled,
      autopilotRuntimeEnabled,
    });
  }

  async function loadMessage(identity, messageId) {
    const safeMessageId = uuid(
      messageId,
      "agent_email_message_id_invalid",
      "Choose a valid Nova email record.",
    );
    const row = await store.getMessage(
      identity.userId,
      identity.agentId,
      safeMessageId,
    );
    if (!row) {
      fail(
        "The selected Nova email record was not found.",
        "agent_email_message_not_found",
        404,
      );
    }
    return row;
  }

  async function loadRecipient(identity, recipientId, marketing = false) {
    const safeRecipientId = uuid(
      recipientId,
      "agent_email_recipient_id_invalid",
      "Choose a valid approved recipient.",
    );
    const row = await store.getRecipient(
      identity.userId,
      identity.agentId,
      safeRecipientId,
    );
    return recipientAllowed(row, marketing);
  }

  async function recordEvent(identity, messageId, eventType, details = {}, providerEventId = null, eventAt = null) {
    return await store.insertEvent({
      user_id: identity.userId,
      agent_id: identity.agentId,
      message_id: messageId,
      event_type: line(eventType, 100),
      provider: "resend",
      provider_event_id: providerEventId ? line(providerEventId, 240) : null,
      event_at: eventAt ?? new Date(now()).toISOString(),
      details: objectValue(details),
    });
  }

  async function enforceDailyCap(identity, settingsRow, ruleId = null, ruleCap = null) {
    const since = zonedDayStart(new Date(now()), line(settingsRow.timezone, 80) || "UTC");
    const total = await store.countSentSince(identity.userId, identity.agentId, since);
    const globalCap = boundedInteger(settingsRow.daily_send_cap, 5, 1, 500);
    if (total >= globalCap) {
      fail(
        "Nova's daily Agent Email send cap has been reached.",
        "agent_email_daily_send_cap_reached",
        429,
      );
    }
    if (ruleId) {
      const ruleTotal = await store.countRuleSentSince(
        identity.userId,
        identity.agentId,
        ruleId,
        since,
      );
      const cap = boundedInteger(ruleCap, 1, 1, 500);
      if (ruleTotal >= cap) {
        fail(
          "This Autopilot rule's daily send cap has been reached.",
          "agent_email_rule_daily_send_cap_reached",
          429,
        );
      }
    }
    return { since, total, globalCap };
  }

  function retryEligibility(message, currentDate) {
    const status = line(message?.status, 40).toLowerCase();
    if (status !== "failed") {
      return Object.freeze({ retry: false, deadlineAt: null });
    }

    const metadata = objectValue(message?.metadata);
    const retryable = metadata.lastFailureRetryable === true;
    const ambiguous = metadata.lastFailureAmbiguous === true;
    const lastAttempt = Date.parse(line(message?.last_attempt_at, 100));
    const configuredDeadline = Date.parse(line(metadata.retryDeadlineAt, 100));
    const deadline = Number.isFinite(configuredDeadline)
      ? configuredDeadline
      : Number.isFinite(lastAttempt)
        ? lastAttempt + PROVIDER_IDEMPOTENCY_SAFE_RETRY_MILLISECONDS
        : Number.NaN;

    if (!retryable) {
      fail(
        "This failed email must be edited and explicitly approved again before sending.",
        "agent_email_message_requires_edit_and_reapproval",
        409,
      );
    }

    if (!Number.isFinite(lastAttempt) || !Number.isFinite(deadline)) {
      fail(
        "This earlier send attempt must be reconciled before another provider request.",
        "agent_email_send_reconciliation_required",
        409,
      );
    }

    if (currentDate.getTime() > deadline) {
      fail(
        ambiguous
          ? "This ambiguous earlier provider request is outside the safe retry window and must be reconciled."
          : "This failed email is outside the safe retry window and must be edited and approved again.",
        ambiguous
          ? "agent_email_send_reconciliation_required"
          : "agent_email_message_requires_edit_and_reapproval",
        409,
      );
    }

    return Object.freeze({
      retry: true,
      deadlineAt: new Date(deadline).toISOString(),
    });
  }

  function assertMarketingSendBoundary(settingsRow, message) {
    if (message.message_kind !== "marketing") return;

    if (!envFlag(
      environment,
      "KORLIX_AGENT_EMAIL_MARKETING_SEND_ENABLED",
      false,
    )) {
      fail(
        "Marketing Agent Email is disabled until its compliance controls are explicitly activated.",
        "agent_email_marketing_send_disabled",
        409,
      );
    }

    if (objectValue(settingsRow?.metadata).marketingEnabled !== true) {
      fail(
        "Enable marketing email in Nova's confirmed settings before sending.",
        "agent_email_marketing_disabled",
        409,
      );
    }

    if (!line(message.physical_address_snapshot, 500)) {
      fail(
        "Marketing email requires Nova's confirmed physical business address.",
        "agent_email_marketing_address_required",
        409,
      );
    }

    approvedHttpsUrl(
      message.unsubscribe_url_snapshot,
      "agent_email_unsubscribe_url_invalid",
      "Marketing email requires an approved HTTPS unsubscribe URL.",
    );
  }

  function assertMessageSendWindow(settingsRow, message, authorizationType) {
    const allowedDays = authorizationType === "preapproved_rule"
      ? objectValue(message.metadata).allowedDays
      : null;

    if (!withinSendWindow(new Date(now()), settingsRow, allowedDays)) {
      fail(
        "Nova's Agent Email send window is currently closed.",
        "agent_email_send_window_closed",
        409,
      );
    }
  }

  async function recordSendAcceptedEvent(
    identity,
    message,
    { source, authorizationType },
  ) {
    const providerMessageId = line(message?.provider_message_id, 240);
    if (!providerMessageId) return null;

    return await recordEvent(
      identity,
      message.id,
      "send_accepted",
      {
        source,
        providerMessageId,
        authorizationType,
      },
      `internal:send-accepted:${providerMessageId}`,
      message.sent_at ?? new Date(now()).toISOString(),
    );
  }

  async function restoreAfterPreProviderAbort({
    identity,
    originalMessage,
    claim,
    source,
    error,
  }) {
    const restored = await store.restoreMessageAfterAbortedClaim({
      userId: identity.userId,
      agentId: identity.agentId,
      messageId: claim.id,
      claimedAt: claim.last_attempt_at,
      patch: {
        status: line(originalMessage.status, 40).toLowerCase(),
        last_attempt_at: originalMessage.last_attempt_at ?? null,
        attempt_count: Math.max(
          0,
          Number(originalMessage.attempt_count) || 0,
        ),
        failure_code: originalMessage.failure_code ?? null,
        failure_message: originalMessage.failure_message ?? null,
        metadata: {
          ...objectValue(originalMessage.metadata),
          lastSendAbortAt: new Date(now()).toISOString(),
          lastSendAbortCode:
            line(error?.code, 120) || "agent_email_pre_provider_abort",
          lastSendAbortSource: source,
        },
      },
    });

    await recordEvent(
      identity,
      claim.id,
      "send_aborted",
      {
        source,
        code: line(error?.code, 120) || "agent_email_pre_provider_abort",
        providerRequestStarted: false,
        restored: Boolean(restored),
      },
      `internal:send-aborted:${claim.id}:${claim.attempt_count}`,
    );

    return restored;
  }

  async function sendAuthorizedMessage({
    identity,
    settingsRow,
    message,
    allowedStatuses,
    authorizationType,
    source,
    confirmationNonceHash = null,
  }) {
    const currentStatus = line(message.status, 40).toLowerCase();
    if (currentStatus === "sent" && message.provider_message_id) {
      await recordSendAcceptedEvent(identity, message, {
        source,
        authorizationType,
      });
      return Object.freeze({
        message: messagePublicView(message),
        replayed: true,
        sent: true,
      });
    }

    if (!allowedStatuses.includes(currentStatus)) {
      fail(
        "This Nova email record is not authorized for sending.",
        "agent_email_message_not_sendable",
        409,
      );
    }

    if (
      line(message.authorization_type, 60).toLowerCase() !==
      authorizationType
    ) {
      fail(
        "The Nova email authorization type does not match this send path.",
        "agent_email_authorization_type_mismatch",
        409,
      );
    }

    if (!message.authorized_at || !message.authorized_by) {
      fail(
        "The Nova email record does not contain a complete authorization.",
        "agent_email_authorization_incomplete",
        409,
      );
    }

    if (
      authorizationType === "one_time_confirmation" &&
      line(message.authorized_by, 80).toLowerCase() !== identity.userId
    ) {
      fail(
        "This email approval belongs to a different KORLIX user.",
        "agent_email_authorized_user_mismatch",
        403,
      );
    }

    const currentDate = new Date(now());
    retryEligibility(message, currentDate);

    if (
      message.scheduled_at &&
      Date.parse(message.scheduled_at) > currentDate.getTime()
    ) {
      fail(
        "This Nova email is scheduled for a later time.",
        "agent_email_scheduled_for_later",
        409,
      );
    }

    assertMarketingSendBoundary(settingsRow, message);
    assertMessageSendWindow(settingsRow, message, authorizationType);

    const recipient = await loadRecipient(
      identity,
      message.recipient_id,
      message.message_kind === "marketing",
    );

    await enforceDailyCap(
      identity,
      settingsRow,
      authorizationType === "preapproved_rule" ? message.rule_id : null,
      objectValue(message.metadata).ruleMaxSendsPerDay,
    );

    const attemptAt = currentDate.toISOString();
    const claim = await store.claimMessageForSend({
      userId: identity.userId,
      agentId: identity.agentId,
      messageId: message.id,
      claimedAt: attemptAt,
      confirmationNonceHash,
    });

    if (!claim) {
      const latest = await loadMessage(identity, message.id);
      if (latest.status === "sent" && latest.provider_message_id) {
        await recordSendAcceptedEvent(identity, latest, {
          source,
          authorizationType,
        });
        return Object.freeze({
          message: messagePublicView(latest),
          replayed: true,
          sent: true,
        });
      }
      fail(
        "Another Agent Email send attempt is already processing this message.",
        "agent_email_send_in_progress",
        409,
      );
    }

    if (claim.status === "sent" && claim.provider_message_id) {
      await recordSendAcceptedEvent(identity, claim, {
        source,
        authorizationType,
      });
      return Object.freeze({
        message: messagePublicView(claim),
        replayed: true,
        sent: true,
      });
    }

    let currentSettingsRow;
    let currentRecipient;

    try {
      currentSettingsRow = (
        await settingsRequired(identity, {
          autopilot: authorizationType === "preapproved_rule",
        })
      ).row;
      assertMarketingSendBoundary(currentSettingsRow, claim);
      assertMessageSendWindow(
        currentSettingsRow,
        claim,
        authorizationType,
      );
      currentRecipient = await loadRecipient(
        identity,
        claim.recipient_id,
        claim.message_kind === "marketing",
      );
    } catch (error) {
      await restoreAfterPreProviderAbort({
        identity,
        originalMessage: message,
        claim,
        source,
        error,
      });
      throw error;
    }

    await recordEvent(
      identity,
      claim.id,
      "send_attempted",
      {
        source,
        recipientId: currentRecipient?.id ?? recipient.id,
        authorizationType,
        attemptCount: claim.attempt_count,
      },
      `internal:send-attempted:${claim.id}:${claim.attempt_count}`,
    );

    let result;
    try {
      result = await resend.send({
        message: claim,
        settings: currentSettingsRow,
      });
    } catch (error) {
      const wrapped = error instanceof KorlixAgentEmailError
        ? error
        : new KorlixAgentEmailError(
            "Resend could not complete the email request.",
            {
              code: "agent_email_resend_failed",
              statusCode: 503,
              cause: error,
            },
          );
      const retryable = Number(wrapped.statusCode) >= 500;
      const ambiguous = retryable;
      const attemptTimestamp = Date.parse(claim.last_attempt_at);
      const retryDeadlineAt = retryable && Number.isFinite(attemptTimestamp)
        ? new Date(
            attemptTimestamp +
              PROVIDER_IDEMPOTENCY_SAFE_RETRY_MILLISECONDS,
          ).toISOString()
        : null;
      const failed = await store.updateMessage(
        identity.userId,
        identity.agentId,
        claim.id,
        {
          status: "failed",
          failure_code: line(wrapped.code, 120),
          failure_message: line(wrapped.message, 600),
          metadata: {
            ...objectValue(claim.metadata),
            lastSendSource: source,
            lastFailureAt: new Date(now()).toISOString(),
            lastFailureRetryable: retryable,
            lastFailureAmbiguous: ambiguous,
            retryDeadlineAt,
          },
        },
      );
      await recordEvent(
        identity,
        claim.id,
        "send_failed",
        {
          source,
          code: line(wrapped.code, 120),
          retryable,
          ambiguous,
          retryDeadlineAt,
        },
        `internal:send-failed:${claim.id}:${claim.attempt_count}`,
      );
      wrapped.messageRecord = messagePublicView(failed);
      throw wrapped;
    }

    const sentAt = new Date(now()).toISOString();
    const sent = await store.updateMessage(
      identity.userId,
      identity.agentId,
      claim.id,
      {
        status: "sent",
        provider: "resend",
        provider_message_id: result.providerMessageId,
        sent_at: sentAt,
        failure_code: null,
        failure_message: null,
        metadata: {
          ...objectValue(claim.metadata),
          lastSendSource: source,
          providerAcceptedAt: sentAt,
          providerIdempotencyKey: result.idempotencyKey,
          deliveryStatus: "accepted",
          lastFailureRetryable: false,
          lastFailureAmbiguous: false,
          retryDeadlineAt: null,
        },
      },
    );

    await recordSendAcceptedEvent(identity, sent, {
      source,
      authorizationType,
    });

    return Object.freeze({
      message: messagePublicView(sent),
      replayed: false,
      sent: true,
    });
  }

  async function normalizeRule({ identity, settingsRow, body, existing = null }) {
    const source = objectValue(body);
    requireConfirmation(
      source,
      "Confirm the exact Agent Email rule before saving it.",
      "agent_email_rule_confirmation_required",
    );
    for (const prohibited of ["recipientEmails", "recipient_emails", "emails", "to", "recipients"]) {
      if (Object.hasOwn(source, prohibited)) {
        fail(
          "Autopilot recipients must come only from explicit approved recipient IDs.",
          "agent_email_rule_recipient_scope_prohibited",
        );
      }
    }

    const existingScope = objectValue(existing?.recipient_scope);
    const existingMetadata = objectValue(existing?.metadata);
    const name = line(source.name ?? existing?.name, 200);
    const triggerKey = normalizeTriggerKey(
      source.triggerKey ?? source.trigger_key ?? existing?.trigger_key,
    );
    const recipientIdsRaw =
      source.recipientIds ??
      source.recipient_ids ??
      existingScope.recipientIds;
    const recipientIds = Array.isArray(recipientIdsRaw)
      ? [...new Set(recipientIdsRaw.map((value) => uuid(
          value,
          "agent_email_rule_recipient_id_invalid",
          "Autopilot rules require valid approved recipient IDs.",
        )))]
      : [];
    const subjectTemplate = line(
      source.subjectTemplate ?? source.subject_template ?? existing?.subject_template,
      200,
    );
    const textTemplate = block(
      source.textTemplate ?? source.text_template ?? existing?.text_template,
      40000,
    );
    const htmlTemplate = block(
      source.htmlTemplate ?? source.html_template ?? existing?.html_template,
      40000,
    );
    const marketing = Object.hasOwn(source, "marketing")
      ? source.marketing === true
      : existing?.marketing === true;
    const sendMode = line(
      source.sendMode ?? source.send_mode ?? existing?.send_mode ?? "draft_only",
      40,
    ).toLowerCase();
    const enabled = Object.hasOwn(source, "enabled")
      ? source.enabled === true
      : existing?.enabled === true;
    const maxSendsPerDay = boundedInteger(
      source.maxSendsPerDay ??
        source.max_sends_per_day ??
        existing?.max_sends_per_day,
      1,
      1,
      500,
    );
    const allowedDays = allowedDaysInput(
      source.allowedDays ?? source.allowed_days,
      existingMetadata.allowedDays,
    );

    if (!name) {
      fail("Enter a name for the Agent Email rule.", "agent_email_rule_name_required");
    }
    const recipientScopeCap = boundedInteger(
      environment?.KORLIX_AGENT_EMAIL_AUTOPILOT_BATCH_CAP,
      20,
      1,
      100,
    );
    if (!recipientIds.length || recipientIds.length > recipientScopeCap) {
      fail(
        `Choose between 1 and ${recipientScopeCap} approved recipients for this rule.`,
        "agent_email_rule_recipient_scope_required",
      );
    }
    if (!subjectTemplate || !textTemplate) {
      fail(
        "Autopilot rules require a preapproved subject and text template.",
        "agent_email_rule_template_required",
      );
    }
    if (!["draft_only", "autopilot"].includes(sendMode)) {
      fail(
        "Choose Draft Only or Approved Autopilot for this rule.",
        "agent_email_rule_send_mode_invalid",
      );
    }
    if (marketing && objectValue(settingsRow.metadata).marketingEnabled !== true) {
      fail(
        "Enable marketing email in Nova's settings before approving a marketing rule.",
        "agent_email_marketing_disabled",
        409,
      );
    }
    if (marketing && !line(settingsRow.physical_address, 500)) {
      fail(
        "Marketing rules require a physical business address in Nova's settings.",
        "agent_email_marketing_address_required",
        409,
      );
    }
    if (marketing) {
      const unsubscribeUrl = line(
        environment?.KORLIX_AGENT_EMAIL_UNSUBSCRIBE_URL,
        1000,
      );
      if (!unsubscribeUrl) {
        fail(
          "Marketing Autopilot requires a server-controlled unsubscribe URL.",
          "agent_email_unsubscribe_url_not_configured",
          503,
        );
      }
      approvedHttpsUrl(
        unsubscribeUrl,
        "agent_email_unsubscribe_url_invalid",
        "Marketing Autopilot requires an approved HTTPS unsubscribe URL.",
      );
    }

    for (const recipientId of recipientIds) {
      await loadRecipient(identity, recipientId, marketing);
    }

    const protectedChanged = existing ? protectedRuleChange(source) : true;
    const previousPreapproval = Boolean(existing?.preapproved_at && existing?.preapproved_by);
    const explicitPreapproval = source.preapproved === true;
    let preapprovedAt = existing?.preapproved_at ?? null;
    let preapprovedBy = existing?.preapproved_by ?? null;
    let nonceHash = line(existingMetadata.preapprovalNonceHash, 64) || null;
    let approvalVersion = Math.max(1, Number(existing?.approval_version) || 1);

    if (sendMode === "autopilot") {
      if (protectedChanged && !explicitPreapproval) {
        fail(
          "Autopilot content or recipients changed. Confirm and preapprove the complete rule again.",
          "agent_email_rule_reapproval_required",
          409,
        );
      }
      if (!previousPreapproval && !explicitPreapproval) {
        fail(
          "Approved Autopilot requires explicit rule preapproval.",
          "agent_email_rule_preapproval_required",
          409,
        );
      }
      if (explicitPreapproval) {
        const nonce = line(
          source.confirmationNonce ?? source.confirmation_nonce,
          240,
        );
        if (nonce.length < 12) {
          fail(
            "A confirmation nonce is required to preapprove this exact Autopilot rule.",
            "agent_email_rule_confirmation_nonce_required",
          );
        }
        preapprovedAt = new Date(now()).toISOString();
        preapprovedBy = identity.userId;
        nonceHash = safeHash(nonce);
        approvalVersion = existing ? approvalVersion + 1 : 1;
      }
    } else {
      preapprovedAt = null;
      preapprovedBy = null;
      nonceHash = null;
      if (protectedChanged && existing) approvalVersion += 1;
    }

    return {
      user_id: identity.userId,
      agent_id: identity.agentId,
      name,
      enabled,
      send_mode: sendMode,
      trigger_key: triggerKey,
      recipient_scope: {
        type: "explicit_ids",
        recipientIds,
      },
      subject_template: subjectTemplate,
      text_template: textTemplate,
      html_template: htmlTemplate,
      marketing,
      max_sends_per_day: maxSendsPerDay,
      preapproved_at: preapprovedAt,
      preapproved_by: preapprovedBy,
      approval_version: approvalVersion,
      metadata: {
        ...existingMetadata,
        allowedDays,
        preapprovalNonceHash: nonceHash,
        lastConfirmedBy: identity.userId,
        lastConfirmedAt: new Date(now()).toISOString(),
      },
    };
  }

  return Object.freeze({
    async getDeliveryStatus({ userId, agentId }) {
      const identity = await context({ userId, agentId });
      const settingsRow = await store.getSettings(identity.userId, identity.agentId);
      const status = korlixAgentEmailStatus({
        environment,
        userId: identity.userId,
        agentId: identity.agentId,
        toolIds: identity.toolIds,
        settings: settingsForPolicy(settingsRow),
      });
      const sendRuntimeEnabled = envFlag(environment, "KORLIX_AGENT_EMAIL_SEND_ENABLED", false);
      const autopilotRuntimeEnabled = envFlag(
        environment,
        "KORLIX_AGENT_EMAIL_AUTOPILOT_ENABLED",
        false,
      );
      return Object.freeze({
        agentId: identity.agentId,
        sameNova: status.sameNova,
        toolAuthorized: status.toolAuthorized,
        settings: settingsPublicView(settingsRow),
        providerConfigured: status.providerConfigured,
        sendRuntimeEnabled,
        autopilotRuntimeEnabled,
        canSend: sendRuntimeEnabled && status.canSend,
        canAutopilot:
          sendRuntimeEnabled && autopilotRuntimeEnabled && status.canAutopilot,
        controlledSendImplemented: true,
        webhookEventsImplemented: true,
        autopilotTriggerImplemented: true,
        autopilotSchedulerConfigured: false,
        autopilotBatchCap: boundedInteger(
          environment?.KORLIX_AGENT_EMAIL_AUTOPILOT_BATCH_CAP,
          20,
          1,
          100,
        ),
        outboundCallingPaused: true,
      });
    },

    async sendApprovedDraft({ userId, agentId, messageId, body }) {
      const identity = await context({ userId, agentId });
      const { row: settingsRow } = await settingsRequired(identity);
      const source = objectValue(body);
      requireConfirmation(
        source,
        "Confirm sending this exact approved Nova email.",
        "agent_email_send_confirmation_required",
      );
      const nonce = line(
        source.confirmationNonce ?? source.confirmation_nonce,
        240,
      );
      if (nonce.length < 12) {
        fail(
          "Use the same confirmation nonce that approved this exact draft.",
          "agent_email_send_confirmation_nonce_required",
        );
      }
      const message = await loadMessage(identity, messageId);
      if (message.status === "sent" && message.provider_message_id) {
        return Object.freeze({
          message: messagePublicView(message),
          replayed: true,
          sent: true,
        });
      }
      if (!SENDABLE_STATUSES.has(line(message.status, 40).toLowerCase())) {
        fail(
          "Only an approved or safely retryable Nova email can be sent.",
          "agent_email_message_not_sendable",
          409,
        );
      }
      if (!constantTimeEqual(safeHash(nonce), message.confirmation_nonce_hash)) {
        fail(
          "The confirmation nonce does not match this exact approved draft.",
          "agent_email_send_confirmation_nonce_mismatch",
          403,
        );
      }
      return await sendAuthorizedMessage({
        identity,
        settingsRow,
        message,
        allowedStatuses: ["approved", "failed"],
        authorizationType: "one_time_confirmation",
        source: "authenticated_one_time_send",
        confirmationNonceHash: safeHash(nonce),
      });
    },

    async listEvents({ userId, agentId, limit = 100 }) {
      const identity = await context({ userId, agentId });
      const rows = await store.listEvents(identity.userId, identity.agentId, {
        limit: boundedInteger(limit, 100, 1, 200),
      });
      return Object.freeze({
        events: rows.map(eventPublicView),
      });
    },

    async listRules({ userId, agentId, limit = 100 }) {
      const identity = await context({ userId, agentId });
      const rows = await store.listRules(identity.userId, identity.agentId, {
        limit: boundedInteger(limit, 100, 1, 200),
      });
      return Object.freeze({
        rules: rows.map(rulePublicView),
      });
    },

    async createRule({ userId, agentId, body }) {
      const identity = await context({ userId, agentId });
      const settingsRow = await store.getSettings(identity.userId, identity.agentId);
      if (!settingsRow) {
        fail(
          "Save Nova's Agent Email settings before creating a rule.",
          "agent_email_settings_required",
          409,
        );
      }
      const row = await store.insertRule({
        id: randomUUID(),
        ...(await normalizeRule({ identity, settingsRow, body })),
      });
      return Object.freeze({
        rule: rulePublicView(row),
        created: true,
        sent: false,
      });
    },

    async updateRule({ userId, agentId, ruleId, body }) {
      const identity = await context({ userId, agentId });
      const safeRuleId = uuid(
        ruleId,
        "agent_email_rule_id_invalid",
        "Choose a valid Agent Email rule.",
      );
      const existing = await store.getRule(identity.userId, identity.agentId, safeRuleId);
      if (!existing) {
        fail(
          "The selected Agent Email rule was not found.",
          "agent_email_rule_not_found",
          404,
        );
      }
      const settingsRow = await store.getSettings(identity.userId, identity.agentId);
      if (!settingsRow) {
        fail(
          "Save Nova's Agent Email settings before updating a rule.",
          "agent_email_settings_required",
          409,
        );
      }
      const row = await store.updateRule(
        identity.userId,
        identity.agentId,
        safeRuleId,
        await normalizeRule({ identity, settingsRow, body, existing }),
      );
      return Object.freeze({
        rule: rulePublicView(row),
        created: false,
        sent: false,
      });
    },

    async processResendWebhook({ rawBody, headers }) {
      const secret =
        envText(environment, "KORLIX_AGENT_EMAIL_RESEND_WEBHOOK_SECRET", 1000) ||
        envText(environment, "RESEND_WEBHOOK_SECRET", 1000);
      const verified = verifyKorlixAgentEmailResendWebhook({
        rawBody,
        headers,
        secret,
        now,
      });
      const event = objectValue(verified.event);
      const eventType = line(event.type, 100).toLowerCase();
      const data = objectValue(event.data);
      const providerMessageId = line(data.email_id ?? data.emailId, 240);
      if (!DELIVERY_EVENTS.has(eventType) || !providerMessageId) {
        return Object.freeze({
          accepted: true,
          matched: false,
          replayed: false,
          eventType,
        });
      }

      const previous = await store.findEventByProviderEventId(
        "resend",
        verified.providerEventId,
      );
      if (previous) {
        return Object.freeze({
          accepted: true,
          matched: true,
          replayed: true,
          event: eventPublicView(previous),
        });
      }

      const message = await store.findMessageByProviderId("resend", providerMessageId);
      if (!message) {
        return Object.freeze({
          accepted: true,
          matched: false,
          replayed: false,
          eventType,
        });
      }
      const identity = Object.freeze({
        userId: korlixAgentEmailUserId(message.user_id),
        agentId: korlixAgentEmailAgentId(message.agent_id),
      });
      const metadata = objectValue(message.metadata);
      const eventAtRaw = line(event.created_at ?? data.created_at, 100);
      const eventAt = Number.isFinite(Date.parse(eventAtRaw))
        ? new Date(eventAtRaw).toISOString()
        : new Date(now()).toISOString();
      const priorProviderAt = Date.parse(
        line(metadata.lastProviderEventAt, 100),
      );
      const incomingProviderAt = Date.parse(eventAt);
      const terminalFailure = TERMINAL_FAILURE_EVENTS.has(eventType);
      const isNewestProviderEvent =
        !Number.isFinite(priorProviderAt) ||
        !Number.isFinite(incomingProviderAt) ||
        incomingProviderAt >= priorProviderAt;
      const patch = {
        metadata: {
          ...metadata,
          ...(terminalFailure || isNewestProviderEvent
            ? {
                deliveryStatus: eventType,
                lastProviderEventAt: eventAt,
              }
            : {}),
        },
      };

      if (eventType === "email.delivered") {
        patch.metadata.deliveredAt = metadata.deliveredAt ?? eventAt;
        if (!["failed", "suppressed"].includes(message.status)) patch.status = "sent";
      } else if (["email.sent", "email.delivery_delayed", "email.opened", "email.clicked"].includes(eventType)) {
        if (!["failed", "suppressed"].includes(message.status)) patch.status = "sent";
      } else if (eventType === "email.suppressed") {
        patch.status = "suppressed";
        patch.failure_code = "resend_suppressed";
        patch.failure_message = "Resend suppressed this recipient.";
      } else {
        patch.status = "failed";
        patch.failure_code = eventType.replaceAll(".", "_");
        patch.failure_message = line(
          data?.failed?.reason ??
            data?.bounce?.message ??
            `Resend reported ${eventType}.`,
          600,
        );
      }

      const updated = await store.updateMessage(
        identity.userId,
        identity.agentId,
        message.id,
        patch,
      );

      if (["email.bounced", "email.complained", "email.suppressed"].includes(eventType)) {
        const recipient = await store.getRecipient(
          identity.userId,
          identity.agentId,
          message.recipient_id,
        );
        if (recipient) {
          await store.updateRecipient(
            identity.userId,
            identity.agentId,
            recipient.id,
            {
              consent_status: "suppressed",
              active: false,
              suppressed_at: eventAt,
              suppression_reason: line(
                data?.bounce?.message ??
                  (eventType === "email.complained"
                    ? "Recipient marked the email as spam."
                    : "Resend suppression event."),
                500,
              ),
              metadata: {
                ...objectValue(recipient.metadata),
                suppressedByProvider: "resend",
                suppressedByEvent: eventType,
                suppressedAt: eventAt,
              },
            },
          );
        }
      }

      const eventRow = await recordEvent(
        identity,
        message.id,
        eventType,
        {
          providerMessageId,
          to: Array.isArray(data.to)
            ? data.to.slice(0, 10).map((value) => line(value, 320))
            : [],
          reason: line(data?.failed?.reason ?? data?.bounce?.message, 600) || null,
        },
        verified.providerEventId,
        eventAt,
      );

      return Object.freeze({
        accepted: true,
        matched: true,
        replayed: false,
        message: messagePublicView(updated),
        event: eventPublicView(eventRow),
      });
    },

    async runAutopilot({ body }) {
      const source = objectValue(body);
      if (
        Object.hasOwn(source, "recipientIds") ||
        Object.hasOwn(source, "recipient_ids") ||
        Object.hasOwn(source, "emails") ||
        Object.hasOwn(source, "to")
      ) {
        fail(
          "Autopilot cannot accept model-selected or request-selected recipients.",
          "agent_email_autopilot_recipient_override_prohibited",
          403,
        );
      }
      const binding = korlixAgentEmailNovaBinding(environment);
      if (!binding.configured) {
        fail(
          "Nova's approved KORLIX Agent Hub binding is not configured.",
          "agent_email_nova_binding_not_configured",
          503,
        );
      }
      const identity = await context({
        userId: binding.ownerUid,
        agentId: binding.agentId,
      });
      const { row: settingsRow } = await settingsRequired(identity, {
        autopilot: true,
      });
      const triggerKey = normalizeTriggerKey(
        source.triggerKey ?? source.trigger_key,
      );
      const eventId = line(source.eventId ?? source.event_id, 200);
      if (!eventId) {
        fail(
          "Autopilot requires a stable event ID for duplicate prevention.",
          "agent_email_autopilot_event_id_required",
        );
      }
      const variables = normalizeVariables(source.variables);
      const rules = await store.listEnabledRulesByTrigger(
        identity.userId,
        identity.agentId,
        triggerKey,
      );
      const batchCap = boundedInteger(
        environment?.KORLIX_AGENT_EMAIL_AUTOPILOT_BATCH_CAP,
        20,
        1,
        100,
      );
      const results = [];
      let attempted = 0;

      for (const rule of rules) {
        if (attempted >= batchCap) break;
        if (!rule.preapproved_at || !rule.preapproved_by) {
          results.push({ ruleId: rule.id, skipped: "not_preapproved" });
          continue;
        }
        const metadata = objectValue(rule.metadata);
        const allowedDays = allowedDaysInput(metadata.allowedDays);
        if (!withinSendWindow(new Date(now()), settingsRow, allowedDays)) {
          results.push({ ruleId: rule.id, skipped: "send_window_closed" });
          continue;
        }

        for (const recipientId of ruleRecipientIds(rule)) {
          if (attempted >= batchCap) break;
          attempted += 1;
          const recipient = await loadRecipient(identity, recipientId, rule.marketing === true);
          const idempotencyKey = [
            "autopilot",
            rule.id,
            safeHash(eventId).slice(0, 32),
            recipient.id,
          ].join(":");
          let message = await store.findMessageByIdempotency(
            identity.userId,
            identity.agentId,
            idempotencyKey,
          );

          if (!message) {
            const templateVariables = {
              ...variables,
              recipient_name: line(recipient.display_name, 160),
              recipient_email: korlixAgentEmailAddress(recipient.email),
              event_id: eventId,
            };
            const subject = korlixAgentEmailRenderTemplate(
              rule.subject_template,
              templateVariables,
            );
            const textBody = korlixAgentEmailRenderTemplate(
              rule.text_template,
              templateVariables,
            );
            const htmlBody = rule.html_template
              ? korlixAgentEmailRenderTemplate(
                  rule.html_template,
                  templateVariables,
                  { html: true },
                )
              : "";
            const createdAt = new Date(now()).toISOString();
            message = await store.insertMessage({
              id: randomUUID(),
              user_id: identity.userId,
              agent_id: identity.agentId,
              recipient_id: recipient.id,
              rule_id: rule.id,
              to_email: korlixAgentEmailAddress(recipient.email),
              subject: line(subject, 200),
              text_body: textBody,
              html_body: htmlBody,
              message_kind: rule.marketing === true ? "marketing" : "transactional",
              status: "approved",
              authorization_type: "preapproved_rule",
              authorized_at: rule.preapproved_at,
              authorized_by: rule.preapproved_by,
              confirmation_nonce_hash: null,
              idempotency_key: idempotencyKey,
              provider: "resend",
              provider_message_id: null,
              physical_address_snapshot:
                rule.marketing === true ? line(settingsRow.physical_address, 500) : "",
              unsubscribe_url_snapshot:
                rule.marketing === true
                  ? line(
                      environment?.KORLIX_AGENT_EMAIL_UNSUBSCRIBE_URL,
                      1000,
                    )
                  : "",
              scheduled_at: null,
              last_attempt_at: null,
              attempt_count: 0,
              sent_at: null,
              failure_code: null,
              failure_message: null,
              metadata: {
                source: "preapproved_autopilot_rule",
                eventIdHash: safeHash(eventId),
                triggerKey,
                allowedDays,
                ruleMaxSendsPerDay: rule.max_sends_per_day,
                ruleApprovalVersion: rule.approval_version,
                createdAt,
              },
            });
            await recordEvent(identity, message.id, "autopilot_message_created", {
              ruleId: rule.id,
              recipientId: recipient.id,
              triggerKey,
            });
          }

          try {
            const sent = await sendAuthorizedMessage({
              identity,
              settingsRow,
              message,
              allowedStatuses: ["approved", "failed"],
              authorizationType: "preapproved_rule",
              source: "preapproved_autopilot_rule",
            });
            results.push({
              ruleId: rule.id,
              recipientId: recipient.id,
              messageId: sent.message.id,
              sent: sent.sent,
              replayed: sent.replayed,
            });
          } catch (error) {
            results.push({
              ruleId: rule.id,
              recipientId: recipient.id,
              messageId: message.id,
              sent: false,
              code: line(error?.code, 120) || "agent_email_autopilot_send_failed",
            });
          }
        }
      }

      return Object.freeze({
        triggerKey,
        eventIdHash: safeHash(eventId),
        matchedRuleCount: rules.length,
        attempted,
        sentCount: results.filter((item) => item.sent === true && item.replayed !== true).length,
        replayedCount: results.filter((item) => item.replayed === true).length,
        results,
        schedulerConfigured: false,
      });
    },
  });
}

function responseError(res, error, fallback) {
  const statusCode = Number.isInteger(error?.statusCode) ? error.statusCode : 500;
  const publicMessage = statusCode >= 500
    ? fallback
    : line(error?.message, 600) || fallback;
  return res.status(statusCode).json({
    ok: false,
    code: line(error?.code, 120) || "agent_email_delivery_failed",
    error: publicMessage,
    sent: false,
  });
}

function authenticatedRoute({ requireUser, service, logger, fallback, handler }) {
  return async (req, res) => {
    try {
      const authenticated = await requireUser(req);
      const user =
        authenticated?.user ?? authenticated?.data?.user ?? authenticated;
      const userId = user?.id ?? user?.user_id ?? user?.uid;
      return await handler({
        req,
        res,
        userId,
        agentId: req.params.agentId,
        service,
      });
    } catch (error) {
      if (
        Number(error?.statusCode || 500) >= 500 &&
        typeof logger?.error === "function"
      ) {
        logger.error("KORLIX_AGENT_EMAIL_DELIVERY_ROUTE_FAILED", {
          code: line(error?.code, 120) || "agent_email_delivery_failed",
        });
      }
      return responseError(res, error, fallback);
    }
  };
}

export function installKorlixAgentEmailDeliveryRoutes(
  app,
  {
    environment = process.env,
    supabaseAdmin = null,
    store = null,
    requireUser,
    loadAgentProfile,
    provider = null,
    fetchImpl = globalThis.fetch,
    logger = console,
    now = () => new Date(),
    randomUUID = () => crypto.randomUUID(),
  } = {},
) {
  if (
    !app ||
    typeof app.get !== "function" ||
    typeof app.post !== "function" ||
    typeof app.patch !== "function"
  ) {
    throw new TypeError("An Express-compatible application is required.");
  }
  if (typeof requireUser !== "function") {
    throw new TypeError("The authenticated KORLIX user loader is required.");
  }

  const persistence = store ?? createKorlixAgentEmailSupabaseStore(supabaseAdmin);
  const resend = provider ?? createKorlixAgentEmailResendProvider({
    environment,
    fetchImpl,
  });
  const service = createKorlixAgentEmailDeliveryService({
    environment,
    store: persistence,
    loadAgentProfile,
    provider: resend,
    now,
    randomUUID,
  });
  const route = (fallback, handler) =>
    authenticatedRoute({
      requireUser,
      service,
      logger,
      fallback,
      handler,
    });
  const routes = KORLIX_AGENT_EMAIL_DELIVERY_ROUTES;

  app.get(
    routes.deliveryStatus,
    route(
      "Could not load Nova's Agent Email delivery status.",
      async ({ res, userId, agentId }) =>
        res.json({
          ok: true,
          status: await service.getDeliveryStatus({ userId, agentId }),
        }),
    ),
  );

  app.post(
    routes.sendDraft,
    route(
      "Could not send Nova's approved email.",
      async ({ req, res, userId, agentId }) =>
        res.json({
          ok: true,
          ...(await service.sendApprovedDraft({
            userId,
            agentId,
            messageId: req.params.messageId,
            body: req.body,
          })),
        }),
    ),
  );

  app.get(
    routes.events,
    route(
      "Could not load Nova's Agent Email events.",
      async ({ req, res, userId, agentId }) =>
        res.json({
          ok: true,
          ...(await service.listEvents({
            userId,
            agentId,
            limit: req.query?.limit,
          })),
        }),
    ),
  );

  app.get(
    routes.rules,
    route(
      "Could not load Nova's Agent Email rules.",
      async ({ req, res, userId, agentId }) =>
        res.json({
          ok: true,
          ...(await service.listRules({
            userId,
            agentId,
            limit: req.query?.limit,
          })),
        }),
    ),
  );

  app.post(
    routes.rules,
    route(
      "Could not create Nova's Agent Email rule.",
      async ({ req, res, userId, agentId }) =>
        res.status(201).json({
          ok: true,
          ...(await service.createRule({
            userId,
            agentId,
            body: req.body,
          })),
        }),
    ),
  );

  app.patch(
    routes.rule,
    route(
      "Could not update Nova's Agent Email rule.",
      async ({ req, res, userId, agentId }) =>
        res.json({
          ok: true,
          ...(await service.updateRule({
            userId,
            agentId,
            ruleId: req.params.ruleId,
            body: req.body,
          })),
        }),
    ),
  );

  app.post(routes.resendWebhook, async (req, res) => {
    try {
      const result = await service.processResendWebhook({
        rawBody: req.korlixAgentEmailRawBody,
        headers: req.headers,
      });
      return res.status(200).json({ ok: true, ...result });
    } catch (error) {
      if (
        Number(error?.statusCode || 500) >= 500 &&
        typeof logger?.error === "function"
      ) {
        logger.error("KORLIX_AGENT_EMAIL_WEBHOOK_FAILED", {
          code: line(error?.code, 120) || "agent_email_webhook_failed",
        });
      }
      return responseError(
        res,
        error,
        "Could not process the Resend delivery event.",
      );
    }
  });

  app.post(routes.autopilotRun, async (req, res) => {
    try {
      internalSecretAuthorized(req, environment);
      return res.json({
        ok: true,
        ...(await service.runAutopilot({ body: req.body })),
      });
    } catch (error) {
      if (
        Number(error?.statusCode || 500) >= 500 &&
        typeof logger?.error === "function"
      ) {
        logger.error("KORLIX_AGENT_EMAIL_AUTOPILOT_ROUTE_FAILED", {
          code: line(error?.code, 120) || "agent_email_autopilot_failed",
        });
      }
      return responseError(
        res,
        error,
        "Could not run Nova's Agent Email Autopilot trigger.",
      );
    }
  });

  return Object.freeze({
    routes,
    controlledSendImplemented: true,
    webhookEventsImplemented: true,
    autopilotTriggerImplemented: true,
    autopilotSchedulerConfigured: false,
    emailSentDuringInstall: false,
    outboundCallingPaused: true,
  });
}
