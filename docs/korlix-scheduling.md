# KORLIX Scheduling — initial release

Verified, active KORLIX accounts can open **Scheduling**, save availability, create a draft event type, and explicitly publish its public booking link. Enterprise users can also open their existing Funnel Studio and Contacts CRM from the dashboard. Sharing a link into those products is manual; this release does not automatically create CRM contacts or trigger marketing campaigns.

## Included

- KORLIX booking pages, desktop and mobile layouts, one-to-one and capacity-limited group appointments.
- IANA time zones, daylight-saving handling, split working hours, date overrides, buffers, minimum notice, booking horizon and daily session limits.
- Cross-event conflict checks for the same host, unavailable time blocks and atomic capacity allocation.
- Required or optional text/choice intake questions; HTTPS meeting links or manually supplied phone/location instructions.
- Private guest links for viewing, cancellation and atomic rescheduling; explicit confirmation and change cutoffs.
- Calendar-file download, CSV export, booking search/filtering, completed/no-show statuses and audit records.
- Host-opted-in booking confirmations, changes and one guest reminder through the existing Resend account. Default: off. Enable in **Availability → Email settings** after saving availability.

Calendar conflicts currently cover **KORLIX bookings and manual blocks**. Outside appointments must be entered as blocks. An imported ICS file is a calendar snapshot, not two-way calendar sync.

## Security and delivery

Owner API routes verify a non-anonymous, email-confirmed Supabase session on every request. All scheduling tables have RLS enabled and no browser-role table/function privileges. Service-only invoker RPCs use a fixed search path and enforce ownership. Mutations serialize on the existing host profile row and validate revisions. Booking contexts bind a short-lived hashed token to an HttpOnly SameSite cookie and the reviewed event/profile revisions.

Guest management uses a random 256-bit capability, supplied in POST bodies or a URL fragment. The database stores its hash; an AES-256-GCM sealed copy supports email delivery. Tokens and rendered email bodies are encrypted with `KORLIX_SCHEDULING_TOKEN_KEY` (base64, 32 bytes). Do not rotate this key without re-encrypting outstanding bookings and queue payloads. Public projections never include ciphertext, token hashes, ownership identifiers or queue recipient addresses.

Email readiness requires `RESEND_API_KEY`, `KORLIX_AGENT_EMAIL_FROM` and the scheduling encryption key. The backend polls a durable database queue every 30 seconds while running. A worker claim uses a three-minute lease, revalidates booking revision/host state, checks the host's current verified email through Auth Admin, and stores an encrypted immutable provider payload before submission. Retries reuse the same payload and idempotency key. At most five attempts occur within a conservative 20-hour window; ambiguous results become `uncertain` rather than being blindly resent after the provider's 24-hour deduplication window. `accepted` means the provider accepted the email, not that it reached the inbox. No delivery webhook or bounce suppression is implemented yet.

Operational email limits are 100 per host, 1,000 total and 20 guest-recipient updates per rolling day. A group confirmation consumes one host and one guest message. Excess messages remain queued; expired meeting updates are skipped. A configured reminder is scheduled only if its due time is in the future at booking/change time. Disabling email skips pending updates but cannot recall an in-flight submission. Changing settings does not backfill old bookings. No SMS is sent. Guest addresses are self-reported; the form includes consent and a honeypot, but no verified-email challenge/CAPTCHA yet.

Public links currently use the backend origin `/book/<slug>`. `KORLIX_SCHEDULING_PUBLIC_URL` can configure an HTTPS origin serving the same backend. Embedding is a website button/link, not a universal iframe widget. Page CSP restricts framing. Public booking privacy relies on keeping management links private; links expire 30 days after the appointment ends.

## Operational limits

200 event types, 500 active time blocks, 60 date overrides and six intake questions per host/event as applicable. Dashboard/export load at most 500 bookings from the past 90 days and upcoming schedule. Daily session limits count the host's non-canceled sessions across all event types; a group session counts once. Bookings are stored beyond this dashboard window; retention/deletion automation is not included. The current API does not support multi-host accounts, pooled calendars or external calendar holds.

## Verification

Run `node --test backend/test/scheduling.test.mjs` from the repository root (PGlite dev dependency), and `flutter test test/scheduling_test.dart` in the frontend release checkout. Tests cover cross-owner denial, browser-role privileges, revisions, concurrent capacity, stable booking retries, DST gaps/folds and narrow windows, private guest changes, intake validation, queue deduplication/retries, encrypted capabilities, opting in and session invalidation.

A local Chromium fixture also exercises booking, private-link reload, rescheduling and cancellation at 1366px and 390px with no horizontal overflow or browser errors. Local email tests use a fake provider. No customer appointment or live email is created as part of deployment verification. Production checks verify deployed commit IDs, health, public assets, unauthorized API behavior and database grants. Live inbox delivery and authenticated production acceptance remain unverified until a host performs an opted-in booking.

## Rollout

Apply `20260930152919_scheduling_engine.sql` before the new backend. Add only the dedicated scheduling token key to the existing Render backend environment; preserve existing variables. Deploy backend and frontend release branches. The additive migration does not enable email or publish any booking page for existing users. A rollback can restore the prior application commits while retaining the new tables and all bookings; avoid dropping data. If email processing must stop during an incident, remove the scheduling token key from the runtime only after securely preserving it for recovery, or set host notifications off through the owner API. A planned process restart may delay reminders; queue state persists.
