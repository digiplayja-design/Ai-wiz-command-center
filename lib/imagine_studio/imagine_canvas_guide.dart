import 'package:flutter/material.dart';
import '../theme/korlix_theme.dart';
import 'imagine_catalog.dart';

class ImagineCanvasGuide extends StatelessWidget {
  const ImagineCanvasGuide({super.key, required this.brief});
  final ImagineBrief brief;

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final colors = switch (brief.palette) {
      'warm' => [const Color(0xffeba96d), const Color(0xff92674f)],
      'gold' => [const Color(0xfff3d889), const Color(0xff776534)],
      'pastel' => [const Color(0xffd2b8ed), const Color(0xffa1d6d2)],
      'mono' => [const Color(0xffe5e7ee), const Color(0xff747985)],
      _ => [const Color(0xff79e2ed), const Color(0xffa591ff)],
    };
    final ratio = switch (brief.size) {
      '1024x1536' => 2 / 3,
      '1536x1024' => 3 / 2,
      _ => 1.0,
    };
    final alignment = switch (brief.composition) {
      'left' => const Alignment(.65, 0),
      'right' => const Alignment(-.65, 0),
      _ => Alignment.center,
    };
    final motion =
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    final composition = brief.composition == 'auto'
        ? 'Scene-led composition'
        : imagineComposition[brief.composition]!;
    return Semantics(
      label:
          'Layout guide: ${brief.sizeLabel}. $composition. Decorative example, not a generated preview.',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(skin.panel, colors.last, .09)!,
                skin.panelDeep,
              ],
            ),
            border: Border.all(color: skin.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LAYOUT GUIDE',
                style: TextStyle(
                  color: skin.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 164,
                child: Center(
                  child: AnimatedContainer(
                    key: const Key('imagine-canvas-guide-frame'),
                    duration: motion
                        ? const Duration(milliseconds: 260)
                        : Duration.zero,
                    curve: Curves.easeOutCubic,
                    width: 132 * ratio,
                    height: 132,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.first.withValues(alpha: .65),
                          const Color(0xff3f395c),
                          colors.last.withValues(alpha: .65),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .25),
                          blurRadius: 18,
                          offset: const Offset(5, 10),
                        ),
                        BoxShadow(
                          color: colors.last.withValues(alpha: .12),
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0xff151629),
                        ),
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: CustomPaint(painter: _CanvasGrid()),
                            ),
                            AnimatedAlign(
                              duration: motion
                                  ? const Duration(milliseconds: 260)
                                  : Duration.zero,
                              alignment: alignment,
                              child: Container(
                                width: brief.composition == 'close'
                                    ? 78
                                    : brief.composition == 'wide'
                                    ? 38
                                    : 56,
                                height: brief.composition == 'close'
                                    ? 78
                                    : brief.composition == 'wide'
                                    ? 38
                                    : 56,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    center: const Alignment(-.5, -.6),
                                    colors: [
                                      Colors.white,
                                      colors.first,
                                      colors.last,
                                      const Color(0xff29233d),
                                    ],
                                    stops: const [0, .2, .65, 1],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: colors.last.withValues(alpha: .25),
                                      blurRadius: 22,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${brief.sizeLabel} · ${brief.styleLabel}',
                style: TextStyle(
                  color: skin.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$composition. Decorative example; your picture is created from your description.',
                style: TextStyle(
                  color: skin.mutedText,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanvasGrid extends CustomPainter {
  const _CanvasGrid();
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = Colors.white.withValues(alpha: .09)
      ..strokeWidth = .7;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(size.width * i / 3, 0),
        Offset(size.width * i / 3, size.height),
        pen,
      );
      canvas.drawLine(
        Offset(0, size.height * i / 3),
        Offset(size.width, size.height * i / 3),
        pen,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasGrid oldDelegate) => false;
}
