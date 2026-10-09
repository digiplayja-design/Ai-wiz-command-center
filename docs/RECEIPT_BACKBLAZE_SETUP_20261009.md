# Receipt backup connection — 9 October 2026

## Scope and current rollout

Ricardo created the private `korlix-backups` Backblaze B2 bucket in `us-east-005`, with automatic SSE-B2 encryption and Object Lock disabled. He created a bucket-restricted application key with the `receipts/` prefix and confirmed saving its two credentials in the existing Render backend. Credentials have not been read into chat or committed to the repository.

This release supplies the provider adapter, automated receipt job, encrypted catalog, controlled recovery command, and synthetic connection probe. Initial rollout used `probe` mode; production receipt backups are now enabled. A successful provider or receipt readback check is not a full application disaster-recovery drill.

Verified live on 9 October 2026 at 05:34:54 UTC: backend commit `068b7139739049abb9e26d15b222e0ff683d106a`, Render deploy `dep-db47pe60tbcc73dena80`, passed the synthetic Backblaze probe. Upload, download, decryption, wrong-owner rejection, corruption rejection, anonymous access denial and removal of the exact test-object version all passed. The backend health endpoint remained healthy. The focused local suite passed 61 tests.

**Production receipt backups are active.** Render deploy `dep-db484gbncjis73c4u5pg` of backend commit `eea668ec37b548fcb442aa1ba06e66e43e90d6f3` became live at 05:57:57 UTC on 9 October 2026. The first real receipt run completed at 05:58:07 UTC (01:58:07 America/New_York): 2 receipts, 2,366,984 source bytes, 2 archives uploaded and 2 downloaded/decrypted/integrity-verified, with `catalogVerified=true`. The backend health endpoint remained healthy. Subsequent scheduled runs have not yet been observed at this checkpoint.

With Ricardo's explicit approval, a working recovery key was saved in the existing Render backend at 05:42 UTC. Its nonsecret fingerprint is `7cce09ea3c5954da`. Do not regenerate or replace this key without a migration plan. At 05:48 UTC Ricardo confirmed a secure independent copy of `RECEIPT_BACKUP_RECOVERY_KEY_BASE64`. His supplied `IMG_3161.png` and `IMG_3162.png` show the correct `receipts/` lifecycle values and the saved custom rule on the private bucket: hide after 30 days, delete one day after hiding. `RECEIPT_BACKUP_MODE=enabled`; the custody, retention and privacy-disclosure readiness flags are all true. The public disclosure in frontend commit `16b0ca8d50e67c80c04ffc26b6ccaa46ac6420b5` is verified live. Probe objects are removed; real encrypted receipt archives and their catalog remain in the bucket.

No new Render service or paid plan is provisioned. Runtime scheduling uses the existing backend: first run 15 seconds after startup, then 60 minutes after each successful run; failures retry after 15 minutes. A restarted service catches up by enumerating the current ready receipts again. Downtime/delay increases the recovery-point interval. Logs report counts and timestamps; no automatic email/SMS alert recipient is configured.

## Private environment configuration

| Variable | Value / source |
| --- | --- |
| `RECEIPT_BACKUP_B2_KEY_ID` | Backblaze scoped key ID (saved by Ricardo) |
| `RECEIPT_BACKUP_B2_APPLICATION_KEY` | Backblaze scoped application key (secret; saved by Ricardo) |
| `RECEIPT_BACKUP_B2_ENDPOINT` | `https://s3.us-east-005.backblazeb2.com` |
| `RECEIPT_BACKUP_B2_REGION` | `us-east-005` |
| `RECEIPT_BACKUP_B2_BUCKET` | `korlix-backups` |
| `RECEIPT_BACKUP_B2_PREFIX` | `receipts/` |
| `RECEIPT_BACKUP_MODE` | `enabled` (initial connection testing used `probe`) |
| `RECEIPT_BACKUP_RECOVERY_KEY_BASE64` | Exactly 32 cryptographically random bytes encoded as canonical base64; independently escrow before activation |
| `RECEIPT_BACKUP_RECOVERY_KEY_FINGERPRINT` | First 16 hex characters of the SHA-256 of the decoded recovery key |
| `RECEIPT_BACKUP_RECOVERY_KEY_ESCROWED` | `true`; independent secure copy confirmed by Ricardo |
| `RECEIPT_BACKUP_RETENTION_CONFIGURED` | `true`; actual Backblaze settings verified from the user's screenshots |
| `RECEIPT_BACKUP_PRIVACY_DISCLOSURE_READY` | `true`; corresponding public disclosure verified live |

Never paste key values into chat, source code, command arguments, or screenshots. Retain the recovery key in a password manager/offline recovery location outside Render, with the bucket and fingerprint recorded. Do not rotate it without retaining old recovery keys and an explicit migration/recovery plan. The fingerprint guard prevents changing the key while silently reusing an earlier custody acknowledgement.

## Layout, reconciliation, and limits

- `receipts/_probe/<random-id>.enc`: synthetic encrypted object only. Upload, download/decrypt, wrong-owner denial, corruption rejection, anonymous access denial and prefix listing are checked. The exact synthetic version is deleted afterwards. No customer records are queried in probe mode.
- `receipts/v1/<project>/daily/<UTC-date>/<source>/<opaque-identity>/<metadata-hash>.enc`: authenticated AES-256-GCM receipt archives. Each includes owner/project/receipt identity, selected metadata, original bytes and optional preview. Identity path segments use keyed hashes; filenames and extracted receipt text are encrypted.
- `receipts/v1/<project>/catalogs/<timestamp>-<random-id>.enc`: encrypted inventory committed only after every archive has been downloaded and verified, then the ready source inventory is re-read and found unchanged. Catalogs are immutable snapshots; no shared mutable latest pointer is used. Choose the latest complete catalog for routine recovery.
- Current Receipt Wiz and legacy Bookkeeping receipts are included. Bookkeeping parent-business ownership is verified. Only selected fields are read; upload tokens, request keys and scan execution credentials are excluded.
- Within one UTC day, unchanged archives are verified and reused. A fresh baseline is written each day so age-based expiry never removes the sole copy of a still-active receipt. Mutable reviewed metadata creates additional versions.
- Initial safety bounds: 10,000 ready receipts and 512 MiB of source originals/previews per complete run, one receipt at a time, 13 MiB per archive, 8 MiB per catalog. Exceeding a limit fails the run without publishing a complete catalog. Review limits/costs before growth exceeds these bounds.
- Production originals are never written, changed, or deleted. The adapter only exposes deletion for a just-created synthetic probe version. The GUI-created Read/Write key itself can delete objects under its prefix; code restrictions are not ransomware-proof credential isolation. Use independently controlled retention/immutability and review narrower Native API capabilities before claiming protection against compromised backup credentials.

## Confirmed retention

Ricardo configured Backblaze lifecycle rules for the `receipts/` prefix to hide current versions 30 days after upload and permanently delete hidden versions after 1 further day. Expiry processing is asynchronous; describe this as approximately 30 days plus the provider's expiry interval, not an exact erasure deadline. The actual age-based expiry has not yet elapsed or been observed. Current receipts receive daily replacement snapshots; deleted receipts stop appearing in new snapshots.

**Lifecycle rules and Object Lock are different.** Ricardo configured the lifecycle rule in the Backblaze console; the backup job does not modify bucket settings. Object Lock remains disabled. Never apply a whole-bucket rule to unrelated future KORLIX backups. Do not enable indefinite retention or legal holds. Any future Object Lock period must be chosen together with deletion obligations and the ability to expire old backups.

Update the public provider/receipt-retention disclosure before copying customer data. Keep the existing Supabase database backup: these object archives do not replace a consistent database/schema/auth backup. Scan history, financial ledger/tax relationships, user identities and unrelated app features still rely on database recovery. Do not advertise this as a backup of all KORLIX features.

## Operational commands

Run from `backend` in a trusted operator environment with the private environment variables loaded; never pass credentials as command-line flags:

```bash
node ops/receipt_backup_cloud.mjs probe
node ops/receipt_backup_cloud.mjs run
node ops/receipt_backup_cloud.mjs list-catalogs
node ops/receipt_backup_cloud.mjs recover --catalog EXACT_CATALOG_KEY --owner EXPECTED_OWNER_UUID --receipt EXPECTED_RECEIPT_UUID --source receipt_wiz --output /private/new-recovery-directory
```

`recover` verifies that the owner still exists and is enabled and that the current ready receipt matches the catalog. It refuses deleted/changed receipts, decrypts and verifies the archive, and extracts into a new private local directory. It does not upload, insert database rows, or restore into production. When recovering a lost database, use `WEB_LAUNCH_RECEIPT_RECOVERY_20261007.md`: reconcile the restored database with deletion requests/journals before reconstructing any records. Retained snapshots must never reactivate a deleted account or receipt automatically.

## Release verification

```bash
node --test test/receipt_backup.test.mjs test/receipt_backblaze.test.mjs test/receipt_wiz.test.mjs test/bookkeeping_receipts.test.mjs
node --check server.js
```

Observe `receipt_backup_probe` with `status: pass` in Render after deploying probe mode. After readiness is confirmed and enabled, require `receipt_backup_run` with `status: complete`, counts and `catalogVerified: true`. A later failure does not reset the last successful timestamp or claim a new recovery point. Review age of the last complete run and configure an independent failure/missed-run alert destination before relying on unattended operation.

Before closing launch recovery readiness, run an isolated application recovery rehearsal with labeled test data and verify correct-owner access and cross-user denial. The live provider probe and controlled automated tests alone do not prove a full production application reconstruction.
