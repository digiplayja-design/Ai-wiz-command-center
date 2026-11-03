import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_copy_box/copybox_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _date = '2026-11-03T10:00:00.000Z';

Map<String, dynamic> _box({String id = 'source-box', String text = 'Saved text'}) => {
  'id': id,
  'title': 'Original title',
  'text': text,
  'folder': 'Work',
  'favorite': true,
  'color': 4,
  'updated': _date,
  'history': ['Earlier text'],
  'trashed': false,
};

String _document(List<Object?> boxes) => jsonEncode({
  'format': 'korlix.copybox',
  'version': 1,
  'boxes': boxes,
});

Future<void> _nextTurn() => Future<void>.delayed(Duration.zero);

class _WriteRequest {
  _WriteRequest(this.key, this.value);

  final String key;
  final Object value;
  final result = Completer<bool>();
}

/// Keeps platform writes pending so ordering and failed-write recovery are
/// verified against asynchronous behavior, rather than a synchronous fake.
class _ControlledPreferences extends SharedPreferencesStorePlatform {
  final data = <String, Object>{};
  final writes = <_WriteRequest>[];

  @override
  Future<Map<String, Object>> getAll() async => Map<String, Object>.of(data);

  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters parameters) =>
      getAll();

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    final request = _WriteRequest(key, value);
    writes.add(request);
    return request.result.future.then((accepted) {
      if (accepted) {
        data[key] = value;
      }
      return accepted;
    });
  }

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('account-scoped persistence', () {
    test('guest and verified accounts cannot see or overwrite one another', () async {
      final prefs = await SharedPreferences.getInstance();
      final guest = CopyBoxStore(prefs, 'guest/device');
      final first = CopyBoxStore(prefs, 'https://issuer.example|user-a');
      final second = CopyBoxStore(prefs, 'https://issuer.example|user-b');
      await guest.save([CopyBoxEntry(text: 'Guest draft')]);
      await first.save([CopyBoxEntry(text: 'Account A draft')]);
      await second.save([CopyBoxEntry(text: 'Account B draft')]);

      expect(guest.load().single.text, 'Guest draft');
      expect(first.load().single.text, 'Account A draft');
      expect(second.load().single.text, 'Account B draft');
      expect({guest.key, first.key, second.key}, hasLength(3));
      expect(CopyBoxStore(prefs, 'other-issuer|user-a').load(), isEmpty);
      expect(
        CopyBoxStore(prefs, 'guest%2Fdevice').key,
        isNot(guest.key),
      );
    });

    test('does not adopt hub data or another account on first load', () async {
      final prefs = await SharedPreferences.getInstance();
      const legacyKey = 'korlix_enterprise_copybox_entries_v1';
      await prefs.setStringList(legacyKey, ['Legacy private text']);
      await prefs.setString('korlix_boxes_v2.user-a.copy', jsonEncode([_box()]));
      expect(CopyBoxStore(prefs, 'user-a').load(), isEmpty);
      expect(prefs.getStringList(legacyKey), ['Legacy private text']);
    });

    test('persists revision history, colors, favorites and recoverable trash', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = CopyBoxStore(prefs, 'user-a');
      final box = CopyBoxEntry.fromJson(_box())..trashed = true;
      await store.save([box]);
      final restored = store.load().single;
      expect(restored.toJson(), box.toJson());
      restored.trashed = false;
      await store.save([restored]);
      expect(store.load().single.text, 'Saved text');
      expect(store.load().single.history, ['Earlier text']);
      expect(store.load().single.trashed, isFalse);
    });

    test('blank account scopes are rejected rather than sharing a bucket', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(() => CopyBoxStore(prefs, '  '), throwsArgumentError);
    });
  });

  group('corruption and write safety', () {
    final corruptDocuments = <String, String>{
      'invalid JSON': '{private saved text',
      'unsupported version': jsonEncode({
        'format': 'korlix.copybox',
        'version': 2,
        'boxes': [_box()],
      }),
      'invalid box': _document([_box(), {'id': 'incomplete'}]),
      'duplicate stored IDs': _document([_box(), _box()]),
    };

    for (final corrupt in corruptDocuments.entries) {
      test('${corrupt.key} is preserved and blocks later saves', () async {
        final prefs = await SharedPreferences.getInstance();
        final store = CopyBoxStore(prefs, 'user-a');
        await prefs.setString(store.key, corrupt.value);
        expect(
          store.load,
          throwsA(
            isA<CopyBoxDataException>().having(
              (error) => error.message,
              'message',
              contains('Your existing data has been kept'),
            ),
          ),
        );
        await expectLater(
          store.save([CopyBoxEntry(text: 'Do not replace saved data')]),
          throwsA(isA<CopyBoxDataException>()),
        );
        expect(prefs.getString(store.key), corrupt.value);
        expect(store.rawData, corrupt.value);
      });
    }

    test('saving before first load cannot overwrite corrupt storage', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = CopyBoxStore(prefs, 'user-a');
      await prefs.setString(store.key, 'unreadable');
      await expectLater(store.save([]), throwsA(isA<CopyBoxDataException>()));
      expect(prefs.getString(store.key), 'unreadable');
    });

    test('unexpected preference type is preserved', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = CopyBoxStore(prefs, 'user-a');
      await prefs.setInt(store.key, 7);
      expect(store.load, throwsA(isA<CopyBoxDataException>()));
      await expectLater(store.save([]), throwsA(isA<CopyBoxDataException>()));
      expect(prefs.get(store.key), 7);
    });

    test('a successful explicit reload unlocks externally recovered data', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = CopyBoxStore(prefs, 'user-a');
      await prefs.setString(store.key, 'broken');
      expect(store.load, throwsA(isA<CopyBoxDataException>()));
      await prefs.setString(store.key, _document([_box()]));
      await expectLater(store.save([]), throwsA(isA<CopyBoxDataException>()));
      final recovered = store.load();
      recovered.single.replace('Recovered and edited');
      await store.save(recovered);
      expect(store.load().single.text, 'Recovered and edited');
    });

    test('invalid editor state leaves the previous saved snapshot intact', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = CopyBoxStore(prefs, 'user-a');
      final box = CopyBoxEntry.fromJson(_box());
      await store.save([box]);
      final previous = prefs.getString(store.key);
      box.color = 6;
      await expectLater(store.save([box]), throwsA(isA<CopyBoxDataException>()));
      expect(prefs.getString(store.key), previous);
    });

    test('concurrent saves are ordered and capture mutable state immediately', () async {
      final platform = _ControlledPreferences();
      SharedPreferencesStorePlatform.instance = platform;
      final prefs = await SharedPreferences.getInstance();
      final store = CopyBoxStore(prefs, 'user-a');
      final box = CopyBoxEntry.fromJson(_box(text: 'First snapshot'));

      final first = store.save([box]);
      box.replace('Second snapshot');
      final second = store.save([box]);
      box.replace('Unsaved change');
      await _nextTurn();

      expect(platform.writes, hasLength(1));
      final firstData = jsonDecode(platform.writes.first.value as String) as Map;
      expect((firstData['boxes'] as List).single['text'], 'First snapshot');
      expect((firstData['boxes'] as List).single['history'], ['Earlier text']);

      platform.writes.first.result.complete(true);
      await first;
      await _nextTurn();
      expect(platform.writes, hasLength(2));
      final secondData = jsonDecode(platform.writes.last.value as String) as Map;
      expect((secondData['boxes'] as List).single['text'], 'Second snapshot');
      expect((secondData['boxes'] as List).single['history'], [
        'First snapshot',
        'Earlier text',
      ]);
      platform.writes.last.result.complete(true);
      await second;

      expect(store.load().single.text, 'Second snapshot');
      expect(store.load().single.history, ['First snapshot', 'Earlier text']);
      final diskData = jsonDecode(platform.data.values.single as String) as Map;
      expect((diskData['boxes'] as List).single['text'], 'Second snapshot');
    });

    for (final throwError in [false, true]) {
      test('a ${throwError ? 'throwing' : 'rejected'} write does not poison retries', () async {
        final platform = _ControlledPreferences();
        SharedPreferencesStorePlatform.instance = platform;
        final prefs = await SharedPreferences.getInstance();
        final store = CopyBoxStore(prefs, 'user-a');
        final failed = store.save([CopyBoxEntry(text: 'First attempt')]);
        final observedFailure = expectLater(
          failed,
          throwsA(
            isA<CopyBoxDataException>().having(
              (error) => error.message,
              'message',
              contains('Could not save'),
            ),
          ),
        );
        final retry = store.save([CopyBoxEntry(text: 'Latest attempt')]);
        await _nextTurn();
        expect(platform.writes, hasLength(1));
        if (throwError) {
          platform.writes.first.result.completeError(StateError('Storage unavailable'));
        } else {
          platform.writes.first.result.complete(false);
        }
        await observedFailure;
        await _nextTurn();
        expect(platform.writes, hasLength(2));
        platform.writes.last.result.complete(true);
        await retry;
        expect(store.load().single.text, 'Latest attempt');
      });
    }
  });

  group('safe imports and backups', () {
    test('round trip preserves content and trash while always changing identity', () {
      final original = CopyBoxEntry.fromJson(_box())..trashed = true;
      final raw = exportBackup([original]);
      final envelope = jsonDecode(raw) as Map;
      expect(envelope['format'], 'korlix.copybox');
      expect(envelope['version'], 1);
      final first = parseImport(raw).single;
      final second = parseImport(raw).single;
      expect({original.id, first.id, second.id}, hasLength(3));
      expect({...first.toJson(), 'id': original.id}, original.toJson());
      expect(original.id, 'source-box');
    });

    test('manual hub list import accepts legacy fields and does not merge IDs', () {
      final legacy = _box()
        ..remove('color')
        ..remove('trashed');
      final imported = parseImport(jsonEncode([legacy, legacy]));
      expect(imported, hasLength(2));
      expect(imported.map((entry) => entry.id).toSet(), hasLength(2));
      expect(imported.every((entry) => entry.id != legacy['id']), isTrue);
      expect(imported.first.color, 0);
      expect(imported.first.trashed, isFalse);
      expect(imported.first.updated, _date);
    });

    test('plain text preserves whitespace, Unicode, and Windows line endings', () {
      const text = '  Hello 👋\r\n\r\nKeep trailing spaces  \n';
      expect(parseImport(text, plainText: true).single.text, text);
      expect(() => parseImport(text), throwsA(isA<CopyBoxDataException>()));
      expect(() => parseImport('', plainText: true), throwsA(isA<CopyBoxDataException>()));
    });

    test('UTF-8 BOM is accepted for JSON backups', () {
      expect(parseImport('\uFEFF${_document([_box()])}').single.text, 'Saved text');
    });

    final invalidFields = <String, Object?>{
      'id': '../../another-account',
      'title': 42,
      'text': null,
      'folder': ['Work'],
      'favorite': 'true',
      'color': 6,
      'updated': 'not-a-date',
      'history': ['valid', 42],
      'trashed': 1,
    };
    for (final invalid in invalidFields.entries) {
      test('rejects invalid ${invalid.key} without partial results', () {
        final boxes = [_box(id: 'valid-box'), {..._box(), invalid.key: invalid.value}];
        expect(
          () => parseImport(_document(boxes)),
          throwsA(
            isA<CopyBoxDataException>().having(
              (error) => error.message,
              'box index',
              startsWith('Box 2:'),
            ),
          ),
        );
      });
    }

    test('validates title, folder, body, revision and count limits', () {
      for (final field in ['title', 'folder']) {
        expect(
          () => parseImport(_document([{..._box(), field: List.filled(201, 'x').join()}])),
          throwsA(isA<CopyBoxDataException>()),
        );
      }
      final tooLong = List.filled(copyBoxMaxTextLength + 1, 'x').join();
      expect(() => parseImport(tooLong, plainText: true), throwsA(isA<CopyBoxDataException>()));
      expect(
        () => parseImport(_document([{..._box(), 'text': tooLong}])),
        throwsA(isA<CopyBoxDataException>()),
      );
      expect(
        () => parseImport(_document([{..._box(), 'history': [tooLong]}])),
        throwsA(isA<CopyBoxDataException>()),
      );
      expect(
        () => parseImport(_document([{..._box(), 'history': List.filled(21, 'old')}])),
        throwsA(isA<CopyBoxDataException>()),
      );
      expect(
        () => parseImport(_document(List.generate(1001, (index) => _box(id: 'box-$index')))),
        throwsA(isA<CopyBoxDataException>()),
      );
    });

    test('5 MB limit counts UTF-8 bytes rather than only string length', () {
      final unicodeText = List.filled(50000, 'é').join();
      final raw = _document(List.generate(60, (index) => _box(id: 'box-$index', text: unicodeText)));
      expect(raw.length, lessThan(copyBoxMaxBytes));
      expect(utf8.encode(raw).length, greaterThan(copyBoxMaxBytes));
      expect(
        () => parseImport(raw),
        throwsA(
          isA<CopyBoxDataException>().having(
            (error) => error.message,
            'size error',
            contains('5 MB'),
          ),
        ),
      );
    });

    test('backup validation catches duplicate in-memory IDs', () {
      expect(
        () => exportBackup([CopyBoxEntry(id: 'duplicate'), CopyBoxEntry(id: 'duplicate')]),
        throwsA(isA<CopyBoxDataException>()),
      );
    });
  });

  group('revisions, templates and filters', () {
    test('revisions are bounded, cloned, and retain the text before a restore', () {
      final history = ['Earlier'];
      final entry = CopyBoxEntry(text: 'Original', history: history, updated: _date);
      history.add('External mutation');
      expect(entry.history, ['Earlier']);
      entry.replace('Original');
      expect(entry.updated, _date);
      entry.replace('Draft');
      entry.replace(entry.history.first);
      expect(entry.text, 'Original');
      expect(entry.history.take(2), ['Draft', 'Original']);
      for (var index = 0; index < 30; index++) {
        entry.replace('Revision $index');
      }
      expect(entry.history, hasLength(20));
      expect(entry.history.first, 'Revision 28');
      final snapshot = entry.toJson();
      (snapshot['history'] as List).clear();
      expect(entry.history, hasLength(20));
    });

    test('template fields are ordered, unique, literal and non-recursive', () {
      const text = '{{ client }} / {{client}} / {{café}} / {{missing}} / {{ }}';
      expect(templateFields(text), ['client', 'café', 'missing']);
      expect(
        renderTemplate(text, {'client': r'A$1\path', 'café': '{{client}}', '': 'unused'}),
        r'A$1\path / A$1\path / {{client}} / {{missing}} / {{ }}',
      );
      expect(copyBoxTemplates, hasLength(6));
      expect(copyBoxTemplates.every((template) => templateFields(template.text).isNotEmpty), isTrue);
    });

    test('search combines filters and preserves workspace order and text', () {
      final entries = [
        CopyBoxEntry(id: 'a', title: 'Launch', text: 'Ready first', folder: 'Work', favorite: true),
        CopyBoxEntry(id: 'b', title: 'Launch', text: 'Ready second', folder: 'Work'),
        CopyBoxEntry(id: 'c', title: 'Launch', text: 'Ready third', folder: 'Work', favorite: true),
        CopyBoxEntry(id: 'd', title: 'Launch', text: 'Ready deleted', folder: 'Work', favorite: true, trashed: true),
        CopyBoxEntry(id: 'e', title: 'Home', text: 'Ready uncategorized'),
      ];
      final result = filterEntries(entries, query: ' READY launch ', folder: 'Work', favoritesOnly: true);
      expect(result.map((entry) => entry.id), ['a', 'c']);
      expect(filterEntries(entries, trashedOnly: true).single.id, 'd');
      expect(filterEntries(entries, includeTrashed: true), hasLength(5));
      expect(filterEntries(entries, folder: '').single.id, 'e');
      expect(entries.map((entry) => entry.id), ['a', 'b', 'c', 'd', 'e']);
      expect(entries.first.text, 'Ready first');
    });
  });
}
