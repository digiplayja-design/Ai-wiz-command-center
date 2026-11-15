# Esha native builds

These scripts operate only on `apps/esha`, with the separate Android package and
iOS bundle identifier `com.korlixdeveloper.esha`. The exact Apple app record,
signing identity and dedicated Esha App Store profile have now been verified.
Two signed iPhone IPAs have been verified and uploaded to Apple. The Google Play
record and signed Play upload remain unverified.

## Verified Apple setup — November 15, 2026

- [Signing job `6afa106590e83b09c4fab58f`](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa106590e83b09c4fab58f),
  source `d1e592b901efe020a9df7c3f6fc33a31600671f4`, authenticated successfully
  and verified the exact Esha app and existing distribution identity at
  **3:05 p.m. EST (20:05:54 UTC)**. It created and verified one Esha App Store
  profile; the subsequent Codemagic UI import was confirmed as
  **`ESHA_APP_STORE_PROFILE`**. The
  [signing evidence](../../apps/esha/release/ios-signing-20261115.json) distinguishes
  public receipt values from the UI-confirmed import facts.
- [Draft-listing job `6afa194090e83b09c4fab8d4`](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa194090e83b09c4fab8d4),
  source `80194affee0b971bcd1e67ac45ed5ee3dd528547`, completed and reread the
  version, listing text, categories and privacy links at
  **3:43 p.m. EST (20:43:54 UTC)**. The
  [draft-listing receipt](../../apps/esha/release/apple-draft-listing-20261115.json)
  records all four operation groups verified and status
  `draft_listing_synchronized`. The manual listing workflow uses `mac_mini_m2`.
- [First signed upload job `6afa19ff90e83b09c4fab91c`](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa19ff90e83b09c4fab91c),
  source `494b070ecf423dd0440bb8b798c4c5ed826f080d`, passed 49 native tests and
  verified App Store distribution signing for **1.0.0 (1)**. Apple accepted the
  IPA at **20:52:05 UTC**; the downloaded artifact was independently rehashed.
  The [build 1 upload receipt](../../apps/esha/release/ios-upload-build-1-20261115.json)
  records the exact artifact and delivery. A separate
  [Apple inventory](../../apps/esha/release/apple-inventory-before-subscription-20261115.json)
  at **20:56:56 UTC** reports build 1 **VALID** and not expired.
- [Branded signed upload job `6afa1c8190e83b09c4faba0a`](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa1c8190e83b09c4faba0a),
  source `fbfde79df731dea5a2e7fc65ee9d4308aebe80dd`, passed **49 native tests**
  and verified App Store distribution signing for **1.0.0 (2)**. The build uses
  Esha's existing pink Korlix logo on its launch screen. Apple accepted the
  **28,206,010-byte IPA at 21:02:06 UTC**, delivery UUID
  `50de7424-a350-42fb-9a9d-78eb17021ace`. Independent download checks matched the
  build receipt's size and SHA-256 and confirmed the bundle, version/build and
  compiled launch storyboard; the launch-screen pixels were not rendered locally.
  The immutable [build 2 upload receipt](../../apps/esha/release/ios-upload-build-2-20261115.json)
  records upload acceptance; subsequent processing is verified separately below.
- [Inventory job `6afa1f8d90e83b09c4fabb26`](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa1f8d90e83b09c4fabb26),
  source `d62f76a8fc97eac812668e884ba0b57d7ba84ceb`, completed **19 GET requests
  at 21:10:34 UTC**. Its
  [post-subscription receipt](../../apps/esha/release/apple-inventory-after-subscription-20261115.json)
  verifies **builds 1 and 2 as VALID and not expired**. At that **21:10:34 UTC**
  check, version 1.0.0 was **Prepare for Submission** with **no selected build**.
  This historical observation precedes the successful selection below. The observed build
  encryption field is `null`; it does not establish an export-compliance answer.
- [Build-selection job `6afa207890e83b09c4fabb6a`](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa207890e83b09c4fabb6a),
  source `8adf46d7587ced117e725f88a404913c0d2eb61b`, selected exact **1.0.0 (2)**
  and verified GET readback at **21:14:24 UTC**. The independently downloaded
  [selection receipt](../../apps/esha/release/apple-build-selected-20261115.json)
  records **16 total requests, one PATCH and zero retries**. Version 1.0.0
  remains **Prepare for Submission**, with build 2 **VALID** and not expired.
  Encryption remains `null`; no declarations, contacts, review or publication
  were changed.
- Esha's **Privacy and Terms pages are deployed and verified live**. Render
  deployment `dep-dbt0l93l550s739n1p3g`, exact commit
  `5e2a4086b7c4a58e8614abfa3625270b05def152`, finished at
  **2:41 p.m. EST (19:41:04 UTC)**. GET checks at
  **3:47 p.m. EST (20:47 UTC)** returned HTTP 200 and verified the whole-app
  membership wording, the three-day / US $4.99 monthly offer in Terms, and the
  Privacy deletion anchor. The
  [live policy and billing-catalog receipt](../../apps/esha/release/live-policy-check-20261115.json)
  records the deployment identity, response hashes and scoped checks.

These checkpoints resolve the earlier false HTTP 401 diagnosis and establish
signing/profile, draft-listing, signed-upload and verified build-selection progress. Both builds' VALID
states are recorded separately from their immutable upload receipts. None of
these jobs submitted a store review, published an app or
activated membership billing.

## Automatic validation

`.github/workflows/esha-native.yml` runs on pushes and pull requests changing
Esha's app, its build scripts, its workflow, or `codemagic.yaml`. It also supports
manual dispatch. It uses read-only repository permission and no signing or store
credentials. The Linux job analyzes and tests the app, then compiles Android.
The macOS job independently compiles iOS for the simulator.

| Artifact | Purpose | Signing status |
| --- | --- | --- |
| `Esha-debug.apk` | Install on an Android test device | Debug test signature; not a Play release |
| `Esha-unsigned-release.aab` | Verify Android release compilation | Verified unsigned; cannot be uploaded as a signed release |
| `Esha-iOS-Simulator.zip` | Run the application in an iOS Simulator | Simulator application; not an IPA or iPhone installation |
| `*-verification.json` | Check app identity, source commit, size, SHA-256, and signing classification | Does not claim any store upload |

The toolchain is Flutter **3.47.9**, Java **17**, and the selected hosted macOS
runner's Xcode. The exact Flutter version is also checked by `check_source.py`.
Codemagic pins Xcode **26.6**, following the independently inspected CopyBox
acceptance workflow. Esha uses Flutter 3.47.9 rather than copying its older
Flutter 3.47.7 pin. Commit `apps/esha/pubspec.lock`; dependency resolution runs
with `--enforce-lockfile`.

Run locally from the repository root after installing the pinned Flutter SDK:

```sh
bash scripts/esha/validate.sh
bash scripts/esha/build_android.sh unsigned
# Requires macOS, Xcode, and the app's native dependency toolchain:
bash scripts/esha/build_ios_simulator.sh
```

The manual Codemagic workflow `esha-native-validation` produces the same three
test artifacts on a Mac builder. It has no triggering events or publishing
configuration. Starting it consumes the existing account's build capacity.

## Manual signed Android candidate

Workflow: `esha-android-candidate`, using **`mac_mini_m2`**.

The [Android signing prerequisite receipt](../../apps/esha/release/android-signing-prerequisites-20261115.json)
records the live Codemagic keystore check at **21:07:44 UTC on November 15**:
**`ESHA_ANDROID_UPLOAD_KEY` was absent**, with only two other product keystores
visible. No Esha key was created/imported and no signed Android build was
started. The public fingerprint variable's value was not inspected. Google
Play access also remains unverified: automatic approval review rejected the
redirect from `play.google.com` to `google.play/business/` as a mismatched or
untrusted origin. The receipt records that block without claiming a Play app
record or registered upload key.

Before starting it, configure the existing Codemagic app with an upload identity
specifically designated for Esha under reference **`ESHA_ANDROID_UPLOAD_KEY`**.
Preserve the existing upload keys for all other Korlix apps. Retain the actual
Esha keystore in the owner's normal secure custody; never commit it.

In the Codemagic environment group **`esha_release`**, set
`ESHA_ANDROID_UPLOAD_CERT_SHA256` to the approved Esha upload certificate's public
SHA-256 fingerprint. The workflow maps Codemagic's keystore variables to
`ESHA_ANDROID_STORE_FILE`, `ESHA_ANDROID_STORE_PASSWORD`,
`ESHA_ANDROID_KEY_ALIAS`, and `ESHA_ANDROID_KEY_PASSWORD` in memory. Gradle must
use those variables only when all four are supplied. It must leave release
signing unconfigured when none are supplied and must reject incomplete signing
configuration. An `android/key.properties` file is rejected.

The exported `Esha-signed-candidate.aab` is accepted only when its manifest has
the Esha package, native Flutter libraries are present, the JAR signature
verifies without unsigned entries, and its public signing certificate matches
the approved fingerprint and has not expired. This workflow creates an artifact
for review. It does not configure Play App Signing, create a Play application,
or upload to a Google Play track.

## Manual iOS profile setup

Workflow: `esha-ios-signing-setup`. Run it manually after `esha_release` contains
`ESHA_APP_STORE_ID=6835184869` and the actual `ESHA_APPLE_TEAM_ID`.

This job uses the existing **`Codemagic Korlix AI`** integration and imports
**`KORLIX_APP_STORE_CERT`** with **`KORLIX_APP_STORE_PROFILE`** as a bootstrap
asset. Codemagic requires a provisioning profile in this environment section;
the existing profile for `com.korlixdeveloper.korlixai` serves only to permit
asset import. The setup job does not configure Xcode, build or sign an app, or
modify any other app. It never exports a private key. The separate Esha candidate
workflow continues to require **`ESHA_APP_STORE_PROFILE`** for Esha's exact
bundle identifier.

The setup job pins `codemagic-cli-tools` to **0.69.0**. Before
creating anything, it verifies Apple's exact Esha record (app ID `6835184869`,
bundle `com.korlixdeveloper.esha`, SKU `ESHA_IOS_001`), its registered Bundle ID,
and a valid installed distribution identity for the configured team. The
keychain certificate must have a corresponding valid private-key identity and
match an existing Apple API certificate byte for byte. No key is exported.

The script reuses a fully verified active iOS App Store profile. Only a complete
successful lookup with no active profiles permits one profile-creation attempt,
using the observed Esha Bundle ID and verified existing certificate resource IDs.
A mismatched or malformed active profile stops the job for review. Authorization
failures, timeouts, incomplete responses, and ambiguous identities also stop it;
creation is never retried automatically. A subsequent manual run inventories
Apple again before deciding whether anything is missing.

The returned profile is decoded and checked for the exact bundle, team, App ID
prefix, certificate, UUID, validity, and App Store distribution constraints. Only
then are these two artifacts written under `apps/esha/artifacts/ios-signing/`:

- `Esha-App-Store.mobileprovision` — the verified public provisioning profile.
- `Esha-iOS-signing-setup-verification.json` — source revision, public resource
  IDs, certificate/profile fingerprints, expiry dates, and created/reused result.

The verified profile has been imported into Codemagic under reference
**`ESHA_APP_STORE_PROFILE`**. Use that Esha-specific reference for the separate
candidate and upload workflows; future replacements must still pass the exact
identity and profile checks above.
The setup job does not create a certificate, change permissions or capabilities,
build an app, or upload anything to Apple. Its artifact allowlist excludes raw
API responses, logs, private keys, and environment variables.

Fixture and pinned CLI-contract checks, without macOS keychain access or Apple
requests (install `codemagic-cli-tools==0.69.0` first):

```sh
python3 -m unittest discover -s scripts/esha/tests -v
```

## Manual signed iOS candidate

Workflow: `esha-ios-candidate`.

The workflow references the existing **`Codemagic Korlix AI`** App Store Connect
integration and **`KORLIX_APP_STORE_CERT`** distribution certificate. It still
checks the following separate Esha configuration, verified during the setup
checkpoint above:

| Configuration | Required value |
| --- | --- |
| Apple app record | `6835184869`, bundle `com.korlixdeveloper.esha`, SKU `ESHA_IOS_001` |
| Codemagic profile reference | `ESHA_APP_STORE_PROFILE`, an App Store distribution profile for that exact bundle |
| `esha_release` → `ESHA_APP_STORE_ID` | `6835184869` |
| `esha_release` → `ESHA_APPLE_TEAM_ID` | `FJKJ9MUDZ4` |

The existing distribution certificate can serve Esha only if the dedicated Esha
profile includes that certificate and belongs to the configured team. Do not
reuse the main Korlix app's provisioning profile. If another distribution
certificate is required, configure it and update only Esha's workflow reference.

The preflight uses read-only App Store Connect CLI lookups to match the supplied
app ID to the exact Esha bundle. It checks the profile's team, bundle, expiry,
distribution type, and debug entitlement. The next build number is selected
from Apple's latest build and the source version. API lookup errors are fatal;
they are not treated as a missing record or build. The workflow never creates
an Apple app record or provisioning profile.

After export, `Esha-signed-candidate.ipa` must pass checks of its device platform,
bundle identifier, version/build, profile, team, signed entitlements, and code
signature. Review it before any separate store upload. The signed candidate
workflow contains **no publishing section**. The existing non-Esha workflows
are preserved unchanged, including their prior publishing behavior.

## Separate manual iOS upload

The separate `esha-ios-upload` workflow uses the same verified Esha signing and
build pipeline, then uploads the signed IPA with the existing App Store Connect
integration. Its publishing settings explicitly set `submit_to_testflight:
false` and `submit_to_app_store: false`. It configures no tester groups or
notifications. A successful upload records Apple's acceptance of the transferred
IPA. Apple's processing state and any later distribution or review submission
require separate verification. The candidate workflow remains available for
artifact review without uploading.

The existing Apple integration authenticated successfully, and the verified
Esha profile is imported for both signed workflows. Each build still reruns
its own identity/profile preflight. The prior
signing setup labeled a local CLI argument failure as HTTP 401: CLI 0.69.0
rejects zero retry limits, and the option name `--api-unauthorized-retries`
matched an overly broad error classifier. That failure did not establish an
Apple authentication rejection. Signing and listing CLI calls now use a limit
of one, which this CLI defines as one request with no retry, and authentication
errors require a numeric status from the CLI's Apple HTTP-error rendering.
The successful corrected signing job, draft-listing job and both signed uploads
are recorded in the checkpoint above, with separate immutable upload receipts.
The **21:10:34 UTC** inventory identifies both exact build IDs and verifies each
as VALID and not expired. No build was selected at that historical checkpoint;
the **21:14:24 UTC** selection receipt subsequently confirms build 2 selected
for version 1.0.0.

The regression check uses the actual pinned CLI parser and HTTP session with
credentials absent and transport mocked. After installing
`codemagic-cli-tools==0.69.0`, run:

```sh
python3 -B -m unittest discover -s scripts/esha/tests -p 'test_cli_contract.py' -v
```

Its single-attempt behavior follows the pinned
[retry argument validation](https://github.com/codemagic-ci-cd/cli-tools/blob/v0.69.0/src/codemagic/tools/app_store_connect/arguments.py)
and [HTTP session counter](https://github.com/codemagic-ci-cd/cli-tools/blob/v0.69.0/src/codemagic/apple/app_store_connect/api_session.py).

## Apple draft listing

Manual workflow: `esha-apple-draft-listing`. It applies the prepared draft fields
using the verified existing integration on `mac_mini_m2`. Its first successful
run is preserved in the draft-listing receipt linked above.

`sync_apple_listing.py` reads `apps/esha/release/store-metadata.json` and verifies
Esha's exact Apple identity and editable pending records. Its default mode
produces a read-only change plan. `--apply-draft` synchronizes only the approved
listing text, categories, version number and privacy links, then reads them back.
It has no upload, submission, publication or questionnaire operations. See
[Apple draft listing synchronization](APPLE_LISTING.md) for invocation, the exact
field allowlist, authentication prerequisites and partial-progress reporting.

## Apple release inventory

Manual workflow: `esha-apple-release-inventory`. `inspect_apple_release.py`
makes GET-only requests for the exact Esha app and records its builds, editable
version, selected-build relationship, screenshot sets, subscription inventory
and review-field presence. It never exports reviewer credential values or
changes them. Its artifact is
`apps/esha/artifacts/apple-inventory/Esha-Apple-release-inventory.json`.

The **20:56:56 UTC** inventory linked above found version **1.0.0** in
**Prepare for Submission**, no selected build, no native screenshot sets and
no subscription groups. Demo-account credential fields were present, while
review contact fields were absent. Presence does not verify that reviewer login
works. Preserve the existing credentials while completing the missing contact
information and testing reviewer access.

The subsequent
[post-subscription inventory](../../apps/esha/release/apple-inventory-after-subscription-20261115.json)
completed **19 GET requests at 21:10:34 UTC**, source
`d62f76a8fc97eac812668e884ba0b57d7ba84ceb`. It observed:

| Area | Verified observation at 21:10:34 UTC, before build selection |
| --- | --- |
| Branded build 2 | ID `50de7424-a350-42fb-9a9d-78eb17021ace`, `VALID`, not expired; build 1 also remains `VALID` |
| Version 1.0.0 | `PREPARE_FOR_SUBMISSION`; no selected build at this historical check |
| Encryption declaration | `uses_non_exempt_encryption: null`; no answer inferred |
| Subscription | Product `6835214491`, exact Esha product ID, `ONE_MONTH`, `MISSING_METADATA`, expected en-US localization |
| USA price schedule | `USD 4.99`, `UPFRONT`; observed schedule does not verify StoreKit's current customer price |
| USA introductory offer | `FREE_TRIAL`, `THREE_DAYS`, one period, start `2026-11-15`, no end date |
| Screenshots | Subscription review screenshot absent; no iPhone/iPad app screenshot sets |
| Review access | Contact fields absent; existing demo credentials present but untested |

The inventory does not select a build, repair missing metadata or complete
owner declarations. It does not inspect account agreements or the app privacy
questionnaire, infer age-rating completeness from nullable fields, or verify
StoreKit purchase behavior and trial eligibility.

## Apple draft build selection

Source `8adf46d7587ced117e725f88a404913c0d2eb61b` publishes
`select_apple_build.py`, **15 selection tests** and the manual
`esha-apple-select-build` workflow. The
[live job `6afa207890e83b09c4fabb6a`](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa207890e83b09c4fabb6a)
completed at **21:14:24 UTC**. Its independently downloaded
[selection receipt](../../apps/esha/release/apple-build-selected-20261115.json)
records **`build_selected_and_read_back`**, **16 total requests**, **one PATCH**
and **zero retries**. Existing version `ab8553e4-56d5-40a9-aa7a-8cfb447fca72`
remains **PREPARE_FOR_SUBMISSION** and now selects exact build
`50de7424-a350-42fb-9a9d-78eb17021ace`, **1.0.0 (2)**, **VALID** and unexpired.
The build's encryption field remains `null`. No declarations, review contacts,
review submission or publication changed. The prior inventory's empty build
relationship is historical and is superseded by this successful readback.

The helper's default invocation makes **GET-only Apple requests** and writes a
local plan. Explicit `--apply-draft` may associate only the following exact build
with the existing editable version:

| Guard | Required value |
| --- | --- |
| App identity | App `6835184869`, bundle `com.korlixdeveloper.esha`, SKU `ESHA_IOS_001` |
| App Store version | Exactly one iOS `1.0.0` version in `PREPARE_FOR_SUBMISSION` |
| Build | Number `2`, ID `50de7424-a350-42fb-9a9d-78eb17021ace`, reached through Esha's own builds list |
| Build processing | `VALID`, not expired, with no incompatible audience value |
| Pre-release version | The build's `preReleaseVersion` must be `1.0.0` on `IOS` |
| Existing selected build | Empty for a write; the exact target is verified without rewriting; any different build stops the operation |

The helper checks identity and inventory during planning, then repeats those
checks immediately before apply. It pins the version and pre-release resource
identities and reads the selected-build relationship last before recording
durable intent. It permits **one PATCH maximum**, changing only the version's
build relationship. A fresh GET readback must confirm the exact target build.
There are no PATCH retries; an uncertain response permits only GET reconciliation
and stops if the result cannot be confirmed.

The manual workflow uses `mac_mini_m2`, the existing **`Codemagic Korlix AI`**
integration and `esha_release`, with `codemagic-cli-tools==0.69.0` installed in
`$CM_BUILD_DIR/.esha-apple-selection-tools`. To produce the default read-only
plan:

```sh
"$CM_BUILD_DIR/.esha-apple-selection-tools/bin/python" \
  "$CM_BUILD_DIR/scripts/esha/select_apple_build.py"
```

The manual workflow invokes the separate apply mode:

```sh
"$CM_BUILD_DIR/.esha-apple-selection-tools/bin/python" \
  "$CM_BUILD_DIR/scripts/esha/select_apple_build.py" --apply-draft
```

Both modes write
`apps/esha/artifacts/apple-build-selection/Esha-Apple-build-selection-verification.json`.
The receipt distinguishes `plan_only_no_changes`, `already_selected_verified`,
`build_selected_and_read_back`, and `selection_reconciled_after_ambiguous_patch`.
A stopped run reports `stopped_review_partial_progress` and preserves the
observed state, attempted operation and sanitized Apple rejection details. An
ambiguous PATCH is not reported as proof that this run changed the relationship.

This helper does **not** answer encryption or other declarations, change review
contacts, submit review or publish the app. If Apple rejects the association
for a compliance requirement, it records the rejection and stops; no declaration
is supplied automatically. Selecting a build does not activate billing or AI
or complete the release checks below.

## Apple subscription draft

Source `d62f76a8fc97eac812668e884ba0b57d7ba84ceb` publishes
`prepare_apple_subscription.py`, the exact
[subscription specification](../../apps/esha/release/apple-subscription-draft.json)
and two manual Codemagic workflows. The
[live plan receipt](../../apps/esha/release/apple-subscription-plan-20261115.json)
records **two GET requests, no writes and nine planned creation stages** at
**21:06:23 UTC**. It confirmed that the Esha group/product did not yet exist.

The subsequent
[draft job `6afa1f0790e83b09c4fabaf9`](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa1f0790e83b09c4fabaf9)
completed at **21:08:56 UTC** from that exact source. The immutable
[prepared-draft receipt](../../apps/esha/release/apple-subscription-prepared-20261115.json)
records `subscription_draft_prepared`, **nine created-and-read-back components**,
**113 total requests** and **zero POST retries**. Apple group **22583130** and
product **6835214491** have the exact specification below, including the actual
USD 4.99 price point, USA-only availability and eligible three-day trial.
Agreement status and real-device purchases remain unverified. This operation
did not activate billing or AI, change agreements, submit review or publish Esha.
The later inventory independently confirms the expected localization, price
schedule and trial shape, while reporting **MISSING_METADATA** and no
subscription review screenshot. Draft creation is not review readiness.

| Workflow | Behavior |
| --- | --- |
| `esha-apple-subscription-plan` | Default invocation: GET-only Apple requests; write a local plan without Apple changes |
| `esha-apple-subscription-draft` | Explicit `--apply-draft`: create only absent components matching the exact specification |

Both workflows use `mac_mini_m2`, the existing **`Codemagic Korlix AI`**
integration and `esha_release` group, with `codemagic-cli-tools==0.69.0` in
`$CM_BUILD_DIR/.esha-apple-subscription-tools`. The helper verifies Apple app
**6835184869**, bundle **com.korlixdeveloper.esha** and SKU **ESHA_IOS_001**
before planning and before writes. The specification is fixed to:

| Setting | Exact value |
| --- | --- |
| Group | `Esha Membership` |
| Product ID | `com.korlixdeveloper.esha.monthly` |
| Product name | `Esha Membership Monthly` |
| Period and payment plan | `ONE_MONTH`, `UPFRONT` — payment in full for each one-month period |
| Territory and price | `USA`, `USD`, `4.99` |
| Introductory offer | `FREE_TRIAL`, `THREE_DAYS`, one period for eligible subscribers |
| Localization | `en-US` |
| Availability | Create only if absent: USA-only `UPFRONT`, `availableInNewTerritories: false` |
| Family sharing and group level | `false`, `1` |

The helper follows Apple API **4.6** subscription/group versions and **v2
localizations**, while using v1 subscription, price and introductory-offer
resources. Independent schema review found no contract mismatch. The
`UPFRONT` plan type is paired with `ONE_MONTH`; it does not create an annual
installment commitment.

Planning inventories the existing group, group version, localization, product,
product version, localization, availability, USA price and introductory offer.
Apply mode reuses exact existing components and creates only missing ones.
Conflicting settings, duplicate or ambiguous resources, an unexpected identity,
or a non-editable draft stop the operation. It never replaces existing
availability, changes existing prices or offers, or silently chooses a different
territory or price.

There are **no HTTP or POST retries**. The helper records write intent before
each POST, then rereads state and verifies the returned resource ID. If a POST
has an ambiguous outcome, it performs GET reconciliation only and stops when
the result cannot be established. Earlier verified creations may remain after
a stopped run. Review the sanitized partial-progress receipt and current Apple
state before deciding whether another run is appropriate.

The default plan invocation is:

```sh
"$CM_BUILD_DIR/.esha-apple-subscription-tools/bin/python" \
  "$CM_BUILD_DIR/scripts/esha/prepare_apple_subscription.py"
```

The separate manual draft invocation is:

```sh
"$CM_BUILD_DIR/.esha-apple-subscription-tools/bin/python" \
  "$CM_BUILD_DIR/scripts/esha/prepare_apple_subscription.py" --apply-draft
```

Both modes write
`apps/esha/artifacts/apple-subscription/Esha-Apple-subscription-draft-verification.json`.
Successful plan status is `plan_only_no_changes`; verified draft completion is
`subscription_draft_prepared`. A stopped run reports
`stopped_review_partial_progress`. The receipt includes public resource IDs,
the specification digest and planned/attempted/verified operations, without raw
credentials or JWTs. It does not constitute owner approval or prove customer
checkout is enabled.

This helper has **no review submission, publication, agreement, permission,
backend activation or AI activation operations**. It does not select a build
or change store declarations. A prepared subscription draft still requires the
release checks below.

The full release automation suite with pinned CLI 0.69.0 passes **91 offline
tests**, including **19 subscription**, **19 inventory** and **15 build-selection**
tests. These validate guarded behavior and
API request shapes. The separate prepared-draft receipt establishes live draft
creation; the offline suite does not verify purchase functionality. To run the
full release suite:

```sh
python3 -B -m unittest discover -s scripts/esha/tests -v
```

## Membership release gate

The intended offer is **3 days free for eligible new subscribers, then
US $4.99 per month**, automatically renewing through the relevant store.
Compilation or signing does not activate this offer. Production release still
depends on verified Esha subscription products, correct regional store pricing
and trial eligibility, backend purchase validation and entitlement handling,
and successful store sandbox tests. The client must keep purchase activation
gated by the server's verified catalog; no local three-day clock grants paid
access. Physical beauty products are separate purchases.

The current live policy deployment does **not** activate checkout or AI.
In the November 15 live receipt linked above, both Apple and Google billing
catalogs returned `purchasesEnabled: false`, `consultationEnabled: false`,
`allowanceConfigured: false` and `storeConfigurationVerified: false`; both
consultation counts were `null` and membership remained `planned`. These live
gates remain blockers to customer checkout and consultations even though the
policy pages, Apple signing setup and draft listing are complete.

Apple's subscription product remains **MISSING_METADATA**. The subscription
review screenshot, iPhone/iPad app screenshots, review contact fields and
required owner declarations remain unfinished. **Build 2 is selected and read
back for version 1.0.0**, which remains **Prepare for Submission**. Existing demo credentials must be preserved while reviewer
access is tested. Agreement status and real-device StoreKit checks remain
unverified even though both uploaded builds have processed successfully.

## Implementation references

- Existing repository branch `ops/copybox-android-acceptance-20261114`, commit
  `4b2c4031ff5716736e18f9a047804cc0bd823423`: inspected for the standalone
  Codemagic working directory, explicit signing references, locked validation,
  Apple CLI 0.69.0, and candidate artifact pattern.
- [Flutter Android release documentation](https://docs.flutter.dev/deployment/android)
- [Flutter iOS release documentation](https://docs.flutter.dev/deployment/ios)
- [Codemagic Android signing](https://docs.codemagic.io/yaml-code-signing/signing-android/)
- [Codemagic iOS signing](https://docs.codemagic.io/yaml-code-signing/signing-ios/)
- [AOSP compiled XML protobuf schema](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/tools/aapt2/Resources.proto)
- [Java 17 JAR signature verification and strict warning codes](https://docs.oracle.com/en/java/javase/17/docs/specs/man/jarsigner.html)
