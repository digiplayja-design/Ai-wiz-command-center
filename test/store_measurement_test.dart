import 'dart:convert';

import 'package:ai_wiz_command_center/billing/store_measurement.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('korlix/store_measurement');
  const checkout = 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
  const owner = 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
  const other = 'cccccccc-cccc-4ccc-cccc-cccccccccccc';
  const instance = '11112222333344445555666677778888';
  late List<http.Request> requests;
  late List<String> nativeCalls;
  late StoreMeasurement measurement;
  late bool permission, online;

  Future<void> account(String id) => measurement.selectAccount(
    id,
    'ios',
    'https://billing.example',
    () => {'Authorization': 'Bearer fixture-$id'},
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests = [];
    nativeCalls = [];
    permission = true;
    online = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call.method);
          return permission && call.method != 'disable' ? instance : null;
        });
    measurement = StoreMeasurement(
      MockClient((request) async {
        requests.add(request);
        if (!online) return http.Response('{}', 503);
        return http.Response(jsonEncode({'checkoutId': checkout}), 200);
      }),
    );
  });
  tearDown(() {
    measurement.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('default and declined users do not enroll; an unavailable sender leaves checkout available', () async {
    await account(owner);
    await measurement.begin('sku');
    expect(requests, isEmpty);
    permission = false;
    await measurement.choose(true);
    expect(measurement.enabled, isFalse);
    await measurement.begin('sku');
    expect(requests, isEmpty);
    permission = true;
    await measurement.choose(true);
    online = false;
    await measurement.begin('sku');
    expect(await measurement.checkoutFor('sku'), isNull);
  });

  test('consent is bound to a real installation, the account, and the purchased SKU', () async {
    await account(owner);
    await measurement.choose(true);
    await measurement.begin('sku');
    expect(jsonDecode(requests.single.body), {
      'store': 'ios',
      'sku': 'sku',
      'consent': true,
      'instanceId': instance,
    });
    expect(await measurement.checkoutFor('sku'), checkout);
    expect(await measurement.checkoutFor('different'), isNull);
    await account(other);
    expect(measurement.enabled, isFalse);
    expect(await measurement.checkoutFor('sku'), isNull);
    await account(owner);
    expect(await measurement.checkoutFor('sku'), checkout);
    await measurement.bound('sku', checkout);
    expect(await measurement.checkoutFor('sku'), isNull);
  });

  test('an offline withdrawal disables native collection and is retried on reconnect', () async {
    await account(owner);
    await measurement.choose(true);
    await measurement.begin('sku');
    online = false;
    await measurement.choose(false);
    expect(measurement.enabled, isFalse);
    expect(nativeCalls.last, 'disable');
    expect(await measurement.checkoutFor('sku'), isNull);
    expect(measurement.feedback, isNotNull);
    online = true;
    await measurement.refresh();
    expect(requests.last.url.path, endsWith('/withdraw'));
    expect(measurement.feedback, isNull);
  });
}
