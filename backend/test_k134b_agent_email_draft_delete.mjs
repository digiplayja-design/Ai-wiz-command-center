import assert from "node:assert/strict";
import test from "node:test";

import {
  KORLIX_AGENT_EMAIL_DRAFT_ROUTES,
  createKorlixAgentEmailDraftService,
} from "./korlix_agent_email_routes.mjs";

const OWNER =
  "11111111-1111-4111-8111-111111111111";
const AGENT =
  "custom_nova_test";
const MESSAGE =
  "22222222-2222-4222-8222-222222222222";
const RECIPIENT =
  "33333333-3333-4333-8333-333333333333";
const RULE =
  "44444444-4444-4444-8444-444444444444";

function environment() {
  return {
    KORLIX_VAPI_NOVA_OWNER_UID:
      OWNER,

    KORLIX_VAPI_NOVA_AGENT_ID:
      AGENT,

    KORLIX_VAPI_NOVA_ASSISTANT_ID:
      "assistant-nova-test",

    KORLIX_AGENT_EMAIL_ENABLED:
      "true",

    KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE:
      "false",

    KORLIX_AGENT_EMAIL_SEND_ENABLED:
      "true",

    KORLIX_AGENT_EMAIL_AUTOPILOT_ENABLED:
      "true",

    KORLIX_AGENT_EMAIL_FROM:
      "Nova <nova@example.com>",

    RESEND_API_KEY:
      "test-only",
  };
}

function message(
  status = "draft",
  overrides = {},
) {
  return {
    id:
      MESSAGE,

    user_id:
      OWNER,

    agent_id:
      AGENT,

    recipient_id:
      RECIPIENT,

    rule_id:
      null,

    to_email:
      "recipient@example.com",

    subject:
      "Delete test",

    text_body:
      "Never send this test message.",

    html_body:
      "",

    message_kind:
      "transactional",

    status,

    authorization_type:
      status === "approved"
        ? "one_time_confirmation"
        : "none",

    authorized_at:
      status === "approved"
        ? "2026-09-03T12:00:00.000Z"
        : null,

    authorized_by:
      status === "approved"
        ? OWNER
        : null,

    confirmation_nonce_hash:
      status === "approved"
        ? "abc"
        : null,

    scheduled_at:
      "2026-09-03T12:30:00.000Z",

    physical_address_snapshot:
      "",

    unsubscribe_url_snapshot:
      "",

    idempotency_key:
      "draft-delete-test",

    provider:
      "resend",

    provider_message_id:
      null,

    last_attempt_at:
      null,

    attempt_count:
      0,

    sent_at:
      null,

    failure_code:
      null,

    failure_message:
      null,

    metadata:
      {},

    created_at:
      "2026-09-03T12:00:00.000Z",

    updated_at:
      "2026-09-03T12:00:00.000Z",

    ...overrides,
  };
}

function harness(
  initial,
  {
    rule = null,
    raceTo = null,
  } = {},
) {
  let current =
    structuredClone(initial);

  const events = [];
  const patches = [];

  const store = {
    client: {},

    async getMessage(
      userId,
      agentId,
      messageId,
    ) {
      assert.equal(
        userId,
        OWNER,
      );

      assert.equal(
        agentId,
        AGENT,
      );

      assert.equal(
        messageId,
        MESSAGE,
      );

      return structuredClone(
        current,
      );
    },

    async cancelMessage(
      userId,
      agentId,
      messageId,
      patch,
    ) {
      assert.equal(
        userId,
        OWNER,
      );

      assert.equal(
        agentId,
        AGENT,
      );

      assert.equal(
        messageId,
        MESSAGE,
      );

      patches.push(
        structuredClone(
          patch,
        ),
      );

      if (raceTo) {
        current = {
          ...current,
          status:
            raceTo,
        };

        return null;
      }

      current = {
        ...current,
        ...structuredClone(
          patch,
        ),
      };

      return structuredClone(
        current,
      );
    },

    async insertEvent(row) {
      events.push(
        structuredClone(
          row,
        ),
      );

      return structuredClone(
        row,
      );
    },

    async getRule(
      userId,
      agentId,
      ruleId,
    ) {
      assert.equal(
        userId,
        OWNER,
      );

      assert.equal(
        agentId,
        AGENT,
      );

      assert.equal(
        ruleId,
        RULE,
      );

      return rule
        ? structuredClone(
            rule,
          )
        : null;
    },

    async listMessages() {
      return [
        structuredClone(
          current,
        ),
      ];
    },
  };

  const service =
    createKorlixAgentEmailDraftService({
      environment:
        environment(),

      store,

      loadAgentProfile:
        async () => ({
          id:
            AGENT,

          agent_id:
            AGENT,

          isCustom:
            true,

          active:
            true,

          toolIds:
            [
              "agent_email",
            ],
        }),

      now:
        () =>
          new Date(
            "2026-09-03T12:10:00.000Z",
          ),
    });

  return {
    service,
    events,
    patches,

    current:
      () =>
        structuredClone(
          current,
        ),
  };
}

test(
  "DELETE route uses the authenticated individual-draft path",
  () => {
    assert.equal(
      KORLIX_AGENT_EMAIL_DRAFT_ROUTES
        .deleteDraft,

      "/api/live-convo/agents/:agentId/email/drafts/:messageId",
    );
  },
);

test(
  "ordinary unsent draft is soft-deleted, authorization revoked, and audited",
  async () => {
    const h = harness(
      message("draft"),
    );

    const result =
      await h.service.deleteDraft({
        userId:
          OWNER,

        agentId:
          AGENT,

        messageId:
          MESSAGE,

        body: {
          confirmed:
            true,
        },
      });

    assert.equal(
      result.deleted,
      true,
    );

    assert.equal(
      result.softDeleted,
      true,
    );

    assert.equal(
      result.sent,
      false,
    );

    assert.equal(
      result.draft.status,
      "cancelled",
    );

    assert.equal(
      result.draft.canDelete,
      false,
    );

    assert.equal(
      h.current()
        .authorization_type,
      "none",
    );

    assert.equal(
      h.current()
        .authorized_at,
      null,
    );

    assert.equal(
      h.current()
        .authorized_by,
      null,
    );

    assert.equal(
      h.current()
        .scheduled_at,
      null,
    );

    assert.equal(
      h.events.length,
      1,
    );

    assert.equal(
      h.events[0]
        .event_type,
      "draft_deleted",
    );

    assert.equal(
      h.events[0]
        .details.sent,
      false,
    );

    assert.equal(
      h.patches.length,
      1,
    );
  },
);

test(
  "approved and failed drafts require the exact typed phrase",
  async () => {
    for (
      const status
      of [
        "approved",
        "failed",
      ]
    ) {
      const h = harness(
        message(
          status,
        ),
      );

      await assert.rejects(
        h.service.deleteDraft({
          userId:
            OWNER,

          agentId:
            AGENT,

          messageId:
            MESSAGE,

          body: {
            confirmed:
              true,
          },
        }),

        (error) =>
          error?.code ===
          "agent_email_draft_delete_phrase_required",
      );

      assert.equal(
        h.patches.length,
        0,
      );

      const result =
        await h.service.deleteDraft({
          userId:
            OWNER,

          agentId:
            AGENT,

          messageId:
            MESSAGE,

          body: {
            confirmed:
              true,

            confirmationPhrase:
              "DELETE DRAFT",
          },
        });

      assert.equal(
        result.deleted,
        true,
      );

      assert.equal(
        result.draft.status,
        "cancelled",
      );
    }
  },
);

test(
  "sent, sending, ambiguous, and provider-accepted records cannot be deleted",
  async () => {
    const blocked = [
      message(
        "sending",
      ),

      message(
        "sent",
        {
          sent_at:
            "2026-09-03T12:05:00.000Z",
        },
      ),

      message(
        "failed",
        {
          provider_message_id:
            "provider-1",
        },
      ),

      message(
        "failed",
        {
          metadata: {
            lastFailureAmbiguous:
              true,
          },
        },
      ),
    ];

    for (
      const row
      of blocked
    ) {
      const h = harness(
        row,
      );

      await assert.rejects(
        h.service.deleteDraft({
          userId:
            OWNER,

          agentId:
            AGENT,

          messageId:
            MESSAGE,

          body: {
            confirmed:
              true,

            confirmationPhrase:
              "DELETE DRAFT",
          },
        }),

        (error) =>
          error?.code ===
          "agent_email_draft_not_deletable",
      );

      assert.equal(
        h.patches.length,
        0,
      );
    }
  },
);

test(
  "draft linked to an active schedule must be paused or completed first",
  async () => {
    const h = harness(
      message(
        "approved",
        {
          rule_id:
            RULE,
        },
      ),

      {
        rule: {
          id:
            RULE,

          enabled:
            true,

          completed_at:
            null,

          deleted_at:
            null,
        },
      },
    );

    await assert.rejects(
      h.service.deleteDraft({
        userId:
          OWNER,

        agentId:
          AGENT,

        messageId:
          MESSAGE,

        body: {
          confirmed:
            true,

          confirmationPhrase:
            "DELETE DRAFT",
        },
      }),

      (error) =>
        error?.code ===
        "agent_email_draft_schedule_active",
    );

    assert.equal(
      h.patches.length,
      0,
    );
  },
);

test(
  "atomic status guard prevents deletion if send starts during confirmation",
  async () => {
    const h = harness(
      message(
        "approved",
      ),

      {
        raceTo:
          "sending",
      },
    );

    await assert.rejects(
      h.service.deleteDraft({
        userId:
          OWNER,

        agentId:
          AGENT,

        messageId:
          MESSAGE,

        body: {
          confirmed:
            true,

          confirmationPhrase:
            "DELETE DRAFT",
        },
      }),

      (error) =>
        error?.code ===
        "agent_email_draft_delete_raced_with_send",
    );

    assert.equal(
      h.current()
        .status,
      "sending",
    );

    assert.equal(
      h.events.length,
      0,
    );
  },
);

test(
  "cancelled drafts are excluded from the active Draft Queue",
  async () => {
    const h = harness(
      message(
        "cancelled",
      ),
    );

    const result =
      await h.service.listDrafts({
        userId:
          OWNER,

        agentId:
          AGENT,

        limit:
          100,
      });

    assert.deepEqual(
      result.drafts,
      [],
    );
  },
);
