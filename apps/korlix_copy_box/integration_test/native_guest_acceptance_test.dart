import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:korlix_copy_box/copybox_app.dart';
import 'package:korlix_copy_box/copybox_card.dart';
import 'package:korlix_copy_box/copybox_store.dart';
import 'package:korlix_copy_box/main.dart' as app;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Run only on the disposable simulator/emulator created by the CI workflow.
// No storage, platform channel, auth client, or clipboard mocks are installed.
const _phase = String.fromEnvironment('COPYBOX_ACCEPTANCE_PHASE');
const _marker = 'copybox_native_acceptance_v1';
const _title = 'Native acceptance note';
const _folder = 'Acceptance';
const _original = 'Hello {{name}}. Keep this useful note on this device.';
const _revised = 'Hello {{name}}. This edited note survives reopening.';

Future<void> _settle(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _enter(WidgetTester tester, Finder finder, String text) async {
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await _settle(tester);
}

Future<void> _navigate(WidgetTester tester, String label) => _tap(
  tester,
  find.widgetWithText(NavigationDestination, label),
);

Finder _card(String id) => find.byKey(ValueKey(id));

Future<void> _option(WidgetTester tester, String id, String label) async {
  await _tap(
    tester,
    find.descendant(of: _card(id), matching: find.byTooltip('Box options')),
  );
  await _tap(tester, find.text(label));
}

Future<List<CopyBoxEntry>> _stored(SharedPreferences prefs) async {
  await prefs.reload();
  return CopyBoxStore(prefs, 'local').load();
}

Future<void> _open(WidgetTester tester) async {
  app.main();
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byKey(const Key('add-box')).evaluate().isNotEmpty) break;
  }
  await _settle(tester);
  expect(find.byKey(const Key('add-box')), findsOneWidget);
  final actual = tester.widget<CopyBoxApp>(find.byType(CopyBoxApp));
  expect(actual.auth.ready, isTrue);
  expect(actual.auth.accountScope, isNull);
  // The app tolerates secure-storage failures. Acceptance must expose one.
  expect(actual.auth.restoreError, isNull);
  final package = await PackageInfo.fromPlatform();
  expect(package.packageName, 'com.korlixdeveloper.copybox');
  expect(package.version, const String.fromEnvironment('COPYBOX_EXPECTED_VERSION'));
  expect(package.buildNumber, const String.fromEnvironment('COPYBOX_EXPECTED_BUILD'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native guest workspace: $_phase', (tester) async {
    expect(Platform.isIOS || Platform.isAndroid, isTrue);
    expect(_phase, isIn(['seed', 'restore']));
    // This CI-only override keeps even an accidental auth request off production.
    expect(
      const String.fromEnvironment('KORLIX_BACKEND_URL'),
      'http://127.0.0.1:1',
    );
    final prefs = await SharedPreferences.getInstance();
    if (_phase == 'seed') {
      expect(prefs.getString(_marker), isNull);
      expect(CopyBoxStore(prefs, 'local').load(), isEmpty);
    } else {
      expect(prefs.getString(_marker), 'seed-complete');
      expect(prefs.getString('copybox_theme'), 'dark');
    }
    await _open(tester);

    if (_phase == 'seed') {
      expect(find.byType(CopyBoxCard), findsNWidgets(12));
      final id = tester.widget<CopyBoxCard>(find.byType(CopyBoxCard).first).box.id;
      await _enter(tester, find.byKey(ValueKey('title-$id')), _title);
      await _enter(tester, find.byKey(ValueKey('folder-$id')), _folder);
      await _enter(tester, find.byKey(ValueKey('text-$id')), _original);
      await _tap(
        tester,
        find.descendant(of: _card(id), matching: find.byTooltip('Add to favorites')),
      );
      var saved = (await _stored(prefs)).singleWhere((box) => box.id == id);
      expect(saved.title, _title);
      expect(saved.folder, _folder);
      expect(saved.text, _original);
      expect(saved.favorite, isTrue);

      await _tap(tester, find.byKey(const Key('copy-all')));
      expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, _original);
      await _enter(tester, find.byKey(const Key('search-boxes')), _title);
      expect(find.byType(CopyBoxCard), findsOneWidget);

      await _option(tester, id, 'Focus editor');
      await _enter(tester, find.byKey(const Key('focus-text')), _revised);
      await _tap(tester, find.byKey(const Key('focus-save')));
      saved = (await _stored(prefs)).singleWhere((box) => box.id == id);
      expect(saved.text, _revised);
      expect(saved.history.first, _original);

      await _option(tester, id, 'Fill template fields');
      await _enter(tester, find.widgetWithText(TextFormField, 'name'), 'Alex');
      await _tap(tester, find.text('Copy finished text'));
      expect(
        (await Clipboard.getData(Clipboard.kTextPlain))?.text,
        _revised.replaceFirst('{{name}}', 'Alex'),
      );
      expect((await _stored(prefs)).singleWhere((box) => box.id == id).text, _revised);

      await _option(tester, id, 'Move to trash');
      expect((await _stored(prefs)).singleWhere((box) => box.id == id).trashed, isTrue);
      await _navigate(tester, 'Backup');
      await _tap(tester, find.text('Open trash'));
      await _tap(tester, find.widgetWithText(ListTile, _title));
      expect((await _stored(prefs)).singleWhere((box) => box.id == id).trashed, isFalse);

      await _navigate(tester, 'Templates');
      await _tap(tester, find.text('Use template').first);
      expect((await _stored(prefs)).length, 13);
      expect((await _stored(prefs)).last.title, 'Client follow-up');
      expect((await _stored(prefs)).last.folder, 'Business');

      await _navigate(tester, 'Settings');
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Dark'));
      await prefs.reload();
      expect(prefs.getString('copybox_theme'), 'dark');
      expect(await prefs.setString(_marker, 'seed-complete'), isTrue);
    } else {
      final saved = await _stored(prefs);
      expect(saved.length, 13);
      final note = saved.singleWhere((box) => box.title == _title);
      expect(note.text, _revised);
      expect(note.folder, _folder);
      expect(note.favorite, isTrue);
      expect(note.trashed, isFalse);
      expect(note.history.first, _original);
      expect(saved.last.title, 'Client follow-up');

      await _enter(tester, find.byKey(const Key('search-boxes')), _title);
      expect(find.byType(CopyBoxCard), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(ValueKey('text-${note.id}'))).controller!.text,
        _revised,
      );
      expect(Theme.of(tester.element(_card(note.id))).brightness, Brightness.dark);
      await _navigate(tester, 'Settings');
      expect(find.text('Connect KORLIX'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
    }
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
