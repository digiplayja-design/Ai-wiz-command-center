import 'dart:math' as math;
import 'dart:typed_data';

/// Local PCM only. These tones never become a WebRTC outgoing track.
Uint8List socialCallTone({bool ringing = false, bool silent = false}) {
  const rate = 8000;
  final seconds = silent
      ? .08
      : ringing
      ? 5.0
      : 1.1;
  final samples = (rate * seconds).round();
  final data = ByteData(44 + samples * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    final t = i / rate, beat = t % .36;
    final on = !silent && (ringing ? t < 1.6 : beat < .2 && t < 1);
    final edge = ringing ? math.min(t, 1.6 - t) : math.min(beat, .2 - beat);
    final fade = (edge / .012).clamp(0, 1);
    final wave = ringing
        ? (math.sin(2 * math.pi * 440 * t) + math.sin(2 * math.pi * 480 * t)) /
              2
        : math.sin(2 * math.pi * 660 * t);
    data.setInt16(
      44 + i * 2,
      on ? (wave * fade * 6500).round() : 0,
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}
