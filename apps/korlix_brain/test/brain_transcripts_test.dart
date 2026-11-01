import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_transcripts.dart';

class MemoryVault implements BrainTranscriptStorage {
  final values = <String, String>{};
  bool failWrite = false;
  Completer<void>? readGate;
  @override
  Future<String?> read(String owner) async {
    await readGate?.future;
    return values[owner];
  }

  @override
  Future<void> write(String owner, String value) async {
    if (failWrite) throw StateError('locked');
    values[owner] = value;
  }

  @override
  Future<void> delete(String owner) async {
    values.remove(owner);
  }
}

void main() {
  late MemoryVault vault;
  BrainTranscripts store([
    String owner = 'account-a',
    bool Function()? current,
  ]) => BrainTranscripts(
    owner: owner,
    storage: vault,
    isCurrent: current ?? () => true,
  );
  setUp(() {
    vault = MemoryVault();
  });

  test(
    'only explicit saves survive restart; accounts remain separate',
    () async {
      final first = store();
      final saved = first.receive('you', 'My private note.')!;
      final unsaved = first.receive('rici', 'An unsaved answer.')!;
      expect(vault.values, isEmpty);
      await first.save(saved.id);
      expect((await store().listSaved()).single['text'], 'My private note.');
      await expectLater(
        store().get(unsaved.id),
        throwsA(isA<BrainTranscriptException>()),
      );
      expect(await store('account-b').listSaved(), isEmpty);
      await expectLater(
        store('account-b').get(saved.id),
        throwsA(isA<BrainTranscriptException>()),
      );
    },
  );

  test(
    'concurrent and repeated saves neither lose nor duplicate messages',
    () async {
      final s = store();
      final a = s.receive('you', 'Same content')!,
          b = s.receive('rici', 'Same content')!;
      await Future.wait([s.save(a.id), s.save(b.id), s.save(a.id)]);
      expect((await store().listSaved()).map((e) => e['id']).toSet(), {
        a.id,
        b.id,
      });
      await s.delete(a.id);
      expect((await store().listSaved()).single['id'], b.id);
      await expectLater(s.get(a.id), throwsA(isA<BrainTranscriptException>()));
      expect((await s.get(b.id)).shareText, contains('Rici'));
      expect((await s.get(b.id)).shareText, endsWith('Same content'));
    },
  );

  test(
    'failed save and delete never claim success or erase existing content',
    () async {
      final s = store();
      final a = s.receive('you', 'Keep me')!,
          b = s.receive('rici', 'Retry me')!;
      await s.save(a.id);
      vault.failWrite = true;
      await expectLater(s.save(b.id), throwsA(isA<BrainTranscriptException>()));
      await expectLater(
        s.delete(a.id),
        throwsA(isA<BrainTranscriptException>()),
      );
      expect((await s.listSaved()).single['id'], a.id);
      expect((await s.get(a.id)).text, 'Keep me');
      vault.failWrite = false;
      await s.save(b.id);
      expect((await store().listSaved()).length, 2);
    },
  );

  test(
    'account change during storage read blocks stale results and writes',
    () async {
      var current = true;
      final s = store('account-a', () => current);
      final a = s.receive('you', 'Do not leak')!;
      vault.readGate = Completer<void>();
      final future = s.save(a.id);
      await Future<void>.delayed(Duration.zero);
      current = false;
      vault.readGate!.complete();
      await expectLater(future, throwsA(isA<BrainTranscriptException>()));
      expect(vault.values, isEmpty);
    },
  );

  test('corrupt archive fails closed without overwriting saved data', () async {
    vault.values['account-a'] = '{broken';
    final s = store();
    final a = s.receive('you', 'New note')!;
    await expectLater(s.save(a.id), throwsA(isA<BrainTranscriptException>()));
    expect(vault.values['account-a'], '{broken');
  });

  test(
    'full archive refuses new saves without silently evicting old ones',
    () async {
      final s = store();
      for (var i = 0; i < BrainTranscripts.maxSaved; i++) {
        await s.save(s.receive('you', 'Message $i')!.id);
      }
      await expectLater(
        s.save(s.receive('rici', 'One too many')!.id),
        throwsA(isA<BrainTranscriptException>()),
      );
      final saved = await store().listSaved();
      expect(saved.length, BrainTranscripts.maxSaved);
      expect(saved.last['text'], 'Message 0');
    },
  );

  test(
    'saved message remains shareable after live window rolls over',
    () async {
      final s = store();
      final a = s.receive('you', 'Keep exact\n<img src=x>')!;
      await s.save(a.id);
      for (var i = 0; i < 70; i++) {
        s.receive('rici', '$i');
      }
      expect((await s.get(a.id)).text, a.text);
      await s.clear();
      expect(await store().listSaved(), isEmpty);
      expect(vault.values, isEmpty);
    },
  );

  test('owner survives token refresh and new sessions but isolates issuers', () {
    String token(String issuer, String subject, String session) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({'iss': issuer, 'sub': subject, 'session_id': session})))}.signature';
    expect(
      brainTranscriptOwner(token('issuer', 'user', 'one')),
      brainTranscriptOwner(token('issuer', 'user', 'two')),
    );
    expect(
      brainTranscriptOwner(token('issuer', 'user', 'one')),
      isNot(brainTranscriptOwner(token('other', 'user', 'one'))),
    );
    expect(
      () => brainTranscriptOwner('invalid'),
      throwsA(isA<BrainTranscriptException>()),
    );
  });
}
