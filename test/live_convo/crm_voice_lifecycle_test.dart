import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_character_stage.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_test_screen.dart';
import 'package:ai_wiz_command_center/contacts_crm/contacts_client.dart';
import 'package:ai_wiz_command_center/contacts_crm/crm_voice.dart';
import 'package:ai_wiz_command_center/contacts_crm/crm_voice_panel.dart';

class _VoiceObservedFake extends Fake {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    debugPrint('F5_MISSING_FAKE_MEMBER=$runtimeType:${invocation.memberName}');
    return super.noSuchMethod(invocation);
  }
}

class _VoiceTrack extends _VoiceObservedFake implements rtc.MediaStreamTrack {
  @override
  bool enabled = true;
  int stops = 0;
  bool failStop = false;
  @override
  String get id => 'fixture-audio';
  @override
  String get kind => 'audio';
  @override
  Future<void> stop() async {
    enabled = false;
    stops++;
    if (failStop) throw StateError('Fixture track cleanup failed');
  }
}

class _VoiceStream extends _VoiceObservedFake implements rtc.MediaStream {
  final audio = _VoiceTrack();
  final extraTracks = <_VoiceTrack>[];
  int disposals = 0;
  @override
  List<rtc.MediaStreamTrack> getAudioTracks() => [audio, ...extraTracks];
  @override
  List<rtc.MediaStreamTrack> getTracks() => [audio, ...extraTracks];
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _VoiceChannel extends _VoiceObservedFake implements rtc.RTCDataChannel {
  @override
  rtc.RTCDataChannelState state =
      rtc.RTCDataChannelState.RTCDataChannelConnecting;
  @override
  dynamic Function(rtc.RTCDataChannelState)? onDataChannelState;
  @override
  dynamic Function(rtc.RTCDataChannelMessage)? onMessage;
  int closes = 0;
  void open() {
    state = rtc.RTCDataChannelState.RTCDataChannelOpen;
    onDataChannelState?.call(state);
  }

  void transcript(String text, String id) {
    onMessage?.call(
      rtc.RTCDataChannelMessage(
        jsonEncode({
          'type': 'conversation.item.input_audio_transcription.completed',
          'transcript': text,
          'item_id': id,
        }),
      ),
    );
  }

  final List<Map<String, dynamic>> sent = [];
  @override
  Future<void> send(rtc.RTCDataChannelMessage message) async {
    sent.add(Map<String, dynamic>.from(jsonDecode(message.text)));
  }

  @override
  Future<void> close() async {
    closes++;
    state = rtc.RTCDataChannelState.RTCDataChannelClosed;
    onDataChannelState?.call(state);
  }
}

class _VoiceSender extends _VoiceObservedFake implements rtc.RTCRtpSender {}

class _VoicePeer extends _VoiceObservedFake implements rtc.RTCPeerConnection {
  final channel = _VoiceChannel();
  Completer<void>? answerGate;
  bool autoOpenChannel = true;
  int closes = 0, disposals = 0, answers = 0;
  @override
  dynamic Function(rtc.RTCPeerConnectionState)? onConnectionState;
  @override
  dynamic Function(rtc.RTCIceConnectionState)? onIceConnectionState;
  @override
  dynamic Function(rtc.RTCIceGatheringState)? onIceGatheringState;
  @override
  dynamic Function(rtc.MediaStream)? onAddStream;
  @override
  dynamic Function(rtc.RTCTrackEvent)? onTrack;
  void connected() => onConnectionState?.call(
    rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected,
  );
  void disconnected() => onConnectionState?.call(
    rtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
  );
  @override
  Future<rtc.RTCRtpSender> addTrack(
    rtc.MediaStreamTrack track, [
    rtc.MediaStream? stream,
  ]) async => _VoiceSender();
  @override
  Future<rtc.RTCDataChannel> createDataChannel(
    String label,
    rtc.RTCDataChannelInit dataChannelDict,
  ) async => channel;
  @override
  Future<rtc.RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async => rtc.RTCSessionDescription('v=0\r\n', 'offer');
  @override
  Future<void> setLocalDescription(
    rtc.RTCSessionDescription description,
  ) async {}
  @override
  Future<rtc.RTCIceGatheringState?> getIceGatheringState() async =>
      rtc.RTCIceGatheringState.RTCIceGatheringStateComplete;
  @override
  Future<rtc.RTCSessionDescription?> getLocalDescription() async =>
      rtc.RTCSessionDescription('v=0\r\n', 'offer');
  @override
  Future<void> setRemoteDescription(
    rtc.RTCSessionDescription description,
  ) async {
    answers++;
    connected();
    if (autoOpenChannel) channel.open();
    if (answerGate != null) await answerGate!.future;
  }

  @override
  Future<void> close() async {
    closes++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _VoiceIo extends K136sLiveConvoIo {
  final callbackFailures = <String>[];
  void expectCallback(Object? actual, Object? matcher) {
    try {
      // Device/network callbacks can run while WidgetTester.pump is active.
      expectSync(actual, matcher);
    } catch (error) {
      // Application error handling must not hide a fixture-contract failure.
      callbackFailures.add(error.toString());
      rethrow;
    }
  }

  final peers = <_VoicePeer>[];
  final streams = <_VoiceStream>[];
  Completer<rtc.RTCPeerConnection>? peerGate;
  Completer<rtc.MediaStream>? micGate;
  Completer<void>? answerGate;
  Completer<http.Response>? responseGate;
  final requests = <http.Request>[];
  bool rejectSession = false;
  bool autoOpenChannel = true;
  final authChanges = ValueNotifier<int>(0);
  String principal = 'Bearer fixture';
  String character = 'yuna';
  @override
  Future<void> initializeRenderer(rtc.RTCVideoRenderer renderer) async {}
  @override
  void clearRenderer(rtc.RTCVideoRenderer renderer) {}
  @override
  Future<void> disposeRenderer(rtc.RTCVideoRenderer renderer) async {}
  @override
  Future<void> muteNative(bool muted, rtc.MediaStreamTrack track) async {}
  @override
  Future<void> prepareAudio() async {}
  @override
  Future<void> configureAudio() async {}
  @override
  Future<void> clearAudio() async {}
  @override
  Future<rtc.RTCPeerConnection> createPeer(Map<String, dynamic> configuration) {
    final pending = peerGate;
    peerGate = null;
    if (pending != null) return pending.future;
    final peer = _VoicePeer()
      ..answerGate = answerGate
      ..autoOpenChannel = autoOpenChannel;
    answerGate = null;
    peers.add(peer);
    return Future<rtc.RTCPeerConnection>.value(peer);
  }

  @override
  Future<rtc.MediaStream> microphone(Map<String, dynamic> constraints) {
    final pending = micGate;
    micGate = null;
    if (pending != null) return pending.future;
    final stream = _VoiceStream();
    streams.add(stream);
    return Future<rtc.MediaStream>.value(stream);
  }

  http.Response response(http.Request request) => http.Response(
    rejectSession ? 'fixture connection refused' : 'v=0\r\n',
    rejectSession ? 503 : 200,
    request: request,
    headers: {
      'x-korlix-live-convo-session-id': 'fixture-${requests.length}',
      'x-korlix-live-convo-max-seconds': '600',
      'x-korlix-live-convo-max-responses': '100',
    },
  );
  @override
  Future<http.Response> connect(
    Uri uri,
    Map<String, String> headers,
    String sdp,
  ) {
    expectCallback(uri.host, 'k136s.invalid');
    final request = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = sdp;
    requests.add(request);
    final pending = responseGate;
    responseGate = null;
    return pending?.future ?? Future<http.Response>.value(response(request));
  }
}

String _token(String subject) =>
    'Bearer fixture.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'fixture', 'sub': subject, 'session_id': 'fixture-session'}))).replaceAll('=', '')}.signature';

class _FieldFixture {
  _FieldFixture() {
    io.principal = _token('field-owner');
  }
  final io = _VoiceIo();
  static const id = '11111111-1111-4111-8111-111111111111';
  static const memberId = '22222222-2222-4222-8222-222222222222';
  late final client = ContactsClient(
    backendBaseUrl: 'https://k136s.invalid',
    headersBuilder: () => {'Authorization': io.principal},
    client: MockClient(request),
    sessionChanges: io.authChanges,
  );
  late final controller = CrmVoiceController(
    client: client,
  );
  Map<String, dynamic> get workspace => {'contacts':[{'id':id,'name':'Sam','version':1,'email':'sam@example.com','email_permission':'transactional'}],'scope':'Your CRM contacts'};
  int reads = 0, prepares = 0, writes = 0;
  bool rejectAccess = false;
  Completer<http.Response>? contextGate;
  Map<String, dynamic>? returnedAction;
  bool? closedAtHandoff;
  final usageReports = <Map<String, dynamic>>[];
  Future<http.Response> request(http.Request request) async {
    if (rejectAccess) return http.Response('{"error":"Sign in again"}', 401);
    final path = request.url.path;
    if (request.method == 'GET' && path == '/api/contacts/voice/context') {
      reads++;
      return contextGate?.future ?? http.Response(jsonEncode(workspace), 200);
    }
    if (request.method == 'POST' && path == '/api/contacts/voice/draft') {
      prepares++;
      final body = jsonDecode(request.body);
      return http.Response(
        jsonEncode({
          'action': body['action'],
          'draft': body['payload'],
          'contact_version': 1,
          'contact_id': id,
          'contact_name': 'Sam',
          'saved': false,
          'reviewRequired': true,
        }),
        200,
      );
    }
    writes++;
    throw StateError('Unexpected write ${request.method} $path');
  }

  _VoiceChannel get channel => io.peers.last.channel;
  void event(Map<String, dynamic> e) =>
      channel.onMessage?.call(rtc.RTCDataChannelMessage(jsonEncode(e)));
  void tool({
    String name = 'get_crm_context',
    String callId = 'context',
    String status = 'completed',
    Map<String, dynamic> args = const {},
    List<dynamic> extras = const [],
  }) => event({
    'type': 'response.done',
    'response': {
      'id': 'response-$callId',
      'status': status,
      'output': [
        {
          'type': 'function_call',
          'status': 'completed',
          'name': name,
          'call_id': callId,
          'arguments': jsonEncode(args),
        },
        ...extras,
      ],
    },
  });
  void spokenDone() => event({
    'type': 'response.done',
    'response': {'id': 'readback', 'status': 'completed', 'output': []},
  });
  void dispose() {
    controller.dispose();
    client.dispose();
    io.authChanges.dispose();
  }
}

KorlixLiveConvoCharacterStage _stage(WidgetTester t) =>
    t.widget(find.byType(KorlixLiveConvoCharacterStage));
CrmVoicePanel _panel(WidgetTester t) =>
    t.widget(find.byType(CrmVoicePanel));
Future<void> _pump(WidgetTester t, [int count = 12]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _finish(WidgetTester t, Future<void> operation) async {
  var done = false;
  final result = operation.whenComplete(() => done = true);
  for (var i = 0; i < 120 && !done; i++) {
    await t.pump(const Duration(milliseconds: 25));
  }
  expect(done, isTrue);
  await result;
}

Future<void> _prepare(WidgetTester t, _FieldFixture f) async {
  f.tool();
  await _pump(t);
  f.spokenDone();
  expect(f.controller.context, isNotEmpty);
  f.tool(
    name: 'draft_crm_email',callId: 'draft',args:{'contact_id':_FieldFixture.id,'subject':'Following up','body':'Any update?'});
  await _pump(t);
  expect(
    f.controller.pendingDraft?['draft']['subject'],
    'Following up',
  );
}

Future<void> _screen(
  WidgetTester t,
  Future<void> Function(_FieldFixture) body,
) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(1200, 1700);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final f = _FieldFixture();
  await http.runWithClient(
    () async {
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open-field-voice'),
                onPressed: () async {
                  final route = MaterialPageRoute<Map<String, dynamic>>(
                    builder: (_) => KorlixLiveConvoTestScreen(
                      backendBaseUrl: 'https://k136s.invalid',
                      headersBuilder: () => {'Authorization': f.io.principal},
                      sessionChanges: f.io.authChanges,
                      characterId: 'yuna',
                      language: 'en',
                      k136sIo: f.io,
                      crmVoice: f.controller,
                    ),
                  );
                  f.returnedAction = await Navigator.of(context).push(route);
                  f.closedAtHandoff =
                      f.io.streams.single.audio.stops > 0 &&
                      !f.io.streams.single.audio.enabled &&
                      f.io.peers.single.closes > 0 &&
                      f.usageReports.any((x) => x['ended'] == true);
                },
                child: const Text('Open voice'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const Key('open-field-voice')));
      await _pump(t);
      try {
        await _finish(t, _stage(t).onStart!());
        await _pump(t);
        expect(_stage(t).connected, isTrue);
        f.spokenDone();
        await body(f);
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        await _pump(t);
        f.dispose();
      }
    },
    () => MockClient((request) async {
      expectSync(request.url.path, '/api/live-convo/usage');
      f.usageReports.add(Map<String, dynamic>.from(jsonDecode(request.body)));
      return http.Response('{"allowed":true}', 200);
    }),
  );
  expect(t.takeException(), isNull);
  expect(f.io.callbackFailures, isEmpty);
}

void main() {
  testWidgets(
    'Crm voice uses five isolated tools and existing allowance',
    (t) async {
      await _screen(t, (f) async {
        expect(f.io.requests.single.url.queryParameters, {
          'crm': '1',
        });
        final tools =
            f.channel.sent
                    .where(
                      (e) =>
                          e['type'] == 'session.update' &&
                          e['session']['tools'] != null,
                    )
                    .last['session']['tools']
                as List;
        expect(
          tools.map((x) => x['name']),
          crmVoiceTools.map((x) => x['name']),
        );
        expect(_stage(t).crmMode, isTrue);
        expect(_stage(t).onOpenAgentHub, isNull);
        expect(_stage(t).onCreateDocument, isNull);
        expect(_stage(t).onSendImage, isNull);
        f.tool();
        await _pump(t);
        final readback = f.channel.sent.lastWhere(
          (e) => e['type'] == 'response.create',
        );
        expect(readback['response']['tool_choice'], 'none');
        expect(
          readback['response']['metadata']['korlix_crm_application'],
          'true',
        );
        expect(f.writes, 0);
      });
    },
  );
  testWidgets(
    'spoken approval does not save; review hands off exact draft after physical cleanup',
    (t) async {
      await _screen(t, (f) async {
        await _prepare(t, f);
        final expected = f.controller.pendingDraft;
        f.channel.transcript('Yes approve and save everything', 'approval');
        await _pump(t);
        expect(f.writes, 0);
        expect(f.returnedAction, isNull);
        await _finish(t, _panel(t).onReview!());
        await _pump(t);
        expect(f.returnedAction, expected);
        expect(f.closedAtHandoff, isTrue);
        expect(f.controller.pendingDraft, isNull);
        expect(f.writes, 0);
      });
    },
  );
  testWidgets('pause discards late private results and stops the microphone', (
    t,
  ) async {
    await _screen(t, (f) async {
      f.contextGate = Completer<http.Response>();
      f.tool();
      await _pump(t, 1);
      expect(f.reads, 1);
      await _finish(t, _stage(t).onTogglePause!());
      f.contextGate!.complete(http.Response(jsonEncode(f.workspace), 200));
      await _pump(t);
      expect(f.controller.context, isEmpty);
      expect(f.controller.result, isEmpty);
      expect(f.io.streams.single.audio.enabled, isFalse);
    });
  });
  testWidgets('account switch clears private draft and closes capture', (
    t,
  ) async {
    await _screen(t, (f) async {
      await _prepare(t, f);
      f.io.principal = _token('other-owner');
      f.io.authChanges.value++;
      await _pump(t);
      expect(f.controller.pendingDraft, isNull);
      expect(f.controller.context, isEmpty);
      expect(f.io.streams.single.audio.enabled, isFalse);
      expect(find.byType(KorlixLiveConvoCharacterStage), findsNothing);
      expect(f.returnedAction, isNull);
    });
  });
  testWidgets(
    'failed microphone cleanup blocks draft handoff and voice resumption',
    (t) async {
      await _screen(t, (f) async {
        await _prepare(t, f);
        f.io.streams.single.audio.failStop = true;
        await _finish(t, _panel(t).onReview!());
        await _pump(t);
        expect(f.returnedAction, isNull);
        expect(_stage(t).paused, isTrue);
        expect(_stage(t).error, contains('reopening CRM'));
        await _finish(t, _stage(t).onTogglePause!());
        expect(f.io.requests.length, 1);
      });
    },
  );
  testWidgets('API access loss clears data and closes capture', (t) async {
    await _screen(t, (f) async {
      f.rejectAccess = true;
      f.tool();
      await _pump(t);
      expect(f.controller.available, isFalse);
      expect(f.controller.result, isEmpty);
      expect(f.io.streams.single.audio.enabled, isFalse);
      expect(f.writes, 0);
    });
  });
  testWidgets(
    'mixed cancelled duplicate and parallel calls never dispatch unintended work',
    (t) async {
      await _screen(t, (f) async {
        f.tool(
          callId: 'mixed',
          extras: [
            {
              'type': 'function_call',
              'status': 'completed',
              'name': 'create_agent_email_draft',
              'call_id': 'email',
              'arguments': '{}',
            },
          ],
        );
        await _pump(t);
        f.spokenDone();
        f.tool(callId: 'cancelled', status: 'cancelled');
        await _pump(t);
        expect(f.reads, 0);
        f.spokenDone();
        f.contextGate = Completer<http.Response>();
        f.tool();
        await _pump(t, 1);
        f.tool(callId: 'parallel');
        await _pump(t, 1);
        expect(f.reads, 1);
        f.contextGate!.complete(http.Response(jsonEncode(f.workspace), 200));
        await _pump(t);
        f.spokenDone();
        f.tool();
        await _pump(t);
        expect(f.reads, 1);
        expect(f.writes, 0);
      });
    },
  );
}
