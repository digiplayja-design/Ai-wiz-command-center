import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_welcome.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.korlix.brain/welcome');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late BrainWelcome welcome;
  late List<MethodCall> calls;
  late List<Map<String, dynamic>> events;
  var allowed = true;

  int lastNativeToken() =>
      (calls.lastWhere((call) => call.method == 'play').arguments as Map)['token'] as int;

  Future<void> ended(int nativeToken) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('ended', {'token': nativeToken, 'reason': 'completed'}),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  setUp(() {
    allowed = true;
    calls = [];
    events = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'play' ? {'started': true} : null;
    });
    welcome = BrainWelcome(
      nativePlayback: true,
      channel: channel,
      canPlay: () => allowed,
      onEvent: events.add,
    );
  });
  tearDown(() async {
    await welcome.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('inactive startup does not consume the automatic welcome', () async {
    allowed = false;
    expect(await welcome.play(1, automatic: true), {'started': false});
    await welcome.stop(dismiss: false);
    expect(welcome.automaticPending, isTrue);
    expect(calls, isEmpty);
    allowed = true;
    expect(await welcome.play(2, automatic: true), {'started': true});
    expect(welcome.automaticPending, isFalse);
  });

  test('successful startup plays once but Replay remains available', () async {
    await welcome.play(1, automatic: true);
    await welcome.stop();
    expect(await welcome.play(2, automatic: true), {'started': false});
    expect(await welcome.play(3, automatic: false), {'started': true});
    expect(calls.where((c) => c.method == 'play').length, 2);
  });

  test(
    'Skip before initialization cancels delayed automatic playback',
    () async {
      await welcome.stop();
      expect(await welcome.play(1, automatic: true), {'started': false});
      expect(calls, isEmpty);
    },
  );

  test(
    'native inactive response leaves the welcome available for foreground',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'started': false, 'retry': true},
      );
      expect(await welcome.play(1, automatic: true), {
        'started': false,
        'retry': true,
      });
      expect(welcome.automaticPending, isTrue);
    },
  );

  test('microphone handoff waits for an already pending native Stop', () async {
    await welcome.play(1, automatic: true);
    final release = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'stop') await release.future;
      return null;
    });
    final firstStop = welcome.stop();
    var captureReady = false;
    final handoff = welcome.stop().then((_) => captureReady = true);
    await Future<void>.delayed(Duration.zero);
    expect(captureReady, isFalse);
    release.complete();
    await Future.wait([firstStop, handoff]);
    expect(captureReady, isTrue);
    expect(calls.where((c) => c.method == 'stop').length, 1);
  });

  test('late native Play completion cannot override Skip', () async {
    final release = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'play' ? release.future : null;
    });
    final playing = welcome.play(1, automatic: true);
    await Future<void>.delayed(Duration.zero);
    await welcome.stop();
    release.complete({'started': true});
    expect(await playing, {'started': false});
    expect(calls.last.method, 'stop');
  });

  test('old completion events cannot stop a newer Replay', () async {
    await welcome.play(1, automatic: true);
    final firstNativeToken = lastNativeToken();
    await welcome.stop();
    await welcome.play(2, automatic: false);
    final secondNativeToken = lastNativeToken();
    await ended(firstNativeToken);
    expect(events, isEmpty);
    await ended(secondNativeToken);
    expect(events.single, {
      'type': 'welcomeEnded',
      'token': 2,
      'reason': 'completed',
    });
  });

  for (final replacementFirst in [false, true]) {
    test('workspace replacement retains its handler and playback token ($replacementFirst)', () async {
      await welcome.play(1, automatic: true);
      final firstNativeToken = lastNativeToken();
      final release = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'stop') await release.future;
        return call.method == 'play' ? {'started': true} : null;
      });
      final replacementEvents = <Map<String, dynamic>>[];
      BrainWelcome replacement() => BrainWelcome(
        nativePlayback: true, channel: channel,
        canPlay: () => true, onEvent: replacementEvents.add,
      );
      final next = replacementFirst ? replacement() : null;
      final disposing = welcome.dispose();
      final current = next ?? replacement();
      await current.play(1, automatic: true);
      final nextNativeToken = lastNativeToken();
      expect(nextNativeToken, isNot(firstNativeToken));
      expect((calls.singleWhere((call) => call.method == 'stop').arguments as Map)['token'],
          firstNativeToken);
      release.complete();
      await disposing;
      await ended(firstNativeToken);
      expect(replacementEvents, isEmpty);
      await ended(nextNativeToken);
      expect(replacementEvents.single['token'], 1);
      expect(events, isEmpty);
      await current.dispose();
    });
  }

  test('no native playback while capture or an overlay owns audio', () async {
    allowed = false;
    expect(await welcome.play(1, automatic: false), {'started': false});
    expect(calls, isEmpty);
  });
}
