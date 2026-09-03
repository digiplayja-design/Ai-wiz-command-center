import assert from "node:assert/strict";
import fs from "node:fs";

const app = fs.readFileSync(
  "website/nova-email/app.js",
  "utf8",
);

const index = fs.readFileSync(
  "website/nova-email/index.html",
  "utf8",
);

const dashboard = fs.readFileSync(
  "website/nova-email/k134b-schedule-dashboard.js",
  "utf8",
);

const css = fs.readFileSync(
  "website/nova-email/k134b-schedule-dashboard.css",
  "utf8",
);

assert.match(
  app,
  /["']\/api\/live-convo\/agents["']/,
);

assert.doesNotMatch(
  app,
  /["']\/api\/agent-hub\/agents["']/,
);

assert.doesNotMatch(
  app,
  /["']\/api\/agents["']/,
);

assert.match(
  index,
  /k134b-schedule-dashboard\.css/,
);

assert.match(
  index,
  /k134b-schedule-dashboard\.js/,
);

assert.match(
  dashboard,
  /K134B_NOVA_EMAIL_SCHEDULE_DASHBOARD_V1_BEGIN/,
);

assert.match(
  dashboard,
  /method:\s*"PATCH"/,
);

assert.match(
  dashboard,
  /confirmed:\s*true/,
);

assert.match(
  dashboard,
  /enabled:\s*false/,
);

assert.match(
  dashboard,
  /SCHEDULED EMAILS/,
);

assert.doesNotMatch(
  dashboard,
  /\/drafts\/[^\s"'`]+\/send/,
);

assert.doesNotMatch(
  dashboard,
  /\/api\/internal\/agent-email\/autopilot\/run/,
);

assert.match(
  css,
  /K134B_NOVA_EMAIL_SCHEDULE_DASHBOARD_V1_BEGIN/,
);

console.log(
  "K134B_NOVA_EMAIL_SCHEDULE_DASHBOARD_SOURCE_TEST_PASS=true",
);
