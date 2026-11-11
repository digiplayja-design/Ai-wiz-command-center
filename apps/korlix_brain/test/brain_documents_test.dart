import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korlix_brain/brain_api.dart';
import 'package:korlix_brain/brain_auth.dart';
import 'package:korlix_brain/brain_documents.dart';
import 'package:korlix_brain/brain_repository.dart';
import 'package:korlix_receipt_core/auth/korlix_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

String token() {
  String part(Object data) => base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'iss': 'https://auth.example.test', 'sub': 'brain-pdf-fixture', 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})}.fixture';
}

http.Response response(Object data, [int status = 200]) => http.Response(jsonEncode(data), status);

const memoryPreview = {
  'requiresApproval': true, 'autoSaved': false,
  'sourceRetention': {'storedByKorlix': false},
  'summary': 'Office procedures',
  'suggestions': [
    {
      'id': 'first-pdf-memory',
      'draft': {'content': 'The office closes at four.', 'kind': 'fact', 'label': 'Office hours', 'source': 'file_memory:abc', 'tags': ['file_memory'], 'sensitive': false},
      'provenance': {'fileName': 'office.pdf', 'page': '2'},
    },
    {
      'id': 'second-pdf-memory',
      'draft': {'content': 'Use the reception entrance.', 'kind': 'procedure', 'label': 'Entrance', 'source': 'file_memory:abc', 'sensitive': false},
      'provenance': {'fileName': 'office.pdf', 'page': '3'},
    },
  ],
};

const trainingPreview = {
  'requiresApproval': true, 'autoSaved': false,
  'sourceRetention': {'storedByKorlix': false},
  'summary': 'A new procedure',
  'trainingDraft': 'Ask which office the visitor needs.',
};

class Fixture {
  late BrainAuthController auth;
  late BrainApi api;
  late BrainRepository repository;
  late BrainDocuments documents;
  String training = 'Keep answers concise.';
  final rows = <Map<String, dynamic>>[];
  final analyses = <String>[];
  final uploads = <String>[];
  final writes = <Map<String, dynamic>>[];
  int failMemoryWrite = 0;
  bool failTrainingAnalysis = false;
  Completer<http.Response>? heldAnalysis;

  Future<void> initialize() async {
    auth = BrainAuthController(
      client: MockClient((_) async => response({'session': {'access_token': token(), 'refresh_token': 'pdf-fixture'}})),
      tokenStore: KorlixTokenStore(useSecureStorage: false, namespace: 'brain_pdf_test'),
    );
    await auth.authenticate(email: 'fixture@example.test', password: 'fixture-password');
    api = BrainApi(auth, client: MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/analyze')) {
        final kind = path.contains('/memory-files/') ? 'memory' : 'training';
        analyses.add(kind);
        uploads.add(request.body);
        if (heldAnalysis != null) return heldAnalysis!.future;
        if (kind == 'training' && failTrainingAnalysis) return response({'error': 'Training analysis unavailable'}, 503);
        return response(kind == 'memory' ? memoryPreview : trainingPreview);
      }
      if (request.method == 'GET') {
        return response(path.endsWith('/memories') ? {'memories': rows} : {'agent': {'trainingInstructions': training, 'persistenceConfigured': true}});
      }
      final data = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      if (path.endsWith('/training')) {
        writes.add(data);
        training = data['trainingInstructions'] as String;
        return response({'agent': {'trainingInstructions': training}});
      }
      if (path.endsWith('/memories')) {
        if (failMemoryWrite == writes.length + 1) return response({'error': 'Temporary save failure'}, 503);
        writes.add(data);
        final row = {'id': 'saved-${rows.length + 1}', ...data};
        rows.add(row);
        return response({'memory': row}, 201);
      }
      throw StateError('Unexpected fixture request: $path');
    }));
    repository = BrainRepository(api);
    documents = BrainDocuments(repository);
    addTearDown(() { documents.dispose(); api.dispose(); auth.dispose(); });
  }

  void choose(BrainDocumentDestination destination) => documents.choose(
    'office.pdf', Uint8List.fromList(utf8.encode('%PDF-1.7\nfixture')), destination,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('PDF Memory reads nested drafts and never saves during analysis', () async {
    final f = Fixture(); await f.initialize();
    f.choose(BrainDocumentDestination.memory);
    await f.documents.analyze();
    expect(f.documents.memories.map((m) => m.content), ['The office closes at four.', 'Use the reception entrance.']);
    expect(f.documents.memories.first.sourceLabel, 'office.pdf · Page 2');
    expect(f.documents.memories.every((m) => !m.selected && !m.saved), isTrue);
    expect(f.writes, isEmpty);
    expect(f.documents.hasFile, isFalse, reason: 'Discard PDF bytes after successful preview.');
  });

  test('Both saves only selected memories and preserves existing training', () async {
    final f = Fixture(); await f.initialize();
    f.choose(BrainDocumentDestination.both);
    await f.documents.analyze();
    f.documents.selectMemory(f.documents.memories.first, true);
    expect(f.documents.combinedTraining, 'Keep answers concise.\n\nAsk which office the visitor needs.');
    await f.documents.save(confirmed: true);
    expect(f.analyses, ['memory', 'training']);
    expect(f.rows, hasLength(1));
    expect(f.rows.single['kind'], 'fact');
    expect(f.rows.single['source'], 'file_memory:abc');
    expect(f.rows.single['memoryKey'], startsWith('brain_pdf:first-pdf-memory:'));
    expect(f.training, 'Keep answers concise.\n\nAsk which office the visitor needs.');
    expect(f.writes.every((row) => row['confirmed'] == true), isTrue);
    expect(f.documents.memories.last.saved, isFalse);
    expect(f.documents.trainingPublished, isTrue);
  });

  test('failed second analysis retains the first preview and retries only the failed destination', () async {
    final f = Fixture()..failTrainingAnalysis = true; await f.initialize();
    f.choose(BrainDocumentDestination.both);
    await f.documents.analyze();
    expect(f.documents.memories, hasLength(2));
    expect(f.documents.analysisErrors.keys, ['training']);
    expect(f.documents.trainingDraft, isEmpty);
    f.failTrainingAnalysis = false;
    await f.documents.analyze();
    expect(f.analyses, ['memory', 'training', 'training']);
    expect(f.documents.memories, hasLength(2));
    expect(f.documents.trainingDraft, isNotEmpty);
    expect(f.documents.analysisErrors, isEmpty);
  });

  test('explicit approval is required and no unselected draft is published', () async {
    final f = Fixture(); await f.initialize();
    f.choose(BrainDocumentDestination.memory);
    await f.documents.analyze();
    await expectLater(f.documents.save(confirmed: true), throwsA(isA<BrainApiException>()));
    f.documents.selectMemory(f.documents.memories.first, true);
    await expectLater(f.documents.save(confirmed: false), throwsA(isA<BrainApiException>()));
    expect(f.writes, isEmpty);
  });

  test('partial save exposes acknowledged items and retry skips them', () async {
    final f = Fixture()..failMemoryWrite = 2; await f.initialize();
    f.choose(BrainDocumentDestination.memory);
    await f.documents.analyze();
    for (final item in f.documents.memories) { f.documents.selectMemory(item, true); }
    await expectLater(f.documents.save(confirmed: true), throwsA(isA<BrainApiException>()));
    expect(f.documents.savedCount, 1);
    expect(f.repository.memories, hasLength(1));
    expect(f.documents.notice, contains('remain saved'));
    f.failMemoryWrite = 0;
    await f.documents.save(confirmed: true);
    expect(f.rows, hasLength(2));
    expect(f.writes, hasLength(2));
    expect(f.documents.savedCount, 2);
  });

  test('existing saved content is detected before retrying a memory', () async {
    final f = Fixture(); await f.initialize();
    f.choose(BrainDocumentDestination.memory);
    await f.documents.analyze();
    f.rows.add({'id': 'existing', 'content': f.documents.memories.first.content});
    f.documents.selectMemory(f.documents.memories.first, true);
    await f.documents.save(confirmed: true);
    expect(f.documents.memories.first.alreadySaved, isTrue);
    expect(f.writes, isEmpty);
  });

  test('changed training blocks every write in Both until the user reviews it again', () async {
    final f = Fixture(); await f.initialize();
    f.choose(BrainDocumentDestination.both);
    await f.documents.analyze();
    f.documents.selectMemory(f.documents.memories.first, true);
    f.training = 'New training from another app.';
    await expectLater(f.documents.save(confirmed: true), throwsA(isA<BrainApiException>()));
    expect(f.writes, isEmpty);
    await f.documents.refreshTraining();
    expect(f.documents.expectedTraining, f.training);
    await f.documents.save(confirmed: true);
    expect(f.training, 'New training from another app.\n\nAsk which office the visitor needs.');
  });

  test('oversized combined training is rejected without truncation or writes', () async {
    final f = Fixture()..training = List.filled(11990, 'a').join(); await f.initialize();
    f.choose(BrainDocumentDestination.training);
    await f.documents.analyze();
    await expectLater(f.documents.save(confirmed: true), throwsA(isA<BrainApiException>()));
    expect(f.writes, isEmpty);
    expect(f.training.length, 11990);
  });

  test('a late old-account PDF preview cannot be displayed or saved', () async {
    final f = Fixture(); await f.initialize();
    f.heldAnalysis = Completer<http.Response>();
    f.choose(BrainDocumentDestination.memory);
    final work = f.documents.analyze();
    final expectation = expectLater(work, throwsA(isA<BrainApiException>()));
    while (f.analyses.isEmpty) { await Future<void>.delayed(Duration.zero); }
    f.auth.revision++;
    f.heldAnalysis!.complete(response(memoryPreview));
    await expectation;
    expect(f.documents.memories, isEmpty);
    expect(f.writes, isEmpty);
  });

  test('sign-out immediately clears displayed knowledge and blocks further publishing', () async {
    final f = Fixture(); await f.initialize();
    f.choose(BrainDocumentDestination.both);
    await f.documents.analyze();
    expect(f.documents.hasPreview, isTrue);
    await f.auth.signOut();
    expect(f.documents.memories, isEmpty);
    expect(f.documents.trainingDraft, isEmpty);
    expect(f.documents.expectedTraining, isEmpty);
    expect(f.documents.filename, isNull);
    await expectLater(f.documents.save(confirmed: true), throwsA(isA<BrainApiException>()));
    expect(f.writes, isEmpty);
  });

  test('existing text formats stay supported and JSON is uploaded as a named text attachment', () async {
    for (final name in ['notes.txt', 'notes.md', 'contacts.csv', 'instructions.json']) {
      final f = Fixture(); await f.initialize();
      final text = name.endsWith('.json') ? '{"office":"Brooklyn"}' : 'office,city\nMain,Brooklyn';
      f.documents.choose(name, Uint8List.fromList(utf8.encode(text)), BrainDocumentDestination.memory);
      await f.documents.analyze();
      expect(f.documents.memories, hasLength(2));
      expect(f.uploads.single, contains('filename="${name.endsWith('.json') ? '$name.txt' : name}"'));
    }
    expect(() => BrainDocuments.validateFile('fake.docx', Uint8List.fromList(utf8.encode('fake'))), throwsA(isA<BrainApiException>()));
    expect(() => BrainDocuments.validateFile('bad.json', Uint8List.fromList(utf8.encode('{bad json}'))), throwsA(isA<BrainApiException>()));
  });

  test('a later import gets a new retry key so it cannot overwrite an edited prior import', () {
    final first = BrainDocumentMemory.fromJson((memoryPreview['suggestions'] as List).first as Map, 0);
    final second = BrainDocumentMemory.fromJson((memoryPreview['suggestions'] as List).first as Map, 0);
    expect(first.id, second.id);
    expect(first.submissionKey, isNot(second.submissionKey));
  });

  test('rejects disguised non-PDF bytes and files exceeding 10 MB', () {
    expect(() => BrainDocuments.validatePdf('bad.pdf', Uint8List.fromList(utf8.encode('not a PDF'))), throwsA(isA<BrainApiException>()));
    expect(() => BrainDocuments.validatePdf('big.pdf', Uint8List(10 * 1024 * 1024 + 1)), throwsA(isA<BrainApiException>()));
    expect(() => BrainDocuments.validatePdf('file.txt', Uint8List.fromList(utf8.encode('%PDF-1.7'))), throwsA(isA<BrainApiException>()));
  });
}
