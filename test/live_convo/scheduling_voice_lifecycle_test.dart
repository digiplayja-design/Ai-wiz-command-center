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
import 'package:ai_wiz_command_center/live_convo/scheduling_voice_readback.dart';
import 'package:ai_wiz_command_center/scheduling/scheduling_client.dart';
import 'package:ai_wiz_command_center/scheduling/scheduling_voice.dart';
import 'package:ai_wiz_command_center/scheduling/scheduling_voice_panel.dart';

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

class _SchedulingFixture {
  final io = _VoiceIo();
  late final SchedulingClient client = SchedulingClient(
    baseUrl: 'https://k136s.invalid',
    headersBuilder: () => {'Authorization': io.principal},
    sessionChanges: io.authChanges,
    client: MockClient(request),
  );
  late final controller = SchedulingVoiceController(client);
  int prepares = 0, applies = 0, contextReads = 0;
  Completer<http.Response>? prepareGate;
  String state = 'review';
  Map<String, dynamic> get proposal => {
    'id': 'proposal-1',
    'state': state,
    'expires_at': DateTime.now()
        .add(const Duration(minutes: 15))
        .toUtc()
        .toIso8601String(),
    'plan': {
      'action': 'draft',
      'summary': 'Create a test page',
      'data': {
        'title': 'Discovery call',
        'description': '',
        'duration_minutes': 30,
      },
    },
  };
  Future<http.Response> request(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/ai/propose')) {
      prepares++;
      return prepareGate?.future ??
          http.Response(jsonEncode({'proposal': proposal}), 200);
    }
    if (path.endsWith('/apply')) {
      applies++;
      state = 'applied';
      return http.Response(jsonEncode({'proposal': proposal}), 200);
    }
    if (path.endsWith('/ai/proposal-1')) {
      return http.Response(jsonEncode({'proposal': proposal}), 200);
    }
    if (path.endsWith('/voice/context')) {
      contextReads++;
      return http.Response(
        '{"profile_ready":true,"timezone":"America/New_York","events":[],"bookings":[]}',
        200,
      );
    }
    throw StateError('Unexpected scheduling fixture request: $path');
  }

  _VoiceChannel get channel => io.peers.last.channel;
  void event(Map<String, dynamic> event) =>
      channel.onMessage?.call(rtc.RTCDataChannelMessage(jsonEncode(event)));
  void tool({
    String name = 'prepare_scheduling_change',
    String callId = 'tool-1',
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
              name == 'prepare_scheduling_change'
                  ? {'prompt': 'Create a thirty minute discovery call'}
                  : {},
            ),
          },
          ...?extras,
        ],
      },
    });
  }

  void speech(String id, String text, {bool start = true}) {
    if (start) {
      event({'type': 'input_audio_buffer.speech_started', 'item_id': id});
    }
    event({
      'type': 'conversation.item.input_audio_transcription.completed',
      'item_id': id,
      'transcript': text,
    });
  }

  Map<String, dynamic> get readbackRequest => channel.sent.lastWhere(
    (e) =>
        e['type'] == 'response.create' &&
        e['response'] is Map &&
        e['response']['metadata'] is Map &&
        e['response']['metadata']['korlix_scheduling_readback'] != null,
  );
  void finishReadback({
    bool audioStopped = true,
    String? transcript,
    String status = 'completed',
  }) {
    final metadata = readbackRequest['response']['metadata'];
    event({
      'type': 'response.created',
      'response': {'id': 'readback-1', 'metadata': metadata},
    });
    event({'type': 'output_audio_buffer.started', 'response_id': 'readback-1'});
    event({
      'type': 'response.output_audio_transcript.done',
      'response_id': 'readback-1',
      'transcript': transcript ?? controller.readback,
    });
    event({
      'type': 'response.done',
      'response': {'id': 'readback-1', 'status': status, 'output': []},
    });
    if (audioStopped) {
      event({
        'type': 'output_audio_buffer.stopped',
        'response_id': 'readback-1',
      });
    }
  }

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
  Future<void> Function(_SchedulingFixture f) body, {
  bool dedicated = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 1700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final f = _SchedulingFixture();
  await http.runWithClient(
    () async {
      await tester.pumpWidget(
        MaterialApp(
          home: KorlixLiveConvoTestScreen(
            backendBaseUrl: 'https://k136s.invalid',
            headersBuilder: () => {'Authorization': f.io.principal},
            sessionChanges: f.io.authChanges,
            characterId: 'yuna',
            language: 'en',
            k136sIo: f.io,
            schedulingVoice: f.controller,
            schedulingMode: dedicated,
          ),
        ),
      );
      await _pump(tester, 2);
      try {
        await _finish(tester, _stage(tester).onStart!());
        await _pump(tester);
        expect(_stage(tester).connected, isTrue);
        f.event({
          'type': 'response.done',
          'response': {'id': 'greeting', 'status': 'completed', 'output': []},
        });
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
  test('spoken number equivalents retain timezone sign and exact day values', () {
    expect(
      SchedulingVoiceReadbackGuard.normalize(
        'October 1, 2026 at 9 AM. UTC minus 4 hours.',
      ),
      SchedulingVoiceReadbackGuard.normalize(
        'October first, two thousand twenty six at nine a.m. UTC minus four hours.',
      ),
    );
    expect(
      SchedulingVoiceReadbackGuard.normalize('GMT-04:00'),
      isNot(SchedulingVoiceReadbackGuard.normalize('GMT+04:00')),
    );
    expect(
      SchedulingVoiceReadbackGuard.normalize('October 1 at 9 AM'),
      isNot(SchedulingVoiceReadbackGuard.normalize('October 2 at 9 AM')),
    );
  });
  test('readback must finish with complete content and a new speech item', () {
    final guard = SchedulingVoiceReadbackGuard();
    guard.begin('p', 'ticket', 'Move to Friday. Confirm scheduling change.');
    guard.speechStarted('old');
    guard.responseCreated('r', {
      'korlix_scheduling_readback': 'p',
      'korlix_scheduling_ticket': 'ticket',
    });
    guard.transcriptDone('r', 'Move to Friday. Confirm scheduling change.');
    guard.responseDone('r', 'completed');
    expect(guard.armed, isFalse);
    guard.audioStopped('r');
    expect(guard.armed, isTrue);
    expect(guard.consume('old', 'Confirm scheduling change', 'p'), isFalse);
    guard.speechStarted('new');
    expect(
      guard.consume('new', 'Confirm scheduling change', 'other-proposal'),
      isFalse,
    );
    guard.speechStarted('fresh');
    expect(guard.consume('fresh', 'Confirm scheduling change', 'p'), isTrue);
    expect(guard.consume('fresh', 'Confirm scheduling change', 'p'), isFalse);
  });

  test(
    'wrong metadata, abbreviated readback and interrupted audio never arm',
    () {
      for (final scenario in ['metadata', 'abbreviated', 'interrupted']) {
        final guard = SchedulingVoiceReadbackGuard();
        guard.begin(
          'p',
          'ticket',
          'Move Tuesday appointment to Friday. Confirm scheduling change.',
        );
        guard.responseCreated('r', {
          'korlix_scheduling_readback': 'p',
          'korlix_scheduling_ticket': scenario == 'metadata' ? 'old' : 'ticket',
        });
        guard.transcriptDone(
          'r',
          scenario == 'abbreviated'
              ? 'Confirm scheduling change.'
              : 'Move Tuesday appointment to Friday. Confirm scheduling change.',
        );
        guard.responseDone('r', 'completed');
        guard.audioStopped('r', interrupted: scenario == 'interrupted');
        guard.speechStarted('new');
        expect(guard.consume('new', 'Confirm scheduling change', 'p'), isFalse);
      }
    },
  );

  test(
    'newer speech start invalidates an older untranscribed confirmation',
    () {
      final guard = SchedulingVoiceReadbackGuard();
      guard.begin('p', 'ticket', 'Confirm scheduling change.');
      guard.responseCreated('r', {
        'korlix_scheduling_readback': 'p',
        'korlix_scheduling_ticket': 'ticket',
      });
      guard.transcriptDone('r', 'Confirm scheduling change.');
      guard.responseDone('r', 'completed');
      guard.audioStopped('r');
      guard.speechStarted('older');
      guard.speechStarted('newer');
      expect(guard.consume('older', 'Confirm scheduling change', 'p'), isFalse);
    },
  );

  testWidgets(
    'dedicated session registers only scheduling tools and displays exact review',
    (tester) async {
      await _screen(tester, (f) async {
        expect(f.io.requests.single.url.queryParameters['scheduling'], '1');
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
          'get_scheduling_context',
          'find_scheduling_slots',
          'prepare_scheduling_change',
        ]);
        expect(_stage(tester).onOpenAgentHub, isNull);
        expect(_stage(tester).onCreateDocument, isNull);
        f.tool();
        await _pump(tester);
        expect(f.prepares, 1);
        expect(f.applies, 0);
        expect(find.byType(SchedulingVoicePanel), findsOneWidget);
        expect(find.text(f.controller.readback), findsOneWidget);
        expect(f.readbackRequest['response']['tool_choice'], 'none');
      });
    },
  );

  testWidgets(
    'early, stale and generic confirmations cannot apply, fresh exact phrase applies once',
    (tester) async {
      await _screen(tester, (f) async {
        f.tool();
        await _pump(tester);
        f.event({
          'type': 'input_audio_buffer.speech_started',
          'item_id': 'too-early',
        });
        f.finishReadback(audioStopped: false);
        await _pump(tester, 1);
        f.speech('before-audio-end', 'Confirm scheduling change');
        await _pump(tester);
        expect(f.applies, 0);
        f.event({
          'type': 'output_audio_buffer.stopped',
          'response_id': 'readback-1',
        });
        f.speech('too-early', 'Confirm scheduling change', start: false);
        await _pump(tester);
        expect(f.applies, 0);
        f.speech('yes', 'yes');
        await _pump(tester);
        f.speech('after-yes', 'Confirm scheduling change');
        await _pump(tester);
        expect(
          f.applies,
          0,
          reason: 'New instruction invalidated old spoken readback',
        );
        // A deliberate screen approval remains available after a full visible review.
        final panel = tester.widget<SchedulingVoicePanel>(
          find.byType(SchedulingVoicePanel),
        );
        await _finish(tester, panel.onApprove!());
        await _pump(tester);
        expect(f.applies, 1);
        f.speech('repeat', 'Confirm scheduling change');
        await _pump(tester);
        expect(f.applies, 1);
      });
    },
  );

  testWidgets(
    'a complete readback and fresh exact spoken phrase applies once',
    (tester) async {
      await _screen(tester, (f) async {
        f.tool();
        await _pump(tester);
        f.finishReadback();
        await _pump(tester, 1);
        f.speech('confirm-now', 'Confirm scheduling change');
        await _pump(tester);
        expect(f.applies, 1);
        f.speech('confirm-now', 'Confirm scheduling change', start: false);
        await _pump(tester);
        expect(f.applies, 1);
      });
    },
  );

  testWidgets(
    'pause clears proposal and a delayed preparation cannot restore it',
    (tester) async {
      await _screen(tester, (f) async {
        f.prepareGate = Completer<http.Response>();
        f.tool();
        await _pump(tester, 1);
        expect(f.prepares, 1);
        await _finish(tester, _stage(tester).onTogglePause!());
        f.prepareGate!.complete(
          http.Response(jsonEncode({'proposal': f.proposal}), 200),
        );
        await _pump(tester);
        expect(f.controller.pendingProposalId, isNull);
        expect(f.controller.result, isEmpty);
        expect(f.applies, 0);
      });
    },
  );

  testWidgets(
    'account switch clears private result and microphone, preventing approval',
    (tester) async {
      await _screen(tester, (f) async {
        f.tool();
        await _pump(tester);
        f.finishReadback();
        f.io.principal = 'Bearer another-user';
        f.io.authChanges.value++;
        await _pump(tester);
        expect(f.controller.pendingProposalId, isNull);
        expect(f.controller.result, isEmpty);
        expect(f.io.streams.single.audio.enabled, isFalse);
        expect(f.applies, 0);
      });
    },
  );

  testWidgets('mixed, parallel and cancelled tool responses execute nothing', (
    tester,
  ) async {
    await _screen(tester, (f) async {
      f.tool(
        extras: [
          {
            'type': 'function_call',
            'name': 'create_agent_email_draft',
            'call_id': 'email-1',
            'arguments': '{}',
          },
        ],
      );
      await _pump(tester);
      expect(f.prepares, 0);
      f.tool(
        callId: 'parallel',
        extras: [
          {
            'type': 'function_call',
            'name': 'get_scheduling_context',
            'status': 'completed',
            'call_id': 'context-2',
            'arguments': '{}',
          },
        ],
      );
      await _pump(tester);
      expect(f.prepares, 0);
      expect(f.contextReads, 0);
      f.tool(callId: 'cancelled', status: 'cancelled');
      await _pump(tester);
      expect(f.prepares, 0);
      expect(f.applies, 0);
    });
  });

  testWidgets(
    'automatic response created before confirmation cannot prepare another change',
    (tester) async {
      await _screen(tester, (f) async {
        f.tool();
        await _pump(tester);
        f.finishReadback();
        await _pump(tester, 1);
        f.event({
          'type': 'input_audio_buffer.speech_started',
          'item_id': 'approve',
        });
        f.event({
          'type': 'response.created',
          'response': {'id': 'model-automatic', 'metadata': {}},
        });
        f.speech('approve', 'Confirm scheduling change', start: false);
        await _pump(tester);
        expect(f.applies, 1);
        f.tool(callId: 'automatic');
        await _pump(tester);
        expect(f.prepares, 1);
        expect(
          f.channel.sent.any(
            (e) =>
                e['type'] == 'response.cancel' &&
                e['response_id'] == 'model-automatic',
          ),
          isTrue,
        );
      });
    },
  );

  testWidgets(
    'muting invalidates spoken approval but keeps explicit screen approval',
    (tester) async {
      await _screen(tester, (f) async {
        f.tool();
        await _pump(tester);
        f.finishReadback();
        await _pump(tester, 1);
        f.event({
          'type': 'input_audio_buffer.speech_started',
          'item_id': 'before-mute',
        });
        await _finish(tester, _stage(tester).onToggleMute!());
        f.speech('before-mute', 'Confirm scheduling change', start: false);
        await _pump(tester);
        expect(f.applies, 0);
        final panel = tester.widget<SchedulingVoicePanel>(
          find.byType(SchedulingVoicePanel),
        );
        expect(panel.onApprove, isNotNull);
        await _finish(tester, panel.onApprove!());
        await _pump(tester);
        expect(f.applies, 1);
      });
    },
  );

  testWidgets(
    'general LIVE CONVO appends scheduling tools while retaining document tools',
    (tester) async {
      await _screen(tester, (f) async {
        expect(
          f.io.requests.single.url.queryParameters['scheduling_tools'],
          '1',
        );
        final tools =
            f.channel.sent
                    .where(
                      (e) =>
                          e['type'] == 'session.update' &&
                          e['session']['tools'] != null,
                    )
                    .last['session']['tools']
                as List;
        expect(tools.any((t) => t['name'] == 'get_scheduling_context'), isTrue);
        expect(
          tools.any((t) => t['name'] == 'generate_live_docs_report'),
          isTrue,
        );
        expect(_stage(tester).onCreateDocument, isNotNull);
      }, dedicated: false);
    },
  );
}
