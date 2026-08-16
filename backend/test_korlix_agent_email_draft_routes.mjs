import assert from "node:assert/strict";
import fs from "node:fs";

import {
  KORLIX_AGENT_EMAIL_DRAFT_ROUTES,
  KORLIX_AGENT_EMAIL_TABLES,
  createKorlixAgentEmailDraftService,
  installKorlixAgentEmailDraftRoutes,
} from "./korlix_agent_email_routes.mjs";

const OWNER = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";
const AGENT = "custom_nova";
const RECIPIENT = "33333333-3333-4333-8333-333333333333";
const MESSAGE = "44444444-4444-4444-8444-444444444444";

function environment(overrides = {}) {
  return {
    KORLIX_VAPI_NOVA_OWNER_UID: OWNER,
    KORLIX_VAPI_NOVA_AGENT_ID: AGENT,
    KORLIX_VAPI_NOVA_ASSISTANT_ID: "assistant-nova",
    KORLIX_AGENT_EMAIL_ENABLED: "false",
    KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE: "true",
    KORLIX_AGENT_EMAIL_FROM: "Nova <nova@korlixdeveloper.com>",
    RESEND_API_KEY: "test-only-key",
    ...overrides,
  };
}

function clone(value) {
  return value === undefined
    ? undefined
    : JSON.parse(JSON.stringify(value));
}

function memoryStore() {
  const state = {
    settings: new Map(),
    recipients: new Map(),
    messages: new Map(),
    events: [],
  };

  const key = (userId, agentId) => `${userId}:${agentId}`;
  const match = (row, userId, agentId) =>
    row.user_id === userId && row.agent_id === agentId;

  return {
    client: { serviceRole: true },
    state,

    async getSettings(userId, agentId) {
      return clone(state.settings.get(key(userId, agentId)) ?? null);
    },

    async saveSettings(row) {
      const current = state.settings.get(key(row.user_id, row.agent_id));
      const saved = {
        id: current?.id ?? "55555555-5555-4555-8555-555555555555",
        created_at: current?.created_at ?? "2026-08-13T12:00:00.000Z",
        updated_at: "2026-08-13T12:00:00.000Z",
        ...clone(current ?? {}),
        ...clone(row),
      };
      state.settings.set(key(row.user_id, row.agent_id), saved);
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
      return row && match(row, userId, agentId) ? clone(row) : null;
    },

    async findRecipientByEmail(userId, agentId, email) {
      const row = [...state.recipients.values()].find(
        (item) => match(item, userId, agentId) && item.email === email,
      );
      return clone(row ?? null);
    },

    async insertRecipient(row) {
      const id = state.recipients.size === 0
        ? RECIPIENT
        : `33333333-3333-4333-8333-${String(state.recipients.size + 1).padStart(12, "0")}`;
      const saved = {
        id,
        created_at: "2026-08-13T12:00:00.000Z",
        updated_at: "2026-08-13T12:00:00.000Z",
        ...clone(row),
      };
      state.recipients.set(id, saved);
      return clone(saved);
    },

    async updateRecipient(userId, agentId, recipientId, patch) {
      const current = state.recipients.get(recipientId);
      if (!current || !match(current, userId, agentId)) {
        return null;
      }
      const saved = {
        ...clone(current),
        ...clone(patch),
        updated_at: "2026-08-13T12:00:00.000Z",
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
      return row && match(row, userId, agentId) ? clone(row) : null;
    },

    async findMessageByIdempotency(userId, agentId, idempotencyKey) {
      const row = [...state.messages.values()].find(
        (item) =>
          match(item, userId, agentId) &&
          item.idempotency_key === idempotencyKey,
      );
      return clone(row ?? null);
    },

    async insertMessage(row) {
      const saved = {
        id: row.id ?? MESSAGE,
        created_at: "2026-08-13T12:00:00.000Z",
        updated_at: "2026-08-13T12:00:00.000Z",
        ...clone(row),
      };
      state.messages.set(saved.id, saved);
      return clone(saved);
    },

    async updateMessage(userId, agentId, messageId, patch) {
      const current = state.messages.get(messageId);
      if (!current || !match(current, userId, agentId)) {
        return null;
      }
      const saved = {
        ...clone(current),
        ...clone(patch),
        updated_at: "2026-08-13T12:00:00.000Z",
      };
      state.messages.set(messageId, saved);
      return clone(saved);
    },

    async insertEvent(row) {
      const saved = {
        id: `66666666-6666-4666-8666-${String(state.events.length + 1).padStart(12, "0")}`,
        created_at: "2026-08-13T12:00:00.000Z",
        ...clone(row),
      };
      state.events.push(saved);
      return clone(saved);
    },
  };
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

function fixture({ profileValue = profile(), env = environment() } = {}) {
  const store = memoryStore();
  let currentProfile = profileValue;
  const service = createKorlixAgentEmailDraftService({
    environment: env,
    store,
    loadAgentProfile: async () => clone(currentProfile),
    now: () => new Date("2026-08-13T12:00:00.000Z"),
    randomUUID: () => MESSAGE,
  });

  return {
    store,
    service,
    setProfile(value) {
      currentProfile = value;
    },
  };
}

async function expectCode(callback, code) {
  await assert.rejects(
    callback,
    (error) => error?.code === code,
  );
}

async function enableSettings(service, overrides = {}) {
  return await service.saveSettings({
    userId: OWNER,
    agentId: AGENT,
    body: {
      confirmed: true,
      enabled: true,
      paused: false,
      mode: "draft_only",
      dailySendCap: 5,
      timezone: "America/New_York",
      physicalAddress: "100 Demo Avenue, Columbus, OH 43215",
      ...overrides,
    },
  });
}

async function addRecipient(service, overrides = {}) {
  return await service.saveRecipient({
    userId: OWNER,
    agentId: AGENT,
    body: {
      confirmed: true,
      email: "customer@example.com",
      displayName: "Demo Customer",
      approvalSource: "manual_user_entry",
      consentScope: "transactional",
      ...overrides,
    },
  });
}

const tests = [];
function test(name, callback) {
  tests.push({ name, callback });
}

test("route catalog and installer expose Draft Only operations without a send endpoint", async () => {
  const registered = [];
  const app = {};
  for (const method of ["get", "post", "put", "patch"]) {
    app[method] = (path) => registered.push(`${method.toUpperCase()} ${path}`);
  }

  const store = memoryStore();
  const installed = installKorlixAgentEmailDraftRoutes(app, {
    environment: environment(),
    store,
    requireUser: async () => ({ id: OWNER }),
    loadAgentProfile: async () => profile(),
    logger: { error() {} },
  });

  assert.equal(registered.length, 11);
  assert.equal(installed.providerSendPathImplemented, false);
  assert.equal(installed.emailSendIncluded, false);
  assert.equal(installed.autopilotExecutionIncluded, false);
  assert.equal(
    Object.values(KORLIX_AGENT_EMAIL_DRAFT_ROUTES).some((path) =>
      /send|resend|autopilot/i.test(path),
    ),
    false,
  );
});

test("exact existing Nova owner and Agent Hub ID are required", async () => {
  const { service } = fixture();
  await expectCode(
    () => service.getStatus({ userId: OTHER, agentId: AGENT }),
    "agent_email_existing_nova_required",
  );
  await expectCode(
    () => service.getStatus({ userId: OWNER, agentId: "custom_other" }),
    "agent_email_existing_nova_required",
  );
});

test("Agent Email requires Nova's active custom Agent Hub profile", async () => {
  const { service } = fixture({
    profileValue: profile({ isCustom: false }),
  });
  await expectCode(
    () => service.getStatus({ userId: OWNER, agentId: AGENT }),
    "agent_email_custom_active_nova_required",
  );
});

test("Agent Email requires explicit agent_email tool authorization", async () => {
  const { service } = fixture({
    profileValue: profile({ toolIds: ["general_chat", "memory"] }),
  });
  await expectCode(
    () => service.getStatus({ userId: OWNER, agentId: AGENT }),
    "agent_email_tool_not_authorized",
  );
});

test("status defaults to disabled Draft Only persistence with no send path", async () => {
  const { service } = fixture();
  const result = await service.getStatus({ userId: OWNER, agentId: AGENT });
  assert.equal(result.sameNova, true);
  assert.equal(result.settings.enabled, false);
  assert.equal(result.settings.mode, "draft_only");
  assert.equal(result.settings.paused, true);
  assert.equal(result.canDraft, false);
  assert.equal(result.canSend, false);
  assert.equal(result.providerSendPathImplemented, false);
});

test("settings require confirmation and persist server-authoritative controls", async () => {
  const { service } = fixture();
  await expectCode(
    () => service.saveSettings({
      userId: OWNER,
      agentId: AGENT,
      body: { enabled: true },
    }),
    "agent_email_settings_confirmation_required",
  );
  const saved = await enableSettings(service, {
    fromEmail: "nova@korlixdeveloper.com",
    replyToEmail: "support@korlixdeveloper.com",
  });
  assert.equal(saved.settings.enabled, true);
  assert.equal(saved.settings.mode, "draft_only");
  assert.equal(saved.settings.paused, false);
  assert.equal(saved.settings.dailySendCap, 5);
  assert.equal(saved.settings.fromEmail, "nova@korlixdeveloper.com");
  assert.equal(saved.sent, false);
});

test("approved recipient creation normalizes explicit user provenance", async () => {
  const { service } = fixture();
  await enableSettings(service);
  const result = await addRecipient(service, {
    email: " Customer@Example.COM ",
    sourceReference: "crm-record-7",
  });
  assert.equal(result.created, true);
  assert.equal(result.recipient.email, "customer@example.com");
  assert.equal(result.recipient.sourceKind, "user_entered");
  assert.equal(result.recipient.consentStatus, "transactional_only");
  assert.equal(result.sent, false);
});

test("scraped or guessed recipient sources fail closed", async () => {
  const { service } = fixture();
  await enableSettings(service);
  await expectCode(
    () => service.saveRecipient({
      userId: OWNER,
      agentId: AGENT,
      body: {
        confirmed: true,
        email: "lead@example.com",
        approvalSource: "scraped",
      },
    }),
    "agent_email_recipient_source_prohibited",
  );
});

test("marketing recipient creation requires a recorded consent date", async () => {
  const { service } = fixture();
  await enableSettings(service);
  await expectCode(
    () => addRecipient(service, {
      consentScope: "marketing",
    }),
    "agent_email_marketing_consent_required",
  );
  const result = await addRecipient(service, {
    consentScope: "marketing",
    consentAt: "2026-08-13T11:00:00Z",
  });
  assert.equal(result.recipient.consentStatus, "marketing_opt_in");
  assert.equal(result.recipient.active, true);
});

test("unsubscribe and suppression controls block silent reactivation", async () => {
  const { service } = fixture();
  await enableSettings(service);
  const added = await addRecipient(service);
  const unsubscribed = await service.updateRecipientStatus({
    userId: OWNER,
    agentId: AGENT,
    recipientId: added.recipient.id,
    body: { confirmed: true, status: "unsubscribed" },
  });
  assert.equal(unsubscribed.recipient.active, false);
  assert.ok(unsubscribed.recipient.unsubscribedAt);
  await expectCode(
    () => addRecipient(service),
    "agent_email_recipient_reactivation_required",
  );
  const suppressed = await service.updateRecipientStatus({
    userId: OWNER,
    agentId: AGENT,
    recipientId: added.recipient.id,
    body: {
      confirmed: true,
      status: "suppressed",
      suppressionReason: "Hard bounce",
    },
  });
  assert.equal(suppressed.recipient.consentStatus, "suppressed");
  assert.equal(suppressed.recipient.suppressionReason, "Hard bounce");
});

test("draft creation requires enabled settings and an approved active recipient", async () => {
  const { service } = fixture();
  await expectCode(
    () => service.createDraft({
      userId: OWNER,
      agentId: AGENT,
      body: {},
    }),
    "agent_email_settings_required",
  );
  await enableSettings(service);
  await expectCode(
    () => service.createDraft({
      userId: OWNER,
      agentId: AGENT,
      body: {
        recipientId: RECIPIENT,
        subject: "Follow-up",
        body: "Hello",
        idempotencyKey: "draft-1",
      },
    }),
    "agent_email_recipient_not_found",
  );
});

test("idempotent draft replay never creates a second message or provider send", async () => {
  const { service, store } = fixture();
  await enableSettings(service);
  const recipient = await addRecipient(service);
  const request = {
    userId: OWNER,
    agentId: AGENT,
    body: {
      recipientId: recipient.recipient.id,
      subject: "Follow-up",
      body: "Thank you for speaking with Nova.",
      idempotencyKey: "draft-idempotent-1",
    },
  };
  const first = await service.createDraft(request);
  const second = await service.createDraft(request);
  assert.equal(first.replayed, false);
  assert.equal(second.replayed, true);
  assert.equal(store.state.messages.size, 1);
  assert.equal(store.state.events.length, 1);
  assert.equal(first.sent, false);
  assert.equal(second.sent, false);
});

test("marketing drafts require opt-in, unsubscribe URL, and physical address", async () => {
  const { service } = fixture();
  await enableSettings(service, { physicalAddress: "" });
  const recipient = await addRecipient(service);
  await expectCode(
    () => service.createDraft({
      userId: OWNER,
      agentId: AGENT,
      body: {
        recipientId: recipient.recipient.id,
        subject: "Offer",
        body: "Demo offer",
        idempotencyKey: "marketing-draft-1",
        marketing: true,
      },
    }),
    "agent_email_marketing_footer_required",
  );
  await expectCode(
    () => service.createDraft({
      userId: OWNER,
      agentId: AGENT,
      body: {
        recipientId: recipient.recipient.id,
        subject: "Offer",
        body: "Demo offer",
        idempotencyKey: "marketing-draft-2",
        marketing: true,
        unsubscribeUrl: "https://example.com/unsubscribe",
        physicalAddress: "100 Demo Avenue, Columbus, OH 43215",
      },
    }),
    "agent_email_marketing_consent_required",
  );
});

test("editing an approved draft resets one-time approval and records an audit event", async () => {
  const { service, store } = fixture();
  await enableSettings(service);
  const recipient = await addRecipient(service);
  const created = await service.createDraft({
    userId: OWNER,
    agentId: AGENT,
    body: {
      recipientId: recipient.recipient.id,
      subject: "First subject",
      body: "First body",
      idempotencyKey: "edit-draft-1",
    },
  });
  await service.approveDraft({
    userId: OWNER,
    agentId: AGENT,
    messageId: created.draft.id,
    body: {
      confirmed: true,
      confirmationNonce: "confirmation-nonce-123",
    },
  });
  const edited = await service.updateDraft({
    userId: OWNER,
    agentId: AGENT,
    messageId: created.draft.id,
    body: { subject: "Updated subject" },
  });
  assert.equal(edited.approvalReset, true);
  assert.equal(edited.draft.status, "draft");
  assert.equal(edited.draft.authorizationType, "none");
  assert.equal(store.state.events.at(-1).event_type, "draft_updated");
});

test("editing a failed provider attempt resets retry state and requires a new approval", async () => {
  const { service, store } = fixture();
  await enableSettings(service);
  const recipient = await addRecipient(service);
  const created = await service.createDraft({
    userId: OWNER,
    agentId: AGENT,
    body: {
      recipientId: recipient.recipient.id,
      subject: "Failed subject",
      body: "Failed body",
      idempotencyKey: "failed-edit-draft-1",
    },
  });
  store.state.messages.set(created.draft.id, {
    ...store.state.messages.get(created.draft.id),
    status: "failed",
    authorization_type: "one_time_confirmation",
    authorized_at: "2026-08-13T11:00:00.000Z",
    authorized_by: OWNER,
    confirmation_nonce_hash: "a".repeat(64),
    last_attempt_at: "2026-08-13T11:30:00.000Z",
    attempt_count: 1,
    failure_code: "agent_email_resend_validation_error",
    failure_message: "Provider rejected the request",
    metadata: {
      lastFailureRetryable: false,
      lastFailureAmbiguous: false,
      retryDeadlineAt: null,
    },
  });

  const edited = await service.updateDraft({
    userId: OWNER,
    agentId: AGENT,
    messageId: created.draft.id,
    body: { subject: "Corrected subject" },
  });
  const stored = store.state.messages.get(created.draft.id);
  assert.equal(edited.approvalReset, true);
  assert.equal(stored.status, "draft");
  assert.equal(stored.authorization_type, "none");
  assert.equal(stored.last_attempt_at, null);
  assert.equal(stored.attempt_count, 0);
  assert.equal(stored.failure_code, null);
  assert.equal(stored.failure_message, null);
  assert.equal(stored.metadata.lastFailureRetryable, false);
});

test("one-time approval records a nonce hash but never sends email", async () => {
  const { service, store } = fixture();
  await enableSettings(service);
  const recipient = await addRecipient(service);
  const created = await service.createDraft({
    userId: OWNER,
    agentId: AGENT,
    body: {
      recipientId: recipient.recipient.id,
      subject: "Approved draft",
      body: "Reviewable body",
      idempotencyKey: "approval-draft-1",
    },
  });
  await expectCode(
    () => service.approveDraft({
      userId: OWNER,
      agentId: AGENT,
      messageId: created.draft.id,
      body: { confirmed: true },
    }),
    "agent_email_confirmation_nonce_required",
  );
  const result = await service.approveDraft({
    userId: OWNER,
    agentId: AGENT,
    messageId: created.draft.id,
    body: {
      confirmed: true,
      confirmationNonce: "confirmation-nonce-456",
    },
  });
  const stored = store.state.messages.get(created.draft.id);
  assert.equal(result.approved, true);
  assert.equal(result.sent, false);
  assert.equal(result.draft.status, "approved");
  assert.equal(result.draft.authorizationType, "one_time_confirmation");
  assert.match(stored.confirmation_nonce_hash, /^[0-9a-f]{64}$/);
  assert.equal(stored.provider_message_id, null);
  assert.equal(store.state.events.at(-1).event_type, "draft_approved");
});

test("both server entry points install the same draft routes before API fallback", async () => {
  const backendServer = fs.readFileSync(
    new URL("./server.js", import.meta.url),
    "utf8",
  );
  const rootServer = fs.readFileSync(
    new URL("../server.js", import.meta.url),
    "utf8",
  );
  const routeSource = fs.readFileSync(
    new URL("./korlix_agent_email_routes.mjs", import.meta.url),
    "utf8",
  );

  assert.equal(
    (backendServer.match(/installKorlixAgentEmailDraftRoutes\(app/g) ?? []).length,
    1,
  );
  assert.equal(
    (rootServer.match(/installKorlixAgentEmailDraftRoutes\(app/g) ?? []).length,
    1,
  );
  assert.ok(
    backendServer.indexOf("KORLIX_AGENT_EMAIL_DRAFT_ROUTES_BUILD133_INSTALL_START") <
      backendServer.indexOf("KORLIX_VAPI_NOVA_BUILD133_INSTALL_START"),
  );
  assert.ok(
    rootServer.indexOf("KORLIX_AGENT_EMAIL_DRAFT_ROUTES_BUILD133_INSTALL_START") <
      rootServer.indexOf('app.use("/api"'),
  );
  assert.doesNotMatch(routeSource, /https:\/\/api\.resend\.com\/emails/);
  assert.doesNotMatch(routeSource, /\/send["'`]/);
  assert.deepEqual(
    Object.keys(KORLIX_AGENT_EMAIL_TABLES).sort(),
    ["events", "messages", "recipients", "rules", "settings"],
  );
});

let passed = 0;
for (const entry of tests) {
  await entry.callback();
  passed += 1;
  console.log(`PASS ${passed}: ${entry.name}`);
}

assert.equal(passed, 17);
console.log(`KORLIX_AGENT_EMAIL_DRAFT_ROUTE_TEST_COUNT=${passed}`);
console.log("KORLIX_AGENT_EMAIL_DRAFT_ROUTE_TEST_PASS=true");
