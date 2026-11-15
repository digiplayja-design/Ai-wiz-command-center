import 'dart:async';
import 'dart:convert';

import 'package:esha_by_korlix/app_controller.dart';
import 'package:esha_by_korlix/models.dart';
import 'package:esha_by_korlix/services/korlix_api.dart';
import 'package:esha_by_korlix/services/purchases.dart';
import 'package:esha_by_korlix/services/vanity_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

http.Response _response(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Future<EshaController> _controller(
  Future<http.Response> Function(http.Request) send,
) async {
  final local = MemoryStore();
  final api = KorlixApi(
    config: fixtureConfig(),
    secureStorage: MemoryStore(),
    localStorage: local,
    platform: 'unsupported',
    client: MockClient(send),
  );
  final sync = VanitySync(gateway: api, storage: local);
  await sync.attach(null);
  return EshaController(
    catalog: fixtureCatalog(),
    api: api,
    sync: sync,
    purchases: EshaPurchases(api, store: NoNativeStore()),
  )..initializing = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final signup in [false, true]) {
    test(
      '${signup ? 'signup' : 'signin'} invalidated during collection loading releases auth controls',
      () async {
        final vanityStarted = Completer<void>();
        final vanityResponse = Completer<http.Response>();
        var vanityRequests = 0;
        final controller = await _controller((request) async {
          switch (request.url.path) {
            case '/api/auth/signin':
            case '/api/auth/signup':
              return _response({'success': true, ...authPayload(accountA)});
            case '/api/auth/refresh':
              return _response({'error': 'Session expired'}, 401);
            case '/rest/v1/korlix_esha_vanity':
              if (vanityRequests++ == 0) {
                vanityStarted.complete();
                return vanityResponse.future;
              }
              return _response([]);
            default:
              return _response({});
          }
        });
        addTearDown(controller.dispose);

        final Future<Object?> authentication = signup
            ? controller.signUp(
                'member@example.test',
                'not-a-real-password',
                ageBand: '18_plus',
                termsAccepted: true,
                privacyAcknowledged: true,
                parentPermission: false,
              )
            : controller.signIn('member@example.test', 'not-a-real-password');
        await vanityStarted.future;
        expect(controller.authBusy, isTrue);
        expect(controller.session?.userId, accountA);

        // Exercise the real refresh-401 callback during post-authentication
        // account loading, rather than invoking the callback directly.
        vanityResponse.complete(_response({'error': 'Unauthorized'}, 401));
        expect(await authentication, signup ? isNull : isFalse);
        expect(controller.session, isNull);
        expect(controller.authBusy, isFalse);
        expect(
          await controller.signIn('member@example.test', 'not-a-real-password'),
          isTrue,
        );
      },
    );
  }

  test(
    'signout releases auth controls while an older signin is pending',
    () async {
      final authStarted = Completer<void>();
      final authResponse = Completer<http.Response>();
      final controller = await _controller((request) async {
        if (request.url.path == '/api/auth/signin') {
          authStarted.complete();
          return authResponse.future;
        }
        return _response({});
      });
      final oldLogin = controller.signIn(
        'member@example.test',
        'not-a-real-password',
      );
      try {
        await authStarted.future;
        expect(controller.authBusy, isTrue);
        await controller.signOut();
        expect(controller.session, isNull);
        expect(controller.authBusy, isFalse);
        authResponse.complete(_response(authPayload(accountA)));
        expect(await oldLogin, isFalse);
        expect(controller.session, isNull);
        expect(controller.authBusy, isFalse);
      } finally {
        if (!authResponse.isCompleted) {
          authResponse.complete(_response(authPayload(accountA)));
        }
        await oldLogin;
        controller.dispose();
      }
    },
  );

  test(
    'an invalidated login finishing late cannot release a newer login',
    () async {
      final oldVanityStarted = Completer<void>();
      final oldVanityResponse = Completer<http.Response>();
      final newAuthStarted = Completer<void>();
      final newAuthResponse = Completer<http.Response>();
      var authRequests = 0, vanityRequests = 0;
      var invalidateMembershipRequest = false;
      final controller = await _controller((request) async {
        switch (request.url.path) {
          case '/api/auth/signin':
            if (authRequests++ == 0) return _response(authPayload(accountA));
            newAuthStarted.complete();
            return newAuthResponse.future;
          case '/api/esha/billing/status':
            if (invalidateMembershipRequest) {
              return _response({'error': 'Unauthorized'}, 401);
            }
            return _response({});
          case '/api/auth/refresh':
            return _response({'error': 'Session expired'}, 401);
          case '/rest/v1/korlix_esha_vanity':
            if (vanityRequests++ == 0) {
              oldVanityStarted.complete();
              return oldVanityResponse.future;
            }
            return _response([]);
          default:
            return _response({});
        }
      });
      final oldLogin = controller.signIn(
        'first@example.test',
        'not-a-real-password',
      );
      Future<bool>? newLogin;
      try {
        await oldVanityStarted.future;
        invalidateMembershipRequest = true;
        await expectLater(
          controller.api.billingStatus(),
          throwsA(isA<EshaException>()),
        );
        invalidateMembershipRequest = false;
        expect(controller.session, isNull);
        expect(controller.authBusy, isFalse);

        newLogin = controller.signIn(
          'second@example.test',
          'not-a-real-password',
        );
        await newAuthStarted.future;
        final newAccountEpoch = controller.accountEpoch;
        expect(controller.authBusy, isTrue);

        oldVanityResponse.complete(_response([]));
        expect(await oldLogin, isFalse);
        expect(controller.accountEpoch, newAccountEpoch);
        expect(controller.authBusy, isTrue);
        expect(controller.authError, isNull);
        expect(controller.session, isNull);

        newAuthResponse.complete(_response(authPayload(accountB)));
        expect(await newLogin, isTrue);
        expect(controller.session?.userId, accountB);
        expect(controller.authBusy, isFalse);
      } finally {
        if (!oldVanityResponse.isCompleted) {
          oldVanityResponse.complete(_response([]));
        }
        if (!newAuthResponse.isCompleted) {
          newAuthResponse.complete(_response(authPayload(accountB)));
        }
        await oldLogin;
        if (newLogin != null) await newLogin;
        controller.dispose();
      }
    },
  );
}
