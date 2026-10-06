import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/scheduling/scheduling_client.dart';
import 'package:ai_wiz_command_center/scheduling/scheduling_connected.dart';

const setup = <String, dynamic>{
  'id': 'setup-owner-a',
  'display_name': 'Owner A business',
  'country': 'US',
  'account_id': 'acct_owner_a',
  'livemode': false,
  'confirmed_at': null,
};
SchedulingMap workspace({bool enabled = true, bool existing = false}) => {
  'profile': {'display_name': 'Owner A business'},
  'merchant_setup': existing ? setup : null,
  'connections': [
    {
      'id': 'old-merchant',
      'provider': 'stripe',
      'state': 'connected',
      'enabled': true,
      'label': 'Current merchant',
      'livemode': false,
      'charges_enabled': false,
    },
  ],
  'capabilities': {
    'providers': {
      'stripe': {
        'configured': true,
        'onboarding_configured': enabled,
        'livemode': false,
      },
    },
  },
};
http.Response response(SchedulingMap value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);
SchedulingClient client(
  Future<http.Response> Function(http.Request) handle, {
  ValueNotifier<int>? changes,
  Map<String, String> Function()? headers,
}) => SchedulingClient(
  baseUrl: 'https://fixture.test',
  headersBuilder: headers ?? () => {'Authorization': 'Bearer owner-a'},
  sessionChanges: changes,
  client: MockClient(handle),
);
Future<void> panel(
  WidgetTester tester,
  SchedulingClient c, {
  bool existing = false,
  bool enabled = true,
  Future<void> Function()? refresh,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SchedulingConnectedPanel(
          mode: 'connections',
          data: workspace(existing: existing, enabled: enabled),
          client: c,
          refresh: refresh ?? () async {},
        ),
      ),
    ),
  ),
);
Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> closePanel(WidgetTester tester, SchedulingClient c) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  c.dispose();
}

void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <String>[];
  setUp(() {
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'launch') launched.add('${call.arguments['url']}');
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'business creation needs owner consent and preserves existing connection',
    (tester) async {
      final calls = <http.Request>[];
      final c = client((r) async {
        calls.add(r);
        return response({});
      });
      await panel(tester, c);
      await tester.pumpAndSettle();
      expect(find.text('Connect account'), findsOneWidget);
      await tap(tester, 'Set up Stripe business');
      expect(
        find.textContaining('sandbox Stripe business account'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your current merchant stays connected'),
        findsOneWidget,
      );
      await tap(tester, 'Cancel');
      expect(calls, isEmpty);
      expect(find.text('Current merchant'), findsOneWidget);
      expect(launched, isEmpty);
      await closePanel(tester, c);
    },
  );

  for (final host in ['connect.stripe.com', 'accounts.stripe.com']) {
    testWidgets('consented creation opens only hosted Stripe at $host', (
      tester,
    ) async {
      final calls = <http.Request>[];
      var refreshes = 0;
      final url = 'https://$host/r/acct_owner_a#alu_test_fixture';
      final c = client((r) async {
        calls.add(r);
        return response({'setup': setup, 'url': url});
      });
      await panel(
        tester,
        c,
        refresh: () async {
          refreshes++;
        },
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Set up Stripe business');
      expect(
        find.text(
          'Setup is currently available for United States businesses only.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('merchant-country')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        true,
      );
      await tester.enterText(
        find.byKey(const ValueKey('merchant-display-name')),
        '',
      );
      await tap(tester, 'Create Stripe account');
      expect(calls, isEmpty);
      expect(find.text('Enter your business name.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('merchant-display-name')),
        'New business',
      );
      await tap(tester, 'Create Stripe account');
      expect(
        calls.single.url.path,
        '/api/scheduling/stripe/merchant-setup/start',
      );
      expect(jsonDecode(calls.single.body), {
        'confirmed': true,
        'display_name': 'New business',
        'country': 'US',
      });
      expect(launched, [url]);
      expect(refreshes, 1);
      expect(find.text('Current merchant'), findsOneWidget);
      expect(calls.any((r) => r.url.path.endsWith('/confirm')), false);
      await closePanel(tester, c);
    });
  }

  testWidgets(
    'resume reuses saved setup and does not create or confirm an account',
    (tester) async {
      final calls = <http.Request>[];
      final c = client((r) async {
        calls.add(r);
        return response({
          'setup': setup,
          'url': 'https://accounts.stripe.com/r/acct_owner_a#alu_test_again',
        });
      });
      await panel(tester, c, existing: true);
      await tester.pumpAndSettle();
      expect(find.text('Set up Stripe business'), findsNothing);
      await tap(tester, 'Continue Stripe setup');
      expect(calls, isEmpty);
      await tap(tester, 'Continue to Stripe');
      expect(
        calls.single.url.path,
        '/api/scheduling/stripe/merchant-setup/setup-owner-a/resume',
      );
      expect(jsonDecode(calls.single.body), {'confirmed': true});
      expect(launched.length, 1);
      await closePanel(tester, c);
    },
  );

  testWidgets('untrusted setup links are never opened', (tester) async {
    for (final url in [
      'http://accounts.stripe.com/r/a',
      'https://accounts.stripe.com.attacker.test/r/a',
      'https://owner@accounts.stripe.com/r/a',
      'https://accounts.stripe.com:444/r/a',
    ]) {
      final c = client((r) async => response({'setup': setup, 'url': url}));
      await panel(tester, c, existing: true);
      await tester.pumpAndSettle();
      await tap(tester, 'Continue Stripe setup');
      await tap(tester, 'Continue to Stripe');
      expect(launched, isEmpty);
      expect(
        find.textContaining('Stripe setup link could not be verified'),
        findsOneWidget,
      );
      await closePanel(tester, c);
    }
  });

  testWidgets(
    'fresh review shows pending and replacement and confirms reviewed token only',
    (tester) async {
      final calls = <http.Request>[];
      final c = client((r) async {
        calls.add(r);
        if (r.method == 'GET') {
          return response({
            'setup': setup,
            'identity': {
              'id': 'acct_owner_a',
              'label': 'Verified business name',
              'livemode': false,
              'charges_enabled': false,
            },
            'replaces_existing': true,
            'review_token': 'review-owner-a-revision-7',
          });
        }
        return response({'saved': true});
      });
      await panel(tester, c, existing: true);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review and confirm business'));
      await tester.tap(find.text('Review and confirm business'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(calls.single.method, 'GET');
      expect(
        find.textContaining('Verified business name (acct_owner_a)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Stripe verification is still pending'),
        findsOneWidget,
      );
      expect(find.textContaining('Confirming replaces'), findsOneWidget);
      await tap(tester, 'Confirm account');
      expect(
        calls.last.url.path,
        '/api/scheduling/stripe/merchant-setup/setup-owner-a/confirm',
      );
      expect(jsonDecode(calls.last.body), {
        'confirmed': true,
        'review_token': 'review-owner-a-revision-7',
      });
      expect(launched, isEmpty);
      await closePanel(tester, c);
    },
  );

  testWidgets('account change discards in-flight merchant review', (
    tester,
  ) async {
    String token = 'Bearer owner-a';
    final changes = ValueNotifier(0), pending = Completer<http.Response>();
    final calls = <http.Request>[];
    final c = client(
      (r) {
        calls.add(r);
        return pending.future;
      },
      changes: changes,
      headers: () => {'Authorization': token},
    );
    await panel(tester, c, existing: true);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review and confirm business'));
    await tester.tap(find.text('Review and confirm business'));
    await tester.pump();
    token = 'Bearer owner-b';
    changes.value++;
    pending.complete(
      response({
        'identity': {'label': 'Private merchant'},
        'review_token': 'private',
      }),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Private merchant'), findsNothing);
    expect(find.text('Confirm account'), findsNothing);
    expect(calls.length, 1);
    await closePanel(tester, c);
    changes.dispose();
  });

  for (final size in [const Size(390, 844), const Size(1366, 1000)]) {
    testWidgets(
      'guided setup fits ${size.width} and respects backend availability',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = client((r) async => response({}));
        await panel(tester, c, enabled: false);
        await tester.pumpAndSettle();
        expect(find.text('Set up Stripe business'), findsNothing);
        expect(find.text('Connect account'), findsOneWidget);
        await panel(tester, c);
        await tester.pumpAndSettle();
        await tap(tester, 'Set up Stripe business');
        expect(tester.takeException(), isNull);
        await tap(tester, 'Cancel');
        await closePanel(tester, c);
      },
    );
  }
}
