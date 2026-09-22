# KORLIX Workforce — first release

Status: implemented and locally verified; production migration and deployment are pending. This is the attendance and work-progress release. No real employees have been invited, photographed or contacted during development.

## Experience

Utility → Workforce opens the employer/employee workspace. Enterprise owners create a workspace and issue one-use, email-bound invitation codes. Invited employees use their existing account and do not require a separate Enterprise subscription. Owners manage roles and individual policies; managers oversee their own workspace; employees see only their own records.

- Employer overview: current attendance, breaks, employee-reported output, overdue updates, searchable roster and team filters.
- Employee My day: clock-in/out, break/resume, working-time timer, output goal, work updates and attendance timeline.
- Optional required attendance selfie and location stamps on clock-in/out. Photos are evidence for human review, not facial recognition or liveness verification. Location is captured on request; there is no background tracking.
- Worksite coordinates, accuracy and geofence exceptions; missing evidence can be explained. Clock-out remains available when evidence is missing or the employer's plan expires.
- Per-workspace and individual employee rules. Default work-update cadence is 60 working minutes plus a ten-minute grace period; breaks pause the reminder. Settings are captured at shift start.
- Written or device-dictated work updates with completed units, project/customer and blockers. Quantities are self-reported, not an automatic employee performance score.
- Shift schedules, correction requests, manager review, immutable attendance events and an audit history. A different manager must review a manager's own correction or timesheet.
- Date filters, full-shift CSV exports and separate approval status. Exports are review inputs; this release does not calculate legal overtime or payroll deductions.
- Team brief from recorded data and an authenticated handoff to the existing NOVA Email Center's draft service. Recipient selection comes from the owner's existing approved recipients. No send operation is called.

## Scope boundaries

Hourly reminders currently appear inside Workforce while the screen refreshes. Background notifications, scheduled autonomous reminder emails, outbound-call escalation, offline punch synchronization, direct payroll integrations and automatic work-output integrations are follow-on work. Existing autonomous outbound calling remains disabled. The team brief is a factual template, not a new AI model call.

The browser camera may present a platform-specific capture/file chooser. Real iPad/iPhone camera, location, speech-input, sharing and app-switch behavior still need an authenticated device acceptance check. Photos are never treated as proof of identity. Capture denial has an exception path.

## Backend and database

- Endpoints: `/api/workforce/workspaces`, `/accept-invite`, `/:org`, `/:org/commands`, `/:org/punch`, `/:org/photos/:event`, `/:org/export`, `/:org/brief`, `/:org/email-recipients`, `/:org/email-draft`, `/:org/audit`.
- All endpoints require the existing verified session. Owner/employee identifiers from request bodies do not establish authority. Enterprise entitlement is checked from the owner's current server-side profile.
- Ten `korlix_workforce_*` tables: organizations, memberships, invites, shifts, events, updates, corrections, schedules, audit and staged photo uploads. RLS is enabled; direct anon/authenticated grants are revoked. The single SECURITY INVOKER command RPC is executable only by service_role.
- Server timestamps, organization/user transaction locks, a global one-open-shift constraint, version checks and request IDs protect attendance transitions and retries.
- Report date boundaries use the workspace IANA timezone. Output totals use updates inside the period. Time exports contain full overlapping shifts; open shifts are separately available for attendance controls when looking at past reports.
- Private `korlix-workforce-evidence` bucket; normalized JPEG images up to 512 KiB; backend-mediated authorized reads; no public or client Storage policy is added. Existing production Storage object policies were read-only inspected and were empty during development.
- Photo and location access expires immediately at the retention deadline. An hourly backend cleanup deletes expired evidence in batches; cleanup resumes when the backend is running. Staged uploads older than 24 hours are checked against committed events before orphan cleanup. Database events retain attendance facts after evidence removal.
- Test-only PGlite is a dev dependency, excluded from production Docker installation.

Migration: `supabase/migrations/20260922000006_enterprise_workforce.sql`.

## Verification

- `cd backend && npm ci && npm run test:workforce`: 8 tests using isolated PostgreSQL (PGlite) and HTTP routes, covering entitlement, invitation binding/reuse, role/company isolation, RLS/grants, clock-in idempotency, breaks, stale versions, plan lapse, corrections, overlapping schedules, expired evidence and identity spoofing.
- Existing CRM backend regression suite: 10 tests passed.
- `flutter test test/workforce`: 10 tests, including employee/employer layouts at 390, 768 and 1440 logical pixels, all employer tabs, editable form error retention, missing-evidence clock-out, and clearing employee data after session expiry.
- `flutter analyze lib/workforce test/workforce`: no issues.
- `flutter build web --release --no-wasm-dry-run`: successful with Flutter 3.47.5 / Dart 3.13.4. No new Flutter dependencies.
- Preview screenshots are rendered from the Flutter implementation with fictional team records and the official KORLIX logo. Optional screenshot test inputs: `KORLIX_WORKFORCE_SCREENSHOTS=1`, `KORLIX_FLUTTER_ROOT`, and `KORLIX_SCREENSHOT_DIR`.

## Rollout order

1. Review the paired backend/frontend changes against the existing release branches.
2. Apply this migration once to the Korlix AI Supabase project. Verify private bucket, RLS and RPC grants. Do not reapply the already-live CRM migration.
3. Deploy backend on the existing manual Render service; verify health and anonymous Workforce rejection.
4. Deploy frontend on the existing manual Render static site.
5. Sign in as an Enterprise owner, create a pilot workspace, invite a separate verified employee and exercise clock-in, break, update, clock-out, correction and expiry paths on the user's iPad. Confirm a basic non-member cannot access organization records and an employee cannot read another employee's photo.
6. Prepare a draft to an already-approved internal NOVA Email recipient and review it without sending. Do not enable outbound calling as part of this release.

Rollback: restore previous frontend/backend deployments. Keep the additive Workforce schema and any recorded attendance data; do not drop live time records to roll back the UI.
