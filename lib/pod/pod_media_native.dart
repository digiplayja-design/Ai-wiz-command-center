import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'pod_media.dart';
import 'pod_media_recorder.dart';

PodMedia createPlatformPodMedia() => PodMediaController(
  playback: NativePodPlayback(),
  recorder: DevicePodRecorder(),
);

/// Every plugin command is ordered. A stop arriving during source preparation
/// runs immediately after that preparation, before any later play operation.
class NativePodPlayback implements PodPlaybackBackend {
  final _player = AudioPlayer();
  Future<void> _commands = Future<void>.value();
  Completer<void>? _ended;
  StreamSubscription<void>? _completion;
  int _revision = 0;
  bool _closed = false;

  Future<void> _command(Future<void> Function() action) {
    final result = _commands.then((_) => action());
    _commands = result.catchError((_) {});
    return result;
  }

  void _finish() {
    if (_ended?.isCompleted == false) _ended!.complete();
    _ended = null;
  }

  @override
  Future<void> activate() async {}

  @override
  Future<void> play(Uint8List wav) {
    if (_closed) return Future<void>.value();
    final revision = ++_revision;
    _finish();
    final ended = _ended = Completer<void>();
    // Attach an error handler before scheduling plugin work so rejected starts
    // remain handled even if the caller stops/disposes before completion.
    final result = ended.future;
    unawaited(
      _command(() async {
        try {
          await _completion?.cancel();
          _completion = null;
          await _player.stop();
          if (_closed || revision != _revision) return;
          _completion = _player.onPlayerComplete.listen((_) {
            if (!_closed && revision == _revision) _finish();
          });
          await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
          if (_closed || revision != _revision) await _player.stop();
        } catch (_) {
          if (!_closed && revision == _revision && !ended.isCompleted) {
            ended.completeError(
              const PodMediaException(
                'Audio could not play. Check your device sound output and try again.',
              ),
            );
            _ended = null;
          }
        }
      }),
    );
    return result;
  }

  @override
  Future<void> stop() {
    ++_revision;
    _finish();
    return _command(() async {
      await _completion?.cancel();
      _completion = null;
      if (!_closed) await _player.stop();
    });
  }

  @override
  Future<void> dispose() {
    if (_closed) return _commands;
    _closed = true;
    ++_revision;
    _finish();
    return _command(() async {
      await _completion?.cancel();
      _completion = null;
      await _player.dispose();
    });
  }
}
