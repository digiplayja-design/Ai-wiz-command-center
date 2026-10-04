import 'dart:typed_data';
import 'knova_welcome_player_native.dart'
    if (dart.library.js_interop) 'knova_welcome_player_web.dart'
    as platform;

KnovaWelcomePlayer createKnovaWelcomePlayer() =>
    platform.createKnovaWelcomePlayer();

abstract class KnovaWelcomePlayer {
  Future<bool> activate();
  Future<bool> play(
    Uint8List wav, {
    required double volume,
    required Duration duration,
  });
  void stop();
  void dispose();
}
