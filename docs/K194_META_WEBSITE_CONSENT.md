# K194 — Future-only Meta website consent and capture

## Outcome

Adds a separately versioned Meta website measurement choice and local receipt store. A visitor can explicitly allow the link's click identifier, inquiry time, browser user agent and published page address without query parameters. The optional checkbox starts unchecked. Declining does not prevent the inquiry. No provider request, script, Pixel cookie, contact hashing, IP collection, upload or attribution claim is added.

The independent `KORLIX_META_CONTEXT_ENABLED=true` gate defaults off. Collection also requires an owner-confirmed campaign setting, current configuration, published page/privacy URL, open Meta plan and recognized campaign link. This release leaves the production gate off. Meta provider activation and owner acceptance are separate work.

## Consent version and compatibility

`meta_measurement_v2` is distinct from K188 `measurement_v1`. Old receipts remain unchanged and cannot gain browser context later. The new version has its own settings, receipts, counts and stable event UUIDs. It describes a future `Lead` event with action_source `website`; prepared receipts are unverified local evidence, not provider delivery eligibility or acceptance.

For new recognized-link visits, active website consent takes precedence over separately enabled click-only intake. When inactive, the original click-only flow still follows its own setting. Turning website consent off does not turn off click-only intake. Existing v1 forms can finish only under their original policy; their encrypted contexts cannot be converted to v2. Google consent and delivery behavior remain unchanged.

The exact disclosure is generated consistently in the public form and SQL receipt:

> Optional: I allow [brand] to store and share with Meta the advertising click identifier from this link, the time of this inquiry, my browser information (user agent), and this page's address without query parameters, to measure advertising results. My name, email, phone, message and IP address are not included. I can send my inquiry without agreeing.

This disclosure authorizes only the listed fields for measurement; it does not enable sending. Guided review signs the policy envelope and consent choice together with the normalized inquiry. Editing or removing consent/context after review fails validation. The encrypted envelope remains bound to the form token and expires after 30 minutes.

## Capture and data minimization

The application reads the final submission's User-Agent header only after affirmative v2 consent, with a supported fbclid, and while the platform gate is enabled. It accepts 1–1024 printable ASCII characters without leading/trailing whitespace. Missing, oversized or invalid input is never truncated or replaced with a synthetic agent. The header and URL click identifier remain unverified client inputs.

The event page address is constructed from the validated configured HTTPS origin and published funnel slug. Host, Referer, forwarded headers, form-supplied URLs and query parameters are not used. It is the canonical published address, not a browser-reported full URL. The configuration rejects credentials, paths, queries, fragments, nondefault ports, localhost and numeric IP origins. The actual public origin must be reviewed before activation.

Four mutually exclusive receipt states:

| State | Meaning | Retained click/browser/page data |
|---|---|---|
| declined | Visitor did not opt in | None |
| missing_click | Consent granted; no supported unique fbclid | None |
| missing_browser | Consent and click present; browser context unavailable | None |
| prepared | Complete bounded evidence after consent | Click ID, first observation time, final User-Agent and canonical page URL |

All receipts retain the exact disclosure, privacy URL, page version, setting revision and original inquiry time. Name, email, phone, message and IP are excluded from measurement receipt columns. The normal inquiry/CRM still retains the contact details requested by the visitor's separate contact consent. Aggregate owner reports never expose click IDs, user agents, page addresses or event UUIDs.

Capture is part of the same database transaction as inquiry/CRM, followup, outcome and recognized-link attribution. First submission wins: retries and concurrent replay cannot add a receipt, change consent or add browser evidence. A lost response can be retried without duplication. Receipt insertion failure rolls the whole inquiry transaction back. Cleanup cascades receipts, and existing removed-request tombstones prevent replay from recreating them.

Owner disable/re-enable changes the settings revision; pending old forms still submit an inquiry but produce no new v2 receipt. Configuration/origin changes suspend collection until renewed. Evidence must come from a form observed after the setting was enabled. There is no history scan, backfill, edit or recovery endpoint.

## Owner interface and API

Meta website consent opens from Meta conversion destination or Conversion intake. Opening and refresh read local state only. Enable and disable each require a separate confirmation checkbox. The screen reports 7/30/90 UTC daily counts, including the incomplete current day. Four states reconcile to the receipt total. Scope/access changes remove private data and discard late results. Write failures require a fresh read before further action; no POST is automatically retried.

- Public GET `/api/funnels/meta-website-consent/readiness`: configured; send_ready=false; provider_verified=false.
- Owner GET `/api/funnels/:id/campaigns/:campaign_id/meta-website-consent?days=30`: local report, 30/minute.
- Owner POST `.../settings`: enabled, expected_revision, days, confirmed=true; 5/minute.

Unknown query/body fields, duplicate windows and unsupported values are rejected. All API and public form responses retain no-store behavior. This chapter adds no provider-network dependency to the ordinary default-off public flow.

## Database

Migration `supabase/migrations/20260924224119_meta_website_measurement_consent.sql` adds:

- `korlix_meta_measurement_settings`: campaign cascade, enabled flag, revision, configuration hash, canonical origin and armed timestamp.
- `korlix_meta_measurement_receipts`: inquiry cascade, stable event UUID, campaign, policy/evidence, original timestamp and bounded receipt state.
- `korlix_meta_measurement_v2(uuid,text,uuid,jsonb)`: read/settings/resolve/capture.

RLS is enabled; browser roles have no table privileges or policies and cannot execute the function. Service role has SELECT/INSERT/UPDATE on settings, SELECT/INSERT only on receipts, and no direct DELETE on either. The invoker RPC uses fixed public/pg_temp search paths and locks funnel/campaign/settings around capture and changes. The backend supplies trusted platform configuration and canonical origin; direct service-role callers must preserve that boundary. No preexisting function or table definition is replaced.

## Verification

178 unique tests passed: 131 backend and 47 Flutter. New cases: 22 backend and 13 Flutter. They exercise consent/no-consent, complete and missing context, hostile headers/body metadata, byte/character limits, default-off gate, canonical origin validation, old/new policy separation, immutable snapshots, no backfill, expiry, guided review, stale settings, concurrent replay, lost response, rollback, deletion/tombstones, entitlement, rate limits, strict UI contracts, confirmation, local entry points and 1400/390/320 layouts with real fonts/increased text size. Changed Dart analysis is clean. JavaScript release build passed in 61.6 seconds; existing ua_client_hints Wasm dry-run warning remains.

## Next

K195: Meta delivery authorization, current destination/access preflight and an explicit one-attempt delivery workflow, with stable event identity, duplicate/uncertain-request handling and provider test evidence. Existing prepared rows are not a promise of delivery or attributed results. Real provider setup, visitor uploads, ads/spend, outreach and owner A–G acceptance remain deferred.

Primary references checked 2026-09-24: [Meta server event parameters](https://developers.facebook.com/documentation/ads-commerce/conversions-api/parameters), [Meta customer information parameters](https://developers.facebook.com/documentation/ads-commerce/conversions-api/parameters/customer-information-parameters), and [Supabase database functions](https://supabase.com/docs/guides/database/functions). Meta's indexed official documentation requires client_user_agent, action_source and event_source_url for website events. This chapter supplies only future consented local capture; provider compatibility will be validated in delivery work.
