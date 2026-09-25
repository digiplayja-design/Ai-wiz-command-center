import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta_delivery.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'funnel_conversion_intake_test.dart' as intake;
import 'funnel_meta_destination_test.dart' as destination;

const event = '00000000-0000-4000-8000-000000000003';
const enableText =
    'Prepare future consented website inquiries. I will confirm each Meta upload.';
const sendText =
    'Send this inquiry to the displayed Meta data source once. This may affect advertising measurement and optimization.';
const accessText =
    'Authorize this credential for the selected Meta data source.';
Map<String, dynamic> fixture({
  bool enabled = false,
  bool configured = true,
  bool connected = true,
  List<String> states = const [],
}) => {
  'source': 'meta_conversion_delivery',
  'funnel_id': intake.fid,
  'campaign_id': intake.cid,
  'campaign_name': 'Autumn campaign',
  'configured': configured,
  'can_authorize': configured,
  'can_enable': configured && connected,
  'enabled': enabled,
  'current': enabled && configured && connected,
  'fingerprint': 'a' * 64,
  'since': enabled ? '2026-09-25T00:00:00Z' : null,
  'authorization': {
    'connected': connected,
    'current': connected && configured,
    'expires_at': null,
    'checked_at': connected ? '2026-09-25T00:00:00Z' : null,
  },
  'destination': {'pixel_id': '987654321', 'name': 'Website inquiries'},
  'row_limit': 50,
  'provider_verified': false,
  'rows': List.generate(
    states.length,
    (i) => {
      'event_id': i == 0
          ? event
          : '00000000-0000-4000-8000-${(i + 3).toString().padLeft(12, '0')}',
      'captured_at': '2026-09-25T00:01:00Z',
      'state': states[i],
      'received_at': states[i] == 'received' ? '2026-09-25T00:02:00Z' : null,
      'has_warnings': false,
    },
  ),
};
FunnelClient client(FutureOr<http.Response> Function(http.Request) fn) =>
    FunnelClient(
      backendBaseUrl: 'https://example.com',
      headersBuilder: () => {},
      client: MockClient((r) async => await fn(r)),
    );
Future<void> app(
  WidgetTester t,
  FunnelClient c, {
  ValueNotifier<int>? scope,
  double scale = 1,
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: FunnelMetaDelivery(
            client: c,
            funnelId: intake.fid,
            campaignId: intake.cid,
            scope: scope,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String s) => intake.tap(t, s);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      final f = File(
        '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      );
      if (f.existsSync()) {
        final loader = FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));
        await loader.load();
      }
    }
  });
  test(
    'K195 strict status rejects secrets, wrong scope and unsupported claims',
    () {
      validateMetaDelivery(
        fixture(enabled: true, states: metaDeliveryLabels.keys.toList()),
        intake.fid,
        intake.cid,
      );
      for (final patch in <void Function(Map<String, dynamic>)>[
        (d) => d['funnel_id'] = 'foreign',
        (d) => d['campaign_id'] = 'foreign',
        (d) => d['provider_verified'] = true,
        (d) => d['configured'] = false,
        (d) => d['authorization']['access_token'] = 'private',
        (d) => d['authorization']['current'] = false,
        (d) => d['rows'][0]['state'] = 'attributed',
        (d) => d['rows'][0]['click_id'] = 'private',
        (d) => d['rows'].add(d['rows'][0]),
        (d) => d['rows'][0]['received_at'] = '2026-09-25T00:02:00Z',
        (d) => d['fingerprint'] = 'invalid',
        (d) => d['destination']['pixel_id'] = 'https://foreign.example',
      ]) {
        final d = fixture(enabled: true, states: ['ready']);
        patch(d);
        expect(
          () => validateMetaDelivery(d, intake.fid, intake.cid),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  testWidgets(
    'K195 opening is local and platform off exposes no credential input',
    (t) async {
      final calls = <http.Request>[];
      await app(
        t,
        client((r) {
          calls.add(r);
          return intake.reply(fixture(configured: false));
        }),
      );
      expect(calls.single.method, 'GET');
      expect(
        find.text('Meta conversion delivery is awaiting platform setup.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Prepare future Meta inquiries',
              ),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets('K195 enabling future inquiries needs exact confirmed settings', (
    t,
  ) async {
    final calls = <http.Request>[];
    await app(
      t,
      client((r) {
        calls.add(r);
        return intake.reply(fixture(enabled: r.method == 'POST'));
      }),
    );
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Prepare future Meta inquiries'),
          )
          .onPressed,
      isNull,
    );
    await tap(t, enableText);
    await tap(t, 'Prepare future Meta inquiries');
    expect(calls.last.url.path.endsWith('/settings'), true);
    expect(jsonDecode(calls.last.body), {
      'enabled': true,
      'fingerprint': 'a' * 64,
      'confirmed': true,
    });
    expect(
      find.text('Future website inquiries are prepared for your review.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'K195 selected inquiry needs confirmation and receipt is not attribution',
    (t) async {
      final calls = <http.Request>[];
      await app(
        t,
        client((r) {
          calls.add(r);
          return intake.reply(
            fixture(
              enabled: true,
              states: [r.method == 'POST' ? 'received' : 'ready'],
            ),
          );
        }),
      );
      await tap(t, 'Select Meta inquiry');
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send selected Meta inquiry'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, sendText);
      await tap(t, 'Send selected Meta inquiry');
      expect(calls.last.url.path.endsWith('/send'), true);
      expect(jsonDecode(calls.last.body), {
        'event_id': event,
        'fingerprint': 'a' * 64,
        'confirmed': true,
      });
      expect(
        find.text('Meta receipt received — attribution unverified'),
        findsOneWidget,
      );
      expect(find.text('Select Meta inquiry'), findsNothing);
    },
  );
  testWidgets('K195 uncertain send refreshes locally once without retry', (
    t,
  ) async {
    final calls = <http.Request>[];
    await app(
      t,
      client((r) {
        calls.add(r);
        if (r.method == 'POST') {
          return intake.reply({'error': 'Transport outcome unknown'}, 503);
        }
        return intake.reply(
          fixture(
            enabled: true,
            states: [calls.length == 1 ? 'ready' : 'uncertain'],
          ),
        );
      }),
    );
    await tap(t, 'Select Meta inquiry');
    await tap(t, sendText);
    await tap(t, 'Send selected Meta inquiry');
    expect(calls.map((r) => r.method).toList(), ['GET', 'POST', 'GET']);
    expect(find.text('Outcome uncertain — do not resend'), findsOneWidget);
    expect(find.text('Send selected Meta inquiry'), findsNothing);
  });
  for (final succeeds in [false, true]) {
    testWidgets(
      'K195 credential is obscured and cleared after authorization success=$succeeds',
      (t) async {
        final calls = <http.Request>[];
        await app(
          t,
          client((r) {
            calls.add(r);
            if (r.method == 'POST' && !succeeds) {
              return intake.reply({
                'error': 'Authorization could not be verified',
              }, 503);
            }
            return intake.reply(
              fixture(connected: succeeds && calls.length > 1),
            );
          }),
        );
        final field = find.widgetWithText(TextField, 'Meta system-user token');
        expect(t.widget<TextField>(field).obscureText, true);
        expect(t.widget<TextField>(field).enableSuggestions, false);
        await t.ensureVisible(field);
        await t.enterText(field, 'fixture-system-user-token');
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(
                  FilledButton,
                  'Save conversion authorization',
                ),
              )
              .onPressed,
          isNull,
        );
        await tap(t, accessText);
        await tap(t, 'Save conversion authorization');
        final sent = calls.singleWhere((r) => r.method == 'POST');
        expect(sent.url.path.endsWith('/authorize'), true);
        expect(jsonDecode(sent.body), {
          'access_token': 'fixture-system-user-token',
          'fingerprint': 'a' * 64,
          'confirmed': true,
        });
        expect(t.widget<TextField>(field).controller!.text, isEmpty);
        expect(
          t
              .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, accessText),
              )
              .value,
          false,
        );
        expect(
          calls.map((r) => r.method).toList(),
          succeeds ? ['GET', 'POST'] : ['GET', 'POST', 'GET'],
        );
      },
    );
  }
  testWidgets('K195 stop and disconnect require their own confirmations', (
    t,
  ) async {
    final calls = <http.Request>[];
    var enabled = true, connected = true;
    await app(
      t,
      client((r) {
        calls.add(r);
        if (r.method == 'POST') {
          enabled = false;
          if (r.url.path.endsWith('/disconnect')) connected = false;
        }
        return intake.reply(fixture(enabled: enabled, connected: connected));
      }),
    );
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(
              OutlinedButton,
              'Stop preparing Meta inquiries',
            ),
          )
          .onPressed,
      isNull,
    );
    await tap(t, 'Stop preparing Meta inquiries for delivery.');
    await tap(t, 'Stop preparing Meta inquiries');
    expect(jsonDecode(calls.last.body), {
      'enabled': false,
      'fingerprint': 'a' * 64,
      'confirmed': true,
    });
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Disconnect conversion access'),
          )
          .onPressed,
      isNull,
    );
    await tap(
      t,
      'Remove saved conversion access and stop preparing inquiries.',
    );
    await tap(t, 'Disconnect conversion access');
    expect(calls.last.url.path.endsWith('/disconnect'), true);
    expect(jsonDecode(calls.last.body), {
      'fingerprint': 'a' * 64,
      'confirmed': true,
    });
    expect(find.text('No conversion credential is saved.'), findsOneWidget);
  });
  testWidgets('K195 scope change clears token and discards pending response', (
    t,
  ) async {
    final scope = ValueNotifier(1), pending = Completer<http.Response>();
    var n = 0;
    final c = client(
      (r) => ++n == 1
          ? intake.reply(fixture(enabled: true, states: ['ready']))
          : pending.future,
    );
    await app(t, c, scope: scope);
    final field = find.widgetWithText(TextField, 'Meta system-user token');
    await t.ensureVisible(field);
    await t.enterText(field, 'fixture-system-user-token');
    final controller = t.widget<TextField>(field).controller!;
    await t.ensureVisible(find.text('Refresh saved Meta delivery'));
    await t.tap(find.text('Refresh saved Meta delivery'));
    await t.pump();
    scope.value++;
    pending.complete(intake.reply(fixture(enabled: true, states: ['ready'])));
    await t.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(find.text('Select Meta inquiry'), findsNothing);
    expect(
      find.text(
        'Your workspace changed. Close Meta delivery and open it again.',
      ),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
    scope.dispose();
  });
  testWidgets('K195 changed client clears private state and loads new scope', (
    t,
  ) async {
    await app(
      t,
      client((r) => intake.reply(fixture(enabled: true, states: ['ready']))),
    );
    final field = find.widgetWithText(TextField, 'Meta system-user token');
    await t.ensureVisible(field);
    await t.enterText(field, 'fixture-system-user-token');
    await app(
      t,
      client((r) => intake.reply(fixture(configured: false, connected: false))),
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Select Meta inquiry'), findsNothing);
    expect(find.text('No conversion credential is saved.'), findsOneWidget);
  });
  testWidgets('K195 denied access removes saved status and controls', (
    t,
  ) async {
    var n = 0;
    await app(
      t,
      client(
        (r) => ++n == 1
            ? intake.reply(fixture(enabled: true, states: ['ready']))
            : intake.reply({'error': 'Enterprise required'}, 403),
      ),
    );
    await tap(t, 'Refresh saved Meta delivery');
    expect(find.text('Select Meta inquiry'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('Sign in with Enterprise access to view Meta delivery.'),
      findsOneWidget,
    );
  });
  for (final fromDestination in [false, true]) {
    testWidgets(
      'K195 entry from destination=$fromDestination opens with GET only',
      (t) async {
        final calls = <http.Request>[];
        final c = client((r) {
          calls.add(r);
          return intake.reply(
            r.url.path.endsWith('/meta-delivery')
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
        await tap(t, 'Meta conversion delivery');
        expect(find.text('Recent Meta delivery'), findsOneWidget);
        expect(calls.length, 2);
        expect(calls.every((r) => r.method == 'GET'), true);
      },
    );
  }
  for (final size in [1400.0, 390.0, 320.0]) {
    testWidgets('K195 real-font delivery layout at $size px', (t) async {
      t.view.physicalSize = Size(size, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await app(
        t,
        client(
          (r) => intake.reply(
            fixture(enabled: true, states: ['ready', 'uncertain', 'received']),
          ),
        ),
        scale: size == 320 ? 1.3 : 1,
      );
      expect(t.takeException(), isNull);
      await tap(t, 'Select Meta inquiry');
      await tap(t, sendText);
      expect(t.takeException(), isNull);
    });
  }
}
