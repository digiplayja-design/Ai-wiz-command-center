# Receipt recovery readiness — 7 October 2026

## Status

**Independent production receipt backups are not verified or activated by this work.** An offline encrypted recovery utility and synthetic restore drill are now prepared and tested. The remaining launch decision is the independent private destination, key custody, retention and scheduled job. Do not advertise loss-proof storage or mark this launch gate complete on the strength of the synthetic drill.

| Item | Evidence / status |
| --- | --- |
| Existing database backup | Earlier authorized dashboard review today verified the physical backup at 2026-10-07 06:14:56 UTC, with Restore available. See `security/DASHBOARD_STATUS_2026-10-07.md`. It was not restored in this work. |
| Receipt object privacy | Read-only live metadata query today confirms both `korlix-receipt-wiz` and `korlix-bookkeeping-receipts` have `public=false` and `file_size_limit=8388608`. No customer objects or receipt rows were listed/downloaded. |
| Independent object backup | No receipt backup implementation, scheduled backup job or independent destination was found in the inspected source/runbooks. This is not an inventory of every external account. No external destination was created or configured. |
| Offline recovery building block | `backend/ops/receipt_backup.mjs`: AES-256-GCM archive, encrypted receipt metadata and original/preview bytes, original SHA-256/size validation and explicit owner/receipt/project verification. |
| Validation | `node --test backend/test/receipt_backup.test.mjs`: 12 passed. `node backend/ops/receipt_backup.mjs drill`: passed using generated synthetic data and an ephemeral key. No network or customer data. |
| Production recovery drill | Still required after the destination and job are configured: write a labeled synthetic receipt through the application in an isolated test account, back it up, simulate loss in an isolated recovery target, then prove authorized download and cross-user denial. Do not delete a production customer's receipt as a test. |

Supabase's current documentation explicitly states that database backups do **not** contain Storage object bytes. Receipt Wiz exposes one owner receipt record in its own screen and in Bookkeeping/Tax Prep inboxes. These are not independent copies. CSV exports contain extracted details, not the original receipt files.

## Prepared utility

This is an **offline, bounded, per-receipt** recovery tool with no Supabase/provider client and no background scheduling. It deliberately cannot fetch customers, upload files, run SQL, delete storage objects or write a production restore. It requires Node 22+ and only Node built-ins; no packages were added.

Commands from the repository root:

```bash
node backend/ops/receipt_backup.mjs drill
node --test backend/test/receipt_backup.test.mjs
```

Prepared operator commands after a separately authorized export and key setup:

```bash
node backend/ops/receipt_backup.mjs pack \
  --input /private/receipt-input \
  --archive /private/receipt-snapshot.enc \
  --key-file /private/receipt-recovery.key

node backend/ops/receipt_backup.mjs verify \
  --archive /private/receipt-snapshot.enc \
  --key-file /private/receipt-recovery.key \
  --owner EXPECTED_OWNER_UUID \
  --receipt EXPECTED_RECEIPT_UUID \
  --project EXPECTED_SOURCE_PROJECT

node backend/ops/receipt_backup.mjs extract \
  --archive /private/receipt-snapshot.enc \
  --key-file /private/receipt-recovery.key \
  --owner EXPECTED_OWNER_UUID \
  --receipt EXPECTED_RECEIPT_UUID \
  --project EXPECTED_SOURCE_PROJECT \
  --output /private/new-recovery-directory
```

The key file must contain exactly **32 cryptographically random bytes**, be a regular non-symlink file and deny group/other access (mode 0600). The tool does not generate or escrow production keys. Keep recovery keys in a separate approved secret store and maintain a tested offline recovery copy; loss of the key makes encrypted archives unrecoverable. Keys and archives must not share the same sole administrative failure point. Never paste a Supabase service-role key or recovery key in chat, put it in this repository or include it in CLI arguments.

The input directory contains `manifest.json`, `original` and, when the metadata requires it, `preview.webp`. The manifest input is `{source, project, ownerId, receipt, capturedAt}`; legacy Bookkeeping additionally requires `businessOwnerId` checked from its parent business. `source` is `receipt_wiz` or `bookkeeping`. Use the exported `receiptRecoveryManifest` function to validate and derive bucket/object paths.

Select only these receipt metadata fields from a verified snapshot; unknown fields are rejected:

- Both sources: `id`, `filename`, `mime_type`, `byte_size`, `sha256`, `preview_size`, `preview_sha256`, `pages`, `state`, `created_at`.
- Receipt Wiz: `owner_id`, `details`, `reviewed`, `version`, `updated_at`.
- Legacy Bookkeeping: `business_id`, `created_by`, `ready_at`.

Only `ready` receipts qualify. The archive includes original bytes, optional preview, extracted/reviewed details and recovery identity metadata. Upload tokens/leases, API credentials and request-idempotency keys are excluded. Auxiliary scan-history rows, ledger associations, parent business/tax records, account identities and schema/RLS are **not** reproduced by this utility; preserve them with a consistent separately encrypted database export. An extracted manifest is not a SQL INSERT script. Production reconstruction must reconcile against the restored database and its deletion journal.

The utility verifies hashes before encryption and after decryption. The archive authenticates all metadata and bytes; source project and owner/receipt must match the independently expected identity supplied during recovery. UUID-derived paths prevent receipt filenames from selecting output paths. Encryption has a new random nonce per archive. Plain metadata/receipt text is not logged. Archive writes refuse overwrite, and extraction requires a new directory, mode 0700, with files mode 0600. Use a trusted parent directory inaccessible to untrusted users. The prepared format is bounded to 13 MiB per archive (sufficient for an 8 MiB original, 1 MiB preview, base64 encoding and selected metadata); process one receipt at a time and do not load a whole customer corpus into memory.

## Recommended production method, pending configuration

1. Keep the existing private primary buckets and Supabase database backup. Add an **independent, private object-store destination in a separate account**, with least-privilege upload/read permissions, restricted deletion, account MFA, version history and an approved retention period. Object-lock retention must be chosen together with privacy/deletion handling; do not enable indefinite retention by default.
2. Use a server-side export job to copy each ready original/preview plus the selected metadata as an authenticated encrypted archive. Read metadata before and after downloading and retry if it changes; compare original and preview SHA-256 and byte lengths. Do not mark an incomplete upload or an inconsistent snapshot backed up. Reconcile both current Receipt Wiz and older Bookkeeping storage.
3. Preserve incremental versions of mutable receipt details without repeatedly storing identical original bytes once a provider adapter supports deduplication safely. Maintain an encrypted inventory of receipt/project/owner bindings, hashes, object counts, snapshot versions and capture times. Preserve consistent database/schema/auth linkage separately.
4. Begin with a proposed **hourly** backup job and daily reconciliation, subject to Ricardo's approval of recovery-point needs and costs. The maximum unprotected interval is approximately the job interval plus failure/delay time; hourly is not zero-loss. For stronger guarantees, add a durable backup queue at receipt save, retries and reconciliation, and expose status only after confirmed independent storage.
5. Verify the uploaded archive by reading it back from the independent destination and decrypting/hash-checking it. Alert on missing objects, failed verification and the age of the last successful complete run. Store only counts/status in routine logs; keep object identities and audit mappings encrypted/private.
6. Track intentional deletion and retention expiry. A restore must exclude receipts/users intentionally deleted after the snapshot; do not silently resurrect deleted content. Do not give the normal backup job permission to irreversibly erase all historical backups. Apply approved retention with a separately controlled cleanup path.
7. Test isolated recovery before launch and periodically afterwards. Record the last successful backup/recovery timestamps, tested recovery point, duration and any missing rows/objects. A successful upload count alone does not prove restore readiness.

## Concrete decisions still needed

- **Destination/account and region:** choose an existing approved independent object-store account or authorize setup of a new one. No destination has been selected or paid for here.
- **Recovery point and retention:** suggested starting proposal is hourly capture, daily completeness checks and 30-day version retention, with a documented deletion process. This is a proposal, not an enabled policy.
- **Key custodian and alert recipient:** identify who can recover the encryption key if the primary hosting account is lost, and who acts on a missed-backup alert. No emails have been sent or automations scheduled by this utility.
- **Budget:** compare current official provider rates after choosing expected stored bytes, versions and transfer pattern. The archive format base64 overhead is approximately one third before provider-side compression. Include source egress, destination storage, requests, retrieval/egress, versions and any job host charge; do not promise a blanket zero-dollar or cheapest plan without those assumptions.

## Recovery execution checklist

1. Open an incident record; determine the affected receipt IDs/owners and intended restore point from authoritative audit data. Secure the source of loss before restoring.
2. Recover into an isolated private target. Verify the independent snapshot and correct key, source project, owner, original/preview hashes and database relationships. Use the utility's `verify` then `extract`; never run receipt content as code.
3. Reconcile the deletion journal and account status. Check parent business ownership and ledger links before rebuilding any associations; stale upload leases and request keys must not be replayed as active operations.
4. Restore bytes without public buckets or public URLs; preserve immutable original checksums. Reconstruct missing database metadata only through a reviewed migration/recovery procedure with backups and conflict detection.
5. Verify authenticated owner access, deny another user's access, and check extracted details, original download and preview. Record missing objects and actual recovery duration. Remove transient plaintext recovery files from the approved encrypted workspace when the incident is closed.

## Sources and verification scope

- [Supabase database backups](https://supabase.com/docs/guides/platform/backups) — retrieved 7 October 2026. Storage object bytes are excluded; the current Pro plan provides seven days of daily database backups. Do not conflate that with independent receipt backup.
- [Supabase changelog](https://supabase.com/changelog.md) — reviewed 7 October 2026, including the August scheduling-timeout fix. The project is already on PostgreSQL 17.11; this task changes no schema or Supabase API behavior.
- `backend/bookkeeping/receipt_files.mjs` — existing immutable-byte hash/size verification and bounded download behavior.
- `supabase/migrations/20261006171056_receipt_wiz_shared_inbox.sql` and `supabase/migrations/20260925024651_bookkeeping_receipts.sql` — ownership, state, bucket and object-path rules.
- `security/DASHBOARD_STATUS_2026-10-07.md` — earlier live database backup observation and upgrade verification.

No customer receipts, employee evidence, keys or billing values were read. Only receipt bucket configuration was queried live. No schema, primary object, external account, paid service, scheduled job or production key was changed.
