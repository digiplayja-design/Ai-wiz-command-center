# KORLIX App Studio

## User experience
The Create an App quick action and Tools → App Studio now open a dedicated workspace. The old five-question dialog that inserted a long specification/code prompt into chat is replaced by a guided creation and revision flow.

- Describe an idea in one field; audience and style guidance are optional.
- Save the idea privately, or request an AI build.
- Six instant starters: Client CRM, Booking tracker, Inventory, Project board, Field service and Personal planner. These do not call AI.
- Interactive web preview with real collection navigation, search, add/edit/delete forms, required-field validation, choices, dates, numbers, checkboxes and status boards.
- Plain-language revisions, completed build recovery and editable instructions after a failed build.
- Free manual name/accent/light-dark styling; desktop/phone preview widths.
- Up to 50 private projects and the last 30 immutable versions per project. Restore creates a new version rather than deleting newer work.
- Export a runnable self-contained web app ZIP with index.html, app.json, runtime.js, runtime.css and README.md.

The exported app uses plain HTML/CSS/JavaScript and needs no package installation or API key. KORLIX itself remains Flutter. This release does not generate Swift/Kotlin packages or a Flutter native app bundle. Interactive preview is web-only; native clients show a clear explanation and can still review/export projects.

## What the generated app can do
This release generates validated structured data-app designs with 1–4 collections, up to 8 fields per collection and up to 8 sample records per collection. The renderer implements the actual interactions. Preview data is temporary and resets when the iframe reloads or a new version opens. Preview interactions never write records into KORLIX businesses or send preview entries to AI.

Downloaded apps can save local entries in the same browser when local storage is available. A warning appears when storage fails. Export data creates a JSON backup. Each exported project version has separate local storage; automatically migrating data between versions is not implemented. Local records are capped at 2,000 per collection. Reset sample data asks for confirmation before replacing local entries.

The app is a prototype, not a production multi-user system. Shared accounts, secure authentication, live payments, messages, real scheduling availability, external services, arbitrary custom code, image uploads, app hosting and native-store publishing are not connected. These limitations are visible in the app plan, launch checklist, export instructions and privacy policy. A status board groups by its first choice field; moving a record is done through Edit, not drag and drop. The builder does not promise a measured 10× improvement or full parity with hosted full-stack builders.

## AI generation and allowance
Builds use the existing gpt-6-astra / xhigh policy via OpenAI Responses with a strict JSON schema, store:false, a five-minute deadline and no automatic provider retries. The model chooses the app's structured design; it never supplies executable preview code. Every response is validated for bounded fields, unique safe IDs, supported data types, valid choices and dates, color and size. Incomplete, refused or invalid output never replaces a saved project.

The existing Basic/Pro/Ultra/Enterprise daily generation and credit limits remain. Each AI build/revision reserves one generation and one credit atomically in the user's existing usage counter. Success keeps the reservation; a definite failure or a stale interrupted build refunds it exactly once. Starter creation, previews, manual styling, restore and export do not use AI credits. There is no new paid plan or checkout.

One build per account, up to 12 attempts/hour and three in-process builds globally. A client-generated request UUID with an input hash prevents a duplicate retry from invoking the provider again. Replaying an existing completed/failed request remains possible even if allowance subsequently changes. New edits require a new request. Usage is locked inside the App Studio transaction; this release does not rewrite legacy usage logic elsewhere in the app.

The backend saves a run before acknowledging it and continues the request while the studio is closed. There is no new background-worker service. Returning to a project reloads saved state. A process restart can interrupt an in-flight build; a run older than 12 minutes is marked failed and refunded on the next App Studio access. It is not automatically reissued to the provider. Completed project versions survive restarts.

## Private storage and isolation
The additive migration *_app_studio_projects.sql adds korlix_app_projects, korlix_app_versions and korlix_app_runs plus the service-only security-invoker korlix_app_studio_v1 RPC. Tables have RLS and no anon/authenticated direct grants. The backend verifies the user and scopes every project, run, version, mutation and export to that owner. Request identity headers, body fields and user-editable metadata do not confer access. All private responses are no-store.

The client binds its lifetime to the issuer, user and session ID. A sign-in change clears private state and confirmation dialogs, destroys the preview and rejects late results/downloads. AI sharing permission is required before a build; non-AI saves/starters do not send anything to a model.

Completed and failed runs discard the full input snapshot and retain the bounded original request for replay/recovery, plus status and usage identifiers. Project deletion erases the idea, versions, build instruction payloads and errors; minimal hash/usage receipts remain so deletion cannot replay a paid request or reset allowance. Account deletion cascades App Studio content and receipts. Exported files remain under the user's control.

The preview uses a sandboxed iframe with scripts/forms allowed, without same-origin privileges, popups or top-navigation permissions. The model cannot provide HTML/JavaScript. The fixed runtime writes all labels and records with textContent; JSON is escaped before embedding. CSP blocks network connections, external images/scripts, form submission, objects and base URL changes. The preview does not access browser storage or offer data download inside the frame. Explicit project export is authenticated and outside the preview. No production token, cookie or provider secret is passed into exported apps.

## Validation and deployment
Backend tests execute the actual SQL in PGlite and real authenticated Express routes. They cover privacy, direct grants/RLS, foreign owners, quotas, durable acknowledgement, retries, stale recovery/refunds, optimistic style versions, restoration, retention, deletion and account cascade. AI calls use fixtures; the request contract is tested.

The exported JavaScript runs in an isolated in-memory DOM fixture for create/edit/delete, whitespace-required validation, searching, status filtering, preview isolation, storage failure and all starters. This is not a real-browser test. ZIP integrity is checked separately using Python zipfile.

Flutter tests cover starter/idea/build flows, AI consent denial, stable retries, polling, completed replay, failed-instruction recovery, styling/restoration, deletion/export, account changes, private-dialog cleanup and late downloads. Phone/desktop layouts are tested at 320, 390 and 1440 px at 125% text; actual Flutter screen captures are inspected. Test captures use a preview placeholder, not an actual browser-rendered app. Focused analysis and the production Flutter web build must pass.

Browser verification of a local data-URL fixture was blocked by the cloud browser's URL policy; no workaround was used. Consequently, the live signed-in browser preview and actual OpenAI generation are remaining owner acceptance checks. No owner token is extracted, owner impersonation performed or owner generation allowance spent by the assistant.

Deploy the migration first, backend second, frontend third. Use the existing Render services and release branches with auto-deploy disabled. No service plan, credentials or unrelated migration changes are required.

## Market references reviewed 2026-09-27
- Bolt QuickStart: https://support.bolt.new/building/quickstart — interactive preview, version restore, editing and publishing flow.
- Lovable Plan mode: https://docs.lovable.dev/features/plan-mode — editable plans and retained planning history.
- Replit App Testing: https://docs.replit.com/features/agent/app-testing — actual-browser interaction checks and automated fixes.

These sources informed the priorities. This release adds a substantial creation workspace but does not claim the competitors' hosted databases, automatic deployment or browser-testing infrastructure.
