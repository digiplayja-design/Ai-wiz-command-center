# KORLIX COPY Box

Independent Flutter writing workspace for Android and iOS. Source lives alongside
KORLIX's other standalone apps; this is a separate app, not a change of identity
for KORLIX AI, Messenger, or Receipt Wiz.

- Android application ID / iOS bundle ID: `com.korlixdeveloper.copybox`
- Display name: **KORLIX COPY Box**
- Initial source version: `1.0.0+1`
- Flutter: `3.47.7`; existing shared authentication/privacy package:
  `../../packages/korlix_receipt_core`

## Run and validate

From this directory:

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter run
```

The dedicated GitHub validation workflow produces Android debug and iOS simulator
builds. Store release signing is separate. The Codemagic candidate workflow
requires an existing Apple app record and the dedicated
`KORLIX_COPYBOX_APP_STORE_PROFILE`; it verifies the resulting IPA's identity.
No existing KORLIX app ID is reused. The candidate does not submit for review.

## Behavior

- Local writing works without an account. Local and signed-in account workspaces
  remain separate. Sign-in uses the existing KORLIX email and password.
- Twelve independent, editable starter boxes; new boxes append to the stack.
  Typing never reorders a box. Save All saves the workspace. Copy All Boxes copies
  every nonempty, non-trashed box in workspace order; Copy shown respects filters.
- Favorites, folders, search, six color labels, duplicate, and manual movement.
- Focus editing commits with Save & close. Replacements preserve up to twenty
  prior text versions. Deletion moves to recoverable trash; emptying trash confirms
  permanent removal.
- Six templates and `{{field}}` replacement preview. Filling and copying a template
  never changes the stored template.
- JSON backups include history/trash; text export includes active current text.
  Imports validate the entire file, preview it, and assign fresh IDs. They add
  content without replacing current boxes. Limits: 5 MiB per workspace/backup,
  1,000 boxes including trash, 100,000 characters per text, 200 per title/folder.
- Clipboard reads happen only after a user chooses Paste. No background clipboard
  monitoring. Native OS clipboard prompts may still appear.
- Optional AI refinement uses the authenticated existing KORLIX API and normal
  usage rules, with explicit provider/data consent and draft review. No new price,
  subscription, free-trial promise, or unlimited AI allowance is introduced.

## Data handling

Saved text uses local preferences, scoped to the local workspace or the account's
issuer/subject. It is not an encrypted vault and is not cloud-synced. Native tokens
use the existing secure token store with a COPY Box namespace. Backups are readable
JSON and should be handled as private documents. Exports are user initiated.

Ordinary typing autosaves with a short debounce and on background transitions.
Writes use snapshots and serialize; malformed saved data is preserved and blocks
new writes. The app reports save failures instead of claiming success. A sudden
OS kill before a pending write completes can still lose recent keystrokes.

Account changes rebuild the navigator and workspace, rejecting late AI results.
The local editing view makes no AI requests. Selected text is transmitted only on
an explicit AI action after consent. Report output sends the reason, details, and
an excerpt of the output to the existing reporting endpoint.

## Branding

The original KORLIX face-and-circuit emblem was supplied to the built-in image
editing tool to create a white-on-black edition. The input silhouette and circular
rings were the identity reference. Source asset: `assets/copybox_icon.png`.
Mobile launcher sizes are generated from the same asset. Editor card colors remain
independent of the monochrome logo.

## Store release status

See `../../docs/releases/copybox-20261103/README.md` for actual verification and
outstanding store gates. Source configuration is not evidence of a store upload,
review approval, TestFlight distribution, or public release.
