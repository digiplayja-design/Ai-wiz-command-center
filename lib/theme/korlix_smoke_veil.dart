import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A transparent plume layer over the live screen. Only the smoke is softened;
/// the original icons, text and media are never blurred, dimmed or replaced.
class KorlixSmokeVeil extends StatefulWidget {
  const KorlixSmokeVeil({super.key});
  @override
  State<KorlixSmokeVeil> createState() => _KorlixSmokeVeilState();
}

class _KorlixSmokeVeilState extends State<KorlixSmokeVeil>
    with SingleTickerProviderStateMixin {
  final _seconds = ValueNotifier<double>(0);
  late final Ticker _ticker;
  Duration _lastPaint = Duration.zero;
  bool _still = false;
  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (elapsed - _lastPaint < const Duration(milliseconds: 40)) return;
      _lastPaint = elapsed;
      _seconds.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (_still) {
      _ticker.stop();
      _seconds.value = 8;
    } else if (!_ticker.isActive) {
      _lastPaint = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: ClipRect(
        child: CustomPaint(
          painter: KorlixSmokePainter(
            _seconds,
            light: Theme.of(context).brightness == Brightness.light,
          ),
        ),
      ),
    ),
  );
}

class KorlixSmokePainter extends CustomPainter {
  KorlixSmokePainter(this.seconds, {required this.light})
    : super(repaint: seconds);
  final ValueListenable<double> seconds;
  final bool light;

  double _smooth(double value) {
    final t = value.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || seconds.value <= 0) return;
    final rect = Offset.zero & size;
    final scale = math.min(600.0, math.min(size.width, size.height));
    final plumeCount = (size.width / 200).round().clamp(4, 6);
    final time = seconds.value;
    final smoke = light ? const Color(0xFF526A79) : const Color(0xFFE5F0F4);
    final fadeIn = _smooth(time / 1.4);
    canvas.save();
    canvas.clipRect(rect);
    // Cap the combined opacity, including overlapping plumes. The live screen
    // retains at least 54% of its original contrast even in the thickest smoke.
    canvas.saveLayer(
      rect,
      Paint()..color = Colors.white.withValues(alpha: .46 * fadeIn),
    );
    for (var plume = 0; plume < plumeCount; plume++) {
      final phase = plume * 2.17;
      final lifetime = 12.8 + plume * .55;
      final delay = plume * .24;
      final root = size.width * ((plume + .5) / plumeCount);
      Offset centerAt(double progress, double seed) => Offset(
        root +
            scale *
                (.12 * math.sin(progress * 7 + phase + seed * .18) +
                    .055 * math.sin(progress * 17 - time * .26 + phase)) *
                (.3 + progress),
        size.height * (1.09 - progress * 1.43),
      );

      // Staggered clouds expand and curl as they rise, then disperse above the
      // screen. Their recycled birth positions are below the clipped edge.
      for (var puff = 0; puff < 8; puff++) {
        final born = delay + puff * lifetime / 8;
        if (time < born) continue;
        final age = (time - born) % lifetime;
        final progress = age / lifetime;
        final envelope =
            _smooth(age / 1.15) * (1 - _smooth((progress - .65) / .35));
        if (envelope <= .001) continue;
        final center = centerAt(progress, puff.toDouble());
        final radius = scale * (.08 + progress * .19);
        final rotation = phase + progress * 3 + .25 * math.sin(time * .22);
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(rotation);
        canvas.scale(1.2 + .2 * math.sin(phase + age), .85);
        // Overlapping offset lobes create billows with soft, irregular edges.
        for (var lobe = 0; lobe < 3; lobe++) {
          final angle = lobe * 2.4 + progress * 4;
          final offset = Offset(
            math.cos(angle) * radius * .38,
            math.sin(angle) * radius * .29,
          );
          final extent = radius * (lobe == 0 ? 1 : .78);
          canvas.drawCircle(
            offset,
            extent,
            Paint()
              ..shader = RadialGradient(
                colors: [
                  smoke.withValues(alpha: envelope * .48),
                  smoke.withValues(alpha: envelope * .22),
                  smoke.withValues(alpha: envelope * .055),
                  smoke.withValues(alpha: 0),
                ],
                stops: const [0, .34, .7, 1],
              ).createShader(Rect.fromCircle(center: offset, radius: extent)),
          );
        }
        // A folded edge inside each billow adds the thin, curling detail of
        // smoke without sharp outlines or a solid sheet across the screen.
        final curl = Path();
        for (var i = 0; i <= 28; i++) {
          final u = i / 28;
          final angle = u * math.pi * 1.75 + phase;
          final r = radius * (.16 + u * .73);
          final point = Offset(math.cos(angle) * r, math.sin(angle) * r * .8);
          if (i == 0) {
            curl.moveTo(point.dx, point.dy);
          } else {
            curl.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(
          curl,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = radius * .19
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .14)
            ..color = smoke.withValues(alpha: envelope * .30),
        );
        canvas.restore();
      }

      // Continuous wisps connect the rising billows to the lower screen.
      final reach = ((time - delay) / lifetime).clamp(0.0, .93);
      if (reach <= 0) continue;
      final trail = Path();
      for (var i = 0; i <= 40; i++) {
        final progress = i / 40 * reach;
        final point = centerAt(progress, 1.5);
        if (i == 0) {
          trail.moveTo(point.dx, point.dy);
        } else {
          trail.lineTo(point.dx, point.dy);
        }
      }
      final trailShader =
          LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              smoke.withValues(alpha: 0),
              smoke.withValues(alpha: .36),
              smoke.withValues(alpha: .20),
              smoke.withValues(alpha: 0),
            ],
            stops: const [0, .15, .55, 1],
          ).createShader(
            Rect.fromLTRB(
              0,
              size.height * (1.09 - reach * 1.43),
              size.width,
              size.height * 1.09,
            ),
          );
      for (final (width, blur) in [(.045, .022), (.011, .009)]) {
        canvas.drawPath(
          trail,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = scale * width
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * blur)
            ..shader = trailShader,
        );
      }
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant KorlixSmokePainter oldDelegate) =>
      light != oldDelegate.light || seconds != oldDelegate.seconds;
}
