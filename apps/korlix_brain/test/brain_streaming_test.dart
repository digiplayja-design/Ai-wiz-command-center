import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korlix_brain/brain_api.dart';
import 'package:korlix_brain/brain_auth.dart';
import 'package:korlix_brain/brain_speech_queue.dart';
import 'package:korlix_brain/brain_voice_turns.dart';
import 'package:korlix_receipt_core/auth/korlix_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brain_account_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  const first =
      'This is the first complete sentence of the answer arriving from Astra Max. ';
  final answer = {
    'answer': '${first}Here is the rest.',
    'model': 'gpt-6-astra',
    'reasoningEffort': 'max',
  };
  final delta = {
    'type': 'answer.delta',
    'text': first,
    'model': 'gpt-6-astra',
    'reasoningEffort': 'max',
  };

  test(
    'first utterance never sends playback controls before any speech exists',
    () async {
      final sent = <Map<String, dynamic>>[];
      final queue = BrainSpeechQueue(
        (e) async {
          sent.add(e);
        },
        () => true,
        () {},
      );
      queue.interrupt(1);
      await flush();
      expect(sent, isEmpty);
      queue.dispose();
    },
  );

  test('speaks first sentence before full response, queues remaining audio in order', () async {
    final pending = Completer<Map<String, dynamic>>(),
        sent = <Map<String, dynamic>>[];
    late void Function(Map<String, dynamic>) emitDelta;
    final turns = BrainVoiceTurns(
      request: (_, _, callback) {
        emitDelta = callback;
        return pending.future;
      },
      send: (e) async {
        sent.add(e);
      },
      emit: (_) {},
      saved: (_) async {},
      isCurrent: () => true,
    );
    turns.accept('one', 'Question');
    emitDelta(delta);
    await flush();
    expect(pending.isCompleted, false);
    expect(
      sent.single['response']['input'][0]['content'][0]['text'],
      first.trim(),
    );
    emitDelta({...delta, 'text': 'Here is the rest.'});
    pending.complete(answer);
    await flush();
    expect(sent.length, 1); // only one generation in flight
    turns.responseStarted({
      'id': 'r1',
      'metadata': {'brain_epoch': '0'},
    });
    turns.responseDone('r1');
    await flush();
    expect(sent.length, 2);
    expect(
      sent.last['response']['input'][0]['content'][0]['text'],
      'Here is the rest.',
    );
    expect(sent.last['response']['metadata']['brain_turn'], 'one');
    turns.dispose();
  });

  test('barge-in before response.created cancels late speech and discards remaining answer', () async {
    final pending = Completer<Map<String, dynamic>>(),
        sent = <Map<String, dynamic>>[];
    late void Function(Map<String, dynamic>) emitDelta;
    final turns = BrainVoiceTurns(
      request: (_, _, callback) {
        emitDelta = callback;
        return pending.future;
      },
      send: (e) async {
        sent.add(e);
      },
      emit: (_) {},
      saved: (_) async {},
      isCurrent: () => true,
    );
    turns.accept('one', 'Question');
    emitDelta(delta);
    await flush();
    turns.speechStarted('two');
    turns.responseStarted({
      'id': 'r1',
      'metadata': {'brain_epoch': '0'},
    });
    emitDelta({...delta, 'text': 'Here is the rest.'});
    pending.complete(answer);
    await flush();
    turns.responseDone('r1');
    await flush();
    expect(sent.where((e) => e['type'] == 'response.create').length, 1);
    expect(
      sent.any(
        (e) => e['type'] == 'response.cancel' && e['response_id'] == 'r1',
      ),
      true,
    );
    expect(sent.any((e) => e['type'] == 'output_audio_buffer.clear'), true);
    turns.dispose();
  });

  test('failed partial stream clears speech even when response.created arrives late', () async {
    final pending = Completer<Map<String, dynamic>>(),
        sent = <Map<String, dynamic>>[];
    late void Function(Map<String, dynamic>) emitDelta;
    final turns = BrainVoiceTurns(
      request: (_, _, callback) {
        emitDelta = callback;
        return pending.future;
      },
      send: (e) async {
        sent.add(e);
      },
      emit: (_) {},
      saved: (_) async {},
      isCurrent: () => true,
    );
    turns.accept('one', 'Question');
    emitDelta(delta);
    await flush();
    pending.completeError(StateError('disconnected'));
    await flush();
    turns.responseStarted({
      'id': 'r1',
      'metadata': {'brain_epoch': '0'},
    });
    await flush();
    expect(sent.reversed.take(2).map((e) => e['type']).toList(), [
      'output_audio_buffer.clear',
      'response.cancel',
    ]);
    turns.dispose();
  });

  test('save acknowledgement does not wait for My Brain refresh', () async {
    final refresh = Completer<void>(), sent = <Map<String, dynamic>>[];
    final turns = BrainVoiceTurns(
      request: (_, _, _) async => {
        'saved': true,
        'memory': {'id': 'saved'},
        'answer': 'Saved that to your brain.',
      },
      send: (e) async {
        sent.add(e);
      },
      emit: (_) {},
      saved: (_) => refresh.future,
      isCurrent: () => true,
    );
    turns.accept('one', 'Rici remember this: gold');
    await flush();
    expect(refresh.isCompleted, false);
    expect(sent.single['type'], 'response.create');
    refresh.complete();
    turns.dispose();
  });

  test('phrase buffer preserves words across token boundaries', () {
    final parts = <String>[];
    final buffer = BrainSpeechBuffer(parts.add);
    for (final char in '$first José is here.'.split('')) {
      buffer.add(char);
    }
    buffer.finish();
    expect(parts.join(''), '$first José is here.');
  });

  test('short first sentence starts before the rest of the answer arrives', () {
    final parts = <String>[];
    final buffer = BrainSpeechBuffer(parts.add);
    buffer.add("I'm Rici. ");
    expect(parts, ["I'm Rici. "]);
    buffer.add('Dr. Jones prefers metric units.');
    expect(parts.length, 1);
    buffer.finish();
    expect(parts.join(), "I'm Rici. Dr. Jones prefers metric units.");
  });

  test('first phrase does not split an abbreviation or decimal', () {
    final parts = <String>[];
    final buffer = BrainSpeechBuffer(parts.add);
    buffer.add('Dr. ');
    expect(parts, isEmpty);
    buffer.add('Jones measured 1.5 meters. ');
    expect(parts, ['Dr. Jones measured 1.5 meters. ']);
  });

  Future<BrainAuthController> login() async {
    SharedPreferences.setMockInitialValues({});
    final auth = BrainAuthController(
      client: MockClient((_) async => fixtures.response(fixtures.session())),
      tokenStore: KorlixTokenStore(
        useSecureStorage: false,
        namespace: 'stream_fixture',
      ),
    );
    addTearDown(auth.dispose);
    await auth.authenticate(email: 'fixture@example.test', password: 'fixture');
    return auth;
  }

  test('authenticated NDJSON releases chunks before completion and handles fragmented UTF-8', () async {
    final auth = await login(), network = StreamController<List<int>>();
    final chunks = <Map<String, dynamic>>[];
    final api = BrainApi(
      auth,
      client: MockClient.streaming((request, _) async {
        expect(request.headers['Authorization'], startsWith('Bearer '));
        expect(request.headers['Accept'], 'application/x-ndjson');
        return http.StreamedResponse(
          network.stream,
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      }),
    );
    addTearDown(api.dispose);
    var done = false;
    final result = api.voiceTurn({'turnId': 'one'}, chunks.add).then((r) {
      done = true;
      return r;
    });
    for (final byte in utf8.encode(
      '${jsonEncode({...delta, 'text': 'José'})}\n',
    )) {
      network.add([byte]);
    }
    await flush();
    expect(chunks.single['text'], 'José');
    expect(done, false);
    network.add(
      utf8.encode('${jsonEncode({'type': 'turn.completed', ...answer})}\n'),
    );
    expect((await result)['answer'], answer['answer']);
    await network.close();
  });

  test('truncated stream fails without replaying the write', () async {
    final auth = await login();
    var requests = 0;
    final api = BrainApi(
      auth,
      client: MockClient.streaming((request, _) async {
        requests++;
        return http.StreamedResponse(
          Stream.value(utf8.encode('${jsonEncode(delta)}\n')),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      }),
    );
    addTearDown(api.dispose);
    await expectLater(
      api.voiceTurn({'turnId': 'one'}, (_) {}),
      throwsA(isA<BrainApiException>()),
    );
    expect(requests, 1);
  });

  test('account change suppresses late streaming data', () async {
    final auth = await login(), network = StreamController<List<int>>();
    final chunks = <Map<String, dynamic>>[];
    final api = BrainApi(
      auth,
      client: MockClient.streaming(
        (request, _) async => http.StreamedResponse(
          network.stream,
          200,
          headers: {'content-type': 'application/x-ndjson'},
        ),
      ),
    );
    addTearDown(api.dispose);
    final result = api.voiceTurn({'turnId': 'one'}, chunks.add);
    final checked = expectLater(result, throwsA(isA<BrainApiException>()));
    await flush();
    await auth.signOut();
    network.add(utf8.encode('${jsonEncode(delta)}\n'));
    await checked;
    await network.close();
    expect(chunks, isEmpty);
  });
}
