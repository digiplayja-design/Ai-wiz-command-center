import 'package:web/web.dart' as web;

/// The orbit's video yields native pointer input to Flutter's swipe and sound
/// controls. Asset URLs are stable even before the platform view is attached.
void Function() allowCharacterVideoGestures(String assetPath) {
  final style = web.HTMLStyleElement()
    ..textContent =
        'video[src\$="$assetPath"] { pointer-events: none !important; }';
  web.document.head?.appendChild(style);
  return () => style.remove();
}
