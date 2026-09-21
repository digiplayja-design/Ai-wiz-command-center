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
