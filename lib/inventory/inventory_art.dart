import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Vector warehouse sculpture; decorative, never represents actual stock.
class InventorySculpture extends StatelessWidget {
  const InventorySculpture({super.key, this.size = 220});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _Sculpture(Theme.of(context).brightness == Brightness.dark),
      ),
    ),
  );
}

class _Sculpture extends CustomPainter {
  _Sculpture(this.dark);
  final bool dark;
  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 240, s.height / 240);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFA4EBD9).withValues(alpha: .42),
          Colors.transparent,
        ],
      ).createShader(const Rect.fromLTWH(5, 5, 230, 230));
    c.drawCircle(const Offset(120, 120), 115, glow);
    c.drawOval(
      const Rect.fromLTWH(36, 178, 172, 34),
      Paint()
        ..color = Colors.black.withValues(alpha: .12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    void poly(List<Offset> points, Color color) {
      final p = Path()..addPolygon(points, true);
      c.drawPath(p, Paint()..color = color);
      c.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: .35),
      );
    }

    void cube(
      double x,
      double y,
      double w,
      double h,
      Color top,
      Color left,
      Color right,
    ) {
      final dx = w / 2, dy = w / 4;
      poly([
        Offset(x, y),
        Offset(x + dx, y - dy),
        Offset(x + w, y),
        Offset(x + dx, y + dy),
      ], top);
      poly([
        Offset(x, y),
        Offset(x + dx, y + dy),
        Offset(x + dx, y + dy + h),
        Offset(x, y + h),
      ], left);
      poly([
        Offset(x + dx, y + dy),
        Offset(x + w, y),
        Offset(x + w, y + h),
        Offset(x + dx, y + dy + h),
      ], right);
    }

    cube(
      37,
      163,
      168,
      12,
      const Color(0xFFC9D5E9),
      const Color(0xFF899ABA),
      const Color(0xFF566786),
    );
    cube(
      46,
      113,
      80,
      54,
      const Color(0xFFF4EDFF),
      const Color(0xFFC9B3EC),
      const Color(0xFF947ACA),
    );
    cube(
      124,
      114,
      68,
      47,
      const Color(0xFFD9FFF0),
      const Color(0xFF8CD5BE),
      const Color(0xFF3C9E87),
    );
    cube(
      83,
      63,
      80,
      54,
      const Color(0xFFE5F4FF),
      const Color(0xFFAACDE6),
      const Color(0xFF6C96BC),
    );
    for (var i = 0; i < 9; i++) {
      c.drawLine(
        Offset(103 + i * 2.5, 83 + i * 1.25),
        Offset(103 + i * 2.5, 97 + i * 1.25),
        Paint()
          ..strokeWidth = i % 3 == 0 ? 2 : 1
          ..color = const Color(0xFF395876),
      );
    }
    final badge = Paint()
      ..color = dark ? const Color(0xFF132C31) : Colors.white;
    c.drawCircle(const Offset(177, 56), 25, badge);
    c.drawCircle(
      const Offset(177, 56),
      25,
      Paint()
        ..color = const Color(0xFF71D5B5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    c.drawPath(
      Path()
        ..moveTo(166, 56)
        ..lineTo(174, 64)
        ..lineTo(188, 48),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF289B7D),
    );
    for (var i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      c.drawCircle(
        Offset(120 + 105 * math.cos(angle), 119 + 91 * math.sin(angle)),
        2.8,
        Paint()..color = const Color(0xFF9D98D0),
      );
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_Sculpture old) => old.dark != dark;
}
