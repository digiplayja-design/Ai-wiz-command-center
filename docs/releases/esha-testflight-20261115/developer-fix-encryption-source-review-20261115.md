# Esha developer-access correction: encryption source review

**Status: build 3 uploaded successfully but failed Apple processing with error
90683. Corrected build 4 passed processing, its compliance answers were saved
with France excluded, and the existing internal group now shows 1.0.0 (4)
as Testing. Physical-device validation of build 4 remains pending.**

Reviewed on 2026-11-15 for Apple app `6835184869`, bundle
`com.korlixdeveloper.esha`, SKU `ESHA_IOS_001`, corrected source commit
`6ad26c6379e9da6ae9a252ec16a0208471ac380c`. GitHub reports tree
`d154f5febdeb8f91d851c8034d840437c267601e`, exactly matching the local committed
tree inspected. Build 3 artifact evidence was appended on 2026-11-16 from the
coordinating agent's downloaded IPA and the two receipts linked below. The
source review and actual artifact observations are distinguished throughout.
Build 4 uses the subsequent privacy-metadata correction at
`262b60ca5e3fe9eb75a7508bdce0da82c0a2b680`, with unchanged cryptographic
dependencies and unchanged application runtime code, as described below.

## Supported questionnaire facts

The source supports the **standard encryption implemented beyond the Apple
operating system** category. The Flutter/Dart HTTPS dependency chain remains,
and the new WebRTC SDK dependency adds standard encrypted media/data transport.
No Esha-authored proprietary cipher or nonstandard encryption algorithm was
found in the reviewed Dart/native app sources. This is a scoped technical
finding, not a signed legal declaration or an exhaustive binary audit.

Apple explicitly includes linked third-party libraries when describing an
app's encryption use. Its documentation table distinguishes OS-only encryption,
standard algorithms supplied outside the OS, and proprietary algorithms.
For the standard non-OS category, the table makes the French declaration
conditional on distribution in France. The owner's current instruction is
**France: No**. The initial source review did not change questionnaire answers
or distribution settings. The later saved build-specific answers are recorded
in the final observation section.

## Exact dependency change from uploaded build 2

The old comparison source is
`fbfde79df731dea5a2e7fc65ee9d4308aebe80dd`. Comparing its exact
`apps/esha/pubspec.lock` with corrected source finds five additions and **no
changed or removed existing package versions**:

| Added package | Locked version |
| --- | --- |
| `flutter_webrtc` | `1.6.3` |
| `webrtc_interface` | `1.5.1` |
| `dart_webrtc` | `1.8.2` |
| `logger` | `2.8.0` |
| `synchronized` | `3.6.1+1` |

`http 1.6.0`, `crypto 3.0.8`, `flutter_secure_storage 10.0.0` and
`flutter_secure_storage_darwin 0.2.0` remain unchanged. The release workflow's
Flutter pin remains `3.47.9`. Build 2's HTTPS/BoringSSL and Keychain findings
provide historical dependency context; its finished-artifact evidence does
not verify the corrected IPA.

The publisher's `flutter_webrtc 1.6.3` archive was downloaded into memory and
hashed during this review: **905,255 bytes**, SHA-256
`b98ef03376401e54ff87fc78907b38e562b15ca8424aba589c263eddc3c1ecf9`, matching both
the publisher metadata and Esha's lockfile. Its iOS podspec, Swift package,
native frame-cryptor mapper and native peer factory were compared byte for
byte with the locally inspected package sources and matched.

Both native packaging paths pin **WebRTC-SDK `150.7871.04`**:

- `ios/flutter_webrtc.podspec` declares that exact CocoaPods dependency.
- `ios/flutter_webrtc/Package.swift` declares the release's
  `WebRTC.xcframework.zip`, with publisher-declared checksum
  `9532fe3ce47507c304f37a4355b907be1e89967971d614a04603005a546249be`.

That framework checksum was read from the verified package source; this review
did not download/hash the framework release or establish which native packaging
path the signed build used. The IPA inspection below confirms an embedded
WebRTC framework, whose generic plist version does not independently confirm
the declared SDK release number.

## WebRTC usage and cryptographic capabilities

`apps/esha/lib/services/voice_audio.dart` creates an audio-only peer connection
using `unified-plan`, no app-supplied ICE servers, and the ordered `oai-events`
data channel. It sets no custom cipher, crypto-options override or
disable-encryption option. The package's default native peer constraints
include `DtlsSrtpKeyAgreement: true`.

Upstream WebRTC documents SRTP media protection with DTLS-SRTP key negotiation,
implemented through `libsrtp`. Its documented SRTP cipher families include
AES-128 counter mode with HMAC-SHA1 and AES-GCM with 128- or 256-bit keys.
The IETF WebRTC architecture specifies SCTP over DTLS for data channels.
These are standard protocol/cipher capabilities; **no live call or negotiated
cipher suite was observed** in this review.

The plugin also contains optional frame/data encryption APIs. The actual iOS
algorithm mapper in `FlutterRTCFrameCryptor.m` selects AES-GCM; the key-derivation
mapper exposes PBKDF2 and HKDF. The Dart enum also names AES-CBC, but its native
iOS mapping falls through to AES-GCM, so the enum is not evidence of AES-CBC
being enabled. Esha does not call the frame/data cryptor factories, key
providers, key ratchets or their enable methods. Optional package capabilities
are not claimed as Esha usage or as retained code in the final binary.

The microphone track's `enabled` property controls transmission, not the choice
of encryption. The backend's disabled voice feature was not enabled, and no
paid voice request or additional grant was created.

## Signed build 3 artifact evidence

Codemagic job
[`6afa462c90e83b09c4fac75a`](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa462c90e83b09c4fac75a)
built the exact corrected source above. The coordinating agent downloaded the
IPA and verification archive through the supported browser download flow and
independently hashed the IPA. The locally computed hash and size match the
Mac build verifier's JSON.

| Observed artifact fact | Value |
| --- | --- |
| Source commit in verifier receipt | `6ad26c6379e9da6ae9a252ec16a0208471ac380c` |
| Version and build | `1.0.0 (3)` |
| IPA size | `48,307,876` bytes |
| IPA SHA-256 | `c38f6e16e5bed6ff7d7a36ae3c10948dfd9bf3e19729a44f2a876084dce6a32b` |
| Bundle identifier | `com.korlixdeveloper.esha` |
| Display name | `Esha by Korlix` |
| Minimum iOS version | `15.0` |
| Mac verifier signing classification | `verified-app-store-distribution` |
| Mac verifier profile type | `app_store` |
| Main plist encryption declarations | `ITSAppUsesNonExemptEncryption` and `ITSEncryptionExportComplianceCode` absent |

The IPA contains `App.framework`, `Flutter.framework`, `WebRTC.framework` and
`objective_c.framework`. The inspected WebRTC framework identifies itself as
`org.webrtc.WebRTC`; **both `CFBundleShortVersionString` and `CFBundleVersion`
are the generic value `1.0`**. Its presence is binary evidence of the embedded
dependency. It is not independent binary confirmation of SDK `150.7871.04`;
that exact version remains supported by the verified source-package pins.

Evidence files:

- [Build 3 Mac signing/artifact verification](build-3-signed-verification.json)
- [Downloaded build 3 IPA identity, hash and framework inspection](build-3-binary-inspection.json)
- [Build 3 successful upload receipt](build-3-upload-receipt.json)
- [Build 3 Apple processing rejection and correction](build-3-processing-failure.json)

The verifier's `submitted_to_store: false` is its **pre-upload** checkpoint.
The subsequent uploader reported success at **2026-11-16 00:00:21.115 UTC**,
delivery UUID `8f8131ba-162d-4ffa-8e75-ddfeb1132cf7`. Apple processing then
**failed with error 90683**, observed at **00:03:50 UTC**, because the IPA lacked
`NSCameraUsageDescription`. Apple's rejection required the purpose string for
camera APIs referenced by the embedded SDK even though Esha does not invoke
those camera APIs. Build 3 was not assigned to the TestFlight group and was
not installable.

## Build 4 correction and artifact evidence

Correction source **`262b60ca5e3fe9eb75a7508bdce0da82c0a2b680`** changes only
the iOS purpose-string metadata, the pubspec build minimum to `1.0.0+4`, the
finished-artifact privacy gate and its focused regression tests. Application
runtime code, dependency versions and the cryptographic source findings above
remain unchanged.

The new gate requires nonempty camera and microphone purpose strings whenever
the exported application embeds `WebRTC.framework`. The processing-failure
receipt records **five passing privacy regression tests** and confirms that
the actual rejected build 3 IPA fails the new gate. The gate therefore checks
the finished bundle before the candidate is exposed for upload.

The downloaded build 4 IPA contains these exact strings:

| Info.plist key | Observed value |
| --- | --- |
| `NSCameraUsageDescription` | Esha’s voice conversations use only your microphone. Esha does not use your camera. |
| `NSMicrophoneUsageDescription` | Esha uses your microphone when you start a voice conversation. Korlix and OpenAI process your audio and conversation to answer you. |

The camera description supplies SDK-required metadata; no camera feature was
added. The unchanged capture call requests `audio: true` and `video: false`,
rejects returned video tracks and requests no incoming video in its SDP offer.

Codemagic job
[`6afa487290e83b09c4fac7d3`](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa487290e83b09c4fac7d3)
finished in **6 minutes 8 seconds**. The independent IPA inspection at
**2026-11-16 00:09:19 UTC** matches the Mac verifier's hash and size:

| Observed artifact fact | Value |
| --- | --- |
| Source commit | `262b60ca5e3fe9eb75a7508bdce0da82c0a2b680` |
| Version and build | `1.0.0 (4)` |
| IPA size | `48,307,985` bytes |
| IPA SHA-256 | `78a4dc53fb004982c014e3c7af604855c6f8e3ee789cddb9d216a25960dde6dd` |
| Bundle identifier | `com.korlixdeveloper.esha` |
| Display name | `Esha by Korlix` |
| Minimum iOS version | `15.0` |
| Mac verifier signing / profile | `verified-app-store-distribution` / `app_store` |
| Main plist encryption declarations | `ITSAppUsesNonExemptEncryption` and `ITSEncryptionExportComplianceCode` absent |

Build 4 again embeds `App.framework`, `Flutter.framework`, `WebRTC.framework`
and `objective_c.framework`. WebRTC identifies itself as `org.webrtc.WebRTC`,
with both plist version fields still **`1.0`**. The exact SDK release
**`150.7871.04` remains verified source-pin evidence**, not an independently
reported version from the binary's generic plist.

Apple's uploader reported **success without errors at 2026-11-16
00:10:17.561 UTC**, delivery UUID `33b13950-e0ad-4b15-94d8-926ee6e652ff`,
transferring **48,307,985 bytes**. The initial post-upload checkpoint showed
Apple **Processing** and no TestFlight group assignment. The later processing,
compliance and testing observations are recorded below.

Evidence files:

- [Build 4 Mac signing/artifact verification](build-4-signed-verification.json)
- [Downloaded build 4 IPA identity, purpose strings, hash and frameworks](build-4-binary-inspection.json)
- [Build 4 successful upload receipt](build-4-upload-receipt.json)

The build 4 verifier's `submitted_to_store: false` is likewise a pre-upload
checkpoint; the separate upload receipt records the later successful transfer.
Absence of the encryption declaration keys is not evidence of an exemption or
completed compliance review. The subsequent compliance and group readback are
recorded separately below.

The artifact observations do not establish negotiated protocols, exact retained
cipher implementations, unused-code linkage, an ANSSI filing or Apple approval.
Build 2's annex remains historical and is not substituted for either newer
build's separate artifact evidence. No live voice session was started by this
review.

## Final Apple processing and internal testing observation

By the **2026-11-16 00:14:54 UTC** release checkpoint, App Store Connect showed
build **1.0.0 (4)** processing as **Complete**. The coordinating agent saved
the standard-algorithms category (encryption in addition to or instead of
Apple's operating-system encryption), with **distribution in France: No**,
consistent with the user's explicit correction. The build then showed
**Ready to Submit**, with no missing-compliance action for this build.

The build was assigned to the existing **Esha Internal Testers** group.
The group's Builds page showed **1.0.0 (4) — Testing**, alongside the prior
**1.0.0 (2) — Testing**, with **1 tester and 2 builds**. No new testers were
added. No external beta review or App Store review was submitted. The user's
device was still recorded as having build 2 installed before the update;
physical-device testing of build 4 remains unverified.

- [Final Apple compliance and TestFlight availability receipt](build-4-testflight-availability.json)
- [Live internal-group build status proof](esha-build-4-testing.jpg)

These observations establish successful Apple processing and internal tester
availability. They do not establish a French declaration, a negotiated live
voice cipher, public App Store approval or physical-device validation.

## Primary sources

- [Apple: encryption export compliance, including third-party libraries](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations.md)
- [Apple: documentation required by encryption category and France condition](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)
- [WebRTC upstream: SRTP implementation, DTLS negotiation and cipher families](https://webrtc.googlesource.com/src/+/32b64e895c0231fe6891a8f6335d66f1dad4f1f5/pc/g3doc/srtp.md)
- [IETF RFC 8827, section 4.3: DTLS/SRTP and SCTP over DTLS](https://www.rfc-editor.org/rfc/rfc8827.html#section-4.3)
- [Publisher metadata for flutter_webrtc 1.6.3](https://pub.dev/api/packages/flutter_webrtc/versions/1.6.3)
- [Verified publisher source archive](https://pub.dev/api/archives/flutter_webrtc-1.6.3.tar.gz)
- [WebRTC-SDK vendor releases](https://github.com/webrtc-sdk/Specs/releases)
- [Exact corrected app dependency lockfile](https://github.com/digiplayja-design/Ai-wiz-command-center/blob/6ad26c6379e9da6ae9a252ec16a0208471ac380c/apps/esha/pubspec.lock)
- [Exact corrected WebRTC usage](https://github.com/digiplayja-design/Ai-wiz-command-center/blob/6ad26c6379e9da6ae9a252ec16a0208471ac380c/apps/esha/lib/services/voice_audio.dart)
