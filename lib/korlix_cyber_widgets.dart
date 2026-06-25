import 'package:flutter/material.dart';

const String kKorlixCyberWidgetsVersion = 'asset_hybrid_hardware_v1_build48';

const String _panelAsset = 'assets/ui/cyber_frames/hardware_panel.png';
const String _promptAsset = 'assets/ui/cyber_frames/hardware_prompt.png';
const String _buttonAsset = 'assets/ui/cyber_frames/hardware_button.png';

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

class _KorlixAssetFrame extends StatelessWidget {
  final Widget child;
  final String assetPath;
  final Rect centerSlice;
  final Color accent;
  final Color secondary;
  final Color fill;
  final EdgeInsetsGeometry padding;
  final double cut;
  final double depth;
  final double? height;
  final bool compactGlow;

  const _KorlixAssetFrame({
    required this.child,
    required this.assetPath,
    required this.centerSlice,
    required this.accent,
    required this.secondary,
    required this.fill,
    required this.padding,
    required this.cut,
    required this.depth,
    this.height,
    this.compactGlow = false,
  });

  @override
  Widget build(BuildContext context) {
    final frame = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.82),
                  blurRadius: depth + 12,
                  spreadRadius: 2,
                  offset: Offset(0, depth * 0.42),
                ),
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: depth + 20,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: secondary.withValues(alpha: 0.16),
                  blurRadius: depth + 22,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: Image.asset(
            assetPath,
            fit: BoxFit.fill,
            centerSlice: centerSlice,
            filterQuality: FilterQuality.high,
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _KorlixThemeGlowOverlayPainter(
              accent: accent,
              secondary: secondary,
              fill: fill,
              cut: cut,
              compact: compactGlow,
            ),
          ),
        ),
        ClipPath(
          clipper: KorlixCyberPanelClipper(cut: cut),
          child: Container(
            width: double.infinity,
            height: height,
            padding: padding,
            child: child,
          ),
        ),
      ],
    );

    return RepaintBoundary(
      child: height == null
          ? frame
          : SizedBox(width: double.infinity, height: height, child: frame),
    );
  }
}

class _KorlixThemeGlowOverlayPainter extends CustomPainter {
  final Color accent;
  final Color secondary;
  final Color fill;
  final double cut;
  final bool compact;

  const _KorlixThemeGlowOverlayPainter({
    required this.accent,
    required this.secondary,
    required this.fill,
    required this.cut,
    required this.compact,
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
      ..strokeJoin = StrokeJoin.bevel
      ..strokeCap = StrokeCap.square
      ..strokeWidth = width
      ..color = color.withValues(alpha: alpha);

    if (blur > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    }

    canvas.drawPath(path, paint);
  }

  void _line(
    Canvas canvas,
    Offset a,
    Offset b,
    Color color, {
    double width = 2,
    double alpha = 0.85,
    double blur = 5,
  }) {
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width + 3
      ..strokeCap = StrokeCap.square
      ..color = color.withValues(alpha: 0.20)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

    final crisp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.square
      ..color = color.withValues(alpha: alpha);

    canvas.drawLine(a, b, glow);
    canvas.drawLine(a, b, crisp);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final w = size.width;
    final h = size.height;
    final path = _korlixCyberPath(size, cut, 6);

    _stroke(canvas, path, accent, compact ? 1.4 : 2.2, alpha: 0.48, blur: 9);
    _stroke(
      canvas,
      path,
      secondary,
      compact ? 1.1 : 1.7,
      alpha: 0.42,
      blur: 12,
    );
    _stroke(
      canvas,
      _korlixCyberPath(size, cut * 0.68, compact ? 14 : 24),
      Colors.white,
      compact ? 0.6 : 0.8,
      alpha: 0.14,
    );

    _line(
      canvas,
      Offset(w * 0.08, h * 0.10),
      Offset(w * 0.30, h * 0.10),
      accent,
      width: compact ? 1.2 : 1.7,
      alpha: 0.72,
    );
    _line(
      canvas,
      Offset(w * 0.70, h * 0.10),
      Offset(w * 0.92, h * 0.10),
      secondary,
      width: compact ? 1.2 : 1.7,
      alpha: 0.72,
    );
    _line(
      canvas,
      Offset(w * 0.10, h * 0.90),
      Offset(w * 0.31, h * 0.90),
      accent,
      width: compact ? 1.0 : 1.4,
      alpha: 0.62,
    );
    _line(
      canvas,
      Offset(w * 0.69, h * 0.90),
      Offset(w * 0.90, h * 0.90),
      secondary,
      width: compact ? 1.0 : 1.4,
      alpha: 0.62,
    );

    if (!compact && h > 180) {
      for (var i = 0; i < 12; i++) {
        final y = h * 0.36 + i * h * 0.023;
        _line(
          canvas,
          Offset(18, y),
          Offset(34, y + 4),
          accent,
          width: 0.8,
          alpha: 0.48,
          blur: 2,
        );
        _line(
          canvas,
          Offset(w - 34, y + 4),
          Offset(w - 18, y),
          secondary,
          width: 0.8,
          alpha: 0.48,
          blur: 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KorlixThemeGlowOverlayPainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.secondary != secondary ||
        oldDelegate.fill != fill ||
        oldDelegate.cut != cut ||
        oldDelegate.compact != compact;
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
    final promptLike = height != null && height! <= 130;

    return _KorlixAssetFrame(
      assetPath: promptLike ? _promptAsset : _panelAsset,
      centerSlice: promptLike
          ? const Rect.fromLTWH(150, 58, 700, 94)
          : const Rect.fromLTWH(170, 160, 660, 300),
      accent: accent,
      secondary: secondary,
      fill: fill,
      padding: padding,
      cut: cut,
      depth: depth,
      height: height,
      compactGlow: promptLike,
      child: child,
    );
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
    return _KorlixAssetFrame(
      assetPath: _buttonAsset,
      centerSlice: const Rect.fromLTWH(92, 54, 336, 82),
      accent: accent.withValues(alpha: 0.88),
      secondary: secondary.withValues(alpha: 0.70),
      fill: Color.lerp(fill, Colors.black, 0.40)!,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      cut: 16,
      depth: 9,
      compactGlow: true,
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
        ? Color.lerp(widget.fill, effectiveAccent, 0.18)!
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
                      color: effectiveAccent.withValues(alpha: 0.52),
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
                              color: effectiveAccent.withValues(alpha: 0.32),
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
          scale: _pressed ? 0.974 : 1,
          duration: const Duration(milliseconds: 90),
          child: _KorlixAssetFrame(
            assetPath: _buttonAsset,
            centerSlice: const Rect.fromLTWH(92, 54, 336, 82),
            accent: effectiveAccent,
            secondary: widget.secondary,
            fill: effectiveFill,
            padding: EdgeInsets.symmetric(
              horizontal: widget.vertical ? 8 : 12,
              vertical: widget.vertical ? 8 : 10,
            ),
            cut: widget.vertical ? 16 : 14,
            depth: widget.active ? 15 : 12,
            compactGlow: true,
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
                spreadRadius: selected ? 1 : 0,
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
