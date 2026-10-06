import 'dart:async';

import 'package:ai_wiz_command_center/characters/character_catalog.dart';
import 'package:ai_wiz_command_center/characters/character_orbit.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_host.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'korlix_sound_service_test.dart' show FakePlayer, MemoryStore;

Widget orbit(KorlixSoundService service) => MaterialApp(
  home: KorlixSoundHost(
    service: service,
    child: Scaffold(
      body: SingleChildScrollView(
        child: KorlixCharacterOrbit(
          selectedId: 'jj',
          availableIds: korlixCharacters.map((c) => c.id).toSet(),
          soundService: service,
          onSelected: (_) async {},
        ),
      ),
    ),
  ),
);

Future<TestGesture> startSpin(WidgetTester t) async {
  final touch = await t.startGesture(
    t.getCenter(find.byKey(const ValueKey('character-orbit-drag'))),
  );
  await touch.moveBy(const Offset(-30, 0));
  await touch.moveBy(const Offset(-90, 0));
  await t.pump();
  return touch;
}

void main() {
  for (final pending in [false, true]) {
    testWidgets(
      'first swipe retries on release when drag activation is ${pending ? 'pending' : 'blocked'}',
      (t) async {
        final gate = Completer<bool>();
        if (!pending) gate.complete(false);
        final player = FakePlayer()..activationGate = gate;
        final service = KorlixSoundService(
          player: player,
          store: MemoryStore(),
          now: () => t.binding.clock.now(),
        );
        await t.pumpWidget(orbit(service));
        await t.pump();
        final touch = await startSpin(t);
        expect(player.plays, isEmpty);
        player.activationGate = null;
        await touch.up();
        await t.pump();
        expect(player.plays, hasLength(1));
        expect(player.plays.single.volume, closeTo(.65 * .0175, .000001));
        if (pending) gate.complete(true);
        await t.pumpAndSettle();
        expect(player.plays, hasLength(1), reason: 'No late duplicate sweep.');
        await t.pumpWidget(const SizedBox());
        service.dispose();
      },
    );
  }

  testWidgets('an unlocked long swipe plays once including its final snap', (
    t,
  ) async {
    final player = FakePlayer()..ready = true;
    final service = KorlixSoundService(
      player: player,
      store: MemoryStore(),
      now: () => t.binding.clock.now(),
    );
    await t.pumpWidget(orbit(service));
    await t.pump();
    final touch = await startSpin(t);
    expect(player.plays, hasLength(1));
    await t.pump(const Duration(milliseconds: 600));
    await touch.moveBy(const Offset(-30, 0));
    await touch.up();
    await t.pumpAndSettle();
    expect(player.plays, hasLength(1));
    await t.pumpWidget(const SizedBox());
    service.dispose();
  });

  for (final teardown in [false, true]) {
    testWidgets(
      'pending swipe stays silent after ${teardown ? 'removal' : 'cancellation'}',
      (t) async {
        final gate = Completer<bool>();
        final player = FakePlayer()..activationGate = gate;
        final service = KorlixSoundService(
          player: player,
          store: MemoryStore(),
        );
        await t.pumpWidget(orbit(service));
        await t.pump();
        final touch = await startSpin(t);
        if (teardown) await t.pumpWidget(const SizedBox());
        await touch.cancel();
        gate.complete(true);
        await t.pumpAndSettle();
        expect(player.plays, isEmpty);
        await t.pumpWidget(const SizedBox());
        service.dispose();
      },
    );
  }
}
