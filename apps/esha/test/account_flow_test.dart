import 'dart:async';
import 'dart:convert';

import 'package:esha_by_korlix/app_controller.dart';
import 'package:esha_by_korlix/models.dart';
import 'package:esha_by_korlix/services/korlix_api.dart';
import 'package:esha_by_korlix/services/purchases.dart';
import 'package:esha_by_korlix/services/vanity_sync.dart';
import 'package:esha_by_korlix/ui/account.dart';
import 'package:esha_by_korlix/ui/brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'fixtures.dart';

class NoStore implements InAppPurchase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

http.Response response(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

KorlixApi apiWith(
  Future<http.Response> Function(http.Request) send, {
  MemoryStore? secure,
  MemoryStore? local,
}) => KorlixApi(
  config: fixtureConfig(),
  secureStorage: secure ?? MemoryStore(),
  localStorage: local ?? MemoryStore(),
  platform: 'unsupported',
  client: MockClient(send),
);

Future<AuthSession?> createAccount(
  KorlixApi api, {
  String ageBand = '18_plus',
  bool parentPermission = false,
  bool termsAccepted = true,
}) => api.signUp(
  ' New@example.test ',
  'safe-test-password',
  ageBand: ageBand,
  termsAccepted: termsAccepted,
  privacyAcknowledged: true,
  parentPermission: parentPermission,
);

Future<EshaController> controllerWith(KorlixApi api) async {
  final sync = VanitySync(gateway: api, storage: api.localStorage);
  await sync.attach(null);
  return EshaController(
    catalog: fixtureCatalog(),
    api: api,
    sync: sync,
    purchases: EshaPurchases(api, store: NoStore()),
  )..initializing = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pending email confirmation does not create a signed-in session or membership', () async {
    http.Request? sent;
    final secure = MemoryStore(), local = MemoryStore();
    final api = apiWith(
      (request) async {
        sent = request;
        return response({
          'success': true,
          'user': {'id': accountA},
          'session': null,
        });
      },
      secure: secure,
      local: local,
    );
    addTearDown(api.dispose);

    expect(await createAccount(api), isNull);
    expect(api.session, isNull);
    expect(secure.values.containsKey(KorlixApi.sessionKey), isFalse);
    final body = object(jsonDecode(sent!.body));
    expect(sent!.url.path, '/api/auth/signup');
    expect(body['email'], 'new@example.test');
    expect(body['client_app'], 'esha_by_korlix');
    expect(sent!.headers['X-Korlix-App'], 'esha_by_korlix');
    expect(body['signup_eligibility'], {
      'age_band': '18_plus',
      'terms_accepted': true,
      'privacy_acknowledged': true,
      'parent_permission': false,
      'policy_version': '2026-10-06',
    });
    expect(body['signup_plan'], 'basic');
    expect(
      local.values.values.any((value) => value.contains('password')),
      isFalse,
    );
  });

  test(
    'signup enforces age and declarations before contacting the service',
    () async {
      var requests = 0;
      final api = apiWith((_) async {
        requests++;
        return response({'success': true, 'session': null});
      });
      addTearDown(api.dispose);
      await expectLater(
        createAccount(api, ageBand: ''),
        throwsA(isA<EshaException>()),
      );
      await expectLater(
        createAccount(api, ageBand: 'under_16'),
        throwsA(isA<EshaException>()),
      );
      await expectLater(
        createAccount(api, ageBand: '16_17'),
        throwsA(isA<EshaException>()),
      );
      await expectLater(
        createAccount(api, termsAccepted: false),
        throwsA(isA<EshaException>()),
      );
      expect(requests, 0);
      expect(
        await createAccount(api, ageBand: '16_17', parentPermission: true),
        isNull,
      );
      expect(requests, 1);
    },
  );

  test('complete signup sessions use secure storage and attach the new account collection', () async {
    final secure = MemoryStore(), local = MemoryStore();
    final api = apiWith(
      (request) async {
        if (request.url.path == '/api/auth/signup') {
          return response({'success': true, ...authPayload(accountA)});
        }
        if (request.url.path.contains('/rest/v1/')) return response([]);
        return response({});
      },
      secure: secure,
      local: local,
    );
    final controller = await controllerWith(api);
    addTearDown(controller.dispose);
    final outcome = await controller.signUp(
      'new@example.test',
      'test-password',
      ageBand: '18_plus',
      termsAccepted: true,
      privacyAcknowledged: true,
      parentPermission: false,
    );
    expect(outcome, SignupOutcome.signedIn);
    expect(controller.session!.userId, accountA);
    expect(
      jsonDecode(secure.values[KorlixApi.sessionKey]!)['user']['id'],
      accountA,
    );
    expect(
      local.values.values.any((value) => value.contains('test-refresh')),
      isFalse,
    );
    expect(controller.authBusy, isFalse);
  });

  test(
    'a late signup response cannot sign in after the user signs out',
    () async {
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final api = apiWith((_) {
        started.complete();
        return pending.future;
      });
      addTearDown(api.dispose);
      final creation = createAccount(api);
      final rejection = expectLater(
        creation,
        throwsA(
          isA<EshaException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      await started.future;
      await api.signOut();
      pending.complete(response({'success': true, ...authPayload(accountA)}));
      await rejection;
      expect(api.session, isNull);
      expect(await api.secureStorage.read(KorlixApi.sessionKey), isNull);
    },
  );

  test(
    'malformed successful signup cannot be mistaken for confirmation pending',
    () async {
      final api = apiWith((_) async => response({}));
      addTearDown(api.dispose);
      await expectLater(
        createAccount(api),
        throwsA(
          isA<EshaException>().having(
            (e) => e.code,
            'code',
            'SIGNUP_UNCONFIRMED',
          ),
        ),
      );
      expect(api.session, isNull);
    },
  );

  test('password reset uses only the supplied mailbox and does not change a session', () async {
    final requests = <http.Request>[];
    final api = apiWith((request) async {
      requests.add(request);
      if (request.url.path == '/api/auth/signin') {
        return response(authPayload(accountA));
      }
      return response({'success': true});
    });
    addTearDown(api.dispose);
    await api.signIn('person@example.test', 'test-password');
    final originalSession = api.session;
    await api.requestPasswordReset(' Person@example.test ');
    final reset = requests.last;
    expect(reset.url.path, '/api/auth/password-reset');
    expect(jsonDecode(reset.body), {'email': 'person@example.test'});
    expect(reset.headers.containsKey('Authorization'), isFalse);
    expect(identical(api.session, originalSession), isTrue);
    await expectLater(
      api.requestPasswordReset('invalid'),
      throwsA(isA<EshaException>()),
    );
    expect(requests.length, 2);
  });

  testWidgets('new-user signup remains signed out until email is confirmed', (
    tester,
  ) async {
    final api = apiWith(
      (request) async => response({
        'success': true,
        'user': {'id': accountA},
        'session': null,
      }),
    );
    final controller = await controllerWith(api);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: eshaTheme,
        home: AccountScreen(controller: controller),
      ),
    );
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'new@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'test-password',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-confirm-password')),
      'test-password',
    );
    await tester.ensureVisible(find.text('18 or older'));
    await tester.tap(find.text('18 or older'));
    await tester.ensureVisible(find.text('I agree to the Terms of Use.'));
    await tester.tap(find.text('I agree to the Terms of Use.'));
    await tester.ensureVisible(find.text('I have read the Privacy Policy.'));
    await tester.tap(find.text('I have read the Privacy Policy.'));
    await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();
    expect(controller.session, isNull);
    expect(find.textContaining('Check your email to confirm'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-confirm-password')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('auth-password')))
          .controller!
          .text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('signup and recovery fit a small display with enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await controllerWith(
      apiWith((_) async => response({}, 503)),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: eshaTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.7)),
          child: child!,
        ),
        home: AccountScreen(controller: controller),
      ),
    );
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('16–17'));
    await tester.tap(find.text('16–17'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-password')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
