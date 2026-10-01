import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'pod_media.dart';
import 'pod_media_recorder.dart';

PodMedia createPlatformPodMedia() => PodMediaController(
  playback: WebPodPlayback(),
  recorder: DevicePodRecorder(),
);

/// A single retained HTML audio sink is unlocked by Listen / Resume. Creating
/// another element for each server response loses Safari's gesture permission.
/// No constructor starts sound, and activation plays only a short silent WAV.
class WebPodPlayback implements PodPlaybackBackend {
  WebPodPlayback() {
    _audio
      ..autoplay = false
      ..preload = 'auto'
      ..setAttribute('playsinline', '')
      ..style.display = 'none';
    web.document.body?.appendChild(_audio);
  }

  final _audio = web.HTMLAudioElement();
  static final _silence =
      'data:audio/wav;base64,${base64Encode(podPcmToWav(Uint8List(480)))}';
  Completer<void>? _ended;
  String? _url;
  JSFunction? _endedListener, _errorListener;
  int _revision = 0;
  bool _closed = false;

  @override
  Future<void> activate() {
    if (_closed) return Future<void>.value();
    final revision = _revision;
    if (_ended == null) _audio.src = _silence;
    _audio.muted = false;
    // This invocation must happen synchronously inside the actual user tap.
    return _audio
        .play()
        .toDart
        .timeout(const Duration(seconds: 5))
        .then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {
            if (_closed || revision != _revision) return;
            throw const PodMediaException(
              'Tap Resume sound to allow audio in your browser.',
              blocked: true,
            );
          },
        );
  }

  @override
  Future<void> play(Uint8List wav) {
    if (_closed) return Future<void>.value();
    _reset();
    final revision = _revision;
    final ended = _ended = Completer<void>();
    final url = _url = web.URL.createObjectURL(
      web.Blob([wav.toJS].toJS, web.BlobPropertyBag(type: 'audio/wav')),
    );
    _endedListener = ((web.Event _) {
      if (_closed || revision != _revision || !_audio.ended) return;
      _reset();
    }).toJS;
    _errorListener = ((web.Event _) {
      if (_closed || revision != _revision) return;
      _fail(
        const PodMediaException(
          'This audio could not be played. Try Resume sound.',
        ),
      );
    }).toJS;
    _audio.addEventListener('ended', _endedListener);
    _audio.addEventListener('error', _errorListener);
    _audio.src = url;
    _audio.muted = false;
    // The controller listens for completion, never a guessed audio duration.
    unawaited(
      _audio
          .play()
          .toDart
          .timeout(const Duration(seconds: 5))
          .then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {
              if (_closed || revision != _revision) return;
              _fail(
                _audio.error == null
                    ? const PodMediaException(
                        'Tap Resume sound to allow audio in your browser.',
                        blocked: true,
                      )
                    : const PodMediaException(
                        'This audio could not be played. Try Resume sound.',
                      ),
              );
            },
          ),
    );
    return ended.future;
  }

  void _fail(PodMediaException error) {
    final ended = _ended;
    _ended = null;
    _reset();
    if (ended?.isCompleted == false) ended!.completeError(error);
  }

  void _reset() {
    ++_revision;
    if (_endedListener != null) {
      _audio.removeEventListener('ended', _endedListener);
    }
    if (_errorListener != null) {
      _audio.removeEventListener('error', _errorListener);
    }
    _endedListener = _errorListener = null;
    _audio.pause();
    _audio.removeAttribute('src');
    // load() cancels pending fetch/decode and releases the previous resource.
    _audio.load();
    if (_url != null) web.URL.revokeObjectURL(_url!);
    _url = null;
    if (_ended?.isCompleted == false) _ended!.complete();
    _ended = null;
  }

  @override
  Future<void> stop() {
    _reset();
    return Future<void>.value();
  }

  @override
  Future<void> dispose() {
    if (_closed) return Future<void>.value();
    _closed = true;
    _reset();
    _audio.remove();
    return Future<void>.value();
  }
}
