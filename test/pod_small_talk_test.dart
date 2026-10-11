import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_wiz_command_center/pod/pod_small_talk.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';

Map<String, dynamic> clip(String id, {int seconds = 1, String? text}) => {
  'id': id,
  'speaker': id.split('-').first,
  'text': text ?? id,
  'audio': {
    'base64': base64Encode(Uint8List(44 + 48000 * seconds)),
    'mime': 'audio/wav',
    'durationSeconds': seconds,
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

  test(
    'long speech filling remains bounded by the request budget and current thought',
    () {
      fakeAsync((clock) {
        final talk = PodSmallTalk((episode, id) async => clip(id, seconds: 18));
        talk.warm('episode', 2, conversationCount: 32);
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
        clock.elapse(const Duration(seconds: 255));
        expect(plays, inInclusiveRange(10, 13));
        expect(done, isTrue);
        expect(clock.pendingTimers, isEmpty);
        talk.dispose();
      });
    },
  );

  for (final hosts in [2, 3]) {
    test(
      '$hosts-person panel uses new remarks across every gap without recycling',
      () {
        fakeAsync((clock) {
          final loaded = <String>[], spoken = <String>[];
          final talk = PodSmallTalk((episode, id) async {
            loaded.add(id);
            return clip(id);
          });
          for (var gap = 0; gap < 6; gap++) {
            talk.warm('episode', hosts, conversationCount: 32);
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
          expect(spoken.toSet(), hasLength(spoken.length));
          expect(loaded.toSet(), hasLength(loaded.length));
          expect(loaded.length, lessThanOrEqualTo(spoken.length + 6));
          for (var n = 0; n + hosts <= spoken.length; n += hosts) {
            final exchange = spoken.skip(n).take(hosts).toList();
            expect(exchange.map((id) => id.split('-').first), [
              'host',
              'analyst',
              if (hosts == 3) 'challenger',
            ]);
            expect(
              exchange.map((id) => id.split('-').last).toSet(),
              hasLength(1),
            );
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
  test('an eighteen-second thought is accepted and hands off at its own end', () {
    fakeAsync((clock) {
      const thought =
          'A conversation can leave room for more than one possibility. '
          'A practical example gives us something specific to explore together. '
          'We can ask what changes when the circumstances are different, and '
          'which part of the idea still holds up.';
      final talk = PodSmallTalk(
        (episode, id) async => clip(id, seconds: 18, text: thought),
      );
      talk.warm('long-thought', 2, conversationCount: 32);
      final waiting = Completer<void>();
      var plays = 0, finished = false;
      talk
          .fillWhile(
            waiting.future,
            canPlay: () => true,
            remaining: () => const Duration(minutes: 5),
            play: (clip) async {
              expect(clip.text, thought);
              expect(clip.duration, const Duration(seconds: 18));
              plays++;
              await Future<void>.delayed(clip.duration);
            },
          )
          .then((_) => finished = true);
      clock.elapse(const Duration(seconds: 12));
      expect(plays, 1);
      waiting.complete();
      clock.flushMicrotasks();
      expect(finished, isFalse);
      clock.elapse(const Duration(seconds: 7));
      expect(finished, isTrue);
      expect(
        plays,
        1,
        reason: 'A ready answer must not wait for the rest of the exchange.',
      );
      expect(clock.pendingTimers, isEmpty);
      talk.dispose();
    });
  });

  test(
    'out-of-order downloads keep the exchange in order and prefetch only six turns',
    () {
      fakeAsync((clock) {
        final downloads = <String, Completer<Map<String, dynamic>>>{};
        final talk = PodSmallTalk(
          (episode, id) =>
              (downloads[id] = Completer<Map<String, dynamic>>()).future,
        );
        talk.warm('ordered', 3, conversationCount: 32);
        expect(downloads, hasLength(2));
        final first = downloads.keys.first;
        final second = downloads.keys.last;
        final waiting = Completer<void>();
        final spoken = <String>[];
        talk.fillWhile(
          waiting.future,
          canPlay: () => true,
          remaining: () => const Duration(minutes: 5),
          play: (clip) async {
            spoken.add(clip.speaker);
            await Future<void>.delayed(clip.duration);
          },
        );
        downloads[second]!.complete(clip(second));
        clock.elapse(const Duration(seconds: 2));
        expect(
          spoken,
          isEmpty,
          reason: 'The answer cannot precede the opening thought.',
        );
        // Resolve all optional prefetches, leaving the first voice pending.
        for (var pass = 0; pass < 6; pass++) {
          for (final entry in downloads.entries.toList()) {
            if (entry.key != first && !entry.value.isCompleted) {
              entry.value.complete(clip(entry.key));
            }
          }
          clock.flushMicrotasks();
        }
        expect(
          downloads,
          hasLength(6),
          reason: 'Do not download the whole larger bank.',
        );
        downloads[first]!.complete(clip(first));
        clock.elapse(const Duration(seconds: 3));
        expect(spoken.take(2), ['host', 'analyst']);
        waiting.complete();
        clock.elapse(const Duration(seconds: 2));
        talk.dispose();
      });
    },
  );

  for (final count in [0, 2]) {
    test(
      'exhausted ${count == 0 ? 'legacy' : 'extended'} bank never restarts after another warm or gap',
      () {
        fakeAsync((clock) {
          final spoken = <String>[], loaded = <String>[];
          final talk = PodSmallTalk((episode, id) async {
            loaded.add(id);
            return clip(id);
          });
          for (var gap = 0; gap < 3; gap++) {
            talk.warm('exhaustion', 2, conversationCount: count);
            final waiting = Completer<void>();
            talk.fillWhile(
              waiting.future,
              canPlay: () => true,
              remaining: () => const Duration(minutes: 5),
              play: (clip) async {
                spoken.add(clip.text);
                await Future<void>.delayed(clip.duration);
              },
            );
            clock.elapse(const Duration(seconds: 20));
            waiting.complete();
            clock.flushMicrotasks();
          }
          expect(spoken, hasLength(count == 0 ? 6 : 4));
          expect(spoken.toSet(), hasLength(spoken.length));
          expect(loaded.toSet(), hasLength(loaded.length));
          expect(clock.pendingTimers, isEmpty);
          talk.dispose();
        });
      },
    );
  }

  test(
    'different episodes shuffle exchanges while stale downloads cannot join the new one',
    () {
      fakeAsync((clock) {
        final old = <String, Completer<Map<String, dynamic>>>{};
        final orders = <String, List<String>>{};
        final talk = PodSmallTalk((episode, id) {
          (orders[episode] ??= []).add(id);
          if (episode == 'old') {
            return (old[id] = Completer<Map<String, dynamic>>()).future;
          }
          return Future.value(clip(id, text: '$episode:$id'));
        });
        talk.warm('old', 2, conversationCount: 32);
        for (final episode in ['new-one', 'new-two']) {
          talk.warm(episode, 2, conversationCount: 32);
          if (episode == 'new-one') {
            for (final entry in old.entries) {
              entry.value.complete(clip(entry.key, text: 'stale'));
            }
          }
          talk.fillWhile(
            Completer<void>().future,
            canPlay: () => true,
            remaining: () => const Duration(minutes: 5),
            play: (clip) async {
              expect(clip.text, startsWith('$episode:'));
              await Future<void>.delayed(clip.duration);
            },
          );
          clock.elapse(const Duration(seconds: 120));
        }
        expect(orders['new-one'], hasLength(64));
        expect(orders['new-two'], hasLength(64));
        expect(orders['new-one'], isNot(orderedEquals(orders['new-two']!)));
        expect(orders['new-one']!.toSet(), orders['new-two']!.toSet());
        expect(clock.pendingTimers, isEmpty);
        talk.dispose();
      });
    },
  );

  test(
    'invalid or overlong extended audio is skipped without retries or blocking valid speech',
    () {
      fakeAsync((clock) {
        var calls = 0;
        final spoken = <String>[];
        final talk = PodSmallTalk((episode, id) async {
          calls++;
          if (calls == 1) return clip(id, seconds: 31);
          if (calls == 2) return {...clip(id), 'speaker': 'unknown'};
          if (calls == 3) return {...clip(id), 'text': ''};
          return clip(id, seconds: 18);
        });
        talk.warm('validated', 2, conversationCount: 2);
        final waiting = Completer<void>();
        talk.fillWhile(
          waiting.future,
          canPlay: () => true,
          remaining: () => const Duration(minutes: 5),
          play: (clip) async => spoken.add(clip.speaker),
        );
        clock.elapse(const Duration(seconds: 3));
        waiting.complete();
        clock.flushMicrotasks();
        expect(calls, 4);
        expect(spoken, ['analyst']);
        talk.dispose();
      });
    },
  );
}
