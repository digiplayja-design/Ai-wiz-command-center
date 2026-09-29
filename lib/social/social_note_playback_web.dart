import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'social_note_playback.dart';

SocialNotePlayback createSocialNotePlayback() => _WebNotePlayback();

class _WebNotePlayback extends SocialNotePlayback {
  final _audio = web.HTMLAudioElement()..preload = 'metadata';
  String? _blob;
  _WebNotePlayback() {
    for (final event in [
      'playing',
      'pause',
      'ended',
      'timeupdate',
      'loadedmetadata',
    ]) {
      _audio.addEventListener(
        event,
        ((web.Event _) {
          playing = !_audio.paused && !_audio.ended;
          if (_audio.currentTime.isFinite) {
            position = Duration(
              milliseconds: (_audio.currentTime * 1000).round(),
            );
          }
          if (_audio.duration.isFinite) {
            duration = Duration(milliseconds: (_audio.duration * 1000).round());
          }
          if (_audio.ended) position = Duration.zero;
          changed();
        }).toJS,
      );
    }
  }
  @override
  void source({Uint8List? bytes, String? url}) {
    if (closed) return;
    _audio.pause();
    if (_blob != null) web.URL.revokeObjectURL(_blob!);
    _blob = bytes == null
        ? null
        : web.URL.createObjectURL(
            web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'audio/wav')),
          );
    _audio.src = _blob ?? url ?? '';
    _audio.load();
  }

  // Invoke HTML play synchronously within the user's tap, before network waits.
  @override
  Future<void> play() {
    if (closed) return Future.value();
    _audio.muted = false;
    if (_audio.ended) _audio.currentTime = 0;
    return _audio.play().toDart.timeout(const Duration(seconds: 15));
  }

  @override
  Future<void> pause() async {
    _audio.pause();
  }

  @override
  Future<void> seek(Duration value) async {
    _audio.currentTime = value.inMilliseconds / 1000;
  }

  @override
  Future<void> speed(double value) async {
    _audio.playbackRate = value;
  }

  @override
  void dispose() {
    closed = true;
    _audio.pause();
    _audio.removeAttribute('src');
    _audio.load();
    if (_blob != null) web.URL.revokeObjectURL(_blob!);
    super.dispose();
  }
}
