import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_wiz_command_center/main.dart' as app;
import 'package:ai_wiz_command_center/auth/knova_welcome_controller.dart';
import 'package:ai_wiz_command_center/auth/rici_welcome_button.dart';
import 'package:ai_wiz_command_center/auth/knova_welcome_player.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_service.dart';
import 'korlix_sound_service_test.dart' as sound;

Uint8List clip() {
  final bytes = Uint8List(96044), h = ByteData(96044);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, 1, Endian.little);
  h.setUint32(24, 24000, Endian.little);
  h.setUint16(34, 16, Endian.little);
  h.setUint32(40, 96000, Endian.little);
  bytes.setRange(20, 44, h.buffer.asUint8List().sublist(20, 44));
  return bytes;
}

class Player implements KnovaWelcomePlayer {
  int activations = 0, plays = 0, stops = 0;
  bool allowed = true;
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
    return allowed;
  }

  @override
  void stop() {
    stops++;
  }

  @override
  void dispose() {
    stop();
  }
}

class Fixture {
  final player = Player();
  final requests = <http.Request>[];
  final sounds = KorlixSoundService(
    player: sound.FakePlayer(),
    store: sound.MemoryStore(),
  );
  Completer<http.Response>? gate;
  late final controller = KnovaWelcomeController(
    backendBaseUrl: 'https://fixture.invalid',
    sounds: sounds,
    player: player,
    client: MockClient((r) async {
      requests.add(r);
      return gate == null ? http.Response.bytes(clip(), 200) : gate!.future;
    }),
  );
  void dispose() {
    controller.dispose();
    sounds.dispose();
  }
}

void main() {
  for (final successful in [true, false]) {
    testWidgets(
      'Sign-in primes audio synchronously and greets only on success: $successful',
      (t) async {
        SharedPreferences.setMockInitialValues({});
        final f = Fixture();
        await f.controller.preload();
        final response = Completer<http.Response>();
        final auth = MockClient((_) async {
          expect(f.player.activations, 1);
          expect(f.player.plays, 0);
          return response.future;
        });
        await t.pumpWidget(
          MaterialApp(
            home: app.AuthScreen(
              client: auth,
              onSignInGesture: f.controller.prepareGesture,
              onSignedIn: (_) => f.controller.signedIn(),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('auth-email')),
          'member@example.test',
        );
        await t.enterText(
          find.byKey(const ValueKey('auth-password')),
          'example-password',
        );
        await t.ensureVisible(find.text('Sign in'));
        await t.tap(find.text('Sign in'));
        expect(f.player.activations, 1);
        response.complete(
          successful
              ? http.Response(
                  jsonEncode({
                    'session': {'access_token': 'synthetic-token'},
                    'user': {'email': 'member@example.test'},
                  }),
                  200,
                )
              : http.Response(
                  jsonEncode({'error': 'Invalid credentials'}),
                  401,
                ),
        );
        await t.pumpAndSettle();
        expect(f.player.plays, successful ? 1 : 0);
        await t.pumpWidget(const SizedBox());
        auth.close();
        f.dispose();
      },
    );
  }
  test(
    'warmup is silent, successful sign-in speaks once, and public audio requests contain no credentials',
    () async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.controller.preload();
      expect(f.requests.single.url.path, '/api/welcome/rici-v3.wav');
      f.controller.prepareGesture();
      expect(f.player.activations, 1);
      expect(f.player.plays, 0);
      await f.controller.signedIn();
      await f.controller.signedIn();
      expect(f.player.plays, 1);
      expect(f.controller.visible, true);
      expect(f.requests.length, 1);
      expect(f.requests.single.headers.containsKey('Authorization'), false);
      expect(f.requests.single.body, isEmpty);
      f.controller.signedOut();
      await f.controller.signedIn();
      expect(f.player.plays, 2);
    },
  );
  test(
    'sign-out cancels a pending greeting and never starts late audio',
    () async {
      final f = Fixture();
      addTearDown(f.dispose);
      f.gate = Completer();
      f.controller.prepareGesture();
      final pending = f.controller.signedIn();
      await Future<void>.delayed(Duration.zero);
      f.controller.signedOut();
      f.gate!.complete(http.Response.bytes(clip(), 200));
      await pending;
      expect(f.player.plays, 0);
      expect(f.controller.visible, false);
    },
  );
  test('autoplay failure has an explicit tap retry', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    f.player.allowed = false;
    f.controller.prepareGesture();
    await f.controller.signedIn();
    expect(f.controller.state, KnovaWelcomeState.blocked);
    f.player.allowed = true;
    await f.controller.listen();
    expect(f.controller.state, KnovaWelcomeState.speaking);
    expect(f.player.plays, 1);
  });
  test(
    'mute, microphone/media use, incoming calls and backgrounding stop the greeting without restarting it',
    () async {
      for (final change in <void Function(Fixture)>[
        (f) => f.sounds.setQuiet('voice', true),
        (f) => f.sounds.setRinging('call', true, callId: 'incoming'),
        (f) => f.sounds.setForeground(false),
        (f) => unawaited(
          f.sounds.update(f.sounds.settings.copyWith(enabled: false)),
        ),
      ]) {
        final f = Fixture();
        await f.controller.signedIn();
        expect(f.controller.active, true);
        change(f);
        expect(f.controller.active, false);
        expect(f.player.stops, greaterThan(0));
        f.sounds.setForeground(true);
        f.sounds.setQuiet('voice', false);
        expect(f.player.plays, 1);
        f.dispose();
      }
    },
  );
  test(
    'the saved welcome preference suppresses both audio and the toolbar control',
    () async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.sounds.update(f.sounds.settings.copyWith(welcomeVoice: false));
      f.controller.prepareGesture();
      await f.controller.signedIn();
      expect(f.player.plays, 0);
      expect(f.controller.visible, false);
      expect(KorlixSoundSettings.fromJson({'version': 1}).welcomeVoice, true);
    },
  );
  for (final width in [390.0, 1024.0]) {
    testWidgets(
      'Welcome uses only a toolbar control at width $width with enlarged text',
      (t) async {
        t.view.physicalSize = Size(width, 1100);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final f = Fixture();
        await f.controller.signedIn();
        await t.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1100),
                textScaler: const TextScaler.linear(1.6),
              ),
              child: Scaffold(
                body: Center(
                  child: RiciWelcomeButton(controller: f.controller),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text(knovaWelcomeText), findsNothing);
        expect(find.byType(Card), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byTooltip('Stop Rici’s welcome'), findsOneWidget);
        await t.ensureVisible(find.byKey(const Key('rici-welcome-audio')));
        await t.tap(find.byKey(const Key('rici-welcome-audio')));
        await t.pump();
        expect(f.controller.active, false);
        expect(find.byTooltip('Listen to Rici’s welcome'), findsOneWidget);
        await t.tap(find.byKey(const Key('rici-welcome-audio')));
        await t.pump();
        expect(f.controller.active, true);
        f.controller.signedOut();
        await t.pump();
        expect(find.byKey(const Key('rici-welcome-audio')), findsNothing);
        await t.pumpWidget(const SizedBox());
        f.dispose();
      },
    );
  }
}
