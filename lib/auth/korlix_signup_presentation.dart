import 'package:flutter/material.dart';

import '../theme/korlix_theme.dart';
import 'korlix_october_welcome.dart';

/// A static, year-round color treatment for registration. Form controls keep
/// their solid theme surfaces; decoration never handles taps or hides labels.
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
    final light = korlixSkinOf(context).isLight;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light
              ? const [Color(0xFFE4ECFF), Color(0xFFF2DFFF), Color(0xFFD8F6F4)]
              : const [Color(0xFF172550), Color(0xFF33204F), Color(0xFF103C4A)],
        ),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: CustomPaint(painter: _SignupColorPainter(light: light)),
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF51319B), Color(0xFF2455A3), Color(0xFF136179)],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFAA9AEF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Image.asset('assets/branding/korlix_mini_mark.png', height: 32,
              excludeFromSemantics: true),
            const SizedBox(width: 10),
            const Flexible(
              child: Text('KORLIX AI', style: TextStyle(color: Colors.white,
                fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Create your free account',
          style: TextStyle(color: Colors.white, fontSize: 25, height: 1.2,
            fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Start with Basic. Upgrade when you need more.',
          style: TextStyle(color: Color(0xFFF0F0FF), height: 1.4)),
        const SizedBox(height: 16),
        const ExcludeSemantics(
          child: Row(children: [
            _ColorMark(Color(0xFFFFA7DD)),
            SizedBox(width: 6),
            _ColorMark(Color(0xFFACA8FF)),
            SizedBox(width: 6),
            _ColorMark(Color(0xFF8CE5EE)),
          ]),
        ),
      ],
    ),
  );
}

class _ColorMark extends StatelessWidget {
  const _ColorMark(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(height: 4, decoration: BoxDecoration(
      color: color, borderRadius: BorderRadius.circular(4))),
  );
}

class _SignupColorPainter extends CustomPainter {
  const _SignupColorPainter({required this.light});
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFF7588FF),
      const Color(0xFFE877C2),
      const Color(0xFF38D3CB),
    ];
    final centers = [
      Offset(size.width * .08, size.height * .10),
      Offset(size.width * .95, size.height * .46),
      Offset(size.width * .12, size.height * .92),
    ];
    for (var i = 0; i < colors.length; i++) {
      canvas.drawCircle(centers[i], size.shortestSide * .34,
        Paint()..color = colors[i].withValues(alpha: light ? .13 : .10));
      canvas.drawCircle(centers[i], size.shortestSide * .39,
        Paint()..color = colors[i].withValues(alpha: .24)
          ..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_SignupColorPainter oldDelegate) => oldDelegate.light != light;
}
