import 'package:flutter/foundation.dart';

abstract class SocialNotePlayback extends ChangeNotifier {
  bool playing = false, closed = false;
  Duration position = Duration.zero, duration = Duration.zero;
  void source({Uint8List? bytes, String? url});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration value);
  Future<void> speed(double value);
  void changed() {
    if (!closed) notifyListeners();
  }
}
