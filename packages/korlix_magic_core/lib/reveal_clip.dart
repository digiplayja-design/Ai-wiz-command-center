import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// Export uses the final image only; the original capture is never an argument.
Future<Uint8List> makeRevealClip(Uint8List finalImage) =>
    compute(_encodeReveal, finalImage);
Uint8List _encodeReveal(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw StateError('Unreadable final image');
  final photo = img.copyResize(decoded, width: 360);
  final height = photo.height.clamp(360, 640);
  final encoder = img.GifEncoder();
  for (var n = 0; n < 24; n++) {
    final frame = img.Image(width: 360, height: height);
    img.fill(frame, color: img.ColorRgb8(7, 17, 31));
    if (n < 12) {
      for (var ring = 0; ring < 3; ring++) {
        for (var dot = 0; dot < 65; dot++) {
          final a = dot * math.pi * 2 / 65 + n * .2 * (ring.isEven ? 1 : -1),
              x = 180 + math.cos(a) * (80 + ring * 25),
              y = height / 2 + math.sin(a) * (32 + ring * 20);
          img.fillCircle(
            frame,
            x: x.round(),
            y: y.round(),
            radius: dot % 9 == 0 ? 3 : 1,
            color: ring.isEven
                ? img.ColorRgb8(255, 152, 47)
                : img.ColorRgb8(57, 156, 255),
          );
        }
      }
    } else {
      final radius = (n - 11) / 6 * math.sqrt(180 * 180 + height * height / 4);
      final offset = (photo.height - height) ~/ 2;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < 360; x++) {
          if (math.pow(x - 180, 2) + math.pow(y - height / 2, 2) <
              radius * radius) {
            final sy = (y + offset).clamp(0, photo.height - 1);
            frame.setPixel(x, y, photo.getPixel(x, sy));
          }
        }
      }
    }
    encoder.addFrame(frame, duration: n == 23 ? 200 : 8);
  }
  // Keep encoding self-contained and keep only final artwork in the clip.
  return Uint8List.fromList(encoder.finish()!);
}
