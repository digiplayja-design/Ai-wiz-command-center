import assert from "node:assert/strict";
import fs from "node:fs";

import {
  createKorlixAgentEmailAutopilotScheduler,
  korlixAgentEmailAutopilotSchedulerConfiguration,
} from "./korlix_agent_email_scheduler.mjs";

const OWNER = "11111111-1111-4111-8111-111111111111";
const AGENT = "custom_nova";
const NOW = "2026-08-21T12:07:30.000Z";

function environment(overrides = {}) {
  return {
    KORLIX_VAPI_NOVA_OWNER_UID: OWNER,
    KORLIX_VAPI_NOVA_AGENT_ID: AGENT,
    KORLIX_VAPI_NOVA_ASSISTANT_ID: "assistant-nova",
    KORLIX_AGENT_EMAIL_ENABLED: "true",
    KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE: "false",
    KORLIX_AGENT_EMAIL_SEND_ENABLED: "true",
    KORLIX_AGENT_EMAIL_AUTOPILOT_ENABLED: "true",
    KORLIX_AGENT_EMAIL_AUTOPILOT_SECRET: "scheduler-secret-never-log",
    KORLIX_AGENT_EMAIL_FROM: "Nova <nova@korlixdeveloper.com>",
    KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_ENABLED: "true",
    KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_TRIGGER_KEY:
      "scheduler.followup",
    KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_INTERVAL_MINUTES: "15",
    KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_VARIABLES_JSON:
      JSON.stringify({ campaign_name: "Approved follow-up" }),
    RESEND_API_KEY: "test-only-resend-key",
    ...overrides,
  };
}

function timerHarness() {
  const scheduled = [];
  const cleared = [];
  let nextId = 1;

  return {
    scheduled,
    cleared,
    setTimeoutImpl(callback, delay) {
      const handle = {
        id: nextId++,
        callback,
        delay,
        unrefCalled: false,
        unref() {
          this.unrefCalled = true;
        },
      };
      scheduled.push(handle);
      return handle;
    },
    clearTimeoutImpl(handle) {
      cleared.push(handle);
    },
  };
}

function loggerHarness() {
  const entries = [];
  return {
    entries,
    info(event, details) {
      entries.push({ level: "info", event, details });
    },
    warn(event, details) {
      entries.push({ level: "warn", event, details });
    },
    error(event, details) {
      entries.push({ level: "error", event, details });
    },
  };
}

const tests = [];
function test(name, callback) {
  tests.push({ name, callback });
}

test("scheduler is disabled by default and exposes no configured trigger", async () => {
  const config = korlixAgentEmailAutopilotSchedulerConfiguration({});
  assert.equal(config.enabled, false);
  assert.equal(config.configured, false);
  assert.equal(config.triggerKey, null);
  assert.equal(config.intervalMinutes, null);
  assert.deepEqual(config.variableKeys, []);
  assert.deepEqual(config.errors, []);
});

test("enabled scheduler fails closed when its required configuration is absent", async () => {
  const config = korlixAgentEmailAutopilotSchedulerConfiguration({
    KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_ENABLED: "true",
  });
  assert.equal(config.enabled, true);
  assert.equal(config.configured, false);
  assert.ok(config.errors.includes("scheduler_trigger_key_required"));
  assert.ok(config.errors.includes("scheduler_interval_minutes_invalid"));
  assert.ok(config.errors.includes("agent_email_feature_disabled"));
  assert.ok(config.errors.includes("agent_email_emergency_paused"));
  assert.ok(config.errors.includes("resend_provider_not_configured"));
  assert.ok(config.errors.includes("autopilot_secret_not_configured"));
});

test("valid scheduler configuration is complete without exposing secrets or values", async () => {
  const env = environment();
  const config = korlixAgentEmailAutopilotSchedulerConfiguration(env);
  assert.equal(config.enabled, true);
  assert.equal(config.configured, true);
  assert.equal(config.triggerKey, "scheduler.followup");
  assert.equal(config.intervalMinutes, 15);
  assert.equal(config.intervalMilliseconds, 900000);
  assert.deepEqual(config.variableKeys, ["campaign_name"]);
  assert.deepEqual(config.errors, []);
  const publicText = JSON.stringify({
    enabled: config.enabled,
    configured: config.configured,
    triggerKey: config.triggerKey,
    intervalMinutes: config.intervalMinutes,
    variableKeys: config.variableKeys,
    errors: config.errors,
  });
  assert.doesNotMatch(publicText, /scheduler-secret-never-log/);
  assert.doesNotMatch(publicText, /Approved follow-up/);
});

test("scheduler variables reject invalid JSON and invalid variable keys", async () => {
  const invalidJson = korlixAgentEmailAutopilotSchedulerConfiguration(
    environment({
      KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_VARIABLES_JSON: "{not-json",
    }),
  );
  assert.equal(invalidJson.configured, false);
  assert.ok(invalidJson.errors.includes("scheduler_variables_json_invalid"));

  const invalidKey = korlixAgentEmailAutopilotSchedulerConfiguration(
    environment({
      KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_VARIABLES_JSON:
        JSON.stringify({ "bad-key": "value" }),
    }),
  );
  assert.equal(invalidKey.configured, false);
  assert.ok(invalidKey.errors.includes("scheduler_variable_key_invalid"));
});

test("disabled scheduler start creates no timer and invokes no Autopilot run", async () => {
  const timers = timerHarness();
  let runs = 0;
  const scheduler = createKorlixAgentEmailAutopilotScheduler({
    environment: environment({
      KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_ENABLED: "false",
    }),
    runAutopilot: async () => {
      runs += 1;
      return {};
    },
    now: () => new Date(NOW),
    ...timers,
    logger: loggerHarness(),
  });
  const status = scheduler.start();
  assert.equal(status.configured, false);
  assert.equal(status.started, false);
  assert.equal(timers.scheduled.length, 0);
  assert.equal(runs, 0);
});

test("scheduler start aligns the first tick and never sends during installation", async () => {
  const timers = timerHarness();
  let runs = 0;
  const scheduler = createKorlixAgentEmailAutopilotScheduler({
    environment: environment(),
    runAutopilot: async () => {
      runs += 1;
      return {};
    },
    now: () => new Date(NOW),
    ...timers,
    logger: loggerHarness(),
  });
  const status = scheduler.start();
  assert.equal(status.configured, true);
  assert.equal(status.started, true);
  assert.equal(status.nextRunAt, "2026-08-21T12:15:00.000Z");
  assert.equal(timers.scheduled.length, 1);
  assert.equal(timers.scheduled[0].delay, 450000);
  assert.equal(timers.scheduled[0].unrefCalled, true);
  assert.equal(runs, 0);
});

test("due tick invokes Autopilot with deterministic slot identity and protected variables", async () => {
  const timers = timerHarness();
  const requests = [];
  let clock = new Date(NOW);
  const scheduler = createKorlixAgentEmailAutopilotScheduler({
    environment: environment(),
    runAutopilot: async (request) => {
      requests.push(request);
      return {
        matchedRuleCount: 2,
        attempted: 2,
        sentCount: 1,
        replayedCount: 1,
      };
    },
    now: () => new Date(clock),
    ...timers,
    logger: loggerHarness(),
  });
  scheduler.start();
  clock = new Date("2026-08-21T12:15:00.000Z");
  await timers.scheduled[0].callback();

  assert.equal(requests.length, 1);
  assert.deepEqual(requests[0], {
    body: {
      triggerKey: "scheduler.followup",
      eventId:
        "korlix-agent-email-scheduler:scheduler.followup:2026-08-21T12:15:00.000Z",
      variables: {
        campaign_name: "Approved follow-up",
        scheduler_trigger_key: "scheduler.followup",
        scheduler_slot_start: "2026-08-21T12:15:00.000Z",
        scheduler_interval_minutes: "15",
      },
    },
  });
  const status = scheduler.status();
  assert.equal(status.runCount, 1);
  assert.deepEqual(status.lastResult, {
    matchedRuleCount: 2,
    attempted: 2,
    sentCount: 1,
    replayedCount: 1,
  });
  assert.equal(status.lastErrorCode, null);
  assert.equal(status.nextRunAt, "2026-08-21T12:30:00.000Z");
});

test("same scheduler slot is idempotently skipped", async () => {
  const timers = timerHarness();
  let runs = 0;
  const scheduler = createKorlixAgentEmailAutopilotScheduler({
    environment: environment(),
    runAutopilot: async () => {
      runs += 1;
      return {};
    },
    now: () => new Date("2026-08-21T12:15:10.000Z"),
    ...timers,
    logger: loggerHarness(),
  });
  scheduler.start();
  await scheduler.runDue();
  await scheduler.runDue();
  assert.equal(runs, 1);
  assert.equal(scheduler.status().runCount, 1);
  assert.equal(scheduler.status().skippedCount, 1);
});

test("overlapping scheduler run is skipped while the first run is in flight", async () => {
  const timers = timerHarness();
  let release;
  let runs = 0;
  const pending = new Promise((resolve) => {
    release = resolve;
  });
  const scheduler = createKorlixAgentEmailAutopilotScheduler({
    environment: environment(),
    runAutopilot: async () => {
      runs += 1;
      await pending;
      return {};
    },
    now: () => new Date("2026-08-21T12:15:10.000Z"),
    ...timers,
    logger: loggerHarness(),
  });
  scheduler.start();
  const first = scheduler.runDue();
  const second = await scheduler.runDue();
  assert.equal(second.inFlight, true);
  assert.equal(second.skippedCount, 1);
  assert.equal(runs, 1);
  release();
  await first;
  assert.equal(scheduler.status().inFlight, false);
});

test("scheduler failure logs only a safe code and continues to the next slot", async () => {
  const timers = timerHarness();
  const logger = loggerHarness();
  const scheduler = createKorlixAgentEmailAutopilotScheduler({
    environment: environment(),
    runAutopilot: async () => {
      const error = new Error("scheduler-secret-never-log");
      error.code = "synthetic_autopilot_failure";
      throw error;
    },
    now: () => new Date("2026-08-21T12:15:10.000Z"),
    ...timers,
    logger,
  });
  scheduler.start();
  await scheduler.runDue();
  assert.equal(scheduler.status().lastErrorCode, "synthetic_autopilot_failure");
  assert.equal(scheduler.status().nextRunAt, "2026-08-21T12:30:00.000Z");
  const logged = JSON.stringify(logger.entries);
  assert.match(logged, /synthetic_autopilot_failure/);
  assert.doesNotMatch(logged, /scheduler-secret-never-log/);
});

test("scheduler stop clears its timer and prevents later execution", async () => {
  const timers = timerHarness();
  let runs = 0;
  const scheduler = createKorlixAgentEmailAutopilotScheduler({
    environment: environment(),
    runAutopilot: async () => {
      runs += 1;
      return {};
    },
    now: () => new Date(NOW),
    ...timers,
    logger: loggerHarness(),
  });
  scheduler.start();
  const handle = timers.scheduled[0];
  const status = scheduler.stop();
  assert.equal(status.started, false);
  assert.equal(status.running, false);
  assert.equal(status.nextRunAt, null);
  assert.deepEqual(timers.cleared, [handle]);
  await scheduler.runDue();
  assert.equal(runs, 0);
});

test("delivery and both server entry points wire the scheduler without immediate send", async () => {
  const delivery = fs.readFileSync(
    new URL("./korlix_agent_email_delivery.mjs", import.meta.url),
    "utf8",
  );
  const backendServer = fs.readFileSync(
    new URL("./server.js", import.meta.url),
    "utf8",
  );
  const rootServer = fs.readFileSync(
    new URL("../server.js", import.meta.url),
    "utf8",
  );

  assert.match(delivery, /createKorlixAgentEmailAutopilotScheduler/);
  assert.match(delivery, /autopilotSchedulerConfigured:\s*scheduler\.configured/);
  assert.match(delivery, /stopAutopilotScheduler:\s*autopilotScheduler\.stop/);
  assert.match(delivery, /emailSentDuringInstall:\s*false/);
  for (const source of [backendServer, rootServer]) {
    assert.match(source, /autoStartScheduler:\s*true/);
    assert.ok(
      source.indexOf("KORLIX_AGENT_EMAIL_DELIVERY_BUILD133_INSTALL_START") <
        source.indexOf('app.use("/api"'),
    );
  }
});

let passed = 0;
for (const entry of tests) {
  await entry.callback();
  passed += 1;
  console.log(`PASS ${passed}: ${entry.name}`);
}

assert.equal(passed, 12);
console.log(`KORLIX_AGENT_EMAIL_SCHEDULER_TEST_COUNT=${passed}`);
console.log("KORLIX_AGENT_EMAIL_SCHEDULER_TEST_PASS=true");
