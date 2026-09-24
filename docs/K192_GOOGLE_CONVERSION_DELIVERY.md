# K192 — Google conversion delivery

K192 adds a gated, owner-initiated path from a future consent receipt to Google Data Manager, with persistent delivery attempts and manual processing checks. Production provider gates remain off. This release does not perform real OAuth, upload visitor data, activate ads or claim provider acceptance.

## Owner flow

Open Google conversion delivery from conversion intake or upload access. Complete the existing Google account, conversion destination, separate upload OAuth and consent collection setup first. Explicitly prepare **future** inquiries for the displayed action. Each eligible inquiry then needs selection and separate confirmation before sending. Preparing inquiries does not send anything and does not start a background worker.

Stopping preparation remains possible locally while platform setup is unavailable. A new preparation window excludes earlier inquiries. Changes to the destination, account, upload grant or consent revision invalidate the current window; review setup and start a new window. The display contains up to 50 most recent prepared inquiries and attempts, not a complete historical export.

## Delivery boundaries

- New `KORLIX_GOOGLE_DELIVERY_ENABLED=true` is required in addition to the existing Ads and upload authorization gates. It defaults off and is not enabled by this release.
- Only Google `inquiry_submitted` receipts with explicit `measurement_v1` consent and a supported URL click identifier are eligible. No receipt backfill. Missing identifiers, declined consent, changed consent settings, archived campaigns, unpublished pages or deleted inquiries cannot send.
- Local age policy is conservative: no more than seven days old, further bounded by the selected action's click window. This does not establish actual click age or attribution; Google can reject an unknown, old or invalid click.
- `gbraid` and `wbraid` require MANY_PER_CLICK. ONE_PER_CLICK can use gclid only. This matches Google's documented processing restriction.
- The body contains one destination and one event: stable random receipt event ID as transactionId, original inquiry time, one ad identifier, adUserData consent granted and adPersonalization denied. No name, contact hash, email, phone, message, IP, user agent, location, campaign targeting, conversion value override or personalization grant is added.
- The operating account owns the saved UPLOAD_CLICKS action; productDestinationId is its exact int64 action ID represented as a string. Login account is the verified OAuth root. No partner-link/developer-token semantics are substituted.
- Before dispatch the server refreshes the separate upload credential and rechecks Google roots, exact advertiser metadata and all saved action fields. SQL then rechecks current Enterprise ownership, setup, grant, inquiry existence, consent and age.

## Durable outcome model

One attempt maximum per consent receipt. SQL serializes through the existing funnel/campaign/Ads/upload locks. Claim persists identity and starts preflight. A committed dispatch transition stores a SHA-256 of the exact body and marks the outcome uncertain **before** the sole Google HTTP write. An expired preflight is shown as stopped; it cannot be reclaimed.

| State | Meaning |
| --- | --- |
| ready | Locally eligible for explicit owner confirmation |
| ineligible | Current context, age or click type prevents sending |
| checking | Preflight claimed; no dispatch committed yet |
| blocked | Stopped before upload; no retry action is exposed |
| uncertain | Dispatch committed; no reliable request receipt recorded; never resend automatically |
| submitted | Google returned a request ID; processing not yet verified |
| processing | Google diagnostics explicitly reports processing |
| succeeded | Google diagnostics reports SUCCESS for the exact destination and one event |
| rejected | Google diagnostics reports FAILED |
| partial | Google diagnostics reports PARTIAL_SUCCESS; no full-success claim |

Even succeeded is a processing result, not proof of attribution, a sale or campaign ROI. Global provider_verified remains false. Request ID alone never becomes succeeded. Unknown/malformed responses and HTTP failures are redacted and leave conservative state. No ingestion retry exists. Status checks use GET requestStatus:retrieve with the saved request ID, one-minute SQL cooldown and single-use poll identity; they never ingest. Terminal outcomes cannot regress. Field warnings are reduced to a boolean; processing errors/warnings retain only bounded enum names and zero/one counts. No raw provider body is stored or returned.

There is an unavoidable boundary after the final dispatch commit: a subsequent local delete/disable cannot recall an HTTP request already in progress. A receipt persistence failure or owner access loss can leave uncertain state even when Google received the event. Manual Google-side reconciliation is required; this version has no operator retry, cancellation, retraction, adjustment or recovery endpoint. Do not blindly upload the transaction ID again because provider semantics can treat repeats as adjustments or duplicates.

## Database and API

CLI-created migration: `20260924213815_funnel_google_conversion_delivery.sql`.

Three service-only tables with RLS and no client policies:

- `korlix_google_delivery_settings`: explicit future window, immutable revision and current-context fingerprint.
- `korlix_google_delivery_attempts`: one attempt/event, immutable identity/context under service-role column grants; update grants only on state and outcome columns. No raw click/token copies.
- `korlix_google_delivery_observations`: append-only transitions, cascading through attempt and receipt to inquiry deletion.

`korlix_google_delivery_v1(uuid,text,uuid,jsonb)` is SECURITY INVOKER with fixed public,pg_temp search path and explicit public/anon/authenticated revokes. Only the server calls private claim/dispatch/receipt/status actions. All actions enforce current owner Enterprise access and exact campaign scope. It does not create a SECURITY DEFINER function or client RLS policy.

The migration updates three existing RPC metadata fields from not_implemented to separate_workflow: consent intake, Google destination and upload authorization. Their local-view behavior is unchanged; the UI accepts both during rollout. All other old functions are preserved.

Owner HTTP routes under `/api/funnels/:id/campaigns/:campaign_id/google-delivery`:

- GET: local status only, no provider call; maximum 30/minute.
- POST `/settings`: exact enabled/fingerprint/confirmed; shared write quota 10/minute.
- POST `/send`: exact event_id/fingerprint/confirmed; shared write quota 10/minute.
- POST `/check`: exact event_id; 10/minute plus one-minute database per-event cooldown.

Public `/api/funnels/google-delivery/readiness` exposes only configured, automatic_delivery=false and provider_verified=false. Owner endpoints are authenticated, scoped and no-store. Tokens, raw click IDs, provider request IDs and private claim data never reach the browser.

## Validation and release

Actual-migration PGlite tests run as service_role after deliberately broad hosted-style default grants. Coverage includes ownership/RLS, future-only windows, consent exclusion, immutability grants, one dispatch under concurrency, uncertain transport, preflight destination/account/entitlement/delete races, status cooldown, terminal outcomes and deletion cascade. Provider tests verify exact fixed HTTPS transport, response bounds, narrow payloads and diagnostic destination/count matching. Flutter tests exercise strict contracts, explicit confirmations, read-only refresh, uncertain outcomes, manual checks, scope changes and 1400/390/320px real-font layouts.

287 unique Google/conversion backend tests and 48 delivery/upload/destination/intake Flutter tests pass (335 total). This includes the final 13-test delivery/provider subset; it is not counted twice. Run changed-file analysis and the full JavaScript web build before publication. Frontend is backward-compatible with existing metadata; deploy it before the migration/backend rollout. Verify exact public trees/parents, migration grants/function hashes, unchanged unrelated advisor findings, both LIVE commits, anonymous 401/no-store, default-off gates and served frontend markers. Preserve autoDeploy off.

## Primary references checked 2026-09-24

- [Data Manager ingest](https://developers.google.com/data-manager/api/reference/rest/v1/events/ingest): fixed endpoint, event/ad identifier shape, request receipt, validateOnly semantics.
- [Destination](https://developers.google.com/data-manager/api/reference/rest/v1/Destination) and [destination accounts](https://developers.google.com/data-manager/api/devguides/concepts/destinations): operating and login account semantics.
- [Google Ads offline destination guide](https://developers.google.com/data-manager/api/devguides/events/google-ads/offline/send-events): action-owner mapping (search-indexed excerpt; direct retrieval was unavailable).
- [Consent](https://developers.google.com/data-manager/api/reference/rest/v1/Consent): separate ad-user-data and personalization signals.
- [Processing status](https://developers.google.com/data-manager/api/reference/rest/v1/requestStatus/retrieve): destination statuses, total record count, errors/warnings and braid restrictions.
- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) and [database functions](https://supabase.com/docs/guides/database/functions): explicit grants and invoker boundaries.

Meta delivery remains separate future work. Real provider activation and owner hands-on A–G acceptance remain deferred.
