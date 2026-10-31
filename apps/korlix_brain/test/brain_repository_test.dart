import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_api.dart';
import 'package:korlix_brain/brain_auth.dart';
import 'package:korlix_brain/brain_repository.dart';

class FakeApi extends BrainApi {
  FakeApi() : super(BrainAuthController());
  String training = 'Keep answers short.\nAsk before assuming.';
  final stored = <Map<String, dynamic>>[];
  final writes = <Map<String, dynamic>>[];
  Completer<void>? gate;
  bool failWrites = false;
  int sequence = 0;
  Map<String, dynamic> get profile => {
    'trainingInstructions': training,
    'persistenceConfigured': true,
  };
  @override
  Future<Map<String, dynamic>> json(
    String method,
    String path, [
    Object? body,
  ]) async {
    if (method == 'GET') {
      return path.endsWith('/memories')
          ? {
              'memories': stored.map((m) => {...m}).toList(),
            }
          : {'agent': profile};
    }
    if (gate != null) await gate!.future;
    if (failWrites) throw const BrainApiException('Network unavailable.');
    final data = Map<String, dynamic>.from(body as Map);
    writes.add({'method': method, 'path': path, 'body': data});
    if (path.endsWith('/training') || method == 'PUT') {
      training = data['trainingInstructions'];
      return {'agent': profile};
    }
    if (method == 'DELETE') {
      stored.removeWhere((m) => path.endsWith('/${m['id']}'));
      return {'ok': true};
    }
    final memory = {...data, 'id': 'memory-${++sequence}'};
    stored.add(memory);
    return {'memory': memory};
  }

  @override
  void dispose() {
    auth.dispose();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeApi api;
  late BrainRepository repo;
  setUp(() {
    api = FakeApi();
    repo = BrainRepository(api);
  });
  tearDown(() => api.dispose());
  test('loading account state performs no writes', () async {
    await repo.load();
    expect(repo.training, api.training);
    expect(api.writes, isEmpty);
  });
  test('saving validates, confirms and avoids duplicate memories', () async {
    await expectLater(
      repo.saveMemory('', 'typed'),
      throwsA(isA<BrainApiException>()),
    );
    await repo.saveMemory('Office closes at 4.', 'typed');
    expect(api.writes, hasLength(1));
    expect(api.writes.single['body']['confirmed'], isTrue);
    expect(repo.memories.single['content'], 'Office closes at 4.');
    await expectLater(
      repo.saveMemory('office closes at 4.', 'typed'),
      throwsA(isA<BrainApiException>()),
    );
    expect(api.writes, hasLength(1));
  });
  test('failed saves never become local memories', () async {
    api.failWrites = true;
    await expectLater(
      repo.saveMemory('Unsaved draft', 'typed'),
      throwsA(isA<BrainApiException>()),
    );
    expect(repo.memories, isEmpty);
    expect(repo.snapshot['canUndo'], isFalse);
  });
  test('stale behavior edits are rejected before writes', () async {
    await repo.load();
    final original = repo.training;
    api.training = 'Changed elsewhere';
    await expectLater(
      repo.saveTraining('My draft', original),
      throwsA(isA<BrainApiException>()),
    );
    expect(api.writes, isEmpty);
    expect(api.training, 'Changed elsewhere');
  });
  test('deleting last behavior preserves memories; undo restores it', () async {
    api.training = 'Be concise';
    api.stored.add({'id': 'one', 'content': 'Remember me'});
    await repo.load();
    await repo.deleteBehavior(0, 'Be concise');
    expect(repo.training, '');
    expect(api.writes.single['method'], 'PUT');
    expect(repo.memories, hasLength(1));
    await repo.undo();
    expect(repo.training, 'Be concise');
    expect(repo.memories, hasLength(1));
  });
  test('selected memory deletion and undo preserve other items', () async {
    api.stored.addAll([
      {'id': 'one', 'content': 'First', 'kind': 'preference'},
      {'id': 'two', 'content': 'Second'},
    ]);
    await repo.load();
    final training = repo.training;
    await repo.deleteMemory('one', 'First');
    expect(repo.memories.single['id'], 'two');
    await repo.undo();
    expect(
      repo.memories.map((m) => m['content']),
      containsAll(['First', 'Second']),
    );
    expect(repo.training, training);
    expect(repo.snapshot['canUndo'], isFalse);
  });
  test('undo refuses to overwrite newer behavior changes', () async {
    await repo.load();
    await repo.saveTraining('New behavior', repo.training);
    api.training = 'A newer change';
    await expectLater(repo.undo(), throwsA(isA<BrainApiException>()));
    expect(api.training, 'A newer change');
  });
  test('overlapping writes are rejected during in-flight save', () async {
    api.gate = Completer<void>();
    final first = repo.saveMemory('First', 'typed');
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      repo.saveMemory('Second', 'typed'),
      throwsA(isA<BrainApiException>()),
    );
    api.gate!.complete();
    await first;
    expect(api.stored, hasLength(1));
  });
}
