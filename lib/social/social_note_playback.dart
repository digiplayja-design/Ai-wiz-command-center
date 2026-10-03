import 'package:flutter/foundation.dart';

abstract class SocialNotePlayback extends ChangeNotifier {
  bool playing = false, closed = false;
  Duration position = Duration.zero, duration = Duration.zero;
  void source({Uint8List? bytes, String? url});

  /// Called directly from a tap before resolving a protected audio URL.
  /// Web implementations unlock their persistent audio element with silence.
  Future<void> activate() async {}
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration value);
  Future<void> speed(double value);
  void changed() {
    if (!closed) notifyListeners();
  }
}
