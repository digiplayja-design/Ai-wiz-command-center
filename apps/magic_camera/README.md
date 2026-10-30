# Korlix Magic Camera

Standalone Android, iOS and web companion using the shared Korlix account. The camera flow and gallery live in `packages/korlix_magic_core`; the main hub opens that same module.

Use Flutter 3.47.7 / Dart 3.13.5. From this directory:

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter run --dart-define=KORLIX_BACKEND_URL=https://YOUR-REVIEW-BACKEND
```

The default URL is the existing Korlix backend. Magic Camera sign-in and generation require the paired backend implementation and migration to be deployed there. A successful build alone does not enable those server routes.

```sh
flutter build apk --debug --no-pub
flutter build ios --simulator --debug --no-pub
flutter build web --release --no-pub
```

The native application ID is `com.korlixdeveloper.magiccamera`. Android requires API 24 or later. Physical camera, speech permissions, save/share, app backgrounding and signed store transactions require device testing. Web camera use requires HTTPS or localhost.

Two successful free photos belong to the Korlix account. Store subscriptions are verified by the backend and remain unavailable until the dedicated app records, products and provider flags are configured. Existing Pro/Ultra access is shared with the hub.

See `../../MAGIC_CAMERA_RELEASE.md` and the paired backend PR for release requirements, quota behavior, privacy, configuration, and known feature boundaries. CI publishes Android review builds, a web build and an iOS simulator archive; none is a signed store release.
