import 'dart:async';

import 'package:flutter/services.dart';

import 'korlix_sound_player.dart';

KorlixSoundPlayer createKorlixSoundPlayer() => _NativeSoundPlayer();

/// Dedicated native effects channel: no audioplayers session/focus changes.
class _NativeSoundPlayer implements KorlixSoundPlayer {
  static const _native = MethodChannel('korlix/sound_effects');
  static int _nextOwner = 0;
  final String _owner =
      '${DateTime.now().microsecondsSinceEpoch}-${_nextOwner++}';
  final _revisions = <String, int>{'effect': 0, 'ring': 0, 'preview': 0};
  final _timers = <String, Timer>{};
  final _preparationTimers = <String, Timer>{};
  bool _ready = false;
  bool _disposed = false;
  Future<bool>? _activation;

  @override
  bool get ready => _ready && !_disposed;

  Future<bool> _send(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    try {
      return await _native.invokeMethod<bool>(method, {
            'owner': _owner,
            ...args,
          }) ==
          true;
    } catch (_) {
      // An older installed app or unsupported desktop lacks this native shim.
      return false;
    }
  }

  @override
  Future<bool> activate() {
    if (_disposed) return Future.value(false);
    if (ready) return Future.value(true);
    return _activation ??= _activate();
  }

  Future<bool> _activate() async {
    final available = await _send('activate');
    _ready = available && !_disposed;
    _activation = null;
    return ready;
  }

  @override
  Future<bool> play(
    Uint8List wav, {
    required double volume,
    required Duration duration,
    required String channel,
    bool loop = false,
  }) async {
    if (!ready ||
        !_revisions.containsKey(channel) ||
        !volume.isFinite ||
        volume <= 0 ||
        duration <= Duration.zero ||
        wav.length < 44 ||
        wav.length > 200000) {
      return false;
    }
    _timers.remove(channel)?.cancel();
    _preparationTimers.remove(channel)?.cancel();
    final revision = _revisions.update(channel, (value) => value + 1);
    final limit = duration.inMilliseconds.clamp(1, loop ? 45000 : 5000);
    void expire() {
      if (_revisions[channel] == revision) stop(channel);
    }

    // Loading a 45ms click must not consume its actual playback duration.
    // Preparation has its own short deadline; rings retain an absolute expiry.
    _preparationTimers[channel] = Timer(
      const Duration(milliseconds: 250),
      expire,
    );
    if (loop) _timers[channel] = Timer(Duration(milliseconds: limit), expire);
    final requestedAt = DateTime.now().millisecondsSinceEpoch;
    final played = await _send('play', {
      'channel': channel,
      'revision': revision,
      'wav': wav,
      'volume': volume.clamp(0.0, 1.0),
      'durationMs': limit,
      'loop': loop,
      'prepareDeadlineEpochMs': requestedAt + 250,
      'expiresEpochMs': requestedAt + limit,
    });
    if (!ready || _revisions[channel] != revision) return true;
    _preparationTimers.remove(channel)?.cancel();
    if (!played) {
      _timers.remove(channel)?.cancel();
    } else if (!loop) {
      // The native timer starts at playback; this is a secondary safety stop.
      _timers[channel] = Timer(Duration(milliseconds: limit), expire);
    }
    return played;
  }

  @override
  void stop(String channel) {
    if (!_revisions.containsKey(channel)) return;
    _timers.remove(channel)?.cancel();
    _preparationTimers.remove(channel)?.cancel();
    final revision = _revisions.update(channel, (value) => value + 1);
    unawaited(_send('stop', {'channel': channel, 'revision': revision}));
  }

  @override
  void stopAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    for (final timer in _preparationTimers.values) {
      timer.cancel();
    }
    _preparationTimers.clear();
    _revisions.updateAll((_, value) => value + 1);
    unawaited(_send('stopAll', {'revisions': Map.of(_revisions)}));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ready = false;
    stopAll();
    unawaited(_send('dispose'));
  }
}
