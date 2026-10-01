import 'dart:async';

import 'package:ai_wiz_command_center/pod/pod_wake_lock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lease implements PodWakeLockLease {
  @override
  bool released = false;
  int releases = 0;
  VoidCallback? callback;
  @override
  void onRelease(VoidCallback? value) => callback = value;
  @override
  Future<void> release() async {
    releases++;
    released = true;
    callback?.call();
  }

  void revoke() {
    released = true;
    callback?.call();
  }
}

class _Backend implements PodWakeLockBackend {
  @override
  bool supported = true;
  int requests = 0;
  bool deny = false;
  Completer<PodWakeLockLease>? pending;
  final leases = <_Lease>[];
  @override
  Future<PodWakeLockLease> acquire() async {
    requests++;
    if (deny) throw StateError('Power saving');
    if (pending != null) return pending!.future;
    final lease = _Lease();
    leases.add(lease);
    return lease;
  }
}

void main() {
  test(
    'visible listening acquires once and pause releases the lease',
    () async {
      final backend = _Backend();
      final lock = PodWakeLock(backend: backend);
      await lock.setRequested(true);
      await lock.setRequested(true);
      expect(lock.active, isTrue);
      expect(backend.requests, 1);
      await lock.setRequested(false);
      expect(lock.active, isFalse);
      expect(backend.leases.single.releases, 1);
      await lock.setRequested(true);
      expect(backend.requests, 2);
      lock.dispose();
      expect(backend.leases.last.releases, 1);
    },
  );

  test(
    'late permission cannot keep the screen awake after pause or disposal',
    () async {
      for (final dispose in [false, true]) {
        final backend = _Backend()..pending = Completer<PodWakeLockLease>();
        final lock = PodWakeLock(backend: backend);
        final acquisition = lock.setRequested(true);
        expect(lock.pending, isTrue);
        if (dispose) {
          lock.dispose();
        } else {
          await lock.setRequested(false);
        }
        final lease = _Lease();
        backend.pending!.complete(lease);
        await acquisition;
        expect(lock.active, isFalse);
        expect(lease.releases, 1);
        if (!dispose) lock.dispose();
      }
    },
  );

  test('denied or unsupported wake lock never fails audio flow', () async {
    final denied = _Backend()..deny = true;
    final lock = PodWakeLock(backend: denied);
    await lock.setRequested(true);
    expect(lock.requested, isTrue);
    expect(lock.pending, isFalse);
    expect(lock.active, isFalse);
    await lock.setRequested(true);
    expect(denied.requests, 1);
    denied.deny = false;
    await lock.setRequested(true, retry: true);
    expect(lock.active, isTrue);
    lock.dispose();
    final unsupported = _Backend()..supported = false;
    final fallback = PodWakeLock(backend: unsupported);
    await fallback.setRequested(true);
    expect(unsupported.requests, 0);
    expect(fallback.active, isFalse);
    fallback.dispose();
  });

  test('OS revocation reports inactive and never retries by itself', () async {
    final backend = _Backend();
    final lock = PodWakeLock(backend: backend);
    var changes = 0;
    lock.addListener(() => changes++);
    await lock.setRequested(true);
    final before = changes;
    backend.leases.single.revoke();
    expect(lock.active, isFalse);
    expect(changes, greaterThan(before));
    expect(backend.requests, 1);
    await lock.setRequested(false);
    await lock.setRequested(true);
    expect(lock.active, isTrue);
    expect(backend.requests, 2);
    lock.dispose();
  });
}
