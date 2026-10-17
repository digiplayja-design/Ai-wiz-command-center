# Korlix onboarding measurement

The first campaign reported installs, while the database only established account
creation. This change records the intervening steps without changing signup,
email confirmation, device limits, or billing.

## What is measured

- Current Android releases already send an installation identifier on auth calls.
  After backend deployment, signup requests, rejections, accepted requests and
  successful sign-ins are counted. Successful sessions are associated with the
  verified account ID. Signup acceptance without a session is not account proof.
- The updated app adds process opens, fresh local app storage versus existing
  storage, registration-screen views, taps on Create account, validation problems,
  network failures and the email-confirmation screen.
- The report joins verified sign-ins to existing `generation_history` records to
  count setups whose account completed a saved AI generation. This is not coverage
  of every tool or all usage, and usage may occur on another signed-in device.
- Account totals separately count actual `auth.users` created in the window,
  email confirmation, sign-in and saved generations across all platforms.

These are **all-source product measurements**, not Google Ads attribution.
A fresh setup may be a reinstall or another device. Stage counts are distinct
setups in the same first-open cohort; returning customers may skip registration.
Authentication and error sections are request/event counts and can include retries.
No historical first-open or registration-screen activity is reconstructed.

## Access and data handling

`GET /api/admin/onboarding/summary?days=7&platform=android` requires a valid account
and its existing server-owned `korlix_developer_access` grant. The updated app
offers **Korlix Account → New user journey** to that account. Allowed windows are
the last 1, 7 or 30 rolling days; exact UTC bounds are returned. The route returns
aggregate counts only. Do not grant developer access just to share this report.

Client events use `POST /api/onboarding/events`. Event names/fields are allowlisted,
batch and rate limits apply, event UUIDs deduplicate retries, and the backend
hashes the installation identifier. Credentials, emails, age bands, prompts,
responses, device labels and IP addresses are not stored in this event table.
User IDs appear only on server-verified successful sign-in events. Raw event data
is service-role-only with RLS; public and authenticated database roles cannot read
or write it or invoke its report functions.

Client events wait in a bounded 48-event local queue, expire after seven days on
restart and retry after network failure. Server receipt time defines the window;
late delivery can shift dates. Cleanup removes event rows older than 90 days in
batches of 10,000, at most once per hour during successful ingestion. No traffic
means cleanup waits for the next ingestion. Account-linked events cascade on
account deletion; unlinked observations remain until that cleanup. Existing
account and generation-history retention is unchanged.

## Release order

1. Run `node --test backend/test/onboarding_measurement.test.mjs backend/test/signup_eligibility.test.mjs`.
2. Apply only `supabase/migrations/20261017123110_onboarding_measurement.sql` to the
   confirmed project and check security advisors. This adds a table and functions;
   it does not rewrite profiles or alter authentication.
3. Deploy this backend branch to the existing Render backend after confirming the
   workspace and service. Check deployment is live, report returns 401 signed out,
   403 for an ordinary account, and valid counts for the existing administrator.
4. Validate and build the app change, retaining the production backend URL and
   Supabase public client settings. Use the next unused Play version code (last
   observed code was 133; verify all tracks/drafts before selecting a number).
5. Install through internal testing; verify a fresh setup, account creation,
   confirmation, sign-in, generation, offline retry and an existing-user update.
   Promote only after this check. The first-open report remains incomplete for
   older app versions; server authentication counts still work for those versions.

Rollback: reverting the backend and app commits leaves auth behavior unchanged.
The isolated event table can remain inaccessible until a deliberate retention or
removal decision. Do not roll back by deleting profiles or generation history.
