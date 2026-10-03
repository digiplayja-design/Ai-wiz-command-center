import 'dart:async';

import 'package:ai_wiz_command_center/sounds/korlix_sound_player_native.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_settings.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_tones.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every generated sound is bounded audible 16-bit PCM with headroom', () {
    for (final pack in KorlixSoundPack.values) {
      for (final sound in KorlixSound.values) {
        for (final outgoing in [false, true]) {
          final wav = korlixSoundWav(sound, pack, outgoing: outgoing);
          final data = ByteData.sublistView(wav);
          final description = '${pack.name}/${sound.name}/$outgoing';
          expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
          expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
          expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
          expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
          expect(data.getUint32(4, Endian.little), wav.length - 8);
          expect(data.getUint16(20, Endian.little), 1);
          expect(data.getUint16(22, Endian.little), 1);
          expect(data.getUint16(34, Endian.little), 16);
          final rate = data.getUint32(24, Endian.little);
          expect(rate, 24000);
          expect(data.getUint32(28, Endian.little), rate * 2);
          final frames = data.getUint32(40, Endian.little) ~/ 2;
          expect(wav.length, 44 + frames * 2);
          final duration = korlixSoundDuration(sound, outgoing: outgoing);
          expect(duration.inMicroseconds, inInclusiveRange(40000, 2000000));
          expect(frames, duration.inMicroseconds * rate ~/ 1000000);
          var peak = 0;
          var power = 0.0;
          for (var i = 0; i < frames; i++) {
            final sample = data.getInt16(44 + i * 2, Endian.little);
            if (sample.abs() > peak) peak = sample.abs();
            power += sample * sample;
          }
          expect(peak, inInclusiveRange(1000, 22282), reason: description);
          expect(power / frames, greaterThan(100000), reason: description);
          expect(data.getInt16(44, Endian.little), 0, reason: description);
          expect(
            data.getInt16(wav.length - 2, Endian.little),
            0,
            reason: description,
          );
        }
      }
    }
  });

  test('packs sound different and generated data is cached', () {
    for (final sound in KorlixSound.values) {
      final signature = korlixSoundWav(sound, KorlixSoundPack.signature);
      final classic = korlixSoundWav(sound, KorlixSoundPack.classic);
      final soft = korlixSoundWav(sound, KorlixSoundPack.soft);
      expect(listEquals(signature, classic), isFalse);
      expect(listEquals(signature, soft), isFalse);
      expect(listEquals(classic, soft), isFalse);
      expect(
        identical(signature, korlixSoundWav(sound, KorlixSoundPack.signature)),
        isTrue,
      );
    }
  });

  test('incoming and outgoing rings differ and have a quiet loop boundary', () {
    for (final pack in KorlixSoundPack.values) {
      final incoming = korlixSoundWav(KorlixSound.ringtone, pack);
      final outgoing = korlixSoundWav(
        KorlixSound.ringtone,
        pack,
        outgoing: true,
      );
      expect(listEquals(incoming, outgoing), isFalse);
      for (final wav in [incoming, outgoing]) {
        // Both cadences have at least 500ms of silence before the next phrase.
        expect(wav.skip(wav.length - 24000).every((byte) => byte == 0), isTrue);
      }
    }
  });

  testWidgets('native bridge supports iOS and bounds ringing to 45 seconds', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('korlix/sound_effects');
    final calls = <MethodCall>[];
    final acknowledged = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'play') return acknowledged.future;
      return true;
    });
    final player = createKorlixSoundPlayer();
    expect(await player.activate(), isTrue);
    expect(player.ready, isTrue);
    final wav = korlixSoundWav(KorlixSound.ringtone, KorlixSoundPack.signature);
    final started = player.play(
      wav,
      volume: 0.5,
      duration: const Duration(minutes: 5),
      channel: 'ring',
      loop: true,
    );
    await tester.pump(const Duration(milliseconds: 100));
    acknowledged.complete(true);
    await tester.pump();
    expect(await started, isTrue);
    final payload = calls.last.arguments as Map;
    expect(payload['durationMs'], 45000);
    expect(payload['channel'], 'ring');
    expect(payload['wav'], wav);
    expect(payload['volume'], 0.5);
    await tester.pump(const Duration(milliseconds: 44900));
    expect(calls.last.method, 'stop');
    expect(
      (calls.last.arguments as Map)['revision'],
      greaterThan(payload['revision'] as int),
    );
    player.dispose();
    await tester.pump();
    expect(await player.activate(), isFalse);
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'native preparation does not consume a short click playback duration',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('korlix/sound_effects');
      final calls = <MethodCall>[];
      final gate = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'play') return gate.future;
        return true;
      });
      final player = createKorlixSoundPlayer();
      expect(await player.activate(), isTrue);
      final started = player.play(
        korlixSoundWav(KorlixSound.click, KorlixSoundPack.signature),
        volume: 0.4,
        duration: const Duration(milliseconds: 45),
        channel: 'effect',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls.where((call) => call.method == 'stop'), isEmpty);
      gate.complete(true);
      await tester.pump();
      expect(await started, isTrue);
      await tester.pump(const Duration(milliseconds: 44));
      expect(calls.where((call) => call.method == 'stop'), isEmpty);
      await tester.pump(const Duration(milliseconds: 2));
      expect(calls.last.method, 'stop');
      player.dispose();
      await tester.pump();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );

  testWidgets(
    'native preparation timeout prevents a late acknowledgement restarting audio',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('korlix/sound_effects');
      final calls = <MethodCall>[];
      final gate = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'play') return gate.future;
        return true;
      });
      final player = createKorlixSoundPlayer();
      expect(await player.activate(), isTrue);
      final started = player.play(
        korlixSoundWav(KorlixSound.click, KorlixSoundPack.signature),
        volume: 0.4,
        duration: const Duration(milliseconds: 45),
        channel: 'effect',
      );
      await tester.pump(const Duration(milliseconds: 251));
      expect(calls.last.method, 'stop');
      gate.complete(true);
      await tester.pump();
      expect(await started, isTrue);
      final count = calls.length;
      await tester.pump(const Duration(seconds: 1));
      expect(
        calls.length,
        count,
        reason: 'Late acknowledgement creates no timer or playback.',
      );
      player.dispose();
      await tester.pump();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );

  testWidgets(
    'native canceled load is successful cancellation without replay',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('korlix/sound_effects');
      final calls = <MethodCall>[];
      final gate = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'play') return gate.future;
        return true;
      });
      final player = createKorlixSoundPlayer();
      expect(await player.activate(), isTrue);
      final started = player.play(
        korlixSoundWav(KorlixSound.bell, KorlixSoundPack.signature),
        volume: 0.4,
        duration: const Duration(seconds: 1),
        channel: 'effect',
      );
      await tester.pump();
      player.stop('effect');
      gate.complete(false);
      await tester.pump();
      expect(
        await started,
        isTrue,
        reason: 'Cancellation is not blocked audio.',
      );
      expect(calls.where((call) => call.method == 'play').length, 1);
      expect(calls.last.method, 'stop');
      expect((calls.last.arguments as Map)['channel'], 'effect');
      await tester.pump(const Duration(seconds: 2));
      expect(calls.where((call) => call.method == 'play').length, 1);
      player.dispose();
      await tester.pump();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );

  testWidgets(
    'older builds fail activation safely when native shim is absent',
    (tester) async {
      const channel = MethodChannel('korlix/sound_effects');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw MissingPluginException();
      });
      final player = createKorlixSoundPlayer();
      expect(await player.activate(), isFalse);
      expect(player.ready, isFalse);
      player.dispose();
      await tester.pump();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}
