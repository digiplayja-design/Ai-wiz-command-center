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
  'mesh',
  'contour',
  'orbit',
  'linen',
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
  'mesh' => 'Color Mesh',
  'contour' => 'Contour',
  'orbit' => 'Orbit',
  'linen' => 'Linen',
  _ => 'Classic',
};
String korlixScreenSkinDescription(String id) => switch (id) {
  'glass' => 'Layered panes, soft reflections and polished edges.',
  'glass_break' => 'Fractured glass facets around your workspace.',
  'bubbles' => 'Iridescent bubbles with a playful, rounded frame.',
  'aurora' => 'Soft ribbons of light around a calm workspace.',
  'prism' => 'Geometric facets with a cut-crystal finish.',
  'mesh' => 'Blended pools of color with a soft, satin finish.',
  'contour' => 'Fine flowing lines and a quiet, sculpted frame.',
  'orbit' => 'Luminous orbital rings and scattered points of light.',
  'linen' => 'A subtle woven texture with a clean, tactile edge.',
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
    final radius = switch (skinId) {
      'bubbles' || 'mesh' => 32.0,
      'prism' || 'glass_break' => 12.0,
      'linen' || 'contour' => 18.0,
      _ => 24.0,
    };
    final quiet = skinId == 'linen' || skinId == 'contour';
    return Container(
      padding: EdgeInsets.all(decorated ? 8 : 0),
      decoration: BoxDecoration(
        gradient: decorated
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    palette.primary.withValues(alpha: quiet ? .04 : .14),
                    palette.panel,
                  ),
                  palette.panel.withValues(alpha: .94),
                  Color.alphaBlend(
                    palette.secondary.withValues(alpha: quiet ? .03 : .10),
                    palette.panel,
                  ),
                ],
                stops: const [0, .5, 1],
              )
            : null,
        borderRadius: BorderRadius.circular(radius),
        border: decorated
            ? Border.all(
                color: palette.primary.withValues(alpha: quiet ? .22 : .42),
                width: skinId == 'prism' ? 1.6 : 1,
              )
            : null,
        boxShadow: decorated
            ? [
                BoxShadow(
                  color: (quiet ? palette.text : palette.glow).withValues(
                    alpha: quiet ? .04 : (palette.isLight ? .10 : .16),
                  ),
                  blurRadius: quiet ? 10 : 26,
                  offset: const Offset(0, 5),
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
      case 'mesh':
        _mesh(canvas, size);
      case 'contour':
        _contour(canvas, size);
      case 'orbit':
        _orbit(canvas, size);
      case 'linen':
        _linen(canvas, size);
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

  void _mesh(Canvas canvas, Size s) {
    for (final (x, y, radius, color) in [
      (-.08, .13, .90, palette.primary),
      (.95, .25, .85, palette.secondary),
      (.70, .92, .90, palette.tertiary),
    ]) {
      final area = Rect.fromCircle(
        center: Offset(s.width * x, s.height * y),
        radius: math.min(s.width, s.height) * radius,
      );
      canvas.drawRect(
        Offset.zero & s,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: palette.isLight ? .22 : .33),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 1],
          ).createShader(area),
      );
    }
    _contour(canvas, s, soft: true);
  }

  void _contour(Canvas canvas, Size s, {bool soft = false}) {
    for (var i = 0; i < 16; i++) {
      final inset = i * .038;
      final path = Path()
        ..moveTo(s.width * (-.12 + inset), 0)
        ..cubicTo(
          s.width * (.90 + inset),
          s.height * .28,
          s.width * (-.48 + inset),
          s.height * .61,
          s.width * (.72 + inset),
          s.height,
        );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i % 4 == 0 ? 1.2 : .6
          ..color = (i.isEven ? palette.primary : palette.secondary).withValues(
            alpha: soft ? .065 : (i % 4 == 0 ? .20 : .09),
          ),
      );
    }
  }

  void _orbit(Canvas canvas, Size s) {
    final scale = math.min(s.width, s.height);
    for (final (x, y, angle) in [(.87, .15, -.55), (.06, .87, .5)]) {
      final center = Offset(s.width * x, s.height * y);
      final halo = Rect.fromCircle(center: center, radius: scale * .58);
      canvas.drawCircle(
        center,
        scale * .58,
        Paint()
          ..shader = RadialGradient(
            colors: [
              palette.primary.withValues(alpha: .16),
              palette.primary.withValues(alpha: 0),
            ],
          ).createShader(halo),
      );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      for (var ring = 0; ring < 4; ring++) {
        final oval = Rect.fromCenter(
          center: Offset.zero,
          width: scale * (.62 + ring * .17),
          height: scale * (.30 + ring * .11),
        );
        canvas.drawOval(
          oval,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = ring == 1 ? 2 : .8
            ..shader = SweepGradient(
              colors: [
                palette.primary.withValues(alpha: .03),
                palette.primary.withValues(alpha: .56),
                palette.secondary.withValues(alpha: .15),
                palette.primary.withValues(alpha: .03),
              ],
            ).createShader(oval),
        );
      }
      canvas.restore();
    }
    for (var i = 0; i < 24; i++) {
      final point = Offset(
        s.width * ((i * .618 + .07) % 1),
        s.height * ((i * .381 + .05) % 1),
      );
      canvas.drawCircle(
        point,
        i % 5 == 0 ? 1.8 : .8,
        Paint()
          ..color = palette.primary.withValues(alpha: i % 5 == 0 ? .55 : .22),
      );
    }
  }

  void _linen(Canvas canvas, Size s) {
    final stepX = math.max(3.0, s.width / 128);
    final stepY = math.max(3.0, s.height / 192);
    final thread = Paint()
      ..strokeWidth = .45
      ..color = palette.text.withValues(alpha: .045);
    for (var x = 0.0; x < s.width; x += stepX) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), thread);
    }
    for (var y = 0.0; y < s.height; y += stepY) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), thread);
    }
    final edge = Rect.fromLTWH(
      10,
      10,
      math.max(0, s.width - 20),
      math.max(0, s.height - 20),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(edge, const Radius.circular(18)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.primary.withValues(alpha: .12),
    );
  }

  @override
  bool shouldRepaint(covariant KorlixScreenSkinPainter oldDelegate) =>
      oldDelegate.palette.id != palette.id || oldDelegate.skinId != skinId;
}
