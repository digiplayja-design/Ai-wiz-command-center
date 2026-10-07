import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/meeting_copilot/k135z_zoom_runtime_binding.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot_access.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot_route.dart';
import '../../lib/privacy/korlix_third_party_ai_consent.dart';
import 'k135z_capture_controller_test.dart' show CaptureFixture;
import 'k135z_spoken_replies_test.dart' show SpokenPlayer;

K135zZoomLaunch launch(CaptureFixture fixture) => K135zZoomLaunch(
  agentId: 'agent',
  backendBaseUri: Uri.parse('https://api.example.test'),
  headersBuilder: () => {'authorization': 'Bearer offline'},
  isCurrent: () => fixture.current,
);

Future<void> openMeeting(WidgetTester tester, CaptureFixture fixture) async {
  await tester.pumpWidget(
    MaterialApp(
      home: KorlixMeetingCopilotRoute(
        zoomLaunch: launch(fixture),
        zoomTransport: fixture.c.transport,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapStart(WidgetTester tester) async {
  tester
      .widget<FilledButton>(find.byKey(const Key('start-listening-button')))
      .onPressed!();
  // The Start button intentionally stays busy beneath the consent dialog.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    KorlixThirdPartyAiConsent.setAccountScope('account-a');
    setKorlixMeetingCopilotEnterpriseAccess(true);
  });
  tearDown(() {
    KorlixThirdPartyAiConsent.setAccountScope(null);
    setKorlixMeetingCopilotEnterpriseAccess(false);
  });

  testWidgets(
    'declining named OpenAI sharing blocks capture before any meeting data request',
    (tester) async {
      final fixture = CaptureFixture();
      addTearDown(fixture.c.dispose);
      await openMeeting(tester, fixture);
      expect(fixture.calls, isEmpty);
      expect(
        find.byKey(const Key('meeting-ai-sharing-notice')),
        findsOneWidget,
      );
      await tapStart(tester);
      expect(find.text('Share data with AI providers?'), findsOneWidget);
      expect(find.textContaining('OpenAI'), findsWidgets);
      expect(
        find.textContaining('Voice, audio, and transcripts'),
        findsOneWidget,
      );
      expect(fixture.calls, isEmpty);
      await tester.tap(find.text("Don't Allow"));
      await tester.pumpAndSettle();
      final capture = tester
          .widget<KorlixMeetingCopilotScreen>(
            find.byType(KorlixMeetingCopilotScreen),
          )
          .capture!;
      expect(capture.statusLabel, isNot('Listening'));
      expect(capture.actionError, contains('Allow sharing'));
      expect(fixture.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'approval starts capture, is reused for resume, and is isolated by account',
    (tester) async {
      final fixture = CaptureFixture();
      addTearDown(fixture.c.dispose);
      await openMeeting(tester, fixture);
      await tapStart(tester);
      await tester.tap(find.text('Allow & Continue'));
      await tester.pumpAndSettle();
      final capture = tester
          .widget<KorlixMeetingCopilotScreen>(
            find.byType(KorlixMeetingCopilotScreen),
          )
          .capture!;
      expect(capture.statusLabel, 'Listening');
      expect(fixture.calls.take(3), ['status', 'consent', 'start']);
      final preferences = await SharedPreferences.getInstance();
      final record =
          jsonDecode(
                preferences.getString(
                  KorlixThirdPartyAiConsent.accountStorageKey('account-a'),
                )!,
              )
              as Map;
      expect(
        record['grants'],
        unorderedEquals([
          'openAi:voiceAudioAndTranscripts',
          'openAi:agentTrainingAndMemory',
        ]),
      );

      await capture.pause();
      await capture.start();
      await tester.pumpAndSettle();
      expect(capture.statusLabel, 'Listening');
      expect(find.text('Share data with AI providers?'), findsNothing);

      await capture.stop();
      await tester.pumpAndSettle();
      final before = fixture.calls.length;
      KorlixThirdPartyAiConsent.setAccountScope('account-b');
      await tapStart(tester);
      expect(find.text('Share data with AI providers?'), findsOneWidget);
      expect(fixture.calls.length, before);
      await tester.tap(find.text("Don't Allow"));
      await tester.pumpAndSettle();
      expect(fixture.calls.length, before);
      expect(
        preferences.getString(
          KorlixThirdPartyAiConsent.accountStorageKey('account-b'),
        ),
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account change while sharing dialog is open cannot authorize old meeting',
    (tester) async {
      final fixture = CaptureFixture();
      addTearDown(fixture.c.dispose);
      await openMeeting(tester, fixture);
      await tapStart(tester);
      fixture.current = false;
      KorlixThirdPartyAiConsent.setAccountScope('account-b');
      await tester.pumpAndSettle();
      expect(find.text('Share data with AI providers?'), findsNothing);
      expect(fixture.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('runtime without a provider consent callback fails closed', () async {
    final fixture = CaptureFixture();
    final runtime = K135zZoomRuntimeBinding(
      launch: launch(fixture),
      transport: fixture.c.transport,
    );
    addTearDown(runtime.dispose);
    addTearDown(fixture.c.dispose);
    await runtime.initialize();
    await runtime.startListening();
    expect(fixture.calls, isEmpty);
    expect(runtime.capture.actionError, contains('Allow sharing'));
  });

  test(
    'Start Nova preserves local audio unlock but sends nothing before consent or after decline',
    () async {
      final fixture = CaptureFixture();
      final player = SpokenPlayer();
      final choice = Completer<bool>();
      final runtime = K135zZoomRuntimeBinding(
        launch: launch(fixture),
        transport: fixture.c.transport,
        spokenPlayer: player,
        requestAiConsent: () => choice.future,
      );
      addTearDown(runtime.dispose);
      addTearDown(fixture.c.dispose);
      await runtime.initialize();
      final starting = runtime.startNova();
      expect(player.enables, 1);
      await Future<void>.delayed(Duration.zero);
      expect(fixture.calls, isEmpty);
      expect(runtime.response.spoken.enabled, isFalse);
      choice.complete(false);
      await starting;
      expect(fixture.calls, isEmpty);
      expect(runtime.response.spoken.enabled, isFalse);
      expect(player.ready, isFalse);
    },
  );

  test(
    'direct capture start cannot bypass declined provider consent',
    () async {
      final fixture = CaptureFixture(requestAiConsent: () async => false);
      addTearDown(fixture.c.dispose);
      await fixture.c.selectMeeting('meeting');
      await fixture.c.setConsent(true);
      fixture.calls.clear();
      await fixture.c.start();
      expect(fixture.calls, isEmpty);
      expect(fixture.c.statusLabel, isNot('Listening'));
    },
  );
}
