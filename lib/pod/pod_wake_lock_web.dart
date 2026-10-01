import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'pod_wake_lock.dart';

PodWakeLockBackend createPodWakeLockBackend() => _WebWakeLock();

class _WebWakeLock implements PodWakeLockBackend {
  @override
  bool get supported =>
      web.window.isSecureContext &&
      web.window.navigator.hasProperty('wakeLock'.toJS).toDart;

  @override
  Future<PodWakeLockLease> acquire() async {
    if (!supported || web.document.visibilityState != 'visible') {
      throw StateError('A visible page is required for screen wake lock.');
    }
    return _WebWakeLockLease(
      await web.window.navigator.wakeLock.request('screen').toDart,
    );
  }
}

class _WebWakeLockLease implements PodWakeLockLease {
  _WebWakeLockLease(this.sentinel);
  final web.WakeLockSentinel sentinel;
  JSFunction? _listener;

  @override
  bool get released => sentinel.released;

  @override
  void onRelease(VoidCallback? callback) {
    if (_listener != null) sentinel.removeEventListener('release', _listener);
    _listener = callback == null ? null : ((web.Event _) => callback()).toJS;
    if (_listener != null) sentinel.addEventListener('release', _listener);
  }

  @override
  Future<void> release() async {
    onRelease(null);
    await sentinel.release().toDart;
  }
}
