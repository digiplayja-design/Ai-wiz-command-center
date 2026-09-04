import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/meeting_copilot/korlix_meeting_copilot.dart';

MemoryImage _pixel() {
  final Uint8List bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==',
  );

  return MemoryImage(bytes);
}

void main() {
  test('Nova is muted and disconnected by default', () {
    final NovaMeetingCopilotController controller =
        NovaMeetingCopilotController();

    expect(controller.state.novaMuted, isTrue);
    expect(controller.state.zoomConnected, isFalse);
    expect(controller.canSpeakNow, isFalse);

    controller.dispose();
  });

  test('listening requires both Zoom connection and host authorization', () {
    final NovaMeetingCopilotController controller =
        NovaMeetingCopilotController();

    expect(controller.startListening, throwsStateError);

    controller.setConnection(
      connected: true,
      meetingTitle: 'Product Review',
      participantCount: 5,
    );

    expect(controller.startListening, throwsStateError);

    controller.setHostAuthorization(true);
    controller.startListening();

    expect(controller.state.status, NovaMeetingCopilotStatus.listening);
    expect(controller.state.novaMuted, isTrue);

    controller.dispose();
  });

  test('pause, resume, and stop keep Nova muted', () {
    final NovaMeetingCopilotController controller =
        NovaMeetingCopilotController();

    controller.setConnection(connected: true);
    controller.setHostAuthorization(true);
    controller.startListening();
    controller.pauseListening();

    expect(controller.state.status, NovaMeetingCopilotStatus.paused);
    expect(controller.state.novaMuted, isTrue);

    controller.startListening();
    controller.stopListening();

    expect(controller.state.status, NovaMeetingCopilotStatus.stopped);
    expect(controller.state.novaMuted, isTrue);

    controller.dispose();
  });

  test('speaking is blocked until the host explicitly invites Nova', () {
    final NovaMeetingCopilotController controller =
        NovaMeetingCopilotController();

    controller.setConnection(connected: true);
    controller.setHostAuthorization(true);
    controller.startListening();

    expect(controller.beginSpeaking, throwsStateError);

    controller.grantHostSpeechInvite(true);
    controller.beginSpeaking();

    expect(controller.state.status, NovaMeetingCopilotStatus.speaking);
    expect(controller.state.novaMuted, isFalse);

    controller.muteNova();

    expect(controller.state.status, NovaMeetingCopilotStatus.listening);
    expect(controller.state.novaMuted, isTrue);
    expect(controller.state.hostInvitedToSpeak, isFalse);

    controller.dispose();
  });

  test('transcript and insight state stay separated', () {
    final NovaMeetingCopilotController controller =
        NovaMeetingCopilotController();

    controller.addTranscriptLine(
      const NovaTranscriptLine(
        speaker: 'Ricardo',
        text: 'Approve the next milestone.',
        timestamp: Duration(seconds: 75),
      ),
    );

    controller.replaceInsights(
      decisions: const <NovaMeetingInsight>[
        NovaMeetingInsight(
          title: 'Milestone',
          detail: 'Proceed to the private pilot.',
        ),
      ],
      actionItems: const <NovaMeetingInsight>[
        NovaMeetingInsight(
          title: 'Owner',
          detail: 'Nova drafts the follow-up.',
        ),
      ],
    );

    expect(controller.state.transcript.single.timestampLabel, '01:15');
    expect(controller.state.decisions, hasLength(1));
    expect(controller.state.actionItems, hasLength(1));
    expect(controller.state.risks, isEmpty);

    controller.dispose();
  });

  testWidgets('Meeting Copilot renders required panels and safe controls', (
    WidgetTester tester,
  ) async {
    final NovaMeetingCopilotController controller =
        NovaMeetingCopilotController();

    await tester.pumpWidget(
      MaterialApp(
        home: KorlixMeetingCopilotScreen(
          controller: controller,
          korlixLogo: _pixel(),
          novaPortrait: _pixel(),
          onConnectZoom: () {},
          onAskNova: () {},
          onThirtySecondUpdate: () {},
          onSpeakNow: () {},
        ),
      ),
    );

    expect(find.text('NOVA MEETING COPILOT'), findsOneWidget);
    expect(find.text('Decisions'), findsOneWidget);
    expect(find.text('Action Items'), findsOneWidget);
    expect(find.text('Deadlines'), findsOneWidget);
    expect(find.text('Risks'), findsOneWidget);
    expect(find.text('Open Questions'), findsOneWidget);
    expect(find.text('Key Takeaways'), findsOneWidget);
    expect(find.textContaining('NOVA IS MUTED'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const Key('speak-now-button')), findsOneWidget);

    final ElevatedButton speakButton = tester.widget<ElevatedButton>(
      find.byKey(const Key('speak-now-button')),
    );

    expect(speakButton.onPressed, isNull);

    controller.dispose();
  });
}
