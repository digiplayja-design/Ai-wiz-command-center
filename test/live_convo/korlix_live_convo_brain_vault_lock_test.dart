import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KORLIX separate BRAIN VAULT credential', () {
    late String sheetSource;
    late String clientSource;
    late String rootServerSource;
    late String backendServerSource;
    late String migrationSource;

    setUpAll(() {
      sheetSource = File(
        'lib/live_convo/korlix_live_convo_agent_sheet.dart',
      ).readAsStringSync();
      clientSource = File(
        'lib/live_convo/korlix_live_convo_agent_client.dart',
      ).readAsStringSync();
      rootServerSource = File('server.js').readAsStringSync();
      backendServerSource = File('backend/server.js').readAsStringSync();
      migrationSource = File(
        'supabase/migrations/'
        '202608050001_brain_vault_credentials_build131.sql',
      ).readAsStringSync();
    });

    test('removes the normal-login-password unlock contract', () {
      for (final source in <String>[
        rootServerSource,
        backendServerSource,
        clientSource,
      ]) {
        expect(source, isNot(contains('/api/auth/reauth')));
        expect(
          source,
          isNot(contains('KORLIX_BRAIN_VAULT_REAUTH_BUILD131_V1_BEGIN')),
        );
      }

      expect(
        sheetSource,
        isNot(contains('Enter your current KORLIX account password to open')),
      );
      expect(sheetSource, isNot(contains('Current KORLIX password')));
    });

    test('uses a separate Account Manager controlled credential', () {
      for (final source in <String>[rootServerSource, backendServerSource]) {
        expect(
          source,
          contains('KORLIX_BRAIN_VAULT_CREDENTIALS_BUILD131_V2_BEGIN'),
        );
        expect(source, contains('korlix_brain_vault_credentials'));
        expect(source, contains('manager_user_id'));
        expect(source, contains('managerMode: "account_owner"'));
        expect(source, contains('crypto.scrypt'));
        expect(source, contains('crypto.randomBytes(16)'));
        expect(source, contains('crypto.timingSafeEqual'));
        expect(source, contains('passwordAlgorithm: "scrypt-v1"'));
        expect(source, contains('KORLIX_BRAIN_VAULT_MAX_FAILURES_V2 = 5'));
        expect(source, contains('15 * 60 * 1000'));
      }

      expect(
        migrationSource,
        contains(
          'create table if not exists public.'
          'korlix_brain_vault_credentials',
        ),
      );
      expect(migrationSource, contains('manager_user_id uuid not null'));
      expect(migrationSource, contains('password_hash text not null'));
      expect(migrationSource, contains('password_salt text not null'));
      expect(migrationSource, contains('enable row level security'));
      expect(migrationSource, contains('to service_role'));
      expect(
        migrationSource,
        contains('revoke all on table public.korlix_brain_vault_credentials'),
      );
    });

    test('verification uses only the separate vault password', () {
      for (final source in <String>[rootServerSource, backendServerSource]) {
        const verifyStart = 'app.post("/api/brain-vault/password/verify"';
        const changeStart = 'app.post("/api/brain-vault/password/change"';
        final start = source.indexOf(verifyStart);
        final finish = source.indexOf(changeStart, start);

        expect(start, greaterThanOrEqualTo(0));
        expect(finish, greaterThan(start));

        final verifySource = source.substring(start, finish);
        expect(verifySource, contains('requireUser(req)'));
        expect(verifySource, contains('req.body?.vaultPassword'));
        expect(verifySource, contains('korlixBrainVaultPasswordMatchesV2'));
        expect(verifySource, isNot(contains('signInWithPassword')));
        expect(verifySource, isNot(contains('req.body?.accountPassword')));
        expect(verifySource, isNot(contains('req.body?.userId')));
        expect(verifySource, isNot(contains('req.body?.email')));
      }

      expect(
        clientSource,
        contains("path: '/api/brain-vault/password/verify'"),
      );
      expect(clientSource, contains("'vaultPassword': password"));
    });

    test(
      'management routes require authenticated account-owner verification',
      () {
        for (final source in <String>[rootServerSource, backendServerSource]) {
          for (final route in <String>[
            '/api/brain-vault/password/set',
            '/api/brain-vault/password/change',
            '/api/brain-vault/password/reset',
          ]) {
            expect(source, contains(route));
          }

          expect(
            source,
            contains('korlixBrainVaultVerifyAccountManagerLoginV2'),
          );
          expect(source, contains('signInWithPassword'));
          expect(source, contains('data.user.id !== user.id'));
          expect(source, contains('vaultPassword === accountPassword'));
          expect(source, contains('newVaultPassword === accountPassword'));
        }

        expect(clientSource, contains('setBrainVaultPassword'));
        expect(clientSource, contains('changeBrainVaultPassword'));
        expect(clientSource, contains('resetBrainVaultPassword'));
        expect(clientSource, contains('loadBrainVaultSecurityStatus'));
      },
    );

    test('shared Flutter lock UI uses the separate credential', () {
      const begin = '// KORLIX_BRAIN_VAULT_LOCK_UI_BUILD131_V2_BEGIN';
      const end = '// KORLIX_BRAIN_VAULT_LOCK_UI_BUILD131_V2_END';
      final start = sheetSource.indexOf(begin);
      final finish = sheetSource.indexOf(end, start);

      expect(start, greaterThanOrEqualTo(0));
      expect(finish, greaterThan(start));

      final lockSource = sheetSource.substring(start, finish);
      expect(lockSource, contains('verifyBrainVaultPassword'));
      expect(lockSource, contains('separate BRAIN VAULT password'));
      expect(lockSource, contains('Account Manager'));
      expect(lockSource, contains('password.length < 12'));
      expect(lockSource, contains('password.length > 128'));
      expect(lockSource, contains('obscureText: obscurePassword'));
      expect(lockSource, contains('enableSuggestions: false'));
      expect(lockSource, contains('autocorrect: false'));
      expect(lockSource, contains('autofillHints: const <String>[]'));
      expect(lockSource, contains('controller.clear()'));
      expect(lockSource, contains('controller.dispose()'));
      expect(lockSource, isNot(contains('SharedPreferences')));
      expect(lockSource, isNot(contains('writeAsString')));
      expect(lockSource, isNot(contains('print(')));
    });

    test('keeps every BRAIN VAULT action behind the lock', () {
      const startMarker =
          'Future<void> _openBrainVault(KorlixLiveConvoAgent agent) async {';
      const endMarker = '// KORLIX_BRAIN_VAULT_UI_BUILD131_V1_END';
      final start = sheetSource.indexOf(startMarker);
      final finish = sheetSource.indexOf(endMarker, start);

      expect(start, greaterThanOrEqualTo(0));
      expect(finish, greaterThan(start));

      final openSource = sheetSource.substring(start, finish);
      final unlockIndex = openSource.indexOf('_unlockBrainVault(agent)');
      final sheetIndex = openSource.indexOf('showModalBottomSheet<String>');
      final expiryIndex = openSource.indexOf('Duration(minutes: 5)');
      final switchIndex = openSource.indexOf('switch (action)');

      expect(unlockIndex, greaterThanOrEqualTo(0));
      expect(sheetIndex, greaterThan(unlockIndex));
      expect(expiryIndex, greaterThan(sheetIndex));
      expect(switchIndex, greaterThan(expiryIndex));

      for (final action in <String>[
        "case 'contents':",
        "case 'duplicate_setup':",
        "case 'duplicate_full':",
        "case 'export_template':",
        "case 'export_private':",
        "case 'import':",
      ]) {
        expect(openSource, contains(action));
      }
    });
  });
}
