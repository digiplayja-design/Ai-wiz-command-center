import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  testWidgets(
    'notes-only workspace renders safe controls and disabled speech',
    (WidgetTester tester) async {
      final K135zFakeGateway gateway = K135zFakeGateway();
      final K135zWorkspaceController workspace = K135zWorkspaceController(
        gateway: gateway,
        context: k135zTestContext(),
        accessGranted: true,
      );
      final NovaMeetingCopilotController legacy =
          NovaMeetingCopilotController();

      await tester.pumpWidget(
        MaterialApp(
          home: KorlixMeetingCopilotScreen(
            controller: legacy,
            workspaceController: workspace,
            notesOnly: true,
            korlixLogo: _pixel(),
            novaPortrait: _pixel(),
            onSpeakNow: () => fail('Notes-only workspace must never speak.'),
          ),
        ),
      );

      expect(find.text('Validated Notes Workspace'), findsOneWidget);
      expect(find.text('Speech: disabled'), findsOneWidget);
      expect(find.byKey(const Key('k135z-workspace-start')), findsOneWidget);

      final ElevatedButton speakButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('speak-now-button')),
      );
      expect(speakButton.onPressed, isNull);

      await tester.tap(find.byKey(const Key('k135z-workspace-start')));
      await tester.pump();
      expect(workspace.state.pendingAction?.name, 'start');
      gateway.acknowledgeNext();
      await tester.pump();
      expect(workspace.state.phase.name, 'listening');

      legacy.dispose();
      workspace.dispose();
    },
  );
}
