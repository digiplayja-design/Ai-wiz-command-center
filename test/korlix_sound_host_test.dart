import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_host.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_service.dart';

import 'korlix_sound_service_test.dart' show FakePlayer, MemoryStore;

void main() {
  testWidgets('touch release retries activation blocked on touch-down', (
    t,
  ) async {
    final blocked = Completer<bool>()..complete(false);
    final player = FakePlayer()..activationGate = blocked;
    final service = KorlixSoundService(player: player, store: MemoryStore());
    await t.pumpWidget(
      MaterialApp(
        home: KorlixSoundHost(
          service: service,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await t.pump();
    final touch = await t.startGesture(t.getCenter(find.byType(Scaffold)));
    await t.pump();
    expect(player.activations, 1);
    expect(service.ready, isFalse);
    player.activationGate = null;
    await touch.up();
    await t.pump();
    expect(player.activations, 2);
    expect(service.ready, isTrue);
    expect(player.plays, isEmpty);
    await t.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets('host restores preferences and unlocks silently on a gesture', (
    t,
  ) async {
    final player = FakePlayer();
    final service = KorlixSoundService(player: player, store: MemoryStore());
    await t.pumpWidget(
      MaterialApp(
        home: KorlixSoundHost(
          service: service,
          child: const Scaffold(body: TextField()),
        ),
      ),
    );
    await t.pump();
    expect(player.activations, 0);
    await t.tap(find.byType(TextField));
    await t.pump();
    expect(player.activations, 1);
    expect(
      player.plays,
      isEmpty,
      reason: 'Typing and focus changes are silent.',
    );
    await t.enterText(find.byType(TextField), 'A private draft');
    await t.pump();
    expect(player.plays, isEmpty);
    await t.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets('backgrounding and removing host stop a ring without replay', (
    t,
  ) async {
    final player = FakePlayer();
    final service = KorlixSoundService(player: player, store: MemoryStore());
    await t.pumpWidget(
      MaterialApp(
        home: KorlixSoundHost(
          service: service,
          child: const Scaffold(body: Text('Korlix')),
        ),
      ),
    );
    await t.pump();
    await service.activate();
    service.setRinging('incoming', true, callId: 'call');
    await t.pump();
    expect(player.active, contains('ring'));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await t.pump();
    expect(player.active, isEmpty);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(player.active, isEmpty);
    service.setRinging('another', true, callId: 'another-call');
    await t.pump();
    expect(player.active, contains('ring'));
    await t.pumpWidget(const SizedBox());
    expect(player.active, isEmpty);
    service.dispose();
  });

  testWidgets('muted or recording sessions do not attempt gesture activation', (
    t,
  ) async {
    final player = FakePlayer();
    final service = KorlixSoundService(player: player, store: MemoryStore());
    await service.update(service.settings.copyWith(enabled: false));
    await t.pumpWidget(
      MaterialApp(
        home: KorlixSoundHost(
          service: service,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await t.pump();
    await t.tap(find.byType(Scaffold));
    await t.pump();
    expect(player.activations, 0);
    await service.update(service.settings.copyWith(enabled: true));
    service.setQuiet('recorder', true);
    await t.tap(find.byType(Scaffold));
    await t.pump();
    expect(player.activations, 0);
    await t.pumpWidget(const SizedBox());
    service.dispose();
  });
}
