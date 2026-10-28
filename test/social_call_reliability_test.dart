import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korlix_social_core/social/social_call_controller.dart';
import 'package:korlix_social_core/social/social_client.dart';

import 'social_calls_test.dart' show FakeMedia;
import 'social_communication_upgrade_test.dart' show RecoveryMedia;
import 'social_screen_sharing_test.dart' show Background;
import 'korlix_sound_service_test.dart' as sound;
import 'package:korlix_social_core/sounds/korlix_sound_service.dart';
import 'social_test.dart' as social;
import 'social_call_audio_test.dart' as audio;

class CallNetwork {
  String state = 'ringing';
  int generation = 0;
  Completer<void>? startGate, candidateGate, offerGate;
  int candidateStatus = 200;
  final requests = <SocialMap>[];
  late final client = SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': 'Bearer caller'},
    client: MockClient((request) async {
      final action = request.url.pathSegments.last;
      final data = request.method == 'POST'
          ? socialMap(jsonDecode(request.body))
          : request.url.queryParameters;
      requests.add({'action': action, ...data});
      if (action == 'call_config') {
        return http.Response(
          jsonEncode({'enabled': true, 'relay': false, 'iceServers': []}),
          200,
        );
      }
      if (action == 'call_start' && startGate != null) {
        await startGate!.future;
      }
      if (action == 'call_poll' && startGate?.isCompleted == false) {
        return http.Response('{"error":"Call not found."}', 404);
      }
      if (action == 'call_signal' && data['kind'] == 'candidate') {
        if (candidateGate != null) await candidateGate!.future;
        if (candidateStatus != 200) {
          return http.Response(
            '{"error":"Temporarily unavailable"}',
            candidateStatus,
          );
        }
      }
      if (action == 'call_signal' &&
          data['kind'] == 'offer' &&
          offerGate != null) {
        await offerGate!.future;
      }
      if (action == 'call_restart') generation++;
      if (action == 'call_end') state = 'ended';
      return http.Response(
        jsonEncode({
          'call': {
            'state': state,
            'generation': generation,
            'recovery_supported': true,
          },
          'signals': [],
        }),
        200,
      );
    }),
  );

  SocialCallController controller(WidgetTester tester, SocialCallMedia media) =>
      SocialCallController(
        client: client,
        peer: social.peer,
        video: false,
        media: media,
        background: Background(),
        sounds: KorlixSoundService(
          player: sound.FakePlayer(),
          store: sound.MemoryStore(),
        ),
        now: tester.binding.clock.now,
      );
}

Future<void> advance(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  test(
    'relay recovery retains authenticated ICE servers and is applied once',
    () async {
      final io = audio.Io();
      final media = SocialCallMedia(io: io, audio: audio.Audio());
      final servers = [
        {
          'urls': ['turn:relay.fixture.test:3478'],
          'username': 'fixture',
          'credential': 'fixture',
        },
      ];
      await media.open(false, servers);
      await media.useRelayForRecovery();
      await media.useRelayForRecovery();
      expect(io.connection.configurations, hasLength(1));
      expect(io.connection.configurations.single['iceServers'], servers);
      expect(
        io.connection.configurations.single['iceTransportPolicy'],
        'relay',
      );
      await media.close();
    },
  );

  test('direct-only calls never switch to an unavailable relay', () async {
    final io = audio.Io();
    final media = SocialCallMedia(io: io, audio: audio.Audio());
    await media.open(false, [
      {'urls': 'stun:stun.fixture.test:3478'},
    ]);
    await media.useRelayForRecovery();
    expect(io.connection.configurations, isEmpty);
    await media.close();
  });
  testWidgets(
    'connected call gets a fresh recovery window after the setup deadline',
    (t) async {
      final network = CallNetwork()..state = 'accepted';
      final media = RecoveryMedia();
      final call = network.controller(t, media);
      await call.initialize();
      media.onState!('connected');
      await advance(t, 60);
      media.onState!('disconnected');
      await advance(t, 5);
      expect(call.ended, isFalse);
      media.onState!('connected');
      await advance(t, 60);
      expect(call.connected, isTrue);
      expect(call.ended, isFalse);
      call.dispose();
      await t.pump();
      network.client.dispose();
    },
  );

  testWidgets(
    'brief network interruption does not start a competing ICE restart',
    (t) async {
      final network = CallNetwork()..state = 'accepted';
      final media = RecoveryMedia();
      final call = network.controller(t, media);
      await call.initialize();
      media.onState!('connected');
      media.onState!('disconnected');
      await advance(t, 1);
      media.onState!('connected');
      await advance(t, 12);
      expect(media.restarts, 0);
      expect(call.ended, isFalse);
      call.dispose();
      await t.pump();
      network.client.dispose();
    },
  );

  testWidgets(
    'peer-requested restart cannot expire a still-connected transport',
    (t) async {
      final network = CallNetwork()..state = 'accepted';
      final media = RecoveryMedia();
      final call = network.controller(t, media);
      await call.initialize();
      media.onState!('connected');
      await call.reconnect();
      // A working transport need not emit another connected event after restart.
      await advance(t, 65);
      expect(call.connected, isTrue);
      expect(call.ended, isFalse);
      expect(media.restarts, 1);
      call.dispose();
      await t.pump();
      network.client.dispose();
    },
  );

  testWidgets(
    'resuming during call registration never polls a nonexistent call',
    (t) async {
      final network = CallNetwork()..startGate = Completer<void>();
      final call = network.controller(t, FakeMedia());
      final initializing = call.initialize();
      await t.pump();
      call.resume();
      await t.pump();
      expect(
        network.requests.where((r) => r['action'] == 'call_poll'),
        isEmpty,
      );
      network.startGate!.complete();
      await initializing;
      expect(call.ended, isFalse);
      call.dispose();
      await t.pump();
      network.client.dispose();
    },
  );

  testWidgets(
    'slow candidate and offer delivery cannot block the call heartbeat',
    (t) async {
      final network = CallNetwork()
        ..candidateGate = Completer<void>()
        ..offerGate = Completer<void>();
      final media = FakeMedia();
      final call = network.controller(t, media);
      await call.initialize();
      media.onCandidate!({
        'candidate': 'candidate:fixture',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
      await t.pump();
      network.state = 'accepted';
      unawaited(call.poll());
      await t.pump();
      expect(network.requests.where((r) => r['kind'] == 'offer'), hasLength(1));
      final before = network.requests
          .where((r) => r['action'] == 'call_poll')
          .length;
      await advance(t, 8);
      expect(
        network.requests.where((r) => r['action'] == 'call_poll').length,
        greaterThan(before),
      );
      expect(call.ended, isFalse);
      network.candidateGate!.complete();
      network.offerGate!.complete();
      await t.pump();
      call.dispose();
      await t.pump();
      network.client.dispose();
    },
  );

  testWidgets('a failed optional candidate does not hang up a working call', (
    t,
  ) async {
    final network = CallNetwork()
      ..state = 'accepted'
      ..candidateStatus = 503;
    final media = FakeMedia();
    final call = network.controller(t, media);
    await call.initialize();
    media.onState!('connected');
    media.onCandidate!({
      'candidate': 'candidate:fixture',
      'sdpMid': '0',
      'sdpMLineIndex': 0,
    });
    await advance(t, 6);
    expect(call.ended, isFalse);
    final attempts = network.requests
        .where((r) => r['kind'] == 'candidate')
        .toList();
    expect(attempts, hasLength(3));
    expect(attempts.map((r) => r['signal_id']).toSet(), hasLength(1));
    call.dispose();
    await t.pump();
    network.client.dispose();
  });

  testWidgets(
    'initial setup still expires and a prolonged lost connection still ends',
    (t) async {
      for (final connectedFirst in [false, true]) {
        final network = CallNetwork()..state = 'accepted';
        final media = RecoveryMedia();
        final call = network.controller(t, media);
        await call.initialize();
        if (connectedFirst) {
          media.onState!('connected');
          await advance(t, 60);
          media.onState!('failed');
        }
        await advance(t, 42);
        expect(call.ended, isTrue);
        call.dispose();
        await t.pump();
        network.client.dispose();
      }
    },
  );
}
