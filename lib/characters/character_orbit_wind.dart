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
    required this.reducedMotion,
  });

  final KorlixSkinPalette skin;
  final double radiusX, radiusY, centerY, rotation, progress, direction;
  final bool front, reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1 || size.isEmpty) return;
    // Hold a clearly visible cloud through the spin before dispersing it.
    final fadeProgress = ((progress - .22) / .78).clamp(0.0, 1.0);
    final fade = math.pow(1 - fadeProgress, 1.1).toDouble();
    final opacity = fade * (front ? .9 : 1.0);
    final cloud = Color.lerp(
      skin.primary,
      skin.isLight ? const Color(0xFF6A859B) : const Color(0xFFF1FAFF),
      .9,
    )!;
    final center = Offset(size.width / 2, centerY + 14);
    final motion = reducedMotion ? 0.0 : progress;
    final phase = reducedMotion ? 0.0 : rotation;
    final drift = direction * motion * 1.25;
    final spread = 1 + motion * .16;

    void puff(Offset point, double width, double height, double alpha) {
      final rect = Rect.fromCenter(center: point, width: width, height: height);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              cloud.withValues(alpha: alpha),
              cloud.withValues(alpha: alpha * .8),
              cloud.withValues(alpha: 0),
            ],
            stops: const [0, .42, 1],
          ).createShader(rect),
      );
    }

    // Staggered, irregular ribbons resemble airy cloud wisps around the orbit.
    for (var ribbon = 0; ribbon < 3; ribbon++) {
      final start = phase + ribbon * 2.15 + drift;
      final sweep = 2.15 + ribbon * .24;
      final lane = 24.0 + ribbon * 8;
      Offset? previous;
      for (var i = 0; i <= 20; i++) {
        final t = i / 20;
        final angle = start - direction * sweep * t;
        final inFront = math.cos(angle) > 0;
        final taper = math.pow(math.sin(math.pi * t), .65).toDouble();
        final ripple = math.sin(t * math.pi * 4 + ribbon + motion * 1.5) * 6;
        final point =
            center +
            Offset(
              math.sin(angle) *
                  math.min(radiusX + lane + ripple, size.width / 2 - 27),
              // Place visible mist beyond the portraits' feet and upper rim.
              math.cos(angle) * (radiusY + 44 + lane * .35) + ripple * .55,
            );
        if (inFront != front) {
          previous = null;
          continue;
        }
        final billow = (23 + 17 * taper + ripple.abs()) * spread;
        final alpha = opacity * taper * (skin.isLight ? .48 : .62);
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
              ..color = cloud.withValues(alpha: opacity * taper * .42)
              ..strokeWidth = .8 + taper * 1.4
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
      oldDelegate.front != front ||
      oldDelegate.reducedMotion != reducedMotion;
}
