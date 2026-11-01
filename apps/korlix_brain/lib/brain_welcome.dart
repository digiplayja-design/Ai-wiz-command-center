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
    if (this.nativePlayback) _channel.setMethodCallHandler(_receive);
  }

  final bool nativePlayback;
  final bool Function() canPlay;
  final void Function(Map<String, dynamic>) onEvent;
  final MethodChannel _channel;
  bool automaticPending = true;
  bool _disposed = false;
  int _generation = 0;
  int? _token;
  Future<void> _stopping = Future<void>.value();

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
    final result = await _channel.invokeMapMethod<String, dynamic>('play', {
      'token': token,
    });
    if (_disposed || generation != _generation) return {'started': false};
    if (result?['started'] == true) {
      automaticPending = false;
      return {'started': true};
    }
    _token = null;
    return {'started': false, 'retry': result?['retry'] == true};
  }

  void heard() => automaticPending = false;

  Future<void> stop({bool dismiss = true}) async {
    if (dismiss) automaticPending = false;
    ++_generation;
    final token = _token;
    _token = null;
    // A second Stop (for microphone handoff) must wait for the first native
    // Stop to release AVAudioSession, even after the token has been cleared.
    _stopping = Future.wait<void>([
      _stopping,
      if (nativePlayback && token != null)
        _channel.invokeMethod<void>('stop', {'token': token}),
    ]).then((_) {});
    await _stopping;
  }

  Future<void> _receive(MethodCall call) async {
    if (_disposed || call.method != 'ended' || call.arguments is! Map) return;
    final data = Map<String, dynamic>.from(call.arguments as Map);
    if (data['token'] != _token) return;
    _token = null;
    onEvent({'type': 'welcomeEnded', ...data});
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      await stop(dismiss: false);
    } finally {
      if (nativePlayback) _channel.setMethodCallHandler(null);
    }
  }
}
