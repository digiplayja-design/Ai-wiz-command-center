# KORLIX legal and privacy update — 2026-10-07

Scope: current KORLIX features and controls; no trading-bot feature. This is an implementation-grounded policy update, not a legal opinion or certification of store approval.

## Source baseline and publication scope

- Frontend: `release/k135z-frontend-20260919`, starting at `d2e2e5539aae79c5b6fea5a603f601c057552333`.
- Backend reviewed: `release/k135z-backend-render-20260919`; live implementation at `4d2fb6d4fa473f68bbd83a52f82799af230f0ed8` (later branch commit changes audit documentation).
- Authoritative public pages are in this frontend checkout's `website/`, published by the existing Render static service. The backend checkout's old website snapshot is not the publishing source.
- No backend, Supabase schema, billing price, subscription entitlement or customer record changes in this update.

## Documents updated

Privacy Policy, Terms of Use, Subscription Terms, Delete Account and Data, AI Safety Policy, Community Guidelines, Child Safety Standards, Music Production Terms, Support and Reports. Added a public `legal.html` centre and links from the homepage and existing policy pages. Effective date: October 7, 2026.

The content now covers Receipt Wiz/shared finance inboxes, Workforce photo/GPS evidence and email automation, FieldProof report emails, Social albums/calls/notifications/Auto Dump, AI and approved memory, Meeting Copilot, The Pod and You, studios, calendar scheduling, CRM/imports, advertising/funnels, connected payroll and telephone providers. Existing accurate feature-specific disclosures were retained.

Important corrections:

- Receipt Wiz, Bookkeeping and Tax Prep use one receipt record, not independent backups. CSV contains extracted fields, not original images/PDFs. Receipt Vault uses account access, not a separate password.
- Social Auto Dump hides a message for that viewer; it does not delete shared content. Album `members` visibility means eligible signed-in Social members, not a selected-member allowlist.
- Agent forget/clear deactivates memory for retrieval but can retain full stored text. Main-chat note deletion is separate.
- Workforce photo and location evidence expires together (30-day default, configurable 7–90 days); attendance records persist and asynchronous cleanup can lag.
- FieldProof can send authorized PDF reports/previews through enabled email rules; exports are not exclusively device-initiated.
- Meeting AI consumes captions/transcripts and approved agent context through OpenAI; raw connected meeting audio can reach KORLIX. Participant permission and recording consent remain separate.
- Calendar connection is not mailbox access. Google Calendar/YouTube data restrictions are distinguished from explicitly authorized advertising account/campaign operations.
- Community age text now matches the implemented 16+ rule and guardian permission declaration for ages 16–17; self-declaration is not verified age or guardian identity.
- No claim of zero provider retention, universal no-training contracts, end-to-end encryption, loss-proof storage, automatic account erasure, guaranteed AI accuracy or store approval was added.

## In-app changes

- Account → Legal & Privacy opens policies and offers a confirmed reset of saved AI-sharing choices for the current account on the current device.
- Reset handles storage errors and account changes and does not claim to stop active sessions, revoke another device, undo earlier processing or pause enabled server automations.
- Inventory has a distinct `inventoryRecords` consent category so existing text/image grants cannot silently authorize business-record sharing.
- Meeting Copilot capture `listenTo` and `start` fail closed unless the authenticated route supplies current OpenAI transcript/approved-memory consent. Local iPhone speaker unlock stays synchronous with the tap; capture/data calls wait for consent.
- Workforce capture, BabyBlend and Social deletion copy now describe actual visibility, processing and recipient-copy limits.
- Signup eligibility protocol remains `2026-10-06` because the backend validates that exact protocol version; changing only the client would break signup/older clients. This identifier is not the public policy effective date.
- Existing AI notice version is retained: new provider/category pairs already prompt, and navigation/copy changes do not broaden existing stored grants.

## Evidence mapping

| Topic | Implementation reviewed |
| --- | --- |
| Receipts and shared inbox | `backend/receipt_wiz/{routes,core}.mjs`; `backend/bookkeeping/receipt_files.mjs`; `20261006171056_receipt_wiz_shared_inbox.sql` |
| Bookkeeping voice / Tax Prep | `backend/bookkeeping/voice.mjs`; `backend/tax_prep/routes.mjs` |
| Workforce evidence and reminders | `backend/workforce/{core,store,routes}.mjs`; `20260922000006_enterprise_workforce.sql`; Workforce email worker |
| FieldProof email/retention | `backend/fieldproof/{routes,emails,email_provider}.mjs`; `20261003235831_fieldproof_autonomous_email.sql` |
| Social audiences, hide/expiry, calls | `20261002033000_korlix_social_albums.sql`; `20261003183004_korlix_social_auto_dump.sql`; `backend/social/{albums,calls}.mjs` |
| Memory and account deletion | `backend/chat_memory/memory.mjs`; `backend/korlix_live_convo_agents.js`; `backend/server.js` deletion-request handler |
| Meeting/provider context | `backend/k135z_zoom/{spoken_reply,meeting_response,meeting_recordings}.cjs`; frontend `lib/meeting_copilot/` |
| Calendar / ads / payroll | `backend/scheduling/calendar_provider.mjs`; `backend/funnels/{google_delivery_provider,meta_delivery_provider}.mjs`; `backend/payroll/{routes,core,provider}.mjs` |
| Telephone bridge | `backend/korlix_vapi_nova.mjs`; telephone `responder.mjs` and `agent_bridge.mjs` |
| Payment / advertising choices | `backend/web_billing/{stripe.mjs,apple_security.mjs}`; `lib/ads/korlix_ad_consent.dart` |
| Device/account permission controls | `lib/privacy/korlix_third_party_ai_consent.dart`; `lib/privacy/korlix_privacy_settings.dart` |

Backend paths above refer to the authoritative backend checkout; migration filenames are within its migrations directory.

## Validation before publication

- Updated required frontend release gate: **141 tests passed**, including consent, signup, account deletion intake, billing, sharing, location, Workforce and the new privacy/meeting regressions.
- Agent focused privacy/Workforce suite: 52 passed. Privacy UI exercised 320px width at 2× text scale, link failure, cancellation, reset persistence/failure, account isolation/change and renewed consent.
- Meeting suite: 253/254 on the initial pass; the sole pre-existing stale source assertion was updated to include current Live Docs privacy exclusions. All six tests in that file passed on rerun, and all 26 directly affected consent/startup/route tests passed. Do not represent this as a fresh all-254 rerun.
- All 11 public entry/policy pages passed structure, unique-anchor and relative-link checks.
- Shell syntax and `git diff --check` passed.
- Existing `main.dart` lint warnings/info remain; focused new standalone privacy files had no analyzer findings.
- Render publication performs its release tests and production web compilation before replacing the live site. Native device/store validation remains separate.

## Operations and legal review still required before store submission

These are not made complete by publishing documents:

1. Confirm the registered contracting entity, business/contact address and target jurisdictions. Existing published operator name `Korlix Developer` and support email are preserved; no unverified company identity, jurisdiction, arbitration or liability cap was invented.
2. Have qualified counsel review regional consumer, privacy, employment/recording, marketing, minors and AI obligations, applicable business processor terms and international-transfer arrangements. Provider contracts/production approvals must match actual enabled integrations.
3. Confirm staffed privacy/deletion and moderation operations, identity verification, fulfillment, exceptions and completion notices. The current account route queues review rather than purging every database/object file instantly. YouTube API data must meet its specific seven-day verified-deletion/disconnection deadline independently of other records; external Google revocation/refresh has the stated 30-day handling.
4. Update and verify App Store privacy labels, Google Play Data safety, policy/deletion URLs, content/age rating, advertising choices and reviewer notes against the shipping SDKs. Website edits do not update store metadata automatically.
5. Validate the signed iPhone/iPad build's new permission flows and billing/restore/recording behaviors. A published web build is not a submitted native release.
6. Complete and demonstrate independent original-file backup/restore procedures if receipt-loss protection is offered. Database backups alone do not include object-storage receipt originals.

## Primary platform guidance checked

- Apple App Review Guidelines (including 5.1 privacy and explicit third-party AI permission): https://developer.apple.com/app-store/review/guidelines/
- Apple account deletion: https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion
- Apple privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Google Play user data: https://support.google.com/googleplay/android-developer/answer/10144311?hl=en
- Google Play account deletion: https://support.google.com/googleplay/android-developer/answer/13327111?hl=en
- Google Workspace API data policy: https://developers.google.com/workspace/workspace-api-user-data-developer-policy
- YouTube developer policies: https://developers.google.com/youtube/terms/developer-policies

No trading API, trading service or investment execution feature was introduced or promised.
