import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/korlix_theme.dart';
import 'resume_model.dart';

class ResumePanel extends StatelessWidget {
  const ResumePanel({super.key, required this.child, this.padding = 20});
  final Widget child;
  final double padding;
  @override
  Widget build(BuildContext context) {
    final s = korlixSkinOf(context);
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [s.panelSoft, s.panelDeep],
        ),
        border: Border.all(color: s.border.withValues(alpha: .6)),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: s.isLight ? .05 : .2),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class ResumeHero extends StatelessWidget {
  const ResumeHero({super.key});
  @override
  Widget build(BuildContext context) {
    final s = korlixSkinOf(context);
    return ResumePanel(
      child: LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 500;
          final words = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KORLIX  /  RESUME STUDIO',
                style: TextStyle(
                  color: s.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.7,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Your next chapter.\nBeautifully written.',
                style: TextStyle(
                  fontSize: narrow ? 30 : 40,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  color: s.text,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Shape your experience into a resume that feels like you. Refine with K-Nova. Make every detail count.',
                style: TextStyle(
                  color: s.mutedText,
                  fontSize: 14,
                  height: 1.65,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in [
                    '3 signature styles',
                    'PDF + Word',
                    'Job-focused drafts',
                  ])
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: s.primary.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: s.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
          final art = Semantics(
            excludeSemantics: true,
            child: SizedBox(
              width: narrow ? 150 : 230,
              height: narrow ? 135 : 245,
              child: CustomPaint(
                painter: ResumeStackPainter(s.primary, s.secondary),
              ),
            ),
          );
          return narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(alignment: Alignment.centerRight, child: art),
                    words,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: words),
                    const SizedBox(width: 24),
                    art,
                  ],
                );
        },
      ),
    );
  }
}

class ResumeStackPainter extends CustomPainter {
  ResumeStackPainter(this.accent, this.secondary);
  final Color accent, secondary;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 220, size.height / 240);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [accent.withValues(alpha: .28), accent.withValues(alpha: 0)],
      ).createShader(const Rect.fromLTWH(-130, -130, 260, 260));
    canvas.drawCircle(Offset.zero, 130, glow);
    for (var i = 2; i >= 0; i--) {
      canvas.save();
      canvas.translate(i * 13.0, i * 2.0);
      canvas.rotate((i - 1) * .105);
      final rect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-68, -93, 136, 184),
        const Radius.circular(8),
      );
      canvas.drawShadow(Path()..addRRect(rect), Colors.black, .0 + 12, true);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = i == 0
              ? const Color(0xFFF8FAFC)
              : Color.lerp(accent, secondary, i / 2)!.withValues(alpha: .55),
      );
      if (i == 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-53, -72, 73, 8),
            const Radius.circular(2),
          ),
          Paint()..color = accent,
        );
        canvas.drawRect(
          const Rect.fromLTWH(-53, -54, 98, 2),
          Paint()..color = const Color(0xFFCBD5E1),
        );
        for (var row = 0; row < 3; row++) {
          final y = -35.0 + row * 41;
          canvas.drawRect(
            Rect.fromLTWH(-53, y, 35, 3),
            Paint()..color = accent,
          );
          for (var l = 0; l < 3; l++) {
            canvas.drawRect(
              Rect.fromLTWH(-53, y + 10 + l * 6, (l == 2 ? 65 : 100), 2),
              Paint()..color = const Color(0xFFCBD5E1),
            );
          }
        }
      }
      canvas.restore();
    }
    canvas.drawCircle(const Offset(61, 68), 22, Paint()..color = accent);
    canvas.drawPath(
      Path()
        ..moveTo(52, 68)
        ..lineTo(58, 74)
        ..lineTo(71, 61),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(ResumeStackPainter old) =>
      old.accent != accent || old.secondary != secondary;
}

class ResumePaper extends StatelessWidget {
  const ResumePaper({
    super.key,
    required this.draft,
    this.letter = false,
    this.mini = false,
  });
  final ResumeDraft draft;
  final bool letter, mini;
  @override
  Widget build(BuildContext context) {
    final accent = Color(
      int.parse(
        'FF${draft.template == 'minimal' ? '1E293B' : draft.accent}',
        radix: 16,
      ),
    );
    final blocks = draft.blocks(letter: letter);
    return Semantics(
      label: letter ? 'Cover letter preview' : 'Resume content preview',
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(mini ? 18 : 30),
        constraints: BoxConstraints(minHeight: mini ? 180 : 480),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(3),
          border: Border(
            top: BorderSide(
              color: accent,
              width: draft.template == 'modern' ? 5 : 0,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .2),
              blurRadius: 25,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (blocks.isEmpty) ...[
              Text(
                'Your name',
                style: TextStyle(
                  color: accent,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your story starts here.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
              const SizedBox(height: 28),
              for (var i = 0; i < 6; i++)
                Container(
                  height: 5,
                  margin: EdgeInsets.only(
                    bottom: i == 2 ? 24 : 9,
                    right: i % 3 == 2 ? 60 : 0,
                  ),
                  color: const Color(0xFFE2E8F0),
                ),
            ],
            for (final b in blocks)
              Padding(
                padding: EdgeInsets.only(
                  top: b.kind == 'heading'
                      ? 20
                      : b.kind == 'title'
                      ? 10
                      : 0,
                  bottom: draft.compact ? 4 : 7,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: b.kind == 'heading'
                        ? Border(
                            bottom: BorderSide(
                              color: accent.withValues(alpha: .3),
                            ),
                          )
                        : null,
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: b.kind == 'heading' ? 5 : 0,
                    ),
                    child: Text(
                      '${b.kind == 'bullet' ? '• ' : ''}${b.kind == 'heading' ? b.text.toUpperCase() : b.text}',
                      textAlign:
                          draft.template == 'executive' &&
                              ['name', 'role', 'contact'].contains(b.kind)
                          ? TextAlign.center
                          : TextAlign.left,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: b.kind == 'name'
                            ? 26
                            : b.kind == 'heading'
                            ? 11
                            : b.kind == 'title'
                            ? 12
                            : b.kind == 'meta' || b.kind == 'contact'
                            ? 10
                            : 12,
                        fontWeight:
                            ['name', 'heading', 'title'].contains(b.kind)
                            ? FontWeight.w700
                            : FontWeight.w400,
                        letterSpacing: b.kind == 'heading' ? 1.1 : 0,
                        height: 1.5,
                        color: ['name', 'heading', 'role'].contains(b.kind)
                            ? accent
                            : const Color(0xFF263445),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
