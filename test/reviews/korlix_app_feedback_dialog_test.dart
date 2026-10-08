import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/reviews/korlix_app_feedback_dialog.dart';
import 'package:ai_wiz_command_center/support/korlix_ai_report_client.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _receipt = 'korlix_report_23a1fa12-e789-4f38-bc1c-701df956d510';

class _Fixture {
  final revision = ValueNotifier(0);
  final submissions = <List<String>>[];
  Completer<String>? pending;
  Object? error;
  String? result;

  Future<void> open(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: korlixBuildTheme('korlix_blue'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => KorlixAppFeedbackDialog(
                    sessionChanges: revision,
                    submitFeedback: (topic, details) async {
                      submissions.add([topic, details]);
                      if (error != null) throw error!;
                      return pending?.future ?? Future.value(_receipt);
                    },
                  ),
                );
              },
              child: const Text('Open feedback'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open feedback'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String topic) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(topic).last);
    await tester.pumpAndSettle();
  }
}

void main() {
  test('feedback goes once to the authenticated support queue without rating or conversation', () async {
    final calls = <http.Request>[];
    final client = MockClient((request) async {
      calls.add(request);
      return http.Response(jsonEncode({'ok': true, 'reportId': _receipt}), 202);
    });
    final result = await submitKorlixAppFeedback(
      baseUrl: 'https://backend.example.test/',
      headers: {'Authorization': 'Bearer fixture-token'},
      topic: 'Problem or bug',
      details: ' The save button did not respond. ',
      client: client,
    );
    expect(result, _receipt);
    expect(calls, hasLength(1));
    final request = calls.single;
    expect(
      request.url.toString(),
      'https://backend.example.test/api/report-output',
    );
    expect(request.headers['Authorization'], 'Bearer fixture-token');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['contentType'], 'app_feedback');
    expect(body['appArea'], 'app_feedback');
    expect(body['reason'], 'Problem or bug');
    expect(body['details'], 'The save button did not respond.');
    expect(body['prompt'], isEmpty);
    expect(body['outputSummary'], isEmpty);
    for (final key in [
      'rating',
      'score',
      'sentiment',
      'reviewEligible',
      'userId',
      'userEmail',
      'imageUrl',
    ]) {
      expect(body.containsKey(key), isFalse, reason: key);
    }
  });

  test(
    'unconfirmed submission never becomes success or an alias retry',
    () async {
      for (final response in [
        http.Response('{"ok":true}', 202),
        http.Response('<html>Unavailable</html>', 200),
        http.Response('{}', 401),
        http.Response('{}', 503),
      ]) {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return response;
        });
        await expectLater(
          submitKorlixAppFeedback(
            baseUrl: 'https://backend.example.test',
            headers: {'Authorization': 'Bearer fixture-token'},
            topic: 'General feedback',
            details: 'A suggestion',
            client: client,
          ),
          throwsA(isA<KorlixAiReportException>()),
        );
        expect(calls, 1);
      }
    },
  );

  late _Fixture fixture;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fixture = _Fixture();
  });

  testWidgets(
    'neutral feedback needs text, never a rating or positive answer',
    (tester) async {
      await fixture.open(tester);
      expect(
        find.textContaining('not posted as a store review'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.star), findsNothing);
      await tester.tap(find.byKey(const Key('app-feedback-submit')));
      await tester.pump();
      expect(find.text('Enter your feedback.'), findsOneWidget);
      expect(fixture.submissions, isEmpty);
      await tester.enterText(
        find.byKey(const Key('app-feedback-details')),
        ' Please add a shortcut. ',
      );
      await tester.tap(find.byKey(const Key('app-feedback-submit')));
      await tester.pumpAndSettle();
      expect(fixture.submissions.single, [
        'General feedback',
        'Please add a shortcut.',
      ]);
      expect(fixture.result, _receipt);
    },
  );

  for (final topic in [
    'Something I love',
    'Problem or bug',
    'Idea or suggestion',
    'Privacy or safety concern',
  ]) {
    testWidgets('$topic submits through the same private feedback flow', (
      tester,
    ) async {
      await fixture.open(tester);
      await fixture.choose(tester, topic);
      await tester.enterText(
        find.byKey(const Key('app-feedback-details')),
        'My feedback',
      );
      await tester.tap(find.byKey(const Key('app-feedback-submit')));
      await tester.pumpAndSettle();
      expect(fixture.submissions.single, [topic, 'My feedback']);
      expect(fixture.result, _receipt);
    });
  }

  testWidgets('repeat activation while pending submits only once', (
    tester,
  ) async {
    fixture.pending = Completer<String>();
    await fixture.open(tester);
    await tester.enterText(
      find.byKey(const Key('app-feedback-details')),
      'My feedback',
    );
    final callback = tester
        .widget<FilledButton>(find.byKey(const Key('app-feedback-submit')))
        .onPressed!;
    callback();
    callback();
    await tester.pump();
    expect(fixture.submissions, hasLength(1));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('app-feedback-submit')))
          .onPressed,
      isNull,
    );
    fixture.pending!.complete(_receipt);
    await tester.pumpAndSettle();
    expect(fixture.result, _receipt);
  });

  testWidgets(
    'an uncertain response preserves draft without success or automatic retry',
    (tester) async {
      fixture.error = const KorlixAiReportException(
        'We could not confirm whether your report was received.',
      );
      await fixture.open(tester);
      await tester.enterText(
        find.byKey(const Key('app-feedback-details')),
        'My feedback',
      );
      await tester.tap(find.byKey(const Key('app-feedback-submit')));
      await tester.pumpAndSettle();
      expect(find.text('My feedback'), findsOneWidget);
      expect(
        find.textContaining('whether your feedback was received'),
        findsOneWidget,
      );
      expect(fixture.result, isNull);
      await tester.pump(const Duration(seconds: 40));
      expect(fixture.submissions, hasLength(1));
    },
  );

  testWidgets(
    'account change clears draft and prevents submission under next account',
    (tester) async {
      await fixture.open(tester);
      await tester.enterText(
        find.byKey(const Key('app-feedback-details')),
        'Private feedback',
      );
      fixture.revision.value++;
      await tester.pumpAndSettle();
      expect(find.text('Private feedback'), findsNothing);
      expect(find.textContaining('Your sign-in changed'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('app-feedback-submit')))
            .onPressed,
        isNull,
      );
      expect(fixture.submissions, isEmpty);
    },
  );

  testWidgets('account change while sending ignores a late receipt', (
    tester,
  ) async {
    fixture.pending = Completer<String>();
    await fixture.open(tester);
    await tester.enterText(
      find.byKey(const Key('app-feedback-details')),
      'Private feedback',
    );
    await tester.tap(find.byKey(const Key('app-feedback-submit')));
    await tester.pump();
    fixture.revision.value++;
    fixture.pending!.complete(_receipt);
    await tester.pumpAndSettle();
    expect(fixture.result, isNull);
    expect(find.text('Private feedback'), findsNothing);
    expect(find.textContaining('Your sign-in changed'), findsOneWidget);
  });

  testWidgets(
    'cancel sends nothing and small screen with large text stays usable',
    (tester) async {
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
      expect(fixture.result, isNull);
    },
  );
}
