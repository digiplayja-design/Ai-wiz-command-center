# Enterprise Contacts CRM

Contacts CRM is added to Enterprise Utility and the Enterprise Agent Hub. It has contact counts, relationship categories, server-side search/filtering/pagination, favorites, notes, tags, follow-up dates, edit/archive, import previews and duplicate detection.

## Installation order

1. Apply `supabase/migrations/20260921162128_enterprise_contacts_crm.sql` to the same Supabase project as the backend. It depends on the existing `user_profiles` and Agent Email migrations. The migration runs in one transaction. Do not run an unfiltered database push from an old worktree.
2. Deploy the backend commit to the backend release branch.
3. Deploy the frontend commit to the frontend release branch.
4. Open Utility → Contacts CRM with an Enterprise account. Check a non-Enterprise account receives HTTP 403 at `/api/contacts`.

No new production dependency or environment variable is required. ExcelJS is already a pinned backend dependency. No customer contacts, email or calls were used for development tests.

## Imports

- CSV/TSV and Excel `.xlsx`: headers include Name, Phone, Email, Status, Company, Notes, Tags. Google/Outlook common export headers are also recognized. First worksheet only. Tags use semicolon separators.
- Phone: direct Contact Picker in browsers that expose it; otherwise import a `.vcf` export. First phone and email per vCard; plain UTF-8 vCards, not legacy quoted-printable vCards.
- Email: Google/Outlook exported contact files, or copy existing approved Nova Email recipients. No Gmail/Outlook OAuth or automatic sync is included.
- Facebook: exported friends JSON (`friends_v2`/`friends`) or contacts CSV. Names-only exports remain names-only; no friends-list scraping or invented email addresses.
- Maximum 1,000 records, 2 MB file, bounded Excel expansion. Review/select contacts before saving. Importing never grants email or call permission.
- Active contacts with matching normalized phone or email are skipped, including repeated imports. Name-only records deduplicate by name/source. Duplicates are not merged or overwritten.

## Nova

Email linking uses the existing `saveRecipient` service, configured Nova account ownership and existing suppression/reactivation checks. It then opens Email Center, where existing drafts or autonomous rules can be used. Linking does not send an email. Imported records need explicit permission before being linked from CRM. An existing independently approved Email Center recipient is not revoked merely by being imported.

**Outbound Nova calling remains disabled by the existing server.** CRM stores call permission and a call brief, exposes a Call ready segment and prepares/copies the brief. It does not call Vapi or queue a fictitious call. Enabling an outbound provider workflow with an approved caller number is a separate activation step.

Do not contact, archiving, removing email permission, and changing an email suppress linked recipients through a database trigger. A recipient trigger also prevents concurrent linking/reactivation from bypassing current CRM restrictions. Clearing a block does not automatically reactivate previously suppressed recipients.

## Access and persistence

Every API endpoint requires a verified session and freshly reads `user_profiles.tier`. The server enforces exact Enterprise membership. Every read and write scopes the verified user ID; client owner IDs are ignored. Browser/native clients have no direct table or RPC grants, RLS is enabled, and only `service_role` accesses storage through the backend. Contact data is not written to browser preferences. Updates use versions to avoid overwriting concurrent edits. Import RPCs are atomic except intentionally skipped uniqueness collisions.

## Checks

```
node --test backend/test/contacts_crm.test.mjs
npm install --prefix /tmp/korlix-crm-db-check --no-audit --no-fund @electric-sql/pglite@0.5.8
KORLIX_CRM_TEST_DEPS=/tmp/korlix-crm-db-check node backend/tools/test_contacts_schema.mjs
```

Frontend: `flutter test test/contacts_crm`, `flutter analyze lib/contacts_crm`, and `flutter build web --release`. Widget checks cover phone/tablet/desktop widths, edit validation, imports, search/category queries, Enterprise denial and clearing contact data after access revocation. Database checks run on isolated PostgreSQL via PGlite, never on production.

## CRM autonomous email and Rici (October 2026)

Apply `20261004115009_crm_autonomous_email.sql` before deploying this backend and its frontend. All three added tables have RLS enabled and browser grants revoked; the service-only RPC enforces ownership, fresh Enterprise access, current permission and versioned dispatch claims.

- CRM → **Autonomous email** creates one editable rule per contact (up to 500 rules). Saving always pauses the rule and invalidates unsent drafts. Explicitly enable it after reviewing the recipient and exact message.
- Rules use the contact's follow-up calendar date, selected IANA timezone and a four-hour sending window. Due dates up to seven days old are included. Review mode creates a draft; automatic mode sends the saved transactional follow-up. Contact/date pairs dispatch at most once, including after editing or re-enabling a rule.
- The scheduler runs once a minute, bounded to ten dispatches per pass. Claims, final authorization, 100/account/rolling-24h quota, immutable dispatch history, suppression and leases are database-backed. Ambiguous delivery outcomes become `unknown` and are never automatically resent. Explicit provider rejection is `blocked`; editing a sent or attempted date cannot duplicate it.
- Contact email permission is required; imports cannot grant it. Changes to the contact or its version block queued messages at final authorization. Reply-to comes from the owner's verified auth account. Signed Resend events update delivery state; bounce/complaint/unsubscribe stop further CRM email to that address from that owner. Stop links require a POST. Existing verified Resend configuration is reused; this is independent of the single-owner Agent Email binding.
- CRM → **Rici** opens the existing metered Live Voice with five isolated CRM tools. They search authorized contacts, summarize due follow-ups and prepare notes, dates or email drafts. No voice tool sends email, enables rules, grants consent, archives records or places calls. App-returned drafts are version-pinned and reviewed in the normal editable screens. Account changes discard private data and stop capture.
- The CRM AI consent describes contact details, notes and follow-up records sent to OpenAI. Retrieval is bounded to 25 contacts per lookup and 1,000 characters of notes. The due-contact search uses UTC; autonomous email uses the rule's selected timezone.

Regression checks: `node --test backend/test/crm_email_schema.test.mjs backend/test/crm_voice_email.test.mjs backend/test/contacts_crm.test.mjs backend/test/workforce_voice.test.mjs backend/test/workforce_emails.test.mjs backend/test/fieldproof_email_provider.test.mjs`; Flutter CRM widgets plus CRM/Workforce voice lifecycle suites. All tests use synthetic contacts and mocked email/voice transports; they do not send real messages.

## Automatic business listing imports (October 2026)

Apply `20261004122927_crm_directory_auto_pull.sql` before deploying this backend and its frontend. It requires the existing Contacts CRM and Business Directory migrations. No new production dependency, API key, environment variable or AI credit charge is added.

- CRM → **Auto-pull listings** imports published listings from the **KORLIX Business Directory**. External directories such as Google or Yelp are not connected.
- Filter by keyword, business category, city/service area, country or current verified status. Country matches the full published country name, ignoring case. **Preview matches** shows up to 25 candidates without creating contacts. **Enable auto-pull** and **Pull now** save the displayed filters automatically after confirmation, including the initial default selection. **Save filters** alone pauses automatic imports. **Pause auto-pull** remains available while filters are being edited and preserves those unsaved edits.
- Each run adds up to 100 new matching listings as leads. Enabled accounts run hourly, starting with the next scheduler pass. The server checks for due accounts once a minute, at most ten per pass, with database locks to prevent concurrent duplicate runs. Enterprise access and public listing visibility are checked again at import time.
- Only public business details are copied: name, available email/phone, category, website, address, city, country, service area, description and public contact name. Private drafts, owner profiles, billing and verification evidence are excluded.
- Matching listing identity, email or normalized phone is skipped, including archived CRM contacts. Existing contacts and personal edits are preserved; later listing changes do not overwrite imported records. Imported records use the **Business Directory** source and can be viewed from this screen.
- Imports leave email and call permission unset and do not create a follow-up date, email rule or outgoing message. The settings table has RLS enabled and no browser grants; both import functions are restricted to the backend service role. Settings changes use optimistic versions and all operations derive the owner from the verified session.

Checks: `node --test backend/test/crm_directory_sync.test.mjs backend/test/contacts_crm.test.mjs backend/test/directory.test.mjs backend/test/directory_routes.test.mjs`, `flutter test --no-pub test/contacts_crm`, and `flutter build web --release --base-href /app/ --no-pub`. Tests use synthetic listings in an isolated PostgreSQL database and mocked API responses; no real accounts are enabled or imported during release verification.
