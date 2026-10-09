import 'dart:async';

import 'package:ai_wiz_command_center/camera_ask/camera_flashlight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Only controllable torch capabilities enable the control', () {
    for (final capability in <Object?>[
      null,
      false,
      [],
      [false],
      [true],
      'true',
    ]) {
      final flashlight = CameraFlashlight(
        capability: capability,
        apply: (_) async => fail('Unsupported light must not be requested'),
        readEnabled: () => false,
      );
      expect(flashlight.supported, isFalse);
    }
    for (final capability in <Object>[
      true,
      [false, true],
    ]) {
      expect(
        CameraFlashlight(
          capability: capability,
          apply: (_) async {},
          readEnabled: () => false,
        ).supported,
        isTrue,
      );
    }
  });

  test('Confirmed changes turn the light on and off', () async {
    var actual = false;
    final changes = <bool>[];
    final flashlight = CameraFlashlight(
      capability: true,
      apply: (enabled) async {
        actual = enabled;
        changes.add(enabled);
      },
      readEnabled: () => actual,
    );
    expect(flashlight.enabled, isFalse);
    await flashlight.toggle();
    expect(flashlight.enabled, isTrue);
    await flashlight.toggle();
    expect(flashlight.enabled, isFalse);
    expect(changes, [true, false]);
  });

  test('Unsupported cameras never receive torch constraints', () async {
    final flashlight = CameraFlashlight(
      capability: false,
      apply: (_) async => fail('Must retain ordinary camera capture'),
      readEnabled: () => false,
    );
    await flashlight.toggle();
    expect(flashlight.changing, isFalse);
  });

  test('Duplicate taps wait for the in-flight setting', () async {
    final pending = Completer<void>();
    var calls = 0;
    final flashlight = CameraFlashlight(
      capability: true,
      apply: (_) {
        calls++;
        return pending.future;
      },
      readEnabled: () => true,
    );
    final first = flashlight.toggle();
    expect(flashlight.changing, isTrue);
    expect(flashlight.enabled, isFalse);
    await flashlight.toggle();
    expect(calls, 1);
    pending.complete();
    await first;
    expect(flashlight.changing, isFalse);
    expect(flashlight.enabled, isTrue);
  });

  test(
    'An ignored or unreported constraint never reports the light on',
    () async {
      for (final actual in <bool?>[false, null]) {
        final flashlight = CameraFlashlight(
          capability: true,
          apply: (_) async {},
          readEnabled: () => actual,
        );
        await expectLater(flashlight.toggle(), throwsStateError);
        expect(flashlight.enabled, isFalse);
        expect(flashlight.changing, isFalse);
      }
    },
  );

  test('A failed off command does not falsely report the light off', () async {
    final flashlight = CameraFlashlight(
      capability: true,
      apply: (_) async {},
      readEnabled: () => true,
    );
    await flashlight.toggle();
    await expectLater(flashlight.toggle(), throwsStateError);
    expect(flashlight.enabled, isTrue);
    expect(flashlight.changing, isFalse);
    flashlight.close();
    expect(flashlight.enabled, isFalse);
  });

  test(
    'Rejected commands propagate so the owner can release the camera',
    () async {
      final flashlight = CameraFlashlight(
        capability: true,
        apply: (_) async => throw StateError('Device unavailable'),
        readEnabled: () => false,
      );
      await expectLater(flashlight.toggle(), throwsStateError);
      expect(flashlight.enabled, isFalse);
      expect(flashlight.changing, isFalse);
    },
  );

  test(
    'Leaving during a pending change cannot revive a closed session',
    () async {
      final pending = Completer<void>();
      var calls = 0;
      final flashlight = CameraFlashlight(
        capability: true,
        apply: (_) {
          calls++;
          return pending.future;
        },
        readEnabled: () => fail('Do not inspect a released track'),
      );
      final change = flashlight.toggle();
      flashlight.close();
      pending.complete();
      await change;
      await flashlight.toggle();
      expect(calls, 1);
      expect(flashlight.enabled, isFalse);
      expect(flashlight.changing, isFalse);
    },
  );
}
