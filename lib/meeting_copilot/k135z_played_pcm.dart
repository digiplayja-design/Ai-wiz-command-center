import 'dart:math' as math;
import 'dart:typed_data';

abstract interface class K135zPcmSink {
  bool get active;
  void write(Uint8List pcm);
  void close();
}

typedef K135zPcmSinkFactory = K135zPcmSink? Function(void Function() flush);

// The cursor comes from the player's audio clock, not wall time. Only samples
// already rendered are copied; a suspended context or Silence cannot add the
// unheard remainder of a generated answer to the recording.
class K135zPlayedPcm {
  K135zPlayedPcm({required this.channels, required this.sampleRate,
    required this.playedSeconds, required this.sinkFactory}) {
    if (channels.isEmpty || channels.length > 8 || sampleRate < 8000 ||
        sampleRate > 192000 || channels.any((c) => c.length != channels.first.length)) {
      throw ArgumentError('Invalid playback buffer');
    }
    _cursor = _playedSamples;
    _sink = sinkFactory(flush);
  }
  final List<Float32List> channels;
  final num sampleRate;
  final double Function() playedSeconds;
  final K135zPcmSinkFactory sinkFactory;
  K135zPcmSink? _sink;
  int _cursor = 0;
  bool _closed = false;
  int get _playedSamples => math.min(
    math.min((playedSeconds().clamp(0, 45) * 16000).floor(),
      (channels.first.length * 16000 / sampleRate).floor()), 45 * 16000);

  void flush() {
    if (_closed) return;
    final end = _playedSamples;
    if (_sink?.active != true) {
      _sink?.close();
      _sink = sinkFactory(flush);
      // Recording may have begun halfway through this reply. Never backfill
      // audio that played before the separate recording choice.
      _cursor = end;
      return;
    }
    while (_cursor < end && _sink!.active) {
      final stop = math.min(end, _cursor + 8000);
      final bytes = Uint8List((stop - _cursor) * 2);
      final data = ByteData.sublistView(bytes);
      for (var i = _cursor; i < stop; i++) {
        final position = i * sampleRate / 16000;
        final a = math.min(position.floor(), channels.first.length - 1);
        final b = math.min(a + 1, channels.first.length - 1);
        final fraction = position - a;
        var sample = 0.0;
        for (final channel in channels) {
          sample += channel[a] * (1 - fraction) + channel[b] * fraction;
        }
        sample /= channels.length;
        if (!sample.isFinite) sample = 0;
        data.setInt16((i - _cursor) * 2,
          (sample.clamp(-1, 1) * 32767).round(), Endian.little);
      }
      _sink!.write(bytes);
      _cursor = stop;
    }
  }

  void finish() {
    if (_closed) return;
    flush();
    _closed = true;
    _sink?.close();
    _sink = null;
  }
}
