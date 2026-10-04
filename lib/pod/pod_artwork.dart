import 'dart:math' as math;

import 'package:flutter/material.dart';

const _ink = Color(0xFF080D20);
const _cyan = Color(0xFF73EFE1);
const _lavender = Color(0xFFB6A2FF);
const _coral = Color(0xFFFF9B88);
const _gold = Color(0xFFF4CC84);

/// Decorative, resolution-independent artwork for the podcast setup.
class PodStudioArtwork extends StatelessWidget {
  const PodStudioArtwork({super.key, this.height});

  final double? height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: double.infinity,
      height: height ?? 300,
      child: const RepaintBoundary(
        child: CustomPaint(painter: _StudioPainter()),
      ),
    ),
  );
}

/// Small topic illustrations; fits the available tile without raster assets.
class PodTopicArtwork extends StatelessWidget {
  const PodTopicArtwork({super.key, required this.category});

  final String category;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _TopicPainter(category),
        size: const Size(120, 90),
      ),
    ),
  );
}

/// Rici's established avatar and distinct synthetic identities for her guests.
class PodHostPortrait extends StatelessWidget {
  const PodHostPortrait({
    super.key,
    required this.role,
    this.size = 80,
    this.active = false,
  });

  final String role;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _HostPainter(role, active),
          foregroundPainter: role.toLowerCase() == 'host'
              ? _HostRimPainter(active)
              : null,
          child: role.toLowerCase() == 'host'
              ? Padding(
                  padding: EdgeInsets.all(size * .09),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/meeting_copilot/nova_canonical.webp',
                      width: size * .82,
                      height: size * .82,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.expand(),
                    ),
                  ),
                )
              : null,
        ),
      ),
    ),
  );
}

Paint _fill(Color color) => Paint()..color = color;

Paint _line(Color color, [double width = 1]) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Color _alpha(Color color, double opacity) =>
    color.withValues(alpha: opacity.clamp(0, 1).toDouble());

Paint _gradient(
  Rect bounds,
  List<Color> colors, {
  Alignment begin = Alignment.topLeft,
  Alignment end = Alignment.bottomRight,
  List<double>? stops,
}) => Paint()
  ..shader = LinearGradient(
    begin: begin,
    end: end,
    colors: colors,
    stops: stops,
  ).createShader(bounds);

void _glow(
  Canvas canvas,
  Offset center,
  double radius,
  Color color, [
  double strength = .24,
]) {
  final bounds = Rect.fromCircle(center: center, radius: radius);
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..shader = RadialGradient(
        colors: [_alpha(color, strength), _alpha(color, 0)],
      ).createShader(bounds),
  );
}

void _star(Canvas canvas, Offset at, double radius, Color color) {
  canvas.drawLine(
    at.translate(-radius, 0),
    at.translate(radius, 0),
    _line(color, .8),
  );
  canvas.drawLine(
    at.translate(0, -radius),
    at.translate(0, radius),
    _line(color, .8),
  );
  canvas.drawCircle(at, radius * .22, _fill(Colors.white));
}

class _StudioPainter extends CustomPainter {
  const _StudioPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    final scale = math.min(size.width / 640, size.height / 380);
    canvas.translate(
      (size.width - 640 * scale) / 2,
      (size.height - 380 * scale) / 2,
    );
    canvas.scale(scale);

    _glow(canvas, const Offset(204, 139), 225, _cyan, .13);
    _glow(canvas, const Offset(428, 144), 210, _lavender, .16);
    _glow(canvas, const Offset(491, 246), 136, _coral, .11);

    // Light curtains behind the three voices.
    for (final spotlight in [
      (x: 188.0, color: _cyan, width: 63.0),
      (x: 322.0, color: _lavender, width: 75.0),
      (x: 456.0, color: _coral, width: 57.0),
    ]) {
      final path = Path()
        ..moveTo(spotlight.x - 6, 36)
        ..lineTo(spotlight.x + 6, 36)
        ..lineTo(spotlight.x + spotlight.width, 304)
        ..lineTo(spotlight.x - spotlight.width, 304)
        ..close();
      canvas.drawPath(
        path,
        _gradient(
          Rect.fromLTRB(
            spotlight.x - spotlight.width,
            36,
            spotlight.x + spotlight.width,
            304,
          ),
          [
            _alpha(spotlight.color, 0),
            _alpha(spotlight.color, .055),
            _alpha(spotlight.color, 0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      );
    }

    // The large orbital sound field is intentionally understated behind the hardware.
    canvas.save();
    canvas.translate(322, 165);
    canvas.rotate(-.19);
    for (var i = 0; i < 4; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: 398.0 + i * 52,
          height: 185.0 + i * 29,
        ),
        _line(_alpha(i.isEven ? _cyan : _lavender, .10 - i * .016), .85),
      );
    }
    canvas.drawArc(
      const Rect.fromLTRB(-248, -120, 248, 120),
      math.pi * .88,
      math.pi * .29,
      false,
      _line(_alpha(_cyan, .53), 1.5),
    );
    canvas.drawArc(
      const Rect.fromLTRB(-275, -136, 275, 136),
      -.2,
      .43,
      false,
      _line(_alpha(_lavender, .53), 1.5),
    );
    canvas.restore();

    for (final star in [
      (at: const Offset(94, 77), size: 3.0),
      (at: const Offset(506, 62), size: 3.5),
      (at: const Offset(552, 189), size: 2.7),
      (at: const Offset(115, 214), size: 2.0),
      (at: const Offset(337, 35), size: 2.0),
    ]) {
      _star(canvas, star.at, star.size, _alpha(_lavender, .7));
    }
    for (var i = 0; i < 21; i++) {
      final x = 80 + (i * 83 % 491).toDouble();
      final y = 38 + (i * 59 % 203).toDouble();
      canvas.drawCircle(
        Offset(x, y),
        i % 3 == 0 ? 1.3 : .7,
        _fill(_alpha(Colors.white, .1 + (i % 4) * .06)),
      );
    }

    // Sound bars float behind the table, with deterministic heights.
    for (var i = 0; i < 61; i++) {
      final x = 69.0 + i * 8.3;
      final envelope = math.pow(math.sin(i / 60 * math.pi), 1.6).toDouble();
      final height = 4 + envelope * (13 + 25 * math.sin(i * 1.27).abs());
      final color = Color.lerp(_cyan, _lavender, i / 60)!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, 267), width: 2, height: height),
          const Radius.circular(2),
        ),
        _fill(_alpha(color, .13 + envelope * .14)),
      );
    }

    // Elliptical broadcast desk, a thin illuminated rim, and a darker front edge.
    const desk = Rect.fromLTWH(75, 278, 490, 73);
    canvas.drawOval(
      desk.shift(const Offset(0, 10)),
      _fill(const Color(0xFF030716)),
    );
    canvas.drawOval(
      desk,
      _gradient(desk, [
        const Color(0xFF26344C),
        const Color(0xFF182337),
        const Color(0xFF111827),
      ]),
    );
    canvas.drawOval(desk, _line(_alpha(_cyan, .19), 1));
    canvas.drawArc(desk, 0, math.pi, false, _line(_alpha(_lavender, .30), 1.5));
    canvas.drawOval(
      const Rect.fromLTWH(145, 287, 345, 43),
      _line(_alpha(_cyan, .055), 1),
    );

    // Two side microphones have individual materials and gestures.
    _microphone(canvas, const Offset(190, 265), .85, -.16, _cyan);
    _microphone(canvas, const Offset(454, 265), .85, .16, _coral);
    _microphone(canvas, const Offset(322, 279), 1.14, 0, _lavender);

    // Minimal studio indicators on the desk surface.
    const console = Rect.fromLTWH(274, 318, 96, 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(console, const Radius.circular(7)),
      _fill(const Color(0xFF080F20)),
    );
    for (var i = 0; i < 15; i++) {
      final h = 2.0 + (math.sin(i * .93).abs() * 5);
      canvas.drawLine(
        Offset(286.0 + i * 5, 326 - h / 2),
        Offset(286.0 + i * 5, 326 + h / 2),
        _line(_alpha(i < 10 ? _cyan : _lavender, .7), 1.8),
      );
    }
    canvas.restore();
  }

  void _microphone(
    Canvas canvas,
    Offset anchor,
    double scale,
    double angle,
    Color accent,
  ) {
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.scale(scale);

    // Contact shadow and lathed stand base.
    canvas.drawOval(
      const Rect.fromLTWH(-49, 21, 98, 19),
      _fill(_alpha(Colors.black, .40)),
    );
    const base = Rect.fromLTWH(-38, 18, 76, 15);
    canvas.drawOval(
      base.shift(const Offset(0, 4)),
      _fill(const Color(0xFF050B14)),
    );
    canvas.drawOval(
      base,
      _gradient(base, [
        const Color(0xFF405367),
        const Color(0xFF102234),
        const Color(0xFF1A2C40),
      ]),
    );
    canvas.drawArc(
      base,
      math.pi,
      math.pi,
      false,
      _line(_alpha(accent, .65), 1.4),
    );
    const stem = Rect.fromLTWH(-5, -31, 10, 55);
    canvas.drawRRect(
      RRect.fromRectAndRadius(stem, const Radius.circular(4)),
      _gradient(
        stem,
        [
          const Color(0xFF0A1423),
          const Color(0xFF65768B),
          const Color(0xFF142436),
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
    );

    canvas.translate(0, -36);
    canvas.rotate(angle);
    // Suspension yoke with two precise highlight edges.
    final yoke = Path()
      ..moveTo(-40, -70)
      ..lineTo(-40, -5)
      ..quadraticBezierTo(-40, 14, -20, 14)
      ..lineTo(20, 14)
      ..quadraticBezierTo(40, 14, 40, -5)
      ..lineTo(40, -70);
    canvas.drawPath(yoke, _line(const Color(0xFF071220), 8));
    canvas.drawPath(yoke, _line(const Color(0xFF43546B), 4));
    canvas.drawPath(yoke, _line(_alpha(accent, .29), 1));

    const body = Rect.fromLTWH(-30, -157, 60, 158);
    final bodyShape = RRect.fromRectAndRadius(body, const Radius.circular(29));
    canvas.drawRRect(
      bodyShape.shift(const Offset(5, 5)),
      _fill(_alpha(Colors.black, .25)),
    );
    canvas.drawRRect(
      bodyShape,
      _gradient(
        body,
        [
          const Color(0xFF0C1929),
          const Color(0xFF69758A),
          const Color(0xFF26384D),
          const Color(0xFF091525),
        ],
        stops: const [0, .25, .58, 1],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
    );
    canvas.drawRRect(bodyShape, _line(_alpha(accent, .5), .9));

    // Dense woven grille in the capsule. No icon-font glyphs or raster assets.
    final grille = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-27, -154, 54, 105),
      const Radius.circular(26),
    );
    canvas.save();
    canvas.clipRRect(grille);
    canvas.drawRRect(
      grille,
      _gradient(
        grille.outerRect,
        [
          const Color(0xFF151E2E),
          const Color(0xFF46576C),
          const Color(0xFF101A2C),
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
    );
    for (var y = -148.0; y < -48; y += 4) {
      canvas.drawLine(
        Offset(-29, y),
        Offset(29, y),
        _line(const Color(0xFF090F1F), 1.65),
      );
      canvas.drawLine(
        Offset(-26, y + 1),
        Offset(26, y + 1),
        _line(_alpha(Colors.white, .11), .65),
      );
    }
    for (var x = -25.0; x < 27; x += 5) {
      canvas.drawLine(
        Offset(x, -156),
        Offset(x, -46),
        _line(_alpha(const Color(0xFFCAD5E1), .12), .6),
      );
    }
    canvas.drawRect(
      const Rect.fromLTWH(-19, -158, 7, 115),
      _fill(_alpha(Colors.white, .055)),
    );
    canvas.restore();

    const band = Rect.fromLTWH(-29, -56, 58, 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(band, const Radius.circular(2)),
      _gradient(
        band,
        [
          const Color(0xFF172A3F),
          const Color(0xFF94A5B9),
          const Color(0xFF25364B),
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
    );
    canvas.drawLine(
      const Offset(-24, -47),
      const Offset(23, -47),
      _line(_alpha(accent, .9), 1.3),
    );
    _glow(canvas, const Offset(0, -23), 16, accent, .25);
    canvas.drawCircle(const Offset(0, -23), 4, _fill(accent));
    canvas.drawCircle(const Offset(-.7, -24), 1.4, _fill(Colors.white));
    for (final x in [-37.0, 37.0]) {
      canvas.drawCircle(Offset(x, -64), 7, _fill(const Color(0xFF16263A)));
      canvas.drawCircle(Offset(x, -64), 5, _line(_alpha(accent, .6), 1));
      canvas.drawLine(
        Offset(x - 1.5, -64),
        Offset(x + 1.5, -64),
        _line(const Color(0xFF718198), 1),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StudioPainter oldDelegate) => false;
}

class _TopicPainter extends CustomPainter {
  const _TopicPainter(this.category);
  final String category;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final scale = math.min(size.width / 120, size.height / 90);
    canvas.translate(
      (size.width - 120 * scale) / 2,
      (size.height - 90 * scale) / 2,
    );
    canvas.scale(scale);
    final key = category.toLowerCase();
    final color = switch (key) {
      'politics' => _lavender,
      'sports' => _coral,
      'religion' => _gold,
      'culture' || 'entertainment' => _coral,
      'business' => _gold,
      _ => _cyan,
    };
    _glow(canvas, const Offset(62, 45), 52, color, .12);
    canvas.drawOval(
      const Rect.fromLTWH(20, 71, 84, 10),
      _fill(_alpha(Colors.black, .25)),
    );
    switch (key) {
      case 'politics':
        _politics(canvas, color);
      case 'sports':
        _sports(canvas, color);
      case 'religion':
        _religion(canvas, color);
      case 'culture' || 'entertainment':
        _culture(canvas, color);
      case 'business':
        _business(canvas, color);
      case 'trending' || 'trending topics':
        _trending(canvas, color);
      default:
        _technology(canvas, color);
    }
    canvas.restore();
  }

  void _politics(Canvas canvas, Color color) {
    final roof = Path()
      ..moveTo(22, 32)
      ..lineTo(61, 13)
      ..lineTo(99, 32)
      ..close();
    canvas.drawPath(
      roof,
      _gradient(
        const Rect.fromLTWH(22, 13, 77, 19),
        [color, const Color(0xFF4A467A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );
    canvas.drawPath(roof, _line(_alpha(Colors.white, .5), .7));
    final inset = Path()
      ..moveTo(39, 28)
      ..lineTo(61, 19)
      ..lineTo(82, 28);
    canvas.drawPath(inset, _line(_alpha(_ink, .55), 1));
    canvas.drawRect(
      const Rect.fromLTWH(22, 33, 77, 5),
      _gradient(const Rect.fromLTWH(22, 33, 77, 5), [
        const Color(0xFFB6A2FF),
        const Color(0xFF4A467A),
      ]),
    );
    for (var i = 0; i < 4; i++) {
      final x = 28.0 + i * 18;
      final column = Rect.fromLTWH(x, 39, 10, 26);
      canvas.drawRect(
        column,
        _gradient(
          column,
          [const Color(0xFF343754), color, const Color(0xFF5E567F)],
          stops: const [0, .35, 1],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      );
      canvas.drawRect(
        Rect.fromLTWH(x - 1, 39, 12, 3),
        _fill(_alpha(color, .9)),
      );
      canvas.drawRect(
        Rect.fromLTWH(x - 1, 64, 12, 3),
        _fill(_alpha(color, .9)),
      );
      canvas.drawLine(
        Offset(x + 3, 43),
        Offset(x + 3, 61),
        _line(_alpha(Colors.white, .35), .7),
      );
    }
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(
        Rect.fromLTWH(24.0 - i * 3, 68.0 + i * 3, 74.0 + i * 6, 2),
        _fill(_alpha(color, .85 - i * .17)),
      );
    }
    _star(canvas, const Offset(105, 19), 3, color);
  }

  void _sports(Canvas canvas, Color color) {
    canvas.save();
    canvas.translate(62, 45);
    canvas.rotate(-.27);
    canvas.drawOval(
      const Rect.fromLTRB(-50, -17, 50, 17),
      _line(_alpha(_lavender, .35), 1.3),
    );
    canvas.drawCircle(
      Offset.zero,
      28,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.45, -.55),
          radius: 1,
          colors: [Color(0xFFFFC79F), Color(0xFFFF9B88), Color(0xFF853F53)],
        ).createShader(const Rect.fromLTRB(-28, -28, 28, 28)),
    );
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 28)),
    );
    canvas.drawLine(
      const Offset(-28, 0),
      const Offset(28, 0),
      _line(const Color(0xFF683848), 1.5),
    );
    canvas.drawLine(
      const Offset(0, -28),
      const Offset(0, 28),
      _line(const Color(0xFF683848), 1.5),
    );
    canvas.drawOval(
      const Rect.fromLTRB(-52, -33, -5, 33),
      _line(const Color(0xFF683848), 1.5),
    );
    canvas.drawOval(
      const Rect.fromLTRB(5, -33, 52, 33),
      _line(const Color(0xFF683848), 1.5),
    );
    for (var y = -23; y <= 23; y += 5) {
      for (var x = -24; x <= 24; x += 5) {
        canvas.drawCircle(
          Offset(x.toDouble(), y.toDouble()),
          .45,
          _fill(_alpha(const Color(0xFF6D3444), .28)),
        );
      }
    }
    canvas.restore();
    canvas.drawArc(
      const Rect.fromLTRB(-50, -17, 50, 17),
      .02,
      math.pi * .86,
      false,
      _line(_alpha(_lavender, .92), 1.6),
    );
    canvas.drawCircle(const Offset(-45, 7), 3, _fill(_cyan));
    canvas.restore();
    _star(canvas, const Offset(96, 18), 3, color);
  }

  void _religion(Canvas canvas, Color color) {
    // An inclusive architectural sunrise: no one faith is used as the category icon.
    for (var i = 0; i < 3; i++) {
      final rect = Rect.fromLTWH(
        25.0 + i * 8,
        13.0 + i * 8,
        72.0 - i * 16,
        65.0 - i * 8,
      );
      final arch = Path()
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.left, rect.top + rect.width / 2)
        ..arcTo(
          Rect.fromLTWH(rect.left, rect.top, rect.width, rect.width),
          math.pi,
          math.pi,
          false,
        )
        ..lineTo(rect.right, rect.bottom);
      canvas.drawPath(arch, _line(_alpha(color, .28 + i * .18), 3.5 - i * .4));
      canvas.drawPath(
        arch.shift(const Offset(1, 0)),
        _line(_alpha(Colors.white, .15), .7),
      );
    }
    _glow(canvas, const Offset(61, 56), 23, color, .3);
    canvas.drawCircle(
      const Offset(61, 57),
      12,
      _gradient(
        const Rect.fromLTWH(49, 45, 24, 24),
        [const Color(0xFFFFEDC3), color, _coral],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    );
    canvas.drawRect(
      const Rect.fromLTWH(33, 58, 57, 20),
      _fill(const Color(0xFF11182B)),
    );
    canvas.drawLine(
      const Offset(33, 58),
      const Offset(90, 58),
      _line(_alpha(color, .7), .8),
    );
    for (var i = 0; i < 4; i++) {
      final w = 19.0 - i * 3;
      canvas.drawLine(
        Offset(61 - w / 2, 62.0 + i * 4),
        Offset(61 + w / 2, 62.0 + i * 4),
        _line(_alpha(color, .5 - i * .1), 1.3),
      );
    }
    _star(canvas, const Offset(100, 31), 2, color);
  }

  void _culture(Canvas canvas, Color color) {
    canvas.save();
    canvas.translate(61, 44);
    canvas.rotate(-.18);
    const sleeve = Rect.fromLTWH(-36, -25, 51, 59);
    canvas.drawRRect(
      RRect.fromRectAndRadius(sleeve, const Radius.circular(3)),
      _gradient(sleeve, [
        const Color(0xFF7D6AAA),
        const Color(0xFF4F4675),
        const Color(0xFF2A324F),
      ]),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-34, 7)
        ..lineTo(-12, -15)
        ..lineTo(15, 16)
        ..lineTo(15, 33)
        ..lineTo(-34, 33)
        ..close(),
      _fill(_alpha(_coral, .7)),
    );
    canvas.drawCircle(const Offset(-19, -11), 7, _fill(_gold));
    canvas.drawCircle(
      const Offset(12, 0),
      28,
      _gradient(const Rect.fromLTRB(-16, -28, 40, 28), [
        const Color(0xFF1A2B41),
        const Color(0xFF060C19),
        const Color(0xFF28334D),
      ]),
    );
    for (var i = 0; i < 6; i++) {
      canvas.drawCircle(
        const Offset(12, 0),
        13 + i * 2.3,
        _line(_alpha(_lavender, .16), .6),
      );
    }
    canvas.drawCircle(
      const Offset(12, 0),
      9,
      _gradient(const Rect.fromLTWH(3, -9, 18, 18), [color, _lavender]),
    );
    canvas.drawCircle(const Offset(12, 0), 2, _fill(_ink));
    canvas.drawArc(
      const Rect.fromLTWH(-10, -22, 44, 44),
      -2.2,
      .8,
      false,
      _line(_alpha(Colors.white, .35), 1.5),
    );
    canvas.restore();
    _star(canvas, const Offset(103, 24), 3, _lavender);
    canvas.drawCircle(const Offset(18, 45), 2, _fill(_cyan));
  }

  void _business(Canvas canvas, Color color) {
    for (var i = 0; i < 3; i++) {
      final x = 29.0 + i * 23;
      final top = 47.0 - i * 12;
      final front = Rect.fromLTRB(x, top, x + 15, 72);
      canvas.drawRect(
        front,
        _gradient(
          front,
          [_alpha(color, .9 - i * .1), const Color(0xFF614D43)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      );
      final side = Path()
        ..moveTo(x + 15, top)
        ..lineTo(x + 21, top - 5)
        ..lineTo(x + 21, 66)
        ..lineTo(x + 15, 72)
        ..close();
      canvas.drawPath(side, _fill(const Color(0xFF755F54)));
      final roof = Path()
        ..moveTo(x, top)
        ..lineTo(x + 6, top - 5)
        ..lineTo(x + 21, top - 5)
        ..lineTo(x + 15, top)
        ..close();
      canvas.drawPath(roof, _fill(_alpha(color, .95)));
      for (var y = top + 7; y < 68; y += 7) {
        canvas.drawLine(
          Offset(x + 4, y),
          Offset(x + 10, y),
          _line(_alpha(_ink, .33), 1.3),
        );
      }
    }
    final growth = Path()
      ..moveTo(18, 41)
      ..lineTo(39, 27)
      ..lineTo(59, 33)
      ..lineTo(90, 12);
    canvas.drawPath(growth, _line(_cyan, 2));
    canvas.drawPath(
      Path()
        ..moveTo(82, 12)
        ..lineTo(90, 12)
        ..lineTo(90, 20),
      _line(_cyan, 2),
    );
    for (final point in [
      const Offset(18, 41),
      const Offset(39, 27),
      const Offset(59, 33),
    ]) {
      canvas.drawCircle(point, 2.5, _fill(_cyan));
    }
  }

  void _trending(Canvas canvas, Color color) {
    // A ribbon waveform climbing into an arrow, backed by orbiting signal dots.
    canvas.drawOval(
      const Rect.fromLTWH(18, 17, 86, 58),
      _line(_alpha(_lavender, .2), 1),
    );
    canvas.drawArc(
      const Rect.fromLTWH(25, 12, 76, 67),
      -.9,
      1.2,
      false,
      _line(_alpha(_lavender, .65), 1),
    );
    final ribbon = Path()
      ..moveTo(22, 62)
      ..cubicTo(34, 62, 31, 32, 43, 35)
      ..cubicTo(55, 38, 51, 62, 65, 47)
      ..lineTo(91, 21);
    canvas.drawPath(
      ribbon.shift(const Offset(0, 4)),
      _line(_alpha(color, .10), 10),
    );
    final shader =
        _gradient(
            const Rect.fromLTWH(22, 21, 69, 43),
            [_lavender, color, const Color(0xFFD4FFF9)],
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round;
    canvas.drawPath(ribbon, shader);
    canvas.drawPath(
      Path()
        ..moveTo(75, 21)
        ..lineTo(91, 21)
        ..lineTo(91, 37),
      _line(const Color(0xFFCCFFF7), 5),
    );
    canvas.drawCircle(const Offset(22, 62), 4, _fill(_lavender));
    canvas.drawCircle(const Offset(95, 63), 4, _fill(_coral));
    canvas.drawCircle(const Offset(30, 21), 2, _fill(color));
    _star(canvas, const Offset(62, 17), 3, _lavender);
  }

  void _technology(Canvas canvas, Color color) {
    canvas.save();
    canvas.translate(61, 45);
    canvas.rotate(-.20);
    for (var i = 0; i < 4; i++) {
      final shift = -15.0 + i * 10;
      for (final side in [-1.0, 1.0]) {
        final vertical = Path()
          ..moveTo(shift, side * 24)
          ..lineTo(shift, side * 33)
          ..lineTo(shift + 6, side * 39);
        canvas.drawPath(vertical, _line(_alpha(color, .4), 1.1));
        canvas.drawCircle(
          Offset(shift + 6, side * 39),
          1.8,
          _fill(_alpha(color, .8)),
        );
        final horizontal = Path()
          ..moveTo(side * 24, shift)
          ..lineTo(side * 35, shift)
          ..lineTo(side * 40, shift + 5);
        canvas.drawPath(horizontal, _line(_alpha(_lavender, .45), 1.1));
        canvas.drawCircle(
          Offset(side * 40, shift + 5),
          1.8,
          _fill(_alpha(_lavender, .8)),
        );
      }
    }
    const chip = Rect.fromLTRB(-24, -24, 24, 24);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        chip.shift(const Offset(3, 4)),
        const Radius.circular(6),
      ),
      _fill(const Color(0xFF030A17)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(chip, const Radius.circular(6)),
      _gradient(chip, [
        const Color(0xFF6DADA9),
        const Color(0xFF193F4E),
        const Color(0xFF142A42),
      ]),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(chip, const Radius.circular(6)),
      _line(_alpha(color, .7), 1),
    );
    const core = Rect.fromLTRB(-15, -15, 15, 15);
    canvas.drawRRect(
      RRect.fromRectAndRadius(core, const Radius.circular(4)),
      _fill(const Color(0xFF0D2136)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(core, const Radius.circular(4)),
      _line(_alpha(color, .45), 1),
    );
    _glow(canvas, Offset.zero, 19, color, .3);
    final neural = Path()
      ..moveTo(-8, 5)
      ..lineTo(-3, -6)
      ..lineTo(4, 7)
      ..lineTo(9, -5);
    canvas.drawPath(neural, _line(color, 2));
    for (final p in [
      const Offset(-8, 5),
      const Offset(-3, -6),
      const Offset(4, 7),
      const Offset(9, -5),
    ]) {
      canvas.drawCircle(p, 2, _fill(const Color(0xFFD9FFF8)));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TopicPainter oldDelegate) =>
      category != oldDelegate.category;
}

class _HostPainter extends CustomPainter {
  const _HostPainter(this.role, this.active);
  final String role;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final key = role.toLowerCase();
    final analyst = key == 'analyst';
    final challenger = key == 'challenger';
    final color = analyst
        ? _gold
        : challenger
        ? _lavender
        : _cyan;
    const bounds = Rect.fromLTWH(3, 3, 94, 94);
    canvas.drawCircle(
      const Offset(50, 50),
      47,
      _gradient(bounds, [
        const Color(0xFF24304B),
        const Color(0xFF0B1429),
        const Color(0xFF171D37),
      ]),
    );
    canvas.drawCircle(
      const Offset(50, 50),
      46.5,
      _line(_alpha(color, active ? .9 : .32), active ? 1.7 : 1),
    );
    _glow(canvas, const Offset(49, 41), 42, color, active ? .28 : .16);
    canvas.save();
    canvas.clipPath(Path()..addOval(const Rect.fromLTWH(6, 6, 88, 88)));

    // The halo and latitudinal geometry give each synthetic presenter its own identity.
    canvas.drawOval(
      const Rect.fromLTWH(19, 18, 62, 65),
      _line(_alpha(color, .2), .6),
    );
    canvas.drawOval(
      const Rect.fromLTWH(11, 40, 78, 31),
      _line(_alpha(color, .13), .6),
    );
    for (var i = 0; i < 5; i++) {
      final y = 29.0 + i * 11;
      canvas.drawLine(
        Offset(13, y),
        Offset(87, y),
        _line(_alpha(color, .04), .6),
      );
    }
    if (analyst) {
      canvas.drawRect(
        const Rect.fromLTWH(24, 16, 52, 60),
        _line(_alpha(color, .13), .6),
      );
    } else if (challenger) {
      canvas.drawPath(
        Path()
          ..moveTo(18, 44)
          ..lineTo(50, 10)
          ..lineTo(82, 44)
          ..lineTo(50, 79)
          ..close(),
        _line(_alpha(color, .23), .7),
      );
    } else {
      canvas.drawArc(
        const Rect.fromLTWH(20, 9, 60, 61),
        -2.9,
        2.2,
        false,
        _line(_alpha(color, .55), 1.1),
      );
    }

    final shoulders = Path()
      ..moveTo(16, 100)
      ..cubicTo(16, 76, 30, 72, 40, 68)
      ..lineTo(60, 68)
      ..cubicTo(76, 72, 84, 81, 85, 100)
      ..close();
    canvas.drawPath(
      shoulders,
      _gradient(
        const Rect.fromLTWH(16, 67, 69, 33),
        [_alpha(color, .6), const Color(0xFF152A41), const Color(0xFF071321)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );
    canvas.drawPath(shoulders, _line(_alpha(color, .30), .9));
    final neck = Path()
      ..moveTo(42, 59)
      ..lineTo(59, 59)
      ..lineTo(61, 73)
      ..lineTo(51, 80)
      ..lineTo(39, 72)
      ..close();
    canvas.drawPath(
      neck,
      _gradient(
        const Rect.fromLTWH(39, 59, 22, 21),
        [_alpha(color, .6), const Color(0xFF14253A)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
    );

    // Faceted face shapes are stylized AI sculptures, rather than human likenesses.
    final face = Path()
      ..moveTo(analyst ? 37 : 34, 27)
      ..quadraticBezierTo(48, challenger ? 15 : 17, 63, 27)
      ..lineTo(68, 43)
      ..lineTo(64, 58)
      ..lineTo(53, 68)
      ..lineTo(43, 66)
      ..lineTo(34, 55)
      ..lineTo(32, 41)
      ..close();
    canvas.drawPath(
      face,
      _gradient(
        const Rect.fromLTWH(32, 18, 37, 50),
        [
          _alpha(color, .90),
          _alpha(color, .39),
          const Color(0xFF22334C),
          const Color(0xFF101E34),
        ],
        stops: const [0, .31, .70, 1],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );
    canvas.drawPath(face, _line(_alpha(color, .75), .8));
    final faceFacet = Path()
      ..moveTo(49, 23)
      ..lineTo(47, 44)
      ..lineTo(53, 53)
      ..lineTo(48, 64)
      ..lineTo(62, 57)
      ..lineTo(66, 43)
      ..close();
    canvas.drawPath(faceFacet, _fill(_alpha(_ink, .24)));
    canvas.drawPath(
      Path()
        ..moveTo(49, 29)
        ..lineTo(47, 47)
        ..lineTo(53, 51)
        ..lineTo(49, 53),
      _line(_alpha(color, .52), .7),
    );
    canvas.drawLine(
      const Offset(43, 58),
      const Offset(55, 59),
      _line(_alpha(color, .4), .8),
    );

    final eyeY = analyst ? 40.0 : 41.0;
    if (analyst) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(34, eyeY - 4, 29, 9),
          const Radius.circular(3),
        ),
        _fill(_alpha(_ink, .60)),
      );
      canvas.drawLine(
        Offset(36, eyeY),
        Offset(61, eyeY),
        _line(_alpha(color, .75), .8),
      );
      canvas.drawCircle(Offset(42, eyeY), 1.5, _fill(const Color(0xFFFFF1D8)));
      canvas.drawCircle(Offset(56, eyeY), 1.5, _fill(const Color(0xFFFFF1D8)));
    } else {
      canvas.drawLine(
        Offset(37, eyeY),
        Offset(43, eyeY + (challenger ? -1 : 0)),
        _line(color, 1.5),
      );
      canvas.drawLine(
        Offset(54, eyeY),
        Offset(61, eyeY - (challenger ? -1 : 0)),
        _line(color, 1.5),
      );
    }

    // Holographic side details and an illuminated collar.
    for (final x in [30.0, 70.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 2, 37, 4, 14),
          const Radius.circular(2),
        ),
        _fill(_alpha(color, .65)),
      );
      canvas.drawCircle(Offset(x, 44), 1.3, _fill(Colors.white));
    }
    final collar = Path()
      ..moveTo(28, 76)
      ..lineTo(42, 85)
      ..lineTo(51, 79)
      ..lineTo(60, 85)
      ..lineTo(73, 76);
    canvas.drawPath(collar, _line(_alpha(color, .75), .9));
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(27.0 + i * 3, 84),
        Offset(27.0 + i * 3, 88.0 + i * 2),
        _line(_alpha(color, .5), .7),
      );
    }
    canvas.drawCircle(const Offset(69, 86), 2.2, _fill(_alpha(color, .9)));
    canvas.restore();

    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6;
      final start = Offset(
        50 + math.cos(angle) * 43,
        50 + math.sin(angle) * 43,
      );
      final end = Offset(50 + math.cos(angle) * 45, 50 + math.sin(angle) * 45);
      canvas.drawLine(
        start,
        end,
        _line(_alpha(color, i % 3 == 0 ? .65 : .2), .6),
      );
    }
    if (active) {
      canvas.drawCircle(
        const Offset(82, 82),
        7,
        _fill(const Color(0xFF101C2D)),
      );
      canvas.drawCircle(const Offset(82, 82), 4, _fill(color));
      canvas.drawCircle(const Offset(82, 82), 6, _line(_alpha(color, .5), .8));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HostPainter oldDelegate) =>
      role != oldDelegate.role || active != oldDelegate.active;
}

class _HostRimPainter extends CustomPainter {
  const _HostRimPainter(this.active);
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    canvas.drawCircle(const Offset(50, 50), 41, _line(_alpha(_cyan, .45), .8));
    canvas.drawArc(
      const Rect.fromLTWH(6, 6, 88, 88),
      -2.5,
      1.0,
      false,
      _line(_alpha(_cyan, active ? .95 : .65), 1.8),
    );
    if (active) {
      canvas.drawCircle(
        const Offset(82, 82),
        7,
        _fill(const Color(0xFF101C2D)),
      );
      canvas.drawCircle(const Offset(82, 82), 4, _fill(_cyan));
      canvas.drawCircle(const Offset(82, 82), 6, _line(_alpha(_cyan, .5), .8));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HostRimPainter oldDelegate) =>
      active != oldDelegate.active;
}
