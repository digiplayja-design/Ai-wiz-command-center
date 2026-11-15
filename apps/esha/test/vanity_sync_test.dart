import 'dart:async';

import 'package:esha_by_korlix/models.dart';
import 'package:esha_by_korlix/services/korlix_api.dart';
import 'package:esha_by_korlix/services/vanity_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

class Gateway implements VanityGateway {
  Future<VanityRecord> Function() load = () async => VanityRecord(Vanity(), 1);
  Future<VanityRecord> Function(Vanity, int) save = (state, version) async =>
      VanityRecord(state, version + 1);
  @override
  Future<VanityRecord> loadVanity() => load();
  @override
  Future<VanityRecord> saveVanity(Vanity state, int expectedVersion) =>
      save(state, expectedVersion);
}

Future<void> settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('late account A load cannot populate guest or account B', () async {
    final delayed = Completer<VanityRecord>();
    final gateway = Gateway()..load = () => delayed.future;
    final sync = VanitySync(gateway: gateway, storage: MemoryStore());
    final pending = sync.attach(accountA);
    await settle();
    await sync.attach(null);
    sync.update(Vanity(favorites: ['guest-only']));
    delayed.complete(VanityRecord(Vanity(favorites: ['private-A']), 9));
    await pending;
    expect(sync.userId, isNull);
    expect(sync.value.favorites, ['guest-only']);
    gateway.load = () async =>
        VanityRecord(Vanity(favorites: ['private-B']), 4);
    await sync.attach(accountB);
    expect(sync.value.favorites, ['private-B']);
    await sync.attach(null);
    expect(sync.value.favorites, ['guest-only']);
    sync.dispose();
  });
  test(
    'serialized saves advance confirmed version without losing newer edits',
    () async {
      final first = Completer<VanityRecord>();
      final requests = <({Vanity state, int version})>[];
      final gateway = Gateway()
        ..save = (state, version) {
          requests.add((state: state, version: version));
          return requests.length == 1
              ? first.future
              : Future.value(VanityRecord(state, version + 1));
        };
      final sync = VanitySync(gateway: gateway, storage: MemoryStore());
      await sync.attach(accountA);
      sync.update(Vanity(favorites: ['first']));
      await settle();
      sync.update(Vanity(favorites: ['first', 'newer']));
      first.complete(VanityRecord(requests.first.state, 2));
      await settle();
      expect(requests.map((r) => r.version), [1, 2]);
      expect(requests.last.state.favorites, ['first', 'newer']);
      expect(sync.value.favorites, ['first', 'newer']);
      expect(sync.confirmedVersion, 3);
      expect(sync.dirty, isFalse);
      sync.dispose();
    },
  );
  test('uncertain write is reconciled, not blindly duplicated', () async {
    Vanity? reachedServer;
    var writes = 0;
    final gateway = Gateway()
      ..save = (state, version) async {
        writes++;
        reachedServer = state;
        throw const EshaException('SYNC_UNCERTAIN', 'Response was lost.');
      };
    final sync = VanitySync(gateway: gateway, storage: MemoryStore());
    await sync.attach(accountA);
    sync.update(Vanity(favorites: ['saved-on-server']));
    await settle();
    expect(sync.status, SyncState.uncertain);
    gateway.load = () async => VanityRecord(reachedServer, 2);
    await sync.retry();
    expect(writes, 1);
    expect(sync.confirmedVersion, 2);
    expect(sync.status, SyncState.saved);
    expect(sync.dirty, isFalse);
    sync.dispose();
  });
  test(
    'conflicting remote version preserves draft until explicit resolution',
    () async {
      final gateway = Gateway()
        ..save = (_, _) async =>
            throw const EshaException('CONFLICT', 'Changed elsewhere.');
      final sync = VanitySync(gateway: gateway, storage: MemoryStore());
      await sync.attach(accountA);
      sync.update(Vanity(favorites: ['local-draft']));
      await settle();
      gateway.load = () async =>
          VanityRecord(Vanity(favorites: ['remote-change']), 7);
      await sync.retry();
      expect(sync.status, SyncState.conflict);
      expect(sync.value.favorites, ['local-draft']);
      await sync.loadAccountVersion();
      expect(sync.value.favorites, ['remote-change']);
      expect(sync.confirmedVersion, 7);
      sync.dispose();
    },
  );
}
