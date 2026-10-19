import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_wiz_command_center/auth/korlix_email_confirmation.dart';

const verified = KorlixConfirmedSession(
  accessToken: 'server-validated-access',
  refreshToken: 'rotated-refresh',
  email: 'member@example.test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Uri> callback({String type = 'signup', String? fragment}) async {
    final state = await KorlixEmailConfirmation.begin(' Member@Example.Test ');
    return Uri.parse(
      '$korlixConfirmationScheme://auth/confirm/$state#${fragment ?? 'type=$type&access_token=incoming-access&refresh_token=incoming-refresh'}',
    );
  }

  test(
    'valid matching callback uses server session once and clears signup state',
    () async {
      final uri = await callback();
      final handler = KorlixEmailConfirmation();
      var exchanges = 0, accepted = 0;
      Future<KorlixConfirmedSession?> exchange(String token) async {
        exchanges++;
        expect(token, 'incoming-refresh');
        return verified;
      }

      Future<void> accept(KorlixConfirmedSession session) async {
        accepted++;
        expect(session.accessToken, 'server-validated-access');
      }

      await handler.complete(
        uri,
        exchange: exchange,
        accept: accept,
        canAccept: () => true,
      );
      await handler.complete(
        uri,
        exchange: exchange,
        accept: accept,
        canAccept: () => true,
      );
      expect(exchanges, 1);
      expect(accepted, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(KorlixEmailConfirmation.pendingKey), isNull);
      expect(
        prefs.getKeys(),
        isEmpty,
        reason: 'Callback credentials never enter preferences',
      );
    },
  );

  test(
    'foreign URLs, wrong state, and recovery links cannot exchange credentials',
    () async {
      final good = await callback();
      final wrongState = '0' * 64;
      var calls = 0;
      for (final uri in [
        good.replace(scheme: 'https'),
        good.replace(host: 'evil.test'),
        good.replace(path: '/confirm/$wrongState'),
        good.replace(query: 'next=evil'),
        good.replace(fragment: 'type=recovery&access_token=x&refresh_token=y'),
      ]) {
        await KorlixEmailConfirmation().complete(
          uri,
          exchange: (_) async {
            calls++;
            return verified;
          },
          accept: (_) async {
            calls++;
          },
          canAccept: () => true,
        );
      }
      expect(calls, 0);
    },
  );

  test(
    'server rejection and account mismatch cannot create an app session',
    () async {
      final uri = await callback();
      for (final result in [
        null,
        const KorlixConfirmedSession(
          accessToken: 'server-access',
          refreshToken: 'server-refresh',
          email: 'different@example.test',
        ),
      ]) {
        var accepted = false;
        await expectLater(
          KorlixEmailConfirmation().complete(
            uri,
            exchange: (_) async => result,
            accept: (_) async {
              accepted = true;
            },
            canAccept: () => true,
          ),
          throwsA(isA<KorlixConfirmationException>()),
        );
        expect(accepted, isFalse);
      }
    },
  );

  test(
    'expired provider link reports a fixed message without sending tokens',
    () async {
      final uri = await callback(
        fragment: 'error=access_denied&error_description=secret-token',
      );
      await expectLater(
        KorlixEmailConfirmation().complete(
          uri,
          exchange: (_) async {
            fail('Must not exchange an error URL');
          },
          accept: (_) async {
            fail('Must not sign in');
          },
          canAccept: () => true,
        ),
        throwsA(
          isA<KorlixConfirmationException>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('secret-token')),
          ),
        ),
      );
    },
  );

  test(
    'late exchange does not replace an account signed in during the request',
    () async {
      final uri = await callback();
      var allowed = true, accepted = false;
      final result = Completer<KorlixConfirmedSession?>();
      final started = Completer<void>();
      final future = KorlixEmailConfirmation().complete(
        uri,
        exchange: (_) {
          started.complete();
          return result.future;
        },
        accept: (_) async {
          accepted = true;
        },
        canAccept: () => allowed,
      );
      await started.future;
      allowed = false;
      result.complete(verified);
      await future;
      expect(accepted, isFalse);
    },
  );

  test('a stale pending signup cannot reuse a confirmation', () async {
    final uri = await callback();
    final prefs = await SharedPreferences.getInstance();
    final pending = jsonDecode(
      prefs.getString(KorlixEmailConfirmation.pendingKey)!,
    ) as Map<String, dynamic>;
    pending['created_at'] = '2000-01-01T00:00:00Z';
    await prefs.setString(
      KorlixEmailConfirmation.pendingKey,
      jsonEncode(pending),
    );
    await expectLater(
      KorlixEmailConfirmation().complete(
        uri,
        exchange: (_) async {
          fail('Stale signup must not exchange tokens');
        },
        accept: (_) async {
          fail('Must not sign in');
        },
        canAccept: () => true,
      ),
      throwsA(isA<KorlixConfirmationException>()),
    );
  });
}
