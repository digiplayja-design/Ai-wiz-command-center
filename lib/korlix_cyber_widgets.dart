import 'package:flutter/material.dart';

const String kKorlixCyberWidgetsVersion = 'contour_v2_deep_hardware';

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

Path _korlixPlatePath(Rect rect, double cut) {
  final safeCut = cut.clamp(0.0, rect.shortestSide / 3).toDouble();

  return Path()
    ..moveTo(rect.left + safeCut, rect.top)
    ..lineTo(rect.right - safeCut, rect.top)
    ..lineTo(rect.right, rect.top + safeCut)
    ..lineTo(rect.right, rect.bottom - safeCut)
    ..lineTo(rect.right - safeCut, rect.bottom)
    ..lineTo(rect.left + safeCut, rect.bottom)
    ..lineTo(rect.left, rect.bottom - safeCut)
    ..lineTo(rect.left, rect.top + safeCut)
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

  void _fill(
    Canvas canvas,
    Path path,
    Color color, {
    double alpha = 1,
    double blur = 0,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: alpha);

    if (blur > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    }

    canvas.drawPath(path, paint);
  }

  void _glowLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color, {
    double width = 2,
    double blur = 7,
    double alpha = 0.88,
  }) {
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width + 3
      ..strokeCap = StrokeCap.square
      ..color = color.withValues(alpha: 0.24)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

    final crisp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.square
      ..color = color.withValues(alpha: alpha);

    canvas.drawLine(start, end, glow);
    canvas.drawLine(start, end, crisp);
  }

  void _drawInsetContour(Canvas canvas, Size size, Color color, double inset) {
    final path = _korlixCyberPath(size, cut * 0.58, inset);
    _stroke(canvas, path, Colors.black, 4.0, alpha: 0.36);
    _stroke(canvas, path, color, 1.05, alpha: 0.42);
    _stroke(canvas, path, Colors.white, 0.55, alpha: 0.16);
  }

  void _drawArmorPlate({
    required Canvas canvas,
    required Rect rect,
    required Color color,
    required double plateCut,
    required bool glow,
  }) {
    final path = _korlixPlatePath(rect, plateCut);

    final shadow = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black.withValues(alpha: 0.56)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawPath(path.shift(const Offset(0, 3)), shadow);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(fill, Colors.white, 0.16)!,
          Color.lerp(fill, Colors.black, 0.25)!,
          Color.lerp(fill, color, 0.18)!,
        ],
      ).createShader(rect);

    canvas.drawPath(path, fillPaint);

    _stroke(canvas, path, Colors.white, 0.75, alpha: 0.28);
    _stroke(canvas, path, Colors.black, 2.3, alpha: 0.42);
    _stroke(
      canvas,
      path,
      color,
      1.25,
      alpha: glow ? 0.62 : 0.36,
      blur: glow ? 5 : 0,
    );
  }

  void _drawRailCluster({
    required Canvas canvas,
    required double x,
    required double y,
    required double width,
    required Color color,
    bool reverse = false,
  }) {
    for (var i = 0; i < 5; i++) {
      final offset = i * 7.0;
      final startX = reverse ? x + width - offset - 18 : x + offset;
      final endX = reverse ? startX + 14 : startX + 14;

      _glowLine(
        canvas,
        Offset(startX, y + i * 1.5),
        Offset(endX, y + i * 1.5),
        color,
        width: 1.0,
        blur: 3.5,
        alpha: 0.70,
      );
    }
  }

  void _drawSideVents({
    required Canvas canvas,
    required Size size,
    required bool right,
    required Color color,
  }) {
    final double w = size.width;
    final double h = size.height;
    final double x = right ? w - 27.0 : 17.0;
    final double y0 = h * 0.34;
    final double y1 = h * 0.66;
    final int count = h > 130.0 ? 11 : 5;

    final double plateLeft = right ? w - 34.0 : 8.0;
    final Rect plateRect = Rect.fromLTWH(plateLeft, h * 0.30, 25.0, h * 0.40);

    final path = _korlixPlatePath(plateRect, 8.0);
    _fill(canvas, path, Colors.black, alpha: 0.34);
    _stroke(canvas, path, color, 1.0, alpha: 0.35, blur: 4.0);

    for (var i = 0; i < count; i++) {
      final double t = count == 1 ? 0.0 : i / (count - 1);
      final double y = y0 + (y1 - y0) * t;

      _glowLine(
        canvas,
        Offset(x, y),
        Offset(x + 9.0, y + 3.0),
        color,
        width: 0.75,
        blur: 2.0,
        alpha: 0.55,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final rect = Offset.zero & size;
    final w = size.width;
    final h = size.height;

    final outer = _korlixCyberPath(size, cut);
    final outerInset = _korlixCyberPath(size, cut * 0.86, 5);
    final bevelInset = _korlixCyberPath(size, cut * 0.72, 11);
    final darkInset = _korlixCyberPath(size, cut * 0.62, 18);
    final inner = _korlixCyberPath(size, cut * 0.48, 25);

    canvas.drawShadow(
      outer,
      Colors.black.withValues(alpha: 0.92),
      depth * 0.80,
      true,
    );

    final softOuterShadow = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black.withValues(alpha: 0.76)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, depth + 6);
    canvas.drawPath(outer.shift(Offset(0, depth * 0.42)), softOuterShadow);

    final glowHalo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeJoin = StrokeJoin.bevel
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          accent.withValues(alpha: 0.30),
          secondary.withValues(alpha: 0.18),
          secondary.withValues(alpha: 0.34),
        ],
      ).createShader(rect)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawPath(outer, glowHalo);

    final basePaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(fill, Colors.white, 0.17)!,
          fill,
          Color.lerp(fill, Colors.black, 0.36)!,
          Color.lerp(fill, secondary, 0.17)!,
        ],
        stops: const [0.0, 0.34, 0.66, 1.0],
      ).createShader(rect);
    canvas.drawPath(outer, basePaint);

    final topBevel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeJoin = StrokeJoin.bevel
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.44),
          accent.withValues(alpha: 0.34),
          Colors.white.withValues(alpha: 0.10),
          secondary.withValues(alpha: 0.34),
        ],
      ).createShader(rect);
    canvas.drawPath(outerInset, topBevel);

    final bottomBevel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeJoin = StrokeJoin.bevel
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.black.withValues(alpha: 0.10),
          Colors.black.withValues(alpha: 0.34),
          Colors.black.withValues(alpha: 0.58),
        ],
      ).createShader(rect);
    canvas.drawPath(bevelInset, bottomBevel);

    final innerFill = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(fill, Colors.white, 0.05)!,
          Color.lerp(fill, Colors.black, 0.46)!,
          Color.lerp(fill, secondary, 0.09)!,
        ],
      ).createShader(rect);
    canvas.drawPath(darkInset, innerFill);

    _stroke(canvas, outer, Colors.black, 4.4, alpha: 0.54);
    _stroke(canvas, outer, accent, 2.6, alpha: 0.74, blur: 5);
    _stroke(canvas, outer, secondary, 1.7, alpha: 0.54, blur: 8);
    _stroke(canvas, outerInset, Colors.white, 1.3, alpha: 0.32);
    _stroke(canvas, bevelInset, Colors.black, 2.4, alpha: 0.58);
    _stroke(canvas, darkInset, Colors.white, 0.9, alpha: 0.18);
    _stroke(canvas, inner, Colors.black, 4.5, alpha: 0.48);
    _stroke(canvas, inner, accent, 0.85, alpha: 0.26);

    _drawInsetContour(canvas, size, accent, 32);
    if (w > 180 && h > 78) {
      _drawInsetContour(canvas, size, secondary, 42);
    }

    final topPlateWidth = w * 0.28;
    final topPlateHeight = (h * 0.10).clamp(11.0, 22.0).toDouble();
    final bottomPlateHeight = (h * 0.09).clamp(10.0, 20.0).toDouble();

    if (w > 150 && h > 70) {
      _drawArmorPlate(
        canvas: canvas,
        rect: Rect.fromLTWH(w * 0.36, 2, topPlateWidth, topPlateHeight),
        color: Color.lerp(accent, secondary, 0.45)!,
        plateCut: 7,
        glow: true,
      );

      _drawArmorPlate(
        canvas: canvas,
        rect: Rect.fromLTWH(
          w * 0.38,
          h - bottomPlateHeight - 2,
          w * 0.24,
          bottomPlateHeight,
        ),
        color: Color.lerp(accent, secondary, 0.55)!,
        plateCut: 7,
        glow: true,
      );

      _drawArmorPlate(
        canvas: canvas,
        rect: Rect.fromLTWH(7.0, 9.0, w * 0.17, topPlateHeight * 0.92),
        color: accent,
        plateCut: 7,
        glow: false,
      );

      _drawArmorPlate(
        canvas: canvas,
        rect: Rect.fromLTWH(
          w - (w * 0.17) - 7,
          9,
          w * 0.17,
          topPlateHeight * 0.92,
        ),
        color: secondary,
        plateCut: 7,
        glow: false,
      );
    }

    if (h > 82) {
      _drawSideVents(canvas: canvas, size: size, right: false, color: accent);
      _drawSideVents(canvas: canvas, size: size, right: true, color: secondary);
    }

    _glowLine(
      canvas,
      Offset(w * 0.08, h * 0.08),
      Offset(w * 0.30, h * 0.08),
      accent,
      width: 2.0,
    );
    _glowLine(
      canvas,
      Offset(w * 0.70, h * 0.08),
      Offset(w * 0.92, h * 0.08),
      secondary,
      width: 2.0,
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

    if (w > 210) {
      _drawRailCluster(
        canvas: canvas,
        x: w * 0.42,
        y: h * 0.055,
        width: w * 0.16,
        color: accent,
      );
      _drawRailCluster(
        canvas: canvas,
        x: w * 0.43,
        y: h * 0.915,
        width: w * 0.16,
        color: secondary,
        reverse: true,
      );
    }

    final cornerGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.8
      ..strokeJoin = StrokeJoin.bevel
      ..strokeCap = StrokeCap.square
      ..shader = LinearGradient(
        colors: [
          accent.withValues(alpha: 0.80),
          secondary.withValues(alpha: 0.80),
        ],
      ).createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(_korlixCyberPath(size, cut, 3), cornerGlow);
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
      accent: accent.withValues(alpha: 0.88),
      secondary: secondary.withValues(alpha: 0.72),
      fill: Color.lerp(fill, Colors.black, 0.40)!,
      cut: 17,
      depth: 10,
      padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 17),
      child: child,
    );
  }
}

class KorlixDeepCyberButton extends StatefulWidget {
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
  State<KorlixDeepCyberButton> createState() => _KorlixDeepCyberButtonState();
}

class _KorlixDeepCyberButtonState extends State<KorlixDeepCyberButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final effectiveAccent = disabled ? Colors.white38 : widget.accent;
    final effectiveFill = widget.active
        ? Color.lerp(widget.fill, effectiveAccent, 0.20)!
        : Color.lerp(widget.fill, Colors.black, 0.24)!;

    final content = widget.vertical
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: effectiveAccent, size: 25),
              const SizedBox(height: 4),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: effectiveAccent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                  shadows: [
                    Shadow(
                      color: effectiveAccent.withValues(alpha: 0.56),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              if (widget.subLabel != null)
                Text(
                  widget.subLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFFA9C6CF).withValues(alpha: 0.82),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: effectiveAccent, size: 22),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: disabled ? Colors.white38 : const Color(0xFFE4EBEE),
                    fontSize: 14,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    shadows: disabled
                        ? const []
                        : [
                            Shadow(
                              color: effectiveAccent.withValues(alpha: 0.34),
                              blurRadius: 7,
                            ),
                          ],
                  ),
                ),
              ),
            ],
          );

    return Opacity(
      opacity: disabled ? 0.54 : 1,
      child: GestureDetector(
        onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
        onTapCancel: disabled ? null : () => setState(() => _pressed = false),
        onTapUp: disabled
            ? null
            : (_) {
                setState(() => _pressed = false);
                widget.onTap?.call();
              },
        child: AnimatedScale(
          scale: _pressed ? 0.975 : 1,
          duration: const Duration(milliseconds: 90),
          child: KorlixDeepCyberFrame(
            accent: effectiveAccent,
            secondary: widget.secondary,
            fill: effectiveFill,
            cut: widget.vertical ? 17 : 15,
            depth: widget.active ? 16.0 : 13.0,
            padding: EdgeInsets.symmetric(
              horizontal: widget.vertical ? 8 : 12,
              vertical: widget.vertical ? 8 : 10,
            ),
            child: SizedBox(height: widget.vertical ? 60 : 40, child: content),
          ),
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
            color: color.withValues(alpha: 0.78),
            blurRadius: 13,
            spreadRadius: 1.5,
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
                color: colorA.withValues(alpha: selected ? 0.48 : 0.18),
                blurRadius: selected ? 17 : 8,
                spreadRadius: selected ? 1.0 : 0.0,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 12,
                offset: const Offset(0, 6),
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
