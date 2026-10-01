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

  /// First called synchronously in a Listen / Resume gesture, then reused to
  /// resume that context before each new gap. Creates no audible sound.
  /// A refused browser gesture or interruption returns false or throws.
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
    this.maximumDuration = const Duration(seconds: 225),
    DateTime Function()? now,
  }) : assert(startDelay >= Duration.zero),
       assert(maximumDuration > Duration.zero),
       assert(maximumDuration <= const Duration(seconds: 225)),
       _now = now ?? DateTime.now;

  final PodTransitionBackend backend;
  final Duration startDelay, maximumDuration;
  final DateTime Function() _now;
  bool _closed = false;
  bool _ready = false, _waiting = false, _active = false;
  bool _gestureRequested = false, _blocked = false;
  bool _delayElapsed = false, _startedThisGap = false;
  DateTime? _gapEndsAt;
  int _activationRevision = 0, _gapRevision = 0;
  Timer? _delayTimer, _limitTimer;

  bool get supported => backend.supported;
  bool get ready => _ready;
  bool get waiting => _waiting;
  bool get active => _active;
  bool get blocked => _blocked;

  void _changed() {
    if (!_closed) notifyListeners();
  }

  /// Invoke directly in the gesture, without awaiting another operation first.
  /// Music failure is deliberately independent from the voice player.
  Future<void> activate() {
    if (_closed || !supported) return Future<void>.value();
    _gestureRequested = true;
    if (_blocked &&
        _waiting &&
        !_active &&
        _gapEndsAt?.isAfter(_now()) == true) {
      _startedThisGap = false;
    }
    return _resumeContext();
  }

  Future<void> _resumeContext() {
    final revision = ++_activationRevision;
    _ready = false;
    _blocked = false;
    try {
      return _finishActivation(backend.activate(), revision);
    } catch (_) {
      if (!_closed && revision == _activationRevision) _blocked = true;
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
    _blocked = !ready;
    _tryStart();
    _changed();
  }

  Future<void> setWaiting(bool waiting, {Duration? remaining}) {
    if (_closed) return Future<void>.value();
    if (!waiting) return _endWaiting(immediate: false);
    if (_waiting) return Future<void>.value();
    final gapRemaining = remaining == null || remaining > maximumDuration
        ? maximumDuration
        : remaining;
    if (gapRemaining <= startDelay) return Future<void>.value();
    _waiting = true;
    _gapEndsAt = _now().add(gapRemaining);
    _delayElapsed = false;
    _startedThisGap = false;
    final revision = ++_gapRevision;
    _delayTimer?.cancel();
    _delayTimer = Timer(startDelay, () {
      if (_closed || revision != _gapRevision || !_waiting) return;
      _delayElapsed = true;
      _tryStart();
    });
    _limitTimer?.cancel();
    _limitTimer = Timer(gapRemaining, () {
      if (_closed || revision != _gapRevision) return;
      _startedThisGap = true;
      _active = false;
      _blocked = false;
      unawaited(_stopBackend(immediate: true));
      _changed();
    });
    // Mobile browsers may suspend or interrupt an already-unlocked context
    // between speech clips. Recheck once per gap; never create audio without
    // a prior Listen/Resume tap, never retry endlessly, and never await this
    // optional operation in the panelist's speech path.
    if (_gestureRequested && supported) unawaited(_resumeContext());
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
    // Activation time counts against the same budget. The audio clock and a
    // separate wall-clock timer both stop the bed at the episode/request limit.
    final duration = _gapEndsAt?.difference(_now()) ?? Duration.zero;
    if (duration <= Duration.zero) return;
    try {
      _active = backend.start(duration);
      if (!_active) {
        _ready = false;
        _blocked = true;
      }
    } catch (_) {
      _ready = _active = false;
      _blocked = true;
      unawaited(_stopBackend(immediate: true));
    }
    _changed();
  }

  /// Leaves the saved music preference to the screen. Stale activation results
  /// cannot start sound after a lifecycle or microphone interruption.
  Future<void> stop({bool immediate = true}) {
    if (_closed) return Future<void>.value();
    ++_activationRevision;
    _ready = false;
    _gestureRequested = false;
    _blocked = false;
    return _endWaiting(immediate: immediate);
  }

  Future<void> _endWaiting({required bool immediate}) {
    ++_gapRevision;
    _waiting = false;
    _active = false;
    _delayElapsed = false;
    _gapEndsAt = null;
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
