import 'dart:async';

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
}

class Harness {
  Harness({
    Future<Map<String, dynamic>> Function(String, String)? save,
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
      isCurrent: () => true,
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
      transcriptionTimeout: timeout,
    );
  }
  late final BrainLiveTurns live;
  final sent = <Map<String, dynamic>>[],
      events = <Map<String, dynamic>>[],
      saved = <Map<String, dynamic>>[];
  final requests = <List<String>>[], timings = <List<Object>>[];
  void begin(String turn, String response) {
    live.speechStarted(turn);
    live.speechStopped(turn);
    live.responseStarted({'id': response});
  }
}
