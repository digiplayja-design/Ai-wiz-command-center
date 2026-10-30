# Magic Camera backend

Apply `supabase/migrations/20261030003135_magic_camera_foundation.sql` to the current production backend database only after review. This is an additive private gallery/queue/allowance schema plus extension of the existing verified companion session discriminator. It does not change hub billing tiers or Improve My Picture access.

The migration source is assembled, in order, from `schema.sql`, `billing_schema.sql`, `apple_schema.sql`, and `session_schema.sql`. Keep these fixtures and the migration identical; tests execute the fixtures in PGlite with service-role and browser-role checks.

Routes under `/api/magic-camera` require the existing authenticated Korlix session. The companion signs in under `/api/magic-account/auth/*`; a client header alone cannot obtain trial access. There is deliberately no original-file route or public storage policy. Responses never expose source paths, worker tokens, account IDs, or provider diagnostics.

`GET /api/magic-camera/requests/:key` recovers an interrupted upload response by the original request key. It returns only the same owner's non-deleted job through the public serializer. Missing keys and other owners return the same 404. This is a read-only operation and never reserves allowance, re-uploads a capture or invokes the provider. The draft foundation migration includes this action and is checked against the tested schema fixtures.

The bounded worker in the web process claims durable database jobs. Jobs survive client navigation and process restarts; a render interrupted by a server crash is expired without a charge instead of blindly retried. Multiple processes coordinate through `SKIP LOCKED` and fenced leases. Cleanup versions prevent a stale removal from confirming a newer deletion; storage operations that settle after expiry re-arm cleanup. The web service must remain running to drain the queue and retry private-file cleanup. A later dedicated worker can call the same `tick` function.

Reporting stores an actual sanitized copy of the generated image, generation ID and prompt in the existing `korlix_ai_output_reports` review queue. It acknowledges only after durable persistence. This module does not send email notifications; the team's existing private review workflow must be monitored.

Store products: `magic_camera_starter` (15/month) and `magic_camera_plus` (40/month), native bundle/package `com.korlixdeveloper.magiccamera`. Google uses existing provider credentials plus `KORLIX_MAGIC_CAMERA_BILLING_ENABLED=true`; Apple uses shared server API signing credentials, the new `KORLIX_MAGIC_APPLE_APP_ID`, and `KORLIX_MAGIC_APPLE_BILLING_ENABLED=true`. Keep sales disabled until native sandbox purchase/restore/refund checks succeed. No card or subscription is required for the two successful lifetime free photos. Pro/Ultra allowances are shared and take priority over a standalone subscription.

Sunburst max is fixed in `core.mjs`; keys remain server-side. This implementation validates output image decoding, dimensions and storage, not facial identity with a biometric system. Identity preservation is a prompt instruction, not a zero-distortion guarantee. Test real diverse portraits before production release.

Run `node --test test/magic_camera.test.mjs` and the relevant shared auth/report/billing regression tests. No real provider generation, store transaction, email, or production mutation is used by the tests.
