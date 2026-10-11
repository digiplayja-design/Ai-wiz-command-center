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
  'text': id,
  'audio': {
    'base64': base64Encode(Uint8List(48044)),
    'mime': 'audio/wav',
    'durationSeconds': 1,
  },
};

void main() {
  test(
    'warming pauses new downloads and resumes the unused bank explicitly',
    () {
      fakeAsync((clock) {
        var allowed = true;
        final loaded = <String>[];
        final first = <String, Completer<Map<String, dynamic>>>{};
        final talk = PodSmallTalk((episode, id) {
          loaded.add(id);
          if (id.endsWith('-0')) {
            return (first[id] = Completer<Map<String, dynamic>>()).future;
          }
          return Future.value(clip(id));
        });
        talk.warm('episode', 2, canLoad: () => allowed);
        expect(loaded, hasLength(2));
        allowed = false;
        for (final download in first.entries) {
          download.value.complete(clip(download.key));
        }
        clock.flushMicrotasks();
        expect(loaded, hasLength(2));
        allowed = true;
        talk.warm('episode', 2, canLoad: () => allowed);
        clock.flushMicrotasks();
        expect(loaded, hasLength(6));
        expect(loaded.toSet(), hasLength(6));
        talk.dispose();
      });
    },
  );

  test(
    'slow cold assets join an existing wait instead of abandoning speech',
    () {
      fakeAsync((clock) {
        final firstDownloads = <String, Completer<Map<String, dynamic>>>{};
        final talk = PodSmallTalk((episode, id) {
          if (id.endsWith('-0')) {
            return (firstDownloads[id] = Completer<Map<String, dynamic>>())
                .future;
          }
          return Future.value(clip(id));
        });
        talk.warm('episode', 2);
        final waiting = Completer<void>();
        final spoken = <String>[];
        talk.fillWhile(
          waiting.future,
          canPlay: () => true,
          remaining: () => const Duration(minutes: 15),
          play: (clip) async {
            spoken.add(clip.text);
            await Future<void>.delayed(clip.duration);
          },
        );
        clock.elapse(const Duration(seconds: 5));
        expect(spoken, isEmpty);
        for (final download in firstDownloads.entries) {
          download.value.complete(clip(download.key));
        }
        clock.elapse(const Duration(seconds: 12));
        expect(spoken.length, greaterThan(4));
        waiting.complete();
        clock.elapse(const Duration(seconds: 2));
        expect(clock.pendingTimers, isEmpty);
        talk.dispose();
      });
    },
  );

  test('ready speech never waits for unfinished studio downloads', () {
    fakeAsync((clock) {
      final talk = PodSmallTalk(
        (episode, id) => Completer<Map<String, dynamic>>().future,
      );
      talk.warm('episode', 3);
      final waiting = Completer<void>();
      var done = false;
      talk
          .fillWhile(
            waiting.future,
            canPlay: () => true,
            remaining: () => const Duration(minutes: 15),
            play: (_) async => fail('No clip has loaded'),
          )
          .then((_) => done = true);
      clock.elapse(const Duration(seconds: 5));
      waiting.complete();
      clock.flushMicrotasks();
      expect(done, isTrue);
      expect(clock.pendingTimers, isEmpty);
      talk.dispose();
    });
  });

  test('long speech filling remains bounded by the request budget', () {
    fakeAsync((clock) {
      final talk = PodSmallTalk((episode, id) async => clip(id));
      talk.warm('episode', 2);
      var plays = 0, done = false;
      talk
          .fillWhile(
            Completer<void>().future,
            canPlay: () => true,
            remaining: () => const Duration(minutes: 15),
            play: (clip) async {
              plays++;
              await Future<void>.delayed(clip.duration);
            },
          )
          .then((_) => done = true);
      clock.elapse(const Duration(seconds: 230));
      expect(plays, greaterThan(20));
      expect(done, isTrue);
      expect(clock.pendingTimers, isEmpty);
      talk.dispose();
    });
  });

  for (final hosts in [2, 3]) {
    test(
      '$hosts-person panel keeps a long gap conversational with a rotating cached bank',
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
                spoken.add(clip.text);
                await Future<void>.delayed(clip.duration);
              },
            );
            clock.elapse(const Duration(seconds: 8));
            expect(spoken.length - before, greaterThan(2));
            waiting.complete();
            clock.elapse(const Duration(seconds: 2));
            clock.flushMicrotasks();
          }
          expect(
            spoken.map((id) => id.split('-').first).toSet(),
            hosts == 2
                ? {'host', 'analyst'}
                : {'host', 'analyst', 'challenger'},
          );
          expect(
            loaded.length,
            hosts * 3,
            reason: 'Each reusable clip is fetched once.',
          );
          for (var n = 1; n < spoken.length; n++) {
            expect(spoken[n], isNot(spoken[n - 1]));
          }
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
        expect(loads, 6);
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
