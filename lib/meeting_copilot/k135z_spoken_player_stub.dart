import 'dart:typed_data';

import 'k135z_spoken_player.dart';

K135zSpokenPlayer createPlayer() => _Unsupported();

class _Unsupported implements K135zSpokenPlayer {
  bool get supported => false;
  bool get ready => false;
  Future<void> enable() =>
      Future.error(StateError('Open Copilot in your browser.'));
  Future<void> play(Uint8List bytes) => enable();
  Future<bool> resume() async => false;
  void interrupt() {}
  void stop() {}
}
