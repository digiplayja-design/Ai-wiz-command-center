# Esha build 2: encryption technical facts

Prepared 15 November 2026 for developer review. This is an engineering evidence note, not a signed declaration, an ANSSI attestation, a certificate, or an export-classification decision. No government filing or Apple encryption-document upload has been made by preparing this note.

## Exact artifact covered

| Field | Value |
| --- | --- |
| App | Esha by Korlix |
| Apple app ID | `6835184869` |
| Bundle identifier | `com.korlixdeveloper.esha` |
| SKU | `ESHA_IOS_001` |
| Marketing version / build | `1.0.0` / `2` |
| Source commit | `fbfde79df731dea5a2e7fc65ee9d4308aebe80dd` |
| Apple build / delivery ID | `50de7424-a350-42fb-9a9d-78eb17021ace` |
| Codemagic job | `6afa1c8190e83b09c4faba0a` |
| IPA SHA-256 | `112d510755024646cdbad23b344e0e0fe2237ce7a065fc5ba3fd1fee54ace43b` |
| Toolchain | Flutter `3.47.9`, Dart `3.13.7` |

The downloaded IPA's hash, bundle identifier, marketing version and build number were independently checked against the existing immutable receipt at `apps/esha/release/ios-upload-build-2-20261115.json`. That receipt records the successful signed upload. This note reuses that completed audit; it does not cover any newer binary.

## Product functions

The inspected app provides a beauty product catalog, private vanity collections and routines, a look illustration, account access, text-based beauty consultations through the Korlix service, and platform membership purchase/restore interfaces. It is not presented as a VPN, secure-messaging product, cryptographic toolkit, file-encryption tool, or information-security product.

Build 2 has no `flutter_webrtc` dependency and contains none of the later native live-voice implementation. A future voice-enabled binary requires its own scope assessment.

## Network confidentiality

The exact build 2 `KorlixApi` constructor creates the default `http.Client()` unless a client is supplied. The production entry point supplies no replacement. The service configuration restricts the app to its Korlix HTTPS API origin and HTTPS account-storage origin.

The implementation chain is:

1. The app locks `http` at `1.6.0`.
2. The package's native default client is `IOClient`, which wraps `dart:io` `HttpClient`.
3. Dart's HTTPS implementation uses `SecureSocket`.
4. Dart `3.13.7`'s native secure-socket implementation invokes SSL handshake/read/write functions and its build configuration links `third_party/boringssl`.
5. The exact downloaded IPA includes `Payload/Runner.app/Frameworks/Flutter.framework/Flutter`. That binary contains the markers `boringssl` and `TLS_AES_128_GCM_SHA256`.

Consequently, the audited HTTPS path includes an embedded standard TLS implementation. It is not established as an Apple `URLSession`-only encryption path. The observed TLS suite identifier is evidence of standard AES-GCM/SHA-256 capability; it is not an exhaustive list of all compiled or negotiable cipher suites.

HTTPS protects the app's account and session requests, private beauty questions and preferences, synchronized vanity data, and purchase-verification exchanges. The app forwards store-provided purchase evidence to its backend rather than offering a user-configurable encryption service.

### Version-specific source inventory

The published toolchain pins are available. The Flutter `3.47.9` framework and engine `DEPS` files both identify the same Dart and BoringSSL revisions:

| Component | Published source revision |
| --- | --- |
| Flutter framework | `c197ca5199e9ee5661e865596c9c07294dfab51c` |
| Flutter engine | `89c39edfdfae2949f6806e4a315c0c08522238b7` |
| Dart | `416e33b0ffaef062a60ec966bb8c82ed2b83f128` |
| BoringSSL | `c7eb007fd10627f1abb41a3e368b85e24cd20af9` |

These are the pinned toolchain's source/build definitions, not a newly extracted build fingerprint. The engine's BoringSSL target includes its crypto, SSL and PKI source lists and defines `OPENSSL_SMALL` and `OPENSSL_STATIC_ARMCAP`. This establishes the implementation selected by that toolchain; it does not establish that every library primitive is reachable from Esha or negotiated with its servers.

**Source-default protocol configuration:** pinned Dart creates a `TLS_method()` context, sets the minimum to TLS `1.2`, and passes the cipher rule `HIGH:MEDIUM`. Pinned BoringSSL's default maximum is TLS `1.3`. No application override was found in the completed build 2 source audit. This supports a source-derived default range of TLS `1.2`–`1.3`; no new TLS handshake or negotiated-protocol measurement was performed for this note. DTLS capability in the upstream library is not evidence that build 2 uses DTLS.

| Algorithm / purpose | Mode and size established by pinned source | Configuration and evidence boundary |
| --- | --- | --- |
| AES record confidentiality | GCM; 128- or 256-bit symmetric keys | TLS 1.2 and 1.3 suite definitions. The earlier IPA audit independently observed the `TLS_AES_128_GCM_SHA256` marker; no particular live negotiation is claimed. |
| AES record confidentiality | CBC; 128- or 256-bit symmetric keys, with SHA-1 record MAC in the relevant legacy suites | Source-defined TLS 1.2 candidates. The distinct ECDHE AES-128-CBC/SHA-256 suites are marked deprecated and excluded by the normal `HIGH` alias. |
| ChaCha20 record confidentiality and Poly1305 authentication | ChaCha20-Poly1305 AEAD; 256-bit key | Source-defined TLS 1.2 and 1.3 suites. This is a source-default library capability, not an observation that an Esha connection selected it. |
| TLS integrity / key-schedule digests | SHA-256 or SHA-384; 256- or 384-bit digest output. SHA-1 has 160-bit output in the legacy CBC record-MAC definitions. | Digest-output size is not a symmetric-encryption key length. Cipher and handshake-digest mappings are in `ssl_cipher.cc`. |
| Elliptic-curve key agreement | X25519 uses 32-byte encoded keys; P-256 and P-384 use the corresponding 256- and 384-bit curves | All three appear in the pinned default supported-group list. Encoded-key/curve size is not a claim of equivalent symmetric security strength. |
| Hybrid key agreement | `X25519MLKEM768`: X25519 plus ML-KEM-768. ML-KEM-768 encoded public key is 1,184 bytes, ciphertext 1,088 bytes, and shared secret 32 bytes. | Also appears in the pinned default group list. `768` is a parameter-set name, not a 768-bit symmetric key. The pinned ML-KEM header identifies the mechanism with NIST FIPS 203. Actual use by an Esha connection was not measured. |
| RSA / ECDSA authentication and TLS 1.2 RSA key exchange | RSA and ECDSA occur in the cipher definitions; the signature implementation includes RSA PKCS#1/PSS and ECDSA with standard digest variants | The server certificate and handshake determine the key/signature actually used. No fixed RSA modulus length is established by Esha's source. |

Additional source capabilities must remain distinct from the default connection path. The pinned library defines 3DES-CBC (168 algorithm bits, 112 effective strength bits), but marks it deprecated and excludes it from `HIGH`. It also implements P-521 and standalone ML-KEM-1024 without listing them in the default supported groups. The signature catalog includes Ed25519 and ML-DSA variants; this inspection does not establish that Esha advertises or negotiates those signatures. None of these entries should be presented as observed Esha traffic.

This closes the previously unknown BoringSSL-version/configuration gap and supplies source-grounded algorithm sizes. It is not a binary-wide reachability audit or a record of actual server certificate sizes, selected suites, or negotiated key groups. Those narrower facts remain unmeasured and should not be invented in a signed dossier.

## Local storage

The app locks `flutter_secure_storage` at `10.0.0` and its Darwin implementation at `0.2.0`. `SecureSessionStore` uses that plugin for session material. The inspected Darwin implementation uses Apple's Keychain `SecItem` APIs. This is separate from the embedded Dart HTTPS implementation.

Other local preferences and vanity drafts use `shared_preferences`; the app does not implement an additional custom encryption layer for those values. The lockfile also contains `crypto` `3.0.8`, whose documented functionality consists of cryptographic digests/HMAC, and `uuid` `4.5.3`. A lockfile entry alone does not prove that every package function survives release compilation or is used by Esha.

## Application-level findings and limits

The audit covered all nine Dart source files and both Swift entry-point files at the exact build 2 commit, plus the dependency manifest/lockfile and the matching IPA. No application-defined proprietary cipher, custom cryptographic protocol, `HttpOverrides`, or replacement native HTTP client was found. A committed `Podfile.lock` was not available at that source commit; the note does not substitute a newer generated lockfile for build 2 evidence.

The IPA omits `ITSAppUsesNonExemptEncryption`. That omission explains why an Apple questionnaire can be required, but does not itself determine the app's cryptographic implementation or exemption status.

## Information still needed for a complete declaration dossier

These items have not been established by this engineering note:

- The registered legal identity/address and registration evidence supporting the project-supplied name `Korlix LLC`, plus the authorized declarant and designated administrative/technical contacts.
- The product's commercial reference and actual market-introduction date, as required by the applicable form.
- Any dossier requirement beyond the pinned-source inventory above: actual negotiated protocols/suites, peer certificate key lengths, or a claim that all source-defined algorithms remain reachable in this particular linked IPA. These were not measured or asserted.
- Any existing upstream ANSSI declaration number, attestation, covered product/version, distribution conditions, or evidence that its scope covers Esha's integration.
- Any ANSSI-confirmed exemption, accepted declaration, or Apple-approved encryption compliance code.
- The declarant's review and signature of the government's accuracy-attestation template, if a filing is pursued.

## Draft filing worksheet

Preparation only. The entries below combine verified product identifiers with business details supplied in the project context. They do not certify legal identity, signing authority, current store availability or government acceptance.

| Filing field | Draft value / owner action |
| --- | --- |
| Beneficiary / manufacturer name | `Korlix LLC` — project-supplied name; confirm the exact registered spelling, legal form and jurisdiction against registration evidence. |
| Registered office / legal address | **Owner to supply.** |
| Registration number, issuing authority and recent registry document | **Owner to supply.** No equivalent foreign registration document has been verified in this note. |
| Authorized declarant and capacity to sign | **Owner to identify and confirm.** The existing Apple review contact does not establish ANSSI signing authority. |
| Administrative contact | Named responsible person **to be designated**; available business contact channel: `support@korlixdeveloper.com`, `+16148942317`. |
| Technical contact | Named responsible person **to be designated**; the same business contact channel is available but no appointment is presumed. |
| Distribution brand / product name | Korlix / Esha by Korlix. |
| Software / version | iOS application; `1.0.0`, build `2`; bundle `com.korlixdeveloper.esha`. |
| Existing identifiers | Apple app ID `6835184869`; SKU `ESHA_IOS_001`. Confirm whether the SKU should also be used as the form's commercial reference. |
| Primary function | Beauty and personal-vanity application with catalog, private collections/routines, account access and text consultation interfaces. |
| Cryptographic functions | Confidentiality, server authentication and integrity of app-to-service HTTPS exchanges; Apple Keychain protection for session material. See the source inventory above for implementation details. |
| Planned distribution | Apple App Store, including France, as expressly approved by the owner. Free app download; membership purchases remain separate. This records intent, not completion of distribution. |
| Actual market-introduction date | **Owner to supply.** The IPA upload date is not proof of a public market-introduction date. |
| Declaration / signature date | **Unknown; enter only when actually signed/filed by the authorized declarant.** |
| Upstream or existing approval reference | **None established.** Require the actual document and demonstrated product/version/scope match before relying on one. |
| Commercial / technical attachments | This engineering note can support a technical brochure. A complete commercial brochure and the official accuracy-attestation template still require owner review; this note is not an approval form or a signed attachment. |

## Technical evidence references

- [Build 2 application manifest](https://github.com/digiplayja-design/Ai-wiz-command-center/blob/fbfde79df731dea5a2e7fc65ee9d4308aebe80dd/apps/esha/pubspec.yaml)
- [Build 2 dependency lockfile](https://github.com/digiplayja-design/Ai-wiz-command-center/blob/fbfde79df731dea5a2e7fc65ee9d4308aebe80dd/apps/esha/pubspec.lock)
- [Build 2 API and secure-storage implementation](https://github.com/digiplayja-design/Ai-wiz-command-center/blob/fbfde79df731dea5a2e7fc65ee9d4308aebe80dd/apps/esha/lib/services/korlix_api.dart)
- [Build 2 production entry point](https://github.com/digiplayja-design/Ai-wiz-command-center/blob/fbfde79df731dea5a2e7fc65ee9d4308aebe80dd/apps/esha/lib/main.dart)
- [HTTP IOClient documentation](https://pub.dev/documentation/http/1.6.0/io_client/IOClient-class.html)
- [Dart 3.13.7 secure-socket implementation](https://github.com/dart-lang/sdk/blob/3.13.7/runtime/bin/secure_socket_filter.cc)
- [Dart 3.13.7 native build configuration](https://github.com/dart-lang/sdk/blob/3.13.7/runtime/bin/BUILD.gn)
- [Flutter 3.47.9 framework dependency pins](https://github.com/flutter/flutter/blob/c197ca5199e9ee5661e865596c9c07294dfab51c/DEPS)
- [Pinned engine dependency pins](https://github.com/flutter/flutter/blob/89c39edfdfae2949f6806e4a315c0c08522238b7/DEPS)
- [Pinned engine BoringSSL build target](https://github.com/flutter/flutter/blob/89c39edfdfae2949f6806e4a315c0c08522238b7/engine/src/flutter/third_party/boringssl/BUILD.gn)
- [Pinned Dart TLS context defaults](https://github.com/dart-lang/sdk/blob/416e33b0ffaef062a60ec966bb8c82ed2b83f128/runtime/bin/security_context.cc)
- [Pinned BoringSSL protocol bounds](https://github.com/google/boringssl/blob/c7eb007fd10627f1abb41a3e368b85e24cd20af9/ssl/ssl_versions.cc)
- [Pinned BoringSSL cipher families, key sizes and deprecations](https://github.com/google/boringssl/blob/c7eb007fd10627f1abb41a3e368b85e24cd20af9/ssl/ssl_cipher.cc)
- [Pinned BoringSSL supported and default key-exchange groups](https://github.com/google/boringssl/blob/c7eb007fd10627f1abb41a3e368b85e24cd20af9/ssl/ssl_key_share.cc)
- [Pinned ML-KEM parameter sizes](https://github.com/google/boringssl/blob/c7eb007fd10627f1abb41a3e368b85e24cd20af9/include/openssl/mlkem.h)
- [Pinned BoringSSL signature implementation](https://github.com/google/boringssl/blob/c7eb007fd10627f1abb41a3e368b85e24cd20af9/ssl/ssl_privkey.cc)
- [BoringSSL upstream project](https://boringssl.googlesource.com/boringssl/)

## Official dossier entry points for the developer

These links identify the official process; this note does not complete or certify any of its forms.

- [ANSSI declaration procedure](https://demarche.numerique.gouv.fr/commencer/declaration-relative-a-un-moyen-de-cryptologie)
- [ANSSI declaration guide dated 31 March 2026](https://cyber.gouv.fr/documents/823/260331_Notice_V3.pdf)
- [Apple encryption-document requirements](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)
- [Apple document-upload procedure](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/)
