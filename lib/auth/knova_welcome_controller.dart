import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../sounds/korlix_sound_service.dart';
import 'knova_welcome_player.dart';

const knovaWelcomeText =
    "Welcome to KORLIX! I'm Rici, your AI voice companion. You'll find me in CRM, Workforce, Inventory, Bookkeeping, Music Studio, and more. Look for Rici or the voice button, tap to start, and tell me what you need. I can guide you, help you find things, and make everyday tasks easier. Let's explore!";

enum KnovaWelcomeState { ready, loading, speaking, blocked, unavailable, muted }

class KnovaWelcomeController extends ChangeNotifier {
  KnovaWelcomeController({
    required String backendBaseUrl,
    required this.sounds,
    KnovaWelcomePlayer? player,
    http.Client? client,
  }) : _url = Uri.parse('$backendBaseUrl/api/welcome/rici-v2.wav'),
       _player = player ?? createKnovaWelcomePlayer(),
       _client = client ?? http.Client() {
    sounds.addListener(_soundChanged);
  }
  final Uri _url;
  final KorlixSoundService sounds;
  final KnovaWelcomePlayer _player;
  final http.Client _client;
  Future<Uint8List?>? _clip;
  Future<bool>? _activation;
  Timer? _finish, _guard;
  int _epoch = 0;
  bool _disposed = false, _signedIn = false;
  bool visible = false;
  KnovaWelcomeState state = KnovaWelcomeState.ready;
  bool get active =>
      state == KnovaWelcomeState.loading || state == KnovaWelcomeState.speaking;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<Uint8List?> preload() => _clip ??= _fetch();
  Future<Uint8List?> _fetch() async {
    try {
      // Public fixed speech only. No session token, email or user content.
      final response = await _client
          .get(_url)
          .timeout(const Duration(seconds: 50));
      final bytes = response.bodyBytes;
      if (response.statusCode != 200 ||
          bytes.length < 48044 ||
          bytes.length > 1920044 ||
          String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
        throw const FormatException();
      }
      final header = ByteData.sublistView(bytes);
      if (header.getUint16(20, Endian.little) != 1 ||
          header.getUint16(22, Endian.little) != 1 ||
          header.getUint32(24, Endian.little) != 24000 ||
          header.getUint16(34, Endian.little) != 16 ||
          header.getUint32(40, Endian.little) != bytes.length - 44) {
        throw const FormatException();
      }
      return bytes;
    } catch (_) {
      _clip = null;
      return null;
    }
  }

  /// Called directly on the Sign in tap/keyboard stack, before any awaits.
  void prepareGesture() {
    if (_disposed || !sounds.canPlayWelcome) return;
    try {
      _activation = _player.activate().catchError((Object _) => false);
    } catch (_) {
      _activation = Future.value(false);
    }
    unawaited(preload());
  }

  /// AuthGate calls this only for a successful explicit sign-in, never refresh.
  Future<void> signedIn() async {
    if (_disposed || _signedIn) return;
    _signedIn = true;
    final epoch = ++_epoch;
    await sounds.restore();
    if (_disposed || epoch != _epoch || !sounds.settings.welcomeVoice) return;
    visible = true;
    await _start(epoch);
  }

  Future<void> listen() {
    if (_disposed || !_signedIn) return Future.value();
    stop();
    prepareGesture();
    return _start(_epoch);
  }

  Future<void> _start(int epoch) async {
    if (!sounds.canPlayWelcome) {
      state = KnovaWelcomeState.muted;
      _notify();
      return;
    }
    state = KnovaWelcomeState.loading;
    _notify();
    final activated = await (_activation ?? Future.sync(_player.activate))
        .catchError((Object _) => false)
        .timeout(const Duration(seconds: 2), onTimeout: () => false);
    if (_disposed || epoch != _epoch || !_signedIn) return;
    if (!activated) {
      state = KnovaWelcomeState.blocked;
      _notify();
      return;
    }
    final clip = await preload();
    if (_disposed || epoch != _epoch || !_signedIn) return;
    if (!sounds.canPlayWelcome) {
      stop();
      return;
    }
    if (clip == null) {
      state = KnovaWelcomeState.unavailable;
      _notify();
      return;
    }
    final duration = Duration(
      microseconds: ((clip.length - 44) / 48000 * 1000000).round(),
    );
    bool played;
    try {
      played = await _player.play(
        clip,
        volume: sounds.settings.volume,
        duration: duration,
      );
    } catch (_) {
      played = false;
    }
    if (_disposed || epoch != _epoch || !_signedIn) return;
    state = played ? KnovaWelcomeState.speaking : KnovaWelcomeState.blocked;
    if (played) {
      _finish = Timer(duration, stop);
      _guard = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!sounds.canPlayWelcome) stop();
      });
    }
    _notify();
  }

  void _soundChanged() {
    if (_disposed) return;
    if (!sounds.settings.welcomeVoice) {
      dismiss();
      return;
    }
    if (active && !sounds.canPlayWelcome) stop();
  }

  void stop() {
    if (_disposed) return;
    _epoch++;
    _finish?.cancel();
    _guard?.cancel();
    _player.stop();
    state = KnovaWelcomeState.ready;
    _notify();
  }

  void dismiss() {
    stop();
    visible = false;
    _notify();
  }

  void signedOut() {
    _signedIn = false;
    _activation = null;
    dismiss();
  }

  @override
  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    sounds.removeListener(_soundChanged);
    _client.close();
    _player.dispose();
    super.dispose();
  }
}
