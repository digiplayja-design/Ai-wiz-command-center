import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_live_turns.dart';
import 'package:korlix_brain/brain_projection.dart';
import 'package:korlix_brain/brain_voice_turns.dart';

const _config = {
  'rendererUrl': 'https://api.example.com/brain-projection/earth.html',
  'mapAvailable': true,
  'geocodingAvailable': true,
  'answersAvailable': false,
};
const _place = {
  'id': 'fixture-property',
  'label': 'Fixture property',
  'address': 'A fixture address',
  'latitude': 40.71,
  'longitude': -74.0,
};
const _answer = {
  'answer': 'An ordinary answer.',
  'model': 'gpt-6.1-sol',
  'reasoningEffort': 'max',
};

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _PropertyFixture {
  _PropertyFixture({ProjectionRequest? request}) {
    projection = BrainProjection(
      backendUrl: 'https://api.example.com',
      request:
          request ??
          (_, path, _) async => path.endsWith('/config')
              ? _config
              : {
                  'candidates': [_place],
                },
      onOpen: () => opens++,
      onClose: () => closes++,
      onStartVoice: () async {
        voiceStarts++;
      },
      onStopVoice: () async {
        voiceStops++;
      },
      onSave: (_, _) async => true,
    );
  }
  late final BrainProjection projection;
  int opens = 0, closes = 0, voiceStarts = 0, voiceStops = 0;
  Map get camera => projection.snapshot['camera'] as Map;
  Map get feedback => projection.snapshot['lastVoiceCommand'] as Map;

  Future<void> select() async {
    projection.open();
    await projection.search('10 Fixture Street');
    projection.select(_place['id'] as String);
    await ready();
  }

  Future<void> ready() async {
    await projection.dispatch('rendererReady', {
      'status': 'ready',
      'sequence': camera['sequence'],
      'viewMode': camera['viewMode'],
    });
  }
}

void main() {
  test('the reported polite Projection request opens and closes from Home', () async {
    const phrases = [
      'Rici can you open projection mode',
      'Rici, can you open projection mode?',
      'Rici. Can you open projection mode?',
      'Hey Rici, could you please open projection mode for me?',
      'Please, Resee, can you open Projection Mode?',
      'Could you, Rici, open the projection mode?',
      'Risi, would you open projection mode, please.',
      'Ree-see, open projection mode.',
      'Reese, can you open projection mode?',
      'Rici, I want you to open projection mode.',
      'Rici, I would like you to open projection mode.',
      'Open projection mode, Rici.',
    ];
    for (final phrase in phrases) {
      final f = _PropertyFixture();
      addTearDown(f.projection.dispose);
      expect(f.projection.isOpen, false);
      expect(f.projection.recognizesVoiceControl(phrase), true, reason: phrase);

      // The transcript itself authorizes entry; no model tool call is needed.
      final opened = await f.projection.voiceTurn('open', phrase, null);
      expect(opened?['handled'], true, reason: phrase);
      expect(opened?['ok'], true, reason: phrase);
      expect(f.projection.isOpen, true, reason: phrase);
      expect(f.opens, 1, reason: phrase);
      expect(f.feedback['action'], 'Open Projection', reason: phrase);

      const close = 'Rici, can you close projection mode?';
      expect(f.projection.recognizesVoiceControl(close), true);
      final closed = await f.projection.voiceTurn('close', close, null);
      expect(closed?['handled'], true);
      expect(f.projection.isOpen, false);
      expect(f.closes, 1);
      expect(f.voiceStarts, 0, reason: 'Entry must retain the current session');
      expect(f.voiceStops, 0, reason: 'Exit must retain the current session');
    }
  });

  test('Projection questions and negated or quoted entry requests stay conversational', () async {
    const phrases = [
      'Rici can you explain how to open projection mode?',
      'Rici, can you tell me how to open projection mode?',
      'How do I open projection mode?',
      'What is projection mode?',
      'Rici, do not open projection mode',
      'Please, Resee, don’t open projection mode',
      'Rici, could you never open projection mode?',
      'I do not want you to open projection mode, Rici',
      'Rici, remember that I want to open projection mode',
      'Save the words open projection mode',
      '"Rici can you open projection mode" is an example',
      '“Rici can you open projection mode” is an example',
      'Rici, open projection mode, actually do not open it',
    ];
    for (final initiallyOpen in [false, true]) {
      final f = _PropertyFixture();
      addTearDown(f.projection.dispose);
      if (initiallyOpen) f.projection.open();
      final before = Map.of(f.camera);
      for (final phrase in phrases) {
        expect(f.projection.recognizesVoiceControl(phrase), false, reason: phrase);
        await f.projection.voiceTurn(phrase, phrase, {'action': 'open', 'value': ''});
        expect(f.projection.isOpen, initiallyOpen, reason: phrase);
        expect(f.camera, before, reason: phrase);
      }
      expect(f.opens, initiallyOpen ? 1 : 0);
      expect(f.voiceStarts, 0);
      expect(f.voiceStops, 0);
    }
  });

  test(
    'natural Rici names and narrow polite camera phrases control the view',
    () async {
      final f = _PropertyFixture();
      addTearDown(f.projection.dispose);
      await f.select();
      const closer = [
        'Reese, zoom in',
        'Reece, zoom in',
        'Resee, zoom in',
        'Risee, zoom in',
        'Ree See, zoom in',
        'Rici. Zoom in.',
        'Hey, Rici, zoom in',
        'Please, zoom in.',
        'Rici, zoom in on the property',
        'Go closer to the building',
        'Zoom in a little bit',
        'Could you please zoom in?',
        'Can you zoom in for me?',
        'Please, Rici, zoom in',
        'Could you, Resee, please zoom in?',
        'Zoom in, Rici',
        'Zoom in Resee',
        'Zoom in, please, Rici.',
        'Rici, I want you to zoom in',
        'Rici, I would like you to zoom in',
        'Rici, I’d like you to zoom in',
        'Rici, can you zoom into the property?',
        'Hey, please, Resee, could you zoom into this building for me?',
      ];
      var index = 0;
      for (final phrase in closer) {
        final before = f.camera['sequence'] as int;
        expect(
          f.projection.recognizesVoiceControl(phrase),
          true,
          reason: phrase,
        );
        await f.projection.voiceTurn('phrase-${index++}', phrase, null);
        expect(f.camera['operation'], 'closer', reason: phrase);
        expect(f.camera['sequence'], before + 1);
        expect(f.feedback['heard'], phrase);
        expect(f.feedback['action'], 'Zoom in');
        expect(f.feedback['status'], 'sent');
      }
      await f.projection.voiceTurn(
        'continuous',
        'Please, Resee, keep zooming in on the building',
        null,
      );
      expect(f.camera['operation'], 'zoomInContinuous');
      await f.projection.voiceTurn('stop', 'Stop zooming in, Resee.', null);
      expect(f.camera['operation'], 'stopCamera');
    },
  );

  test('questions, memories, negation and corrections cannot become camera controls', () async {
    final f = _PropertyFixture();
    addTearDown(f.projection.dispose);
    await f.select();
    const phrases = [
      'Reese, do not zoom in',
      'Rici, zoom in, no, zoom out',
      'Rici, open VR, actually, do not open it',
      'Close VR, no, keep it open',
      'How do I zoom in on the property?',
      'Zoom in on the history of this building',
      'Look up quantum mechanics',
      'Remember that I like Street View',
      'Show me how Street View works',
      'Please, Rici, don’t zoom in',
      'Resee, I want you to explain how to zoom in',
      'I do not want you to zoom in, Rici',
      'Rici, could you never zoom in?',
      'Rici, I want you to remember to zoom in',
      'Could you explain “zoom in”, Resee?',
      'Resee, zoom into the history of this property',
      'Please, Rici, zoom in, actually zoom out',
    ];
    final before = Map.of(f.camera);
    for (final phrase in phrases) {
      expect(
        f.projection.recognizesVoiceControl(phrase),
        false,
        reason: phrase,
      );
    }
    expect(f.camera, before);
  });

  test(
    'assistant wrappers preserve the complete destination and confirmation',
    () async {
      final queries = <String>[];
      final f = _PropertyFixture(
        request: (_, path, payload) async {
          if (path.endsWith('/config')) return _config;
          queries.add(payload!['query'] as String);
          return {
            'candidates': [_place],
          };
        },
      );
      addTearDown(f.projection.dispose);
      f.projection.open();
      const address = '20 Resee Street, Unit 4, Reece, NY 10012';
      await f.projection.voiceTurn(
        'address',
        'Please, Resee, can you go to $address?',
        null,
      );
      expect(queries, [address]);
      expect(f.projection.snapshot['selectedPlace'], isNull);
      await f.projection.voiceTurn('confirm', 'That’s it, Resee.', null);
      expect(
        (f.projection.snapshot['selectedPlace'] as Map)['id'],
        _place['id'],
      );
      expect(f.camera['viewMode'], 'street');
    },
  );

  test(
    'missing speech transcript replaces stale command feedback explicitly',
    () async {
      final f = _PropertyFixture();
      addTearDown(f.projection.dispose);
      await f.select();
      await f.projection.voiceTurn('earlier', 'Resee, zoom in', null);
      final before = Map.of(f.camera);
      f.projection.receiveVoice({
        'type': 'voiceNotice',
        'code': 'transcription_timeout',
        'message':
            'The spoken words did not arrive. Please repeat the view command.',
      });
      expect(f.feedback['heard'], isEmpty);
      expect(f.feedback['action'], 'Speech recognition');
      expect(f.feedback['status'], 'failed');
      expect(f.feedback['result'], contains('Please repeat'));
      expect(f.camera, before);
    },
  );

  test('Street View is the default and explicit mode switches work through renderer failures', () async {
    final f = _PropertyFixture();
    addTearDown(f.projection.dispose);
    expect(f.camera['viewMode'], 'street');
    await f.select();
    expect(f.camera['viewMode'], 'street');
    await f.projection.dispatch('rendererReady', {'status': 'error'});
    expect(f.projection.camera('earthView')['ok'], true);
    expect(f.camera['operation'], 'flyTo');
    expect(f.camera['viewMode'], 'earth');
    expect(f.camera['latitude'], _place['latitude']);
    expect(f.projection.camera('closer')['ok'], false);
    await f.ready();
    expect(f.projection.camera('closer')['ok'], true);
    expect(f.camera['viewMode'], 'earth');
    await f.projection.dispatch('rendererReady', {'status': 'loading'});
    expect(f.projection.camera('streetView')['ok'], true);
    expect(f.camera['viewMode'], 'street');
    f.projection.camera('earthView');
    await f.projection.search('20 Another Street');
    f.projection.select(_place['id'] as String);
    expect(
      f.camera['viewMode'],
      'street',
      reason: 'A new property starts at street level.',
    );
    expect(
      f.projection.camera('closer')['ok'],
      false,
      reason: 'A newly selected property must finish loading before relative movement.',
    );
    expect(f.projection.camera('stopCamera')['ok'], true);
    f.projection.camera('earthView');
    f.projection.close();
    f.projection.open();
    expect(
      f.camera['viewMode'],
      'earth',
      reason: 'Reopening preserves an explicit view choice.',
    );
  });

  test('front-of-property and overhead phrases choose imagery without claiming live video', () async {
    final f = _PropertyFixture();
    addTearDown(f.projection.dispose);
    await f.select();
    const phrases = {
      'Reese, show street view': 'street',
      'Show the front of the property': 'street',
      'Show me the front of this building': 'street',
      'Face the building': 'street',
      'Show overhead': 'earth',
      'Show the overhead map': 'earth',
      'Show me the 3D map': 'earth',
    };
    var index = 0;
    for (final entry in phrases.entries) {
      expect(
        f.projection.recognizesVoiceControl(entry.key),
        true,
        reason: entry.key,
      );
      final result = await f.projection.voiceTurn(
        'view-${index++}',
        entry.key,
        null,
      );
      expect(result?['ok'], true);
      expect(f.camera['operation'], 'flyTo');
      expect(f.camera['viewMode'], entry.value);
      expect(f.feedback['status'], 'sent');
    }
    final live = await f.projection.voiceTurn(
      'live',
      'Show me a live view of this address.',
      null,
    );
    expect(live?['isLive'], false);
    expect(live?['answer'], contains('not a live feed'));
  });

  test('old mode readiness cannot enable a newer view and feedback follows renderer status', () async {
    final f = _PropertyFixture();
    addTearDown(f.projection.dispose);
    await f.select();
    await f.projection.voiceTurn('earth', 'Show overhead', null);
    final old = Map.of(f.camera);
    await f.projection.voiceTurn('street', 'Show street view', null);
    await f.projection.dispatch('rendererReady', {
      'status': 'ready',
      'sequence': old['sequence'],
      'viewMode': old['viewMode'],
    });
    expect(f.projection.camera('closer')['ok'], false);
    expect(f.feedback['status'], 'sent');
    await f.ready();
    expect(f.feedback['status'], 'completed');
    expect(f.feedback['result'], 'Recorded Street View is ready.');
    await f.projection.voiceTurn('zoom', 'Reese, zoom in', null);
    await f.projection.dispatch('rendererReady', {
      'status': 'error',
      'sequence': f.camera['sequence'],
      'viewMode': 'street',
    });
    expect(f.feedback['status'], 'failed');
    expect(f.feedback['result'], contains('could not load'));
  });

  test(
    'recognition and voice notices are visible in the Projection snapshot',
    () async {
      final f = _PropertyFixture();
      addTearDown(f.projection.dispose);
      await f.select();
      f.projection.receiveVoice({
        'type': 'transcript',
        'role': 'you',
        'text': 'Reese, zoom in',
      });
      expect(f.feedback['heard'], 'Reese, zoom in');
      expect(f.feedback['action'], 'Zoom in');
      expect(f.feedback['status'], 'heard');
      await f.projection.voiceTurn('current', 'Reese, zoom in', null);
      final latest = Map.of(f.feedback);
      f.projection.receiveVoice({
        'type': 'transcript',
        'role': 'you',
        'text': 'Old command',
        'current': false,
      });
      expect(f.feedback, latest);
      f.projection.receiveVoice({
        'type': 'voiceNotice',
        'message': 'The spoken acknowledgement could not play.',
      });
      expect(f.feedback['status'], 'failed');
      expect(f.projection.snapshot['notice'], contains('could not play'));
      f.projection.receiveVoice({
        'type': 'voiceNotice',
        'code': 'transcription_failed',
        'message': 'Please repeat that command.',
      });
      expect(f.feedback['heard'], isEmpty);
      expect(f.feedback['action'], 'Speech recognition');
      expect(f.feedback['result'], 'Please repeat that command.');
    },
  );

  test(
    'a late lookup result cannot replace feedback from a newer command',
    () async {
      final result = Completer<Map<String, dynamic>>();
      final f = _PropertyFixture(
        request: (_, path, _) async =>
            path.endsWith('/config') ? _config : result.future,
      );
      addTearDown(f.projection.dispose);
      final search = f.projection.voiceTurn(
        'lookup',
        'Go to 10 Fixture Street',
        null,
      );
      await _flush();
      await f.projection.voiceTurn('hold', 'Stop zooming', null);
      final feedback = Map.of(f.feedback);
      result.complete({
        'candidates': [_place],
      });
      await search;
      expect(f.feedback, feedback);
    },
  );

  test(
    'Live ASR with a real controller moves once and acknowledges once',
    () async {
      final f = _PropertyFixture();
      addTearDown(f.projection.dispose);
      await f.select();
      final sent = <Map<String, dynamic>>[];
      final live = BrainLiveTurns(
        send: (event) async => sent.add(event),
        requestMemory: (_, _) async => throw StateError('No memory request'),
        emit: f.projection.receiveVoice,
        saved: (_) async {},
        isCurrent: () => true,
        reportTiming: (_, _) async {},
        onProjection: f.projection.voiceTurn,
        recognizesProjection: f.projection.recognizesVoiceControl,
      );
      addTearDown(live.dispose);
      final before = f.camera['sequence'] as int;
      live.speechStarted('one');
      live.speechStopped('one');
      live.responseStarted({'id': 'auto-one'});
      live.accept('one', 'Please, Resee, zoom into the property');
      live.accept('one', 'Please, Resee, zoom into the property');
      await live.responseDone({
        'id': 'auto-one',
        'status': 'cancelled',
        'output': <Object>[],
      });
      await _flush();
      expect(f.camera['operation'], 'closer');
      expect(f.camera['sequence'], before + 1);
      expect(
        sent.where((event) => event['type'] == 'response.create'),
        hasLength(1),
      );
      live.speechStarted('old');
      live.speechStarted('new');
      final feedback = Map.of(f.feedback);
      live.accept('old', 'Reese, keep zooming in');
      expect(f.camera['sequence'], before + 1);
      expect(f.feedback, feedback);
      live.transcriptionFailed('old');
      expect(f.feedback, feedback);
      live.transcriptionFailed('new');
      expect(f.feedback['action'], 'Speech recognition');
      expect(f.feedback['status'], 'failed');
    },
  );

  test(
    'Deep Think executes zoom and Stop before a slow ordinary answer finishes',
    () async {
      final f = _PropertyFixture();
      addTearDown(f.projection.dispose);
      await f.select();
      final pending = Completer<Map<String, dynamic>>();
      final requests = <String>[], sent = <Map<String, dynamic>>[];
      final turns = BrainVoiceTurns(
        request: (id, _, _) {
          requests.add(id);
          return pending.future;
        },
        send: (event) async => sent.add(event),
        emit: f.projection.receiveVoice,
        isCurrent: () => true,
        saved: (_) async {},
        onProjection: f.projection.voiceTurn,
        recognizesProjection: f.projection.recognizesVoiceControl,
      );
      addTearDown(turns.dispose);
      turns.speechStarted('question');
      turns.accept('question', 'Explain quantum mechanics');
      await _flush();
      expect(requests, ['question']);
      turns.speechStarted('zoom');
      turns.accept(
        'zoom',
        'Resee, I want you to keep zooming in on the building',
      );
      expect(f.camera['operation'], 'zoomInContinuous');
      await _flush();
      turns.responseStarted({
        'id': 'zoom-ack',
        'metadata': {'brain_epoch': '2'},
      });
      turns.speechStarted('stop');
      turns.accept('stop', 'Stop zooming, Resee');
      final stoppedSequence = f.camera['sequence'];
      expect(f.camera['operation'], 'stopCamera');
      expect(pending.isCompleted, false);
      turns.accept('stop', 'Stop zooming, Resee');
      turns.responseDone('zoom-ack');
      await _flush();
      final acknowledgements = sent
          .where((event) => event['type'] == 'response.create')
          .toList();
      expect(acknowledgements, hasLength(2));
      expect(
        acknowledgements.last['response']['metadata']['brain_turn'],
        'stop',
      );
      pending.complete(_answer);
      await _flush();
      expect(f.camera['sequence'], stoppedSequence);
      expect(requests, ['question']);
      expect(
        sent.where((event) => event['type'] == 'response.create'),
        hasLength(2),
      );
    },
  );

  test('Deep duplicate VAD and stale ASR cannot replay controls or acknowledgements', () async {
    final f = _PropertyFixture();
    addTearDown(f.projection.dispose);
    await f.select();
    final sent = <Map<String, dynamic>>[], requests = <String>[];
    final turns = BrainVoiceTurns(
      request: (id, _, _) async {
        requests.add(id);
        return _answer;
      },
      send: (event) async => sent.add(event),
      emit: f.projection.receiveVoice,
      isCurrent: () => true,
      saved: (_) async {},
      onProjection: f.projection.voiceTurn,
      recognizesProjection: f.projection.recognizesVoiceControl,
    );
    addTearDown(turns.dispose);
    final before = f.camera['sequence'] as int;
    turns.speechStarted('one');
    turns.speechStarted('one');
    turns.accept('one', 'Zoom in a little bit');
    turns.accept('one', 'Zoom in a little bit');
    await _flush();
    expect(f.camera['sequence'], before + 1);
    expect(
      sent.where((event) => event['type'] == 'response.create'),
      hasLength(1),
    );
    turns.speechStarted('old');
    turns.speechStarted('new');
    final feedback = Map.of(f.feedback);
    turns.accept('old', 'Keep zooming in');
    turns.transcriptionFailed('old');
    await _flush();
    expect(f.camera['sequence'], before + 1);
    expect(f.feedback, feedback);
    expect(requests, isEmpty);
    turns.transcriptionFailed('new');
    expect(f.feedback['status'], 'failed');
    expect(f.feedback['action'], 'Speech recognition');
  });
}
