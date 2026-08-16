import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";

import {
  KORLIX_AGENT_EMAIL_DELIVERY_ROUTES,
  createKorlixAgentEmailDeliveryService,
  createKorlixAgentEmailResendProvider,
  installKorlixAgentEmailDeliveryRoutes,
  korlixAgentEmailRenderTemplate,
  verifyKorlixAgentEmailResendWebhook,
} from "./korlix_agent_email_delivery.mjs";

import {
  createKorlixAgentEmailSupabaseStore,
} from "./korlix_agent_email_routes.mjs";

const OWNER = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";
const AGENT = "custom_nova";
const RECIPIENT = "33333333-3333-4333-8333-333333333333";
const MESSAGE = "44444444-4444-4444-8444-444444444444";
const RULE = "55555555-5555-4555-8555-555555555555";
const WEBHOOK_SECRET_BYTES = Buffer.from("agent-email-webhook-secret-for-tests");
const WEBHOOK_SECRET = `whsec_${WEBHOOK_SECRET_BYTES.toString("base64")}`;
const NOW = "2026-08-13T15:00:00.000Z";

function environment(overrides = {}) {
  return {
    KORLIX_VAPI_NOVA_OWNER_UID: OWNER,
    KORLIX_VAPI_NOVA_AGENT_ID: AGENT,
    KORLIX_VAPI_NOVA_ASSISTANT_ID: "assistant-nova",
    KORLIX_AGENT_EMAIL_ENABLED: "true",
    KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE: "false",
    KORLIX_AGENT_EMAIL_SEND_ENABLED: "true",
    KORLIX_AGENT_EMAIL_AUTOPILOT_ENABLED: "true",
    KORLIX_AGENT_EMAIL_FROM: "Nova <nova@korlixdeveloper.com>",
    KORLIX_AGENT_EMAIL_REPLY_TO: "reply@korlixdeveloper.com",
    KORLIX_AGENT_EMAIL_UNSUBSCRIBE_URL:
      "https://korlixdeveloper.com/unsubscribe",
    KORLIX_AGENT_EMAIL_MARKETING_SEND_ENABLED: "true",
    KORLIX_AGENT_EMAIL_AUTOPILOT_SECRET: "autopilot-test-secret",
    RESEND_API_KEY: "test-only-resend-key",
    RESEND_WEBHOOK_SECRET: WEBHOOK_SECRET,
    ...overrides,
  };
}

function clone(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

function profile(overrides = {}) {
  return {
    id: AGENT,
    name: "Nova",
    isCustom: true,
    active: true,
    toolIds: [
      "general_chat",
      "memory",
      "agent_training",
      "agent_email",
    ],
    ...overrides,
  };
}

function memoryStore() {
  const state = {
    settings: new Map(),
    recipients: new Map(),
    messages: new Map(),
    rules: new Map(),
    events: [],
    lastClaimArgs: null,
    restoreCalls: [],
  };
  const match = (row, userId, agentId) =>
    row?.user_id === userId && row?.agent_id === agentId;

  return {
    client: { serviceRole: true },
    state,

    async getSettings(userId, agentId) {
      return clone(state.settings.get(`${userId}:${agentId}`) ?? null);
    },

    async saveSettings(row) {
      const key = `${row.user_id}:${row.agent_id}`;
      const current = state.settings.get(key);
      const saved = {
        id: current?.id ?? "77777777-7777-4777-8777-777777777777",
        created_at: current?.created_at ?? NOW,
        updated_at: NOW,
        ...clone(current ?? {}),
        ...clone(row),
      };
      state.settings.set(key, saved);
      return clone(saved);
    },

    async listRecipients(userId, agentId, { limit = 100 } = {}) {
      return [...state.recipients.values()]
        .filter((row) => match(row, userId, agentId))
        .slice(0, limit)
        .map(clone);
    },

    async getRecipient(userId, agentId, recipientId) {
      const row = state.recipients.get(recipientId);
      return match(row, userId, agentId) ? clone(row) : null;
    },

    async findRecipientByEmail(userId, agentId, email) {
      const row = [...state.recipients.values()].find(
        (item) => match(item, userId, agentId) && item.email === email,
      );
      return clone(row ?? null);
    },

    async insertRecipient(row) {
      const id = row.id ?? RECIPIENT;
      const saved = {
        id,
        created_at: NOW,
        updated_at: NOW,
        ...clone(row),
      };
      state.recipients.set(id, saved);
      return clone(saved);
    },

    async updateRecipient(userId, agentId, recipientId, patch) {
      const current = state.recipients.get(recipientId);
      if (!match(current, userId, agentId)) return null;
      const saved = {
        ...clone(current),
        ...clone(patch),
        updated_at: NOW,
      };
      state.recipients.set(recipientId, saved);
      return clone(saved);
    },

    async listMessages(userId, agentId, { limit = 100 } = {}) {
      return [...state.messages.values()]
        .filter((row) => match(row, userId, agentId))
        .slice(0, limit)
        .map(clone);
    },

    async getMessage(userId, agentId, messageId) {
      const row = state.messages.get(messageId);
      return match(row, userId, agentId) ? clone(row) : null;
    },

    async findMessageByIdempotency(userId, agentId, idempotencyKey) {
      const row = [...state.messages.values()].find(
        (item) =>
          match(item, userId, agentId) &&
          item.idempotency_key === idempotencyKey,
      );
      return clone(row ?? null);
    },

    async findMessageByProviderId(provider, providerMessageId) {
      const row = [...state.messages.values()].find(
        (item) =>
          item.provider === provider &&
          item.provider_message_id === providerMessageId,
      );
      return clone(row ?? null);
    },

    async insertMessage(row) {
      const saved = {
        id: row.id ?? MESSAGE,
        created_at: NOW,
        updated_at: NOW,
        ...clone(row),
      };
      state.messages.set(saved.id, saved);
      return clone(saved);
    },

    async updateMessage(userId, agentId, messageId, patch) {
      const current = state.messages.get(messageId);
      if (!match(current, userId, agentId)) return null;
      const saved = {
        ...clone(current),
        ...clone(patch),
        updated_at: NOW,
      };
      state.messages.set(messageId, saved);
      return clone(saved);
    },

    async claimMessageForSend({
      userId,
      agentId,
      messageId,
      claimedAt,
      confirmationNonceHash = null,
    }) {
      state.lastClaimArgs = clone({
        userId,
        agentId,
        messageId,
        claimedAt,
        confirmationNonceHash,
      });
      const current = state.messages.get(messageId);
      if (!match(current, userId, agentId)) return null;
      if (current.status === "sent" && current.provider_message_id) {
        return clone(current);
      }
      if (![
        "approved",
        "queued",
        "failed",
        "sending",
      ].includes(current.status)) {
        return null;
      }
      if (
        current.authorization_type === "one_time_confirmation" &&
        (
          current.authorized_by !== userId ||
          current.confirmation_nonce_hash !== confirmationNonceHash
        )
      ) {
        const error = new Error("agent_email_confirmation_nonce_mismatch");
        error.code = "agent_email_confirmation_nonce_mismatch";
        error.statusCode = 403;
        throw error;
      }
      const dayStart = `${String(claimedAt).slice(0, 10)}T00:00:00.000Z`;
      const cap = state.settings.get(`${userId}:${agentId}`)?.daily_send_cap ?? 5;
      const activeCount = [...state.messages.values()].filter(
        (row) =>
          match(row, userId, agentId) &&
          row.id !== messageId &&
          ["sending", "sent"].includes(row.status) &&
          String(row.sent_at ?? row.last_attempt_at ?? row.updated_at ?? "") >= dayStart,
      ).length;
      if (activeCount >= cap) {
        const error = new Error("agent_email_daily_cap_reached");
        error.code = "agent_email_daily_cap_reached";
        error.statusCode = 429;
        throw error;
      }
      return await this.updateMessage(userId, agentId, messageId, {
        status: "sending",
        last_attempt_at: claimedAt,
        attempt_count: Math.min(
          100,
          Math.max(0, Number(current.attempt_count) || 0) + 1,
        ),
        failure_code: null,
        failure_message: null,
      });
    },

    async restoreMessageAfterAbortedClaim({
      userId,
      agentId,
      messageId,
      claimedAt,
      patch,
    }) {
      state.restoreCalls.push(clone({
        userId,
        agentId,
        messageId,
        claimedAt,
        patch,
      }));
      const current = state.messages.get(messageId);
      if (
        !match(current, userId, agentId) ||
        current.status !== "sending" ||
        current.last_attempt_at !== claimedAt
      ) {
        return null;
      }
      return await this.updateMessage(
        userId,
        agentId,
        messageId,
        patch,
      );
    },

    async countSentSince(userId, agentId, since) {
      return [...state.messages.values()].filter(
        (row) =>
          match(row, userId, agentId) &&
          row.status === "sent" &&
          row.sent_at >= since,
      ).length;
    },

    async countRuleSentSince(userId, agentId, ruleId, since) {
      return [...state.messages.values()].filter(
        (row) =>
          match(row, userId, agentId) &&
          row.rule_id === ruleId &&
          row.status === "sent" &&
          row.sent_at >= since,
      ).length;
    },

    async listRules(userId, agentId, { limit = 100 } = {}) {
      return [...state.rules.values()]
        .filter((row) => match(row, userId, agentId))
        .slice(0, limit)
        .map(clone);
    },

    async getRule(userId, agentId, ruleId) {
      const row = state.rules.get(ruleId);
      return match(row, userId, agentId) ? clone(row) : null;
    },

    async listEnabledRulesByTrigger(userId, agentId, triggerKey) {
      return [...state.rules.values()]
        .filter(
          (row) =>
            match(row, userId, agentId) &&
            row.enabled === true &&
            row.send_mode === "autopilot" &&
            row.trigger_key === triggerKey,
        )
        .map(clone);
    },

    async insertRule(row) {
      const saved = {
        id: row.id ?? RULE,
        created_at: NOW,
        updated_at: NOW,
        ...clone(row),
      };
      state.rules.set(saved.id, saved);
      return clone(saved);
    },

    async updateRule(userId, agentId, ruleId, patch) {
      const current = state.rules.get(ruleId);
      if (!match(current, userId, agentId)) return null;
      const saved = {
        ...clone(current),
        ...clone(patch),
        updated_at: NOW,
      };
      state.rules.set(ruleId, saved);
      return clone(saved);
    },

    async listEvents(userId, agentId, { limit = 100 } = {}) {
      return state.events
        .filter((row) => match(row, userId, agentId))
        .slice(-limit)
        .reverse()
        .map(clone);
    },

    async findEventByProviderEventId(provider, providerEventId) {
      const row = state.events.find(
        (item) =>
          item.provider === provider &&
          item.provider_event_id === providerEventId,
      );
      return clone(row ?? null);
    },

    async insertEvent(row) {
      const duplicate = row.provider_event_id
        ? state.events.find(
            (item) =>
              item.provider === row.provider &&
              item.provider_event_id === row.provider_event_id,
          )
        : null;
      if (duplicate) return clone(duplicate);
      const saved = {
        id: `88888888-8888-4888-8888-${String(state.events.length + 1).padStart(12, "0")}`,
        created_at: NOW,
        ...clone(row),
      };
      state.events.push(saved);
      return clone(saved);
    },
  };
}

function seedSettings(store, overrides = {}) {
  const row = {
    id: "77777777-7777-4777-8777-777777777777",
    user_id: OWNER,
    agent_id: AGENT,
    provider: "resend",
    enabled: true,
    operating_mode: "approval_required",
    emergency_paused: false,
    daily_send_cap: 5,
    from_name: "Nova",
    from_email: "nova@korlixdeveloper.com",
    reply_to_email: "reply@korlixdeveloper.com",
    physical_address: "100 Demo Avenue, Columbus, OH 43215",
    timezone: "UTC",
    metadata: {
      sendWindowStart: "00:00",
      sendWindowEnd: "23:59",
      marketingEnabled: true,
    },
    created_at: NOW,
    updated_at: NOW,
    ...clone(overrides),
  };
  store.state.settings.set(`${OWNER}:${AGENT}`, row);
  return clone(row);
}

function seedRecipient(store, overrides = {}) {
  const row = {
    id: RECIPIENT,
    user_id: OWNER,
    agent_id: AGENT,
    email: "customer@example.com",
    display_name: "Demo Customer",
    source_kind: "user_entered",
    consent_status: "transactional_only",
    consent_recorded_at: null,
    unsubscribed_at: null,
    suppressed_at: null,
    suppression_reason: null,
    active: true,
    metadata: {},
    created_at: NOW,
    updated_at: NOW,
    ...clone(overrides),
  };
  store.state.recipients.set(row.id, row);
  return clone(row);
}

function seedApprovedMessage(store, overrides = {}) {
  const nonce = "confirmation-nonce-123";
  const row = {
    id: MESSAGE,
    user_id: OWNER,
    agent_id: AGENT,
    recipient_id: RECIPIENT,
    rule_id: null,
    to_email: "customer@example.com",
    subject: "Approved follow-up",
    text_body: "Thank you for speaking with Nova.",
    html_body: "",
    message_kind: "transactional",
    status: "approved",
    authorization_type: "one_time_confirmation",
    authorized_at: NOW,
    authorized_by: OWNER,
    confirmation_nonce_hash: crypto
      .createHash("sha256")
      .update(nonce)
      .digest("hex"),
    idempotency_key: "manual-message-1",
    provider: "resend",
    provider_message_id: null,
    physical_address_snapshot: "",
    unsubscribe_url_snapshot: "",
    scheduled_at: null,
    last_attempt_at: null,
    attempt_count: 0,
    sent_at: null,
    failure_code: null,
    failure_message: null,
    metadata: {},
    created_at: NOW,
    updated_at: NOW,
    ...clone(overrides),
  };
  store.state.messages.set(row.id, row);
  return { row: clone(row), nonce };
}

function providerFixture({ fail = null } = {}) {
  const calls = [];
  return {
    calls,
    async send(input) {
      calls.push(clone(input));
      if (fail) throw fail;
      return {
        provider: "resend",
        providerMessageId: `resend-${calls.length}`,
        idempotencyKey: `korlix-agent-email/${input.message.id}`,
      };
    },
  };
}

function fixture({
  env = environment(),
  profileValue = profile(),
  provider = providerFixture(),
} = {}) {
  const store = memoryStore();
  let idCounter = 0;
  const ids = [
    MESSAGE,
    RULE,
    "99999999-9999-4999-8999-999999999991",
    "99999999-9999-4999-8999-999999999992",
  ];
  const service = createKorlixAgentEmailDeliveryService({
    environment: env,
    store,
    loadAgentProfile: async () => clone(profileValue),
    provider,
    now: () => new Date(NOW),
    randomUUID: () => ids[idCounter++] ?? crypto.randomUUID(),
  });
  return { store, service, provider };
}

async function expectCode(callback, code) {
  await assert.rejects(callback, (error) => error?.code === code);
}

function signWebhook(payload, {
  secret = WEBHOOK_SECRET,
  messageId = "msg_test_webhook_1",
  timestamp = Math.floor(new Date(NOW).getTime() / 1000),
} = {}) {
  const body = typeof payload === "string" ? payload : JSON.stringify(payload);
  const secretBytes = Buffer.from(secret.slice("whsec_".length), "base64");
  const signature = crypto
    .createHmac("sha256", secretBytes)
    .update(`${messageId}.${timestamp}.${body}`)
    .digest("base64");
  return {
    body,
    headers: {
      "svix-id": messageId,
      "svix-timestamp": String(timestamp),
      "svix-signature": `v1,${signature}`,
    },
  };
}

const tests = [];
function test(name, callback) {
  tests.push({ name, callback });
}

test("delivery installer registers controlled routes without sending during installation", async () => {
  const registered = [];
  const app = {};
  for (const method of ["get", "post", "patch"]) {
    app[method] = (path) => registered.push(`${method.toUpperCase()} ${path}`);
  }
  const provider = providerFixture();
  const installed = installKorlixAgentEmailDeliveryRoutes(app, {
    environment: environment(),
    store: memoryStore(),
    requireUser: async () => ({ id: OWNER }),
    loadAgentProfile: async () => profile(),
    provider,
    logger: { error() {} },
  });
  assert.equal(registered.length, 8);
  assert.equal(provider.calls.length, 0);
  assert.equal(installed.controlledSendImplemented, true);
  assert.equal(installed.webhookEventsImplemented, true);
  assert.equal(installed.autopilotTriggerImplemented, true);
  assert.equal(installed.autopilotSchedulerConfigured, false);
});

test("Supabase persistence claims sends only through the atomic service-role RPC", async () => {
  const calls = [];
  const client = {
    from() {
      throw new Error("Table access should not run in this claim test.");
    },
    async rpc(name, args) {
      calls.push({ name, args });
      return {
        data: [{ id: MESSAGE, status: "sending" }],
        error: null,
      };
    },
  };
  const store = createKorlixAgentEmailSupabaseStore(client);
  const claimed = await store.claimMessageForSend({
    userId: OWNER,
    agentId: AGENT,
    messageId: MESSAGE,
    claimedAt: NOW,
    confirmationNonceHash: null,
  });
  assert.equal(claimed.status, "sending");
  assert.deepEqual(calls, [{
    name: "korlix_agent_email_claim_send_build133",
    args: {
      p_user_id: OWNER,
      p_agent_id: AGENT,
      p_message_id: MESSAGE,
      p_claimed_at: NOW,
      p_confirmation_nonce_hash: null,
    },
  }]);
});

test("delivery context requires the exact existing Nova owner", async () => {
  const { service } = fixture();
  await expectCode(
    () => service.getDeliveryStatus({ userId: OTHER, agentId: AGENT }),
    "agent_email_existing_nova_required",
  );
});

test("delivery context requires active custom Nova and agent_email authorization", async () => {
  const inactive = fixture({ profileValue: profile({ active: false }) });
  await expectCode(
    () => inactive.service.getDeliveryStatus({ userId: OWNER, agentId: AGENT }),
    "agent_email_custom_active_nova_required",
  );
  const noTool = fixture({
    profileValue: profile({ toolIds: ["general_chat", "memory"] }),
  });
  await expectCode(
    () => noTool.service.getDeliveryStatus({ userId: OWNER, agentId: AGENT }),
    "agent_email_tool_not_authorized",
  );
});

test("send and Autopilot runtime switches default closed independently", async () => {
  const { service, store } = fixture({
    env: environment({
      KORLIX_AGENT_EMAIL_SEND_ENABLED: "false",
      KORLIX_AGENT_EMAIL_AUTOPILOT_ENABLED: "false",
    }),
  });
  seedSettings(store, { operating_mode: "autopilot" });
  const result = await service.getDeliveryStatus({ userId: OWNER, agentId: AGENT });
  assert.equal(result.canSend, false);
  assert.equal(result.canAutopilot, false);
  assert.equal(result.controlledSendImplemented, true);
});

test("Draft Only operating mode blocks provider sending", async () => {
  const { service, store } = fixture();
  seedSettings(store, { operating_mode: "draft_only" });
  seedRecipient(store);
  const { nonce } = seedApprovedMessage(store);
  await expectCode(
    () => service.sendApprovedDraft({
      userId: OWNER,
      agentId: AGENT,
      messageId: MESSAGE,
      body: { confirmed: true, confirmationNonce: nonce },
    }),
    "agent_email_send_runtime_disabled",
  );
});

test("emergency pause blocks sending even when the draft is approved", async () => {
  const { service, store } = fixture({
    env: environment({ KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE: "true" }),
  });
  seedSettings(store);
  seedRecipient(store);
  const { nonce } = seedApprovedMessage(store);
  await expectCode(
    () => service.sendApprovedDraft({
      userId: OWNER,
      agentId: AGENT,
      messageId: MESSAGE,
      body: { confirmed: true, confirmationNonce: nonce },
    }),
    "agent_email_send_runtime_disabled",
  );
});

test("marketing sending remains fail-closed until its separate runtime switch is enabled", async () => {
  const { service, store, provider } = fixture({
    env: environment({
      KORLIX_AGENT_EMAIL_MARKETING_SEND_ENABLED: "false",
    }),
  });
  seedSettings(store);
  seedRecipient(store, {
    consent_status: "marketing_opt_in",
    consent_recorded_at: NOW,
  });
  const { nonce } = seedApprovedMessage(store, {
    message_kind: "marketing",
    physical_address_snapshot: "100 Demo Avenue, Columbus, OH 43215",
    unsubscribe_url_snapshot: "https://korlixdeveloper.com/unsubscribe",
  });
  await expectCode(
    () => service.sendApprovedDraft({
      userId: OWNER,
      agentId: AGENT,
      messageId: MESSAGE,
      body: { confirmed: true, confirmationNonce: nonce },
    }),
    "agent_email_marketing_send_disabled",
  );
  assert.equal(provider.calls.length, 0);
});

test("one-time send requires explicit confirmation and the exact approval nonce", async () => {
  const { service, store } = fixture();
  seedSettings(store);
  seedRecipient(store);
  seedApprovedMessage(store);
  await expectCode(
    () => service.sendApprovedDraft({
      userId: OWNER,
      agentId: AGENT,
      messageId: MESSAGE,
      body: {},
    }),
    "agent_email_send_confirmation_required",
  );
  await expectCode(
    () => service.sendApprovedDraft({
      userId: OWNER,
      agentId: AGENT,
      messageId: MESSAGE,
      body: {
        confirmed: true,
        confirmationNonce: "wrong-confirmation-nonce",
      },
    }),
    "agent_email_send_confirmation_nonce_mismatch",
  );
});

test("one-time approval hash is passed into the atomic database claim", async () => {
  const { service, store } = fixture();
  seedSettings(store);
  seedRecipient(store);
  const { nonce } = seedApprovedMessage(store);
  await service.sendApprovedDraft({
    userId: OWNER,
    agentId: AGENT,
    messageId: MESSAGE,
    body: { confirmed: true, confirmationNonce: nonce },
  });
  assert.equal(
    store.state.lastClaimArgs.confirmationNonceHash,
    crypto.createHash("sha256").update(nonce).digest("hex"),
  );
});

test("a late emergency pause after the atomic claim aborts before Resend and restores the message", async () => {
  const { service, store, provider } = fixture();
  seedSettings(store);
  seedRecipient(store);
  const { nonce } = seedApprovedMessage(store);
  const claim = store.claimMessageForSend.bind(store);
  store.claimMessageForSend = async (input) => {
    const result = await claim(input);
    const key = `${OWNER}:${AGENT}`;
    store.state.settings.set(key, {
      ...store.state.settings.get(key),
      emergency_paused: true,
    });
    return result;
  };

  await expectCode(
    () => service.sendApprovedDraft({
      userId: OWNER,
      agentId: AGENT,
      messageId: MESSAGE,
      body: { confirmed: true, confirmationNonce: nonce },
    }),
    "agent_email_send_runtime_disabled",
  );

  const saved = store.state.messages.get(MESSAGE);
  assert.equal(provider.calls.length, 0);
  assert.equal(saved.status, "approved");
  assert.equal(saved.last_attempt_at, null);
  assert.equal(saved.attempt_count, 0);
  assert.equal(store.state.restoreCalls.length, 1);
  assert.equal(store.state.events.at(-1).event_type, "send_aborted");
});

test("recipient suppression is rechecked immediately before provider sending", async () => {
  const { service, store, provider } = fixture();
  seedSettings(store);
  seedRecipient(store, {
    active: false,
    consent_status: "suppressed",
    suppressed_at: NOW,
  });
  const { nonce } = seedApprovedMessage(store);
  await expectCode(
    () => service.sendApprovedDraft({
      userId: OWNER,
      agentId: AGENT,
      messageId: MESSAGE,
      body: { confirmed: true, confirmationNonce: nonce },
    }),
    "agent_email_recipient_blocked",
  );
  assert.equal(provider.calls.length, 0);
});

test("future schedules and closed send windows fail before provider access", async () => {
  const future = fixture();
  seedSettings(future.store);
  seedRecipient(future.store);
  const first = seedApprovedMessage(future.store, {
    scheduled_at: "2026-08-14T15:00:00.000Z",
  });
  await expectCode(
    () => future.service.sendApprovedDraft({
      userId: OWNER,
      agentId: AGENT,
      messageId: MESSAGE,
      body: { confirmed: true, confirmationNonce: first.nonce },
    }),
    "agent_email_scheduled_for_later",
  );

  const closed = fixture();
  seedSettings(closed.store, {
    metadata: {
      sendWindowStart: "16:00",
      sendWindowEnd: "17:00",
      marketingEnabled: true,
    },
  });
  seedRecipient(closed.store);
  const second = seedApprovedMessage(closed.store);
  await expectCode(
    () => closed.service.sendApprovedDraft({
      userId: OWNER,
      agentId: AGENT,
      messageId: MESSAGE,
      body: { confirmed: true, confirmationNonce: second.nonce },
    }),
    "agent_email_send_window_closed",
  );
});

test("daily send cap is enforced server-side", async () => {
  const { service, store, provider } = fixture();
  seedSettings(store, { daily_send_cap: 1 });
  seedRecipient(store);
  seedApprovedMessage(store);
  store.state.messages.set("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", {
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    user_id: OWNER,
    agent_id: AGENT,
    status: "sent",
    sent_at: NOW,
  });
  await expectCode(
    () => service.sendApprovedDraft({
      userId: OWNER,
      agentId: AGENT,
      messageId: MESSAGE,
      body: {
        confirmed: true,
        confirmationNonce: "confirmation-nonce-123",
      },
    }),
    "agent_email_daily_send_cap_reached",
  );
  assert.equal(provider.calls.length, 0);
});

test("successful one-time send claims, sends, stores provider ID, and audits", async () => {
  const { service, store, provider } = fixture();
  seedSettings(store);
  seedRecipient(store);
  const { nonce } = seedApprovedMessage(store);
  const result = await service.sendApprovedDraft({
    userId: OWNER,
    agentId: AGENT,
    messageId: MESSAGE,
    body: { confirmed: true, confirmationNonce: nonce },
  });
  assert.equal(result.sent, true);
  assert.equal(result.replayed, false);
  assert.equal(result.message.status, "sent");
  assert.equal(result.message.providerMessageId, "resend-1");
  assert.equal(provider.calls.length, 1);
  assert.deepEqual(
    store.state.events.map((event) => event.event_type),
    ["send_attempted", "send_accepted"],
  );
});

test("sent-message replay never invokes Resend twice", async () => {
  const { service, store, provider } = fixture();
  seedSettings(store);
  seedRecipient(store);
  const { nonce } = seedApprovedMessage(store);
  await service.sendApprovedDraft({
    userId: OWNER,
    agentId: AGENT,
    messageId: MESSAGE,
    body: { confirmed: true, confirmationNonce: nonce },
  });
  const replay = await service.sendApprovedDraft({
    userId: OWNER,
    agentId: AGENT,
    messageId: MESSAGE,
    body: { confirmed: true, confirmationNonce: nonce },
  });
  assert.equal(replay.replayed, true);
  assert.equal(replay.sent, true);
  assert.equal(provider.calls.length, 1);
});

test("provider failure records a retryable failed state and audit event", async () => {
  const provider = providerFixture({
    fail: Object.assign(new Error("Temporary provider outage"), {
      code: "agent_email_resend_network_error",
      statusCode: 503,
    }),
  });
  const { service, store } = fixture({ provider });
  seedSettings(store);
  seedRecipient(store);
  const { nonce } = seedApprovedMessage(store);
  await expectCode(
    () => service.sendApprovedDraft({
      userId: OWNER,
      agentId: AGENT,
      messageId: MESSAGE,
      body: { confirmed: true, confirmationNonce: nonce },
    }),
    "agent_email_resend_failed",
  );
  assert.equal(store.state.messages.get(MESSAGE).status, "failed");
  assert.equal(store.state.events.at(-1).event_type, "send_failed");
});

test("failed one-time send can be retried safely with the same approval nonce", async () => {
  let calls = 0;
  const provider = {
    async send(input) {
      calls += 1;
      if (calls === 1) {
        const error = new Error("Temporary");
        error.code = "agent_email_resend_network_error";
        error.statusCode = 503;
        throw error;
      }
      return {
        provider: "resend",
        providerMessageId: "resend-retry",
        idempotencyKey: `korlix-agent-email/${input.message.id}`,
      };
    },
  };
  const { service, store } = fixture({ provider });
  seedSettings(store);
  seedRecipient(store);
  const { nonce } = seedApprovedMessage(store);
  await assert.rejects(() => service.sendApprovedDraft({
    userId: OWNER,
    agentId: AGENT,
    messageId: MESSAGE,
    body: { confirmed: true, confirmationNonce: nonce },
  }));
  const retry = await service.sendApprovedDraft({
    userId: OWNER,
    agentId: AGENT,
    messageId: MESSAGE,
    body: { confirmed: true, confirmationNonce: nonce },
  });
  assert.equal(retry.sent, true);
  assert.equal(retry.message.providerMessageId, "resend-retry");
  assert.equal(calls, 2);
});

test("a stale ambiguous provider failure requires reconciliation instead of an unsafe retry", async () => {
  const { service, store, provider } = fixture();
  seedSettings(store);
  seedRecipient(store);
  const { nonce } = seedApprovedMessage(store, {
    status: "failed",
    last_attempt_at: "2026-08-12T14:00:00.000Z",
    attempt_count: 1,
    failure_code: "agent_email_resend_timeout",
    failure_message: "Earlier ambiguous timeout",
    metadata: {
      lastFailureRetryable: true,
      lastFailureAmbiguous: true,
      retryDeadlineAt: "2026-08-13T13:00:00.000Z",
    },
  });
  await expectCode(
    () => service.sendApprovedDraft({
      userId: OWNER,
      agentId: AGENT,
      messageId: MESSAGE,
      body: { confirmed: true, confirmationNonce: nonce },
    }),
    "agent_email_send_reconciliation_required",
  );
  assert.equal(provider.calls.length, 0);
});

test("a nonretryable provider rejection requires editing and explicit reapproval", async () => {
  const { service, store, provider } = fixture();
  seedSettings(store);
  seedRecipient(store);
  const { nonce } = seedApprovedMessage(store, {
    status: "failed",
    last_attempt_at: "2026-08-13T14:30:00.000Z",
    attempt_count: 1,
    failure_code: "agent_email_resend_validation_error",
    failure_message: "Provider rejected invalid content",
    metadata: {
      lastFailureRetryable: false,
      lastFailureAmbiguous: false,
      retryDeadlineAt: null,
    },
  });
  await expectCode(
    () => service.sendApprovedDraft({
      userId: OWNER,
      agentId: AGENT,
      messageId: MESSAGE,
      body: { confirmed: true, confirmationNonce: nonce },
    }),
    "agent_email_message_requires_edit_and_reapproval",
  );
  assert.equal(provider.calls.length, 0);
});

test("Resend provider sends to the official endpoint with provider idempotency and marketing footer", async () => {
  const requests = [];
  const provider = createKorlixAgentEmailResendProvider({
    environment: environment(),
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      return {
        ok: true,
        status: 200,
        async json() {
          return { id: "resend-provider-id" };
        },
      };
    },
  });
  const result = await provider.send({
    settings: { reply_to_email: "reply@korlixdeveloper.com" },
    message: {
      id: MESSAGE,
      to_email: "customer@example.com",
      subject: "Marketing message",
      text_body: "Approved offer",
      html_body: "",
      message_kind: "marketing",
      unsubscribe_url_snapshot: "https://korlixdeveloper.com/unsubscribe",
      physical_address_snapshot: "100 Demo Avenue, Columbus, OH 43215",
    },
  });
  assert.equal(result.providerMessageId, "resend-provider-id");
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, "https://api.resend.com/emails");
  assert.equal(
    requests[0].options.headers["Idempotency-Key"],
    `korlix-agent-email/${MESSAGE}`,
  );
  const payload = JSON.parse(requests[0].options.body);
  assert.match(payload.text, /Unsubscribe:/);
  assert.match(payload.text, /100 Demo Avenue/);
  assert.equal(payload.reply_to, "reply@korlixdeveloper.com");
});

test("Resend concurrent idempotent requests are classified as safely retryable", async () => {
  const provider = createKorlixAgentEmailResendProvider({
    environment: environment(),
    fetchImpl: async () => ({
      ok: false,
      status: 409,
      async json() {
        return {
          name: "concurrent_idempotent_requests",
          message: "The original request is still processing.",
        };
      },
    }),
  });
  await assert.rejects(
    () => provider.send({
      message: {
        id: MESSAGE,
        to_email: "customer@example.com",
        subject: "Hello",
        text_body: "Body",
        html_body: "",
        message_kind: "transactional",
      },
      settings: {},
    }),
    (error) =>
      error?.code ===
        "agent_email_resend_concurrent_idempotent_requests" &&
      error?.statusCode === 503,
  );
});

test("template rendering substitutes only declared variables and fails on missing data", async () => {
  assert.equal(
    korlixAgentEmailRenderTemplate("Hello {{recipient_name}}", {
      recipient_name: "Ricardo",
    }),
    "Hello Ricardo",
  );
  await expectCode(
    async () => korlixAgentEmailRenderTemplate("Hello {{missing}}", {}),
    "agent_email_autopilot_variables_missing",
  );
});

test("Svix-compatible webhook verification requires raw body, timestamp, and valid signature", async () => {
  const signed = signWebhook({
    type: "email.sent",
    created_at: NOW,
    data: { email_id: "resend-1" },
  });
  const verified = verifyKorlixAgentEmailResendWebhook({
    rawBody: signed.body,
    headers: signed.headers,
    secret: WEBHOOK_SECRET,
    now: () => new Date(NOW),
  });
  assert.equal(verified.providerEventId, "msg_test_webhook_1");
  assert.equal(verified.event.type, "email.sent");
  await expectCode(
    async () => verifyKorlixAgentEmailResendWebhook({
      rawBody: `${signed.body} `,
      headers: signed.headers,
      secret: WEBHOOK_SECRET,
      now: () => new Date(NOW),
    }),
    "agent_email_webhook_signature_invalid",
  );
});

test("verified delivery webhook updates message state and stores an idempotent event", async () => {
  const { service, store } = fixture();
  seedSettings(store);
  seedRecipient(store);
  seedApprovedMessage(store, {
    status: "sent",
    provider_message_id: "resend-delivered",
    sent_at: NOW,
  });
  const signed = signWebhook({
    type: "email.delivered",
    created_at: NOW,
    data: {
      email_id: "resend-delivered",
      to: ["customer@example.com"],
    },
  });
  const first = await service.processResendWebhook({
    rawBody: signed.body,
    headers: signed.headers,
  });
  const second = await service.processResendWebhook({
    rawBody: signed.body,
    headers: signed.headers,
  });
  assert.equal(first.matched, true);
  assert.equal(first.replayed, false);
  assert.equal(first.message.deliveryStatus, "email.delivered");
  assert.equal(second.replayed, true);
  assert.equal(store.state.events.length, 1);
});

test("out-of-order nonterminal webhooks do not regress the latest delivery state", async () => {
  const { service, store } = fixture();
  seedSettings(store);
  seedRecipient(store);
  seedApprovedMessage(store, {
    status: "sent",
    provider_message_id: "resend-ordering",
    sent_at: NOW,
    metadata: {},
  });

  const delivered = JSON.stringify({
    type: "email.delivered",
    created_at: "2026-08-13T15:00:00.000Z",
    data: { email_id: "resend-ordering", to: ["customer@example.com"] },
  });
  const deliveredSigned = signWebhook(delivered, {
    messageId: "msg-delivered-ordering",
  });
  await service.processResendWebhook({
    rawBody: deliveredSigned.body,
    headers: deliveredSigned.headers,
  });

  const olderSent = JSON.stringify({
    type: "email.sent",
    created_at: "2026-08-13T14:59:00.000Z",
    data: { email_id: "resend-ordering", to: ["customer@example.com"] },
  });
  const olderSentSigned = signWebhook(olderSent, {
    messageId: "msg-sent-ordering",
  });
  await service.processResendWebhook({
    rawBody: olderSentSigned.body,
    headers: olderSentSigned.headers,
  });

  const saved = store.state.messages.get(MESSAGE);
  assert.equal(saved.metadata.deliveryStatus, "email.delivered");
  assert.equal(saved.metadata.deliveredAt, "2026-08-13T15:00:00.000Z");
});

test("bounce, complaint, and suppression events automatically suppress the approved recipient", async () => {
  for (const [index, type] of [
    "email.bounced",
    "email.complained",
    "email.suppressed",
  ].entries()) {
    const { service, store } = fixture();
    seedSettings(store);
    seedRecipient(store);
    seedApprovedMessage(store, {
      status: "sent",
      provider_message_id: `resend-terminal-${index}`,
      sent_at: NOW,
    });
    const signed = signWebhook(
      {
        type,
        created_at: NOW,
        data: {
          email_id: `resend-terminal-${index}`,
          bounce: { message: "Permanent rejection" },
        },
      },
      { messageId: `msg_terminal_${index}` },
    );
    await service.processResendWebhook({
      rawBody: signed.body,
      headers: signed.headers,
    });
    const recipient = store.state.recipients.get(RECIPIENT);
    assert.equal(recipient.active, false);
    assert.equal(recipient.consent_status, "suppressed");
  }
});

test("Autopilot rule rejects arbitrary email recipient fields", async () => {
  const { service, store } = fixture();
  seedSettings(store, { operating_mode: "autopilot" });
  seedRecipient(store);
  await expectCode(
    () => service.createRule({
      userId: OWNER,
      agentId: AGENT,
      body: {
        confirmed: true,
        name: "Bad rule",
        triggerKey: "demo.followup",
        recipientEmails: ["guessed@example.com"],
      },
    }),
    "agent_email_rule_recipient_scope_prohibited",
  );
});

test("Autopilot rule requires explicit preapproval and confirmation nonce", async () => {
  const { service, store } = fixture();
  seedSettings(store, { operating_mode: "autopilot" });
  seedRecipient(store);
  const base = {
    confirmed: true,
    name: "Demo follow-up",
    triggerKey: "demo.followup",
    recipientIds: [RECIPIENT],
    subjectTemplate: "Hello {{recipient_name}}",
    textTemplate: "Event {{event_id}}",
    sendMode: "autopilot",
    enabled: true,
  };
  await expectCode(
    () => service.createRule({ userId: OWNER, agentId: AGENT, body: base }),
    "agent_email_rule_reapproval_required",
  );
  await expectCode(
    () => service.createRule({
      userId: OWNER,
      agentId: AGENT,
      body: { ...base, preapproved: true },
    }),
    "agent_email_rule_confirmation_nonce_required",
  );
});

test("preapproved Autopilot rule stores only explicit approved recipient IDs", async () => {
  const { service, store } = fixture();
  seedSettings(store, { operating_mode: "autopilot" });
  seedRecipient(store);
  const result = await service.createRule({
    userId: OWNER,
    agentId: AGENT,
    body: {
      confirmed: true,
      preapproved: true,
      confirmationNonce: "autopilot-confirmation-123",
      name: "Demo follow-up",
      triggerKey: "demo.followup",
      recipientIds: [RECIPIENT],
      subjectTemplate: "Hello {{recipient_name}}",
      textTemplate: "Event {{event_id}}",
      sendMode: "autopilot",
      enabled: true,
      maxSendsPerDay: 3,
    },
  });
  assert.equal(result.rule.preapproved, true);
  assert.deepEqual(result.rule.recipientIds, [RECIPIENT]);
  assert.equal(result.rule.sendMode, "autopilot");
  assert.equal(store.state.rules.size, 1);
});

test("Autopilot recipient scope cannot exceed the server batch cap", async () => {
  const secondRecipient = "66666666-6666-4666-8666-666666666666";
  const { service, store } = fixture({
    env: environment({ KORLIX_AGENT_EMAIL_AUTOPILOT_BATCH_CAP: "1" }),
  });
  seedSettings(store, { operating_mode: "autopilot" });
  seedRecipient(store);
  seedRecipient(store, {
    id: secondRecipient,
    email: "second@example.com",
  });
  await expectCode(
    () => service.createRule({
      userId: OWNER,
      agentId: AGENT,
      body: {
        confirmed: true,
        preapproved: true,
        confirmationNonce: "autopilot-confirmation-123",
        name: "Too broad",
        triggerKey: "demo.followup",
        recipientIds: [RECIPIENT, secondRecipient],
        subjectTemplate: "Hello {{recipient_name}}",
        textTemplate: "Event {{event_id}}",
        sendMode: "autopilot",
        enabled: true,
      },
    }),
    "agent_email_rule_recipient_scope_required",
  );
});

test("changing protected Autopilot content requires a new complete preapproval", async () => {
  const { service, store } = fixture();
  seedSettings(store, { operating_mode: "autopilot" });
  seedRecipient(store);
  const created = await service.createRule({
    userId: OWNER,
    agentId: AGENT,
    body: {
      confirmed: true,
      preapproved: true,
      confirmationNonce: "autopilot-confirmation-123",
      name: "Demo follow-up",
      triggerKey: "demo.followup",
      recipientIds: [RECIPIENT],
      subjectTemplate: "Hello {{recipient_name}}",
      textTemplate: "Event {{event_id}}",
      sendMode: "autopilot",
      enabled: true,
    },
  });
  await expectCode(
    () => service.updateRule({
      userId: OWNER,
      agentId: AGENT,
      ruleId: created.rule.id,
      body: {
        confirmed: true,
        subjectTemplate: "Changed {{recipient_name}}",
      },
    }),
    "agent_email_rule_reapproval_required",
  );
});

test("preapproved Autopilot trigger creates and sends from rule scope only", async () => {
  const { service, store, provider } = fixture();
  seedSettings(store, { operating_mode: "autopilot" });
  seedRecipient(store);
  await service.createRule({
    userId: OWNER,
    agentId: AGENT,
    body: {
      confirmed: true,
      preapproved: true,
      confirmationNonce: "autopilot-confirmation-123",
      name: "Demo follow-up",
      triggerKey: "demo.followup",
      recipientIds: [RECIPIENT],
      subjectTemplate: "Hello {{recipient_name}}",
      textTemplate: "Event {{event_id}}: {{note}}",
      sendMode: "autopilot",
      enabled: true,
      allowedDays: [4],
    },
  });
  const result = await service.runAutopilot({
    body: {
      triggerKey: "demo.followup",
      eventId: "event-001",
      variables: { note: "Approved demo follow-up" },
    },
  });
  assert.equal(result.matchedRuleCount, 1);
  assert.equal(result.sentCount, 1);
  assert.equal(provider.calls.length, 1);
  assert.equal(provider.calls[0].message.to_email, "customer@example.com");
  assert.equal(provider.calls[0].message.authorization_type, "preapproved_rule");
});

test("Autopilot trigger replay is idempotent and never sends twice", async () => {
  const { service, store, provider } = fixture();
  seedSettings(store, { operating_mode: "autopilot" });
  seedRecipient(store);
  await service.createRule({
    userId: OWNER,
    agentId: AGENT,
    body: {
      confirmed: true,
      preapproved: true,
      confirmationNonce: "autopilot-confirmation-123",
      name: "Demo follow-up",
      triggerKey: "demo.followup",
      recipientIds: [RECIPIENT],
      subjectTemplate: "Hello {{recipient_name}}",
      textTemplate: "Event {{event_id}}",
      sendMode: "autopilot",
      enabled: true,
      allowedDays: [4],
    },
  });
  const request = {
    body: {
      triggerKey: "demo.followup",
      eventId: "event-idempotent-001",
      variables: {},
    },
  };
  const first = await service.runAutopilot(request);
  const second = await service.runAutopilot(request);
  assert.equal(first.sentCount, 1);
  assert.equal(second.replayedCount, 1);
  assert.equal(provider.calls.length, 1);
});

test("Autopilot request-selected recipients are prohibited", async () => {
  const { service, store } = fixture();
  seedSettings(store, { operating_mode: "autopilot" });
  await expectCode(
    () => service.runAutopilot({
      body: {
        triggerKey: "demo.followup",
        eventId: "event-001",
        recipientIds: [RECIPIENT],
      },
    }),
    "agent_email_autopilot_recipient_override_prohibited",
  );
});

test("marketing Autopilot requires opt-in, business address, and server unsubscribe URL", async () => {
  const { service, store } = fixture({
    env: environment({ KORLIX_AGENT_EMAIL_UNSUBSCRIBE_URL: "" }),
  });
  seedSettings(store, { operating_mode: "autopilot" });
  seedRecipient(store, {
    consent_status: "marketing_opt_in",
    consent_recorded_at: NOW,
  });
  await expectCode(
    () => service.createRule({
      userId: OWNER,
      agentId: AGENT,
      body: {
        confirmed: true,
        preapproved: true,
        confirmationNonce: "autopilot-confirmation-123",
        name: "Marketing follow-up",
        triggerKey: "demo.marketing",
        recipientIds: [RECIPIENT],
        subjectTemplate: "Offer",
        textTemplate: "Approved offer",
        sendMode: "autopilot",
        enabled: true,
        marketing: true,
      },
    }),
    "agent_email_unsubscribe_url_not_configured",
  );
});

test("both server entry points capture raw webhook bytes and install delivery routes before fallback", async () => {
  const backendServer = fs.readFileSync(
    new URL("./server.js", import.meta.url),
    "utf8",
  );
  const rootServer = fs.readFileSync(
    new URL("../server.js", import.meta.url),
    "utf8",
  );
  for (const source of [backendServer, rootServer]) {
    assert.equal(
      (source.match(/installKorlixAgentEmailDeliveryRoutes\(app/g) ?? []).length,
      1,
    );
    assert.match(source, /KORLIX_AGENT_EMAIL_RESEND_RAW_BODY_BUILD133/);
    assert.match(source, /req\.korlixAgentEmailRawBody = Buffer\.from\(buffer\)/);
    assert.match(source, /providerSendPathImplemented:\s*true/);
    assert.match(source, /autopilotExecutionImplemented:\s*true/);
    assert.match(source, /webhookEventsImplemented:\s*true/);
    assert.ok(
      source.indexOf("KORLIX_AGENT_EMAIL_DELIVERY_BUILD133_INSTALL_START") <
        source.indexOf('app.use("/api"'),
    );
  }
});

test("route catalog contains controlled send, webhook, rule, event, and internal Autopilot endpoints", async () => {
  assert.match(KORLIX_AGENT_EMAIL_DELIVERY_ROUTES.sendDraft, /\/send$/);
  assert.match(KORLIX_AGENT_EMAIL_DELIVERY_ROUTES.resendWebhook, /resend\/webhook$/);
  assert.match(KORLIX_AGENT_EMAIL_DELIVERY_ROUTES.autopilotRun, /autopilot\/run$/);
  assert.match(KORLIX_AGENT_EMAIL_DELIVERY_ROUTES.rules, /\/rules$/);
  assert.match(KORLIX_AGENT_EMAIL_DELIVERY_ROUTES.events, /\/events$/);
});

let passed = 0;
for (const entry of tests) {
  await entry.callback();
  passed += 1;
  console.log(`PASS ${passed}: ${entry.name}`);
}

assert.equal(passed, 38);
console.log(`KORLIX_AGENT_EMAIL_DELIVERY_TEST_COUNT=${passed}`);
console.log("KORLIX_AGENT_EMAIL_DELIVERY_TEST_PASS=true");
