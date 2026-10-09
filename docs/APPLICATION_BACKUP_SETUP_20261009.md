# KORLIX wider backup setup — 9 October 2026

## Current state

Ricardo authorized extending the receipt backups to the other important KORLIX data. The implementation and offline synthetic recovery checks are prepared. **Wider production backups are not active until the new scoped Backblaze credential, database connection and retention/disclosure checks are configured.** Existing receipt backups remain separate and enabled.

Prepared code is deployed: backend commit `09dd79fdea79812f000e29f99cd71907fa18f3b3`, deploy `dep-db4dbi3tqb8s73etefr0`, became live at 11:55:17 UTC. The backend health endpoint returned HTTP 200. The live application-backup runtime explicitly reports `mode=off`, `productionBackupsActive=false`, `state=awaiting-configuration`. A receipt run completed at 11:55:29 UTC with both receipts and its catalog verified. Earlier scheduled receipt runs at 10:16:51 and 11:16:52 UTC also completed successfully, confirming the hourly timer beyond startup.

The expanded conditional privacy disclosure is deployed in frontend commit `bf947a705b6d86251aa45d0d1f10778d1ef78c02`, deploy `dep-db4dbjflot8c738kmsng`, live at 11:57:08 UTC. No new paid service, database schema change, production restore or broader customer-data export was performed.

Read-only inventory on 9 October: PostgreSQL 17.11, approximately 45.5 MB database, 256 public tables plus Auth and private application schemas, 16 private Storage buckets and 97 current objects (93 outside the receipt buckets). `vault.secrets` is empty. No production data or credentials were exported into chat or the development workspace. The most recent provider-backup observation in the existing runbook is 7 October, not a new confirmation of today's Supabase backup.

The Supabase connector provides queries but not a PostgreSQL connection credential. The Render connector can merge environment variables but cannot retrieve or generate the missing database password. The existing B2 application key is deliberately restricted to `receipts/`. It cannot be used for `application/`, and this implementation does not put unrelated application data under `receipts/` to bypass that boundary.

## Coverage when enabled

- A PostgreSQL 17 custom-format export, daily and after each backend restart, using a read-only repeatable-read snapshot. Includes `public`, `auth`, `storage`, `k135z_b5b_private`, `k135z_workspace_private`, `korlix_live_private` and `supabase_migrations`: account/auth records, subscriptions, credits, financial/inventory/CRM/booking/workforce/social records, memories, schema, relationships, functions and RLS/grants. Role attributes/memberships and installed-extension metadata are saved with the dump. Role passwords are not exported.
- All current files in the 16 approved Storage buckets, including receipts, hourly while the backend runs. New buckets, versioned objects, unexpected schemas and a newly populated Supabase Vault stop completion for review instead of silently excluding data.
- Deletion requests, Social Auto Dump controls, CRM email suppressions, funnel removal records and account-status inventory in every hourly snapshot. This supplements the daily database snapshot; it does not eliminate changes lost between successful captures.
- Allowlisted at-rest application encryption keys plus non-secret configuration and environment-variable names, encrypted inside each daily snapshot. The master recovery key, B2 credentials and general provider API credentials are never copied into that archive. Preserve/reissue external credentials through the provider accounts and their independent secure custody arrangements.
- Source archives for the exact deployed backend commit and the current frontend release-branch commit. The latter is labeled as a release-branch snapshot, not proof of which frontend commit was deployed. Repository history, local uncommitted code, domain registrar settings, provider console settings and mobile signing credentials are not covered by these source archives.

**Short-retention exclusion:** row data for `public.korlix_live_studio_*` and `LIVE_STUDIO_TOKEN_KEY` are deliberately excluded from the 30-day application archive because YouTube-derived records have shorter deletion obligations. Schema remains included. Reconnect YouTube and recreate Live Studio schedules after a restore. Independently uploaded private rehearsal/video objects are included. External-provider-only files and device-only files are outside the Storage inventory and are not copied.

The daily database dump shares its snapshot with the Storage inventory. Each object is downloaded or its same-day immutable encrypted copy verified; the current Storage inventory is re-read at the end. If it changed, no complete catalog is committed. Hourly file catalogs are separate recovery points and do not claim a new hourly database snapshot.

## Operator setup needed

### Backblaze

Create a new standard application key, leaving the receipt key intact:

| Setting | Value |
| --- | --- |
| Name | `korlix-application-backups` |
| Bucket | `korlix-backups` only |
| File name prefix | `application/` |
| Access | Read and Write |
| List all bucket names | Off |

Add a **separate** lifecycle row for `application/`: hide after 30 days and delete one day after hiding. Preserve the existing `receipts/` row. Do not apply a whole-bucket lifecycle or change Object Lock as part of this setup. Expiry is asynchronous, not a precise deletion timestamp. The GUI Read/Write key can delete objects in its prefix; this setup is not ransomware-proof immutability.

Save the new values directly in the existing Render backend's Environment screen:

| Environment variable | Private value |
| --- | --- |
| `KORLIX_BACKUP_B2_KEY_ID` | New application key ID |
| `KORLIX_BACKUP_B2_APPLICATION_KEY` | New application key secret |
| `KORLIX_BACKUP_DATABASE_URL` | Supabase **Session pooler**, port 5432, for project `uxtjzjbwtppjvnsoiijv`, with its database password |
| `KORLIX_BACKUP_DATABASE_CA_PEM` | Only if needed for certificate verification: project's downloaded root CA certificate |

Use the actual hostname from Supabase's Connect panel. Never paste credentials into chat, Git, command arguments or screenshots. Do not reset a database password without reviewing other clients. The backup client requires TLS certificate/hostname verification; it never disables certificate verification. It accepts only this project's direct connection or Ohio Session pooler and refuses the transaction pooler on port 6543.

The existing independently saved receipt recovery key is reused **through HKDF domain separation**, deriving a different application-backup encryption key. Do not rotate or overwrite it. Independent custody and its saved fingerprint are checked before use.

After confirming the new lifecycle row and the live expanded privacy disclosure, set:

```text
KORLIX_BACKUP_RETENTION_CONFIGURED=true
KORLIX_BACKUP_PRIVACY_DISCLOSURE_READY=true
KORLIX_BACKUP_MODE=probe
```

Verify `application_backup_probe` reports upload/readback, encryption, tamper/binding rejection and denied anonymous access. Then set `KORLIX_BACKUP_MODE=enabled` and verify a real `application_backup_run` with `databaseIncluded=true` and `catalogVerified=true`. Environment updates on this Render service trigger deployment; avoid starting a duplicate deployment. A configuration flag alone is not evidence that a backup completed.

Destination is pinned to private bucket `korlix-backups`, endpoint `https://s3.us-east-005.backblazeb2.com`, prefix `application/`. There is no arbitrary destination URL or incoming public backup endpoint. Production file deletion is not exposed; the only adapter deletion removes the exact synthetic probe object version.

## Scheduling, verification and limits

The existing backend starts a run 60 seconds after startup, then 60 minutes after a successful run. Database/source/config snapshots are daily plus after restart; file and recovery-control snapshots are hourly. Failures retry after 15 minutes. Downtime or failures lengthen the recovery interval. No new paid Render service is required.

Each archive uses authenticated AES-256-GCM. Filenames, ownership metadata, database contents and keys in the configuration archive are encrypted. Object keys use keyed opaque identities. Every upload is downloaded, decrypted and hash-verified. `pg_restore --list` checks the dump table of contents; `pg_restore --file=/dev/null` additionally decompresses every entry without executing SQL. This is archive validation, **not a PostgreSQL or full application restore drill**.

Daily object namespaces ensure current files receive fresh copies as older snapshots expire. A complete encrypted catalog is written only after every referenced part verifies. Failed runs can leave unreferenced encrypted parts until lifecycle expiry; they do not publish a complete catalog. Keep complete catalog keys from `application_backup_run` logs in the operator recovery record.

Initial limits: 10,000 objects, 64 MiB per source object, 1 GiB of file bytes per run, 128 MiB per encrypted part, 16 MiB catalog and recovery-control payloads, 10,000 rows per control table, 20-minute run timeout. Exceeding a limit produces a failure, not a truncated backup. Review these limits as usage grows. The implementation uses sequential bounded buffers; large future datasets may require a streaming worker.

Failures use the existing Resend connection and Ricardo's approved `support@korlixdeveloper.com` recipient, with a separate application-backup subject/idempotency scope. No customer content, filenames or secret values enter notifications. Identical errors are grouped into six-hour UTC windows. Receipt test notifications are not replayed. Independent full-backend-outage monitoring remains unconfigured.

## Isolated recovery

Run in a trusted recovery environment with secrets loaded privately:

```bash
node ops/application_backup.mjs recover --catalog EXACT_CATALOG_KEY --output /private/new-isolated-directory --isolated
```

The command creates a new private directory, refuses overwrite, verifies every archive and writes safe generated filenames plus an encrypted-snapshot-derived manifest. Corruption removes the incomplete extraction. It does not connect to Supabase, write production SQL, publish files, enable accounts or run stored actions.

Before any real restore:

1. Use an isolated target and equivalent Supabase/PostgreSQL 17 platform dependencies. Recreate required extensions/roles and provider configuration; review the exported schema, RLS and grants. Supabase-managed platform schemas and settings require the provider's supported restoration procedure.
2. Keep customer access and all email, phone, advertising, payment and scheduling workers disabled. Never resume outbound actions solely because they were pending in an old snapshot.
3. Choose the desired complete daily database-and-files catalog. Use newer file/control catalogs only through reviewed reconciliation; they may not match the older database point in time.
4. Reconcile **all available later** deletion requests, account disablement, Social hiding/deletion controls, consent revocations and email suppressions before exposing any restored records. If later deletion evidence is missing, keep affected data unavailable pending reconciliation.
5. Reconcile Stripe/store/provider transactions and sent actions after the database restore point. Avoid duplicate charges, credits, refunds, emails and scheduled actions. Revoke restored sessions; require reauthentication where appropriate.
6. Verify real sign-in, access tiers/balances, representative financial/customer records, owner-authorized file retrieval and cross-user denial. Record missing data and measured recovery time. Only then approve switching customer traffic to the recovered target.

## Validation evidence

66 focused automated checks passed on 9 October, including authenticated encryption, corruption and wrong-project rejection, strict database/destination scope, same-day reuse/new-day copies, incomplete-catalog rejection, a private offline synthetic extraction, snapshot argument/credential separation, Vault-change refusal, alert deduplication and existing receipt-backup regression tests.

Production credential connectivity, a real wider backup run, a database restoration and an end-to-end application recovery drill remain unverified until the access setup is completed. No new production backup should be claimed before those separate milestones are observed.

Sources reviewed: Supabase current changelog; Database Backups; Backup and Restore using the CLI; PostgreSQL 17 pg_dump documentation. Supabase database backups do not contain Storage object bytes. Keep the provider database backups as well as the independent copies.
