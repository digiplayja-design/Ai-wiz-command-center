# K193 — Meta conversion destination setup

## Purpose and behavior

Owners can save a Meta data source (Pixel) listed for their active ad account and linked Meta campaign. This prepares the destination for future inquiry `Lead` events. Listing and saving do not prove Conversions API write permission, website ownership, event eligibility, receipt acceptance or attributed conversion credit. No provider settings are changed and no events are sent.

The UI opens from Conversion intake for Meta plans and from Linked Meta campaign. Opening/refreshing reads local state only. Loading data sources is explicit. Saving requires a selected source and separate confirmation; clearing has its own confirmation. Saved metadata remains readable and clearable after disconnection or archival. A failed save discards choices and requires a local refresh before any further write. Workspace/access changes remove private metadata and ignore delayed responses.

## Platform gate and provider access

The independent `KORLIX_META_CONVERSION_SETUP_ENABLED=true` gate is required alongside the existing valid Meta configuration and exact API version `v26.0`. It defaults off. This release does not enable the gate, OAuth, provider applications, ad publishing, spend or visitor uploads.

Discovery uses only GET `https://graph.facebook.com/v26.0/act_<account-id>/adspixels` with explicit `fields=id,name`, Bearer authorization and appsecret_proof. It follows only bounded `after` cursors on the fixed account edge; provider next URLs are never followed. Each response is bounded to 1 MiB and 10 seconds, with at most five pages of 100 rows. Redirects and automatic retries are disabled. Duplicate IDs, malformed shapes, unreadable names, cursor loops and incomplete oversized lists fail closed. Raw responses, pixel code/snippets, tokens and extra fields are never returned or saved.

Metadata is reduced to `{pixel_id, name}`. No manual ID input, public-node lookup, create-pixel API, browser Pixel script or event endpoint exists in this chapter. Names can repeat; identity is the ID. Successful edge membership is deliberately the only provider claim. Meta permission errors 10/200/283 produce a data source access error without invalidating the whole ads connection. Invalid OAuth 190 requires reconnect. General provider failures are redacted.

## Endpoints

- Public GET `/api/funnels/meta-conversion-destination/readiness`: configured, send_ready=false, provider_verified=false.
- Owner GET `/api/funnels/:id/campaigns/:campaign_id/meta-conversion-destination`: local context and selection; 30 requests/minute.
- Owner GET `.../choices?fingerprint=...`: live account and data source reads.
- Owner POST `.../save`: version, fingerprint, confirmed=true, destination and proof.
- Owner POST `.../clear`: version, fingerprint and confirmed=true; local only.

Choices and saves share a 10 request/minute owner limit. Clear has a separate 10 request/minute limit. Responses use no-store. Unknown body/query fields are rejected. Choices carry a five-minute HMAC over owner, funnel, campaign, context fingerprint and exact metadata. Saving repeats the live account and complete source list checks, revalidates the proof after discovery, then writes under fresh database locks. Account metadata, connection version/binding, permissions, account selection, campaign link, funnel/campaign edits, archival and entitlement changes reject stale work. Concurrent saves have one winner.

## Database

Migration: `supabase/migrations/20260924222246_funnel_meta_conversion_destination.sql`.

- New `korlix_funnel_meta_conversion_destinations`: campaign primary key/cascade, version, selected metadata, context fingerprint/snapshot, checked/saved/update timestamps.
- New `korlix_meta_conversion_destination_valid(jsonb)` validates exact metadata keys and types.
- New `korlix_funnel_meta_destination_v1(uuid,text,uuid,jsonb)` supports read/save/clear and delegates Enterprise, owner, platform and locking checks to the existing Meta campaign-link RPC.
- RLS enabled; no browser policies or privileges. Service role gets SELECT/INSERT/UPDATE, no direct DELETE. Cleared rows keep versions; campaign/funnel deletion cascades them.
- RPCs use SECURITY INVOKER, fixed public/pg_temp search paths and service-role execution only. No existing function is replaced.

The RPC trusts the internal backend to verify provider membership/proof. Service-role credentials must remain server-only. Saved timestamps describe the last live lookup; `selection_current` means local context still matches, not that provider permissions cannot change afterward. Future delivery must recheck current provider access and destination membership.

## Verification

238 backend tests and 50 frontend tests passed. New coverage comprises 19 backend cases and 11 Flutter cases. It includes gate/API-version defaults, provider response/byte/page bounds, fixed host/cursor behavior, no retry, metadata/proof forgery, cross-context replay, expiry, provider removal/renaming, account mismatch, permission versus OAuth failure, late disconnect/relink/downgrade, SQL grants, ownership, concurrency, local clear, cascade, UI confirmation, uncertain save, private scope changes, intake integration and real-font 1400/390/320-pixel layouts. Changed Dart analysis is clean. The JavaScript release build is checked separately before publication.

## Remaining delivery work

K194 should implement a separately versioned, future-only Meta consent/capture contract before actual delivery. Meta website events require browser-context fields; current K188 click-only receipts do not capture or authorize that expanded data. Do not backfill missing browser context, fabricate a user agent, hash additional contact data without scoped consent, or misclassify website inquiries as offline/CRM events. Later delivery also needs explicit provider authorization, stable event identity, deduplication/uncertainty handling, test-event processing evidence and owner acceptance. The saved source alone enables none of those actions.

## Primary references checked 2026-09-24

- [Official SDK account data-source edge](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/adaccount.py), `get_ads_pixels` GET `/adspixels`.
- [Official SDK Pixel identity fields](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/adspixel.py).
- [Official SDK account Pixel listing example](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/test/docs.py), explicit ID/name fields.
- [Meta Conversions API parameters](https://developers.facebook.com/documentation/ads-commerce/conversions-api/parameters).
- [Meta Conversions API best practices](https://developers.facebook.com/documentation/ads-commerce/conversions-api/best-practices), website event requirements.
- [Meta end-to-end implementation](https://developers.facebook.com/documentation/ads-commerce/conversions-api/guides/end-to-end-implementation), Lead event example.

Some direct Meta documentation fetches were rate limited. SDK source and indexed official documentation were used; this chapter makes no live provider-approval or event-write-permission claim.
