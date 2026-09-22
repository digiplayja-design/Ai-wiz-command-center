# K139 · Enterprise NOVA Funnel Studio

First release: three editable landing-page templates, NOVA copy generation through the existing Astra provider, saved drafts, deliberate publication, a public inquiry form, transactional CRM capture, campaign links and lead-source reporting. The Flutter editor is under Utility → Funnel Studio for Enterprise users.

## Deployment and rollback

Apply `enterprise_funnel_studio` before deploying the backend. It adds three private RLS tables, one service-only RPC, and the `funnel` CRM source. The frontend uses `/api/funnels` with the current Supabase access token. Anonymous visitors only use `/f/:slug` and its form endpoint.

Deploy the backend release before the frontend release. Both use the existing Render services and require no new paid infrastructure. `OPENAI_API_KEY` is reused. Optional `KORLIX_FUNNEL_PUBLIC_BASE_URL` overrides the existing backend origin. Optional `KORLIX_FUNNEL_FORM_SECRET` supplies a stable random HMAC secret across restarts/instances; otherwise the single-instance service generates an ephemeral secret. Open forms must be reloaded after a restart in that mode. Configure a shared secret before scaling to multiple instances.

Rollback by deploying the previous frontend/backend commits. Keep the additive migration and captured leads. Do not drop tables to roll back UI. Pausing a page disables public capture; drafts and historical leads remain. Saved drafts never change the published snapshot until the owner confirms publication again.

## Access and data handling

- Every owner command checks current `user_profiles.tier` and owner identity in PostgreSQL. Browser roles have no table or RPC grants.
- Public access checks both publication and the owner's current Enterprise tier. Only the published document is returned.
- Form submission needs a signed, cookie-bound, page-version-bound nonce, a 1.5-second minimum form age and a 30-minute maximum. Replay is idempotent. Hidden honeypot, body/text limits, rate limits and a 2,000 submissions/funnel/day cap reduce basic abuse. These do not constitute identity verification or comprehensive bot protection.
- New contacts are marked `source=funnel`, `category=lead`, with inquiry-only transactional email consent. Calling permission remains `none`; marketing is not opted in. Phone identifiers are unverified and not normalized into the calling match key.
- Existing contacts and their suppression/permissions are never modified by anonymous submissions. No email recipient, automation rule, call, email or ad is created by submitting or publishing.
- Form messages and UTM tags live in the private lead inbox. Identities and tags are visitor-supplied. Do not use them as verified facts. No cookies for advertising, third-party pixels, or tracking scripts are added.
- Counts are page requests (including bots and repeats) and submissions, not unique visitors, verified customers, revenue or multi-touch attribution.
- Owner data follows the existing account lifecycle: funnel deletion cascades lead rows, account deletion cascades funnels. Archiving a CRM contact does not delete its funnel inquiry. Dedicated lead deletion/retention controls remain a follow-up before broad rollout.
- Up to 50 funnels per owner; latest 100 leads and top 50 source/campaign groups shown. NOVA allows 10 attempts per owner per UTC day; failed generation attempts count. No streaming or automatic publication.

## Verification

`node --test test/funnels.test.mjs test/contacts_crm.test.mjs`

Tests execute both actual migrations in PGlite and the Express routes through HTTP. They cover role grants, ownership, downgrade and pause, snapshot isolation, version conflicts, publication consent, CRM permission preservation, nonce and cookie validation, expiration, retry deduplication, UTM capture, HTML escaping, unsafe URL rejection, and AI entitlement/budget enforcement. No external AI requests or real outreach occur.

Flutter: `flutter test test/funnel_studio_test.dart test/contacts_crm/contacts_screen_test.dart`; `flutter analyze lib/funnel_studio test/funnel_studio_test.dart`; `flutter build web --release --base-href=/app/`.

## Next stages (not implemented in this release)

1. Multi-step journeys, media uploads, domain mapping, lead retention/deletion UI, exports, stronger bot protection and verified contact ownership.
2. Approved NOVA email/call follow-up rules connected to CRM consent and suppression; booking and Workforce-aware routing. The existing CRM remains the manual review and handoff point today.
3. Integrated Ads Manager: Meta first, then Google. OAuth, platform approvals, account isolation, budget caps, explicit campaign review, pausing, spend retrieval and attribution reconciliation. Tracking links already work with ads created externally; this release does not launch ads or spend money.
4. A/B experiments, source-backed recommendations, Zoom-to-campaign drafts, approved agent-memory context, rehearsal, profit/cost reporting and agency roles.

Planning estimate remains 3–4 weeks for the broader private beta and 8–12 weeks for the advanced release with three engineers and shared design/QA. Ads integrations add approximately 4–8 engineering weeks; platform approval time is external.
