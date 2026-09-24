# K190 — Google conversion destination setup

## Purpose and limits

Conversion intake now opens **Google conversion destination** for Google campaigns. Opening reads local setup. Loading actions explicitly queries Google, and saving explicitly confirms and rechecks the selected action before storing it locally. Clearing needs confirmation and remains available after disconnect or archive. Nothing is uploaded, no Google action is created or edited, and no ad setting changes.

This chapter does not enable Data Manager access, establish provider acceptance, change consent receipts, or make delivery ready. Responses retain `send_ready:false`, `provider_verified:false`, and `delivery_state:not_implemented`. K188 consent receipts remain local, with the same awaiting-setup states and deletion behavior. No raw click identifiers or contact fields are returned here. Meta destination setup is outside this chapter.

## Eligibility and account ownership

The existing Enterprise owner and Linked Google campaign association determine the advertiser. Discovery requires a current connection, enabled nonmanager production account, editable Google campaign and current saved association. Backend configuration remains default off. No production gates or OAuth scopes change.

Using Google Ads v25 read-only search, the adapter reads the advertiser's `conversion_tracking_setting.google_ads_conversion_customer`. That conversion account owns the actions, including cross-account manager-owned actions. Requests retain the selected login-manager header; directly accessed self-owned accounts also work without that header. The adapter rechecks conversion ownership after enumeration and discards changes.

KORLIX's narrow inquiry policy lists only enabled `UPLOAD_CLICKS` actions with `SUBMIT_LEAD_FORM` category and Google last-click or data-driven attribution. This is a product policy, not a statement that Google supports no other categories. Unknown attribution models, mismatched resources/owners, malformed metadata, duplicates, more than 200 actions and incomplete pagination fail closed. Enumeration has a five-page limit; partial lists are never returned.

The screen displays action ID/name, conversion owner, click window, count mode, primary-for-goal and default value behavior. A secondary action can still influence bidding through custom goals. Saving the destination does not modify these settings. Metadata is a last-checked snapshot, not continuous verification.

## Trust and concurrency

- A five-minute HMAC proof binds actor, funnel, campaign, context fingerprint and all fourteen normalized destination fields. Browser-supplied IDs cannot select an arbitrary action.
- Save repeats current local ownership/Enterprise and account checks, decrypts/refreshes the existing connection server-side, verifies accessible roots/account, then repeats action discovery. Removed or changed action metadata rejects the choice.
- Provider results are discarded after concurrent account, authorization, campaign/link or entitlement changes. OAuth revocation marks the current version for reconnect; ordinary provider errors do not erase the connection.
- SQL locks the existing funnel/campaign/connection context and destination row. Fingerprint/version checks reject competing writes, late saves and replay. Clear keeps an incremented tombstone version. No credentials, click data or upload authorization enter the destination table.
- UI discards choices after refresh, writes, errors, scope/client changes or access denial. No action is preselected; save and clear each require confirmation. An uncertain save instructs a local refresh instead of automatic resend.
- Provider list/save share a ten-per-minute owner quota. Local reads and confirmed clears have separate bounded quotas. Private responses retain no-store and current Enterprise access checks.

## Database and API

CLI-created migration: `20260924071214_funnel_google_conversion_destination.sql`.

New table: `korlix_funnel_google_conversion_destinations`; one row per campaign, cascading with campaign deletion. RLS enabled, no client policies; explicit revokes override default grants. Only service_role SELECT/INSERT/UPDATE. No direct service DELETE grant is needed for parent cascade.

New service-only, SECURITY INVOKER functions with fixed `public,pg_temp` search paths:

- `korlix_google_conversion_destination_valid(jsonb)` validates the exact destination schema.
- `korlix_funnel_google_destination_v1(uuid,text,uuid,jsonb)` handles read/save/clear using the existing campaign-link context. No existing function is replaced.

Routes below `/api/funnels/:id/campaigns/:campaign_id/google-conversion-destination`:

| Route | Behavior |
| --- | --- |
| GET base | Local state and current context; no provider access or write |
| GET `/choices?fingerprint=...` | Bounded read-only provider discovery and signed choices |
| POST `/save` | Confirmed version/fingerprint/destination/proof; provider recheck then local save |
| POST `/clear` | Confirmed version/fingerprint; local clear without provider access |

## Verification

258 Google/conversion backend tests and 23 destination/intake Flutter tests pass. Tests exercise actual migrations under PGlite, strict role/grant boundaries, proof scope/expiry/tampering, changed provider metadata, revocation, late authorization/context changes, concurrent writes, deletion cascade, pagination and v25 transport. Frontend checks include explicit selection/confirmation, uncertain writes, scope/access loss, intake integration and real-font 1400/390/320-pixel layouts with enlarged text. Changed Dart files analyze cleanly; JavaScript production build is checked before publication.

These are automated mocks/local SQL tests and anonymous deployment checks. Real account discovery, provider upload acceptance and owner A–G acceptance remain deferred.

## Next delivery contract

Google's current Data Manager event API requires the separate `https://www.googleapis.com/auth/datamanager` OAuth scope. A saved Ads action and Ads read access do not grant it. The operating account must own the conversion action; the login account supplies authorized access. `productDestinationId` identifies the upload-click action.

Future implementation must preserve narrow click/time consent, explicitly authorize delivery, validate action compatibility/window and consent, persist immutable attempt/deduplication identity before dispatch, and distinguish transport acknowledgement from provider processing. Data Manager can treat repeated transaction IDs as adjustments, so uncertain outcomes must never be blindly retried. A request ID is not an accepted conversion; diagnostic reconciliation remains necessary. Independently verify Meta's current official contract before implementing Meta delivery.

Official references checked September 24, 2026:

- [Google Ads conversion setup and conversion-tracking ownership](https://developers.google.com/google-ads/api/docs/conversions/getting-started)
- [Google Ads conversion-tracking statuses](https://developers.google.com/google-ads/api/reference/rpc/v25/ConversionTrackingStatusEnum.ConversionTrackingStatus)
- [Google Ads attribution models](https://developers.google.com/google-ads/api/reference/rpc/v25/AttributionModelEnum.AttributionModel)
- [Official ConversionAction protobuf definitions](https://github.com/googleads/google-ads-python/blob/main/google/ads/googleads/v25/resources/types/conversion_action.py)
- [Data Manager event/destination guide](https://developers.google.com/data-manager/api/devguides/events/send-events)
- [Data Manager ingest authorization and response](https://developers.google.com/data-manager/api/reference/rest/v1/events/ingest)
