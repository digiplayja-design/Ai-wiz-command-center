import 'dart:async';
import 'package:ai_wiz_command_center/input_tools/voice_composer.dart';
// Included by the existing speech_to_text plugin; no extra dependency.
// ignore: depend_on_referenced_packages
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/pod/pod_media.dart';
import 'package:ai_wiz_command_center/social/social_voice_note.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_service.dart';

class _SpeechPlatform extends SpeechToTextPlatform {
  bool accepted = false;
  @override
  Future<bool> initialize({
    dynamic debugLogging = false,
    List<SpeechConfigOption>? options,
  }) async => true;
  @override
  Future<List<dynamic>> locales() async => ['en_US:English'];
  @override
  Future<bool> listen({
    String? localeId,
    dynamic partialResults = true,
    dynamic onDevice = false,
    int listenMode = 0,
    dynamic sampleRate = 0,
    SpeechListenOptions? options,
  }) async => accepted;
  @override
  Future<void> cancel() async {}
}

class _Recorder implements SocialRecorder, PodRecorderBackend {
  StreamController<Uint8List>? stream;
  Completer<void>? permission, cancelGate;
  bool failStart = false, failStop = false;
  int revision = 0;

  @override
  void cancelPendingStart() => revision++;

  @override
  Future<Stream<Uint8List>> start() async {
    expect(
      kKorlixSounds.quiet,
      isTrue,
      reason: 'Effects must be quiet before opening the microphone.',
    );
    final current = revision;
    await permission?.future;
    if (failStart || current != revision) throw StateError('Mic unavailable');
    stream = StreamController<Uint8List>.broadcast(sync: true);
    return stream!.stream;
  }

  @override
  Future<void> stop() async {
    if (failStop) throw StateError('Interrupted');
    if (stream?.isClosed == false) {
      stream!.add(Uint8List(24000));
      await stream!.close();
    }
  }

  @override
  Future<void> cancel() async {
    await cancelGate?.future;
    if (stream?.isClosed == false) await stream!.close();
  }

  @override
  Future<void> dispose() => cancel();
}

class _Playback implements PodPlaybackBackend {
  Completer<void>? done;
  bool fail = false;
  @override
  Future<void> activate() async {}
  @override
  Future<void> play(Uint8List wav, {VoidCallback? onStarted}) {
    expect(kKorlixSounds.quiet, isTrue);
    if (fail) return Future<void>.error(const PodMediaException('No output'));
    done = Completer<void>();
    onStarted?.call();
    return done!.future;
  }

  @override
  Future<void> stop() async {
    if (done?.isCompleted == false) done!.complete();
  }

  @override
  Future<void> dispose() => stop();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => expect(kKorlixSounds.quiet, isFalse));

  test(
    'silent dictation rejection releases quiet and delayed real start reacquires it',
    () async {
      final previous = SpeechToTextPlatform.instance;
      final platform = _SpeechPlatform();
      SpeechToTextPlatform.instance = platform;
      final engine = KorlixDeviceDictation();
      try {
        await engine.initialize(onStatus: (_) {}, onError: (_) {});
        await engine.start(onWords: (_) {}, onLevel: (_) {});
        expect(
          kKorlixSounds.quiet,
          isFalse,
          reason: 'A false platform result must not leave a quiet lease.',
        );
        platform.accepted = true;
        await engine.start(onWords: (_) {}, onLevel: (_) {});
        platform.onStatus!('listening');
        expect(kKorlixSounds.quiet, isTrue);
        await engine.cancel();
        expect(kKorlixSounds.quiet, isFalse);
        platform.onStatus!('listening');
        expect(
          kKorlixSounds.quiet,
          isFalse,
          reason: 'Late callbacks cannot reacquire a cancelled request.',
        );
      } finally {
        engine.dispose();
        await Future<void>.delayed(Duration.zero);
        SpeechToTextPlatform.instance = previous;
      }
    },
  );

  test(
    'Social voice capture guards the mic, then releases after stop',
    () async {
      final capture = SocialVoiceCapture(recorder: _Recorder());
      addTearDown(capture.dispose);
      expect(kKorlixSounds.quiet, isFalse);
      await capture.start();
      expect(kKorlixSounds.quiet, isTrue);
      await capture.stop();
      expect(capture.preview, isNotNull);
      expect(kKorlixSounds.quiet, isFalse);
    },
  );

  test(
    'Social permission failure and discard release their own lease',
    () async {
      final capture = SocialVoiceCapture(
        recorder: _Recorder()..failStart = true,
      );
      addTearDown(capture.dispose);
      await capture.start();
      expect(capture.error, isNotNull);
      expect(kKorlixSounds.quiet, isFalse);
      final other = Object();
      kKorlixSounds.setQuiet(other, true);
      addTearDown(() => kKorlixSounds.setQuiet(other, false));
      await capture.discard();
      expect(
        kKorlixSounds.quiet,
        isTrue,
        reason: 'A failed recording cannot release another activity.',
      );
    },
  );

  test(
    'Social disposal during permission does not leave permanent quiet',
    () async {
      final recorder = _Recorder()..permission = Completer<void>();
      final capture = SocialVoiceCapture(recorder: recorder);
      final pending = capture.start();
      expect(kKorlixSounds.quiet, isTrue);
      capture.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(kKorlixSounds.quiet, isFalse);
      recorder.permission!.complete();
      await pending;
      expect(capture.recording, isFalse);
      expect(kKorlixSounds.quiet, isFalse);
    },
  );

  test(
    'disposal stays quiet until each recorder actually finishes cancellation',
    () async {
      final socialRecorder = _Recorder()..cancelGate = Completer<void>();
      final podRecorder = _Recorder()..cancelGate = Completer<void>();
      final capture = SocialVoiceCapture(recorder: socialRecorder);
      final pod = PodMediaController(
        playback: _Playback(),
        recorder: podRecorder,
      );
      await capture.start();
      await pod.startRecording();
      capture.dispose();
      pod.dispose();
      expect(kKorlixSounds.quiet, isTrue);
      socialRecorder.cancelGate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        kKorlixSounds.quiet,
        isTrue,
        reason: 'The other recorder is still closing.',
      );
      podRecorder.cancelGate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(kKorlixSounds.quiet, isFalse);
    },
  );

  test('Pod playback completion and failure release effects', () async {
    final player = _Playback();
    final pod = PodMediaController(playback: player, recorder: _Recorder());
    addTearDown(pod.dispose);
    final playing = pod.play(Uint8List(44));
    expect(kKorlixSounds.quiet, isTrue);
    await player.stop();
    await playing;
    expect(kKorlixSounds.quiet, isFalse);
    player.fail = true;
    await expectLater(
      pod.play(Uint8List(44)),
      throwsA(isA<PodMediaException>()),
    );
    expect(kKorlixSounds.quiet, isFalse);
  });

  test(
    'Concurrent Pod playback and Social capture retain independent leases',
    () async {
      final pod = PodMediaController(
        playback: _Playback(),
        recorder: _Recorder(),
      );
      final capture = SocialVoiceCapture(recorder: _Recorder());
      addTearDown(pod.dispose);
      addTearDown(capture.dispose);
      final playing = pod.play(Uint8List(44));
      await capture.start();
      await pod.stop();
      await playing;
      expect(kKorlixSounds.quiet, isTrue);
      await capture.discard();
      expect(kKorlixSounds.quiet, isFalse);
    },
  );

  test(
    'Pod recording holds quiet through capture and releases after failure',
    () async {
      final recorder = _Recorder()..failStop = true;
      final pod = PodMediaController(playback: _Playback(), recorder: recorder);
      addTearDown(pod.dispose);
      await pod.startRecording();
      expect(kKorlixSounds.quiet, isTrue);
      await expectLater(pod.stopRecording(), throwsA(isA<PodMediaException>()));
      expect(kKorlixSounds.quiet, isFalse);
    },
  );

  test(
    'Pod cancelled pending permission releases and permits a fresh recording',
    () async {
      final recorder = _Recorder()..permission = Completer<void>();
      final pod = PodMediaController(playback: _Playback(), recorder: recorder);
      addTearDown(pod.dispose);
      final pending = pod.startRecording();
      await Future<void>.delayed(Duration.zero);
      expect(kKorlixSounds.quiet, isTrue);
      final cancel = pod.cancelRecording();
      recorder.permission!.complete();
      await pending;
      await cancel;
      expect(kKorlixSounds.quiet, isFalse);
      await pod.startRecording();
      expect(kKorlixSounds.quiet, isTrue);
      await pod.stopRecording();
      expect(kKorlixSounds.quiet, isFalse);
    },
  );
}
