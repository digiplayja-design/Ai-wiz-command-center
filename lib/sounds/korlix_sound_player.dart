import 'dart:typed_data';

import 'korlix_sound_player_native.dart'
    if (dart.library.js_interop) 'korlix_sound_player_web.dart'
    as platform;

KorlixSoundPlayer createKorlixSoundPlayer() =>
    platform.createKorlixSoundPlayer();

/// Playback is isolated from microphone/WebRTC tracks and uses its own channels.
abstract class KorlixSoundPlayer {
  bool get ready;

  /// Implementations must request browser activation before their first await.
  Future<bool> activate();
  Future<bool> play(
    Uint8List wav, {
    required double volume,
    required Duration duration,
    required String channel,
    bool loop = false,
  });
  void stop(String channel);
  void stopAll();
  void dispose();
}
