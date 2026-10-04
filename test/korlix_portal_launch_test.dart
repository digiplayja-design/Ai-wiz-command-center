import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/auth/korlix_portal_launch.dart';

void main() {
  const id = '12345678-1234-4234-8234-123456789abc';
  const code = 'aBcdEF_1234567890-abcdefghijklmNOPQRSTuvwxYZ12';
  test('captures fragment invitation and clears credentials before sign-in', () {
    final uri = Uri.parse(
      'https://www.korlixdeveloper.com/app/?app_portal=$id&renderer=canvaskit#invite=$code',
    );
    final launch = KorlixPortalLaunch.parse(uri)!;
    expect(launch.portalId, id);
    expect(launch.inviteToken, code);
    final clean = KorlixPortalLaunch.withoutCredentials(uri);
    expect(clean.queryParameters, {'renderer': 'canvaskit'});
    expect(clean.fragment, isEmpty);
    expect(clean.host, uri.host);
    expect(clean.path, uri.path);
  });
  test(
    'public portal link has no invitation and legacy query code is removed',
    () {
      expect(
        KorlixPortalLaunch.parse(
          Uri.parse('https://example.com/app/?app_portal=$id'),
        )!.inviteToken,
        isNull,
      );
      final uri = Uri.parse(
        'https://example.com/app/?app_portal=$id&invite=$code',
      );
      expect(KorlixPortalLaunch.parse(uri)!.inviteToken, code);
      expect(
        KorlixPortalLaunch.withoutCredentials(uri).queryParameters,
        isEmpty,
      );
    },
  );
  test('rejects malformed or ambiguous destinations and codes', () {
    for (final query in [
      'app_portal=https://attacker.example',
      'app_portal=$id&app_portal=$id',
      'app_portal=$id&invite=short',
      'app_portal=$id&invite=$code#invite=$code',
      'app_portal=$id#invite=$code&invite=$code',
      'app_portal=$id#invite=https://attacker.example',
    ]) {
      expect(
        KorlixPortalLaunch.parse(Uri.parse('https://example.com/app/?$query')),
        isNull,
        reason: query,
      );
    }
  });
  test('does not consume unrelated authentication fragments or routes', () {
    final uri = Uri.parse(
      'https://example.com/app/?renderer=html#access_token=example',
    );
    expect(KorlixPortalLaunch.parse(uri), isNull);
    expect(KorlixPortalLaunch.withoutCredentials(uri), uri);
    final portal = Uri.parse(
      'https://example.com/app/?app_portal=$id#access_token=example',
    );
    expect(
      KorlixPortalLaunch.withoutCredentials(portal).fragment,
      'access_token=example',
    );
  });
}
