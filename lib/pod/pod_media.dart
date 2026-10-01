import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'pod_media_native.dart'
    if (dart.library.js_interop) 'pod_media_web.dart'
    as platform;

PodMedia createPodMedia() => platform.createPlatformPodMedia();

class PodMediaException implements Exception {
  const PodMediaException(this.message, {this.blocked = false});
  final String message;
  final bool blocked;
  @override
  String toString() => message;
}

/// A screen-owned, foreground-only audio session.
///
/// Call [activate] directly in the Listen / Resume tap, before network awaits.
/// It unlocks the existing browser audio element without opening a microphone.
/// The screen must call [stop] and [cancelRecording] on background, navigation,
/// sign-out and deadline expiry. Returning to the screen never resumes audio.
/// Browser permission and physical iPad output routing still need device tests.
abstract class PodMedia extends ChangeNotifier {
  bool get blocked;
  bool get playing;
  bool get recording;
  bool get recordingAvailable;
  Duration get elapsed;
  String? get error;

  Future<void> activate();

  /// Completes at the end of this turn, or when explicitly stopped. A failure
  /// throws [PodMediaException]. Keep the turn bytes for an explicit retry;
  /// blocked sound must not cause another paid generation request.
  Future<void> play(Uint8List wav);
  Future<void> stop();
  Future<void> startRecording();

  /// Also returns the retained clip after the automatic 30-second stop.
  Future<Uint8List> stopRecording();
  Future<void> cancelRecording();
}

/// Injectable device boundaries. Neither constructor may request permissions.
abstract class PodPlaybackBackend {
  Future<void> activate();
  Future<void> play(Uint8List wav);
  Future<void> stop();
  Future<void> dispose();
}

abstract class PodRecorderBackend {
  /// Raw little-endian 24kHz mono PCM16, including the final chunk before done.
  Future<Stream<Uint8List>> start();

  /// Synchronously revoke a pending start before awaiting serialized cleanup.
  /// A permission prompt itself cannot be dismissed programmatically.
  void cancelPendingStart() {}
  Future<void> stop();
  Future<void> cancel();
  Future<void> dispose();
}

/// Shared state and limits; production devices and deterministic test fakes use
/// the same controller. Recorder operations are serialized so a late permission
/// result cannot restart a microphone after cancellation or disposal.
class PodMediaController extends PodMedia {
  PodMediaController({required this.playback, required this.recorder});
  final PodPlaybackBackend playback;
  final PodRecorderBackend recorder;
  static const maxRecordingDuration = Duration(seconds: 30);
  static const maxPcmBytes = 24000 * 2 * 30;
  static const maxWavBytes = maxPcmBytes + 44;

  @override
  bool blocked = false;
  @override
  bool playing = false;
  @override
  bool recording = false;
  @override
  String? error;
  @override
  bool get recordingAvailable => _clip != null;
  @override
  Duration get elapsed => _elapsed;

  bool _closed = false, _starting = false;
  int _playRevision = 0, _captureRevision = 0, _activationRevision = 0;
  Duration _elapsed = Duration.zero;
  final _watch = Stopwatch();
  final _bytes = BytesBuilder();
  Uint8List? _clip;
  Timer? _timer, _limitTimer;
  StreamSubscription<Uint8List>? _stream;
  Completer<void>? _streamEnded, _playCancelled;
  Future<void> _captureTail = Future<void>.value();
  Future<void>? _startFuture;
  Future<Uint8List>? _stopFuture;

  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<T> _captureOperation<T>(Future<T> Function() operation) {
    final result = _captureTail.then((_) => operation());
    _captureTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  @override
  Future<void> activate() {
    if (_closed || recording || _starting) return Future<void>.value();
    final revision = ++_activationRevision;
    // Deliberately no await before this call: Safari requires the tap's gesture.
    try {
      return _finishActivation(playback.activate(), revision, _playRevision);
    } catch (e) {
      return _finishActivation(Future<void>.error(e), revision, _playRevision);
    }
  }

  Future<void> _finishActivation(
    Future<void> activation,
    int revision,
    int playRevision,
  ) async {
    try {
      await activation;
      if (_closed ||
          revision != _activationRevision ||
          playRevision != _playRevision) {
        return;
      }
      blocked = false;
      error = null;
    } catch (e) {
      if (_closed ||
          revision != _activationRevision ||
          playRevision != _playRevision) {
        return;
      }
      blocked = e is PodMediaException && e.blocked;
      error = e is PodMediaException
          ? e.message
          : 'Sound could not start. Tap Resume sound to try again.';
      // Activation reports through state. The screen can show its resume action
      // without an unhandled Future from the synchronous gesture callback.
    }
    _changed();
  }

  @override
  Future<void> play(Uint8List wav) async {
    if (_closed) return;
    if (recording || _starting) {
      throw const PodMediaException('Finish recording before resuming sound.');
    }
    final revision = ++_playRevision;
    _playCancelled?.complete();
    final cancelled = _playCancelled = Completer<void>();
    playing = true;
    blocked = false;
    error = null;
    _changed();
    try {
      await Future.any<void>([
        playback.play(wav).timeout(const Duration(seconds: 45)),
        cancelled.future,
      ]);
    } catch (e) {
      if (_closed || revision != _playRevision) return;
      final failure = e is PodMediaException
          ? e
          : const PodMediaException(
              'Audio could not finish. Tap Resume sound to try again.',
            );
      blocked = failure.blocked;
      error = failure.message;
      unawaited(playback.stop().catchError((_) {}));
      throw failure;
    } finally {
      if (!_closed && revision == _playRevision) {
        _playCancelled = null;
        playing = false;
        _changed();
      }
    }
  }

  @override
  Future<void> stop() {
    ++_playRevision;
    ++_activationRevision;
    _playCancelled?.complete();
    _playCancelled = null;
    playing = false;
    blocked = false;
    error = null;
    _changed();
    return playback.stop().catchError((_) {});
  }

  @override
  Future<void> startRecording() {
    if (_closed) return Future<void>.value();
    if (_starting) return _startFuture!;
    if (recording) return Future<void>.value();
    final revision = ++_captureRevision;
    _starting = true;
    _clip = null;
    error = null;
    _elapsed = Duration.zero;
    _bytes.clear();
    _stopFuture = null;
    final stopped = stop();
    _startFuture = _captureOperation(() async {
      try {
        await stopped;
        if (_closed || revision != _captureRevision) return;
        final stream = await recorder.start();
        if (_closed || revision != _captureRevision) {
          await recorder.cancel();
          return;
        }
        _streamEnded = Completer<void>();
        _watch
          ..reset()
          ..start();
        recording = true;
        _stream = stream.listen(
          (part) {
            if (_closed || revision != _captureRevision) return;
            final remaining = maxPcmBytes - _bytes.length;
            if (remaining > 0) {
              _bytes.add(
                part.length <= remaining ? part : part.sublist(0, remaining),
              );
            }
            if (_bytes.length >= maxPcmBytes) _autoStop();
          },
          onDone: () {
            if (_closed || revision != _captureRevision) return;
            if (_streamEnded?.isCompleted == false) _streamEnded!.complete();
            if (recording) _autoStop();
          },
          onError: (Object _) {
            if (_closed || revision != _captureRevision) return;
            unawaited(_recordingFailed());
          },
        );
        _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (_closed || revision != _captureRevision) return;
          _elapsed = _watch.elapsed > maxRecordingDuration
              ? maxRecordingDuration
              : _watch.elapsed;
          if (_elapsed >= maxRecordingDuration) {
            _autoStop();
          } else {
            _changed();
          }
        });
        _limitTimer = Timer(maxRecordingDuration, () {
          if (!_closed && revision == _captureRevision) _autoStop();
        });
      } catch (e) {
        await recorder.cancel().catchError((_) {});
        if (_closed || revision != _captureRevision) return;
        error = e is PodMediaException
            ? e.message
            : 'The microphone could not start. Check microphone permission and try again.';
        throw PodMediaException(error!);
      } finally {
        if (!_closed && revision == _captureRevision) {
          _starting = false;
          _changed();
        }
      }
    });
    _changed();
    return _startFuture!;
  }

  void _autoStop() {
    unawaited(
      stopRecording().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  Future<void> _recordingFailed() async {
    final cancelled = cancelRecording();
    final revision = _captureRevision;
    await cancelled;
    if (_closed || revision != _captureRevision) return;
    error = 'Recording was interrupted. Try again.';
    _changed();
  }

  @override
  Future<Uint8List> stopRecording() {
    if (_clip != null) return Future<Uint8List>.value(_clip!);
    if (_stopFuture != null) return _stopFuture!;
    if (_closed || (!recording && !_starting)) {
      return Future<Uint8List>.error(
        const PodMediaException('There is no recording to use.'),
      );
    }
    final revision = _captureRevision;
    _timer?.cancel();
    _limitTimer?.cancel();
    _watch.stop();
    _stopFuture = _captureOperation(() async {
      if (_closed || revision != _captureRevision) {
        throw const PodMediaException('Recording was cancelled.');
      }
      // A stop requested while microphone permission was pending still closes
      // the resulting stream before exposing any bytes.
      _timer?.cancel();
      _limitTimer?.cancel();
      _watch.stop();
      final captureStream = _stream;
      final streamEnded = _streamEnded;
      try {
        await recorder.stop();
        await streamEnded?.future.timeout(const Duration(seconds: 2));
        if (_closed || revision != _captureRevision) {
          throw const PodMediaException('Recording was cancelled.');
        }
        final pcm = _bytes.takeBytes();
        if (pcm.length < 2) {
          throw const PodMediaException(
            'No speech was recorded. Please try again.',
          );
        }
        _clip = podPcmToWav(pcm);
        _elapsed = Duration(
          microseconds: ((_clip!.length - 44) * 1000000 / 48000).round(),
        );
        return _clip!;
      } catch (e) {
        await recorder.cancel().catchError((_) {});
        final failure = e is PodMediaException
            ? e
            : const PodMediaException(
                'The recording could not be completed. Please try again.',
              );
        if (!_closed && revision == _captureRevision) error = failure.message;
        throw failure;
      } finally {
        // onDone already releases a stream subscription. Cancelling it again
        // adds an unnecessary asynchronous boundary after hardware has stopped.
        // A revoked or interrupted capture still needs best-effort cleanup.
        if (revision != _captureRevision || streamEnded?.isCompleted != true) {
          await captureStream?.cancel().catchError((_) {});
        }
        if (!_closed && revision == _captureRevision) {
          recording = false;
          _stream = null;
          _changed();
        }
      }
    });
    return _stopFuture!;
  }

  @override
  Future<void> cancelRecording() {
    ++_captureRevision;
    recorder.cancelPendingStart();
    _timer?.cancel();
    _limitTimer?.cancel();
    _watch
      ..stop()
      ..reset();
    _elapsed = Duration.zero;
    _clip = null;
    _bytes.clear();
    recording = false;
    _starting = false;
    error = null;
    _stopFuture = null;
    final captureStream = _stream;
    _stream = null;
    if (_streamEnded?.isCompleted == false) _streamEnded!.complete();
    _changed();
    return _captureOperation(() async {
      await recorder.cancel().catchError((_) {});
      await captureStream?.cancel();
    });
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    unawaited(stop());
    unawaited(
      cancelRecording().whenComplete(recorder.dispose).catchError((_) {}),
    );
    unawaited(playback.dispose().catchError((_) {}));
    super.dispose();
  }
}

/// Encode only complete PCM16 samples, with a hard server-compatible bound.
Uint8List podPcmToWav(Uint8List pcm) {
  final bounded = pcm.length > PodMediaController.maxPcmBytes
      ? PodMediaController.maxPcmBytes
      : pcm.length;
  final size = bounded - bounded % 2;
  final wav = Uint8List(size + 44);
  final data = ByteData.sublistView(wav);
  void text(int offset, String value) =>
      wav.setRange(offset, offset + value.length, value.codeUnits);
  text(0, 'RIFF');
  data.setUint32(4, size + 36, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 24000, Endian.little);
  data.setUint32(28, 48000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, size, Endian.little);
  wav.setRange(44, wav.length, pcm);
  return wav;
}
