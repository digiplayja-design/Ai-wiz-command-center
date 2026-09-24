import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_conversion_intake.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

const fid = '00000000-0000-4000-8000-000000000001',
    cid = '00000000-0000-4000-8000-000000000002';
Map<String, dynamic> fixture({
  bool enabled = false,
  bool available = true,
  int days = 30,
  String campaign = cid,
}) {
  final start = DateTime.utc(2026, 9, 24).subtract(Duration(days: days - 1));
  return {
    'source': 'conversion_intake',
    'funnel_id': fid,
    'campaign_id': campaign,
    'name': 'Autumn campaign',
    'platform': 'meta',
    'enabled': enabled,
    'collecting': enabled && available,
    'can_enable': available,
    'revision': enabled ? '00000000-0000-4000-8000-000000000003' : null,
    'event_name': 'inquiry_submitted',
    'policy_version': 'measurement_v1',
    'provider_delivery': 'not_implemented',
    'provider_verified': false,
    'days': days,
    'from_day': start.toIso8601String().substring(0, 10),
    'through_day': '2026-09-24',
    'timezone': 'UTC',
    'includes_today': true,
    'checked_at': '2026-09-24T12:00:00Z',
    'totals': {
      'receipts': 6,
      'declined': 1,
      'missing_click': 2,
      'awaiting_setup': 3,
    },
    'rows': List.generate(
      days,
      (i) => {
        'day': start.add(Duration(days: i)).toIso8601String().substring(0, 10),
        'receipts': i == days - 1 ? 6 : 0,
        'declined': i == days - 1 ? 1 : 0,
        'missing_click': i == days - 1 ? 2 : 0,
        'awaiting_setup': i == days - 1 ? 3 : 0,
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
          body: FunnelConversionIntake(
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
    'K188 strict receipt contract rejects incorrect scope, states, totals, dates and provider claims',
    () {
      for (final days in [7, 30, 90]) {
        validateConversionIntake(fixture(days: days), fid, cid, days);
      }
      for (final patch in <void Function(Map<String, dynamic>)>[
        (d) => d['campaign_id'] = 'foreign',
        (d) => d['funnel_id'] = 'foreign',
        (d) => d['days'] = 7,
        (d) => d['provider_verified'] = true,
        (d) => d['provider_delivery'] = 'accepted',
        (d) => d['enabled'] = true,
        (d) => d['revision'] = 'bad',
        (d) => d['collecting'] = true,
        (d) => d['event_name'] = 'sale',
        (d) => d['policy_version'] = 'unknown',
        (d) => d['rows'][0]['declined'] = -1,
        (d) => d['rows'][0]['receipts'] = 1,
        (d) => d['totals']['receipts'] = 0,
        (d) => d['rows'][0]['day'] = '2026-01-01',
        (d) => d['through_day'] = '2026-02-31',
      ]) {
        final d = fixture();
        patch(d);
        expect(
          () => validateConversionIntake(d, fid, cid, 30),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  testWidgets(
    'K188 initial view reads only and exposes truthful receipt states',
    (t) async {
      final requests = <http.Request>[];
      await app(
        t,
        client((r) async {
          requests.add(r);
          return reply(fixture());
        }),
      );
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path.endsWith('/measurement'), isTrue);
      expect(find.text(conversionIntakeBoundary), findsOneWidget);
      expect(find.text('Consent collection is off'), findsOneWidget);
      expect(find.text('Awaiting conversion setup'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'K188 enable and disable use the exact latest revision and explicit setting',
    (t) async {
      final requests = <http.Request>[];
      final c = client((r) async {
        requests.add(r);
        return reply(
          fixture(
            enabled:
                r.method == 'POST' && jsonDecode(r.body)['enabled'] == true,
          ),
        );
      });
      await app(t, c);
      await tap(t, 'Enable consent collection');
      expect(requests.last.method, 'POST');
      expect(requests.last.url.path.endsWith('/measurement/settings'), isTrue);
      expect(jsonDecode(requests.last.body), {
        'days': 30,
        'enabled': true,
        'expected_revision': null,
      });
      expect(find.text('Consent collection is on'), findsOneWidget);
      await tap(t, 'Disable consent collection');
      expect(jsonDecode(requests.last.body), {
        'days': 30,
        'enabled': false,
        'expected_revision': '00000000-0000-4000-8000-000000000003',
      });
      expect(find.text('Consent collection is off'), findsOneWidget);
    },
  );
  testWidgets(
    'K188 unavailable collection cannot enable; suspended enabled collection can disable',
    (t) async {
      for (final enabled in [false, true]) {
        await t.pumpWidget(const SizedBox());
        await app(
          t,
          client(
            (_) async => reply(fixture(enabled: enabled, available: false)),
          ),
        );
        final button = t.widget<FilledButton>(
          find.widgetWithText(
            FilledButton,
            enabled
                ? 'Disable consent collection'
                : 'Enable consent collection',
          ),
        );
        expect(button.onPressed, enabled ? isNotNull : isNull);
      }
    },
  );
  testWidgets('K188 stale-save failure clears settings and requires refresh', (
    t,
  ) async {
    final c = client(
      (r) async => r.method == 'POST'
          ? reply({
              'error': 'Measurement settings changed. Refresh before saving.',
            }, 409)
          : reply(fixture()),
    );
    await app(t, c);
    await tap(t, 'Enable consent collection');
    expect(
      find.text('Measurement settings changed. Refresh before saving.'),
      findsOneWidget,
    );
    expect(find.text('Autumn campaign'), findsNothing);
    expect(find.text('Enable consent collection'), findsNothing);
    await tap(t, 'Refresh conversion intake');
    expect(find.text('Enable consent collection'), findsOneWidget);
  });
  testWidgets('K188 reporting windows and failures clear private data', (
    t,
  ) async {
    var fail = false;
    final seen = <int>[];
    final c = client((r) async {
      final days = int.parse(r.url.queryParameters['days']!);
      seen.add(days);
      return fail
          ? reply({'error': 'Storage unavailable'}, 503)
          : reply(fixture(days: days));
    });
    await app(t, c);
    await tap(t, 'Last 30 UTC days');
    await t.tap(find.text('Last 7 UTC days').last);
    await t.pumpAndSettle();
    expect(seen, [30, 7]);
    fail = true;
    await tap(t, 'Refresh conversion intake');
    expect(find.text('Storage unavailable'), findsOneWidget);
    expect(find.text('Autumn campaign'), findsNothing);
  });
  testWidgets('K188 malformed report never offers a settings action', (
    t,
  ) async {
    final d = fixture();
    d['totals']['receipts'] = 999;
    await app(t, client((_) async => reply(d)));
    expect(
      find.text('Conversion intake could not be verified. Refresh it.'),
      findsOneWidget,
    );
    expect(find.text('Enable consent collection'), findsNothing);
  });
  testWidgets('K188 workspace loss suppresses delayed mutation results', (
    t,
  ) async {
    final wait = Completer<http.Response>(), scope = ValueNotifier(0);
    addTearDown(scope.dispose);
    final c = client(
      (r) async => r.method == 'POST' ? wait.future : reply(fixture()),
    );
    await app(t, c, scope: scope);
    await t.ensureVisible(find.text('Enable consent collection'));
    await t.tap(find.text('Enable consent collection'));
    await t.pump();
    scope.value++;
    await t.pumpAndSettle();
    wait.complete(reply(fixture(enabled: true)));
    await t.pumpAndSettle();
    expect(
      find.text(
        'Your workspace changed. Close conversion intake and open it again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Autumn campaign'), findsNothing);
    expect(find.text('Disable consent collection'), findsNothing);
  });
  testWidgets('K188 access denial removes private receipts', (t) async {
    var denied = false;
    final c = client(
      (_) async => denied ? reply({'error': 'Denied'}, 403) : reply(fixture()),
    );
    await app(t, c);
    denied = true;
    await tap(t, 'Refresh conversion intake');
    expect(
      find.text('Sign in with Enterprise access to view conversion intake.'),
      findsOneWidget,
    );
    expect(find.text('Autumn campaign'), findsNothing);
    expect(find.text('Refresh conversion intake'), findsNothing);
  });
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('K188 real-font conversion intake at $width', (t) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await app(
        t,
        client((_) async => reply(fixture())),
        scale: width == 320 ? 1.3 : 1,
      );
      await t.ensureVisible(find.text('Enable consent collection'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('2026-09-24'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
