import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A local, pointer-transparent celebration after a message leaves history.
/// The caller owns deletion and may remove this overlay whenever the route or
/// account changes. No message contents or media leave this widget.
class SocialDumpTruck extends StatefulWidget {
  const SocialDumpTruck({
    super.key,
    required this.preview,
    required this.onComplete,
    this.pickupY,
    this.duration = const Duration(milliseconds: 4400),
  });

  final String preview;
  final VoidCallback onComplete;

  /// Selected message center, in the enclosing overlay's local coordinates.
  final double? pickupY;
  final Duration duration;

  @override
  State<SocialDumpTruck> createState() => _SocialDumpTruckState();
}

class _SocialDumpTruckState extends State<SocialDumpTruck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false, _reducedMotion = false, _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_completed && mounted) {
          _completed = true;
          widget.onComplete();
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (!_started || reduced != _reducedMotion) {
      _reducedMotion = reduced;
      _started = true;
      _controller.duration = reduced
          ? const Duration(milliseconds: 450)
          : widget.duration;
      if (!_completed) _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final preview = widget.preview
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .characters
        .take(140)
        .join();
    return IgnorePointer(
      key: const ValueKey('social-dump-overlay'),
      child: Semantics(
        label: 'Auto dump: removing the selected message from your history.',
        liveRegion: true,
        child: ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width;
              final height = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : MediaQuery.sizeOf(context).height;
              final scale = math.min(1.15, width / 360);
              final sceneHeight = math.min(height, 270.0 * scale + 70);
              final top = ((widget.pickupY ?? height * .55) - sceneHeight * .5)
                  .clamp(0.0, math.max(0.0, height - sceneHeight))
                  .toDouble();
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: top,
                    height: sceneHeight,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        final t = _controller.value;
                        if (_reducedMotion) {
                          return Opacity(
                            key: const ValueKey('social-dump-reduced-motion'),
                            opacity: 1 - _part(t, .3, 1),
                            child: Center(
                              child: _DumpNotice(
                                dark: dark,
                                label: 'Message removed from your history',
                              ),
                            ),
                          );
                        }
                        return _DumpScene(
                          progress: t,
                          scale: scale,
                          dark: dark,
                          preview: preview.isEmpty
                              ? 'Selected message'
                              : preview,
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

double _part(double progress, double start, double end) =>
    ((progress - start) / (end - start)).clamp(0.0, 1.0);

double _smooth(double progress, double start, double end) =>
    Curves.easeInOutCubic.transform(_part(progress, start, end));

class _DumpNotice extends StatelessWidget {
  const _DumpNotice({required this.dark, required this.label});
  final bool dark;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 300),
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    decoration: BoxDecoration(
      color: dark ? const Color(0xFF123346) : const Color(0xFFE6FAFF),
      border: Border.all(color: const Color(0xFF3ACEE7)),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .12),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: dark ? const Color(0xFFE4FAFF) : const Color(0xFF12384F),
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _DumpScene extends StatelessWidget {
  const _DumpScene({
    required this.progress,
    required this.scale,
    required this.dark,
    required this.preview,
  });
  final double progress, scale;
  final bool dark;
  final String preview;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final width = bounds.maxWidth, height = bounds.maxHeight;
      final ground = height - 42 * scale;
      final stopX = (width - 280 * scale) / 2;
      final arrive = _smooth(progress, 0, .28);
      final depart = _smooth(progress, .74, 1);
      final truckX =
          (-290 * scale) * (1 - arrive) +
          stopX * arrive +
          (width + 300 * scale) * depart;
      final lift = _smooth(progress, .38, .63);
      final drop = _smooth(progress, .63, .73);
      final original = Offset(stopX + 219 * scale, ground - 65 * scale);
      final aboveBed = Offset(stopX + 72 * scale, ground - 181 * scale);
      final inBed = Offset(stopX + 72 * scale, ground - 80 * scale);
      var message = Offset.lerp(original, aboveBed, lift)!;
      if (drop > 0) message = Offset.lerp(aboveBed, inBed, drop)!;
      final cardScale = 1 - lift * .26 - drop * .38;
      final cardWidth = math.min(190.0, width * .48);
      final alpha = (1 - _part(progress, .69, .74)) * _part(progress, 0, .08);
      final fade = 1 - _part(progress, .91, 1);
      return Opacity(
        opacity: fade,
        child: Stack(
          key: const ValueKey('social-dump-scene'),
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, .3),
                    radius: .72,
                    colors: [
                      (dark ? const Color(0xFF0B2038) : Colors.white)
                          .withValues(alpha: .96),
                      (dark ? const Color(0xFF0B2038) : Colors.white)
                          .withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: ground + 7 * scale,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF32CBE4).withValues(alpha: 0),
                      const Color(0xFF32CBE4).withValues(alpha: .55),
                      const Color(0xFF32CBE4).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: truckX,
              top: ground - 200 * scale,
              width: 290 * scale,
              height: 205 * scale,
              child: CustomPaint(
                key: const ValueKey('social-dump-truck'),
                painter: _TruckPainter(
                  lift: lift,
                  drop: drop,
                  travel: arrive + depart * 2,
                  loaded: progress >= .7,
                  dark: dark,
                ),
              ),
            ),
            if (alpha > 0)
              Positioned(
                left: message.dx - cardWidth / 2,
                top: message.dy - 30,
                width: cardWidth,
                child: Opacity(
                  opacity: alpha,
                  child: Transform.rotate(
                    angle: lift * -.14 + drop * .2,
                    child: Transform.scale(
                      scale: cardScale,
                      child: Container(
                        key: const ValueKey('social-dump-preview'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: dark
                              ? const Color(0xFF153C50)
                              : const Color(0xFFF0FCFF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFF40D7EC),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF17B5D4,
                              ).withValues(alpha: .2),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: dark
                                ? const Color(0xFFF0FBFF)
                                : const Color(0xFF12384F),
                            fontSize: 12,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: 8,
              child: Center(
                child: _DumpNotice(
                  dark: dark,
                  label: progress < .63
                      ? 'Auto dump · Picking it up'
                      : 'Auto dump · Carrying it away',
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _TruckPainter extends CustomPainter {
  const _TruckPainter({
    required this.lift,
    required this.drop,
    required this.travel,
    required this.loaded,
    required this.dark,
  });
  final double lift, drop, travel;
  final bool loaded, dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 290, size.height / 205);
    const navy = Color(0xFF163047), cyan = Color(0xFF32D4ED);
    const amber = Color(0xFFFFBA45), gold = Color(0xFFE99220);
    final paint = Paint()..isAntiAlias = true;
    void fill(Path path, Color color) =>
        canvas.drawPath(path, paint..color = color);
    void line(Offset a, Offset b, Color color, double width) => canvas.drawLine(
      a,
      b,
      paint
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    void rect(Rect rect, double radius, Color color) => canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint..color = color,
    );

    canvas.drawOval(
      const Rect.fromLTWH(14, 194, 218, 11),
      paint..color = Colors.black.withValues(alpha: dark ? .24 : .1),
    );
    // A rounded blue dump bed and sturdy lower chassis.
    rect(const Rect.fromLTWH(24, 153, 184, 22), 7, navy);
    fill(
      Path()
        ..moveTo(18, 104)
        ..lineTo(130, 104)
        ..lineTo(118, 153)
        ..lineTo(36, 153)
        ..close(),
      const Color(0xFF1EA8CD),
    );
    rect(const Rect.fromLTWH(13, 100, 121, 10), 4, cyan);
    for (final x in [41.0, 68.0, 95.0]) {
      line(Offset(x, 119), Offset(x + 5, 141), const Color(0xFF75E8F5), 4);
    }
    if (loaded) {
      canvas.save();
      canvas.translate(68, 104);
      canvas.rotate(-.12);
      rect(const Rect.fromLTWH(-22, -18, 48, 26), 6, const Color(0xFFE8FBFF));
      line(
        const Offset(-12, -9),
        const Offset(16, -9),
        const Color(0xFF32AFC6),
        3,
      );
      line(
        const Offset(-12, -2),
        const Offset(7, -2),
        const Color(0xFF32AFC6),
        3,
      );
      canvas.restore();
    }
    // Amber cab, windshield, mirror and headlight make the silhouette legible.
    fill(
      Path()
        ..moveTo(136, 91)
        ..quadraticBezierTo(137, 84, 145, 84)
        ..lineTo(175, 84)
        ..quadraticBezierTo(181, 84, 186, 92)
        ..lineTo(205, 127)
        ..lineTo(207, 162)
        ..lineTo(134, 162)
        ..close(),
      amber,
    );
    fill(
      Path()
        ..moveTo(149, 93)
        ..lineTo(173, 93)
        ..lineTo(190, 124)
        ..lineTo(149, 124)
        ..close(),
      navy,
    );
    fill(
      Path()
        ..moveTo(156, 95)
        ..lineTo(168, 95)
        ..lineTo(153, 119)
        ..lineTo(153, 100)
        ..close(),
      const Color(0xFF75DBEE),
    );
    rect(const Rect.fromLTWH(139, 132, 24, 5), 2, gold);
    rect(const Rect.fromLTWH(194, 143, 12, 9), 3, const Color(0xFFFFF1BE));
    rect(const Rect.fromLTWH(196, 161, 17, 9), 3, navy);
    line(const Offset(190, 119), const Offset(204, 114), navy, 4);
    rect(const Rect.fromLTWH(201, 107, 7, 12), 2, navy);
    rect(const Rect.fromLTWH(149, 76, 14, 8), 3, const Color(0xFFFFD775));

    // An articulated pickup arm reaches under the card, lifts, and tips it
    // backwards into the dump bed. Geometry matches the ghost card trajectory.
    final pivot = const Offset(178, 148);
    final bucket = Offset.lerp(
      const Offset(219, 164),
      const Offset(72, 43),
      lift,
    )!;
    final elbow = Offset.lerp(
      const Offset(213, 125),
      const Offset(171, 44),
      lift,
    )!;
    line(pivot, elbow, navy, 15);
    line(pivot, elbow, amber, 10);
    line(elbow, bucket, navy, 13);
    line(elbow, bucket, amber, 8);
    line(
      const Offset(183, 143),
      Offset.lerp(elbow, bucket, .28)!,
      const Color(0xFFDFEAF0),
      4,
    );
    for (final point in [pivot, elbow, bucket]) {
      canvas.drawCircle(point, 5.5, paint..color = navy);
      canvas.drawCircle(point, 2.1, paint..color = const Color(0xFFFFD878));
    }
    canvas.save();
    canvas.translate(bucket.dx, bucket.dy);
    canvas.rotate(-lift * .16 + drop * .75);
    fill(
      Path()
        ..moveTo(-25, -5)
        ..lineTo(-19, 10)
        ..quadraticBezierTo(-17, 14, -11, 14)
        ..lineTo(27, 14)
        ..lineTo(33, 5)
        ..lineTo(-12, 5)
        ..lineTo(-16, -7)
        ..close(),
      gold,
    );
    line(const Offset(-10, 6), const Offset(29, 6), const Color(0xFFFFD482), 3);
    canvas.restore();

    for (final x in [55.0, 105.0, 179.0]) {
      canvas.save();
      canvas.translate(x, 181);
      canvas.rotate(travel * math.pi * 8);
      canvas.drawCircle(Offset.zero, 19, paint..color = navy);
      canvas.drawCircle(
        Offset.zero,
        11,
        paint..color = const Color(0xFFBFD2DC),
      );
      canvas.drawCircle(Offset.zero, 5, paint..color = const Color(0xFF3C5B73));
      for (var i = 0; i < 4; i++) {
        final a = i * math.pi / 2;
        line(
          Offset(math.cos(a) * 12, math.sin(a) * 12),
          Offset(math.cos(a) * 15, math.sin(a) * 15),
          const Color(0xFF587084),
          2,
        );
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TruckPainter oldDelegate) =>
      lift != oldDelegate.lift ||
      drop != oldDelegate.drop ||
      travel != oldDelegate.travel ||
      loaded != oldDelegate.loaded ||
      dark != oldDelegate.dark;
}
