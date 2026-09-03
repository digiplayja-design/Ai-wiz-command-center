import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source =
  fs.readFileSync(
    "website/nova-email/k134b-schedule-dashboard.js",
    "utf8",
  );

const index =
  fs.readFileSync(
    "website/nova-email/index.html",
    "utf8",
  );

assert.match(
  source,
  /K134B_SCHEDULE_STATUS_NORMALIZATION_V1_BEGIN/,
);

assert.match(
  source,
  /KorlixK134BScheduleDashboardTest/,
);

assert.match(
  index,
  /k134b-schedule-dashboard\.js\?v=k134b-status-normalization-v1/,
);

const context = {
  console,

  APP: {
    rules: [],
    recipients: [],
    drafts: [],
    settings: {},
  },

  renderDashboard() {
    return undefined;
  },

  document: {
    readyState: "loading",

    addEventListener() {},

    getElementById() {
      return null;
    },

    querySelector() {
      return null;
    },

    createElement() {
      return {};
    },

    documentElement: {
      classList: {
        add() {},
        remove() {},
      },
    },
  },

  requestJson:
    async () => ({}),

  emailBase:
    () => "/api",

  refreshDashboard:
    async () => undefined,

  confirm:
    () => false,

  prompt:
    () => "",

  alert() {},

  setTimeout,
  clearTimeout,
  queueMicrotask,
  Intl,
  Date,
  Number,
  String,
  Object,
  Array,
  Set,
  JSON,
  Math,
  encodeURIComponent,
};

context.window =
  context;

vm.createContext(
  context,
);

vm.runInContext(
  source,
  context,
  {
    filename:
      "k134b-schedule-dashboard.js",
  },
);

const hooks =
  context
    .KorlixK134BScheduleDashboardTest;

assert.ok(
  hooks,
  "schedule-dashboard test hooks must be published",
);

assert.equal(
  hooks.first(
    undefined,
    null,
    "",
    " undefined ",
    "null",
    "usable",
  ),
  "usable",
);

assert.equal(
  hooks.optionalText(
    " undefined ",
  ),
  "",
);

const future =
  new Date(
    Date.now() +
      24 * 60 * 60 * 1000,
  ).toISOString();

const past =
  new Date(
    Date.now() -
      24 * 60 * 60 * 1000,
  ).toISOString();

const futureRule = {
  enabled:
    true,

  schedule_type:
    "once",

  scheduled_for:
    future,

  next_run_at:
    future,

  last_result:
    "undefined",

  failure_code:
    "undefined",

  error_codes:
    [
      "undefined",
    ],

  metadata: {
    lastScheduleResult:
      "null",

    lastScheduleErrorCodes:
      [
        "undefined",
      ],
  },
};

assert.equal(
  hooks.statusFor(
    futureRule,
    null,
  ).label,
  "SCHEDULED",
);

assert.equal(
  hooks.failureCode(
    futureRule,
    null,
  ),
  "",
);

assert.equal(
  hooks.messageStatusLabel(
    futureRule,
    null,
  ),
  "No message attempt yet",
);

assert.equal(
  hooks.nextRunForDisplay(
    futureRule,
  ),
  future,
);

const cancelledRule = {
  ...futureRule,

  enabled:
    false,

  next_run_at:
    null,
};

assert.equal(
  hooks.statusFor(
    cancelledRule,
    null,
  ).label,
  "CANCELLED",
);

assert.equal(
  hooks.nextRunForDisplay(
    cancelledRule,
  ),
  null,
);

assert.equal(
  hooks.messageStatusLabel(
    cancelledRule,
    null,
  ),
  "Cancelled before send",
);

const completedRule = {
  ...futureRule,

  enabled:
    false,

  next_run_at:
    null,

  completed_at:
    new Date().toISOString(),
};

assert.equal(
  hooks.statusFor(
    completedRule,
    null,
  ).label,
  "COMPLETED",
);

assert.equal(
  hooks.nextRunForDisplay(
    completedRule,
  ),
  null,
);

const failedRule = {
  ...futureRule,

  error_codes:
    [
      "provider_rejected",
    ],
};

assert.equal(
  hooks.failureCode(
    failedRule,
    null,
  ),
  "provider_rejected",
);

assert.equal(
  hooks.statusFor(
    failedRule,
    null,
  ).label,
  "FAILED",
);

const overdueRule = {
  ...futureRule,

  scheduled_for:
    past,

  next_run_at:
    past,
};

assert.equal(
  hooks.statusFor(
    overdueRule,
    null,
  ).label,
  "OVERDUE",
);

assert.equal(
  hooks.statusFor(
    futureRule,
    {
      status:
        "delivered",

      delivered_at:
        new Date().toISOString(),
    },
  ).label,
  "DELIVERED",
);

const needsReview =
  [
    hooks.statusFor(
      futureRule,
      null,
    ),

    hooks.statusFor(
      cancelledRule,
      null,
    ),
  ].filter(
    (status) =>
      [
        "OVERDUE",
        "FAILED",
      ].includes(
        status.label,
      ),
  );

assert.equal(
  needsReview.length,
  0,
);

console.log(
  "K134B_SCHEDULE_STATUS_NORMALIZATION_RUNTIME_TEST_PASS=true",
);
