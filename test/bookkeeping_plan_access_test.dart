import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_client.dart';

void main() {
  test(
    'Enterprise upgrade preserves the session for free personal Tax Prep',
    () async {
      var accessDenied = false;
      final client = BookkeepingClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {'Authorization': 'Bearer fixture'},
        client: MockClient((request) async {
          if (request.url.path.endsWith('/businesses')) {
            return http.Response(
              jsonEncode({
                'error': 'Bookkeeping is available with Enterprise. Your saved records are retained.',
                'code': 'BOOKKEEPING_ENTERPRISE_REQUIRED',
                'requiredTier': 'enterprise',
                'upgradeRequired': true,
              }),
              402,
            );
          }
          return http.Response('{"workspaces":[],"businesses":[]}', 200);
        }),
      );
      addTearDown(client.dispose);
      client.onAccessDenied = () => accessDenied = true;
      await expectLater(
        client.request('GET', '/businesses'),
        throwsA(
          isA<BookkeepingException>()
              .having((e) => e.status, 'status', 402)
              .having((e) => e.message, 'message', contains('Enterprise')),
        ),
      );
      expect(accessDenied, false);
      expect(client.sessionChanged, false);
      expect(await client.request('GET', '/tax-prep'), {
        'workspaces': <dynamic>[],
        'businesses': <dynamic>[],
      });
    },
  );
}
