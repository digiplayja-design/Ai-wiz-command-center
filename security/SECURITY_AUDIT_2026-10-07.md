# KORLIX security audit — 7 October 2026

This is the earlier security pass. See [the final pre-submission audit](PRE_APP_STORE_AUDIT_2026-10-07.md) for subsequent fixes, current dependency results and remaining release gates.

Provider follow-up on October 7: leaked-password protection and Render security headers were applied and verified. The explicitly approved PostgreSQL upgrade to 17.11.0.003 completed successfully; the project is ACTIVE_HEALTHY and post-upgrade permissions, Auth/backend connectivity and app startup checks passed. The historical pending-provider statements below describe this earlier pass and are superseded by [the dashboard verification record](DASHBOARD_STATUS_2026-10-07.md).

This audit found and corrected exploitable access-control and abuse weaknesses. It is a source, configuration and targeted regression review, not a guarantee that the application has no vulnerabilities.

## Scope and method

Reviewed the active backend entry point (`backend/server.js`), authentication and device sessions, database grants/RLS, private storage, video generation, Apple and web billing, provider callbacks, Email Center, uploads, and tenant isolation in Receipt Wiz, Bookkeeping, Tax Prep, CRM, Workforce and Social. The root-level legacy `server.js` is not the deployed entry point.

Production checks used database metadata, permission inspection and harmless public requests. Reproductions used synthetic users, mocks and isolated PostgreSQL tests. No real purchases, generated videos, emails, customer document reads, password changes, deletion requests or load attacks were performed.

Deployment targets are the existing backend and frontend release branches. Native iPhone/Android binary distribution is separate from the web deployment; the Flutter source changes need inclusion in the next native release.

## Confirmed findings and fixes

| Area | Finding | Correction |
|---|---|---|
| Privileged database functions | Browser roles could execute six server functions, including custom-access-code issuance/redemption and arbitrary-user quota/entitlement functions. | Revoked PUBLIC/anonymous/authenticated execution; retained service-role execution. Pinned five helper search paths and removed browser TRUNCATE, REFERENCES and TRIGGER privileges. Signup trigger and normal owner access remain functional. |
| Video access | Image-to-video creation was anonymous; video status/content routes did not verify job ownership. | Authenticate before upload parsing; bind provider job IDs to verified owners; check ownership before provider access. Unknown or ambiguous legacy IDs fail closed. |
| Video limits | Deletable display history and post-provider charging allowed allowance restoration and concurrent overspending. | Private authoritative reservations, serialized quota checks and atomic purchased-credit debits before provider calls. Text and image-video allowances remain separate. |
| Sessions | Explicit device-denial errors were swallowed, refresh could reactivate revoked devices, and account disablement was not enforced consistently. | Deny disabled accounts centrally; preserve explicit revocation; conditional active-only updates; revoke provider refresh sessions on signout and rejected rotated sessions. |
| Apple billing | Unbound historical purchases could be claimed by transaction ID; replayed signed receipts could reinstate stale paid access. | Immutable account/transaction bindings, fresh Apple lookup, persisted ordering and expiry checks, atomic entitlement transitions. Active Sandbox purchases require a server-controlled tester allowlist. |
| Email Center | Editable backend destinations could receive session credentials; cached credentials could survive a shared-browser account switch. | Pin credentialed requests to the production API; reject redirects; bind tokens and replies to the active app account/session; clear data on logout or account change. |
| Report submission | Anonymous, impersonated, oversized or repeated reports could trigger support email and unbounded content logging. | Verified identity, 32 KiB limit, five reports per user per ten minutes across aliases, bounded limiter memory, sanitized responses/logs. Admin secrets only accepted in headers, not URL queries. |
| Dependencies and headers | Vulnerable upload/image/XML dependencies and missing API response hardening. | Updated and locked affected packages; removed Express disclosure; added API MIME, referrer and HTTPS response policies. |

The earlier CRM dashboard fix remains applied: `crm_user_dashboard` uses `security_invoker=true`, so it observes underlying caller permissions/RLS.

## Live database verification

After the three audit migrations:

- 253 of 253 public tables have RLS enabled; none have RLS disabled.
- All 16 storage buckets are private.
- Zero public SECURITY DEFINER functions are executable by anonymous or authenticated browser roles.
- Security Advisor no longer reports the exposed-function or mutable-search-path warnings.
- At this earlier checkpoint, the remaining warning was disabled leaked-password protection; it was subsequently enabled and the warning cleared.
- Informational “RLS enabled without policy” notices refer to server-only tables. A missing policy denies browser rows; it does not grant public access.

Applied migration history:

- `20261007015159_rpc_security_hardening.sql`
- `20261007015226_video_access_security.sql`
- `20261007015513_apple_billing_security.sql`

The private Apple/video tables retain RLS and no browser grants. Service-role authorization is enforced by backend verified-user and membership checks, rather than relying on RLS to restrict the service role.

## Verification evidence

| Check group | Result |
|---|---|
| Integrated new backend security suites | 89 passing in one run; the additional actual administrator-header regression also passes, bringing the new checks to 90. |
| Receipt/Bookkeeping/Tax/CRM/Workforce/Social isolation suites | 120 passing. |
| Upload/image/document dependency compatibility suites | 102 passing, plus DOCX generation/extraction round-trip and Sharp load. Some coverage overlaps other groups; do not add these counts. |
| Existing payment/callback/OAuth selection | 82 passing; one existing Zoom registrar assertion expects seven routes where the current implementation registers nineteen. |
| Email Center session/destination checks | 14 passing. |
| Image-video credential routing | Four Flutter checks passing; focused Dart analysis and formatting clean. |
| Broader existing web suite | Two stale version assertions also reproduce at the clean baseline; one environment lacked Dart on PATH. This suite is not reported as fully passing. |
| Syntax and patch integrity | Active backend syntax and Git whitespace checks pass. |

Tests exercise anonymous denial, cross-account denial, legitimate owner access, quota reservations, stale/revoked purchases, sandbox grants, account switching, credential destinations and report abuse. External media URLs receive no KORLIX credentials. Public protected video downloads use authenticated fetching, including browser blob playback.

## Dependency status

The backend npm audit changed from 13 affected dependency nodes (one critical, five high, six moderate, one low) to five moderate nodes and zero critical/high/low nodes. Five remaining nodes correspond to two advisories:

- `uuid` through ExcelJS: the affected external-buffer v3/v5/v6 use was not found; inspected ExcelJS calls use v4 without an external buffer.
- `sprintf-js` through Mammoth's CLI dependency: no upstream fixed release is available; the app uses the extraction API, not the CLI or attacker-controlled format strings.

The DOCX package also embeds older nanoid code. Inspected calls use fixed positive lengths; no reachable negative-size input was found. Lockfile updates do not rewrite embedded bundles. These are documented residual dependencies, not claims of zero risk.

## Compatibility and residual limits

1. **Provider settings — subsequently completed.** Supabase leaked-password protection and static-site frame protection/related response headers were applied through the authorized dashboards. The PostgreSQL security upgrade also completed after outage approval. See `DASHBOARD_STATUS_2026-10-07.md`. No paid-plan upgrade was made.
2. **TestFlight paid testing is now opt-in.** Set `APPLE_SANDBOX_ALLOWED_USER_IDS` on the backend to exact, explicitly approved tester UUIDs. No testers were chosen or granted access during this audit. Production purchases and expired/refunded cleanup remain supported.
3. **Legacy access tokens.** Older clients without device headers remain compatible. Signing out revokes the provider refresh session; an already issued bearer token can remain usable until expiry. This release does not claim universal instantaneous access-token invalidation.
4. **Historical Apple tier provenance.** The existing previous-tier fallback preserves manual grants. Distinguishing every historical manually granted tier from a subscription-derived tier needs separate entitlement provenance work. The live aggregate inspection found no active Apple entitlements at audit time.
5. **Rate limiting.** The report limiter is per process and resets on restart. Distributed enforcement, account-creation abuse controls and edge traffic protection need separate infrastructure controls; this is not a DDoS/load certification.
6. **Video recovery.** Previously untracked image-video jobs cannot be safely assigned to owners and now fail closed. A provider failure after reservation does not automatically refund an ambiguous charge; administrative reconciliation may be needed.
7. **Acceptance coverage.** No real payment, native-device, production-account-switch or full external penetration test was performed. Repository secret scanning of all historical commits and third-party infrastructure internals are outside this review.

Source fixes and these limitations should be reviewed together. Periodic dependency review and independent penetration testing remain useful as features change.
