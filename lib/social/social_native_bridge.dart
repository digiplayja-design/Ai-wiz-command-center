import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'social_client.dart';

/// One handler per Flutter engine, shared by push and floating-chat UI.
/// Account identifiers and user actions cross this bridge, never auth tokens.
abstract final class SocialNativeBridge {
  static const channel = MethodChannel('korlix/social_native');
  static final _events = StreamController<SocialMap>.broadcast();
  static bool _listening = false;

  static bool get mobile => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static void _listen() {
    if (_listening) return;
    _listening = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'event' && call.arguments is Map) {
        _events.add(socialMap(call.arguments));
      }
    });
  }

  static Stream<SocialMap> get events {
    _listen();
    return _events.stream;
  }

  static Future<T?> invoke<T>(String method, [dynamic arguments]) async {
    if (!mobile) return null;
    _listen();
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }
}
