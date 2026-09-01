import {
  KorlixAgentEmailError,
} from "./korlix_agent_email.mjs";

export const KORLIX_AGENT_EMAIL_SCHEDULE_TYPES = Object.freeze([
  "event",
  "once",
  "weekly",
]);

const SCHEDULE_TYPES = new Set(KORLIX_AGENT_EMAIL_SCHEDULE_TYPES);
const TIME = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
const DAY_MILLISECONDS = 24 * 60 * 60 * 1000;

function line(value, maximum = 500) {
  return String(value ?? "")
    .replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, Math.max(1, Number(maximum) || 500));
}

function objectValue(value) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value
    : {};
}

function fail(message, code, statusCode = 400, cause) {
  throw new KorlixAgentEmailError(message, {
    code,
    statusCode,
    cause,
  });
}

function dateValue(value, code = "agent_email_schedule_clock_invalid") {
  const date = value instanceof Date
    ? new Date(value.getTime())
    : new Date(value);

  if (!Number.isFinite(date.getTime())) {
    fail(
      "Nova could not verify the scheduled email clock.",
      code,
      500,
    );
  }

  return date;
}

export function korlixAgentEmailScheduleType(
  value,
  fallback = "event",
) {
  const normalized = line(value || fallback, 40).toLowerCase();

  if (!SCHEDULE_TYPES.has(normalized)) {
    fail(
      "Choose an event-triggered, one-time, or weekly Agent Email schedule.",
      "agent_email_schedule_type_invalid",
    );
  }

  return normalized;
}

export function korlixAgentEmailScheduleTimezone(
  value,
  fallback = "UTC",
) {
  const timeZone = line(value || fallback, 80) || "UTC";

  try {
    new Intl.DateTimeFormat("en-US", {
      timeZone,
      year: "numeric",
    }).format(new Date(0));
  } catch (error) {
    fail(
      "Enter a valid IANA timezone for the scheduled email.",
      "agent_email_schedule_timezone_invalid",
      400,
      error,
    );
  }

  return timeZone;
}

export function korlixAgentEmailScheduleLocalTime(
  value,
  {
    allowNull = false,
  } = {},
) {
  const raw = line(value, 16);
  const localTime = /^\d{2}:\d{2}:\d{2}$/.test(raw)
    ? raw.slice(0, 5)
    : raw;

  if (!localTime && allowNull) {
    return null;
  }

  if (!TIME.test(localTime)) {
    fail(
      "Scheduled email time must use 24-hour HH:MM format.",
      "agent_email_schedule_local_time_invalid",
    );
  }

  return localTime;
}

export function korlixAgentEmailScheduleDays(
  value,
  fallback = [0, 1, 2, 3, 4, 5, 6],
) {
  const safeFallback = Array.isArray(fallback)
    ? fallback
    : [0, 1, 2, 3, 4, 5, 6];
  const source = Array.isArray(value) ? value : safeFallback;
  const days = [...new Set(source.map((item) => Number(item)))];

  if (
    !days.length ||
    days.some(
      (day) => !Number.isInteger(day) || day < 0 || day > 6,
    )
  ) {
    fail(
      "Scheduled email days must be integers from 0 through 6.",
      "agent_email_schedule_days_invalid",
    );
  }

  return days.sort((left, right) => left - right);
}

export function korlixAgentEmailScheduleTimestamp(
  value,
  {
    allowNull = false,
    futureAfter = null,
  } = {},
) {
  const text = line(value, 100);

  if (!text && allowNull) {
    return null;
  }

  const timestamp = Date.parse(text);

  if (!Number.isFinite(timestamp)) {
    fail(
      "Enter a valid date and time for the scheduled email.",
      "agent_email_schedule_timestamp_invalid",
    );
  }

  if (futureAfter !== null) {
    const boundary = dateValue(futureAfter);

    if (timestamp <= boundary.getTime()) {
      fail(
        "The scheduled email time must be in the future.",
        "agent_email_schedule_time_must_be_future",
        409,
      );
    }
  }

  return new Date(timestamp).toISOString();
}

export function korlixAgentEmailScheduleZonedParts(
  value,
  timeZone,
) {
  const date = dateValue(value);
  const safeTimeZone = korlixAgentEmailScheduleTimezone(timeZone);

  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: safeTimeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
      weekday: "short",
    }).formatToParts(date);
    const map = Object.fromEntries(
      parts.map((part) => [part.type, part.value]),
    );
    const weekday = [
      "Sun",
      "Mon",
      "Tue",
      "Wed",
      "Thu",
      "Fri",
      "Sat",
    ].indexOf(map.weekday);

    return Object.freeze({
      year: Number(map.year),
      month: Number(map.month),
      day: Number(map.day),
      hour: Number(map.hour),
      minute: Number(map.minute),
      second: Number(map.second),
      weekday,
    });
  } catch (error) {
    fail(
      "Nova could not evaluate the scheduled email timezone.",
      "agent_email_schedule_timezone_invalid",
      400,
      error,
    );
  }
}

function timezoneOffsetMilliseconds(date, timeZone) {
  const parts = korlixAgentEmailScheduleZonedParts(date, timeZone);
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

function localDateTimeToUtc({
  year,
  month,
  day,
  hour,
  minute,
  timeZone,
}) {
  const targetAsUtc = Date.UTC(
    year,
    month - 1,
    day,
    hour,
    minute,
    0,
    0,
  );
  let candidate = new Date(targetAsUtc);

  for (let index = 0; index < 6; index += 1) {
    const next = new Date(
      targetAsUtc - timezoneOffsetMilliseconds(candidate, timeZone),
    );

    if (Math.abs(next.getTime() - candidate.getTime()) < 1000) {
      candidate = next;
      break;
    }

    candidate = next;
  }

  const parts = korlixAgentEmailScheduleZonedParts(candidate, timeZone);
  const exact =
    parts.year === year &&
    parts.month === month &&
    parts.day === day &&
    parts.hour === hour &&
    parts.minute === minute;

  return exact ? candidate : null;
}

export function korlixAgentEmailNextWeeklyRunAt({
  after,
  timeZone,
  localTime,
  days,
}) {
  const boundary = dateValue(after);
  const safeTimeZone = korlixAgentEmailScheduleTimezone(timeZone);
  const safeLocalTime = korlixAgentEmailScheduleLocalTime(localTime);
  const safeDays = korlixAgentEmailScheduleDays(days);
  const [hour, minute] = safeLocalTime.split(":").map(Number);
  const localBoundary = korlixAgentEmailScheduleZonedParts(
    boundary,
    safeTimeZone,
  );
  const localCalendarStart = Date.UTC(
    localBoundary.year,
    localBoundary.month - 1,
    localBoundary.day,
  );

  for (let offset = 0; offset < 15; offset += 1) {
    const calendarDate = new Date(
      localCalendarStart + offset * DAY_MILLISECONDS,
    );

    if (!safeDays.includes(calendarDate.getUTCDay())) {
      continue;
    }

    const candidate = localDateTimeToUtc({
      year: calendarDate.getUTCFullYear(),
      month: calendarDate.getUTCMonth() + 1,
      day: calendarDate.getUTCDate(),
      hour,
      minute,
      timeZone: safeTimeZone,
    });

    // A local time such as 02:30 can be nonexistent on a DST transition.
    // Skip only that calendar occurrence and continue to the next allowed day.
    if (!candidate) {
      continue;
    }

    if (candidate.getTime() > boundary.getTime()) {
      return candidate.toISOString();
    }
  }

  fail(
    "Nova could not calculate the next weekly email occurrence.",
    "agent_email_schedule_next_run_unavailable",
    500,
  );
}

export function korlixAgentEmailNextRunAt({
  scheduleType,
  after,
  timeZone = "UTC",
  localTime = null,
  days = [0, 1, 2, 3, 4, 5, 6],
  scheduledFor = null,
}) {
  const type = korlixAgentEmailScheduleType(scheduleType);
  const boundary = dateValue(after);

  if (type === "event") {
    return null;
  }

  if (type === "once") {
    return korlixAgentEmailScheduleTimestamp(scheduledFor, {
      futureAfter: boundary,
    });
  }

  return korlixAgentEmailNextWeeklyRunAt({
    after: boundary,
    timeZone,
    localTime,
    days,
  });
}

export function korlixAgentEmailScheduleFromRule(row) {
  const source = objectValue(row);
  const metadata = objectValue(source.metadata);
  const type = korlixAgentEmailScheduleType(
    source.schedule_type ?? metadata.scheduleType ?? "event",
  );
  const timeZone = korlixAgentEmailScheduleTimezone(
    source.schedule_timezone ??
      metadata.scheduleTimezone ??
      "UTC",
  );
  const localTime = type === "weekly"
    ? korlixAgentEmailScheduleLocalTime(
        source.schedule_local_time ??
          metadata.scheduleLocalTime,
      )
    : null;
  const storedDays = Array.isArray(source.schedule_days) &&
      source.schedule_days.length
    ? source.schedule_days
    : metadata.allowedDays;
  const days = type === "weekly"
    ? korlixAgentEmailScheduleDays(storedDays)
    : [];
  const scheduledFor = type === "once"
    ? korlixAgentEmailScheduleTimestamp(
        source.scheduled_for ?? metadata.scheduledFor,
      )
    : null;
  const nextRunAt = line(source.next_run_at, 100)
    ? korlixAgentEmailScheduleTimestamp(
        source.next_run_at,
      )
    : null;

  return Object.freeze({
    type,
    timeZone,
    localTime,
    days: Object.freeze([...days]),
    scheduledFor,
    nextRunAt,
    lastRunAt: line(source.last_run_at, 100) || null,
    completedAt: line(source.completed_at, 100) || null,
    deletedAt: line(source.deleted_at, 100) || null,
  });
}

export function korlixAgentEmailScheduleFingerprint({
  scheduleType,
  timeZone,
  localTime,
  days,
  scheduledFor,
}) {
  const type = korlixAgentEmailScheduleType(scheduleType);

  return JSON.stringify({
    scheduleType: type,
    timeZone: korlixAgentEmailScheduleTimezone(timeZone),
    localTime: type === "weekly"
      ? korlixAgentEmailScheduleLocalTime(localTime)
      : null,
    days: type === "weekly"
      ? korlixAgentEmailScheduleDays(days)
      : [],
    scheduledFor: type === "once"
      ? korlixAgentEmailScheduleTimestamp(scheduledFor)
      : null,
  });
}
