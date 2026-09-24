import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta_website_consent.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';
import 'funnel_conversion_intake_test.dart' as intake;
import 'funnel_meta_destination_test.dart' as destination;

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
    'source': 'meta_website_consent',
    'funnel_id': fid,
    'campaign_id': campaign,
    'name': 'Autumn campaign',
    'configured': available,
    'context_current': enabled,
    'armed_at': enabled ? '2026-09-24T10:00:00Z' : null,
    'enabled': enabled,
    'collecting': enabled && available,
    'can_enable': available,
    'revision': enabled ? '00000000-0000-4000-8000-000000000003' : null,
    'event_name': 'Lead',
    'action_source': 'website',
    'send_ready': false,
    'policy_version': 'meta_measurement_v2',
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
      'missing_browser': 1,
      'prepared': 2,
    },
    'rows': List.generate(
      days,
      (i) => {
        'day': start.add(Duration(days: i)).toIso8601String().substring(0, 10),
        'receipts': i == days - 1 ? 6 : 0,
        'declined': i == days - 1 ? 1 : 0,
        'missing_click': i == days - 1 ? 2 : 0,
        'missing_browser': i == days - 1 ? 1 : 0,
        'prepared': i == days - 1 ? 2 : 0,
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
          body: FunnelMetaWebsiteConsent(
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
    'K194 strict receipt contract rejects incorrect scope, states, totals, dates and provider claims',
    () {
      for (final days in [7, 30, 90]) {
        validateMetaWebsiteConsent(fixture(days: days), fid, cid, days);
      }
      for (final patch in <void Function(Map<String, dynamic>)>[
        (d) => d['campaign_id'] = 'foreign',
        (d) => d['funnel_id'] = 'foreign',
        (d) => d['days'] = 7,
        (d) => d['provider_verified'] = true,
        (d) => d['send_ready'] = true,
        (d) => d['client_user_agent'] = 'private',
        (d) => d['rows'][0]['click_id'] = 'private',
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
          () => validateMetaWebsiteConsent(d, fid, cid, 30),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  testWidgets(
    'K194 initial view reads only and exposes truthful receipt states',
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
      expect(
        requests.single.url.path.endsWith('/meta-website-consent'),
        isTrue,
      );
      expect(find.text(metaWebsiteConsentBoundary), findsOneWidget);
      expect(find.text('Website consent collection is off'), findsOneWidget);
      expect(find.text('Prepared website receipt'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'K194 enable and disable use the exact latest revision and explicit setting',
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
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enable website consent'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, 'Collect website context for future consenting inquiries.');
      await tap(t, 'Enable website consent');
      expect(requests.last.method, 'POST');
      expect(
        requests.last.url.path.endsWith('/meta-website-consent/settings'),
        isTrue,
      );
      expect(jsonDecode(requests.last.body), {
        'days': 30,
        'enabled': true,
        'expected_revision': null,
        'confirmed': true,
      });
      expect(find.text('Website consent collection is on'), findsOneWidget);
      await tap(t, 'Stop website context collection.');
      await tap(t, 'Disable website consent');
      expect(jsonDecode(requests.last.body), {
        'days': 30,
        'enabled': false,
        'expected_revision': '00000000-0000-4000-8000-000000000003',
        'confirmed': true,
      });
      expect(find.text('Website consent collection is off'), findsOneWidget);
    },
  );
  testWidgets(
    'K194 unavailable collection cannot enable; suspended enabled collection can disable',
    (t) async {
      for (final enabled in [false, true]) {
        await t.pumpWidget(const SizedBox());
        await app(
          t,
          client(
            (_) async => reply(fixture(enabled: enabled, available: false)),
          ),
        );
        await tap(
          t,
          enabled
              ? 'Stop website context collection.'
              : 'Collect website context for future consenting inquiries.',
        );
        final button = t.widget<FilledButton>(
          find.widgetWithText(
            FilledButton,
            enabled ? 'Disable website consent' : 'Enable website consent',
          ),
        );
        expect(button.onPressed, enabled ? isNotNull : isNull);
      }
    },
  );
  testWidgets('K194 stale-save failure clears settings and requires refresh', (
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
    await tap(t, 'Collect website context for future consenting inquiries.');
    await tap(t, 'Enable website consent');
    expect(
      find.text(
        'Measurement settings changed. Refresh before saving. Refresh to check the saved state before trying again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Autumn campaign'), findsNothing);
    expect(find.text('Enable website consent'), findsNothing);
    await tap(t, 'Refresh Meta website consent');
    expect(find.text('Enable website consent'), findsOneWidget);
  });
  testWidgets('K194 reporting windows and failures clear private data', (
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
    await tap(t, 'Refresh Meta website consent');
    expect(find.text('Storage unavailable'), findsOneWidget);
    expect(find.text('Autumn campaign'), findsNothing);
  });
  testWidgets('K194 malformed report never offers a settings action', (
    t,
  ) async {
    final d = fixture();
    d['totals']['receipts'] = 999;
    await app(t, client((_) async => reply(d)));
    expect(
      find.text('Meta website consent could not be verified. Refresh it.'),
      findsOneWidget,
    );
    expect(find.text('Enable website consent'), findsNothing);
  });
  testWidgets('K194 workspace loss suppresses delayed mutation results', (
    t,
  ) async {
    final wait = Completer<http.Response>(), scope = ValueNotifier(0);
    addTearDown(scope.dispose);
    final c = client(
      (r) async => r.method == 'POST' ? wait.future : reply(fixture()),
    );
    await app(t, c, scope: scope);
    await tap(t, 'Collect website context for future consenting inquiries.');
    await t.ensureVisible(find.text('Enable website consent'));
    await t.tap(find.text('Enable website consent'));
    await t.pump();
    scope.value++;
    await t.pumpAndSettle();
    wait.complete(reply(fixture(enabled: true)));
    await t.pumpAndSettle();
    expect(
      find.text(
        'Your workspace changed. Close Meta website consent and open it again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Autumn campaign'), findsNothing);
    expect(find.text('Disable website consent'), findsNothing);
  });
  testWidgets('K194 access denial removes private receipts', (t) async {
    var denied = false;
    final c = client(
      (_) async => denied ? reply({'error': 'Denied'}, 403) : reply(fixture()),
    );
    await app(t, c);
    denied = true;
    await tap(t, 'Refresh Meta website consent');
    expect(
      find.text('Sign in with Enterprise access to view Meta website consent.'),
      findsOneWidget,
    );
    expect(find.text('Autumn campaign'), findsNothing);
    expect(find.text('Refresh Meta website consent'), findsNothing);
  });
  testWidgets(
    'K194 both Meta entry points open consent with a local read only',
    (t) async {
      for (final fromDestination in [false, true]) {
        await t.pumpWidget(const SizedBox());
        final requests = <http.Request>[];
        final c = client((r) async {
          requests.add(r);
          return reply(
            r.url.path.endsWith('/meta-website-consent')
                ? fixture()
                : fromDestination
                ? destination.state()
                : intake.fixture(),
          );
        });
        if (fromDestination) {
          await destination.app(t, c);
        } else {
          await intake.app(t, c);
        }
        await tap(t, 'Meta website consent');
        expect(requests.length, 2);
        expect(requests.every((r) => r.method == 'GET'), isTrue);
        expect(
          requests.last.url.path.endsWith('/meta-website-consent'),
          isTrue,
        );
      }
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('K194 real-font Meta website consent at $width', (t) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await app(
        t,
        client((_) async => reply(fixture())),
        scale: width == 320 ? 1.3 : 1,
      );
      await t.ensureVisible(find.text('Enable website consent'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('2026-09-24'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
