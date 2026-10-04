# FieldProof Autonomous Email

FieldProof provides account-private customer job reports, one optional courtesy follow-up per closeout, and scheduled supervisor summaries. Each account configures its own recipients and rules. Existing jobs are not automatically emailed when a rule is enabled.

## Set up

1. Open **FieldProof → Autonomous Email** and confirm the displayed Reply-To email. It comes from the verified signed-in account; recipients reply to that account. Delivery uses Korlix's configured sending service.
2. Enter a business name and choose **Off**, **Review drafts**, or **Automatic** independently for completed-job reports, the courtesy follow-up, and supervisor summaries. New accounts start with all three off.
3. For customer emails, open a job's **Email customer** screen, enter the customer email, and enable that job's recipient. Both the global mode and the job recipient must be enabled. Closing a future job queues the configured report/follow-up. A completed job can also prepare an explicit draft for review.
4. For supervisors, select up to five email addresses, weekdays, an IANA time zone and local delivery time. Each recipient gets a separate email. Summaries cover the previous local calendar day's recorded closeouts and identify currently overdue jobs and unresolved punch-list items. The first run is at a future configured time, not a historical backlog. A missed run can catch up for up to six hours, within the same local day.
5. **Activity** shows waiting messages, saved previews, draft approval, cancellation, safe retry, and provider acceptance. Provider acceptance is not proof of inbox delivery. Refresh to see worker updates. The shared backend worker runs every 30 seconds while the service is running.

The daily limit defaults to 25 and can be set from 1 to 100 emails per account, counted by UTC day. Pause stops waiting messages; a submission already in flight may finish. Editing delivery settings or changing a job recipient invalidates waiting messages so an old approval cannot authorize a different recipient or report.

## Customer report content

The customer report contains entered work details, checklist status, exact readings, materials, outstanding items and accurately labelled recorded approval. It includes a PDF and optional reduced-size photo previews (up to 12). Original image metadata, original-file downloads, internal notes, billing notes/hours, AI review drafts, and private storage URLs are excluded. Omitted photos are disclosed; PDFs are limited to 5 MB and 24 pages. English, Spanish and French accents are supported. Unsupported font characters are visibly represented in the PDF; the UTF-8 email body preserves the original text.

Reports describe technician-entered records, not independent certification. Sending a report does not close a job, approve customer identity, issue an invoice or update bookkeeping. K-Nova's existing non-writing voice permissions remain unchanged; email setup and approvals use the FieldProof controls.

The courtesy follow-up sends once, 1–30 days after closeout (default three). It invites the customer to reply with questions. It does not claim payment is due or send marketing content.

## Delivery and privacy

The queue is durable in PostgreSQL. The closeout trigger creates events in the same transaction as job completion, and each event/recipient is unique. A claim has a short lease. Before dispatch, the server rechecks the owner, verified account email, paused state, rule revision, job revision, recipient and suppression status. Database functions are SECURITY INVOKER and callable only by the backend service role; direct anon/authenticated access to the email tables and PDF bucket is denied.

The exact message and immutable private PDF are prepared before sending. Provider retries retain the same idempotency key and bytes; the sender identity is fingerprinted so a changed server sender cannot silently change a retry. An interrupted or ambiguous provider response remains **Outcome unknown**. Recovery never creates a new message ID to retry an uncertain send. Same-ID retries stop before the provider's 24-hour key expiry.

Every email offers an opt-out for that business. Issued links remain valid for one year; opting out suppresses subsequent reports, follow-ups and summaries to that recipient for that owner. Signed provider bounce/complaint/suppression events use the existing Resend webhook and also stop future messages. Recipients and reports are never shared across business accounts.

Prepared report content/PDFs are retained for up to 30 days, subject to earlier deletion or the 500-record history limit. Compact event records prevent repeat sending after history is removed. Job/account deletion schedules private attachment removal; cleanup retries failed storage removal. Activity retains delivery receipts separately from the report payload. Existing sent email in a recipient's mailbox cannot be recalled.

## Operations

- Backend entry: `backend/fieldproof/emails.mjs`; API: `/api/fieldproof/email`.
- Transport: `backend/fieldproof/email_provider.mjs`, using existing `RESEND_API_KEY` and `KORLIX_AGENT_EMAIL_FROM`. No customer-supplied From address or NOVA singleton is used.
- Webhooks: `backend/fieldproof/email_webhook.mjs` runs before the existing `/api/agent-email/resend/webhook` handler, with the existing signing secret. Both consumers must persist their work before acknowledgment.
- Private bucket: `korlix-fieldproof-mail`. Original job evidence remains in the existing FieldProof bucket.
- Database: migration `20261003235831_fieldproof_autonomous_email.sql`. Service-only RPC: `korlix_fieldproof_email_v1`.
- Production public email preference links use `RENDER_EXTERNAL_URL`; local tests supply a fixture origin.
- No AI request, new Google billing product, or AI GAS debit is needed to create these deterministic reports and summaries. Normal email provider usage still applies.

## Verification

Release verification covers the real migration in PGlite, Express routes connected to that migration and the worker, account isolation, off/draft/automatic modes, immutable PDFs, duplicate suppression, old unsubscribe links, provider errors and webhooks, time zones/DST, and phone/desktop layouts. Provider and storage calls in tests are fixtures; no external customer email is sent by development verification. A real recipient mailbox acceptance test remains distinct from automated checks and public deployment verification.
