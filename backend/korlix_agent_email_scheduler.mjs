const TRUE_VALUES = new Set(["1", "true", "yes", "on", "enabled"]);
const FALSE_VALUES = new Set(["0", "false", "no", "off", "disabled"]);
const TRIGGER_KEY = /^[a-z][a-z0-9_.:-]{0,119}$/;
const VARIABLE_KEY = /^[A-Za-z][A-Za-z0-9_]{0,63}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const AGENT_ID = /^[a-z][a-z0-9_]{0,95}$/;
const MINIMUM_INTERVAL_MINUTES = 1;
const MAXIMUM_INTERVAL_MINUTES = 1440;
const MAXIMUM_VARIABLE_COUNT = 50;
const MAXIMUM_VARIABLE_JSON_BYTES = 20_000;
const MAXIMUM_VARIABLE_VALUE_CHARACTERS = 4000;

function line(value, maximum = 500) {
  return String(value ?? "")
    .replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, Math.max(1, Number(maximum) || 500));
}

function block(value, maximum = MAXIMUM_VARIABLE_VALUE_CHARACTERS) {
  return String(value ?? "")
    .replace(/\r\n?/g, "\n")
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, " ")
    .trim()
    .slice(0, Math.max(1, Number(maximum) || MAXIMUM_VARIABLE_VALUE_CHARACTERS));
}

function objectValue(value) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value
    : {};
}

function envText(environment, name, maximum = 1000) {
  return line(environment?.[name], maximum);
}

function envFlag(environment, name, fallback = false) {
  const value = envText(environment, name, 40).toLowerCase();
  if (!value) return fallback;
  if (TRUE_VALUES.has(value)) return true;
  if (FALSE_VALUES.has(value)) return false;
  return fallback;
}

function schedulerVariables(environment) {
  const raw = String(
    environment?.KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_VARIABLES_JSON ?? "",
  ).trim();

  if (!raw) {
    return Object.freeze({
      variables: Object.freeze({}),
      variableKeys: Object.freeze([]),
      error: null,
    });
  }

  if (Buffer.byteLength(raw, "utf8") > MAXIMUM_VARIABLE_JSON_BYTES) {
    return Object.freeze({
      variables: Object.freeze({}),
      variableKeys: Object.freeze([]),
      error: "scheduler_variables_json_too_large",
    });
  }

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return Object.freeze({
      variables: Object.freeze({}),
      variableKeys: Object.freeze([]),
      error: "scheduler_variables_json_invalid",
    });
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return Object.freeze({
      variables: Object.freeze({}),
      variableKeys: Object.freeze([]),
      error: "scheduler_variables_object_required",
    });
  }

  const entries = Object.entries(parsed);
  if (entries.length > MAXIMUM_VARIABLE_COUNT) {
    return Object.freeze({
      variables: Object.freeze({}),
      variableKeys: Object.freeze([]),
      error: "scheduler_variables_count_exceeded",
    });
  }

  const variables = {};
  for (const [key, value] of entries) {
    if (!VARIABLE_KEY.test(key)) {
      return Object.freeze({
        variables: Object.freeze({}),
        variableKeys: Object.freeze([]),
        error: "scheduler_variable_key_invalid",
      });
    }
    variables[key] = block(value);
  }

  return Object.freeze({
    variables: Object.freeze({ ...variables }),
    variableKeys: Object.freeze(Object.keys(variables).sort()),
    error: null,
  });
}

function intervalMinutes(environment) {
  const raw = envText(
    environment,
    "KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_INTERVAL_MINUTES",
    20,
  );
  const parsed = Number.parseInt(raw, 10);
  return Number.isInteger(parsed) &&
      parsed >= MINIMUM_INTERVAL_MINUTES &&
      parsed <= MAXIMUM_INTERVAL_MINUTES
    ? parsed
    : null;
}

export function korlixAgentEmailAutopilotSchedulerConfiguration(
  environment = process.env,
) {
  const enabled = envFlag(
    environment,
    "KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_ENABLED",
    false,
  );
  const triggerKey = envText(
    environment,
    "KORLIX_AGENT_EMAIL_AUTOPILOT_SCHEDULER_TRIGGER_KEY",
    120,
  ).toLowerCase();
  const minutes = intervalMinutes(environment);
  const parsedVariables = schedulerVariables(environment);
  const errors = [];

  if (enabled) {
    if (!triggerKey) {
      errors.push("scheduler_trigger_key_required");
    } else if (!TRIGGER_KEY.test(triggerKey)) {
      errors.push("scheduler_trigger_key_invalid");
    }

    if (minutes === null) {
      errors.push("scheduler_interval_minutes_invalid");
    }

    if (parsedVariables.error) {
      errors.push(parsedVariables.error);
    }

    if (!envFlag(environment, "KORLIX_AGENT_EMAIL_ENABLED", false)) {
      errors.push("agent_email_feature_disabled");
    }
    if (envFlag(environment, "KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE", true)) {
      errors.push("agent_email_emergency_paused");
    }
    if (!envFlag(environment, "KORLIX_AGENT_EMAIL_SEND_ENABLED", false)) {
      errors.push("agent_email_send_runtime_disabled");
    }
    if (!envFlag(environment, "KORLIX_AGENT_EMAIL_AUTOPILOT_ENABLED", false)) {
      errors.push("agent_email_autopilot_runtime_disabled");
    }

    const ownerUid = envText(environment, "KORLIX_VAPI_NOVA_OWNER_UID", 80);
    const agentId = envText(environment, "KORLIX_VAPI_NOVA_AGENT_ID", 96).toLowerCase();
    const assistantId =
      envText(environment, "KORLIX_VAPI_NOVA_ASSISTANT_ID", 200) ||
      envText(environment, "VAPI_NOVA_ASSISTANT_ID", 200);
    if (!UUID.test(ownerUid) || !AGENT_ID.test(agentId) || !assistantId) {
      errors.push("nova_agent_binding_not_configured");
    }

    if (
      !envText(environment, "RESEND_API_KEY", 1000) ||
      !envText(environment, "KORLIX_AGENT_EMAIL_FROM", 500)
    ) {
      errors.push("resend_provider_not_configured");
    }

    if (!envText(environment, "KORLIX_AGENT_EMAIL_AUTOPILOT_SECRET", 1000)) {
      errors.push("autopilot_secret_not_configured");
    }
  }

  const configured = enabled && errors.length === 0;
  return Object.freeze({
    enabled,
    configured,
    triggerKey: TRIGGER_KEY.test(triggerKey) ? triggerKey : null,
    intervalMinutes: minutes,
    intervalMilliseconds: minutes === null ? null : minutes * 60 * 1000,
    variableKeys: parsedVariables.variableKeys,
    errors: Object.freeze([...errors]),
    variables: parsedVariables.variables,
  });
}

function dateValue(now) {
  const value = typeof now === "function" ? now() : new Date();
  const date = value instanceof Date ? new Date(value.getTime()) : new Date(value);
  if (!Number.isFinite(date.getTime())) {
    throw new TypeError("The Agent Email scheduler clock returned an invalid date.");
  }
  return date;
}

function summary(result) {
  const source = objectValue(result);
  return Object.freeze({
    matchedRuleCount: Math.max(0, Number(source.matchedRuleCount) || 0),
    attempted: Math.max(0, Number(source.attempted) || 0),
    sentCount: Math.max(0, Number(source.sentCount) || 0),
    replayedCount: Math.max(0, Number(source.replayedCount) || 0),
  });
}

function safeErrorCode(error) {
  return line(error?.code, 120) || "agent_email_scheduler_run_failed";
}

export function createKorlixAgentEmailAutopilotScheduler({
  environment = process.env,
  runAutopilot,
  now = () => new Date(),
  setTimeoutImpl = globalThis.setTimeout,
  clearTimeoutImpl = globalThis.clearTimeout,
  logger = console,
} = {}) {
  if (typeof runAutopilot !== "function") {
    throw new TypeError("The Agent Email Autopilot runner is required.");
  }
  if (typeof setTimeoutImpl !== "function" || typeof clearTimeoutImpl !== "function") {
    throw new TypeError("The Agent Email scheduler timer functions are required.");
  }

  const configuration =
    korlixAgentEmailAutopilotSchedulerConfiguration(environment);
  let timer = null;
  let stopped = true;
  let inFlight = false;
  let nextRunAt = null;
  let lastSlotStart = null;
  let lastEventId = null;
  let lastResult = null;
  let lastErrorCode = null;
  let runCount = 0;
  let skippedCount = 0;

  const log = (level, event, details = {}) => {
    const method = logger?.[level];
    if (typeof method === "function") {
      method.call(logger, event, details);
    }
  };

  const publicStatus = () => Object.freeze({
    enabled: configuration.enabled,
    configured: configuration.configured,
    triggerKey: configuration.triggerKey,
    intervalMinutes: configuration.intervalMinutes,
    variableKeys: [...configuration.variableKeys],
    configurationErrors: [...configuration.errors],
    started: !stopped,
    running: !stopped && configuration.configured,
    inFlight,
    nextRunAt,
    lastSlotStart,
    lastEventId,
    lastResult,
    lastErrorCode,
    runCount,
    skippedCount,
  });

  const scheduleNext = () => {
    if (stopped || !configuration.configured) return;

    const current = dateValue(now);
    const interval = configuration.intervalMilliseconds;
    const nextSlot = (Math.floor(current.getTime() / interval) + 1) * interval;
    const delay = Math.max(1, nextSlot - current.getTime());
    nextRunAt = new Date(nextSlot).toISOString();
    timer = setTimeoutImpl(() => {
      timer = null;
      nextRunAt = null;
      return runDue();
    }, delay);
    if (timer && typeof timer.unref === "function") timer.unref();
  };

  const runDue = async () => {
    if (stopped || !configuration.configured) return publicStatus();

    const current = dateValue(now);
    const interval = configuration.intervalMilliseconds;
    const slotStartMilliseconds = Math.floor(current.getTime() / interval) * interval;
    const slotStart = new Date(slotStartMilliseconds).toISOString();
    const eventId = [
      "korlix-agent-email-scheduler",
      configuration.triggerKey,
      slotStart,
    ].join(":");

    if (inFlight) {
      skippedCount += 1;
      log("warn", "KORLIX_AGENT_EMAIL_SCHEDULER_TICK_SKIPPED", {
        reason: "run_in_flight",
        triggerKey: configuration.triggerKey,
        slotStart,
      });
      return publicStatus();
    }

    if (lastEventId === eventId) {
      skippedCount += 1;
      log("info", "KORLIX_AGENT_EMAIL_SCHEDULER_TICK_REPLAY_SKIPPED", {
        triggerKey: configuration.triggerKey,
        slotStart,
      });
      return publicStatus();
    }

    inFlight = true;
    lastSlotStart = slotStart;
    lastEventId = eventId;
    lastErrorCode = null;
    runCount += 1;

    try {
      const result = await runAutopilot({
        body: {
          triggerKey: configuration.triggerKey,
          eventId,
          variables: {
            ...configuration.variables,
            scheduler_trigger_key: configuration.triggerKey,
            scheduler_slot_start: slotStart,
            scheduler_interval_minutes: String(configuration.intervalMinutes),
          },
        },
      });
      lastResult = summary(result);
      log("info", "KORLIX_AGENT_EMAIL_SCHEDULER_TICK_COMPLETE", {
        triggerKey: configuration.triggerKey,
        slotStart,
        ...lastResult,
      });
    } catch (error) {
      lastResult = null;
      lastErrorCode = safeErrorCode(error);
      log("error", "KORLIX_AGENT_EMAIL_SCHEDULER_TICK_FAILED", {
        triggerKey: configuration.triggerKey,
        slotStart,
        code: lastErrorCode,
      });
    } finally {
      inFlight = false;
      scheduleNext();
    }

    return publicStatus();
  };

  const start = () => {
    if (!configuration.configured) {
      stopped = true;
      if (configuration.enabled) {
        log("error", "KORLIX_AGENT_EMAIL_SCHEDULER_CONFIGURATION_BLOCKED", {
          errors: [...configuration.errors],
        });
      }
      return publicStatus();
    }
    if (!stopped) return publicStatus();
    stopped = false;
    scheduleNext();
    log("info", "KORLIX_AGENT_EMAIL_SCHEDULER_STARTED", {
      triggerKey: configuration.triggerKey,
      intervalMinutes: configuration.intervalMinutes,
      nextRunAt,
    });
    return publicStatus();
  };

  const stop = () => {
    stopped = true;
    if (timer !== null) {
      clearTimeoutImpl(timer);
      timer = null;
    }
    nextRunAt = null;
    return publicStatus();
  };

  return Object.freeze({
    start,
    stop,
    status: publicStatus,
    runDue,
  });
}
