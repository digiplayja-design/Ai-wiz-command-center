import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_wiz_command_center/pod/pod_small_talk.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';

Map<String, dynamic> clip(String id) => {
  'id': id,
  'speaker': id.split('-').first,
  'text': 'A brief transition.',
  'audio': {
    'base64': base64Encode(Uint8List(48044)),
    'mime': 'audio/wav',
    'durationSeconds': 1,
  },
};

void main() {
  for (final hosts in [2, 3]) {
    test(
      '$hosts-person panel fills gaps in panel voices with at most two short clips',
      () {
        fakeAsync((clock) {
          final loaded = <String>[], spoken = <String>[];
          final talk = PodSmallTalk((episode, id) async {
            loaded.add(id);
            return clip(id);
          });
          for (var gap = 0; gap < 6; gap++) {
            talk.warm('episode', hosts);
            clock.flushMicrotasks();
            final waiting = Completer<void>();
            final before = spoken.length;
            talk.fillWhile(
              waiting.future,
              canPlay: () => true,
              remaining: () => const Duration(minutes: 15),
              play: (clip) async {
                spoken.add(clip.speaker);
                await Future<void>.delayed(clip.duration);
              },
            );
            clock.elapse(const Duration(seconds: 8));
            expect(spoken.length - before, 2);
            waiting.complete();
            clock.flushMicrotasks();
          }
          expect(
            spoken.toSet(),
            hosts == 2
                ? {'host', 'analyst'}
                : {'host', 'analyst', 'challenger'},
          );
          expect(
            loaded.length,
            hosts * 3,
            reason: 'Each reusable clip is fetched once.',
          );
          talk.dispose();
        });
      },
    );
  }
  test(
    'ready panelist skips filler; readiness during speech waits only for that sentence',
    () {
      fakeAsync((clock) {
        final talk = PodSmallTalk((episode, id) async => clip(id));
        talk.warm('episode', 2);
        clock.flushMicrotasks();
        var plays = 0, finished = false;
        talk.fillWhile(
          Future<void>.value(),
          canPlay: () => true,
          remaining: () => const Duration(minutes: 1),
          play: (_) async {
            plays++;
          },
        );
        clock.flushMicrotasks();
        expect(plays, 0);
        expect(clock.pendingTimers, isEmpty);
        final waiting = Completer<void>(), speech = Completer<void>();
        talk
            .fillWhile(
              waiting.future,
              canPlay: () => true,
              remaining: () => const Duration(minutes: 1),
              play: (_) {
                plays++;
                return speech.future;
              },
            )
            .then((_) => finished = true);
        clock.elapse(const Duration(milliseconds: 800));
        expect(plays, 1);
        waiting.complete();
        clock.flushMicrotasks();
        expect(finished, isFalse);
        speech.complete();
        clock.flushMicrotasks();
        expect(finished, isTrue);
        expect(plays, 1);
        expect(clock.pendingTimers, isEmpty);
        talk.dispose();
      });
    },
  );
  test('a ready voice wins if preparation completes during the music fade', () {
    fakeAsync((clock) {
      final talk = PodSmallTalk((episode, id) async => clip(id));
      talk.warm('episode', 2);
      clock.flushMicrotasks();
      final waiting = Completer<void>(), fade = Completer<void>();
      var plays = 0;
      talk.fillWhile(
        waiting.future,
        canPlay: () => true,
        remaining: () => const Duration(minutes: 1),
        beforePlay: () => fade.future,
        play: (_) async {
          plays++;
        },
      );
      clock.elapse(const Duration(milliseconds: 800));
      waiting.complete();
      fade.complete();
      clock.flushMicrotasks();
      expect(plays, 0);
      expect(clock.pendingTimers, isEmpty);
      talk.dispose();
    });
  });

  test(
    'pause, deadline and missing optional assets cannot play stale filler or hold up handoff',
    () {
      fakeAsync((clock) {
        var allowed = true, seconds = 60, plays = 0;
        final talk = PodSmallTalk((episode, id) async => clip(id));
        talk.warm('episode', 2);
        clock.flushMicrotasks();
        for (final mode in ['pause', 'deadline', 'disposed']) {
          final waiting = Completer<void>();
          allowed = true;
          seconds = 60;
          talk.fillWhile(
            waiting.future,
            canPlay: () => allowed,
            remaining: () => Duration(seconds: seconds),
            play: (_) async {
              plays++;
            },
          );
          if (mode == 'pause') allowed = false;
          if (mode == 'deadline') seconds = 2;
          if (mode == 'disposed') talk.dispose();
          clock.elapse(const Duration(seconds: 1));
          waiting.complete();
          clock.flushMicrotasks();
        }
        expect(plays, 0);
      });
    },
  );
  test(
    'failed warmup is optional, bounded and does not block other available voices',
    () {
      fakeAsync((clock) {
        var loads = 0;
        final spoken = <String>[];
        final talk = PodSmallTalk((episode, id) async {
          loads++;
          if (id == 'host-0') throw StateError('unavailable');
          return clip(id);
        });
        talk.warm('episode', 2);
        clock.flushMicrotasks();
        talk.warm('episode', 2);
        clock.flushMicrotasks();
        expect(loads, 2);
        final waiting = Completer<void>();
        talk.fillWhile(
          waiting.future,
          canPlay: () => true,
          remaining: () => const Duration(minutes: 1),
          play: (clip) async {
            spoken.add(clip.speaker);
          },
        );
        clock.elapse(const Duration(milliseconds: 800));
        waiting.complete();
        clock.flushMicrotasks();
        expect(spoken, ['analyst']);
        talk.dispose();
      });
    },
  );
}
