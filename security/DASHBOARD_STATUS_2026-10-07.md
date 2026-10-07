# KORLIX provider security settings — 7 October 2026

Completed using the authorized Supabase and Render dashboards. Application release code remains backend `4d2fb6d4fa473f68bbd83a52f82799af230f0ed8` and frontend `d2e2e5539aae79c5b6fea5a603f601c057552333`; this record changes documentation and evidence only.

## Completed and verified

- **Supabase leaked-password protection:** enabled and saved for Korlix AI (`uxtjzjbwtppjvnsoiijv`). Reopening the Email settings confirms it remains enabled. The Security Advisor now returns only 236 informational RLS-without-policy findings for server-only tables; no leaked-password warning remains. Organization is already Pro; no plan or billing changes made.
- **Render response headers:** all ten scoped rules saved successfully on static service `srv-d8ekf7t7vvec73dpar60`. Five rules each apply to `/app/*` and `/nova-email/*`: `Content-Security-Policy: frame-ancestors 'self'`, `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, and `Strict-Transport-Security: max-age=86400`.
- **Live delivery:** HTTP 200 and the intended protections verified for `/app/`, `/app/main.dart.js` and `/nova-email/` on both `www.korlixdeveloper.com` and the Render hostname. Render's hostname retains its stronger platform HSTS value (`max-age=315360000; includeSubdomains; preload`); the custom domain serves the configured one-day value. Exact results are in `DASHBOARD_HEADER_VERIFICATION_2026-10-07.json`.
- **Public application check:** the Flutter app renders the normal sign-in form and 16+ notice after these settings. No customer login, purchase, email or location capture was performed.

## Database upgrade prepared, not started

Current database: **17.6.1.127**, ACTIVE_HEALTHY. Stable offered target: **17.11.0.003**. The dropdown also offered a 17.6 preview; the reviewed target is the stable 17.11 release.

The final dashboard warning states **all services will be offline for up to one hour** and **downgrade to 17.6.1.127 is unavailable**. No Confirm upgrade action was taken. A maintenance window needs explicit approval because the newly observed potential outage materially affects the live application.

Readiness checks:

| Check | Observed result |
|---|---|
| Latest listed physical backup | 2026-10-07 06:14:56 UTC; 02:14:56 America/New_York; Restore control available |
| Read replicas | Dashboard explicitly says No read replicas |
| Logical / physical replication slots | 0 / 0 |
| Active WAL sender connections | 0 |
| Unsupported extensions | None found in documented unsupported list |
| MD5-password login roles | 0 of 10; no password hashes disclosed |
| Unsupported reg* data columns | None; provider regclass/regrole types are supported |
| pg_cron / cron job history | Not installed / absent |
| Database logical size | Approximately 40.8 MiB; this is not a downtime guarantee |
| Release-specific compatibility | Earlier preflight found no affected ltree, float GiST, custom-operator or legacy pgcrypto uses |

The backup check verifies an available provider backup, not an independent restore drill or a zero-loss recovery point. Supabase's dashboard explicitly warns that database backups exclude Storage object bytes. Recheck backup freshness and health at the chosen maintenance time, review the upgrade dialog, then verify version, Auth, database access, RLS and application connectivity after upgrade.

## Screenshot evidence

Saved settings:

![Leaked-password protection enabled](evidence/supabase-password-protection-2026-10-07.jpg)

![Render header rules saved](evidence/render-response-headers-2026-10-07.jpg)

Upgrade hold requiring an outage window:

![Stable upgrade target and provider downtime warning](evidence/supabase-upgrade-warning-2026-10-07.jpg)

## Documentation

- [Supabase upgrade process](https://supabase.com/docs/guides/platform/upgrading)
- [17.11 security release and compatibility notes](https://supabase.com/changelog/postgres-15-19-17-11-breaking-changes)
- [Database backups](https://supabase.com/docs/guides/platform/backups)
- [Password security](https://supabase.com/docs/guides/auth/password-security)
- [Render static-site headers](https://render.com/docs/static-site-headers)
