import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/meeting_copilot/k135z_zoom_runtime_binding.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot_access.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot_route.dart';
import 'k135z_capture_controller_test.dart' show CaptureFixture;

void main() {
for (final width in [390.0, 1024.0]) {
testWidgets('connected startup takes meeting, consent and Start at width $width', (tester) async {
tester.view.physicalSize = Size(width, 900);
tester.view.devicePixelRatio = 1;
addTearDown(tester.view.resetPhysicalSize);
addTearDown(tester.view.resetDevicePixelRatio);
final f = CaptureFixture();
addTearDown(f.c.dispose);
setKorlixMeetingCopilotEnterpriseAccess(true);
final launch = K135zZoomLaunch(agentId:'agent', backendBaseUri:Uri.parse('https://api.example.test'),
headersBuilder:() => {'authorization':'Bearer offline'}, isCurrent:() => true);
await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(),
home:KorlixMeetingCopilotRoute(zoomLaunch:launch, zoomTransport:f.c.transport)));
await tester.pumpAndSettle();
expect(find.text('Pilot'), findsOneWidget);
expect(find.text('Prepare Zoom authorization'), findsNothing);
expect(f.calls, isEmpty); // Opening the screen only reads account/meeting data.
await tester.tap(find.text('Pilot'));
await tester.pumpAndSettle();
expect(f.calls, ['status']);
await tester.ensureVisible(find.byKey(const Key('g6n-consent')));
await tester.tap(find.byKey(const Key('g6n-consent')));
await tester.pumpAndSettle();
await tester.ensureVisible(find.byKey(const Key('start-listening-button')));
await tester.tap(find.byKey(const Key('start-listening-button')));
await tester.pumpAndSettle();
final capture = tester.widget<KorlixMeetingCopilotScreen>(find.byType(KorlixMeetingCopilotScreen)).capture!;
expect(capture.statusLabel, 'Listening');
expect(f.calls, ['status','consent','start']);
expect(tester.takeException(), isNull);
expect(find.byKey(const Key('zoom-connect-button')), findsNothing);
// A real visibility loss suspends capture, keeps the choice, and only reads on return.
tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
await tester.pump();
expect(capture.consent, isTrue);
expect(capture.canStart, isFalse);
final before = f.calls.length;
tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
await tester.pumpAndSettle();
expect(f.calls.skip(before), ['status']);
expect(capture.consent, isTrue);
expect(find.text('Resume Nova Copilot'), findsOneWidget);
await tester.tap(find.byKey(const Key('start-listening-button')));
await tester.pumpAndSettle();
expect(capture.statusLabel, 'Listening');
expect(f.calls.sublist(f.calls.length-4), ['status','pause','consent','start']);
await tester.tap(find.byKey(const Key('stop-listening-button')));
await tester.pumpAndSettle();
expect(capture.consent, isFalse);
expect(capture.statusLabel, 'Stopped');
expect(tester.takeException(), isNull);
await tester.pumpWidget(const SizedBox());
setKorlixMeetingCopilotEnterpriseAccess(false);
});
}
}
