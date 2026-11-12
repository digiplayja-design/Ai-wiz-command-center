import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_projection.dart';
import 'package:korlix_brain/brain_projection_screen.dart';

const config = <String, dynamic>{
  'rendererUrl': 'https://api.example.com/brain-projection/earth.html',
  'mapAvailable': true,
  'geocodingAvailable': true,
  'answersAvailable': true,
  'answerCredits': 4,
  'answerCostLabel': '4 credits per sourced answer',
};
const place = <String, dynamic>{
  'id': 'place-test',
  'label': 'Test destination',
  'address': 'A verified fixture address',
  'latitude': 40.71,
  'longitude': -74.0,
  'provider': 'fixture',
};

class Fixture {
  Fixture({ProjectionRequest? request}) {
    projection = BrainProjection(
      backendUrl: 'https://api.example.com',
      request:
          request ??
          (method, path, body) async {
            requests.add(path);
            if (path.endsWith('/config')) return config;
            if (path.endsWith('/resolve')) {
              return {
                'candidates': [place],
              };
            }
            return {
              'text': 'A test answer with evidence. [1]',
              'scope': 'The selected fixture city',
              'date': '2026-11-07',
              'sources': [
                {
                  'title': 'Official fixture',
                  'url': 'https://example.org/facts',
                },
              ],
            };
          },
      onOpen: () => opens++,
      onClose: () => closes++,
      onStartVoice: () async {
        starts++;
      },
      onStopVoice: () async {
        stops++;
      },
      onSave: (text, fromVoice) async {
        saves.add({'text': text, 'fromVoice': fromVoice});
        return true;
      },
    );
  }
  late final BrainProjection projection;
  int opens = 0, closes = 0, starts = 0, stops = 0;
  final requests = <String>[];
  final saves = <Map<String, dynamic>>[];

  Future<void> select() async {
    projection.open();
    await projection.search('My destination');
    projection.select('place-test');
    await projection.dispatch('rendererReady', {});
  }
}

void main() {
  group('Projection ownership', () {
    test('open, room changes and close never start or stop voice', () async {
      final f = Fixture();
      addTearDown(f.projection.dispose);
      f.projection.open();
      f.projection.open();
      await f.projection.dispatch('room', {'room': 'discovery'});
      f.projection.close();
      expect(f.opens, 1);
      expect(f.closes, 1);
      expect(f.starts, 0);
      expect(f.stops, 0);
      expect(f.projection.snapshot['room'], 'discovery');
    });

    test('stop is distinct from closing the view', () async {
      final f = Fixture();
      addTearDown(f.projection.dispose);
      f.projection.open();
      await f.projection.dispatch('stopVoice', {});
      expect(f.stops, 1);
      expect(f.projection.isOpen, true);
      expect(f.closes, 0);
    });

    test('renderer must be the exact first-party HTTPS document', () {
      final f = Fixture();
      addTearDown(f.projection.dispose);
      expect(
        f.projection.checkedRenderer(config['rendererUrl']),
        config['rendererUrl'],
      );
      for (final value in [
        'http://api.example.com/brain-projection/earth.html',
        'https://evil.example/brain-projection/earth.html',
        'https://api.example.com/arbitrary.html',
        'https://api.example.com/brain-projection/earth.html?token=x',
        'https://user@api.example.com/brain-projection/earth.html',
      ]) {
        expect(f.projection.checkedRenderer(value), isNull, reason: value);
      }
    });
  });

  group('Projection capability refresh', () {
    test(
      'a genuine reopening refreshes previously unavailable services',
      () async {
        var reads = 0;
        final refreshed = Completer<Map<String, dynamic>>();
        final f = Fixture(
          request: (method, path, body) async {
            if (path.endsWith('/config')) {
              if (++reads == 1) return <String, dynamic>{};
              return refreshed.future;
            }
            return {
              'candidates': [place],
            };
          },
        );
        addTearDown(f.projection.dispose);
        f.projection.open();
        final unavailable = await f.projection.search('10 Downing Street');
        expect(unavailable['ok'], false);
        expect(
          unavailable['answer'],
          contains('Address search is not connected yet'),
        );
        f.projection.open(room: 'discovery');
        await f.projection.dispatch('room', {'room': 'command'});
        expect(reads, 1, reason: 'An open view and room changes share config');

        f.projection.close();
        f.projection.open();
        expect((f.projection.snapshot['config'] as Map)['checking'], true);
        final lookup = f.projection.search(
          '10 Downing Street, London SW1A 2AA',
        );
        expect(reads, 2, reason: 'Search joins this opening’s config request');
        refreshed.complete(config);
        expect((await lookup)['ok'], true);
        expect((f.projection.snapshot['config'] as Map)['mapAvailable'], true);
        expect((f.projection.snapshot['config'] as Map)['checking'], false);
        expect(f.projection.snapshot['selectedPlace'], isNull);
        expect(f.projection.snapshot['candidates'], hasLength(1));
        expect(f.opens, 2);
        expect(f.starts, 0);
        expect(f.stops, 0);
      },
    );

    for (final oldFails in [false, true]) {
      for (final oldFinishesFirst in [false, true]) {
        test(
          'stale config ${oldFails ? 'failure' : 'success'} ${oldFinishesFirst ? 'before' : 'after'} the new request is ignored',
          () async {
            final old = Completer<Map<String, dynamic>>();
            final current = Completer<Map<String, dynamic>>();
            var reads = 0;
            final f = Fixture(
              request: (method, path, body) async {
                if (path.endsWith('/config')) {
                  return ++reads == 1 ? old.future : current.future;
                }
                return {
                  'candidates': [place],
                };
              },
            );
            addTearDown(f.projection.dispose);
            f.projection.open();
            f.projection.close();
            f.projection.open();

            void finishOld() {
              if (oldFails) {
                old.completeError(StateError('old request failed'));
              } else {
                old.complete(<String, dynamic>{});
              }
            }

            if (oldFinishesFirst) {
              finishOld();
              await Future<void>.delayed(Duration.zero);
              expect(
                (f.projection.snapshot['config'] as Map)['checking'],
                true,
              );
            }
            final lookup = f.projection.search('Current destination');
            expect(
              reads,
              2,
              reason: 'An old finalizer cannot clear the new pending request',
            );
            current.complete(config);
            await lookup;
            final before = jsonEncode(f.projection.snapshot);
            if (!oldFinishesFirst) {
              finishOld();
              await Future<void>.delayed(Duration.zero);
            }
            expect(jsonEncode(f.projection.snapshot), before);
            expect(
              (f.projection.snapshot['config'] as Map)['mapAvailable'],
              true,
            );
            expect((f.projection.snapshot['config'] as Map)['checking'], false);
            expect(reads, 2);
          },
        );
      }
    }

    test(
      'a failed refresh does not reuse previously enabled capabilities',
      () async {
        var reads = 0;
        var resolves = 0;
        final f = Fixture(
          request: (method, path, body) async {
            if (path.endsWith('/config')) {
              if (++reads == 1) return config;
              throw StateError('refresh unavailable');
            }
            resolves++;
            return {
              'candidates': [place],
            };
          },
        );
        addTearDown(f.projection.dispose);
        f.projection.open();
        await f.projection.search('First destination');
        f.projection.close();
        f.projection.open();
        expect((await f.projection.search('Second destination'))['ok'], false);
        final current = f.projection.snapshot['config'] as Map;
        expect(current['rendererUrl'], isNull);
        expect(current['mapAvailable'], false);
        expect(current['geocodingAvailable'], false);
        expect(current['checking'], false);
        expect(current['checkFailed'], true);
        expect(resolves, 1);
        f.projection.open(room: 'discovery');
        await f.projection.search('Another attempt in the same opening');
        expect(
          reads,
          2,
          reason: 'Failed checks also remain scoped to one opening',
        );
        f.projection.close();
        f.projection.open();
        await Future<void>.delayed(Duration.zero);
        expect(
          reads,
          3,
          reason: 'Closing and reopening retries a failed check',
        );
      },
    );

    test('close and dispose ignore pending configuration completion', () async {
      for (final dispose in [false, true]) {
        final pending = Completer<Map<String, dynamic>>();
        final f = Fixture(request: (_, _, _) => pending.future);
        var notifications = 0;
        f.projection.addListener(() => notifications++);
        f.projection.open();
        if (dispose) {
          f.projection.dispose();
        } else {
          f.projection.close();
          addTearDown(f.projection.dispose);
        }
        final before = jsonEncode(f.projection.snapshot);
        final count = notifications;
        pending.complete(config);
        await Future<void>.delayed(Duration.zero);
        expect(jsonEncode(f.projection.snapshot), before);
        expect(notifications, count);
      }
    });
  });

  group('Place state and evidence', () {
    test(
      'camera waits for the renderer and readiness resets on errors and reopen',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        f.projection.open();
        await f.projection.search('My destination');
        f.projection.select('place-test');
        final initialCamera = f.projection.snapshot['camera'];
        final connecting = f.projection.camera('closer');
        expect(connecting['ok'], false);
        expect(connecting['answer'], contains('still connecting'));
        expect(f.projection.snapshot['camera'], initialCamera);

        await f.projection.dispatch('rendererReady', {});
        expect(f.projection.camera('closer')['ok'], true);
        await f.projection.dispatch('room', {'room': 'discovery'});
        expect(f.projection.camera('farther')['ok'], true);

        await f.projection.dispatch('rendererReady', {'status': 'error'});
        final failedCamera = f.projection.snapshot['camera'];
        final unavailable = f.projection.camera('left');
        expect(unavailable['ok'], false);
        expect(unavailable['answer'], contains('unavailable'));
        expect(f.projection.snapshot['camera'], failedCamera);

        await f.projection.dispatch('rendererReady', {'status': 'ready'});
        expect(f.projection.camera('right')['ok'], true);
        await f.projection.dispatch('rendererReady', {'status': 'loading'});
        expect(f.projection.camera('closer')['ok'], false);

        await f.projection.dispatch('rendererReady', {'status': 'ready'});
        f.projection.close();
        f.projection.open();
        final reopened = f.projection.camera('closer');
        expect(reopened['ok'], false);
        expect(reopened['answer'], contains('still connecting'));
        expect(f.starts, 0);
        expect(f.stops, 0);
      },
    );

    test(
      'even a single result needs confirmation; rooms retain selection',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        f.projection.open();
        await f.projection.search('My destination');
        expect(f.projection.snapshot['selectedPlace'], isNull);
        expect(f.projection.snapshot['candidates'], hasLength(1));
        f.projection.select('place-test');
        await f.projection.dispatch('room', {'room': 'discovery'});
        expect(
          (f.projection.snapshot['selectedPlace'] as Map)['id'],
          'place-test',
        );
        expect((f.projection.snapshot['camera'] as Map)['operation'], 'flyTo');
      },
    );

    test(
      'voice lookup and selection keep provider address labels on screen',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        f.projection.open();
        final lookup = await f.projection.voiceTurn(
          'provider-lookup',
          'Go to San Francisco Ferry Building',
          {'action': 'search', 'value': 'San Francisco Ferry Building'},
        );
        expect(
          lookup?['answer'],
          contains('Review the full address on screen'),
        );
        expect(
          (f.projection.snapshot['candidates'] as List).single['address'],
          place['address'],
        );
        final selection = await f.projection.voiceTurn(
          'provider-confirm',
          'Yes that is the place',
          {'action': 'search', 'value': 'yes'},
        );
        expect(selection?['answer'], contains('confirmed'));
        expect(
          (f.projection.snapshot['selectedPlace'] as Map)['address'],
          place['address'],
        );
        for (final result in [lookup, selection]) {
          final spoken = jsonEncode(result);
          expect(spoken, isNot(contains(place['address'] as String)));
          expect(spoken, isNot(contains(place['label'] as String)));
          expect(spoken, isNot(contains(place['id'] as String)));
        }
      },
    );

    test('reopening restores the selected destination while room changes retain the camera', () async {
      final f = Fixture();
      addTearDown(f.projection.dispose);
      await f.select();
      f.projection.camera('closer');
      final relativeCamera = Map<String, dynamic>.from(
        f.projection.snapshot['camera'] as Map,
      );
      expect(relativeCamera['operation'], 'closer');

      await f.projection.dispatch('room', {'room': 'discovery'});
      expect(f.projection.snapshot['camera'], relativeCamera);
      f.projection.open();
      expect(f.projection.snapshot['camera'], relativeCamera);

      f.projection.close();
      f.projection.open();
      final restored = f.projection.snapshot['camera'] as Map;
      expect(
        restored['sequence'],
        greaterThan(relativeCamera['sequence'] as int),
      );
      expect(restored['operation'], 'flyTo');
      expect(restored['latitude'], place['latitude']);
      expect(restored['longitude'], place['longitude']);
      expect(restored['height'], 650);
      expect(restored['heading'], 0);
      expect(restored['pitch'], -45);
      expect(f.projection.snapshot['room'], 'discovery');
      expect(
        (f.projection.snapshot['selectedPlace'] as Map)['id'],
        'place-test',
      );
      expect(f.starts, 0);
      expect(f.stops, 0);
    });

    test('stopped or closed lookup cannot repopulate candidates', () async {
      final pending = Completer<Map<String, dynamic>>();
      final f = Fixture(
        request: (method, path, body) async {
          if (path.endsWith('/config')) return config;
          return pending.future;
        },
      );
      addTearDown(f.projection.dispose);
      f.projection.open();
      final lookup = f.projection.search('A place');
      await Future<void>.delayed(Duration.zero);
      f.projection.cancelPending();
      pending.complete({
        'candidates': [place],
      });
      await lookup;
      expect(f.projection.snapshot['candidates'], isEmpty);
      expect(f.projection.snapshot['loading'], false);
    });

    test('latest lookup wins when results arrive out of order', () async {
      final first = Completer<Map<String, dynamic>>();
      final second = Completer<Map<String, dynamic>>();
      final f = Fixture(
        request: (method, path, body) async {
          if (path.endsWith('/config')) return config;
          return body!['query'] == 'First place' ? first.future : second.future;
        },
      );
      addTearDown(f.projection.dispose);
      final one = f.projection.search('First place');
      await Future<void>.delayed(Duration.zero);
      final two = f.projection.search('Second place');
      second.complete({
        'candidates': [
          {...place, 'id': 'second'},
        ],
      });
      await two;
      first.complete({
        'candidates': [place],
      });
      await one;
      expect(
        (f.projection.snapshot['candidates'] as List).single['id'],
        'second',
      );
    });

    test(
      'source-less and unsafe URL answers are not presented as verified',
      () async {
        final f = Fixture(
          request: (method, path, body) async {
            if (path.endsWith('/config')) return config;
            if (path.endsWith('/resolve')) {
              return {
                'candidates': [place],
              };
            }
            return {
              'text': 'Unsupported factual assertion',
              'sources': [
                {'title': 'bad', 'url': 'javascript:alert(1)'},
              ],
            };
          },
        );
        addTearDown(f.projection.dispose);
        await f.select();
        final answer = await f.projection.ask('Who is the mayor?');
        expect(answer['ok'], false);
        expect(
          answer['answer'],
          isNot(contains('Unsupported factual assertion')),
        );
        expect(f.projection.mayOpenSource('javascript:alert(1)'), false);
      },
    );

    test('sources can only be opened for current confirmed answer', () async {
      final f = Fixture();
      addTearDown(f.projection.dispose);
      await f.select();
      await f.projection.ask('Who is the mayor?');
      expect(f.projection.mayOpenSource('https://example.org/facts'), true);
      expect(f.projection.mayOpenSource('https://other.example/'), false);
      await f.projection.search('Another destination');
      expect(f.projection.mayOpenSource('https://example.org/facts'), false);
    });

    test(
      'live view and imagery age use honest local unavailable responses',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        await f.select();
        final before = f.requests.length;
        final live = await f.projection.ask(
          'Show me a live view of the address',
        );
        final age = await f.projection.ask('How old is the imagery?');
        expect(live['isLive'], false);
        expect(live['answer'], contains('no connected'));
        expect(age['imageryDate'], isNull);
        expect(f.requests.length, before);
      },
    );
  });

  group('Original voice transcript', () {
    test('VR aliases open and close without starting a conversation', () async {
      final f = Fixture();
      addTearDown(f.projection.dispose);
      expect(
        (await f.projection.voiceTurn(
          'open-vr',
          'Rici, enter VR',
          null,
        ))?['ok'],
        true,
      );
      expect(f.projection.isOpen, true);
      expect(
        (await f.projection.voiceTurn('close-vr', 'Close VR', null))?['ok'],
        true,
      );
      expect(f.projection.isOpen, false);
      expect(f.starts, 0);
      expect(f.stops, 0);
      for (final phrase in [
        'Do not open VR',
        'How do I enter VR?',
        '"Open VR" is an example',
      ]) {
        await f.projection.voiceTurn(phrase, phrase, {'action': 'open'});
      }
      expect(f.opens, 1);
    });

    test('explicit address display preserves the full original address and confirmation', () async {
      const address = '14360 Jupiter Rd, Apt 4B, Brooklyn, NY 10012';
      for (final phrase in [
        'Rici, show me $address',
        'Please show $address in 3D.',
        'Risi, could you please show me $address in 3-D?',
      ]) {
        final queries = <String>[];
        final f = Fixture(
          request: (method, path, body) async {
            if (path.endsWith('/config')) return config;
            queries.add(body!['query'] as String);
            return {
              'candidates': [place],
            };
          },
        );
        addTearDown(f.projection.dispose);
        await f.projection.voiceTurn('show-address', phrase, {
          'action': 'search',
          'value': 'Brooklyn',
        });
        expect(queries, [address], reason: phrase);
        expect(f.projection.isOpen, true);
        expect(f.projection.snapshot['selectedPlace'], isNull);
        expect((f.projection.snapshot['camera'] as Map)['operation'], 'reset');
        expect(f.projection.snapshot['candidates'], hasLength(1));
        await f.projection.voiceTurn(
          'confirm-address',
          'Yes that is the place',
          null,
        );
        expect(
          (f.projection.snapshot['selectedPlace'] as Map)['userQuery'],
          address,
        );
        expect((f.projection.snapshot['camera'] as Map)['operation'], 'flyTo');
        expect(f.starts, 0);
      }
    });

    test(
      'address display is recognized without model tool arguments',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        final result = await f.projection.voiceTurn(
          'show-local',
          'Show 10 Downing Street, London SW1A 2AA in 3D',
          null,
        );
        expect(result?['ok'], true);
        expect(
          (f.projection.snapshot['candidates'] as List).single['userQuery'],
          '10 Downing Street, London SW1A 2AA',
        );
        expect(f.projection.snapshot['selectedPlace'], isNull);
      },
    );

    test(
      'street names containing live or research words remain addresses',
      () async {
        final queries = <String>[];
        final f = Fixture(
          request: (method, path, body) async {
            if (path.endsWith('/config')) return config;
            queries.add(body!['query'] as String);
            return {
              'candidates': [place],
            };
          },
        );
        addTearDown(f.projection.dispose);
        const addresses = [
          '123 Live Oak Road, Live Oak, FL 32060',
          '10 New Street, New York, NY 10004',
          '45 History Lane, Apt 2B, London SW1A 2AA',
          '123 Main Street, Newport News, VA 23601',
          '123 Main Street Newport News VA 23601',
        ];
        for (final address in addresses) {
          final result = await f.projection.voiceTurn(
            address,
            'Show me $address',
            null,
          );
          expect(result?['ok'], true, reason: address);
        }
        expect(queries, addresses);
        expect(f.projection.snapshot['selectedPlace'], isNull);
      },
    );

    test(
      'show requests for research or media cannot become address lookups',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        f.projection.open();
        const phrases = [
          'Show me 3 facts about 10 Downing Street',
          'Show me 3 photos of 10 Downing Street',
          'Show me 10 Downing Street history',
          'Show me 10 Downing Street, history',
          'Show me 10 Downing Street history of the street',
          'Show me 10 Downing Street, history of the street',
          'Show me 3 buildings in Downing Street',
          'Show me 3D printing examples',
          'Do not show me 10 Downing Street',
          'How do I show 10 Downing Street in 3D?',
          '"Show me 10 Downing Street" is an example',
        ];
        for (final phrase in phrases) {
          await f.projection.voiceTurn(phrase, phrase, {
            'action': 'search',
            'value': '10 Downing Street',
          });
        }
        expect(f.requests.where((path) => path.endsWith('/resolve')), isEmpty);
        expect(f.projection.snapshot['selectedPlace'], isNull);
      },
    );

    test(
      'live camera address requests keep the explicit unavailable response',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        f.projection.open();
        for (final phrase in [
          'Show me a live view of 10 Downing Street',
          'Show me 10 Downing Street live camera imagery',
          'Show me 10 Downing Street live camera on the road',
          'Show me 10 Downing Street, live camera on the road',
          'Show 10 Downing Street real-time video in 3D',
        ]) {
          final result = await f.projection.voiceTurn(phrase, phrase, {
            'action': 'search',
            'value': '10 Downing Street',
          });
          expect(result?['isLive'], false);
          expect(
            result?['answer'],
            contains('no connected, permitted live camera'),
          );
        }
        expect(f.requests.where((path) => !path.endsWith('/config')), isEmpty);
        expect(f.projection.snapshot['selectedPlace'], isNull);
      },
    );

    test('existing Risi and Ree-see aliases can open projection', () async {
      for (final alias in ['Risi', 'Ree-see', 'Ree see']) {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        final result = await f.projection.voiceTurn(
          'alias-open',
          '$alias, project virtual reality',
          {'action': 'open', 'value': ''},
        );
        expect(result?['handled'], true, reason: alias);
        expect(f.projection.isOpen, true, reason: alias);
        expect(f.opens, 1);
        expect(f.starts, 0);
      }
    });

    test('remember this about this place saves the original note with aliases', () async {
      for (final alias in ['Rici', 'Risi', 'Ree-see']) {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        await f.select();
        final transcript =
            '$alias, please remember this about this place: meet here next week';
        final result = await f.projection.voiceTurn('alias-save', transcript, {
          'action': 'savePlace',
          'value': 'An invented note from tool arguments',
        });
        expect(result?['saved'], true, reason: alias);
        expect(f.saves, hasLength(1));
        expect(f.saves.single['fromVoice'], true);
        expect(f.saves.single['text'], contains(transcript));
        expect(f.saves.single['text'], contains('Place ID: place-test'));
        expect(f.saves.single['text'], isNot(contains('An invented note')));
      }
    });

    test(
      'aliases do not turn negated or hypothetical place notes into saves',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        await f.select();
        const phrases = [
          'Risi, do not remember this about this place',
          'Ree-see, how do I remember this about this place?',
          'Ree see, what happens if I say remember this about this place?',
        ];
        for (var i = 0; i < phrases.length; i++) {
          await f.projection.voiceTurn('alias-negative-$i', phrases[i], {
            'action': 'savePlace',
            'value': 'Save anyway',
          });
        }
        expect(f.saves, isEmpty);
      },
    );

    test(
      'explicit projection command opens once with duplicate turn IDs',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        await f.projection.voiceTurn(
          'turn-1',
          'Rici, project virtual reality',
          {'action': 'open', 'value': ''},
        );
        await f.projection.voiceTurn(
          'turn-1',
          'Rici, project virtual reality',
          {'action': 'open', 'value': ''},
        );
        expect(f.opens, 1);
      },
    );

    test('tool arguments cannot authorize an unrelated place save', () async {
      final f = Fixture();
      addTearDown(f.projection.dispose);
      await f.select();
      await f.projection.voiceTurn('turn-2', 'What is this building?', {
        'action': 'savePlace',
        'value': 'I live here',
      });
      expect(f.saves, isEmpty);
    });

    test('ordinary conversation and ordinary memory pass through', () async {
      final f = Fixture();
      addTearDown(f.projection.dispose);
      await f.select();
      expect(
        await f.projection.voiceTurn('t-a', 'Tell me a joke', null),
        isNull,
      );
      expect(
        await f.projection.voiceTurn(
          't-b',
          'Rici remember this: I enjoy walking',
          null,
        ),
        isNull,
      );
      expect(
        await f.projection.voiceTurn(
          't-build',
          'How do I build a website?',
          null,
        ),
        isNull,
      );
      expect(f.saves, isEmpty);
    });

    test('negative, quoted and hypothetical place saves never write', () async {
      final f = Fixture();
      addTearDown(f.projection.dispose);
      await f.select();
      const phrases = [
        'Do not save this place',
        "Don't remember this address",
        'How do I save this place?',
        'What happens if I say remember this place?',
        'Rici, do not remember this place',
        'Rici, could you explain how to save this place?',
        '"Remember this place" is an example command',
      ];
      for (var i = 0; i < phrases.length; i++) {
        await f.projection.voiceTurn('negative-$i', phrases[i], {
          'action': 'savePlace',
          'value': 'Untrusted model proposal',
        });
      }
      expect(f.saves, isEmpty);
    });

    test(
      'model substring cannot drop street and postal code from the address',
      () async {
        final queries = <String>[];
        final f = Fixture(
          request: (method, path, body) async {
            if (path.endsWith('/config')) return config;
            queries.add(body!['query'] as String);
            return {
              'candidates': [place],
            };
          },
        );
        addTearDown(f.projection.dispose);
        await f.projection.voiceTurn(
          'address-1',
          'Rici, go to 14360 Jupiter Rd, Brooklyn, 10012',
          {'action': 'search', 'value': 'Brooklyn'},
        );
        expect(
          queries.single.toLowerCase(),
          '14360 jupiter rd, brooklyn, 10012',
        );
        expect(f.projection.snapshot['selectedPlace'], isNull);
      },
    );

    test(
      'a street number is not mistaken for a displayed result number',
      () async {
        final queries = <String>[];
        final f = Fixture(
          request: (method, path, body) async {
            if (path.endsWith('/config')) return config;
            queries.add(body!['query'] as String);
            return {
              'candidates': [place],
            };
          },
        );
        addTearDown(f.projection.dispose);
        f.projection.open();
        await f.projection.search('Previous destination');
        await f.projection.voiceTurn('address-2', 'Go to 1 Main Street', {
          'action': 'search',
          'value': '1 Main Street',
        });
        expect(queries.last.toLowerCase(), '1 main street');
        expect(f.projection.snapshot['selectedPlace'], isNull);
      },
    );

    test(
      'camera commands require a direct request and accept the example phrase',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        await f.select();
        final originalCamera = f.projection.snapshot['camera'];
        await f.projection.voiceTurn('camera-negative', 'Do not zoom in', {
          'action': 'camera',
          'value': 'closer',
        });
        expect(f.projection.snapshot['camera'], originalCamera);
        await f.projection.voiceTurn('camera-1', 'Go closer to the building', {
          'action': 'camera',
          'value': 'closer',
        });
        expect((f.projection.snapshot['camera'] as Map)['operation'], 'closer');
      },
    );

    test(
      'voice can choose a displayed result without another address lookup',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        f.projection.open();
        await f.projection.search('My destination');
        final count = f.requests.length;
        await f.projection.voiceTurn('t-c', 'Go to the first result', {
          'action': 'search',
          'value': 'the first result',
        });
        expect(
          (f.projection.snapshot['selectedPlace'] as Map)['id'],
          'place-test',
        );
        expect(f.requests.length, count);
      },
    );

    test(
      'explicit selected-place note saves only user words and place ID',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        await f.select();
        await f.projection.voiceTurn(
          'save-1',
          'Remember this place for my next visit',
          {'action': 'savePlace', 'value': 'Made-up preference'},
        );
        await f.projection.voiceTurn(
          'save-1',
          'Remember this place for my next visit',
          {'action': 'savePlace', 'value': ''},
        );
        expect(f.saves, hasLength(1));
        expect(f.saves.single['fromVoice'], true);
        expect(f.saves.single['text'], contains('My destination'));
        expect(f.saves.single['text'], contains('Place ID: place-test'));
        expect(f.saves.single['text'], isNot(contains('Made-up preference')));
        expect(
          f.saves.single['text'],
          isNot(contains('A verified fixture address')),
        );
      },
    );
  });

  group('Hands-free destinations and continuous zoom', () {
    test('ordinary lookup requests remain conversation outside a destination prompt', () async {
      final f = Fixture();
      addTearDown(f.projection.dispose);
      const phrases = [
        'Look up quantum mechanics',
        'Find a good restaurant recipe',
        'Explore relativity',
        'Search for cooking tips',
        'Show me quantum mechanics',
      ];
      for (final phrase in phrases) {
        expect(
          f.projection.recognizesVoiceControl(phrase),
          false,
          reason: phrase,
        );
      }
      await f.select();
      for (final phrase in phrases) {
        expect(
          f.projection.recognizesVoiceControl(phrase),
          false,
          reason: phrase,
        );
      }
      expect(f.projection.recognizesVoiceControl('Go to Paris'), true);
      expect(
        f.projection.recognizesVoiceControl('Find the Eiffel Tower'),
        true,
      );
    });

    test(
      'landmark and compound VR requests preserve the spoken destination',
      () async {
        for (final phrase in [
          'Rici, show me San Francisco Ferry Building, San Francisco, CA',
          'Open VR and show me San Francisco Ferry Building, San Francisco, CA',
          'Open virtual reality and take me to San Francisco Ferry Building, San Francisco, CA',
        ]) {
          final queries = <String>[];
          final f = Fixture(
            request: (method, path, body) async {
              if (path.endsWith('/config')) return config;
              queries.add(body!['query'] as String);
              return {
                'candidates': [place],
              };
            },
          );
          addTearDown(f.projection.dispose);
          expect(f.projection.recognizesVoiceControl(phrase), true);
          await f.projection.voiceTurn('landmark', phrase, null);
          expect(queries, ['San Francisco Ferry Building, San Francisco, CA']);
          expect(f.projection.snapshot['selectedPlace'], isNull);
          expect(f.projection.recognizesVoiceControl("That's it"), true);
          await f.projection.voiceTurn('confirmation', "That's it", null);
          expect(
            (f.projection.snapshot['selectedPlace'] as Map)['id'],
            place['id'],
          );
          expect(f.starts, 0);
          expect(f.stops, 0);
        }
      },
    );

    test('a prompted bare landmark works but ordinary conversation is not a lookup', () async {
      final f = Fixture();
      addTearDown(f.projection.dispose);
      await f.projection.voiceTurn('open', 'Open VR', null);
      for (final phrase in [
        'Tell me a joke',
        'How old is the Ferry Building?',
        'Remember I like San Francisco',
        'Do not go to the Ferry Building',
      ]) {
        expect(
          f.projection.recognizesVoiceControl(phrase),
          false,
          reason: phrase,
        );
      }
      expect(
        f.projection.recognizesVoiceControl('San Francisco Ferry Building'),
        true,
      );
      await f.projection.voiceTurn(
        'bare',
        'San Francisco Ferry Building',
        null,
      );
      expect(
        f.requests.where((path) => path.endsWith('/resolve')),
        hasLength(1),
      );
      await f.projection.voiceTurn('select', 'First one', null);
      expect(f.projection.snapshot['selectedPlace'], isNotNull);
      expect(
        f.projection.recognizesVoiceControl('San Francisco Ferry Building'),
        false,
      );
    });

    test(
      'camera stop holds the view and keeps the conversation active',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        await f.select();
        f.projection.receiveVoice({'type': 'voice', 'phase': 'listening'});
        await f.projection.voiceTurn('keep-in', 'Keep zooming in', null);
        expect(
          (f.projection.snapshot['camera'] as Map)['operation'],
          'zoomInContinuous',
        );
        expect(f.projection.recognizesVoiceControl('Stop'), true);
        await f.projection.voiceTurn('stop-camera', 'Stop zooming', null);
        expect(
          (f.projection.snapshot['camera'] as Map)['operation'],
          'stopCamera',
        );
        expect((f.projection.snapshot['voice'] as Map)['active'], true);
        expect(f.stops, 0);
        expect(f.projection.recognizesVoiceControl('Stop'), false);
        await f.projection.voiceTurn('keep-out', 'Keep zooming out', null);
        expect(
          (f.projection.snapshot['camera'] as Map)['operation'],
          'zoomOutContinuous',
        );
        await f.projection.voiceTurn('hold', 'Hold this view', null);
        expect(
          (f.projection.snapshot['camera'] as Map)['operation'],
          'stopCamera',
        );
      },
    );

    test('repeated zoom is not capped by a command count and duplicates never move twice', () async {
      final f = Fixture();
      addTearDown(f.projection.dispose);
      await f.select();
      final start = (f.projection.snapshot['camera'] as Map)['sequence'] as int;
      for (var i = 0; i < 80; i++) {
        expect(
          (await f.projection.voiceTurn('step-$i', 'Zoom in', null))?['ok'],
          true,
        );
      }
      expect((f.projection.snapshot['camera'] as Map)['sequence'], start + 80);
      await f.projection.voiceTurn('step-79', 'Zoom in', {
        'action': 'camera',
        'value': 'closer',
      });
      expect((f.projection.snapshot['camera'] as Map)['sequence'], start + 80);
      expect(
        f.projection.recognizesVoiceControl('Do not keep zooming in'),
        false,
      );
      expect(
        f.projection.recognizesVoiceControl('How do I stop zooming?'),
        false,
      );
      for (final phrase in [
        'Zoom in on the history of this building',
        'Zoom in, no, zoom out',
        'Turn left but do not move the view',
      ]) {
        expect(
          f.projection.recognizesVoiceControl(phrase),
          false,
          reason: phrase,
        );
      }
      expect(f.projection.recognizesVoiceControl('Stop moving the view'), true);
    });

    test(
      'pause, stop, background and errors cancel continuous camera motion',
      () async {
        for (final event in [
          {'type': 'voice', 'phase': 'pausing'},
          {'type': 'voice', 'phase': 'paused'},
          {'type': 'voice', 'phase': 'stopping'},
          {'type': 'voice', 'phase': 'complete'},
          {'type': 'voice', 'phase': 'error'},
          {'type': 'appLifecycle', 'active': false},
        ]) {
          final f = Fixture();
          addTearDown(f.projection.dispose);
          await f.select();
          f.projection.camera('zoomInContinuous');
          f.projection.receiveVoice(event);
          expect(
            (f.projection.snapshot['camera'] as Map)['operation'],
            'stopCamera',
            reason: '$event',
          );
          expect(f.stops, 0);
        }
        final f = Fixture();
        addTearDown(f.projection.dispose);
        await f.select();
        f.projection.camera('zoomInContinuous');
        await f.projection.dispatch('rendererReady', {'status': 'error'});
        expect(
          (f.projection.snapshot['camera'] as Map)['operation'],
          'stopCamera',
        );
        f.projection.receiveVoice({'type': 'appLifecycle', 'active': false});
        expect(f.projection.camera('zoomInContinuous')['ok'], false);
      },
    );

    test(
      'new searches stop movement before a new destination is confirmed',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        await f.select();
        f.projection.camera('zoomInContinuous');
        await f.projection.search('A different destination');
        expect(
          (f.projection.snapshot['camera'] as Map)['operation'],
          'stopCamera',
        );
        expect(f.projection.snapshot['selectedPlace'], isNull);
        expect(f.projection.snapshot['candidates'], isNotEmpty);
      },
    );

    test(
      'only the current camera outcome can stop motion or report its limit',
      () async {
        final f = Fixture();
        addTearDown(f.projection.dispose);
        await f.select();
        f.projection.camera('zoomInContinuous');
        final old = (f.projection.snapshot['camera'] as Map)['sequence'];
        f.projection.camera('zoomOutContinuous');
        final current = (f.projection.snapshot['camera'] as Map)['sequence'];
        await f.projection.dispatch('cameraStatus', {
          'sequence': old,
          'state': 'limit',
          'reason': 'closest',
        });
        expect(
          (f.projection.snapshot['camera'] as Map)['operation'],
          'zoomOutContinuous',
        );
        await f.projection.dispatch('cameraStatus', {
          'sequence': current,
          'state': 'limit',
          'reason': 'farthest',
        });
        expect(
          (f.projection.snapshot['camera'] as Map)['operation'],
          'stopCamera',
        );
        expect(f.projection.snapshot['notice'], contains('farthest view'));
        f.projection.camera('zoomInContinuous');
        await f.projection.dispatch('cameraStatus', {
          'sequence': (f.projection.snapshot['camera'] as Map)['sequence'],
          'state': 'limit',
          'reason': 'closest',
        });
        expect(
          f.projection.snapshot['notice'],
          contains('More detail depends on the imagery'),
        );
      },
    );
  });

  group('Projection bridge', () {
    String message(
      String id,
      String action, {
      String nonce = 'per-view-secret',
    }) =>
        jsonEncode({'id': id, 'nonce': nonce, 'action': action, 'payload': {}});
    test('requires a nonce and a narrow action; rejects replays', () {
      final bridge = BrainProjectionBridge('per-view-secret');
      expect(
        bridge.accept(message('1', 'search', nonce: 'iframe-does-not-know')),
        isNull,
      );
      expect(bridge.accept(message('1', 'deleteMemory')), isNull);
      expect(bridge.accept(message('1', 'room')), isNotNull);
      bridge.complete('1');
      expect(bridge.accept(message('1', 'room')), isNull);
    });
    test('close and Stop remain available when ordinary requests are full', () {
      final bridge = BrainProjectionBridge('per-view-secret');
      for (var i = 1; i <= 8; i++) {
        expect(bridge.accept(message('$i', 'ask')), isNotNull);
      }
      expect(bridge.accept(message('9', 'ask')), isNull);
      expect(bridge.accept(message('10', 'stopVoice')), isNotNull);
      expect(bridge.accept(message('11', 'close')), isNotNull);
      expect(
        bridge.accept(
          jsonEncode({
            'id': '12',
            'nonce': 'per-view-secret',
            'action': 'camera',
            'payload': {'operation': 'stopCamera'},
          }),
        ),
        isNotNull,
      );
    });
  });
}
