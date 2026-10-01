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
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_client.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_voice.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_voice_panel.dart';

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
  @override
  String get id => 'fixture-audio';
  @override
  String get kind => 'audio';
  @override
  Future<void> stop() async {
    enabled = false;
    stops++;
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

class _BookkeepingFixture {
  final io = _VoiceIo();
  static const businessId = '11111111-1111-4111-8111-111111111111';
  final month =
      '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
  late final client = BookkeepingClient(
    backendBaseUrl: 'https://k136s.invalid',
    headersBuilder: () => {'Authorization': io.principal},
    client: MockClient(request),
  );
  late final controller = BookkeepingVoiceController(
    client: client,
    businessId: businessId,
    businessName: 'Fixture business',
    month: month,
  );
  int reads = 0, prepares = 0, writes = 0;
  Map<String, dynamic>? returnedDraft;
  Future<void>? routeCompleted;
  Completer<http.Response>? contextGate;
  Map<String, dynamic> get context => {
    'business': {
      'id': businessId,
      'name': 'Fixture business',
      'currency': 'USD',
      'basis': 'cash',
    },
    'month': month,
    'from_date': '$month-01',
    'as_of': '$month-01',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'summary': {
      'income_cents': '123450',
      'expense_cents': '34550',
      'net_cents': '88900',
    },
    'categories': [
      {
        'code': '5000',
        'name': 'Office supplies',
        'kind': 'expense',
        'amount_cents': '34550',
      },
    ],
    'cash_accounts': [
      {'code': '1000', 'name': 'Recorded cash control'},
    ],
    'scope': 'Recorded activity, not bank balance',
    'warnings': [],
    'opening_date': '2026-01-01',
  };
  Map<String, dynamic> get draft => {
    'business_id': businessId,
    'kind': 'expense',
    'amount': '125.50',
    'entry_date': '$month-01',
    'category': '5000',
    'cash_account': '1000',
    'purpose': 'Office supplies',
    'counterparty': 'Fixture store',
    'receipt_reference': '',
  };
  Future<http.Response> request(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/voice/context')) {
      reads++;
      return contextGate?.future ?? http.Response(jsonEncode(context), 200);
    }
    if (path.endsWith('/voice/draft')) {
      prepares++;
      return http.Response(
        jsonEncode({'draft': draft, 'saved': false, 'review_required': true}),
        200,
      );
    }
    writes++;
    throw StateError('Unexpected bookkeeping request: $path');
  }

  _VoiceChannel get channel => io.peers.last.channel;
  void event(Map<String, dynamic> event) =>
      channel.onMessage?.call(rtc.RTCDataChannelMessage(jsonEncode(event)));
  void tool({
    String name = 'get_bookkeeping_context',
    String callId = 'context-1',
    String status = 'completed',
    List<dynamic>? extras,
  }) {
    event({
      'type': 'response.done',
      'response': {
        'id': 'model-$callId',
        'status': status,
        'output': [
          {
            'type': 'function_call',
            'status': 'completed',
            'name': name,
            'call_id': callId,
            'arguments': jsonEncode(
              name == 'prepare_bookkeeping_entry'
                  ? (Map<String, dynamic>.from(draft)..remove('business_id'))
                  : {},
            ),
          },
          ...?extras,
        ],
      },
    });
  }

  void spokenResultDone() => event({
    'type': 'response.done',
    'response': {'id': 'readback', 'status': 'completed', 'output': []},
  });
  void dispose() {
    controller.dispose();
    client.dispose();
    io.authChanges.dispose();
  }
}

KorlixLiveConvoCharacterStage _stage(WidgetTester tester) =>
    tester.widget<KorlixLiveConvoCharacterStage>(
      find.byType(KorlixLiveConvoCharacterStage),
    );
Future<void> _pump(WidgetTester tester, [int count = 12]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _finish(WidgetTester tester, Future<void> operation) async {
  var done = false;
  final result = operation.whenComplete(() {
    done = true;
  });
  for (var i = 0; i < 120 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(done, isTrue);
  await result;
}

Future<void> _screen(
  WidgetTester tester,
  Future<void> Function(_BookkeepingFixture) body,
) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 1700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final f = _BookkeepingFixture();
  await http.runWithClient(
    () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open-bookkeeping-voice'),
                onPressed: () async {
                  final route = MaterialPageRoute<Map<String, dynamic>>(
                    builder: (_) => KorlixLiveConvoTestScreen(
                      backendBaseUrl: 'https://k136s.invalid',
                      headersBuilder: () => {'Authorization': f.io.principal},
                      sessionChanges: f.io.authChanges,
                      characterId: 'yuna',
                      language: 'en',
                      k136sIo: f.io,
                      bookkeepingVoice: f.controller,
                    ),
                  );
                  f.routeCompleted = route.completed.then<void>((_) {});
                  f.returnedDraft = await Navigator.of(context).push(route);
                },
                child: const Text('Open voice'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-bookkeeping-voice')));
      await _pump(tester);
      try {
        await _finish(tester, _stage(tester).onStart!());
        await _pump(tester);
        expect(_stage(tester).connected, isTrue);
        f.spokenResultDone();
        await body(f);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pump(tester);
        f.dispose();
      }
    },
    () => MockClient((request) async {
      expectSync(request.url.path, '/api/live-convo/usage');
      return http.Response('{"allowed":true}', 200);
    }),
  );
  expect(tester.takeException(), isNull);
  expect(f.io.callbackFailures, isEmpty);
}

void main() {
  testWidgets(
    'bookkeeping binds session business and exposes only read and draft tools',
    (tester) async {
      await _screen(tester, (f) async {
        final query = f.io.requests.single.url.queryParameters;
        expect(query['bookkeeping'], '1');
        expect(
          query['bookkeeping_business_id'],
          _BookkeepingFixture.businessId,
        );
        expect(query['bookkeeping_month'], f.month);
        final tools =
            f.channel.sent
                    .where(
                      (e) =>
                          e['type'] == 'session.update' &&
                          e['session']['tools'] != null,
                    )
                    .last['session']['tools']
                as List;
        expect(tools.map((t) => t['name']), [
          'get_bookkeeping_context',
          'prepare_bookkeeping_entry',
        ]);
        expect(_stage(tester).onOpenAgentHub, isNull);
        expect(_stage(tester).onCreateDocument, isNull);
        expect(_stage(tester).onSendImage, isNull);
        expect(_stage(tester).onPickLiveDocsAttachments, isNull);
        f.tool();
        await _pump(tester);
        expect(f.reads, 1);
        expect(f.writes, 0);
        final readback = f.channel.sent.lastWhere(
          (e) => e['type'] == 'response.create',
        );
        expect(readback['response']['tool_choice'], 'none');
        expect(
          readback['response']['metadata']['korlix_bookkeeping_application'],
          'true',
        );
      });
    },
  );

  testWidgets('a prepared expense remains an unsaved visible review', (
    tester,
  ) async {
    await _screen(tester, (f) async {
      f.tool();
      await _pump(tester);
      f.spokenResultDone();
      f.tool(name: 'prepare_bookkeeping_entry', callId: 'draft-1');
      await _pump(tester);
      expect(f.prepares, 1);
      expect(f.writes, 0);
      expect(f.controller.pendingDraft?['amount'], '125.50');
      expect(find.byType(BookkeepingVoicePanel), findsOneWidget);
      expect(
        tester
            .widget<BookkeepingVoicePanel>(find.byType(BookkeepingVoicePanel))
            .onReview,
        isNotNull,
      );
      f.channel.transcript('Yes save it', 'approval');
      await _pump(tester);
      expect(f.writes, 0);
    });
  });

  testWidgets(
    'Review entry closes the actual voice transport before returning the unchanged draft',
    (tester) async {
      await _screen(tester, (f) async {
        f.tool();
        await _pump(tester);
        f.spokenResultDone();
        f.tool(name: 'prepare_bookkeeping_entry', callId: 'review-draft');
        await _pump(tester);
        final panel = tester.widget<BookkeepingVoicePanel>(
          find.byType(BookkeepingVoicePanel),
        );
        await _finish(tester, panel.onReview!());
        await _pump(tester);
        expect(f.returnedDraft, f.draft);
        expect(f.io.streams.single.audio.enabled, isFalse);
        expect(f.io.streams.single.audio.stops, greaterThan(0));
        expect(f.io.peers.single.closes, greaterThan(0));
        expect(f.controller.pendingDraft, isNull);
        expect(find.text('Stop LIVE CONVO?'), findsNothing);
        // Pop returns the draft before the outgoing Material route finishes
        // its transition. Await route completion before asserting disposal.
        await _finish(tester, f.routeCompleted!);
        expect(find.byType(KorlixLiveConvoTestScreen), findsNothing);
        expect(f.writes, 0);
      });
    },
  );

  testWidgets(
    'pause and account switch discard late financial context and turn microphone off',
    (tester) async {
      await _screen(tester, (f) async {
        f.contextGate = Completer<http.Response>();
        f.tool();
        await _pump(tester, 1);
        expect(f.reads, 1);
        await _finish(tester, _stage(tester).onTogglePause!());
        f.contextGate!.complete(http.Response(jsonEncode(f.context), 200));
        await _pump(tester);
        expect(f.controller.result, isEmpty);
        expect(f.controller.pendingDraft, isNull);
        expect(f.io.streams.single.audio.enabled, isFalse);
        expect(f.writes, 0);
      });
      await _screen(tester, (f) async {
        f.tool();
        await _pump(tester);
        f.io.principal = 'Bearer another-user';
        f.io.authChanges.value++;
        await _pump(tester);
        expect(f.controller.result, isEmpty);
        expect(f.io.streams.single.audio.enabled, isFalse);
        expect(f.writes, 0);
      });
    },
  );

  testWidgets(
    'mixed and cancelled responses cannot read or prepare bookkeeping',
    (tester) async {
      await _screen(tester, (f) async {
        f.tool(
          extras: [
            {
              'type': 'function_call',
              'status': 'completed',
              'name': 'create_agent_email_draft',
              'call_id': 'email-1',
              'arguments': '{}',
            },
          ],
        );
        await _pump(tester);
        f.spokenResultDone();
        f.tool(callId: 'cancelled', status: 'cancelled');
        await _pump(tester);
        expect(f.reads, 0);
        expect(f.prepares, 0);
        expect(f.writes, 0);
      });
    },
  );

  testWidgets(
    'parallel request rejection does not strand the original request',
    (tester) async {
      await _screen(tester, (f) async {
        f.contextGate = Completer<http.Response>();
        f.tool();
        await _pump(tester, 1);
        f.tool(callId: 'parallel');
        await _pump(tester, 1);
        expect(f.reads, 1);
        f.contextGate!.complete(http.Response(jsonEncode(f.context), 200));
        await _pump(tester);
        expect(f.controller.busy, isFalse);
        expect(f.controller.result, isNotEmpty);
        f.spokenResultDone();
        f.tool(name: 'prepare_bookkeeping_entry', callId: 'draft-after-read');
        await _pump(tester);
        expect(f.prepares, 1);
      });
    },
  );
}
