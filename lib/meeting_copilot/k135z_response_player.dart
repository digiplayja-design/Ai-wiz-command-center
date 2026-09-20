import 'dart:typed_data';

import 'k135z_response_player_stub.dart'
    if (dart.library.html) 'k135z_response_player_web.dart'
    as platform;

abstract interface class K135zResponsePlayer {
  bool get supported;
  Future<void> play(Uint8List bytes);
  void stop();
}

K135zResponsePlayer createResponsePlayer() => platform.createPlayer();
