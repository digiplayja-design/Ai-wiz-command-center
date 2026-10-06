import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Soft procedural smoke. No video, network image, audio or continuous ticker
/// is created until the screensaver is actually visible.
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
      // Gentle motion needs at most 25 updates per second.
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
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final ink = light ? const Color(0xFF203943) : const Color(0xFFECF4F7);
    return Material(
      type: MaterialType.transparency,
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: _still ? Duration.zero : const Duration(milliseconds: 1400),
          curve: Curves.easeOut,
          builder: (context, opacity, child) =>
              Opacity(opacity: opacity, child: child),
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: ColoredBox(
                    color:
                        (light
                                ? const Color(0xFFCCD7DC)
                                : const Color(0xFF07111A))
                            .withValues(alpha: .76),
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: KorlixSmokePainter(_seconds, light: light),
                  ),
                ),
                Center(
                  child: Text(
                    'KORLIX',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: ink.withValues(alpha: .60),
                      fontSize: 30,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 10,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (light ? Colors.white : const Color(0xFF0A1520))
                                  .withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: ink.withValues(alpha: .14)),
                        ),
                        child: Text(
                          'Tap anywhere to return',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: ink,
                            fontSize: 13,
                            height: 1.4,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class KorlixSmokePainter extends CustomPainter {
  KorlixSmokePainter(this.seconds, {required this.light})
    : super(repaint: seconds);
  final ValueListenable<double> seconds;
  final bool light;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final scale = math.min(size.width, size.height);
    final time = seconds.value * .14;
    final smoke = light ? const Color(0xFF667E8B) : const Color(0xFFD1E5EA);
    canvas.save();
    canvas.clipRect(rect);
    for (var layer = 0; layer < 6; layer++) {
      Offset at(double u) => Offset(
        size.width * (u * 1.5 - .25),
        size.height *
            ((layer + .2) / 5.8 +
                .09 *
                    math.sin(
                      u * 5.4 + time * (layer.isEven ? 1 : -.7) + layer * 1.7,
                    ) +
                .035 * math.sin(u * 11.7 - time * .5 + layer) +
                .018 * math.cos(time + layer)),
      );
      for (var puff = 0; puff < 8; puff++) {
        final u = (puff + .3) / 8 + .035 * math.sin(time * .7 + layer);
        final center = at(u);
        final radius =
            scale * (.16 + .06 * math.sin(puff * 2.4 + layer + time * .35));
        final area = Rect.fromCircle(center: Offset.zero, radius: radius);
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(.5 * math.sin(u * 5 + time + layer));
        canvas.scale(1.7, .85 + .22 * math.sin(puff + time));
        canvas.drawCircle(
          Offset.zero,
          radius,
          Paint()
            ..shader = RadialGradient(
              colors: [
                smoke.withValues(alpha: light ? .17 : .15),
                smoke.withValues(alpha: .045),
                smoke.withValues(alpha: 0),
              ],
              stops: const [0, .46, 1],
            ).createShader(area),
        );
        canvas.restore();
      }
      final path = Path()..moveTo(at(0).dx, at(0).dy);
      for (var point = 1; point <= 32; point++) {
        final next = at(point / 32);
        path.lineTo(next.dx, next.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = scale * .065
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * .032)
          ..shader = LinearGradient(
            colors: [
              smoke.withValues(alpha: 0),
              smoke.withValues(alpha: light ? .23 : .17),
              smoke.withValues(alpha: .03),
              smoke.withValues(alpha: 0),
            ],
            stops: const [0, .35, .72, 1],
          ).createShader(rect),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = scale * .012
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * .010)
          ..color = smoke.withValues(alpha: .08),
      );
    }
    // Two curling wisps break up the horizontal haze with drifting eddies.
    for (var curl = 0; curl < 2; curl++) {
      final center = Offset(
        size.width * (.25 + curl * .55 + .08 * math.sin(time)),
        size.height * (.30 + curl * .43 + .07 * math.cos(time * .8)),
      );
      final path = Path();
      for (var point = 0; point <= 56; point++) {
        final angle =
            point / 56 * math.pi * 2.3 + time * (curl == 0 ? .5 : -.5);
        final radius = scale * (.04 + point / 56 * .27);
        final offset =
            center +
            Offset(math.cos(angle) * radius * 1.6, math.sin(angle) * radius);
        if (point == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = scale * .035
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * .022)
          ..color = smoke.withValues(alpha: .17),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant KorlixSmokePainter oldDelegate) =>
      light != oldDelegate.light || seconds != oldDelegate.seconds;
}
