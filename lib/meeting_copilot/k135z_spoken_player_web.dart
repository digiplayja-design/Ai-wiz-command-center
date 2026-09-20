// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:web_audio' as web;

import 'k135z_spoken_player.dart';

K135zSpokenPlayer createPlayer() => _SpokenPlayer();

class _SpokenPlayer implements K135zSpokenPlayer {
  web.AudioContext? _context;
  int _epoch = 0;
  void Function()? _cancel;
  StreamSubscription<html.Event>? _visibility, _pageHide;
  bool get supported => web.AudioContext.supported;
  bool get ready =>
      _context?.state == 'running' && html.document.hidden != true;

  Future<void> enable() async {
    stop();
    final epoch = _epoch;
    final context = _context = web.AudioContext();
    // Resume in the button's synchronous call stack, before any network request.
    final resumed = context.resume();
    _visibility = html.document.onVisibilityChange.listen((_) {
      if (html.document.hidden == true) stop();
    });
    _pageHide = html.window.onPageHide.listen((_) => stop());
    try {
      await resumed.timeout(const Duration(seconds: 5));
      if (epoch != _epoch || !ready)
        throw StateError('Audio activation interrupted');
      // Short, quiet confirmation tone also verifies the selected output device.
      final source = context.createOscillator(), gain = context.createGain();
      gain.gain!.value = 0.035;
      source.frequency!.value = 660;
      source.connectNode(gain);
      gain.connectNode(context.destination!);
      source.start2(0);
      source.stop(context.currentTime! + 0.12);
      source.onEnded.first.then((_) {
        source.disconnect();
        gain.disconnect();
      });
    } catch (_) {
      if (epoch == _epoch) stop();
      rethrow;
    }
  }

  Future<void> play(Uint8List bytes) async {
    if (!ready || _cancel != null)
      throw StateError('Tap Enable spoken replies again');
    final context = _context!, epoch = _epoch;
    final buffer = await context
        .decodeAudioData(Uint8List.fromList(bytes).buffer)
        .timeout(const Duration(seconds: 8));
    if (epoch != _epoch || !ready) throw StateError('Playback cancelled');
    final source = context.createBufferSource()..buffer = buffer;
    final done = Completer<void>();
    Timer? timer;
    StreamSubscription<html.Event>? ended;
    bool finished = false;
    void finish([Object? failure]) {
      if (finished) return;
      finished = true;
      timer?.cancel();
      ended?.cancel();
      try {
        source.stop(0);
      } catch (_) {}
      source.disconnect();
      _cancel = null;
      if (failure == null) {
        done.complete();
      } else {
        done.completeError(failure);
      }
    }

    _cancel = () => finish(StateError('Playback stopped'));
    ended = source.onEnded.listen((_) => finish());
    timer = Timer(
      const Duration(seconds: 45),
      () => finish(StateError('Playback timed out')),
    );
    source.connectNode(context.destination!);
    try {
      source.start(0);
    } catch (_) {
      finish(StateError('Playback unavailable'));
    }
    await done.future;
  }

  void stop() {
    _epoch++;
    _cancel?.call();
    _cancel = null;
    _visibility?.cancel();
    _pageHide?.cancel();
    _visibility = null;
    _pageHide = null;
    final context = _context;
    _context = null;
    if (context != null) context.close().catchError((_) {});
  }
}
