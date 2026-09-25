# K196 — Funnel Studio request and confirmation fixes

## Problem and result

The original studio could accept a delayed list response after Enterprise access was denied, restore old content after replacing its API client, or leave a publish/pause/create confirmation open across that replacement. Reloading a funnel that had disappeared from the saved list raised an unhelpful collection error. Its campaign-link help also still said direct publishing was unavailable even though gated provider controls had since been implemented.

K196 invalidates pending studio operations when the client changes or the backend reports denied access. List, save, publish, pause, generation, creation, reload, image selection and queued-follow-up results now belong to their initiating studio context. Older request failures or completion handlers cannot clear the current request's loading indicator or replace its content. Denial clears drafts, names, filters, tags and selection. A new client loads its own saved list; a late response cannot undo an access denial.

Publish and pause confirmations bind the exact selected funnel ID and saved version. Follow-up confirmation binds the selected funnel. Studio-owned dialogs and their nested confirmations close when their context is invalidated. A create request that already reached the server may still create a private draft, but its late response cannot open that draft in the replacement workspace. No write is retried automatically; these UI fixes do not cancel already committed server work.

A missing saved funnel returns the owner to the current saved list with a clear message. Campaign-link help now points to Ads workspace for setup, controls and conversion delivery, while retaining the requirement for separate setup and explicit confirmation.

The screen uses an access-denied listener rather than replacing the client's existing callback. Borrowed clients are not disposed by the screen. The main application route explicitly marks its newly created client as owned, so it is disposed when replaced or when that route closes.

These guards react to client replacement and backend 401/403 notifications. They are not a new authentication service and do not claim independent, proactive detection of an account switch that emits neither event. Server-side ownership, entitlement and version checks remain authoritative.

## Verification scope

151 tests passed: 86 backend and 65 Flutter, including four new backend journeys and 11 new UI lifecycle regressions.

New Flutter regression tests reproduce late list/save/generation/create responses, late denial from an old client, access-denied dialog closure, publish/pause confirmation invalidation, nested image deletion confirmation closure, a newer pending load, missing-funnel reload and preservation of other borrowed-client consumers. Existing studio, template, rehearsal, image, inbox, follow-up and campaign tests cover normal navigation, saves, publication and desktop/mobile layouts. The image denial regression now expects the obsolete modal to close and the studio access message to appear.

Four new backend journey tests use Express HTTP routes and the actual relevant migrations in local PGlite:

1. Create a private draft; run valid and invalid rehearsals without new business records; publish; save newer copy while the published snapshot stays unchanged; reject a stale save; republish deliberately.
2. Complete a guided inquiry with conditional questions; ignore hidden answers; retain one inquiry on replay; select the booking route; verify CRM permissions; edit private stage/note; reconcile filtered export; deny another owner access.
3. Enable a local test workflow; capture two review tasks without email/calls; preserve an existing contact's suppression and permissions; create no email recipient or sequence; confirm provider gates remain off.
4. Preview and confirm one inquiry cleanup; acknowledge an idempotent replay without recreating deleted evidence; retain CRM history; pause the page and reject further public submissions.

The journey harness permits HTTP requests only to its localhost fixture server and supplies provider adapters that fail on any call. It creates no production page, inquiry, contact, task, account or campaign. An acknowledged replay after cleanup is allowed by the existing public contract; the assertion checks that it cannot recreate the inquiry.

This extends automated evidence across the core journey. It does not mark owner acceptance A–G, real browser/device behavior, external clipboard/download behavior, provider connection, actual email delivery, ad acceptance or attributed conversions as passed.

## Scope, deployment and rollback

Frontend behavior changes only; backend runtime behavior is unchanged. The backend commit contains the journey tests and this documentation. **No migration, database write, environment change or provider activation is required.** Deploy through the existing release branches and Render services. AutoDeploy remains off.

Rollback the frontend to K195 if needed. No data rollback or migration rollback is necessary. Keep the backend test/documentation commit if desired; it changes no runtime behavior.

Meta developer setup remains paused. The recovered K173 acceptance handoff (version 2) explicitly defers all owner hands-on A–G batches and says not to restart those tests or ask for screenshots on “Next.” Routine automated verification remains permitted. K196 does not add a new acceptance gate or reduce the agreed connected-funnel scope.

## Remaining completion work

Core features are implemented and deployed. The connected funnel still needs real Google/Meta setup and permissions, controlled provider acceptance, conversion delivery/report reconciliation and final owner/device acceptance. Those dependencies remain deferred. Advanced autonomous optimization/outreach is not silently added to this release scope.

The planning estimate remains **6–18 working hours**, plus external provider approval delays. It remains provisional until the real integrations and owner acceptance are completed; passing mocks or deploying disabled provider paths does not establish those outcomes. Detailed test counts, commits and live deployment evidence are recorded in the K196 checkpoint.
