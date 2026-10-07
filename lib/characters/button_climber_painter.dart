import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'button_climber_motion.dart';
export 'button_climber_motion.dart' show KorlixClimberPose, ClimberAction;

/// Photographic human cutouts are articulated around anatomical joints. Limb
/// endpoints are solved against the actual rounded button border, not a sine
/// wave attached to a vertically sliding character.
class KorlixButtonClimbersPainter extends CustomPainter {
  KorlixButtonClimbersPainter({
    required this.seconds,
    required this.buttons,
    required this.visible,
    required this.artwork,
  }) : super(repaint: Listenable.merge([seconds, buttons, visible, artwork]));
  final ValueListenable<double> seconds;
  final ValueListenable<List<Rect>> buttons;
  final ValueListenable<bool> visible;
  final ValueListenable<ui.Image?> artwork;

  @override
  void paint(Canvas canvas, Size size) {
    final image = artwork.value;
    if (!visible.value || image == null || buttons.value.isEmpty) return;
    final ledges = buttons.value;
    final left = ledges
        .where((r) => r.left >= 28 && r.center.dx <= size.width / 2 + 4)
        .toList();
    final right = ledges
        .where(
          (r) =>
              r.right <= size.width - 28 && r.center.dx >= size.width / 2 - 4,
        )
        .toList();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final woman in [false, true]) {
      final choices = woman ? right : left;
      if (choices.isEmpty) continue;
      final pose = KorlixClimberPose.at(
        seconds.value,
        choices.first,
        size,
        woman: woman,
      );
      canvas.save();
      canvas.translate(pose.edge, pose.button.top);
      canvas.scale(pose.direction, 1);
      _person(canvas, image, pose, woman ? _woman : _man);
      canvas.restore();
    }
    canvas.restore();
  }

  void _person(
    Canvas canvas,
    ui.Image image,
    KorlixClimberPose pose,
    _HumanRig rig,
  ) {
    final scale = pose.height / rig.height;
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;
    void part(_BodyPart part, Offset a, Offset b, {double width = 1}) {
      final source = part.end - part.start, target = b - a;
      canvas.save();
      canvas.translate(a.dx, a.dy);
      canvas.rotate(math.atan2(target.dy, target.dx));
      canvas.scale(target.distance / source.distance, scale * width);
      canvas.rotate(-math.atan2(source.dy, source.dx));
      canvas.translate(-part.start.dx, -part.start.dy);
      canvas.clipPath(part.clip, doAntiAlias: true);
      canvas.drawImage(image, Offset.zero, paint);
      canvas.restore();
    }

    for (final contact in [
      (pose.handA, pose.handAPlanted, true),
      (pose.handB, pose.handBPlanted, true),
      (pose.footA, pose.footAPlanted, false),
      (pose.footB, pose.footBPlanted, false),
    ]) {
      if (!contact.$2) continue;
      canvas.drawOval(
        Rect.fromCenter(
          center: contact.$1 + const Offset(1.5, 1),
          width: contact.$3 ? 4 : 5,
          height: contact.$3 ? 7 : 3,
        ),
        Paint()..color = Colors.black.withValues(alpha: .32),
      );
    }

    final elbowA = climberJoint(
      pose.shoulderA,
      pose.wristA,
      pose.height * .17,
      pose.height * .16,
      -1,
    );
    final elbowB = climberJoint(
      pose.shoulderB,
      pose.wristB,
      pose.height * .17,
      pose.height * .16,
      -1,
    );
    final kneeA = climberJoint(
      pose.hipA,
      pose.ankleA,
      pose.height * .225,
      pose.height * .215,
      1,
    );
    final kneeB = climberJoint(
      pose.hipB,
      pose.ankleB,
      pose.height * .225,
      pose.height * .215,
      1,
    );

    // The far limbs are behind the torso. Overlapping joint caps avoid visible
    // seams in the original skin/fabric as elbows and knees articulate.
    part(rig.armB, pose.shoulderB, elbowB);
    part(rig.forearmB, elbowB, pose.wristB);
    part(rig.thighB, pose.hipB, kneeB);
    part(rig.shinB, kneeB, pose.ankleB);
    part(rig.shoeB, pose.ankleB, pose.footB);
    part(rig.thighA, pose.hipA, kneeA);
    part(rig.shinA, kneeA, pose.ankleA);
    part(rig.shoeA, pose.ankleA, pose.footA);
    part(
      rig.torso,
      pose.hip,
      pose.neck,
      width: .78 + .12 * math.max(pose.wave, pose.reach),
    );
    part(
      rig.head,
      pose.neck,
      pose.neck + Offset(1.2 * (1 - pose.wave), -pose.height * .105),
    );
    part(rig.armA, pose.shoulderA, elbowA);
    part(rig.forearmA, elbowA, pose.wristA);
    part(rig.handB, pose.wristB, pose.handB);
    part(rig.handA, pose.wristA, pose.handA, width: 1 + pose.reach * .45);

    // Fingers curl over the lip, over the textured palm, so the grip reads at
    // phone scale. Contact shadows remain attached to the button underneath.
    final skin = pose.woman ? const Color(0xFFD7A075) : const Color(0xFFBE875D);
    for (final contact in [
      (pose.handA, pose.handAPlanted),
      (pose.handB, pose.handBPlanted),
    ]) {
      if (!contact.$2) continue;
      for (var finger = 0; finger < 3; finger++) {
        final p = contact.$1 + Offset(0, finger * 1.3 - 1);
        final path = Path()
          ..moveTo(p.dx - 1.4, p.dy)
          ..quadraticBezierTo(p.dx + 2.6, p.dy - 1.2, p.dx + 2.1, p.dy + 1);
        canvas.drawPath(
          path,
          Paint()
            ..color = skin
            ..style = PaintingStyle.stroke
            ..strokeWidth = .95
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(KorlixButtonClimbersPainter old) =>
      old.seconds != seconds ||
      old.buttons != buttons ||
      old.visible != visible ||
      old.artwork != artwork;
}

class _BodyPart {
  _BodyPart(this.start, this.end, this.clip);
  factory _BodyPart.limb(Offset start, Offset end, double radius) {
    final vector = end - start;
    final normal = Offset(-vector.dy, vector.dx) / vector.distance * radius;
    final extension = vector / vector.distance * radius * .6;
    return _BodyPart(
      start,
      end,
      Path()
        ..moveTo((start + normal).dx, (start + normal).dy)
        ..lineTo((end + normal).dx, (end + normal).dy)
        ..quadraticBezierTo(
          (end + extension).dx,
          (end + extension).dy,
          (end - normal).dx,
          (end - normal).dy,
        )
        ..lineTo((start - normal).dx, (start - normal).dy)
        ..quadraticBezierTo(
          (start - extension).dx,
          (start - extension).dy,
          (start + normal).dx,
          (start + normal).dy,
        )
        ..close(),
    );
  }
  final Offset start, end;
  final Path clip;
}

Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);
Path _rect(double x, double y, double w, double h) =>
    Path()..addRect(Rect.fromLTWH(x, y, w, h));

class _HumanRig {
  const _HumanRig({
    required this.height,
    required this.torso,
    required this.head,
    required this.armA,
    required this.forearmA,
    required this.handA,
    required this.armB,
    required this.forearmB,
    required this.handB,
    required this.thighA,
    required this.shinA,
    required this.shoeA,
    required this.thighB,
    required this.shinB,
    required this.shoeB,
  });
  final double height;
  final _BodyPart torso, head, armA, forearmA, handA, armB, forearmB, handB;
  final _BodyPart thighA, shinA, shoeA, thighB, shinB, shoeB;
}

// Anatomical source joints measured on the unmodified 1536 x 1024 alpha atlas.
final _man = _HumanRig(
  height: 963,
  torso: _BodyPart(
    const Offset(426, 533),
    const Offset(418, 184),
    _polygon(const [
      Offset(317, 207),
      Offset(378, 169),
      Offset(459, 169),
      Offset(518, 208),
      Offset(529, 306),
      Offset(519, 465),
      Offset(537, 533),
      Offset(502, 559),
      Offset(448, 573),
      Offset(425, 555),
      Offset(397, 574),
      Offset(314, 553),
      Offset(318, 481),
      Offset(322, 306),
    ]),
  ),
  head: _BodyPart(
    const Offset(418, 184),
    const Offset(416, 83),
    _rect(350, 10, 133, 187),
  ),
  armA: _BodyPart.limb(const Offset(302, 250), const Offset(229, 369), 37),
  forearmA: _BodyPart.limb(const Offset(229, 369), const Offset(167, 490), 25),
  handA: _BodyPart(
    const Offset(167, 490),
    const Offset(146, 540),
    _polygon(const [
      Offset(151, 474),
      Offset(185, 495),
      Offset(168, 542),
      Offset(140, 580),
      Offset(121, 577),
      Offset(136, 515),
    ]),
  ),
  armB: _BodyPart.limb(const Offset(536, 250), const Offset(609, 370), 36),
  forearmB: _BodyPart.limb(const Offset(609, 370), const Offset(674, 490), 25),
  handB: _BodyPart(
    const Offset(674, 490),
    const Offset(690, 538),
    _polygon(const [
      Offset(652, 479),
      Offset(680, 476),
      Offset(704, 523),
      Offset(722, 577),
      Offset(700, 581),
      Offset(670, 540),
    ]),
  ),
  thighA: _BodyPart.limb(const Offset(372, 538), const Offset(348, 734), 52),
  shinA: _BodyPart.limb(const Offset(348, 734), const Offset(330, 911), 40),
  shoeA: _BodyPart(
    const Offset(330, 911),
    const Offset(302, 963),
    _rect(270, 894, 96, 89),
  ),
  thighB: _BodyPart.limb(const Offset(481, 538), const Offset(513, 735), 49),
  shinB: _BodyPart.limb(const Offset(513, 735), const Offset(528, 912), 40),
  shoeB: _BodyPart(
    const Offset(528, 912),
    const Offset(554, 963),
    _rect(489, 894, 96, 89),
  ),
);

final _woman = _HumanRig(
  height: 911,
  torso: _BodyPart(
    const Offset(1119, 537),
    const Offset(1115, 241),
    _polygon(const [
      Offset(1015, 255),
      Offset(1069, 223),
      Offset(1155, 223),
      Offset(1218, 261),
      Offset(1203, 328),
      Offset(1193, 437),
      Offset(1220, 545),
      Offset(1166, 565),
      Offset(1121, 551),
      Offset(1094, 568),
      Offset(1010, 553),
      Offset(1023, 470),
      Offset(1032, 336),
    ]),
  ),
  head: _BodyPart(
    const Offset(1115, 241),
    const Offset(1118, 146),
    _rect(1045, 63, 132, 183),
  ),
  armA: _BodyPart.limb(const Offset(1017, 276), const Offset(956, 390), 30),
  forearmA: _BodyPart.limb(const Offset(956, 390), const Offset(882, 505), 22),
  handA: _BodyPart(
    const Offset(882, 505),
    const Offset(863, 547),
    _polygon(const [
      Offset(871, 489),
      Offset(901, 507),
      Offset(874, 554),
      Offset(845, 582),
      Offset(825, 580),
      Offset(850, 532),
    ]),
  ),
  armB: _BodyPart.limb(const Offset(1213, 276), const Offset(1277, 392), 31),
  forearmB: _BodyPart.limb(
    const Offset(1277, 392),
    const Offset(1357, 506),
    22,
  ),
  handB: _BodyPart(
    const Offset(1357, 506),
    const Offset(1380, 545),
    _polygon(const [
      Offset(1338, 501),
      Offset(1362, 489),
      Offset(1393, 532),
      Offset(1413, 583),
      Offset(1393, 585),
      Offset(1360, 553),
    ]),
  ),
  thighA: _BodyPart.limb(const Offset(1065, 544), const Offset(1033, 733), 47),
  shinA: _BodyPart.limb(const Offset(1033, 733), const Offset(1009, 916), 35),
  shoeA: _BodyPart(
    const Offset(1009, 916),
    const Offset(989, 963),
    _rect(958, 897, 86, 88),
  ),
  thighB: _BodyPart.limb(const Offset(1170, 544), const Offset(1200, 734), 43),
  shinB: _BodyPart.limb(const Offset(1200, 734), const Offset(1221, 916), 35),
  shoeB: _BodyPart(
    const Offset(1221, 916),
    const Offset(1240, 963),
    _rect(1186, 897, 84, 88),
  ),
);
