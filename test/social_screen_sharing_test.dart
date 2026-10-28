import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:korlix_social_core/social/social_call_controller.dart';

import 'social_call_audio_test.dart' as media;
import 'social_calls_test.dart' as calls;
import 'social_test.dart' as social;
import 'korlix_sound_service_test.dart' as sound;

import 'package:korlix_social_core/sounds/korlix_sound_service.dart';

class ScreenIo extends media.Io {
  final displayTrack = media.Track('display', 'video');
  late final display = media.Stream('screen', [displayTrack]);
  bool consent = true;
  Completer<bool>? permissionGate;
  final order = <String>[];
  late media.Sender reserved;
  @override
  bool get canShareScreen => true;
  @override
  Future<bool> screenPermission() async {
    order.add('consent');
    return permissionGate == null ? consent : await permissionGate!.future;
  }

  @override
  Future<rtc.MediaStream> captureScreen() async {
    order.add('capture');
    return display;
  }

  @override
  Future<rtc.RTCRtpSender> reserveVideo(rtc.RTCPeerConnection peer) async =>
      reserved = media.Sender(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('audio call reserves video without camera and shares only after consent and service', () async {
    final io = ScreenIo();
    final call = SocialCallMedia(io: io, audio: media.Audio());
    await call.open(false, []);
    expect(io.captureModes, [false]);
    expect(io.reserved.current, isNull);
    await call.startScreenShare(() async {
      io.order.add('service');
      return true;
    });
    expect(io.order, ['consent', 'service', 'capture']);
    expect(call.screenSharing, isTrue);
    expect(io.reserved.current, same(io.displayTrack));
    expect(io.mic.enabled, isTrue);
    await call.stopScreenShare();
    expect(call.screenSharing, isFalse);
    expect(io.displayTrack.stopped, isTrue);
    expect(io.reserved.current, isNull);
    expect(io.mic.stopped, isFalse);
    expect(call.ready, isTrue);
    await call.close();
  });
  test('denied projection never captures and preserves the call', () async {
    final io = ScreenIo()..consent = false;
    final call = SocialCallMedia(io: io, audio: media.Audio());
    await call.open(false, []);
    await call.startScreenShare(() async {
      fail('No service without consent');
    });
    expect(io.order, ['consent']);
    expect(call.ready, isTrue);
    expect(call.screenSharing, isFalse);
    await call.close();
  });
  test('ending while consent is open never starts capture later', () async {
    final io = ScreenIo()..permissionGate = Completer<bool>();
    final call = SocialCallMedia(io: io, audio: media.Audio());
    await call.open(false, []);
    final sharing = call.startScreenShare(() async {
      fail('Call ended');
    });
    await call.close();
    io.permissionGate!.complete(true);
    await sharing;
    expect(io.order, ['consent']);
    expect(io.mic.stopped, isTrue);
  });
  testWidgets(
    'answer handshake progresses at setup cadence without manual polls',
    (t) async {
      final store = calls.CallStore();
      final callerClient = store.client('caller'),
          calleeClient = store.client('callee');
      final callerMedia = calls.FakeMedia(), calleeMedia = calls.FakeMedia();
      final caller = SocialCallController(
        client: callerClient,
        peer: social.peer,
        video: false,
        media: callerMedia,
      );
      await caller.initialize();
      final callee = SocialCallController(
        client: calleeClient,
        peer: social.peer,
        video: false,
        media: calleeMedia,
        incoming: {'id': caller.id, 'state': 'ringing'},
      );
      await callee.initialize();
      await callee.accept();
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(milliseconds: 350));
        await t.pump();
      }
      expect(callerMedia.descriptions, contains('answer:callee-sdp'));
      expect(calleeMedia.descriptions, contains('offer:caller-sdp'));
      caller.dispose();
      callee.dispose();
      await t.pump();
      callerClient.dispose();
      calleeClient.dispose();
    },
  );
  testWidgets('ringback survives slow audio activation across capture setup', (
    t,
  ) async {
    final player = sound.FakePlayer()..activationGate = Completer<bool>();
    final sounds = KorlixSoundService(
      player: player,
      store: sound.MemoryStore(),
    );
    final activation = sounds.activate();
    sounds.setQuiet('capture', true);
    sounds.setQuiet('capture', false);
    sounds.setRinging('caller', true, callId: 'new-call', outgoing: true);
    expect(player.plays, isEmpty);
    player.activationGate!.complete(true);
    await activation;
    expect(player.active, contains('ring'));
    sounds.setRinging('caller', false);
    expect(player.active, isEmpty);
    sounds.dispose();
  });
}
