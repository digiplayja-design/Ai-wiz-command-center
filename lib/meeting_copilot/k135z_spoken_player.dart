import 'dart:typed_data';

import 'k135z_spoken_player_stub.dart'
    if (dart.library.html) 'k135z_spoken_player_web.dart'
    as platform;

abstract interface class K135zSpokenPlayer {
  bool get supported;
  bool get ready;
  Future<void> enable();
  Future<bool> resume();
  void interrupt();
  Future<void> play(Uint8List bytes);
  void stop();
}

K135zSpokenPlayer createSpokenPlayer() => platform.createPlayer();
