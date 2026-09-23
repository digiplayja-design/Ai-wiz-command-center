import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_campaign_link.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

final fp = 'a' * 64, proof = '1790190000000.${'b' * 64}';
Map<String, dynamic> clone(Map d) => jsonDecode(jsonEncode(d));
Map<String, dynamic> fixture({
  bool saved = true,
  bool configured = true,
  String state = 'draft',
  String campaign = 'c',
  int? version,
}) {
  final a = {
    'id': '1234567890',
    'name': 'Owner account',
    'currency': 'KWD',
    'timezone': 'America/New_York',
    'status': 'ENABLED',
    'manager': false,
    'test_account': false,
  };
  return clone({
    'source': 'google_campaign_link',
    'funnel_id': 'f',
    'campaign_id': campaign,
    'campaign_name': 'Autumn plan',
    'state': state,
    'version': version ?? (saved ? 1 : 0),
    'fingerprint': fp,
    'configured': configured,
    'editable': state != 'archived',
    'lookup_ready': configured && state != 'archived',
    'connection_version': 3,
    'root_id': '1111111111',
    'login_customer_id': '1111111111',
    'account': a,
    'link_current': saved && configured,
    'report_ready': saved && configured,
    'updated_at': saved || version != null ? '2026-09-23T12:00:00Z' : null,
    'checked_at': '2026-09-23T12:00:00Z',
    'link': saved
        ? {
            'root_id': '1111111111',
            'login_customer_id': '1111111111',
            'account': a,
            'provider_campaign_id': '11',
            'provider_campaign_name': 'Same name',
            'linked_at': '2026-09-23T12:00:00Z',
          }
        : null,
    'ad_publishing_ready': false,
    'attribution_verified': false,
  });
}

Map<String, dynamic> common(Map d, String source) => clone({
  'source': source,
  'funnel_id': d['funnel_id'],
  'campaign_id': d['campaign_id'],
  'fingerprint': d['fingerprint'],
  'connection_version': d['connection_version'],
  'root_id': d['root_id'],
  'login_customer_id': d['login_customer_id'],
  'account': d['account'],
  'range': {'from': '2026-09-16', 'to': '2026-09-22', 'days': 7},
  'fetched_at': '2026-09-23T12:00:00Z',
  'ad_publishing_ready': false,
  'attribution_verified': false,
});
Map<String, dynamic> choices(Map d, {int count = 2}) =>
    common(d, 'google_campaign_choices')
      ..['choices'] = [
        for (var i = 0; i < count; i++)
          {
            'provider_campaign_id': '${11 + i}',
            'provider_campaign_name': 'Same name',
            'proof': proof,
          },
      ];
Map<String, dynamic> report(
  Map d, {
  bool missing = false,
  String spend = '0.123456',
}) => common(d, 'google_linked_performance')
  ..addAll(
    clone({
      'link': d['link'],
      'row': missing
          ? null
          : {
              'campaign_id': '11',
              'campaign_name': 'Renamed in Google',
              'spend': spend,
              'clicks': 10,
              'impressions': 1000,
              'status': 'PAUSED',
              'channel': 'SEARCH',
            },
      'measurement': {
        'from': '2026-09-16',
        'to': '2026-09-22',
        'days': 7,
        'timezone': 'America/New_York',
        'start_inclusive': '2026-09-16T04:00:00Z',
        'end_exclusive': '2026-09-23T04:00:00Z',
        'tagged_inquiries': 2,
        'checked_at': '2026-09-23T12:00:00Z',
      },
    }),
  );
http.Response response(Map d, [int status = 200]) => http.Response(
  jsonEncode(d),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
FunnelClient client(Future<http.Response> Function(http.Request) handler) =>
    FunnelClient(
      backendBaseUrl: 'https://example.com',
      headersBuilder: () => {},
      client: MockClient(handler),
    );
Widget surface(
  FunnelClient c, {
  ValueNotifier<int>? scope,
  String campaign = 'c',
  double scale = 1,
}) => MaterialApp(
  theme: WfStyle.theme,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: FunnelGoogleCampaignLink(
        client: c,
        funnelId: 'f',
        campaignId: campaign,
        scope: scope,
      ),
    ),
  ),
);
Future<void> show(
  WidgetTester t,
  FunnelClient c, {
  ValueNotifier<int>? scope,
  double scale = 1,
}) async {
  await t.pumpWidget(surface(c, scope: scope, scale: scale));
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String label) async {
  await t.pumpAndSettle();
  await t.ensureVisible(find.text(label).last);
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

Future<void> choose(WidgetTester t, String id) async {
  final f = find.byKey(ValueKey('google-link-choice-$id'));
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      for (final f in ['MaterialIcons-Regular.otf', 'Roboto-Regular.ttf']) {
        final file = File('$root/bin/cache/artifacts/material_fonts/$f');
        await (FontLoader(f.startsWith('Material') ? 'MaterialIcons' : 'Roboto')
              ..addFont(
                Future.value(ByteData.sublistView(file.readAsBytesSync())),
              ))
            .load();
      }
    }
  });
  test(
    'Local context refuses mismatched identity, unsafe readiness and publishing claims',
    () {
      expect(validateGoogleCampaignLink(fixture(), 'f', 'c')['version'], 1);
      expect(
        validateGoogleCampaignLink(
          fixture(saved: false, version: 2),
          'f',
          'c',
        )['link'],
        isNull,
      );
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (d) => d['campaign_id'] = 'other',
        (d) => d['funnel_id'] = 'other',
        (d) => d['fingerprint'] = 'bad',
        (d) => d['ad_publishing_ready'] = true,
        (d) => d['attribution_verified'] = true,
        (d) => d['configured'] = false,
        (d) => d['link']['account']['id'] = '9999999999',
        (d) => d['account']['status'] = 'SUSPENDED',
        (d) => d['account']['manager'] = true,
        (d) => d['account']['test_account'] = true,
        (d) => d['root_id'] = '2222222222',
        (d) => d['login_customer_id'] = null,
        (d) => d['editable'] = false,
        (d) => d['version'] = 0,
        (d) => d['connection_version'] = 0,
      ]) {
        final d = fixture();
        mutate(d);
        expect(
          () => validateGoogleCampaignLink(d, 'f', 'c'),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  test(
    'Choice receipts require exact context, distinct IDs and strict private shape',
    () {
      final d = fixture();
      expect(
        validateGoogleCampaignChoices(choices(d), d, 7)['choices'],
        hasLength(2),
      );
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (r) => r['account']['currency'] = 'USD',
        (r) => r['fingerprint'] = 'b' * 64,
        (r) => r['range']['to'] = '2026-09-23',
        (r) => r['range']['from'] = '2026-02-30',
        (r) => r['choices'][1]['provider_campaign_id'] = '11',
        (r) => r['choices'][0]['proof'] = 'bad',
        (r) => r['choices'][0]['spend'] = '1',
        (r) => r['choices'] = List.generate(
          501,
          (i) => {
            'provider_campaign_id': '$i',
            'provider_campaign_name': 'C',
            'proof': proof,
          },
        ),
      ]) {
        final r = choices(d);
        mutate(r);
        expect(
          () => validateGoogleCampaignChoices(r, d, 7),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  test(
    'Performance validates identities, exact money and aligned local measurement context',
    () {
      final d = fixture();
      expect(
        validateGoogleLinkedPerformance(report(d), d, 7)['row']['spend'],
        '0.123456',
      );
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (r) => r['row']['campaign_id'] = '12',
        (r) => r['row']['status'] = 'BOGUS',
        (r) => r['row']['channel'] = 'BOGUS',
        (r) => r['root_id'] = '2222222222',
        (r) => r['login_customer_id'] = null,
        (r) => r['row']['spend'] = 0.1,
        (r) => r['row']['spend'] = '1000000000000.000001',
        (r) => r['row']['spend'] = '0.1234567',
        (r) => r['row']['clicks'] = -1,
        (r) => r['row']['impressions'] = 1.5,
        (r) => r['measurement']['timezone'] = 'UTC',
        (r) => r['measurement']['from'] = '2026-09-15',
        (r) => r['measurement']['end_exclusive'] = '2026-09-16T04:00:00Z',
        (r) => r['measurement']['tagged_inquiries'] = -1,
        (r) => r['link']['provider_campaign_id'] = '12',
        (r) => r['attribution_verified'] = true,
      ]) {
        final r = report(d);
        mutate(r);
        expect(
          () => validateGoogleLinkedPerformance(r, d, 7),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  test(
    'Summary distinguishes missing from zero and preserves source, currency and time boundaries',
    () {
      final d = fixture(), r = report(d);
      final s = googleLinkedSummary(d, r);
      expect(s, contains('KWD 0.123456'));
      expect(s, contains('2'));
      expect(s, contains('Renamed in Google'));
      expect(s, contains('2026-09-16T04:00:00Z inclusive'));
      expect(s, contains(googleCampaignLinkBoundary));
      expect(s, contains('No currency conversion'));
      expect(s, isNot(contains(proof)));
      final missing = validateGoogleLinkedPerformance(
        report(d, missing: true),
        d,
        7,
      );
      expect(googleLinkedSummary(d, missing), contains('unknown'));
      final zero = validateGoogleLinkedPerformance(report(d, spend: '0'), d, 7);
      expect(googleLinkedSummary(d, zero), contains('Google spend: KWD 0\n'));
      expect(googleLinkedSummary(d, zero), isNot(contains('unknown')));
    },
  );
  for (final size in [
    const Size(1400, 1100),
    const Size(390, 844),
    const Size(320, 740),
  ]) {
    testWidgets('Choice and linked report fit ${size.width}', (t) async {
      await t.binding.setSurfaceSize(size);
      addTearDown(() => t.binding.setSurfaceSize(null));
      final d = fixture();
      final c = client(
        (r) async => response(
          r.url.path.endsWith('/campaigns')
              ? choices(d)
              : r.url.path.endsWith('/performance')
              ? report(d)
              : d,
        ),
      );
      addTearDown(c.dispose);
      await show(t, c, scale: size.width == 320 ? 1.3 : 1);
      await tap(t, 'Load Google campaigns');
      await choose(t, '12');
      expect(find.text('Google campaign ID: 12'), findsOneWidget);
      await tap(t, 'Cancel selection');
      await tap(t, 'Load linked performance');
      await t.ensureVisible(find.text('2 tagged inquiries in the same period'));
      await t.pumpAndSettle();
      expect(find.text('Spend: KWD 0.123456'), findsOneWidget);
      expect(find.text('GOOGLE REPORTED'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'No automatic provider request; duplicate names select exact ID and signed save body',
    (t) async {
      final calls = <http.Request>[];
      final d = fixture(saved: false);
      final c = client((r) async {
        calls.add(r);
        if (r.url.path.endsWith('/campaigns')) return response(choices(d));
        if (r.url.path.endsWith('/save')) {
          final s = fixture();
          s['link']['provider_campaign_id'] = '12';
          return response(s);
        }
        return response(d);
      });
      addTearDown(c.dispose);
      await show(t, c);
      expect(calls, hasLength(1));
      await tap(t, 'Load Google campaigns');
      expect(calls.last.url.queryParameters, {'days': '7', 'fingerprint': fp});
      await choose(t, '12');
      expect(calls, hasLength(2));
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Copy association summary'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, 'Confirm campaign link');
      expect(jsonDecode(calls.last.body), {
        'version': 0,
        'fingerprint': fp,
        'confirmed': true,
        'provider_campaign_id': '12',
        'provider_campaign_name': 'Same name',
        'proof': proof,
      });
      expect(find.text('Google campaign association saved.'), findsOneWidget);
      expect(find.text('Google campaign ID: 12'), findsOneWidget);
      expect(find.text('Confirm campaign link'), findsNothing);
    },
  );
  testWidgets(
    'Clear confirms and retains optimistic version; clipboard excludes choice receipts',
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
      final calls = <http.Request>[];
      final d = fixture();
      final c = client((r) async {
        calls.add(r);
        return response(
          r.method == 'POST'
              ? fixture(saved: false, version: 2)
              : r.url.path.endsWith('/performance')
              ? report(d)
              : d,
        );
      });
      addTearDown(c.dispose);
      await show(t, c);
      await tap(t, 'Load linked performance');
      await tap(t, 'Copy association summary');
      expect(copied, contains('KWD 0.123456'));
      expect(copied, contains(googleCampaignLinkBoundary));
      expect(copied, isNot(contains(proof)));
      await tap(t, 'Clear saved association');
      await tap(t, 'Keep association');
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      await tap(t, 'Clear saved association');
      await tap(t, 'Clear association');
      expect(jsonDecode(calls.last.body), {
        'version': 1,
        'fingerprint': fp,
        'confirmed': true,
      });
      expect(find.text('ASSOCIATION SAVED'), findsNothing);
    },
  );
  testWidgets(
    'Archived and unconfigured states prevent lookup without blocking local clear',
    (t) async {
      for (final d in [
        fixture(state: 'archived'),
        fixture(configured: false),
      ]) {
        final c = client((_) async => response(d));
        addTearDown(c.dispose);
        await show(t, c);
        expect(
          t
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Load Google campaigns'),
              )
              .onPressed,
          isNull,
        );
        expect(
          t
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Clear saved association'),
              )
              .onPressed,
          isNotNull,
        );
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Load linked performance'),
              )
              .onPressed,
          d['report_ready'] == true ? isNotNull : isNull,
        );
      }
    },
  );
  testWidgets(
    'Period changes clear old figures and conflicts require fresh association',
    (t) async {
      var fail = false;
      final calls = <http.Request>[];
      final d = fixture();
      final c = client((r) async {
        calls.add(r);
        return fail
            ? response({'error': 'Account changed. Reload.'}, 409)
            : response(r.url.path.endsWith('/performance') ? report(d) : d);
      });
      addTearDown(c.dispose);
      await show(t, c);
      await tap(t, 'Load linked performance');
      expect(find.text('Spend: KWD 0.123456'), findsOneWidget);
      await t.ensureVisible(find.byType(DropdownButtonFormField<int>));
      await t.tap(find.byType(DropdownButtonFormField<int>));
      await t.pumpAndSettle();
      await t.tap(find.text('30 days').last);
      await t.pumpAndSettle();
      expect(find.text('Spend: KWD 0.123456'), findsNothing);
      expect(calls, hasLength(2));
      fail = true;
      await tap(t, 'Load linked performance');
      expect(calls.last.url.queryParameters['days'], '30');
      expect(find.text('Account changed. Reload.'), findsOneWidget);
      expect(find.text('Copy association summary'), findsNothing);
      fail = false;
      await tap(t, 'Refresh association');
      expect(find.text('Autumn plan'), findsOneWidget);
    },
  );
  testWidgets('Campaign search matches ID and paginates bounded results', (
    t,
  ) async {
    final d = fixture();
    final c = client(
      (r) async => response(
        r.url.path.endsWith('/campaigns') ? choices(d, count: 24) : d,
      ),
    );
    addTearDown(c.dispose);
    await show(t, c);
    await tap(t, 'Load Google campaigns');
    expect(find.byKey(const ValueKey('google-link-choice-30')), findsOneWidget);
    expect(find.byKey(const ValueKey('google-link-choice-31')), findsNothing);
    await tap(t, 'Next campaigns');
    expect(find.byKey(const ValueKey('google-link-choice-31')), findsOneWidget);
    expect(find.byKey(const ValueKey('google-link-choice-11')), findsNothing);
    await t.enterText(find.byType(TextField), '34');
    await t.pumpAndSettle();
    expect(find.text('1 matches · 24 returned campaigns'), findsOneWidget);
    await choose(t, '34');
    expect(find.text('Confirm campaign link'), findsOneWidget);
  });
  testWidgets('Workspace invalidation removes private inline confirmation', (
    t,
  ) async {
    final scope = ValueNotifier(0), d = fixture();
    final c = client(
      (r) async => response(r.url.path.endsWith('/campaigns') ? choices(d) : d),
    );
    addTearDown(c.dispose);
    addTearDown(scope.dispose);
    await show(t, c, scope: scope);
    await tap(t, 'Load Google campaigns');
    await choose(t, '12');
    scope.value++;
    await t.pumpAndSettle();
    expect(find.text('Confirm campaign link'), findsNothing);
    expect(find.text('Same name'), findsNothing);
    expect(find.text('Copy association summary'), findsNothing);
    expect(find.textContaining('Your workspace changed.'), findsOneWidget);
  });
  testWidgets('Pending provider results are ignored after workspace changes', (
    t,
  ) async {
    final pending = Completer<http.Response>(),
        scope = ValueNotifier(0),
        d = fixture();
    final c = client(
      (r) async =>
          r.url.path.endsWith('/performance') ? pending.future : response(d),
    );
    addTearDown(c.dispose);
    addTearDown(scope.dispose);
    await show(t, c, scope: scope);
    await t.ensureVisible(find.text('Load linked performance'));
    await t.tap(find.text('Load linked performance'));
    await t.pump();
    scope.value++;
    await t.pump();
    pending.complete(response(report(d)));
    await t.pumpAndSettle();
    expect(find.text('Spend: KWD 0.123456'), findsNothing);
    expect(find.text('Autumn plan'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('Access denial clears saved data and prevents further actions', (
    t,
  ) async {
    var count = 0;
    final c = client(
      (_) async => ++count == 1
          ? response(fixture())
          : response({'error': 'Denied'}, 403),
    );
    addTearDown(c.dispose);
    await show(t, c);
    await tap(t, 'Refresh association');
    expect(find.text('Autumn plan'), findsNothing);
    expect(find.text('Refresh association'), findsNothing);
    expect(find.textContaining('Sign in with Enterprise'), findsOneWidget);
  });
  testWidgets('Changed client and campaign ignore late old private context', (
    t,
  ) async {
    final pending = Completer<http.Response>();
    final old = client((_) => pending.future),
        fresh = client(
          (_) async => response(
            fixture(campaign: 'new')..['campaign_name'] = 'New plan',
          ),
        );
    addTearDown(old.dispose);
    addTearDown(fresh.dispose);
    await t.pumpWidget(surface(old));
    await t.pump();
    await t.pumpWidget(surface(fresh, campaign: 'new'));
    await t.pumpAndSettle();
    pending.complete(response(fixture()));
    await t.pumpAndSettle();
    expect(find.text('New plan'), findsOneWidget);
    expect(find.text('Autumn plan'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'A stale manager link can still be cleared after access changes',
    (t) async {
      final d = fixture()
        ..['root_id'] = '2222222222'
        ..['login_customer_id'] = '2222222222'
        ..['link_current'] = false
        ..['report_ready'] = false;
      final calls = <http.Request>[];
      final c = client((r) async {
        calls.add(r);
        return response(
          r.method == 'POST' ? fixture(saved: false, version: 2) : d,
        );
      });
      addTearDown(c.dispose);
      await show(t, c);
      expect(find.text('REPORTING UNAVAILABLE'), findsOneWidget);
      await tap(t, 'Clear saved association');
      await tap(t, 'Clear association');
      expect(calls.last.url.path, endsWith('/google-link/clear'));
      expect(calls.last.method, 'POST');
      expect(find.text('ASSOCIATION SAVED'), findsNothing);
    },
  );
  testWidgets(
    'Direct test-account reporting is labeled in the panel and export on a narrow screen',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final d = fixture();
      d['root_id'] = d['account']['id'];
      d['login_customer_id'] = null;
      d['account']['test_account'] = true;
      d['link']['root_id'] = d['root_id'];
      d['link']['login_customer_id'] = null;
      d['link']['account']['test_account'] = true;
      final r = report(d);
      final c = client(
        (q) async => response(q.url.path.endsWith('/performance') ? r : d),
      );
      addTearDown(c.dispose);
      await show(t, c, scale: 1.3);
      expect(
        find.text('Google test account · not live ad delivery.'),
        findsOneWidget,
      );
      await tap(t, 'Load linked performance');
      await t.ensureVisible(
        find.text('Google status: PAUSED · Channel: SEARCH'),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final s = googleLinkedSummary(d, r);
      expect(s, contains('Test account: true'));
      expect(s, contains('Manager header: Direct access'));
      expect(s, contains('Google status/channel: PAUSED / SEARCH'));
    },
  );
  test(
    'Google campaign IDs remain exact at int64 maximum and reject overflow or zero',
    () {
      final d = fixture();
      d['link']['provider_campaign_id'] = '9223372036854775807';
      validateGoogleCampaignLink(d, 'f', 'c');
      final r = report(d);
      r['row']['campaign_id'] = '9223372036854775807';
      expect(
        validateGoogleLinkedPerformance(r, d, 7)['row']['campaign_id'],
        '9223372036854775807',
      );
      for (final id in ['0', '01', '9223372036854775808']) {
        final bad = clone(d);
        bad['link']['provider_campaign_id'] = id;
        expect(
          () => validateGoogleCampaignLink(bad, 'f', 'c'),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
}
