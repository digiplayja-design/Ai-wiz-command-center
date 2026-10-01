import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pod_wake_lock_stub.dart'
    if (dart.library.js_interop) 'pod_wake_lock_web.dart'
    as platform;

PodWakeLock createPodWakeLock() =>
    PodWakeLock(backend: platform.createPodWakeLockBackend());

abstract class PodWakeLockBackend {
  bool get supported;
  Future<PodWakeLockLease> acquire();
}

abstract class PodWakeLockLease {
  bool get released;
  void onRelease(VoidCallback? callback);
  Future<void> release();
}

/// An advisory screen wake lock, scoped to a visible, actively playing pod.
/// Acquisition is optional: browser/OS refusal must never interrupt audio.
/// A late acquisition is released if listening stopped while it was pending.
class PodWakeLock extends ChangeNotifier {
  PodWakeLock({required this.backend});
  final PodWakeLockBackend backend;
  PodWakeLockLease? _lease;
  bool _closed = false, _requested = false, _pending = false;
  int _revision = 0;

  bool get supported => backend.supported;
  bool get requested => _requested;
  bool get pending => _pending;
  bool get active => _lease != null && !_lease!.released;

  Future<void> setRequested(bool requested, {bool retry = false}) async {
    if (_closed || (_requested == requested && !retry)) return;
    _requested = requested;
    final revision = ++_revision;
    final previous = _lease;
    _lease = null;
    previous?.onRelease(null);
    if (previous != null) unawaited(_release(previous));
    _pending = requested && supported;
    notifyListeners();
    if (!_pending) return;
    try {
      final lease = await backend.acquire();
      if (_closed || revision != _revision || !_requested) {
        await _release(lease);
        return;
      }
      if (!lease.released) {
        _lease = lease;
        lease.onRelease(() {
          if (_closed || !identical(_lease, lease)) return;
          lease.onRelease(null);
          _lease = null;
          // Do not fight an OS power-saving decision with repeated requests.
          // A later Listen/Resume gesture or explicit Retry may acquire again.
          notifyListeners();
        });
      }
    } catch (_) {
      // Unsupported browsers, power-saving mode and permission policy are all
      // normal fallbacks. The screen shows that protection is unavailable.
    } finally {
      if (!_closed && revision == _revision) {
        _pending = false;
        notifyListeners();
      }
    }
  }

  Future<void> _release(PodWakeLockLease lease) async {
    try {
      await lease.release();
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    ++_revision;
    final lease = _lease;
    _lease = null;
    lease?.onRelease(null);
    if (lease != null) unawaited(_release(lease));
    super.dispose();
  }
}
