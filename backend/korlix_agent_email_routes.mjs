import crypto from "node:crypto";

import {
  KORLIX_AGENT_EMAIL_TOOL_ID,
  KorlixAgentEmailError,
  korlixAgentEmailAddress,
  korlixAgentEmailAgentId,
  korlixAgentEmailDraftInput,
  korlixAgentEmailIsExistingNova,
  korlixAgentEmailNovaBinding,
  korlixAgentEmailRecipientInput,
  korlixAgentEmailSettingsInput,
  korlixAgentEmailStatus,
  korlixAgentEmailUserId,
} from "./korlix_agent_email.mjs";

export const KORLIX_AGENT_EMAIL_TABLES = Object.freeze({
  settings: "korlix_agent_email_settings",
  recipients: "korlix_agent_email_recipients",
  rules: "korlix_agent_email_rules",
  messages: "korlix_agent_email_messages",
  events: "korlix_agent_email_events",
});

const PREFIX = "/api/live-convo/agents/:agentId/email";

export const KORLIX_AGENT_EMAIL_DRAFT_ROUTES = Object.freeze({
  status: `${PREFIX}/status`,
  settings: `${PREFIX}/settings`,
  recipients: `${PREFIX}/recipients`,
  recipient: `${PREFIX}/recipients/:recipientId`,
  drafts: `${PREFIX}/drafts`,
  draft: `${PREFIX}/drafts/:messageId`,
  approveDraft: `${PREFIX}/drafts/:messageId/approve`,
  deleteDraft: `${PREFIX}/drafts/:messageId`,
});

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const EDITABLE_MESSAGE_STATUSES = new Set([
  "draft",
  "pending_approval",
  "approved",
  "failed",
]);

// K134B_SAFE_DRAFT_DELETE_V1_BEGIN
const DELETABLE_MESSAGE_STATUSES = new Set([
  "draft",
  "pending_approval",
  "approved",
  "failed",
]);
const TYPED_DRAFT_DELETE_STATUSES = new Set([
  "approved",
  "failed",
]);
const DRAFT_DELETE_CONFIRMATION_PHRASE = "DELETE DRAFT";
// K134B_SAFE_DRAFT_DELETE_V1_END

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

function isoTimestamp(
  value,
  {
    allowNull = true,
    code = "agent_email_timestamp_invalid",
    message = "Enter a valid date and time.",
  } = {},
) {
  const text = line(value, 100);

  if (!text && allowNull) {
    return null;
  }

  const timestamp = Date.parse(text);

  if (!Number.isFinite(timestamp)) {
    fail(message, code);
  }

  return new Date(timestamp).toISOString();
}

function databaseUniqueViolation(error) {
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

  return code === "23505" || detail.includes("duplicate key");
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

  const rpcCode = detail.match(/\bagent_email_[a-z0-9_]+\b/)?.[0] ?? "";
  if (code === "P0001" && rpcCode) {
    const rateLimited = new Set([
      "agent_email_daily_cap_reached",
      "agent_email_rule_daily_cap_reached",
    ]).has(rpcCode);
    const notFound = new Set([
      "agent_email_message_not_found",
      "agent_email_recipient_not_found",
      "agent_email_rule_not_found",
    ]).has(rpcCode);
    const serverFault = new Set([
      "agent_email_claimed_at_invalid",
      "agent_email_timezone_invalid",
    ]).has(rpcCode);
    const forbidden = new Set([
      "agent_email_confirmation_nonce_mismatch",
      "agent_email_authorized_user_mismatch",
      "agent_email_rule_authorization_stale",
    ]).has(rpcCode);
    const reconciliation = rpcCode === "agent_email_send_reconciliation_required";
    const requiresEdit = rpcCode === "agent_email_message_requires_edit_and_reapproval";

    return new KorlixAgentEmailError(
      rateLimited
        ? "Nova's Agent Email daily send limit has been reached."
        : notFound
          ? "The selected Agent Email record was not found."
          : serverFault
            ? "The controlled Agent Email send clock or timezone could not be verified."
            : forbidden
              ? "The current authorization no longer matches this exact Nova email."
              : reconciliation
                ? "This earlier send attempt must be reconciled before another provider request."
                : requiresEdit
                  ? "This failed email must be edited and explicitly approved again before sending."
                  : "The controlled Agent Email send was blocked by a server safety rule.",
      {
        code: rpcCode,
        statusCode: rateLimited
          ? 429
          : notFound
            ? 404
            : serverFault
              ? 500
              : forbidden
                ? 403
                : 409,
        cause: error,
      },
    );
  }

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

async function query(pending, operation) {
  let result;

  try {
    result = await pending;
  } catch (error) {
    throw databaseError(error, operation);
  }

  if (result?.error) {
    throw databaseError(result.error, operation);
  }

  return result?.data ?? null;
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
  if (!row) {
    return null;
  }

  const metadata = objectValue(row.metadata);

  return Object.freeze({
    id: line(row.id, 80),
    agentId: line(row.agent_id, 96).toLowerCase(),
    email: line(row.email, 320).toLowerCase(),
    displayName: line(row.display_name, 160),
    sourceKind: line(row.source_kind, 80).toLowerCase(),
    sourceReference: line(row.source_reference, 500) || null,
    approvalSource:
      line(
        metadata.approvalSource ??
          metadata.approval_source ??
          row.consent_source,
        80,
      ).toLowerCase() || null,
    consentStatus: line(row.consent_status, 80).toLowerCase(),
    consentAt: row.consent_recorded_at ?? null,
    unsubscribedAt: row.unsubscribed_at ?? null,
    suppressedAt: row.suppressed_at ?? null,
    suppressionReason: line(row.suppression_reason, 500) || null,
    active: row.active !== false,
    createdAt: row.created_at ?? null,
    updatedAt: row.updated_at ?? null,
  });
}

function messagePublicView(row) {
  if (!row) {
    return null;
  }

  const status = line(row.status, 40).toLowerCase() || "draft";
  const metadata = objectValue(row.metadata);
  const providerMessageId = line(row.provider_message_id, 240) || null;
  const lastFailureAmbiguous =
    metadata.lastFailureAmbiguous === true ||
    metadata.last_failure_ambiguous === true;
  const canDelete =
    DELETABLE_MESSAGE_STATUSES.has(status) &&
    !row.sent_at &&
    !providerMessageId &&
    !lastFailureAmbiguous;

  return Object.freeze({
    id: line(row.id, 80),
    agentId: line(row.agent_id, 96).toLowerCase(),
    recipientId: line(row.recipient_id, 80) || null,
    ruleId: line(row.rule_id, 80) || null,
    toEmail: line(row.to_email, 320).toLowerCase(),
    subject: line(row.subject, 240),
    textBody: String(row.text_body ?? ""),
    htmlBody: String(row.html_body ?? ""),
    messageKind:
      line(row.message_kind, 40).toLowerCase() || "transactional",
    status,
    authorizationType:
      line(row.authorization_type, 60).toLowerCase() || "none",
    authorizedAt: row.authorized_at ?? null,
    authorizedBy: line(row.authorized_by, 80) || null,
    scheduledAt: row.scheduled_at ?? null,
    physicalAddress: line(row.physical_address_snapshot, 500),
    unsubscribeUrl: line(row.unsubscribe_url_snapshot, 1000),
    idempotencyKey: line(row.idempotency_key, 240),
    provider: line(row.provider, 40).toLowerCase() || "resend",    providerMessageId,
    lastAttemptAt: row.last_attempt_at ?? null,
    attemptCount: boundedInteger(row.attempt_count, 0, 0, 100),
    sentAt: row.sent_at ?? null,
    failureCode: line(row.failure_code, 120) || null,
    failureMessage: line(row.failure_message, 600) || null,
    canDelete,
    deleteConfirmationRequired:
      canDelete && TYPED_DRAFT_DELETE_STATUSES.has(status),
    canEdit: EDITABLE_MESSAGE_STATUSES.has(status),
    canApprove: status === "draft" || status === "pending_approval",
    sent: status === "sent",
    createdAt: row.created_at ?? null,
    updatedAt: row.updated_at ?? null,
  });
}

function settingsForPolicy(row) {
  return {
    enabled: row?.enabled === true,
    paused: row ? row.emergency_paused !== false : true,
    mode: line(row?.operating_mode, 40).toLowerCase() || "draft_only",
  };
}

export function createKorlixAgentEmailSupabaseStore(client) {
  if (
    !client ||
    typeof client.from !== "function" ||
    typeof client.rpc !== "function"
  ) {
    fail(
      "The Agent Email persistence service is unavailable.",
      "agent_email_database_unavailable",
      503,
    );
  }

  const tables = KORLIX_AGENT_EMAIL_TABLES;

  return Object.freeze({
    client,

    async getSettings(userId, agentId) {
      return await query(
        client
          .from(tables.settings)
          .select("*")
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .maybeSingle(),
        "load Nova's Agent Email settings",
      );
    },

    async saveSettings(row) {
      return await query(
        client
          .from(tables.settings)
          .upsert(row, {
            onConflict: "user_id,agent_id",
          })
          .select("*")
          .single(),
        "save Nova's Agent Email settings",
      );
    },

    async listRecipients(userId, agentId, { limit = 100 } = {}) {
      return (
        (await query(
          client
            .from(tables.recipients)
            .select("*")
            .eq("user_id", userId)
            .eq("agent_id", agentId)
            .order("updated_at", { ascending: false })
            .limit(limit),
          "list Nova's approved email recipients",
        )) ?? []
      );
    },

    async getRecipient(userId, agentId, recipientId) {
      return await query(
        client
          .from(tables.recipients)
          .select("*")
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .eq("id", recipientId)
          .maybeSingle(),
        "load the approved email recipient",
      );
    },

    async findRecipientByEmail(userId, agentId, email) {
      return await query(
        client
          .from(tables.recipients)
          .select("*")
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .eq("email", email)
          .maybeSingle(),
        "find the approved email recipient",
      );
    },

    async insertRecipient(row) {
      return await query(
        client
          .from(tables.recipients)
          .insert(row)
          .select("*")
          .single(),
        "save the approved email recipient",
      );
    },

    async updateRecipient(userId, agentId, recipientId, patch) {
      return await query(
        client
          .from(tables.recipients)
          .update(patch)
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .eq("id", recipientId)
          .select("*")
          .single(),
        "update the approved email recipient",
      );
    },

    async listMessages(userId, agentId, { limit = 100 } = {}) {
      return (
        (await query(
          client
            .from(tables.messages)
            .select("*")
            .eq("user_id", userId)
            .eq("agent_id", agentId)
            .order("created_at", { ascending: false })
            .limit(limit),
          "list Nova's email drafts",
        )) ?? []
      );
    },

    async getMessage(userId, agentId, messageId) {
      return await query(
        client
          .from(tables.messages)
          .select("*")
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .eq("id", messageId)
          .maybeSingle(),
        "load Nova's email draft",
      );
    },

    async findMessageByIdempotency(userId, agentId, idempotencyKey) {
      return await query(
        client
          .from(tables.messages)
          .select("*")
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .eq("idempotency_key", idempotencyKey)
          .maybeSingle(),
        "replay Nova's idempotent email draft",
      );
    },

    async findMessageByProviderId(provider, providerMessageId) {
      return await query(
        client
          .from(tables.messages)
          .select("*")
          .eq("provider", provider)
          .eq("provider_message_id", providerMessageId)
          .maybeSingle(),
        "match the Resend delivery event",
      );
    },

    async insertMessage(row) {
      let result;

      try {
        result = await client
          .from(tables.messages)
          .insert(row)
          .select("*")
          .single();
      } catch (error) {
        if (databaseUniqueViolation(error) && row?.idempotency_key) {
          return await this.findMessageByIdempotency(
            row.user_id,
            row.agent_id,
            row.idempotency_key,
          );
        }
        throw databaseError(error, "save Nova's email draft");
      }

      if (result?.error) {
        if (databaseUniqueViolation(result.error) && row?.idempotency_key) {
          const existing = await this.findMessageByIdempotency(
            row.user_id,
            row.agent_id,
            row.idempotency_key,
          );
          if (existing) return existing;
        }
        throw databaseError(result.error, "save Nova's email draft");
      }

      return result?.data ?? null;
    },

    async updateMessage(userId, agentId, messageId, patch) {
      return await query(
        client
          .from(tables.messages)
          .update(patch)
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .eq("id", messageId)
          .select("*")
          .single(),
        "update Nova's email draft",
      );
    },

    async cancelMessage(userId, agentId, messageId, patch) {
      return await query(
        client
          .from(tables.messages)
          .update(patch)
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .eq("id", messageId)
          .in("status", [...DELETABLE_MESSAGE_STATUSES])
          .is("provider_message_id", null)
          .is("sent_at", null)
          .select("*")
          .maybeSingle(),
        "cancel Nova's unsent email draft",
      );
    },

    async claimMessageForSend({
      userId,
      agentId,
      messageId,
      claimedAt,
      confirmationNonceHash = null,
    }) {
      const data = await query(
        client.rpc("korlix_agent_email_claim_send_build133", {
          p_user_id: userId,
          p_agent_id: agentId,
          p_message_id: messageId,
          p_claimed_at: claimedAt,
          p_confirmation_nonce_hash: confirmationNonceHash,
        }),
        "claim Nova's email for a controlled send",
      );

      return Array.isArray(data) ? data[0] ?? null : data;
    },

    async restoreMessageAfterAbortedClaim({
      userId,
      agentId,
      messageId,
      claimedAt,
      patch,
    }) {
      return await query(
        client
          .from(tables.messages)
          .update(patch)
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .eq("id", messageId)
          .eq("status", "sending")
          .eq("last_attempt_at", claimedAt)
          .select("*")
          .maybeSingle(),
        "restore Nova's email after a pre-provider safety abort",
      );
    },

    async countSentSince(userId, agentId, since) {
      let result;

      try {
        result = await client
          .from(tables.messages)
          .select("id", { count: "exact", head: true })
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .eq("status", "sent")
          .gte("sent_at", since);
      } catch (error) {
        throw databaseError(error, "count Nova's daily email sends");
      }

      if (result?.error) {
        throw databaseError(result.error, "count Nova's daily email sends");
      }

      return Math.max(0, Number(result?.count) || 0);
    },

    // K134B_AUTHORITATIVE_DAILY_USAGE_V1_STORE_BEGIN
    async countSendingSince(userId, agentId, since) {
      let result;

      try {
        result = await client
          .from(tables.messages)
          .select("id", { count: "exact", head: true })
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .eq("status", "sending")
          .gte("last_attempt_at", since);
      } catch (error) {
        throw databaseError(
          error,
          "count Nova's in-flight daily email sends",
        );
      }

      if (result?.error) {
        throw databaseError(
          result.error,
          "count Nova's in-flight daily email sends",
        );
      }

      return Math.max(
        0,
        Number(result?.count) || 0,
      );
    },
    // K134B_AUTHORITATIVE_DAILY_USAGE_V1_STORE_END

    async countRuleSentSince(userId, agentId, ruleId, since) {
      let result;

      try {
        result = await client
          .from(tables.messages)
          .select("id", { count: "exact", head: true })
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .eq("rule_id", ruleId)
          .eq("status", "sent")
          .gte("sent_at", since);
      } catch (error) {
        throw databaseError(error, "count the Autopilot rule's daily sends");
      }

      if (result?.error) {
        throw databaseError(
          result.error,
          "count the Autopilot rule's daily sends",
        );
      }

      return Math.max(0, Number(result?.count) || 0);
    },

    async listRules(userId, agentId, { limit = 100 } = {}) {
      return (
        (await query(
          client
            .from(tables.rules)
            .select("*")
            .eq("user_id", userId)
            .eq("agent_id", agentId)
            .is("deleted_at", null)
            .order("updated_at", { ascending: false })
            .limit(limit),
          "list Nova's Agent Email rules",
        )) ?? []
      );
    },

    async getRule(userId, agentId, ruleId) {
      return await query(
        client
          .from(tables.rules)
          .select("*")
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .eq("id", ruleId)
          .is("deleted_at", null)
          .maybeSingle(),
        "load Nova's Agent Email rule",
      );
    },

    async listEnabledRulesByTrigger(userId, agentId, triggerKey) {
      return (
        (await query(
          client
            .from(tables.rules)
            .select("*")
            .eq("user_id", userId)
            .eq("agent_id", agentId)
            .eq("enabled", true)
            .eq("send_mode", "autopilot")
            .eq("schedule_type", "event")
            .eq("trigger_key", triggerKey)
            .is("deleted_at", null)
            .order("created_at", { ascending: true }),
          "load Nova's preapproved Autopilot rules",
        )) ?? []
      );
    },

    async listDueScheduledRules(
      userId,
      agentId,
      dueAt,
      { limit = 20 } = {},
    ) {
      return (
        (await query(
          client
            .from(tables.rules)
            .select("*")
            .eq("user_id", userId)
            .eq("agent_id", agentId)
            .eq("enabled", true)
            .eq("send_mode", "autopilot")
            .in("schedule_type", ["once", "weekly"])
            .is("deleted_at", null)
            .lte("next_run_at", dueAt)
            .order("next_run_at", { ascending: true })
            .limit(limit),
          "load Nova's due scheduled Agent Email rules",
        )) ?? []
      );
    },

    async insertRule(row) {
      return await query(
        client
          .from(tables.rules)
          .insert(row)
          .select("*")
          .single(),
        "save Nova's Agent Email rule",
      );
    },

    async updateRule(userId, agentId, ruleId, patch) {
      return await query(
        client
          .from(tables.rules)
          .update(patch)
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .eq("id", ruleId)
          .is("deleted_at", null)
          .select("*")
          .single(),
        "update Nova's Agent Email rule",
      );
    },

    async softDeleteRule(userId, agentId, ruleId, patch) {
      return await query(
        client
          .from(tables.rules)
          .update(patch)
          .eq("user_id", userId)
          .eq("agent_id", agentId)
          .eq("id", ruleId)
          .is("deleted_at", null)
          .select("*")
          .maybeSingle(),
        "delete Nova's Agent Email rule",
      );
    },

    async listEvents(userId, agentId, { limit = 100 } = {}) {
      return (
        (await query(
          client
            .from(tables.events)
            .select("*")
            .eq("user_id", userId)
            .eq("agent_id", agentId)
            .order("event_at", { ascending: false })
            .limit(limit),
          "list Nova's Agent Email audit events",
        )) ?? []
      );
    },

    async findEventByProviderEventId(provider, providerEventId) {
      return await query(
        client
          .from(tables.events)
          .select("*")
          .eq("provider", provider)
          .eq("provider_event_id", providerEventId)
          .maybeSingle(),
        "replay the Resend webhook event safely",
      );
    },

    async insertEvent(row) {
      let result;

      try {
        result = await client
          .from(tables.events)
          .insert(row)
          .select("*")
          .single();
      } catch (error) {
        if (databaseUniqueViolation(error) && row?.provider_event_id) {
          const existing = await this.findEventByProviderEventId(
            row.provider,
            row.provider_event_id,
          );
          if (existing) return existing;
        }
        throw databaseError(error, "record the Agent Email audit event");
      }

      if (result?.error) {
        if (databaseUniqueViolation(result.error) && row?.provider_event_id) {
          const existing = await this.findEventByProviderEventId(
            row.provider,
            row.provider_event_id,
          );
          if (existing) return existing;
        }
        throw databaseError(result.error, "record the Agent Email audit event");
      }

      return result?.data ?? null;
    },
  });
}

function normalizeStatusValue(value) {
  const normalized = line(value, 80).toLowerCase();

  const aliases = new Map([
    ["transactional", "transactional_only"],
    ["transactional_only", "transactional_only"],
    ["marketing", "marketing_opt_in"],
    ["marketing_opt_in", "marketing_opt_in"],
    ["unsubscribe", "unsubscribed"],
    ["unsubscribed", "unsubscribed"],
    ["suppress", "suppressed"],
    ["suppressed", "suppressed"],
  ]);

  const status = aliases.get(normalized);

  if (!status) {
    fail(
      "Choose Transactional, Marketing Opt-In, Unsubscribed, or Suppressed.",
      "agent_email_recipient_status_invalid",
    );
  }

  return status;
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
      "Nova cannot prepare email for an unsubscribed or suppressed recipient.",
      "agent_email_recipient_blocked",
      409,
    );
  }

  if (marketing && status !== "marketing_opt_in") {
    fail(
      "Marketing email requires a recipient with recorded marketing consent.",
      "agent_email_marketing_consent_required",
      409,
    );
  }

  return row;
}

export function createKorlixAgentEmailDraftService({
  environment = process.env,
  store,
  loadAgentProfile,
  now = () => new Date(),
  randomUUID = () => crypto.randomUUID(),
  providerSendPathImplemented = false,
  autopilotExecutionImplemented = false,
  webhookEventsImplemented = false,
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

    if (
      !korlixAgentEmailIsExistingNova({
        environment,
        userId: safeUserId,
        agentId: safeAgentId,
      })
    ) {
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

    if (!profile) {
      fail(
        "The approved Nova Agent Hub profile was not found.",
        "agent_email_nova_profile_not_found",
        404,
      );
    }

    const profileId = korlixAgentEmailAgentId(profile.id ?? profile.agent_id);
    const toolIds = Array.isArray(profile.toolIds)
      ? profile.toolIds
      : Array.isArray(profile.tool_ids)
        ? profile.tool_ids
        : [];

    if (
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
      profile,
      toolIds,
      binding,
    });
  }

  async function settingsRequired(identity) {
    const row = await store.getSettings(identity.userId, identity.agentId);

    if (!row) {
      fail(
        "Save Nova's Agent Email settings before creating a draft.",
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

    if (!status.canDraft) {
      fail(
        "Nova's Agent Email feature must be enabled before creating a draft.",
        "agent_email_drafting_disabled",
        409,
      );
    }

    return { row, status };
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

  async function loadMessage(identity, messageId) {
    const safeMessageId = uuid(
      messageId,
      "agent_email_message_id_invalid",
      "Choose a valid Nova email draft.",
    );

    const row = await store.getMessage(
      identity.userId,
      identity.agentId,
      safeMessageId,
    );

    if (!row) {
      fail(
        "The selected Nova email draft was not found.",
        "agent_email_draft_not_found",
        404,
      );
    }

    return row;
  }

  async function recordEvent(identity, messageId, eventType, details = {}) {
    return await store.insertEvent({
      user_id: identity.userId,
      agent_id: identity.agentId,
      message_id: messageId,
      event_type: line(eventType, 100),
      provider: "resend",
      provider_event_id: null,
      event_at: now().toISOString(),
      details: objectValue(details),
    });
  }

  return Object.freeze({
    async getStatus({ userId, agentId }) {
      const identity = await context({ userId, agentId });
      const settingsRow = await store.getSettings(
        identity.userId,
        identity.agentId,
      );
      const settings = settingsPublicView(settingsRow);
      const status = korlixAgentEmailStatus({
        environment,
        userId: identity.userId,
        agentId: identity.agentId,
        toolIds: identity.toolIds,
        settings: settingsForPolicy(settingsRow),
      });

      return Object.freeze({
        agentId: identity.agentId,
        assistantId: identity.binding.assistantId,
        sameNova: status.sameNova,
        toolAuthorized: status.toolAuthorized,
        featureEnabled: status.featureEnabled,
        providerConfigured: status.providerConfigured,
        canDraft: status.canDraft,
        canSend:
          providerSendPathImplemented === true && status.canSend,
        canAutopilot:
          autopilotExecutionImplemented === true && status.canAutopilot,
        settings,
        persistenceConfigured: true,
        draftRoutesImplemented: true,
        providerSendPathImplemented:
          providerSendPathImplemented === true,
        autopilotExecutionImplemented:
          autopilotExecutionImplemented === true,
        webhookEventsImplemented:
          webhookEventsImplemented === true,
        outboundCallingPaused: true,
      });
    },

    async getSettings({ userId, agentId }) {
      const identity = await context({ userId, agentId });
      const row = await store.getSettings(identity.userId, identity.agentId);

      return Object.freeze({
        settings: settingsPublicView(row),
        exists: Boolean(row),
      });
    },

    async saveSettings({ userId, agentId, body }) {
      const identity = await context({ userId, agentId });
      const source = objectValue(body);
      const input = korlixAgentEmailSettingsInput(source, environment);
      const existing = await store.getSettings(
        identity.userId,
        identity.agentId,
      );
      const existingMetadata = objectValue(existing?.metadata);

      const fromEmailValue = Object.hasOwn(source, "fromEmail") ||
        Object.hasOwn(source, "from_email")
        ? line(source.fromEmail ?? source.from_email, 320).toLowerCase()
        : line(existing?.from_email, 320).toLowerCase();
      const replyToValue = Object.hasOwn(source, "replyToEmail") ||
        Object.hasOwn(source, "reply_to_email")
        ? line(source.replyToEmail ?? source.reply_to_email, 320).toLowerCase()
        : line(existing?.reply_to_email, 320).toLowerCase();

      const fromEmail = fromEmailValue
        ? korlixAgentEmailAddress(fromEmailValue)
        : "";
      const replyToEmail = replyToValue
        ? korlixAgentEmailAddress(replyToValue)
        : "";

      const row = await store.saveSettings({
        user_id: identity.userId,
        agent_id: identity.agentId,
        provider: "resend",
        enabled: input.enabled,
        operating_mode: input.mode,
        emergency_paused: input.paused,
        daily_send_cap: input.dailySendCap,
        from_name:
          Object.hasOwn(source, "fromName") ||
          Object.hasOwn(source, "from_name")
            ? line(source.fromName ?? source.from_name, 160)
            : line(existing?.from_name, 160),
        from_email: fromEmail,
        reply_to_email: replyToEmail,
        physical_address:
          Object.hasOwn(source, "physicalAddress") ||
          Object.hasOwn(source, "physical_address")
            ? line(source.physicalAddress ?? source.physical_address, 500)
            : line(existing?.physical_address, 500),
        timezone: input.timezone,
        metadata: {
          ...existingMetadata,
          sendWindowStart: input.sendWindowStart,
          sendWindowEnd: input.sendWindowEnd,
          maxFollowUps: input.maxFollowUps,
          marketingEnabled: input.marketingEnabled,
          lastConfirmedBy: identity.userId,
          lastConfirmedAt: now().toISOString(),
        },
      });

      return Object.freeze({
        settings: settingsPublicView(row),
        saved: true,
        sent: false,
      });
    },

    async listRecipients({ userId, agentId, limit = 100 }) {
      const identity = await context({ userId, agentId });
      const rows = await store.listRecipients(
        identity.userId,
        identity.agentId,
        {
          limit: boundedInteger(limit, 100, 1, 200),
        },
      );

      return Object.freeze({
        recipients: rows.map(recipientPublicView),
      });
    },

    async saveRecipient({ userId, agentId, body }) {
      const identity = await context({ userId, agentId });
      const source = objectValue(body);
      const settings = await store.getSettings(
        identity.userId,
        identity.agentId,
      );

      if (!settings) {
        fail(
          "Save Nova's Agent Email settings before adding recipients.",
          "agent_email_settings_required",
          409,
        );
      }

      const input = korlixAgentEmailRecipientInput(source);
      const existing = await store.findRecipientByEmail(
        identity.userId,
        identity.agentId,
        input.email,
      );

      if (
        existing &&
        ["unsubscribed", "suppressed"].includes(
          line(existing.consent_status, 80).toLowerCase(),
        )
      ) {
        fail(
          "Use the recipient status control to reactivate an unsubscribed or suppressed address.",
          "agent_email_recipient_reactivation_required",
          409,
        );
      }

      const consentStatus = input.consentScope === "marketing"
        ? "marketing_opt_in"
        : "transactional_only";
      const sourceKind = input.approvalSource === "user_confirmed"
        ? "customer_record"
        : "user_entered";
      const metadata = {
        ...objectValue(existing?.metadata),
        approvalSource: input.approvalSource,
        confirmedBy: identity.userId,
        confirmedAt: now().toISOString(),
      };
      const patch = {
        user_id: identity.userId,
        agent_id: identity.agentId,
        email: input.email,
        display_name: input.displayName,
        source_kind: sourceKind,
        source_reference:
          line(source.sourceReference ?? source.source_reference, 500) ||
          input.approvalSource,
        consent_status: consentStatus,
        consent_source: input.approvalSource,
        consent_recorded_at: input.consentAt,
        unsubscribed_at: null,
        suppressed_at: null,
        suppression_reason: null,
        active: true,
        metadata,
      };

      const row = existing
        ? await store.updateRecipient(
            identity.userId,
            identity.agentId,
            existing.id,
            patch,
          )
        : await store.insertRecipient(patch);

      return Object.freeze({
        recipient: recipientPublicView(row),
        created: !existing,
        sent: false,
      });
    },

    async updateRecipientStatus({
      userId,
      agentId,
      recipientId,
      body,
    }) {
      const identity = await context({ userId, agentId });
      const source = objectValue(body);
      requireConfirmation(
        source,
        "Confirm the recipient status change.",
        "agent_email_recipient_status_confirmation_required",
      );
      const safeRecipientId = uuid(
        recipientId,
        "agent_email_recipient_id_invalid",
        "Choose a valid approved recipient.",
      );
      const existing = await store.getRecipient(
        identity.userId,
        identity.agentId,
        safeRecipientId,
      );

      if (!existing) {
        fail(
          "The selected approved recipient was not found.",
          "agent_email_recipient_not_found",
          404,
        );
      }

      const status = normalizeStatusValue(
        source.status ?? source.consentStatus ?? source.consent_status,
      );
      const timestamp = now().toISOString();
      const patch = {
        consent_status: status,
        metadata: {
          ...objectValue(existing.metadata),
          statusUpdatedBy: identity.userId,
          statusUpdatedAt: timestamp,
        },
      };

      if (status === "marketing_opt_in") {
        const marketing = korlixAgentEmailRecipientInput({
          confirmed: true,
          email: existing.email,
          displayName: existing.display_name,
          approvalSource: "user_confirmed",
          consentScope: "marketing",
          consentAt: source.consentAt ?? source.consent_at,
        });

        Object.assign(patch, {
          consent_source: "user_confirmed",
          consent_recorded_at: marketing.consentAt,
          unsubscribed_at: null,
          suppressed_at: null,
          suppression_reason: null,
          active: true,
        });
      } else if (status === "transactional_only") {
        Object.assign(patch, {
          consent_source: "user_confirmed",
          consent_recorded_at: null,
          unsubscribed_at: null,
          suppressed_at: null,
          suppression_reason: null,
          active: true,
        });
      } else if (status === "unsubscribed") {
        Object.assign(patch, {
          unsubscribed_at: timestamp,
          suppressed_at: null,
          suppression_reason: null,
          active: false,
        });
      } else {
        const reason = line(
          source.suppressionReason ?? source.suppression_reason,
          500,
        );

        if (!reason) {
          fail(
            "Enter a reason before suppressing this recipient.",
            "agent_email_suppression_reason_required",
          );
        }

        Object.assign(patch, {
          unsubscribed_at: null,
          suppressed_at: timestamp,
          suppression_reason: reason,
          active: false,
        });
      }

      const row = await store.updateRecipient(
        identity.userId,
        identity.agentId,
        safeRecipientId,
        patch,
      );

      return Object.freeze({
        recipient: recipientPublicView(row),
        sent: false,
      });
    },

    async listDrafts({ userId, agentId, limit = 100 }) {
      const identity = await context({ userId, agentId });
      const rows = await store.listMessages(
        identity.userId,
        identity.agentId,
        {
          limit: boundedInteger(limit, 100, 1, 200),
        },
      );

      return Object.freeze({
        drafts: rows
          .filter(
            (row) => line(row?.status, 40).toLowerCase() !== "cancelled",
          )
          .map(messagePublicView),
      });
    },

    async getDraft({ userId, agentId, messageId }) {
      const identity = await context({ userId, agentId });
      const row = await loadMessage(identity, messageId);

      return Object.freeze({
        draft: messagePublicView(row),
      });
    },

    async createDraft({ userId, agentId, body }) {
      const identity = await context({ userId, agentId });
      const { row: settingsRow } = await settingsRequired(identity);
      const source = objectValue(body);
      const input = korlixAgentEmailDraftInput({
        ...source,
        physicalAddress:
          source.physicalAddress ??
          source.physical_address ??
          settingsRow.physical_address,
      });
      const existing = await store.findMessageByIdempotency(
        identity.userId,
        identity.agentId,
        input.idempotencyKey,
      );

      if (existing) {
        return Object.freeze({
          draft: messagePublicView(existing),
          replayed: true,
          sent: false,
        });
      }

      const recipient = await loadRecipient(
        identity,
        input.recipientId,
        input.marketing,
      );
      const scheduledAt = input.scheduledAt
        ? isoTimestamp(input.scheduledAt, {
            code: "agent_email_schedule_invalid",
            message: "Enter a valid draft schedule date and time.",
          })
        : null;
      const row = await store.insertMessage({
        id: randomUUID(),
        user_id: identity.userId,
        agent_id: identity.agentId,
        recipient_id: recipient.id,
        rule_id: null,
        to_email: korlixAgentEmailAddress(recipient.email),
        subject: input.subject,
        text_body: input.textBody,
        html_body: "",
        message_kind: input.marketing ? "marketing" : "transactional",
        status: "draft",
        authorization_type: "none",
        authorized_at: null,
        authorized_by: null,
        confirmation_nonce_hash: null,
        idempotency_key: input.idempotencyKey,
        provider: "resend",
        provider_message_id: null,
        physical_address_snapshot: input.physicalAddress || "",
        unsubscribe_url_snapshot: input.unsubscribeUrl || "",
        scheduled_at: scheduledAt,
        last_attempt_at: null,
        attempt_count: 0,
        sent_at: null,
        failure_code: null,
        failure_message: null,
        metadata: {
          source: "authenticated_draft_route",
          createdBy: identity.userId,
          providerSendPathImplemented: providerSendPathImplemented === true,
        },
      });

      await recordEvent(identity, row.id, "draft_created", {
        recipientId: recipient.id,
        messageKind: row.message_kind,
        sent: false,
      });

      return Object.freeze({
        draft: messagePublicView(row),
        replayed: false,
        sent: false,
      });
    },

    async updateDraft({ userId, agentId, messageId, body }) {
      const identity = await context({ userId, agentId });
      const { row: settingsRow } = await settingsRequired(identity);
      const existing = await loadMessage(identity, messageId);
      const status = line(existing.status, 40).toLowerCase();

      if (!EDITABLE_MESSAGE_STATUSES.has(status)) {
        fail(
          "This Nova email record can no longer be edited.",
          "agent_email_draft_not_editable",
          409,
        );
      }

      const source = objectValue(body);
      const suppliedIdempotency = line(
        source.idempotencyKey ?? source.idempotency_key,
        240,
      );

      if (
        suppliedIdempotency &&
        suppliedIdempotency !== existing.idempotency_key
      ) {
        fail(
          "The draft idempotency key cannot be changed.",
          "agent_email_idempotency_key_immutable",
          409,
        );
      }

      const marketing = Object.hasOwn(source, "marketing")
        ? source.marketing === true
        : existing.message_kind === "marketing";
      const merged = korlixAgentEmailDraftInput({
        recipientId:
          source.recipientId ??
          source.recipient_id ??
          existing.recipient_id,
        subject: source.subject ?? existing.subject,
        textBody:
          source.textBody ??
          source.text_body ??
          source.body ??
          existing.text_body,
        idempotencyKey: existing.idempotency_key,
        marketing,
        unsubscribeUrl:
          source.unsubscribeUrl ??
          source.unsubscribe_url ??
          existing.unsubscribe_url_snapshot,
        physicalAddress:
          source.physicalAddress ??
          source.physical_address ??
          existing.physical_address_snapshot ??
          settingsRow.physical_address,
        scheduledAt:
          source.scheduledAt ??
          source.scheduled_at ??
          existing.scheduled_at,
      });
      const recipient = await loadRecipient(
        identity,
        merged.recipientId,
        merged.marketing,
      );
      const scheduledAt = merged.scheduledAt
        ? isoTimestamp(merged.scheduledAt, {
            code: "agent_email_schedule_invalid",
            message: "Enter a valid draft schedule date and time.",
          })
        : null;
      const approvalReset =
        existing.authorization_type !== "none" || status === "approved";
      const row = await store.updateMessage(
        identity.userId,
        identity.agentId,
        existing.id,
        {
          recipient_id: recipient.id,
          rule_id: null,
          to_email: korlixAgentEmailAddress(recipient.email),
          subject: merged.subject,
          text_body: merged.textBody,
          html_body: "",
          message_kind: merged.marketing ? "marketing" : "transactional",
          status: "draft",
          authorization_type: "none",
          authorized_at: null,
          authorized_by: null,
          confirmation_nonce_hash: null,
          physical_address_snapshot: merged.physicalAddress || "",
          unsubscribe_url_snapshot: merged.unsubscribeUrl || "",
          scheduled_at: scheduledAt,
          provider_message_id: null,
          last_attempt_at: null,
          attempt_count: 0,
          sent_at: null,
          failure_code: null,
          failure_message: null,
          metadata: {
            ...objectValue(existing.metadata),
            lastEditedBy: identity.userId,
            lastEditedAt: now().toISOString(),
            approvalReset,
            lastFailureRetryable: false,
            lastFailureAmbiguous: false,
            retryDeadlineAt: null,
            providerSendPathImplemented: providerSendPathImplemented === true,
          },
        },
      );

      await recordEvent(identity, row.id, "draft_updated", {
        approvalReset,
        sent: false,
      });

      return Object.freeze({
        draft: messagePublicView(row),
        approvalReset,
        sent: false,
      });
    },

    // K133_AGENT_EMAIL_DRAFT_REAPPROVAL_V1_BEGIN
    async deleteDraft({
      userId,
      agentId,
      messageId,
      body,
    }) {
      const identity = await context({ userId, agentId });
      const source = objectValue(body);

      requireConfirmation(
        source,
        "Confirm that this unsent Nova email draft should be deleted.",
        "agent_email_draft_delete_confirmation_required",
      );

      const existing = await loadMessage(identity, messageId);
      const status = line(existing.status, 40).toLowerCase();

      if (status === "cancelled") {
        return Object.freeze({
          draft: messagePublicView(existing),
          replayed: true,
          deleted: true,
          softDeleted: true,
          sent: false,
        });
      }

      const metadata = objectValue(existing.metadata);
      const providerMessageId =
        line(existing.provider_message_id, 240);
      const ambiguousProviderOutcome =
        metadata.lastFailureAmbiguous === true ||
        metadata.last_failure_ambiguous === true;

      if (
        !DELETABLE_MESSAGE_STATUSES.has(status) ||
        existing.sent_at ||
        providerMessageId ||
        ambiguousProviderOutcome
      ) {
        fail(
          "This email can no longer be deleted because a send is active, complete, or requires provider reconciliation.",
          "agent_email_draft_not_deletable",
          409,
        );
      }

      if (existing.rule_id) {
        const rule = await store.getRule(
          identity.userId,
          identity.agentId,
          existing.rule_id,
        );

        if (!rule) {
          fail(
            "Review the linked schedule before deleting this draft.",
            "agent_email_draft_schedule_review_required",
            409,
          );
        }

        if (
          rule.enabled === true &&
          !rule.completed_at &&
          !rule.deleted_at
        ) {
          fail(
            "Pause or cancel the linked schedule before deleting this draft.",
            "agent_email_draft_schedule_active",
            409,
          );
        }
      }

      const typedPhrase = line(
        source.confirmationPhrase ??
          source.confirmation_phrase,
        80,
      );

      if (
        TYPED_DRAFT_DELETE_STATUSES.has(status) &&
        typedPhrase !== DRAFT_DELETE_CONFIRMATION_PHRASE
      ) {
        fail(
          `Type ${DRAFT_DELETE_CONFIRMATION_PHRASE} to delete this ${status} draft.`,
          "agent_email_draft_delete_phrase_required",
          409,
        );
      }

      const deletedAt = now().toISOString();

      const row = await store.cancelMessage(
        identity.userId,
        identity.agentId,
        existing.id,
        {
          status: "cancelled",
          authorization_type: "none",
          authorized_at: null,
          authorized_by: null,
          confirmation_nonce_hash: null,
          scheduled_at: null,
          metadata: {
            ...metadata,
            draftDeleted: true,
            draftDeletedAt: deletedAt,
            draftDeletedBy: identity.userId,
            draftDeletePreviousStatus: status,
            draftDeleteReason: "user_confirmed",
            draftDeleteTypedConfirmationRequired:
              TYPED_DRAFT_DELETE_STATUSES.has(status),
          },
        },
      );

      if (!row) {
        const current = await store.getMessage(
          identity.userId,
          identity.agentId,
          existing.id,
        );

        if (
          line(current?.status, 40).toLowerCase() ===
          "cancelled"
        ) {
          return Object.freeze({
            draft: messagePublicView(current),
            replayed: true,
            deleted: true,
            softDeleted: true,
            sent: false,
          });
        }

        fail(
          "The draft changed while deletion was being confirmed. Refresh before trying again.",
          "agent_email_draft_delete_raced_with_send",
          409,
        );
      }

      await recordEvent(
        identity,
        row.id,
        "draft_deleted",
        {
          previousStatus: status,
          hardDeleted: false,
          authorizationRevoked: true,
          scheduledAtCleared: true,
          sent: false,
        },
      );

      return Object.freeze({
        draft: messagePublicView(row),
        replayed: false,
        deleted: true,
        softDeleted: true,
        sent: false,
      });
    },

    async approveDraft({ userId, agentId, messageId, body }) {
      const identity = await context({ userId, agentId });
      await settingsRequired(identity);
      const source = objectValue(body);
      requireConfirmation(
        source,
        "Confirm this exact email draft before approving it.",
        "agent_email_draft_approval_confirmation_required",
      );
      const nonce = line(
        source.confirmationNonce ?? source.confirmation_nonce,
        240,
      );

      if (nonce.length < 12) {
        fail(
          "A confirmation nonce is required to approve this exact draft.",
          "agent_email_confirmation_nonce_required",
        );
      }

      const nonceHash = crypto
        .createHash("sha256")
        .update(nonce)
        .digest("hex");

      const existing = await loadMessage(identity, messageId);
      const status = line(existing.status, 40).toLowerCase();

      if (
        status === "approved" &&
        existing.authorization_type === "one_time_confirmation"
      ) {
        const storedNonceHash = line(
          existing.confirmation_nonce_hash,
          128,
        );

        const sameNonce =
          storedNonceHash.length === nonceHash.length &&
          storedNonceHash.length > 0 &&
          crypto.timingSafeEqual(
            Buffer.from(storedNonceHash, "utf8"),
            Buffer.from(nonceHash, "utf8"),
          );

        if (sameNonce) {
          return Object.freeze({
            draft: messagePublicView(existing),
            replayed: true,
            reapproved: false,
            approved: true,
            sent: false,
          });
        }

        if (source.reapprove !== true) {
          fail(
            "This Nova email draft is already approved with a different confirmation nonce. Reapprove this exact draft before sending it.",
            "agent_email_draft_reapproval_required",
            409,
          );
        }

        await loadRecipient(
          identity,
          existing.recipient_id,
          existing.message_kind === "marketing",
        );

        const authorizedAt = now().toISOString();
        const existingMetadata = objectValue(existing.metadata);
        const reapprovalCount =
          Math.max(
            0,
            Number.parseInt(
              existingMetadata.reapprovalCount,
              10,
            ) || 0,
          ) + 1;

        const row = await store.updateMessage(
          identity.userId,
          identity.agentId,
          existing.id,
          {
            status: "approved",
            authorization_type: "one_time_confirmation",
            authorized_at: authorizedAt,
            authorized_by: identity.userId,
            confirmation_nonce_hash: nonceHash,
            metadata: {
              ...existingMetadata,
              approvedBy: identity.userId,
              approvedAt: authorizedAt,
              reapprovedBy: identity.userId,
              reapprovedAt: authorizedAt,
              reapprovalCount,
              previousApprovalReplaced: true,
              providerSendPathImplemented:
                providerSendPathImplemented === true,
            },
          },
        );

        await recordEvent(
          identity,
          row.id,
          "draft_reapproved",
          {
            authorizationType: "one_time_confirmation",
            previousApprovalReplaced: true,
            sent: false,
          },
        );

        return Object.freeze({
          draft: messagePublicView(row),
          replayed: false,
          reapproved: true,
          approved: true,
          sent: false,
        });
      }

      if (status !== "draft" && status !== "pending_approval") {
        fail(
          "Only a reviewable Nova email draft can be approved.",
          "agent_email_draft_not_approvable",
          409,
        );
      }

      await loadRecipient(
        identity,
        existing.recipient_id,
        existing.message_kind === "marketing",
      );

      const authorizedAt = now().toISOString();
      const row = await store.updateMessage(
        identity.userId,
        identity.agentId,
        existing.id,
        {
          status: "approved",
          authorization_type: "one_time_confirmation",
          authorized_at: authorizedAt,
          authorized_by: identity.userId,
          confirmation_nonce_hash: nonceHash,
          metadata: {
            ...objectValue(existing.metadata),
            approvedBy: identity.userId,
            approvedAt: authorizedAt,
            providerSendPathImplemented: providerSendPathImplemented === true,
          },
        },
      );

      await recordEvent(identity, row.id, "draft_approved", {
        authorizationType: "one_time_confirmation",
        sent: false,
      });

      return Object.freeze({
        draft: messagePublicView(row),
        replayed: false,
        reapproved: false,
        approved: true,
        sent: false,
      });
    },
    // K133_AGENT_EMAIL_DRAFT_REAPPROVAL_V1_END
  });
}

function responseError(res, error, fallback) {
  const statusCode = Number.isInteger(error?.statusCode)
    ? error.statusCode
    : 500;
  const publicMessage = statusCode >= 500
    ? fallback
    : line(error?.message, 600) || fallback;

  return res.status(statusCode).json({
    ok: false,
    code: line(error?.code, 120) || "agent_email_failed",
    error: publicMessage,
    sent: false,
  });
}

function authenticatedRoute({ requireUser, service, logger, fallback, handler }) {
  return async (req, res) => {
    try {
      const authenticated = await requireUser(req);
      const user =
        authenticated?.user ??
        authenticated?.data?.user ??
        authenticated;
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
        logger.error("KORLIX_AGENT_EMAIL_DRAFT_ROUTE_FAILED", {
          code: line(error?.code, 120) || "agent_email_failed",
        });
      }

      return responseError(res, error, fallback);
    }
  };
}

export function installKorlixAgentEmailDraftRoutes(
  app,
  {
    environment = process.env,
    supabaseAdmin = null,
    store = null,
    requireUser,
    loadAgentProfile,
    logger = console,
    now = () => new Date(),
    randomUUID = () => crypto.randomUUID(),
    providerSendPathImplemented = false,
    autopilotExecutionImplemented = false,
    webhookEventsImplemented = false,
  } = {},
) {
  if (
    !app ||
    typeof app.get !== "function" ||
    typeof app.post !== "function" ||
    typeof app.put !== "function" ||
    typeof app.patch !== "function"
    || typeof app.delete !== "function"
  ) {
    throw new TypeError("An Express-compatible application is required.");
  }

  if (typeof requireUser !== "function") {
    throw new TypeError("The authenticated KORLIX user loader is required.");
  }

  const persistence =
    store ?? createKorlixAgentEmailSupabaseStore(supabaseAdmin);
  const service = createKorlixAgentEmailDraftService({
    environment,
    store: persistence,
    loadAgentProfile,
    now,
    randomUUID,
    providerSendPathImplemented,
    autopilotExecutionImplemented,
    webhookEventsImplemented,
  });
  const route = (fallback, handler) =>
    authenticatedRoute({
      requireUser,
      service,
      logger,
      fallback,
      handler,
    });
  const routes = KORLIX_AGENT_EMAIL_DRAFT_ROUTES;

  app.get(
    routes.status,
    route(
      "Could not load Nova's Agent Email status.",
      async ({ res, userId, agentId }) =>
        res.json({
          ok: true,
          status: await service.getStatus({ userId, agentId }),
        }),
    ),
  );

  app.get(
    routes.settings,
    route(
      "Could not load Nova's Agent Email settings.",
      async ({ res, userId, agentId }) =>
        res.json({
          ok: true,
          ...(await service.getSettings({ userId, agentId })),
        }),
    ),
  );

  app.put(
    routes.settings,
    route(
      "Could not save Nova's Agent Email settings.",
      async ({ req, res, userId, agentId }) =>
        res.json({
          ok: true,
          ...(await service.saveSettings({
            userId,
            agentId,
            body: req.body,
          })),
        }),
    ),
  );

  app.get(
    routes.recipients,
    route(
      "Could not load Nova's approved email recipients.",
      async ({ req, res, userId, agentId }) =>
        res.json({
          ok: true,
          ...(await service.listRecipients({
            userId,
            agentId,
            limit: req.query?.limit,
          })),
        }),
    ),
  );

  app.post(
    routes.recipients,
    route(
      "Could not save Nova's approved email recipient.",
      async ({ req, res, userId, agentId }) => {
        const result = await service.saveRecipient({
          userId,
          agentId,
          body: req.body,
        });

        return res.status(result.created ? 201 : 200).json({
          ok: true,
          ...result,
        });
      },
    ),
  );

  app.patch(
    routes.recipient,
    route(
      "Could not update Nova's approved email recipient.",
      async ({ req, res, userId, agentId }) =>
        res.json({
          ok: true,
          ...(await service.updateRecipientStatus({
            userId,
            agentId,
            recipientId: req.params.recipientId,
            body: req.body,
          })),
        }),
    ),
  );

  app.get(
    routes.drafts,
    route(
      "Could not load Nova's email drafts.",
      async ({ req, res, userId, agentId }) =>
        res.json({
          ok: true,
          ...(await service.listDrafts({
            userId,
            agentId,
            limit: req.query?.limit,
          })),
        }),
    ),
  );

  app.post(
    routes.drafts,
    route(
      "Could not create Nova's email draft.",
      async ({ req, res, userId, agentId }) => {
        const result = await service.createDraft({
          userId,
          agentId,
          body: req.body,
        });

        return res.status(result.replayed ? 200 : 201).json({
          ok: true,
          ...result,
        });
      },
    ),
  );

  app.get(
    routes.draft,
    route(
      "Could not load Nova's email draft.",
      async ({ req, res, userId, agentId }) =>
        res.json({
          ok: true,
          ...(await service.getDraft({
            userId,
            agentId,
            messageId: req.params.messageId,
          })),
        }),
    ),
  );

  app.patch(
    routes.draft,
    route(
      "Could not update Nova's email draft.",
      async ({ req, res, userId, agentId }) =>
        res.json({
          ok: true,
          ...(await service.updateDraft({
            userId,
            agentId,
            messageId: req.params.messageId,
            body: req.body,
          })),
        }),
    ),
  );

  app.delete(
    routes.deleteDraft,
    route(
      "Could not delete Nova's email draft.",
      async ({ req, res, userId, agentId }) =>
        res.json({
          ok: true,
          ...(await service.deleteDraft({
            userId,
            agentId,
            messageId: req.params.messageId,
            body: req.body,
          })),
        }),
    ),
  );

  app.post(
    routes.approveDraft,
    route(
      "Could not approve Nova's email draft.",
      async ({ req, res, userId, agentId }) =>
        res.json({
          ok: true,
          ...(await service.approveDraft({
            userId,
            agentId,
            messageId: req.params.messageId,
            body: req.body,
          })),
        }),
    ),
  );

  return Object.freeze({
    routes,
    providerSendPathImplemented:
      providerSendPathImplemented === true,
    emailSendIncluded:
      providerSendPathImplemented === true,
    autopilotExecutionIncluded:
      autopilotExecutionImplemented === true,
    webhookEventsImplemented:
      webhookEventsImplemented === true,
    outboundCallingPaused: true,
  });
}
