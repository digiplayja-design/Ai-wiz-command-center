# Esha native builds

These scripts operate only on `apps/esha`, with the separate Android package and
iOS bundle identifier `com.korlixdeveloper.esha`. That identifier is a release
candidate until its Apple and Google store records have been verified.

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

Workflow: `esha-android-candidate`.

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

Import the verified profile into Codemagic under reference
**`ESHA_APP_STORE_PROFILE`** before starting the separate candidate workflow.
The setup job does not create a certificate, change permissions or capabilities,
build an app, or upload anything to Apple. Its artifact allowlist excludes raw
API responses, logs, private keys, and environment variables.

Fixture checks, without macOS keychain access or Apple requests:

```sh
python3 -m unittest discover -s scripts/esha/tests -v
```

## Manual signed iOS candidate

Workflow: `esha-ios-candidate`.

The workflow references the existing **`Codemagic Korlix AI`** App Store Connect
integration and **`KORLIX_APP_STORE_CERT`** distribution certificate. It still
requires the following separate Esha configuration:

| Configuration | Required value |
| --- | --- |
| Apple app record | Existing Esha record with the exact bundle `com.korlixdeveloper.esha` |
| Codemagic profile reference | `ESHA_APP_STORE_PROFILE`, an App Store distribution profile for that exact bundle |
| `esha_release` → `ESHA_APP_STORE_ID` | Numeric ID of Esha's own App Store Connect record |
| `esha_release` → `ESHA_APPLE_TEAM_ID` | Actual Apple Developer team ID for Esha's profile and distribution certificate |

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
signature. Review it before any separate store upload. Esha workflows contain
**no publishing section**, so they neither upload to TestFlight nor submit to
App Review. The existing non-Esha workflows are preserved unchanged, including
their prior publishing behavior.

## Membership release gate

The intended offer is **3 days free for eligible new subscribers, then
US $4.99 per month**, automatically renewing through the relevant store.
Compilation or signing does not activate this offer. Production release still
depends on verified Esha subscription products, correct regional store pricing
and trial eligibility, backend purchase validation and entitlement handling,
and successful store sandbox tests. The client must keep purchase activation
gated by the server's verified catalog; no local three-day clock grants paid
access. Physical beauty products are separate purchases.

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
