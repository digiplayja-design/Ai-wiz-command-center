import 'package:flutter/material.dart';

/// The rain repaints independently of the studio and uses cached glyphs.
class LogoProcessingPanel extends StatefulWidget {
  const LogoProcessingPanel({
    super.key,
    required this.elapsed,
    required this.stage,
    this.reconnecting = false,
  });
  final int elapsed;
  final String stage;
  final bool reconnecting;

  @override
  State<LogoProcessingPanel> createState() => _LogoProcessingPanelState();
}

class _LogoProcessingPanelState extends State<LogoProcessingPanel>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  late final _rain = _MatrixRain(_motion);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    if (media.disableAnimations ||
        media.accessibleNavigation ||
        !TickerMode.valuesOf(context).enabled) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    _rain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = switch (widget.stage) {
      'planning' => 'Astra is shaping your logo',
      'rendering' => 'Rendering your logo',
      'finishing' => 'Finishing your logo',
      _ => 'Starting your logo',
    };
    final title = widget.reconnecting ? 'Reconnecting to your logo' : stage;
    final caption = widget.reconnecting
        ? 'Checking the same job. Your concept may still be processing.'
        : switch (widget.stage) {
            'planning' => 'Exploring the symbol, lettering and composition.',
            'rendering' => 'Bringing your creative direction to life.',
            'finishing' => 'Checking the artwork and saving your result.',
            _ => 'Your creative brief is on its way to Astra.',
          };
    final time =
        '${widget.elapsed ~/ 60}:${(widget.elapsed % 60).toString().padLeft(2, '0')}';
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ColoredBox(
          color: const Color(0xFF020F0C),
          child: Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(child: CustomPaint(painter: _rain)),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF020F0C).withValues(alpha: .12),
                        const Color(0xFF020F0C).withValues(alpha: .92),
                        const Color(0xFF020F0C).withValues(alpha: .98),
                      ],
                      stops: const [0, .55, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 32, 22, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'ASTRA / MAX',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.2,
                            color: Color(0xFF7AFFC4),
                          ),
                        ),
                        ExcludeSemantics(
                          child: Text(
                            time,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFB4D6C8),
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 21,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF0FFF8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      caption,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: Color(0xFFB4D6C8),
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'Great concepts can take a few minutes.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: Color(0xFF86A699),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF24583F)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatrixRain extends CustomPainter {
  _MatrixRain(this.motion) : super(repaint: motion) {
    for (var brightness = 0; brightness < 8; brightness++) {
      glyphs.add([
        for (final rune in '01KORLIX+=<>'.runes)
          TextPainter(
            text: TextSpan(
              text: String.fromCharCode(rune),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1,
                color: brightness == 0
                    ? const Color(0xFFD8FFEB)
                    : const Color(
                        0xFF36F994,
                      ).withValues(alpha: (8 - brightness) / 10),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(),
      ]);
    }
  }
  final Animation<double> motion;
  final List<List<TextPainter>> glyphs = [];

  @override
  void paint(Canvas canvas, Size size) {
    final columns = (size.width / 19).ceil().clamp(8, 28);
    final step = size.width / columns;
    for (var column = 0; column < columns; column++) {
      final distance = size.height + 160;
      final head =
          ((column * 73 + motion.value * distance * (2 + column % 3)) %
              distance) -
          20;
      for (var trail = 0; trail < glyphs.length; trail++) {
        final y = head - trail * 17;
        if (y < -14 || y > size.height) continue;
        final index =
            (column * 7 + trail * 3 + (motion.value * 24).floor()) %
            glyphs[trail].length;
        glyphs[trail][index].paint(canvas, Offset(step * (column + .3), y));
      }
    }
  }

  void dispose() {
    for (final row in glyphs) {
      for (final glyph in row) {
        glyph.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MatrixRain oldDelegate) =>
      oldDelegate.motion != motion;
}
