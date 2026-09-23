import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_controls.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';
import 'funnel_google_create_test.dart'
    as creation
    show fixture, clone, client, reply, tap, fid, cid, aid;

const fid = creation.fid, cid = creation.cid;
Map<String, dynamic> fixture({
  String? status,
  bool enabled = true,
  bool unknown = false,
  bool budget = false,
}) {
  final c = creation.fixture(state: 'created');
  final resources = c['attempt']['resources'];
  final ready = enabled && !unknown;
  final graph = {
    'resources': resources,
    'statuses': {'campaign': 'PAUSED', 'ad_group': 'PAUSED', 'ad': 'PAUSED'},
    'policy': 'APPROVED',
  };
  return creation.clone({
    'source': 'google_campaign_controls',
    'funnel_id': fid,
    'campaign_id': cid,
    'creation': c,
    'fingerprint': 'b' * 64,
    'checks': {
      'platform_enabled': enabled,
      'creation_recorded': true,
      'no_uncertain_command': !unknown,
      'command_capacity': true,
      'preparation_current': true,
      'saved_content_current': true,
      'schedule_open': true,
    },
    'activation_ready': ready,
    'budget_enabled': enabled && budget,
    'managed_budget': {
      'daily_cents': c['attempt']['snapshot']['plan']['daily_cents'],
      'original_daily_cents': c['attempt']['snapshot']['plan']['daily_cents'],
      'command_id': null,
      'confirmed_at': null,
    },
    'latest_command': unknown
        ? {
            'id': creation.aid,
            'sequence': 1,
            'action': 'activate',
            'state': 'unknown',
            'created_at': '2026-09-23T12:01:00Z',
            'confirmed_at': null,
            'observed': {},
          }
        : null,
    if (status != null)
      'observation': {
        'status': {
          'resource': resources['campaign'],
          'name': 'Created campaign',
          'status': status,
        },
        'graph': status == 'PAUSED' && ready ? graph : null,
        'can_activate': status == 'PAUSED' && ready,
        'can_pause': status == 'ENABLED' && ready,
        'checked_at': '2026-09-23T12:02:00Z',
        'reason': unknown ? 'Check Google Ads.' : null,
        'proof': ready && status != 'REMOVED' ? 'YQ.${'a' * 43}' : null,
      },
  });
}

Widget app(
  FunnelClient c, {
  ValueNotifier<int>? scope,
  double scale = 1,
  String funnel = fid,
}) => MaterialApp(
  theme: WfStyle.theme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: FunnelGoogleControls(
      client: c,
      funnelId: funnel,
      campaignId: cid,
      scope: scope,
    ),
  ),
);
Future<void> confirm(WidgetTester t) async {
  await creation.tap(
    t,
    'I confirm activation of this saved campaign, ad group and ad.',
  );
  await creation.tap(
    t,
    'I authorize ad spending using the latest confirmed average daily budget and saved schedule. The planned total is not a hard cap.',
  );
}

Map<String, dynamic> budgetFixture({
  int cents = 3000,
  String status = 'PAUSED',
}) {
  final d = fixture(budget: true);
  final old = d['managed_budget']['daily_cents'] as int;
  final resources = d['creation']['attempt']['resources'];
  d['budget_preview'] = {
    'kind': 'budget',
    'daily_cents': cents,
    'increase': cents > old,
    'status': {
      'resource': resources['campaign'],
      'name': 'Saved campaign',
      'status': status,
    },
    'budget': {'resource': resources['budget'], 'daily_cents': old},
    'graph': cents > old
        ? {
            'resources': resources,
            'statuses': {
              'campaign': status,
              'ad_group': 'PAUSED',
              'ad': 'PAUSED',
            },
            'policy': 'APPROVED',
          }
        : null,
    'checked_at': '2026-09-23T13:00:00Z',
    'proof': 'Yg.${'b' * 43}',
  };
  return d;
}

const budgetAck =
    'I authorize this budget and acknowledge the spending impact, including earlier charges and today’s highest budget.';
Future<void> reviewBudget(WidgetTester t, [String amount = '30.00']) async {
  await t.ensureVisible(find.byType(TextField));
  await t.enterText(find.byType(TextField), amount);
  await creation.tap(t, 'Review budget change');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      for (final name in ['MaterialIcons-Regular.otf', 'Roboto-Regular.ttf']) {
        final file = File('$root/bin/cache/artifacts/material_fonts/$name');
        if (file.existsSync()) {
          await (FontLoader(
                name.startsWith('Material') ? 'MaterialIcons' : 'Roboto',
              )..addFont(
                Future.value(ByteData.sublistView(file.readAsBytesSync())),
              ))
              .load();
        }
      }
    }
  });
  test(
    'K182 validates controls and rejects identity, capability, graph and proof mismatches',
    () {
      for (final status in [null, 'PAUSED', 'ENABLED', 'REMOVED']) {
        expect(
          validateGoogleControls(fixture(status: status), fid, cid)['source'],
          'google_campaign_controls',
        );
      }
      for (final change in <void Function(Map)>[
        (d) => d['campaign_id'] = 'other',
        (d) => d['activation_ready'] = false,
        (d) => d['checks']['extra'] = true,
        (d) => d['observation']['can_pause'] = true,
        (d) => d['observation']['graph']['policy'] = 'DISAPPROVED',
        (d) => d['observation']['graph']['resources']['campaign'] = 'wrong',
        (d) => d['observation']['proof'] = 'bad',
        (d) => d['observation']['checked_at'] = 'bad',
      ]) {
        final d = fixture(status: 'PAUSED');
        change(d);
        expect(
          () => validateGoogleControls(d, fid, cid),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  testWidgets(
    'K182 opening reads locally; explicit load and both unticked confirmations are required to activate',
    (t) async {
      final calls = <http.Request>[];
      final c = creation.client((r) async {
        calls.add(r);
        return creation.reply(
          r.url.path.endsWith('/inspect')
              ? fixture(status: 'PAUSED')
              : fixture(),
        );
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(calls.length, 1);
      expect(calls.single.method, 'GET');
      expect(find.text('Activate Google campaign'), findsNothing);
      await creation.tap(t, 'Load current Google status');
      expect(calls.length, 2);
      expect(jsonDecode(calls.last.body), {});
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Activate Google campaign'),
            )
            .onPressed,
        isNull,
      );
      await confirm(t);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Activate Google campaign'),
            )
            .onPressed,
        isNotNull,
      );
      await creation.tap(t, 'Activate Google campaign');
      expect(jsonDecode(calls.last.body), {
        'proof': 'YQ.${'a' * 43}',
        'action': 'activate',
        'confirmed': true,
        'spend_acknowledged': true,
      });
      expect(find.text('Activate Google campaign'), findsNothing);
    },
  );
  testWidgets(
    'K182 pause uses separate confirmation without spending authorization',
    (t) async {
      http.Request? applied;
      final c = creation.client((r) async {
        if (r.url.path.endsWith('/apply')) applied = r;
        return creation.reply(
          r.method == 'GET' || applied != null
              ? fixture()
              : fixture(status: 'ENABLED'),
        );
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await creation.tap(t, 'Load current Google status');
      expect(find.text('Activate Google campaign'), findsNothing);
      await creation.tap(
        t,
        'I confirm pausing this Google campaign. Earlier charges may still appear.',
      );
      await creation.tap(t, 'Pause Google campaign');
      expect(jsonDecode(applied!.body)['spend_acknowledged'], false);
    },
  );
  testWidgets(
    'K182 refresh and failure discard pending confirmations and provider observation',
    (t) async {
      bool fail = false;
      final c = creation.client(
        (r) async => fail
            ? creation.reply({'error': 'Reload required'}, 409)
            : creation.reply(
                r.url.path.endsWith('/inspect')
                    ? fixture(status: 'PAUSED')
                    : fixture(),
              ),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await creation.tap(t, 'Load current Google status');
      await confirm(t);
      await creation.tap(t, 'Refresh command record');
      expect(find.text('Activate Google campaign'), findsNothing);
      await creation.tap(t, 'Load current Google status');
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Activate Google campaign'),
            )
            .onPressed,
        isNull,
      );
      fail = true;
      await creation.tap(t, 'Load current Google status');
      expect(find.text('Activate Google campaign'), findsNothing);
      expect(find.textContaining('Reload required'), findsOneWidget);
    },
  );
  testWidgets(
    'K182 unknown outcomes show spending warning and cannot issue another command',
    (t) async {
      final c = creation.client(
        (r) async => creation.reply(
          fixture(status: r.method == 'GET' ? null : 'ENABLED', unknown: true),
        ),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Further KORLIX commands are blocked'),
        findsOneWidget,
      );
      await creation.tap(t, 'Load current Google status');
      expect(find.text('Activate Google campaign'), findsNothing);
      expect(find.text('Pause Google campaign'), findsNothing);
    },
  );
  testWidgets(
    'K182 access loss and workspace change suppress delayed private observations',
    (t) async {
      final pending = Completer<http.Response>(), scope = ValueNotifier(0);
      final c = creation.client(
        (r) => r.method == 'GET'
            ? Future.value(creation.reply(fixture()))
            : pending.future,
      );
      addTearDown(c.dispose);
      addTearDown(scope.dispose);
      await t.pumpWidget(app(c, scope: scope));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Load current Google status'));
      await t.tap(find.text('Load current Google status'));
      await t.pump();
      scope.value++;
      await t.pump();
      pending.complete(creation.reply(fixture(status: 'PAUSED')));
      await t.pumpAndSettle();
      expect(find.text('Activate Google campaign'), findsNothing);
      expect(find.textContaining('Your workspace changed'), findsOneWidget);
    },
  );
  testWidgets(
    'K182 disabled platform has local record only and no activation action',
    (t) async {
      final c = creation.client(
        (r) async => creation.reply(fixture(enabled: false)),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(find.text('Load current Google status'), findsNothing);
      expect(find.text('Activate Google campaign'), findsNothing);
      expect(
        find.textContaining('after KORLIX Google platform activation'),
        findsOneWidget,
      );
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('K182 controls fit ${width}px with enlarged real text', (
      t,
    ) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = creation.client(
        (r) async => creation.reply(fixture(status: 'PAUSED')),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c, scale: 1.3));
      await t.pumpAndSettle();
      await creation.tap(t, 'Review saved campaign content');
      await t.ensureVisible(find.text('Activate Google campaign'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
  test(
    'K183 validates exact cents, proposal identity, budget receipt and increase eligibility',
    () {
      for (final amount in ['1', '1.00', '1.01', '10000.00']) {
        expect(parseGoogleBudget(amount), isNotNull);
      }
      for (final amount in [
        '0.99',
        '10000.01',
        '1.001',
        '1e3',
        '-1',
        'NaN',
        '2,500',
        '01',
      ]) {
        expect(parseGoogleBudget(amount), isNull);
      }
      expect(parseGoogleBudget('12.34'), 1234);
      validateGoogleControls(budgetFixture(), fid, cid);
      validateGoogleControls(budgetFixture(cents: 100), fid, cid);
      for (final change in <void Function(Map)>[
        (d) => d['budget_enabled'] = false,
        (d) => d['budget_preview']['budget']['daily_cents'] = 999,
        (d) => d['budget_preview']['budget']['resource'] = 'wrong',
        (d) => d['budget_preview']['daily_cents'] = 1.5,
        (d) => d['budget_preview']['increase'] = false,
        (d) => d['budget_preview']['graph']['policy'] = 'DISAPPROVED',
        (d) => d['budget_preview']['status']['status'] = 'REMOVED',
        (d) => d['budget_preview']['proof'] = 'bad',
        (d) => d['managed_budget']['daily_cents'] = 500,
      ]) {
        final d = budgetFixture();
        change(d);
        expect(
          () => validateGoogleControls(d, fid, cid),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  testWidgets(
    'K183 budget change needs fresh proposal and two unticked confirmations',
    (t) async {
      final calls = <http.Request>[];
      final c = creation.client((r) async {
        calls.add(r);
        return creation.reply(
          r.url.path.endsWith('/budget-preview')
              ? budgetFixture()
              : fixture(budget: true),
        );
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(calls.length, 1);
      await reviewBudget(t);
      expect(jsonDecode(calls.last.body), {'daily_cents': 3000});
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply Google budget change'),
            )
            .onPressed,
        isNull,
      );
      await creation.tap(
        t,
        'I confirm changing the average daily budget to \$30.00 USD.',
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply Google budget change'),
            )
            .onPressed,
        isNull,
      );
      await creation.tap(t, budgetAck);
      await creation.tap(t, 'Apply Google budget change');
      expect(calls.last.url.path.endsWith('/budget-apply'), true);
      expect(jsonDecode(calls.last.body), {
        'daily_cents': 3000,
        'proof': 'Yg.${'b' * 43}',
        'confirmed': true,
        'spend_acknowledged': true,
      });
      expect(find.text('Apply Google budget change'), findsNothing);
    },
  );
  testWidgets(
    'K183 editing or refreshing the amount discards proposal and confirmations',
    (t) async {
      final c = creation.client(
        (r) async => creation.reply(
          r.url.path.endsWith('/budget-preview')
              ? budgetFixture()
              : fixture(budget: true),
        ),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await reviewBudget(t);
      await creation.tap(
        t,
        'I confirm changing the average daily budget to \$30.00 USD.',
      );
      await creation.tap(t, budgetAck);
      await t.ensureVisible(find.byType(TextField));
      await t.enterText(find.byType(TextField), '40.00');
      await t.pumpAndSettle();
      expect(find.text('Apply Google budget change'), findsNothing);
      await reviewBudget(t);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply Google budget change'),
            )
            .onPressed,
        isNull,
      );
      await creation.tap(t, 'Refresh command record');
      expect(find.text('Apply Google budget change'), findsNothing);
    },
  );
  testWidgets(
    'K183 budget unknown retains prior receipt and blocks new budget proposals',
    (t) async {
      final d = fixture(unknown: true, budget: true);
      d['latest_command']['action'] = 'budget';
      d['latest_command']['daily_cents'] = 3000;
      final c = creation.client((r) async => creation.reply(d));
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(find.textContaining('BUDGET CHANGE'), findsOneWidget);
      expect(find.text('Review budget change'), findsNothing);
      expect(
        find.textContaining('Requested average daily budget: \$30.00 USD'),
        findsOneWidget,
      );
    },
  );
  testWidgets('K183 delayed budget preview cannot survive workspace change', (
    t,
  ) async {
    final pending = Completer<http.Response>(), scope = ValueNotifier(0);
    final c = creation.client(
      (r) => r.method == 'GET'
          ? Future.value(creation.reply(fixture(budget: true)))
          : pending.future,
    );
    addTearDown(c.dispose);
    addTearDown(scope.dispose);
    await t.pumpWidget(app(c, scope: scope));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byType(TextField));
    await t.enterText(find.byType(TextField), '30.00');
    await t.ensureVisible(find.text('Review budget change'));
    await t.tap(find.text('Review budget change'));
    await t.pump();
    scope.value++;
    await t.pump();
    pending.complete(creation.reply(budgetFixture()));
    await t.pumpAndSettle();
    expect(find.text('Apply Google budget change'), findsNothing);
    expect(find.textContaining('Your workspace changed'), findsOneWidget);
  });
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets(
      'K183 budget proposal fits ${width}px with enlarged real text',
      (t) async {
        await t.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final c = creation.client(
          (r) async => creation.reply(
            r.method == 'GET'
                ? fixture(budget: true)
                : budgetFixture(status: 'ENABLED'),
          ),
        );
        addTearDown(c.dispose);
        await t.pumpWidget(app(c, scale: 1.3));
        await t.pumpAndSettle();
        await reviewBudget(t);
        await t.ensureVisible(find.text('Apply Google budget change'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );
  }
}
