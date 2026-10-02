import 'package:flutter/material.dart';

/// A code-drawn photo tile, not a generated or edited photo preview.
class PictureArtwork extends StatelessWidget {
  const PictureArtwork({super.key});

  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: CustomPaint(painter: _PicturePainter()));
}

class _PicturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / 160, size.height / 160);
    final tile = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 160, 160),
      const Radius.circular(36),
    );
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF713DE8), Color(0xFFDF459B), Color(0xFFFA9474)],
        ).createShader(tile.outerRect),
    );
    canvas.save();
    canvas.translate(78, 88);
    canvas.rotate(-.12);
    final photo = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-50, -47, 100, 96),
      const Radius.circular(13),
    );
    canvas.drawRRect(photo, Paint()..color = const Color(0xFFFAF5FF));
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-42, -39, 84, 70),
        const Radius.circular(8),
      ),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-42, -39, 84, 70),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF92E0EB), Color(0xFFD0F3FC)],
        ).createShader(const Rect.fromLTWH(-42, -39, 84, 70)),
    );
    canvas.drawCircle(
      const Offset(19, -18),
      11,
      Paint()..color = const Color(0xFFFFCF78),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-48, 36)
        ..lineTo(-15, -9)
        ..lineTo(16, 36)
        ..close(),
      Paint()..color = const Color(0xFF548FC9),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-11, 36)
        ..lineTo(24, 0)
        ..lineTo(56, 36)
        ..close(),
      Paint()..color = const Color(0xFF3CB6AC),
    );
    canvas.restore();
    canvas.drawPath(
      Path()
        ..moveTo(122, 15)
        ..quadraticBezierTo(125, 33, 143, 37)
        ..quadraticBezierTo(125, 40, 122, 59)
        ..quadraticBezierTo(118, 40, 101, 37)
        ..quadraticBezierTo(118, 33, 122, 15)
        ..close(),
      Paint()..color = const Color(0xFFFFF3C6),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PicturePainter oldDelegate) => false;
}
