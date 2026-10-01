import 'dart:typed_data';

import 'package:record/record.dart';

import 'pod_media.dart';

/// record implements PCM streaming / resampling on web as well as native.
/// Only start() requests microphone access; browsing and listening do not.
class DevicePodRecorder implements PodRecorderBackend {
  final _recorder = AudioRecorder();
  int _startRevision = 0;

  @override
  void cancelPendingStart() => _startRevision++;

  @override
  Future<Stream<Uint8List>> start() async {
    final revision = _startRevision;
    final permitted = await _recorder.hasPermission();
    if (revision != _startRevision) {
      throw const PodMediaException('Recording was cancelled.');
    }
    if (!permitted) {
      throw const PodMediaException(
        'Microphone access is off. Allow it in browser or device settings, then try again.',
      );
    }
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 24000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}
