import 'dart:ui' as ui;
import 'package:flutter/services.dart';

/// One shared decoded atlas (about 6 MiB) across home mounts. No video players,
/// network providers, or per-frame image decoding are involved.
class KorlixClimberArtwork {
  static const asset =
      'assets/characters/button_climbers/realistic-people-v2.png';
  static Future<ui.Image>? _loading;
  static ui.Image? ready;
  static Future<ui.Image> load() => _loading ??= _decode();
  static Future<ui.Image> _decode() async {
    try {
      final bytes = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      try {
        return ready = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }
}
