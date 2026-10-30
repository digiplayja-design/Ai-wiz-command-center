import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magic_camera/magic_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('standalone signup uses dedicated Magic account scope and basic shared account', () async {
    SharedPreferences.setMockInitialValues({});
    http.Request? seen;
    final auth = MagicAuthController(
      backendUrl: 'https://fixture.invalid',
      client: MockClient((r) async {
        seen = r;
        return http.Response('{}', 200);
      }),
    );
    await auth.authenticate(
      email: 'person@example.test',
      password: 'fixture-password',
      signup: true,
      ageBand: '18_plus',
      acceptedPolicies: true,
    );
    expect(seen!.url.path, '/api/magic-account/auth/signup');
    final body = jsonDecode(seen!.body) as Map;
    expect(body['client_app'], 'magic_camera');
    expect(body['signup_plan'], 'basic');
    expect(body.containsKey('gender'), false);
    auth.dispose();
  });
}
