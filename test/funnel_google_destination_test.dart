import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_destination.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'funnel_conversion_intake_test.dart' as intake;

Map<String, dynamic> destination() => {
  'conversion_customer_id': '1234567890',
  'conversion_action_id': '9223372036854775807',
  'resource_name': 'customers/1234567890/conversionActions/9223372036854775807',
  'name': 'Private lead action',
  'status': 'ENABLED',
  'type': 'UPLOAD_CLICKS',
  'category': 'SUBMIT_LEAD_FORM',
  'counting_type': 'ONE_PER_CLICK',
  'primary_for_goal': true,
  'click_window_days': 90,
  'attribution_model': 'GOOGLE_ADS_LAST_CLICK',
  'default_value': 0,
  'default_currency': 'USD',
  'always_use_default_value': false,
};
Map<String, dynamic> context() => {
  'account': {
    'id': '1234567890',
    'name': 'Private advertiser',
    'currency': 'USD',
    'timezone': 'America/New_York',
    'status': 'ENABLED',
    'manager': false,
    'test_account': false,
  },
  'root_id': '1234567890',
  'login_customer_id': null,
  'connection_version': 1,
  'provider_campaign_id': '456',
  'link_current': true,
  'editable': true,
};
Map<String, dynamic> state({
  bool saved = false,
  bool ready = true,
  int? version,
}) => {
  'source': 'google_conversion_destination',
  'funnel_id': intake.fid,
  'campaign_id': intake.cid,
  'campaign_name': 'Autumn campaign',
  'version': version ?? (saved ? 1 : 0),
  'fingerprint': 'a' * 64,
  'context': context()..['editable'] = ready,
  'lookup_ready': ready,
  'selection_current': saved && ready,
  'selection': saved
      ? {
          'destination': destination(),
          'context': context(),
          'checked_at': '2026-09-24T12:00:00Z',
          'saved_at': '2026-09-24T12:00:01Z',
        }
      : null,
  'event_name': 'inquiry_submitted',
  'delivery_state': 'not_implemented',
  'send_ready': false,
  'provider_verified': false,
};
Map<String, dynamic> choices({bool empty = false}) => {
  'source': 'google_conversion_choices',
  'funnel_id': intake.fid,
  'campaign_id': intake.cid,
  'fingerprint': 'a' * 64,
  'checked_at': '2026-09-24T12:00:00Z',
  'expires_at': '2026-09-24T12:05:00Z',
  'choices': empty
      ? []
      : [
          {'destination': destination(), 'proof': '1790251500000.${'b' * 64}'},
        ],
  'send_ready': false,
  'provider_verified': false,
};
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
          body: FunnelGoogleDestination(
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

Future<void> tap(WidgetTester t, String label) => intake.tap(t, label);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      final file = File(
        '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      );
      if (file.existsSync()) {
        await (FontLoader('Roboto')..addFont(
              Future.value(ByteData.sublistView(await file.readAsBytes())),
            ))
            .load();
      }
    }
  });
  test(
    'K190 validates account contexts, strict actions and rejects readiness overclaims',
    () {
      validateGoogleDestinationState(state(), intake.fid, intake.cid);
      validateGoogleDestinationState(
        state(saved: true, ready: false),
        intake.fid,
        intake.cid,
      );
      final offline = state(ready: false);
      offline['context'] = {
        'account': null,
        'root_id': null,
        'login_customer_id': null,
        'connection_version': 0,
        'provider_campaign_id': null,
        'link_current': false,
        'editable': true,
      };
      validateGoogleDestinationState(offline, intake.fid, intake.cid);
      for (final patch in <void Function(Map<String, dynamic>)>[
        (d) => d['campaign_id'] = 'foreign',
        (d) => d['send_ready'] = true,
        (d) => d['provider_verified'] = true,
        (d) => d['delivery_state'] = 'accepted',
        (d) => d['selection_current'] = true,
        (d) => d['context']['account']['test_account'] = true,
        (d) => d['context']['login_customer_id'] = '9999999999',
        (d) => d['context']['account']['manager'] = true,
        (d) => d['fingerprint'] = 'bad',
      ]) {
        final d = state();
        patch(d);
        expect(
          () => validateGoogleDestinationState(d, intake.fid, intake.cid),
          throwsA(isA<FunnelException>()),
        );
      }
      for (final patch in <void Function(Map<String, dynamic>)>[
        (d) => d['category'] = 'PURCHASE',
        (d) => d['unknown'] = true,
        (d) => d['conversion_action_id'] = '9223372036854775808',
        (d) => d['resource_name'] = 'foreign',
        (d) => d['click_window_days'] = 0,
        (d) => d['default_value'] = double.nan,
        (d) => d['primary_for_goal'] = null,
      ]) {
        final d = destination();
        patch(d);
        expect(
          () => validateGoogleDestination(d),
          throwsA(isA<FunnelException>()),
        );
      }
      for (final patch in <void Function(Map<String, dynamic>)>[
        (d) => d['choices'].add(d['choices'][0]),
        (d) => d['expires_at'] = '2026-09-24T12:10:00Z',
        (d) => d['choices'][0]['proof'] = 'bad',
        (d) => d['fingerprint'] = 'b' * 64,
      ]) {
        final d = choices();
        patch(d);
        expect(
          () => validateGoogleDestinationChoices(
            d,
            state(),
            intake.fid,
            intake.cid,
          ),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  testWidgets(
    'K190 reads locally, lists only on request and requires selection plus confirmation',
    (t) async {
      final requests = <http.Request>[];
      await app(
        t,
        intake.client((r) async {
          requests.add(r);
          return intake.reply(
            r.url.path.endsWith('/choices')
                ? choices()
                : r.method == 'POST'
                ? state(saved: true)
                : state(),
          );
        }),
      );
      expect(requests.length, 1);
      expect(requests.single.method, 'GET');
      expect(find.text(googleDestinationBoundary), findsOneWidget);
      await tap(t, 'Load Google conversion actions');
      expect(requests.length, 2);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save destination'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, 'Private lead action');
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save destination'),
            )
            .onPressed,
        isNull,
      );
      await tap(
        t,
        'Save this destination for inquiry measurement. This does not enable uploads.',
      );
      await tap(t, 'Save destination');
      expect(jsonDecode(requests.last.body), {
        'version': 0,
        'fingerprint': 'a' * 64,
        'confirmed': true,
        'destination': destination(),
        'proof': choices()['choices'][0]['proof'],
      });
      expect(
        find.text('Destination saved. Uploads remain off.'),
        findsOneWidget,
      );
      expect(find.text('Save destination'), findsNothing);
    },
  );
  testWidgets('K190 stale saved selection clears locally without lookup', (
    t,
  ) async {
    final requests = <http.Request>[];
    await app(
      t,
      intake.client((r) async {
        requests.add(r);
        return intake.reply(
          r.method == 'POST'
              ? state(ready: false, version: 2)
              : state(saved: true, ready: false),
        );
      }),
    );
    expect(find.text('Saved destination needs review'), findsOneWidget);
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(
              OutlinedButton,
              'Load Google conversion actions',
            ),
          )
          .onPressed,
      isNull,
    );
    await tap(t, 'Clear this saved destination.');
    await tap(t, 'Clear destination');
    expect(requests.length, 2);
    expect(requests.last.url.path.endsWith('/clear'), isTrue);
    expect(jsonDecode(requests.last.body), {
      'version': 1,
      'fingerprint': 'a' * 64,
      'confirmed': true,
    });
    expect(find.text('Saved destination cleared.'), findsOneWidget);
  });
  testWidgets('K190 refresh discards choices and empty discovery is explicit', (
    t,
  ) async {
    var empty = false;
    await app(
      t,
      intake.client(
        (r) async => intake.reply(
          r.url.path.endsWith('/choices') ? choices(empty: empty) : state(),
        ),
      ),
    );
    await tap(t, 'Load Google conversion actions');
    expect(find.text('Private lead action'), findsOneWidget);
    await tap(t, 'Refresh destination setup');
    expect(find.text('Private lead action'), findsNothing);
    empty = true;
    await tap(t, 'Load Google conversion actions');
    expect(
      find.text(
        'No eligible conversion actions found. Review conversion setup in Google Ads, then load the actions again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Save destination'), findsNothing);
  });
  testWidgets('K190 uncertain save discards choices and requires local refresh', (
    t,
  ) async {
    await app(
      t,
      intake.client(
        (r) async => r.method == 'POST'
            ? intake.reply({'error': 'Unavailable'}, 503)
            : intake.reply(
                r.url.path.endsWith('/choices') ? choices() : state(),
              ),
      ),
    );
    await tap(t, 'Load Google conversion actions');
    await tap(t, 'Private lead action');
    await tap(
      t,
      'Save this destination for inquiry measurement. This does not enable uploads.',
    );
    await tap(t, 'Save destination');
    expect(
      find.text(
        'Unavailable Refresh to check the saved state before trying again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Private lead action'), findsNothing);
    expect(find.text('Save destination'), findsNothing);
  });
  testWidgets('K190 workspace loss suppresses delayed provider data', (
    t,
  ) async {
    final wait = Completer<http.Response>(), scope = ValueNotifier(0);
    addTearDown(scope.dispose);
    await app(
      t,
      intake.client(
        (r) async => r.url.path.endsWith('/choices')
            ? wait.future
            : intake.reply(state()),
      ),
      scope: scope,
    );
    await t.ensureVisible(find.text('Load Google conversion actions'));
    await t.tap(find.text('Load Google conversion actions'));
    await t.pump();
    scope.value++;
    await t.pumpAndSettle();
    wait.complete(intake.reply(choices()));
    await t.pumpAndSettle();
    expect(
      find.text(
        'Your workspace changed. Close destination setup and open it again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Private lead action'), findsNothing);
    expect(find.text('Autumn campaign'), findsNothing);
  });
  testWidgets('K190 access denial removes saved private metadata', (t) async {
    var deny = false;
    await app(
      t,
      intake.client(
        (_) async => deny
            ? intake.reply({'error': 'Denied'}, 403)
            : intake.reply(state(saved: true)),
      ),
    );
    deny = true;
    await tap(t, 'Refresh destination setup');
    expect(
      find.text(
        'Sign in with Enterprise access to view conversion destinations.',
      ),
      findsOneWidget,
    );
    expect(find.text('Private lead action'), findsNothing);
  });
  testWidgets('K190 intake opens destination setup with only a local read', (
    t,
  ) async {
    final requests = <http.Request>[];
    await intake.app(
      t,
      intake.client((r) async {
        requests.add(r);
        return intake.reply(
          r.url.path.endsWith('/measurement')
              ? (intake.fixture()..['platform'] = 'google')
              : state(),
        );
      }),
    );
    await tap(t, 'Google conversion destination');
    expect(requests.length, 2);
    expect(
      requests.last.url.path.endsWith('/google-conversion-destination'),
      isTrue,
    );
    expect(requests.every((r) => r.method == 'GET'), isTrue);
  });
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('K190 destination layout at $width', (t) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await app(
        t,
        intake.client(
          (r) async => intake.reply(
            r.url.path.endsWith('/choices') ? choices() : state(saved: true),
          ),
        ),
        scale: width == 320 ? 1.3 : 1,
      );
      await tap(t, 'Load Google conversion actions');
      await t.ensureVisible(find.text('Save destination'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
