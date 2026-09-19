import 'dart:io';
import 'k135z_capture_controller_test.dart' show CaptureFixture;
import '../../lib/meeting_copilot/k135z_zoom_runtime_binding.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot.dart';
import '../../lib/meeting_copilot/korlix_zoom_connection_client.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/main.dart' as app;
import '../../lib/meeting_copilot/k135z_workspace_controller.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot_access.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot_route.dart';
import 'helpers/k135z_korlixai_fakes.dart';

void main() {
  gate6cRouteTests();
  gate6pWidgetTests();
  testWidgets('Gate6N route buttons dispatch authenticated capture controls', (tester) async {
    final f = CaptureFixture();
    setKorlixMeetingCopilotEnterpriseAccess(true);
    final launch = K135zZoomLaunch(agentId:'agent', backendBaseUri:Uri.parse('https://api.example.test'),
      headersBuilder:() => {'authorization':'Bearer offline'}, isCurrent:() => true);
    await tester.pumpWidget(MaterialApp(home:KorlixMeetingCopilotRoute(zoomLaunch:launch,zoomTransport:f.c.transport)));
    final screen = tester.widget<KorlixMeetingCopilotScreen>(find.byType(KorlixMeetingCopilotScreen));
    final capture = screen.capture!;
    await capture.selectMeeting('meeting'); await tester.pump();
    expect(tester.widget<ElevatedButton>(find.byKey(const Key('start-listening-button'))).onPressed, isNull);
    tester.widget<CheckboxListTile>(find.byKey(const Key('g6n-consent'))).onChanged!(true);
    await tester.pump();
    tester.widget<ElevatedButton>(find.byKey(const Key('start-listening-button'))).onPressed!();
    await tester.pumpAndSettle(); expect(capture.statusLabel, 'Listening');
    expect(screen.controller.state.status, isNot(NovaMeetingCopilotStatus.listening));
    tester.widget<OutlinedButton>(find.byKey(const Key('pause-listening-button'))).onPressed!();
    await tester.pumpAndSettle(); expect(capture.statusLabel, 'Paused');
    tester.widget<OutlinedButton>(find.byKey(const Key('stop-listening-button'))).onPressed!();
    await tester.pumpAndSettle(); expect(capture.statusLabel, 'Stopped');
    expect(f.calls, ['status','consent','start','pause','stop']);
    await tester.pumpWidget(const SizedBox()); f.c.dispose();
    setKorlixMeetingCopilotEnterpriseAccess(false);
  });
  test('Meeting Copilot route name is stable', () {
    expect(KorlixMeetingCopilotRoute.routeName, '/meeting-copilot');
  });

  test('KORLIX and Nova use separate canonical asset paths', () {
    expect(
      KorlixMeetingCopilotAssets.korlixLogo,
      'assets/meeting_copilot/korlix_logo.jpeg',
    );
    expect(
      KorlixMeetingCopilotAssets.novaPortrait,
      'assets/meeting_copilot/nova_canonical.webp',
    );
    expect(
      KorlixMeetingCopilotAssets.korlixLogo,
      isNot(KorlixMeetingCopilotAssets.novaPortrait),
    );
  });

  test('main MaterialApp registers the Meeting Copilot named route', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(
      source,
      contains("import 'meeting_copilot/korlix_meeting_copilot_route.dart';"),
    );
    expect(source, contains('KorlixMeetingCopilotRoute.routeName:'));
    expect(source, contains('const KorlixMeetingCopilotRoute()'));
  });

  test('pubspec declares both exact Meeting Copilot assets', () {
    final source = File('pubspec.yaml').readAsStringSync();
    expect(source, contains('assets/meeting_copilot/korlix_logo.jpeg'));
    expect(source, contains('assets/meeting_copilot/nova_canonical.webp'));
  });

  test('controller-aware route and app entrypoint compile together', () {
    const route = KorlixMeetingCopilotRoute();
    expect(route, isA<StatefulWidget>());
    expect(
      KorlixMeetingCopilotRoute.accessibilityLabel.toLowerCase(),
      contains('muted by default'),
    );
    expect(app.main, isA<Function>());
  });

  testWidgets(
    'route accepts feature-local workspace injection and reacts to access loss',
    (WidgetTester tester) async {
      final K135zFakeGateway gateway = K135zFakeGateway();
      final K135zWorkspaceController workspace = K135zWorkspaceController(
        gateway: gateway,
        context: k135zTestContext(),
      );
      setKorlixMeetingCopilotEnterpriseAccess(true);
      await tester.pumpWidget(
        MaterialApp(
          home: KorlixMeetingCopilotRoute(workspaceController: workspace),
        ),
      );
      await tester.pump();

      expect(find.byKey(KorlixMeetingCopilotRoute.screenKey), findsOneWidget);
      expect(workspace.state.accessGranted, isTrue);

      setKorlixMeetingCopilotEnterpriseAccess(false);
      await tester.pump();
      expect(workspace.state.accessGranted, isFalse);
      expect(workspace.state.phase.name, 'locked');

      workspace.dispose();
      setKorlixMeetingCopilotEnterpriseAccess(false);
    },
  );
}

void gate6cRouteTests() {
  testWidgets('Gate6C direct route lacks implicit selected-agent authority', (tester) async {
    setKorlixMeetingCopilotEnterpriseAccess(true);
    await tester.pumpWidget(const MaterialApp(home: KorlixMeetingCopilotRoute()));
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('g6c-refresh'))).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    setKorlixMeetingCopilotEnterpriseAccess(false);
  });
  testWidgets('Gate6C route reflects acknowledged account without enabling listening', (tester) async {
    setKorlixMeetingCopilotEnterpriseAccess(true);
    final launch = K135zZoomLaunch(agentId: 'custom_9',
      backendBaseUri: Uri.parse('https://api.korlix.test'),
      headersBuilder: () => {'authorization': 'Bearer offline-user'}, isCurrent: () => true);
    int requests = 0;
    await tester.pumpWidget(MaterialApp(home: KorlixMeetingCopilotRoute(zoomLaunch: launch,
      zoomTransport: ({required String method, required Uri uri,
          required Map<String, String> headers, Object? body}) async {
        requests++; expect(uri.queryParameters['agent_id'], 'custom_9');
        return const KorlixZoomTransportResponse(statusCode: 200,
          body: '{"status":{"connected":true,"requires_reauthorization":false,"access_token_expired":false}}');
      })));
    expect(requests, 0);
    await tester.tap(find.byKey(const Key('g6c-refresh')));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('Zoom account connected. No meeting is being captured.'), findsOneWidget);
    final screen = tester.widget<KorlixMeetingCopilotScreen>(find.byType(KorlixMeetingCopilotScreen));
    expect(screen.controller.canStartListening, isFalse);
    expect(screen.controller.state.novaMuted, isTrue);
    expect(screen.notesOnly, isTrue);
    setKorlixMeetingCopilotEnterpriseAccess(false); await tester.pump();
    expect(find.byType(KorlixMeetingCopilotLockedPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

void gate6pWidgetTests() {
  testWidgets('Gate6P route displays authorized captions and clears them on access loss', (tester) async {
    final f = CaptureFixture();setKorlixMeetingCopilotEnterpriseAccess(true);
    final launch = K135zZoomLaunch(agentId:'agent',backendBaseUri:Uri.parse('https://api.example.test'),
      headersBuilder:() => {'authorization':'Bearer offline'},isCurrent:() => true);
    await tester.pumpWidget(MaterialApp(home:KorlixMeetingCopilotRoute(zoomLaunch:launch,zoomTransport:f.c.transport)));
    final capture = tester.widget<KorlixMeetingCopilotScreen>(find.byType(KorlixMeetingCopilotScreen)).capture!;
    await capture.selectMeeting('meeting');await capture.setConsent(true);await capture.start();await tester.pump();
    tester.widget<OutlinedButton>(find.byKey(const Key('g6p-refresh-transcript'))).onPressed!();
    await tester.pumpAndSettle();expect(find.text('Host: Meeting caption'),findsOneWidget);
    expect(find.text('Recent captions only. Not saved; meeting coverage is incomplete.'),findsOneWidget);
    setKorlixMeetingCopilotEnterpriseAccess(false);await tester.pump();
    expect(find.text('Host: Meeting caption'),findsNothing);
    await tester.pumpWidget(const SizedBox());f.c.dispose();
  });
}
