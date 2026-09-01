import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";

import {
  KORLIX_AGENT_EMAIL_DELIVERY_ROUTES,
  createKorlixAgentEmailDeliveryService,
} from "./korlix_agent_email_delivery.mjs";

import {
  korlixAgentEmailNextWeeklyRunAt,
  korlixAgentEmailScheduleZonedParts,
} from "./korlix_agent_email_schedule_k134b.mjs";

const OWNER = "11111111-1111-4111-8111-111111111111";
const AGENT = "custom_nova";
const RECIPIENT = "33333333-3333-4333-8333-333333333333";
const WEEKLY_RULE = "55555555-5555-4555-8555-555555555555";
const MESSAGE_A = "77777777-7777-4777-8777-777777777777";
const MESSAGE_B = "88888888-8888-4888-8888-888888888888";

function clone(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

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
    KORLIX_AGENT_EMAIL_AUTOPILOT_SECRET: "schedule-test-secret",
    KORLIX_AGENT_EMAIL_AUTOPILOT_BATCH_CAP: "20",
    RESEND_API_KEY: "test-only",
    ...overrides,
  };
}

function profile() {
  return {
    id: AGENT,
    name: "Nova",
    isCustom: true,
    active: true,
    toolIds: ["general_chat", "memory", "agent_training", "agent_email"],
  };
}

function memoryStore() {
  const state = {
    settings: new Map(),
    recipients: new Map(),
    messages: new Map(),
    rules: new Map(),
    events: [],
  };
  const belongs = (row, userId, agentId) =>
    row?.user_id === userId && row?.agent_id === agentId;

  return {
    client: { serviceRole: true },
    state,

    async getSettings(userId, agentId) {
      return clone(state.settings.get(`${userId}:${agentId}`) ?? null);
    },

    async getRecipient(userId, agentId, recipientId) {
      const row = state.recipients.get(recipientId);
      return belongs(row, userId, agentId) ? clone(row) : null;
    },

    async countSentSince(userId, agentId, since) {
      return [...state.messages.values()].filter(
        (row) =>
          belongs(row, userId, agentId) &&
          row.status === "sent" &&
          String(row.sent_at ?? "") >= since,
      ).length;
    },

    async countRuleSentSince(userId, agentId, ruleId, since) {
      return [...state.messages.values()].filter(
        (row) =>
          belongs(row, userId, agentId) &&
          row.rule_id === ruleId &&
          row.status === "sent" &&
          String(row.sent_at ?? "") >= since,
      ).length;
    },

    async getMessage(userId, agentId, messageId) {
      const row = state.messages.get(messageId);
      return belongs(row, userId, agentId) ? clone(row) : null;
    },

    async findMessageByIdempotency(userId, agentId, idempotencyKey) {
      const row = [...state.messages.values()].find(
        (item) =>
          belongs(item, userId, agentId) &&
          item.idempotency_key === idempotencyKey,
      );
      return clone(row ?? null);
    },

    async insertMessage(row) {
      const existing = [...state.messages.values()].find(
        (item) =>
          item.user_id === row.user_id &&
          item.agent_id === row.agent_id &&
          item.idempotency_key === row.idempotency_key,
      );
      if (existing) return clone(existing);
      const saved = {
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        ...clone(row),
      };
      state.messages.set(saved.id, saved);
      return clone(saved);
    },

    async updateMessage(userId, agentId, messageId, patch) {
      const current = state.messages.get(messageId);
      if (!belongs(current, userId, agentId)) return null;
      const saved = {
        ...clone(current),
        ...clone(patch),
        updated_at: new Date().toISOString(),
      };
      state.messages.set(messageId, saved);
      return clone(saved);
    },

    async claimMessageForSend({
      userId,
      agentId,
      messageId,
      claimedAt,
    }) {
      const current = state.messages.get(messageId);
      if (!belongs(current, userId, agentId)) return null;
      if (current.status === "sent" && current.provider_message_id) {
        return clone(current);
      }
      if (!["approved", "failed"].includes(current.status)) return null;
      return await this.updateMessage(userId, agentId, messageId, {
        status: "sending",
        last_attempt_at: claimedAt,
        attempt_count: Math.max(0, Number(current.attempt_count) || 0) + 1,
      });
    },

    async restoreMessageAfterAbortedClaim({
      userId,
      agentId,
      messageId,
      patch,
    }) {
      return await this.updateMessage(userId, agentId, messageId, patch);
    },

    async insertEvent(row) {
      const saved = {
        id: crypto.randomUUID(),
        created_at: new Date().toISOString(),
        ...clone(row),
      };
      state.events.push(saved);
      return clone(saved);
    },

    async listRules(userId, agentId, { limit = 100 } = {}) {
      return [...state.rules.values()]
        .filter(
          (row) =>
            belongs(row, userId, agentId) &&
            !row.deleted_at,
        )
        .slice(0, limit)
        .map(clone);
    },

    async getRule(userId, agentId, ruleId) {
      const row = state.rules.get(ruleId);
      return belongs(row, userId, agentId) && !row.deleted_at
        ? clone(row)
        : null;
    },

    async insertRule(row) {
      const saved = {
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        ...clone(row),
      };
      state.rules.set(saved.id, saved);
      return clone(saved);
    },

    async updateRule(userId, agentId, ruleId, patch) {
      const current = state.rules.get(ruleId);
      if (!belongs(current, userId, agentId) || current.deleted_at) return null;
      const saved = {
        ...clone(current),
        ...clone(patch),
        updated_at: new Date().toISOString(),
      };
      state.rules.set(ruleId, saved);
      return clone(saved);
    },

    async softDeleteRule(userId, agentId, ruleId, patch) {
      return await this.updateRule(userId, agentId, ruleId, patch);
    },

    async listDueScheduledRules(userId, agentId, dueAt, { limit = 20 } = {}) {
      return [...state.rules.values()]
        .filter(
          (row) =>
            belongs(row, userId, agentId) &&
            row.enabled === true &&
            row.send_mode === "autopilot" &&
            ["once", "weekly"].includes(row.schedule_type) &&
            !row.deleted_at &&
            row.next_run_at &&
            row.next_run_at <= dueAt,
        )
        .sort((left, right) =>
          String(left.next_run_at).localeCompare(String(right.next_run_at)),
        )
        .slice(0, limit)
        .map(clone);
    },
  };
}

function fixture({ initialClock = "2026-08-31T20:00:00.000Z" } = {}) {
  let clock = new Date(initialClock);
  let idIndex = 0;
  const ids = [WEEKLY_RULE, MESSAGE_A, MESSAGE_B];
  const provider = {
    calls: [],
    async send(input) {
      this.calls.push(clone(input));
      return {
        provider: "resend",
        providerMessageId: `resend-${this.calls.length}`,
        idempotencyKey: `korlix-agent-email/${input.message.id}`,
      };
    },
  };
  const store = memoryStore();
  store.state.settings.set(`${OWNER}:${AGENT}`, {
    id: crypto.randomUUID(),
    user_id: OWNER,
    agent_id: AGENT,
    enabled: true,
    operating_mode: "autopilot",
    emergency_paused: false,
    daily_send_cap: 20,
    timezone: "America/New_York",
    physical_address: "100 KORLIX Way",
    metadata: {
      sendWindowStart: "00:00",
      sendWindowEnd: "23:59",
      marketingEnabled: false,
    },
  });
  store.state.recipients.set(RECIPIENT, {
    id: RECIPIENT,
    user_id: OWNER,
    agent_id: AGENT,
    email: "thomas@example.com",
    display_name: "Thomas Bello",
    consent_status: "transactional_only",
    active: true,
  });
  const service = createKorlixAgentEmailDeliveryService({
    environment: environment(),
    store,
    loadAgentProfile: async () => profile(),
    provider,
    now: () => new Date(clock),
    randomUUID: () => ids[idIndex++] ?? crypto.randomUUID(),
  });

  return {
    service,
    store,
    provider,
    setClock(value) {
      clock = new Date(value);
    },
  };
}

const tests = [];
function test(name, callback) {
  tests.push({ name, callback });
}

async function expectCode(callback, code) {
  await assert.rejects(callback, (error) => error?.code === code);
}

test("weekly timezone calculation preserves Thursday 7:00 AM Eastern", async () => {
  const next = korlixAgentEmailNextWeeklyRunAt({
    after: "2026-08-31T20:00:00.000Z",
    timeZone: "America/New_York",
    localTime: "07:00",
    days: [4],
  });
  assert.equal(next, "2026-09-03T11:00:00.000Z");
  assert.deepEqual(
    korlixAgentEmailScheduleZonedParts(next, "America/New_York"),
    {
      year: 2026,
      month: 9,
      day: 3,
      hour: 7,
      minute: 0,
      second: 0,
      weekday: 4,
    },
  );
});

test("weekly rule stores server-calculated schedule fields", async () => {
  const { service } = fixture();
  const created = await service.createRule({
    userId: OWNER,
    agentId: AGENT,
    body: {
      confirmed: true,
      preapproved: true,
      confirmationNonce: "weekly-rule-confirmation-123",
      name: "Thursday staff meeting reminder",
      recipientIds: [RECIPIENT],
      subjectTemplate: "Friday staff meeting reminder",
      textTemplate: "Reminder: the staff meeting is Friday at 7:00 AM.",
      sendMode: "autopilot",
      enabled: true,
      scheduleType: "weekly",
      scheduleTimezone: "America/New_York",
      scheduleLocalTime: "07:00",
      scheduleDays: [4],
    },
  });
  assert.equal(created.rule.scheduleType, "weekly");
  assert.equal(created.rule.scheduleTimezone, "America/New_York");
  assert.equal(created.rule.scheduleLocalTime, "07:00");
  assert.deepEqual(created.rule.scheduleDays, [4]);
  assert.equal(created.rule.nextRunAt, "2026-09-03T11:00:00.000Z");
  assert.equal(created.rule.triggerKey, "schedule.k134b");
});

test("due weekly schedule sends once and advances to the following week", async () => {
  const fixtureValue = fixture();
  const { service, store, provider } = fixtureValue;
  await service.createRule({
    userId: OWNER,
    agentId: AGENT,
    body: {
      confirmed: true,
      preapproved: true,
      confirmationNonce: "weekly-rule-confirmation-123",
      name: "Thursday staff meeting reminder",
      recipientIds: [RECIPIENT],
      subjectTemplate: "Friday staff meeting reminder",
      textTemplate: "Reminder: the staff meeting is Friday at 7:00 AM.",
      sendMode: "autopilot",
      enabled: true,
      scheduleType: "weekly",
      scheduleTimezone: "America/New_York",
      scheduleLocalTime: "07:00",
      scheduleDays: [4],
    },
  });
  fixtureValue.setClock("2026-09-03T11:00:00.000Z");
  const result = await service.runScheduledAutopilot({ body: {} });
  assert.equal(result.matchedRuleCount, 1);
  assert.equal(result.sentCount, 1);
  assert.equal(provider.calls.length, 1);
  assert.equal(provider.calls[0].message.to_email, "thomas@example.com");
  assert.equal(provider.calls[0].message.scheduled_at, "2026-09-03T11:00:00.000Z");
  const rule = store.state.rules.get(WEEKLY_RULE);
  assert.equal(rule.last_run_at, "2026-09-03T11:00:00.000Z");
  assert.equal(rule.next_run_at, "2026-09-10T11:00:00.000Z");
  assert.equal(rule.enabled, true);

  const replay = await service.runScheduledAutopilot({ body: {} });
  assert.equal(replay.matchedRuleCount, 0);
  assert.equal(provider.calls.length, 1);
});

test("one-time schedule disables itself after the provider accepts it", async () => {
  const fixtureValue = fixture();
  const { service, store, provider } = fixtureValue;
  const created = await service.createRule({
    userId: OWNER,
    agentId: AGENT,
    body: {
      confirmed: true,
      preapproved: true,
      confirmationNonce: "one-time-confirmation-123",
      name: "One-time call request",
      recipientIds: [RECIPIENT],
      subjectTemplate: "Please call Ricardo",
      textTemplate: "Please call Ricardo as soon as you receive this message.",
      sendMode: "autopilot",
      enabled: true,
      scheduleType: "once",
      scheduledFor: "2026-09-01T13:00:00.000Z",
      scheduleTimezone: "America/New_York",
    },
  });
  fixtureValue.setClock("2026-09-01T13:00:00.000Z");
  const result = await service.runScheduledAutopilot({ body: {} });
  assert.equal(result.sentCount, 1);
  assert.equal(provider.calls.length, 1);
  const rule = store.state.rules.get(created.rule.id);
  assert.equal(rule.enabled, false);
  assert.equal(rule.next_run_at, null);
  assert.equal(rule.completed_at, "2026-09-01T13:00:00.000Z");
});

test("past one-time schedules fail closed", async () => {
  const { service } = fixture();
  await expectCode(
    () => service.createRule({
      userId: OWNER,
      agentId: AGENT,
      body: {
        confirmed: true,
        preapproved: true,
        confirmationNonce: "past-time-confirmation-123",
        name: "Past schedule",
        recipientIds: [RECIPIENT],
        subjectTemplate: "Past",
        textTemplate: "Past",
        sendMode: "autopilot",
        enabled: true,
        scheduleType: "once",
        scheduledFor: "2026-08-30T13:00:00.000Z",
      },
    }),
    "agent_email_schedule_time_must_be_future",
  );
});

test("authenticated rule deletion is soft and removes the rule from active lists", async () => {
  const { service, store } = fixture();
  const created = await service.createRule({
    userId: OWNER,
    agentId: AGENT,
    body: {
      confirmed: true,
      preapproved: true,
      confirmationNonce: "delete-rule-confirmation-123",
      name: "Rule to delete",
      recipientIds: [RECIPIENT],
      subjectTemplate: "Delete test",
      textTemplate: "Delete test",
      sendMode: "autopilot",
      enabled: true,
      scheduleType: "weekly",
      scheduleTimezone: "America/New_York",
      scheduleLocalTime: "08:00",
      scheduleDays: [1],
    },
  });
  const deleted = await service.deleteRule({
    userId: OWNER,
    agentId: AGENT,
    ruleId: created.rule.id,
    body: { confirmed: true },
  });
  assert.equal(deleted.deleted, true);
  assert.ok(deleted.rule.deletedAt);
  assert.equal(store.state.rules.get(created.rule.id).enabled, false);
  assert.equal((await service.listRules({ userId: OWNER, agentId: AGENT })).rules.length, 0);
});

test("schedule runtime fields cannot be supplied by the client", async () => {
  const { service } = fixture();
  await expectCode(
    () => service.createRule({
      userId: OWNER,
      agentId: AGENT,
      body: {
        confirmed: true,
        preapproved: true,
        confirmationNonce: "runtime-field-confirmation-123",
        name: "Unsafe next run",
        recipientIds: [RECIPIENT],
        subjectTemplate: "Unsafe",
        textTemplate: "Unsafe",
        sendMode: "autopilot",
        enabled: true,
        scheduleType: "weekly",
        scheduleTimezone: "America/New_York",
        scheduleLocalTime: "08:00",
        scheduleDays: [1],
        nextRunAt: "2030-01-01T00:00:00.000Z",
      },
    }),
    "agent_email_rule_schedule_runtime_field_prohibited",
  );
});

test("K134B migration and route contracts are present", async () => {
  const migration = fs.readFileSync(
    new URL(
      "../supabase/migrations/202609010001_agent_email_schedules_k134b.sql",
      import.meta.url,
    ),
    "utf8",
  );
  assert.match(migration, /schedule_type text not null default 'event'/);
  assert.match(migration, /schedule_timezone text not null default 'UTC'/);
  assert.match(migration, /schedule_local_time text/);
  assert.match(migration, /next_run_at timestamptz/);
  assert.match(migration, /deleted_at timestamptz/);
  assert.match(KORLIX_AGENT_EMAIL_DELIVERY_ROUTES.scheduledRun, /scheduled\/run$/);
  assert.match(KORLIX_AGENT_EMAIL_DELIVERY_ROUTES.rule, /rules\/:ruleId$/);
});

let passed = 0;
for (const entry of tests) {
  await entry.callback();
  passed += 1;
  console.log(`PASS ${passed}: ${entry.name}`);
}

assert.equal(passed, 8);
console.log(`KORLIX_AGENT_EMAIL_SCHEDULE_K134B_TEST_COUNT=${passed}`);
console.log("KORLIX_AGENT_EMAIL_SCHEDULE_K134B_TEST_PASS=true");
