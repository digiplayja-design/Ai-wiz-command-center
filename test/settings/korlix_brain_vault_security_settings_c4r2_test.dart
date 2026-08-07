import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String mainSource;
  late String rootServerSource;
  late String backendServerSource;
  late String migrationSource;

  setUpAll(() {
    mainSource = File('lib/main.dart').readAsStringSync();
    rootServerSource = File('server.js').readAsStringSync();
    backendServerSource = File('backend/server.js').readAsStringSync();
    migrationSource = File(
      'supabase/migrations/202608050001_brain_vault_credentials_build131.sql',
    ).readAsStringSync();
  });

  test('shared account panel exposes Account Manager BRAIN VAULT security', () {
    expect(
      'KORLIX_BRAIN_VAULT_SECURITY_SETTINGS_UI_BUILD131_V1_BEGIN'
          .allMatches(mainSource)
          .length,
      1,
    );
    expect(
      'KORLIX_BRAIN_VAULT_ACCOUNT_MANAGER_SETTINGS_BUILD131_V1_BEGIN'
          .allMatches(mainSource)
          .length,
      1,
    );
    expect(mainSource, contains("label: const Text('BRAIN VAULT Security')"));
    expect(mainSource, contains('Account Manager controls'));
    expect(mainSource, contains('web, iOS, and Android'));
    expect(mainSource, contains('different from the KORLIX login'));
  });

  test('security UI uses the authenticated separate-password routes', () {
    expect(mainSource, contains("path: '/api/brain-vault/security-status'"));
    expect(mainSource, contains("'/api/brain-vault/password/set'"));
    expect(mainSource, contains("'/api/brain-vault/password/change'"));
    expect(mainSource, contains("'/api/brain-vault/password/reset'"));
    expect(mainSource, contains("'accountPassword': accountPassword"));
    expect(
      mainSource,
      contains("'currentVaultPassword': currentVaultPassword"),
    );
    expect(mainSource, contains("'newVaultPassword': newVaultPassword"));
    expect(mainSource, contains("'confirmVaultPassword': confirmation"));
    expect(
      mainSource,
      contains(
        'The BRAIN VAULT password must differ from the KORLIX login password.',
      ),
    );
  });

  test(
    'mirrored backend routes and guarded migration source remain present',
    () {
      for (final source in <String>[rootServerSource, backendServerSource]) {
        expect(source, contains('app.get("/api/brain-vault/security-status"'));
        expect(source, contains('app.post("/api/brain-vault/password/set"'));
        expect(source, contains('app.post("/api/brain-vault/password/change"'));
        expect(source, contains('app.post("/api/brain-vault/password/reset"'));
        expect(source, contains('managerMode: "account_owner"'));
      }

      expect(
        migrationSource,
        contains(
          'create table if not exists public.korlix_brain_vault_credentials',
        ),
      );
      expect(migrationSource, contains('manager_user_id uuid not null'));
      expect(migrationSource, contains('enable row level security'));
    },
  );

  test('C4R2 does not add AI GAS purchasing or weaken Saved Settings', () {
    expect(
      mainSource,
      contains('KORLIX_SAVED_SETTINGS_DELETE_BUILD131_V1_BEGIN'),
    );
    expect(mainSource, isNot(contains('KORLIX_AI_GAS_PURCHASE_BUILD131')));
    expect(
      mainSource,
      contains('placed in Saved Settings, exports, billing, or AI GAS'),
    );
  });
}
