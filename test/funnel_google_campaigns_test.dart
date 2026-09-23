import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_performance.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_campaign_results.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';
import 'funnel_google_ads_test.dart' show response, root, account;
import 'funnel_google_performance_test.dart' show connection, report;
import 'funnel_questions_test.dart' show keyed, tap;

Map<String, dynamic> campaigns({int count = 23}) {
  final total = count * (count + 1) ~/ 2;
  return {
    ...report(),
    'scope': 'campaign',
    'reported_campaigns': count,
    'totals': {
      'spend': '$total.00',
      'impressions': total * 100,
      'clicks': total,
    },
    'rows': List.generate(
      count,
      (i) => {
        'campaign_id': '${1000 + i}',
        'campaign_name': 'Campaign ${(i + 1).toString().padLeft(2, '0')}',
        'status': i % 2 == 0 ? 'ENABLED' : 'PAUSED',
        'channel': 'SEARCH',
        'spend': '${i + 1}.00',
        'impressions': (i + 1) * 100,
        'clicks': i + 1,
      },
    ),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      for (final e in {
        'Roboto': 'Roboto-Regular.ttf',
        'MaterialIcons': 'MaterialIcons-Regular.otf',
      }.entries) {
        await (FontLoader(e.key)..addFont(
              File(
                '$root/bin/cache/artifacts/material_fonts/${e.value}',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    }
  });
  FunnelClient client(Future<http.Response> Function(http.Request) handler) =>
      FunnelClient(
        backendBaseUrl: 'https://example.com',
        headersBuilder: () => {'Authorization': 'current-user'},
        client: MockClient(handler),
      );
  Future<void> shell(WidgetTester t, Widget child, {double width = 700}) async {
    await t.binding.setSurfaceSize(Size(width, 1100));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('campaign-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: WfStyle.theme,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.3 : 1)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Widget panel(
    FunnelClient c, {
    Map<String, dynamic>? conn,
    bool available = true,
  }) => FunnelGooglePerformance(
    client: c,
    connection: conn ?? connection(),
    available: available,
  );
  Future<void> load(WidgetTester t) async {
    await tap(t, keyed('google-scope-campaign'));
    await tap(t, keyed('google-load-performance'));
  }

  List<String> order(WidgetTester t) => find
      .byWidgetPredicate(
        (w) =>
            w is Container &&
            w.key is ValueKey &&
            '${(w.key as ValueKey).value}'.startsWith('google-campaign-'),
      )
      .evaluate()
      .map((e) => '${(e.widget.key as ValueKey).value}')
      .toList();

  test(
    'Campaign sorting preserves micro-decimal order and uses IDs to disambiguate equal metrics or names',
    () {
      final a = {
        'campaign_id': '101',
        'campaign_name': 'Same',
        'spend': '999999999999.000001',
        'impressions': 5,
        'clicks': 8,
      };
      final b = {...a, 'campaign_id': '102', 'spend': '999999999999.000002'};
      expect(compareGoogleCampaigns(a, b, 'spend'), greaterThan(0));
      expect(compareGoogleCampaigns(a, b, 'name'), lessThan(0));
      expect(
        compareGoogleCampaigns(a, {...b, 'impressions': 6}, 'impressions'),
        greaterThan(0),
      );
      expect(
        compareGoogleCampaigns(a, {...b, 'clicks': 9}, 'clicks'),
        greaterThan(0),
      );
    },
  );

  testWidgets(
    'Campaign comparison loads explicitly; local search, sorting and paging preserve full-report totals',
    (t) async {
      final calls = <http.Request>[];
      final c = client((r) async {
        calls.add(r);
        return response(campaigns());
      });
      addTearDown(c.dispose);
      await shell(t, panel(c));
      await tap(t, keyed('google-scope-campaign'));
      expect(calls, isEmpty);
      await tap(t, keyed('google-load-performance'));
      expect(
        calls.single.url.path,
        '/api/funnels/google-ads/campaign-performance',
      );
      expect(calls.single.url.queryParameters, {
        'days': '7',
        'account_id': account,
        'root_id': root,
        'version': '3',
      });
      expect(find.text('USD 276.00'), findsOneWidget);
      expect(find.text('Google daily results'), findsNothing);
      expect(order(t).length, 20);
      expect(order(t).first, 'google-campaign-1022');
      await tap(t, keyed('google-campaign-next'));
      expect(find.text('Showing 21–23 of 23'), findsOneWidget);
      expect(order(t).length, 3);
      await t.ensureVisible(keyed('google-campaign-search'));
      await t.enterText(keyed('google-campaign-search'), '1000');
      await t.pumpAndSettle();
      expect(find.text('Showing 1–1 of 1'), findsOneWidget);
      expect(order(t), ['google-campaign-1000']);
      expect(find.text('USD 276.00'), findsOneWidget);
      await t.enterText(keyed('google-campaign-search'), 'missing');
      await t.pumpAndSettle();
      expect(find.textContaining('No matching campaigns.'), findsOneWidget);
      expect(find.text('USD 276.00'), findsOneWidget);
      await tap(t, find.byTooltip('Clear search'));
      await tap(t, keyed('google-campaign-sort'));
      await t.tap(find.text('Name A–Z').last);
      await t.pumpAndSettle();
      expect(order(t).first, 'google-campaign-1000');
      expect(find.text('Showing 1–20 of 23'), findsOneWidget);
      expect(calls.length, 1);
      await t.enterText(keyed('google-campaign-search'), '1000');
      await t.pumpAndSettle();
      await tap(t, keyed('google-load-performance'));
      expect(calls.length, 2);
      expect(
        t.widget<TextField>(keyed('google-campaign-search')).controller!.text,
        isEmpty,
      );
      expect(order(t).length, 20);
      expect(order(t).first, 'google-campaign-1022');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Switching report scope discards an in-flight account response and loads only the current campaign request',
    (t) async {
      final account = Completer<http.Response>(),
          campaign = Completer<http.Response>();
      final c = client(
        (r) => r.url.path.endsWith('/campaign-performance')
            ? campaign.future
            : account.future,
      );
      addTearDown(c.dispose);
      await shell(t, panel(c));
      await t.tap(keyed('google-load-performance'));
      await t.pump();
      await tap(t, keyed('google-scope-campaign'));
      await t.tap(keyed('google-load-performance'));
      await t.pump();
      account.complete(response(report()));
      await t.pump();
      expect(find.text('USD 12,345.123456'), findsNothing);
      campaign.complete(response(campaigns(count: 1)));
      await t.pumpAndSettle();
      expect(find.text('Campaign 01'), findsOneWidget);
      await tap(t, keyed('google-period-90'));
      expect(find.text('Campaign 01'), findsNothing);
      expect(find.text('Load Google campaign comparison'), findsOneWidget);
    },
  );

  testWidgets(
    'Campaign failures, mismatched scope and empty responses cannot retain previous figures',
    (t) async {
      var state = 0;
      final c = client(
        (r) async => switch (state) {
          1 => response({'error': 'Google reporting unavailable'}, 503),
          2 => response(report()),
          3 => response(campaigns(count: 0)),
          _ => response(campaigns(count: 1)),
        },
      );
      addTearDown(c.dispose);
      await shell(t, panel(c));
      await load(t);
      expect(find.text('Campaign 01'), findsOneWidget);
      state = 1;
      await tap(t, keyed('google-load-performance'));
      expect(find.text('Campaign 01'), findsNothing);
      expect(find.text('Google reporting unavailable'), findsOneWidget);
      state = 2;
      await tap(t, keyed('google-load-performance'));
      expect(find.textContaining('could not be verified'), findsOneWidget);
      state = 3;
      await tap(t, keyed('google-load-performance'));
      expect(find.textContaining('no campaign rows'), findsOneWidget);
      expect(find.text('Amount spent'), findsNothing);
      expect(keyed('google-campaign-search'), findsNothing);
    },
  );

  testWidgets(
    'Changed account bindings and access loss discard pending and already-loaded campaign reports',
    (t) async {
      var conn = connection();
      late StateSetter change;
      final pending = Completer<http.Response>();
      var delayed = true;
      final c = client((r) async {
        if (r.url.path.endsWith('/denied')) {
          return response({'error': 'Access removed'}, 403);
        }
        if (delayed) return pending.future;
        return response({
          ...campaigns(count: 1),
          'connection_version': 8,
          'account': {...report()['account'], 'id': '1111111111'},
        });
      });
      addTearDown(c.dispose);
      await shell(
        t,
        StatefulBuilder(
          builder: (context, set) {
            change = set;
            return panel(c, conn: conn);
          },
        ),
      );
      await tap(t, keyed('google-scope-campaign'));
      await t.tap(keyed('google-load-performance'));
      await t.pump();
      change(
        () => conn = {...conn, 'version': 8, 'selected_account': '1111111111'},
      );
      await t.pump();
      pending.complete(response(campaigns(count: 1)));
      await t.pumpAndSettle();
      expect(find.text('Campaign 01'), findsNothing);
      delayed = false;
      await tap(t, keyed('google-load-performance'));
      expect(find.text('Campaign 01'), findsOneWidget);
      await expectLater(
        c.request('GET', '/denied'),
        throwsA(isA<FunnelException>()),
      );
      await t.pumpAndSettle();
      expect(find.text('Campaign 01'), findsNothing);
      expect(
        t.widget<FilledButton>(keyed('google-load-performance')).onPressed,
        isNull,
      );
    },
  );

  test(
    'Campaign validation preserves large IDs, accepts 500 rows and reconciles every metric',
    () {
      final valid = campaigns(count: 500);
      valid['rows'][0]['campaign_id'] = '9223372036854775807';
      expect(
        googlePerformanceReport(
          valid,
          connection(),
          7,
          scope: 'campaign',
        )['reported_campaigns'],
        500,
      );
      final changes = <void Function(Map<String, dynamic>)>[
        (r) => r['scope'] = 'account',
        (r) => r['root_id'] = '0000000000',
        (r) => r['account']['id'] = '1111111111',
        (r) => r['connection_version'] = 99,
        (r) => r['range']['days'] = 30,
        (r) => r['rows'][0]['campaign_id'] = '9223372036854775808',
        (r) => r['rows'][0]['campaign_id'] = '01',
        (r) => r['rows'][0]['campaign_id'] = 1000,
        (r) => r['rows'][0]['campaign_name'] = ' ',
        (r) => r['rows'][0]['campaign_name'] = 'a' * 1001,
        (r) => r['rows'][0]['status'] = 'invented',
        (r) => r['rows'][0]['channel'] = null,
        (r) => r['rows'][1]['campaign_id'] = '1000',
        (r) => r['rows'][0]['spend'] = '-1.00',
        (r) => r['rows'][0]['spend'] = '1000000000000.000001',
        (r) => r['rows'][0]['impressions'] = 1.5,
        (r) => r['rows'][0]['clicks'] = null,
        (r) => r['rows'][0]['clicks'] = 9007199254740992,
        (r) => r['totals']['spend'] = '276.000001',
        (r) => r['totals']['impressions'] = 1,
        (r) => r['totals']['clicks'] = 1,
        (r) => r['reported_campaigns'] = 24,
      ];
      for (final change in changes) {
        final r = jsonDecode(jsonEncode(campaigns())) as Map<String, dynamic>;
        change(r);
        expect(
          () => googlePerformanceReport(r, connection(), 7, scope: 'campaign'),
          throwsA(isA<FunnelException>()),
        );
      }
      expect(
        () => googlePerformanceReport(
          campaigns(count: 501),
          connection(),
          7,
          scope: 'campaign',
        ),
        throwsA(isA<FunnelException>()),
      );
    },
  );
  testWidgets(
    'Campaign labels show current status and channel; a returned zero is not treated as no report',
    (t) async {
      final r = campaigns(count: 1);
      r['rows'][0].addAll({
        'status': 'REMOVED',
        'channel': 'PERFORMANCE_MAX',
        'spend': '0.00',
        'impressions': 0,
        'clicks': 0,
      });
      r['totals'] = {'spend': '0.00', 'impressions': 0, 'clicks': 0};
      final c = client((_) async => response(r));
      addTearDown(c.dispose);
      await shell(t, panel(c));
      await load(t);
      expect(find.text('USD 0.00'), findsOneWidget);
      expect(
        find.textContaining(
          'Current status: Removed · Channel: Performance Max',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('not historical status'), findsOneWidget);
      expect(find.text('Google daily results'), findsNothing);
    },
  );
  testWidgets(
    'Changing back to account totals cannot show a late campaign response',
    (t) async {
      final pending = Completer<http.Response>();
      final c = client(
        (r) async => r.url.path.endsWith('/campaign-performance')
            ? pending.future
            : response(report()),
      );
      addTearDown(c.dispose);
      await shell(t, panel(c));
      await tap(t, keyed('google-scope-campaign'));
      await t.tap(keyed('google-load-performance'));
      await t.pump();
      await tap(t, keyed('google-scope-account'));
      await tap(t, keyed('google-load-performance'));
      pending.complete(response(campaigns(count: 1)));
      await t.pumpAndSettle();
      expect(find.text('USD 12,345.123456'), findsOneWidget);
      expect(find.text('Google daily results'), findsOneWidget);
      expect(find.text('Campaign 01'), findsNothing);
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets(
      'Campaign names, controls and precise results fit $width including enlarged text',
      (t) async {
        final data = campaigns(count: 3);
        data['account'] = {...data['account'], 'currency': 'KWD'};
        data['rows'][2]['campaign_name'] =
            'KORLIX autumn launch — returning customers and new conversations';
        data['rows'][2]['spend'] = '3.123456';
        data['totals']['spend'] = '6.123456';
        final c = client((r) async => response(data));
        addTearDown(c.dispose);
        await shell(t, panel(c), width: width);
        await load(t);
        await t.ensureVisible(keyed('google-campaign-sort'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        Future<void> capture(String name) async {
          if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] != '1') return;
          await t.runAsync(() async {
            final image = await t
                .renderObject<RenderRepaintBoundary>(keyed('campaign-capture'))
                .toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '/tmp/k160-$name-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('controls');
        await tap(t, keyed('google-campaign-sort'));
        await t.tap(find.text('Most impressions').last);
        await t.pumpAndSettle();
        await t.ensureVisible(keyed('google-campaign-1002'));
        await t.pumpAndSettle();
        expect(find.text('Spent: KWD 3.123456'), findsOneWidget);
        expect(t.takeException(), isNull);
        await capture('results');
      },
    );
  }
}
