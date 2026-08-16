import assert from "node:assert/strict";

import {
  KORLIX_AGENT_EMAIL_TOOL_ID,
  korlixAgentEmailAddress,
  korlixAgentEmailDraftInput,
  korlixAgentEmailIdempotencyKey,
  korlixAgentEmailIsExistingNova,
  korlixAgentEmailRecipientInput,
  korlixAgentEmailSettingsInput,
  korlixAgentEmailStatus,
} from "./korlix_agent_email.mjs";

const OWNER = "11111111-1111-4111-8111-111111111111";
const RECIPIENT = "22222222-2222-4222-8222-222222222222";

function environment(overrides = {}) {
  return {
    KORLIX_VAPI_NOVA_OWNER_UID: OWNER,
    KORLIX_VAPI_NOVA_AGENT_ID: "custom_nova",
    KORLIX_VAPI_NOVA_ASSISTANT_ID: "vapi-nova-assistant",
    KORLIX_AGENT_EMAIL_ENABLED: "false",
    KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE: "true",
    KORLIX_AGENT_EMAIL_FROM: "Nova <nova@korlixdeveloper.com>",
    RESEND_API_KEY: "test-only-key",
    ...overrides,
  };
}

let passed = 0;
function test(name, callback) {
  callback();
  passed += 1;
  console.log(`PASS ${passed}: ${name}`);
}

test("exact Vapi owner and Agent Hub ID identify the existing Nova", () => {
  assert.equal(
    korlixAgentEmailIsExistingNova({
      environment: environment(),
      userId: OWNER,
      agentId: "custom_nova",
    }),
    true,
  );
  assert.equal(
    korlixAgentEmailIsExistingNova({
      environment: environment(),
      userId: OWNER,
      agentId: "custom_other",
    }),
    false,
  );
});

test("Agent Email defaults to disabled, paused, and unable to send", () => {
  const status = korlixAgentEmailStatus({
    environment: environment(),
    userId: OWNER,
    agentId: "custom_nova",
    toolIds: [KORLIX_AGENT_EMAIL_TOOL_ID],
    settings: { enabled: true, paused: false, mode: "approval_required" },
  });
  assert.equal(status.sameNova, true);
  assert.equal(status.featureEnabled, false);
  assert.equal(status.emergencyPaused, true);
  assert.equal(status.canSend, false);
});

test("sending requires exact Nova, tool authorization, settings, and provider", () => {
  const status = korlixAgentEmailStatus({
    environment: environment({
      KORLIX_AGENT_EMAIL_ENABLED: "true",
      KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE: "false",
    }),
    userId: OWNER,
    agentId: "custom_nova",
    toolIds: [KORLIX_AGENT_EMAIL_TOOL_ID],
    settings: { enabled: true, paused: false, mode: "approval_required" },
  });
  assert.equal(status.canDraft, true);
  assert.equal(status.canSend, true);
  assert.equal(status.canAutopilot, false);
});

test("settings require confirmation and cap daily sending", () => {
  assert.throws(
    () => korlixAgentEmailSettingsInput({ mode: "autopilot" }),
    (error) => error?.code === "agent_email_settings_confirmation_required",
  );
  const settings = korlixAgentEmailSettingsInput(
    {
      confirmed: true,
      enabled: true,
      paused: false,
      mode: "draft_only",
      dailySendCap: 999,
    },
    environment({ KORLIX_AGENT_EMAIL_MAX_DAILY_CAP: "12" }),
  );
  assert.equal(settings.mode, "draft_only");
  assert.equal(settings.dailySendCap, 12);
  assert.equal(settings.maxFollowUps, 0);
});

test("recipient addresses normalize and scraped sources fail closed", () => {
  assert.equal(korlixAgentEmailAddress(" User@Example.COM "), "user@example.com");
  assert.throws(
    () => korlixAgentEmailRecipientInput({
      confirmed: true,
      email: "user@example.com",
      approvalSource: "scraped",
    }),
    (error) => error?.code === "agent_email_recipient_source_prohibited",
  );
});

test("marketing recipients require recorded consent", () => {
  assert.throws(
    () => korlixAgentEmailRecipientInput({
      confirmed: true,
      email: "user@example.com",
      consentScope: "marketing",
    }),
    (error) => error?.code === "agent_email_marketing_consent_required",
  );
  const recipient = korlixAgentEmailRecipientInput({
    confirmed: true,
    email: "user@example.com",
    consentScope: "marketing",
    consentAt: "2026-08-12T12:00:00Z",
  });
  assert.equal(recipient.consentScope, "marketing");
});

test("drafts require approved recipient IDs and idempotency", () => {
  const draft = korlixAgentEmailDraftInput({
    recipientId: RECIPIENT,
    subject: " Follow-up ",
    body: "Thank you for speaking with Nova.",
    idempotencyKey: "message-123",
  });
  assert.equal(draft.subject, "Follow-up");
  assert.equal(draft.idempotencyKey, "message-123");
  assert.throws(
    () => korlixAgentEmailDraftInput({
      recipientId: RECIPIENT,
      subject: "Follow-up",
      body: "Hello",
    }),
    (error) => error?.code === "agent_email_idempotency_key_required",
  );
});

test("marketing drafts require unsubscribe and physical-address controls", () => {
  assert.throws(
    () => korlixAgentEmailDraftInput({
      recipientId: RECIPIENT,
      subject: "Offer",
      body: "Hello",
      idempotencyKey: "marketing-1",
      marketing: true,
    }),
    (error) => error?.code === "agent_email_marketing_footer_required",
  );
});

test("idempotency keys bind user, existing Nova, and message", () => {
  assert.equal(
    korlixAgentEmailIdempotencyKey({
      userId: OWNER,
      agentId: "custom_nova",
      messageId: "message-7",
    }),
    `korlix-agent-email:${OWNER}:custom_nova:message-7`,
  );
});

assert.equal(passed, 9);
console.log(`KORLIX_AGENT_EMAIL_POLICY_TEST_COUNT=${passed}`);
console.log("KORLIX_AGENT_EMAIL_POLICY_TEST_PASS=true");
