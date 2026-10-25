import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'social_note_playback.dart';

SocialNotePlayback createSocialNotePlayback() => _NativeNotePlayback();

class _NativeNotePlayback extends SocialNotePlayback {
  AudioPlayer? _player;
  Source? _source;
  bool _prepared = false;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  double _speed = 1;
  Duration? _seekTarget;
  int _revision = 0;
  Future<void> _sourceChange = Future.value();
  @override
  void source({Uint8List? bytes, String? url}) {
    if (closed) return;
    _revision++;
    // Clearing on logout/background may never be followed by play(), so consume
    // cleanup failures here instead of leaving an unhandled platform future.
    _sourceChange = (_player?.stop() ?? Future<void>.value()).catchError(
      (Object _) {},
    );
    _source = bytes != null
        ? BytesSource(bytes, mimeType: 'audio/wav')
        : url == null || url.isEmpty
        ? null
        : UrlSource(url, mimeType: 'audio/wav');
    playing = false;
    position = duration = Duration.zero;
    _seekTarget = null;
    _prepared = false;
  }

  @override
  Future<void> play() async {
    if (closed) return;
    if (_source == null) throw StateError('No audio source');
    final revision = _revision;
    bool current() => !closed && revision == _revision;
    await _sourceChange;
    if (!current()) return;
    if (_player == null) {
      final p = AudioPlayer();
      _player = p;
      _subscriptions.add(
        p.onPositionChanged.listen((v) {
          position = v;
          changed();
        }),
      );
      _subscriptions.add(
        p.onDurationChanged.listen((v) {
          duration = v;
          changed();
        }),
      );
      _subscriptions.add(
        p.onPlayerStateChanged.listen((v) {
          playing = v == PlayerState.playing;
          changed();
        }),
      );
      _subscriptions.add(
        p.onPlayerComplete.listen((_) {
          playing = false;
          position = Duration.zero;
          changed();
        }),
      );
      await p.setReleaseMode(ReleaseMode.stop);
    }
    if (!current()) return;
    if (!_prepared) {
      await _player!.setSource(_source!);
      if (!current()) return;
      _prepared = true;
    }
    if (_seekTarget != null) {
      await _player!.seek(_seekTarget!);
      if (!current()) return;
      _seekTarget = null;
    }
    if (!current()) return;
    await _player!.setPlaybackRate(_speed);
    if (!current()) return;
    await _player!.setVolume(1);
    if (!current()) return;
    await _player!.resume();
  }

  @override
  Future<void> pause() async {
    _revision++;
    try {
      await _player?.pause();
    } catch (_) {
      // Lifecycle cleanup can race the native player's disposal.
    }
  }

  @override
  Future<void> seek(Duration value) async {
    if (closed) return;
    position = value;
    if (_prepared) {
      await _player?.seek(value);
    } else {
      _seekTarget = value;
    }
  }

  @override
  Future<void> speed(double value) async {
    _speed = value;
    await _player?.setPlaybackRate(value);
  }

  @override
  void dispose() {
    closed = true;
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    unawaited(_player?.dispose());
    super.dispose();
  }
}
