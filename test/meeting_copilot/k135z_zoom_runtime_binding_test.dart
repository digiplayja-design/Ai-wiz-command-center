import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/meeting_copilot/k135z_zoom_runtime_binding.dart';
import '../../lib/meeting_copilot/korlix_zoom_connection_client.dart';

KorlixZoomTransportResponse status(bool connected) => KorlixZoomTransportResponse(
    statusCode: 200, body: jsonEncode({'status': {'connected': connected,
      'requires_reauthorization': false, 'access_token_expired': false}}));

void main() {
  late Map<String, String> headers;
  late bool current;
  late List<Uri> requests;
  late K135zZoomLaunch launch;
  setUp(() {
    headers = {'authorization': 'Bearer offline-user-one'};
    current = true;
    requests = <Uri>[];
    launch = K135zZoomLaunch(agentId: 'custom_agent_7',
        backendBaseUri: Uri.parse('https://api.korlix.test'),
        headersBuilder: () => headers, isCurrent: () => current);
  });
  K135zZoomRuntimeBinding binding({
      KorlixZoomTransportResponse Function(Uri)? reply,
      Future<bool> Function(Uri)? openUrl,
      DateTime Function()? now}) {
    final result = K135zZoomRuntimeBinding(launch: launch, now: now,
      openUrl: openUrl ?? (_) async => false,
      transport: ({required String method, required Uri uri,
          required Map<String, String> headers, Object? body}) async {
        requests.add(uri);
        expect(headers['authorization'], 'Bearer offline-user-one');
        expect(uri.queryParameters['agent_id'], 'custom_agent_7');
        if (reply != null) return reply(uri);
        if (uri.path.endsWith('/status')) return status(true);
        if (uri.path.endsWith('/upcoming')) return const KorlixZoomTransportResponse(
            statusCode: 200, body: '{"meetings":[{"id":"123","topic":"Pilot","is_host":true}]}');
        if (uri.path.endsWith('/start')) return const KorlixZoomTransportResponse(
            statusCode: 200, body: '{"authorization_url":"https://zoom.us/oauth/authorize?state=fixture"}');
        return const KorlixZoomTransportResponse(statusCode: 200, body: '{"ok":true}');
      });
    addTearDown(result.dispose);
    return result;
  }
  test('construction makes no request and does not claim connection', () {
    final b = binding();
    expect(requests, isEmpty);
    expect(b.connected, isFalse);
    expect(b.message, contains('not checked'));
  });
  test('selected agent follows status meetings and disconnect', () async {
    final b = binding();
    await b.refresh(); expect(b.connected, isTrue);
    await b.loadMeetings(); expect(b.meetings.single.id, '123');
    await b.disconnect(); expect(b.connected, isFalse);
    expect(b.meetings, isEmpty); expect(requests.length, 3);
  });
  test('authorization preparation alone never opens a URL', () async {
    int opened = 0;
    final b = binding(openUrl: (_) async { opened++; return true; });
    await b.prepareAuthorization();
    expect(opened, 0); expect(b.canOpenAuthorization, isTrue);
    expect(b.connected, isFalse);
    await b.openAuthorization(); await b.openAuthorization();
    expect(opened, 1); expect(b.connected, isFalse);
    expect(b.canOpenAuthorization, isFalse);
  });
  test('authorization expires locally rather than opening a stale state', () async {
    var now = DateTime.utc(2026, 9, 18);
    int opened = 0;
    final b = binding(now: () => now, openUrl: (_) async { opened++; return true; });
    await b.prepareAuthorization();
    now = now.add(const Duration(seconds: 61));
    b.checkContext(); await b.openAuthorization();
    expect(opened, 0); expect(b.canOpenAuthorization, isFalse);
  });
  test('authentication changes clear connection and block later requests', () async {
    final b = binding(); await b.refresh();
    headers = {'authorization': 'Bearer offline-user-two'};
    b.checkContext(); await b.loadMeetings(); await b.disconnect();
    expect(b.usable, isFalse); expect(b.connected, isFalse);
    expect(b.meetings, isEmpty); expect(requests.length, 1);
  });
  test('selected-agent change invalidates prepared authorization', () async {
    int opened = 0;
    final b = binding(openUrl: (_) async { opened++; return true; });
    await b.prepareAuthorization(); current = false;
    b.checkContext(); await b.openAuthorization();
    expect(opened, 0); expect(b.usable, isFalse);
  });
  test('late status result cannot cross account context', () async {
    final pending = Completer<KorlixZoomTransportResponse>();
    final b = K135zZoomRuntimeBinding(launch: launch,
      transport: ({required String method, required Uri uri,
          required Map<String, String> headers, Object? body}) => pending.future);
    addTearDown(b.dispose);
    final operation = b.refresh(); await Future<void>.delayed(Duration.zero);
    current = false; b.checkContext(); pending.complete(status(true)); await operation;
    expect(b.connected, isFalse); expect(b.usable, isFalse);
  });
  test('late completion after disposal does not notify or restore state', () async {
    final pending = Completer<KorlixZoomTransportResponse>();
    final b = K135zZoomRuntimeBinding(launch: launch,
      transport: ({required String method, required Uri uri,
          required Map<String, String> headers, Object? body}) => pending.future);
    final operation = b.refresh(); await Future<void>.delayed(Duration.zero);
    b.dispose(); pending.complete(status(true)); await operation;
    expect(b.connected, isFalse); expect(b.usable, isFalse);
  });
  test('unacknowledged disconnect is not reported as successful', () async {
    final b = binding(reply: (uri) => uri.path.endsWith('/status') ? status(true)
      : const KorlixZoomTransportResponse(statusCode: 200, body: '{"ok":false}'));
    await b.refresh(); await b.disconnect();
    expect(b.message, contains('not confirmed'));
    expect(b.message, isNot(contains('reports no Zoom')));
  });
  test('untrusted authorization host is rejected without launching', () async {
    int opened = 0;
    final b = binding(reply: (_) => const KorlixZoomTransportResponse(statusCode: 200,
      body: '{"authorization_url":"https://attacker.invalid/oauth/authorize?state=fixture"}'),
      openUrl: (_) async { opened++; return true; });
    await b.prepareAuthorization(); await b.openAuthorization();
    expect(opened, 0); expect(b.canOpenAuthorization, isFalse);
  });
  test('missing authentication and invalid explicit agent fail closed', () {
    expect(() => K135zZoomLaunch(agentId: 'nova',
      backendBaseUri: Uri.parse('https://api.korlix.test'),
      headersBuilder: () => {}, isCurrent: () => true), throwsStateError);
    expect(() => K135zZoomLaunch(agentId: ' ', backendBaseUri: launch.backendBaseUri,
      headersBuilder: () => headers, isCurrent: () => true), throwsStateError);
  });
}
