import 'dart:typed_data';

import 'k135z_response_player.dart';

K135zResponsePlayer createPlayer() => _Unsupported();

class _Unsupported implements K135zResponsePlayer {
  @override
  bool get supported => false;
  @override
  Future<void> play(Uint8List bytes) =>
      Future.error(StateError('Open Copilot in Chrome.'));
  @override
  void stop() {}
}
