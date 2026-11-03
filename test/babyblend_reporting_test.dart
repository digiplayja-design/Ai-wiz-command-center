import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_wiz_command_center/babyblend/babyblend_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'babyblend_test.dart' as fixture;

const receipt = 'korlix_report_30000000-0000-4000-8000-000000000001';

class Reports {
  final bodies = <Map<String, dynamic>>[];
  Completer<void>? sent;
  Completer<http.Response>? pending;
  String account = fixture.token('owner');
  final revision = ValueNotifier(0);

  late final client = fixture.FakeBlend(
    headersBuilder: () => {'Authorization': 'Bearer $account'},
    sessionChanges: revision,
    transport: MockClient((request) async {
      expect(request.url.path, '/api/report-output');
      expect(request.headers['Authorization'], 'Bearer $account');
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (sent?.isCompleted == false) sent!.complete();
      return pending == null
          ? http.Response(jsonEncode({'ok': true, 'reportId': receipt}), 202)
          : await pending!.future;
    }),
  );

  void prepare() {
    final old = fixture.asset('older-portrait', kind: 'portrait');
    old['details']['age'] = 'child';
    old['details']['style'] = 'artistic';
    client.assets.addAll([
      fixture.asset('newer-portrait', kind: 'portrait'),
      old,
    ]);
    client.jobs = [fixture.makeJob('newer-portrait', state: 'completed')];
  }
}

Future<void> chooseReason(WidgetTester tester) async {
  await fixture.tap(tester, find.byKey(const Key('saved-report-reason')));
  await fixture.tap(tester, find.text('Unsafe or harmful').last);
  await tester.enterText(
    find.byKey(const Key('saved-report-details')),
    'Please review this portrait.',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> send(WidgetTester tester, Reports reports) async {
  final button = find.byKey(const Key('saved-report-submit'));
  await tester.ensureVisible(button);
  await tester.runAsync(() async {
    reports.sent = Completer<void>();
    await tester.tap(button);
    await reports.sent!.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('result report is in-app and cancellation sends or fetches nothing', (
    tester,
  ) async {
    final reports = Reports()..prepare();
    await fixture.show(tester, reports.client);
    await fixture.tap(tester, find.byKey(const Key('babyblend-result-report')));
    expect(find.textContaining('adult reference photos will not be attached'), findsOneWidget);
    await fixture.tap(tester, find.text('Cancel'));
    expect(reports.client.downloadedIds, isEmpty);
    expect(reports.bodies, isEmpty);
    expect(find.text('Your little possibility'), findsOneWidget);
    await fixture.close(tester);
    reports.revision.dispose();
  });

  testWidgets('gallery report attaches the selected older portrait and its creation options', (
    tester,
  ) async {
    final reports = Reports()..prepare();
    await fixture.show(tester, reports.client, width: 320, scale: 1.25);
    await fixture.gallery(tester);
    await fixture.tap(
      tester,
      find.byKey(const ValueKey('babyblend-gallery-report-older-portrait')),
    );
    await chooseReason(tester);
    await send(tester, reports);
    expect(reports.client.downloadedIds, ['older-portrait']);
    final body = reports.bodies.single;
    expect(body['appArea'], 'babyblend');
    expect(body['contentType'], 'image');
    expect(body['contentId'], 'older-portrait');
    expect(body['prompt'], contains('Age: Child. Style: Artistic.'));
    expect(body['imageDataUrl'], startsWith('data:image/png;base64,'));
    expect(jsonEncode(body), isNot(contains('source-1')));
    expect(jsonEncode(body), isNot(contains('source-2')));
    expect(find.textContaining('Report received.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
    reports.revision.dispose();
  });

  testWidgets('unconfirmed delivery retains the draft and duplicate submission stays disabled', (
    tester,
  ) async {
    final reports = Reports()..prepare();
    await fixture.show(tester, reports.client);
    await fixture.tap(tester, find.byKey(const Key('babyblend-result-report')));
    await chooseReason(tester);
    await tester.runAsync(() async {
      reports.pending = Completer<http.Response>();
    });
    await send(tester, reports);
    final button = find.byKey(const Key('saved-report-submit'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(button);
    expect(reports.bodies, hasLength(1));
    await tester.runAsync(() async {
      reports.pending!.complete(http.Response('{"ok":true}', 202));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('could not confirm whether your report was received'), findsOneWidget);
    expect(find.text('Please review this portrait.'), findsOneWidget);
    expect(find.textContaining('Report received.'), findsNothing);
    expect(reports.bodies, hasLength(1));
    await fixture.tap(tester, find.text('Close'));
    await fixture.close(tester);
    reports.revision.dispose();
  });

  testWidgets('changing accounts closes an open report and clears private portraits', (
    tester,
  ) async {
    final reports = Reports()..prepare();
    await fixture.show(tester, reports.client);
    await fixture.tap(tester, find.byKey(const Key('babyblend-result-report')));
    reports.account = fixture.token('another-owner');
    reports.revision.value++;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saved-report-submit')), findsNothing);
    expect(find.textContaining('Your session changed.'), findsOneWidget);
    expect(reports.bodies, isEmpty);
    await fixture.close(tester);
    reports.revision.dispose();
  });

  test('account changes during portrait retrieval prevent report transmission', () async {
    final reports = Reports()..prepare();
    final image = Completer<Uint8List>();
    reports.client.pendingImage = image.future;
    final pending = reports.client.reportPortrait(
      id: 'older-portrait',
      age: 'Child',
      style: 'Artistic',
      reason: 'Unsafe or harmful',
      details: 'Please review this portrait.',
    );
    await Future<void>.delayed(Duration.zero);
    reports.account = fixture.token('another-owner');
    reports.revision.value++;
    image.complete(fixture.photo);
    await expectLater(pending, throwsA(isA<BabyBlendException>()));
    expect(reports.bodies, isEmpty);
    reports.client.dispose();
    reports.revision.dispose();
  });
}
