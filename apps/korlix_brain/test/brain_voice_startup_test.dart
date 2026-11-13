import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korlix_brain/brain_api.dart';
import 'package:korlix_brain/brain_auth.dart';
import 'package:korlix_brain/brain_voice.dart';
import 'package:korlix_brain/brain_projection.dart';
import 'package:korlix_receipt_core/auth/korlix_session_refresh.dart';

// Exercise the real voice coordinator, HTTP usage guard and WebRTC Dart
// wrappers. Only the HTTP service and native plugin boundary are simulated.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _VoiceHarness h;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    h = _VoiceHarness();
  });
  tearDown(() async {
    await h.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  test('background Pause is a no-op for an idle conversation', () async {
    await h.voice.pause(reason: 'app_backgrounded');
    expect(h.voice.active, isFalse);
    expect(h.voice.paused, isFalse);
    expect(h.calls, isEmpty);
    expect(h.sessionRequests, 0);
  });

  test('background Pause cancels a start before native capture is allocated', () async {
    final starting = h.voice.start();
    await h.voice.pause(reason: 'app_backgrounded');
    await starting;
    expect(h.voice.active, isFalse);
    expect(h.voice.paused, isTrue);
    expect(h.sessionRequests, 0);
    expect(h.calls.where((call) => call.method == 'getUserMedia'), isEmpty);

    await Future<void>.delayed(Duration.zero);
    expect(h.sessionRequests, 0, reason: 'Foreground presentation must not auto-start capture.');
    await h.voice.resume();
    expect(h.voice.active, isTrue);
    expect(h.sessionRequests, 1);
  });

  test('background Pause cannot revive a start already canceled by Stop', () async {
    final starting = h.voice.start();
    final stopping = h.voice.stop();
    await h.voice.pause(reason: 'app_backgrounded');
    await Future.wait([starting, stopping]);
    expect(h.voice.active, isFalse);
    expect(h.voice.paused, isFalse);
    expect(h.sessionRequests, 0);
    await h.voice.resume();
    expect(h.voice.paused, isFalse);
    expect(h.sessionRequests, 0);
  });

  test(
    'post-200 server contract failure closes and meters the allocated call',
    () async {
      h.sessionHeaders['x-korlix-brain-model'] = 'unexpected-model';

      await expectLater(h.voice.start(), throwsA(isA<BrainApiException>()));

      expect(h.sessionRequests, 1);
      expect(h.usage.first['ended'], isFalse);
      expect(h.usage.last['ended'], isTrue);
      expect(h.usage.last['endReason'], 'startup_server_contract');
      expect(h.microphoneEnabled, isNot(contains(true)));
      expect(
        h.calls.map((c) => c.method),
        containsAll(['trackDispose', 'peerConnectionClose']),
      );
      expect(h.voice.active, isFalse);
      expect(
        h.events.last['message'],
        contains('not available on this server'),
      );
    },
  );

  test(
    'remote SDP failure closes with its stage without leaking platform details',
    () async {
      h.failRemoteDescription = true;

      await expectLater(h.voice.start(), throwsA(anything));

      expect(h.sessionRequests, 1);
      expect(h.usage.last['ended'], isTrue);
      expect(h.usage.last['endReason'], 'startup_remote_description');
      expect(h.microphoneEnabled, isNot(contains(true)));
      expect(h.voice.active, isFalse);
      expect(jsonEncode(h.usage), isNot(contains('private-platform-detail')));
      expect(jsonEncode(h.events), isNot(contains('private-platform-detail')));
    },
  );

  test('reordered startup acknowledgments keep the mic muted until configuration is ready', () async {
    await h.voice.start();
    expect(h.microphoneEnabled, [false]);
    expect(h.listening, isFalse);

    await h.provider({
      'type': 'session.created',
      'session': <String, dynamic>{},
    });
    expect(h.sent.length, 1);
    expect((h.sent.single['session'] as Map).containsKey('tools'), isFalse);

    final original = _serverSession();
    await h.provider({'type': 'session.updated', 'session': original});
    expect(h.sent.length, 2);
    final configured = Map<String, dynamic>.from(h.sent.last['session'] as Map);
    expect((configured['tools'] as List).length, 2);

    // This earlier memory-only acknowledgment can arrive while the projection
    // configuration is in flight. It must neither activate nor close the call.
    await h.provider({'type': 'session.updated', 'session': original});
    expect(h.voice.active, isTrue);
    expect(h.listening, isFalse);
    expect(h.microphoneEnabled, [false]);
    expect(
      h.sent.length,
      2,
      reason: 'A stale acknowledgment must not trigger another update.',
    );
    expect(h.usage.where((event) => event['ended'] == true), isEmpty);

    await h.provider({
      'type': 'session.updated',
      'session': {...original, ...configured},
    });
    expect(h.listening, isTrue);
    expect(h.microphoneEnabled, [false, true]);

    await h.voice.stop();
    expect(h.usage.last['endReason'], 'user_ended');
    expect(h.microphoneEnabled.last, isFalse);
  });

  test('Stop then fresh Live start retains Projection voice capability', () async {
    const utterance = 'Rici can you open projection mode';
    for (var session = 1; session <= 2; session++) {
      h.events.clear();
      h.sent.clear();
      h.sessionHeaders['x-korlix-live-convo-session-id'] = 'restart-fixture-$session';
      await h.voice.start();
      expect(h.voice.active, isTrue);
      expect(h.listening, isFalse);
      expect(h.microphoneEnabled.last, isFalse);

      final original = _serverSession();
      await h.provider({'type': 'session.created', 'session': original});
      final configured = Map<String, dynamic>.from(
        h.sent.single['session'] as Map,
      );
      expect((configured['tools'] as List).map((tool) => tool['name']),
          ['remember_in_brain', 'control_projection']);
      expect(configured['instructions'], contains('from Home'));
      expect(configured['instructions'], contains('use action open'));
      await h.provider({
        'type': 'session.updated',
        'session': {...original, ...configured},
      });
      expect(h.listening, isTrue);
      expect(h.microphoneEnabled.last, isTrue);

      final turnId = 'projection-after-start-$session';
      final responseId = 'automatic-$session';
      await h.provider({'type': 'input_audio_buffer.speech_started',
        'item_id': turnId});
      await h.provider({'type': 'input_audio_buffer.speech_stopped',
        'item_id': turnId});
      await h.provider({'type': 'response.created',
        'response': {'id': responseId}});
      await h.provider({
        'type': 'conversation.item.input_audio_transcription.completed',
        'item_id': turnId,
        'transcript': utterance,
      });
      expect(h.projection.isOpen, isTrue);
      expect(h.projectionOpens, session);
      expect(h.projectionVoiceStarts, 0,
          reason: 'Opening Projection must preserve the current voice session.');
      expect(h.sessionRequests, session);
      expect(h.voice.active, isTrue);
      expect(h.sent.where((event) => event['type'] == 'response.cancel')
          .map((event) => event['response_id']), contains(responseId));
      await h.provider({
        'type': 'response.output_audio_transcript.done',
        'response_id': responseId,
        'transcript': 'I cannot open it from here. Use your onscreen controls.',
      });
      expect(h.events.where((event) => event['role'] == 'rici'), isEmpty);
      await h.provider({'type': 'response.done', 'response': {
        'id': responseId, 'status': 'cancelled', 'output': <Object>[]}});
      final acknowledgement = h.sent.singleWhere((event) =>
          event['type'] == 'response.create'
          && (event['response'] as Map?)?['metadata'] is Map)['response'] as Map;
      await h.provider({'type': 'response.created', 'response': {
        'id': 'confirmed-$session',
        'metadata': acknowledgement['metadata'],
      }});
      await h.provider({
        'type': 'response.output_audio_transcript.done',
        'response_id': 'confirmed-$session',
        'transcript': 'Projection is open.',
      });
      await h.provider({'type': 'response.done', 'response': {
        'id': 'confirmed-$session', 'status': 'completed',
        'output': <Object>[],
      }});
      expect(h.events.where((event) => event['role'] == 'rici')
          .map((event) => event['text']), ['Projection is open.']);

      await h.voice.stop();
      expect(h.voice.active, isFalse);
      expect(h.voice.paused, isFalse);
      expect(h.events.last['phase'], 'complete');
      expect(h.microphoneEnabled.last, isFalse);
      expect(h.usage.where((event) => event['ended'] == true).length, session);
      h.projection.close();
    }
    expect(h.usage.where((event) => event['ended'] == true)
        .map((event) => event['sessionId']),
        ['restart-fixture-1', 'restart-fixture-2']);
  });

  test(
    'a provider setup error never unmutes and is distinct from a manual stop',
    () async {
      await h.voice.start();
      await h.provider({
        'type': 'error',
        'error': {
          'code': 'invalid_request_error',
          'message': 'private-platform-detail',
        },
      });
      await h.ended.future.timeout(const Duration(seconds: 3));

      expect(h.usage.last['endReason'], 'provider_setup_error');
      expect(h.microphoneEnabled, isNot(contains(true)));
      expect(h.voice.active, isFalse);
      expect(jsonEncode(h.usage), isNot(contains('private-platform-detail')));
      expect(jsonEncode(h.events), isNot(contains('private-platform-detail')));
    },
  );
}

Map<String, dynamic> _serverSession() => {
  'model': 'gpt-realtime-2.1',
  'instructions': 'Rici instructions with synthetic test account context.',
  'reasoning': {'effort': 'low'},
  'tool_choice': 'auto',
  'tools': [
    {
      'type': 'function',
      'name': 'remember_in_brain',
      'description': 'Original memory tool fixture.',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
  ],
  'audio': {
    'input': {
      'transcription': {'model': 'gpt-transcribe'},
      'turn_detection': {
        'type': 'semantic_vad',
        'create_response': true,
        'interrupt_response': true,
      },
    },
  },
};

class _VoiceHarness {
  _VoiceHarness() {
    auth = BrainAuthController(
      client: MockClient(
        (_) async => throw StateError('Unexpected auth request'),
      ),
    );
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    auth.session = KorlixAuthSession(
      accessToken:
          '${part({'alg': 'none'})}.${part({'iss': 'https://auth.example.test', 'sub': 'startup-test-account', 'session_id': 'startup-test-session', 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})}.fixture',
    );
    api = BrainApi(
      auth,
      client: MockClient((request) async {
        if (request.url.path == '/api/live-convo/session') {
          sessionRequests++;
          return http.Response(_sdp, 200, headers: sessionHeaders);
        }
        if (request.url.path == '/api/live-convo/usage') {
          final report = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          usage.add(report);
          if (report['ended'] == true && !ended.isCompleted) ended.complete();
          return http.Response(jsonEncode({'ok': true, 'allowed': true}), 200);
        }
        throw StateError('Unexpected HTTP endpoint ${request.url.path}');
      }),
    );
    projection = BrainProjection(
      backendUrl: 'https://api.example.test',
      request: (method, path, body) async {
        if (method == 'GET' && path == '/api/brain-projection/config') {
          return {
            'rendererUrl': 'https://api.example.test/brain-projection/earth.html',
            'mapAvailable': true,
            'geocodingAvailable': true,
            'answersAvailable': false,
          };
        }
        throw StateError('Unexpected Projection endpoint $path');
      },
      onOpen: () => projectionOpens++,
      onClose: () {},
      onStartVoice: () async { projectionVoiceStarts++; },
      onStopVoice: () async {},
      onSave: (_, _) async => throw StateError('No place save expected'),
    );
    voice = BrainVoice(
      api,
      (event) {
        events.add(event);
        projection.receiveVoice(event);
      },
      onSaved: (_) async {},
      onProjection: projection.voiceTurn,
      recognizesProjection: projection.recognizesVoiceControl,
    );
    messenger.setMockMethodCallHandler(_plugin, _native);
    for (final channel in _eventChannels) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => null,
      );
    }
  }

  static const _plugin = MethodChannel('FlutterWebRTC.Method');
  static const _peerEvents = 'FlutterWebRTC/peerConnectionEventstartup-peer';
  static const _dataEvents =
      'FlutterWebRTC/dataChannelEventstartup-peerstartup-channel';
  static const _eventChannels = [
    _peerEvents,
    _dataEvents,
    'FlutterWebRTC/Texture7',
    'FlutterWebRTC.Event',
  ];
  static const _sdp = 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late final BrainAuthController auth;
  late final BrainApi api;
  late final BrainVoice voice;
  late final BrainProjection projection;
  int projectionOpens = 0, projectionVoiceStarts = 0;
  final calls = <MethodCall>[];
  final events = <Map<String, dynamic>>[];
  final usage = <Map<String, dynamic>>[];
  final sent = <Map<String, dynamic>>[];
  final microphoneEnabled = <bool>[];
  final ended = Completer<void>();
  var sessionRequests = 0;
  var failRemoteDescription = false;
  final sessionHeaders = <String, String>{
    'x-korlix-live-convo-session-id': 'startup-fixture',
    'x-korlix-live-convo-max-seconds': '600',
    'x-korlix-live-convo-max-responses': '100',
    'x-korlix-brain-voice': 'rici-live-v1',
    'x-korlix-brain-model': 'gpt-realtime-2.1',
    'x-korlix-brain-reasoning': 'low',
  };

  bool get listening => events.any((event) => event['phase'] == 'listening');

  Future<void> _event(String name, Map<String, dynamic> value) async {
    final delivered = Completer<void>();
    messenger.handlePlatformMessage(
      name,
      const StandardMethodCodec().encodeSuccessEnvelope(value),
      (_) => delivered.complete(),
    );
    await delivered.future;
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> provider(Map<String, dynamic> value) => _event(_dataEvents, {
    'event': 'dataChannelReceiveMessage',
    'id': 0,
    'type': 'text',
    'data': jsonEncode(value),
  });

  Future<Object?> _native(MethodCall call) async {
    calls.add(call);
    final args = call.arguments as Map? ?? {};
    switch (call.method) {
      case 'createVideoRenderer':
        return {'textureId': 7};
      case 'createPeerConnection':
        return {'peerConnectionId': 'startup-peer'};
      case 'getUserMedia':
        return {
          'streamId': 'startup-microphone',
          'audioTracks': [
            {
              'id': 'startup-audio',
              'label': 'Microphone',
              'kind': 'audio',
              'enabled': true,
            },
          ],
          'videoTracks': [],
        };
      case 'mediaStreamTrackSetEnable':
        microphoneEnabled.add(args['enabled'] as bool);
        return null;
      case 'addTrack':
        return {
          'senderId': 'startup-sender',
          'track': <String, dynamic>{},
          'ownsTrack': false,
          'rtpParameters': {
            'encodings': [],
            'headerExtensions': [],
            'codecs': [],
            'rtcp': {'cname': 'startup-test', 'reducedSize': true},
          },
        };
      case 'createDataChannel':
        return {'id': 0, 'flutterId': 'startup-channel'};
      case 'createOffer':
      case 'getLocalDescription':
        return {'sdp': _sdp, 'type': 'offer'};
      case 'setLocalDescription':
        await _event(_peerEvents, {
          'event': 'iceGatheringState',
          'state': 'complete',
        });
        return null;
      case 'setRemoteDescription':
        if (failRemoteDescription) {
          throw PlatformException(
            code: 'setRemoteDescriptionFailed',
            message: 'private-platform-detail',
          );
        }
        return null;
      case 'dataChannelSend':
        sent.add(
          Map<String, dynamic>.from(jsonDecode(args['data'] as String) as Map),
        );
        return null;
      default:
        return null;
    }
  }

  Future<void> dispose() async {
    await voice.stop();
    projection.dispose();
    api.client.close();
    auth.dispose();
    messenger.setMockMethodCallHandler(_plugin, null);
    for (final channel in _eventChannels) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
  }
}
