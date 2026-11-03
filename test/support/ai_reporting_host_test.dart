import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/support/korlix_ai_reporting_host.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const receipt = 'korlix_report_23a1fa12-e789-4f38-bc1c-701df956d510';
const entry = Key('app-wide-report-ai-content');

class Fixture {
  final navigator = GlobalKey<NavigatorState>();
  final changes = ValueNotifier(0);
  final requests = <http.Request>[];
  String? account = 'fixture-account';
  Completer<Map<String, String>>? pendingHeaders;
  Completer<http.Response>? pendingResponse;
  int status = 202;
  String response = jsonEncode({'ok': true, 'reportId': receipt});
  late final client = MockClient((request) async {
    requests.add(request);
    return pendingResponse?.future ?? http.Response(response, status);
  });

  Future<void> mount(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      theme: korlixBuildTheme('korlix_blue'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: KorlixAiReportingHost(
          navigatorKey: navigator,
          sessionChanges: changes,
          accountScope: () => account,
          endpoint: Uri.https('fixture.test', '/api/report-output'),
          headersBuilder: () async => pendingHeaders?.future ??
              {'Authorization': 'Bearer fixture-token'},
          client: client,
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Builder(builder: (context) => Center(child: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Center(child: Text('Live voice fixture'))),
          )),
          child: const Text('Open live voice'),
        ))),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(entry));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, {String details = 'Live voice: please review the unsafe advice I heard.'}) async {
    await tester.tap(find.byKey(const Key('saved-report-reason')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unsafe or harmful').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('saved-report-details')), details);
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('saved-report-submit')));
    await tester.tap(find.byKey(const Key('saved-report-submit')));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('reporting stays available on a pushed route without navigating away', (tester) async {
    final f = Fixture();
    await f.mount(tester);
    await tester.tap(find.text('Open live voice'));
    await tester.pumpAndSettle();
    expect(find.byKey(entry), findsOneWidget);
    await f.open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Live voice fixture'), findsOneWidget);
    expect(f.requests, isEmpty);
    f.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(entry), findsOneWidget);
  });

  testWidgets('signed-out screens hide reporting and keep their navigator', (tester) async {
    final f = Fixture()..account = null;
    await f.mount(tester);
    final navigator = f.navigator.currentState;
    expect(find.byKey(entry), findsNothing);
    f.account = 'fixture-account';
    f.changes.value++;
    await tester.pumpAndSettle();
    expect(find.byKey(entry), findsOneWidget);
    expect(identical(f.navigator.currentState, navigator), isTrue);
  });

  testWidgets('description is required and success requires a durable receipt', (tester) async {
    final f = Fixture();
    await f.mount(tester);
    await f.open(tester);
    await f.fill(tester, details: '   ');
    await f.submit(tester);
    expect(find.text('Describe what needs review.'), findsOneWidget);
    expect(f.requests, isEmpty);
    await tester.enterText(find.byKey(const Key('saved-report-details')), 'Podcast: please review the advice in the final answer.');
    await f.submit(tester);
    expect(f.requests, hasLength(1));
    final request = f.requests.single;
    expect(request.url, Uri.https('fixture.test', '/api/report-output'));
    expect(request.headers['Authorization'], 'Bearer fixture-token');
    final body = jsonDecode(request.body) as Map;
    expect(body['appArea'], 'app_wide_ai_reporting');
    expect(body['reason'], 'Unsafe or harmful');
    expect(body['details'], 'Podcast: please review the advice in the final answer.');
    expect(body['prompt'], '');
    expect(body.containsKey('imageDataUrl'), isFalse);
    expect(find.text('Report received'), findsOneWidget);
    expect(find.textContaining(receipt), findsOneWidget);
  });

  testWidgets('an unconfirmed response preserves the draft and does not claim success', (tester) async {
    final f = Fixture()..response = '{"ok":true}';
    await f.mount(tester);
    await f.open(tester);
    await f.fill(tester);
    await f.submit(tester);
    expect(f.requests, hasLength(1));
    expect(find.text('Report received'), findsNothing);
    expect(find.textContaining('could not confirm'), findsOneWidget);
    expect(find.text('Live voice: please review the unsafe advice I heard.'), findsOneWidget);
  });

  testWidgets('account changes during credential refresh abort the request', (tester) async {
    final f = Fixture()..pendingHeaders = Completer<Map<String, String>>();
    await f.mount(tester);
    await f.open(tester);
    await f.fill(tester);
    await tester.tap(find.byKey(const Key('saved-report-submit')));
    await tester.pump();
    f.account = 'different-account';
    f.changes.value++;
    f.pendingHeaders!.complete({'Authorization': 'Bearer different-fixture-token'});
    await tester.pumpAndSettle();
    expect(f.requests, isEmpty);
    expect(find.text('Report received'), findsNothing);
    expect(find.textContaining('Your sign-in changed'), findsOneWidget);
  });

  testWidgets('repeated taps while submitting send only one report', (tester) async {
    final f = Fixture()..pendingResponse = Completer<http.Response>();
    await f.mount(tester);
    await f.open(tester);
    await f.fill(tester);
    await tester.tap(find.byKey(const Key('saved-report-submit')));
    await tester.pump();
    expect(tester.widget<TextButton>(find.byKey(entry)).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.byKey(const Key('saved-report-submit'))).onPressed, isNull);
    f.pendingResponse!.complete(http.Response(f.response, 202));
    await tester.pumpAndSettle();
    expect(f.requests, hasLength(1));
    expect(find.text('Report received'), findsOneWidget);
  });

  testWidgets('large text fits a narrow screen and typing does not cover controls', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final f = Fixture();
    await f.mount(tester, scale: 2);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(entry)).height, greaterThanOrEqualTo(48));
    await f.open(tester);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    expect(find.byKey(entry), findsNothing);
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(entry), findsOneWidget);
  });
}
