import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'magic_theme.dart';

class MagicOrbits extends StatefulWidget {
  const MagicOrbits({
    super.key,
    this.style = 'Cosmic orbits',
    this.label = 'Making a little magic',
    this.detail = 'Your finished photo will appear here.',
  });
  final String style, label, detail;
  @override
  State<MagicOrbits> createState() => _MagicOrbitsState();
}

class _MagicOrbitsState extends State<MagicOrbits>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  bool _paused = false;
  Offset? _touch;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    if (_paused || MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
    } else {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: magicNavy,
    child: Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onPanUpdate: (d) => setState(() => _touch = d.localPosition),
              onPanEnd: (_) => setState(() => _touch = null),
              onTapDown: (d) => setState(() => _touch = d.localPosition),
              onTapUp: (_) => setState(() => _touch = null),
              child: SizedBox(
                width: 320,
                height: 330,
                child: AnimatedBuilder(
                  animation: _motion,
                  builder: (context, _) => CustomPaint(
                    painter: OrbitPainter(_motion.value, widget.style, _touch),
                    child: const Center(child: MagicMark(size: 112)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                widget.detail,
                textAlign: TextAlign.center,
                style: const TextStyle(color: magicMuted, height: 1.5),
              ),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: () {
                setState(() => _paused = !_paused);
                _sync();
              },
              icon: Icon(
                _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              ),
              label: Text(_paused ? 'Resume animation' : 'Pause animation'),
            ),
          ],
        ),
      ),
    ),
  );
}

class OrbitPainter extends CustomPainter {
  OrbitPainter(this.progress, this.style, [this.touch]);
  final double progress;
  final String style;
  final Offset? touch;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2),
        t = progress * math.pi * 2;
    for (var i = 0; i < 4; i++) {
      final color = i.isEven ? magicOrange : magicBlue;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(i * math.pi / 3 + (i.isEven ? t : -t) * .16);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: 244 + i * 13,
        height: style == 'Portal' ? 244 + i * 13 : 92 + i * 24,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..color = color.withValues(alpha: .26)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
      final angle = (i.isEven ? t : -t) + i * 1.8,
          p = Offset(
            math.cos(angle) * rect.width / 2,
            math.sin(angle) * rect.height / 2,
          );
      canvas.drawCircle(
        p,
        9,
        Paint()
          ..color = color.withValues(alpha: .35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(p, 3.5, Paint()..color = color);
      canvas.restore();
    }
    for (var i = 0; i < (style == 'Stardust' ? 55 : 26); i++) {
      final angle = i * 2.399 + t * (i.isEven ? 0.2 : -0.13),
          radius = 80 + (i * 31 % 82).toDouble();
      final p = c + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      canvas.drawCircle(
        p,
        i % 3 == 0 ? 1.8 : 1,
        Paint()
          ..color = (i.isEven ? magicBlue : magicOrange).withValues(
            alpha: .2 + .6 * (.5 + .5 * math.sin(t + i)),
          ),
      );
    }
    if (touch != null) {
      canvas.drawCircle(
        touch!,
        24,
        Paint()
          ..color = magicBlue.withValues(alpha: .25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4 + t;
        canvas.drawCircle(
          touch! + Offset(math.cos(a) * 25, math.sin(a) * 25),
          2,
          Paint()..color = magicOrange,
        );
      }
    }
  }

  @override
  bool shouldRepaint(OrbitPainter old) =>
      old.progress != progress || old.style != style || old.touch != touch;
}
