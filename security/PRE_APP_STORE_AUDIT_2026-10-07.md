# KORLIX AI — final pre-submission audit

Date: 7 October 2026. Verdict: source hardening, web/backend release and the listed provider hardening are complete; **App Store submission remains gated** on the operational and native checks below. This audit does not certify that all vulnerabilities are absent.

## Scope and deployment identity

Reviewed the active Flutter application, native iOS/Android configuration, the deployed `backend/server.js`, database authorization, private storage, dependencies, uploads, consent, billing, account lifecycle and mobile usability. Feature coverage includes Receipt Wiz, Bookkeeping, Tax Prep, Workforce/location, CRM, Social, Email Center, meeting/voice/podcast flows, Picture/Portrait/Logo studios, image/video generation, App Studio portals, business tools, sharing and the idle screensaver. Source and automated coverage vary by feature; no claim of live end-to-end execution of every integration is made.

The production backend is `backend/` on `release/k135z-backend-render-20260919`, Render service `srv-d8csvkkp3tds73emfikg`. The frontend is `release/k135z-frontend-20260919`, service `srv-d8ekf7t7vvec73dpar60`, publishing `website/` and `/app/`. Baselines were backend `7367b22af79dbd7e07e0c55cb57cec7472b68fd6` and frontend `6e71770c4f952211b466127be0f29892a33b4631`. Both services have automatic deployment disabled. Native source changes require a new signed binary; deploying the website does not update installed iPhone applications.

The frontend branch contains a historical backend snapshot and the repository has a legacy root `server.js`. Neither is the deployed API. A new README explicitly identifies the authoritative branch. Old dependency findings in those snapshots were not represented as fixes to the running backend or silently removed from history.

## Fixed findings

| Area | Confirmed problem | Correction |
|---|---|---|
| Deletion requests | Anonymous callers could submit another email; retries could duplicate requests. | Require verified active user/device, bind identity and email server-side, bound input, service-only database RPC with per-user transaction locking and idempotency. |
| Browser database access | Reports/deletion intake allowed anonymous null-user inserts with caller-controlled workflow values. Browser maintenance grants and permissive future-object defaults remained. | Restrict intake to backend service, revoke browser MAINTAIN and harden application-owner defaults. Existing records preserved. |
| Tenant identity | Learning routes trusted editable account metadata as an authorization fallback. | Remove user-editable account ID fallback. |
| Authentication and errors | Custom Access lacked consistent disabled/revoked-device checks; password-reset URL fallback trusted request Host; malformed requests could expose details. | Shared verified authentication, trusted HTTPS reset destination, bounded account budgets, safe JSON errors and no-store API responses. |
| Native credentials | Access and refresh tokens were stored in ordinary preferences. | Atomic secure storage, verified migration, device-only Keychain settings, no plaintext fallback, logout tombstone, backup exclusions and reinstall protection. |
| Session recovery | Locked secure storage could leave the app loading or keep in-memory authentication after signout; late refresh could revive an old account. | End loading in finally, preserve recoverable migration data, clear memory first, guard asynchronous refresh by session generation and bound signout requests. |
| AI consent | Consent was shared between accounts and independent provider/category sets could grant combinations never explicitly approved. | Account-specific atomic records of exact provider/category pairs; fresh consent for legacy records; cancel pending decisions on account change/revocation and fail closed on persistence failure. |
| Advertising privacy | Mobile Ads initialized before a consent gate. | Android UMP consent and eligibility before SDK initialization, required privacy controls, account/billing generation guards, safe ad disposal. Paid sessions without ads do not initialize advertising. |
| Upload processing | Multipart parsing allocated memory before authentication; document extraction could exhaust resources; PDF API usage was incompatible; archive metadata could hide inflated input. | Authentication before parsing, bounded concurrent/file/field sizes, PDF/DOCX worker isolation and deadlines, bounded actual decompression, shared ZIP validation for documents and CRM spreadsheets. |
| Native video download | Download accumulated an unbounded response. | Streamed download, 64 MiB cap, 90-second total deadline, cancellation and cleanup. |
| Apple billing | Replaced upgrade transactions could grant access; history traversal and verification lacked adequate bounds; stale UI responses could cross accounts. | Reject upgraded transactions, cap/cycle-check history, shared account verification budget, serialized purchase handling, session guards and recovery controls. |
| Directory billing | Paused collection and inconsistent invoice facts could preserve activation. | Enforce collection state and matching customer/subscription/mode/currency/payment facts. |
| Production dependencies | Five remaining moderate transitive findings. | Scoped compatible overrides, updated lockfile and real DOCX/ExcelJS/CLI checks. Production npm audit now reports zero known advisories. |

Process-local abuse budgets supplement authorization; they are not a distributed rate limiter or a DDoS certification. Existing release fixes for device compatibility, Workforce location timeouts, video ownership/quota reservations and private receipt isolation were preserved.

## Usability and aesthetics

Improved safe areas across business screens; fixed iPad share anchors and filenames; protected asynchronous picture selection and sharing; retained readable small-phone and enlarged-text layouts. The iOS launch screen now uses the existing brand mark on the app's dark background instead of a blank white placeholder.

The native subscription sheet opens immediately while loading, displays localized monthly prices and allowances, exposes Terms/Privacy, refresh and restore, and avoids a redundant personal purchase for organization-managed membership. Deletion confirmation now explains exports and recurring subscriptions, links Apple subscription management and the deletion policy, shows progress, prevents duplicates and handles timeout/account change. Success explicitly means a request was recorded for review, not that data has already been erased.

Native permission descriptions, Keychain entitlements, first-party required-reason privacy manifest, CocoaPods configuration, test bundle identity and release signing safeguards were corrected. Android no longer falls back to debug signing or allows app backups/cleartext traffic.

## Verification

| Check | Result and limits |
|---|---|
| Runnable backend suite | **2,787 passed, 0 failed** across the final runnable selection. Includes billing, authorization, provider callbacks, upload parsing and feature isolation. |
| Initial unrestricted backend run | 2,822 tests: 2,772 passed, 50 failed. Fifteen failures were stale route/middleware fixtures, repaired and rerun. The remaining environment/history-dependent checks are listed below, not silently called passing. |
| Consolidated Flutter release gate | **127 passed, 0 failed** across 13 test files: auth/session, signup, secure storage, billing, ads, sharing, deletion, download limits, Locator, AI privacy and Workforce. The Render build now runs this gate with analytics suppressed. |
| Broader UI review | 142 checks passed in earlier focused interface suites; one optional screenshot-export check was skipped. Counts overlap other groups and must not be added. Home fixtures visually reviewed at 390 px, 320 px with 200% text and 1024 px. |
| Production dependency audit | Zero known production npm vulnerabilities at audit time. This does not cover all native SDKs, OS components or historical source snapshots. |
| Database migration | `20261007113219_support_intake_and_default_privileges.sql` applied successfully after preflight and actual-SQL tests. Live metadata confirms zero public tables without RLS, zero public buckets, no browser intake writes or deletion RPC execution, and retained service RPC execution. |
| Native metadata | Plist/XML/resource checks passed; 18 iOS icon dimensions and opaque marketing icon verified. No signed iOS/Android build or physical device verification occurred here. |

The two native PostgreSQL suites (`k135z_b5b_storage_rpc.test.cjs`, `k135z_workspace_storage_rpc.test.cjs`) need nonce-bound, nonroot Unix-socket database harnesses unavailable in this root-only environment. They account for 33 initial failures. Run them in the supported isolated CI environment before release; their safety guards were not weakened and tests never connected to production. Two historical `k136s_no_conflict_guard.test.cjs` checks depend on a missing pinned feature-branch commit in the shallow checkout; they were left intact. Current tracked source was separately checked for high-confidence credentials and patch integrity.

No customer receipts or private documents were read, no real locations were collected, and no customer emails, purchases, account deletions or provider media-generation calls were triggered by this audit.

## Remaining release gates

Provider follow-up completed October 7: leaked-password protection and static-site security headers are applied and verified. The user approved the outage, and PostgreSQL was upgraded to **17.11.0.003**, returning ACTIVE_HEALTHY at 13:40 UTC. Post-upgrade SQL, RLS/private-storage permissions, backend/Auth connectivity and public app startup passed. See `DASHBOARD_STATUS_2026-10-07.md` and `DATABASE_UPGRADE_VERIFICATION_2026-10-07.json`.

1. **Deletion fulfillment and moderation:** verify a staffed process that actually deletes account-associated database/storage/provider data, handles legitimate retention exceptions, gives a real processing timeframe and sends completion confirmation. Current implementation securely queues the request. Do not invent a deadline or treat acknowledgment as fulfillment. Verify Social reporting/blocking review and child-safety contact handling operationally.
2. **Signed iOS archive and devices:** build with Apple's currently required Xcode 26+/iOS 26 SDK, inspect the aggregate SDK privacy report, validate signing and App Store privacy labels. Test iPhone and iPad with denied/limited camera, microphone, photos and location; locked Keychain/migration/logout; background calls/media; interrupted uploads; network loss; accessibility; share sheets; a full 15-minute two/three-person podcast and receipt scan/save/next-scan recovery. Automated tests cannot certify these hardware/provider paths.
3. **Billing and ads configuration:** verify StoreKit Sandbox/TestFlight purchase, restore, upgrade/downgrade, expiry/refund and both subscription products' group configuration. Explicitly approve tester IDs before enabling Sandbox entitlements. Publish the AdMob privacy messages and verify UMP geography/form behavior on Android test devices.
4. **App Store metadata:** complete the current age questionnaire, reviewer account/instructions, support/privacy links and data disclosures. Signup uses a 16+ self-declaration; this does not implement Apple's Declared Age Range API or justify its verified under-13 social-media descriptor.
5. **Isolated database gates and operational recovery:** run the native PostgreSQL suites above; verify backup restore and receipt recovery with synthetic data in a separate environment. No production disaster-recovery restore was attempted during this audit.

Known existing limits from the prior audit remain: legacy access tokens without device headers may survive signout until expiry; historical manual-versus-subscription tier provenance needs care; ambiguous provider charges require reconciliation; abandoned web checkout versus native-purchase concurrency needs a coordinated lifecycle review. No destructive cleanup, speculative entitlement rewrite or paid infrastructure upgrade was performed.

## Primary references reviewed

- [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple account deletion](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion)
- [Apple upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)
- [Apple age ratings](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)
- [Google UMP for Flutter](https://developers.google.com/admob/flutter/privacy)
- [Supabase PostgreSQL security update and compatibility notes](https://supabase.com/changelog/postgres-15-19-17-11-breaking-changes)
- [Supabase password security](https://supabase.com/docs/guides/auth/password-security)
- [Render static-site headers](https://render.com/docs/static-site-headers)
