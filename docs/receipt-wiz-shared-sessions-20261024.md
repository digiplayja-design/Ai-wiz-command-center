# Receipt Wiz independent sessions — 24 October 2026

## Result and current status

The backend change lets KORLIX AI and the independent Receipt Wiz app stay signed
in to the same account. Receipt Wiz has a separate installation allowance;
signing out of either app preserves the other app's login. Receipt ownership,
quotas, subscriptions and paid access remain attached to the existing account.

Implementation and local verification are complete. Ricardo explicitly approved
public GitHub publication, the database migration and backend deployment on
24 October 2026. Publication is in progress; live deployment and mobile build
results remain to be verified.

- Backend branch: `feature/receipt-wiz-shared-sessions-20261024`, based on
  `958687b3b75407863bd4011d5bce5689af101e23` (the existing duplicate-signup fix).
- Mobile validation branch: `feature/receipt-wiz-mobile-validation-20261024`,
  commit `7b21888ceea16a7c27967a86e758eaee8f35e268`, based on standalone app
  commit `51681ad2a0f7934aabdb9b868705956f6c839817`.
- Public destination: `digiplayja-design/Ai-wiz-command-center`.
- Mobile CI has not run. The new workflow builds an Android debug APK and an
  unsigned iOS simulator app. It does not sign or upload an App Store build.

## Implementation

`backend/security/receipt_app_sessions.mjs` binds a verified Supabase login's
session ID to its Receipt Wiz installation. The server consults this binding for
authenticated requests, even when an app header is changed or omitted. Companion
sessions may access the existing receipt endpoints, refresh, signout and shared
account deletion request. They cannot use hub-only paid features.

`supabase/migrations/20261024155931_receipt_wiz_app_sessions.sql` adds the
server-owned bindings table and registration function. Clients cannot read or
modify either. An account-level transaction lock serializes registration. The
allowance is Basic/Pro one, Ultra/Enterprise two; existing server-owned account
overrides and developer grants remain effective. The existing hub session table
is not modified by companion registration or signout.

Refresh preserves the provider session binding. New password sign-in replaces
only the older companion login for that same installation. Revoked bindings are
retained so an unexpired token cannot fall back to legacy hub behavior. No tokens
or passwords are stored in the new table. Disabled accounts and database failures
fail closed. Rejected fresh logins revoke the newly issued provider session.

The app already sends its installation ID and `client_app: receipt_wiz`; no Dart
changes are required for this backend behavior. Existing unbound standalone
sessions must sign in again. Physical testing should use fresh companion sessions;
older alpha installations may have a legacy hub registration to sign out first.

## Verification

Node syntax and whitespace checks passed. The following combined command passed
**246 tests, zero failures, zero skipped**, against local synthetic accounts.
The new session tests execute the actual migration in PGlite and actual server
authentication handlers with a simulated identity provider.

```bash
cd backend
node --check server.js
node --test \
  test/receipt_wiz.test.mjs test/receipt_app_sessions.test.mjs \
  test/auth_session_security.test.mjs test/final_auth_security.test.mjs \
  test/signup_eligibility.test.mjs test/receipt_wiz_signup.test.mjs \
  test/account_deletion_rehearsal.test.mjs test/chat_memory.test.mjs \
  test/chat_quality.test.cjs test/logo_studio.test.cjs test/logo_jobs.test.mjs \
  test/social_reactions.test.mjs test/social_online_push.test.mjs \
  test/pod_small_talk.test.mjs test/pod_routes.test.mjs \
  test/pod_providers.test.mjs test/pod_runtime.test.mjs
```

The 15 new session cases cover both sign-in orders, independent limits, refresh
and process restart, header changes, logout in both directions, colliding device
IDs, replaced and revoked tokens, disabled accounts, database failures, concurrent
registration, trusted overrides, table/function permissions, confirmed signup and
route restrictions. Existing auth/account-deletion test fixtures now include the
real shared developer-access and companion-session helpers; assertions remain.

These checks do not substitute for a real Supabase authentication round trip,
physical phone testing, or signed mobile distribution.

## Approved release sequence

1. Push the two feature branches to the existing repository. Monitor **Receipt
   Wiz mobile validation**; inspect Android and iOS build artifacts and resolve
   any platform-specific failures before distributing them.
2. Recheck the live backend's configured release branch and current commit.
   At inspection, `release/signup-plan-intent-20261021` and Render's live backend
   both pointed to `f14546a7b8a5a0614e542f4628bc480beab5d885`. Do not overwrite
   concurrent work or deploy the frontend branch as backend code.
3. Apply the additive migration to the existing Korlix AI Supabase project using
   the connected Supabase migration tool. Verify the table, RLS, service-role
   permissions and registration function, then review security advisories.
   **The migration must precede the new backend**, since authentication consults
   the table. Do not retry the telemetry-blocked Supabase CLI.
4. Fast-forward the configured backend release branch to the tested backend
   commit. Auto-deploy was disabled at inspection; recheck it before triggering
   one deployment of the existing Render backend.
5. Wait for Render's terminal `live` status at the exact intended commit. Check
   `/api/health`, startup logs and schema-related errors. An accepted deployment
   request alone is not completion.
6. Use an authorized test account on physical devices: sign into both apps in
   both orders, scan and edit a receipt, verify shared visibility, restart and
   refresh, sign out of each independently, and check the separate device limits.
   Also test email confirmation, duplicate signup, recovery, camera permissions,
   PDF intake, export/share and VoiceOver/TalkBack.

Do not drop or purge revoked binding rows during rollback. Once companion logins
exist, reverting to a backend without the scope check would allow their JWTs to
follow legacy hub behavior. A rollback must retain the binding authorization
guard (and can disable new companion sign-ins) until those sessions are safely
revoked and expired. Store signing, independent store records, privacy disclosures
and owner device acceptance remain separate release prerequisites.
