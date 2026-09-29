import 'package:flutter/material.dart';

/// Native vector artwork stays sharp in a home tile and the studio hero.
class EmailArtwork extends StatelessWidget {
  const EmailArtwork({super.key});
  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: CustomPaint(painter: _MailPainter()));
}

class _MailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 160, size.height / 160);
    final glow = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x555A7EFF), Color(0x00445CFF)],
      ).createShader(const Rect.fromLTWH(0, 0, 160, 160));
    canvas.drawCircle(const Offset(80, 90), 79, glow);
    canvas.translate(8, 12);
    canvas.rotate(-.09);
    final shadow = RRect.fromRectAndRadius(
      const Rect.fromLTWH(24, 61, 121, 84),
      const Radius.circular(17),
    );
    canvas.drawRRect(
      shadow,
      Paint()
        ..color = const Color(0x45000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(19, 47, 124, 88),
        const Radius.circular(16),
      ),
      Paint()..color = const Color(0xFF30429A),
    );
    final paper = RRect.fromRectAndRadius(
      const Rect.fromLTWH(32, 20, 95, 104),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      paper,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFB9D9FA)],
        ).createShader(paper.outerRect),
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(47, 39 + i * 13, i == 2 ? 32 : 62, 5),
          const Radius.circular(3),
        ),
        Paint()
          ..color = i == 0 ? const Color(0xFF677BCE) : const Color(0xFFA7B9D9),
      );
    }
    final front = Path()
      ..moveTo(19, 61)
      ..lineTo(78, 99)
      ..quadraticBezierTo(82, 102, 88, 98)
      ..lineTo(143, 61)
      ..lineTo(143, 121)
      ..quadraticBezierTo(143, 135, 129, 135)
      ..lineTo(33, 135)
      ..quadraticBezierTo(19, 135, 19, 121)
      ..close();
    canvas.drawPath(
      front,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF91C5FF), Color(0xFF7365EB), Color(0xFF3845A5)],
        ).createShader(const Rect.fromLTWH(19, 61, 124, 74)),
    );
    canvas.drawPath(
      Path()
        ..moveTo(21, 128)
        ..lineTo(63, 96)
        ..moveTo(141, 128)
        ..lineTo(100, 96),
      Paint()
        ..color = const Color(0x558BCFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawPath(
      Path()
        ..moveTo(21, 63)
        ..lineTo(80, 100)
        ..lineTo(142, 62),
      Paint()
        ..color = const Color(0xCCDAE8FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    final star = Path()
      ..moveTo(136, 15)
      ..quadraticBezierTo(138, 29, 151, 31)
      ..quadraticBezierTo(138, 34, 136, 48)
      ..quadraticBezierTo(133, 34, 121, 31)
      ..quadraticBezierTo(133, 29, 136, 15)
      ..close();
    canvas.drawPath(star, Paint()..color = const Color(0xFFA8F9EE));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MailPainter oldDelegate) => false;
}
