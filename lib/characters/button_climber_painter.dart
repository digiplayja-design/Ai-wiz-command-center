import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

double _ease(double value) {
  final t = value.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Deterministic choreography: climb, pull up, wave, reach out, then climb down.
/// The second figure starts partway through so the two never move in lockstep.
@immutable
class KorlixClimberPose {
  const KorlixClimberPose({
    required this.position,
    required this.stride,
    required this.perch,
    required this.wave,
    required this.reach,
    required this.seconds,
  });
  final Offset position;
  final double stride, perch, wave, reach, seconds;

  factory KorlixClimberPose.at(
    double seconds,
    Rect button,
    Size viewport, {
    required bool woman,
  }) {
    final time = seconds + (woman ? 9.5 : 0);
    final phase = time % 27;
    double ascent, perch = 0, wave = 0, reach = 0;
    if (phase < 7) {
      ascent = _ease(phase / 7);
    } else if (phase < 9) {
      ascent = 1;
      perch = _ease((phase - 7) / 2);
    } else if (phase < 13) {
      ascent = perch = 1;
      wave = _ease((phase - 9) / .6) * (1 - _ease((phase - 12.3) / .7));
    } else if (phase < 17) {
      ascent = perch = 1;
      reach = _ease((phase - 13) / .9) * (1 - _ease((phase - 16) / 1));
    } else if (phase < 19) {
      ascent = 1;
      perch = 1 - _ease((phase - 17) / 2);
    } else {
      ascent = 1 - _ease((phase - 19) / 8);
    }
    final direction = woman ? -1.0 : 1.0;
    final edge = woman ? button.right : button.left;
    final scale = viewport.width < 430 ? .86 : 1.0;
    // Keep the torso outboard of the label, with one foot on the rounded lip.
    final x = (edge + direction * (-6 + 8 * perch)).clamp(
      24.0,
      math.max(24.0, viewport.width - 24),
    );
    final lower = math.min(button.bottom - 8, viewport.height - 30);
    final upper = button.top + 12;
    final y = ui.lerpDouble(lower, upper, ascent)! - 36 * scale * perch;
    return KorlixClimberPose(
      position: Offset(x.toDouble(), y),
      stride: math.sin(time * 4.1) * (1 - perch),
      perch: perch,
      wave: wave,
      reach: reach,
      seconds: time,
    );
  }
}

/// Vector artwork stays crisp on Retina screens and adds no media downloads.
class KorlixButtonClimbersPainter extends CustomPainter {
  KorlixButtonClimbersPainter({
    required this.seconds,
    required this.buttons,
    required this.visible,
  }) : super(repaint: Listenable.merge([seconds, buttons, visible]));
  final ValueListenable<double> seconds;
  final ValueListenable<List<Rect>> buttons;
  final ValueListenable<bool> visible;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible.value || size.width < 120 || size.height < 120) return;
    final ledges = buttons.value;
    if (ledges.isEmpty) return;
    final left = ledges
        .where((r) => r.center.dx <= size.width / 2 + 4)
        .toList();
    final right = ledges
        .where((r) => r.center.dx >= size.width / 2 - 4)
        .toList();
    final manButton = (left.isEmpty ? ledges : left).first;
    final womanChoices = right.isEmpty ? ledges : right;
    // Opposite sides of the top row; if it is a full-width control, share it.
    final womanButton = womanChoices.first;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final woman in [false, true]) {
      final button = woman ? womanButton : manButton;
      final pose = KorlixClimberPose.at(
        seconds.value,
        button,
        size,
        woman: woman,
      );
      final scale = size.width < 430 ? .86 : 1.0;
      _person(canvas, pose, woman: woman, scale: scale);
    }
    canvas.restore();
  }

  void _person(
    Canvas canvas,
    KorlixClimberPose pose, {
    required bool woman,
    required double scale,
  }) {
    final accent = woman ? const Color(0xFFB59AFF) : const Color(0xFF5AE5F0);
    final coat = woman ? const Color(0xFF7251CF) : const Color(0xFF168CBB);
    final coatDeep = woman ? const Color(0xFF34215E) : const Color(0xFF073D60);
    final skin = woman ? const Color(0xFFDEA37B) : const Color(0xFFB77950);
    final skinLight = woman ? const Color(0xFFFFD0A6) : const Color(0xFFEAB389);
    final skinDark = woman ? const Color(0xFF9D5D43) : const Color(0xFF70412F);
    const hair = Color(0xFF211C2A), trousers = Color(0xFF1A263F);
    final stride = pose.stride, perch = pose.perch;
    final breath = math.sin(pose.seconds * 2.1) * .55 * perch;
    final lean = (1 - perch) * (.045 + stride * .035);

    canvas.save();
    canvas.translate(pose.position.dx, pose.position.dy);
    canvas.scale(woman ? -scale : scale, scale);
    canvas.rotate(lean);
    // A contact shadow grounds shoes on the button, and a narrow rim separates
    // the figures from both bright and dark palettes without blurring the UI.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(2, 27), width: 27, height: 5),
      Paint()..color = Colors.black.withValues(alpha: .20 * perch),
    );
    canvas.translate(0, breath);

    void stroke(List<Offset> points, Color color, double width) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    void limb(List<Offset> points, Color base, Color light, double width) {
      stroke(
        points,
        const Color(0xFFD1F6FF).withValues(alpha: .7),
        width + 1.5,
      );
      stroke(points, const Color(0xFF111827), width + .5);
      stroke(points, base, width);
      stroke(
        points.map((p) => p + const Offset(-1, -.7)).toList(),
        light,
        width * .30,
      );
    }

    void shoe(Offset ankle) {
      final rect = Rect.fromLTWH(ankle.dx - 5, ankle.dy - 1, 12, 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(.6), const Radius.circular(3)),
        Paint()..color = const Color(0xFF0B1428),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..shader = LinearGradient(
            colors: [const Color(0xFFE5F4FC), accent, coat],
          ).createShader(rect),
      );
      stroke(
        [
          Offset(rect.left + 1, rect.bottom),
          Offset(rect.right - 1, rect.bottom),
        ],
        const Color(0xFFF2F6FF),
        1.4,
      );
      stroke(
        [
          Offset(rect.left + 4, rect.top + 1),
          Offset(rect.left + 6, rect.top + 2),
        ],
        coatDeep,
        1,
      );
    }

    final leftKnee = Offset(-8 - (1 - perch) * 5, 12 - stride * 5);
    final rightKnee = Offset(8 + (1 - perch) * 4, 12 + stride * 5);
    final leftFoot = Offset(
      -8 + (1 - perch) * 3,
      24 - math.max(0.0, stride) * 10,
    );
    final rightFoot = Offset(8, 24 + math.min(0.0, stride) * 10);
    limb(
      [const Offset(-5, -1), leftKnee, leftFoot],
      trousers,
      const Color(0xFF506580),
      6.7,
    );
    limb(
      [const Offset(5, -1), rightKnee, rightFoot],
      trousers,
      const Color(0xFF506580),
      6.7,
    );
    shoe(leftFoot);
    shoe(rightFoot);
    // Small knee guards and jacket hem give the figures an explorer outfit.
    canvas.drawCircle(leftKnee, 2.2, Paint()..color = coatDeep);
    canvas.drawCircle(rightKnee, 2.2, Paint()..color = coatDeep);

    if (woman) {
      final sway = math.sin(pose.seconds * 3.0) * 3;
      final ponytail = Path()
        ..moveTo(-7, -37)
        ..cubicTo(-21, -39, -20 + sway, -18, -12 + sway, -16)
        ..cubicTo(-17 + sway, -25, -7, -26, -7, -37);
      canvas.drawPath(ponytail, Paint()..color = const Color(0xFF302336));
      stroke(
        [
          const Offset(-10, -35),
          Offset(-16 + sway * .3, -29),
          Offset(-14 + sway, -20),
        ],
        const Color(0xFF725063),
        1.8,
      );
      canvas.drawCircle(const Offset(-9, -35), 2.6, Paint()..color = accent);
    }

    final torso = Path()
      ..moveTo(-8, -23)
      ..quadraticBezierTo(0, -27, 8, -23)
      ..quadraticBezierTo(12, -14, 9, 1)
      ..quadraticBezierTo(0, 4, -9, 1)
      ..quadraticBezierTo(-12, -14, -8, -23)
      ..close();
    canvas.drawPath(
      torso,
      Paint()
        ..color = const Color(0xFFD1F6FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7,
    );
    canvas.drawPath(
      torso,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, coat, coatDeep],
        ).createShader(const Rect.fromLTWH(-10, -25, 21, 29)),
    );
    stroke(
      [const Offset(-8, -20), const Offset(-5, -10), const Offset(-6, -2)],
      accent.withValues(alpha: .6),
      1.5,
    );
    stroke(
      [const Offset(0, -21), const Offset(0, 1)],
      const Color(0xFF112A42),
      1.2,
    );
    stroke([const Offset(-8, 1), const Offset(8, 1)], coatDeep, 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, -18, 4.5, 5),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0xFFE5FAFF),
    );
    stroke(
      [const Offset(4, -17), const Offset(5.5, -15.8), const Offset(7, -17)],
      coat,
      .9,
    );
    canvas.drawCircle(const Offset(0, .5), 1.5, Paint()..color = accent);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-3, -29, 6, 8),
        const Radius.circular(2),
      ),
      Paint()..color = skin,
    );
    stroke(
      [const Offset(-4, -23), const Offset(0, -20), const Offset(4, -23)],
      coatDeep,
      2.5,
    );

    // Ears, shaded face, hair, brows, eyes, nose and smile remain visible at 1x.
    canvas.drawOval(
      const Rect.fromLTWH(-10, -37, 5, 7),
      Paint()..color = skinDark,
    );
    canvas.drawOval(const Rect.fromLTWH(5, -37, 5, 7), Paint()..color = skin);
    final head = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-8.5, -43, 17, 19),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      head,
      Paint()
        ..color = const Color(0xFFF0ECE3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawRRect(
      head,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.5, -.4),
          radius: 1.1,
          colors: [skinLight, skin, skinDark],
        ).createShader(head.outerRect),
    );
    final hairline = Path()
      ..moveTo(-8.6, -32)
      ..cubicTo(-13, -47, 1, -49, 8, -42)
      ..quadraticBezierTo(11, -38, 8, -33)
      ..lineTo(6.5, -38)
      ..quadraticBezierTo(0, -36, -3, -41)
      ..quadraticBezierTo(-5, -36, -7, -36)
      ..close();
    canvas.drawPath(hairline, Paint()..color = hair);
    stroke(
      [const Offset(-6, -42), const Offset(-1, -44), const Offset(4, -42)],
      const Color(0xFF615062),
      1.3,
    );
    if (!woman) {
      final beard = Path()
        ..moveTo(-7, -30)
        ..quadraticBezierTo(0, -25, 7, -30)
        ..quadraticBezierTo(5, -23, 0, -24)
        ..quadraticBezierTo(-6, -24, -7, -30);
      canvas.drawPath(beard, Paint()..color = hair.withValues(alpha: .65));
    }
    final blinking = (pose.seconds + (woman ? 1.4 : 0)) % 5.1 < .13;
    for (final x in [-3.4, 3.4]) {
      stroke([Offset(x - 1.6, -36.6), Offset(x + 1.2, -36.8)], hair, .9);
      if (blinking) {
        stroke([Offset(x - 1.2, -34), Offset(x + 1.2, -34)], hair, 1);
      } else {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, -34), width: 3.1, height: 3.3),
          Paint()..color = const Color(0xFFFFF8EF),
        );
        canvas.drawCircle(Offset(x + .3, -33.9), 1.05, Paint()..color = hair);
        canvas.drawCircle(
          Offset(x + .6, -34.4),
          .35,
          Paint()..color = Colors.white,
        );
      }
    }
    stroke(
      [const Offset(.1, -33), const Offset(-.5, -30.5), const Offset(1, -30.4)],
      skinDark.withValues(alpha: .6),
      .75,
    );
    final smile = Path()
      ..moveTo(-2.5, -28.7)
      ..quadraticBezierTo(0, -26.6, 2.7, -28.9);
    canvas.drawPath(
      smile,
      Paint()
        ..color = woman ? const Color(0xFF9C4449) : const Color(0xFFFFD9BD)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..strokeCap = StrokeCap.round,
    );

    final idleLeft = Offset(-12, -24 - stride * 9);
    final idleRight = Offset(14, -28 + stride * 9);
    final restingLeft = Offset(-12, -6);
    final restingRight = Offset(12, -7);
    var leftHand = Offset.lerp(idleLeft, restingLeft, perch)!;
    var rightHand = Offset.lerp(idleRight, restingRight, perch)!;
    // One hand waves from above the head; then both palms grow toward the glass.
    final wave = pose.wave;
    rightHand = Offset.lerp(
      rightHand,
      Offset(
        17 + 4 * math.sin(pose.seconds * 9),
        -40 + 2 * math.cos(pose.seconds * 9),
      ),
      wave,
    )!;
    leftHand = Offset.lerp(leftHand, const Offset(-15, -18), pose.reach)!;
    rightHand = Offset.lerp(rightHand, const Offset(15, -18), pose.reach)!;
    final leftElbow = Offset(
      -14 - 2 * pose.reach,
      -12 + (leftHand.dy + 15) * .24,
    );
    final rightElbow = Offset(
      15 + 2 * pose.reach,
      -12 + (rightHand.dy + 15) * .30,
    );
    limb([const Offset(-8, -21), leftElbow, leftHand], coat, accent, 5.6);
    limb([const Offset(8, -21), rightElbow, rightHand], coat, accent, 5.6);

    for (final item in [(leftHand, false), (rightHand, true)]) {
      final hand = item.$1;
      final openness = math.max(pose.reach, item.$2 ? wave : 0.0);
      canvas.save();
      canvas.translate(hand.dx, hand.dy);
      if (item.$2 && wave > 0) {
        canvas.rotate(math.sin(pose.seconds * 9) * .28 * wave);
      }
      final palmScale = 1 + pose.reach * .65;
      canvas.scale(palmScale);
      if (pose.reach > .05) {
        final ripple = (pose.seconds * .8) % 1;
        canvas.drawCircle(
          Offset.zero,
          6 + ripple * 5,
          Paint()
            ..color = accent.withValues(alpha: .28 * pose.reach * (1 - ripple))
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8,
        );
        canvas.drawCircle(
          Offset.zero,
          5,
          Paint()..color = accent.withValues(alpha: .10 * pose.reach),
        );
      }
      final palm = Rect.fromCenter(
        center: Offset.zero,
        width: 5.3 + openness,
        height: 6.2 + openness,
      );
      canvas.drawOval(palm.inflate(.65), Paint()..color = coatDeep);
      canvas.drawOval(
        palm,
        Paint()
          ..shader = LinearGradient(
            colors: [skinLight, skin],
          ).createShader(palm),
      );
      if (openness > .01) {
        for (var finger = 0; finger < 4; finger++) {
          final x = -2.1 + finger * 1.35;
          stroke(
            [
              Offset(x, -1),
              Offset(
                x + (finger - 1.5) * .38 * openness,
                -3 - (finger == 0 || finger == 3 ? 2.5 : 3.6) * openness,
              ),
            ],
            skinLight,
            1.1,
          );
        }
        stroke([const Offset(2, .5), Offset(3.7 + openness, -1.2)], skin, 1.5);
        stroke(
          [const Offset(-1.4, .4), const Offset(1, .8)],
          skinDark.withValues(alpha: .5),
          .5,
        );
      } else {
        stroke([const Offset(-1.5, -1), const Offset(1.4, -1)], skinLight, .8);
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(KorlixButtonClimbersPainter oldDelegate) =>
      oldDelegate.seconds != seconds ||
      oldDelegate.buttons != buttons ||
      oldDelegate.visible != visible;
}
