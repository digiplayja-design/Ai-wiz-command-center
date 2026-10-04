import 'dart:typed_data';
import '../sounds/korlix_sound_player_web.dart' as audio;
import 'knova_welcome_player.dart';

KnovaWelcomePlayer createKnovaWelcomePlayer() => _WelcomeWebPlayer();

class _WelcomeWebPlayer implements KnovaWelcomePlayer {
  final _player = audio.createKorlixSoundPlayer();
  @override
  Future<bool> activate() => _player.activate();
  @override
  Future<bool> play(
    Uint8List wav, {
    required double volume,
    required Duration duration,
  }) =>
      _player.play(wav, volume: volume, duration: duration, channel: 'welcome');
  @override
  void stop() => _player.stop('welcome');
  @override
  void dispose() => _player.dispose();
}
