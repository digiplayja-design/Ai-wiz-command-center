import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

class PodSmallTalkClip {
  const PodSmallTalkClip(this.speaker, this.text, this.wav, this.duration);
  final String speaker, text;
  final Uint8List wav;
  final Duration duration;
}

/// Optional, bounded spoken transitions on the SAME unlocked voice player.
/// No browser speech synthesis, extra audio element, or microphone is used.
class PodSmallTalk {
  PodSmallTalk(this.load);
  final Future<Map<String, dynamic>> Function(String episode, String clip) load;
  final _loading = <String, Future<void>>{};
  final _clips = <String, PodSmallTalkClip>{};
  List<String> _order = [];
  String? _episode;
  int _cursor = 0;
  bool _closed = false;

  void warm(String episode, int hostCount) {
    if (_closed) return;
    final roles = ['host', 'analyst', if (hostCount == 3) 'challenger'];
    if (_episode != episode) {
      _episode = episode;
      _cursor = 0;
      _order = [
        for (var n = 0; n < 3; n++)
          for (final role in roles) '$role-$n',
      ];
    }
    for (var n = 0; n < roles.length; n++) {
      final id = _order[(_cursor + n) % _order.length];
      _loading.putIfAbsent(id, () async {
        try {
          final result = await load(episode, id);
          final audio = result['audio'];
          if (_closed ||
              result['id'] != id ||
              result['speaker'] != id.split('-').first ||
              result['text'] is! String ||
              (result['text'] as String).length > 180 ||
              audio is! Map ||
              audio['mime'] != 'audio/wav' ||
              audio['base64'] is! String ||
              (audio['base64'] as String).length > 640060) {
            return;
          }
          final seconds = audio['durationSeconds'];
          if (seconds is! num ||
              !seconds.isFinite ||
              seconds <= 0 ||
              seconds > 10) {
            return;
          }
          final wav = base64Decode(audio['base64'] as String);
          if (wav.length < 46 || wav.length > 480044) return;
          _clips[id] = PodSmallTalkClip(
            result['speaker'] as String,
            result['text'] as String,
            wav,
            Duration(milliseconds: (seconds * 1000).ceil()),
          );
        } catch (_) {
          // Small talk is optional. Failed assets cannot stall the actual pod
          // or trigger repeated synthesis requests in this screen.
        }
      });
    }
  }

  Future<void> fillWhile(
    Future<void> waiting, {
    required bool Function() canPlay,
    required Duration Function() remaining,
    Future<void> Function()? beforePlay,
    required Future<void> Function(PodSmallTalkClip clip) play,
  }) async {
    var ready = false;
    final settled = waiting.then<void>(
      (_) {
        ready = true;
      },
      onError: (Object _) {
        ready = true;
      },
    );
    final used = <String>{};
    for (var n = 0; n < 2; n++) {
      final delay = Completer<void>();
      final timer = Timer(
        Duration(milliseconds: n == 0 ? 800 : 1500),
        delay.complete,
      );
      try {
        await Future.any<void>([settled, delay.future]);
      } finally {
        timer.cancel();
      }
      if (_closed || ready || !canPlay() || _order.isEmpty) return;
      // Preserve the planned panel order; never wait for an optional download.
      PodSmallTalkClip? clip;
      for (var offset = 0; offset < _order.length; offset++) {
        final id = _order[(_cursor + offset) % _order.length];
        final candidate = _clips[id];
        if (candidate != null && !used.contains(id)) {
          _cursor += offset + 1;
          used.add(id);
          clip = candidate;
          break;
        }
      }
      if (clip == null ||
          remaining() <= clip.duration + const Duration(seconds: 2)) {
        return;
      }
      try {
        await beforePlay?.call();
        if (_closed || ready || !canPlay() || remaining() <= clip.duration) {
          return;
        }
        await play(clip);
      } catch (_) {
        return;
      }
      // Let a short sentence finish naturally if the next panelist became
      // ready during it. The caller awaits this before starting that panelist.
    }
  }

  void dispose() {
    _closed = true;
    _clips.clear();
    _loading.clear();
  }
}
