# KORLIX 2MEETU — connected release

Verified, active KORLIX accounts can open **KORLIX 2MEETU**, save availability, create a draft event type, and explicitly publish its public booking link. Enterprise users can also open their existing Funnel Studio and Contacts CRM from the dashboard. Sharing a link into those products is manual; this release does not automatically create CRM contacts or trigger marketing campaigns.

## K-Nova in LIVE CONVO

**Talk to K-Nova** opens a dedicated signed-in 2MEETU conversation. Regular LIVE CONVO also offers the scheduling tools; Inventory voice remains isolated. The existing microphone, voice/language controls, account checks and voice usage limits apply.

- Ask for upcoming confirmed appointments or the event types available in 2MEETU. Results contain at most 100 event types and 100 upcoming bookings, identify truncated results, and omit guest email, intake answers, private management tokens and connection credentials.
- Ask for available times for a published event type. The backend checks enabled calendars and current scheduling rules. Returned slots are possibilities, not reservations.
- Ask to prepare an unpublished free booking-page draft, change weekly availability, or reschedule/cancel a specific future booking you organize. These use the existing immutable AI proposal workflow and its ten-proposals-per-day limit.

The voice model has no apply tool. A prepared change is displayed and read back with its exact effect and relevant local dates, times and timezone. Approve the displayed proposal or, after the readback finishes, say **“Confirm scheduling change.”** Generic agreement does not approve a scheduling change. Pause, Stop, account/session changes and replacement proposals invalidate pending voice approval. The server rechecks ownership, revisions and applicable calendar conflicts when applying. A timeout is not reported as success; the client checks the original proposal's status before offering a retry.

This phase does not create a new guest appointment by voice or expose voice controls on public booking pages. Publishing pages, payments/refunds, calendar connections and team administration remain in their existing screens. Booking changes retain the host's existing notification settings; the confirmation explains when enabled booking emails will be queued.

Device acceptance: on iPad, open 2MEETU → Talk to K-Nova, start the microphone, ask for your next appointment and real available times, then prepare a harmless unpublished draft and confirm it. Verify the draft in Event types. Also prepare a change and dismiss it or pause before confirmation; it must remain unapplied. Live voice acceptance requires the host's own signed-in device test.

## Included

- KORLIX booking pages, desktop and mobile layouts, one-to-one and capacity-limited group appointments.
- IANA time zones, daylight-saving handling, split working hours, date overrides, buffers, minimum notice, booking horizon and daily session limits.
- Cross-event conflict checks for the same host, unavailable time blocks and atomic capacity allocation.
- Required or optional text/choice intake questions; HTTPS meeting links or manually supplied phone/location instructions.
- Private guest links for viewing, cancellation and atomic rescheduling; explicit confirmation and change cutoffs.
- Calendar-file download, CSV export, booking search/filtering, completed/no-show statuses and audit records.
- Host-opted-in booking confirmations, changes and one guest reminder through the existing Resend account. Default: off. Enable in **Availability → Email settings** after saving availability.

Calendar conflicts cover KORLIX bookings and manual blocks, plus Google/Microsoft calendars the host has connected and enabled. An imported ICS file remains a snapshot; host calendar updates use the connected-provider workflow described below.

## Security and delivery

Owner API routes verify a non-anonymous, email-confirmed Supabase session on every request. All scheduling tables have RLS enabled and no browser-role table/function privileges. Service-only invoker RPCs use a fixed search path and enforce ownership. Mutations serialize on the existing host profile row and validate revisions. Booking contexts bind a short-lived hashed token to an HttpOnly SameSite cookie and the reviewed event/profile revisions.

Guest management uses a random 256-bit capability, supplied in POST bodies or a URL fragment. The database stores its hash; an AES-256-GCM sealed copy supports email delivery. Tokens and rendered email bodies are encrypted with `KORLIX_SCHEDULING_TOKEN_KEY` (base64, 32 bytes). Do not rotate this key without re-encrypting outstanding bookings and queue payloads. Public projections never include ciphertext, token hashes, ownership identifiers or queue recipient addresses.

Email readiness requires `RESEND_API_KEY`, `KORLIX_AGENT_EMAIL_FROM` and the scheduling encryption key. The backend polls a durable database queue every 30 seconds while running. A worker claim uses a three-minute lease, revalidates booking revision/host state, checks the host's current verified email through Auth Admin, and stores an encrypted immutable provider payload before submission. Retries reuse the same payload and idempotency key. At most five attempts occur within a conservative 20-hour window; ambiguous results become `uncertain` rather than being blindly resent after the provider's 24-hour deduplication window. `accepted` means the provider accepted the email, not that it reached the inbox. No delivery webhook or bounce suppression is implemented yet.

Operational email limits are 100 per host, 1,000 total and 20 guest-recipient updates per rolling day. A group confirmation consumes one host and one guest message. Excess messages remain queued; expired meeting updates are skipped. A configured reminder is scheduled only if its due time is in the future at booking/change time. Disabling email skips pending updates but cannot recall an in-flight submission. Changing settings does not backfill old bookings. No SMS is sent. Guest addresses are self-reported; the form includes consent and a honeypot, but no verified-email challenge/CAPTCHA yet.

Public links currently use the backend origin `/book/<slug>`. `KORLIX_SCHEDULING_PUBLIC_URL` can configure an HTTPS origin serving the same backend. Embedding is a website button/link, not a universal iframe widget. Page CSP restricts framing. Public booking privacy relies on keeping management links private; links expire 30 days after the appointment ends.

## Operational limits

200 event types, 500 active time blocks, 60 date overrides and six intake questions per host/event as applicable. Dashboard/export load at most 500 bookings from the past 90 days and upcoming schedule. Daily session limits count the host's non-canceled sessions across all event types; a group session counts once. Bookings are stored beyond this dashboard window; retention/deletion automation is not included. The connected release adds multi-host routing and selected external calendars; it does not create temporary holds in external calendars.

## Verification

Run `node --test backend/test/scheduling.test.mjs` from the repository root (PGlite dev dependency), and `flutter test test/scheduling_test.dart` in the frontend release checkout. Tests cover cross-owner denial, browser-role privileges, revisions, concurrent capacity, stable booking retries, DST gaps/folds and narrow windows, private guest changes, intake validation, queue deduplication/retries, encrypted capabilities, opting in and session invalidation.

A local Chromium fixture also exercises booking, private-link reload, rescheduling and cancellation at 1366px and 390px with no horizontal overflow or browser errors. Local email tests use a fake provider. No customer appointment or live email is created as part of deployment verification. Production checks verify deployed commit IDs, health, public assets, unauthorized API behavior and database grants. Live inbox delivery and authenticated production acceptance remain unverified until a host performs an opted-in booking.

## Connected scheduling release — 2026-09-30

This release adds the four previously unfinished areas. Provider activation is a separate gate from code deployment.

### Calendar connections

In **Connections**, a host starts OAuth, authorizes Google or Microsoft in a separate tab, returns to KORLIX, and explicitly confirms the identified account. Then **Choose calendars** selects one to five calendars per connection for conflicts and optionally one writable calendar for appointment updates. Up to five calendar accounts can be connected. Only one write calendar is active per host.

OAuth uses a one-use handoff, hashed state, an HttpOnly browser-binding cookie, PKCE for Google/Microsoft, a ten-minute attempt lifetime, and owner confirmation. Provider grants use AES-256-GCM with a separate, identity-bound namespace under the existing scheduling key. Callback configuration changes invalidate pending attempts. Refresh-token rotation is persisted before further requests, under a database lease. Grants never reach the Flutter client or guest projections.

Availability checks fetch complete, bounded event lists, including recurring instances and all-day events. Titles and attendee lists are not cached. Stale/missing caches, pagination failures, provider outages, revoked connections, and malformed times block affected booking requests. Cache windows must match the current connection revision and be no older than 60 seconds. Slots and final reservation/rescheduling both refresh the calendars. Internal reservations remain serialized and authoritative. There is no atomic transaction across KORLIX and an external calendar; a concurrent external edit can still race the final check.

A durable worker writes host-only entries without attendees or invitations. It creates, updates, and removes entries for future KORLIX booking activity; no historical backfill occurs. Google uses a deterministic event ID; Microsoft uses a transaction ID. Creation payloads are frozen and IDs checkpointed before subsequent updates. Ambiguous creation retries stop after 15 minutes; after five unsuccessful updates the job becomes uncertain for manual review. Changes in external calendars do not reschedule the KORLIX appointment. Disconnecting stops checks and future updates; existing entries and provider-side app permissions must be managed in the provider dashboard. Calendar settings do not send customer invitations.

### Team routing

**Teams** supports owned teams, seven-day private invite codes, membership preview/consent, removal, and leaving. The owner can replace an invite code. Teams are limited to 20 active hosts; a host may own ten teams. Members must have saved verified host profiles.

Event types support single-host, round-robin, and collective routing. Round-robin chooses the available host least recently assigned within the team. Collective meetings require every selected active host. Team routing currently uses one guest per appointment; group events remain single-host. The page owner's hours define business booking hours; each assigned host must also be available. Deterministically ordered locks reserve all affected hosts and protect their other KORLIX event types. Assignment changes during locking cause a retry instead of using an unlocked host. Leaving stops new assignments; existing appointments remain visible to their assigned hosts. The organizer's email preferences govern booking email; separate assigned-host emails are not implemented. Each participating host may enable their own calendar updates.

### Booking payments

Hosts authorize their existing full-dashboard Stripe accounts in Connections through the existing OAuth flow. Readiness is verified through Accounts v2, including Stripe-managed processing fees and negative balance responsibility. Customers pay that business directly through Stripe-hosted checkout in USD using eligible payment methods configured in Stripe. This integration adds no KORLIX application fee; Stripe processing costs and account terms remain applicable. KORLIX subscriptions and payroll billing are separate.

As of 2026-10-06, new paid bookings and checkout require the explicit backend switch `KORLIX_SCHEDULING_STRIPE_ENABLED=true`; the default is off. Complete credentials still allow account connection, signed payment confirmations, reconciliation and refunds while the switch is off. Free bookings remain available. The switch does not expire checkout links already issued by Stripe; those need provider-side expiration if an emergency shutdown of outstanding sessions is required. Dedicated sandbox settings remain staged on the disabled production scheduling integration. The single isolated hosted USD 1.00 payment/refund acceptance passed; broader failure-path and production acceptance remain outstanding. See the [production readiness review](STRIPE_PRODUCTION_READINESS_20261006.md) for concrete remaining gaps and [the Connect rollout plan](STRIPE_CONNECT_NO_TRANSACTION_FEE_20261005.md) for configuration history.

Event prices are free or $0.50–$10,000 USD, with a displayed refund policy. Paid bookings must start at least 55 minutes ahead. A reservation holds capacity for 50 minutes; the checkout session expires 40 minutes after reservation. Checkout creation must begin promptly (within the first nine minutes to preserve Stripe's minimum session lifetime). Confirmation requires a server-side Stripe read matching account, booking, amount, currency, and test/live mode, followed by current calendar/host checks. The return URL is never treated as payment proof. Meeting-link details and confirmed calendar files are withheld until payment is confirmed.

Checkout requests store an encrypted immutable payload and reuse the booking's idempotency key. Signed raw-body webhooks and a polling worker reconcile payments. If the create response is lost, a signed webhook plus an independent Stripe read can restore the session association. A stale event, expired hold, removed host, or unavailable final slot produces an unfulfilled-payment record and automatic full refund request. Temporary calendar errors retry while the hold is active. Expired holds no longer block other bookings.

Cancellation alone does not refund a confirmed payment. The organizer can explicitly request **Refund full amount**, which cancels the appointment and queues a full refund. The worker uses a stable idempotency key and verifies Stripe's refund result. Unknown results are retried within a conservative 20-hour window, then flagged for manual review. Guests can view pending/succeeded/failed refund status; a request is not presented as a completed refund. Partial refunds, dispute management, tax calculation, multicurrency, subscriptions, deposits, and stored-card charging are outside this release. Handle those in Stripe. Disconnecting is blocked while current holds or refunds are pending; older payments may require direct Stripe administration afterward.

### AI scheduling

**Assistant** uses the existing GPT-6 Astra/xhigh configuration to prepare one reviewed proposal: unpublished free event drafts, weekly availability changes, actual available times, cancellation, or rescheduling. Context includes host timezone/availability, event names, and up to 100 upcoming booking names/times. Guest emails and intake answers are excluded. Requests use `store:false`; no automatic tool execution is exposed to the model.

Model output is validated through ordinary scheduling validators. The backend, not the model, queries availability and controls identifiers/revisions. Proposals are owner-bound, expire after 15 minutes, and require explicit approval; stale revisions fail closed. Applying a proposal and recording its result share one transaction. Replays do not duplicate a change. The operational cap is ten proposals per host per rolling day. AI cannot publish pages, charge/refund, connect accounts, change team membership, or send marketing messages. Ambiguous requests produce clarification instead of a mutation. Live model acceptance must still be checked in the configured production account.

### Administrator activation

Preserve the existing `KORLIX_SCHEDULING_TOKEN_KEY`. Do not rotate it without re-encrypting stored grants, booking capabilities, and queue payloads. Configure secrets only in the backend environment, never Flutter, source code, or chat.

| Provider | Backend settings | Required callback/setup |
| --- | --- | --- |
| Google | `KORLIX_SCHEDULING_GOOGLE_CLIENT_ID`, `KORLIX_SCHEDULING_GOOGLE_CLIENT_SECRET` | Web OAuth callback: `https://chee-chai-chee-backend.onrender.com/api/scheduling/connect/google/callback`; Calendar API enabled, consent configuration and production verification as required by Google |
| Microsoft | `KORLIX_SCHEDULING_MICROSOFT_CLIENT_ID`, `KORLIX_SCHEDULING_MICROSOFT_CLIENT_SECRET` | Web redirect: `https://chee-chai-chee-backend.onrender.com/api/scheduling/connect/microsoft/callback`; delegated `User.Read`, `Calendars.ReadWrite`, `offline_access`; account audience must support the intended Microsoft users |
| Stripe | `KORLIX_SCHEDULING_STRIPE_CLIENT_ID`, `KORLIX_SCHEDULING_STRIPE_SECRET_KEY`, `KORLIX_SCHEDULING_STRIPE_WEBHOOK_SECRET`; `KORLIX_SCHEDULING_STRIPE_ENABLED=false` until approved activation | Existing-account OAuth redirect: `https://chee-chai-chee-backend.onrender.com/api/scheduling/connect/stripe/callback`; **connected-account** webhook at `/api/scheduling/payments/webhook` for `checkout.session.completed`, `checkout.session.expired`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, and `charge.refunded` |
| AI | Existing `OPENAI_API_KEY` with access to the configured Astra model | No new client-side key |

Stripe requests default to API version `2026-09-30.endive`; `KORLIX_SCHEDULING_STRIPE_API_VERSION` is a dedicated override. Keep OAuth ID, API key, and webhook endpoint in the same sandbox/live context. Test mode is visibly labeled to hosts and guests. A custom scheduling public origin must serve these backend paths and be registered with each provider. `/api/scheduling/payments/health` reports configuration and checkout status without returning credentials or merchant information. Configured means settings are present, not that Stripe has been verified end to end.

Each checkout creation/retry retrieves the connected business through `/v2/core/accounts` and requires `configuration.merchant.capabilities.card_payments.status` and `configuration.merchant.capabilities.stripe_balance.payouts.status` to be `active`. The existing database field named `charges_enabled` is a projection of those checks, not a v1 readiness decision. Existing-account OAuth remains available alongside the owner-controlled Accounts v2 setup below.

### Owner-controlled Stripe business setup — 2026-10-06

In **2MEETU → Connections → Set up Stripe business**, the signed-in verified host supplies a business name and explicitly approves creating their own Stripe account. This guided rollout supports United States businesses; the backend rejects other country inputs before persisting setup. The server uses the host's verified email, creates an Accounts v2 merchant with a full Stripe Dashboard and Stripe responsible for processing fees and payment losses, and opens Stripe-hosted onboarding. No KORLIX application fee is added. Bank and verification information is entered on Stripe, not in KORLIX.

The owner returns to **Connections → Review and confirm business** for a fresh server-side identity check. A ten-minute, one-use review token binds that owner, setup, and the current connection revision. Confirmation rechecks Stripe and changes the active connection atomically. Pending verification can be saved, but cannot make payments ready. Existing merchants remain connected until explicit confirmation, and open holds, unpaid checkouts, or pending refunds prevent replacing them.

Setup is persisted before contacting Stripe. Concurrent starts and interrupted responses reuse the same frozen creation parameters, merchant and idempotency key. **Continue Stripe setup** obtains a fresh single-use hosted link after owner authentication. Public return/refresh callbacks only show instructions; neither creates a link nor changes a connection. Unknown creation results older than 29 days require administrator reconciliation before retrying, within Stripe's documented 30-day API v2 idempotency window. Configuration changes or provider rejection of immutable creation data require administrator reconciliation instead of silently creating a replacement merchant. Do not reset an uncertain attempt without reconciling its original provider request.

Apply `20261006030649_scheduling_stripe_merchant_setup.sql` before the backend. Its table and invoker RPC are service-only; browser roles cannot access stored contact emails, review hashes or account reservations. Each owner and payment mode has one durable setup, and both guided setup and existing OAuth enforce the same cross-owner merchant reservation.

Sandbox setup is available when the dedicated scheduling Stripe configuration is present. Live account creation additionally requires `KORLIX_SCHEDULING_STRIPE_ONBOARDING_ENABLED=true`; it defaults off. Checkout remains controlled independently by `KORLIX_SCHEDULING_STRIPE_ENABLED` and stays off during this rollout. `merchantSetupEnabled` in payment health means locally configured, not that provider permissions or a merchant's verification have passed.

For a restricted backend key, Stripe's [permissions reference](https://docs.stripe.com/keys/permissions-reference) lists `v2_account_storer_write` for both `POST /v2/core/accounts` and `POST /v2/core/account_links`, and `v2_account_storer_read` for account retrieval. Configure the corresponding Accounts v2 permission on the platform's dedicated scheduling key; retain the read permissions required for merchant readiness. A provider permission failure preserves setup for resumption and exposes only a sanitized administrator-setup message. Do not replace keys or broaden unrelated permissions to bypass an error.

Verification uses mocked provider I/O and real isolated PostgreSQL migrations: `node --test backend/test/scheduling*.test.mjs`; frontend: `flutter test --no-pub test/scheduling_merchant_setup_test.dart test/scheduling_connected_test.dart test/scheduling_test.dart`. Real merchant creation and hosted verification require the owner's interactive consent; deploying this flow does not perform them.

Missing settings show **Administrator setup required**, not a connected account. Credentials alone do not grant access: each host must still authorize, review, and confirm their own accounts. Real Google/Microsoft OAuth and calendar operations, real Stripe test-mode transactions/refunds/webhooks, and live AI responses are required acceptance gates before advertising those provider workflows as verified live.

### Connected-release validation and rollback

Run backend tests: `node --test backend/test/scheduling.test.mjs backend/test/scheduling_connected.test.mjs backend/test/payroll.test.mjs backend/test/social.test.mjs`. Run frontend tests: `flutter test --no-pub test/scheduling_test.dart test/scheduling_connected_test.dart test/payroll_test.dart test/social_notifications_test.dart`. Current local results: **102 backend + 34 frontend tests pass**; scheduling analysis reports no issues. Browser fixtures at 390px and 1366px verify free booking/reopening/rescheduling/canceling plus paid hold/checkout/return-without-payment/verified payment, without overflow or browser errors. Providers, payment events, and model responses in these tests are fakes; no customer messages, real charges, or real refunds are generated.

Apply the additive `scheduling_connected` migration after the original scheduling migration and before deploying this backend. All new tables have RLS enabled and browser-role privileges revoked. Functions are service-only invoker RPCs with fixed search paths. The migration does not connect accounts, publish pages, enable email, or charge anyone.

Do not roll back to the original booking engine after teams or payment holds are active: the old code does not understand those states. Prefer a forward fix. If a provider incident occurs, disable new paid event publication/booking through current settings and retain the current payment reconciliation worker until holds/refunds finish. Preserve all scheduling tables, grants, and ciphertext. Pausing event pages stops new bookings without deleting existing appointments.
