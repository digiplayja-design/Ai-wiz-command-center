# K191 — Google upload authorization

## User flow and limits

Conversion intake → Google conversion destination → **Google upload access** now provides a separate, explicit OAuth flow for future Google inquiry uploads. Opening the screen reads local state. The owner confirms the requested permissions, starts an authorization, taps Continue to Google, completes Google consent, then returns to the same KORLIX window and taps Finish upload authorization.

The flow requests exactly the Google Ads (`adwords`) and Data Manager (`datamanager`) scopes. Ads access is used to verify the selected advertiser, accessible manager/root and saved conversion action using the newly authorized credentials. Ads permission itself is broad; this flow only performs account and conversion-action reads. The existing Ads connection and its configuration hash are unchanged.

This release **does not send events**, make Data Manager ingestion calls, activate ads, or enable a provider. Scope consent and Ads reads do not prove Data Manager API enablement, account eligibility, destination upload permission or conversion acceptance. All responses retain `send_ready:false`, `provider_verified:false`, `delivery_state:not_implemented`. K188 receipts and K190 destination contracts are unchanged.

Upload access is stored per KORLIX owner for the selected Ads binding/account/root. It can be reused by that owner's campaigns with the same current account context. The saved state is last-known authorization, not a fresh provider test. The particular conversion action is checked when authorization finishes; future dispatch must recheck its own current destination and upload rights.

## Configuration — remains default off

No production environment values are changed by this release.

| Setting | Requirement |
| --- | --- |
| Existing Google Ads configuration | Must be ready with Cloud-project access model and v25 |
| `KORLIX_GOOGLE_UPLOAD_AUTH_ENABLED` | Exact `true` required; otherwise disabled |
| `KORLIX_GOOGLE_UPLOAD_REDIRECT_URI` | HTTPS, no userinfo/query/fragment, exact path `/api/funnels/google-upload-access/callback` |
| OAuth client, secret and encryption key | Reuses existing server-side Ads configuration, with a distinct configuration hash and encryption binding |

Before real use, the platform administrator must enable the applicable Google APIs, register the new redirect URI on the OAuth client, and complete applicable OAuth/project verification. The upload gate is a separate operator setting. This code release and the owner's standing publication approval do not enable it or perform account consent.

## Authorization integrity

1. A confirmed begin checks current Enterprise ownership, current production Ads connection and saved destination, plus the displayed access version/fingerprint. It creates a single pending attempt per owner with a ten-minute expiry. Starting again replaces an unfinished upload attempt after a 30-second cooldown; it preserves any existing saved grant.
2. PKCE S256, a random callback state and a separate original-window proof protect the exchange. Only hashes of state/proof and an AES-GCM encrypted verifier are stored. The upload encryption associated data is separate from Ads token storage and bound to owner/attempt/purpose.
3. The public callback consumes state once before token exchange, repeats the live local destination/authorization context, and requires both scopes and an offline refresh token. Partial consent cannot produce a ready candidate. Token requests use a fixed HTTPS host, POST body, no redirects, ten-second timeout and bounded 128 KiB response; errors are redacted.
4. Finish requires the original owner's in-memory proof. A service-only SQL claim changes ready to verifying once before provider work. The new refresh credential must still expose both scopes when refresh returns a scope field; OAuth omission of an unchanged scope is supported after the initial explicit check.
5. The new access token reads accessible roots, advertiser metadata and eligible conversion actions. Wrong-root/account access, changed action settings or account metadata reject the attempt. SQL repeats current ownership, destination fingerprint, expiry and authorization version before replacing the saved grant.
6. Disconnect, account/destination changes, supersession or entitlement loss during remote work prevent a late write. A failed replacement preserves the previous saved grant. Concurrent finishes have one winner. No automatic OAuth write retry occurs.

The state fingerprint also binds the current pending attempt ID, preventing old windows from starting or clearing over a newer attempt. The grant uses a monotonically increasing sequence; reconnect cannot reuse an old grant version. Expired pending data is purged on successful local reads/actions. An abandoned verifier/candidate remains encrypted and unusable after expiry until cleanup or parent deletion.

## Removal and recovery

Removing upload access is a confirmed local operation applying to the owner's campaigns. It deletes the saved upload credential and pending attempt without provider requests, leaves the Ads connection and destinations in place, and does not revoke the application's Google-account permissions. Deleting the Ads connection cascades upload credentials and pending attempts. Account/configuration changes mark saved access stale; they do not silently authorize a new account.

The browser keeps the finish proof and authorization URL only in widget memory. Refresh discards them if the exact attempt is no longer current and unclaimed. Access denial, scope/client/campaign changes or closing the screen discard private state. Safari-compatible window launch happens directly on the Continue tap, never automatically after the begin response.

An early Finish can be retried only after a fresh local read confirms that the same attempt remains waiting/exchanging/ready. A verifying or uncertain outcome disables resubmission and asks for a local refresh. Server claims are never automatically replayed. If a process dies while verifying, an explicit new authorization can replace the abandoned attempt after expiry/refresh; the old attempt cannot later overwrite the new one.

## Database and endpoints

CLI-created migration `20260924090911_google_upload_authorization.sql` adds:

- `korlix_google_upload_connections`: encrypted refresh token, exact scope contract, Ads binding/account/root, version and timestamps; no visitor data.
- `korlix_google_upload_oauth_attempts`: short-lived encrypted verifier/candidate and context/proof hashes.
- `korlix_google_upload_version_seq`.
- `korlix_google_upload_sealed_valid(jsonb)` and `korlix_google_upload_access_v1(uuid,text,uuid,jsonb)`.

Both tables have RLS, no client policies and explicit revokes overriding default grants. Only service_role has table CRUD and sequence usage. Both functions are SECURITY INVOKER with fixed `public,pg_temp`, service_role execute only. No existing table data, function, scope or permission is replaced. The established funnel/campaign/Ads lock order is retained before the per-owner upload lock.

| Endpoint | Behavior |
| --- | --- |
| GET `/api/funnels/google-upload-access/readiness` | Public configuration readiness; sending and provider-verification always false |
| GET campaign `/google-upload-access` | Current local state, no provider calls |
| POST campaign `/google-upload-access/begin` | Confirmed version/fingerprint and new OAuth attempt |
| GET `/api/funnels/google-upload-access/callback` | Single-use callback; restrictive CSP, no-store and no-referrer |
| POST campaign `/google-upload-access/finish` | Original-window proof, one-time claim, provider account/action checks, local grant save |
| POST campaign `/google-upload-access/disconnect` | Confirmed local removal across owner's campaigns |

Campaign prefix is `/api/funnels/:id/campaigns/:campaign_id`. Reads are limited to 30/minute per owner; mutations share 10/minute per owner; public callbacks have a separate 30/minute IP limit. Current SQL ownership/Enterprise authorization is repeated; private responses are no-store. Browser responses never contain tokens, sealed values, state/proof hashes or private configuration hashes.

## Verification and next work

274 Google/conversion backend tests and 37 upload/destination/intake Flutter tests pass. SQL tests run actual migrations with deliberately broad default grants before explicit revokes; they cover role boundaries, PKCE/proof/state, missing scopes, expiry, cancellation, stale context, wrong credentials, late entitlement changes, concurrent finish, removal and cascade. Frontend covers strict URL/scope/state validation, explicit launch, original-window completion, uncertain outcomes, scope/access loss and real-font 1400/390/320px layouts. Changed Dart analyzes cleanly; production JavaScript build is checked before publication.

Automated tests use mocked providers and local SQL. Production checks are anonymous only. Real OAuth consent, Data Manager acceptance and owner A–G testing remain deferred.

Next: implement explicit delivery authorization, immutable event/attempt/deduplication records, narrow consent-based payloads, provider validation/dispatch, truthful accepted/rejected/uncertain receipts and diagnostics. Future dispatch must recheck current upload grant, account/root, destination ownership/settings, consent, event age and click-window eligibility. A scope grant or request ID alone must never count as a delivered/accepted conversion. Never blindly retry uncertain ingestion: repeated transaction IDs can be treated as adjustments. Meta needs independent current-contract verification.

Official references checked September 24, 2026:

- [Data Manager ingest scope and validation semantics](https://developers.google.com/data-manager/api/reference/rest/v1/events/ingest)
- [Data Manager event destinations and conversion owners](https://developers.google.com/data-manager/api/devguides/events/send-events)
- [Google OAuth web-server consent, offline access and scope handling](https://developers.google.com/identity/protocols/oauth2/web-server)
- [Supabase RLS and explicit grants](https://supabase.com/docs/guides/database/postgres/row-level-security)
