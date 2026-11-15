import 'dart:async';
import 'dart:convert';

import 'package:esha_by_korlix/app_controller.dart';
import 'package:esha_by_korlix/models.dart';
import 'package:esha_by_korlix/services/korlix_api.dart';
import 'package:esha_by_korlix/services/purchases.dart';
import 'package:esha_by_korlix/services/vanity_sync.dart';
import 'package:esha_by_korlix/ui/account.dart';
import 'package:esha_by_korlix/ui/app.dart';
import 'package:esha_by_korlix/ui/brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

class AccessStorage extends MemoryStore {
  Completer<void>? pendingWrite;
  @override
  Future<void> write(String key, String value) async {
    if (key.startsWith('esha.consultation.pending.') && pendingWrite != null) {
      await pendingWrite!.future;
    }
    await super.write(key, value);
  }
}

class AccessFixture {
  DateTime now = DateTime.utc(2026, 11, 15, 12);
  late String? expiry = now.add(const Duration(days: 30)).toIso8601String();
  bool active = true, fresh = true, trial = false, offline = false;
  bool failQuestion = false;
  int remaining = 10, version = 0;
  String account = accountA;
  String? warning;
  Completer<http.Response>? nextStatus;
  final secure = AccessStorage(), local = MemoryStore();
  final List<Json> questions = [];
  late KorlixApi api;
  late EshaController c;
  Json get status => {
    'consultationEnabled': true,
    'membership': {
      'active': active,
      'verificationFresh': fresh,
      'trial': trial,
      'expiresAt': expiry,
    },
    'allowance': {'limit': 20, 'remaining': remaining},
    if (warning != null) 'warning': warning,
  };
  http.Response reply(Object body, [int code = 200]) =>
      http.Response(jsonEncode(body), code);

  Future<void> start({bool signedIn = true}) async {
    api = KorlixApi(
      config: fixtureConfig(),
      secureStorage: secure,
      localStorage: local,
      platform: 'unsupported',
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/signin') {
          return reply(authPayload(account));
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
          final delayed = nextStatus;
          nextStatus = null;
          if (delayed != null) return delayed.future;
          if (offline) return reply({'error': 'Unavailable'}, 503);
          return reply(status);
        }
        if (request.url.path == '/api/esha/consult') {
          final body = object(jsonDecode(request.body));
          questions.add(body);
          if (failQuestion) return reply({'error': 'Unavailable'}, 503);
          return reply({
            'requestId': body['requestId'],
            'answer': 'Try a satin lip.',
            'usage': {'limit': 20, 'remaining': remaining},
          });
        }
        return reply({});
      }),
    );
    c = EshaController(
      catalog: fixtureCatalog(),
      api: api,
      sync: VanitySync(gateway: api, storage: local),
      purchases: EshaPurchases(api, store: NoNativeStore(), now: () => now),
    );
    if (signedIn) {
      await c.signIn('member@example.test', 'not-a-real-password');
      await c.purchases.refresh();
    } else {
      await c.sync.attach(null);
    }
    c.initializing = false;
  }

  bool _closed = false;
  void close() {
    if (_closed) return;
    _closed = true;
    c.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('verified trial and paid membership unlock all core features even with no AI allowance', () async {
    final f = AccessFixture()..remaining = 0;
    await f.start();
    addTearDown(f.close);
    for (final trial in [true, false]) {
      f.trial = trial;
      await f.c.purchases.refresh();
      expect(f.c.hasAppAccess, isTrue);
      expect(f.c.purchases.canConsult, isFalse);
      final product = f.c.catalog.products.first;
      f.c.toggleFavorite(product);
      expect(f.c.vanity.favorites, contains(product.id));
      f.c.toggleFavorite(product);
      expect(f.c.saveLook(), isTrue);
    }
  });

  test('inactive, stale, missing, malformed and expired store entitlements stay locked', () async {
    final f = AccessFixture();
    await f.start();
    addTearDown(f.close);
    for (final expiry in [
      null,
      'not-a-date',
      f.now.toIso8601String(),
      f.now.subtract(const Duration(seconds: 1)).toIso8601String(),
    ]) {
      f.expiry = expiry;
      await f.c.purchases.refresh();
      expect(f.c.hasAppAccess, isFalse, reason: '$expiry');
    }
    f.expiry = f.now.add(const Duration(days: 1)).toIso8601String();
    f.fresh = false;
    await f.c.purchases.refresh();
    expect(f.c.hasAppAccess, isFalse);
    f.fresh = true;
    f.active = false;
    await f.c.purchases.refresh();
    expect(f.c.hasAppAccess, isFalse);
  });

  test('quiet refresh keeps valid access but a failed fresh check or store warning locks honestly', () async {
    final f = AccessFixture();
    await f.start();
    addTearDown(f.close);
    final delayed = Completer<http.Response>();
    f.nextStatus = delayed;
    final refresh = f.c.purchases.refresh();
    expect(f.c.hasAppAccess, isTrue);
    f.c.purchases.applyAllowance({'limit': 20, 'remaining': 9});
    delayed.complete(f.reply({'error': 'Unavailable'}, 503));
    await refresh;
    expect(f.c.hasAppAccess, isFalse);
    expect(f.c.purchases.accessMessage, contains('Connect to verify'));
    expect(f.c.purchases.canPurchase, isFalse);
    f.warning = 'The store could not refresh every membership.';
    await f.c.purchases.refresh();
    expect(f.c.hasAppAccess, isFalse);
    f.warning = null;
    await f.c.purchases.refresh();
    expect(f.c.hasAppAccess, isTrue);
  });

  test('account switch rejects an old account status even before a new status arrives', () async {
    final f = AccessFixture();
    await f.start();
    addTearDown(f.close);
    final oldStatus = f.status;
    final delayed = Completer<http.Response>();
    f.nextStatus = delayed;
    final refresh = f.c.purchases.refresh();
    f.account = accountB;
    await f.api.signIn('other@example.test', 'not-a-real-password');
    expect(f.c.hasAppAccess, isFalse);
    delayed.complete(f.reply(oldStatus));
    await refresh;
    expect(f.c.hasAppAccess, isFalse);
    f.c.purchases.accountChanged();
    await f.c.purchases.refresh();
    expect(f.c.hasAppAccess, isTrue);
    await f.c.signOut();
    expect(f.c.hasAppAccess, isFalse);
  });

  test('locked controller cannot modify saved products, edits or looks and preserves existing data', () async {
    final f = AccessFixture();
    await f.start();
    addTearDown(f.close);
    final product = f.c.catalog.products.first;
    f.c.toggleFavorite(product);
    f.c.saveLook();
    final before = jsonEncode(f.c.vanity.toJson());
    f.active = false;
    await f.c.purchases.refresh();
    f.c.toggleFavorite(product);
    f.c.toggleOwned(product);
    f.c.setPreferences(f.c.vanity.prefs.copyWith(budget: 100));
    f.c.setStudio(f.c.vanity.studio.copyWith(shade: 1));
    expect(f.c.saveRoutine(), isFalse);
    expect(f.c.saveLook(), isFalse);
    f.c.deleteLook(f.c.vanity.looks.first.id);
    f.c.deleteRoutine('example');
    expect(jsonEncode(f.c.vanity.toJson()), before);
  });

  test('pending AI replay keeps its ID, needs current entitlement and consent, but no second allowance', () async {
    final f = AccessFixture()..failQuestion = true;
    await f.start();
    addTearDown(f.close);
    f.c.setAiSharingConsent(true);
    await f.c.ask('Which finish?');
    final original = jsonEncode(f.questions.single);
    f.active = false;
    await f.c.purchases.refresh();
    await f.c.retryQuestion();
    expect(f.questions, hasLength(1));
    expect(f.c.hasPendingQuestion, isTrue);
    f.active = true;
    f.remaining = 0;
    f.failQuestion = false;
    await f.c.purchases.refresh();
    f.c.setAiSharingConsent(false);
    await f.c.retryQuestion();
    expect(f.questions, hasLength(1));
    f.c.setAiSharingConsent(true);
    await f.c.retryQuestion();
    expect(f.questions, hasLength(2));
    expect(jsonEncode(f.questions.last), original);
    expect(f.c.hasPendingQuestion, isFalse);
  });

  test('entitlement loss while a pending question is being saved prevents dispatch', () async {
    final f = AccessFixture();
    await f.start();
    addTearDown(f.close);
    f.c.setAiSharingConsent(true);
    final saved = Completer<void>();
    f.secure.pendingWrite = saved;
    final asking = f.c.ask('Which finish?');
    f.active = false;
    await f.c.purchases.refresh();
    saved.complete();
    await asking;
    expect(f.questions, isEmpty);
    expect(f.c.hasPendingQuestion, isTrue);
  });

  testWidgets(
    'signed-out feature access is locked while account and membership management stay accessible',
    (tester) async {
      final f = AccessFixture();
      await f.start(signedIn: false);
      addTearDown(f.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: eshaTheme,
          home: EshaHome(controller: f.c),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(IndexedStack), findsNothing);
      expect(find.byKey(const Key('catalog-search')), findsNothing);
      for (final label in [
        'Restore purchases',
        'Manage subscription',
        'Privacy Policy',
        'Terms of Use',
        'Contact support',
        'Sign in or create an account',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Account, privacy and support'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.close();
    },
  );

  testWidgets(
    'foreground expiry locks the app and an already-open product sheet',
    (tester) async {
      final f = AccessFixture();
      f.expiry = f.now.add(const Duration(seconds: 3)).toIso8601String();
      await f.start();
      addTearDown(f.close);
      final product = f.c.catalog.products.first;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showProduct(context, product, f.c),
                child: const Text('Open product'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open product'));
      await tester.pumpAndSettle();
      expect(find.text(product.name), findsOneWidget);
      f.now = f.now.add(const Duration(seconds: 4));
      f.offline = true;
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(f.c.hasAppAccess, isFalse);
      expect(find.text(product.name), findsNothing);
      expect(find.text('Close this view'), findsOneWidget);
      expect(find.textContaining('Connect to verify'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.close();
    },
  );

  testWidgets(
    'freshness deadline locks even while a quiet refresh is still pending',
    (tester) async {
      final f = AccessFixture();
      await f.start();
      addTearDown(f.close);
      await tester.pumpWidget(MaterialApp(home: EshaHome(controller: f.c)));
      expect(find.byType(IndexedStack), findsOneWidget);
      final delayed = Completer<http.Response>();
      f.nextStatus = delayed;
      f.now = f.now.add(EshaPurchases.refreshInterval);
      await tester.pump(EshaPurchases.refreshInterval);
      expect(f.c.hasAppAccess, isTrue);
      f.offline = true;
      f.now = f.now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      await tester.pumpAndSettle();
      expect(f.c.hasAppAccess, isFalse);
      expect(find.byType(IndexedStack), findsNothing);
      delayed.complete(f.reply(f.status));
      await tester.pumpAndSettle();
      expect(
        f.c.hasAppAccess,
        isFalse,
        reason: 'older refresh cannot revive the expired verification lease',
      );
      await tester.pumpWidget(const SizedBox());
      f.close();
    },
  );

  testWidgets(
    'signed-in locked accounts retain deletion, privacy withdrawal and support controls',
    (tester) async {
      final f = AccessFixture()..active = false;
      await f.start();
      addTearDown(f.close);
      f.c.setAiSharingConsent(true);
      await tester.pumpWidget(
        MaterialApp(home: AccountScreen(controller: f.c)),
      );
      expect(find.text('Request Korlix account deletion'), findsOneWidget);
      expect(find.text('Manage store subscription'), findsOneWidget);
      expect(find.text('Contact support'), findsOneWidget);
      await tester.ensureVisible(find.text('Stop sharing with OpenAI'));
      await tester.tap(find.text('Stop sharing with OpenAI'));
      await tester.pump();
      expect(f.c.aiSharingConsented, isFalse);
      await tester.pumpWidget(const SizedBox());
      f.close();
    },
  );

  testWidgets(
    'resume hides an expired feature view before the network check finishes',
    (tester) async {
      final f = AccessFixture();
      f.expiry = f.now.add(const Duration(seconds: 3)).toIso8601String();
      await f.start();
      addTearDown(f.close);
      await tester.pumpWidget(MaterialApp(home: EshaHome(controller: f.c)));
      expect(find.byType(IndexedStack), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      f.now = f.now.add(const Duration(seconds: 4));
      final delayed = Completer<http.Response>();
      f.nextStatus = delayed;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byType(IndexedStack), findsNothing);
      expect(find.text('Checking your Esha membership…'), findsOneWidget);
      delayed.complete(f.reply({'error': 'Unavailable'}, 503));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Connect to verify your Esha membership'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      f.close();
    },
  );

  testWidgets(
    'an open saved edit remains hidden after a different member signs in',
    (tester) async {
      final f = AccessFixture();
      await f.start();
      addTearDown(f.close);
      expect(f.c.saveRoutine(), isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VanityScreen(
              controller: f.c,
              onDiscover: () {},
              onConsult: () {},
              onStudio: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edits (1)'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open saved edit'));
      await tester.tap(find.text('Open saved edit'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This is the exact saved selection.'),
        findsOneWidget,
      );
      f.account = accountB;
      await f.c.signIn('other@example.test', 'not-a-real-password');
      await f.c.purchases.refresh();
      await tester.pumpAndSettle();
      expect(f.c.hasAppAccess, isTrue);
      expect(
        find.textContaining('This is the exact saved selection.'),
        findsNothing,
      );
      expect(
        find.textContaining('different signed-in account'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      f.close();
    },
  );
}
