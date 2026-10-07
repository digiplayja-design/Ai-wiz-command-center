import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/support/korlix_ai_report_client.dart';
import 'package:ai_wiz_command_center/support/korlix_saved_output_report_dialog.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const reportId = 'korlix_report_23a1fa12-e789-4f38-bc1c-701df956d510';
final endpoint = Uri.https('reports.example.test', '/api/report-output');
final accepted = jsonEncode({'ok': true, 'reportId': reportId});

Future<String> submit(
  http.Client client, {
  String prompt = 'Saved prompt',
  String output = 'Saved response',
  String details = 'The statement is incorrect.',
  Duration timeout = const Duration(seconds: 30),
}) => submitKorlixAiReport(
  endpoint: endpoint,
  headers: {'Authorization': 'Bearer fixture-token'},
  contentId: 'saved-generation-id',
  reason: 'False or misleading',
  details: details,
  prompt: prompt,
  outputSummary: output,
  client: client,
  timeout: timeout,
);

class _DialogFixture {
  final revision = ValueNotifier(0);
  final submissions = <List<String>>[];
  Completer<String>? pending;
  Object? error;
  String? recorded;

  Future<void> open(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: korlixBuildTheme('korlix_blue'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                recorded = await showDialog<String>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => KorlixSavedOutputReportDialog(
                    sessionChanges: revision,
                    isSessionCurrent: () => revision.value == 0,
                    submitReport: (reason, details) async {
                      submissions.add([reason, details]);
                      if (error != null) throw error!;
                      return pending?.future ?? Future.value(reportId);
                    },
                  ),
                );
              },
              child: const Text('Report output'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Report output'));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String reason) async {
    await tester.tap(find.byKey(const Key('saved-report-reason')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(reason).last);
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final status in [200, 202]) {
    test(
      'HTTP $status confirms a durable receipt and sends actual context once',
      () async {
        final calls = <http.Request>[];
        final client = MockClient((request) async {
          calls.add(request);
          return http.Response(accepted, status);
        });
        expect(await submit(client), reportId);
        expect(calls, hasLength(1));
        final request = calls.single;
        expect(request.url, endpoint);
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer fixture-token');
        final body = jsonDecode(request.body) as Map;
        expect(body['contentId'], 'saved-generation-id');
        expect(body['prompt'], 'Saved prompt');
        expect(body['outputSummary'], 'Saved response');
        expect(body['reason'], 'False or misleading');
        expect(body['details'], 'The statement is incorrect.');
        expect(body.containsKey('userId'), isFalse);
        expect(body.containsKey('userEmail'), isFalse);
      },
    );
  }

  test(
    'malformed and non-durable responses never become success or alias retries',
    () async {
      for (final response in [
        http.Response('<html>Unavailable</html>', 200),
        http.Response('{"ok":true}', 200),
        http.Response('{"ok":true,"reportId":"unverified"}', 202),
        http.Response(accepted, 500),
        http.Response(accepted, 302),
      ]) {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return response;
        });
        await expectLater(
          submit(client),
          throwsA(isA<KorlixAiReportException>()),
        );
        expect(calls, 1);
      }
    },
  );

  test('known failures are actionable and never echo server secrets', () async {
    for (final entry in {
      401: 'Sign in',
      403: 'Sign in',
      429: 'Too many',
      413: 'too long',
      503: 'temporarily unavailable',
    }.entries) {
      final client = MockClient(
        (_) async => http.Response('private server error', entry.key),
      );
      await expectLater(
        submit(client),
        throwsA(
          isA<KorlixAiReportException>()
              .having((e) => e.message, 'message', contains(entry.value))
              .having(
                (e) => e.message,
                'no server data',
                isNot(contains('private server')),
              ),
        ),
      );
    }
  });

  test(
    'ambiguous timeout sends once and never retries after late acceptance',
    () async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final client = MockClient((_) {
        calls++;
        return pending.future;
      });
      await expectLater(
        submit(client, timeout: const Duration(milliseconds: 5)),
        throwsA(
          isA<KorlixAiReportException>().having(
            (e) => e.message,
            'uncertainty',
            contains('may already be saved'),
          ),
        ),
      );
      pending.complete(http.Response(accepted, 202));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
    },
  );

  test(
    'large Unicode and escaped content remains under the intake limit',
    () async {
      final client = MockClient((request) async {
        expect(utf8.encode(request.body).length, lessThan(28 * 1024));
        final body = jsonDecode(request.body) as Map;
        expect(body['prompt'], endsWith('[Excerpt shortened]'));
        expect(body['outputSummary'], endsWith('[Excerpt shortened]'));
        expect(body['details'], 'User detail preserved');
        return http.Response(accepted, 202);
      });
      expect(
        await submit(
          client,
          prompt: '🌧️\u0000' * 5000,
          output: '🌀\n' * 10000,
          details: 'User detail preserved',
        ),
        reportId,
      );
    },
  );

  test('oversized user details fail before sending anything', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(accepted, 200);
    });
    await expectLater(
      submit(client, details: 'x' * 40000),
      throwsA(isA<KorlixAiReportException>()),
    );
    expect(calls, 0);
  });

  late _DialogFixture fixture;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fixture = _DialogFixture();
  });
  tearDown(() => fixture.revision.dispose());

  testWidgets('reason is explicit and Other requires useful context', (
    tester,
  ) async {
    await fixture.open(tester);
    expect(find.textContaining('excerpt'), findsOneWidget);
    await tester.tap(find.byKey(const Key('saved-report-submit')));
    await tester.pump();
    expect(find.text('Choose a reason.'), findsOneWidget);
    expect(fixture.submissions, isEmpty);
    await fixture.select(tester, 'Other');
    await tester.tap(find.byKey(const Key('saved-report-submit')));
    await tester.pump();
    expect(find.text('Describe what needs review.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('saved-report-details')),
      ' Wrong receipt total ',
    );
    await tester.tap(find.byKey(const Key('saved-report-submit')));
    await tester.pumpAndSettle();
    expect(fixture.submissions.single, ['Other', 'Wrong receipt total']);
    expect(fixture.recorded, reportId);
  });

  testWidgets('duplicate activation while submitting only sends once', (
    tester,
  ) async {
    fixture.pending = Completer<String>();
    await fixture.open(tester);
    await fixture.select(tester, 'Unsafe or harmful');
    final callback = tester
        .widget<FilledButton>(find.byKey(const Key('saved-report-submit')))
        .onPressed!;
    callback();
    callback();
    await tester.pump();
    expect(fixture.submissions, hasLength(1));
    expect(find.text('Sending report…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('saved-report-submit')))
          .onPressed,
      isNull,
    );
    fixture.pending!.complete(reportId);
    await tester.pumpAndSettle();
    expect(fixture.recorded, reportId);
  });

  testWidgets(
    'failure retains entered context and does not claim receipt or retry automatically',
    (tester) async {
      fixture.error = const KorlixAiReportException(
        'We could not confirm whether your report was received.',
      );
      await fixture.open(tester);
      await fixture.select(tester, 'Privacy concern');
      await tester.enterText(
        find.byKey(const Key('saved-report-details')),
        'Please review the exposed detail.',
      );
      await tester.tap(find.byKey(const Key('saved-report-submit')));
      await tester.pumpAndSettle();
      expect(fixture.recorded, isNull);
      expect(fixture.submissions, hasLength(1));
      expect(find.textContaining('could not confirm'), findsOneWidget);
      expect(find.text('Please review the exposed detail.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 40));
      expect(fixture.submissions, hasLength(1));
    },
  );

  testWidgets(
    'session change disables old context and ignores late acceptance',
    (tester) async {
      fixture.pending = Completer<String>();
      await fixture.open(tester);
      await fixture.select(tester, 'False or misleading');
      await tester.tap(find.byKey(const Key('saved-report-submit')));
      await tester.pump();
      fixture.revision.value++;
      fixture.pending!.complete(reportId);
      await tester.pumpAndSettle();
      expect(fixture.recorded, isNull);
      expect(find.textContaining('Your sign-in changed'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('saved-report-submit')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('cancel sends nothing and 320px large text remains usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await fixture.open(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fixture.submissions, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
