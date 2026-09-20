import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/meeting_copilot/k135z_zoom_runtime_binding.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot_access.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot_route.dart';
import 'k135z_capture_controller_test.dart' show CaptureFixture;

void main() {
  for (final width in [390.0, 1024.0]) {
    testWidgets('one tap starts the sole meeting and Stop stays visible at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      final f = CaptureFixture(); addTearDown(f.c.dispose);
      // Reproduce the old persisted meeting shown in the user's screenshots.
      f.row['snapshot']['context']['meetingUuid'] = 'previous';
      setKorlixMeetingCopilotEnterpriseAccess(true);
      final launch = K135zZoomLaunch(agentId:'agent', backendBaseUri:Uri.parse('https://api.example.test'),
        headersBuilder:() => {'authorization':'Bearer offline'}, isCurrent:() => true);
      await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(),
        home:KorlixMeetingCopilotRoute(zoomLaunch:launch, zoomTransport:f.c.transport)));
      await tester.pumpAndSettle();
      expect(find.text('Meeting: Pilot'), findsOneWidget);
      expect(find.byKey(const Key('g6n-consent')), findsNothing);
      expect(find.byKey(const Key('listening-consent-notice')), findsOneWidget);
      expect(find.text('Start listening').hitTestable(), findsOneWidget);
      expect(find.text('Stop listening').hitTestable(), findsOneWidget);
      expect(f.calls, isEmpty);
      await tester.tap(find.text('Start listening')); await tester.pumpAndSettle();
      final capture = tester.widget<KorlixMeetingCopilotScreen>(find.byType(KorlixMeetingCopilotScreen)).capture!;
      expect(capture.statusLabel, 'Listening');
      expect(f.calls, ['status','stop','bind','consent','start']);
      expect(tester.takeException(), isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden); await tester.pump();
      final before = f.calls.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await tester.pumpAndSettle();
      expect(f.calls.skip(before), contains('status'));
      expect(f.calls.skip(before).where((x) => ['start','pause','stop','consent'].contains(x)), isEmpty);
      // Returning keeps listening active without another Start tap.
      expect(capture.statusLabel, 'Listening');
      await tester.tap(find.text('Stop listening')); await tester.pumpAndSettle();
      expect(capture.consent, isFalse); expect(capture.statusLabel, 'Stopped');
      expect(find.text('Start listening').hitTestable(), findsOneWidget);
      expect(find.text('Stop listening').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox()); setKorlixMeetingCopilotEnterpriseAccess(false);
    });
  }
}
