import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/imagine_studio/imagine_catalog.dart';
import 'package:ai_wiz_command_center/imagine_studio/imagine_client.dart';
import 'imagine_studio_test.dart' as imagine;
import 'package:ai_wiz_command_center/logo_studio/logo_client.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_model.dart';

class LogoFixture {
  LogoFixture({imagine.Briefs? storage})
    : studio = imagine.Studio(storage: storage);
  final imagine.Studio studio;
  late final c = LogoClient(
    images: studio.client,
    headers: {'Authorization': studio.token},
    store: studio.storage,
  );
}

class PendingStore extends imagine.Briefs {
  final pending = Completer<List<String>>();
  @override
  Future<List<String>> read(String key) => pending.future;
}

const sample = LogoDesign(
  name: 'DA FINAL STOP',
  tagline: 'GOOD FOOD. GREAT COMPANY.',
  industry: 'Food & drink',
  style: 'Organic',
  mark: 'Leaf',
  primary: '16604B',
  secondary: 'CB825B',
  paper: 'F5F3EA',
);

class BlockingLogoStore extends imagine.Briefs {
  final writing = Completer<void>();
  final release = Completer<void>();
  bool fail = false;

  @override
  Future<void> write(String key, List<String> value) async {
    if (!writing.isCompleted) writing.complete();
    await release.future;
    if (fail) throw StateError('Storage unavailable');
    await super.write(key, value);
  }
}

String sessionToken({String session = 'session-alice', int expires = 1}) =>
    'Bearer x.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'https://fixture.test', 'sub': 'alice', 'session_id': session, 'exp': expires}))).replaceAll('=', '')}.x';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'saving updates the current project and save copy gets a new identity',
    () async {
      final f = LogoFixture();
      addTearDown(f.c.dispose);
      f.c.generate(sample);
      expect(f.c.currentProjectId, isNull);
      expect(f.c.hasUnsavedChanges, isTrue);
      await f.c.save();
      final originalId = f.c.currentProjectId;
      expect(originalId, isNotNull);
      expect(f.c.hasUnsavedChanges, isFalse);

      f.c.update(f.c.design.copy(tagline: 'A new chapter'));
      expect(f.c.hasUnsavedChanges, isTrue);
      await f.c.save();
      expect(f.c.currentProjectId, originalId);
      expect(f.c.projects, hasLength(1));
      expect(f.c.projects.single['design']['tagline'], 'A new chapter');
      expect(f.c.hasUnsavedChanges, isFalse);

      await f.c.save(asCopy: true);
      expect(f.c.currentProjectId, isNot(originalId));
      expect(f.c.projects, hasLength(2));
      expect(f.c.hasUnsavedChanges, isFalse);
      expect(f.studio.requests, isEmpty);
    },
  );

  test(
    'reopening saved projects preserves identity and undo restores clean state',
    () async {
      final store = imagine.Briefs();
      final first = LogoFixture(storage: store);
      first.c.generate(sample);
      await first.c.save();
      final id = first.c.currentProjectId!;
      first.c.dispose();

      final second = LogoFixture(storage: store);
      addTearDown(second.c.dispose);
      await second.c.load();
      second.c.openProject(id);
      expect(second.c.currentProjectId, id);
      expect(second.c.hasUnsavedChanges, isFalse);
      second.c.update(second.c.design.copy(primary: '123456'));
      expect(second.c.hasUnsavedChanges, isTrue);
      second.c.undo();
      expect(second.c.hasUnsavedChanges, isFalse);
      second.c.redo();
      expect(second.c.hasUnsavedChanges, isTrue);
      await second.c.save();
      expect(second.c.projects, hasLength(1));
      expect(second.c.projects.single['design']['primary'], '123456');
    },
  );

  test(
    'updating remains possible at the project limit while copying is refused',
    () async {
      final f = LogoFixture();
      addTearDown(f.c.dispose);
      for (var i = 0; i < 20; i++) {
        f.c.choose(sample.copy(name: 'Brand $i'));
        await f.c.save();
      }
      final id = f.c.currentProjectId;
      f.c.update(f.c.design.copy(name: 'Updated brand'));
      await f.c.save();
      expect(f.c.projects, hasLength(20));
      expect(f.c.currentProjectId, id);
      expect(f.c.projects.first['design']['name'], 'Updated brand');
      await expectLater(
        f.c.save(asCopy: true),
        throwsA(isA<ImagineException>()),
      );
      expect(f.c.projects, hasLength(20));
      expect(f.c.saving, isFalse);
    },
  );

  test(
    'a failed save leaves the active document unsaved and keeps saved rows intact',
    () async {
      final store = BlockingLogoStore()..fail = true;
      final f = LogoFixture(storage: store);
      addTearDown(f.c.dispose);
      f.c.generate(sample);
      final saving = f.c.save();
      final failure = expectLater(saving, throwsStateError);
      await store.writing.future;
      store.release.complete();
      await failure;
      expect(f.c.projects, isEmpty);
      expect(f.c.currentProjectId, isNull);
      expect(f.c.hasUnsavedChanges, isTrue);
      expect(f.c.saving, isFalse);
    },
  );

  test(
    'a pending save cannot attach the previous brand identity to a new brand',
    () async {
      final store = BlockingLogoStore();
      final f = LogoFixture(storage: store);
      addTearDown(f.c.dispose);
      f.c.generate(sample);
      final saving = f.c.save();
      await store.writing.future;
      f.c.newBrand();
      f.c.generate(sample.copy(name: 'Another brand'));
      store.release.complete();
      await saving;
      expect(f.c.design.name, 'Another brand');
      expect(f.c.currentProjectId, isNull);
      expect(f.c.hasUnsavedChanges, isTrue);
      expect(f.c.projects.single['design']['name'], sample.name);
    },
  );

  test(
    'edits during a save remain dirty after the saved snapshot completes',
    () async {
      final store = BlockingLogoStore();
      final f = LogoFixture(storage: store);
      addTearDown(f.c.dispose);
      f.c.generate(sample);
      final saving = f.c.save();
      await store.writing.future;
      f.c.update(f.c.design.copy(name: 'Changed while saving'));
      store.release.complete();
      await saving;
      expect(f.c.currentProjectId, isNotNull);
      expect(f.c.hasUnsavedChanges, isTrue);
      expect(f.c.projects.single['design']['name'], sample.name);
      expect(f.c.design.name, 'Changed while saving');
    },
  );

  test(
    'shortlisting is bounded and more directions preserve the selected project',
    () async {
      final f = LogoFixture();
      addTearDown(f.c.dispose);
      f.c.generate(sample);
      await f.c.save();
      final selected = f.c.design, id = f.c.currentProjectId;
      for (final d in f.c.concepts.take(3)) {
        f.c.toggleShortlist(d);
      }
      final favorites = f.c.shortlist.map((d) => jsonEncode(d.json)).toList();
      expect(f.c.isShortlisted(selected), isTrue);
      expect(
        () => f.c.toggleShortlist(f.c.concepts[3]),
        throwsA(isA<ImagineException>()),
      );
      f.c.generate(f.c.design, preserveSelection: true);
      expect(f.c.design, same(selected));
      expect(f.c.currentProjectId, id);
      expect(f.c.hasUnsavedChanges, isFalse);
      expect(f.c.shortlist.map((d) => jsonEncode(d.json)), favorites);
      f.c.toggleShortlist(selected);
      expect(f.c.isShortlisted(selected), isFalse);
      expect(f.c.shortlist, hasLength(2));
      expect(f.studio.requests, isEmpty);
    },
  );

  test(
    'new brand clears draft, concepts, favorites, AI artwork and undo only',
    () async {
      final f = LogoFixture();
      addTearDown(f.c.dispose);
      f.c.generate(sample);
      await f.c.save();
      f.c.toggleShortlist(f.c.design);
      f.c.update(f.c.design.copy(tagline: 'Unsaved edit'));
      f.c.images.results.add(
        ImagineResult(
          bytes: Uint8List.fromList([1, 2, 3]),
          brief: const ImagineBrief(prompt: 'Private prior brand'),
          id: 'old-ai-concept',
          width: 1,
          height: 1,
        ),
      );
      f.c.newBrand();
      expect(f.c.design.name, isEmpty);
      expect(f.c.currentProjectId, isNull);
      expect(f.c.hasUnsavedChanges, isFalse);
      expect(f.c.concepts, isEmpty);
      expect(f.c.shortlist, isEmpty);
      expect(f.c.images.results, isEmpty);
      expect(f.c.canUndo, isFalse);
      expect(f.c.canRedo, isFalse);
      expect(f.c.round, 0);
      expect(f.c.projects, hasLength(1));
    },
  );

  test(
    'new brand cannot discard a generation while its response is pending',
    () {
      final f = LogoFixture();
      addTearDown(f.c.dispose);
      f.c.generate(sample);
      f.c.images.busy = true;
      expect(f.c.newBrand, throwsA(isA<ImagineException>()));
      expect(f.c.design.name, sample.name);
      f.c.images.busy = false;
    },
  );

  test(
    'local operations catch account changes even without an auth notification',
    () async {
      final f = LogoFixture();
      addTearDown(f.c.dispose);
      f.c.generate(sample);
      f.c.toggleShortlist(f.c.design);
      await f.c.save();
      f.studio.token = imagine.auth('bob');
      expect(f.c.available, isFalse);
      expect(() => f.c.update(sample), throwsA(isA<ImagineException>()));
      expect(f.c.design.name, isEmpty);
      expect(f.c.projects, isEmpty);
      expect(f.c.shortlist, isEmpty);
      expect(f.c.currentProjectId, isNull);
      f.studio.token = imagine.auth('alice');
      expect(
        f.c.available,
        isFalse,
        reason: 'An invalidated studio cannot revive.',
      );
    },
  );

  test(
    'token refresh preserves the studio while a new login session is rejected',
    () {
      final f = LogoFixture();
      addTearDown(f.c.dispose);
      f.c.generate(sample);
      f.studio.token = sessionToken(expires: 999);
      expect(f.c.available, isTrue);
      f.c.update(f.c.design.copy(tagline: 'Still this session'));
      f.studio.token = sessionToken(session: 'new-login-session');
      expect(() => f.c.generate(sample), throwsA(isA<ImagineException>()));
      expect(f.c.available, isFalse);
      expect(f.c.design.name, isEmpty);
    },
  );

  test(
    'late reads and writes do not restore data after an unannounced account switch',
    () async {
      final reading = PendingStore();
      final f = LogoFixture(storage: reading);
      addTearDown(f.c.dispose);
      final loading = f.c.load();
      final loadFailure = expectLater(
        loading,
        throwsA(isA<ImagineException>()),
      );
      f.studio.token = imagine.auth('bob');
      reading.pending.complete([
        jsonEncode({'id': 'old', 'design': sample.json}),
      ]);
      await loadFailure;
      expect(f.c.projects, isEmpty);

      final store = BlockingLogoStore();
      final g = LogoFixture(storage: store);
      addTearDown(g.c.dispose);
      g.c.generate(sample);
      final saving = g.c.save();
      final saveFailure = expectLater(saving, throwsA(isA<ImagineException>()));
      await store.writing.future;
      g.studio.token = imagine.auth('bob');
      store.release.complete();
      await saveFailure;
      expect(g.c.projects, isEmpty);
      expect(g.c.currentProjectId, isNull);
      expect(g.c.design.name, isEmpty);
      expect(g.c.saving, isFalse);
    },
  );

  test(
    'deleting the active saved copy keeps the editable design as unsaved work',
    () async {
      final f = LogoFixture();
      addTearDown(f.c.dispose);
      f.c.generate(sample);
      await f.c.save();
      final id = f.c.currentProjectId!;
      await f.c.delete(id);
      expect(f.c.currentProjectId, isNull);
      expect(f.c.design.name, sample.name);
      expect(f.c.hasUnsavedChanges, isTrue);
      expect(() => f.c.openProject(id), throwsA(isA<ImagineException>()));
    },
  );
}
