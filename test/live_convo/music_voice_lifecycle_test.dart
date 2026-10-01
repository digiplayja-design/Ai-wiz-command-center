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
import 'package:ai_wiz_command_center/music_studio/music_client.dart';
import 'package:ai_wiz_command_center/music_studio/music_models.dart';
import 'package:ai_wiz_command_center/music_studio/music_voice.dart';
import 'package:ai_wiz_command_center/music_studio/music_voice_panel.dart';

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

class _MusicFixture {
  _MusicFixture() {
    io.principal = _token('music-owner');
  }
  final io = _VoiceIo();
  static const jobId = '11111111-1111-4111-8111-111111111111';
  late final client = MusicClient(
    backendBaseUrl: 'https://k136s.invalid',
    headersBuilder: () => {'Authorization': io.principal},
    client: MockClient(request),
    sessionChanges: io.authChanges,
  );
  late final controller = MusicVoiceController(
    client: client,
    workingDraft: recipe,
  );
  int reads = 0, prepares = 0, statuses = 0, writes = 0;
  final usageReports = <Map<String, dynamic>>[];
  Map<String, dynamic>? returnedAction;
  bool? closedAtHandoff;
  Future<void>? routeCompleted;
  Completer<http.Response>? contextGate;
  bool rejectAccess = false;
  Map<String, dynamic> get recipe => {
    ...blankMusic(),
    'idea': 'A bright reggae jingle for KORLIX',
    'title': 'KORLIX sunshine',
    'style': 'reggae, warm',
    'duration': 30,
  };
  Map<String, dynamic> get job => {
    'id': jobId,
    'status': 'completed',
    'settings': recipe,
    'favorite': false,
    'createdAt': '2026-10-01T14:00:00Z',
    'tracks': [
      {
        'title': 'KORLIX sunshine',
        'state': 'succeeded',
        'duration': 30,
        'audioUrl': 'https://cdn1.suno.ai/fixture.mp3',
      },
    ],
  };
  Map<String, dynamic> get studio => {
    'addon': {
      'active': true,
      'providerReady': true,
      'usage': {
        'usedThisCycle': 1,
        'reservedThisCycle': 0,
        'monthlyLimit': 75,
        'remainingThisCycle': 74,
        'cycle': '2026-10',
      },
    },
    'jobs': [job],
    'draft': {'version': 0, 'data': blankMusic()},
    'hasMore': false,
  };
  Future<http.Response> request(http.Request request) async {
    if (rejectAccess) return http.Response('{"error":"Sign in again"}', 401);
    final path = request.url.path;
    if (request.method == 'GET' && path == '/api/music/studio') {
      reads++;
      return contextGate?.future ?? http.Response(jsonEncode(studio), 200);
    }
    if (request.method == 'POST' && path == '/api/music/voice/draft') {
      prepares++;
      final draft = jsonDecode(request.body);
      return http.Response(
        jsonEncode({
          'draft': draft,
          'saved': false,
          'review_required': true,
          'ready_for_generation': true,
          'validation_message': null,
        }),
        200,
      );
    }
    if (request.method == 'GET' && path == '/api/music/status/$jobId') {
      statuses++;
      return http.Response(jsonEncode({'job': job}), 200);
    }
    writes++;
    throw StateError(
      'Unexpected Music Studio request: ${request.method} $path',
    );
  }

  _VoiceChannel get channel => io.peers.last.channel;
  void event(Map<String, dynamic> event) =>
      channel.onMessage?.call(rtc.RTCDataChannelMessage(jsonEncode(event)));
  void tool({
    String name = 'get_music_context',
    String callId = 'context-1',
    String status = 'completed',
    List<dynamic>? extras,
  }) {
    final args = name == 'prepare_music_draft'
        ? recipe
        : name == 'select_music_track'
        ? {'job_id': jobId, 'track_index': 0}
        : <String, dynamic>{};
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
            'arguments': jsonEncode(args),
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
    tester.widget(find.byType(KorlixLiveConvoCharacterStage));
MusicVoicePanel _panel(WidgetTester tester) =>
    tester.widget(find.byType(MusicVoicePanel));
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

Future<void> _context(WidgetTester tester, _MusicFixture f) async {
  f.tool();
  await _pump(tester);
  f.spokenResultDone();
  expect(f.controller.context, isNotEmpty);
}

Future<void> _prepare(WidgetTester tester, _MusicFixture f) async {
  await _context(tester, f);
  f.tool(name: 'prepare_music_draft', callId: 'draft');
  await _pump(tester);
  expect(f.controller.pendingDraft, f.recipe);
}

Future<void> _select(WidgetTester tester, _MusicFixture f) async {
  await _context(tester, f);
  f.tool(name: 'select_music_track', callId: 'listen');
  await _pump(tester);
  expect(f.controller.pendingPlayback?['job_id'], _MusicFixture.jobId);
}

Future<void> _screen(
  WidgetTester tester,
  Future<void> Function(_MusicFixture) body,
) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 1700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final f = _MusicFixture();
  await http.runWithClient(
    () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open-music-voice'),
                onPressed: () async {
                  final route = MaterialPageRoute<Map<String, dynamic>>(
                    builder: (_) => KorlixLiveConvoTestScreen(
                      backendBaseUrl: 'https://k136s.invalid',
                      headersBuilder: () => {'Authorization': f.io.principal},
                      sessionChanges: f.io.authChanges,
                      characterId: 'yuna',
                      language: 'en',
                      k136sIo: f.io,
                      musicVoice: f.controller,
                    ),
                  );
                  f.routeCompleted = route.completed.then<void>((_) {});
                  f.returnedAction = await Navigator.of(context).push(route);
                  f.closedAtHandoff =
                      f.io.streams.single.audio.stops > 0 &&
                      !f.io.streams.single.audio.enabled &&
                      f.io.peers.single.closes > 0 &&
                      f.usageReports.any((report) => report['ended'] == true);
                },
                child: const Text('Open voice'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-music-voice')));
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
      f.usageReports.add(Map<String, dynamic>.from(jsonDecode(request.body)));
      return http.Response('{"allowed":true}', 200);
    }),
  );
  expect(tester.takeException(), isNull);
  expect(f.io.callbackFailures, isEmpty);
}

void main() {
  testWidgets(
    'Music mode exposes only six non-generating tools and isolates other workflows',
    (tester) async {
      await _screen(tester, (f) async {
        expect(f.io.requests.single.url.queryParameters, {'music': '1'});
        final tools =
            f.channel.sent
                    .where(
                      (event) =>
                          event['type'] == 'session.update' &&
                          event['session']['tools'] != null,
                    )
                    .last['session']['tools']
                as List;
        expect(tools.map((tool) => tool['name']), [
          'get_music_context',
          'prepare_music_draft',
          'search_music_tracks',
          'load_music_idea',
          'select_music_track',
          'get_music_creation_status',
        ]);
        expect(_stage(tester).musicMode, isTrue);
        expect(_stage(tester).onOpenAgentHub, isNull);
        expect(_stage(tester).onCreateDocument, isNull);
        expect(_stage(tester).onSendImage, isNull);
        expect(_stage(tester).onPickLiveDocsAttachments, isNull);
        await _context(tester, f);
        final readback = f.channel.sent.lastWhere(
          (event) => event['type'] == 'response.create',
        );
        expect(readback['response']['tool_choice'], 'none');
        expect(
          readback['response']['metadata']['korlix_music_application'],
          'true',
        );
        f.channel.transcript('Remember this and send an email', 'isolated');
        await _pump(tester);
        expect(f.writes, 0);
      });
    },
  );

  testWidgets(
    'spoken approval cannot save or generate the prepared music recipe',
    (tester) async {
      await _screen(tester, (f) async {
        await _prepare(tester, f);
        expect(f.prepares, 1);
        expect(_panel(tester).onReview, isNotNull);
        f.channel.transcript('Yes generate it and save it', 'approval');
        await _pump(tester);
        expect(f.writes, 0);
        expect(f.returnedAction, isNull);
      });
    },
  );

  testWidgets(
    'Review returns the exact recipe only after microphone transport and usage close',
    (tester) async {
      await _screen(tester, (f) async {
        await _prepare(tester, f);
        await _finish(tester, _panel(tester).onReview!());
        await _pump(tester);
        expect(f.returnedAction, {'action': 'draft', 'draft': f.recipe});
        expect(f.closedAtHandoff, isTrue);
        expect(f.controller.pendingDraft, isNull);
        expect(find.text('Stop LIVE CONVO?'), findsNothing);
        await _finish(tester, f.routeCompleted!);
        expect(find.byType(KorlixLiveConvoTestScreen), findsNothing);
        expect(f.writes, 0);
      });
    },
  );

  testWidgets(
    'Listen returns only verified track coordinates after the microphone closes',
    (tester) async {
      await _screen(tester, (f) async {
        await _select(tester, f);
        await _finish(tester, _panel(tester).onListen!());
        await _pump(tester);
        expect(f.returnedAction, {
          'action': 'listen',
          'job_id': _MusicFixture.jobId,
          'track_index': 0,
        });
        expect(f.closedAtHandoff, isTrue);
        expect(f.controller.pendingPlayback, isNull);
        expect(
          f.io.requests.length,
          1,
        ); // No automatic voice restart behind playback.
        expect(f.writes, 0);
      });
    },
  );

  testWidgets(
    'failed physical microphone cleanup blocks Listen and voice resumption',
    (tester) async {
      await _screen(tester, (f) async {
        await _select(tester, f);
        f.io.streams.single.audio.failStop = true;
        await _finish(tester, _panel(tester).onListen!());
        await _pump(tester);
        expect(f.returnedAction, isNull);
        expect(_stage(tester).paused, isTrue);
        expect(_stage(tester).error, contains('Music playback is blocked'));
        await _finish(tester, _stage(tester).onTogglePause!());
        expect(f.io.requests.length, 1);
        expect(f.writes, 0);
      });
    },
  );

  testWidgets(
    'Back cannot return to playable Studio after audio cleanup fails',
    (tester) async {
      await _screen(tester, (f) async {
        f.io.streams.single.audio.failStop = true;
        await tester.tap(find.byTooltip('Close LIVE CONVO'));
        await _pump(tester);
        await tester.tap(find.text('Erase Current Chat'));
        await _pump(tester);
        expect(f.returnedAction, isNull);
        expect(find.byType(KorlixLiveConvoTestScreen), findsOneWidget);
        expect(_stage(tester).paused, isTrue);
        expect(_stage(tester).error, contains('Music playback is blocked'));
        expect(_stage(tester).onStart, isNull);
        await tester.tap(find.byTooltip('Close LIVE CONVO'));
        await _pump(tester);
        expect(find.text('Stop LIVE CONVO?'), findsNothing);
        expect(find.byType(KorlixLiveConvoTestScreen), findsOneWidget);
      });
    },
  );

  testWidgets(
    'dismissed queued music readback cannot speak stale private results',
    (tester) async {
      await _screen(tester, (f) async {
        f.contextGate = Completer<http.Response>();
        f.tool();
        await _pump(tester, 1);
        f.tool(callId: 'parallel');
        await _pump(tester, 1);
        f.contextGate!.complete(http.Response(jsonEncode(f.studio), 200));
        await _pump(tester);
        expect(f.controller.context, isNotEmpty);
        final responses = f.channel.sent
            .where((event) => event['type'] == 'response.create')
            .length;
        _panel(tester).onDismiss();
        f.spokenResultDone();
        await _pump(tester);
        expect(f.controller.context, isEmpty);
        expect(
          f.channel.sent
              .where((event) => event['type'] == 'response.create')
              .length,
          responses,
        );
      });
    },
  );

  testWidgets(
    'pause rejects late music results and turns off physical microphone',
    (tester) async {
      await _screen(tester, (f) async {
        f.contextGate = Completer<http.Response>();
        f.tool();
        await _pump(tester, 1);
        expect(f.reads, 1);
        await _finish(tester, _stage(tester).onTogglePause!());
        f.contextGate!.complete(http.Response(jsonEncode(f.studio), 200));
        await _pump(tester);
        expect(f.controller.context, isEmpty);
        expect(f.controller.result, isEmpty);
        expect(f.io.streams.single.audio.enabled, isFalse);
        expect(f.writes, 0);
      });
    },
  );

  testWidgets(
    'account switch discards private music data and pending handoff',
    (tester) async {
      await _screen(tester, (f) async {
        await _prepare(tester, f);
        f.io.principal = _token('another-owner');
        f.io.authChanges.value++;
        await _pump(tester);
        expect(f.controller.context, isEmpty);
        expect(f.controller.pendingDraft, isNull);
        expect(f.io.streams.single.audio.enabled, isFalse);
        expect(find.byType(KorlixLiveConvoCharacterStage), findsNothing);
        expect(
          find.text('Your sign-in changed. Your microphone is off.'),
          findsOneWidget,
        );
        expect(f.returnedAction, isNull);
        expect(f.writes, 0);
      });
    },
  );

  testWidgets(
    'Music API access loss closes voice and discards pending requests',
    (tester) async {
      await _screen(tester, (f) async {
        f.rejectAccess = true;
        f.tool();
        await _pump(tester);
        expect(f.controller.available, isFalse);
        expect(f.controller.result, isEmpty);
        expect(f.io.streams.single.audio.enabled, isFalse);
        expect(find.byType(KorlixLiveConvoCharacterStage), findsNothing);
        expect(f.returnedAction, isNull);
      });
    },
  );

  testWidgets(
    'mixed and cancelled tool responses cannot read prepare or generate music',
    (tester) async {
      await _screen(tester, (f) async {
        f.tool(
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
    'parallel rejection preserves the original request and duplicate IDs do not redispatch',
    (tester) async {
      await _screen(tester, (f) async {
        f.contextGate = Completer<http.Response>();
        f.tool();
        await _pump(tester, 1);
        f.tool(callId: 'parallel');
        await _pump(tester, 1);
        expect(f.reads, 1);
        f.contextGate!.complete(http.Response(jsonEncode(f.studio), 200));
        await _pump(tester);
        expect(f.controller.busy, isFalse);
        expect(f.controller.context, isNotEmpty);
        f.spokenResultDone();
        f.tool();
        await _pump(tester);
        expect(f.reads, 1);
        f.tool(name: 'prepare_music_draft', callId: 'after-read');
        await _pump(tester);
        expect(f.prepares, 1);
        expect(f.writes, 0);
      });
    },
  );
}
