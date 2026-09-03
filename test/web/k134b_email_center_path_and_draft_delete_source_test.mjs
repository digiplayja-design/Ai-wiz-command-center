import assert from "node:assert/strict";
import fs from "node:fs";

const index =
  fs.readFileSync(
    "website/nova-email/index.html",
    "utf8",
  );

const manifest =
  fs.readFileSync(
    "website/nova-email/manifest.webmanifest",
    "utf8",
  );

const deleteUi =
  fs.readFileSync(
    "website/nova-email/k134b-draft-delete.js",
    "utf8",
  );

const deleteCss =
  fs.readFileSync(
    "website/nova-email/k134b-draft-delete.css",
    "utf8",
  );

assert.match(
  index,
  /K134B_NOVA_EMAIL_CANONICAL_PATH_V1_BEGIN/,
);

assert.match(
  index,
  /<base href="\/nova-email\/">/,
);

assert.match(
  index,
  /window\.location\.pathname === "\/nova-email"/,
);

assert.match(
  index,
  /window\.location\.replace/,
);

assert.doesNotMatch(
  index,
  /\b(?:src|href)\s*=\s*["']\.\//i,
);

for (
  const asset
  of [
    "/nova-email/styles.css",
    "/nova-email/app.js",
    "/nova-email/template-rule-builder.css",
    "/nova-email/template-rule-builder.js",
    "/nova-email/k134b-schedule-dashboard.css",
    "/nova-email/k134b-schedule-dashboard.js",
    "/nova-email/k134b-draft-delete.css",
    "/nova-email/k134b-draft-delete.js",
    "/nova-email/assets/korlix-nova-logo-v2.jpeg",
  ]
) {
  assert.ok(
    index.includes(
      asset,
    ),
    `missing absolute asset ${asset}`,
  );
}

assert.doesNotMatch(
  manifest,
  /"src"\s*:\s*"\.\//,
);

assert.match(
  deleteUi,
  /K134B_SAFE_DRAFT_DELETE_UI_V1_BEGIN/,
);

assert.match(
  deleteUi,
  /method:\s*"DELETE"/,
);

assert.match(
  deleteUi,
  /confirmationPhrase/,
);

assert.match(
  deleteUi,
  /DELETE DRAFT/,
);

assert.match(
  deleteUi,
  /deleteStatuses/,
);

assert.match(
  deleteUi,
  /approved/,
);

assert.match(
  deleteUi,
  /failed/,
);

assert.match(
  deleteUi,
  /Delete Drafts/,
);

assert.doesNotMatch(
  deleteUi,
  /\/send["'`]/,
);

assert.doesNotMatch(
  deleteUi,
  /autopilot\/run/,
);

assert.match(
  deleteCss,
  /K134B_SAFE_DRAFT_DELETE_UI_V1_BEGIN/,
);

console.log(
  "K134B_EMAIL_CENTER_PATH_AND_DRAFT_DELETE_SOURCE_TEST_PASS=true",
);
