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
  final _requested = <String>{};
  final _clips = <String, PodSmallTalkClip>{};
  List<String> _order = [];
  String? _episode, _lastClip;
  int _cursor = 0, _revision = 0, _warming = 0;
  bool _closed = false;
  final _disposed = Completer<void>();

  void warm(String episode, int hostCount, {bool Function()? canLoad}) {
    if (_closed) return;
    final roles = ['host', 'analyst', if (hostCount == 3) 'challenger'];
    if (_episode != episode) {
      _episode = episode;
      _cursor = 0;
      _lastClip = null;
      _requested.clear();
      _order = [
        for (var n = 0; n < 3; n++)
          for (final role in roles) '$role-$n',
      ];
      ++_revision;
      _warming = 0;
    }
    if (_warming > 0 || canLoad?.call() == false) return;
    final revision = _revision;
    _warming = 2;
    // Fill the entire reusable bank in two lanes, including during a long
    // first research gap. Warming only the next pair left that gap stranded.
    for (var lane = 0; lane < 2; lane++) {
      unawaited(
        _warmLane(episode, revision, [
          for (var i = lane; i < _order.length; i += 2) _order[i],
        ], canLoad),
      );
    }
  }

  Future<void> _warmLane(
    String episode,
    int revision,
    List<String> ids,
    bool Function()? canLoad,
  ) async {
    try {
      for (final id in ids) {
        if (_closed || revision != _revision || canLoad?.call() == false) {
          return;
        }
        if (_clips.containsKey(id) || !_requested.add(id)) continue;
        try {
          final result = await load(episode, id);
          final audio = result['audio'];
          if (_closed ||
              revision != _revision ||
              result['id'] != id ||
              result['speaker'] != id.split('-').first ||
              result['text'] is! String ||
              (result['text'] as String).length > 180 ||
              audio is! Map ||
              audio['mime'] != 'audio/wav' ||
              audio['base64'] is! String ||
              (audio['base64'] as String).length > 640060) {
            continue;
          }
          final seconds = audio['durationSeconds'];
          if (seconds is! num ||
              !seconds.isFinite ||
              seconds <= 0 ||
              seconds > 10) {
            continue;
          }
          final wav = base64Decode(audio['base64'] as String);
          if (wav.length < 46 || wav.length > 480044) continue;
          _clips[id] = PodSmallTalkClip(
            result['speaker'] as String,
            result['text'] as String,
            wav,
            Duration(milliseconds: (seconds * 1000).ceil()),
          );
        } catch (_) {
          // Each asset is attempted once per episode. A failed download must
          // not stop warming the other voices or hold up the real discussion.
        }
      }
    } finally {
      if (revision == _revision) _warming--;
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
    var expired = false;
    final limit = Completer<void>();
    final budget = remaining() < const Duration(seconds: 225)
        ? remaining()
        : const Duration(seconds: 225);
    if (budget <= Duration.zero) return;
    final limitTimer = Timer(budget, () {
      expired = true;
      limit.complete();
    });
    final revision = _revision;
    final used = <String>{};
    var delayDuration = const Duration(milliseconds: 800);
    try {
      while (!_closed &&
          !ready &&
          !expired &&
          revision == _revision &&
          canPlay()) {
        final delay = Completer<void>();
        final timer = Timer(delayDuration, delay.complete);
        try {
          await Future.any<void>([
            settled,
            delay.future,
            limit.future,
            _disposed.future,
          ]);
        } finally {
          timer.cancel();
        }
        if (_closed ||
            ready ||
            expired ||
            revision != _revision ||
            !canPlay() ||
            _order.isEmpty) {
          return;
        }
        final available = _order.where((id) => _clips.containsKey(id)).toList();
        // Rotate through the available bank before reusing a sentence. Never
        // repeat the same clip consecutively, including across adjacent waits.
        if (available.length > 1 && available.every(used.contains)) {
          used.clear();
        }
        PodSmallTalkClip? clip;
        for (var offset = 0; offset < _order.length; offset++) {
          final id = _order[(_cursor + offset) % _order.length];
          final candidate = _clips[id];
          if (candidate != null && !used.contains(id) && id != _lastClip) {
            _cursor += offset + 1;
            used.add(id);
            _lastClip = id;
            clip = candidate;
            break;
          }
        }
        if (clip == null) {
          // Slow first downloads used to abandon the entire gap after 800 ms.
          // Wait only for local availability, racing the real response each time.
          if (_warming == 0) return;
          delayDuration = const Duration(milliseconds: 250);
          continue;
        }
        if (remaining() <= clip.duration + const Duration(seconds: 2)) return;
        try {
          await beforePlay?.call();
          if (_closed ||
              ready ||
              expired ||
              revision != _revision ||
              !canPlay() ||
              remaining() <= clip.duration) {
            return;
          }
          await play(clip);
        } catch (_) {
          return;
        }
        // Let a short sentence finish naturally if the next panelist became
        // ready during it. The caller awaits this before starting that panelist.
        delayDuration = const Duration(milliseconds: 900);
      }
    } finally {
      limitTimer.cancel();
    }
  }

  void dispose() {
    _closed = true;
    if (!_disposed.isCompleted) _disposed.complete();
    _clips.clear();
    _requested.clear();
  }
}
