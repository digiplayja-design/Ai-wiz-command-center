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
          'Go to My destination',
          {'action': 'search', 'value': 'My destination'},
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
    });
  });
}
