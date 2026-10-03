import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_player.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_service.dart';

class MemoryStore implements KorlixSoundStore {
  String? value;
  Completer<String?>? readGate;
  Completer<bool>? writeGate;
  bool fail = false;
  final writes = <String>[];
  @override
  Future<String?> read() async => readGate == null ? value : readGate!.future;
  @override
  Future<bool> write(String next) async {
    writes.add(next);
    final gate = writeGate;
    writeGate = null;
    if (gate != null && !await gate.future) return false;
    if (fail) throw StateError('storage unavailable');
    value = next;
    return true;
  }
}

class FakePlayer implements KorlixSoundPlayer {
  @override
  bool ready = false;
  bool disposed = false;
  bool failPlay = false;
  Completer<bool>? activationGate;
  Completer<bool>? playGate;
  int activations = 0;
  final plays =
      <({String channel, Duration duration, double volume, bool loop})>[];
  final active = <String>{};
  final stopped = <String>[];
  final generation = <String, int>{};
  @override
  Future<bool> activate() async {
    activations++;
    final okay = activationGate == null ? true : await activationGate!.future;
    if (!disposed) ready = okay;
    return ready;
  }

  @override
  Future<bool> play(
    Uint8List wav, {
    required double volume,
    required Duration duration,
    required String channel,
    bool loop = false,
  }) async {
    stop(channel);
    final revision = generation[channel];
    plays.add((
      channel: channel,
      duration: duration,
      volume: volume,
      loop: loop,
    ));
    if (playGate != null) await playGate!.future;
    if (revision != generation[channel] || disposed) return true;
    if (failPlay) return false;
    active.add(channel);
    return true;
  }

  @override
  void stop(String channel) {
    generation[channel] = (generation[channel] ?? 0) + 1;
    stopped.add(channel);
    active.remove(channel);
  }

  @override
  void stopAll() {
    for (final channel in ['effect', 'ring', 'preview']) {
      stop(channel);
    }
  }

  @override
  void dispose() {
    disposed = true;
    stopAll();
  }
}

void main() {
  test(
    'preferences round trip, bound malformed values, and wrap local quiet hours',
    () {
      const settings = KorlixSoundSettings(quietHours: true);
      expect(
        KorlixSoundSettings.fromJson(settings.toJson()).toJson(),
        settings.toJson(),
      );
      expect(settings.isQuietAt(DateTime(2026, 10, 3, 23)), isTrue);
      expect(settings.isQuietAt(DateTime(2026, 10, 4, 6, 59)), isTrue);
      expect(settings.isQuietAt(DateTime(2026, 10, 4, 7)), isFalse);
      expect(settings.isQuietAt(DateTime(2026, 10, 4, 21, 59)), isFalse);
      expect(
        settings
            .copyWith(quietStartMinute: 60, quietEndMinute: 60)
            .isQuietAt(DateTime(2026, 10, 4, 12)),
        isTrue,
      );
      final malformed = KorlixSoundSettings.fromJson({
        'version': 1,
        'volume': 9,
        'quietStartMinute': -2,
        'pack': 'unknown',
      });
      expect(malformed.volume, 1);
      expect(malformed.quietStartMinute, 0);
      expect(malformed.pack, KorlixSoundPack.signature);
      expect(
        () => KorlixSoundSettings.fromJson({'version': 50}),
        throwsFormatException,
      );
    },
  );

  test(
    'corrupt storage recovers and newest update wins over a delayed restore',
    () async {
      final store = MemoryStore()..value = 'broken json';
      final service = KorlixSoundService(player: FakePlayer(), store: store);
      await service.restore();
      expect(service.storageError, isNotNull);
      expect(
        await service.update(
          service.settings.copyWith(pack: KorlixSoundPack.soft),
        ),
        isTrue,
      );
      expect(service.storageError, isNull);
      service.dispose();

      final gate = Completer<String?>();
      final delayed = MemoryStore()..readGate = gate;
      final raced = KorlixSoundService(player: FakePlayer(), store: delayed);
      final restoration = raced.restore();
      await raced.update(const KorlixSoundSettings(enabled: false));
      gate.complete(jsonEncode(const KorlixSoundSettings().toJson()));
      await restoration;
      expect(raced.settings.enabled, isFalse);
      raced.dispose();
    },
  );

  test(
    'writes serialize and failure is recoverable without reverting live settings',
    () async {
      final first = Completer<bool>();
      final store = MemoryStore()..writeGate = first;
      final service = KorlixSoundService(player: FakePlayer(), store: store);
      final update1 = service.update(const KorlixSoundSettings(volume: .2));
      final update2 = service.update(const KorlixSoundSettings(volume: .8));
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, hasLength(1));
      first.complete(true);
      expect(await update1, isTrue);
      expect(await update2, isTrue);
      expect(jsonDecode(store.value!)['volume'], .8);
      store.fail = true;
      expect(
        await service.update(service.settings.copyWith(enabled: false)),
        isFalse,
      );
      expect(service.settings.enabled, isFalse);
      expect(service.storageError, isNotNull);
      store.fail = false;
      expect(
        await service.update(service.settings.copyWith(enabled: true)),
        isTrue,
      );
      expect(service.storageError, isNull);
      service.dispose();
    },
  );

  test(
    'activation is immediate and late completion never queues old sounds',
    () async {
      final gate = Completer<bool>();
      final player = FakePlayer()..activationGate = gate;
      final service = KorlixSoundService(player: player, store: MemoryStore());
      final activation = service.activate();
      expect(player.activations, 1);
      await service.play(KorlixSound.message, eventId: 'not-ready');
      service.clearSession();
      gate.complete(true);
      expect(await activation, isFalse);
      expect(player.plays, isEmpty);
      service.setQuiet('mic', true);
      expect(await service.activate(), isFalse);
      expect(player.activations, 1);
      service.dispose();
    },
  );

  test(
    'event dedup, click cooldown, message flood control and category mute',
    () async {
      var now = DateTime(2026, 10, 3, 12);
      final player = FakePlayer();
      final service = KorlixSoundService(
        player: player,
        store: MemoryStore(),
        now: () => now,
      );
      await service.activate();
      await service.play(KorlixSound.click);
      await service.play(KorlixSound.click);
      expect(player.plays, hasLength(1));
      expect(player.plays.single.volume, closeTo(.1625, .0001));
      now = now.add(const Duration(milliseconds: 80));
      await service.play(KorlixSound.click);
      await service.play(KorlixSound.message, eventId: 'one');
      await service.play(KorlixSound.message, eventId: 'two');
      expect(player.plays, hasLength(3));
      now = now.add(const Duration(seconds: 2));
      await service.play(KorlixSound.message, eventId: 'one');
      await service.play(KorlixSound.message, eventId: 'two');
      expect(player.plays, hasLength(3));
      await service.play(KorlixSound.message, eventId: 'three');
      expect(player.plays, hasLength(4));
      await service.update(service.settings.copyWith(bells: false));
      await service.play(KorlixSound.bell);
      await service.play(KorlixSound.success);
      await service.play(KorlixSound.warning);
      expect(player.plays, hasLength(4));
      service.dispose();
    },
  );

  test(
    'muted events and blocked microphone/background events never replay',
    () async {
      final player = FakePlayer();
      final service = KorlixSoundService(player: player, store: MemoryStore());
      await service.activate();
      await service.update(service.settings.copyWith(enabled: false));
      await service.play(KorlixSound.message, eventId: 'muted');
      await service.update(service.settings.copyWith(enabled: true));
      await service.play(KorlixSound.message, eventId: 'muted');
      service.setQuiet('mic', true);
      service.setQuiet('call', true);
      service.setQuiet('mic', false);
      expect(service.quiet, isTrue);
      await service.play(KorlixSound.bell);
      service.setQuiet('call', false);
      service.setForeground(false);
      await service.play(KorlixSound.message, eventId: 'hidden');
      service.setForeground(true);
      await service.play(KorlixSound.message, eventId: 'hidden');
      expect(player.plays, isEmpty);
      service.dispose();
    },
  );

  testWidgets(
    'ring owners share one loop, incoming wins and expiry survives handoff',
    (tester) async {
      var now = DateTime(2026, 10, 3, 12);
      final player = FakePlayer();
      final service = KorlixSoundService(
        player: player,
        store: MemoryStore(),
        now: () => now,
      );
      await service.activate();
      service.setRinging('banner', true, callId: 'one');
      await tester.pump();
      service.setRinging('screen', true, callId: 'one');
      expect(player.plays, hasLength(1));
      service.setRinging('banner', false);
      expect(player.active, contains('ring'));
      now = now.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 20));
      service.setRinging('screen', false);
      service.setRinging('screen2', true, callId: 'one');
      await tester.pump();
      expect(player.plays.last.duration, const Duration(seconds: 25));
      service.setRinging('outgoing', true, callId: 'two', outgoing: true);
      expect(player.plays, hasLength(2)); // Existing incoming remains primary.
      service.setRinging('screen2', false);
      await tester.pump();
      expect(player.plays, hasLength(3));
      service.setRinging('new-incoming', true, callId: 'three');
      await tester.pump();
      expect(player.plays, hasLength(4));
      service.setRinging('outgoing', false);
      now = now.add(const Duration(seconds: 45));
      await tester.pump(const Duration(seconds: 45));
      expect(player.active, isNot(contains('ring')));
      service.setRinging('repeated', true, callId: 'three');
      await tester.pump();
      expect(player.plays, hasLength(4));
      service.dispose();
    },
  );

  testWidgets('mute, background and quiet stop rings without resume replay', (
    tester,
  ) async {
    final player = FakePlayer();
    final service = KorlixSoundService(player: player, store: MemoryStore());
    await service.activate();
    service.setRinging('banner', true, callId: 'one');
    await tester.pump();
    service.setQuiet('mic', true);
    expect(player.active, isEmpty);
    service.setQuiet('mic', false);
    service.setRinging('screen', true, callId: 'one');
    await tester.pump();
    expect(player.plays, hasLength(1));
    service.setRinging('banner', true, callId: 'two');
    await tester.pump();
    service.setForeground(false);
    service.setForeground(true);
    service.setRinging('banner', true, callId: 'two');
    await tester.pump();
    expect(player.plays, hasLength(2));
    service.setRinging('banner', true, callId: 'three');
    await tester.pump();
    await service.update(service.settings.copyWith(calls: false));
    await service.update(service.settings.copyWith(calls: true));
    service.setRinging('banner', true, callId: 'three');
    await tester.pump();
    expect(player.plays, hasLength(3));
    expect(player.active, isEmpty);
    service.dispose();
  });

  testWidgets('quiet-hour boundary stops a ringing call and never queues it', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 3, 21, 59, 50);
    final player = FakePlayer();
    final service = KorlixSoundService(
      player: player,
      store: MemoryStore(),
      now: () => now,
    );
    await service.activate();
    await service.update(service.settings.copyWith(quietHours: true));
    service.setRinging('banner', true, callId: 'boundary');
    await tester.pump();
    expect(player.active, contains('ring'));
    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(player.active, isEmpty);
    await service.update(service.settings.copyWith(quietHours: false));
    service.setRinging('banner', true, callId: 'boundary');
    await tester.pump();
    expect(player.plays, hasLength(1));
    service.dispose();
  });

  testWidgets(
    'previews obey master mute, last at most three seconds, and do not replace calls',
    (tester) async {
      final player = FakePlayer();
      final service = KorlixSoundService(player: player, store: MemoryStore());
      await service.activate();
      await service.update(service.settings.copyWith(calls: false));
      await service.preview(KorlixSound.ringtone);
      expect(player.plays.single.duration, const Duration(seconds: 3));
      expect(player.plays.single.loop, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(player.active, isEmpty);
      await service.update(service.settings.copyWith(enabled: false));
      await service.preview(KorlixSound.bell);
      expect(player.plays, hasLength(1));
      await service.update(
        service.settings.copyWith(enabled: true, calls: true),
      );
      service.setRinging('banner', true, callId: 'call');
      await tester.pump();
      await service.preview(KorlixSound.bell);
      expect(player.plays, hasLength(2));
      service.clearSession();
      expect(player.active, isEmpty);
      expect(service.settings.enabled, isTrue);
      service.dispose();
    },
  );

  test(
    'session changes preserve active microphone leases until owners release',
    () async {
      final player = FakePlayer();
      final service = KorlixSoundService(player: player, store: MemoryStore());
      await service.activate();
      service.setQuiet('old-account-recorder', true);
      service.clearSession();
      expect(service.quiet, isTrue);
      expect(await service.activate(), isFalse);
      await service.play(KorlixSound.click);
      expect(player.plays, isEmpty);
      service.setQuiet('old-account-recorder', false);
      expect(service.quiet, isFalse);
      await service.play(KorlixSound.click);
      expect(player.plays, hasLength(1));
      service.dispose();
    },
  );

  testWidgets(
    'preview failure updates blocked state and canceled previews do not',
    (tester) async {
      final player = FakePlayer()..failPlay = true;
      final service = KorlixSoundService(player: player, store: MemoryStore());
      await service.activate();
      await service.preview(KorlixSound.bell);
      expect(service.blocked, isTrue);
      expect(player.active, isEmpty);
      await service.activate();
      expect(service.blocked, isFalse);
      final gate = Completer<bool>();
      player.playGate = gate;
      final pending = service.preview(KorlixSound.bell);
      service.clearSession();
      gate.complete(true);
      await pending;
      expect(service.blocked, isFalse);
      service.dispose();
    },
  );

  testWidgets(
    'click preview gets its full duration after bounded preparation',
    (tester) async {
      final gate = Completer<bool>();
      final player = FakePlayer()..playGate = gate;
      final service = KorlixSoundService(player: player, store: MemoryStore());
      await service.activate();
      final preview = service.preview(KorlixSound.click);
      final revision = player.generation['preview'];
      await tester.pump(const Duration(milliseconds: 100));
      expect(player.generation['preview'], revision);
      gate.complete(true);
      await preview;
      expect(player.active, contains('preview'));
      await tester.pump(const Duration(milliseconds: 44));
      expect(player.active, contains('preview'));
      await tester.pump(const Duration(milliseconds: 1));
      expect(player.active, isNot(contains('preview')));
      service.dispose();
    },
  );

  testWidgets(
    'stopping during async decoding cancels late play without marking blocked',
    (tester) async {
      final gate = Completer<bool>();
      final player = FakePlayer()..playGate = gate;
      final service = KorlixSoundService(player: player, store: MemoryStore());
      await service.activate();
      final playback = service.play(KorlixSound.message);
      service.setForeground(false);
      gate.complete(true);
      await playback;
      expect(player.active, isEmpty);
      expect(service.blocked, isFalse);
      service.dispose();
    },
  );
}
