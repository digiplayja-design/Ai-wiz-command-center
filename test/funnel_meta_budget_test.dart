import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta_controls.dart';
import 'funnel_meta_controls_test.dart' as controls show fixture, app, fid, cid;
import 'funnel_meta_create_test.dart'
    as creation
    show clone, client, reply, tap, aid;

Map<String, dynamic> preview({int cents = 3500, bool active = false}) {
  final d = controls.fixture(), r = d['creation']['attempt']['resources'];
  final graph = controls.fixture(status: 'PAUSED')['observation']['graph'];
  if (active) {
    for (final key in ['campaign', 'ad_set', 'ad']) {
      graph['statuses'][key] = 'ACTIVE';
      graph['effective_statuses'][key] = 'ACTIVE';
    }
  }
  d['budget_preview'] = {
    'kind': 'budget',
    'status': {
      'resource': r['campaign'],
      'name': 'Created campaign',
      'status': graph['statuses']['campaign'],
      'effective_status': graph['effective_statuses']['campaign'],
    },
    'budget': {
      'resource': r['ad_set'],
      'daily_cents': d['managed_budget']['daily_cents'],
      'status': graph['statuses']['ad_set'],
      'effective_status': graph['effective_statuses']['ad_set'],
    },
    'daily_cents': cents,
    'increase': cents > d['managed_budget']['daily_cents'],
    'graph': cents > d['managed_budget']['daily_cents'] ? graph : null,
    'checked_at': '2026-09-24T01:02:00Z',
    'proof': 'YQ.${'a' * 43}',
  };
  return creation.clone(d);
}

Map<String, dynamic> receipt({bool unknown = false, bool progress = true}) {
  final d = preview();
  final observed = Map<String, dynamic>.from(d.remove('budget_preview'))
    ..remove('proof')
    ..remove('checked_at');
  d['latest_command'] = {
    'id': creation.aid,
    'sequence': 1,
    'action': 'budget',
    'state': unknown ? 'unknown' : 'confirmed',
    'created_at': '2026-09-24T01:02:00Z',
    'confirmed_at': unknown ? null : '2026-09-24T01:02:01Z',
    'daily_cents': 3500,
    'observed': observed,
    'steps': ['budget'],
    'progress': progress ? {'budget': 3500} : {},
  };
  if (unknown) {
    d['checks']['no_uncertain_command'] = false;
    d['activation_ready'] = false;
  } else {
    d['managed_budget']['daily_cents'] = 3500;
    d['managed_budget']['command_id'] = creation.aid;
    d['managed_budget']['confirmed_at'] = '2026-09-24T01:02:01Z';
  }
  return d;
}

Future<void> enter(WidgetTester t, String value) async {
  final field = find.widgetWithText(
    TextField,
    'New average daily budget (USD)',
  );
  await t.ensureVisible(field);
  await t.enterText(field, value);
  await t.pumpAndSettle();
}

Future<void> confirmations(WidgetTester t) async {
  await creation.tap(
    t,
    r'I confirm changing the average daily budget to $35.00 USD.',
  );
  await creation.tap(
    t,
    'I authorize this budget and acknowledge the spending impact, including earlier charges and variable daily spending.',
  );
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
    'K186 parses exact USD cents without exponents, fractions of a cent or separators',
    () {
      for (final pair in {
        '1': 100,
        '1.01': 101,
        '25.5': 2550,
        '10000.00': 1000000,
      }.entries) {
        expect(parseMetaBudget(pair.key), pair.value);
      }
      for (final value in [
        '0.99',
        '10000.01',
        '1e3',
        '25.001',
        '1,000',
        '-2',
        '+3',
        '01',
        'NaN',
        '',
      ]) {
        expect(parseMetaBudget(value), isNull);
      }
    },
  );
  test(
    'K186 validates paused/active budget proposals, history and original versus managed amounts',
    () {
      for (final d in [
        preview(),
        preview(active: true),
        preview(cents: 1000),
        receipt(),
        receipt(unknown: true),
        receipt(unknown: true, progress: false),
      ]) {
        expect(
          validateMetaControls(d, controls.fid, controls.cid)['source'],
          'meta_campaign_controls',
        );
      }
      for (final change in <void Function(Map)>[
        (d) => d['budget_enabled'] = false,
        (d) => d['managed_budget']['daily_cents'] = 3400,
        (d) => d['budget_preview']['budget']['resource'] = 'wrong',
        (d) => d['budget_preview']['daily_cents'] = 2500,
        (d) => d['budget_preview']['increase'] = false,
        (d) => d['budget_preview']['proof'] = 'bad',
        (d) => d['budget_preview']['graph']['effective_statuses']['ad'] =
            'DISAPPROVED',
        (d) => d['budget_preview']['graph']['statuses']['campaign'] = 'ACTIVE',
        (d) => d['budget_preview']['graph']['statuses']['other'] = 'ACTIVE',
      ]) {
        final d = preview();
        change(d);
        expect(
          () => validateMetaControls(d, controls.fid, controls.cid),
          throwsA(isA<FunnelException>()),
        );
      }
      for (final change in <void Function(Map)>[
        (d) => d['latest_command']['daily_cents'] = 3600,
        (d) => d['latest_command']['steps'] = ['campaign'],
        (d) => d['latest_command']['progress'] = {'budget': '3500'},
        (d) => d['latest_command']['progress'] = {},
        (d) => d['managed_budget']['command_id'] = null,
      ]) {
        final d = receipt();
        change(d);
        expect(
          () => validateMetaControls(d, controls.fid, controls.cid),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  testWidgets(
    'K186 local opening, review and two unchecked confirmations precede exact budget write',
    (t) async {
      final calls = <http.Request>[];
      final c = creation.client((r) async {
        calls.add(r);
        return creation.reply(
          r.url.path.endsWith('budget-preview')
              ? preview()
              : r.url.path.endsWith('budget-apply')
              ? receipt()
              : controls.fixture(),
        );
      });
      addTearDown(c.dispose);
      await t.pumpWidget(controls.app(c));
      await t.pumpAndSettle();
      expect(calls.length, 1);
      expect(calls.single.method, 'GET');
      await enter(t, '35.00');
      await creation.tap(t, 'Review budget change');
      expect(calls.last.url.path, endsWith('/meta-controls/budget-preview'));
      expect(jsonDecode(calls.last.body), {'daily_cents': 3500});
      final button = find.widgetWithText(
        FilledButton,
        'Apply Meta budget change',
      );
      expect(t.widget<FilledButton>(button).onPressed, isNull);
      await confirmations(t);
      await creation.tap(t, 'Apply Meta budget change');
      expect(jsonDecode(calls.last.body), {
        'proof': 'YQ.${'a' * 43}',
        'daily_cents': 3500,
        'confirmed': true,
        'spend_acknowledged': true,
      });
      expect(
        find.text('Last command: BUDGET CHANGE · META ACCEPTED'),
        findsOneWidget,
      );
      expect(
        find.text(r'Latest confirmed average daily budget: $35.00 USD'),
        findsOneWidget,
      );
      expect(find.text('Apply Meta budget change'), findsNothing);
    },
  );
  testWidgets(
    'K186 editing or refreshing discards the proposal and confirmations',
    (t) async {
      final c = creation.client(
        (r) async => creation.reply(
          r.url.path.endsWith('budget-preview')
              ? preview()
              : controls.fixture(),
        ),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(controls.app(c));
      await t.pumpAndSettle();
      await enter(t, '35');
      await creation.tap(t, 'Review budget change');
      await confirmations(t);
      await enter(t, '36');
      expect(find.text('Apply Meta budget change'), findsNothing);
      await enter(t, '35');
      await creation.tap(t, 'Review budget change');
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply Meta budget change'),
            )
            .onPressed,
        isNull,
      );
      await confirmations(t);
      await creation.tap(t, 'Refresh command record');
      expect(find.text('Apply Meta budget change'), findsNothing);
    },
  );
  testWidgets(
    'K186 uncertain budget shows accepted receipt and blocks further budget writes',
    (t) async {
      final c = creation.client(
        (r) async => creation.reply(receipt(unknown: true)),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(controls.app(c));
      await t.pumpAndSettle();
      expect(
        find.text('Last command: BUDGET CHANGE · OUTCOME UNCERTAIN'),
        findsOneWidget,
      );
      expect(find.text(r'Ad set budget: $35.00 USD'), findsOneWidget);
      expect(find.text('Review budget change'), findsNothing);
      expect(find.textContaining('Ads may be spending.'), findsOneWidget);
    },
  );
  testWidgets(
    'K186 apply failure clears proof and requires a new record/review',
    (t) async {
      final c = creation.client(
        (r) async => r.url.path.endsWith('budget-apply')
            ? http.Response(jsonEncode({'error': 'Budget changed'}), 409)
            : creation.reply(
                r.url.path.endsWith('budget-preview')
                    ? preview()
                    : controls.fixture(),
              ),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(controls.app(c));
      await t.pumpAndSettle();
      await enter(t, '35');
      await creation.tap(t, 'Review budget change');
      await confirmations(t);
      await creation.tap(t, 'Apply Meta budget change');
      expect(find.text('Apply Meta budget change'), findsNothing);
      expect(find.textContaining('Budget changed'), findsOneWidget);
      expect(find.text('Refresh command record'), findsOneWidget);
    },
  );
  testWidgets(
    'K186 workspace changes suppress a delayed private budget proposal',
    (t) async {
      final pending = Completer<http.Response>(), scope = ValueNotifier<int>(0);
      final c = creation.client(
        (r) async => r.url.path.endsWith('budget-preview')
            ? pending.future
            : creation.reply(controls.fixture()),
      );
      addTearDown(c.dispose);
      addTearDown(scope.dispose);
      await t.pumpWidget(controls.app(c, scope: scope));
      await t.pumpAndSettle();
      await enter(t, '35');
      await t.ensureVisible(find.text('Review budget change'));
      await t.tap(find.text('Review budget change'));
      await t.pump();
      scope.value++;
      await t.pump();
      pending.complete(creation.reply(preview()));
      await t.pumpAndSettle();
      expect(find.text('Apply Meta budget change'), findsNothing);
      expect(find.textContaining('workspace changed'), findsOneWidget);
      expect(find.textContaining('Meta budget observed:'), findsNothing);
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets(
      'K186 budget review fits real-font width $width with enlarged mobile text',
      (t) async {
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final c = creation.client(
          (r) async => creation.reply(preview(active: true)),
        );
        addTearDown(c.dispose);
        await t.pumpWidget(controls.app(c, scale: width == 320 ? 1.3 : 1));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Apply Meta budget change'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );
  }
}
