import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Decorative, code-drawn artwork. Prompt starters are not generated previews.
class ImagineArtwork extends StatelessWidget {
  const ImagineArtwork({super.key, this.variant = 3});
  final int variant;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      painter: _ImaginePainter(variant),
      child: const SizedBox.expand(),
    ),
  );
}

class _ImaginePainter extends CustomPainter {
  _ImaginePainter(this.variant);
  final int variant;
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff191a43), Color(0xff080f24)],
        ).createShader(bounds),
    );
    final scale = math.min(size.width / 300, size.height / 240);
    canvas.translate(
      (size.width - 300 * scale) / 2,
      (size.height - 240 * scale) / 2,
    );
    canvas.scale(scale);
    final palette = variant % 4 == 0
        ? [const Color(0xfff1ba85), const Color(0xff453751)]
        : variant % 4 == 1
        ? [const Color(0xff55c6d4), const Color(0xff181941)]
        : variant % 4 == 2
        ? [const Color(0xffee988e), const Color(0xff432755)]
        : [const Color(0xff87a9ff), const Color(0xff191a43)];
    final p = Paint();
    p.shader = RadialGradient(
      colors: [
        palette[0].withValues(alpha: .5),
        palette[1].withValues(alpha: 0),
      ],
    ).createShader(const Rect.fromLTWH(15, -70, 290, 290));
    canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 240), p);
    p.shader = null;
    p
      ..color = Colors.white.withValues(alpha: .05)
      ..strokeWidth = .6;
    for (var x = -200.0; x < 500; x += 35) {
      canvas.drawLine(Offset(150, 75), Offset(x, 240), p);
    }
    for (var y = 150.0; y < 240; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(300, y), p);
    }
    p
      ..color = Colors.black.withValues(alpha: .55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawOval(const Rect.fromLTWH(57, 190, 195, 27), p);
    p.maskFilter = null;
    if (variant % 4 == 1) {
      p.shader = RadialGradient(
        colors: [
          const Color(0xffffd5af),
          const Color(0xfff4aeaa),
          const Color(0xffbe80dd),
        ],
      ).createShader(const Rect.fromLTWH(167, 25, 73, 73));
      canvas.drawCircle(const Offset(203, 62), 37, p);
      p.shader = null;
      for (var layer = 0; layer < 3; layer++) {
        final path = Path()
          ..moveTo(-10, 210)
          ..lineTo(45, 110 + layer * 25)
          ..lineTo(83, 150 + layer * 16)
          ..lineTo(145, 72 + layer * 37)
          ..lineTo(220, 166 + layer * 12)
          ..lineTo(269, 113 + layer * 20)
          ..lineTo(325, 190)
          ..lineTo(310, 250)
          ..lineTo(0, 250)
          ..close();
        p.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette[0].withValues(alpha: .65 - layer * .13),
            palette[1],
          ],
        ).createShader(const Rect.fromLTWH(0, 70, 300, 170));
        canvas.drawPath(path, p);
      }
    } else if (variant % 4 == 0) {
      p.shader = const LinearGradient(
        colors: [Color(0xffb7a79e), Color(0xff454457)],
      ).createShader(const Rect.fromLTWH(75, 163, 154, 65));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(75, 166, 154, 70),
          const Radius.circular(8),
        ),
        p,
      );
      p.shader = const LinearGradient(
        colors: [Color(0xfffde1bc), Color(0xffa87344), Color(0xff402d33)],
      ).createShader(const Rect.fromLTWH(112, 67, 77, 113));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(112, 70, 77, 117),
          const Radius.circular(16),
        ),
        p,
      );
      p.shader = const LinearGradient(
        colors: [Color(0xffe9d7b6), Color(0xff474346)],
      ).createShader(const Rect.fromLTWH(128, 48, 46, 30));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(128, 47, 46, 30),
          const Radius.circular(5),
        ),
        p,
      );
      p
        ..shader = null
        ..color = const Color(0xfff0d1ad);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(123, 119, 55, 35),
          const Radius.circular(3),
        ),
        p,
      );
      p
        ..color = Colors.white.withValues(alpha: .36)
        ..strokeWidth = 3;
      canvas.drawLine(const Offset(123, 87), const Offset(123, 109), p);
    } else if (variant % 4 == 2) {
      canvas.save();
      canvas.translate(145, 118);
      canvas.rotate(-.12);
      p.shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xffffe4d2), Color(0xffd79798)],
      ).createShader(const Rect.fromLTWH(-66, -91, 132, 182));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-66, -91, 132, 182),
          const Radius.circular(8),
        ),
        p,
      );
      p
        ..shader = null
        ..color = const Color(0xff8a5172);
      canvas.drawCircle(const Offset(0, -20), 39, p);
      p.color = const Color(0xfff3b783);
      canvas.drawCircle(const Offset(14, -29), 32, p);
      p
        ..color = const Color(0xff512e4e)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(-35, 45), const Offset(36, 45), p);
      canvas.drawLine(const Offset(-21, 58), const Offset(23, 58), p);
      canvas.restore();
    } else {
      canvas.save();
      canvas.translate(150, 151);
      canvas.rotate(-.25);
      p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20
        ..shader = const SweepGradient(
          colors: [
            Color(0xff6b51c8),
            Color(0xffd5edff),
            Color(0xff66d9e5),
            Color(0xff6b51c8),
          ],
        ).createShader(const Rect.fromLTWH(-88, -33, 176, 66));
      canvas.drawOval(const Rect.fromLTWH(-88, -33, 176, 66), p);
      canvas.restore();
      p
        ..style = PaintingStyle.fill
        ..shader = const RadialGradient(
          center: Alignment(-.45, -.55),
          colors: [
            Color(0xffeff8ff),
            Color(0xff97dfe6),
            Color(0xff8480d9),
            Color(0xff303258),
          ],
          stops: [0, .23, .65, 1],
        ).createShader(const Rect.fromLTWH(96, 36, 110, 110));
      canvas.drawCircle(const Offset(151, 91), 55, p);
      p
        ..shader = null
        ..color = Colors.white.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawArc(
        const Rect.fromLTWH(107, 46, 88, 87),
        math.pi,
        math.pi * .53,
        false,
        p,
      );
      p.style = PaintingStyle.fill;
    }
    p
      ..shader = null
      ..color = Colors.white.withValues(alpha: .5);
    for (final o in [
      const Offset(34, 43),
      const Offset(265, 81),
      const Offset(241, 33),
    ]) {
      canvas.drawCircle(o, 1.5, p);
    }
    canvas.restore();
    if (size.shortestSide < 65) {
      final bezel = RRect.fromRectAndRadius(
        bounds.deflate(.8),
        const Radius.circular(10),
      );
      canvas.drawRRect(
        bezel,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffd5f6ff), Color(0xff6376bc), Color(0xff8b63c3)],
          ).createShader(bounds),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ImaginePainter old) => old.variant != variant;
}
