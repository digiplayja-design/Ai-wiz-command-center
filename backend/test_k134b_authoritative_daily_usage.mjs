import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import {
  createKorlixAgentEmailDeliveryService,
} from "./korlix_agent_email_delivery.mjs";

const OWNER =
  "11111111-1111-4111-8111-111111111111";

const AGENT =
  "custom_nova";

const NOW =
  "2026-09-03T15:30:00.000Z";

const routesSource =
  fs.readFileSync(
    new URL(
      "./korlix_agent_email_routes.mjs",
      import.meta.url,
    ),
    "utf8",
  );

const deliverySource =
  fs.readFileSync(
    new URL(
      "./korlix_agent_email_delivery.mjs",
      import.meta.url,
    ),
    "utf8",
  );

test(
  "backend publishes authoritative daily-usage markers",
  () => {
    assert.match(
      routesSource,
      /K134B_AUTHORITATIVE_DAILY_USAGE_V1_STORE_BEGIN/,
    );

    assert.match(
      routesSource,
      /async countSendingSince\(/,
    );

    assert.match(
      deliverySource,
      /K134B_AUTHORITATIVE_DAILY_USAGE_V1_TIME_BEGIN/,
    );

    assert.match(
      deliverySource,
      /K134B_AUTHORITATIVE_DAILY_USAGE_V1_STATUS_BEGIN/,
    );

    assert.match(
      deliverySource,
      /source:\s*"agent_email_messages"/,
    );
  },
);

test(
  "delivery status reports New York daily usage independently of historical events",
  async () => {
    const calls = [];

    const store = {
      async getSettings(
        userId,
        agentId,
      ) {
        assert.equal(
          userId,
          OWNER,
        );

        assert.equal(
          agentId,
          AGENT,
        );

        return {
          id:
            "77777777-7777-4777-8777-777777777777",

          user_id:
            OWNER,

          agent_id:
            AGENT,

          provider:
            "resend",

          enabled:
            true,

          operating_mode:
            "autopilot",

          emergency_paused:
            false,

          daily_send_cap:
            100,

          from_name:
            "Nova",

          from_email:
            "nova@korlixdeveloper.com",

          reply_to_email:
            "reply@korlixdeveloper.com",

          physical_address:
            "100 KORLIX Way",

          timezone:
            "America/New_York",

          metadata: {
            sendWindowStart:
              "00:00",

            sendWindowEnd:
              "23:59",

            marketingEnabled:
              false,
          },
        };
      },

      async countSentSince(
        userId,
        agentId,
        since,
      ) {
        calls.push(
          [
            "sent",
            userId,
            agentId,
            since,
          ],
        );

        return 1;
      },

      async countSendingSince(
        userId,
        agentId,
        since,
      ) {
        calls.push(
          [
            "sending",
            userId,
            agentId,
            since,
          ],
        );

        return 0;
      },
    };

    const service =
      createKorlixAgentEmailDeliveryService({
        environment: {
          KORLIX_VAPI_NOVA_OWNER_UID:
            OWNER,

          KORLIX_VAPI_NOVA_AGENT_ID:
            AGENT,

          KORLIX_VAPI_NOVA_ASSISTANT_ID:
            "assistant-nova",

          KORLIX_AGENT_EMAIL_ENABLED:
            "true",

          KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE:
            "false",

          KORLIX_AGENT_EMAIL_SEND_ENABLED:
            "true",

          KORLIX_AGENT_EMAIL_AUTOPILOT_ENABLED:
            "true",

          KORLIX_AGENT_EMAIL_AUTOPILOT_SECRET:
            "test-only-autopilot-secret",

          KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_ENABLED:
            "false",

          KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_INTERVAL_MINUTES:
            "1",

          KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_TRIGGER_KEY:
            "scheduler.scheduled_email",

          KORLIX_AGENT_EMAIL_FROM:
            "Nova <nova@korlixdeveloper.com>",

          KORLIX_AGENT_EMAIL_MAX_DAILY_CAP:
            "100",

          RESEND_API_KEY:
            "test-only-resend-key",
        },

        store,

        provider: {
          async send() {
            throw new Error(
              "No email send is permitted in this test.",
            );
          },
        },

        loadAgentProfile:
          async () => ({
            id:
              AGENT,

            agent_id:
              AGENT,

            name:
              "Nova",

            isCustom:
              true,

            active:
              true,

            toolIds: [
              "agent_email",
            ],
          }),

        now:
          () =>
            new Date(
              NOW,
            ),
      });

    const result =
      await service.getDeliveryStatus({
        userId:
          OWNER,

        agentId:
          AGENT,
      });

    assert.equal(
      result.dailyUsage.authoritative,
      true,
    );

    assert.equal(
      result.dailyUsage.source,
      "agent_email_messages",
    );

    assert.equal(
      result.dailyUsage.timezone,
      "America/New_York",
    );

    assert.equal(
      result.dailyUsage.windowStartAt,
      "2026-09-03T04:00:00.000Z",
    );

    assert.equal(
      result.dailyUsage.windowEndAt,
      "2026-09-04T04:00:00.000Z",
    );

    assert.equal(
      result.dailySendCap,
      100,
    );

    assert.equal(
      result.sentToday,
      1,
    );

    assert.equal(
      result.sendingToday,
      0,
    );

    assert.equal(
      result.usedToday,
      1,
    );

    assert.equal(
      result.remainingToday,
      99,
    );

    assert.deepEqual(
      calls,
      [
        [
          "sent",
          OWNER,
          AGENT,
          "2026-09-03T04:00:00.000Z",
        ],
        [
          "sending",
          OWNER,
          AGENT,
          "2026-09-03T04:00:00.000Z",
        ],
      ],
    );
  },
);
