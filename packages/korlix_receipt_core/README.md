# KORLIX receipt core

The source of truth for Receipt Wiz, receipt file handling, authenticated HTTP,
secure token storage, and AI sharing consent. Both the KORLIX AI app and
`apps/receipt_wiz` depend on this package. Original `lib/` paths are compatibility
exports; edit this package instead. `SOURCE_FILES.txt` lists the extracted files.

Both apps use the same backend owner UID and receipt library. Sessions and native
secure storage remain separate for each installed app. Tests cover scanner,
review, export, manual fallback, account changes, refresh rotation, secure-storage
failures and account-scoped consent. The hub retains its integration tests.

Use Flutter 3.47.7:

```bash
cd packages/korlix_receipt_core
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
```
