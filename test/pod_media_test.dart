import 'dart:async';
import 'dart:typed_data';

// Supplied by the existing flutter_test dependency; no new dependency needed.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/pod/pod_media.dart';

class FakePlayback implements PodPlaybackBackend {
  int activations = 0, plays = 0, stops = 0;
  bool disposed = false;
  Completer<void>? activation, pending;
  PodMediaException? failure;

  @override
  Future<void> activate() {
    activations++;
    return activation?.future ?? Future<void>.value();
  }

  @override
  Future<void> play(Uint8List wav) {
    plays++;
    if (failure != null) return Future<void>.error(failure!);
    pending = Completer<void>();
    return pending!.future;
  }

  void finish() {
    if (pending?.isCompleted == false) pending!.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
    finish();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    finish();
  }
}

class FakeRecorder implements PodRecorderBackend {
  int starts = 0, stops = 0, cancels = 0;
  int startRevision = 0;
  bool disposed = false;
  Completer<void>? permission;
  Uint8List? finalChunk;
  StreamController<Uint8List>? stream;

  @override
  void cancelPendingStart() => startRevision++;

  @override
  Future<Stream<Uint8List>> start() async {
    final revision = startRevision;
    starts++;
    await permission?.future;
    if (revision != startRevision) {
      throw const PodMediaException('Recording was cancelled.');
    }
    stream = StreamController<Uint8List>.broadcast(sync: true);
    return stream!.stream;
  }

  void add(List<int> values) => stream!.add(Uint8List.fromList(values));

  @override
  Future<void> stop() async {
    stops++;
    if (finalChunk != null) stream!.add(finalChunk!);
    if (stream?.isClosed == false) await stream!.close();
  }

  @override
  Future<void> cancel() async {
    cancels++;
    if (stream?.isClosed == false) await stream!.close();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  late FakePlayback playback;
  late FakeRecorder recorder;
  late PodMediaController media;

  setUp(() {
    playback = FakePlayback();
    recorder = FakeRecorder();
    media = PodMediaController(playback: playback, recorder: recorder);
  });

  tearDown(() => media.dispose());

  test(
    'Listen activation reaches backend synchronously without microphone',
    () async {
      playback.activation = Completer<void>();
      final activation = media.activate();
      expect(playback.activations, 1);
      expect(recorder.starts, 0);
      expect(media.playing, false);
      playback.activation!.complete();
      await activation;
      expect(media.blocked, false);
    },
  );

  test('play waits for ended and stop releases the pending turn', () async {
    var finished = false;
    final first = media.play(Uint8List(4)).then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(media.playing, true);
    expect(finished, false);
    playback.finish();
    await first;
    expect(media.playing, false);

    final second = media.play(Uint8List(4));
    await media.stop();
    await second;
    expect(media.playing, false);
    expect(media.error, isNull);
  });

  test('blocked playback is explicit and never opens microphone', () async {
    playback.failure = const PodMediaException(
      'Tap Resume sound.',
      blocked: true,
    );
    await expectLater(
      media.play(Uint8List(4)),
      throwsA(isA<PodMediaException>()),
    );
    expect(media.blocked, true);
    expect(media.playing, false);
    expect(media.error, 'Tap Resume sound.');
    expect(recorder.starts, 0);
    playback.failure = null;
    await media.activate();
    expect(media.blocked, false);
    expect(media.error, isNull);
  });

  test('late activation rejection cannot update a stopped session', () async {
    playback.activation = Completer<void>();
    final activation = media.activate();
    await media.stop();
    playback.activation!.completeError(
      const PodMediaException('blocked', blocked: true),
    );
    await activation;
    expect(media.blocked, false);
    expect(media.error, isNull);
  });

  test(
    'capture stops playback, flushes last chunk and encodes exact PCM WAV',
    () async {
      final playing = media.play(Uint8List(4));
      await media.startRecording();
      await playing;
      expect(media.playing, false);
      expect(media.recording, true);
      recorder.add([1, 2, 3]);
      recorder.finalChunk = Uint8List.fromList([4, 5]);
      final wav = await media.stopRecording();
      final data = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(data.getUint16(20, Endian.little), 1);
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint32(24, Endian.little), 24000);
      expect(data.getUint32(28, Endian.little), 48000);
      expect(data.getUint16(34, Endian.little), 16);
      expect(data.getUint32(40, Endian.little), 4);
      expect(wav.sublist(44), [1, 2, 3, 4]);
      expect(media.recording, false);
      expect(media.recordingAvailable, true);
      expect(await media.stopRecording(), same(wav));
      await media.cancelRecording();
      expect(media.recordingAvailable, false);
      expect(media.elapsed, Duration.zero);
    },
  );

  test('PCM byte cap stops capture and retains at most 30 seconds', () async {
    await media.startRecording();
    recorder.stream!.add(Uint8List(PodMediaController.maxPcmBytes + 400));
    final wav = await media.stopRecording();
    expect(wav.length, 1440044);
    expect(media.elapsed, const Duration(seconds: 30));
    expect(media.recording, false);
    expect(recorder.stops, 1);
  });

  test('wall-clock limit stops recording even if PCM delivery stalls', () {
    fakeAsync((clock) {
      // Construct every Future, stream and timer inside the same explicit fake
      // zone. No widget binding, rendering pump or real-time await is involved.
      final timedRecorder = FakeRecorder();
      final timedMedia = PodMediaController(
        playback: FakePlayback(),
        recorder: timedRecorder,
      );
      var started = false;
      unawaited(
        timedMedia.startRecording().then<void>((_) {
          started = true;
        }),
      );
      clock.flushMicrotasks();
      expect(started, true);
      expect(timedMedia.recording, true);
      timedRecorder.add([1, 2]);

      clock.elapse(const Duration(seconds: 29));
      expect(timedMedia.recording, true);
      expect(timedRecorder.stops, 0);

      // Only the production 30-second timer can request this first stop.
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(timedRecorder.stops, 1);
      expect(timedMedia.recording, false);
      expect(timedMedia.recordingAvailable, true);

      Uint8List? retained;
      unawaited(
        timedMedia.stopRecording().then<void>((wav) {
          retained = wav;
        }),
      );
      clock.flushMicrotasks();
      expect(retained?.length, 46);
      expect(timedRecorder.stops, 1);
      timedMedia.dispose();
      clock.flushMicrotasks();
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test(
    'cancel during permission prompt prevents late capture from starting',
    () async {
      recorder.permission = Completer<void>();
      final starting = media.startRecording();
      await Future<void>.delayed(Duration.zero);
      expect(recorder.starts, 1);
      final cancelled = media.cancelRecording();
      recorder.permission!.complete();
      await starting;
      await cancelled;
      expect(recorder.cancels, greaterThanOrEqualTo(1));
      expect(recorder.stream, isNull);
      expect(media.recording, false);
      expect(media.recordingAvailable, false);
    },
  );

  test(
    'disposal ignores late microphone permission and notifies no listeners',
    () async {
      recorder.permission = Completer<void>();
      final starting = media.startRecording();
      await Future<void>.delayed(Duration.zero);
      var notifications = 0;
      media.addListener(() => notifications++);
      media.dispose();
      recorder.permission!.complete();
      await starting;
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);
      expect(recorder.stream, isNull);
      expect(recorder.disposed, true);
      expect(playback.disposed, true);
    },
  );

  test('host playback is rejected while microphone is active', () async {
    await media.startRecording();
    await expectLater(
      media.play(Uint8List(4)),
      throwsA(isA<PodMediaException>()),
    );
    expect(playback.plays, 0);
    expect(media.recording, true);
    await media.cancelRecording();
  });

  test('WAV helper drops odd trailing byte and enforces server byte bound', () {
    expect(podPcmToWav(Uint8List.fromList([1, 2, 3])).sublist(44), [1, 2]);
    expect(podPcmToWav(Uint8List(1440101)).length, 1440044);
  });
}
