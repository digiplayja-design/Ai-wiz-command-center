library passkeys_web;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Korlix local web shim.
///
/// The upstream passkeys_web plugin expects an extra browser JavaScript SDK
/// bundle to be installed in index.html and calls an external JS init()
/// during plugin registration. Korlix AI does not expose passkey login in the
/// current UI, but supabase_flutter pulls passkeys transitively, so Flutter
/// still auto-registers the plugin on web.
///
/// This no-op shim lets the app boot on web while preserving Android/iOS
/// passkeys dependencies for native builds.
class PasskeysWeb {
  static void registerWith([Object? registrar]) {
    // Intentionally no-op. Do not call the upstream JS init().
  }
}
