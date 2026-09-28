import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A visual model of an agent's knowledge, not a model of neural weights.
class KorlixNeuralBrain extends StatefulWidget {
  const KorlixNeuralBrain({
    super.key,
    this.activity = 'ready',
    this.height = 270,
    this.accent = const Color(0xFF57DDEB),
    this.interactive = true,
  });
  final String activity;
  final double height;
  final Color accent;
  final bool interactive;
  @override
  State<KorlixNeuralBrain> createState() => _KorlixNeuralBrainState();
}

class _KorlixNeuralBrainState extends State<KorlixNeuralBrain>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  double _yaw = -.35;
  bool _paused = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    if (MediaQuery.disableAnimationsOf(context) || _paused) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Interactive brain visualization. ${brainActivityLabel(widget.activity)}.',
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onHorizontalDragUpdate: widget.interactive
                    ? (d) => setState(() => _yaw += d.delta.dx * .009)
                    : null,
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _clock,
                    builder: (context, _) => CustomPaint(
                      painter: _NeuralPainter(
                        phase: (_clock.value * 360).floor() / 360,
                        yaw: _yaw,
                        accent: widget.accent,
                        activity: widget.activity,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.interactive)
              Positioned(
                bottom: 3,
                left: 8,
                right: 8,
                child: Row(
                  children: [
                    const Icon(
                      Icons.swipe_rounded,
                      size: 14,
                      color: Color(0xFF9AB6CE),
                    ),
                    const SizedBox(width: 5),
                    const Expanded(
                      child: Text(
                        'Drag to explore',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9AB6CE),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _paused
                          ? 'Animate brain'
                          : 'Pause brain animation',
                      onPressed: () {
                        setState(() => _paused = !_paused);
                        _syncMotion();
                      },
                      icon: Icon(
                        _paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        size: 18,
                      ),
                      color: const Color(0xFFB5D4E8),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String brainActivityLabel(String value) => switch (value) {
  'memory' => 'Saving memory',
  'training' => 'Publishing training',
  'analyzing' => 'Reading source material',
  'editing' => 'Draft in progress',
  'saved' => 'Update saved',
  'error' => 'Update needs attention',
  _ => 'Knowledge at rest',
};

class _Point3 {
  const _Point3(this.x, this.y, this.z);
  final double x, y, z;
}

class _Face {
  _Face(this.points, this.depth, this.tint);
  final List<Offset> points;
  final double depth, tint;
}

class _NeuralPainter extends CustomPainter {
  _NeuralPainter({
    required this.phase,
    required this.yaw,
    required this.accent,
    required this.activity,
  });
  final double phase, yaw;
  final Color accent;
  final String activity;
  static const rows = 24, columns = 36;
  static _Point3 cortex(double side, double lat, double lon) {
    final folds = 1 + .022 * math.sin(lon * 7 + lat * 5) * math.sin(lat * 9);
    final w = math.sin(lat), z = math.sin(lon) * w;
    return _Point3(
      side * math.max(.027, .35 + .61 * math.cos(lon) * w * folds),
      .06 + .64 * math.cos(lat) * folds - .04 * z,
      .78 * z * folds,
    );
  }

  static final List<List<_Point3>> _lobes = [-1.0, 1.0]
      .map(
        (side) => List.generate(
          (rows + 1) * columns,
          (i) => cortex(
            side,
            (i ~/ columns) / rows * math.pi,
            (i % columns) / columns * math.pi * 2,
          ),
        ),
      )
      .toList(growable: false);
  static final List<List<_Point3>> _foldLines = [
    for (final side in [-1.0, 1.0])
      for (var band = 1; band < 12; band++)
        [
          for (var i = 0; i <= 180; i++)
            cortex(
              side,
              band / 12 * math.pi +
                  .10 * math.sin(i / 180 * math.pi * 10 + band * 1.8) +
                  .045 * math.sin(i / 180 * math.pi * 22),
              i / 180 * math.pi * 2,
            ),
        ],
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .5, size.height * .44);
    final scale = math.min(size.width * .34, size.height * .40);
    final angle = yaw + math.sin(phase * math.pi * 2) * .12;
    final busy = ['memory', 'training', 'analyzing'].contains(activity);
    final c = activity == 'saved'
        ? const Color(0xFF79E8B3)
        : activity == 'error'
        ? const Color(0xFFFF9DA9)
        : accent;
    _Point3 rotate(_Point3 p) {
      final x = p.x * math.cos(angle) + p.z * math.sin(angle);
      final z = -p.x * math.sin(angle) + p.z * math.cos(angle);
      return _Point3(x, p.y * .92 + z * .3, z * .92 - p.y * .3);
    }

    Offset project(_Point3 p) {
      final perspective = 3.8 / (3.8 - p.z);
      return center +
          Offset(p.x * scale * perspective, -p.y * scale * perspective);
    }

    final glow = Rect.fromCircle(center: center, radius: scale * 1.5);
    canvas.drawOval(
      glow,
      Paint()
        ..shader = RadialGradient(
          colors: [c.withValues(alpha: .12), c.withValues(alpha: 0)],
        ).createShader(glow),
    );
    final floor = Offset(center.dx, size.height * .78);
    // Three translucent rings give the hologram a raised, dimensional base.
    for (var i = 3; i >= 0; i--) {
      final rect = Rect.fromCenter(
        center: floor + Offset(0, i * 5.0),
        width: scale * 2.65,
        height: scale * .54,
      );
      canvas.drawOval(
        rect,
        Paint()..color = const Color(0xFF12304D).withValues(alpha: .38),
      );
      canvas.drawOval(
        rect,
        Paint()
          ..color = c.withValues(alpha: i == 0 ? .5 : .12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final stemPoints = [
      const _Point3(-.12, -.35, -.15),
      const _Point3(.13, -.35, -.15),
      const _Point3(.15, -.79, -.12),
      const _Point3(.07, -1.02, -.24),
      const _Point3(-.06, -.99, -.24),
      const _Point3(-.07, -.72, -.12),
    ].map(rotate).map(project).toList();
    final stem = Path()..addPolygon(stemPoints, true);
    canvas.drawPath(
      stem,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF1B405A),
            c.withValues(alpha: .65),
            const Color(0xFF16324C),
          ],
        ).createShader(stem.getBounds()),
    );
    canvas.drawPath(
      stem,
      Paint()
        ..color = c.withValues(alpha: .38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final faces = <_Face>[],
        projected = <List<Offset>>[],
        depths = <List<double>>[];
    for (final lobe in _lobes) {
      final pts = lobe.map(rotate).toList(growable: false);
      final points = pts.map(project).toList(growable: false);
      projected.add(points);
      depths.add(pts.map((p) => p.z).toList());
      for (var row = 0; row < rows; row++) {
        for (var col = 0; col < columns; col++) {
          final a = row * columns + col,
              b = row * columns + (col + 1) % columns;
          final ids = [a, b, b + columns, a + columns];
          final depth = ids.map((i) => pts[i].z).reduce((a, b) => a + b) / 4;
          faces.add(
            _Face(
              ids.map((i) => points[i]).toList(),
              depth,
              .5 + .5 * math.sin(row * 1.7 + col * 1.4),
            ),
          );
        }
      }
    }
    faces.sort((a, b) => a.depth.compareTo(b.depth));
    final scan = math.sin(phase * math.pi * 8) * scale * .6 + center.dy;
    for (final face in faces) {
      final p = Path()..addPolygon(face.points, true);
      final front = ((face.depth + 1) / 2).clamp(0.0, 1.0);
      final base = Color.lerp(
        const Color(0xFF102E58),
        c,
        .12 + front * .30 + face.tint * .025,
      )!;
      canvas.drawPath(p, Paint()..color = base.withValues(alpha: .96));
      canvas.drawPath(
        p,
        Paint()
          ..color = c.withValues(alpha: .015 + front * .025)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .55,
      );
      if (busy && (face.points.first.dy - scan).abs() < 8) {
        canvas.drawPath(p, Paint()..color = c.withValues(alpha: .35));
      }
    }
    // Project folded cortical contours onto the same 3D surface.
    for (final line in _foldLines) {
      var path = Path(), drawing = false;
      void draw() {
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFF071D36).withValues(alpha: .75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = scale * .043
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
        canvas.drawPath(
          path.shift(const Offset(-.6, -.8)),
          Paint()
            ..color = c.withValues(alpha: .57)
            ..style = PaintingStyle.stroke
            ..strokeWidth = scale * .016
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }

      for (final raw in line) {
        final rotated = rotate(raw);
        if (rotated.z < .07 || raw.x.abs() < .065) {
          if (drawing) {
            draw();
            path = Path();
            drawing = false;
          }
          continue;
        }
        final pt = project(rotated);
        if (!drawing) {
          path.moveTo(pt.dx, pt.dy);
          drawing = true;
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      if (drawing) draw();
    }
    for (var l = 0; l < projected.length; l++) {
      for (var i = columns; i < rows * columns; i += 23) {
        if (depths[l][i] < -.1) continue;
        final pt = projected[l][i];
        final pulse = .5 + .5 * math.sin(phase * math.pi * (busy ? 12 : 4) + i);
        canvas.drawCircle(
          pt,
          busy ? 3.0 + pulse * 2 : 2.2,
          Paint()
            ..color = c.withValues(alpha: .16)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawCircle(
          pt,
          1.0 + pulse * .8,
          Paint()
            ..color = Color.lerp(
              c,
              Colors.white,
              .4,
            )!.withValues(alpha: .55 + .4 * pulse),
        );
      }
    }
    // Activity pulses travel toward the brain only during a real operation.
    if (busy) {
      for (var i = 0; i < 5; i++) {
        final t = (phase * 4 + i / 5) % 1;
        final from = Offset(center.dx + (i - 2) * scale * .42, floor.dy);
        final to = center + Offset((i - 2) * scale * .25, scale * .1);
        canvas.drawCircle(
          Offset.lerp(from, to, t)!,
          2.7,
          Paint()..color = c.withValues(alpha: math.sin(t * math.pi)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NeuralPainter old) =>
      old.phase != phase ||
      old.yaw != yaw ||
      old.activity != activity ||
      old.accent != accent;
}

class AgentStudioColors {
  AgentStudioColors(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get background =>
      dark ? const Color(0xFF060D19) : const Color(0xFFF0F4FA);
  Color get surface => dark ? const Color(0xFF0D192B) : Colors.white;
  Color get raised => dark ? const Color(0xFF13233A) : const Color(0xFFEAF1FA);
  Color get line => dark ? const Color(0xFF233852) : const Color(0xFFD6E0EE);
  Color get text => dark ? const Color(0xFFF2F6FC) : const Color(0xFF132039);
  Color get muted => dark ? const Color(0xFFA2B5CF) : const Color(0xFF52637D);
  Color get cyan => dark ? const Color(0xFF6FE2F0) : const Color(0xFF087780);
}

class AgentStudioPanel extends StatelessWidget {
  const AgentStudioPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.accent,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? accent;
  @override
  Widget build(BuildContext context) {
    final p = AgentStudioColors(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: accent?.withValues(alpha: .4) ?? p.line),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF020917,
            ).withValues(alpha: p.dark ? .16 : .045),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class AgentStudioPill extends StatelessWidget {
  const AgentStudioPill(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final p = AgentStudioColors(context),
        c = color ?? AgentStudioColors(context).cyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: p.dark ? .12 : .08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: c,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AgentBrainHero extends StatelessWidget {
  const AgentBrainHero({
    super.key,
    required this.name,
    required this.memories,
    required this.version,
    this.activity = 'ready',
    this.compact = false,
  });
  final String name, activity;
  final int memories, version;
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF122744), Color(0xFF081321), Color(0xFF131B39)],
      ),
      border: Border.all(color: const Color(0xFF2B4260)),
    ),
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.psychology_alt_rounded,
              size: 17,
              color: Color(0xFF6FE2F0),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 2,
                style: const TextStyle(
                  color: Color(0xFFF1F6FF),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: Color(0xFF9AB6CE),
            ),
          ],
        ),
        KorlixNeuralBrain(activity: activity, height: compact ? 178 : 265),
        Semantics(
          liveRegion: true,
          child: Text(
            brainActivityLabel(activity),
            style: const TextStyle(
              color: Color(0xFF85E8ED),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '$memories saved memories  ·  Training v$version',
          style: const TextStyle(color: Color(0xFFB1C3DB), fontSize: 12),
        ),
        const SizedBox(height: 5),
        const Text(
          'Visual map of your agent’s knowledge',
          style: TextStyle(color: Color(0xFF8BA2BE), fontSize: 10),
        ),
      ],
    ),
  );
}
