import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Only a call explicitly started in the foreground may acquire this lease.
/// Old app builds and missing/failed native services return false safely.
class SocialCallBackground {
  SocialCallBackground({this.kind = 'social'})
    : assert(kind == 'social' || kind == 'rici');
  final String kind;
  static const _channel = MethodChannel('korlix/social_call_background');
  static final _owners = <String, VoidCallback>{};
  static bool _listening = false;
  bool ready = false;
  String? _id;
  Completer<bool>? _pending;
  Timer? _deadline;
  VoidCallback? onStopped;
  bool get starting => _pending != null;

  /// A lifecycle transition may arrive before native service startup completes.
  Future<bool> waitUntilReady() async {
    final pending = _pending;
    if (pending != null) await pending.future;
    return ready;
  }

  Future<bool> start(String id) async {
    if (_id == id && ready) return true;
    if (_id == id && _pending != null) return waitUntilReady();
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      return false;
    }
    _id = id;
    _owners[id] = () {
      ready = false;
      onStopped?.call();
    };
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'stopped' && call.arguments is Map) {
          _owners[call.arguments['id']]?.call();
        }
      });
    }
    try {
      final pending = Completer<bool>();
      _pending = pending;
      _deadline = Timer(const Duration(seconds: 8), () {
        if (!pending.isCompleted) pending.complete(false);
      });
      unawaited(
        _channel
            .invokeMethod<bool>('start', {'id': id, 'kind': kind})
            .then((value) {
              if (!pending.isCompleted) pending.complete(value == true);
            })
            .catchError((Object _) {
              if (!pending.isCompleted) pending.complete(false);
            }),
      );
      final started = await pending.future;
      _deadline?.cancel();
      _pending = null;
      if (_id != id) {
        unawaited(
          _channel
              .invokeMethod<void>('stop', {'id': id})
              .catchError((Object _) {}),
        );
        return false;
      }
      ready = started;
      if (!started) {
        _owners.remove(id);
        unawaited(
          _channel
              .invokeMethod<void>('stop', {'id': id})
              .catchError((Object _) {}),
        );
      }
      return started;
    } catch (_) {
      ready = false;
      try {
        await _channel.invokeMethod<void>('stop', {'id': id});
      } catch (_) {}
      return false;
    }
  }

  Future<void> stop() async {
    final id = _id;
    _id = null;
    ready = false;
    _deadline?.cancel();
    if (_pending?.isCompleted == false) _pending!.complete(false);
    if (id == null) return;
    _owners.remove(id);
    try {
      await _channel.invokeMethod<void>('stop', {'id': id});
    } catch (_) {}
  }
}
