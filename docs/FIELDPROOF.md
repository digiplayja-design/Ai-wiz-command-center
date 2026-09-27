# KORLIX FieldProof

FieldProof turns technician-supplied job records into a private completion packet: original photos, starter checklists, missing-record reminders, recorded customer approval, a downloadable PDF and a copyable invoice handoff. KORLIX names the working AI agent. NOVA is reserved for AI voice.

## User flow

Open **FieldProof** from the home shortcuts or Tools. Start a job with its title, customer and site. Choose Utility, Installation, Maintenance or General. Save technician details and the completed work; add photos from a camera or file picker and label their evidence categories. The checklist shows missing records. Add company-specific required photos or checklist items as needed.

Record customer approval when required. This is the technician's declaration, including who recorded it, the reported approver, notes, time and job revision. It is not a customer-authenticated signature. Changes to the job or photos invalidate earlier approval for closeout. Closing a job requires explicit confirmation and current required records; reopening creates a new revision.

The Report tab exports a PDF with photo previews, the original-file hash manifest, entered facts, approval status, recent activity and any current KORLIX review. Original files download individually. The invoice handoff is a text draft containing scope, hours, materials, outstanding items and billing notes. It does not issue an invoice or post to bookkeeping. Exports and customer delivery are deliberate user actions.

## Optional KORLIX review

Ultra Premium and Enterprise accounts may review job details and photo previews with the application's configured GPT-6 Astra / extra-high reasoning settings. Existing AI-sharing consent is required. A completed review uses **one existing credit**, debited atomically with the saved result. Failed, interrupted or repeated requests do not debit again. Manual records and exports do not require an AI review.

The model flags unclear or missing documentation and prepares customer-report and invoice-handoff drafts. It cannot change checklists, approve a job, authenticate signatures, certify safety or workmanship, identify people, invent readings or treat photo text as instructions. Returned photo references must belong to the supplied evidence. Earlier-revision drafts are retained in history but excluded from the current export.

## Evidence and privacy

Records belong to the signed-in account. The backend authenticates each request and applies ownership on every RPC. Four RLS-enabled tables and a service-only security-invoker RPC deny direct anon/authenticated access. The private `korlix-fieldproof` bucket has a restrictive policy that remains effective even alongside broad legacy storage policies. Preview links expire after 600 seconds. JSON and authenticated downloads use `Cache-Control: no-store`; downloads verify the stored SHA-256 digest.

Original bytes are retained unchanged, including embedded metadata. A separate normalized JPEG preview, at most 1200 pixels per side, removes EXIF metadata and is used for preview, AI and PDF. Hashes detect changed bytes; they do not prove who captured an image, its capture date, location or truthfulness. Dates and serials in job details are technician-entered. The PDF labels a job as a working draft or technician-closed record, never an independent certification.

Limits: 200 jobs/account; 8 photos/job; 10 MB per still JPG, PNG or WEBP; 40 megapixels; 500 MB/account including previews; 16 checklist items total. Uploads use three-minute recovery leases. An interrupted photo remains visibly incomplete and blocks closeout until retried or removed. Delete operations remove both original and preview objects before removing database records, with retryable deletion state if storage is unavailable. Administrative account deletion must remove the account's bucket objects before cascading its database records; the database cascade alone does not delete stored files.

## Operational behavior

Migration: the repository's `*_fieldproof.sql`. API base: `/api/fieldproof`. Health includes `fieldProof.version`, model, reasoning effort, credit cost, maximum photos and original-evidence support. No new environment variables or services are required.

Review jobs run in the existing backend process: one per account, two per process, up to 12 starts/hour/account. Reopening a screen polls the same saved review. A stale review is marked failed after eight minutes on the next FieldProof request and uses no credit. This release does not provide a durable distributed worker, crew sharing, offline synchronization, legally authenticated signatures, video evidence, automatic bookkeeping posting or automated customer delivery. It retains 20 reviews/job and 200 activity records/job, returning the newest 30 activities.

## Validation

Backend tests execute the real migration in PostgreSQL-compatible PGlite and exercise Express routes with fixture storage/provider responses: ownership, storage policy, byte integrity, upload/delete recovery, optimistic concurrency, approval revision, explicit closeout, provider consent, charge-once behavior and grounded photo references. They do not constitute a paid live model run.

Flutter tests cover saved-response validation, account changes, multipart bytes, failed saves/uploads, closeout, consent, resumed polling, private-state clearing, export inputs, explicit deletion and phone/desktop layouts. PDF generation uses bundled Apache-licensed Roboto fonts; sample output is rendered and visually reviewed before release. The first signed-in production job with real photos and an optional paid AI review remains a user acceptance check.
