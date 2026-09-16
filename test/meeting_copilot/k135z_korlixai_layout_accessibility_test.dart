import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/meeting_copilot/k135z_copilot_contract.dart';
import '../../lib/meeting_copilot/k135z_notes_projection.dart';
import '../../lib/meeting_copilot/k135z_workspace_controller.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot.dart';
import 'helpers/k135z_korlixai_fakes.dart';

MemoryImage _pixel() => MemoryImage(
  Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
      'AAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==',
    ),
  ),
);

void _configureIpadPortrait(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(834, 1112);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required NovaMeetingCopilotController legacy,
  required K135zWorkspaceController workspace,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: KorlixMeetingCopilotScreen(
        controller: legacy,
        workspaceController: workspace,
        notesOnly: true,
        korlixLogo: _pixel(),
        novaPortrait: _pixel(),
        onSpeakNow: () => fail('Notes-only certification must never speak.'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _startWorkspace(
  K135zWorkspaceController workspace,
  K135zFakeGateway gateway,
) async {
  final Future<bool> pending = workspace.startListening();
  gateway.acknowledgeNext();
  expect(await pending, isTrue);
}

void main() {
  testWidgets('iPad portrait width stacks panels without overflow', (
    WidgetTester tester,
  ) async {
    _configureIpadPortrait(tester);
    final K135zFakeGateway gateway = K135zFakeGateway();
    final K135zWorkspaceController workspace = K135zWorkspaceController(
      gateway: gateway,
      context: k135zTestContext(),
      accessGranted: true,
    );
    final NovaMeetingCopilotController legacy = NovaMeetingCopilotController();

    await _pumpWorkspace(tester, legacy: legacy, workspace: workspace);

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final double controlsTop = tester
        .getTopLeft(find.text('Nova Assistant Controls'))
        .dy;
    final double transcriptTop = tester
        .getTopLeft(find.text('Live Transcript Preview'))
        .dy;
    expect(transcriptTop, greaterThan(controlsTop));
    expect(tester.takeException(), isNull);

    legacy.dispose();
    workspace.dispose();
  });

  testWidgets('enlarged text keeps controls and disclosure reachable', (
    WidgetTester tester,
  ) async {
    _configureIpadPortrait(tester);
    final K135zFakeGateway gateway = K135zFakeGateway();
    final K135zWorkspaceController workspace = K135zWorkspaceController(
      gateway: gateway,
      context: k135zTestContext(),
      accessGranted: true,
    );
    final NovaMeetingCopilotController legacy = NovaMeetingCopilotController();

    await _pumpWorkspace(
      tester,
      legacy: legacy,
      workspace: workspace,
      textScale: 2.0,
    );

    expect(find.text('Start Notes Capture'), findsOneWidget);
    final Finder disclosure = find.textContaining(
      'Disclosure and host control are required.',
    );
    await tester.ensureVisible(disclosure);
    await tester.pumpAndSettle();
    expect(disclosure, findsOneWidget);
    final Rect disclosureRect = tester.getRect(disclosure);
    expect(disclosureRect.top, greaterThanOrEqualTo(0));
    expect(disclosureRect.bottom, lessThanOrEqualTo(1112));
    expect(tester.takeException(), isNull);

    legacy.dispose();
    workspace.dispose();
  });

  testWidgets('long labels transcript and evidence content remain reachable', (
    WidgetTester tester,
  ) async {
    _configureIpadPortrait(tester);
    final K135zFakeGateway gateway = K135zFakeGateway();
    final K135zWorkspaceController workspace = K135zWorkspaceController(
      gateway: gateway,
      context: k135zTestContext(),
      accessGranted: true,
    );
    final NovaMeetingCopilotController legacy = NovaMeetingCopilotController();
    const String longTitle =
        'Enterprise Planning Session for the KORLIX Notes-Only Zoom Copilot '
        'with a deliberately extended meeting title that must wrap safely';
    const String longEvidence =
        'This evidence-linked insight deliberately uses a long explanation '
        'covering ownership, deadline context, privacy limits, host control, '
        'and the requirement that every statement remain readable without '
        'horizontal clipping or an inaccessible off-screen control.';

    legacy.setConnection(
      connected: true,
      meetingTitle: longTitle,
      participantCount: 24,
    );
    legacy.setHostAuthorization(true);
    legacy.startListening();
    for (int index = 1; index <= 12; index += 1) {
      legacy.addTranscriptLine(
        NovaTranscriptLine(
          speaker: 'Participant with a deliberately long display name $index',
          text:
              'Transcript segment $index contains deliberately long meeting '
              'content that must wrap inside the bounded transcript panel and '
              'remain reachable through vertical scrolling on an iPad-width '
              'surface without causing a RenderFlex overflow.',
          timestamp: Duration(seconds: index * 15),
        ),
      );
    }
    legacy.replaceInsights(
      decisions: const <NovaMeetingInsight>[
        NovaMeetingInsight(
          title: 'Evidence-linked long-form decision',
          detail: longEvidence,
          owner: 'A participant with a deliberately long ownership label',
        ),
      ],
    );

    await _startWorkspace(workspace, gateway);
    for (int index = 1; index <= 12; index += 1) {
      workspace.ingest(
        k135zTestEvent(
          index,
          text:
              'Validated evidence segment $index contains long content for '
              'responsive layout certification and remains bounded.',
          speaker: 'Evidence owner with a long participant label $index',
        ),
      );
    }
    final request = workspace.prepareNotes('layout-certification-request');
    expect(request, isNotNull);
    workspace.acceptNotes(
      request: request!,
      draft: <K135zDraftInsight>[
        K135zDraftInsight(
          category: K135zInsightCategory.decisions,
          title: 'Long evidence-linked workspace decision',
          detail: longEvidence,
          owner: 'A participant with a deliberately long ownership label',
          evidenceSegmentIds: <String>['S1'],
        ),
      ],
      metadata: k135zFixtureMetadata(),
    );

    await _pumpWorkspace(tester, legacy: legacy, workspace: workspace);

    final Text meetingTitle = tester.widget<Text>(find.text(longTitle));
    expect(meetingTitle.maxLines, isNull);
    expect(meetingTitle.softWrap, isNot(false));

    final Finder evidenceFinder = find.textContaining(longEvidence);
    await tester.ensureVisible(evidenceFinder);
    await tester.pumpAndSettle();
    final Text evidenceText = tester.widget<Text>(evidenceFinder);
    expect(evidenceText.maxLines, isNull);
    expect(evidenceText.softWrap, isNot(false));
    final Rect evidenceRect = tester.getRect(evidenceFinder);
    expect(evidenceRect.top, greaterThanOrEqualTo(0));
    expect(evidenceRect.bottom, lessThanOrEqualTo(1112));
    expect(tester.takeException(), isNull);

    legacy.dispose();
    workspace.dispose();
  });
}
