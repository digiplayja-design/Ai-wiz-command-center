import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

abstract class MusicPlayback extends ChangeNotifier {
  String? activeId, error;
  bool playing = false, busy = false;
  Duration position = Duration.zero, duration = Duration.zero;
  Future<void> toggle(String id, String url);
  Future<void> seek(Duration value);
  Future<void> stop();
}

class DeviceMusicPlayback extends MusicPlayback {
  DeviceMusicPlayback() : _player = AudioPlayer() {
    _subscriptions = [
      _player.onPositionChanged.listen((v) {
        position = v;
        _changed();
      }),
      _player.onDurationChanged.listen((v) {
        duration = v;
        _changed();
      }),
      _player.onPlayerStateChanged.listen((v) {
        playing = v == PlayerState.playing;
        _changed();
      }),
      _player.onPlayerComplete.listen((_) {
        activeId = null;
        duration = Duration.zero;
        playing = false;
        position = Duration.zero;
        _changed();
      }),
    ];
  }
  final AudioPlayer _player;
  late final List<StreamSubscription> _subscriptions;
  bool _closed = false;
  int _revision = 0;
  Future<void> _tail = Future.value();
  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<void> _queue(Future<void> Function() fn) {
    final next = _tail.catchError((_) {}).then((_) => fn());
    _tail = next.catchError((_) {});
    return next;
  }

  @override
  Future<void> toggle(String id, String url) async {
    if (_closed || busy) return;
    final revision = _revision;
    busy = true;
    error = null;
    _changed();
    await _queue(() async {
      if (_closed || revision != _revision) return;
      try {
        if (activeId == id) {
          if (playing) {
            await _player.pause();
          } else {
            await _player.resume();
          }
        } else {
          await _player.stop();
          if (_closed || revision != _revision) return;
          activeId = id;
          position = Duration.zero;
          duration = Duration.zero;
          await _player.play(UrlSource(url));
        }
      } catch (_) {
        error = 'Audio could not play. Try again or use Open audio.';
      }
    });
    if (!_closed) {
      busy = false;
      _changed();
    }
  }

  @override
  Future<void> seek(Duration value) async {
    if (_closed || activeId == null || duration == Duration.zero) return;
    await _queue(() async {
      if (_closed) return;
      try {
        await _player.seek(value);
      } catch (_) {
        error = 'Could not seek in this audio.';
        _changed();
      }
    });
  }

  @override
  Future<void> stop() async {
    _revision++;
    activeId = null;
    playing = false;
    busy = false;
    position = Duration.zero;
    duration = Duration.zero;
    _changed();
    await _queue(() async {
      try {
        await _player.stop();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _revision++;
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(
      _queue(() async {
        try {
          await _player.stop();
          await _player.dispose();
        } catch (_) {}
      }),
    );
    super.dispose();
  }
}
