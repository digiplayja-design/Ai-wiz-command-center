# Native store screenshot capture

This isolated target renders the existing build-14 `BrainApp`, `BrainWorkspace`,
native WKWebView and bundled assets in iPhone 16 Pro and 13-inch iPad simulators.
It uses a fictional empty account and an in-process, read-only localhost fixture.
No real credentials, personal information or production backend are used.

The capture target is never uploaded to TestFlight or either store. The release
branch, normal app entry point, authentication, application screens and assets
are unchanged. The workflow runs only on the dedicated capture branch or manual
dispatch and uploads PNGs plus provenance, not an installable app.

Inspect both images before choosing a store screenshot. These captures document
the production UI layout; they are not evidence of login, voice, store products,
receipt verification, subscription renewals, restores or AI GAS purchases.

Apple still needs valid reviewer credentials and a working reviewed backend.
Real device purchase verification and purchase-review screenshots remain separate.

## Run

On a Mac with Flutter 3.47.9, Xcode and the two simulators available:

```sh
flutter pub get --enforce-lockfile
flutter build ios --simulator --debug --no-pub --target tools/store_capture/main.dart
python3 tools/store_capture/capture.py
```
