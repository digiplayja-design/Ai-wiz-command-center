enum KorlixSound { click, bell, message, success, warning, ringtone }

enum KorlixSoundPack { signature, classic, soft }

/// Preferences belong to this device, independently of the signed-in account.
class KorlixSoundSettings {
  const KorlixSoundSettings({
    this.enabled = true,
    this.clicks = true,
    this.messages = true,
    this.calls = true,
    this.bells = true,
    this.volume = .65,
    this.pack = KorlixSoundPack.signature,
    this.quietHours = false,
    this.quietStartMinute = 1320,
    this.quietEndMinute = 420,
  });

  final bool enabled, clicks, messages, calls, bells, quietHours;
  final double volume;
  final KorlixSoundPack pack;
  final int quietStartMinute, quietEndMinute;

  KorlixSoundSettings copyWith({
    bool? enabled,
    bool? clicks,
    bool? messages,
    bool? calls,
    bool? bells,
    double? volume,
    KorlixSoundPack? pack,
    bool? quietHours,
    int? quietStartMinute,
    int? quietEndMinute,
  }) => KorlixSoundSettings(
    enabled: enabled ?? this.enabled,
    clicks: clicks ?? this.clicks,
    messages: messages ?? this.messages,
    calls: calls ?? this.calls,
    bells: bells ?? this.bells,
    volume: (volume ?? this.volume).clamp(0, 1).toDouble(),
    pack: pack ?? this.pack,
    quietHours: quietHours ?? this.quietHours,
    quietStartMinute: (quietStartMinute ?? this.quietStartMinute).clamp(
      0,
      1439,
    ),
    quietEndMinute: (quietEndMinute ?? this.quietEndMinute).clamp(0, 1439),
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'enabled': enabled,
    'clicks': clicks,
    'messages': messages,
    'calls': calls,
    'bells': bells,
    'volume': volume,
    'pack': pack.name,
    'quietHours': quietHours,
    'quietStartMinute': quietStartMinute,
    'quietEndMinute': quietEndMinute,
  };

  factory KorlixSoundSettings.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported sound settings version');
    }
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    int minute(String key, int fallback) =>
        json[key] is int ? (json[key] as int).clamp(0, 1439) : fallback;
    final volume = json['volume'];
    return KorlixSoundSettings(
      enabled: flag('enabled', true),
      clicks: flag('clicks', true),
      messages: flag('messages', true),
      calls: flag('calls', true),
      bells: flag('bells', true),
      volume: volume is num && volume.isFinite
          ? volume.toDouble().clamp(0, 1)
          : .65,
      pack: KorlixSoundPack.values.firstWhere(
        (p) => p.name == json['pack'],
        orElse: () => KorlixSoundPack.signature,
      ),
      quietHours: flag('quietHours', false),
      quietStartMinute: minute('quietStartMinute', 1320),
      quietEndMinute: minute('quietEndMinute', 420),
    );
  }

  bool isQuietAt(DateTime localTime) {
    if (!quietHours) return false;
    final minute = localTime.hour * 60 + localTime.minute;
    if (quietStartMinute == quietEndMinute) return true;
    if (quietStartMinute < quietEndMinute) {
      return minute >= quietStartMinute && minute < quietEndMinute;
    }
    return minute >= quietStartMinute || minute < quietEndMinute;
  }
}
