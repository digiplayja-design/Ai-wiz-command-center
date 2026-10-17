import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_wiz_command_center/analytics/korlix_onboarding.dart';

const headers = {
  'X-Korlix-Device-Id': 'korlix_123456789_12345',
  'X-Korlix-Platform': 'android',
};
Future<void> settleQueue() async {
  // SharedPreferences and the injected HTTP client finish on the real event loop.
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'opening an existing installation is not classified as a fresh setup',
    () async {
      final sent = <Map<String, dynamic>>[];
      final telemetry = KorlixOnboarding(
        client: MockClient((request) async {
          sent.addAll(
            (jsonDecode(request.body)['events'] as List)
                .cast<Map<String, dynamic>>(),
          );
          return http.Response('{}', 202);
        }),
      );
      addTearDown(telemetry.dispose);
      await telemetry.start(
        baseUrl: 'https://example.test',
        context: () async =>
            const KorlixOnboardingContext(headers, newSetup: false),
      );
      await settleQueue();
      expect(sent.single['name'], 'app_open');
      expect(sent.single['new_setup'], isFalse);
      expect(sent.single.containsKey('queued_at'), isFalse);
    },
  );

  test('offline events survive a restart with the same IDs, without blocking startup', () async {
    final offline = KorlixOnboarding(
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    await offline.start(
      baseUrl: 'https://example.test',
      context: () async =>
          const KorlixOnboardingContext(headers, newSetup: true),
    );
    offline.track('registration_submit');
    await settleQueue();
    final prefs = await SharedPreferences.getInstance();
    final pending =
        jsonDecode(prefs.getString(KorlixOnboarding.queueKey)!) as List;
    expect(pending.length, 2);
    offline.dispose();
    final sent = <Map<String, dynamic>>[];
    final online = KorlixOnboarding(
      client: MockClient((request) async {
        sent.addAll(
          (jsonDecode(request.body)['events'] as List)
              .cast<Map<String, dynamic>>(),
        );
        return http.Response('{}', 202);
      }),
    );
    addTearDown(online.dispose);
    await online.start(
      baseUrl: 'https://example.test',
      context: () async =>
          const KorlixOnboardingContext(headers, newSetup: false),
    );
    await settleQueue();
    expect(sent.map((e) => e['id']), containsAll(pending.map((e) => e['id'])));
    expect(sent.where((e) => e['new_setup'] == true).length, 1);
    expect(jsonDecode(prefs.getString(KorlixOnboarding.queueKey)!), isEmpty);
  });

  test(
    'unapproved names and free-text error details never leave the app',
    () async {
      final sent = <Map<String, dynamic>>[];
      final telemetry = KorlixOnboarding(
        client: MockClient((request) async {
          sent.addAll(
            (jsonDecode(request.body)['events'] as List)
                .cast<Map<String, dynamic>>(),
          );
          return http.Response('{}', 202);
        }),
      );
      addTearDown(telemetry.dispose);
      await telemetry.start(
        baseUrl: 'https://example.test',
        context: () async =>
            const KorlixOnboardingContext(headers, newSetup: true),
      );
      telemetry.track('sign_in_succeeded');
      telemetry.track(
        'registration_validation_error',
        errorCode: 'secret@example.test',
      );
      telemetry.track(
        'registration_validation_error',
        errorCode: 'required_fields',
      );
      await settleQueue();
      expect(sent.map((e) => e['name']), [
        'app_open',
        'registration_validation_error',
      ]);
      expect(jsonEncode(sent), isNot(contains('secret@example.test')));
    },
  );
}
