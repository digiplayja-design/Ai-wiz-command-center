import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_campaign_attribution.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

const fid = '00000000-0000-4000-8000-000000000001',
    cid = '00000000-0000-4000-8000-000000000002';
Map<String, dynamic> fixture({
  bool link = true,
  int days = 30,
  String campaign = cid,
}) {
  final end = DateTime.utc(2026, 9, 24),
      start = end.subtract(Duration(days: days - 1));
  return {
    'source': 'campaign_link_attribution',
    'funnel_id': fid,
    'campaign_id': campaign,
    'name': 'Autumn campaign',
    'platform': 'meta',
    'state': 'reviewed',
    'page_state': 'published',
    'slug': 'autumn-page',
    'days': days,
    'from_day': start.toIso8601String().substring(0, 10),
    'through_day': '2026-09-24',
    'timezone': 'UTC',
    'includes_today': true,
    'checked_at': '2026-09-24T12:00:00Z',
    'provider_verified': false,
    'link': link
        ? {
            'url':
                'https://example.com/f/autumn-page?utm_source=facebook&utm_medium=paid&utm_campaign=k143_${campaign.replaceAll('-', '')}&kl=${'a' * 64}',
            'created_at': '2026-09-24T10:00:00Z',
          }
        : null,
    'totals': {
      'link_inquiries': 2,
      'tag_only_inquiries': 3,
      'tag_conflicts': 1,
    },
    'rows': List.generate(
      days,
      (i) => {
        'day': start.add(Duration(days: i)).toIso8601String().substring(0, 10),
        'link_inquiries': i == days - 1 ? 2 : 0,
        'tag_only_inquiries': i == days - 1 ? 3 : 0,
        'tag_conflicts': i == days - 1 ? 1 : 0,
      },
    ),
  };
}

http.Response reply(Map<String, dynamic> d, [int status = 200]) =>
    http.Response(
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
Future<void> app(
  WidgetTester t,
  FunnelClient c, {
  ValueNotifier<int>? scope,
  String campaign = cid,
  double scale = 1,
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: WfStyle.theme,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(1400, 900),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: FunnelCampaignAttribution(
            client: c,
            funnelId: fid,
            campaignId: campaign,
            scope: scope,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String text) async {
  final f = find.text(text);
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      final file = File(
        '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      );
      if (file.existsSync()) {
        final loader = FontLoader('Roboto')
          ..addFont(
            Future.value(ByteData.sublistView(await file.readAsBytes())),
          );
        await loader.load();
      }
    }
  });
  test(
    'K187 validates daily reconciliation, exact scope, dates and link identity',
    () {
      for (final days in [7, 30, 90]) {
        validateCampaignAttribution(fixture(days: days), fid, cid, days);
      }
      for (final change in <void Function(Map<String, dynamic>)>[
        (d) => d['campaign_id'] = 'other',
        (d) => d['funnel_id'] = 'other',
        (d) => d['days'] = 7,
        (d) => d['provider_verified'] = true,
        (d) => d['rows'][0]['day'] = '2026-01-01',
        (d) => d['rows'][0]['link_inquiries'] = -1,
        (d) => d['totals']['link_inquiries'] = 20,
        (d) => d['rows'].removeLast(),
        (d) => d['from_day'] = '2026-02-30',
        (d) => d['through_day'] = '2026-09-23',
        (d) => d['rows'].last['tag_conflicts'] = 3,
        (d) => d['checked_at'] = 'bad',
        (d) => d['link']['url'] = 'http://example.com/f/autumn-page',
        (d) => d['link']['url'] = (d['link']['url'] as String).replaceFirst(
          'facebook',
          'google',
        ),
        (d) => d['link']['url'] = '${d['link']['url']}&kl=${'b' * 64}',
        (d) => d['link']['url'] = (d['link']['url'] as String).replaceFirst(
          'autumn-page',
          'other-page',
        ),
      ]) {
        final d = fixture();
        change(d);
        expect(
          () => validateCampaignAttribution(d, fid, cid, 30),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  testWidgets(
    'K187 loads locally recorded evidence without creating a link or calling a provider',
    (t) async {
      final requests = <http.Request>[];
      final c = client((r) async {
        requests.add(r);
        return reply(fixture(link: false));
      });
      await app(t, c);
      expect(requests.length, 1);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.queryParameters['days'], '30');
      expect(find.text('Create attribution link'), findsOneWidget);
      expect(find.text(campaignAttributionBoundary), findsOneWidget);
      expect(find.text('Link-associated inquiries'), findsOneWidget);
      expect(find.text('Tag-only inquiries'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('K187 create and copy use the exact returned recognized link', (
    t,
  ) async {
    final requests = <http.Request>[];
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
    final c = client((r) async {
      requests.add(r);
      return reply(fixture(link: r.method == 'POST'));
    });
    await app(t, c);
    await tap(t, 'Create attribution link');
    expect(requests.last.method, 'POST');
    expect(requests.last.url.path.endsWith('/attribution/link'), isTrue);
    expect(jsonDecode(requests.last.body), {'days': 30});
    await tap(t, 'Copy attribution link');
    expect(copied, fixture()['link']['url']);
    expect(find.text('Campaign attribution link copied.'), findsOneWidget);
  });
  testWidgets(
    'K187 reporting window loads corresponding days and errors clear private results',
    (t) async {
      var fail = false;
      final seen = <int>[];
      final c = client((r) async {
        final n = int.parse(r.url.queryParameters['days']!);
        seen.add(n);
        return fail
            ? reply({'error': 'Storage unavailable'}, 503)
            : reply(fixture(days: n));
      });
      await app(t, c);
      await tap(t, 'Last 30 UTC days');
      await t.tap(find.text('Last 7 UTC days').last);
      await t.pumpAndSettle();
      expect(seen, [30, 7]);
      expect(
        find.text(
          '2026-09-18 through 2026-09-24 UTC · Includes today, which is incomplete.',
        ),
        findsOneWidget,
      );
      fail = true;
      await tap(t, 'Refresh attribution');
      expect(find.text('Storage unavailable'), findsOneWidget);
      expect(find.text('Autumn campaign'), findsNothing);
      expect(find.text('Copy attribution link'), findsNothing);
    },
  );
  testWidgets(
    'K187 invalid server evidence is rejected without exposing a copy button',
    (t) async {
      final d = fixture();
      d['totals']['tag_only_inquiries'] = 999;
      await app(t, client((_) async => reply(d)));
      expect(
        find.text('Campaign attribution could not be verified. Refresh it.'),
        findsOneWidget,
      );
      expect(find.text('Copy attribution link'), findsNothing);
    },
  );
  testWidgets('K187 archived or unpublished campaigns cannot create links', (
    t,
  ) async {
    for (final patch in [
      {'state': 'archived'},
      {'page_state': 'paused'},
    ]) {
      await t.pumpWidget(const SizedBox());
      final d = fixture(link: false)..addAll(patch);
      await app(t, client((_) async => reply(d)));
      expect(find.text('Create attribution link'), findsNothing);
      expect(
        find.text(
          'Publish the page and reopen the campaign before creating its attribution link.',
        ),
        findsOneWidget,
      );
    }
  });
  testWidgets(
    'K187 scope loss suppresses delayed link creation and removes private results',
    (t) async {
      final wait = Completer<http.Response>(), scope = ValueNotifier(0);
      addTearDown(scope.dispose);
      final c = client(
        (r) async =>
            r.method == 'POST' ? wait.future : reply(fixture(link: false)),
      );
      await app(t, c, scope: scope);
      await t.ensureVisible(find.text('Create attribution link'));
      await t.tap(find.text('Create attribution link'));
      await t.pump();
      scope.value++;
      await t.pumpAndSettle();
      wait.complete(reply(fixture()));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Your workspace changed. Close this report and open it again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Copy attribution link'), findsNothing);
      expect(find.text('Autumn campaign'), findsNothing);
    },
  );
  testWidgets('K187 access denial clears results and disables refresh', (
    t,
  ) async {
    var denied = false;
    final c = client(
      (_) async => denied ? reply({'error': 'Denied'}, 403) : reply(fixture()),
    );
    await app(t, c);
    denied = true;
    await tap(t, 'Refresh attribution');
    expect(
      find.text('Sign in with Enterprise access to view campaign attribution.'),
      findsOneWidget,
    );
    expect(find.text('Refresh attribution'), findsNothing);
    expect(find.text('Autumn campaign'), findsNothing);
  });
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('K187 real-font attribution layout at $width', (t) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await app(
        t,
        client((_) async => reply(fixture())),
        scale: width == 320 ? 1.3 : 1,
      );
      await t.ensureVisible(find.text('Copy attribution link'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('2026-09-24'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
