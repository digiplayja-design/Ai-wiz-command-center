# Magic Camera backend

Migration `supabase/migrations/20261030031457_magic_camera_foundation.sql` was applied to the current production database on 2026-10-30. Its version matches the database migration history; do not apply it again. This is an additive private gallery/queue/allowance schema plus extension of the existing verified companion session discriminator. It does not change hub billing tiers or Improve My Picture access.

The migration source is assembled, in order, from `schema.sql`, `billing_schema.sql`, `apple_schema.sql`, and `session_schema.sql`. Keep these fixtures and the migration identical; tests execute the fixtures in PGlite with service-role and browser-role checks.

Routes under `/api/magic-camera` require the existing authenticated Korlix session. The companion signs in under `/api/magic-account/auth/*`; a client header alone cannot obtain trial access. There is deliberately no original-file route or public storage policy. Responses never expose source paths, worker tokens, account IDs, or provider diagnostics.

`GET /api/magic-camera/requests/:key` recovers an interrupted upload response by the original request key. It returns only the same owner's non-deleted job through the public serializer. Missing keys and other owners return the same 404. This is a read-only operation and never reserves allowance, re-uploads a capture or invokes the provider. The draft foundation migration includes this action and is checked against the tested schema fixtures.

The bounded worker in the web process claims durable database jobs. Jobs survive client navigation and process restarts; a render interrupted by a server crash is expired without a charge instead of blindly retried. Multiple processes coordinate through `SKIP LOCKED` and fenced leases. Cleanup versions prevent a stale removal from confirming a newer deletion; storage operations that settle after expiry re-arm cleanup. The web service must remain running to drain the queue and retry private-file cleanup. A later dedicated worker can call the same `tick` function.

Reporting stores an actual sanitized copy of the generated image, generation ID and prompt in the existing `korlix_ai_output_reports` review queue. It acknowledges only after durable persistence. This module does not send email notifications; the team's existing private review workflow must be monitored.

Store products: `magic_camera_starter` (15/month) and `magic_camera_plus` (40/month), native bundle/package `com.korlixdeveloper.magiccamera`. Google uses existing provider credentials plus `KORLIX_MAGIC_CAMERA_BILLING_ENABLED=true`; Apple uses shared server API signing credentials, the new `KORLIX_MAGIC_APPLE_APP_ID`, and `KORLIX_MAGIC_APPLE_BILLING_ENABLED=true`. Keep sales disabled until native sandbox purchase/restore/refund checks succeed. No card or subscription is required for the two successful lifetime free photos. Pro/Ultra allowances are shared and take priority over a standalone subscription.

Sunburst max is fixed in `core.mjs`; keys remain server-side. This implementation validates output image decoding, dimensions and storage, not facial identity with a biometric system. Identity preservation is a prompt instruction, not a zero-distortion guarantee. Test real diverse portraits before production release.

Run `node --test test/magic_camera.test.mjs` and the relevant shared auth/report/billing regression tests. No real provider generation, store transaction, email, or production mutation is used by the tests.

The applied SQL contents were verified against production: SHA-256 `7a9b0be59314bcbef9991b76da538275aa1ae6d9efc43c34efb90b1160970016`.

## Verified release checkpoint

Backend commit `b3715eaeb167779d3ca278554507ac323336f14b` became live on the existing Render service in deployment `dep-dbi0nmlg1s2s73dkoil0`. The service uses `release/signup-plan-intent-20261021`, with automatic deploys disabled. The live `/api/health` check returned 200; gallery, upload recovery, and both billing status routes returned 401 without credentials. Live database checks confirmed RLS, service-only functions, a private bucket and all four restrictive storage policies. These checks do not establish a completed real generation or store transaction.

App commit `d17ef65e52c7c26785b28ce65171a02431d7b3d2` passed [GitHub Actions run 40994493237](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40994493237): standalone Android/web, shared camera tests, hub Android integration, iOS simulator, release identity checks and rejection of unsigned Android release builds. Its artifacts are review builds; the iOS simulator archive cannot be installed through TestFlight.

Remaining release work: dedicated store records, signing/provisioning, approved store products and signed purchase/restore tests, plus physical-device camera and real-provider quality/latency acceptance. Keep paid sales disabled until those checks pass.

`test/magic_camera_migration.test.mjs` applies the complete release migration after the existing companion migrations, using the production profile-function signature. It verifies preservation of existing app sessions, independent Magic Camera access and private storage even in the presence of unrelated permissive policies. It uses an isolated local database only.
