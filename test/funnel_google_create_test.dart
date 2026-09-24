import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_create.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';
import 'funnel_google_preflight_test.dart'
    as preparation
    show fixture, fid, cid;

const fid = preparation.fid,
    cid = preparation.cid,
    aid = '00000000-0000-4000-8000-000000000099';
Map<String, dynamic> clone(Map m) => jsonDecode(jsonEncode(m));
Map<String, dynamic> fixture({String? state, bool enabled = true}) {
  final prep = preparation.fixture();
  final setup = prep['setup']['current_snapshot'];
  final draft = clone({
    'search_language_mode': 'automatic_from_creative_v1',
    'plan': setup['campaign'],
    'page': setup['landing_page'],
    'identity': setup['google_ads'],
    'creative': prep['creative']['assets'],
    'keywords': prep['keywords']['assets'],
    'targeting': prep['targeting']['assets'],
  });
  final account = draft['identity']['account']['id'];
  final days = draft['plan']['days'] as int;
  return clone({
    'source': 'google_paused_creation',
    'funnel_id': fid,
    'campaign_id': cid,
    'fingerprint': 'a' * 64,
    'checks': {
      'platform_enabled': enabled,
      'preparation_complete': true,
      'maximize_clicks': true,
      'account_calendar': true,
      'no_previous_attempt': state == null,
    },
    'create_ready': enabled && state == null,
    'today': '2026-09-23',
    'latest_start': '2026-10-23',
    'preparation': prep,
    'draft': draft,
    'ad_publishing_ready': false,
    'activation_supported': false,
    'attempt': state == null
        ? null
        : {
            'id': aid,
            'state': state,
            'snapshot': {
              ...draft,
              'start_date': '2026-09-23',
              'end_date': DateTime.utc(2026, 9, 23)
                  .add(Duration(days: days - 1))
                  .toIso8601String()
                  .substring(0, 10),
              'provider_name': 'KORLIX $aid',
              'no_eu_political_ads': true,
              'budget_acknowledged': true,
            },
            'resources': state == 'created'
                ? {
                    'budget': 'customers/$account/campaignBudgets/101',
                    'campaign': 'customers/$account/campaigns/102',
                    'ad_group': 'customers/$account/adGroups/103',
                    'ad': 'customers/$account/adGroupAds/103~104',
                  }
                : null,
            'created_at': '2026-09-23T12:00:00Z',
            'completed_at': state == 'created' ? '2026-09-23T12:01:00Z' : null,
          },
  });
}

http.Response reply(Map m, [int status = 200]) => http.Response(
  jsonEncode(m),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
FunnelClient client(Future<http.Response> Function(http.Request) fn) =>
    FunnelClient(
      backendBaseUrl: 'https://example.com',
      headersBuilder: () => {},
      client: MockClient(fn),
    );
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
    body: FunnelGoogleCreate(
      client: c,
      funnelId: funnel,
      campaignId: cid,
      scope: scope,
    ),
  ),
);
Future<void> tap(WidgetTester t, String text) async {
  await t.pumpAndSettle();
  await t.ensureVisible(find.text(text).last);
  await t.pumpAndSettle();
  await t.tap(find.text(text).last);
  await t.pumpAndSettle();
}

Future<void> confirm(WidgetTester t) async {
  for (final text in [
    'Create the campaign, ad group and ad paused. I am not activating ad delivery.',
    'I understand this is an average daily budget, not a hard daily or total cap.',
    'I confirm this campaign does not contain EU political advertising.',
  ]) {
    await tap(t, text);
  }
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
    'K181 validates current and historical creation records and rejects mismatched details',
    () {
      for (final state in [null, 'unknown', 'created']) {
        expect(
          validateGoogleCreation(fixture(state: state), fid, cid)['source'],
          'google_paused_creation',
        );
      }
      for (final change in <void Function(Map)>[
        (d) => d['create_ready'] = false,
        (d) => d['activation_supported'] = true,
        (d) => d['checks']['extra'] = true,
        (d) => d['draft']['plan']['daily_cents'] = 9900,
        (d) => d['latest_start'] = '2026-10-24',
        (d) => d['preparation']['campaign_id'] = 'other',
      ]) {
        final d = fixture();
        change(d);
        expect(
          () => validateGoogleCreation(d, fid, cid),
          throwsA(isA<FunnelException>()),
        );
      }
      for (final change in <void Function(Map)>[
        (d) =>
            d['attempt']['snapshot']['identity']['account']['currency'] = 'EUR',
        (d) => d['attempt']['snapshot']['provider_name'] = 'wrong',
        (d) => d['attempt']['resources']['campaign'] =
            'customers/1111111111/campaigns/102',
        (d) => d['attempt']['resources']['ad'] =
            'customers/${d['draft']['identity']['account']['id']}/adGroupAds/777~104',
        (d) => d['attempt']['completed_at'] = null,
        (d) => d['attempt']['snapshot']['end_date'] = '2026-12-31',
      ]) {
        final d = fixture(state: 'created');
        change(d);
        expect(
          () => validateGoogleCreation(d, fid, cid),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  test(
    'K189 new language contract and legacy history are distinct and validated',
    () {
      final current = fixture(state: 'created');
      expect(
        googleCreationSummary(current),
        contains('Language matching: automatic from ads and landing page.'),
      );
      expect(
        googleCreationSummary(current),
        contains('Content languages (planning):'),
      );
      final legacy = fixture(state: 'created');
      legacy['attempt']['snapshot'].remove('search_language_mode');
      expect(
        validateGoogleCreation(legacy, fid, cid)['attempt']['state'],
        'created',
      );
      expect(
        googleCreationSummary(legacy),
        contains('Language settings: historical manual criteria'),
      );
      final oldDraft = fixture();
      oldDraft['draft'].remove('search_language_mode');
      expect(
        () => validateGoogleCreation(oldDraft, fid, cid),
        throwsA(isA<FunnelException>()),
      );
      for (final mode in [null, 'automatic', 1, <String, dynamic>{}]) {
        final bad = fixture(state: 'created');
        bad['attempt']['snapshot']['search_language_mode'] = mode;
        expect(
          () => validateGoogleCreation(bad, fid, cid),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  testWidgets(
    'K181 opening and refresh are local reads with clear activation boundary',
    (t) async {
      final methods = <String>[];
      final c = client((r) async {
        methods.add(r.method);
        return reply(fixture(enabled: false));
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(find.text('Create paused Google campaign'), findsOneWidget);
      expect(
        find.textContaining('after KORLIX Google platform activation'),
        findsOneWidget,
      );
      expect(find.text('Confirm paused creation'), findsNothing);
      await tap(t, 'Refresh creation record');
      expect(methods, ['GET', 'GET']);
    },
  );
  testWidgets(
    'K181 requires three explicit confirmations and sends only exact narrow body',
    (t) async {
      final requests = <http.Request>[];
      final c = client((r) async {
        requests.add(r);
        return reply(fixture(state: r.method == 'POST' ? 'created' : null));
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      final button = find.widgetWithText(
        FilledButton,
        'Confirm paused creation',
      );
      expect(t.widget<FilledButton>(button).onPressed, isNull);
      await confirm(t);
      await tap(t, 'Confirm paused creation');
      final body = jsonDecode(requests.last.body);
      expect(requests.last.url.path, endsWith('/google-create/create'));
      expect(body, {
        'fingerprint': 'a' * 64,
        'start_date': '2026-09-23',
        'confirmed': true,
        'budget_acknowledged': true,
        'no_eu_political_ads': true,
      });
      expect(find.text('CREATION RECORDED'), findsOneWidget);
      expect(find.text('Confirm paused creation'), findsNothing);
      expect(find.textContaining('Google campaign ID: 102'), findsOneWidget);
    },
  );
  testWidgets(
    'K181 editing date resets all confirmation and invalid date never sends',
    (t) async {
      int posts = 0;
      final c = client((r) async {
        if (r.method == 'POST') posts++;
        return reply(fixture());
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await confirm(t);
      await t.enterText(find.byType(TextField), '2026-02-30');
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm paused creation'),
            )
            .onPressed,
        isNull,
      );
      await confirm(t);
      await tap(t, 'Confirm paused creation');
      expect(posts, 0);
      expect(find.textContaining('Choose a date from'), findsOneWidget);
    },
  );
  testWidgets(
    'K181 pending outcome only offers read-only result checking and never creation again',
    (t) async {
      final requests = <http.Request>[];
      final c = client((r) async {
        requests.add(r);
        return reply(
          fixture(state: r.method == 'POST' ? 'created' : 'unknown'),
        );
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(find.text('OUTCOME NEEDS CHECKING'), findsOneWidget);
      expect(find.text('Confirm paused creation'), findsNothing);
      await tap(t, 'Check creation result');
      expect(requests.last.url.path, endsWith('/google-create/reconcile'));
      expect(jsonDecode(requests.last.body), {'attempt_id': aid});
      expect(find.text('CREATION RECORDED'), findsOneWidget);
    },
  );
  testWidgets(
    'K181 transport failure clears stale state and confirmations until a record refresh',
    (t) async {
      int reads = 0;
      final c = client((r) async {
        if (r.method == 'POST') {
          return reply({'error': 'Outcome uncertain'}, 503);
        }
        reads++;
        return reply(fixture(state: reads > 1 ? 'unknown' : null));
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await confirm(t);
      await tap(t, 'Confirm paused creation');
      expect(find.text('Confirm paused creation'), findsNothing);
      expect(find.textContaining('Refresh the saved record'), findsOneWidget);
      await tap(t, 'Refresh creation record');
      expect(find.text('OUTCOME NEEDS CHECKING'), findsOneWidget);
    },
  );
  testWidgets(
    'K181 scope invalidation suppresses late creation results and private copy',
    (t) async {
      final scope = ValueNotifier(0), pending = Completer<http.Response>();
      final c = client(
        (r) async => r.method == 'POST' ? pending.future : reply(fixture()),
      );
      addTearDown(c.dispose);
      addTearDown(scope.dispose);
      await t.pumpWidget(app(c, scope: scope));
      await t.pumpAndSettle();
      await confirm(t);
      await t.ensureVisible(find.text('Confirm paused creation'));
      await t.tap(find.text('Confirm paused creation'));
      await t.pump();
      scope.value++;
      await t.pump();
      pending.complete(reply(fixture(state: 'created')));
      await t.pumpAndSettle();
      expect(find.text('CREATION RECORDED'), findsNothing);
      expect(find.text('Copy creation summary'), findsNothing);
      expect(find.textContaining('Your workspace changed'), findsOneWidget);
    },
  );
  testWidgets(
    'K181 access denial removes saved private record and disables further actions',
    (t) async {
      int count = 0;
      final c = client(
        (r) async => ++count == 1
            ? reply(fixture(state: 'created'))
            : reply({'error': 'No access'}, 403),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await tap(t, 'Refresh creation record');
      expect(find.textContaining('Google campaign ID:'), findsNothing);
      expect(find.text('Copy creation summary'), findsNothing);
      expect(find.textContaining('Sign in with Enterprise'), findsOneWidget);
    },
  );
  testWidgets(
    'K181 copied historical summary contains exact resources, dates and budget limits',
    (t) async {
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
      final c = client((r) async => reply(fixture(state: 'created')));
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await tap(t, 'Copy creation summary');
      expect(copied, contains('KORLIX $aid'));
      expect(copied, contains('not a hard spending cap'));
      expect(
        copied,
        contains('Current Google delivery status is not monitored'),
      );
      expect(copied, contains('00:00:00'));
      expect(copied, contains('23:59:59'));
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('K181 real-font creation layout at $width with scaled text', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = client((r) async => reply(fixture()));
      addTearDown(c.dispose);
      await t.pumpWidget(app(c, scale: width == 320 ? 1.3 : 1));
      await t.pumpAndSettle();
      await tap(t, 'Review exact campaign details');
      expect(t.takeException(), isNull);
      await confirm(t);
      expect(t.takeException(), isNull);
    });
  }
}
