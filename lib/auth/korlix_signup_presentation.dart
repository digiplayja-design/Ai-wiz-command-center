import 'package:flutter/material.dart';

import 'korlix_october_welcome.dart';

/// Static circuit decoration: no motion, input interception, or spoken clutter.
class KorlixAuthBackground extends StatelessWidget {
  const KorlixAuthBackground({
    super.key,
    required this.signup,
    required this.child,
    this.date,
  });
  final bool signup;
  final Widget child;
  final DateTime? date;
  @override
  Widget build(BuildContext context) {
    if (!signup) return KorlixOctoberWelcome(date: date, child: child);
    return ColoredBox(
      color: Colors.white,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: CustomPaint(painter: _CircuitPainter()),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class KorlixSignupHeader extends StatelessWidget {
  const KorlixSignupHeader({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Image.asset(
            'assets/branding/korlix_mini_mark.png',
            height: 40,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'KORLIX AI',
              style: TextStyle(
                color: Color(0xFF102D3B),
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const Text(
        'YOUR NEXT CHAPTER',
        style: TextStyle(
          color: Color(0xFF006C80),
          fontSize: 12,
          letterSpacing: 2,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 8),
      Semantics(
        header: true,
        child: const Text(
          'Create your account',
          style: TextStyle(
            color: Color(0xFF102D3B),
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Choose your plan. Bring your ideas to life.',
        style: TextStyle(color: Color(0xFF405865), fontSize: 16, height: 1.5),
      ),
    ],
  );
}

class _CircuitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFFD9EEF2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final node = Paint()..color = const Color(0xFFA6D9E2);
    for (var i = 0; i < 7; i++) {
      final y = 60.0 + i * 150;
      canvas.drawPath(
        Path()
          ..moveTo(0, y)
          ..lineTo(25 + i * 5, y)
          ..lineTo(60 + i * 5, y + 35)
          ..lineTo(60 + i * 5, y + 90),
        line,
      );
      canvas.drawCircle(Offset(60 + i * 5, y + 90), 3, node);
      canvas.drawPath(
        Path()
          ..moveTo(size.width, y + 70)
          ..lineTo(size.width - 30, y + 70)
          ..lineTo(size.width - 65, y + 105)
          ..lineTo(size.width - 65, y + 160),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_CircuitPainter oldDelegate) => false;
}
