import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_campaign_budget.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

Map<String, dynamic> fixture({
  bool saved = true,
  String state = 'draft',
  int? version,
  String campaign = 'c',
}) => {
  'funnel_id': 'f',
  'campaign_id': campaign,
  'name': 'Autumn launch',
  'state': state,
  'campaign_version': 7,
  'daily_cents': 2500,
  'days': 4,
  'currency': 'USD',
  'version': version ?? (saved ? 1 : 0),
  'start_date': saved ? '2026-09-20' : null,
  'updated_at': saved || version != null ? '2026-09-22T10:00:00Z' : null,
  'as_of_date': '2026-09-22',
  'checked_at': '2026-09-22T10:00:00Z',
  'reporting_source': 'manual',
  'budget_enforced': false,
  'ad_publishing_ready': false,
  'reports': [
    {'day': '2026-09-19', 'spend_cents': 333},
    {'day': '2026-09-20', 'spend_cents': 1000},
    {'day': '2026-09-22', 'spend_cents': 12000},
  ],
  'pacing': saved
      ? {
          'end_date': '2026-09-23',
          'phase': 'active',
          'planned_total_cents': 10000,
          'recorded_spend_cents': 13000,
          'balance_cents': -3000,
          'completed_days': 2,
          'reported_days': 2,
          'reported_completed_days': 1,
          'completed_spend_cents': 1000,
          'reported_days_plan_cents': 2500,
          'reported_days_variance_cents': -1500,
          'missing_dates': ['2026-09-21'],
          'excluded_report_days': 1,
          'rows': [
            {'day': '2026-09-20', 'spend_cents': 1000, 'status': 'recorded'},
            {'day': '2026-09-21', 'spend_cents': null, 'status': 'missing'},
            {'day': '2026-09-22', 'spend_cents': 12000, 'status': 'today'},
            {'day': '2026-09-23', 'spend_cents': null, 'status': 'future'},
          ],
        }
      : null,
};
http.Response response(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(
      jsonEncode(data),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
FunnelClient client(Future<http.Response> Function(http.Request) handler) =>
    FunnelClient(
      backendBaseUrl: 'https://example.com',
      headersBuilder: () => {},
      client: MockClient(handler),
    );
Future<void> show(
  WidgetTester t,
  FunnelClient c, {
  ValueNotifier<int>? scope,
  String campaign = 'c',
  double scale = 1,
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: WfStyle.theme,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: FunnelCampaignBudget(
            client: c,
            funnelId: 'f',
            campaignId: campaign,
            scope: scope,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String label) async {
  await t.pumpAndSettle();
  await t.ensureVisible(find.text(label).last);
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      for (final f in ['MaterialIcons-Regular.otf', 'Roboto-Regular.ttf']) {
        final file = File('$root/bin/cache/artifacts/material_fonts/$f');
        if (file.existsSync()) {
          await (FontLoader(
                f.startsWith('Material') ? 'MaterialIcons' : 'Roboto',
              )..addFont(
                Future.value(ByteData.sublistView(file.readAsBytesSync())),
              ))
              .load();
        }
      }
    }
  });
  test(
    'Validator verifies identity, reporting boundaries and every derived total',
    () {
      expect(
        validateCampaignBudget(
          fixture(),
          'f',
          'c',
        )['pacing']['recorded_spend_cents'],
        13000,
      );
      expect(
        validateCampaignBudget(fixture(saved: false), 'f', 'c')['pacing'],
        isNull,
      );
      expect(
        validateCampaignBudget(
          fixture(saved: false, version: 2),
          'f',
          'c',
        )['version'],
        2,
      );
      for (final change in <void Function(Map<String, dynamic>)>[
        (d) => d['campaign_id'] = 'other',
        (d) => d['funnel_id'] = 'other',
        (d) => d['currency'] = 'JMD',
        (d) => d['budget_enforced'] = true,
        (d) => d['ad_publishing_ready'] = true,
        (d) => d['reporting_source'] = 'provider',
        (d) => d['as_of_date'] = '2026-09-23',
        (d) => d['start_date'] = '2026-02-30',
        (d) => d['reports'].add({'day': '2026-09-20', 'spend_cents': 1}),
        (d) => d['reports'][0]['spend_cents'] = -1,
        (d) => d['reports'][0]['day'] = '2026-09-23',
        (d) => d['pacing']['balance_cents'] = 999,
        (d) => d['pacing']['completed_spend_cents'] = 13000,
        (d) => d['pacing']['missing_dates'] = [],
        (d) => d['pacing']['rows'][1]['spend_cents'] = 0,
        (d) => d['pacing']['rows'][2]['status'] = 'recorded',
      ]) {
        final d = Map<String, dynamic>.from(jsonDecode(jsonEncode(fixture())));
        change(d);
        expect(
          () => validateCampaignBudget(d, 'f', 'c'),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  test(
    'Saved summary preserves exact window, unknown dates, partial today and spending boundary',
    () {
      final s = campaignBudgetSummary(
        validateCampaignBudget(fixture(), 'f', 'c'),
      );
      expect(s, contains('2026-09-20 through 2026-09-23 UTC'));
      expect(s, contains('Recorded spend: \$130.00 USD'));
      expect(s, contains('2026-09-21 UTC | missing | no entry'));
      expect(s, contains('2026-09-22 UTC | today | \$120.00 USD'));
      expect(s, contains('Completed-day coverage: 1/2'));
      expect(s, contains('not confirmed money available to spend'));
      expect(s, contains(campaignBudgetBoundary));
    },
  );
  for (final size in [
    const Size(1400, 1100),
    const Size(390, 844),
    const Size(320, 740),
  ]) {
    testWidgets('Budget totals and daily coverage fit ${size.width}', (
      t,
    ) async {
      await t.binding.setSurfaceSize(size);
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = client((_) async => response(fixture()));
      addTearDown(c.dispose);
      await show(t, c, scale: size.width == 320 ? 1.3 : 1);
      expect(find.text('Autumn launch'), findsOneWidget);
      expect(
        find.text('Recorded spend exceeds the total plan by \$30.00.'),
        findsOneWidget,
      );
      expect(find.text('1 completed days have no report.'), findsOneWidget);
      await tap(t, 'Daily coverage');
      await t.ensureVisible(find.text('2026-09-23 UTC'));
      await t.pumpAndSettle();
      expect(find.text('No entry · Missing report'), findsOneWidget);
      expect(find.text('\$120.00 recorded · Today · partial'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'Save validates date and sends only the exact optimistic versions',
    (t) async {
      final calls = <http.Request>[];
      final c = client((r) async {
        calls.add(r);
        return response(fixture(saved: r.method == 'POST'));
      });
      addTearDown(c.dispose);
      await show(t, c);
      await t.enterText(find.byType(TextField), '2026-02-30');
      await tap(t, 'Save reporting window');
      expect(calls.length, 1);
      expect(
        find.text('Enter YYYY-MM-DD within the past two years or next year.'),
        findsOneWidget,
      );
      await t.enterText(find.byType(TextField), '2026-09-20');
      await t.pumpAndSettle();
      final copy = t.widget<TextButton>(
        find.widgetWithText(TextButton, 'Copy saved summary'),
      );
      expect(copy.onPressed, isNull);
      await tap(t, 'Save reporting window');
      expect(calls.last.url.path, '/api/funnels/f/campaigns/c/budget/save');
      expect(jsonDecode(calls.last.body), {
        'version': 0,
        'campaign_version': 7,
        'start_date': '2026-09-20',
      });
      expect(find.text('Reporting window saved.'), findsOneWidget);
      expect(find.text('Daily coverage'), findsOneWidget);
    },
  );
  testWidgets('Clear confirms, retains records and uses the current version', (
    t,
  ) async {
    final calls = <http.Request>[];
    final c = client((r) async {
      calls.add(r);
      return response(
        r.method == 'POST' ? fixture(saved: false, version: 2) : fixture(),
      );
    });
    addTearDown(c.dispose);
    await show(t, c);
    await tap(t, 'Clear reporting window');
    expect(calls.length, 1);
    await tap(t, 'Clear window');
    expect(calls.last.url.path, '/api/funnels/f/campaigns/c/budget/clear');
    expect(jsonDecode(calls.last.body), {
      'version': 1,
      'campaign_version': 7,
      'confirmed': true,
    });
    expect(
      find.text('Reporting window cleared. Daily results are retained.'),
      findsOneWidget,
    );
    expect(find.text('Daily coverage'), findsNothing);
  });
  testWidgets(
    'Conflict clears stale totals and copying until an explicit reload',
    (t) async {
      final c = client(
        (r) async => r.method == 'POST'
            ? response({'error': 'Campaign changed. Refresh.'}, 409)
            : response(fixture()),
      );
      addTearDown(c.dispose);
      await show(t, c);
      await t.enterText(find.byType(TextField), '2026-09-19');
      await tap(t, 'Save reporting window');
      expect(find.text('Campaign changed. Refresh.'), findsOneWidget);
      expect(find.text('Autumn launch'), findsNothing);
      expect(find.text('Copy saved summary'), findsNothing);
      await tap(t, 'Refresh tracker');
      expect(find.text('Autumn launch'), findsOneWidget);
    },
  );
  testWidgets(
    'A failed refresh clears previous data instead of exporting stale totals',
    (t) async {
      var calls = 0;
      final c = client(
        (_) async => ++calls == 1
            ? response(fixture())
            : response({'error': 'Unavailable'}, 503),
      );
      addTearDown(c.dispose);
      await show(t, c);
      await tap(t, 'Refresh tracker');
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('Copy saved summary'), findsNothing);
      expect(find.text('Autumn launch'), findsNothing);
    },
  );
  testWidgets('Archived windows can be copied but not edited', (t) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = call.arguments['text'];
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final c = client((_) async => response(fixture(state: 'archived')));
    addTearDown(c.dispose);
    await show(t, c);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Save reporting window'), findsNothing);
    await tap(t, 'Copy saved summary');
    expect(copied, contains('Autumn launch'));
    expect(copied, contains(campaignBudgetBoundary));
  });
  testWidgets(
    'Workspace changes reject pending results and clear private content',
    (t) async {
      final pending = Completer<http.Response>(), scope = ValueNotifier(0);
      final c = client((_) => pending.future);
      addTearDown(c.dispose);
      addTearDown(scope.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FunnelCampaignBudget(
              client: c,
              funnelId: 'f',
              campaignId: 'c',
              scope: scope,
            ),
          ),
        ),
      );
      await t.pump();
      scope.value++;
      await t.pump();
      pending.complete(response(fixture()));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Your workspace changed. Close this tracker and open it again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Autumn launch'), findsNothing);
      expect(find.text('Copy saved summary'), findsNothing);
    },
  );
  testWidgets(
    'Access denial invalidates saved data and suppresses pending actions',
    (t) async {
      var calls = 0;
      final c = client(
        (_) async => ++calls == 1
            ? response(fixture())
            : response({'error': 'Denied'}, 403),
      );
      addTearDown(c.dispose);
      await show(t, c);
      await tap(t, 'Refresh tracker');
      expect(
        find.text(
          'Sign in with Enterprise access to view this budget tracker.',
        ),
        findsOneWidget,
      );
      expect(find.text('Autumn launch'), findsNothing);
      expect(find.text('Refresh tracker'), findsNothing);
    },
  );
  testWidgets('Changed client and campaign ignore the old response', (t) async {
    final pending = Completer<http.Response>();
    final old = client((_) => pending.future),
        fresh = client(
          (_) async =>
              response(fixture(campaign: 'new')..['name'] = 'New campaign'),
        );
    addTearDown(old.dispose);
    addTearDown(fresh.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FunnelCampaignBudget(
            client: old,
            funnelId: 'f',
            campaignId: 'c',
          ),
        ),
      ),
    );
    await t.pump();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FunnelCampaignBudget(
            client: fresh,
            funnelId: 'f',
            campaignId: 'new',
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    pending.complete(response(fixture()));
    await t.pumpAndSettle();
    expect(find.text('New campaign'), findsOneWidget);
    expect(find.text('Autumn launch'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
