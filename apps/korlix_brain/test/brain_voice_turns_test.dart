import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_voice_turns.dart';

void main() {
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  final answer = {
    'answer': 'An Astra answer.',
    'model': 'gpt-6-astra',
    'reasoningEffort': 'max',
  };

  test(
    'deduplicates completed ASR and uses only server answer for speech',
    () async {
      final calls = <String>[], sent = <Map<String, dynamic>>[];
      final turns = BrainVoiceTurns(
        request: (id, text, onDelta) async {
          calls.add(id);
          return answer;
        },
        send: (e) async {
          if (e['type'] == 'response.create') sent.add(e);
        },
        emit: (_) {},
        isCurrent: () => true,
        saved: (_) async {},
      );
      turns.speechStarted('one');
      turns.accept('one', 'User question');
      turns.accept('one', 'User question');
      await flush();
      expect(calls, ['one']);
      expect(sent.single['response']['conversation'], 'none');
      expect(
        sent.single['response']['input'][0]['content'][0]['text'],
        'An Astra answer.',
      );
      turns.dispose();
    },
  );

  test('out of order ASR completes in spoken order; interrupted answer stays silent', () async {
    final calls = <String>[], sent = <Map<String, dynamic>>[];
    final turns = BrainVoiceTurns(
      request: (id, text, onDelta) async {
        calls.add(id);
        return answer;
      },
      send: (e) async {
        if (e['type'] == 'response.create') sent.add(e);
      },
      emit: (_) {},
      isCurrent: () => true,
      saved: (_) async {},
    );
    turns.speechStarted('one');
    turns.speechStarted('two');
    turns.accept('two', 'Second');
    await flush();
    expect(calls, isEmpty);
    turns.accept('one', 'First');
    await flush();
    expect(calls, ['one', 'two']);
    expect(sent.length, 1);
    turns.dispose();
  });

  test('interrupted save waits for acknowledgment, updates brain, and does not speak over user', () async {
    final pending = Completer<Map<String, dynamic>>(),
        sent = <Map<String, dynamic>>[],
        saved = <Map<String, dynamic>>[];
    final turns = BrainVoiceTurns(
      request: (_, _, onDelta) => pending.future,
      send: (e) async {
        if (e['type'] == 'response.create') sent.add(e);
      },
      emit: (_) {},
      isCurrent: () => true,
      saved: (value) async {
        saved.add(value);
      },
    );
    turns.speechStarted('one');
    turns.accept('one', 'Rici remember this: purple');
    expect(saved, isEmpty);
    turns.speechStarted('two');
    pending.complete({
      'saved': true,
      'memory': {'id': 'm1', 'content': 'purple'},
      'answer': 'Saved that to your brain.',
    });
    await flush();
    expect(saved.length, 1);
    expect(sent, isEmpty);
    turns.dispose();
  });

  test('account changes and disposal suppress late saves and speech', () async {
    final pending = Completer<Map<String, dynamic>>(), effects = <String>[];
    var current = true;
    final turns = BrainVoiceTurns(
      request: (_, _, onDelta) => pending.future,
      send: (_) async {
        effects.add('speech');
      },
      emit: (_) {},
      isCurrent: () => current,
      saved: (_) async {
        effects.add('saved');
      },
    );
    turns.accept('one', 'Rici remember this: private');
    current = false;
    turns.dispose();
    pending.complete({
      'saved': true,
      'memory': {'id': 'm1'},
      'answer': 'Saved.',
    });
    await flush();
    expect(effects, isEmpty);
  });

  test('failed save never emits success and returns to listening', () async {
    final emitted = <Map<String, dynamic>>[],
        saved = <Object>[],
        sent = <Object>[];
    final turns = BrainVoiceTurns(
      request: (_, _, onDelta) async => throw StateError('offline'),
      send: (e) async {
        if (e['type'] == 'response.create') sent.add(e);
      },
      emit: emitted.add,
      isCurrent: () => true,
      saved: (value) async {
        saved.add(value);
      },
    );
    turns.accept('one', 'Rici remember this: x');
    await flush();
    expect(saved, isEmpty);
    expect(sent, isEmpty);
    expect(emitted.any((e) => e['type'] == 'voiceSaved'), false);
    expect(emitted.last['phase'], 'listening');
    turns.dispose();
  });

  test(
    'no speech is generated from an unverified different reasoning model',
    () async {
      final sent = <Object>[];
      final turns = BrainVoiceTurns(
        request: (_, _, onDelta) async => {...answer, 'model': 'gpt-6-luna'},
        send: (value) async {
          if (value['type'] == 'response.create') sent.add(value);
        },
        emit: (_) {},
        isCurrent: () => true,
        saved: (_) async {},
      );
      turns.accept('one', 'Question');
      await flush();
      expect(sent, isEmpty);
      turns.dispose();
    },
  );
}
