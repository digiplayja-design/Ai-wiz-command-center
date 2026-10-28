# Auto-Email mailbox connections

This increment adds Google Workspace/Gmail and Microsoft 365 authorization to the existing approved Auto-Email owner/agent pilot. Customers can connect an existing mailbox without entering Resend credentials. The feature is disabled by default; provider registration and real consent testing are still required. Linking a mailbox does not enable sending or scheduling.

## Implemented flow

1. The signed-in user chooses a provider from Connections. A top-level visit to the fixed backend bootstrap sets a secure HttpOnly SameSite=Lax browser cookie and returns a short-lived HMAC proof containing only its hash.
2. The authenticated start binds the owner, agent, device and provider. The backend creates expiring single-use state and a PKCE verifier, then returns a fixed provider authorization URL. The browser retains only account/provider/flow intent in sessionStorage.
3. The callback requires the same browser cookie, claims the state once, exchanges the code server-side and retrieves the account identity from the provider's authenticated resource endpoint. Provider tokens are never returned to the browser.
4. The user reviews the verified sender address and explicitly confirms it. A transaction activates only the current, unexpired flow and destroys pending credentials.
5. Disconnect deletes locally stored credentials and cancels unfinished attempts. The separate Google/Microsoft consent grant remains until removed in the provider's account permissions, as explained in the UI.

Both providers use PKCE S256. Google identity requires a verified email from OpenID userinfo. Microsoft identity requires an actual mailbox address from Graph `/me`; ID/access tokens are opaque and their unverified JWT claims are not trusted. Microsoft supports work/school accounts through `organizations` or an explicitly configured tenant GUID. Personal Microsoft accounts and shared mailboxes are outside this release. A configured authority is not represented as a discovered tenant identity.

## Storage and isolation

Applied Supabase migration: `20261028022242_auto_email_mailbox_connections.sql` in project `uxtjzjbwtppjvnsoiijv`. Its filename matches the remote migration ledger. Do not apply it again.

`korlix_auto_email_mailboxes` and `korlix_auto_email_mailbox_flows` have RLS enabled with no client policies. Anon and authenticated roles have neither table CRUD nor function execution; the backend service role has the necessary grants. The four mutation/cleanup functions are SECURITY INVOKER with a fixed search path. The security advisor's informational [RLS without policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) finding is expected for these service-only tables.

AES-256-GCM ciphertext is bound to owner/agent/provider and, for pending flows, flow/device. Row locks and a monotonically increasing connection generation prevent old callbacks or confirmations from restoring a disconnected/replaced connection. Only the existing approved owner/agent can access these endpoints; a general KORLIX sign-in is insufficient. Exact companion-session route/method restrictions deny legacy sending/approval, scheduling and unrelated app access. The later reviewed-delivery increment adds only its dedicated review/submit routes.

Pending attempts expire after ten minutes. Cleanup runs on API activity and best-effort at startup/every sixty seconds in the backend process. Expired attempts cannot be used before cleanup. An outage can delay physical cleanup until the backend restarts; no database cron was installed. Flow metadata is purged after one day. Token key rotation needs a separate re-encryption or reconnection procedure.

## Activation

Use dedicated KORLIX-owned confidential **Web** provider app registrations. Do not reuse calendar, marketing or social grants as mailbox authorization. Register these exact redirect URLs:

- Google: `https://chee-chai-chee-backend.onrender.com/api/auto-email/mailboxes/oauth/google/callback`
- Microsoft: `https://chee-chai-chee-backend.onrender.com/api/auto-email/mailboxes/oauth/microsoft/callback`

Google requests `openid`, `email` and `https://www.googleapis.com/auth/gmail.send` with offline access. Enable Gmail API and complete applicable production verification, privacy/support and domain requirements before broader release.

Microsoft requests `offline_access`, `https://graph.microsoft.com/User.Read` and `https://graph.microsoft.com/Mail.Send`. Tenant consent policy can require administrator approval. The code rejects missing sending/identity scopes, missing refresh access and grants that include inbox reading/composition. Validate the actual consent and returned grant with the approved pilot account before widening availability.

The names-only configuration is in `backend/.env.example`. Set the dedicated client ID/secret for each supported provider and a separately generated 32-byte `KORLIX_AUTO_EMAIL_TOKEN_KEY` represented as 64 hex characters in the backend secret environment. Origins must be fixed HTTPS origins. Only then set `KORLIX_AUTO_EMAIL_MAILBOX_OAUTH_ENABLED=true`. Never put secrets in frontend assets, browser storage, git, logs or chat. No Render variables or provider registrations were changed by this implementation.

`GET /api/auto-email/status` reports configuration readiness as `mailboxOAuth`; this is not evidence of live provider consent. Authenticated `GET /api/auto-email/mailboxes` reports each provider's readiness and stored connection metadata. The UI displays Awaiting activation when unavailable. A linked connection is not continuous proof that a provider still accepts its credentials.

## Validation and release boundaries

65 backend tests passed, including mocked HTTP OAuth exchanges and real PGlite execution of the migration, callback replay/browser/account isolation, disconnect races, expiry and existing voice/auth/session regressions. 21 frontend tests passed. JavaScript syntax and whitespace checks passed. Supabase grants, RLS, function settings and cleanup were checked after application; the new tables contained zero rows.

Desktop and 390 px mobile browser QA exercised sample-data connection status and sender-review layouts. Desktop confirmation and disconnect used an injected fake API; no real account credentials, provider consent, microphone call or email delivery was exercised. Test fixture files are excluded from deployed assets.

Token refresh, explicitly reviewed delegated sending and a durable outbox were subsequently added in `auto-email-delivery-20261028.md`, and remain gated pending activation. Provider delivery reconciliation and automatic job execution remain unimplemented. General business release also needs business workspaces, member roles, mailbox ownership, plan entitlements, approved sending policies, bounded retries and delivery audit history. The main KORLIX website and existing sender/recipient consent were not changed.

## Primary references

- [Google web-server OAuth](https://developers.google.com/identity/protocols/oauth2/web-server)
- [Google OpenID identity](https://developers.google.com/identity/openid-connect/openid-connect)
- [Gmail scopes](https://developers.google.com/workspace/gmail/api/auth/scopes)
- [Google sensitive scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification)
- [Microsoft authorization-code flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow)
- [Microsoft Graph permissions](https://learn.microsoft.com/en-us/graph/permissions-reference#mail-send)
- [Microsoft access tokens](https://learn.microsoft.com/en-us/entra/identity-platform/access-tokens)
