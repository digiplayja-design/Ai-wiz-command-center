# Auto-Email connected pilot

Base: the Render production backend commit `f31c922ce3003f8e05e99746c5a7ae77c06b00c1`.

Adds an `auto_email` companion session alongside Receipt Wiz and Messenger. It uses the existing KORLIX identity and server-owned plan/device limits with a separate per-app device allowance. The verified provider session ID, user, installation ID, status, and route scope determine access. Changing a request header cannot promote a companion session to a hub session. No subscription is created or changed.

New routes:

- `GET /api/auto-email/status`: public capability description, no account data.
- `GET /api/auto-email/session`: authenticated identity, selected profile fields, and the approved email workspace only for its existing owner.
- `POST /api/auto-email/auth/signin`, `/refresh`, `/signout`: exact aliases to existing account handlers with forced `auto_email` scope. Unsupported operations fail closed on older/newer servers.

The pilot can read its existing email records and create/edit drafts for existing approved recipients. Its route scope cannot send/approve messages, create recipients, change consent, edit settings, activate schedules, or access other feature APIs. Existing per-owner and approved-agent checks are retained. This is not a general multi-business release.

Migration `20261027224536_korlix_auto_email_app_sessions.sql` extends the existing companion discriminator and server-only registration RPC. It preserves table ownership rules, RLS, existing rows, indexes, and other apps' limits. Apply before the matching backend deployment. Rollback to the previous backend will make Auto-Email unavailable; it does not require removing the additive schema support or deleting sessions.

Validation: 52 tests passed across Auto-Email routes, companion sessions with PGlite, Messenger auth aliases, shared auth session security, and final auth guards. Coverage includes independent allowances, refresh, revocation, forged headers, wrong users/devices, disabled accounts, database failures, and denial of registration RPCs to client roles. No real user credentials or customer mail were used by these tests.

Frontend integration is maintained in the private KORLIX Auto-Email Site. It keeps auth in its own per-tab session storage with a 12-hour application lifetime, does not persist cloud email bodies, preserves draft idempotency keys, and never calls approval/send routes. Gmail/Microsoft mailbox OAuth, Rici audio, new business workspace provisioning, sending approval UX, billing and app-store packaging remain separate implementation work.
