import 'dart:convert';
import 'dart:io';

import 'package:esha_by_korlix/app_controller.dart';
import 'package:esha_by_korlix/models.dart';
import 'package:esha_by_korlix/services/korlix_api.dart';
import 'package:esha_by_korlix/services/purchases.dart';
import 'package:esha_by_korlix/services/vanity_sync.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

// Guest layout tests do not contact native stores. Constructing the real
// singleton starts a billing channel even when the fixture platform is disabled.
class NoNativeStore implements InAppPurchase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryStore implements StringStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

Catalog fixtureCatalog() => Catalog.fromJson(
  object(jsonDecode(File('assets/catalog.json').readAsStringSync())),
);
ServiceConfig fixtureConfig() => ServiceConfig.fromJson({
  'apiOrigin': 'https://chee-chai-chee-backend.onrender.com',
  'supabaseUrl': 'https://uxtjzjbwtppjvnsoiijv.supabase.co',
  'supabasePublishableKey': 'sb_publishable_test_only',
});

Future<EshaController> guestController() async {
  final local = MemoryStore();
  final api = KorlixApi(
    config: fixtureConfig(),
    secureStorage: MemoryStore(),
    localStorage: local,
    platform: 'unsupported',
    client: MockClient((_) async => http.Response('{}', 503)),
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

const accountA = '11111111-1111-4111-8111-111111111111';
const accountB = '22222222-2222-4222-8222-222222222222';
Json authPayload(String userId) => {
  'user': {'id': userId, 'email': '$userId@example.test'},
  'session': {
    'access_token': 'test-token-$userId',
    'refresh_token': 'test-refresh-$userId',
    'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  },
};
