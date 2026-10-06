import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/korlix_theme.dart';

/// Two depth passes let the characters sit inside a brief cloud of wind.
/// Soft radial gradients need no image assets, blur filters or looping timers.
class KorlixOrbitWindPainter extends CustomPainter {
  const KorlixOrbitWindPainter({
    required this.skin,
    required this.radiusX,
    required this.radiusY,
    required this.centerY,
    required this.rotation,
    required this.progress,
    required this.direction,
    required this.front,
  });

  final KorlixSkinPalette skin;
  final double radiusX, radiusY, centerY, rotation, progress, direction;
  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1 || size.isEmpty) return;
    final fade = math.pow(1 - progress, 1.45).toDouble();
    final opacity = fade * (front ? .55 : 1.0);
    final cloud = Color.lerp(
      skin.primary,
      skin.isLight ? const Color(0xFF789AAC) : const Color(0xFFE9F7FF),
      .8,
    )!;
    final center = Offset(size.width / 2, centerY + 7);
    final drift = direction * progress * .5;
    final spread = 1 + progress * .2;

    void puff(Offset point, double width, double height, double alpha) {
      final rect = Rect.fromCenter(center: point, width: width, height: height);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              cloud.withValues(alpha: alpha),
              cloud.withValues(alpha: alpha * .62),
              cloud.withValues(alpha: 0),
            ],
            stops: const [0, .35, 1],
          ).createShader(rect),
      );
    }

    // Staggered, irregular ribbons resemble airy cloud wisps around the orbit.
    for (var ribbon = 0; ribbon < 3; ribbon++) {
      final start = rotation + ribbon * 2.15 + drift;
      final sweep = 1.9 + ribbon * .24;
      final lane = 10.0 + ribbon * 8;
      Offset? previous;
      for (var i = 0; i <= 20; i++) {
        final t = i / 20;
        final angle = start - direction * sweep * t;
        final inFront = math.cos(angle) > 0;
        final taper = math.pow(math.sin(math.pi * t), .65).toDouble();
        final ripple = math.sin(t * math.pi * 4 + ribbon) * 5;
        final point =
            center +
            Offset(
              math.sin(angle) * (radiusX + lane + ripple),
              math.cos(angle) * (radiusY + lane * .65) + ripple * .55,
            );
        if (inFront != front) {
          previous = null;
          continue;
        }
        final billow = (18 + 13 * taper + ripple.abs()) * spread;
        final alpha = opacity * taper * (skin.isLight ? .18 : .25);
        puff(point, billow * 2.0, billow * 1.15, alpha);
        // Small off-center lobes break up the shape into cloudlets.
        if (i.isEven) {
          puff(
            point + Offset(direction * 4, -7 - ribbon * 2),
            billow * 1.05,
            billow * .85,
            alpha * .7,
          );
        }
        if (previous != null) {
          canvas.drawLine(
            previous,
            point,
            Paint()
              ..color = cloud.withValues(alpha: opacity * taper * .27)
              ..strokeWidth = .65 + taper * 1.1
              ..strokeCap = StrokeCap.round,
          );
        }
        previous = point;
      }
    }
  }

  @override
  bool shouldRepaint(KorlixOrbitWindPainter oldDelegate) =>
      oldDelegate.skin != skin ||
      oldDelegate.radiusX != radiusX ||
      oldDelegate.radiusY != radiusY ||
      oldDelegate.centerY != centerY ||
      oldDelegate.rotation != rotation ||
      oldDelegate.progress != progress ||
      oldDelegate.direction != direction ||
      oldDelegate.front != front;
}
