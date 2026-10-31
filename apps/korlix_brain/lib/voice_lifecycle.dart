import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps a user-started Android conversation visible while the screen is locked.
class VoiceLifecycle {
  static const _channel = MethodChannel('korlix.brain/voice-lifecycle');
  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static void onStop(Future<void> Function() stop) {
    if (_android) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'stopRequested') await stop();
      });
    }
  }

  static Future<void> start() async {
    if (_android) await _channel.invokeMethod<void>('start');
  }

  static Future<void> stop() async {
    if (_android) await _channel.invokeMethod<void>('stop');
  }
}
