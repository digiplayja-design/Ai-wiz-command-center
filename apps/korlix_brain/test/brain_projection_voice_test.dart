import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_live_turns.dart';
import 'package:korlix_brain/brain_model.dart';
import 'package:korlix_brain/brain_voice_session.dart';
import 'package:korlix_brain/brain_voice_turns.dart';

const _memoryTool = <String, dynamic>{
  'type': 'function',
  'name': 'remember_in_brain',
  'description': 'Original server memory tool.',
  'parameters': {
    'type': 'object',
    'properties': <String, dynamic>{},
    'additionalProperties': false,
  },
};

Map<String, dynamic> _serverSession() => {
  'model': 'gpt-realtime-2.1',
  'instructions': 'Original Rici instructions. Account memory: Joy is the dog.',
  'reasoning': {'effort': 'low'},
  'tool_choice': 'auto',
  'tools': [_memoryTool],
  'audio': {
    'input': {
      'transcription': {'model': 'gpt-transcribe'},
      'turn_detection': {'type': 'semantic_vad', 'create_response': true},
    },
  },
};

Map<String, dynamic> _ack(Map session) => {
  'type': 'session.updated',
  'session': session,
};

Map<String, dynamic> _projectionCall({
  String response = 'response1',
  String call = 'call1',
  String name = 'control_projection',
  Object? arguments = const {'action': 'open', 'value': ''},
}) => {
  'id': response,
  'status': 'completed',
  'output': [
    {
      'type': 'function_call',
      'name': name,
      'arguments': jsonEncode(arguments),
      'call_id': call,
    },
  ],
};

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('projection session negotiation', () {
    test('legacy Live retains one tool and its original partial update', () {
      final gate = BrainVoiceSessionGate(mode: BrainVoiceMode.live);
      gate.observe({'type': 'session.created', 'session': _serverSession()});
      final update = gate.configuration['session'] as Map;
      expect(update.containsKey('tools'), isFalse);
      expect(update.containsKey('instructions'), isFalse);
      expect(gate.observe(_ack(_serverSession())), BrainSessionAction.ready);
      expect(
        gate.observe(
          _ack({
            ..._serverSession(),
            'tools': [_memoryTool, BrainVoiceSessionGate.projectionTool],
          }),
        ),
        BrainSessionAction.reject,
      );
    });

    test(
      'enabled Live appends to the exact server memory and instructions',
      () {
        final server = _serverSession();
        final gate = BrainVoiceSessionGate(
          mode: BrainVoiceMode.live,
          projectionEnabled: true,
        );
        expect(
          gate.observe({'type': 'session.created', 'session': server}),
          BrainSessionAction.configure,
        );
        final update = gate.configuration['session'] as Map;
        expect((update['tools'] as List).first, _memoryTool);
        expect((update['tools'] as List).length, 2);
        expect(
          update['instructions'],
          startsWith('${server['instructions']}\n\n'),
        );
        expect(update.containsKey('model'), isFalse);
        expect(
          gate.observe(_ack({...server, ...update})),
          BrainSessionAction.ready,
        );
        final parameters =
            BrainVoiceSessionGate.projectionTool['parameters'] as Map;
        expect(parameters['required'], ['action', 'value']);
        expect(parameters['additionalProperties'], isFalse);
      },
    );

    test('default created event waits for server context before appending', () {
      final gate = BrainVoiceSessionGate(
        mode: BrainVoiceMode.live,
        projectionEnabled: true,
      );
      gate.observe({'type': 'session.created', 'session': {}});
      expect(
        (gate.configuration['session'] as Map).containsKey('tools'),
        isFalse,
      );
      expect(
        gate.observe(_ack(_serverSession())),
        BrainSessionAction.configure,
      );
      expect(
        gate.observe(
          _ack({..._serverSession(), ...gate.configuration['session'] as Map}),
        ),
        BrainSessionAction.ready,
      );
    });

    test(
      'enabled gate rejects missing, extra or duplicate tools and lost context',
      () {
        final gate = BrainVoiceSessionGate(
          mode: BrainVoiceMode.live,
          projectionEnabled: true,
        )..observe({'type': 'session.created', 'session': _serverSession()});
        final ready = {
          ..._serverSession(),
          ...gate.configuration['session'] as Map,
        };
        for (final tools in [
          [_memoryTool],
          [BrainVoiceSessionGate.projectionTool],
          [_memoryTool, _memoryTool],
          [
            _memoryTool,
            BrainVoiceSessionGate.projectionTool,
            {'name': 'delete_all'},
          ],
        ]) {
          expect(
            gate.observe(_ack({...ready, 'tools': tools})),
            BrainSessionAction.reject,
          );
        }
        expect(
          gate.observe(_ack({...ready, 'instructions': 'Lost memory context'})),
          BrainSessionAction.reject,
        );
      },
    );

    test(
      'no server instructions means projection negotiation fails closed',
      () {
        final gate = BrainVoiceSessionGate(
          mode: BrainVoiceMode.live,
          projectionEnabled: true,
        )..observe({'type': 'session.created'});
        expect(
          gate.observe(_ack({..._serverSession(), 'instructions': ''})),
          BrainSessionAction.reject,
        );
      },
    );

    test(
      'Deep Think remains a speech-only transport with the callback enabled',
      () {
        final gate = BrainVoiceSessionGate(projectionEnabled: true);
        gate.observe({'type': 'session.created', 'session': _serverSession()});
        final update = gate.configuration['session'] as Map;
        expect(update['tools'], isEmpty);
        expect(update['tool_choice'], 'none');
        expect(update.containsKey('instructions'), isFalse);
        expect(gate.observe(_ack(update)), BrainSessionAction.ready);
      },
    );
  });

  group('Live projection turns', () {
    test('waits for original transcript, preserves evidence and deduplicates calls', () async {
      final h = _LiveHarness(
        project: (_, _, _) async => {
          'ok': true,
          'handled': true,
          'saved': true,
          'answer': 'Saved the selected place.',
          'scope': 'Selected building',
          'sources': [
            {'title': 'City record', 'url': 'https://example.org/record'},
          ],
          'date': '2026-01-01',
          'isLive': false,
          'imageryDate': 'Unknown',
        },
      );
      h.begin();
      final call = _projectionCall(
        arguments: {'action': 'savePlace', 'value': ''},
      );
      final pending = h.live.responseDone(call);
      await _flush();
      expect(h.projections, isEmpty);
      h.live.accept('turn1', 'Rici remember this place');
      await pending;
      expect(h.projections.single['turnId'], 'turn1');
      expect(h.projections.single['transcript'], 'Rici remember this place');
      expect(h.projections.single['arguments'], {
        'action': 'savePlace',
        'value': '',
      });
      expect(h.memories, isEmpty);
      expect(
        h.saved,
        isEmpty,
        reason: 'Controller already owns the place save',
      );
      final output =
          jsonDecode((h.sent.first['item'] as Map)['output'] as String) as Map;
      expect(output['scope'], 'Selected building');
      expect(output['sources'], isNotEmpty);
      expect(output['date'], '2026-01-01');
      expect(output['isLive'], isFalse);
      expect(output['imageryDate'], 'Unknown');
      expect(h.sent.last['response']['metadata']['brain_turn'], 'turn1');
      final sentCount = h.sent.length;
      await h.live.responseDone(call);
      expect(h.projections.length, 1);
      expect(h.sent.length, sentCount);
      h.live.dispose();
    });

    test(
      'legacy callback absence and invalid calls cannot execute projection',
      () async {
        final cases = <Map<String, dynamic>>[
          {
            'enabled': false,
            'args': {'action': 'open', 'value': ''},
          },
          {
            'args': {'action': 'delete_all', 'value': ''},
          },
          {
            'args': {'action': 'open'},
          },
          {
            'args': {'action': 'open', 'value': '', 'extra': true},
          },
          {
            'args': {'action': 'open', 'value': 123},
          },
          {
            'args': {'action': 'open', 'value': List.filled(1001, 'x').join()},
          },
          {
            'name': 'launch_browser',
            'args': {'action': 'open', 'value': ''},
          },
        ];
        for (final data in cases) {
          final h = _LiveHarness(enabled: data['enabled'] != false);
          h.begin();
          h.live.accept('turn1', 'Project virtual reality');
          await h.live.responseDone(
            _projectionCall(
              name: data['name'] as String? ?? 'control_projection',
              arguments: data['args'],
            ),
          );
          expect(h.projections, isEmpty);
          expect(h.memories, isEmpty);
          expect(h.saved, isEmpty);
          final output = jsonDecode(
            (h.sent.first['item'] as Map)['output'] as String,
          ) as Map;
          expect(output['ok'], isFalse);
          h.live.dispose();
        }
      },
    );

    test(
      'missing or failed original transcription never executes projection',
      () async {
        for (final failed in [false, true]) {
          final h = _LiveHarness(timeout: const Duration(milliseconds: 1));
          h.begin();
          if (failed) h.live.transcriptionFailed('turn1');
          await h.live.responseDone(_projectionCall());
          expect(h.projections, isEmpty);
          expect(
            (h.sent.first['item'] as Map)['output'],
            contains('could not be confirmed'),
          );
          h.live.dispose();
        }
      },
    );

    test('new speech cannot authorize an old pending projection', () async {
      final h = _LiveHarness();
      h.begin();
      final pending = h.live.responseDone(_projectionCall());
      await _flush();
      h.live.speechStarted('turn2');
      h.live.accept('turn2', 'Open the command center');
      h.live.accept('turn1', 'Project virtual reality');
      await pending;
      expect(h.projections, isEmpty);
      expect(h.sent.where((e) => e['type'] == 'response.create'), isEmpty);
      h.live.dispose();
    });

    test(
      'Stop awaiting transcript prevents later callback and speech',
      () async {
        final h = _LiveHarness();
        h.begin();
        final pending = h.live.responseDone(_projectionCall());
        await _flush();
        h.live.dispose();
        await pending;
        h.live.accept('turn1', 'Project virtual reality');
        expect(h.projections, isEmpty);
        expect(h.sent, isEmpty);
      },
    );

    test(
      'Stop during projection suppresses its late output and speech',
      () async {
        final finish = Completer<Map<String, dynamic>?>();
        final h = _LiveHarness(project: (_, _, _) => finish.future);
        h.begin();
        h.live.accept('turn1', 'Project virtual reality');
        final pending = h.live.responseDone(_projectionCall());
        await _flush();
        expect(h.projections.length, 1);
        h.live.dispose();
        finish.complete({
          'ok': true,
          'handled': true,
          'answer': 'Stale place.',
        });
        await pending;
        expect(h.sent, isEmpty);
        expect(h.events.where((e) => e['type'] == 'voiceNotice'), isEmpty);
      },
    );

    test(
      'new utterance suppresses stale place evidence and continuation',
      () async {
        final finish = Completer<Map<String, dynamic>?>();
        final h = _LiveHarness(project: (_, _, _) => finish.future);
        h.begin();
        h.live.accept('turn1', 'Go to Paris');
        final pending = h.live.responseDone(
          _projectionCall(arguments: {'action': 'search', 'value': 'Paris'}),
        );
        await _flush();
        h.live.speechStarted('turn2');
        finish.complete({
          'ok': true,
          'handled': true,
          'answer': 'Old Paris result.',
        });
        await pending;
        expect(h.sent.where((e) => e['type'] == 'response.create'), isEmpty);
        expect(jsonEncode(h.sent), isNot(contains('Old Paris result.')));
        expect(jsonEncode(h.sent), contains('interrupted'));
        h.live.dispose();
      },
    );
  });

  test(
    'new Live projection command does not wait behind an older lookup',
    () async {
      final first = Completer<Map<String, dynamic>?>();
      final h = _LiveHarness(
        project: (id, _, _) async {
          if (id == 'turn1') return first.future;
          return {'ok': true, 'handled': true, 'answer': 'Projection closed.'};
        },
      );
      h.begin();
      h.live.accept('turn1', 'Go to Paris');
      final pending = h.live.responseDone(
        _projectionCall(arguments: {'action': 'search', 'value': 'Paris'}),
      );
      await _flush();
      h.live.speechStarted('turn2');
      h.live.speechStopped('turn2');
      h.live.responseStarted({'id': 'response2'});
      h.live.accept('turn2', 'Close projection');
      await h.live.responseDone(
        _projectionCall(
          response: 'response2',
          call: 'call2',
          arguments: {'action': 'close', 'value': ''},
        ),
      );
      expect(h.projections.map((p) => p['turnId']), ['turn1', 'turn2']);
      expect(jsonEncode(h.sent), contains('Projection closed.'));
      first.complete({
        'ok': true,
        'handled': true,
        'answer': 'Old Paris result.',
      });
      await pending;
      final replies = h.sent
          .where((e) => e['type'] == 'response.create')
          .toList();
      expect(replies.length, 1);
      expect(replies.single['response']['metadata']['brain_turn'], 'turn2');
      expect(jsonEncode(h.sent), isNot(contains('Old Paris result.')));
      h.live.dispose();
    },
  );

  group('Deep Think projection dispatch', () {
    test('handled commands use existing speech queue without reasoning or duplicate save', () async {
      final h = _DeepHarness(
        project: (_, _, _) async => {
          'ok': true,
          'handled': true,
          'saved': true,
          'answer': 'Saved this place to your brain.',
        },
      );
      h.turns.speechStarted('turn1');
      h.turns.accept('turn1', 'Remember this place');
      h.turns.accept('turn1', 'Remember this place');
      await _flush();
      expect(h.projections.length, 1);
      expect(h.projections.single['arguments'], isNull);
      expect(h.requests, isEmpty);
      expect(h.saved, isEmpty);
      final response = h.speech.single['response'] as Map;
      expect(response['conversation'], 'none');
      expect(response['metadata']['brain_turn'], 'turn1');
      expect(
        response['input'][0]['content'][0]['text'],
        'Saved this place to your brain.',
      );
      h.turns.dispose();
    });

    test(
      'null and unhandled results pass ordinary turns through unchanged',
      () async {
        for (final result in [
          null,
          {'handled': false, 'answer': 'Do not speak this'},
        ]) {
          final h = _DeepHarness(project: (_, _, _) async => result);
          h.turns.accept('turn1', 'Tell me a story');
          await _flush();
          expect(h.requests.single, ['turn1', 'Tell me a story']);
          expect(
            h.speech.single['response']['input'][0]['content'][0]['text'],
            'Verified Sol answer.',
          );
          h.turns.dispose();
        }
      },
    );

    test('ordinary explicit memories retain the existing save path', () async {
      final h = _DeepHarness(
        project: (_, _, _) async => null,
        result: {
          'ok': true,
          'saved': true,
          'answer': 'Saved that to your brain.',
          'memory': {'id': 'memory1'},
        },
      );
      h.turns.accept('turn1', 'Rici remember this: my dog is Joy');
      await _flush();
      expect(h.requests.length, 1);
      expect(h.saved.length, 1);
      h.turns.dispose();
    });

    test(
      'Stop and newer speech suppress a late handled projection reply',
      () async {
        for (final stop in [false, true]) {
          final finish = Completer<Map<String, dynamic>?>();
          final h = _DeepHarness(project: (_, _, _) => finish.future);
          h.turns.speechStarted('turn1');
          h.turns.accept('turn1', 'Project virtual reality');
          await _flush();
          if (stop) {
            h.turns.dispose();
          } else {
            h.turns.speechStarted('turn2');
          }
          finish.complete({'handled': true, 'answer': 'Old projection reply.'});
          await _flush();
          expect(h.requests, isEmpty);
          expect(h.speech, isEmpty);
          h.turns.dispose();
        }
      },
    );
  });
}

typedef _Project = Future<Map<String, dynamic>?> Function(
  String,
  String,
  Map<String, dynamic>?,
);

class _LiveHarness {
  _LiveHarness({
    bool enabled = true,
    _Project? project,
    Duration timeout = const Duration(seconds: 15),
  }) {
    live = BrainLiveTurns(
      send: (event) async => sent.add(event),
      emit: events.add,
      saved: (result) async => saved.add(result),
      isCurrent: () => true,
      reportTiming: (_, _) async {},
      requestMemory: (id, text) async {
        memories.add([id, text]);
        return {'ok': true, 'saved': true, 'answer': 'Saved.'};
      },
      onProjection: enabled
          ? (id, text, args) async {
              projections.add({
                'turnId': id,
                'transcript': text,
                'arguments': args,
              });
              return project == null
                  ? {
                      'ok': true,
                      'handled': true,
                      'answer': 'Projection opened.',
                    }
                  : await project(id, text, args);
            }
          : null,
      transcriptionTimeout: timeout,
    );
  }

  late final BrainLiveTurns live;
  final sent = <Map<String, dynamic>>[],
      events = <Map<String, dynamic>>[],
      saved = <Map<String, dynamic>>[],
      projections = <Map<String, dynamic>>[];
  final memories = <List<String>>[];

  void begin() {
    live.speechStarted('turn1');
    live.speechStopped('turn1');
    live.responseStarted({'id': 'response1'});
  }
}

class _DeepHarness {
  _DeepHarness({required _Project project, Map<String, dynamic>? result}) {
    turns = BrainVoiceTurns(
      request: (id, text, onDelta) async {
        requests.add([id, text]);
        return result ??
            {
              'answer': 'Verified Sol answer.',
              'model': 'gpt-6.1-sol',
              'reasoningEffort': 'max',
            };
      },
      onProjection: (id, text, args) async {
        projections.add({'turnId': id, 'transcript': text, 'arguments': args});
        return project(id, text, args);
      },
      send: (event) async {
        if (event['type'] == 'response.create') speech.add(event);
      },
      emit: (_) {},
      isCurrent: () => true,
      saved: (value) async => saved.add(value),
    );
  }

  late final BrainVoiceTurns turns;
  final requests = <List<String>>[];
  final speech = <Map<String, dynamic>>[],
      saved = <Map<String, dynamic>>[],
      projections = <Map<String, dynamic>>[];
}
