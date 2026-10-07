import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/auth/korlix_token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SecureBackend implements KorlixSecureTokenBackend {
  String? value;
  bool failRead = false;
  bool failWrite = false;
  bool failDelete = false;
  bool ignoreWrite = false;
  Completer<void>? writeBarrier;
  final calls = <String>[];

  @override
  Future<String?> read() async {
    calls.add('read');
    if (failRead) throw StateError('Storage locked');
    return value;
  }

  @override
  Future<void> write(String next) async {
    calls.add('write');
    if (failWrite) throw StateError('Storage unavailable');
    await writeBarrier?.future;
    if (!ignoreWrite) value = next;
  }

  @override
  Future<void> delete() async {
    calls.add('delete');
    if (failDelete) throw StateError('Storage unavailable');
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late _SecureBackend backend;
  late KorlixTokenStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      KorlixTokenStore.accessTokenKey: 'fixture-access',
      KorlixTokenStore.refreshTokenKey: 'fixture-refresh',
    });
    prefs = await SharedPreferences.getInstance();
    backend = _SecureBackend();
    store = KorlixTokenStore(
      useSecureStorage: true,
      preferences: () async => prefs,
      secureStorage: backend,
    );
  });

  test('migrates and verifies both tokens before removing legacy storage', () async {
    final tokens = await store.read();
    expect(tokens?.accessToken, 'fixture-access');
    expect(tokens?.refreshToken, 'fixture-refresh');
    expect(backend.calls, ['read', 'write', 'read']);
    expect(jsonDecode(backend.value!), {
      'access_token': 'fixture-access',
      'refresh_token': 'fixture-refresh',
    });
    expect(prefs.containsKey(KorlixTokenStore.accessTokenKey), false);
    expect(prefs.containsKey(KorlixTokenStore.refreshTokenKey), false);
    expect((await store.read())?.refreshToken, 'fixture-refresh');
  });

  test('a failed migration preserves both legacy values for retry', () async {
    backend.failWrite = true;
    await expectLater(store.read(), throwsA(isA<KorlixTokenStorageException>()));
    expect(prefs.getString(KorlixTokenStore.accessTokenKey), 'fixture-access');
    expect(prefs.getString(KorlixTokenStore.refreshTokenKey), 'fixture-refresh');
    backend.failWrite = false;
    expect((await store.read())?.accessToken, 'fixture-access');
  });

  test('unverified writes do not erase legacy credentials', () async {
    backend.ignoreWrite = true;
    await expectLater(store.read(), throwsA(isA<KorlixTokenStorageException>()));
    expect(prefs.getString(KorlixTokenStore.accessTokenKey), 'fixture-access');
    expect(prefs.getString(KorlixTokenStore.refreshTokenKey), 'fixture-refresh');
  });

  test('secure read failure never authenticates using plaintext fallback', () async {
    backend.failRead = true;
    await expectLater(store.read(), throwsA(isA<KorlixTokenStorageException>()));
    expect(backend.calls, ['read']);
  });

  test('malformed secure records neither leak content nor fall back', () async {
    backend.value = 'private-invalid-json-fixture';
    try {
      await store.read();
      fail('Corrupt secure records must fail closed');
    } on KorlixTokenStorageException catch (error) {
      expect(error.toString(), isNot(contains(backend.value!)));
    }
    expect(prefs.getString(KorlixTokenStore.accessTokenKey), 'fixture-access');
  });

  test('a new account without a refresh token removes the previous one', () async {
    await store.read();
    await store.write(accessToken: 'new-account-access');
    final tokens = await store.read();
    expect(tokens?.accessToken, 'new-account-access');
    expect(tokens?.refreshToken, isNull);
    expect(prefs.containsKey(KorlixTokenStore.refreshTokenKey), false);
  });

  test('failed secure deletion cannot restore a signed-out session', () async {
    await store.read();
    backend.failDelete = true;
    await expectLater(store.clear(), throwsA(isA<KorlixTokenStorageException>()));
    final reopened = KorlixTokenStore(
      useSecureStorage: true,
      preferences: () async => prefs,
      secureStorage: backend,
    );
    expect(await reopened.read(), isNull);
    expect(backend.value, isNotNull);
    backend.failDelete = false;
    await reopened.clear();
    expect(backend.value, isNull);
  });

  test('a pending save completes before a following sign-out', () async {
    backend.writeBarrier = Completer<void>();
    final saving = store.write(accessToken: 'new-access');
    final clearing = store.clear();
    await Future<void>.delayed(Duration.zero);
    expect(backend.calls, ['write']);
    backend.writeBarrier!.complete();
    await Future.wait([saving, clearing]);
    expect(await store.read(), isNull);
    expect(backend.value, isNull);
  });

  test('fresh installs do not restore a keychain session left by uninstall', () async {
    await store.read();
    await prefs.clear();
    expect(await store.read(), isNull);
  });

  test('web preserves storage compatibility without accessing native storage', () async {
    final webStore = KorlixTokenStore(
      useSecureStorage: false,
      preferences: () async => prefs,
      secureStorage: backend,
    );
    expect((await webStore.read())?.refreshToken, 'fixture-refresh');
    await webStore.write(accessToken: 'web-access');
    expect((await webStore.read())?.refreshToken, isNull);
    expect(prefs.getString(KorlixTokenStore.accessTokenKey), 'web-access');
    await webStore.clear();
    expect(await webStore.read(), isNull);
    expect(backend.calls, isEmpty);
  });
}
