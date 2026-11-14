# KORLIX auth core

Shared session renewal, secure token storage, and account-scoped AI consent for
KORLIX COPY Box. The package contains the account and privacy code that Copy Box
uses, with no receipt, bookkeeping, camera, image-picker, or theme dependency.

## Provenance

The following production files were initially copied without changes from
`packages/korlix_receipt_core` at commit
`93253b767f6df1a8aec97bd29ce9cfbc09a34508` on 2026-11-03. Paths are relative to
each package root:

| File | Responsibility |
| --- | --- |
| `lib/auth/korlix_session_refresh.dart` | Refresh coordination, session identity, and authenticated request transport |
| `lib/auth/korlix_token_store.dart` | App-scoped credentials and native secure storage |
| `lib/privacy/korlix_third_party_ai_consent.dart` | Account-scoped provider/content consent and its dialog |

Their existing test suites were copied into the matching `test/auth` and
`test/privacy` directories. Test package imports now reference
`korlix_auth_core`; the obsolete indirect-dependency lint suppression was removed
because `shared_preferences_platform_interface` is a declared test dependency.
No production behavior changed during extraction.

After extraction, the consent dialog in this package gained an optional
`additionalDisclosure` parameter for Copy Box's explanation of online generation
history. Its notice version is now
`copybox.third-party-ai-consent.v3.history-disclosure`, so permissions saved under
the previous notice cannot bypass the updated disclosure. Token storage and
session refresh code remain unchanged from the source package.

The original package and its consumers remain unchanged. Keep security and
consent fixes synchronized between these copies until the original consumers can
be migrated in a separately reviewed change. The receipt HTTP convenience
wrapper and screensaver theme controller are not used by Copy Box and are not
included here.

## Dependencies and app integration

Runtime dependencies are Flutter, `http`, `shared_preferences`,
`flutter_secure_storage`, and `url_launcher`. Copy Box depends directly on this
package using `../../packages/korlix_auth_core`. It must not also depend on
`korlix_receipt_core`, which would reintroduce the receipt scanner's native
plugins.

Consumers retain responsibility for using a separate application ID, passing an
app-specific token namespace, and setting or clearing the consent account scope
when the authenticated account changes. Existing storage keys are preserved;
the consent notice version was advanced as described above. Further material
changes to consent disclosures must advance that version again. Accounts are
not migrated between installed apps.

## Validation

The Copy Box validation workflow resolves this package, analyzes it, and runs its
existing tests before validating the app. Use Flutter 3.47.7 in a permitted build
environment:

```bash
cd packages/korlix_auth_core
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

No dependency lockfile is fabricated during extraction. The build environment
resolves dependencies, and the Copy Box app's lockfile captures the final app
dependency graph for review.
