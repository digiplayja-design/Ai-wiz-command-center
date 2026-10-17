import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_wiz_command_center/auth/knova_welcome_player.dart';
import 'package:ai_wiz_command_center/auth/korlix_entry_intro.dart';
import 'package:ai_wiz_command_center/auth/korlix_entry_intro_controller.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_service.dart';

import 'korlix_sound_service_test.dart' as sound;

class IntroPlayer implements KnovaWelcomePlayer {
  int activations = 0, plays = 0, stops = 0;
  bool allowed = true;
  Duration? duration;

  @override
  Future<bool> activate() async {
    activations++;
    return allowed;
  }

  @override
  Future<bool> play(
    Uint8List wav, {
    required double volume,
    required Duration duration,
  }) async {
    plays++;
    this.duration = duration;
    return allowed;
  }

  @override
  void stop() => stops++;

  @override
  void dispose() => stop();
}

class Fixture {
  final player = IntroPlayer();
  final store = sound.MemoryStore();
  late final sounds = KorlixSoundService(
    player: sound.FakePlayer(),
    store: store,
  );
  int loads = 0;
  Completer<Uint8List>? gate;
  bool corrupt = false;
  late final controller = KorlixEntryIntroController(
    sounds: sounds,
    player: player,
    loadClip: () async {
      loads++;
      return gate?.future ??
          (corrupt
              ? Uint8List(12)
              : File(korlixEntryIntroAsset).readAsBytesSync());
    },
  );

  void dispose() {
    controller.dispose();
    sounds.dispose();
  }
}

void main() {
  test('bundled narration is playable mono PCM and about thirty seconds', () {
    final bytes = File(korlixEntryIntroAsset).readAsBytesSync();
    final duration = KorlixEntryIntroController.clipDuration(bytes);
    expect(duration.inMilliseconds, inInclusiveRange(29000, 33000));
    expect(bytes.length, lessThan(1600000));
  });

  testWidgets('reading the welcome never starts playback or loads audio', (
    tester,
  ) async {
    final f = Fixture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: KorlixEntryIntro(controller: f.controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(f.player.activations, 0);
    expect(f.loads, 0);
    await tester.tap(find.byKey(const Key('entry-intro-read')));
    await tester.pumpAndSettle();
    expect(find.text(korlixEntryIntroText), findsOneWidget);
    expect(f.player.activations, 0);
    expect(f.player.plays, 0);
    expect(f.loads, 0);
    await tester.tap(find.byTooltip('Close introduction'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets(
    'explicit play, stop and replay are available without an account',
    (tester) async {
      final f = Fixture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KorlixEntryIntro(controller: f.controller)),
        ),
      );
      await tester.tap(find.byKey(const Key('entry-intro-play')));
      expect(f.player.activations, 1);
      await tester.pumpAndSettle();
      expect(f.player.plays, 1);
      expect(find.text('Stop welcome'), findsOneWidget);
      await tester.tap(find.byKey(const Key('entry-intro-play')));
      await tester.pump();
      expect(f.player.stops, greaterThan(0));
      expect(find.text('Replay welcome'), findsOneWidget);
      await tester.tap(find.byKey(const Key('entry-intro-play')));
      await tester.pumpAndSettle();
      expect(f.player.plays, 2);
      expect(f.loads, 1);
      // The music lead-in extends the complete recording past 31 seconds.
      await tester.pump(const Duration(seconds: 31));
      expect(f.controller.active, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(f.controller.active, isFalse);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  test(
    'saved mute prevents playback even if preference restore is delayed',
    () async {
      final f = Fixture();
      addTearDown(f.dispose);
      f.store.readGate = Completer<String?>();
      final pending = f.controller.listen();
      expect(f.player.activations, 1);
      f.store.readGate!.complete(
        jsonEncode(const KorlixSoundSettings(welcomeVoice: false).toJson()),
      );
      await pending;
      expect(f.player.plays, 0);
      expect(f.loads, 0);
      expect(f.controller.state, KorlixEntryIntroState.muted);
    },
  );

  test('stop while the clip loads prevents delayed playback', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    f.gate = Completer<Uint8List>();
    final pending = f.controller.listen();
    await Future<void>.delayed(Duration.zero);
    f.controller.stop();
    f.gate!.complete(File(korlixEntryIntroAsset).readAsBytesSync());
    await pending;
    expect(f.player.plays, 0);
    expect(f.controller.active, isFalse);
  });

  testWidgets(
    'navigation and backgrounding stop audio without automatic resume',
    (tester) async {
      final f = Fixture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KorlixEntryIntro(controller: f.controller)),
        ),
      );
      await tester.runAsync(f.controller.listen);
      await tester.pump();
      expect(f.controller.active, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(f.controller.active, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(f.player.plays, 1);
      await tester.runAsync(f.controller.listen);
      await tester.pump();
      expect(f.player.plays, 2);
      await tester.pumpWidget(const SizedBox());
      expect(f.controller.active, isFalse);
      f.dispose();
    },
  );

  test('starting another audio session stops the introduction', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    await f.controller.listen();
    expect(f.controller.active, isTrue);
    f.sounds.setQuiet('call', true);
    expect(f.controller.active, isFalse);
    expect(f.controller.state, KorlixEntryIntroState.muted);
    f.sounds.setQuiet('call', false);
    expect(f.player.plays, 1);
  });

  test(
    'corrupt audio and blocked playback fail without starting narration',
    () async {
      final f = Fixture();
      addTearDown(f.dispose);
      f.corrupt = true;
      await f.controller.listen();
      expect(f.controller.state, KorlixEntryIntroState.unavailable);
      expect(f.player.plays, 0);
      f.player.allowed = false;
      await f.controller.listen();
      expect(f.controller.state, KorlixEntryIntroState.blocked);
      expect(f.player.plays, 0);
    },
  );
}
