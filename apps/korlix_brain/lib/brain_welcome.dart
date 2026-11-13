import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Local greeting audio. It never opens a microphone or contacts the backend.
class BrainWelcome {
  BrainWelcome({
    required this.canPlay,
    required this.onEvent,
    bool? nativePlayback,
    MethodChannel? channel,
  }) : nativePlayback =
           nativePlayback ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS),
       _channel = channel ?? const MethodChannel('com.korlix.brain/welcome') {
    if (this.nativePlayback) {
      _channelOwners[(_channel.binaryMessenger, _channel.name)] = this;
      _channel.setMethodCallHandler(_receive);
    }
  }

  static final _channelOwners = <(BinaryMessenger, String), BrainWelcome>{};
  static int _nextNativeToken = 0;
  final bool nativePlayback;
  final bool Function() canPlay;
  final void Function(Map<String, dynamic>) onEvent;
  final MethodChannel _channel;
  bool automaticPending = true;
  bool _disposed = false;
  int _generation = 0;
  int? _token;
  int? _nativeToken;
  Future<void> _stopping = Future<void>.value();
  Future<void>? _disposing;

  Future<Map<String, dynamic>> play(
    int token, {
    required bool automatic,
  }) async {
    if (_disposed || !canPlay() || (automatic && !automaticPending)) {
      return {'started': false};
    }
    if (!nativePlayback) return {'started': false};
    final generation = ++_generation;
    await _stopping;
    if (_disposed || generation != _generation || !canPlay()) {
      return {'started': false};
    }
    _token = token;
    // WebView request IDs restart when a workspace is replaced. Keep native
    // playback ownership distinct so an old asynchronous Stop cannot end a
    // new workspace's greeting with the same UI token.
    final nativeToken = ++_nextNativeToken;
    _nativeToken = nativeToken;
    final result = await _channel.invokeMapMethod<String, dynamic>('play', {
      'token': nativeToken,
    });
    if (_disposed || generation != _generation) return {'started': false};
    if (result?['started'] == true) {
      automaticPending = false;
      return {'started': true};
    }
    _token = null;
    _nativeToken = null;
    return {'started': false, 'retry': result?['retry'] == true};
  }

  void heard() => automaticPending = false;

  Future<void> stop({bool dismiss = true}) async {
    if (dismiss) automaticPending = false;
    ++_generation;
    final nativeToken = _nativeToken;
    _token = null;
    _nativeToken = null;
    // A second Stop (for microphone handoff) must wait for the first native
    // Stop to release AVAudioSession, even after the token has been cleared.
    _stopping = Future.wait<void>([
      _stopping,
      if (nativePlayback && nativeToken != null)
        _channel.invokeMethod<void>('stop', {'token': nativeToken}),
    ]).then((_) {});
    await _stopping;
  }

  Future<void> _receive(MethodCall call) async {
    if (_disposed || call.method != 'ended' || call.arguments is! Map) return;
    final data = Map<String, dynamic>.from(call.arguments as Map);
    if (data['token'] != _nativeToken || _token == null) return;
    final token = _token;
    _token = null;
    _nativeToken = null;
    onEvent({'type': 'welcomeEnded', ...data, 'token': token});
  }

  Future<void> dispose() {
    final pending = _disposing;
    if (pending != null) return pending;
    _disposed = true;
    final key = (_channel.binaryMessenger, _channel.name);
    if (nativePlayback && identical(_channelOwners[key], this)) {
      _channelOwners.remove(key);
      // Clear synchronously, before awaiting native audio cleanup. A new
      // workspace may install its handler while that cleanup is still pending.
      _channel.setMethodCallHandler(null);
    }
    return _disposing = stop(dismiss: false);
  }
}
