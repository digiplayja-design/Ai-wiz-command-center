import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/auth/korlix_login_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'defaults to not remembering email and permits password-manager offer',
    () async {
      final choice = await KorlixLoginPreferences.load();
      expect(choice.rememberEmail, isFalse);
      expect(choice.email, isEmpty);
      expect(choice.offerPasswordSave, isTrue);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test('remembered email and password-manager choice survive reload', () async {
    expect(
      await const KorlixLoginPreferences(
        rememberEmail: true,
        email: ' person@example.com ',
        offerPasswordSave: false,
      ).save(),
      isTrue,
    );
    final restored = await KorlixLoginPreferences.load();
    expect(restored.rememberEmail, isTrue);
    expect(restored.email, 'person@example.com');
    expect(restored.offerPasswordSave, isFalse);
  });

  test(
    'opting out removes email while preserving unrelated session preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        'korlix_user_email': 'signed-in@example.com',
        'korlix_ui_theme': 'pure_white',
      });
      await const KorlixLoginPreferences(
        rememberEmail: true,
        email: 'person@example.com',
      ).save();
      await const KorlixLoginPreferences(
        rememberEmail: false,
        email: 'person@example.com',
      ).save();
      final preferences = await SharedPreferences.getInstance();
      final record = jsonDecode(
        preferences.getString(KorlixLoginPreferences.storageKey)!,
      );
      expect(record, {'rememberEmail': false, 'offerPasswordSave': true});
      expect(
        preferences.getString('korlix_user_email'),
        'signed-in@example.com',
      );
      expect(preferences.getString('korlix_ui_theme'), 'pure_white');
      expect((await KorlixLoginPreferences.load()).email, isEmpty);
    },
  );

  test('rapid opt-out wins over an earlier delayed opt-in write', () async {
    final gate = Completer<SharedPreferences>();
    final first = const KorlixLoginPreferences(
      rememberEmail: true,
      email: 'person@example.com',
    ).save(loadPreferences: () => gate.future);
    final last = const KorlixLoginPreferences().save();
    final restoring = KorlixLoginPreferences.load();
    gate.complete(await SharedPreferences.getInstance());
    expect(await first, isTrue);
    expect(await last, isTrue);
    final restored = await restoring;
    expect(restored.rememberEmail, isFalse);
    expect(restored.email, isEmpty);
  });

  test(
    'record is allowlisted and never persists password-like extra fields',
    () async {
      SharedPreferences.setMockInitialValues({
        KorlixLoginPreferences.storageKey: jsonEncode({
          'rememberEmail': true,
          'email': 'person@example.com',
          'offerPasswordSave': true,
          'password': 'not-a-real-password',
          'accessToken': 'not-a-real-token',
        }),
      });
      final restored = await KorlixLoginPreferences.load();
      await restored.save();
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), {KorlixLoginPreferences.storageKey});
      expect(
        jsonDecode(preferences.getString(KorlixLoginPreferences.storageKey)!),
        {
          'rememberEmail': true,
          'email': 'person@example.com',
          'offerPasswordSave': true,
        },
      );
    },
  );

  test('an opted-out record never restores a stale email', () async {
    SharedPreferences.setMockInitialValues({
      KorlixLoginPreferences.storageKey: jsonEncode({
        'rememberEmail': false,
        'email': 'stale@example.com',
      }),
    });
    final restored = await KorlixLoginPreferences.load();
    expect(restored.rememberEmail, isFalse);
    expect(restored.email, isEmpty);
  });

  test('corrupt and invalid records use safe defaults', () async {
    for (final raw in [
      '{',
      '[]',
      'null',
      '{"rememberEmail":"true","email":12}',
    ]) {
      SharedPreferences.setMockInitialValues({
        KorlixLoginPreferences.storageKey: raw,
      });
      final restored = await KorlixLoginPreferences.load();
      expect(restored.rememberEmail, isFalse);
      expect(restored.email, isEmpty);
      expect(restored.offerPasswordSave, isTrue);
    }
  });

  test(
    'storage failure does not block login or subsequent preference saves',
    () async {
      Future<SharedPreferences> unavailable() async =>
          throw StateError('Unavailable');
      final restored = await KorlixLoginPreferences.load(
        loadPreferences: unavailable,
      );
      expect(restored.rememberEmail, isFalse);
      expect(
        await const KorlixLoginPreferences().save(loadPreferences: unavailable),
        isFalse,
      );
      expect(
        await const KorlixLoginPreferences(offerPasswordSave: false).save(),
        isTrue,
      );
      expect((await KorlixLoginPreferences.load()).offerPasswordSave, isFalse);
    },
  );

  testWidgets('login lifecycle can finish a preference write', (tester) async {
    bool? saved;
    const KorlixLoginPreferences(
      rememberEmail: true,
      email: 'one@example.com',
    ).save().then((value) => saved = value);
    await tester.pumpAndSettle();
    expect(saved, isTrue);
  });

  testWidgets('next login lifecycle does not await the old event zone', (
    tester,
  ) async {
    KorlixLoginPreferences? restored;
    KorlixLoginPreferences.load().then((value) => restored = value);
    await tester.pumpAndSettle();
    expect(restored, isNotNull);
    expect(restored!.rememberEmail, isFalse);

    bool? saved;
    const KorlixLoginPreferences(
      offerPasswordSave: false,
    ).save().then((value) => saved = value);
    await tester.pumpAndSettle();
    expect(saved, isTrue);
  });
}
