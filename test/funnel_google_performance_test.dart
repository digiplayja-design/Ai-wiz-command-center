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
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_ads.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';
import 'funnel_google_ads_test.dart' show connected, response, root, account;
import 'funnel_questions_test.dart' show keyed, tap;

Map<String, dynamic> connection() => {
  ...connected()['connection'],
  'selected_account': account,
};
Map<String, dynamic> report({String currency = 'USD', bool empty = false}) => {
  'source': 'google_ads',
  'scope': 'account',
  'connection_version': 3,
  'root_id': root,
  'account': {
    'id': account,
    'name': 'KORLIX Growth',
    'currency': currency,
    'timezone': 'America/New_York',
    'test_account': true,
  },
  'range': {'from': '2026-09-14', 'to': '2026-09-20', 'days': 7},
  'fetched_at': '2026-09-22T12:00:00Z',
  'reported_days': empty ? 0 : 2,
  'totals': empty
      ? {'spend': '0.00', 'impressions': 0, 'clicks': 0}
      : {'spend': '12345.123456', 'impressions': 1234567, 'clicks': 9876},
  'rows': empty
      ? []
      : [
          {
            'date': '2026-09-20',
            'spend': '12345.00',
            'impressions': 1234500,
            'clicks': 9800,
          },
          {
            'date': '2026-09-19',
            'spend': '0.123456',
            'impressions': 67,
            'clicks': 76,
          },
        ],
};
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
  Future<void> shell(WidgetTester t, Widget child, {double width = 700}) async {
    await t.binding.setSurfaceSize(Size(width, 1100));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('performance-capture'),
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

  FunnelClient client(Future<http.Response> Function(http.Request) handler) =>
      FunnelClient(
        backendBaseUrl: 'https://example.com',
        headersBuilder: () => {'Authorization': 'current-user'},
        client: MockClient(handler),
      );
  testWidgets(
    'Reports load only on demand; changing period clears old results and request failures clear previous totals',
    (t) async {
      final calls = <http.Request>[];
      var fail = false;
      final c = client((r) async {
        calls.add(r);
        return fail
            ? response({'error': 'Google is temporarily unavailable.'}, 503)
            : response(report());
      });
      addTearDown(c.dispose);
      await shell(
        t,
        FunnelGooglePerformance(
          client: c,
          connection: connection(),
          available: true,
        ),
      );
      expect(calls, isEmpty);
      await tap(t, keyed('google-load-performance'));
      expect(calls.single.method, 'GET');
      expect(calls.single.url.queryParameters, {
        'days': '7',
        'account_id': account,
        'version': '3',
        'root_id': root,
      });
      expect(find.text('USD 12,345.123456'), findsOneWidget);
      expect(
        find.textContaining('Entire selected advertising account'),
        findsOneWidget,
      );
      await tap(t, keyed('google-period-30'));
      expect(find.text('USD 12,345.123456'), findsNothing);
      expect(calls.length, 1);
      await tap(t, keyed('google-load-performance'));
      expect(calls.last.url.queryParameters['days'], '30');
      expect(find.textContaining('could not be verified'), findsOneWidget);
      fail = true;
      await tap(t, keyed('google-load-performance'));
      expect(find.text('USD 12,345.123456'), findsNothing);
      expect(find.text('Google is temporarily unavailable.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Setup and selected-account requirements disable reporting without a provider request',
    (t) async {
      var count = 0;
      final c = client((r) async {
        count++;
        return response(report());
      });
      addTearDown(c.dispose);
      for (final entry in [
        (connection(), false),
        (<String, dynamic>{'version': 7}, true),
      ]) {
        await shell(
          t,
          FunnelGooglePerformance(
            client: c,
            connection: entry.$1,
            available: entry.$2,
          ),
        );
        expect(
          t.widget<FilledButton>(keyed('google-load-performance')).onPressed,
          isNull,
        );
      }
      expect(count, 0);
    },
  );
  testWidgets(
    'Empty provider results do not imply zero spend or fill missing dates',
    (t) async {
      final c = client((r) async => response(report(empty: true)));
      addTearDown(c.dispose);
      await shell(
        t,
        FunnelGooglePerformance(
          client: c,
          connection: connection(),
          available: true,
        ),
      );
      await tap(t, keyed('google-load-performance'));
      expect(find.textContaining('No totals are displayed'), findsOneWidget);
      expect(find.text('Amount spent'), findsNothing);
      expect(find.text('Google daily results'), findsNothing);
    },
  );
  testWidgets(
    'A report arriving after account reselection or disconnect cannot reappear',
    (t) async {
      var conn = connection(), available = true;
      late StateSetter change;
      var pending = Completer<http.Response>();
      final c = client((r) => pending.future);
      addTearDown(c.dispose);
      await shell(
        t,
        StatefulBuilder(
          builder: (context, set) {
            change = set;
            return FunnelGooglePerformance(
              client: c,
              connection: conn,
              available: available,
            );
          },
        ),
      );
      await t.tap(keyed('google-load-performance'));
      await t.pump();
      change(
        () => conn = {...conn, 'version': 8, 'selected_account': '1111111111'},
      );
      await t.pump();
      pending.complete(response(report()));
      await t.pumpAndSettle();
      expect(find.text('KORLIX Growth'), findsNothing);
      pending = Completer<http.Response>();
      await t.tap(keyed('google-load-performance'));
      await t.pump();
      change(() => available = false);
      await t.pump();
      pending.complete(
        response({
          ...report(),
          'connection_version': 8,
          'account': {...report()['account'], 'id': '1111111111'},
        }),
      );
      await t.pumpAndSettle();
      expect(find.text('KORLIX Growth'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Access loss clears already-loaded account figures and a mismatched response is rejected',
    (t) async {
      var mismatch = false;
      final c = client(
        (r) async => r.url.path.endsWith('/denied')
            ? response({'error': 'Access removed'}, 403)
            : response({...report(), if (mismatch) 'connection_version': 99}),
      );
      addTearDown(c.dispose);
      await shell(
        t,
        FunnelGooglePerformance(
          client: c,
          connection: connection(),
          available: true,
        ),
      );
      await tap(t, keyed('google-load-performance'));
      expect(find.text('USD 12,345.123456'), findsOneWidget);
      mismatch = true;
      await tap(t, keyed('google-load-performance'));
      expect(find.text('USD 12,345.123456'), findsNothing);
      expect(find.textContaining('could not be verified'), findsOneWidget);
      mismatch = false;
      await tap(t, keyed('google-load-performance'));
      await expectLater(
        c.request('GET', '/denied'),
        throwsA(isA<FunnelException>()),
      );
      await t.pumpAndSettle();
      expect(find.text('USD 12,345.123456'), findsNothing);
      expect(
        t.widget<FilledButton>(keyed('google-load-performance')).onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'The Google connection panel exposes reporting for the selected account and hides it on disconnect',
    (t) async {
      var state = {...connected(), 'connection': connection()};
      final calls = <http.Request>[];
      final c = client((r) async {
        calls.add(r);
        if (r.url.path.endsWith('/performance')) return response(report());
        if (r.url.path.endsWith('/disconnect')) {
          state = {'configured': true, 'connection': null};
        }
        return response(state);
      });
      addTearDown(c.dispose);
      await shell(t, FunnelGoogleAdsConnection(client: c));
      await tap(t, keyed('google-load-performance'));
      expect(find.text('USD 12,345.123456'), findsOneWidget);
      await tap(t, find.text('Disconnect Google'));
      await tap(t, find.text('Disconnect Google Ads'));
      expect(find.text('USD 12,345.123456'), findsNothing);
      expect(
        t.widget<FilledButton>(keyed('google-load-performance')).onPressed,
        isNull,
      );
      expect(calls.where((r) => r.url.path.endsWith('/performance')).length, 1);
    },
  );
  test(
    'Google report validation reconciles exact micros and rejects identity, range and metric corruption',
    () {
      expect(
        googlePerformanceReport(report(), connection(), 7)['reported_days'],
        2,
      );
      expect(
        googlePerformanceReport(report(empty: true), connection(), 7)['rows'],
        isEmpty,
      );
      final mutations = <void Function(Map<String, dynamic>)>[
        (r) => r['source'] = 'meta',
        (r) => r['scope'] = 'campaign',
        (r) => r['root_id'] = '0000000000',
        (r) => r['connection_version'] = 99,
        (r) => r['account']['id'] = '1111111111',
        (r) => r['account']['currency'] = 'bad',
        (r) => r['account']['timezone'] = '',
        (r) => r['account']['test_account'] = null,
        (r) => r['range']['days'] = 30,
        (r) => r['range']['from'] = '2026-09-15',
        (r) => r['range']['from'] = '2026-02-30',
        (r) => r['rows'][0]['date'] = '2026-09-21',
        (r) => r['rows'][1]['date'] = '2026-09-20',
        (r) => r['rows'] = (r['rows'] as List).reversed.toList(),
        (r) => r['rows'][0]['spend'] = '1e5',
        (r) => r['rows'][0]['spend'] = '-1.00',
        (r) => r['rows'][0]['spend'] = '1000000000000.000001',
        (r) => r['rows'][0]['impressions'] = 1.5,
        (r) => r['rows'][0]['clicks'] = null,
        (r) => r['rows'][0]['clicks'] = 9007199254740992,
        (r) => r['totals']['spend'] = '12345.123457',
        (r) => r['totals']['impressions'] = 1234568,
        (r) => r['reported_days'] = 3,
        (r) => r['fetched_at'] = 'invalid',
      ];
      for (final mutate in mutations) {
        final r = jsonDecode(jsonEncode(report())) as Map<String, dynamic>;
        mutate(r);
        expect(
          () => googlePerformanceReport(r, connection(), 7),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  testWidgets(
    'Returned zero metrics display zero; no returned rows suppress totals',
    (t) async {
      final r = report();
      r['reported_days'] = 1;
      r['rows'] = [
        {'date': '2026-09-20', 'spend': '0.00', 'impressions': 0, 'clicks': 0},
      ];
      r['totals'] = {'spend': '0.00', 'impressions': 0, 'clicks': 0};
      final c = client((_) async => response(r));
      addTearDown(c.dispose);
      await shell(
        t,
        FunnelGooglePerformance(
          client: c,
          connection: connection(),
          available: true,
        ),
      );
      await tap(t, keyed('google-load-performance'));
      expect(find.text('USD 0.00'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
    },
  );
  testWidgets('A newer period report wins over an older in-flight response', (
    t,
  ) async {
    final requests = <http.Request>[], replies = <Completer<http.Response>>[];
    final c = client((r) {
      requests.add(r);
      final reply = Completer<http.Response>();
      replies.add(reply);
      return reply.future;
    });
    addTearDown(c.dispose);
    await shell(
      t,
      FunnelGooglePerformance(
        client: c,
        connection: connection(),
        available: true,
      ),
    );
    await t.tap(keyed('google-load-performance'));
    await t.pump();
    await t.tap(keyed('google-period-30'));
    await t.pump();
    await t.tap(keyed('google-load-performance'));
    await t.pump();
    expect(requests.last.url.queryParameters['days'], '30');
    final r = report();
    r['range'] = {'days': 30, 'from': '2026-08-22', 'to': '2026-09-20'};
    r['account']['name'] = 'Current thirty-day report';
    replies[1].complete(response(r));
    await t.pumpAndSettle();
    replies[0].complete(response(report()));
    await t.pumpAndSettle();
    expect(find.text('Current thirty-day report'), findsOneWidget);
    expect(find.text('KORLIX Growth'), findsNothing);
    expect(find.textContaining('2026-08-22 – 2026-09-20'), findsOneWidget);
  });
  testWidgets(
    'Root, version, availability and client changes clear existing figures and old clients lose their listener',
    (t) async {
      var conn = connection(), available = true;
      final first = client(
        (r) async => r.url.path.endsWith('/denied')
            ? response({'error': 'Access removed'}, 401)
            : response(report()),
      );
      final second = client((r) async => response(report()));
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      var active = first;
      late StateSetter change;
      await shell(
        t,
        StatefulBuilder(
          builder: (_, set) {
            change = set;
            return FunnelGooglePerformance(
              client: active,
              connection: conn,
              available: available,
            );
          },
        ),
      );
      for (final kind in ['root', 'version', 'available', 'client']) {
        await tap(t, keyed('google-load-performance'));
        expect(find.text('USD 12,345.123456'), findsOneWidget);
        change(() {
          if (kind == 'root') conn = {...conn, 'root_id': '2222222222'};
          if (kind == 'version') conn = {...conn, 'version': 4};
          if (kind == 'available') available = false;
          if (kind == 'client') active = second;
        });
        await t.pumpAndSettle();
        expect(find.text('USD 12,345.123456'), findsNothing);
        change(() {
          conn = connection();
          available = true;
        });
        await t.pumpAndSettle();
      }
      await tap(t, keyed('google-load-performance'));
      await expectLater(
        first.request('GET', '/denied'),
        throwsA(isA<FunnelException>()),
      );
      await t.pumpAndSettle();
      expect(find.text('USD 12,345.123456'), findsOneWidget);
      expect(
        t.widget<FilledButton>(keyed('google-load-performance')).onPressed,
        isNotNull,
      );
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets(
      'Google totals and daily rows fit $width with explicit currency and account scope',
      (t) async {
        final c = client((r) async => response(report(currency: 'KWD')));
        addTearDown(c.dispose);
        await shell(
          t,
          FunnelGooglePerformance(
            client: c,
            connection: connection(),
            available: true,
          ),
          width: width,
        );
        await tap(t, keyed('google-load-performance'));
        await t.ensureVisible(find.text('KWD 12,345.123456'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        Future<void> capture(String name) async {
          if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] != '1') return;
          await t.runAsync(() async {
            final image = await t
                .renderObject<RenderRepaintBoundary>(
                  keyed('performance-capture'),
                )
                .toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '/tmp/k159-$name-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('totals');
        await tap(t, find.text('Google daily results'));
        await t.ensureVisible(keyed('google-day-2026-09-19'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Spent: KWD 0.123456'), findsOneWidget);
        await capture('daily');
      },
    );
  }
}
