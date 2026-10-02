# KORLIX FieldProof

FieldProof turns technician-supplied job records into a private completion packet: original photos, starter checklists, missing-record reminders, recorded customer approval, a downloadable PDF and a copyable invoice handoff. KORLIX names the working AI agent. NOVA is reserved for AI voice.

## User flow

Open **FieldProof** from the home shortcuts or Tools. Start a job with its title, customer and site. Choose from 14 templates: Utility, Installation, Maintenance, General, HVAC, Plumbing, Electrical, Property inspection, Roofing, Cleaning, Delivery, Equipment service, Construction or Landscaping. Save technician details and the completed work; add photos from a camera or file picker and label their evidence categories. The checklist shows missing records. Add company-specific required photos or checklist items as needed.

Record customer approval when required. This is the technician's declaration, including who recorded it, the reported approver, notes, time and job revision. It is not a customer-authenticated signature. Changes to the job or photos invalidate earlier approval for closeout. Closing a job requires explicit confirmation and current required records; reopening creates a new revision.

The Report tab exports a PDF with photo previews, the original-file hash manifest, entered facts, approval status, recent activity and any current KORLIX review. Original files download individually. The invoice handoff is a text draft containing scope, hours, materials, outstanding items and billing notes. It does not issue an invoice or post to bookkeeping. Exports and customer delivery are deliberate user actions.

## K-Nova and the expanded workspace

Select **Talk to K-Nova** after saving any manual edits. The isolated live voice workspace can search your jobs, explain current missing records, prepare a new job, dictate individual fields, preserve exact readings (including leading zeros), and append unresolved follow-up items. It uses the existing LIVE CONVO allowance and explicit OpenAI consent for voice, text and field-job records. It receives photo metadata, not image bytes; the separate KORLIX photo review remains optional.

Voice drafts are unsaved. Tap **Review in FieldProof**; the app stops the microphone, transport and usage session, rechecks the selected job revision, and opens the editable form. Save there after reviewing. Voice cannot mark checks done, resolve existing issues, alter evidence requirements, approve customers, save/delete/close jobs, start a paid photo review, send reports or bill customers. Pausing, access loss and account changes discard pending voice tools; late responses cannot restore private drafts.

Jobs now include priority, work stage and due date. The dashboard supports attention/overdue filters and due-date/priority sorting. Readings preserve entered values and units. Punch-list items carry a responsible person, date, priority, blocking flag and explicit resolved status. Blocking unresolved items and a blocked work stage prevent closeout. A responsible-person label does not invite or notify that person.

**Add several photos** queues up to 12 originals at a time, with separate labels, categories and notes. Each upload uses a stable retry key; successful photos are skipped on retry. The job limit is 24 photos; storage and file-size limits remain unchanged. **Compare before & after** overlays two previews with a divider and never changes the originals. **Create follow-up job** reuses customer/site/asset context and requirements, while clearing completed work, readings, issues, checked items, photos and approvals. Reports include priority, stage, due date, readings and punch-list status.

## Optional KORLIX review

Ultra Premium and Enterprise accounts may review job details and photo previews with the application's configured GPT-6 Astra / extra-high reasoning settings. Existing AI-sharing consent is required. A completed review uses **one existing credit**, debited atomically with the saved result. Failed, interrupted or repeated requests do not debit again. Manual records and exports do not require an AI review.

The model flags unclear or missing documentation and prepares customer-report and invoice-handoff drafts. It cannot change checklists, approve a job, authenticate signatures, certify safety or workmanship, identify people, invent readings or treat photo text as instructions. Returned photo references must belong to the supplied evidence. Earlier-revision drafts are retained in history but excluded from the current export.

## Evidence and privacy

Records belong to the signed-in account. The backend authenticates each request and applies ownership on every RPC. Four RLS-enabled tables and a service-only security-invoker RPC deny direct anon/authenticated access. The private `korlix-fieldproof` bucket has a restrictive policy that remains effective even alongside broad legacy storage policies. Preview links expire after 600 seconds. JSON and authenticated downloads use `Cache-Control: no-store`; downloads verify the stored SHA-256 digest.

Original bytes are retained unchanged, including embedded metadata. A separate normalized JPEG preview, at most 1200 pixels per side, removes EXIF metadata and is used for preview, AI and PDF. Hashes detect changed bytes; they do not prove who captured an image, its capture date, location or truthfulness. Dates and serials in job details are technician-entered. The PDF labels a job as a working draft or technician-closed record, never an independent certification.

Limits: 200 jobs/account; 24 photos/job; 10 MB per still JPG, PNG or WEBP; 40 megapixels; 500 MB/account including previews; 32 checklist items, 20 readings and 16 punch-list items total. Uploads use three-minute recovery leases. An interrupted photo remains visibly incomplete and blocks closeout until retried or removed. Delete operations remove both original and preview objects before removing database records, with retryable deletion state if storage is unavailable. Administrative account deletion must remove the account's bucket objects before cascading its database records; the database cascade alone does not delete stored files.

## Operational behavior

Migrations: the repository's `*_fieldproof.sql` and `*_fieldproof_workspace_upgrade.sql`. The upgrade replaces only the photo-capacity check in the deployed RPC and guards against an unexpected prior function body. API base: `/api/fieldproof`. Health includes `fieldProof.version`, model, reasoning effort, credit cost, maximum photos and original-evidence support. No new environment variables or services are required.

Review jobs run in the existing backend process: one per account, two per process, up to 12 starts/hour/account. Reopening a screen polls the same saved review. A stale review is marked failed after eight minutes on the next FieldProof request and uses no credit. This release does not provide a durable distributed worker, crew sharing, offline synchronization, legally authenticated signatures, video evidence, automatic bookkeeping posting or automated customer delivery. It retains 20 reviews/job and 200 activity records/job, returning the newest 30 activities.

## Validation

Backend tests execute the real migration in PostgreSQL-compatible PGlite and exercise Express routes with fixture storage/provider responses: ownership, storage policy, byte integrity, upload/delete recovery, optimistic concurrency, approval revision, explicit closeout, provider consent, charge-once behavior and grounded photo references. They do not constitute a paid live model run.

Flutter tests cover saved-response validation, account changes, multipart bytes, failed saves/uploads, closeout, consent, resumed polling, private-state clearing, export inputs, explicit deletion and phone/desktop layouts. PDF generation uses bundled Apache-licensed Roboto fonts; sample output is rendered and visually reviewed before release. The first signed-in production job with real photos and an optional paid AI review remains a user acceptance check.

## Upgrade verification (2026-10-02)

- 41 backend tests: real migrations, ownership/RLS, 24-photo quota, originals, retry/revision rules, closeout blockers, exact readings, non-writing voice drafts and session-mode authentication.
- 46 distinct Flutter tests, including FieldProof widget/controller tests and Music/Bookkeeping voice lifecycle regressions cover draft review, stale revisions, microphone/transport/usage cleanup, failed cleanup, account changes, mixed/cancelled/replayed tools and batch retry identity.
- Phone (390px) and desktop (1440px) layouts at 1.25 text scale and a three-page report were rendered and visually inspected. The complete release web build passed.
- Live voice/provider audio and genuine signed-in customer evidence still require a real-device acceptance check. Fixture tests and public HTTP checks do not establish those outcomes.

Supabase advisor baseline: FieldProof tables intentionally deny direct client access and have RLS with no client policies; the service-only invoker RPC is the access boundary. Existing unrelated CRM view, legacy functions and Auth advisories predate this upgrade and are not changed here. Advisor references: https://supabase.com/docs/guides/database/database-linter and https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection.
