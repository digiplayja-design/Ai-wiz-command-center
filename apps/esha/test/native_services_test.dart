import 'dart:async';
import 'dart:convert';

import 'package:esha_by_korlix/models.dart';
import 'package:esha_by_korlix/services/korlix_api.dart';
import 'package:esha_by_korlix/services/purchases.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'fixtures.dart';

Future<void> settle() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

http.Response jsonReply(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

class TestStore implements InAppPurchase {
  final changes = StreamController<List<PurchaseDetails>>.broadcast();
  int completed = 0;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => changes.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('device identity is stable and late authenticated responses cannot cross accounts', () async {
    final delayed = Completer<http.Response>();
    final secure = MemoryStore(), local = MemoryStore();
    final requests = <http.Request>[];
    var account = accountA;
    final api = KorlixApi(
      config: fixtureConfig(),
      secureStorage: secure,
      localStorage: local,
      platform: 'android',
      client: MockClient((r) async {
        requests.add(r);
        if (r.url.path == '/api/auth/signin') {
          return jsonReply(authPayload(account));
        }
        if (r.url.path.contains('/rest/v1/')) return delayed.future;
        return jsonReply({'success': true});
      }),
    );
    await api.signIn('person@example.test', 'not-a-real-password');
    final oldOwner = api.owner();
    final pending = api.loadVanity();
    final rejection = expectLater(
      pending,
      throwsA(
        isA<EshaException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    await settle();
    await api.signOut();
    account = accountB;
    await api.signIn('other@example.test', 'not-a-real-password');
    delayed.complete(
      jsonReply([
        {
          'state': Vanity(favorites: ['private-A']).toJson(),
          'version': 1,
        },
      ]),
    );
    await rejection;
    expect(api.isOwner(oldOwner), isFalse);
    expect(api.session!.userId, accountB);
    expect(
      jsonDecode(secure.values[KorlixApi.sessionKey]!)['user']['id'],
      accountB,
    );
    final signins = requests
        .where((r) => r.url.path == '/api/auth/signin')
        .toList();
    final firstDevice = jsonDecode(signins.first.body)['device_id'];
    expect(jsonDecode(signins.last.body)['device_id'], firstDevice);
    expect(signins.first.headers['X-Korlix-Device-Id'], firstDevice);
    expect(signins.first.headers['X-Korlix-Platform'], 'android');
    expect(local.values.values.any((v) => v.contains('test-refresh')), isFalse);
    api.dispose();
  });

  test('cloud writes use conditional version filters and reject empty mutation results', () async {
    http.Request? mutation;
    final api = KorlixApi(
      config: fixtureConfig(),
      secureStorage: MemoryStore(),
      localStorage: MemoryStore(),
      platform: 'ios',
      client: MockClient((r) async {
        if (r.url.path == '/api/auth/signin') {
          return jsonReply(authPayload(accountA));
        }
        mutation = r;
        return jsonReply([]);
      }),
    );
    await api.signIn('person@example.test', 'not-real');
    await expectLater(
      api.saveVanity(Vanity(favorites: ['a']), 7),
      throwsA(isA<EshaException>().having((e) => e.code, 'code', 'CONFLICT')),
    );
    expect(mutation!.method, 'PATCH');
    expect(mutation!.url.queryParameters['user_id'], 'eq.$accountA');
    expect(mutation!.url.queryParameters['version'], 'eq.7');
    expect(object(jsonDecode(mutation!.body)).keys, ['state']);
    expect(mutation!.headers['Prefer'], 'return=representation');
    api.dispose();
  });

  test('a malformed cloud read is an error, never an empty account', () async {
    final api = KorlixApi(
      config: fixtureConfig(),
      secureStorage: MemoryStore(),
      localStorage: MemoryStore(),
      platform: 'ios',
      client: MockClient(
        (r) async => r.url.path == '/api/auth/signin'
            ? jsonReply(authPayload(accountA))
            : jsonReply({'unexpected': 'object'}),
      ),
    );
    await api.signIn('person@example.test', 'not-real');
    await expectLater(
      api.loadVanity(),
      throwsA(
        isA<EshaException>().having((e) => e.code, 'code', 'LOAD_UNCONFIRMED'),
      ),
    );
    api.dispose();
  });

  test(
    'purchase completion requires backend verification and the same account',
    () async {
      final response = Completer<http.Response>();
      final store = TestStore();
      Json? sent;
      var user = accountA;
      final api = KorlixApi(
        config: fixtureConfig(),
        secureStorage: MemoryStore(),
        localStorage: MemoryStore(),
        platform: 'android',
        client: MockClient((r) async {
          if (r.url.path == '/api/auth/signin') {
            return jsonReply(authPayload(user));
          }
          if (r.url.path == '/api/esha/billing/verify') {
            sent = object(jsonDecode(r.body));
            // A later automatic retry under B must model the server's actual
            // receipt ownership check, not reuse A's successful response.
            if (r.headers['Authorization'] != 'Bearer test-token-$accountA') {
              return jsonReply({
                'error': 'This purchase belongs to another Korlix account.',
                'code': 'purchase_ownership_mismatch',
              }, 409);
            }
            return response.future;
          }
          return jsonReply({
            'purchasesEnabled': false,
            'storeConfigurationVerified': false,
            'membership': {'active': false},
            'allowance': {'configured': false},
          });
        }),
      );
      await api.signIn('a@example.test', 'not-real');
      final billing = EshaPurchases(api, store: store);
      await billing.initialize();
      final purchase = PurchaseDetails(
        purchaseID: 'test-purchase',
        productID: 'esha_monthly',
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: 'test-google-purchase-token',
          source: 'google_play',
        ),
        transactionDate: '0',
        status: PurchaseStatus.purchased,
      )..pendingCompletePurchase = true;
      store.changes.add([purchase]);
      await settle();
      expect(sent, {
        'provider': 'google',
        'productId': 'esha_monthly',
        'purchaseToken': 'test-google-purchase-token',
      });
      expect(store.completed, 0);
      await api.signOut();
      user = accountB;
      await api.signIn('b@example.test', 'not-real');
      billing.accountChanged();
      response.complete(
        jsonReply({
          'verified': true,
          'completePurchase': true,
          'active': true,
          'status': {
            'membership': {'active': true, 'verificationFresh': true},
          },
        }),
      );
      await settle();
      expect(store.completed, 0);
      expect(billing.membership.active, isFalse);
      billing.dispose();
      await store.changes.close();
      api.dispose();
    },
  );

  test(
    'completion flags are strict and never derive from local purchase state',
    () {
      expect(
        mayCompleteVerifiedPurchase({
          'verified': true,
          'completePurchase': true,
        }, sameAccount: true),
        isTrue,
      );
      for (final response in <Json>[
        {},
        {'active': true},
        {'verified': true},
        {'completePurchase': true},
        {'verified': 'true', 'completePurchase': true},
        {'verified': true, 'completePurchase': false},
      ]) {
        expect(
          mayCompleteVerifiedPurchase(response, sameAccount: true),
          isFalse,
        );
      }
      expect(
        mayCompleteVerifiedPurchase({
          'verified': true,
          'completePurchase': true,
        }, sameAccount: false),
        isFalse,
      );
      expect(
        MembershipStatus.fromJson({
          'membership': {'active': true, 'verificationFresh': false},
          'consultationEnabled': true,
          'allowance': {'limit': 10, 'remaining': 10},
        }).canConsult,
        isFalse,
      );
    },
  );
}
