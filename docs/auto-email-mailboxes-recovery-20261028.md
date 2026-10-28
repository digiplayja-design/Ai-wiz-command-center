# Auto-Email mailbox connections: recovery checkpoint

Date: 2026-10-28

## Publication status

The implementation was completed locally and checked, but the execution environment disconnected during the final mobile browser check. This checkpoint preserves the applied database migration and implementation/release notes. It does **not** include the unpublished backend or frontend implementation files; recover those from the workspaces below when the execution environment is available.

Do not deploy this checkpoint branch as a completed mailbox release. The release branch was rechecked after the interruption and still points to `7c76d20b2633d65faa41684af4bb2ef1b81e1cf3`. No release ref, Render configuration, provider registration, real provider consent, sending rule, subscription or Site publication was changed for this increment.

The sole external change is the additive service-only Supabase schema described below. There were zero mailbox and flow rows after migration. Mailbox OAuth remains default-off and the existing approved owner/agent restriction remains in force.

## Workspaces to recover

- Backend: `/workspace/scratch/5fac34a0e68d/korlix-mailboxes`, local branch `feature/auto-email-mailboxes-20261028`.
- Site: `/workspace/sites/korlix-auto-email`.
- Backend base: local `38cf569` has the same tree as remote `7c76d20b2633d65faa41684af4bb2ef1b81e1cf3`; remote base tree is `855c79418ed4faaeed06e570cb7e35ec831a2c1b`.
- Current Site source: `7731b3fc570a7f4fae0e30ca263408cb2ca5cfd7`.
- Site project: `appgprj_6ae11f671bc08191a17a11f643d84310`.
- Site URL: https://korlix-auto-email-by-voice.silkyhinny128.chatgpt.site
- Render service: `srv-d8csvkkp3tds73emfikg`, workspace `tea-d8cskuf7f7vs73emq1p0`.
- Render release branch: `release/signup-plan-intent-20261021`; automatic deployments are disabled.

The existing Site audience was verified owner-private and must remain unchanged. Preserve the original KORLIX face/circuit emblem in lime green, with pearl/champagne/deep-green aesthetics.

## Database migration already applied

Remote Supabase project: `uxtjzjbwtppjvnsoiijv`.

Applied migration: `20261028022242_auto_email_mailbox_connections.sql`. It was created with the Supabase CLI locally, applied using the migration tool, and the local filename/test reference was aligned to the remote migration version. **Do not apply it a second time.**

Tables:

- `korlix_auto_email_mailboxes`: owner/agent/provider binding, connection generation, verified public identity, scopes, encrypted credential envelope.
- `korlix_auto_email_mailbox_flows`: expiring device-bound OAuth attempts, hashed state/browser binding, encrypted PKCE or token material, review/confirmation status.

Service-only functions:

- `korlix_auto_email_mailbox_begin(jsonb)`
- `korlix_auto_email_mailbox_confirm(uuid,text,text,uuid,jsonb)`
- `korlix_auto_email_mailbox_disconnect(uuid,text,text)`
- `korlix_auto_email_mailbox_cleanup()`

Post-migration checks confirmed both tables have RLS enabled, anon/authenticated have no CRUD grants, service_role has CRUD grants, anon/authenticated have no execute on the four functions, and service_role has execute. Functions are SECURITY INVOKER with fixed `search_path=public, pg_temp`. No public-client RLS policies are intentional: these are backend service-only credential tables. Security advisors returned only the expected informational [RLS enabled without policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) findings for these two tables.

## Locally implemented backend

New files:
- `backend/auto_email/mailbox-security.mjs`
- `backend/auto_email/mailbox-providers.mjs`
- `backend/auto_email/mailbox-store.mjs`
- `backend/auto_email/mailboxes.mjs`
- `backend/test/auto_email_mailboxes.test.mjs`
- `backend/test/auto_email_mailbox_schema.test.mjs`

Modified:
- `backend/server.js`: register mailbox routes after supabaseAdmin initialization.
- `backend/security/auto_email_app.mjs`: exact companion route whitelist; capabilities version 3 and mailbox OAuth readiness.
- `backend/auto_email/voice.mjs`: voice directs mailbox management to Connections and still cannot send.

The implementation uses a same-tab bootstrap with a secure HttpOnly SameSite=Lax browser cookie; HMAC proof contains only the browser nonce hash. The authenticated start binds owner, agent, device and provider. Both providers use single-use state and PKCE S256. Token exchange, identity lookup and storage are server-side only. AES-256-GCM binds ciphertext to its owner/agent/provider and, for pending flows, its flow and device.

Google identity comes from the authenticated OpenID userinfo resource, with verified email. Microsoft identity comes from Graph /me with an actual mail address; no JWT claims are trusted as identity evidence. Microsoft currently supports work/school accounts via organizations or a configured tenant GUID. The configured authority is not represented as a discovered tenant identity.

After provider consent, the flow enters review. The user must explicitly confirm the returned sender identity before the database activates the connection. Generation checks and row locking prevent older attempts or late callbacks from restoring a disconnected/replaced connection. Disconnect purges stored credentials and unfinished attempts. It does not revoke the provider's separate consent grant; the UI says to remove that in provider app permissions if desired.

Pending flows expire after ten minutes. Best-effort cleanup runs on API activity and at startup/every sixty seconds in the backend process. Expired attempts cannot be used even before cleanup runs. There is no pg_cron installation; physical cleanup after a service outage waits for restart. Flow metadata is purged after a day.

No token-refresh delivery worker, Gmail send operation or Graph sendMail operation was added. Connection status means linked identity, not continuous provider-health monitoring. Existing sending and schedule mutation restrictions remain intact.

## Required activation configuration

No environment variables or credentials were changed. Provider readiness must be determined from the new API after deployment, not inferred from existing calendar/marketing OAuth.

Use dedicated KORLIX-owned confidential Web application registrations and exact callbacks:

- Google: https://chee-chai-chee-backend.onrender.com/api/auto-email/mailboxes/oauth/google/callback
- Microsoft: https://chee-chai-chee-backend.onrender.com/api/auto-email/mailboxes/oauth/microsoft/callback

Google scopes: `openid`, `email`, `https://www.googleapis.com/auth/gmail.send`, with offline access. Enable Gmail API. Complete applicable production verification, privacy/support and domain requirements before broad release.

Microsoft scopes: `offline_access`, `https://graph.microsoft.com/User.Read`, `https://graph.microsoft.com/Mail.Send`. Organizational consent policies may require administrator approval. Personal Microsoft accounts and shared mailboxes are not supported by this increment.

Configuration names, with no secrets in source:

```dotenv
KORLIX_AUTO_EMAIL_MAILBOX_OAUTH_ENABLED=false
KORLIX_AUTO_EMAIL_TOKEN_KEY=
KORLIX_AUTO_EMAIL_GOOGLE_CLIENT_ID=
KORLIX_AUTO_EMAIL_GOOGLE_CLIENT_SECRET=
KORLIX_AUTO_EMAIL_MICROSOFT_CLIENT_ID=
KORLIX_AUTO_EMAIL_MICROSOFT_CLIENT_SECRET=
KORLIX_AUTO_EMAIL_MICROSOFT_TENANT=organizations
KORLIX_AUTO_EMAIL_APP_ORIGIN=https://korlix-auto-email-by-voice.silkyhinny128.chatgpt.site
KORLIX_AUTO_EMAIL_API_ORIGIN=https://chee-chai-chee-backend.onrender.com
```

TOKEN_KEY must be separately generated 32-byte key material encoded as 64 hex characters and stored in the backend secret environment. Do not put it in the frontend, logs, browser storage, git or chat. Key rotation needs a deliberate re-encryption/reconnection process.

Customers would connect their work mailbox directly and would not configure Resend. This checkpoint does not claim registration, live consent or sending is operational.

## Locally implemented frontend

New `dist/mailbox-navigation.js` validates fixed Google/Microsoft/API destinations, preserves only provider/user/flow intent in sessionStorage, rejects unsolicited or mismatched callback fragments, and never stores provider credentials.

Modified `dist/korlix-api.js`, `dist/live-workspace.js`, `dist/app.js`, `dist/styles.css`, `package.json` and local fixture. New `test/mailbox-navigation.test.js`, plus mailbox API restrictions test in `test/korlix-api.test.js`.

Connections has provider availability, a three-step guide, explicit sender review, disconnect confirmation and honest unavailable/error states. Real Connect actions are shown only when backend configuration is ready. Signed-out preview routes users to KORLIX sign-in.

**Remove temporary `dist/qa-mailboxes.html` and `dist/qa-mailboxes-mobile.html` before packaging.** Retain only the test fixture under `test/fixtures/connected-workspace.html`, outside the deployed directory. Do not commit `supabase/.temp/`.

Desktop screenshot was written by the cloud browser to `/home/oai/share/korlix-mailbox-preview.jpg` (normally mirrored to `/workspace/scratch/korlix-mailbox-preview.jpg`). The execution environment disconnected before its nonempty mirrored file could be verified or copied to the Site repository. Verify the file before linking it. It shows sample data, not real provider authorization.

## Verification completed

- 65 backend tests passed across mailbox HTTP/security, real PGlite migration execution, voice, Auto-Email app isolation and existing auth/companion regressions.
- Affected mailbox/voice suites passed again after small final error-copy changes.
- 21 frontend tests passed.
- JavaScript syntax and git whitespace checks passed.
- Real Supabase grants/RLS/function settings checked as above.
- Desktop browser QA exercised provider-awaiting-activation details, verified sender review, explicit confirm and disconnect using an injected sample API.
- Mobile Connections navigation and accessible content were checked in a 390 px frame. The final mobile screenshot failed when the environment disconnected, so final mobile visual QA is incomplete.
- No real account credentials, microphone session, provider consent or email sending were exercised for this increment.

Backend test log before interruption: `/workspace/scratch/5fac34a0e68d/mailbox-backend-tests.log`.

## Resume and release

1. Restore the workspaces, inspect local diffs, and verify the above files still exist. This checkpoint is not a substitute for recovering the implementation.
2. Finish mobile visual QA and verify/save the screenshot. Update Site README, docs/INTEGRATION.md and docs/MAILBOX_CONNECTIONS.md from planned to implemented-but-inactive. Add the names-only disabled configuration to backend/.env.example.
3. Keep the migration version aligned to 20261028022242. Do not rerun the applied migration.
4. Commit the full reviewed backend implementation on the feature branch, with remote parent 7c76d20b2633d65faa41684af4bb2ef1b81e1cf3. Protect release updates with expected_sha; inspect any conflicting head.
5. Deploy the exact commit to the existing Render service. Verify health, capabilities, unauthenticated rejection, callback security headers and CORS for the actual Site.
6. Remove temporary deployed fixtures. Use Sites source workflow to push the exact Site source and package its dist output, then publish the existing private Site and verify terminal success.
7. Report implementation and publication honestly. Provider activation and business sending remain separate pending milestones.

## Primary references reviewed

- https://developers.google.com/identity/protocols/oauth2/web-server
- https://developers.google.com/identity/openid-connect/openid-connect
- https://developers.google.com/workspace/gmail/api/auth/scopes
- https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification
- https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow
- https://learn.microsoft.com/en-us/graph/permissions-reference#mail-send
- https://learn.microsoft.com/en-us/entra/identity-platform/access-tokens
