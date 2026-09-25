# K195 — Explicit Meta conversion delivery

K195 adds separate conversion authorization and one explicit send per future, consenting website inquiry. Meta developer setup remains paused. The platform delivery gate defaults off; this release does not activate it, start OAuth, upload real visitors, publish ads or spend money.

## Owner workflow

Open **Meta conversion delivery** from Conversion intake or Meta conversion destination. Opening and refreshing read saved local state only. The saved Meta data source, current Enterprise owner access, linked campaign, published page/privacy URL and enabled K194 website consent must be current.

When platform activation is completed separately, the owner supplies a system-user token for the configured KORLIX Meta app with `ads_management` and access to the selected Pixel/data source. Its field is obscured, not autofilled, and cleared on submission, refresh or workspace/access changes. An explicit authorization confirmation is required. Saved status never returns the token or encryption envelope. Replacing or disconnecting access stops the current window. Disconnecting the base Meta connection deletes the conversion credential.

The existing advertising USER token is used only for account/data-source membership reads; it is never used to upload conversions. The separate SYSTEM_USER token is checked with Meta debug_token for app ID, validity, scope, identity and expiry, then the exact selected Pixel identity is read. Scope and readable identity are preflight evidence, not proof that an event write will be accepted. Token authorization does not send an event.

**Prepare future Meta inquiries** requires a separate confirmation and creates a new window. Only prepared, explicitly granted `meta_measurement_v2` receipts captured after that window, under its current consent revision, are eligible. Earlier inquiries, click-only v1 receipts and incomplete or declined receipts are excluded. Every send requires selecting one inquiry and a separate confirmation. No background upload or retry worker exists.

## Payload and evidence

Graph API v26.0 receives one `Lead` event at `/{pixel_id}/events`: original inquiry Unix time in seconds, stable random event UUID, `action_source=website`, canonical HTTPS page URL without query parameters, bounded original browser User-Agent, and `fbc=fb.1.<original-observation-milliseconds>.<original-case-sensitive-fbclid>`. The event is at most seven days old. No names, emails, phone numbers, inquiry messages, IP addresses, contact hashes, fabricated fbp cookies or test-event code are included. Advertising click identifiers and browser context are still visitor information and require the K194 disclosure and affirmative consent.

A local attempt is claimed once. Current token, account and data-source membership are rechecked before dispatch. A second transaction checks entitlement, campaign, destination, consent, window, grant and inquiry existence. It commits the uncertain state and SHA256 of the exact event body before the only events POST. Concurrent requests cannot claim the same receipt. A lost response, process interruption or uncertain provider outcome is never retried. Failures before dispatch become blocked. Lost database responses can conservatively leave an uncertain attempt even when no POST occurred.

A validated `events_received=1` response stores only a bounded trace identifier and warning flag, with append-only state observations. Provider messages are discarded. **Received means a receipt only: matching, processing, attributed credit, revenue and sales remain unverified.** Review matching and attribution separately in Meta Events Manager. There is no invented automatic processing-check API. Stopping or disconnecting prevents future dispatches but cannot recall a request already dispatched. Deleting an inquiry cascades local delivery evidence; it cannot erase data already sent to Meta.

The owner sees up to 50 recent rows with stable references and ready, ineligible, checking, blocked, uncertain or received labels. Pending checks older than two minutes are shown as blocked. Changing workspace, client, campaign or access clears private UI state and discards late responses. A write failure performs one local status read; it never repeats the write.

## API, configuration and storage

- Public: `GET /api/funnels/meta-delivery/readiness` (no-store; configured false by default, automatic_delivery false, provider_verified false).
- Owner: `GET /api/funnels/:id/campaigns/:campaign_id/meta-delivery` and POST suffixes `/authorize`, `/disconnect`, `/settings`, `/send`.
- All writes require an exact current fingerprint and explicit confirmation. Inputs are exact-field validated, owner/Enterprise scoped and rate limited. Internal credential, claim, dispatch and receipt commands have no HTTP endpoints.
- `KORLIX_META_DELIVERY_ENABLED=true` is a new independent, default-off gate. The existing Meta configuration must be complete and pinned to v26.0, `KORLIX_META_CONVERSION_SETUP_ENABLED=true` must be active, and K194 `KORLIX_META_CONTEXT_ENABLED=true` must be active for a window to become send-ready. Existing measurement prerequisites remain required.
- Four service-only RLS tables: `korlix_meta_delivery_connections`, `korlix_meta_delivery_settings`, `korlix_meta_delivery_attempts`, `korlix_meta_delivery_observations`.
- The credential is AES-256-GCM encrypted and bound to owner, campaign and a random grant UUID. It is separate from advertising authorization and cannot be transferred between contexts.
- `korlix_meta_delivery_v1` is SECURITY INVOKER with a fixed public/pg_temp search path, service-only EXECUTE, exact commands and consistent parent-to-child locks. Browser roles have no table privileges or policies. Attempt updates are column-limited; observations are append-only. No historical receipt or existing function body is changed.
- Migration: `20260925002037_funnel_meta_conversion_delivery.sql`. Apply once to the existing project. All prior migrations remain required.

For compatibility, the older destination endpoint retains its legacy `delivery_state=not_implemented` marker and `send_ready=false`: that endpoint only stores destination identity. The new delivery endpoint is the authoritative delivery status. Website-consent and intake status continue to describe collection only.

## Platform activation, deferred

Complete Meta app and business setup, appropriate review/access, configured app secrets and system-user/data-source assignments before activating the gates. Meta's platform guide specifies Advanced Access, Marketing API Access Tier and `ads_management`, `pages_read_engagement`, `ads_read` permissions for its platform integration. For own/managed Pixels, assign the system user Manage Pixel as appropriate. This manual system-user credential route is not a completed Meta Business Extension onboarding flow. Verify the actual token response and expiry representation in a separately authorized integration exercise; unexpected representations fail closed.

Test-event codes are not treated as a harmless sandbox: Meta documents that such events can flow into measurement and targeting. This release uses mocks and local database fixtures, with no real provider event uploads. Public origin/privacy content, real authorization, live integration and owner acceptance remain separate unfinished work.

## Verification

31 new backend tests cover provider payload/response bounds, exact system-user access, future-only consent, encrypted storage, owner roles, concurrent sends, lost provider/database responses, changed setup/entitlement, data-source removal, expiry, blocked/uncertain evidence, deletion and default-off gates.

16 new Flutter tests cover strict status contracts, credential hiding/clearing, exact explicit authorization/settings/send/disconnect bodies, local recovery without retry, both entry points, access/scope changes and real-font layouts at 1400, 390 and 320 pixels (1.3 text scaling at 320). The release regression run passed 189 unique tests: 126 backend and 63 Flutter. Related Meta, consent, intake and Google delivery behavior remains covered. Changed Dart analysis is clean; deployment evidence is recorded in the K195 checkpoint.

## Primary references

Retrieved September 25, 2026. Meta documentation HTML was rate-limited; its official Markdown representations were retrieved successfully.

- [Conversions API for platforms](https://developers.facebook.com/documentation/ads-commerce/conversions-api/set-up-conversions-api-as-a-platform.md)
- [Using the Conversions API](https://developers.facebook.com/documentation/ads-commerce/conversions-api/using-the-api.md)
- [fbc and fbp parameters](https://developers.facebook.com/documentation/ads-commerce/conversions-api/parameters/fbp-and-fbc.md)
- [Supabase database functions](https://supabase.com/docs/guides/database/functions)
