import 'package:flutter/material.dart';

Path _korlixCyberPath(Size size, double cut, [double inset = 0]) {
  final left = inset;
  final top = inset;
  final right = size.width - inset;
  final bottom = size.height - inset;
  final width = right - left;
  final height = bottom - top;
  final shortest = width < height ? width : height;
  final safeCut = cut.clamp(0.0, shortest / 3).toDouble();

  return Path()
    ..moveTo(left + safeCut, top)
    ..lineTo(right - safeCut, top)
    ..lineTo(right, top + safeCut)
    ..lineTo(right, bottom - safeCut)
    ..lineTo(right - safeCut, bottom)
    ..lineTo(left + safeCut, bottom)
    ..lineTo(left, bottom - safeCut)
    ..lineTo(left, top + safeCut)
    ..close();
}

class KorlixCyberPanelClipper extends CustomClipper<Path> {
  final double cut;

  const KorlixCyberPanelClipper({this.cut = 24});

  @override
  Path getClip(Size size) => _korlixCyberPath(size, cut);

  @override
  bool shouldReclip(covariant KorlixCyberPanelClipper oldClipper) {
    return oldClipper.cut != cut;
  }
}

class KorlixDeepCyberFrame extends StatelessWidget {
  final Widget child;
  final Color accent;
  final Color secondary;
  final Color fill;
  final EdgeInsetsGeometry padding;
  final double cut;
  final double depth;
  final double? height;

  const KorlixDeepCyberFrame({
    super.key,
    required this.child,
    required this.accent,
    required this.secondary,
    required this.fill,
    this.padding = const EdgeInsets.all(12),
    this.cut = 24,
    this.depth = 14,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _KorlixDeepCyberFramePainter(
          accent: accent,
          secondary: secondary,
          fill: fill,
          cut: cut,
          depth: depth,
        ),
        child: ClipPath(
          clipper: KorlixCyberPanelClipper(cut: cut),
          child: Container(
            height: height,
            width: double.infinity,
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _KorlixDeepCyberFramePainter extends CustomPainter {
  final Color accent;
  final Color secondary;
  final Color fill;
  final double cut;
  final double depth;

  const _KorlixDeepCyberFramePainter({
    required this.accent,
    required this.secondary,
    required this.fill,
    required this.cut,
    required this.depth,
  });

  void _stroke(
    Canvas canvas,
    Path path,
    Color color,
    double width, {
    double alpha = 1,
    double blur = 0,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.bevel
      ..strokeCap = StrokeCap.square
      ..color = color.withValues(alpha: alpha);

    if (blur > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    }

    canvas.drawPath(path, paint);
  }

  void _glowLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Color color, {
    double width = 2,
    double blur = 7,
  }) {
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width + 2
      ..strokeCap = StrokeCap.square
      ..color = color.withValues(alpha: 0.28)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

    final crisp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.square
      ..color = color.withValues(alpha: 0.88);

    canvas.drawLine(a, b, glow);
    canvas.drawLine(a, b, crisp);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final rect = Offset.zero & size;
    final outer = _korlixCyberPath(size, cut);
    final mid = _korlixCyberPath(size, cut * 0.82, 5);
    final inner = _korlixCyberPath(size, cut * 0.62, 13);

    final shadow = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black.withValues(alpha: 0.74)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, depth);
    canvas.drawPath(outer.shift(Offset(0, depth * 0.42)), shadow);

    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(fill, accent, 0.20)!,
          fill,
          Color.lerp(fill, secondary, 0.18)!,
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(rect);
    canvas.drawPath(outer, base);

    final bevelTop = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeJoin = StrokeJoin.bevel
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.30),
          accent.withValues(alpha: 0.36),
          secondary.withValues(alpha: 0.30),
        ],
      ).createShader(rect);
    canvas.drawPath(mid, bevelTop);

    final darkBevel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeJoin = StrokeJoin.bevel
      ..color = Colors.black.withValues(alpha: 0.34);
    canvas.drawPath(inner, darkBevel);

    _stroke(canvas, outer, accent, 2.2, alpha: 0.82, blur: 8);
    _stroke(canvas, outer, secondary, 1.4, alpha: 0.42, blur: 15);
    _stroke(canvas, mid, Colors.white, 0.9, alpha: 0.20);
    _stroke(canvas, inner, accent, 0.9, alpha: 0.28);

    final w = size.width;
    final h = size.height;

    _glowLine(
      canvas,
      Offset(w * 0.08, h * 0.08),
      Offset(w * 0.29, h * 0.08),
      accent,
    );
    _glowLine(
      canvas,
      Offset(w * 0.71, h * 0.08),
      Offset(w * 0.92, h * 0.08),
      secondary,
    );
    _glowLine(
      canvas,
      Offset(w * 0.09, h * 0.92),
      Offset(w * 0.31, h * 0.92),
      accent,
      width: 1.7,
    );
    _glowLine(
      canvas,
      Offset(w * 0.69, h * 0.92),
      Offset(w * 0.91, h * 0.92),
      secondary,
      width: 1.7,
    );
  }

  @override
  bool shouldRepaint(covariant _KorlixDeepCyberFramePainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.secondary != secondary ||
        oldDelegate.fill != fill ||
        oldDelegate.cut != cut ||
        oldDelegate.depth != depth;
  }
}

class KorlixInputFieldFrame extends StatelessWidget {
  final Widget child;
  final Color accent;
  final Color secondary;
  final Color fill;

  const KorlixInputFieldFrame({
    super.key,
    required this.child,
    required this.accent,
    required this.secondary,
    required this.fill,
  });

  @override
  Widget build(BuildContext context) {
    return KorlixDeepCyberFrame(
      accent: accent.withValues(alpha: 0.85),
      secondary: secondary.withValues(alpha: 0.68),
      fill: Color.lerp(fill, Colors.black, 0.36)!,
      cut: 16,
      depth: 7,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      child: child,
    );
  }
}

class KorlixDeepCyberButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subLabel;
  final Color accent;
  final Color secondary;
  final Color fill;
  final bool active;
  final bool vertical;
  final VoidCallback? onTap;

  const KorlixDeepCyberButton({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.secondary,
    required this.fill,
    this.subLabel,
    this.active = false,
    this.vertical = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final effectiveAccent = disabled ? Colors.white38 : accent;
    final effectiveFill = active
        ? Color.lerp(fill, effectiveAccent, 0.18)!
        : Color.lerp(fill, Colors.black, 0.20)!;

    final content = vertical
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: effectiveAccent, size: 25),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: effectiveAccent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                ),
              ),
              if (subLabel != null)
                Text(
                  subLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFFA9C6CF).withValues(alpha: 0.78),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: effectiveAccent, size: 21),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: disabled ? Colors.white38 : const Color(0xFFE4EBEE),
                    fontSize: 14,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          );

    return Opacity(
      opacity: disabled ? 0.54 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: KorlixDeepCyberFrame(
          accent: effectiveAccent,
          secondary: secondary,
          fill: effectiveFill,
          cut: vertical ? 16 : 14,
          depth: active ? 13 : 10,
          padding: EdgeInsets.symmetric(
            horizontal: vertical ? 8 : 12,
            vertical: vertical ? 8 : 10,
          ),
          child: SizedBox(height: vertical ? 58 : 38, child: content),
        ),
      ),
    );
  }
}

class KorlixGlowDot extends StatelessWidget {
  final Color color;

  const KorlixGlowDot({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.75),
            blurRadius: 12,
            spreadRadius: 1.4,
          ),
        ],
      ),
    );
  }
}

class KorlixThemeDot extends StatelessWidget {
  final bool selected;
  final Color colorA;
  final Color colorB;
  final VoidCallback onTap;

  const KorlixThemeDot({
    super.key,
    required this.selected,
    required this.colorA,
    required this.colorB,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.14 : 1.0,
        duration: const Duration(milliseconds: 160),
        child: Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [colorA, colorB]),
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colorA.withValues(alpha: selected ? 0.45 : 0.18),
                blurRadius: selected ? 16 : 8,
                spreadRadius: selected ? 1 : 0,
              ),
            ],
          ),
          child: selected
              ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
