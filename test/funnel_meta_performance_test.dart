import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta_performance.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';
import 'funnel_meta_test.dart' show connected, response;
import 'funnel_questions_test.dart' show keyed, tap;

Map<String, dynamic> connection() => {
  ...connected()['connection'],
  'selected_account': 'act_123',
};
Map<String, dynamic> report({String currency = 'USD', bool empty = false}) => {
  'source': 'meta',
  'scope': 'account',
  'connection_version': 7,
  'account': {
    'id': 'act_123',
    'name': 'KORLIX Growth',
    'currency': currency,
    'timezone': 'America/New_York',
  },
  'range': {'from': '2026-09-14', 'to': '2026-09-20', 'days': 7},
  'fetched_at': '2026-09-22T12:00:00Z',
  'reported_days': empty ? 0 : 2,
  'totals': {'spend': '12345.123456', 'impressions': 1234567, 'clicks': 9876},
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
  test(
    'Currency reporting preserves exact decimal values and groups counts without floating-point conversion',
    () {
      expect(metaMoney('KWD', '12345.123456'), 'KWD 12,345.123456');
      expect(metaMoney('JPY', '12345.00'), 'JPY 12,345.00');
      expect(metaCount(1234567), '1,234,567');
    },
  );
  testWidgets(
    'Reports load only on demand; changing period clears old results and request failures clear previous totals',
    (t) async {
      final calls = <http.Request>[];
      var fail = false;
      final c = client((r) async {
        calls.add(r);
        return fail
            ? response({'error': 'Meta is temporarily unavailable.'}, 503)
            : response(report());
      });
      addTearDown(c.dispose);
      await shell(
        t,
        FunnelMetaPerformance(
          client: c,
          connection: connection(),
          available: true,
        ),
      );
      expect(calls, isEmpty);
      await tap(t, keyed('meta-load-performance'));
      expect(calls.single.method, 'GET');
      expect(calls.single.url.queryParameters, {
        'days': '7',
        'account_id': 'act_123',
        'version': '7',
      });
      expect(find.text('USD 12,345.123456'), findsOneWidget);
      expect(find.textContaining('Entire selected ad account'), findsOneWidget);
      await tap(t, keyed('meta-period-30'));
      expect(find.text('USD 12,345.123456'), findsNothing);
      expect(calls.length, 1);
      await tap(t, keyed('meta-load-performance'));
      expect(calls.last.url.queryParameters['days'], '30');
      fail = true;
      await tap(t, keyed('meta-load-performance'));
      expect(find.text('USD 12,345.123456'), findsNothing);
      expect(find.text('Meta is temporarily unavailable.'), findsOneWidget);
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
          FunnelMetaPerformance(
            client: c,
            connection: entry.$1,
            available: entry.$2,
          ),
        );
        expect(
          t.widget<FilledButton>(keyed('meta-load-performance')).onPressed,
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
        FunnelMetaPerformance(
          client: c,
          connection: connection(),
          available: true,
        ),
      );
      await tap(t, keyed('meta-load-performance'));
      expect(find.textContaining('No totals are available'), findsOneWidget);
      expect(find.text('Amount spent'), findsNothing);
      expect(find.text('Daily results'), findsNothing);
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
            return FunnelMetaPerformance(
              client: c,
              connection: conn,
              available: available,
            );
          },
        ),
      );
      await t.tap(keyed('meta-load-performance'));
      await t.pump();
      change(
        () => conn = {...conn, 'version': 8, 'selected_account': 'act_999'},
      );
      await t.pump();
      pending.complete(response(report()));
      await t.pumpAndSettle();
      expect(find.text('KORLIX Growth'), findsNothing);
      pending = Completer<http.Response>();
      await t.tap(keyed('meta-load-performance'));
      await t.pump();
      change(() => available = false);
      await t.pump();
      pending.complete(
        response({
          ...report(),
          'connection_version': 8,
          'account': {...report()['account'], 'id': 'act_999'},
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
        FunnelMetaPerformance(
          client: c,
          connection: connection(),
          available: true,
        ),
      );
      await tap(t, keyed('meta-load-performance'));
      expect(find.text('USD 12,345.123456'), findsOneWidget);
      mismatch = true;
      await tap(t, keyed('meta-load-performance'));
      expect(find.text('USD 12,345.123456'), findsNothing);
      expect(find.textContaining('unreadable report'), findsOneWidget);
      mismatch = false;
      await tap(t, keyed('meta-load-performance'));
      await expectLater(
        c.request('GET', '/denied'),
        throwsA(isA<FunnelException>()),
      );
      await t.pumpAndSettle();
      expect(find.text('USD 12,345.123456'), findsNothing);
      expect(
        t.widget<FilledButton>(keyed('meta-load-performance')).onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'The Meta connection panel exposes reporting for the selected account and hides it on disconnect',
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
      await shell(t, FunnelMetaConnection(client: c));
      await tap(t, keyed('meta-load-performance'));
      expect(find.text('USD 12,345.123456'), findsOneWidget);
      await tap(t, find.text('Disconnect'));
      await tap(t, find.text('Disconnect Meta'));
      expect(find.text('USD 12,345.123456'), findsNothing);
      expect(
        t.widget<FilledButton>(keyed('meta-load-performance')).onPressed,
        isNull,
      );
      expect(calls.where((r) => r.url.path.endsWith('/performance')).length, 1);
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets(
      'Meta totals and daily rows fit $width with explicit currency and account scope',
      (t) async {
        final c = client((r) async => response(report(currency: 'KWD')));
        addTearDown(c.dispose);
        await shell(
          t,
          FunnelMetaPerformance(
            client: c,
            connection: connection(),
            available: true,
          ),
          width: width,
        );
        await tap(t, keyed('meta-load-performance'));
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
              '/tmp/k156-$name-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('totals');
        await tap(t, find.text('Daily results'));
        await t.ensureVisible(keyed('meta-day-2026-09-19'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Spent: KWD 0.123456'), findsOneWidget);
        await capture('daily');
      },
    );
  }
}
