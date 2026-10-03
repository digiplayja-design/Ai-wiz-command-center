import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'korlix_sound_player.dart';

KorlixSoundPlayer createKorlixSoundPlayer() => _WebSoundPlayer();

class _WebSoundPlayer implements KorlixSoundPlayer {
  web.AudioContext? _context;
  final _channels = <String, _Channel>{};
  final _generation = <String, int>{};
  final _buffers = <Uint8List, Future<web.AudioBuffer>>{};
  bool _disposed = false;
  JSFunction? _visibilityListener;

  @override
  bool get ready => !_disposed && _context?.state == 'running';

  @override
  Future<bool> activate() {
    if (_disposed || web.document.visibilityState != 'visible') {
      return Future.value(false);
    }
    try {
      final context = _context ??= web.AudioContext(
        web.AudioContextOptions(latencyHint: 'interactive'.toJS),
      );
      if (_visibilityListener == null) {
        _visibilityListener = ((web.Event _) {
          if (web.document.visibilityState != 'visible') stopAll();
        }).toJS;
        web.document.addEventListener('visibilitychange', _visibilityListener);
      }
      // Invoked synchronously from the user gesture; never after decoding.
      return context.resume().toDart.then(
        (_) => ready,
        onError: (Object _) => false,
      );
    } catch (_) {
      return Future.value(false);
    }
  }

  @override
  Future<bool> play(
    Uint8List wav, {
    required double volume,
    required Duration duration,
    required String channel,
    bool loop = false,
  }) async {
    if (!ready || web.document.visibilityState != 'visible') return false;
    stop(channel);
    final generation = _generation[channel] ?? 0;
    final context = _context!;
    try {
      final decoded = _buffers.putIfAbsent(wav, () {
        // decodeAudioData detaches its buffer; retain the cached WAV untouched.
        final bytes = Uint8List.fromList(wav);
        return context.decodeAudioData(bytes.buffer.toJS).toDart;
      });
      final buffer = await decoded;
      // Superseded or stopped requests are successful cancellations, not an
      // autoplay failure. They must never mark a newer ringtone as blocked.
      if (_generation[channel] != generation) return true;
      if (!ready || web.document.visibilityState != 'visible') {
        return false;
      }
      final gain = context.createGain();
      gain.gain.value = volume.clamp(0, 1);
      gain.connect(context.destination);
      final source = context.createBufferSource();
      source.buffer = buffer;
      source.loop = loop;
      source.connect(gain);
      final seconds = (duration.inMicroseconds / 1000000).clamp(.001, 45.0);
      final active = _Channel(source, gain);
      _channels[channel] = active;
      source.start();
      // Audio-clock bound survives throttled/suspended JavaScript timers.
      source.stop(context.currentTime + seconds);
      active.timer = Timer(
        Duration(microseconds: (seconds * 1000000).round()),
        () {
          if (identical(_channels[channel], active)) stop(channel);
        },
      );
      return true;
    } catch (_) {
      _buffers.remove(wav);
      return false;
    }
  }

  @override
  void stop(String channel) {
    _generation[channel] = (_generation[channel] ?? 0) + 1;
    final active = _channels.remove(channel);
    if (active == null) return;
    active.timer?.cancel();
    try {
      active.gain.disconnect();
    } catch (_) {}
    try {
      active.source.stop();
    } catch (_) {}
    try {
      active.source.disconnect();
    } catch (_) {}
  }

  @override
  void stopAll() {
    for (final channel in {'effect', 'ring', 'preview', ..._generation.keys}) {
      stop(channel);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    stopAll();
    _disposed = true;
    _buffers.clear();
    if (_visibilityListener != null) {
      web.document.removeEventListener('visibilitychange', _visibilityListener);
    }
    final context = _context;
    _context = null;
    if (context != null && context.state != 'closed') {
      unawaited(
        context.close().toDart.then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }
}

class _Channel {
  _Channel(this.source, this.gain);
  final web.AudioBufferSourceNode source;
  final web.GainNode gain;
  Timer? timer;
}
