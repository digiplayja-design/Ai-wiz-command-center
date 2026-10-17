import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../sounds/korlix_sound_service.dart';
import 'knova_welcome_player.dart';

const korlixEntryIntroAsset = 'assets/onboarding/welcome-business-v1.wav';
const korlixEntryIntroText =
    'Welcome to Korlix AI! Whether you’re working on a personal idea or building '
    'your business, there’s something here for you.\n\n'
    'Business owners—this is where it gets exciting. Explore tools to create '
    'compelling content, manage customer relationships, organize your team, '
    'and bring your next big idea to life.\n\n'
    'Create your free account and get started. Then explore our upgraded plans '
    'to discover more of what Korlix can bring to your business.\n\n'
    'We’re not just an app—we’re a hub. Let’s get to work!';

enum KorlixEntryIntroState {
  ready,
  loading,
  playing,
  unavailable,
  muted,
  blocked,
}

/// A fixed, bundled introduction. Never requests a microphone, session or AI job.
class KorlixEntryIntroController extends ChangeNotifier {
  KorlixEntryIntroController({
    KorlixSoundService? sounds,
    this._player,
    Future<Uint8List> Function()? loadClip,
  }) : _sounds = sounds ?? kKorlixSounds,
       _loadClip = loadClip ?? _loadBundledClip {
    _sounds.addListener(_soundChanged);
  }

  final KorlixSoundService _sounds;
  final Future<Uint8List> Function() _loadClip;
  KnovaWelcomePlayer? _player;
  Uint8List? _clip;
  Timer? _finish, _quietGuard;
  int _epoch = 0;
  bool _disposed = false;
  bool hasPlayed = false;
  KorlixEntryIntroState state = KorlixEntryIntroState.ready;

  bool get active =>
      state == KorlixEntryIntroState.loading ||
      state == KorlixEntryIntroState.playing;

  static Future<Uint8List> _loadBundledClip() async {
    final data = await rootBundle.load(korlixEntryIntroAsset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Duration clipDuration(Uint8List bytes) {
    if (bytes.length < 48044 || bytes.length > 4320044) {
      throw const FormatException('Invalid introduction length');
    }
    final header = ByteData.sublistView(bytes);
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 16)) != 'WAVEfmt ' ||
        String.fromCharCodes(bytes.sublist(36, 40)) != 'data' ||
        header.getUint32(16, Endian.little) != 16 ||
        header.getUint16(20, Endian.little) != 1 ||
        header.getUint16(22, Endian.little) != 1 ||
        header.getUint32(24, Endian.little) != 24000 ||
        header.getUint32(28, Endian.little) != 48000 ||
        header.getUint16(32, Endian.little) != 2 ||
        header.getUint16(34, Endian.little) != 16 ||
        header.getUint32(4, Endian.little) != bytes.length - 8 ||
        header.getUint32(40, Endian.little) != bytes.length - 44) {
      throw const FormatException('Invalid introduction audio');
    }
    return Duration(
      microseconds: ((bytes.length - 44) * 1000000 / 48000).round(),
    );
  }

  /// Invoke directly from a tap so browser playback can activate synchronously.
  Future<void> listen() async {
    if (_disposed || active) return;
    final epoch = ++_epoch;
    state = KorlixEntryIntroState.loading;
    notifyListeners();
    try {
      final player = _player ??= createKnovaWelcomePlayer();
      final activation = player
          .activate()
          .timeout(const Duration(seconds: 2), onTimeout: () => false)
          .catchError((Object _) => false);
      await _sounds.restore();
      final activated = await activation;
      if (_disposed || epoch != _epoch) return;
      if (!_sounds.canPlayWelcome) {
        _setState(KorlixEntryIntroState.muted);
        return;
      }
      if (!activated) {
        _setState(KorlixEntryIntroState.blocked);
        return;
      }
      final clip = _clip ??= await _loadClip().timeout(
        const Duration(seconds: 4),
      );
      if (_disposed || epoch != _epoch) return;
      if (!_sounds.canPlayWelcome) {
        _setState(KorlixEntryIntroState.muted);
        return;
      }
      final duration = clipDuration(clip);
      final played = await player.play(
        clip,
        volume: _sounds.settings.volume,
        duration: duration,
      );
      if (_disposed || epoch != _epoch) return;
      if (!_sounds.canPlayWelcome) {
        stop();
        _setState(KorlixEntryIntroState.muted);
        return;
      }
      if (!played) {
        _setState(KorlixEntryIntroState.blocked);
        return;
      }
      hasPlayed = true;
      _setState(KorlixEntryIntroState.playing);
      _finish = Timer(duration, stop);
      _quietGuard = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _soundChanged(),
      );
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        _player?.stop();
        _setState(KorlixEntryIntroState.unavailable);
      }
    }
  }

  void _setState(KorlixEntryIntroState value) {
    if (_disposed) return;
    state = value;
    notifyListeners();
  }

  void _soundChanged() {
    if (!_disposed && active && !_sounds.canPlayWelcome) {
      stop();
      _setState(KorlixEntryIntroState.muted);
    }
  }

  void stop() {
    if (_disposed) return;
    _epoch++;
    _finish?.cancel();
    _quietGuard?.cancel();
    _player?.stop();
    _setState(KorlixEntryIntroState.ready);
  }

  @override
  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    _sounds.removeListener(_soundChanged);
    _player?.dispose();
    super.dispose();
  }
}
