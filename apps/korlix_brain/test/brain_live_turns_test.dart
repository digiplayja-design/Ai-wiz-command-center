import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_live_turns.dart';

void main() {
  Map<String, dynamic> done(
    String response, {
    String name = 'remember_in_brain',
    String args = '{}',
    String call = 'call1',
  }) => {
    'id': response,
    'status': 'completed',
    'output': [
      {
        'type': 'function_call',
        'name': name,
        'arguments': args,
        'call_id': call,
      },
    ],
  };
  test('ordinary audio replies do not wait for ASR or invoke any backend text turn', () async {
    final h = Harness();
    h.live.speechStarted('user1');
    h.live.speechStopped('user1');
    h.live.responseStarted({'id': 'r1'});
    h.live.audioStarted('r1');
    await h.live.responseDone({
      'id': 'r1',
      'status': 'completed',
      'output': [],
    });
    expect(h.requests, isEmpty);
    expect(h.sent, isEmpty);
    expect(h.timings.length, 1);
    h.live.accept('user1', 'Hello');
    expect(h.requests, isEmpty);
    expect(h.events.single['text'], 'Hello');
    h.live.dispose();
  });
  test('memory tool waits for its original transcript, then confirms the exact save', () async {
    final h = Harness();
    h.begin('user1', 'r1');
    final pending = h.live.responseDone(done('r1'));
    await Future<void>.delayed(Duration.zero);
    expect(h.requests, isEmpty);
    h.live.accept('user1', 'Rici remember this: My dog is Joy.');
    await pending;
    expect(h.requests.single, ['user1', 'Rici remember this: My dog is Joy.']);
    expect(h.saved.length, 1);
    expect(h.sent[0]['type'], 'conversation.item.create');
    expect(h.sent[1]['type'], 'response.create');
    await h.live.responseDone(done('r1'));
    expect(h.requests.length, 1);
    h.live.dispose();
  });
  test(
    'new speech cannot substitute another transcript into an older memory tool',
    () async {
      final h = Harness();
      h.begin('one', 'r1');
      final pending = h.live.responseDone(done('r1'));
      h.live.speechStarted('two');
      h.live.speechStopped('two');
      h.live.accept('two', 'Different words');
      h.live.accept('one', 'Rici remember this: original');
      await pending;
      expect(h.requests.single, ['one', 'Rici remember this: original']);
      expect(
        h.sent.where((e) => e['type'] == 'response.create'),
        isEmpty,
        reason: 'No stale spoken confirmation',
      );
      expect(h.saved.length, 1);
      h.live.dispose();
    },
  );
  test(
    'Stop while awaiting transcription prevents the write and later speech',
    () async {
      final h = Harness();
      h.begin('one', 'r1');
      final pending = h.live.responseDone(done('r1'));
      await Future<void>.delayed(Duration.zero);
      h.live.dispose();
      await pending;
      h.live.accept('one', 'Rici remember this: x');
      expect(h.requests, isEmpty);
      expect(h.sent, isEmpty);
      expect(h.saved, isEmpty);
    },
  );
  test('Stop during an authorized write suppresses old UI and audio, without retrying', () async {
    final finish = Completer<Map<String, dynamic>>();
    final h = Harness(save: (_, _) => finish.future);
    h.begin('one', 'r1');
    h.live.accept('one', 'Rici remember this: x');
    final pending = h.live.responseDone(done('r1'));
    await Future<void>.delayed(Duration.zero);
    expect(h.requests.length, 1);
    h.live.dispose();
    finish.complete({'ok': true, 'saved': true, 'answer': 'Saved.'});
    await pending;
    expect(h.sent, isEmpty);
    expect(h.saved, isEmpty);
    expect(h.requests.length, 1);
  });
  test(
    'unsupported tools and model-supplied memory text cannot authorize writes',
    () async {
      for (final data in [
        {'name': 'delete_all', 'args': '{}'},
        {'name': 'remember_in_brain', 'args': '{"text":"invented"}'},
      ]) {
        final h = Harness();
        h.begin('one', 'r1');
        h.live.accept('one', 'ordinary conversation');
        await h.live.responseDone(
          done('r1', name: data['name']!, args: data['args']!),
        );
        expect(h.requests, isEmpty);
        expect(h.saved, isEmpty);
        expect(
          (h.sent.first['item'] as Map)['output'],
          contains('"saved":false'),
        );
        h.live.dispose();
      }
    },
  );
  test('failed or absent ASR never claims or performs a save', () async {
    final h = Harness(timeout: const Duration(milliseconds: 1));
    h.begin('one', 'r1');
    await h.live.responseDone(done('r1'));
    expect(h.requests, isEmpty);
    expect(h.saved, isEmpty);
    expect((h.sent.first['item'] as Map)['output'], contains('not confirmed'));
    h.live.dispose();
  });
  test('server failure is explicit, without automatic write retry', () async {
    final h = Harness(save: (_, _) async => throw StateError('offline'));
    h.begin('one', 'r1');
    h.live.accept('one', 'Rici remember this: x');
    await h.live.responseDone(done('r1'));
    expect(h.requests.length, 1);
    expect(h.saved, isEmpty);
    expect((h.sent.first['item'] as Map)['output'], contains('"saved":false'));
    h.live.dispose();
  });
  test('tool response and continuation share one usage turn; stale responses are canceled', () async {
    final h = Harness();
    h.begin('one', 'r1');
    final usage = h.live.usageEvent({
      'type': 'response.done',
      'response': {
        'id': 'r1',
        'usage': {'total_tokens': 8},
      },
    });
    expect(
      ((usage['response'] as Map)['metadata'] as Map)['brain_turn'],
      'one',
    );
    h.live.responseStarted({
      'id': 'r2',
      'metadata': {'brain_turn': 'one'},
    });
    final follow = h.live.usageEvent({
      'type': 'response.done',
      'response': {'id': 'r2'},
    });
    expect(
      ((follow['response'] as Map)['metadata'] as Map)['brain_turn'],
      'one',
    );
    h.live.speechStarted('two');
    h.live.responseStarted({
      'id': 'late',
      'metadata': {'brain_turn': 'one'},
    });
    await Future<void>.delayed(Duration.zero);
    expect(
      h.sent.any(
        (e) => e['type'] == 'response.cancel' && e['response_id'] == 'late',
      ),
      isTrue,
    );
    h.live.dispose();
  });

  group('live transcription watchdog', () {
    const timeout = Duration(seconds: 1);

    testWidgets(
      'missing ASR is visible without a tool and a late camera command is retired',
      (tester) async {
        final h = Harness(
          timeout: timeout,
          recognizes: (text) => text == 'Keep zooming in',
          project: (_, _, _) async => {
            'ok': true,
            'handled': true,
            'answer': 'Zooming in.',
          },
        );
        addTearDown(h.live.dispose);
        h.begin('one', 'auto1');
        await h.live.responseDone({
          'id': 'auto1',
          'status': 'completed',
          'output': <Object>[],
        });
        await tester.pump(const Duration(milliseconds: 999));
        expect(h.events, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        expect(h.events.single['type'], 'voiceNotice');
        expect(h.events.single['code'], 'transcription_timeout');
        expect(h.events.single['message'], contains('repeat the view command'));
        expect(h.events.single['message'], isNot(contains('Microphone off')));
        expect(h.requests, isEmpty);
        expect(
          h.sent,
          isEmpty,
          reason: 'Ordinary audio must keep its own flow',
        );

        h.live.accept('one', 'Keep zooming in');
        await tester.pump();
        expect(h.projections, isEmpty);
        expect(h.events, hasLength(1));

        // The session remains usable; only the timed-out item was retired.
        h.begin('two', 'auto2');
        h.live.accept('two', 'Keep zooming in');
        await tester.pump();
        expect(h.projections.single.first, 'two');
      },
    );

    testWidgets(
      'accepted ASR cancels the watchdog and duplicate VAD cannot rearm it',
      (tester) async {
        final h = Harness(timeout: timeout);
        addTearDown(h.live.dispose);
        h.live.speechStarted('one');
        h.live.speechStopped('one');
        h.live.accept('one', 'Hello');
        h.live.speechStarted('one');
        h.live.speechStopped('one');
        await tester.pump(const Duration(seconds: 2));
        expect(h.events.single['type'], 'transcript');
        expect(h.events.single['text'], 'Hello');
      },
    );

    testWidgets('ASR arriving before speech completion never arms a watchdog', (
      tester,
    ) async {
      final h = Harness(timeout: timeout);
      addTearDown(h.live.dispose);
      h.live.speechStarted('one');
      h.live.accept('one', 'Hello');
      h.live.speechStopped('one');
      await tester.pump(const Duration(seconds: 2));
      expect(h.events.single['type'], 'transcript');
    });

    testWidgets(
      'explicit failure cancels the deadline and rejects delayed ASR once',
      (tester) async {
        final h = Harness(timeout: timeout);
        addTearDown(h.live.dispose);
        h.live.speechStarted('one');
        h.live.speechStopped('one');
        h.live.transcriptionFailed('one');
        await tester.pump(const Duration(seconds: 2));
        h.live.accept('one', 'Delayed words');
        expect(h.events, hasLength(1));
        expect(h.events.single['code'], 'transcription_failed');
      },
    );

    testWidgets(
      'new speech cancels the old warning and only the current turn expires',
      (tester) async {
        final h = Harness(timeout: timeout);
        addTearDown(h.live.dispose);
        h.live.speechStarted('staleWithoutStop');
        h.live.speechStarted('one');
        h.live.speechStopped('one');
        await tester.pump(const Duration(milliseconds: 600));
        h.live.speechStarted('two');
        h.live.speechStopped('one');
        h.live.speechStopped('staleWithoutStop');
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          h.events,
          isEmpty,
          reason: 'The superseded deadline was canceled',
        );
        h.live.speechStopped('two');
        await tester.pump(timeout);
        expect(h.events.single['code'], 'transcription_timeout');
        h.live.accept('two', 'Too late');
        expect(h.events, hasLength(1));
      },
    );

    testWidgets(
      'supersession preserves the original transcript for an older memory tool',
      (tester) async {
        final h = Harness(timeout: timeout);
        addTearDown(h.live.dispose);
        h.begin('one', 'r1');
        h.begin('two', 'r2');
        h.live.accept('two', 'Hello');
        await tester.pump(const Duration(seconds: 2));
        expect(
          h.events.where((event) => event['type'] == 'voiceNotice'),
          isEmpty,
        );
        h.live.accept('one', 'Rici remember this: original');
        await h.live.responseDone(done('r1'));
        expect(h.requests.single, ['one', 'Rici remember this: original']);
        expect(h.saved, hasLength(1));
        expect(
          h.sent.where((event) => event['type'] == 'response.create'),
          isEmpty,
        );
      },
    );

    testWidgets(
      'Stop and an expired session suppress watchdog notices and late controls',
      (tester) async {
        for (final stop in [true, false]) {
          final h = Harness(
            timeout: timeout,
            recognizes: (_) => true,
            project: (_, _, _) async => {'handled': true, 'answer': 'Too late'},
          );
          h.live.speechStarted('one');
          h.live.speechStopped('one');
          if (stop) {
            h.live.dispose();
          } else {
            h.sessionCurrent = false;
          }
          await tester.pump(const Duration(seconds: 2));
          expect(h.events, isEmpty);
          h.sessionCurrent = true;
          h.live.accept('one', 'Keep zooming in');
          await tester.pump();
          expect(h.projections, isEmpty);
          h.live.dispose();
        }
      },
    );
  });

  group('original-transcript view controls', () {
    Future<void> flush() => Future<void>.delayed(Duration.zero);
    bool recognizes(String text) => {
      'Show me the Ferry Building in 3D',
      'Keep zooming in',
      'Stop zooming',
      'Close VR',
    }.contains(text);
    Map<String, dynamic> result(String text) => {
      'ok': true,
      'handled': true,
      'answer': text,
    };
    Map<String, dynamic> automaticDone(
      String id, {
      String status = 'completed',
    }) => {'id': id, 'status': status, 'output': <Object>[]};
    List<Map<String, dynamic>> acknowledgements(Harness h) =>
        h.sent.where((event) => event['type'] == 'response.create').toList();

    test(
      'ASR moves the view without a model tool and speaks one verified result',
      () async {
        final h = Harness(
          recognizes: recognizes,
          project: (_, _, _) async =>
              result('Zooming in. Say stop zooming to stop.'),
        );
        h.begin('one', 'r1');
        h.live.accept('one', 'Keep zooming in');
        h.live.accept('one', 'Keep zooming in');
        await flush();
        expect(h.projections.single, ['one', 'Keep zooming in', null]);
        expect(
          h.sent
              .where((e) => e['type'] == 'response.cancel')
              .single['response_id'],
          'r1',
        );
        expect(
          acknowledgements(h),
          isEmpty,
          reason: 'Wait for cancellation to finish',
        );
        await h.live.responseDone(automaticDone('r1', status: 'cancelled'));
        await flush();
        final response = acknowledgements(h).single['response'] as Map;
        expect(response['conversation'], 'none');
        expect(response['metadata']['brain_turn'], 'one');
        expect(response['metadata']['brain_projection_direct'], 'true');
        expect(response['tool_choice'], 'none');
        expect(response['tools'], isEmpty);
        expect(
          response['input'][0]['content'][0]['text'],
          'Zooming in. Say stop zooming to stop.',
        );
        expect(
          h.sent.where((e) => e['type'] == 'conversation.item.create'),
          isEmpty,
          reason: 'Never invent a function call or call output',
        );
        h.live.responseStarted({
          'id': 'ack1',
          'metadata': {'brain_turn': 'one', 'brain_projection_direct': 'true'},
        });
        await h.live.responseDone(automaticDone('ack1'));
        expect(acknowledgements(h).length, 1);
        expect(h.sent.where((e) => e['type'] == 'response.cancel').length, 1);
        expect(
          h.live.usageEvent({
            'type': 'response.done',
            'response': {
              'id': 'ack1',
              'usage': {'total_tokens': 9},
            },
          })['response']['metadata']['brain_turn'],
          'one',
        );
        h.live.dispose();
      },
    );

    test(
      'ASR before response.created cancels the later automatic reply',
      () async {
        final h = Harness(
          recognizes: recognizes,
          project: (_, _, _) async => result('The view stopped.'),
        );
        h.live.speechStarted('one');
        h.live.speechStopped('one');
        h.live.accept('one', 'Stop zooming');
        await flush();
        expect(h.projections.length, 1);
        expect(h.sent, isEmpty);
        h.live.responseStarted({'id': 'late-auto'});
        await flush();
        expect(h.sent.map((e) => e['type']), [
          'response.cancel',
          'output_audio_buffer.clear',
        ]);
        await h.live.responseDone(
          automaticDone('late-auto', status: 'cancelled'),
        );
        expect(acknowledgements(h).length, 1);
        h.live.dispose();
      },
    );

    test(
      'ASR after automatic completion clears old audio before acknowledging',
      () async {
        final h = Harness(
          recognizes: recognizes,
          project: (_, _, _) async => result('The view stopped.'),
        );
        h.begin('one', 'auto1');
        h.live.audioStarted('auto1');
        await h.live.responseDone(automaticDone('auto1'));
        h.live.accept('one', 'Stop zooming');
        await flush();
        expect(h.sent.map((e) => e['type']), [
          'output_audio_buffer.clear',
          'response.create',
        ]);
        h.live.dispose();
      },
    );

    test('queued automatic audio is cleared even before its started event', () async {
      final h = Harness(
        recognizes: recognizes,
        project: (_, _, _) async => result('The view stopped.'),
      );
      h.begin('one', 'auto1');
      await h.live.responseDone(automaticDone('auto1'));
      h.live.accept('one', 'Stop zooming');
      await flush();
      expect(h.sent.map((e) => e['type']), [
        'output_audio_buffer.clear',
        'response.create',
      ]);
      // A delayed event for the cleared reply must not cut off the new speech.
      h.live.audioStarted('auto1');
      await flush();
      expect(
        h.sent.where((e) => e['type'] == 'output_audio_buffer.clear').length,
        1,
      );
      expect(acknowledgements(h).length, 1);
      h.live.dispose();
    });

    test(
      'late ASR waits for a previously requested tool continuation',
      () async {
        final h = Harness(
          recognizes: recognizes,
          project: (_, _, _) async => result('The view stopped.'),
          timeout: const Duration(milliseconds: 1),
        );
        h.begin('one', 'auto1');
        await h.live.responseDone(done('auto1'));
        expect(h.requests, isEmpty);
        expect(
          acknowledgements(h).length,
          1,
          reason:
              'The failed ASR tool has already requested its ordinary reply',
        );
        h.live.accept('one', 'Stop zooming');
        await flush();
        expect(h.projections.length, 1);
        expect(
          acknowledgements(h).length,
          1,
          reason:
              'Do not overlap the continuation still awaiting response.created',
        );
        h.live.responseStarted({
          'id': 'tool-follow',
          'metadata': {'brain_turn': 'one'},
        });
        await flush();
        expect(
          h.sent
              .where((e) => e['type'] == 'response.cancel')
              .single['response_id'],
          'tool-follow',
        );
        await h.live.responseDone(
          automaticDone('tool-follow', status: 'cancelled'),
        );
        await flush();
        expect(acknowledgements(h).length, 2);
        expect(
          acknowledgements(h)
              .last['response']['metadata']['brain_projection_direct'],
          'true',
        );
        expect(h.projections.length, 1);
        h.live.dispose();
      },
    );

    test(
      'a tool already waiting for ASR shares its direct result exactly once',
      () async {
        final finish = Completer<Map<String, dynamic>?>();
        final h = Harness(
          recognizes: recognizes,
          project: (_, _, _) => finish.future,
        );
        h.begin('one', 'auto1');
        final pending = h.live.responseDone(
          done(
            'auto1',
            name: 'control_projection',
            args: '{"action":"search","value":"model changed the destination"}',
            call: 'real-call',
          ),
        );
        await flush();
        h.live.accept('one', 'Show me the Ferry Building in 3D');
        await flush();
        expect(h.projections.single, [
          'one',
          'Show me the Ferry Building in 3D',
          null,
        ]);
        expect(acknowledgements(h), isEmpty);
        finish.complete(
          result('Review the full address on screen and confirm it.'),
        );
        await pending;
        await flush();
        expect(h.projections.length, 1);
        final outputs = h.sent
            .where((e) => e['type'] == 'conversation.item.create')
            .toList();
        expect(outputs.single['item']['call_id'], 'real-call');
        expect(
          jsonDecode(outputs.single['item']['output'])['answer'],
          'Review the full address on screen and confirm it.',
        );
        expect(acknowledgements(h).length, 1);
        final outputIndex = h.sent.indexOf(outputs.single);
        expect(
          h.sent.indexOf(acknowledgements(h).single),
          greaterThan(outputIndex),
        );
        await h.live.responseDone(
          done(
            'auto1',
            name: 'control_projection',
            args: '{"action":"search","value":"again"}',
            call: 'real-call',
          ),
        );
        expect(h.projections.length, 1);
        expect(acknowledgements(h).length, 1);
        h.live.dispose();
      },
    );

    test('a completed real call in a cancelled reply receives an output, incomplete calls do not', () async {
      final h = Harness(
        recognizes: recognizes,
        project: (_, _, _) async => result('Zooming in.'),
      );
      h.begin('one', 'auto1');
      h.live.accept('one', 'Keep zooming in');
      await h.live.responseDone({
        'id': 'auto1',
        'status': 'cancelled',
        'output': [
          {
            'type': 'function_call',
            'status': 'completed',
            'name': 'control_projection',
            'call_id': 'completed-call',
            'arguments': '{"action":"camera","value":"zoomInContinuous"}',
          },
          {
            'type': 'function_call',
            'status': 'incomplete',
            'name': 'control_projection',
            'call_id': 'incomplete-call',
            'arguments': '{"action":',
          },
        ],
      });
      final outputs = h.sent
          .where((e) => e['type'] == 'conversation.item.create')
          .toList();
      expect(outputs.single['item']['call_id'], 'completed-call');
      expect(h.projections.length, 1);
      expect(acknowledgements(h).length, 1);
      h.live.dispose();
    });

    test(
      'later tool arguments cannot replace or replay the original control',
      () async {
        final h = Harness(
          recognizes: recognizes,
          project: (_, _, _) async => result('The view stopped.'),
        );
        h.begin('one', 'auto1');
        final pending = h.live.responseDone({
          'id': 'auto1',
          'status': 'completed',
          'output': [
            {
              'type': 'function_call',
              'name': 'control_projection',
              'call_id': 'real-call-one',
              'arguments': '{malformed',
            },
            {
              'type': 'function_call',
              'name': 'control_projection',
              'call_id': 'real-call-two',
              'arguments': '{"action":"camera","value":"zoomInContinuous"}',
            },
          ],
        });
        await flush();
        expect(
          h.sent,
          isEmpty,
          reason: 'The original transcript owns the action',
        );
        h.live.accept('one', 'Stop zooming');
        await pending;
        await flush();
        expect(h.projections.single, ['one', 'Stop zooming', null]);
        final outputs = h.sent
            .where((e) => e['type'] == 'conversation.item.create')
            .toList();
        expect(outputs.map((e) => e['item']['call_id']), [
          'real-call-one',
          'real-call-two',
        ]);
        for (final output in outputs) {
          expect(
            jsonDecode(output['item']['output'])['answer'],
            'The view stopped.',
          );
        }
        expect(acknowledgements(h).length, 1);
        expect(h.requests, isEmpty);
        h.live.dispose();
      },
    );

    test(
      'wrong memory tool cannot turn a direct camera utterance into a write',
      () async {
        final h = Harness(
          recognizes: recognizes,
          project: (_, _, _) async => result('The view stopped.'),
        );
        h.begin('one', 'auto1');
        h.live.accept('one', 'Stop zooming');
        await h.live.responseDone(
          done('auto1', args: '{"text":"invented memory"}'),
        );
        expect(h.requests, isEmpty);
        expect(h.saved, isEmpty);
        final output = h.sent.firstWhere(
          (e) => e['type'] == 'conversation.item.create',
        );
        expect(jsonDecode(output['item']['output'])['saved'], isFalse);
        expect(acknowledgements(h).length, 1);
        h.live.dispose();
      },
    );

    test(
      'ordinary conversation and memory commands preserve the native paths',
      () async {
        final h = Harness(
          recognizes: recognizes,
          project: (_, _, _) async => result('Must never execute'),
        );
        h.begin('one', 'auto1');
        h.live.accept('one', 'Tell me a story about a telescope');
        await h.live.responseDone(automaticDone('auto1'));
        expect(h.projections, isEmpty);
        expect(h.sent, isEmpty);
        h.begin('two', 'auto2');
        h.live.accept('two', 'Rici remember this: my dog is Joy');
        await h.live.responseDone(done('auto2'));
        expect(h.projections, isEmpty);
        expect(h.requests.single, ['two', 'Rici remember this: my dog is Joy']);
        expect(h.saved.length, 1);
        expect(acknowledgements(h).single['response']['conversation'], isNull);
        h.live.dispose();
      },
    );

    test('late ASR after a newer utterance never moves the view', () async {
      final h = Harness(
        recognizes: recognizes,
        project: (_, _, _) async => result('Must never execute'),
      );
      h.begin('one', 'auto1');
      h.live.speechStarted('two');
      h.live.accept('one', 'Keep zooming in');
      await h.live.responseDone(automaticDone('auto1', status: 'cancelled'));
      expect(h.projections, isEmpty);
      expect(acknowledgements(h), isEmpty);
      h.live.dispose();
    });

    test(
      'new stop control is not blocked by an earlier address lookup',
      () async {
        final search = Completer<Map<String, dynamic>?>();
        final h = Harness(
          recognizes: recognizes,
          project: (id, _, _) => id == 'one'
              ? search.future
              : Future.value(result('The view stopped.')),
        );
        h.begin('one', 'auto1');
        h.live.accept('one', 'Show me the Ferry Building in 3D');
        await h.live.responseDone(automaticDone('auto1', status: 'cancelled'));
        h.begin('two', 'auto2');
        h.live.accept('two', 'Stop zooming');
        await h.live.responseDone(automaticDone('auto2', status: 'cancelled'));
        await flush();
        expect(h.projections.map((p) => p.first), ['one', 'two']);
        expect(
          acknowledgements(h).single['response']['metadata']['brain_turn'],
          'two',
        );
        search.complete(result('Stale address result'));
        await flush();
        expect(acknowledgements(h).length, 1);
        expect(jsonEncode(h.sent), isNot(contains('Stale address result')));
        h.live.dispose();
      },
    );

    test(
      'Stop or account teardown suppresses a late result and acknowledgement',
      () async {
        final finish = Completer<Map<String, dynamic>?>();
        final h = Harness(
          recognizes: recognizes,
          project: (_, _, _) => finish.future,
        );
        h.begin('one', 'auto1');
        h.live.accept('one', 'Show me the Ferry Building in 3D');
        await flush();
        await h.live.responseDone(automaticDone('auto1', status: 'cancelled'));
        h.live.dispose();
        final count = h.sent.length;
        finish.complete(result('Stale address result'));
        await flush();
        expect(h.sent.length, count);
        expect(acknowledgements(h), isEmpty);
      },
    );

    test('failed direct control acknowledges failure once without retry or success claim', () async {
      final h = Harness(
        recognizes: recognizes,
        project: (_, _, _) async => throw StateError('private provider detail'),
      );
      h.begin('one', 'auto1');
      h.live.accept('one', 'Keep zooming in');
      await h.live.responseDone(automaticDone('auto1', status: 'cancelled'));
      await flush();
      expect(h.projections.length, 1);
      expect(
        acknowledgements(h)
            .single['response']['input'][0]['content'][0]['text'],
        contains('could not finish'),
      );
      expect(jsonEncode(h.sent), isNot(contains('private provider detail')));
      expect(h.requests, isEmpty);
      h.live.dispose();
    });
  });
}

class Harness {
  Harness({
    Future<Map<String, dynamic>> Function(String, String)? save,
    Future<Map<String, dynamic>?> Function(
      String,
      String,
      Map<String, dynamic>?,
    )?
    project,
    bool Function(String)? recognizes,
    Duration timeout = const Duration(seconds: 15),
  }) {
    live = BrainLiveTurns(
      send: (e) async {
        sent.add(e);
      },
      emit: events.add,
      saved: (r) async {
        saved.add(r);
      },
      isCurrent: () => sessionCurrent,
      requestMemory: (id, text) async {
        requests.add([id, text]);
        return save != null
            ? await save(id, text)
            : {
                'ok': true,
                'saved': true,
                'answer': 'Saved that to your brain.',
                'memory': {'id': 'm'},
              };
      },
      reportTiming: (id, ms) async {
        timings.add([id, ms]);
      },
      recognizesProjection: recognizes,
      onProjection: project == null
          ? null
          : (id, text, args) {
              projections.add([id, text, args]);
              return project(id, text, args);
            },
      transcriptionTimeout: timeout,
    );
  }
  late final BrainLiveTurns live;
  bool sessionCurrent = true;
  final sent = <Map<String, dynamic>>[],
      events = <Map<String, dynamic>>[],
      saved = <Map<String, dynamic>>[];
  final requests = <List<String>>[], timings = <List<Object>>[];
  final projections = <List<Object?>>[];
  void begin(String turn, String response) {
    live.speechStarted(turn);
    live.speechStopped(turn);
    live.responseStarted({'id': response});
  }
}
