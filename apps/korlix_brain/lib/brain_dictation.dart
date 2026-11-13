import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

import 'brain_api.dart';

/// Owns short dictation capture across asynchronous permissions and workspaces.
/// SpeechToText is a process singleton, so its native commands must share one
/// queue even when authentication replaces the widget that requested capture.
class BrainDictation {
  BrainDictation({
    required this.canListen,
    required this.prepare,
    required this.emit,
    SpeechToText? speech,
  }) : _speech = speech ?? SpeechToText();

  static Future<void> _nativePending = Future<void>.value();
  static BrainDictation? _nativeOwner;
  final SpeechToText _speech;
  final bool Function() canListen;
  final Future<void> Function() prepare;
  final void Function(Map<String, dynamic>) emit;
  bool _disposed = false, _active = false, _needsRelease = false;
  int _generation = 0;
  int? _resultGeneration;
  Future<void>? _starting, _disposing;

  bool get active => _active;

  bool _current(int generation) =>
      !_disposed && generation == _generation && canListen();

  bool get _ownsNative => identical(_nativeOwner, this);

  static Future<void> _serialize(Future<void> Function() operation) {
    final previous = _nativePending;
    final task = () async {
      await previous;
      await operation();
    }();
    // A failed plugin call must not prevent the next cleanup attempt. The
    // caller still receives the error; a new owner retries cancellation first.
    _nativePending = task.catchError((Object _) {});
    return task;
  }

  Future<void> toggle(String kind) async {
    if (_active || _starting != null) {
      await stop();
      return;
    }
    if (_disposed || !canListen()) return;
    final generation = ++_generation;
    _resultGeneration = generation;
    final task = _start(kind, generation);
    _starting = task;
    try {
      await task;
    } finally {
      if (identical(_starting, task)) _starting = null;
    }
  }

  Future<void> _start(String kind, int generation) async {
    await prepare();
    if (!_current(generation)) return;
    await _serialize(() async {
      if (!_current(generation)) return;
      final previous = _nativeOwner;
      if (previous != null && !identical(previous, this)) {
        await previous._speech.cancel();
        previous._needsRelease = false;
        previous._resultGeneration = null;
        previous._clearCallbacks();
      }
      if (!_current(generation)) return;
      _nativeOwner = this;
      final available = await _speech.initialize(
        onError: _onError,
        onStatus: _onStatus,
      );
      if (!_current(generation)) return;
      if (!available) {
        throw const BrainApiException(
          'Enable microphone and speech recognition in your device settings, or type instead.',
        );
      }
      // initialize() retains the first successful listeners. Explicitly assign
      // this workspace's listeners after acquiring the shared recognizer.
      _speech.errorListener = _onError;
      _speech.statusListener = _onStatus;
      _active = true;
      _needsRelease = true;
      try {
        await _speech.listen(
          onResult: (result) {
            if (_disposed || !_ownsNative || !canListen() ||
                _resultGeneration != generation) {
              return;
            }
            emit({
              'type': 'dictation',
              'kind': kind,
              'text': result.recognizedWords,
              'final': result.finalResult,
            });
          },
          listenOptions: SpeechListenOptions(
            listenFor: const Duration(minutes: 1),
            pauseFor: const Duration(seconds: 5),
            partialResults: true,
            cancelOnError: true,
            listenMode: ListenMode.dictation,
          ),
        );
      } catch (_) {
        _active = false;
        _resultGeneration = null;
        await _speech.cancel();
        _needsRelease = false;
        rethrow;
      }
      if (!_current(generation)) {
        // A Stop/background event can arrive while native listen is pending.
        // Cancel after it completes before any later microphone owner starts.
        _active = false;
        _resultGeneration = null;
        await _speech.cancel();
        _needsRelease = false;
        return;
      }
      _status('Listening… tap Stop dictation when finished.');
    });
  }

  Future<void> stop({bool cancel = false}) {
    ++_generation;
    final wasActive = _active;
    _active = false;
    if (cancel) _resultGeneration = null;
    return _serialize(() async {
      if (!_ownsNative) return;
      if (_needsRelease || cancel) {
        if (cancel) {
          await _speech.cancel();
        } else {
          await _speech.stop();
        }
        _needsRelease = false;
      }
      if (wasActive) {
        _status('Dictation stopped. Review your text before saving.');
      }
    });
  }

  void _onError(SpeechRecognitionError error) {
    if (_disposed || !_ownsNative || _resultGeneration != _generation ||
        (!_active && _starting == null)) {
      return;
    }
    _active = false;
    _status('Dictation stopped. Check microphone and speech permissions, or type instead.');
  }

  void _onStatus(String status) {
    if (_disposed || !_ownsNative || !_active) return;
    if (status == 'done' || status == 'notListening') {
      _active = false;
      _status('Dictation stopped. Review your text before saving.');
    }
  }

  void _status(String message) {
    if (_disposed || !canListen()) return;
    emit({'type': 'dictationStatus', 'active': _active, 'message': message});
  }

  void _clearCallbacks() {
    _speech.errorListener = null;
    _speech.statusListener = null;
  }

  Future<void> dispose() {
    final pending = _disposing;
    if (pending != null) return pending;
    _disposed = true;
    return _disposing = stop(cancel: true).then((_) {
      if (_ownsNative) {
        _clearCallbacks();
        _nativeOwner = null;
      }
    }, onError: (Object error, StackTrace stack) {
      if (_ownsNative) _clearCallbacks();
      // Keep failed ownership so a later workspace retries native cancellation
      // before starting capture, rather than treating a failed release as done.
      Error.throwWithStackTrace(error, stack);
    });
  }
}
