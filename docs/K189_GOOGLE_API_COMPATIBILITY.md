# K189 — Google API access and Search language compatibility

Reviewed September 24, 2026. This release updates API compatibility; it does not activate provider access, create live advertising, change budgets or upload conversions.

## Cloud project access

Google's [current access guidance](https://developers.google.com/google-ads/api/docs/api-policy/developer-token) says developer tokens sunset on September 9, 2026. Existing headers are optional and ignored, so their presence alone does not prove an existing integration is broken. Access levels now belong to the Google Cloud project that owns the OAuth client. Future major API versions will reject the obsolete header.

The backend no longer reads, hashes or sends `KORLIX_GOOGLE_ADS_DEVELOPER_TOKEN`. Configuration requires explicit `KORLIX_GOOGLE_ADS_ACCESS_MODEL=cloud_project`, the existing `KORLIX_GOOGLE_ADS_ENABLED=true` gate, valid OAuth client credentials, a separate 32-byte encryption key, exact HTTPS callback and API version (currently v25 for mutation adapters). No production environment variable is changed by this release. Removing the token requirement cannot enable a deployment missing the new explicit access model.

Configuration readiness does not establish Google Cloud production access, OAuth verification, account permissions or measurement capability. Operators must check the project's Google Ads API access level in Google Cloud Console before enabling it. The new configuration hash deliberately requires reconnecting old stored authorizations and refreshing dependent account selections/reviews. Credential rows and historical campaign records are not rewritten. Changes to a retired token no longer invalidate connections.

Structured `CLOUD_PROJECT_NOT_APPROVED_FOR_PRODUCTION` failures return fixed project-approval guidance without copying remote details or marking the user's OAuth connection revoked. Actual OAuth invalid_grant/401 still follows the existing reconnect path. Fixed hosts, bounded responses, manager headers, redaction and no automatic mutation retries remain enforced.

## Versioned Search language behavior

Google's [August 13 announcement](https://ads-developers.googleblog.com/2026/08/google-ads-language-targeting-changes.html) and [deprecation schedule](https://developers.google.com/google-ads/api/docs/deprecations) describe the late-September removal of manual language targeting in Search. New language criterion mutates can fail; existing criteria remain queryable. Search language matching uses the ads and landing-page content.

Migration `20260924034142_funnel_google_search_language_contract.sql` replaces only `korlix_funnel_google_create_v1(uuid,text,uuid,jsonb)`, preserving SECURITY INVOKER, fixed search_path, service-only execution, transaction locks, current entitlement/review checks and the durable one-dispatch slot. New drafts and claimed snapshots include `search_language_mode: automatic_from_creative_v1`. Fingerprints include the marker, so a pre-migration confirmation cannot dispatch. No tables or historical rows are altered.

The new compiler omits every manual language criterion while preserving geographic targets/exclusions, keywords, ad copy, URLs, dates, exact budget and all three PAUSED delivery levels. Content language choices remain planning notes and a preparation completeness requirement. Unknown or malformed language modes fail before provider calls.

Unversioned historical snapshots compile under the original contract for read-only reconciliation/control inspection. They cannot enter either validate-only or actual campaign creation. Saved snapshot and request hashes remain unchanged. Reconciliation continues to compare exact expected criteria for each version; it does not broadly ignore changed or unexpected language/geographic criteria. Existing status/budget controls do not mutate language criteria. The UI distinguishes automatic matching from historical manual settings and rejects stale current drafts.

## Verification and remaining work

Automated checks cover real SQL migration/claims, stale confirmations, unchanged historical records, request hashes, role denial, concurrent dispatch and uncertain recovery, OAuth/project errors, transport headers, strict reconciliation, UI legacy/current validation and responsive layouts. Reporting fixtures reset their rate counters without artificially advancing across the database's reporting day.

Provider gates remain off; actual Google account approval and owner A–G acceptance remain deferred. This release does not establish live provider acceptance. Conversion destination setup and Google Data Manager / Meta delivery with accepted, rejected and uncertain receipts remain future work. Follow the [current Google conversion guidance](https://developers.google.com/data-manager/api/devguides/events/google-ads/offline) before implementing delivery.
