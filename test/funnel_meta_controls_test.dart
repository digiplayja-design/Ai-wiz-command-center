import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta_controls.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';
import 'funnel_meta_create_test.dart'
    as creation
    show fixture, clone, client, reply, tap, fid, cid, aid;

const fid = creation.fid, cid = creation.cid;
Map<String, dynamic> fixture({
  String? status,
  bool enabled = true,
  bool unknown = false,
}) {
  final c = creation.fixture(state: 'created');
  final resources = c['attempt']['resources'];
  final ready = enabled && !unknown;
  final graph = {
    'resources': resources,
    'statuses': {'campaign': 'PAUSED', 'ad_set': 'PAUSED', 'ad': 'PAUSED'},
    'effective_statuses': {
      'campaign': 'PAUSED',
      'ad_set': 'CAMPAIGN_PAUSED',
      'ad': 'CAMPAIGN_PAUSED',
    },
  };
  return creation.clone({
    'source': 'meta_campaign_controls',
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
      'identity_current': true,
      'schedule_open': true,
    },
    'activation_ready': ready,
    'latest_command': unknown
        ? {
            'id': creation.aid,
            'sequence': 1,
            'action': 'activate',
            'state': 'unknown',
            'created_at': '2026-09-23T12:01:00Z',
            'confirmed_at': null,
            'observed': {
              'status': {
                'resource': resources['campaign'],
                'name': 'Created campaign',
                'status': 'PAUSED',
                'effective_status': 'PAUSED',
              },
              'graph': graph,
              'can_activate': true,
              'can_pause': false,
              'reason': null,
            },
            'steps': ['ad', 'ad_set', 'campaign'],
            'progress': {'ad': 'ACTIVE'},
          }
        : null,
    if (status != null)
      'observation': {
        'status': {
          'resource': resources['campaign'],
          'name': 'Created campaign',
          'status': status,
          'effective_status': status,
        },
        'graph': status == 'PAUSED' && ready ? graph : null,
        'can_activate': status == 'PAUSED' && ready,
        'can_pause': status == 'ACTIVE' && ready,
        'checked_at': '2026-09-23T12:02:00Z',
        'reason': unknown ? 'Check Meta Ads Manager.' : null,
        'proof': ready && ['PAUSED', 'ACTIVE'].contains(status)
            ? 'YQ.${'a' * 43}'
            : null,
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
    body: FunnelMetaControls(
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
    'I confirm activation of this saved campaign, ad set and ad.',
  );
  await creation.tap(
    t,
    'I authorize ad spending using the saved average daily budget and schedule. The planned total is not a hard cap.',
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
    'K185 validates controls and rejects identity, capability, graph and proof mismatches',
    () {
      for (final status in [null, 'PAUSED', 'ACTIVE', 'ARCHIVED', 'DELETED']) {
        expect(
          validateMetaControls(fixture(status: status), fid, cid)['source'],
          'meta_campaign_controls',
        );
      }
      for (final change in <void Function(Map)>[
        (d) => d['campaign_id'] = 'other',
        (d) => d['activation_ready'] = false,
        (d) => d['checks']['extra'] = true,
        (d) => d['observation']['can_pause'] = true,
        (d) => d['observation']['graph']['effective_statuses']['ad'] =
            'DISAPPROVED',
        (d) => d['observation']['graph']['resources']['campaign'] = 'wrong',
        (d) => d['observation']['proof'] = 'bad',
        (d) => d['observation']['checked_at'] = 'bad',
      ]) {
        final d = fixture(status: 'PAUSED');
        change(d);
        expect(
          () => validateMetaControls(d, fid, cid),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  testWidgets(
    'K185 opening reads locally; explicit load and both unticked confirmations are required to activate',
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
      expect(find.text('Activate Meta campaign'), findsNothing);
      await creation.tap(t, 'Load current Meta status');
      expect(calls.length, 2);
      expect(jsonDecode(calls.last.body), {});
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Activate Meta campaign'),
            )
            .onPressed,
        isNull,
      );
      await confirm(t);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Activate Meta campaign'),
            )
            .onPressed,
        isNotNull,
      );
      await creation.tap(t, 'Activate Meta campaign');
      expect(jsonDecode(calls.last.body), {
        'proof': 'YQ.${'a' * 43}',
        'action': 'activate',
        'confirmed': true,
        'spend_acknowledged': true,
      });
      expect(find.text('Activate Meta campaign'), findsNothing);
    },
  );
  testWidgets(
    'K185 pause uses separate confirmation without spending authorization',
    (t) async {
      http.Request? applied;
      final c = creation.client((r) async {
        if (r.url.path.endsWith('/apply')) applied = r;
        return creation.reply(
          r.method == 'GET' || applied != null
              ? fixture()
              : fixture(status: 'ACTIVE'),
        );
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await creation.tap(t, 'Load current Meta status');
      expect(find.text('Activate Meta campaign'), findsNothing);
      await creation.tap(
        t,
        'I confirm pausing this Meta campaign. Earlier charges may still appear.',
      );
      await creation.tap(t, 'Pause Meta campaign');
      expect(jsonDecode(applied!.body)['spend_acknowledged'], false);
    },
  );
  testWidgets(
    'K185 refresh and failure discard pending confirmations and provider observation',
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
      await creation.tap(t, 'Load current Meta status');
      await confirm(t);
      await creation.tap(t, 'Refresh command record');
      expect(find.text('Activate Meta campaign'), findsNothing);
      await creation.tap(t, 'Load current Meta status');
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Activate Meta campaign'),
            )
            .onPressed,
        isNull,
      );
      fail = true;
      await creation.tap(t, 'Load current Meta status');
      expect(find.text('Activate Meta campaign'), findsNothing);
      expect(find.textContaining('Reload required'), findsOneWidget);
    },
  );
  testWidgets(
    'K185 unknown outcomes show spending warning and cannot issue another command',
    (t) async {
      final c = creation.client(
        (r) async => creation.reply(
          fixture(status: r.method == 'GET' ? null : 'ACTIVE', unknown: true),
        ),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Further KORLIX commands are blocked'),
        findsOneWidget,
      );
      expect(find.text('Ad: ACTIVE'), findsOneWidget);
      expect(find.text('Ad set: not confirmed'), findsOneWidget);
      await creation.tap(t, 'Load current Meta status');
      expect(find.text('Activate Meta campaign'), findsNothing);
      expect(find.text('Pause Meta campaign'), findsNothing);
    },
  );
  testWidgets(
    'K185 access loss and workspace change suppress delayed private observations',
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
      await t.ensureVisible(find.text('Load current Meta status'));
      await t.tap(find.text('Load current Meta status'));
      await t.pump();
      scope.value++;
      await t.pump();
      pending.complete(creation.reply(fixture(status: 'PAUSED')));
      await t.pumpAndSettle();
      expect(find.text('Activate Meta campaign'), findsNothing);
      expect(find.textContaining('Your workspace changed'), findsOneWidget);
    },
  );
  testWidgets(
    'K185 disabled platform has local record only and no activation action',
    (t) async {
      final c = creation.client(
        (r) async => creation.reply(fixture(enabled: false)),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(find.text('Load current Meta status'), findsNothing);
      expect(find.text('Activate Meta campaign'), findsNothing);
      expect(
        find.textContaining('after KORLIX Meta platform activation'),
        findsOneWidget,
      );
    },
  );
  test(
    'K185 partial command receipts must be an ordered prefix and confirmation requires every receipt',
    () {
      final d = fixture(unknown: true);
      expect(validateMetaControls(d, fid, cid)['latest_command']['progress'], {
        'ad': 'ACTIVE',
      });
      for (final change in <void Function(Map)>[
        (d) => d['latest_command']['progress'] = {'campaign': 'ACTIVE'},
        (d) => d['latest_command']['progress'] = {'ad': 'PAUSED'},
        (d) => d['latest_command']['steps'] = ['campaign', 'ad'],
        (d) => d['latest_command']['observed']['graph']['resources']['ad'] =
            'wrong',
        (d) => d['latest_command']['state'] = 'confirmed',
        (d) => d['latest_command']['observed']['can_activate'] = false,
      ]) {
        final changed = fixture(unknown: true);
        change(changed);
        expect(
          () => validateMetaControls(changed, fid, cid),
          throwsA(isA<FunnelException>()),
        );
      }
      final complete = fixture(unknown: true);
      complete['latest_command']['progress'] = {
        'ad': 'ACTIVE',
        'ad_set': 'ACTIVE',
        'campaign': 'ACTIVE',
      };
      expect(
        validateMetaControls(complete, fid, cid)['latest_command']['state'],
        'unknown',
      );
      complete['latest_command']['state'] = 'confirmed';
      complete['latest_command']['confirmed_at'] = '2026-09-23T12:05:00Z';
      complete['checks']['no_uncertain_command'] = true;
      complete['activation_ready'] = true;
      expect(
        validateMetaControls(complete, fid, cid)['latest_command']['state'],
        'confirmed',
      );
    },
  );
  testWidgets(
    'K185 missing or incomplete creation never exposes a control or crashes',
    (t) async {
      for (final state in [null, 'unknown']) {
        final d = fixture();
        d['creation'] = creation.fixture(state: state);
        if (state == 'unknown') d['creation']['attempt']['resources'] = {};
        d['checks']['creation_recorded'] = false;
        d['checks']['saved_content_current'] = state != null;
        d['checks']['identity_current'] = state != null;
        d['checks']['schedule_open'] = state != null;
        d['activation_ready'] = false;
        final c = creation.client((r) async => creation.reply(d));
        await t.pumpWidget(app(c));
        await t.pumpAndSettle();
        expect(find.textContaining('Complete paused creation'), findsOneWidget);
        expect(find.text('Load current Meta status'), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        c.dispose();
      }
    },
  );
  testWidgets(
    'K185 authorization loss clears private data and delayed responses',
    (t) async {
      final pending = Completer<http.Response>();
      final c = creation.client(
        (r) => r.method == 'GET'
            ? Future.value(creation.reply(fixture()))
            : pending.future,
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Load current Meta status'));
      await t.tap(find.text('Load current Meta status'));
      await t.pump();
      pending.complete(
        creation.reply({'error': 'Enterprise access required'}, 403),
      );
      await t.pumpAndSettle();
      expect(
        find.textContaining('Sign in with Enterprise access'),
        findsOneWidget,
      );
      expect(find.textContaining('Saved plan:'), findsNothing);
      expect(find.text('Activate Meta campaign'), findsNothing);
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('K185 controls fit ${width}px with enlarged real text', (
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
      await t.ensureVisible(find.text('Activate Meta campaign'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
