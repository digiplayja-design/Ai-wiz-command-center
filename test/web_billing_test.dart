import 'dart:async';
import 'dart:convert';
import 'package:ai_wiz_command_center/billing/web_billing_client.dart';
import 'package:ai_wiz_command_center/billing/web_billing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String token(String user) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'https://fixture.test', 'sub': user, 'session_id': 'session-$user'})))}.s';
Map<String, dynamic> status() => {
  'version': 'web_monthly_20261004',
  'tier': 'basic',
  'livePayments': true,
  'checkoutEnabled': true,
  'canPurchase': true,
  'canManage': false,
  'nativeSubscription': false,
  'membership': null,
  'plans': [
    {
      'tier': 'pro',
      'name': 'Pro',
      'amount': 3499,
      'currency': 'usd',
      'interval': 'month',
      'features': [
        '30 AI requests and 60 credits per day',
        '2 video generations per month',
        'All AI characters',
      ],
    },
    {
      'tier': 'ultra',
      'name': 'Ultra Premium',
      'amount': 12499,
      'currency': 'usd',
      'interval': 'month',
      'features': [
        '75 AI requests and 200 credits per day',
        '10 video generations per month',
        'All AI characters',
      ],
    },
  ],
};

class Fixture {
  String user = 'owner';
  final revision = ValueNotifier(0);
  final requests = <http.Request>[];
  final links = <Uri>[];
  Completer<http.Response>? gate;
  String checkoutUrl = 'https://checkout.stripe.com/c/pay/fixture';
  http.Response json(Map<String, dynamic> value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json'},
  );
  late final client = WebBillingClient(
    baseUrl: 'https://backend.fixture',
    headersBuilder: () => {'Authorization': 'Bearer ${token(user)}'},
    sessionChanges: revision,
    httpClient: MockClient((req) async {
      requests.add(req);
      if (gate != null) return gate!.future;
      return req.url.path.endsWith('/checkout')
          ? json({'url': checkoutUrl})
          : json(status());
    }),
  );
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    String? returned,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: WebBillingScreen(
          client: client,
          checkoutReturn: returned,
          openUrl: (uri) async {
            links.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets('Plans fit width $width without overflow', (tester) async {
      final f = Fixture();
      await f.pump(tester, size: Size(width, 960));
      expect(find.text('Plans & Billing'), findsOneWidget);
      expect(find.text('USD \$34.99 / month'), findsOneWidget);
      expect(find.text('USD \$124.99 / month'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Contact Sales').last,
        600,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('large phone text remains scrollable', (tester) async {
    final f = Fixture();
    await f.pump(tester, size: const Size(320, 844), scale: 1.8);
    await tester.scrollUntilVisible(
      find.text('Choose Pro'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Choose Pro'));
    await tester.pumpAndSettle();
    expect(find.text('Subscribe to Pro?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('recurring consent is required before opening Stripe', (
    tester,
  ) async {
    final f = Fixture();
    await f.pump(tester);
    await tester.ensureVisible(find.text('Choose Pro'));
    await tester.tap(find.text('Choose Pro'));
    await tester.pumpAndSettle();
    final proceed = find.widgetWithText(FilledButton, 'Continue to Stripe');
    expect(tester.widget<FilledButton>(proceed).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(proceed);
    await tester.pumpAndSettle();
    expect(f.links.single.host, 'checkout.stripe.com');
    final body = jsonDecode(f.requests.last.body);
    expect(body['tier'], 'pro');
    expect(body['acceptRecurring'], true);
    expect(body.containsKey('amount'), false);
  });
  testWidgets('account switch dismisses consent and clears private status', (
    tester,
  ) async {
    final f = Fixture();
    await f.pump(tester);
    await tester.ensureVisible(find.text('Choose Pro'));
    await tester.tap(find.text('Choose Pro'));
    await tester.pumpAndSettle();
    f.user = 'other';
    f.revision.value++;
    await tester.pumpAndSettle();
    expect(find.text('Subscribe to Pro?'), findsNothing);
    expect(find.text('Your membership'), findsNothing);
    expect(f.requests.where((r) => r.url.path.endsWith('/checkout')), isEmpty);
    expect(f.links, isEmpty);
  });
  testWidgets(
    'return from checkout refreshes server status and does not assume payment',
    (tester) async {
      final f = Fixture();
      await f.pump(tester, returned: 'return');
      expect(f.requests.first.method, 'POST');
      expect(f.requests.first.url.path.endsWith('/refresh'), true);
      expect(
        find.text(
          'You are using the free Basic plan. Choose a monthly plan when you need more capacity.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('late response from a previous account is rejected', () async {
    final f = Fixture();
    f.gate = Completer();
    final pending = f.client.status();
    f.user = 'other';
    f.revision.value++;
    f.gate!.complete(f.json(status()));
    await expectLater(pending, throwsA(isA<WebBillingException>()));
    f.client.dispose();
  });
  test('untrusted payment links cannot redirect users', () async {
    for (final url in [
      'http://checkout.stripe.com/pay',
      'https://checkout.stripe.com.evil.invalid/pay',
      'https://user@checkout.stripe.com/pay',
    ]) {
      final f = Fixture()..checkoutUrl = url;
      await expectLater(
        f.client.checkout('pro', 'web_monthly_20261004'),
        throwsA(isA<WebBillingException>()),
      );
      f.client.dispose();
    }
  });
}
