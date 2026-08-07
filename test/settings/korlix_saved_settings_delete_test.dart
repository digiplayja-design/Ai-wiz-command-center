import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String mainSource;
  late List<String> serverSources;

  setUpAll(() {
    mainSource = File('lib/main.dart').readAsStringSync();
    serverSources = <String>[
      File('server.js').readAsStringSync(),
      File('backend/server.js').readAsStringSync(),
    ];
  });

  test('Saved Settings exposes confirmed individual and Delete All controls', () {
    expect(
      'KORLIX_SAVED_SETTINGS_DELETE_BUILD131_V1_BEGIN'
          .allMatches(mainSource)
          .length,
      1,
    );
    expect(mainSource, contains("title: 'Delete saved generation?'"));
    expect(mainSource, contains("title: 'Delete all Saved Settings?'"));
    expect(mainSource, contains("tooltip: 'Delete saved generation'"));
    expect(mainSource, contains("historyDeleteBusy ? 'Deleting…' : 'Delete All'"));
    expect(mainSource, contains('history.removeWhere((candidate)'));
    expect(mainSource, contains('history.clear();'));
  });

  test('deletions use authenticated server history routes and safe IDs', () {
    expect(mainSource, contains('Uri.encodeComponent(id)'));
    expect(mainSource, contains('headers: _headers()'));
    expect(mainSource, contains('await _loadSavedHistoryBatch()'));
    expect(mainSource, contains('while (true)'));

    for (final source in serverSources) {
      final start = source.indexOf('app.delete("/api/history/:id"');
      final end = source.indexOf(
        'app.post("/api/account/delete-request"',
        start,
      );
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final route = source.substring(start, end);
      expect(route, contains('requireUser(req)'));
      expect(route, contains('.eq("id", id)'));
      expect(route, contains('.eq("user_id", user.id)'));
    }
  });

  test('Saved Settings deletion does not weaken BRAIN VAULT or add AI GAS', () {
    expect(
      mainSource,
      isNot(contains('KORLIX_AI_GAS_PURCHASE_BUILD131')),
    );
    final vaultSource = File(
      'lib/live_convo/korlix_live_convo_agent_sheet.dart',
    ).readAsStringSync();
    expect(
      vaultSource,
      contains('KORLIX_BRAIN_VAULT_LOCK_UI_BUILD131_V2_BEGIN'),
    );
  });
}
