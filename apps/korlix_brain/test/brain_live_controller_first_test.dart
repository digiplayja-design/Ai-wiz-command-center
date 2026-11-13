import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_live_turns.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

class ManualLiveHarness {
  ManualLiveHarness({
    bool Function(String)? recognizes,
    Future<Map<String, dynamic>?> Function(String, String, Map<String, dynamic>?)? project,
  }) {
    live = BrainLiveTurns(
      controllerFirst: true,
      send: (event) async => sent.add(event),
      emit: events.add,
      isCurrent: () => true,
      saved: (_) async {},
      reportTiming: (_, _) async {},
      requestMemory: (_, _) async => throw StateError('No memory write expected'),
      recognizesProjection: recognizes ?? (text) => text.startsWith('Go to '),
      onProjection: (id, text, args) async {
        controls.add([id, text, args]);
        return project != null
            ? project(id, text, args)
            : {'ok': true, 'handled': true, 'answer': 'Controller result for $text'};
      },
    );
  }

  late final BrainLiveTurns live;
  final sent = <Map<String, dynamic>>[];
  final events = <Map<String, dynamic>>[];
  final controls = <List<Object?>>[];

  List<Map<String, dynamic>> get replies =>
      sent.where((event) => event['type'] == 'response.create').toList();

  void begin(String id) {
    live.speechStarted(id);
    live.speechStopped(id);
  }

  Map<String, dynamic> started(Map<String, dynamic> request, String id) => {
    'id': id,
    'metadata': (request['response'] as Map)['metadata'],
  };

  Future<void> finish(Map<String, dynamic> request, String id, {
    String status = 'completed',
    List<Object> output = const [],
  }) async {
    live.responseStarted(started(request, id));
    await live.responseDone({'id': id, 'status': status, 'output': output});
    await flush();
  }
}

void main() {
  test('a local command speaks its controller result without an automatic response event', () async {
    final h = ManualLiveHarness();
    addTearDown(h.live.dispose);
    h.begin('first');
    expect(h.replies, isEmpty);
    h.live.accept('first', 'Go to 123 Main Street');
    h.live.accept('first', 'Go to 123 Main Street');
    await flush();
    expect(h.controls, [
      ['first', 'Go to 123 Main Street', null],
    ]);
    expect(h.replies, hasLength(1));
    final response = h.replies.single['response'] as Map;
    expect(response['conversation'], 'none');
    expect(response['tools'], isEmpty);
    expect(response['tool_choice'], 'none');
    expect(response['metadata'], {
      'brain_turn': 'first', 'brain_projection_direct': 'true',
    });
    expect(response['input'][0]['content'][0]['text'],
        'Controller result for Go to 123 Main Street');
    expect(h.sent.where((e) => e['type'] == 'conversation.item.create'), isEmpty);
    await h.finish(h.replies.single, 'ack-first');
    expect(h.replies, hasLength(1));
  });

  test('ordinary Live conversation waits for its transcript and requests one Realtime reply', () async {
    final h = ManualLiveHarness();
    addTearDown(h.live.dispose);
    h.begin('ordinary');
    expect(h.sent, isEmpty);
    h.live.accept('ordinary', 'Tell me a joke');
    h.live.accept('ordinary', 'Tell me a joke');
    await flush();
    expect(h.controls, isEmpty);
    expect(h.replies, hasLength(1));
    final request = h.replies.single;
    expect(request['response'], {
      'metadata': {'brain_turn': 'ordinary'}, 'tool_choice': 'auto',
    });
    h.live.responseStarted(h.started(request, 'reply-ordinary'));
    h.live.acceptAssistantTranscript('reply-ordinary', 'Here is a joke.');
    await h.live.responseDone({
      'id': 'reply-ordinary', 'status': 'completed', 'output': <Object>[],
    });
    expect(h.events.where((e) => e['role'] == 'rici').single['text'],
        'Here is a joke.');
    expect(h.replies, hasLength(1));
  });

  test('ASR before speech_stopped schedules one reply without leaving a pending turn', () async {
    for (final phrase in ['Go to 123 Main Street', 'Tell me a joke']) {
      final h = ManualLiveHarness();
      addTearDown(h.live.dispose);
      h.live.speechStarted('early-transcript');
      h.live.accept('early-transcript', phrase);
      await flush();
      expect(h.replies, hasLength(1), reason: phrase);
      final request = h.replies.single;
      await h.finish(request, 'early-reply');
      h.live.speechStopped('early-transcript');
      h.live.speechStopped('early-transcript');
      h.live.accept('early-transcript', phrase);
      await flush();
      expect(h.replies, hasLength(1), reason: phrase);
      expect(h.controls, hasLength(phrase.startsWith('Go to ') ? 1 : 0));
      h.begin('next');
      h.live.accept('next', 'Tell me something else');
      await flush();
      expect(h.replies, hasLength(2));
      expect(h.replies.last['response']['metadata']['brain_turn'], 'next');
    }
  });

  test('an unexpected automatic refusal before ASR is canceled and cannot own the command', () async {
    final h = ManualLiveHarness();
    addTearDown(h.live.dispose);
    h.begin('next');
    h.live.responseStarted({'id': 'unexpected-auto'});
    h.live.acceptAssistantTranscript('unexpected-auto', 'I cannot show another address from here.');
    h.live.accept('next', 'Go to 456 Oak Road');
    await flush();
    expect(h.controls, hasLength(1));
    expect(h.replies, isEmpty,
        reason: 'The requested acknowledgement waits for the unexpected response to end.');
    expect(h.sent.where((e) => e['type'] == 'response.cancel').single['response_id'],
        'unexpected-auto');
    await h.live.responseDone({
      'id': 'unexpected-auto', 'status': 'cancelled', 'output': <Object>[],
    });
    await flush();
    expect(h.replies, hasLength(1));
    expect(h.events.where((e) => e['role'] == 'rici'), isEmpty);
    expect(jsonEncode(h.replies), isNot(contains('cannot show')));
  });

  test('an automatic response after ASR cannot replace the requested controller acknowledgement', () async {
    final h = ManualLiveHarness();
    addTearDown(h.live.dispose);
    h.begin('next');
    h.live.accept('next', 'Go to 456 Oak Road');
    await flush();
    final acknowledgement = h.replies.single;
    h.live.responseStarted({'id': 'unexpected-late-auto'});
    await h.live.responseDone({
      'id': 'unexpected-late-auto', 'status': 'cancelled', 'output': <Object>[],
    });
    await h.finish(acknowledgement, 'requested-ack');
    expect(h.controls, hasLength(1));
    expect(h.replies, hasLength(1));
    expect(h.sent.where((e) => e['type'] == 'response.cancel').single['response_id'],
        'unexpected-late-auto');
  });

  test('a replayed completed unexpected response cannot block a later reply', () async {
    final h = ManualLiveHarness();
    addTearDown(h.live.dispose);
    h.begin('first');
    h.live.responseStarted({'id': 'old-unexpected'});
    await h.live.responseDone({
      'id': 'old-unexpected', 'status': 'cancelled', 'output': <Object>[],
    });
    h.live.responseStarted({'id': 'old-unexpected'});
    h.live.accept('first', 'Go to 123 Main Street');
    await flush();
    expect(h.replies, hasLength(1));
    expect(h.sent.where((e) => e['type'] == 'response.cancel'), hasLength(1));
  });

  test('interruption before response.created reserves one response and waits for cancellation', () async {
    final h = ManualLiveHarness();
    addTearDown(h.live.dispose);
    h.begin('ordinary');
    h.live.accept('ordinary', 'Tell me a joke');
    await flush();
    final old = h.replies.single;
    h.begin('replacement');
    h.live.accept('replacement', 'Go to 456 Oak Road');
    await flush();
    expect(h.controls, hasLength(1));
    expect(h.replies, hasLength(1), reason: 'The old response is still reserved.');
    h.live.responseStarted(h.started(old, 'old-response'));
    h.live.acceptAssistantTranscript('old-response', 'A stale answer.');
    expect(h.sent.where((e) => e['type'] == 'response.cancel').single['response_id'],
        'old-response');
    await h.live.responseDone({
      'id': 'old-response', 'status': 'cancelled', 'output': <Object>[],
    });
    await flush();
    expect(h.replies, hasLength(2));
    expect(h.replies.last['response']['metadata']['brain_turn'], 'replacement');
    expect(h.events.where((e) => e['role'] == 'rici'), isEmpty);
    await h.finish(h.replies.last, 'replacement-ack');
  });

  test('failed or empty current ASR produces one repeat request and cannot replay later', () async {
    for (final empty in [false, true]) {
      final h = ManualLiveHarness();
      addTearDown(h.live.dispose);
      h.begin('failed');
      if (empty) {
        h.live.accept('failed', '   ');
      } else {
        h.live.transcriptionFailed('failed');
      }
      h.live.transcriptionFailed('failed');
      h.live.accept('failed', 'Go to 123 Main Street');
      await flush();
      expect(h.controls, isEmpty);
      expect(h.replies, hasLength(1));
      expect(h.replies.single['response']['input'][0]['content'][0]['text'],
          contains('Please repeat'));
      expect(h.replies.single['response']['tool_choice'], 'none');
      final request = h.replies.single;
      final spoken = request['response']['input'][0]['content'][0]['text'] as String;
      h.live.responseStarted(h.started(request, 'failure-ack'));
      h.live.acceptAssistantTranscript('failure-ack', spoken);
      await h.live.responseDone({
        'id': 'failure-ack', 'status': 'completed',
        'output': [
          {'type': 'function_call', 'name': 'control_projection', 'call_id': 'ignored-tool',
            'arguments': jsonEncode({'action': 'search', 'value': '123 Main Street'})},
        ],
      });
      expect(h.events.where((e) => e['role'] == 'rici').single['text'], spoken);
      expect(h.controls, isEmpty);
      expect(h.sent.where((e) => e['type'] == 'conversation.item.create'), isEmpty);
      expect(h.replies, hasLength(1));
    }
  });

  test('superseded transcripts and failures cannot schedule a stale reply', () async {
    final h = ManualLiveHarness();
    addTearDown(h.live.dispose);
    h.begin('old');
    h.begin('current');
    h.live.accept('old', 'Go to 123 Main Street');
    h.live.transcriptionFailed('old');
    await flush();
    expect(h.controls, isEmpty);
    expect(h.replies, isEmpty);
    h.live.accept('current', 'Tell me a joke');
    await flush();
    expect(h.replies, hasLength(1));
    expect(h.replies.single['response']['metadata']['brain_turn'], 'current');
  });

  test('duplicate model tool calls share original transcript and one continuation', () async {
    final h = ManualLiveHarness(recognizes: (_) => false);
    addTearDown(h.live.dispose);
    h.begin('research');
    h.live.accept('research', 'When was this building built?');
    await flush();
    final request = h.replies.single;
    final call = <String, dynamic>{
      'type': 'function_call', 'name': 'control_projection', 'call_id': 'tool-one',
      'arguments': jsonEncode({'action': 'ask', 'value': 'Model-proposed text'}),
    };
    await h.finish(request, 'research-response', output: [call, call]);
    await h.live.responseDone({
      'id': 'research-response', 'status': 'completed', 'output': [call, call],
    });
    expect(h.controls, [
      ['research', 'When was this building built?',
        {'action': 'ask', 'value': 'Model-proposed text'}],
    ]);
    expect(h.sent.where((e) => e['type'] == 'conversation.item.create'), hasLength(1));
    expect(h.replies, hasLength(2));
    expect(h.replies.last['response']['tool_choice'], 'none');
    await h.finish(h.replies.last, 'research-followup');
    expect(h.replies, hasLength(2));
  });

  test('a newer command speaks while an older controller lookup is pending', () async {
    final older = Completer<Map<String, dynamic>?>();
    final h = ManualLiveHarness(project: (id, _, _) => id == 'first'
        ? older.future
        : Future.value({'ok': true, 'handled': true, 'answer': 'Latest destination checked.'}));
    addTearDown(h.live.dispose);
    h.begin('first');
    h.live.accept('first', 'Go to 123 Main Street');
    h.begin('next');
    h.live.accept('next', 'Go to 456 Oak Road');
    await flush();
    expect(h.controls, hasLength(2));
    expect(h.replies, hasLength(1));
    expect(h.replies.single['response']['metadata']['brain_turn'], 'next');
    older.complete({'ok': true, 'handled': true, 'answer': 'Obsolete destination.'});
    await flush();
    expect(h.replies, hasLength(1));
    expect(jsonEncode(h.sent), isNot(contains('Obsolete destination')));
  });

  test('disposing a reserved response retires queued speech and late controller results', () async {
    final h = ManualLiveHarness();
    h.begin('ordinary');
    h.live.accept('ordinary', 'Tell me a joke');
    await flush();
    final old = h.replies.single;
    h.begin('next');
    h.live.accept('next', 'Go to 456 Oak Road');
    await flush();
    expect(h.replies, hasLength(1));
    h.live.dispose();
    await h.finish(old, 'late-response');
    expect(h.replies, hasLength(1));
  });
}
