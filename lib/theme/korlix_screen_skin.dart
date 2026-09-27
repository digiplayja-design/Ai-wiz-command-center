import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'korlix_theme.dart';

const korlixScreenSkinIds = [
  'classic',
  'glass',
  'glass_break',
  'bubbles',
  'aurora',
  'prism',
];
final kKorlixScreenSkinNotifier = ValueNotifier<String>('classic');
String korlixNormalizeScreenSkin(String value) =>
    korlixScreenSkinIds.contains(value) ? value : 'classic';
String korlixScreenSkinLabel(String id) => switch (id) {
  'glass' => 'Glass',
  'glass_break' => 'Glass Break',
  'bubbles' => 'Bubbles',
  'aurora' => 'Aurora',
  'prism' => 'Prism',
  _ => 'Classic',
};
String korlixScreenSkinDescription(String id) => switch (id) {
  'glass' => 'Layered panes, soft reflections and polished edges.',
  'glass_break' => 'Fractured glass facets around your workspace.',
  'bubbles' => 'Iridescent bubbles with a playful, rounded frame.',
  'aurora' => 'Soft ribbons of light around a calm workspace.',
  'prism' => 'Geometric facets with a cut-crystal finish.',
  _ => 'A clean screen with no decorative wrapper.',
};

/// Decoration stays behind content, never receives input, and has no animation.
class KorlixScreenBackdrop extends StatelessWidget {
  const KorlixScreenBackdrop({
    super.key,
    required this.palette,
    required this.skinId,
    required this.child,
  });
  final KorlixSkinPalette palette;
  final String skinId;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Positioned.fill(
        child: ExcludeSemantics(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: KorlixScreenSkinPainter(palette, skinId),
              ),
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

class KorlixSkinFrame extends StatelessWidget {
  const KorlixSkinFrame({
    super.key,
    required this.palette,
    required this.skinId,
    required this.child,
  });
  final KorlixSkinPalette palette;
  final String skinId;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    // The widget structure remains stable when changing skins, preserving drafts.
    final decorated = skinId != 'classic';
    final radius = skinId == 'bubbles' ? 36.0 : 24.0;
    return Container(
      padding: EdgeInsets.all(decorated ? 10 : 0),
      decoration: BoxDecoration(
        color: decorated ? palette.panel.withValues(alpha: .88) : null,
        borderRadius: BorderRadius.circular(radius),
        border: decorated
            ? Border.all(
                color: palette.primary.withValues(alpha: .38),
                width: 1.3,
              )
            : null,
        boxShadow: decorated
            ? [
                BoxShadow(
                  color: palette.glow.withValues(
                    alpha: palette.isLight ? .10 : .16,
                  ),
                  blurRadius: 26,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class KorlixScreenSkinPainter extends CustomPainter {
  const KorlixScreenSkinPainter(this.palette, this.skinId);
  final KorlixSkinPalette palette;
  final String skinId;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.backgroundTop,
            palette.backgroundMid,
            palette.backgroundBottom,
          ],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipRect(rect);
    switch (korlixNormalizeScreenSkin(skinId)) {
      case 'glass':
        _glass(canvas, size);
      case 'glass_break':
        _fracture(canvas, size);
      case 'bubbles':
        _bubbles(canvas, size);
      case 'aurora':
        _aurora(canvas, size);
      case 'prism':
        _prism(canvas, size);
      default:
        break;
    }
    canvas.restore();
  }

  void _glass(Canvas canvas, Size s) {
    for (var i = 0; i < 5; i++) {
      final left = s.width * (-.2 + i * .27);
      final pane = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left,
          s.height * (-.12 + (i % 2) * .26),
          s.width * .46,
          s.height * .94,
        ),
        const Radius.circular(38),
      );
      canvas.save();
      canvas.translate(s.width / 2, s.height / 2);
      canvas.rotate(-.17);
      canvas.translate(-s.width / 2, -s.height / 2);
      canvas.drawRRect(
        pane,
        Paint()
          ..shader = LinearGradient(
            colors: [
              palette.primary.withValues(alpha: palette.isLight ? .09 : .17),
              palette.panel.withValues(alpha: .02),
              palette.secondary.withValues(alpha: .12),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(pane.outerRect),
      );
      canvas.drawRRect(
        pane,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = palette.primary.withValues(alpha: .25),
      );
      canvas.drawLine(
        Offset(pane.left + 18, pane.top + 40),
        Offset(pane.left + 18, pane.bottom - 40),
        Paint()
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: palette.isLight ? .65 : .25),
      );
      canvas.restore();
    }
  }

  void _bubbles(Canvas canvas, Size s) {
    const points = [
      (.08, .12, .13),
      (.85, .08, .18),
      (.24, .39, .09),
      (.91, .44, .14),
      (.10, .75, .18),
      (.70, .79, .12),
      (.51, .98, .19),
      (.59, .22, .07),
    ];
    final scale = math.min(s.width, s.height);
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final center = Offset(s.width * point.$1, s.height * point.$2);
      final radius = scale * point.$3;
      final area = Rect.fromCircle(center: center, radius: radius);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.4, -.5),
            colors: [
              Colors.white.withValues(alpha: palette.isLight ? .85 : .25),
              palette.primary.withValues(alpha: .08),
              palette.secondary.withValues(alpha: .30),
            ],
            stops: const [0, .65, 1],
          ).createShader(area),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..shader = SweepGradient(
            colors: [
              palette.primary.withValues(alpha: .7),
              palette.secondary.withValues(alpha: .16),
              Colors.white.withValues(alpha: .75),
              palette.primary.withValues(alpha: .7),
            ],
          ).createShader(area),
      );
      canvas.drawArc(
        area.deflate(radius * .16),
        math.pi * 1.05,
        math.pi * .40,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.5
          ..color = Colors.white.withValues(alpha: .72),
      );
    }
  }

  void _fracture(Canvas canvas, Size s) {
    final origin = Offset(s.width * .82, s.height * .19);
    final edges = [
      Offset(s.width * .50, 0),
      Offset(s.width * .89, 0),
      Offset(s.width, s.height * .06),
      Offset(s.width, s.height * .36),
      Offset(s.width, s.height * .88),
      Offset(s.width * .55, s.height),
      Offset(0, s.height * .90),
      Offset(0, s.height * .42),
      Offset(0, s.height * .05),
    ];
    for (var i = 0; i < edges.length; i++) {
      final next = edges[(i + 1) % edges.length];
      final edge = edges[i];
      final mid =
          Offset.lerp(origin, edge, .45)! +
          Offset((i.isEven ? 1 : -1) * s.width * .035, s.height * .015);
      final path = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(mid.dx, mid.dy)
        ..lineTo(edge.dx, edge.dy)
        ..lineTo(next.dx, next.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            colors: [
              palette.primary.withValues(alpha: .015),
              palette.secondary.withValues(alpha: i.isEven ? .17 : .05),
            ],
          ).createShader(Offset.zero & s),
      );
      final crack = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(mid.dx, mid.dy)
        ..lineTo(edge.dx, edge.dy);
      canvas.drawPath(
        crack,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = palette.primary.withValues(alpha: .40),
      );
      canvas.drawPath(
        crack.shift(const Offset(1.4, 1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8
          ..color = Colors.white.withValues(alpha: .5),
      );
      final fork = Offset.lerp(mid, next, .32)!;
      canvas.drawLine(
        mid,
        fork,
        Paint()
          ..strokeWidth = .7
          ..color = palette.secondary.withValues(alpha: .27),
      );
    }
  }

  void _aurora(Canvas canvas, Size s) {
    for (var i = 0; i < 5; i++) {
      final x = s.width * (-.25 + i * .30);
      final path = Path()
        ..moveTo(x, 0)
        ..cubicTo(
          x + s.width * .55,
          s.height * .33,
          x - s.width * .22,
          s.height * .62,
          x + s.width * .50,
          s.height,
        )
        ..lineTo(x + s.width * .69, s.height)
        ..cubicTo(
          x - s.width * .01,
          s.height * .64,
          x + s.width * .76,
          s.height * .32,
          x + s.width * .18,
          0,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              palette.primary.withValues(alpha: .06),
              palette.secondary.withValues(alpha: .20),
              palette.tertiary.withValues(alpha: .05),
            ],
          ).createShader(Offset.zero & s),
      );
    }
  }

  void _prism(Canvas canvas, Size s) {
    for (var row = 0; row < 4; row++) {
      for (var column = 0; column < 4; column++) {
        final x = column * s.width / 3, y = row * s.height / 3;
        final path = Path()
          ..moveTo(x, y)
          ..lineTo(x + s.width / 3, y + s.height / 9)
          ..lineTo(x + s.width / 7, y + s.height / 3)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              colors: [
                palette.primary.withValues(
                  alpha: (row + column).isEven ? .16 : .03,
                ),
                palette.secondary.withValues(alpha: .035),
              ],
            ).createShader(path.getBounds()),
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .7
            ..color = palette.primary.withValues(alpha: .14),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant KorlixScreenSkinPainter oldDelegate) =>
      oldDelegate.palette.id != palette.id || oldDelegate.skinId != skinId;
}
