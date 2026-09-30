# Enterprise US payroll

KORLIX Payroll is a US-only, USD workspace available to verified, active Enterprise business owners. It uses Gusto Embedded Payroll hosted flows for company/employee onboarding, regular and off-cycle payroll, contractor payments, schedules, benefits, history, reports, and year-end company tax document review. The owner reviews and submits payroll inside Gusto. KORLIX does not calculate taxes, initiate payroll autonomously, or claim a payment/filing is complete based on opening a session.

## Deployment and activation

Apply `supabase/migrations/20260930132942_enterprise_us_payroll.sql`, deploy the backend, then deploy the frontend. The feature is useful for preparing a US business workspace before the provider is configured. No secrets or provider account creation are required for deployment.

Gusto production access requires its commercial, security, and implementation approval. Complete partner onboarding at https://docs.gusto.com/embedded-payroll/docs/introduction and obtain app credentials from https://dev.gusto.com. Demo credentials cannot process real payroll. Run a complete provider demo acceptance exercise before enabling production; automated tests use fixtures, not Gusto's live service.

Set these **backend-only** environment variables securely in Render:

| Variable | Value |
|---|---|
| `PAYROLL_GUSTO_ENVIRONMENT` | `demo` for a staging service; `production` for approved production |
| `GUSTO_CLIENT_ID` | App client ID for that environment |
| `GUSTO_CLIENT_SECRET` | App client secret for that environment |
| `PAYROLL_TOKEN_ENCRYPTION_KEY` | Base64 encoding of 32 cryptographically random bytes; store in the secret manager and retain for decryption |
| `PAYROLL_GUSTO_PRODUCTION_APPROVED` | `true` only after Gusto approves production and the acceptance checklist is complete |
| `PAYROLL_TRUST_PROXY_HOPS` | Correct count of trusted reverse proxies for the deployment; defaults to 0 for direct connections. Verify the Render ingress chain before setting to 1 or more. Used to record the actual IP for explicit provider terms acceptance. |

Generate the encryption key with `openssl rand -base64 32`, and enter it directly into the secret manager. Never put credentials in Flutter, git, logs, URLs, or chat. Changing the key without re-encrypting existing rows will lock those connections. Company tokens are AES-256-GCM encrypted with account ID, provider environment, and company UUID as authenticated context.

API version is pinned to `2026-06-15`. Request partner scopes for managed company creation, terms acceptance, company onboarding status, and the selected Flows. Confirm exact scopes and supported flows with Gusto for the approved application. Separate staging/production databases and provider applications are recommended. Existing workspaces cannot be silently switched between demo and production.

## Owner flow

1. From KORLIX business tools, open **Payroll**. Non-Enterprise customers cannot see its tool tile and are rejected by every API/database command.
2. Choose an owned Bookkeeping business, enter its legal name, and explicitly confirm US business authority.
3. Once the provider is activated, enter the payroll administrator's first/last name and authorize sharing those names, the business name, and the verified account email with Gusto. This creates one new partner-managed company. Existing Gusto customers require an assisted migration; do not create a duplicate company.
4. Review and explicitly accept the linked Gusto Embedded terms. The backend records acceptance with Gusto; it never accepts by default.
5. Complete provider onboarding: addresses, EIN, state/federal setup, bank verification, employees, pay schedule, signed forms, and prior payroll when applicable. These details remain in the provider's secure UI.
6. Refresh setup status. Open the desired payroll action in a new secure window. Complete onboarding before payroll-related flows can open. Gusto additionally controls underwriting, funding, state coverage, deadlines, calculations, and final submission.
7. Return to KORLIX. Payroll history/reports and tax document flows show provider records. Workspace activity records access/setup events only, never claims payroll was submitted or taxes filed.

Workforce and Bookkeeping navigation is included. Approved time, employee identity mapping, payroll journal posting, and reconciliation are **manual** in this release. The UI states this explicitly. There is no automated payroll scheduler or AI payment execution.

## Access and failure handling

- Supabase's authoritative `user_profiles.tier` and `is_disabled` plus business ownership are checked server-side and again inside the service-role-only database RPC. Client tier labels do not grant access.
- Browser roles have no table, sequence, or function access to payroll storage. RLS is enabled with no browser policies. Provider tokens, company UUIDs, admin emails, and lease IDs are excluded from public responses.
- Account/session changes and 401/403 responses clear the Flutter workspace and close its dialogs. The open screen rechecks access every 45 seconds. Already-issued provider sessions are bearer capabilities: Gusto expires them after one hour of inactivity or 24 hours total. KORLIX cannot instantly revoke an already-issued Gusto flow after a tier downgrade. New sessions and KORLIX data are blocked immediately by the backend. The UI only allows a generated link to be launched for one minute and never persists it.
- Each business has one payroll workspace. Connection claims serialize provider company creation. An ambiguous provider response or crash leaves `connecting`/`connection_review`; it is never automatically retried into a duplicate company.
- Token refresh uses a 90-second database lease across server replicas. A persisted `refresh_pending` marker prevents replaying a potentially consumed refresh token after an uncertain response or crash. Successful refresh saves encrypted tokens before using them. Stale lease holders cannot overwrite new credentials.
- If a connection needs review, reconcile its provider record with Gusto support before restoring it. Never clear `refresh_pending`, reset a connection to draft, or replace `provider_company_id` merely to make the button work. Restore approved credentials only through a reviewed server-side maintenance operation using the same authenticated encryption context; rotate affected credentials with Gusto as needed.
- No raw upstream error bodies are returned or logged. HTTPS flow origins are exact allowlists. API redirects are disabled. Responses are `Cache-Control: no-store`.

## Production acceptance

Before setting the production approval flag, validate Gusto demo company setup/terms, completed onboarding and underwriting, W-2 employee/direct-deposit setup, a reviewed regular payroll, off-cycle payroll, contractor payments, provider reports/tax documents, expired-token refresh, and terms acceptance client-IP accuracy behind the deployed proxy. Confirm mobile/browser launch behavior and supported tax jurisdictions with Gusto. Do not run this exercise with real bank accounts or submit a real payroll as a software test.

Automated verification:

- `node --test backend/test/payroll.test.mjs`
- `flutter test test/payroll_test.dart test/social_notifications_test.dart`
- `dart analyze lib/payroll`

These cover tier/ownership isolation, anonymous/browser-role denial, production configuration gates, encrypted credentials, duplicate company prevention, ambiguous failures, refresh leases, explicit consent, onboarding gating, URL validation, redacted errors, account-switch clearing, US-only workspace creation, and mobile/desktop layout.

Official references: https://docs.gusto.com/embedded-payroll/docs/flow-types, https://docs.gusto.com/embedded-payroll/docs/authentication-and-authorization, https://docs.gusto.com/embedded-payroll/docs/flows-quickstart, https://docs.gusto.com/embedded-payroll/reference/post-v1-partner-managed-companies.
