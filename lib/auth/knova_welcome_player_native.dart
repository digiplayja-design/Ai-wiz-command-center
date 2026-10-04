import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'knova_welcome_player.dart';

KnovaWelcomePlayer createKnovaWelcomePlayer() => _WelcomeNativePlayer();

class _WelcomeNativePlayer implements KnovaWelcomePlayer {
  final _player = AudioPlayer();
  int _revision = 0;
  bool _disposed = false;
  Future<void> _pending = Future<void>.value();
  @override
  Future<bool> activate() => Future.value(!_disposed);
  @override
  Future<bool> play(
    Uint8List wav, {
    required double volume,
    required Duration duration,
  }) {
    final revision = ++_revision;
    final result = Completer<bool>();
    _pending = _pending.then((_) async {
      if (_disposed || revision != _revision) {
        result.complete(false);
        return;
      }
      try {
        await _player.play(
          BytesSource(wav, mimeType: 'audio/wav'),
          volume: volume,
        );
        if (_disposed || revision != _revision) await _player.stop();
        result.complete(!_disposed && revision == _revision);
      } catch (_) {
        result.complete(false);
      }
    });
    return result.future;
  }

  @override
  void stop() {
    _revision++;
    _pending = _pending.then((_) async {
      try {
        await _player.stop();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    _pending = _pending.then((_) async {
      try {
        await _player.dispose();
      } catch (_) {}
    });
  }
}
