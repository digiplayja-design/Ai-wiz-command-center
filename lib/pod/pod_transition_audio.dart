import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pod_transition_audio_stub.dart'
    if (dart.library.js_interop) 'pod_transition_audio_web.dart'
    as platform;

PodTransitionAudio createPodTransitionAudio() =>
    PodTransitionAudio(backend: platform.createPodTransitionBackend());

/// Optional local sound only. This boundary never calls a speech provider,
/// downloads media, opens a microphone, or keeps a background session alive.
abstract class PodTransitionBackend {
  bool get supported;

  /// Called synchronously in the Listen / Resume gesture. Creates no audible
  /// sound. A refused browser gesture returns false or throws.
  Future<bool> activate();

  /// Starts a quiet original pad and schedules its own audio-clock cutoff.
  /// Returns false if browser audio is no longer available. Must not await or
  /// create a delayed start that can race a subsequent [stop].
  bool start(Duration maximumDuration);

  /// Immediate stops must silence output before the first asynchronous step.
  Future<void> stop({required bool immediate});
  Future<void> dispose();
}

/// A small, bounded sound bed for a real gap between panelists.
///
/// The screen owns the music preference and calls [setWaiting] only while a
/// foreground episode is waiting for its next voice. Call [stop] immediately
/// for pause, errors, microphone use, backgrounding, account changes and end.
/// No transition sound starts in the constructor or without [activate].
class PodTransitionAudio extends ChangeNotifier {
  PodTransitionAudio({
    required this.backend,
    this.startDelay = const Duration(milliseconds: 600),
    this.maximumDuration = const Duration(seconds: 15),
  }) : assert(startDelay >= Duration.zero),
       assert(maximumDuration > Duration.zero),
       assert(maximumDuration <= const Duration(seconds: 15));

  final PodTransitionBackend backend;
  final Duration startDelay, maximumDuration;
  bool _closed = false;
  bool _ready = false, _waiting = false, _active = false;
  bool _delayElapsed = false, _startedThisGap = false;
  int _activationRevision = 0, _gapRevision = 0;
  Timer? _delayTimer, _limitTimer;

  bool get supported => backend.supported;
  bool get ready => _ready;
  bool get waiting => _waiting;
  bool get active => _active;

  void _changed() {
    if (!_closed) notifyListeners();
  }

  /// Invoke directly in the gesture, without awaiting another operation first.
  /// Music failure is deliberately independent from the voice player.
  Future<void> activate() {
    if (_closed || !supported) return Future<void>.value();
    final revision = ++_activationRevision;
    try {
      return _finishActivation(backend.activate(), revision);
    } catch (_) {
      if (!_closed && revision == _activationRevision) _ready = false;
      _changed();
      return Future<void>.value();
    }
  }

  Future<void> _finishActivation(Future<bool> activation, int revision) async {
    var ready = false;
    try {
      ready = await activation.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Optional music must never reject Listen, Resume or voice playback.
    }
    if (_closed || revision != _activationRevision) return;
    _ready = ready;
    _tryStart();
    _changed();
  }

  Future<void> setWaiting(bool waiting) {
    if (_closed) return Future<void>.value();
    if (!waiting) return _endWaiting(immediate: false);
    if (_waiting) return Future<void>.value();
    _waiting = true;
    _delayElapsed = false;
    _startedThisGap = false;
    final revision = ++_gapRevision;
    _delayTimer?.cancel();
    _delayTimer = Timer(startDelay, () {
      if (_closed || revision != _gapRevision || !_waiting) return;
      _delayElapsed = true;
      _tryStart();
    });
    _changed();
    return Future<void>.value();
  }

  void _tryStart() {
    if (_closed ||
        !_ready ||
        !_waiting ||
        !_delayElapsed ||
        _startedThisGap ||
        !supported) {
      return;
    }
    // A repeated waiting notification never restarts an expired sound bed.
    _startedThisGap = true;
    try {
      _active = backend.start(maximumDuration);
      if (!_active) _ready = false;
    } catch (_) {
      _ready = _active = false;
      unawaited(_stopBackend(immediate: true));
    }
    if (_active) {
      final revision = _gapRevision;
      _limitTimer?.cancel();
      _limitTimer = Timer(maximumDuration, () {
        if (_closed || revision != _gapRevision) return;
        _active = false;
        unawaited(_stopBackend(immediate: true));
        _changed();
      });
    }
    _changed();
  }

  /// Leaves the saved music preference to the screen. Stale activation results
  /// cannot start sound after a lifecycle or microphone interruption.
  Future<void> stop({bool immediate = true}) {
    if (_closed) return Future<void>.value();
    ++_activationRevision;
    _ready = false;
    return _endWaiting(immediate: immediate);
  }

  Future<void> _endWaiting({required bool immediate}) {
    ++_gapRevision;
    _waiting = false;
    _active = false;
    _delayElapsed = false;
    _delayTimer?.cancel();
    _limitTimer?.cancel();
    _delayTimer = _limitTimer = null;
    _changed();
    return _stopBackend(immediate: immediate);
  }

  Future<void> _stopBackend({required bool immediate}) {
    try {
      return backend.stop(immediate: immediate).catchError((_) {});
    } catch (_) {
      return Future<void>.value();
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    ++_activationRevision;
    unawaited(_endWaiting(immediate: true));
    try {
      unawaited(backend.dispose().catchError((_) {}));
    } catch (_) {}
    super.dispose();
  }
}
