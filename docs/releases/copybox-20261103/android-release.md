# COPY Box Android release candidate

**Status: signed candidate verified and accepted into a saved Play internal testing draft; no rollout.**
The user explicitly replied **Approve setup** for free download, all supported
countries, Google's creation declarations, a dedicated upload key with protected
independent backup, Codemagic import, and the signed candidate build. Google Play
app **4974456296219116192** now exists under KORLIX developer
**4772708594176030332**. A fresh page confirms **Your app is Free**, and all
**178** production targets, including Rest of World, are saved. Production is
**Inactive**; no review or rollout has been submitted. The verified AAB is saved
as version **1.0.0 (1)** in internal testing draft release **1**, track
**4699672053930799570**. No testers are configured.

Signing and build results are tracked in [release-status.json](release-status.json).
The unchanged [artifact verification report](android-artifact-verification.json)
records the actual AAB and generated universal APK checks. Physical-device
runtime and Play-delivered APK testing remain outstanding.

## Manual workflow

Select **`korlix-copybox-android-candidate`** in the root `codemagic.yaml`, on the
reviewed release branch. It has no automatic triggering events or publishing
configuration. It builds the independent app with application ID
`com.korlixdeveloper.copybox` using Flutter `3.47.7` and Java `17`.
The current revision selects `mac_mini_m2` after the worker-only fix described
below.

The workflow resolves the committed lockfiles with `pub get --enforce-lockfile`,
then analyzes and tests both `packages/korlix_auth_core` and
`apps/korlix_copy_box`. It builds the release bundle only after these checks pass.
The app test step uses the same SDK font and screenshot fixture settings as the
successful GitHub validation run.

## Build attempts — November 4, 2026

| Attempt | Source | Worker | Observed result |
| --- | --- | --- | --- |
| `6aeb7e24c89c60076c761c73` | `4dd07806ff471263b1fb82d593f300cfe9693a4d` | `linux_x2` | Failed before compilation: selected instance unavailable on the current billing plan |
| [6aeb7ea6004ce28f20ede0b2](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6aeb7ea6004ce28f20ede0b2), index 2 | `2c6544dba9afe2117181afabdc78a856ef4f249d` | `mac_mini_m2` | Finished successfully in 7m 16s; analyzers clean and all 140 tests passed; actual AAB/generated APK static verification passed with documented warnings |

The first attempt reported **The selected instance type is not available with
the current billing plan.** It did not compile or produce an AAB. Commit
`2c6544dba9afe2117181afabdc78a856ef4f249d` changes exactly one line: this
workflow's `instance_type: linux_x2` becomes `instance_type: mac_mini_m2`.
The YAML blob is `b51ace57dd3094da6c5a5b3246af6c3a2ad7c15d`. The M2 worker already
completed the separate iOS signed build successfully. App code, signing key,
version, tests, and other workflows were not changed, and no billing plan was
modified.

The retry was verified queued on the M2 worker, the exact fixed commit, and
branch `feature/korlix-copy-box-20261103`; SSH/VNC remained unchecked. A fresh
reload then showed **Building**, started **November 4 at 18:56 UTC / 13:56 EST**.
The log confirms no analyzer issues (shared 5.9 seconds; app 7.5 seconds) and all
**59 shared + 81 app tests** passed. The final status is **FINISHED**, total
duration **7m 16s**. Packaging took **4m 29s**, publishing **6s**, and cleanup
**less than 1s**. There is no automatic Play publishing step. The subsequent
manual console upload and saved draft are recorded below.

The artifact list shows `KorlixCopyBox.aab` (**53.28 MB**) and
`Ai-wiz-command-center_2_artifacts.zip` (**793 B**). The actual downloaded AAB is
**55,864,103 bytes**, SHA-256
`cc9e3b467fe3b4409db2ce93cc9ebc961cddd09333174bc9a82227c87f9bebaa`.
CI's native scanner reported no validation errors and
`apk_zip_layout_checked: false`. The additional bundletool and generated-APK
checks were completed independently on that downloaded bundle.

### Actual signed artifact results

The unchanged [sanitized verification report](android-artifact-verification.json)
is **14,655 bytes**, SHA-256
`9ea3e9c54fc6a95ea0799b7618c43050061e3e4e87dda9d46fa953b12d87249b`.
Its status is **passed_with_documented_jarsigner_warnings**.

| Check | Verified result |
| --- | --- |
| Bundle structure | Official bundletool 1.18.3 validation passed |
| AAB signature | Dedicated COPY Box upload certificate matched; all 406 payloads have matching signed-manifest SHA-256 digests; no unsigned payload entries |
| Manifest | `com.korlixdeveloper.copybox`, version 1.0.0, code 1, minimum SDK 24, target SDK 36 |
| Release controls | Debugging, backup, and cleartext traffic disabled |
| Permissions | INTERNET and the app's own signature-protected dynamic-receiver permission only |
| Native packaging | `PAGE_ALIGNMENT_16K`; all 12 AAB native libraries pass ELF alignment |
| Generated universal APK | Valid v2/v3 signatures, matching upload certificate, all 12 libraries uncompressed and aligned in ELF and APK ZIP layout |

The generated universal APK is **57,115,896 bytes**, SHA-256
`d4ccf6591dcdc0008e0f4c34316c9d9062b45c26d49ae9dad337924f2b571bab`.
Java reported a self-signed upload certificate, no JAR signature timestamp,
unsigned POSIX attributes, and a JarInputStream warning because the signing
manifest is the last ZIP entry. Random-access signature verification succeeded;
the additional coverage check confirmed matching signed digests for all 406
payloads and the whole signing manifest. The original AAB was not modified.
The report records these warnings and their evidence explicitly.

These are static artifact results. No installation, physical-device or 16 KB-page
runtime test, or Play-delivered APK check is established by this report. Its
scope also predates the separate Play acceptance observation below.

### Google Play upload and saved internal draft

The verified AAB was uploaded and processed successfully. A fresh saved
Prepare page shows **App bundle 1 (1.0.0)**, API **24+**, target **36**, **4 screen
layouts**, **3 ABIs**, and **1 required feature**, with ReTrace mapping and native
debug symbols attached and an **Enhanced** label. Release **1** in internal
testing track **4699672053930799570** has name
**1.0.0 (1) - initial internal test** and the prepared **en-US** release notes.
Save as draft confirmed **Changes saved. You can now preview your release before
publishing it.**

The [release preview](https://play.google.com/console/u/0/developers/4772708594176030332/app/4974456296219116192/tracks/4699672053930799570/releases/1/review)
showed **one warning**: no testers are specified, so the release is not available
to any users. No error was displayed. The estimated download is **11 MB / 6s**.
**Save and publish was available but was not clicked.** No testers, invitations,
review submission, or rollout were configured. The upload-certificate
registration page was not rechecked; bundle acceptance is the verified result.

The final [internal-track readback](https://play.google.com/console/u/0/developers/4772708594176030332/app/4974456296219116192/tracks/internal-testing?releaseType=defaultReleases)
shows **Inactive**, the named **Draft** release, and **1 of 3 complete**, with
Create a new release completed. Its expanded summary confirms version code
**1**, **178 countries**, **19,573 supported Android devices**, and bundle
explorer artifact ID **4860247929005203987**. Testers are not selected and the
preview has not been published.

## Required signing reference

Codemagic must already contain the COPY Box upload keystore under **Code signing
identities → Android keystores**, with this exact reference:

```text
KORLIX_COPYBOX_ANDROID_UPLOAD_KEY
```

The dedicated key has been created, its protected independent backup verified,
and Codemagic import confirmed by the fresh keystore list. Public certificate
details:

| Field | Verified value |
| --- | --- |
| Alias | `korlix_copybox_upload` |
| Common name / issuer shown in Codemagic | KORLIX COPY Box Upload |
| Key and signature | RSA 2048 / SHA256withRSA |
| Certificate validity | 2026-11-04T18:30:56Z–2054-03-22T18:30:56Z |
| Certificate SHA-256 | `4E:92:04:B6:04:11:F4:F5:72:30:51:6E:E3:CD:E8:8D:27:B9:8A:72:FF:3E:72:97:4A:44:94:31:10:B9:3F:A7` |

These facts establish the dedicated signing identity and its successful
Codemagic import. The completed build, artifact checks, and accepted Play bundle
are recorded separately above. Explicit Play upload-certificate registration UI
evidence remains unverified because that page was not rechecked after upload.
Keep private paths, backup links, credential values, and recovery material out
of this repository and retained build reports.

### Google-managed app-signing certificate

Google Play's App signing page shows **App signing key: In use**, with displayed
install base **0.0%**. Its Digital Asset Links JSON names exact package
`com.korlixdeveloper.copybox` and SHA-256
`C5:B8:82:D1:29:C8:46:A9:D6:36:06:75:11:B3:5D:AB:52:1B:DD:3C:9D:D0:0C:57:82:BC:4E:C3:25:07:C8:0A`.
This is the Google-managed **app-signing** certificate. The `4E:92:…` fingerprint
in the preceding table belongs to the dedicated **upload** key, which must be
used when verifying the local Codemagic AAB's signer. No separate
enrollment/acceptance prompt appeared, and no signing settings were changed.
The later bundle upload was accepted. Explicit upload-key registration UI
evidence was not rechecked and is not inferred from this app-signing page.

### Workflow signing inputs

Codemagic fetches that single referenced keystore and supplies these variables.
The build step maps them to the app's existing Gradle signing interface:

| Codemagic variable | COPY Box Gradle environment variable |
| --- | --- |
| `CM_KEYSTORE_PATH` | `KORLIX_COPYBOX_ANDROID_STORE_FILE` |
| `CM_KEYSTORE_PASSWORD` | `KORLIX_COPYBOX_ANDROID_STORE_PASSWORD` |
| `CM_KEY_ALIAS` | `KORLIX_COPYBOX_ANDROID_KEY_ALIAS` |
| `CM_KEY_PASSWORD` | `KORLIX_COPYBOX_ANDROID_KEY_PASSWORD` |

The workflow rejects missing values, a missing keystore file, or an
`android/key.properties` file. That file takes precedence in Gradle, so rejecting
it ensures the declared Codemagic identity supplies the signing configuration.
Credentials remain environment variables in the build process and are not
written into repository files or retained artifacts.

## Build command and retained output

After the environment mappings and successful locked validation, the command is
run from `apps/korlix_copy_box`:

```sh
flutter build appbundle --release --no-pub
```

Version name and version code come from the app's committed `pubspec.yaml`
(currently `1.0.0+1`). Initial version code **1** is accepted in the saved Play
draft. A later replacement binary must use an unused version code for that app
and rebuild the reviewed source.

The workflow checks that the bundle exists and retains this downloadable
Codemagic artifact:

```text
apps/korlix_copy_box/artifacts/KorlixCopyBox.aab
```

The source output is
`build/app/outputs/bundle/release/app-release.aab`. The initial signed candidate
was downloaded and verified before its authorized Play Console upload. This workflow
has no Google Play publishing step or Play service-account integration.

The native scanner checks the AAB's ELF load alignment, but an AAB is not the
APK installed on a device. Bundletool's `PAGE_ALIGNMENT_16K` configuration and
the generated APK ZIP alignment have now been checked. Before release,
exercise the signed build in a 16 KB-page Android environment. The successful
debug APK check from run 41844773126 does not verify that later signed bundle's
packaging or runtime behavior.

## Reproduce the actual downloaded-bundle checks

The initial candidate's checks are complete in the report above. For a later
candidate, run these checks on the downloaded AAB from its specific Codemagic
build. Record that build's source commit, artifact byte size and SHA-256, and
compare its public signer fingerprint with the dedicated upload key's verified
public certificate. The existing workflow performs locked analysis/tests and
the ELF scan; its success alone does not verify the AAB signature or compiled
manifest. Repeating the earlier source tests locally is unnecessary.

From the repository root, set `COPYBOX_AAB`, `COPYBOX_REPORT_DIR`, and
`COPYBOX_BUNDLETOOL_JAR` to the actual artifact, report directory, and verified
tool paths. These commands do not require signing credentials:

```sh
mkdir -p "$COPYBOX_REPORT_DIR"
wc -c < "$COPYBOX_AAB"
sha256sum "$COPYBOX_AAB"
java --module jdk.jartool/sun.security.tools.jarsigner.Main \
  -verify -verbose -certs "$COPYBOX_AAB" \
  > "$COPYBOX_REPORT_DIR/aab-signature.txt"
keytool -printcert -jarfile "$COPYBOX_AAB" \
  > "$COPYBOX_REPORT_DIR/aab-public-certificate.txt"
python3 scripts/ci/inspect-copybox-artifact.py android "$COPYBOX_AAB" \
  --output "$COPYBOX_REPORT_DIR/aab-native-dependencies.json"
java -jar "$COPYBOX_BUNDLETOOL_JAR" validate --bundle="$COPYBOX_AAB"
java -jar "$COPYBOX_BUNDLETOOL_JAR" dump config --bundle="$COPYBOX_AAB" \
  > "$COPYBOX_REPORT_DIR/BundleConfig.json"
java -jar "$COPYBOX_BUNDLETOOL_JAR" dump manifest \
  --bundle="$COPYBOX_AAB" --module=base \
  > "$COPYBOX_REPORT_DIR/AndroidManifest.xml"
rg 'PAGE_ALIGNMENT_16K|PAGE_ALIGNMENT_4K' "$COPYBOX_REPORT_DIR/BundleConfig.json"
```

Review the signature result, including any unsigned payload warning; a public
certificate fingerprint by itself is not signature verification. A self-signed
Android upload certificate does not need a public certificate-authority chain.
Verify package `com.korlixdeveloper.copybox`, actual version/code against the
build record (currently `1.0.0` / `1`), minimum SDK 24, target SDK 36, debugging
absent/false, backup disabled, cleartext disabled, and the full merged permission
inventory. The existing compiled-APK checks in
`.github/workflows/korlix-copybox-validation.yml` provide the identity and
protected/media/storage/ad-ID permission checks to carry over to this artifact.
Require no ELF validation errors and a `PAGE_ALIGNMENT_16K` request in the bundle
configuration. These are artifact checks, not installation or runtime results.

To inspect a representative APK generated from that exact AAB, use bundletool's
`build-apks --mode=universal` with the authorized existing keystore, its alias,
and `--ks-pass=file:...` / `--key-pass=file:...` pointing to protected inputs.
Do not copy credential values into commands or reports. Without explicit signing
information, bundletool attempts debug signing. Extract the generated
`universal.apk`, run the same Python native scanner on it, and verify its signer
with an APK signature verifier. The completed check used `com.android.apksig.ApkVerifier`
from the pinned official bundletool JAR, checked across API 24–36. The scanner checks the APK's actual
uncompressed-library ZIP offsets in addition to ELF load alignment.

For the final device check, confirm `adb shell getconf PAGE_SIZE` returns
`16384`, then exercise the signed candidate's local writing, clipboard,
file-picker/sharing, sign-in, and optional AI flows. Record this separately from
static alignment and the earlier debug-build evidence.

### Verification tool availability observed November 4

The current workspace has Java 17.0.20 and `keytool`. The `jarsigner` launcher is
absent, but the installed `jdk.jartool` module and its jarsigner entry point above
were verified with their help output. The initial scoped lookup found no
Android SDK tools or bundletool on PATH or in configured/common JVM and Android
SDK locations.

The minimal additional tool for the AAB checks is Google's
[bundletool 1.18.3 all-JAR](https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar).
The official release API reports **32,520,401 bytes** and SHA-256
`a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`.
That pinned artifact was subsequently downloaded to an ephemeral tool directory
through normal public HTTPS. Its exact byte size and SHA-256 matched, and
`java -jar ... version` returned **1.18.3**. The official pinned source confirms
the `validate --bundle`, `dump config`, and `dump manifest` command forms.

If Android SDK tooling is needed for the generated APK, acquire it through the
[official command-line tools](https://developer.android.com/studio#command-tools)
and [SDK package manager](https://developer.android.com/tools/sdkmanager): Build
Tools `36.0.0` supplies `zipalign` and `apksigner`, and Command-Line Tools supplies
`apkanalyzer`. The corresponding checks are `zipalign -c -P 16 -v 4` and
`apksigner verify --verbose --print-certs` on the actual APK. The existing Python
scanner remains available without those downloads. No workflow change is
required merely because these tools were absent from this workspace.

## Official configuration references

Syntax was checked against Codemagic's current documentation:

- [Android code signing](https://docs.codemagic.io/yaml-code-signing/signing-android/):
  keystore reference names, `environment.android_signing`, and the four generated
  signing variables.
- [YAML configuration](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/):
  Java selection, working directories, manual execution when triggering events
  are absent, and artifact paths.
- [Android bundletool](https://developer.android.com/tools/bundletool): bundle
  validation/generation workflow and explicit signing inputs for generated APKs.
- [Android 16 KB page sizes](https://developer.android.com/guide/practices/page-sizes):
  bundle configuration, generated APK alignment, and device runtime checks.

Initial preparation checks were limited to YAML parsing, shell syntax, and
preservation of existing workflow definitions. No local Flutter command or
store-release workflow was executed during that initial preparation. Later
execution and artifact results belong in the dated release checkpoint.
