@TestOn('browser')
library;

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:ai_wiz_command_center/social/social_call_controller.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';

class BrowserIo extends SocialCallIo {
  late rtc.RTCPeerConnection connection;
  @override
  Future<rtc.RTCPeerConnection> peer(List<dynamic> servers) async {
    connection = await super.peer(servers);
    return connection;
  }
}

Future<void> until(Future<bool> Function() check) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(end)) {
    if (await check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('Real browser media did not flow within 20 seconds');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final video in [false, true]) {
    test(
      'real browser ${video ? 'video and audio' : 'audio'} flows both ways and microphone replacement keeps sending',
      () async {
        final leftIo = BrowserIo(), rightIo = BrowserIo();
        final left = SocialCallMedia(io: leftIo),
            right = SocialCallMedia(io: rightIo);
        final toLeft = <SocialMap>[], toRight = <SocialMap>[];
        var leftDescription = false, rightDescription = false;
        Future<void> candidate(
          SocialCallMedia target,
          SocialMap value,
          List<SocialMap> queue,
          bool ready,
        ) async {
          if (ready) {
            await target.candidate(value);
          } else {
            queue.add(value);
          }
        }

        left.onCandidate = (c) =>
            unawaited(candidate(right, c, toRight, rightDescription));
        right.onCandidate = (c) =>
            unawaited(candidate(left, c, toLeft, leftDescription));
        try {
          await left.open(video, []);
          await right.open(video, []);
          await right.description('offer', await left.offer());
          rightDescription = true;
          for (final c in toRight) {
            await right.candidate(c);
          }
          toRight.clear();
          await left.description('answer', await right.answer());
          leftDescription = true;
          for (final c in toLeft) {
            await left.candidate(c);
          }
          toLeft.clear();
          await until(() async {
            await left.checkAudio();
            await right.checkAudio();
            return left.incomingAudioBytes > 0 &&
                right.incomingAudioBytes > 0 &&
                left.outgoingAudioBytes > 0 &&
                right.outgoingAudioBytes > 0;
          });
          expect(left.audio.playing, true);
          expect(right.audio.playing, true);
          if (video) {
            await until(() async {
              for (final io in [leftIo, rightIo]) {
                final stats = await io.connection.getStats();
                if (!stats.any(
                  (r) =>
                      r.type == 'inbound-rtp' &&
                      r.values['kind'] == 'video' &&
                      (r.values['bytesReceived'] as num? ?? 0) > 0,
                )) {
                  return false;
                }
              }
              return true;
            });
            expect(left.remote.srcObject!.getVideoTracks(), isNotEmpty);
            expect(right.remote.srcObject!.getVideoTracks(), isNotEmpty);
          }
          final before = right.incomingAudioBytes;
          await left.restartMicrophone();
          expect(left.microphoneIssue, isEmpty);
          await until(() async {
            await right.checkAudio();
            return right.incomingAudioBytes > before;
          });
          // Sustain real RTP well beyond the reported 30–45 second failure.
          for (var i = 0; i < 13; i++) {
            final leftBefore = left.incomingAudioBytes;
            final rightBefore = right.incomingAudioBytes;
            await Future<void>.delayed(const Duration(seconds: 5));
            await left.checkAudio();
            await right.checkAudio();
            expect(left.incomingAudioBytes, greaterThan(leftBefore));
            expect(right.incomingAudioBytes, greaterThan(rightBefore));
          }
        } finally {
          await left.close();
          await right.close();
        }
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  }

  for (final legacyCalls in [true, false]) {
    test(
      'legacy audio-only peer ${legacyCalls ? 'calls' : 'answers'} Messenger across ICE restart',
      () async {
        // Main KORLIX builds negotiate audio calls without the newer screen-share
        // video slot. Exercise that exact offer/answer shape with a real peer.
        final legacy = await rtc.createPeerConnection({
          'iceServers': [],
          'sdpSemantics': 'unified-plan',
        });
        final stream = await rtc.navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
        for (final track in stream.getTracks()) {
          await legacy.addTrack(track, stream);
        }
        final modern = SocialCallMedia();
        final toLegacy = <SocialMap>[], toModern = <SocialMap>[];
        var legacyReady = false, modernReady = false;
        Future<void> addLegacy(SocialMap c) => legacy.addCandidate(
          rtc.RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']),
        );
        modern.onCandidate = (c) {
          if (legacyReady) {
            unawaited(addLegacy(c));
          } else {
            toLegacy.add(c);
          }
        };
        legacy.onIceCandidate = (c) {
          if (c.candidate?.isNotEmpty != true) return;
          final value = {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          };
          if (modernReady) {
            unawaited(modern.candidate(value));
          } else {
            toModern.add(value);
          }
        };
        Future<void> negotiate({bool restart = false}) async {
          legacyReady = modernReady = false;
          if (legacyCalls) {
            if (restart) await legacy.restartIce();
            final offer = await legacy.createOffer();
            await legacy.setLocalDescription(offer);
            await modern.description('offer', offer.sdp!);
            modernReady = true;
            await legacy.setRemoteDescription(
              rtc.RTCSessionDescription(await modern.answer(), 'answer'),
            );
            legacyReady = true;
          } else {
            final offer = restart
                ? await modern.restartOffer()
                : await modern.offer();
            await legacy.setRemoteDescription(
              rtc.RTCSessionDescription(offer, 'offer'),
            );
            legacyReady = true;
            final answer = await legacy.createAnswer();
            await legacy.setLocalDescription(answer);
            await modern.description('answer', answer.sdp!);
            modernReady = true;
          }
          for (final c in toLegacy) {
            await addLegacy(c);
          }
          for (final c in toModern) {
            await modern.candidate(c);
          }
          toLegacy.clear();
          toModern.clear();
        }

        Future<int> legacyBytes() async => (await legacy.getStats())
            .where(
              (r) =>
                  r.type == 'inbound-rtp' &&
                  (r.values['kind'] ?? r.values['mediaType']) == 'audio',
            )
            .fold<int>(
              0,
              (sum, r) =>
                  sum + ((r.values['bytesReceived'] as num?)?.toInt() ?? 0),
            );
        try {
          await modern.open(false, []);
          await negotiate();
          await until(() async {
            await modern.checkAudio();
            return modern.incomingAudioBytes > 0 && await legacyBytes() > 0;
          });
          for (var i = 0; i < 13; i++) {
            final before = modern.incomingAudioBytes,
                oldBefore = await legacyBytes();
            if (i == 7) await negotiate(restart: true);
            await Future<void>.delayed(const Duration(seconds: 5));
            await modern.checkAudio();
            expect(modern.incomingAudioBytes, greaterThan(before));
            expect(await legacyBytes(), greaterThan(oldBefore));
          }
        } finally {
          await modern.close();
          await legacy.close();
          for (final track in stream.getTracks()) {
            await track.stop();
          }
          await stream.dispose();
          await legacy.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  }
}
