# KORLIX POS practice app

Standalone Flutter shell for the shared retail/restaurant POS practice workspace.

```sh
flutter pub get
flutter run -d chrome
flutter build web --release --no-web-resources-cdn
```

Shared code and tests live in `../../packages/korlix_pos_core`. Android/iOS scaffolds are not signed or store-published. The proposed Android application ID is `com.korlixdeveloper.pos`; production signing has deliberately not been configured.

The app is a local sample-data practice workspace, with no KORLIX credential entry and no live payments or cloud records. The embedded hub route is opt-in with `--dart-define=KORLIX_POS_PRACTICE=true`. See `../../docs/KORLIX_POS_2026-10-24.md` for integration status and production requirements.
