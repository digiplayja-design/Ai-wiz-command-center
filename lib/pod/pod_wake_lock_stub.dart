import 'pod_wake_lock.dart';

PodWakeLockBackend createPodWakeLockBackend() => _UnsupportedWakeLock();

class _UnsupportedWakeLock implements PodWakeLockBackend {
  @override
  bool get supported => false;

  @override
  Future<PodWakeLockLease> acquire() =>
      Future.error(UnsupportedError('Screen wake lock is unavailable.'));
}
