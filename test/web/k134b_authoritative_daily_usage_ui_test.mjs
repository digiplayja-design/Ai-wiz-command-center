import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source =
  fs.readFileSync(
    "website/nova-email/app.js",
    "utf8",
  );

const index =
  fs.readFileSync(
    "website/nova-email/index.html",
    "utf8",
  );

const start =
  source.indexOf(
    "// K134B_AUTHORITATIVE_DAILY_USAGE_UI_V1_BEGIN",
  );

const end =
  source.indexOf(
    "// K134B_AUTHORITATIVE_DAILY_USAGE_UI_V1_END",
  );

assert.ok(
  start >= 0 &&
  end > start,
);

const helper =
  source.slice(
    start,
    end,
  );

const context = {
  APP: {
    settings: {
      dailySendCap:
        5,

      timezone:
        "America/New_York",
    },

    delivery: {
      dailyUsage: {
        authoritative:
          true,

        dailySendCap:
          100,

        sentToday:
          1,

        sendingToday:
          0,

        usedToday:
          1,

        remainingToday:
          99,

        timezone:
          "America/New_York",

        windowStartAt:
          "2026-09-03T04:00:00.000Z",

        windowEndAt:
          "2026-09-04T04:00:00.000Z",
      },
    },

    events:
      Array.from(
        {
          length:
            5,
        },

        (
          _,
          indexValue,
        ) => ({
          id:
            indexValue,

          type:
            "send_accepted",
        }),
      ),
  },

  firstDefined:
    (...values) =>
      values.find(
        (value) =>
          value !==
            undefined &&
          value !==
            null,
      ),

  asNumber:
    (
      value,
      fallback = 0,
    ) => {
      const number =
        Number(value);

      return Number.isFinite(
        number,
      )
        ? number
        : fallback;
    },

  Object,
  Math,
  String,
};

vm.createContext(
  context,
);

vm.runInContext(
  `${helper}
this.snapshot = authoritativeDailyUsage({});`,
  context,
);

assert.equal(
  context.snapshot.authoritative,
  true,
);

assert.equal(
  context.snapshot.dailySendCap,
  100,
);

assert.equal(
  context.snapshot.sentToday,
  1,
);

assert.equal(
  context.snapshot.sendingToday,
  0,
);

assert.equal(
  context.snapshot.usedToday,
  1,
);

assert.equal(
  context.snapshot.remainingToday,
  99,
);

assert.equal(
  context.snapshot.timezone,
  "America/New_York",
);

const renderStart =
  source.indexOf(
    "  const dailyUsage =",
    source.indexOf(
      "function renderDashboard()",
    ),
  );

const renderEnd =
  source.indexOf(
    "  setTopStatus({",
    renderStart,
  );

const dailyBlock =
  source.slice(
    renderStart,
    renderEnd,
  );

assert.doesNotMatch(
  dailyBlock,
  /metrics\.sent|calculateDeliveryMetrics|APP\.events/,
);

assert.match(
  source,
  /used today/,
);

assert.match(
  source,
  /remaining ·/,
);

assert.match(
  index,
  /\/nova-email\/app\.js\?v=k134b-authoritative-daily-usage-v1/,
);

console.log(
  "K134B_AUTHORITATIVE_DAILY_USAGE_UI_TEST_PASS=true",
);
