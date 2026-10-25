import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';

double climberEase(double value) {
  final t = value.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

enum ClimberAction { up, hoist, wave, reach, lower, down, rest }

/// All limb targets are relative to the button's real outside edge. A stroke
/// moves one contact at a time; the other three remain fixed as weight transfers.
@immutable
class KorlixClimberPose {
  const KorlixClimberPose({
    required this.hip,
    required this.handA,
    required this.handB,
    required this.footA,
    required this.footB,
    required this.height,
    required this.button,
    required this.woman,
    required this.action,
    required this.handAPlanted,
    required this.handBPlanted,
    required this.footAPlanted,
    required this.footBPlanted,
    this.wave = 0,
    this.reach = 0,
    required this.seconds,
  });

  static const cycle = 24.8;
  static const womanDelay = 3.6;
  final Offset hip, handA, handB, footA, footB;
  final Rect button;
  final double height, wave, reach, seconds;
  final bool woman, handAPlanted, handBPlanted, footAPlanted, footBPlanted;
  final ClimberAction action;
  double get direction => woman ? -1 : 1;
  double get edge => woman ? button.right : button.left;
  Offset toViewport(Offset point) =>
      Offset(edge + point.dx * direction, button.top + point.dy);
  Offset get position => toViewport(hip);
  Offset get shoulderA => hip + Offset(-height * .07, -height * .29);
  Offset get shoulderB => hip + Offset(height * .10, -height * .30);
  Offset get neck => hip + Offset(height * .025, -height * .36);
  Offset get hipA => hip + Offset(-height * .035, 0);
  Offset get hipB => hip + Offset(height * .045, .5);
  Offset get wristA =>
      handA +
      Offset.lerp(
        Offset(-height * .04, height * .045),
        Offset(0, height * .055),
        math.max(wave, reach),
      )!;
  Offset get wristB => handB + Offset(-height * .04, height * .045);
  Offset get ankleA => footA + Offset(-height * .095, -height * .045);
  Offset get ankleB => footB + Offset(-height * .095, -height * .045);

  // Rounded button corners recede from the straight side. Fingers and toes
  // follow that contour rather than grabbing empty space beside the corner.
  static double edgeInset(double y, double buttonHeight) {
    final radius = math.min(18.0, buttonHeight / 2);
    final end = math.min(y, buttonHeight - y).clamp(0.0, radius);
    return radius -
        math.sqrt(math.max(0.0, radius * radius - math.pow(radius - end, 2)));
  }

  factory KorlixClimberPose.at(
    double seconds,
    Rect button,
    Size viewport, {
    required bool woman,
  }) {
    final time = seconds + (woman ? womanDelay : 0);
    final phase = time % cycle;
    final height = viewport.width < 430 ? 90.0 : 100.0;
    final baseX = -height * .135;
    final low = button.height - 44;
    final high = math.min(36.0, low - 10);
    final travel = math.min(170.0, low - high);
    final bottom = high + travel;
    Offset grip(double y) {
      final safeY = y.clamp(7.0, button.height - 5);
      return Offset(edgeInset(safeY, button.height) + .5, safeY);
    }

    List<Offset> contacts(double hipY) => [
      grip(hipY - height * .56),
      grip(math.max(18, hipY - height * .43)),
      grip(hipY + height * .36 - 4),
      grip(hipY + height * .36 + 7),
    ];
    Offset swing(Offset start, Offset end, double amount, double lift) {
      final p = climberEase(amount);
      return Offset.lerp(start, end, p)! +
          Offset(-math.sin(math.pi * p) * lift, 0);
    }

    double hipY = bottom, hipX = baseX, wave = 0, reach = 0;
    var targets = contacts(bottom);
    var planted = [true, true, true, true];
    var action = ClimberAction.rest;

    if (phase < 7.2 || (phase >= 16 && phase < 23.2)) {
      final ascending = phase < 7.2;
      action = ascending ? ClimberAction.up : ClimberAction.down;
      final local = ascending ? phase : phase - 16;
      final stepCount = math.max(1, (travel / 14).ceil());
      final stepDuration = 7.2 / stepCount;
      final step = (local / stepDuration).floor().clamp(0, stepCount - 1);
      final progress = (local / stepDuration) - step;
      final start = ascending
          ? bottom - travel * step / stepCount
          : high + travel * step / stepCount;
      final end = ascending
          ? start - travel / stepCount
          : start + travel / stepCount;
      final oldContacts = contacts(start), nextContacts = contacts(end);
      final movements = ascending
          ? [
              progress / .22,
              (progress - .64) / .18,
              (progress - .82) / .18,
              (progress - .22) / .16,
            ]
          : [
              (progress - .82) / .18,
              (progress - .22) / .16,
              progress / .22,
              (progress - .64) / .18,
            ];
      targets = [
        for (var i = 0; i < 4; i++)
          swing(oldContacts[i], nextContacts[i], movements[i], i < 2 ? 7 : 9),
      ];
      planted = [
        for (final movement in movements) movement <= 0 || movement >= 1,
      ];
      // Reach with a weight shift on the three remaining holds, then finish the
      // pull with every contact planted. This keeps the reaching arm in range.
      final pull =
          .6 * climberEase(progress / .22) +
          .4 * climberEase((progress - .38) / .26);
      hipY = lerpDouble(start, end, pull)!;
      hipX += math.sin(math.pi * pull) * 2.2;
    } else if (phase < 16) {
      final highContacts = contacts(high);
      final crestContacts = [
        highContacts[0],
        highContacts[1],
        grip(high + height * .27),
        grip(high + height * .30),
      ];
      if (phase < 8.4) {
        action = ClimberAction.hoist;
        final p = (phase - 7.2) / 1.2;
        final liftA = (p / .3).clamp(0.0, 1.0),
            liftB = ((p - .3) / .3).clamp(0.0, 1.0);
        targets = [
          highContacts[0],
          highContacts[1],
          swing(highContacts[2], crestContacts[2], liftA, 6),
          swing(highContacts[3], crestContacts[3], liftB, 6),
        ];
        planted = [
          true,
          true,
          liftA == 0 || liftA == 1,
          liftB == 0 || liftB == 1,
        ];
        hipY = high - 10 * climberEase((p - .35) / .65);
      } else if (phase < 14.8) {
        hipY = high - 10;
        targets = crestContacts;
        if (phase < 11.6) {
          action = ClimberAction.wave;
          final p = phase - 8.4;
          wave = climberEase(p / .55) * (1 - climberEase((p - 2.6) / .6));
          targets[0] = Offset.lerp(
            targets[0],
            Offset(baseX - 7 + math.sin(time * 6) * 2.5, hipY - height * .46),
            wave,
          )!;
          planted[0] = wave == 0;
        } else {
          action = ClimberAction.reach;
          final p = phase - 11.6;
          reach = climberEase(p / .65) * (1 - climberEase((p - 2.5) / .7));
          targets[0] = Offset.lerp(
            targets[0],
            Offset(baseX - 9, hipY - height * .25),
            reach,
          )!;
          planted[0] = reach == 0;
        }
      } else {
        action = ClimberAction.lower;
        final p = (phase - 14.8) / 1.2;
        hipY = high - 10 * (1 - climberEase(p / .55));
        final lowerA = ((p - .5) / .25).clamp(0.0, 1.0),
            lowerB = ((p - .75) / .25).clamp(0.0, 1.0);
        targets = [
          highContacts[0],
          highContacts[1],
          swing(crestContacts[2], highContacts[2], lowerA, 6),
          swing(crestContacts[3], highContacts[3], lowerB, 6),
        ];
        planted = [
          true,
          true,
          lowerA == 0 || lowerA == 1,
          lowerB == 0 || lowerB == 1,
        ];
      }
    }
    return KorlixClimberPose(
      hip: Offset(hipX, hipY),
      handA: targets[0],
      handB: targets[1],
      footA: targets[2],
      footB: targets[3],
      height: height,
      button: button,
      woman: woman,
      action: action,
      wave: wave,
      reach: reach,
      seconds: time,
      handAPlanted: planted[0],
      handBPlanted: planted[1],
      footAPlanted: planted[2],
      footBPlanted: planted[3],
    );
  }
}

/// Two-bone inverse kinematics keeps elbows/knees bent while endpoints remain
/// attached. Normal adult limb lengths prevent elastic or windmilling arms.
Offset climberJoint(
  Offset start,
  Offset end,
  double upper,
  double lower,
  double bend,
) {
  final delta = end - start;
  final distance = delta.distance.clamp(.001, upper + lower - .001);
  final unit = delta / math.max(.001, delta.distance);
  final along =
      (upper * upper - lower * lower + distance * distance) / (2 * distance);
  final side = math.sqrt(math.max(0.0, upper * upper - along * along));
  return start + unit * along + Offset(-unit.dy, unit.dx) * side * bend;
}
