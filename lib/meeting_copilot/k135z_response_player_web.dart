// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import '../sounds/korlix_sound_service.dart';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:web_audio' as web;
import 'k135z_response_player.dart';
import 'k135z_played_pcm.dart';

K135zResponsePlayer createPlayer({K135zPcmSinkFactory? recordingSink}) => _WebPlayer(recordingSink);

class _WebPlayer implements K135zResponsePlayer {
  _WebPlayer(this.recordingSink);
  final K135zPcmSinkFactory? recordingSink;
  void Function()? _cancel;
  @override
  bool get supported => web.AudioContext.supported;
  @override
  Future<void> play(Uint8List bytes) async {
    stop();
    // Activate audio in the Speak button's direct gesture, before decoding.
    final context = web.AudioContext();
    final resumed = context.resume();
    final done = Completer<void>();
    web.AudioBufferSourceNode? source;
    Timer? timer, recordingTimer;
    K135zPlayedPcm? recording;
    StreamSubscription<html.Event>? ended, visibility, pageHide;
    final soundQuietOwner = Object();
    bool finished = false;
    void finish([Object? failure]) {
      if (finished) return;
      finished = true;
      kKorlixSounds.setQuiet(soundQuietOwner, false);
      timer?.cancel();recordingTimer?.cancel();recording?.finish();
      ended?.cancel();visibility?.cancel();pageHide?.cancel();
      try { source?.stop(0); } catch (_) {}
      source?.disconnect();
      context.close().catchError((_) {});
      _cancel = null;
      if (failure == null) { done.complete(); } else { done.completeError(failure); }
    }
    // Attach a handler immediately; cancellation can precede decoding completion.
    unawaited(done.future.catchError((Object _) {}));
    _cancel = () => finish(StateError('Stopped'));
    visibility = html.document.onVisibilityChange.listen((_) {
      if (html.document.hidden == true) finish(StateError('Page hidden'));
    });
    pageHide = html.window.onPageHide.listen((_) => finish(StateError('Page closed')));
    timer = Timer(const Duration(seconds: 45), () => finish(StateError('Playback timed out')));
    try {
      await resumed.timeout(const Duration(seconds: 5));
      final buffer = await context.decodeAudioData(Uint8List.fromList(bytes).buffer)
        .timeout(const Duration(seconds: 8));
      if (finished || context.state != 'running') throw StateError('Playback unavailable');
      source = context.createBufferSource()..buffer = buffer;
      ended = source!.onEnded.listen((_) => finish());
      source!.connectNode(context.destination!);
      kKorlixSounds.setQuiet(soundQuietOwner, true);
      source!.start(0);
      if (recordingSink != null) {
        final started = context.currentTime!;
        recording = K135zPlayedPcm(
          channels: List.generate(buffer.numberOfChannels!, (i) => Float32List.fromList(buffer.getChannelData(i))),
          sampleRate: buffer.sampleRate!,
          playedSeconds: () => (context.currentTime! - started).toDouble(),
          sinkFactory: recordingSink!);
        recordingTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => recording?.flush());
      }
    } catch (_) { finish(StateError('Playback unavailable')); }
    await done.future;
  }
  @override
  void stop() => _cancel?.call();
}
