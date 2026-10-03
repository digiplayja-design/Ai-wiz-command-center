import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'social_note_playback.dart';
import 'social_call_tones.dart';

SocialNotePlayback createSocialNotePlayback() => _WebNotePlayback();

class _WebNotePlayback extends SocialNotePlayback {
  final _audio = web.HTMLAudioElement()..preload = 'metadata';
  String? _blob;
  bool _priming = false;
  Duration? _seekTarget;
  static final _silence =
      'data:audio/wav;base64,${base64Encode(socialCallTone(silent: true))}';
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
          if (closed || _priming) return;
          if (_seekTarget != null && _audio.readyState >= 1) {
            _audio.currentTime = _seekTarget!.inMilliseconds / 1000;
            _seekTarget = null;
          }
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
    _priming = false;
    _seekTarget = null;
    _audio.pause();
    _audio.loop = false;
    playing = false;
    position = duration = Duration.zero;
    if (_blob != null) web.URL.revokeObjectURL(_blob!);
    _blob = bytes == null
        ? null
        : web.URL.createObjectURL(
            web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'audio/wav')),
          );
    final source = _blob ?? url;
    if (source == null || source.isEmpty) {
      _audio.removeAttribute('src');
    } else {
      _audio.src = source;
    }
    _audio.load();
  }

  @override
  Future<void> activate() {
    if (closed) return Future.value();
    // Use the same element for the silent gesture and the eventual voice note.
    // This preserves iOS Safari's user activation across the permission lookup.
    _priming = true;
    _audio.pause();
    _audio.src = _silence;
    _audio.loop = true;
    _audio.muted = false;
    _audio.load();
    return _audio.play().toDart.timeout(const Duration(seconds: 5));
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
    if (closed) return;
    _seekTarget = value;
    position = value;
    if (_audio.readyState >= 1) {
      _audio.currentTime = value.inMilliseconds / 1000;
      _seekTarget = null;
    }
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
