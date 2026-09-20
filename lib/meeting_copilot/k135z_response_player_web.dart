// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'k135z_response_player.dart';

K135zResponsePlayer createPlayer() => _WebPlayer();

class _WebPlayer implements K135zResponsePlayer {
  void Function()? _cancel;
  @override
  bool get supported => true;
  @override
  Future<void> play(Uint8List bytes) {
    stop();
    final done = Completer<void>(), audio = html.AudioElement();
    final url = html.Url.createObjectUrlFromBlob(
      html.Blob([bytes], 'audio/mpeg'),
    );
    Timer? timer;
    StreamSubscription<html.Event>? ended, error, visibility, pageHide;
    bool finished = false;
    void finish([Object? failure]) {
      if (finished) return;
      finished = true;
      timer?.cancel();
      ended?.cancel();
      error?.cancel();
      visibility?.cancel();
      pageHide?.cancel();
      audio.pause();
      audio.removeAttribute('src');
      audio.load();
      audio.remove();
      html.Url.revokeObjectUrl(url);
      _cancel = null;
      if (failure == null) {
        done.complete();
      } else {
        done.completeError(failure);
      }
    }

    _cancel = () => finish(StateError('Stopped'));
    audio
      ..autoplay = false
      ..loop = false
      ..muted = false
      ..volume = 1
      ..src = url;
    audio.setAttribute('playsinline', '');
    html.document.body?.append(audio);
    ended = audio.onEnded.listen((_) {
      if (audio.ended) finish();
    });
    error = audio.onError.listen(
      (_) => finish(StateError('Playback unavailable')),
    );
    visibility = html.document.onVisibilityChange.listen((_) {
      if (html.document.hidden == true) finish(StateError('Page hidden'));
    });
    pageHide = html.window.onPageHide.listen(
      (_) => finish(StateError('Page closed')),
    );
    timer = Timer(
      const Duration(seconds: 45),
      () => finish(StateError('Playback timed out')),
    );
    // Synchronous call in the Speak tap; loading audio never starts playback.
    audio.play().then((_) {
      if (finished) audio.pause();
    }, onError: (Object _) => finish(StateError('Playback unavailable')));
    return done.future;
  }

  @override
  void stop() => _cancel?.call();
}
