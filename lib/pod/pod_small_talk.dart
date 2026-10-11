import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

class PodSmallTalkClip {
  const PodSmallTalkClip(this.speaker, this.text, this.wav, this.duration);
  final String speaker, text;
  final Uint8List wav;
  final Duration duration;
}

/// Optional spoken interludes on the SAME unlocked voice player.
/// Each episode consumes its shuffled bank once, with six turns prefetched and
/// at most two downloads in flight. There is no repeat loop or separate player.
class PodSmallTalk {
  PodSmallTalk(this.load);
  final Future<Map<String, dynamic>> Function(String episode, String clip) load;
  final _loading = <String>{};
  final _clips = <String, PodSmallTalkClip>{};
  List<String> _order = [];
  String? _episode;
  bool Function()? _canLoad;
  int _cursor = 0, _nextLoad = 0, _revision = 0;
  bool _closed = false;
  final _disposed = Completer<void>();

  void warm(
    String episode,
    int hostCount, {
    int conversationCount = 0,
    bool Function()? canLoad,
  }) {
    if (_closed) return;
    _canLoad = canLoad;
    if (_episode != episode) {
      _episode = episode;
      _cursor = _nextLoad = 0;
      _clips.clear();
      _loading.clear();
      ++_revision;
      final roles = ['host', 'analyst', if (hostCount == 3) 'challenger'];
      final extended = conversationCount > 0 && conversationCount <= 64;
      final exchanges = List.generate(
        extended ? conversationCount : 3,
        (n) => n,
      );
      // Shuffle exchanges, not individual voices: each mini conversation keeps
      // its host/analyst/challenger order, with a different route in each pod.
      if (extended) exchanges.shuffle(Random(episode.hashCode));
      _order = [
        for (final n in exchanges)
          for (final role in roles) extended ? '$role-chat-$n' : '$role-$n',
      ];
    }
    _fillBuffer();
  }

  void _fillBuffer() {
    if (_closed || _canLoad?.call() == false) return;
    while (_loading.length < 2 &&
        _nextLoad < _order.length &&
        _nextLoad < _cursor + 6) {
      final id = _order[_nextLoad++];
      _loading.add(id);
      unawaited(_loadOne(_episode!, _revision, id));
    }
  }

  Future<void> _loadOne(String episode, int revision, String id) async {
    try {
      final result = await load(episode, id);
      final audio = result['audio'];
      final extended = id.contains('-chat-');
      final maxSeconds = extended ? 30 : 10;
      final maxBytes = 44 + 48000 * maxSeconds;
      if (_closed ||
          revision != _revision ||
          result['id'] != id ||
          result['speaker'] != id.split('-').first ||
          result['text'] is! String ||
          (result['text'] as String).trim().isEmpty ||
          (result['text'] as String).length > (extended ? 480 : 180) ||
          audio is! Map ||
          audio['mime'] != 'audio/wav' ||
          audio['base64'] is! String ||
          (audio['base64'] as String).length > ((maxBytes + 2) ~/ 3) * 4) {
        return;
      }
      final seconds = audio['durationSeconds'];
      if (seconds is! num ||
          !seconds.isFinite ||
          seconds <= 0 ||
          seconds > maxSeconds) {
        return;
      }
      final wav = base64Decode(audio['base64'] as String);
      if (wav.length < 46 || wav.length > maxBytes) return;
      _clips[id] = PodSmallTalkClip(
        result['speaker'] as String,
        result['text'] as String,
        wav,
        Duration(milliseconds: (seconds * 1000).ceil()),
      );
    } catch (_) {
      // Attempt each asset once. A missing optional turn cannot block the next
      // available one or trigger paid retry loops.
    } finally {
      if (revision == _revision) {
        _loading.remove(id);
        _fillBuffer();
      }
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
            !canPlay()) {
          return;
        }
        // Only move forward. This cursor survives every gap, pause and warmup
        // in the episode; exhausting the bank must never restart a recording.
        while (_cursor < _nextLoad &&
            !_loading.contains(_order[_cursor]) &&
            !_clips.containsKey(_order[_cursor])) {
          _cursor++;
          _fillBuffer();
        }
        if (_cursor >= _order.length) return;
        final id = _order[_cursor];
        final clip = _clips[id];
        if (clip == null) {
          // Keep exchange order even if the second voice downloaded first.
          // Readiness always wins this wait for optional local audio.
          if (_loading.isEmpty) return;
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
          _cursor++;
          _clips.remove(id);
          _fillBuffer();
          await play(clip);
        } catch (_) {
          return;
        }
        // Finish the current thought naturally, then hand off immediately if
        // the researched turn is ready. Never finish a whole exchange first.
        delayDuration = const Duration(milliseconds: 450);
      }
    } finally {
      limitTimer.cancel();
    }
  }

  void dispose() {
    _closed = true;
    if (!_disposed.isCompleted) _disposed.complete();
    _clips.clear();
    _loading.clear();
  }
}
