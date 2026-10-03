import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/korlix_theme.dart';

/// Uses the device's calendar month, so the seasonal welcome ends in November.
/// The optional date keeps previews and boundary tests deterministic.
bool korlixIsOctober([DateTime? date]) => (date ?? DateTime.now()).month == 10;

/// A seasonal background around the existing authentication form.
/// Decorations never receive input, enter the semantics tree, or animate.
class KorlixOctoberWelcome extends StatelessWidget {
  const KorlixOctoberWelcome({super.key, required this.child, this.date});

  final Widget child;
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final october = korlixIsOctober(date);
    final skin = korlixSkinOf(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: october
              ? const [Color(0xFF17142F), Color(0xFF332044), Color(0xFF132B39)]
              : [skin.backgroundTop, skin.backgroundMid, skin.backgroundBottom],
        ),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          if (october)
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: CustomPaint(painter: _OctoberWelcomePainter()),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// Compact seasonal copy that belongs with the form, not behind its controls.
/// It disappears completely outside October and supports the app languages.
class KorlixOctoberGreeting extends StatelessWidget {
  const KorlixOctoberGreeting({super.key, this.date, this.languageCode = 'en'});

  final DateTime? date;
  final String languageCode;

  @override
  Widget build(BuildContext context) {
    if (!korlixIsOctober(date)) return const SizedBox.shrink();
    final copy = _copyFor(languageCode);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF0D9), Color(0xFFFFE4C7)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFFCA85)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              const ExcludeSemantics(
                child: SizedBox(
                  width: 42,
                  height: 44,
                  child: CustomPaint(painter: _FriendlyPumpkinPainter()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      copy.$1,
                      style: const TextStyle(
                        color: Color(0xFF603313),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      copy.$2,
                      style: const TextStyle(
                        color: Color(0xFF70452E),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static (String, String) _copyFor(String language) {
    switch (language.toLowerCase().split(RegExp('[-_]')).first) {
      case 'es':
      case 'spanish':
      case 'español':
        return ('Un octubre lleno de magia', '¡Feliz temporada de Halloween!');
      case 'fr':
      case 'french':
      case 'français':
        return ("Un peu de magie en octobre", "Joyeuse saison d’Halloween !");
      default:
        return ('A little October magic', 'Happy Halloween season!');
    }
  }
}

class _FriendlyPumpkinPainter extends CustomPainter {
  const _FriendlyPumpkinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 130, size.height / 130);
    canvas.save();
    canvas.translate(
      (size.width - scale * 130) / 2,
      (size.height - scale * 130) / 2,
    );
    canvas.scale(scale);
    _paintPumpkin(canvas, const Offset(65, 70), 59);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FriendlyPumpkinPainter oldDelegate) => false;
}

class _OctoberWelcomePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wide = size.width >= 850;
    final unit = wide ? math.min(size.width / 1280, 1.4) : 0.64;

    // Soft amber and violet pools frame the form without reducing its contrast.
    for (final glow in [
      (Offset(size.width * 0.1, size.height * 0.73), const Color(0xFFEA8739)),
      (Offset(size.width * 0.89, size.height * 0.25), const Color(0xFFAC8AFF)),
    ]) {
      final radius = (wide ? 290.0 : 170.0) * unit;
      canvas.drawCircle(
        glow.$1,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              glow.$2.withValues(alpha: .13),
              glow.$2.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: glow.$1, radius: radius)),
      );
    }

    // Fixed positions keep the page calm and respect reduced-motion settings.
    const stars = [
      (.08, .13, 5.0),
      (.2, .25, 3.5),
      (.36, .07, 3.0),
      (.74, .09, 4.0),
      (.93, .38, 4.5),
      (.86, .68, 3.0),
      (.11, .53, 2.5),
      (.27, .89, 4.0),
      (.71, .94, 3.0),
      (.92, .89, 5.0),
      (.045, .32, 2.5),
      (.97, .17, 2.0),
    ];
    for (final star in stars) {
      _paintStar(
        canvas,
        Offset(size.width * star.$1, size.height * star.$2),
        star.$3 * (wide ? unit : .8),
        const Color(0xFFFFD6A2).withValues(alpha: .7),
      );
    }

    final moon = Offset(
      size.width * .85,
      wide ? 100 * unit : 57,
    );
    canvas.drawCircle(
      moon,
      29 * unit,
      Paint()..color = const Color(0xFFFFE4B0),
    );
    canvas.drawCircle(
      moon + Offset(12 * unit, -7 * unit),
      26 * unit,
      Paint()..color = const Color(0xFF2D1E40),
    );

    final pumpkin = Offset(
      wide ? size.width * .14 : 29,
      size.height - 78 * unit,
    );
    _paintPumpkin(canvas, pumpkin, 99 * unit);
    _paintPumpkin(canvas, pumpkin + Offset(100 * unit, 27 * unit), 51 * unit);
    _paintLeaf(
      canvas,
      pumpkin + Offset(-66 * unit, -84 * unit),
      21 * unit,
      -.6,
    );
    _paintLeaf(
      canvas,
      Offset(size.width * .89, size.height * .8),
      20 * unit,
      .5,
    );

    final ghost = Offset(
      wide ? size.width * .87 : size.width - 23,
      wide ? size.height * .43 : 123,
    );
    _paintGhost(canvas, ghost, 54 * unit);
  }

  @override
  bool shouldRepaint(_OctoberWelcomePainter oldDelegate) => false;
}

void _paintPumpkin(Canvas canvas, Offset center, double radius) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(radius / 60);
  canvas.drawOval(
    const Rect.fromLTWH(-58, 39, 116, 17),
    Paint()..color = const Color(0xFF101427).withValues(alpha: .22),
  );
  final stem = Path()
    ..moveTo(-6, -40)
    ..quadraticBezierTo(-12, -57, 1, -62)
    ..lineTo(10, -56)
    ..quadraticBezierTo(0, -52, 7, -40)
    ..close();
  canvas.drawPath(stem, Paint()..color = const Color(0xFF619073));
  for (final segment in [
    (-57.0, -39.0, 53.0, 85.0, const Color(0xFFF19A3E)),
    (4.0, -39.0, 53.0, 85.0, const Color(0xFFDB762C)),
    (-43.0, -43.0, 59.0, 94.0, const Color(0xFFFFB74D)),
    (-16.0, -43.0, 59.0, 94.0, const Color(0xFFF28B2F)),
    (-27.0, -46.0, 54.0, 99.0, const Color(0xFFFFA742)),
  ]) {
    canvas.drawOval(
      Rect.fromLTWH(segment.$1, segment.$2, segment.$3, segment.$4),
      Paint()..color = segment.$5,
    );
  }
  final face = Paint()
    ..color = const Color(0xFF603717)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.5
    ..strokeCap = StrokeCap.round;
  // Little happy arcs, blush and a smile make this welcoming rather than scary.
  for (final x in [-18.0, 18.0]) {
    canvas.drawArc(
      Rect.fromCenter(center: Offset(x, -4), width: 10, height: 10),
      math.pi,
      math.pi,
      false,
      face,
    );
  }
  canvas.drawArc(const Rect.fromLTWH(-17, 4, 34, 25), 0, math.pi, false, face);
  for (final x in [-30.0, 30.0]) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, 9), width: 14, height: 7),
      Paint()..color = const Color(0xFFD86338).withValues(alpha: .46),
    );
  }
  canvas.restore();
}

void _paintGhost(Canvas canvas, Offset center, double radius) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(radius / 50);
  canvas.rotate(-.12);
  final body = Path()
    ..moveTo(-42, 43)
    ..lineTo(-38, -4)
    ..cubicTo(-36, -53, 34, -53, 39, -4)
    ..lineTo(45, 43)
    ..quadraticBezierTo(33, 56, 22, 43)
    ..quadraticBezierTo(10, 60, -2, 45)
    ..quadraticBezierTo(-17, 60, -27, 43)
    ..quadraticBezierTo(-35, 54, -42, 43)
    ..close();
  canvas.drawPath(body, Paint()..color = const Color(0xFFEDE6FF));
  final face = Paint()..color = const Color(0xFF4B3C6C);
  canvas.drawOval(const Rect.fromLTWH(-17, -4, 7, 11), face);
  canvas.drawOval(const Rect.fromLTWH(10, -4, 7, 11), face);
  canvas.drawArc(
    const Rect.fromLTWH(-8, 10, 16, 12),
    0,
    math.pi,
    false,
    Paint()
      ..color = const Color(0xFF4B3C6C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round,
  );
  for (final x in [-24.0, 24.0]) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, 11), width: 10, height: 6),
      Paint()..color = const Color(0xFFD7B5D0),
    );
  }
  canvas.restore();
}

void _paintStar(Canvas canvas, Offset center, double radius, Color color) {
  final star = Path()
    ..moveTo(center.dx, center.dy - radius)
    ..quadraticBezierTo(
      center.dx + radius * .22,
      center.dy - radius * .22,
      center.dx + radius,
      center.dy,
    )
    ..quadraticBezierTo(
      center.dx + radius * .22,
      center.dy + radius * .22,
      center.dx,
      center.dy + radius,
    )
    ..quadraticBezierTo(
      center.dx - radius * .22,
      center.dy + radius * .22,
      center.dx - radius,
      center.dy,
    )
    ..quadraticBezierTo(
      center.dx - radius * .22,
      center.dy - radius * .22,
      center.dx,
      center.dy - radius,
    )
    ..close();
  canvas.drawPath(star, Paint()..color = color);
}

void _paintLeaf(Canvas canvas, Offset center, double radius, double rotation) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(rotation);
  final leaf = Path()
    ..moveTo(0, -radius)
    ..quadraticBezierTo(radius, -radius * .4, 0, radius)
    ..quadraticBezierTo(-radius, radius * .4, 0, -radius)
    ..close();
  canvas.drawPath(
    leaf,
    Paint()..color = const Color(0xFFE6A458).withValues(alpha: .6),
  );
  canvas.drawLine(
    Offset(0, -radius * .5),
    Offset(0, radius * .6),
    Paint()
      ..color = const Color(0xFF543B38)
      ..strokeWidth = 1.3,
  );
  canvas.restore();
}
