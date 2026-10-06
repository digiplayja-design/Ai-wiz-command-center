import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'korlix_sound_player.dart';
import 'korlix_sound_settings.dart';
import 'korlix_sound_tones.dart';

export 'korlix_sound_settings.dart';

/// Storage is injectable so failures and competing loads/writes can be tested.
abstract class KorlixSoundStore {
  Future<String?> read();
  Future<bool> write(String value);
}

class _PreferenceStore implements KorlixSoundStore {
  static const key = 'korlix.sounds.v1';
  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<bool> write(String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}

/// Construction does not touch platform plugins or request audio permission.
final kKorlixSounds = KorlixSoundService();

class KorlixSoundService extends ChangeNotifier {
  KorlixSoundService({
    KorlixSoundPlayer? player,
    KorlixSoundStore? store,
    DateTime Function()? now,
  }) : _player = player ?? createKorlixSoundPlayer(),
       _store = store ?? _PreferenceStore(),
       _now = now ?? DateTime.now;

  final KorlixSoundPlayer _player;
  final KorlixSoundStore _store;
  final DateTime Function() _now;
  KorlixSoundSettings _settings = const KorlixSoundSettings();
  bool _disposed = false, _foreground = true, _blocked = false;
  String? _storageError;
  int _settingsRevision = 0, _epoch = 0, _previewRevision = 0;
  Future<void>? _restore;
  Future<void> _writes = Future<void>.value();
  final _quietOwners = <Object>{};
  final _rings = <Object, _Ring>{};
  final _callDeadlines = <String, DateTime>{};
  final _silencedCalls = <String>{};
  final _events = <String, DateTime>{};
  final _lastPlayed = <KorlixSound, DateTime>{};
  Timer? _ringTimer, _previewTimer;
  String? _ringIdentity;

  KorlixSoundSettings get settings => _settings;
  bool get ready => !_disposed && _player.ready;
  bool get blocked => _blocked;
  bool get quiet => _quietOwners.isNotEmpty;
  bool get canPlayWelcome =>
      !_disposed &&
      _foreground &&
      _settings.enabled &&
      _settings.welcomeVoice &&
      _settings.volume > 0 &&
      !quiet &&
      _rings.isEmpty &&
      !_settings.isQuietAt(_now());
  String? get storageError => _storageError;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restore() => _restore ??= _restoreSettings();

  Future<void> _restoreSettings() async {
    final revision = _settingsRevision;
    try {
      final value = await _store.read();
      if (_disposed || revision != _settingsRevision) return;
      if (value != null) {
        final json = jsonDecode(value);
        if (json is! Map<String, dynamic>) {
          throw const FormatException('Invalid sound settings');
        }
        _settings = KorlixSoundSettings.fromJson(json);
      }
      _storageError = null;
      _enforceSettings();
    } catch (_) {
      if (_disposed || revision != _settingsRevision) return;
      _storageError = 'Saved sound settings could not be read. Choose your preferences again.';
    }
    _notify();
  }

  Future<bool> update(KorlixSoundSettings value) {
    if (_disposed) return Future<bool>.value(false);
    final revision = ++_settingsRevision;
    _settings = value.copyWith();
    _storageError = null;
    _enforceSettings();
    _notify();
    final encoded = jsonEncode(_settings.toJson());
    final result = Completer<bool>();
    // The newest record must land last, even when a prior platform write stalls.
    _writes = _writes.then((_) async {
      var saved = false;
      try {
        saved = await _store.write(encoded);
      } catch (_) {}
      if (!_disposed && revision == _settingsRevision) {
        _storageError = saved
            ? null
            : 'Sound changes work now, but could not be saved on this device.';
        _notify();
      }
      result.complete(saved);
    });
    return result.future;
  }

  Future<bool> activate() {
    if (_disposed || !_foreground || _quietOwners.isNotEmpty) {
      return Future<bool>.value(false);
    }
    final epoch = _epoch;
    // Do not await storage before this call: browsers require the tap gesture.
    Future<bool> activation;
    try {
      activation = _player.activate();
    } catch (_) {
      _blocked = true;
      _notify();
      return Future<bool>.value(false);
    }
    return activation.then(
      (ok) {
        if (_disposed || epoch != _epoch) return false;
        _blocked = !ok;
        _notify();
        return ok;
      },
      onError: (Object _) {
        if (!_disposed && epoch == _epoch) {
          _blocked = true;
          _notify();
        }
        return false;
      },
    );
  }

  bool get _audible =>
      !_disposed &&
      _foreground &&
      ready &&
      _settings.enabled &&
      _settings.volume > 0 &&
      _quietOwners.isEmpty &&
      !_settings.isQuietAt(_now());

  bool _category(KorlixSound sound) => switch (sound) {
    KorlixSound.click || KorlixSound.orbitBreeze => _settings.clicks,
    KorlixSound.message => _settings.messages,
    KorlixSound.ringtone => _settings.calls,
    _ => _settings.bells,
  };

  Future<void> play(KorlixSound sound, {String? eventId}) async {
    if (_disposed) return;
    final now = _now();
    _prune(now);
    if (eventId != null) {
      final key = '${sound.name}:$eventId';
      if (_events.containsKey(key)) return;
      _events[key] = now;
    }
    if (!_audible || !_category(sound) || _ringIdentity != null) return;
    final cooldown = switch (sound) {
      KorlixSound.click => const Duration(milliseconds: 80),
      KorlixSound.orbitBreeze => const Duration(milliseconds: 420),
      KorlixSound.message => const Duration(milliseconds: 900),
      _ => const Duration(milliseconds: 350),
    };
    final last = _lastPlayed[sound];
    if (last != null && now.difference(last) < cooldown) return;
    _lastPlayed[sound] = now;
    final epoch = _epoch;
    try {
      final ok = await _player.play(
        korlixSoundWav(sound, _settings.pack),
        volume: _volume(sound),
        duration: korlixSoundDuration(sound),
        channel: 'effect',
      );
      if (!_disposed && epoch == _epoch && !ok) {
        _blocked = true;
        _notify();
      }
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        _blocked = true;
        _notify();
      }
    }
  }

  double _volume(KorlixSound sound) =>
      _settings.volume *
      switch (sound) {
        KorlixSound.click => .25,
        KorlixSound.orbitBreeze => .0175,
        _ => 1.0,
      };

  Future<void> preview(KorlixSound sound) async {
    if (!_audible || _ringIdentity != null) return;
    final revision = ++_previewRevision;
    final epoch = _epoch;
    _previewTimer?.cancel();
    _previewTimer = null;
    _player.stop('preview');
    final duration = sound == KorlixSound.ringtone
        ? const Duration(seconds: 3)
        : korlixSoundDuration(sound);
    void stopPreview() {
      if (_previewRevision != revision) return;
      _previewRevision++;
      _player.stop('preview');
    }

    // Rings retain an absolute preview limit. A brief one-shot receives its
    // full duration after the player has finished bounded preparation.
    if (sound == KorlixSound.ringtone) {
      _previewTimer = Timer(duration, stopPreview);
    }
    var played = false;
    try {
      played = await _player.play(
        korlixSoundWav(sound, _settings.pack),
        volume: _volume(sound),
        duration: duration,
        channel: 'preview',
        loop: sound == KorlixSound.ringtone,
      );
    } catch (_) {}
    if (!_disposed &&
        epoch == _epoch &&
        revision == _previewRevision &&
        played &&
        sound != KorlixSound.ringtone) {
      _previewTimer = Timer(duration, stopPreview);
    }
    if (!_disposed &&
        epoch == _epoch &&
        revision == _previewRevision &&
        _ringIdentity == null &&
        !played) {
      _previewTimer?.cancel();
      _player.stop('preview');
      _blocked = true;
      _notify();
    }
  }

  void setForeground(bool value) {
    if (_disposed || _foreground == value) return;
    _foreground = value;
    if (!value) _silence();
    _syncRing();
    _notify();
  }

  void setQuiet(Object owner, bool active) {
    if (_disposed) return;
    final changed = active
        ? _quietOwners.add(owner)
        : _quietOwners.remove(owner);
    if (!changed) return;
    if (active) _silence();
    _syncRing();
    _notify();
  }

  void setRinging(
    Object owner,
    bool ringing, {
    String? callId,
    DateTime? expiresAt,
    bool outgoing = false,
  }) {
    if (_disposed) return;
    if (!ringing) {
      _rings.remove(owner);
      _syncRing();
      _notify();
      return;
    }
    final now = _now();
    _prune(now);
    final id = callId ?? 'owner:${identityHashCode(owner)}';
    final fallback = now.add(const Duration(seconds: 45));
    var end = expiresAt == null || expiresAt.isAfter(fallback)
        ? fallback
        : expiresAt;
    final original = _callDeadlines[id];
    if (original != null && original.isBefore(end)) end = original;
    _callDeadlines[id] = end;
    final prior = _rings[owner];
    final allowed = _audible && _settings.calls && !_silencedCalls.contains(id);
    _rings[owner] = _Ring(
      id,
      end,
      outgoing,
      prior != null && prior.id == id ? prior.audible && allowed : allowed,
    );
    if (!allowed) _silencedCalls.add(id);
    _syncRing();
    _notify();
  }

  void _syncRing() {
    _ringTimer?.cancel();
    _ringTimer = null;
    if (_disposed) return;
    final now = _now();
    _rings.removeWhere((_, ring) => !ring.end.isAfter(now));
    final candidates = _rings.values.where((ring) => ring.audible).toList()
      ..sort((a, b) => (a.outgoing ? 1 : 0).compareTo(b.outgoing ? 1 : 0));
    final ring = _audible && _settings.calls && candidates.isNotEmpty
        ? candidates.first
        : null;
    final identity = ring == null ? null : '${ring.id}:${ring.outgoing}';
    if (identity != _ringIdentity) {
      _player.stop('ring');
      _ringIdentity = identity;
      if (ring != null) {
        _player.stop('effect');
        _previewRevision++;
        _player.stop('preview');
        unawaited(_playRing(ring));
      }
    }
    if (ring != null) {
      // Recheck quiet hours at each local minute boundary and on expiry.
      final minuteBoundary = Duration(
        milliseconds: 60000 - now.second * 1000 - now.millisecond,
      );
      final remaining = ring.end.difference(now);
      final delay = remaining < minuteBoundary ? remaining : minuteBoundary;
      _ringTimer = Timer(delay, () {
        if (!_audible || !_settings.calls) _silence();
        _syncRing();
      });
    }
  }

  Future<void> _playRing(_Ring ring) async {
    final epoch = _epoch;
    try {
      final ok = await _player.play(
        korlixSoundWav(
          KorlixSound.ringtone,
          _settings.pack,
          outgoing: ring.outgoing,
        ),
        volume: _settings.volume,
        duration: ring.end.difference(_now()),
        channel: 'ring',
        loop: true,
      );
      if (!ok &&
          !_disposed &&
          epoch == _epoch &&
          _ringIdentity == '${ring.id}:${ring.outgoing}') {
        _blocked = true;
        _silence();
        _notify();
      }
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        _blocked = true;
        _silence();
        _notify();
      }
    }
  }

  void _enforceSettings() {
    if (!_audible || !_settings.calls) {
      _silence();
    } else {
      _player.stop('effect');
      _previewRevision++;
      _player.stop('preview');
      // Apply changed pack/volume immediately to a currently audible call.
      _ringIdentity = null;
      _player.stop('ring');
    }
    _syncRing();
  }

  void _silence() {
    _epoch++;
    _previewRevision++;
    for (final ring in _rings.values) {
      ring.audible = false;
      _silencedCalls.add(ring.id);
    }
    _ringIdentity = null;
    _ringTimer?.cancel();
    _previewTimer?.cancel();
    _player.stopAll();
  }

  void _prune(DateTime now) {
    _events.removeWhere(
      (_, date) => now.difference(date) > const Duration(minutes: 10),
    );
    while (_events.length > 512) {
      _events.remove(_events.keys.first);
    }
    _callDeadlines.removeWhere((id, end) {
      final old = now.difference(end) > const Duration(minutes: 10);
      if (old) _silencedCalls.remove(id);
      return old;
    });
  }

  /// Drop prior-account events and callers; device preferences remain intact.
  /// Microphone/media leases survive until their owners finish tearing down.
  void clearSession() {
    if (_disposed) return;
    _silence();
    _rings.clear();
    _callDeadlines.clear();
    _silencedCalls.clear();
    _events.clear();
    _lastPlayed.clear();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _silence();
    _disposed = true;
    _player.dispose();
    super.dispose();
  }
}

class _Ring {
  _Ring(this.id, this.end, this.outgoing, this.audible);
  final String id;
  final DateTime end;
  final bool outgoing;
  bool audible;
}
