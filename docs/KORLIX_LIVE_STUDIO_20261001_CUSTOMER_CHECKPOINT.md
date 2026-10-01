# Live Studio customer checkpoint — October 1, 2026

This supersedes the earlier single-channel pilot checkpoint. The user's goal is a service sold to customers. The application owner's personal YouTube channel is not required for configuration; each customer connects their own. A dedicated authorized test channel is needed later for real streaming acceptance.

## Completed and live

- Backend production commit: e1ab1fa1cff93d8fd332a34cc02e48d9abb2c5c7. Render deploy dep-dava323ncjis73cf6oi0 live October 1 at 18:08:54 UTC.
- Frontend production commit: 107524ca9141249d43b27ad957962e1199d0860c. Render deploy dep-dava33btqb8s73d1dh0g live October 1 at 18:10:14 UTC.
- Applied Supabase migrations: 20261001180353_live_studio_customer_workspaces and 20261001180428_live_studio_connections.
- Seven feature tables have RLS and no anonymous/authenticated direct grants. RPCs are service-only. Production service-role workspace/connection reads passed, while direct auth.users SELECT remains denied. The only feature advisor notice is the expected informational RLS-with-no-policies entry for intentionally server-only tables.
- Backend health returns Live Studio version 2/customerWorkspaces true. Unauthenticated workspace returns 401. Public OAuth launch returns an explicit administrator-setup 503 because app credentials are not yet installed.
- Website app, updated compiled bundle and privacy policy all return 200. The deployed bundle contains the customer channel/allowance interface.
- 54 focused backend tests and 16 frontend tests passed. Real local FFmpeg fixtures were used; no paid generation or real YouTube broadcast was performed. Flutter web release build and Blueprint schema validation passed.

Implementation details and configuration are in LIVE_STUDIO.md. Local and GitHub trees were checked for byte identity before Render deployment.

## Worker and external setup

The user approved the proposed US$25/month Render worker and YouTube setup on October 1 at 12:40 Eastern, then authorized dashboard use. Do not ask for that same cost or browser approval again.

The authenticated Render dashboard is on its unsaved Blueprint creation form for KORLIX Live Studio, backend release branch, deploy/live-studio-worker.render.yaml. It has been refreshed to the new customer architecture. It now requests application client ID/secret and the shared encryption key, with no single-owner UUID or global channel refresh token. The form still shows one 1c-2g worker at $25/month. No worker was created and Deploy Blueprint was not clicked. All secret fields remain empty.

Next required work:

1. Configure a dedicated Live Studio Google OAuth application client and enable YouTube Data API, consent details/scopes and exact callback. Install the same app settings and 32-byte base64 encryption key on the existing API and approved worker. Do not borrow calendar refresh tokens or ask for secrets in chat.
2. Create the approved worker after its prerequisites are present. New instances support separate customer jobs but the initial approved single instance supplies one encoder slot.
3. Confirm a dedicated test channel through the product's customer OAuth flow; run 15/30-minute unlisted acceptance, including controls, app closure/reopen, provider failure, disconnect, revoke and worker termination.
4. Implement verified subscription billing, plan decisions, renewals/revocation, reservation reconciliation and operating limits. Current customer grants are explicit service-managed records; no customer checkout or commercial prices have been added.

The main app is at https://www.korlixdeveloper.com/app/ → Tools → Live Studio.

Estimated remaining: roughly 2–4 development weeks for a customer-ready MVP, plus external approval time. The prior 2–4 development days applied only to the single-channel pilot.
