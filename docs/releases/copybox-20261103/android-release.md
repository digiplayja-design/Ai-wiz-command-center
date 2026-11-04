# COPY Box Android release candidate

**Status: prepared, unexecuted.** The new Codemagic workflow has not been run.
Its configuration is not evidence of a signed release AAB or a Google Play
upload. The existing debug APK validation is separate from release signing.

## Manual workflow

Select **`korlix-copybox-android-candidate`** in the root `codemagic.yaml`, on the
reviewed release branch. It has no automatic triggering events or publishing
configuration. It builds the independent app with application ID
`com.korlixdeveloper.copybox` using Flutter `3.47.7` and Java `17`.

The workflow resolves the committed lockfiles with `pub get --enforce-lockfile`,
then analyzes and tests both `packages/korlix_auth_core` and
`apps/korlix_copy_box`. It builds the release bundle only after these checks pass.
The app test step uses the same SDK font and screenshot fixture settings as the
successful GitHub validation run.

## Required signing reference

Codemagic must already contain the COPY Box upload keystore under **Code signing
identities → Android keystores**, with this exact reference:

```text
KORLIX_COPYBOX_ANDROID_UPLOAD_KEY
```

The release owner must supply the dedicated COPY Box upload key and its correct
passwords and alias. This preparation did not create, upload, replace, or rotate
any signing credentials. Retain an independent secure copy of the keystore.

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
(currently `1.0.0+1`). Before a later Play submission, the release owner must
choose an unused version code for that app and rebuild the reviewed source.

The workflow checks that the bundle exists and retains this downloadable
Codemagic artifact:

```text
apps/korlix_copy_box/artifacts/KorlixCopyBox.aab
```

The source output is
`build/app/outputs/bundle/release/app-release.aab`. Download and review the signed
candidate before any separately authorized Play Console upload. This workflow
has no Google Play publishing step or Play service-account integration.

The native scanner checks the AAB's ELF load alignment, but an AAB is not the
APK installed on a device. Before release, also inspect bundletool's
`PAGE_ALIGNMENT_16K` configuration and the generated APK ZIP alignment, then
exercise the signed build in a 16 KB-page Android environment. The successful
debug APK check from run 41844773126 does not verify that later signed bundle's
packaging or runtime behavior.

## Official configuration references

Syntax was checked against Codemagic's current documentation:

- [Android code signing](https://docs.codemagic.io/yaml-code-signing/signing-android/):
  keystore reference names, `environment.android_signing`, and the four generated
  signing variables.
- [YAML configuration](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/):
  Java selection, working directories, manual execution when triggering events
  are absent, and artifact paths.

Local checks for this addition are limited to YAML parsing, shell syntax, and
preservation of existing workflow definitions. No local Flutter command or
store-release workflow was executed.
