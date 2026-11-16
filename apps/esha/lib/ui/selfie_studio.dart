import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/selfie.dart';
import 'brand.dart';

class SelfiePreviewCard extends StatelessWidget {
  const SelfiePreviewCard({
    super.key,
    required this.controller,
    required this.look,
  });

  final SelfieStudioController controller;
  final StudioLook look;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final photo = controller.photo;
      return EshaPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (photo == null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 26,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [blush, ivory],
                  ),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 46,
                      color: pink,
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Your face. A little color.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Georgia', fontSize: 24),
                    ),
                    SizedBox(height: 9),
                    Text(
                      'Choose a well-lit selfie with one person, looking ahead, with eyes and lips visible.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              )
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ColoredBox(
                  color: blush,
                  child: LayoutBuilder(
                    builder: (context, constraints) => Semantics(
                      image: true,
                      excludeSemantics: true,
                      label: controller.showOriginal
                          ? 'Your original selfie, without makeup overlays'
                          : 'Selfie preview with ${lookNames[look.shade]} lips, ${look.finish.toLowerCase()} finish and ${look.lashes.toLowerCase()} lashes',
                      child: SizedBox(
                        width: double.infinity,
                        height: (constraints.maxWidth * 1.15).clamp(240, 520),
                        child: CustomPaint(
                          key: const Key('selfie-preview-image'),
                          painter: SelfieMakeupPainter(
                            photo: photo,
                            look: look,
                            showOriginal: controller.showOriginal,
                            intensity: controller.intensity,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Original'),
                    selected: controller.showOriginal,
                    onSelected: controller.busy
                        ? null
                        : (_) => controller.setShowOriginal(true),
                  ),
                  ChoiceChip(
                    label: const Text('Try-on'),
                    selected: !controller.showOriginal,
                    onSelected: controller.busy
                        ? null
                        : (_) => controller.setShowOriginal(false),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Makeup strength',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(controller.intensity * 100).round()}%',
                    style: const TextStyle(color: muted),
                  ),
                ],
              ),
              Semantics(
                label: 'Makeup strength',
                child: Slider(
                  key: const Key('selfie-intensity'),
                  min: .15,
                  max: .85,
                  divisions: 14,
                  value: controller.intensity,
                  semanticFormatterCallback: (value) =>
                      '${(value * 100).round()} percent',
                  onChanged: controller.busy || controller.showOriginal
                      ? null
                      : controller.setIntensity,
                ),
              ),
              if (controller.showOriginal)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Switch to Try-on to adjust the strength.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('choose-selfie'),
              onPressed: controller.canChoose ? controller.choosePhoto : null,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(photo == null ? 'Upload selfie' : 'Change selfie'),
            ),
            if (controller.busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 9),
              Semantics(
                liveRegion: true,
                child: Text(
                  controller.busyMessage,
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: controller.removePhoto,
                child: const Text('Cancel preview'),
              ),
            ] else if (photo != null)
              TextButton.icon(
                onPressed: controller.removePhoto,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Remove photo'),
              ),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    controller.error!,
                    style: const TextStyle(color: pink),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'The preview runs on your device. Your photo is not uploaded or synced, and your original is unchanged. Remove it here or sign out to clear the preview.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      );
    },
  );
}

/// Draws the source image once, then paints local color and lash strokes in the
/// same contained image rectangle. No image pixels are moved or reshaped.
class SelfieMakeupPainter extends CustomPainter {
  const SelfieMakeupPainter({
    required this.photo,
    required this.look,
    required this.showOriginal,
    required this.intensity,
  });

  final SelfiePhoto photo;
  final StudioLook look;
  final bool showOriginal;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || photo.size.isEmpty) return;
    final fit = applyBoxFit(BoxFit.contain, photo.size, size);
    final imageRect = Alignment.center.inscribe(
      fit.destination,
      Offset.zero & size,
    );
    canvas.save();
    canvas.clipRect(imageRect);
    canvas.drawImageRect(
      photo.image,
      Offset.zero & photo.size,
      imageRect,
      Paint()
        ..filterQuality = imageRect.size == photo.size
            ? FilterQuality.none
            : FilterQuality.high,
    );
    final strength = intensity.clamp(0.0, 1.0);
    if (!showOriginal && strength > 0) {
      Offset point(Offset p) => Offset(
        imageRect.left + p.dx * imageRect.width,
        imageRect.top + p.dy * imageRect.height,
      );
      List<Offset> ring(List<Offset> points) => points.map(point).toList();
      final outer = ring(photo.face.outerLips);
      final inner = ring(photo.face.innerLips);
      final left = ring(photo.face.leftEye);
      final right = ring(photo.face.rightEye);
      final mouth = outer.isEmpty
          ? point(photo.face.bounds.bottomCenter)
          : _center(outer);
      _lips(canvas, outer, inner, left, right, strength);
      _lashes(canvas, left, mouth, strength);
      _lashes(canvas, right, mouth, strength);
    }
    canvas.restore();
  }

  void _lips(
    Canvas canvas,
    List<Offset> outer,
    List<Offset> inner,
    List<Offset> leftEye,
    List<Offset> rightEye,
    double strength,
  ) {
    // Without a valid inner ring, painting would risk coloring the mouth/teeth.
    if (outer.length < 3 || inner.length < 3) return;
    // Explicit subtraction also excludes an inner edge protruding beyond a
    // smoothed outer contour. An even-odd XOR alone would fill that region.
    final mask = Path.combine(
      PathOperation.difference,
      _closedRing(outer),
      Path()..addPolygon(inner, true),
    );
    final shade = lookColors[look.shade.clamp(0, lookColors.length - 1)];
    canvas.save();
    canvas.clipPath(mask);
    // The color blend retains the photo's luminosity and fine lip texture.
    canvas.drawPath(
      mask,
      Paint()
        ..color = shade.withValues(alpha: .72 * strength)
        ..blendMode = BlendMode.color,
    );
    canvas.drawPath(
      mask,
      Paint()
        ..color = shade.withValues(alpha: .20 * strength)
        ..blendMode = BlendMode.softLight,
    );
    if (look.finish == 'Gloss') {
      final ends = _endpoints(outer);
      final axis = _unit(outer[ends.$2] - outer[ends.$1]);
      final center = (outer[ends.$1] + outer[ends.$2]) / 2;
      var up = Offset(axis.dy, -axis.dx);
      final eyes = [...leftEye, ...rightEye];
      if (eyes.isNotEmpty && _dot(up, _center(eyes) - center) < 0) up = -up;
      final depth = outer.map((p) => _dot(p - center, up)).reduce(math.min);
      final width = (outer[ends.$2] - outer[ends.$1]).distance;
      final highlight = center + up * (depth * .68);
      canvas.drawLine(
        highlight - axis * width * .17,
        highlight + axis * width * .17,
        Paint()
          ..color = Colors.white.withValues(alpha: .18 * strength)
          ..blendMode = BlendMode.screen
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(.65, width * .028)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * .012),
      );
    }
    canvas.restore();
  }

  void _lashes(Canvas canvas, List<Offset> eye, Offset mouth, double strength) {
    if (eye.length < 4) return;
    final ends = _endpoints(eye);
    final start = eye[ends.$1], end = eye[ends.$2];
    final width = (end - start).distance;
    if (width < 2) return;
    final axis = _unit(end - start);
    var up = Offset(axis.dy, -axis.dx);
    final center = (start + end) / 2;
    if (_dot(up, center - mouth) < 0) up = -up;
    final first = _arc(eye, ends.$1, ends.$2, 1);
    final second = _arc(eye, ends.$1, ends.$2, -1);
    double elevation(List<Offset> arc) =>
        arc.map((p) => _dot(p - center, up)).reduce((a, b) => a + b) /
        arc.length;
    final upper = elevation(first) >= elevation(second) ? first : second;
    final lid = Path()..moveTo(upper.first.dx, upper.first.dy);
    for (final p in upper.skip(1)) {
      lid.lineTo(p.dx, p.dy);
    }
    final bold = look.lashes == 'Bold';
    final wispy = look.lashes == 'Wispy';
    final lashPaint = Paint()
      ..color = const Color(0xFF241B23)
          .withValues(alpha: strength * (bold ? .90 : .76))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(.55, width * (bold ? .022 : .014));
    canvas.drawPath(lid, lashPaint);
    final count = bold
        ? 14
        : wispy
        ? 11
        : 8;
    final metric = lid.computeMetrics().first;
    for (var i = 0; i < count; i++) {
      final fraction = .07 + .86 * i / (count - 1);
      final tangent = metric.getTangentForOffset(metric.length * fraction);
      if (tangent == null) continue;
      var normal = Offset(tangent.vector.dy, -tangent.vector.dx);
      if (_dot(normal, up) < 0) normal = -normal;
      final variation = wispy && i.isEven ? 1.24 : 1.0;
      final length =
          width *
          (bold
              ? .19
              : wispy
              ? .15
              : .11) *
          (.72 + .28 * math.sin(math.pi * fraction)) *
          variation;
      final root = tangent.position;
      final fan = axis * ((fraction - .5) * width * .10);
      final tip = root + normal * length + fan;
      canvas.drawPath(
        Path()
          ..moveTo(root.dx, root.dy)
          ..quadraticBezierTo(
            root.dx + normal.dx * length * .7,
            root.dy + normal.dy * length * .7,
            tip.dx,
            tip.dy,
          ),
        lashPaint,
      );
    }
  }

  static Path _closedRing(List<Offset> points) {
    final first = (points.last + points.first) / 2;
    final path = Path()..moveTo(first.dx, first.dy);
    for (var i = 0; i < points.length; i++) {
      final next = (points[i] + points[(i + 1) % points.length]) / 2;
      path.quadraticBezierTo(points[i].dx, points[i].dy, next.dx, next.dy);
    }
    return path..close();
  }

  static (int, int) _endpoints(List<Offset> points) {
    var a = 0, b = 1, longest = 0.0;
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final distance = (points[i] - points[j]).distanceSquared;
        if (distance > longest) {
          a = i;
          b = j;
          longest = distance;
        }
      }
    }
    return points[a].dx <= points[b].dx ? (a, b) : (b, a);
  }

  static List<Offset> _arc(List<Offset> ring, int from, int to, int step) {
    final result = <Offset>[ring[from]];
    var i = from;
    while (i != to) {
      i = (i + step + ring.length) % ring.length;
      result.add(ring[i]);
    }
    return result;
  }

  static Offset _unit(Offset value) =>
      value.distance < .001 ? const Offset(1, 0) : value / value.distance;
  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
  static Offset _center(List<Offset> points) =>
      points.reduce((a, b) => a + b) / points.length.toDouble();

  @override
  bool shouldRepaint(SelfieMakeupPainter oldDelegate) =>
      !identical(photo, oldDelegate.photo) ||
      look.shade != oldDelegate.look.shade ||
      look.finish != oldDelegate.look.finish ||
      look.lashes != oldDelegate.look.lashes ||
      showOriginal != oldDelegate.showOriginal ||
      intensity != oldDelegate.intensity;
}
