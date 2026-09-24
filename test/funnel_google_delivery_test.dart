import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_delivery.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'funnel_conversion_intake_test.dart' as intake;
import 'funnel_google_upload_access_test.dart' as upload;

const event = '00000000-0000-4000-8000-000000000003';
const enableText =
    'Prepare future consented inquiries for this conversion action. I will confirm each upload.';
const sendText =
    'Send this inquiry to the displayed Google conversion action once. This may affect conversion reporting and bidding.';
Map<String, dynamic> fixture({
  bool enabled = false,
  bool configured = true,
  List<String> states = const [],
}) => {
  'source': 'google_conversion_delivery',
  'funnel_id': intake.fid,
  'campaign_id': intake.cid,
  'campaign_name': 'Autumn campaign',
  'configured': configured,
  'can_enable': configured,
  'enabled': enabled,
  'current': enabled && configured,
  'fingerprint': 'a' * 64,
  'since': enabled ? '2026-09-24T12:00:00Z' : null,
  'destination': {
    'name': 'Inquiry submitted',
    'account_id': '1234567890',
    'action_id': '456',
  },
  'row_limit': 50,
  'provider_verified': false,
  'rows': List.generate(
    states.length,
    (i) => {
      'event_id': i == 0
          ? event
          : '00000000-0000-4000-8000-${(i + 3).toString().padLeft(12, '0')}',
      'captured_at': '2026-09-24T12:10:00Z',
      'click_type': 'gclid',
      'state': states[i],
      'checked_at':
          ['processing', 'succeeded', 'rejected', 'partial'].contains(states[i])
          ? '2026-09-24T12:11:00Z'
          : null,
      'has_warnings': false,
      'errors': [],
      'warnings': [],
      'can_check':
          configured && ['submitted', 'processing'].contains(states[i]),
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
          body: FunnelGoogleDelivery(
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
    'K192 strict status contract rejects wrong scope, secrets, inconsistent readiness and acceptance claims',
    () {
      validateGoogleDelivery(
        fixture(enabled: true, states: googleDeliveryLabels.keys.toList()),
        intake.fid,
        intake.cid,
      );
      for (final patch in <void Function(Map<String, dynamic>)>[
        (d) => d['funnel_id'] = 'foreign',
        (d) => d['campaign_id'] = 'foreign',
        (d) => d['provider_verified'] = true,
        (d) => d['configured'] = false,
        (d) => d['rows'][0]['state'] = 'accepted',
        (d) => d['rows'][0]['click_id'] = 'private',
        (d) => d['rows'][0]['can_check'] = true,
        (d) => d['rows'].add(d['rows'][0]),
        (d) => d['fingerprint'] = 'bad',
        (d) => d['rows'][0]['errors'] = [
          {'reason': 'private data', 'count': 1},
        ],
      ]) {
        final d = fixture(enabled: true, states: ['ready']);
        patch(d);
        expect(
          () => validateGoogleDelivery(d, intake.fid, intake.cid),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  testWidgets(
    'K192 opening reads locally and disabled platform cannot start delivery',
    (t) async {
      final calls = <http.Request>[];
      final c = client((r) {
        calls.add(r);
        return intake.reply(fixture(configured: false));
      });
      await app(t, c);
      expect(calls.length, 1);
      expect(calls.single.method, 'GET');
      expect(
        find.text('Google conversion delivery is awaiting platform setup.'),
        findsOneWidget,
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Prepare future inquiries'),
            )
            .onPressed,
        isNull,
      );
      expect(calls.where((x) => x.method == 'POST'), isEmpty);
    },
  );
  testWidgets(
    'K192 future setup requires confirmation and sends only exact settings',
    (t) async {
      final calls = <http.Request>[];
      final c = client((r) {
        calls.add(r);
        return intake.reply(fixture(enabled: r.method == 'POST'));
      });
      await app(t, c);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Prepare future inquiries'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, enableText);
      await tap(t, 'Prepare future inquiries');
      expect(jsonDecode(calls.last.body), {
        'enabled': true,
        'fingerprint': 'a' * 64,
        'confirmed': true,
      });
      expect(
        find.text('Future inquiries are prepared for your review.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'K192 selected inquiry needs separate confirmation; receipt never means success',
    (t) async {
      final calls = <http.Request>[];
      final c = client((r) {
        calls.add(r);
        return intake.reply(
          fixture(
            enabled: true,
            states: [r.method == 'POST' ? 'submitted' : 'ready'],
          ),
        );
      });
      await app(t, c);
      await tap(t, 'Select inquiry');
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send selected inquiry'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, sendText);
      await tap(t, 'Send selected inquiry');
      expect(calls.last.url.path.endsWith('/send'), true);
      expect(jsonDecode(calls.last.body), {
        'event_id': event,
        'fingerprint': 'a' * 64,
        'confirmed': true,
      });
      expect(
        find.text('Upload received — processing unverified'),
        findsOneWidget,
      );
      expect(find.text('Google processing succeeded'), findsNothing);
    },
  );
  testWidgets(
    'K192 uncertain POST gets local status once and never retries send',
    (t) async {
      final calls = <http.Request>[];
      final c = client((r) {
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
      });
      await app(t, c);
      await tap(t, 'Select inquiry');
      await tap(t, sendText);
      await tap(t, 'Send selected inquiry');
      expect(calls.map((r) => r.method).toList(), ['GET', 'POST', 'GET']);
      expect(find.text('Outcome uncertain — do not resend'), findsOneWidget);
      expect(find.text('Send selected inquiry'), findsNothing);
    },
  );
  testWidgets(
    'K192 manual status check posts only event id and cannot resubmit',
    (t) async {
      final calls = <http.Request>[];
      final c = client((r) {
        calls.add(r);
        return intake.reply(
          fixture(
            enabled: true,
            states: [r.method == 'POST' ? 'succeeded' : 'submitted'],
          ),
        );
      });
      await app(t, c);
      await tap(t, 'Check Google processing');
      expect(calls.last.url.path.endsWith('/check'), true);
      expect(jsonDecode(calls.last.body), {'event_id': event});
      expect(find.text('Google processing succeeded'), findsOneWidget);
      expect(find.text('Send selected inquiry'), findsNothing);
    },
  );
  testWidgets(
    'K192 scope change discards pending response and removes controls',
    (t) async {
      final scope = ValueNotifier(1), pending = Completer<http.Response>();
      var n = 0;
      final c = client((r) {
        n++;
        return n == 1
            ? intake.reply(fixture(enabled: true, states: ['ready']))
            : pending.future;
      });
      await app(t, c, scope: scope);
      await t.ensureVisible(find.text('Refresh saved delivery status'));
      await t.tap(find.text('Refresh saved delivery status'));
      await t.pump();
      scope.value++;
      pending.complete(intake.reply(fixture(enabled: true, states: ['ready'])));
      await t.pumpAndSettle();
      expect(find.text('Select inquiry'), findsNothing);
      expect(
        find.text(
          'Your workspace changed. Close Google delivery and open it again.',
        ),
        findsOneWidget,
      );
      scope.dispose();
    },
  );
  testWidgets(
    'K192 upload access opens delivery without starting authorization',
    (t) async {
      final calls = <http.Request>[];
      final c = client((r) {
        calls.add(r);
        return intake.reply(
          r.url.path.endsWith('/google-delivery') ? fixture() : upload.state(),
        );
      });
      await upload.app(t, c);
      await tap(t, 'Google conversion delivery');
      expect(find.text('Recent inquiry delivery'), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), true);
    },
  );
  for (final size in [1400.0, 390.0, 320.0]) {
    testWidgets('K192 real-font delivery layout at $size px', (t) async {
      t.view.physicalSize = Size(size, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await app(
        t,
        client(
          (_) => intake.reply(
            fixture(enabled: true, states: ['ready', 'uncertain', 'succeeded']),
          ),
        ),
        scale: size == 320 ? 1.3 : 1,
      );
      expect(t.takeException(), isNull);
      await tap(t, 'Select inquiry');
      await tap(t, sendText);
      expect(t.takeException(), isNull);
    });
  }
}
