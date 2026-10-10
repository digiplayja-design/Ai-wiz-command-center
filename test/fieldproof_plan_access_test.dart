import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/fieldproof/fieldproof_client.dart';

void main() {
  test(
    'FieldProof upgrade requirement preserves sign-in and allows retry after upgrading',
    () async {
      var enterprise = false;
      var accessDenied = false;
      final client = FieldProofClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {'Authorization': 'Bearer fixture'},
        client: MockClient((request) async {
          expect(request.url.path, '/api/fieldproof');
          return enterprise
              ? http.Response('{"jobs":[]}', 200)
              : http.Response(
                  jsonEncode({
                    'error':
                        'FieldProof is available with Enterprise. Your saved records are retained.',
                    'code': 'fieldproof_enterprise_required',
                    'requiredTier': 'enterprise',
                    'upgradeRequired': true,
                  }),
                  402,
                );
        }),
      );
      addTearDown(client.dispose);
      client.onAccessDenied = () => accessDenied = true;
      await expectLater(
        client.load(),
        throwsA(
          isA<FieldProofException>()
              .having((e) => e.status, 'status', 402)
              .having((e) => e.message, 'message', contains('Enterprise')),
        ),
      );
      expect(accessDenied, false);
      expect(client.sessionChanged, false);
      enterprise = true;
      expect(await client.load(), {'jobs': <dynamic>[]});
    },
  );
}
