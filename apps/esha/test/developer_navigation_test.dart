import 'dart:async';
import 'dart:convert';

import 'package:esha_by_korlix/app_controller.dart';
import 'package:esha_by_korlix/models.dart';
import 'package:esha_by_korlix/services/korlix_api.dart';
import 'package:esha_by_korlix/services/purchases.dart';
import 'package:esha_by_korlix/services/vanity_sync.dart';
import 'package:esha_by_korlix/ui/account.dart';
import 'package:esha_by_korlix/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

class _NavigationFixture {
  _NavigationFixture({this.developer = true});

  final bool developer;
  final requests = <http.Request>[];
  Completer<http.Response>? firstStatus;
  late EshaController controller;
  int version = 0;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    controller.dispose();
  }

  Json get status => {
    'appAccess': {
      'active': developer,
      'source': developer ? 'developer' : null,
    },
    'membership': {
      'active': false,
      'trial': false,
      'verificationFresh': true,
      'expiresAt': null,
    },
    'allowance': {'limit': null, 'remaining': null},
    'consultationEnabled': false,
    'purchasesEnabled': false,
    'state': 'not_configured',
  };

  http.Response reply(Object body, [int code = 200]) =>
      http.Response(jsonEncode(body), code);

  Future<void> initialize() async {
    final local = MemoryStore();
    final api = KorlixApi(
      config: fixtureConfig(),
      secureStorage: MemoryStore(),
      localStorage: local,
      platform: 'unsupported',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/auth/signin') {
          return reply(authPayload(accountA));
        }
        if (request.url.path.startsWith('/rest/v1/')) {
          if (request.method == 'GET') return reply([]);
          return reply([
            {
              'state': object(jsonDecode(request.body))['state'],
              'version': ++version,
            },
          ]);
        }
        if (request.url.path == '/api/esha/billing/status') {
          final delayed = firstStatus;
          firstStatus = null;
          return delayed == null ? reply(status) : delayed.future;
        }
        // No native audio or paid service is configured in this regression.
        // Any accidental paid POST is recorded and asserted absent below.
        return reply({'error': 'Not configured'}, 503);
      }),
    );
    final sync = VanitySync(gateway: api, storage: local);
    await sync.attach(null);
    controller = EshaController(
      catalog: fixtureCatalog(),
      api: api,
      sync: sync,
      purchases: EshaPurchases(api, store: NoNativeStore()),
    )..initializing = false;
  }

  int get statusRequests => requests
      .where((request) => request.url.path == '/api/esha/billing/status')
      .length;

  Iterable<http.Request> get paidRequests => requests.where(
    (request) =>
        request.method == 'POST' &&
        (request.url.path == '/api/esha/consult' ||
            request.url.path == '/api/esha/voice/sessions'),
  );
}

Future<void> _signIn(
  WidgetTester tester, {
  String email = 'developer@example.test',
}) async {
  await tester.tap(find.byTooltip('Account, privacy and support'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('auth-email')), email);
  await tester.enterText(
    find.byKey(const ValueKey('auth-password')),
    'test-only-password',
  );
  final submit = find.byKey(const ValueKey('auth-submit'));
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, String label, int index) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
  expect(
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
    index,
  );
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'server-granted developer signs in and can tap every beauty tab and local actions without paid AI',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final f = _NavigationFixture();
      await f.initialize();
      addTearDown(f.close);
      await tester.pumpWidget(EshaApp(controller: f.controller));
      await tester.pumpAndSettle();

      await _signIn(tester);
      expect(f.controller.hasAppAccess, isTrue);
      expect(f.controller.purchases.membership.active, isFalse);
      expect(f.controller.purchases.canPurchase, isFalse);
      expect(find.byType(AccountScreen), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);

      final product = f.controller.catalog.products.first;
      await _tapVisible(tester, find.byTooltip('Favorite ${product.name}'));
      expect(f.controller.vanity.favorites, contains(product.id));

      await _tab(tester, 'Ask Esha', 1);
      await _tapVisible(tester, find.widgetWithText(ChoiceChip, 'Body ritual'));
      expect(f.controller.vanity.prefs.goal, 'body');
      await _tapVisible(
        tester,
        find.widgetWithText(ChoiceChip, 'Chat with Esha'),
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('esha-ai-sharing-consent')),
      );
      expect(f.controller.aiSharingConsented, isTrue);
      expect(f.controller.purchases.canConsult, isFalse);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Ask Esha'))
            .onPressed,
        isNull,
      );
      await _tapVisible(
        tester,
        find.widgetWithText(ChoiceChip, 'Voice with Esha'),
      );
      expect(f.controller.voice.canStart, isFalse);

      await _tab(tester, 'Try a Look', 2);
      await _tapVisible(tester, find.widgetWithText(ChoiceChip, 'Gloss'));
      expect(f.controller.vanity.studio.finish, 'Gloss');
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Save this look'),
      );
      expect(f.controller.vanity.looks, hasLength(1));

      await _tab(tester, 'My Vanity', 3);
      expect(find.widgetWithText(ChoiceChip, 'Favorites (1)'), findsOneWidget);
      await _tapVisible(tester, find.widgetWithText(ChoiceChip, 'Looks (1)'));
      expect(find.textContaining(' · Gloss'), findsOneWidget);
      await _tab(tester, 'Discover', 0);
      expect(
        find.byTooltip('Remove ${product.name} from favorites'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Esha membership'));
      await tester.pumpAndSettle();
      expect(find.text('Your developer access is active.'), findsOneWidget);
      expect(find.text('Your membership is active.'), findsNothing);
      expect(
        find.text('Membership verified by the store service.'),
        findsNothing,
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('membership-open-esha')),
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(f.paidRequests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.close();
    },
  );

  testWidgets('delayed verified access offers a working Open Esha action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pending = Completer<http.Response>();
    final f = _NavigationFixture()..firstStatus = pending;
    await f.initialize();
    addTearDown(f.close);
    await tester.pumpWidget(EshaApp(controller: f.controller));
    await tester.pumpAndSettle();
    await _signIn(tester);

    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('account-open-esha')), findsNothing);
    pending.complete(f.reply(f.status));
    await tester.pumpAndSettle();
    expect(find.text('Developer access'), findsOneWidget);
    await _tapVisible(tester, find.byKey(const ValueKey('account-open-esha')));
    expect(find.byType(AccountScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(f.paidRequests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.close();
  });

  testWidgets(
    'an email without a server grant stays gated while account and refresh controls respond',
    (tester) async {
      final f = _NavigationFixture(developer: false);
      await f.initialize();
      addTearDown(f.close);
      await tester.pumpWidget(EshaApp(controller: f.controller));
      await tester.pumpAndSettle();
      await _signIn(tester, email: 'support@korlixdeveloper.com');

      expect(f.controller.hasAppAccess, isFalse);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byKey(const ValueKey('account-open-esha')), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsNothing);
      expect(find.byType(MembershipScreen), findsOneWidget);
      final before = f.statusRequests;
      await _tapVisible(
        tester,
        find.widgetWithText(TextButton, 'Refresh status'),
      );
      expect(f.statusRequests, before + 1);
      await tester.tap(find.byTooltip('Account, privacy and support'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(f.controller.hasAppAccess, isFalse);
      expect(f.paidRequests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.close();
    },
  );
}
