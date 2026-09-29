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
  @override
  void source({Uint8List? bytes, String? url}) {
    _source = bytes != null
        ? BytesSource(bytes, mimeType: 'audio/wav')
        : UrlSource(url ?? '', mimeType: 'audio/wav');
    _prepared = false;
  }

  @override
  Future<void> play() async {
    if (closed) return;
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
    if (closed) return;
    if (!_prepared) {
      await _player!.setSource(_source!);
      _prepared = true;
    }
    await _player!.setPlaybackRate(_speed);
    await _player!.setVolume(1);
    await _player!.resume();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Future<void> seek(Duration value) async {
    await _player?.seek(value);
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
