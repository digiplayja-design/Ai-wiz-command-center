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
        } finally {
          await left.close();
          await right.close();
        }
      },
      timeout: const Timeout(Duration(seconds: 55)),
    );
  }
}
