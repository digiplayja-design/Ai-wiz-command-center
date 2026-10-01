import 'pod_transition_audio.dart';

PodTransitionBackend createPodTransitionBackend() => _NoTransitionAudio();

/// Native voice playback stays unchanged where this optional web sound bed is
/// unavailable. A later native adapter can use the same bounded controller.
class _NoTransitionAudio implements PodTransitionBackend {
  @override
  bool get supported => false;
  @override
  Future<bool> activate() async => false;
  @override
  bool start(Duration maximumDuration) => false;
  @override
  Future<void> stop({required bool immediate}) async {}
  @override
  Future<void> dispose() async {}
}
