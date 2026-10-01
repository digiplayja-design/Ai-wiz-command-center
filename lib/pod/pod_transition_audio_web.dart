import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'pod_transition_audio.dart';

PodTransitionBackend createPodTransitionBackend() => _WebTransitionAudio();

/// Three original sine tones form a soft C-major pad. Its peak summed signal
/// is below 0.05, well below full-scale speech. Everything is synthesized on
/// device: no copyrighted recording, downloaded asset or paid provider call.
class _WebTransitionAudio implements PodTransitionBackend {
  web.AudioContext? _context;
  final _groups = <_PadGroup>{};
  bool _closed = false;
  JSFunction? _visibilityListener;
  static const _fade = Duration(milliseconds: 120);
  static const _gain = 0.014;

  @override
  bool get supported => web.window.hasProperty('AudioContext'.toJS).toDart;

  @override
  Future<bool> activate() {
    if (_closed || !supported || web.document.visibilityState != 'visible') {
      return Future<bool>.value(false);
    }
    final context = _context ??= web.AudioContext(
      web.AudioContextOptions(latencyHint: 'interactive'.toJS),
    );
    _visibilityListener ??= ((web.Event _) {
      if (web.document.visibilityState != 'visible') {
        unawaited(stop(immediate: true));
      }
    }).toJS;
    web.document.addEventListener('visibilitychange', _visibilityListener);
    // resume() is invoked before the first await, preserving the tap gesture.
    return context.resume().toDart.then((_) {
      return !_closed &&
          web.document.visibilityState == 'visible' &&
          context.state == 'running';
    });
  }

  @override
  bool start(Duration maximumDuration) {
    final context = _context;
    if (_closed ||
        context == null ||
        context.state != 'running' ||
        web.document.visibilityState != 'visible') {
      return false;
    }
    _clearAll();
    final seconds = (maximumDuration.inMicroseconds / 1000000).clamp(0.1, 15.0);
    final now = context.currentTime;
    final end = now + seconds;
    final attack = (seconds * 0.1).clamp(0.02, 0.55);
    final release = (seconds * 0.1).clamp(0.02, 0.4);
    final gain = context.createGain();
    gain.gain.value = 0;
    gain.connect(context.destination);
    final group = _PadGroup(gain);
    _groups.add(group);
    gain.gain
      ..setValueAtTime(0, now)
      ..linearRampToValueAtTime(_gain, now + attack)
      ..setValueAtTime(_gain, end - release)
      ..linearRampToValueAtTime(0, end);
    for (final frequency in [130.8128, 195.9977, 329.6276]) {
      final oscillator = context.createOscillator();
      group.oscillators.add(oscillator);
      oscillator.type = 'sine';
      oscillator.frequency.value = frequency;
      oscillator.connect(gain);
      oscillator.start(now);
      // Audio-clock automation enforces the limit even if page timers stall.
      oscillator.stop(end);
    }
    group.cleanup = Timer(maximumDuration, () => _finish(group));
    return true;
  }

  @override
  Future<void> stop({required bool immediate}) {
    final context = _context;
    if (immediate || context == null || context.state != 'running') {
      _clearAll();
      return Future<void>.value();
    }
    final pending = <Future<void>>[];
    for (final group in _groups.toList()) {
      pending.add(group.finished.future);
      if (group.fading) continue;
      group.fading = true;
      group.cleanup?.cancel();
      final now = context.currentTime;
      final end = now + _fade.inMicroseconds / 1000000;
      final current = group.gain.gain.value.clamp(0.0, _gain);
      group.gain.gain
        ..cancelScheduledValues(now)
        ..setValueAtTime(current, now)
        ..linearRampToValueAtTime(0, end);
      for (final oscillator in group.oscillators) {
        oscillator.stop(end);
      }
      group.cleanup = Timer(_fade, () => _finish(group));
    }
    return Future.wait(pending).then((_) {});
  }

  void _clearAll() {
    for (final group in _groups.toList()) {
      _finish(group);
    }
  }

  void _finish(_PadGroup group) {
    if (!_groups.remove(group)) return;
    group.cleanup?.cancel();
    // Disconnect first: lifecycle and microphone stops silence immediately.
    try {
      group.gain.disconnect();
    } catch (_) {}
    for (final oscillator in group.oscillators) {
      try {
        oscillator.stop();
        oscillator.disconnect();
      } catch (_) {}
    }
    if (!group.finished.isCompleted) group.finished.complete();
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    if (_visibilityListener != null) {
      web.document.removeEventListener('visibilitychange', _visibilityListener);
      _visibilityListener = null;
    }
    _clearAll();
    final context = _context;
    _context = null;
    if (context != null && context.state != 'closed') {
      try {
        await context.close().toDart.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }
}

class _PadGroup {
  _PadGroup(this.gain);
  final web.GainNode gain;
  final oscillators = <web.OscillatorNode>[];
  final finished = Completer<void>();
  Timer? cleanup;
  bool fading = false;
}
