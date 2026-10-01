import 'dart:async';

import 'package:ai_wiz_command_center/pod/pod_transition_audio.dart';
// Supplied by flutter_test; no additional package or provider is needed.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class _TransitionBackend implements PodTransitionBackend {
  @override
  bool supported = true;
  bool allowActivation = true, allowStart = true;
  bool failActivation = false, failStart = false, failStop = false;
  int activations = 0, starts = 0, disposals = 0;
  final stops = <bool>[];
  final durations = <Duration>[];
  Completer<bool>? activation;
  Completer<void>? fade;

  @override
  Future<bool> activate() {
    activations++;
    if (failActivation) {
      return Future<bool>.error(StateError('Autoplay denied'));
    }
    return activation?.future ?? Future<bool>.value(allowActivation);
  }

  @override
  bool start(Duration maximumDuration) {
    starts++;
    durations.add(maximumDuration);
    if (failStart) throw StateError('Audio route interrupted');
    return allowStart;
  }

  @override
  Future<void> stop({required bool immediate}) {
    stops.add(immediate);
    if (failStop) return Future<void>.error(StateError('Already stopped'));
    if (immediate && fade?.isCompleted == false) fade!.complete();
    return !immediate && fade != null ? fade!.future : Future<void>.value();
  }

  @override
  Future<void> dispose() async => disposals++;
}

void main() {
  test('gesture unlock is synchronous and sound waits for a real gap', () {
    fakeAsync((clock) {
      final backend = _TransitionBackend();
      final audio = PodTransitionAudio(backend: backend);
      audio.activate();
      expect(backend.activations, 1);
      expect(backend.starts, 0);
      clock.flushMicrotasks();
      expect(audio.ready, isTrue);
      audio.setWaiting(true);
      clock.elapse(const Duration(milliseconds: 599));
      expect(backend.starts, 0);
      clock.elapse(const Duration(milliseconds: 1));
      expect(backend.starts, 1);
      expect(audio.active, isTrue);
      audio.setWaiting(false);
      expect(backend.stops.last, isFalse);
      expect(audio.active, isFalse);
      expect(audio.ready, isTrue);
      audio.dispose();
      clock.flushMicrotasks();
    });
  });

  test('a prepared response avoids unnecessary transition music', () {
    fakeAsync((clock) {
      final backend = _TransitionBackend();
      final audio = PodTransitionAudio(backend: backend);
      audio.activate();
      clock.flushMicrotasks();
      audio.setWaiting(true);
      clock.elapse(const Duration(milliseconds: 200));
      audio.setWaiting(false);
      clock.elapse(const Duration(seconds: 2));
      expect(backend.starts, 0);
      audio.dispose();
      clock.flushMicrotasks();
    });
  });

  test('one gap has a hard limit and repeated waiting never restarts it', () {
    fakeAsync((clock) {
      final backend = _TransitionBackend();
      final audio = PodTransitionAudio(backend: backend);
      audio.activate();
      clock.flushMicrotasks();
      audio.setWaiting(true);
      clock.elapse(const Duration(milliseconds: 600));
      expect(backend.durations.single, const Duration(seconds: 15));
      clock.elapse(const Duration(seconds: 15));
      expect(audio.active, isFalse);
      expect(backend.stops.last, isTrue);
      audio.setWaiting(true);
      clock.elapse(const Duration(seconds: 30));
      expect(backend.starts, 1);
      audio.setWaiting(false);
      audio.setWaiting(true);
      clock.elapse(const Duration(milliseconds: 600));
      expect(backend.starts, 2);
      audio.dispose();
      clock.flushMicrotasks();
    });
  });

  test('a late unlock cannot start music after pause or disposal', () {
    for (final dispose in [false, true]) {
      fakeAsync((clock) {
        final backend = _TransitionBackend()..activation = Completer<bool>();
        final audio = PodTransitionAudio(backend: backend);
        audio.activate();
        audio.setWaiting(true);
        clock.elapse(const Duration(milliseconds: 600));
        expect(backend.starts, 0);
        if (dispose) {
          audio.dispose();
        } else {
          audio.stop();
        }
        backend.activation!.complete(true);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 20));
        expect(backend.starts, 0);
        expect(audio.active, isFalse);
        expect(audio.waiting, isFalse);
        expect(audio.ready, isFalse);
        if (!dispose) audio.dispose();
        clock.flushMicrotasks();
      });
    }
  });

  test('music unlock failure is optional and a later gesture can recover', () {
    fakeAsync((clock) {
      final backend = _TransitionBackend()..failActivation = true;
      final audio = PodTransitionAudio(backend: backend);
      audio.activate();
      audio.setWaiting(true);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      expect(audio.active, isFalse);
      expect(audio.ready, isFalse);
      backend.failActivation = false;
      audio.activate();
      clock.flushMicrotasks();
      expect(backend.starts, 1);
      expect(audio.active, isTrue);
      audio.dispose();
      clock.flushMicrotasks();
    });
  });

  test('unlock timeout never becomes late audio or an unhandled error', () {
    fakeAsync((clock) {
      final backend = _TransitionBackend()..activation = Completer<bool>();
      final audio = PodTransitionAudio(backend: backend);
      audio.activate();
      audio.setWaiting(true);
      clock.elapse(const Duration(seconds: 6));
      expect(audio.ready, isFalse);
      backend.activation!.complete(true);
      clock.flushMicrotasks();
      expect(backend.starts, 0);
      audio.dispose();
      clock.flushMicrotasks();
    });
  });

  test('microphone interruption immediately cancels an in-progress fade', () {
    fakeAsync((clock) {
      final backend = _TransitionBackend()..fade = Completer<void>();
      final audio = PodTransitionAudio(backend: backend);
      audio.activate();
      clock.flushMicrotasks();
      audio.setWaiting(true);
      clock.elapse(const Duration(milliseconds: 600));
      var handoffComplete = false;
      audio.setWaiting(false).then((_) => handoffComplete = true);
      expect(handoffComplete, isFalse);
      audio.stop();
      expect(backend.stops, [false, true]);
      clock.flushMicrotasks();
      expect(handoffComplete, isTrue);
      expect(audio.ready, isFalse);
      expect(audio.waiting, isFalse);
      audio.dispose();
      clock.flushMicrotasks();
    });
  });

  test('unsupported platforms never attempt audio activation or synthesis', () {
    fakeAsync((clock) {
      final backend = _TransitionBackend()..supported = false;
      final audio = PodTransitionAudio(backend: backend);
      audio.activate();
      audio.setWaiting(true);
      clock.elapse(const Duration(seconds: 20));
      expect(audio.supported, isFalse);
      expect(backend.activations, 0);
      expect(backend.starts, 0);
      audio.dispose();
      clock.flushMicrotasks();
    });
  });

  test('interrupted sound setup and cleanup cannot fail the voice flow', () {
    for (final throws in [false, true]) {
      fakeAsync((clock) {
        final backend = _TransitionBackend()
          ..allowStart = false
          ..failStart = throws
          ..failStop = true;
        final audio = PodTransitionAudio(backend: backend);
        audio.activate();
        clock.flushMicrotasks();
        audio.setWaiting(true);
        clock.elapse(const Duration(milliseconds: 600));
        expect(audio.active, isFalse);
        expect(audio.ready, isFalse);
        audio.stop();
        audio.dispose();
        clock.flushMicrotasks();
        expect(backend.disposals, 1);
      });
    }
  });

  test(
    'stop cancels the grace timer and disposal prevents future notifications',
    () {
      fakeAsync((clock) {
        final backend = _TransitionBackend();
        final audio = PodTransitionAudio(backend: backend);
        var changes = 0;
        audio.addListener(() => changes++);
        audio.activate();
        clock.flushMicrotasks();
        audio.setWaiting(true);
        clock.elapse(const Duration(milliseconds: 300));
        audio.stop();
        audio.dispose();
        final before = changes;
        audio.setWaiting(true);
        audio.activate();
        audio.stop();
        clock.elapse(const Duration(seconds: 20));
        expect(changes, before);
        expect(backend.starts, 0);
        expect(backend.disposals, 1);
        clock.flushMicrotasks();
      });
    },
  );
}
