import 'dart:math' as math;
import 'dart:typed_data';

import 'korlix_sound_settings.dart';

const _sampleRate = 24000;
final _cache = <(KorlixSound, KorlixSoundPack, bool), Uint8List>{};

/// Duration includes the quiet part of the ringtone's repeating phrase.
Duration korlixSoundDuration(KorlixSound sound, {bool outgoing = false}) =>
    switch (sound) {
      KorlixSound.click => const Duration(milliseconds: 45),
      KorlixSound.bell => const Duration(milliseconds: 650),
      KorlixSound.message => const Duration(milliseconds: 280),
      KorlixSound.success => const Duration(milliseconds: 480),
      KorlixSound.warning => const Duration(milliseconds: 360),
      KorlixSound.ringtone => const Duration(seconds: 2),
    };

/// Original, locally synthesized 16-bit mono PCM. No network or licensed assets.
/// Cached bytes are read-only by convention; players must not mutate them.
Uint8List korlixSoundWav(
  KorlixSound sound,
  KorlixSoundPack pack, {
  bool outgoing = false,
}) {
  final ringback = sound == KorlixSound.ringtone && outgoing;
  return _cache.putIfAbsent((sound, pack, ringback), () {
    final count =
        korlixSoundDuration(sound).inMicroseconds * _sampleRate ~/ 1000000;
    final samples = Float64List(count);
    final base = switch (pack) {
      KorlixSoundPack.signature => 659.255,
      KorlixSoundPack.classic => 523.251,
      KorlixSoundPack.soft => 440.0,
    };

    void note(
      double start,
      double length,
      double frequency, {
      double gain = 0.45,
      bool bell = false,
    }) {
      final first = (start * _sampleRate).round();
      final frames = (length * _sampleRate).round();
      for (var j = 0; j < frames && first + j < count; j++) {
        final t = j / _sampleRate;
        final progress = j / (frames - 1);
        // Rounded attacks avoid clicks, and both ends reach digital silence.
        final attack = math.min(1.0, t / 0.004);
        final release = math.min(1.0, (1 - progress) * length / 0.024);
        final decay = math.exp(-(bell ? 5.5 : 2.8) * progress);
        final fundamental = math.sin(2 * math.pi * frequency * t);
        final overtone = switch (pack) {
          KorlixSoundPack.signature =>
            0.20 * math.sin(2 * math.pi * frequency * (bell ? 2.76 : 2) * t),
          KorlixSoundPack.classic =>
            0.30 * math.sin(2 * math.pi * frequency * 2 * t) +
                0.10 * math.sin(2 * math.pi * frequency * 3 * t),
          KorlixSoundPack.soft =>
            0.08 * math.sin(2 * math.pi * frequency * 2 * t),
        };
        samples[first + j] +=
            (fundamental + overtone) * gain * attack * release * decay;
      }
    }

    switch (sound) {
      case KorlixSound.click:
        note(0, 0.045, base * 1.9, gain: 0.34);
      case KorlixSound.bell:
        note(0, 0.65, base, bell: true);
        note(0.10, 0.50, base * 1.5, gain: 0.16, bell: true);
      case KorlixSound.message:
        note(0, 0.15, base, gain: 0.36);
        note(0.08, 0.20, base * 1.5, gain: 0.34);
      case KorlixSound.success:
        note(0, 0.22, base, gain: 0.33);
        note(0.11, 0.23, base * 1.25, gain: 0.33);
        note(0.22, 0.26, base * 1.5, gain: 0.33);
      case KorlixSound.warning:
        note(0, 0.17, base * 0.85, gain: 0.38);
        note(0.19, 0.17, base * 0.72, gain: 0.38);
      case KorlixSound.ringtone:
        if (ringback) {
          // A restrained dual tone distinguishes outgoing from incoming calls.
          note(0, 0.7, base * 0.64, gain: 0.22);
          note(0, 0.7, base * 0.73, gain: 0.22);
        } else {
          for (final start in [0.0, 0.70]) {
            note(start, 0.22, base, gain: 0.32);
            note(start + 0.15, 0.24, base * 1.25, gain: 0.32);
            note(start + 0.31, 0.28, base * 1.5, gain: 0.32);
          }
        }
    }

    final wav = Uint8List(44 + count * 2);
    final data = ByteData.sublistView(wav);
    void label(int offset, String value) =>
        wav.setRange(offset, offset + value.length, value.codeUnits);
    label(0, 'RIFF');
    data.setUint32(4, wav.length - 8, Endian.little);
    label(8, 'WAVE');
    label(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little); // Uncompressed PCM.
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, _sampleRate, Endian.little);
    data.setUint32(28, _sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    label(36, 'data');
    data.setUint32(40, count * 2, Endian.little);
    for (var i = 0; i < count; i++) {
      // Headroom also bounds overlapping notes before user volume is applied.
      data.setInt16(
        44 + i * 2,
        (samples[i].clamp(-0.68, 0.68) * 32767).round(),
        Endian.little,
      );
    }
    return wav;
  });
}
