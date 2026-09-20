import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../lib/meeting_copilot/k135z_copilot_entry.dart';
import '../../lib/meeting_copilot/k135z_zoom_runtime_binding.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot_access.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot_route.dart';
import 'k135z_capture_controller_test.dart' show CaptureFixture;

const pref = 'k135z.copilot.agent.v1.api.example.test.user';
class EntryFixture {
  final capture = CaptureFixture();
  final auth = ValueNotifier(0);
  final requests = <String>[];
  String? token = 'offline';
  String tier = 'enterprise';
  int code = 200;
  Completer<void>? hold;
  List<Map<String, Object>> agents = [
    {'id':'agent','name':'Nova','active':true},
    {'id':'other','name':'Other agent','active':true},
  ];
  late final client = MockClient((req) async {
    expectSync(req.method, 'GET'); expectSync(req.followRedirects, isFalse);
    final authorization = req.headers['Authorization'];
    requests.add('${req.url.path}:$authorization');
    if (hold != null && authorization == 'Bearer offline') await hold!.future;
    if (code != 200) return http.Response('{}', code);
    return http.Response(jsonEncode(req.url.path == '/api/me'
      ? {'user':{'id':authorization == 'Bearer offline' ? 'user' : 'second-user'},'profile':{'tier':tier}}
      : {'ok':true,'agents':agents}), 200);
  });
  Widget app({K135zZoomLaunch? launch}) => MaterialApp(
    home: const Scaffold(body: Text('Korlix home')),
    initialRoute: '/meeting-copilot',
    onGenerateRoute: (settings) => settings.name == '/meeting-copilot'
      ? MaterialPageRoute(settings:RouteSettings(name:settings.name, arguments:launch), builder: (_) =>
        K135zCopilotEntry(backendBaseUri:Uri.parse('https://api.example.test'),
          headersBuilder:() => {if (token != null) 'authorization':'Bearer $token'},
          authChanges:auth, client:client, zoomTransport:capture.c.transport)) : null,
  );
  void dispose() { capture.c.dispose(); auth.dispose(); client.close(); }
}

void main() {
  setUp(() { SharedPreferences.setMockInitialValues({}); setKorlixMeetingCopilotEnterpriseAccess(false); });
  tearDown(() => setKorlixMeetingCopilotEnterpriseAccess(false));
  testWidgets('reload with no route argument restores the chosen agent; Start remains explicit', (tester) async {
    final f = EntryFixture(); addTearDown(f.dispose);
    await tester.pumpWidget(f.app()); await tester.pumpAndSettle();
    expect(find.text('Nova'), findsOneWidget); expect(f.capture.calls, isEmpty);
    await tester.tap(find.text('Nova')); await tester.pumpAndSettle();
    expect(find.text('Start listening'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString(pref), 'agent');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(f.app()); await tester.pumpAndSettle();
    expect(find.text('Start listening'), findsOneWidget); expect(f.capture.calls, isEmpty);
    expect(find.text('Open Meeting Copilot from your selected agent in Agent Hub.'), findsNothing);
    await tester.tap(find.text('Start listening')); await tester.pumpAndSettle();
    expect(tester.widget<KorlixMeetingCopilotScreen>(find.byType(KorlixMeetingCopilotScreen)).capture!.statusLabel, 'Listening');
    await tester.tap(find.text('Stop listening')); await tester.pumpAndSettle();
    expect(f.capture.calls, ['status','consent','start','status','stop']);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Agent Hub navigation remembers its explicit agent for a later reload', (tester) async {
    final f = EntryFixture(); addTearDown(f.dispose);
    final launch = K135zZoomLaunch(agentId:'agent', backendBaseUri:Uri.parse('https://api.example.test'),
      headersBuilder:() => {'authorization':'Bearer offline'}, isCurrent:() => true);
    await tester.pumpWidget(f.app(launch:launch)); await tester.pumpAndSettle();
    expect(find.text('Start listening'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString(pref), 'agent');
    expect(f.capture.calls, isEmpty); await tester.pumpWidget(const SizedBox());
  });
  testWidgets('sign-in arriving after the route opens restores without another navigation', (tester) async {
    SharedPreferences.setMockInitialValues({pref:'agent'});
    final f = EntryFixture()..token = null; addTearDown(f.dispose);
    await tester.pumpWidget(f.app()); await tester.pumpAndSettle();
    expect(find.text('Sign in to restore Nova Meeting Copilot.'), findsOneWidget);
    expect(f.requests, isEmpty);
    f.token = 'offline'; f.auth.value++; await tester.pumpAndSettle();
    expect(find.text('Start listening'), findsOneWidget);
    f.token = null; f.auth.value++; await tester.pumpAndSettle();
    expect(find.text('Start listening'), findsNothing);
    expect(f.capture.calls, isEmpty); await tester.pumpWidget(const SizedBox());
  });
  testWidgets('an account switch ignores late data and does not inherit another user preference', (tester) async {
    SharedPreferences.setMockInitialValues({pref:'agent'});
    final f = EntryFixture()..hold = Completer<void>(); addTearDown(f.dispose);
    await tester.pumpWidget(f.app()); await tester.pump();
    f.token = 'second'; f.auth.value++;
    f.hold!.complete(); await tester.pumpAndSettle();
    expect(find.text('Choose your agent once. Copilot will remember it for your next visit.'), findsOneWidget);
    expect(find.text('Start listening'), findsNothing);
    expect(f.requests.where((r) => r == '/api/live-convo/agents:Bearer offline'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('stale enterprise UI does not override the current account tier', (tester) async {
    setKorlixMeetingCopilotEnterpriseAccess(true);
    final f = EntryFixture()..tier = 'basic'; addTearDown(f.dispose);
    await tester.pumpWidget(f.app()); await tester.pumpAndSettle();
    expect(find.text('Enterprise upgrade required'), findsOneWidget);
    expect(f.requests.length, 1); expect(f.capture.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed restoration has a working Retry button', (tester) async {
    SharedPreferences.setMockInitialValues({pref:'agent'});
    final f = EntryFixture()..code = 503; addTearDown(f.dispose);
    await tester.pumpWidget(f.app()); await tester.pumpAndSettle();
    expect(find.text('Retry connection'), findsOneWidget);
    f.code = 200; await tester.tap(find.text('Retry connection')); await tester.pumpAndSettle();
    expect(find.text('Start listening'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('deleted or disabled remembered agents require a fresh choice', (tester) async {
    SharedPreferences.setMockInitialValues({pref:'agent'});
    final f = EntryFixture(); addTearDown(f.dispose); f.agents.first['active'] = false;
    await tester.pumpWidget(f.app()); await tester.pumpAndSettle();
    expect(find.text('Nova'), findsNothing); expect(find.text('Other agent'), findsOneWidget);
    expect(find.text('Start listening'), findsNothing); expect(f.capture.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('route binds when entitlement arrives after a valid launch', (tester) async {
    final f = CaptureFixture(); addTearDown(f.c.dispose);
    final launch = K135zZoomLaunch(agentId:'agent', backendBaseUri:Uri.parse('https://api.example.test'),
      headersBuilder:() => {'authorization':'Bearer offline'}, isCurrent:() => true);
    await tester.pumpWidget(MaterialApp(home:KorlixMeetingCopilotRoute(zoomLaunch:launch, zoomTransport:f.c.transport)));
    await tester.pumpAndSettle(); setKorlixMeetingCopilotEnterpriseAccess(true);
    await tester.pumpAndSettle();
    expect(find.text('Meeting: Pilot'), findsOneWidget); expect(f.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
