import 'dart:async';

import 'package:ai_wiz_command_center/sounds/korlix_sound_actions.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_player.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Player implements KorlixSoundPlayer {
  @override
  bool ready = false;
  final events = <String>[];
  Completer<bool>? activation;
  bool activationThrows = false, playbackThrows = false;

  @override
  Future<bool> activate() {
    events.add('activate');
    if (activationThrows) throw StateError('Audio unavailable');
    return (activation?.future ?? Future.value(true)).then((value) {
      ready = value;
      return value;
    });
  }

  @override
  Future<bool> play(
    Uint8List wav, {
    required double volume,
    required Duration duration,
    required String channel,
    bool loop = false,
  }) async {
    events.add('play');
    if (playbackThrows) throw StateError('Output unavailable');
    return true;
  }

  @override
  void stop(String channel) {}
  @override
  void stopAll() {}
  @override
  void dispose() {}
}

void main() {
  testWidgets('disabled callback stays null and does not activate audio', (
    t,
  ) async {
    final player = _Player();
    final service = KorlixSoundService(player: player);
    addTearDown(service.dispose);
    expect(korlixSoundAction(null, service: service), isNull);
    expect(player.events, isEmpty);
  });

  testWidgets(
    'requests activation in gesture and runs action without waiting',
    (t) async {
      final player = _Player()..activation = Completer<bool>();
      final service = KorlixSoundService(player: player);
      addTearDown(service.dispose);
      final action = korlixSoundAction(
        () => player.events.add('action'),
        service: service,
      )!;
      action();
      expect(player.events, ['activate', 'action']);
      await t.pump(const Duration(milliseconds: 100));
      player.activation!.complete(true);
      await t.pump();
      expect(player.events, ['activate', 'action', 'play']);
    },
  );

  testWidgets('late activation never plays a delayed click', (t) async {
    final player = _Player()..activation = Completer<bool>();
    final service = KorlixSoundService(player: player);
    addTearDown(service.dispose);
    var calls = 0;
    korlixSoundAction(() => calls++, service: service)!();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 275)),
    );
    player.activation!.complete(true);
    await t.pump();
    expect(calls, 1);
    expect(player.events, ['activate']);
  });

  testWidgets('blocked, throwing and failing audio never cancel the action', (
    t,
  ) async {
    for (final mode in [
      'blocked',
      'activation throw',
      'playback throw',
      'future error',
    ]) {
      final player = _Player()
        ..activationThrows = mode == 'activation throw'
        ..playbackThrows = mode == 'playback throw';
      if (mode == 'blocked' || mode == 'future error') {
        player.activation = Completer<bool>();
      }
      final service = KorlixSoundService(player: player);
      var calls = 0;
      korlixSoundAction(() => calls++, service: service)!();
      if (mode == 'blocked') player.activation!.complete(false);
      if (mode == 'future error') {
        player.activation!.completeError(StateError('Blocked'));
      }
      await t.pump();
      expect(calls, 1, reason: mode);
      expect(t.takeException(), isNull, reason: mode);
      service.dispose();
    }
  });

  testWidgets('action errors are not swallowed by sound error handling', (
    t,
  ) async {
    final player = _Player();
    final service = KorlixSoundService(player: player);
    addTearDown(service.dispose);
    expect(
      korlixSoundAction(
        () => throw StateError('Real action error'),
        service: service,
      ),
      throwsStateError,
    );
    await t.pump();
  });

  testWidgets(
    'native tap, Enter and Space sound only after activation; canceled drag and typing stay quiet',
    (t) async {
      final player = _Player();
      final service = KorlixSoundService(
        player: player,
        now: () => t.binding.clock.now(),
      );
      final focus = FocusNode();
      addTearDown(service.dispose);
      addTearDown(focus.dispose);
      var calls = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                TextButton(
                  focusNode: focus,
                  onPressed: korlixSoundAction(() => calls++, service: service),
                  child: const Text('Open tool'),
                ),
                TextButton(
                  onPressed: korlixSoundAction(null, service: service),
                  child: const Text('Disabled'),
                ),
                const TextField(),
                const SizedBox(height: 1800),
              ],
            ),
          ),
        ),
      );
      final button = find.text('Open tool');
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(t.getCenter(button));
      await t.pump();
      final canceled = await t.startGesture(t.getCenter(button));
      await canceled.cancel();
      await mouse.removePointer();
      await t.tap(find.text('Disabled'));
      await t.enterText(find.byType(TextField), 'No typing sounds');
      await t.pump();
      expect(player.events, isEmpty);
      await t.drag(button, const Offset(0, -150));
      await t.pumpAndSettle();
      expect(player.events, isEmpty);
      await t.drag(find.byType(ListView), const Offset(0, 500));
      await t.pumpAndSettle();
      await t.tap(button);
      await t.pump(const Duration(milliseconds: 100));
      focus.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump(const Duration(milliseconds: 100));
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(calls, 3);
      expect(player.events.where((e) => e == 'play').length, 3);
    },
  );
}
