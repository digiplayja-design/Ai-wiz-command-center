import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// Local eligibility only: this deliberately never records a rating or sentiment.
class ReviewActivityProgress {
  ReviewActivityProgress({
    int activeMilliseconds = 0,
    this.automaticPromptHandled = false,
    this.suppressed = false,
  }) : activeMilliseconds = activeMilliseconds
           .clamp(0, thresholdMilliseconds)
           .toInt();

  static const threshold = Duration(hours: 3);
  static const thresholdMilliseconds = 10800000;

  final int activeMilliseconds;
  final bool automaticPromptHandled;
  final bool suppressed;

  bool get eligible =>
      activeMilliseconds >= thresholdMilliseconds &&
      !automaticPromptHandled &&
      !suppressed;

  ReviewActivityProgress copyWith({
    int? activeMilliseconds,
    bool? automaticPromptHandled,
    bool? suppressed,
  }) => ReviewActivityProgress(
    activeMilliseconds: activeMilliseconds ?? this.activeMilliseconds,
    automaticPromptHandled:
        automaticPromptHandled ?? this.automaticPromptHandled,
    suppressed: suppressed ?? this.suppressed,
  );

  Map<String, Object> toJson() => {
    'version': 1,
    'active_ms': activeMilliseconds,
    'automatic_prompt_handled': automaticPromptHandled,
    'suppressed': suppressed,
  };

  /// Invalid time cannot manufacture eligibility. Previously stored true flags
  /// remain true even when the accumulated time is corrupt.
  factory ReviewActivityProgress.fromJson(Object? value) {
    if (value is! Map || value['version'] != 1) {
      return ReviewActivityProgress();
    }
    final active = value['active_ms'];
    return ReviewActivityProgress(
      activeMilliseconds:
          active is int && active >= 0 && active <= thresholdMilliseconds
          ? active
          : 0,
      automaticPromptHandled: value['automatic_prompt_handled'] == true,
      suppressed: value['suppressed'] == true,
    );
  }

  static ReviewActivityProgress decode(String? raw) {
    if (raw == null || raw.length > 2048) return ReviewActivityProgress();
    try {
      return ReviewActivityProgress.fromJson(jsonDecode(raw));
    } catch (_) {
      return ReviewActivityProgress();
    }
  }

  /// Stale checkpoints must never clear an already persisted prompt claim.
  ReviewActivityProgress merge(ReviewActivityProgress other) =>
      ReviewActivityProgress(
        activeMilliseconds: math.max(
          activeMilliseconds,
          other.activeMilliseconds,
        ),
        automaticPromptHandled:
            automaticPromptHandled || other.automaticPromptHandled,
        suppressed: suppressed || other.suppressed,
      );
}

/// One tracker belongs to one authenticated account. The host must replace it on
/// account change, and set availability false for background/hidden/locked or
/// screensaver states. It must tick at least every [maximumObservationGap].
///
/// A Stopwatch supplies production time; injecting elapsed Duration avoids any
/// wall-clock changes. Foreground time counts only within two minutes of input.
class KorlixReviewActivityTracker {
  KorlixReviewActivityTracker({
    required this.userId,
    required ReviewActivityProgress initialProgress,
    required Duration Function() monotonicNow,
    this.idleCutoff = const Duration(minutes: 2),
    this.maximumObservationGap = const Duration(seconds: 15),
  }) : _progress = initialProgress,
       _now = monotonicNow {
    if (userId.trim().isEmpty ||
        idleCutoff <= Duration.zero ||
        maximumObservationGap <= Duration.zero) {
      throw ArgumentError(
        'An account and positive activity intervals are required.',
      );
    }
    _lastObserved = _now();
  }

  final String userId;
  final Duration idleCutoff;
  final Duration maximumObservationGap;
  final Duration Function() _now;
  ReviewActivityProgress _progress;
  late Duration _lastObserved;
  Duration? _lastInteraction;
  bool _available = false;
  int _uncreditedMicroseconds = 0;

  ReviewActivityProgress get progress => _progress;
  bool get available => _available;
  bool get eligible {
    tick();
    final lastInteraction = _lastInteraction;
    return _available &&
        _progress.eligible &&
        lastInteraction != null &&
        _lastObserved - lastInteraction < idleCutoff;
  }

  void setAvailable(bool value) {
    tick();
    if (_available == value) return;
    _available = value;
    // Returning to a tab/app is not proof of active use: wait for real input.
    _lastInteraction = null;
  }

  /// Call only for actual pointer, touch, keyboard or scroll input, not timers,
  /// audio playback, animation, network traffic, or a navigation callback.
  void recordInteraction() {
    tick();
    if (_available) _lastInteraction = _lastObserved;
  }

  void tick() {
    final now = _now();
    final delta = now - _lastObserved;
    final previous = _lastObserved;
    _lastObserved = now;
    if (delta < Duration.zero || delta > maximumObservationGap) {
      // Timers can stop without lifecycle notifications (sleep, suspended tabs).
      // Do not credit an unobserved gap, even if it is shorter than idleCutoff.
      _lastInteraction = null;
      return;
    }
    final interaction = _lastInteraction;
    if (!_available ||
        interaction == null ||
        _progress.automaticPromptHandled ||
        _progress.suppressed) {
      return;
    }
    final deadline = interaction + idleCutoff;
    final end = now < deadline ? now : deadline;
    final start = previous > interaction ? previous : interaction;
    if (end <= start) return;
    final microseconds = (end - start).inMicroseconds + _uncreditedMicroseconds;
    _uncreditedMicroseconds =
        microseconds % Duration.microsecondsPerMillisecond;
    _progress = _progress.copyWith(
      activeMilliseconds:
          _progress.activeMilliseconds +
          microseconds ~/ Duration.microsecondsPerMillisecond,
    );
  }

  /// Apply the persisted state returned from saving/claiming; flags only advance.
  void mergeProgress(ReviewActivityProgress value) {
    _progress = _progress.merge(value);
  }
}

/// Device-local, account-scoped storage. No activity timeline is retained.
/// A claim is persisted before opening UI; closing or choosing Later therefore
/// cannot cause an automatic prompt at every subsequent launch.
class SharedPreferencesReviewActivityRepository {
  SharedPreferencesReviewActivityRepository({
    Future<SharedPreferences> Function()? loadPreferences,
  }) : _loadPreferences = loadPreferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _loadPreferences;
  static final Map<String, Future<void>> _pending = {};

  static String storageKey(String userId) {
    if (userId.trim().isEmpty || userId.length > 2048) {
      throw ArgumentError.value(
        userId,
        'userId',
        'A valid account is required.',
      );
    }
    final encoded = base64Url.encode(utf8.encode(userId)).replaceAll('=', '');
    return 'korlix.review_activity.v1.$encoded';
  }

  Future<T> _serial<T>(String key, Future<T> Function() action) async {
    final prior = _pending[key] ?? Future<void>.value();
    final done = Completer<void>();
    _pending[key] = done.future;
    await prior;
    try {
      return await action();
    } finally {
      done.complete();
      if (identical(_pending[key], done.future)) _pending.remove(key);
    }
  }

  Future<SharedPreferences> _freshPreferences() async {
    final preferences = await _loadPreferences();
    await preferences.reload();
    return preferences;
  }

  ReviewActivityProgress _read(SharedPreferences preferences, String key) {
    final raw = preferences.get(key);
    return ReviewActivityProgress.decode(raw is String ? raw : null);
  }

  Future<ReviewActivityProgress> load(String userId) {
    final key = storageKey(userId);
    return _serial(key, () async => _read(await _freshPreferences(), key));
  }

  Future<void> _write(
    SharedPreferences preferences,
    String key,
    ReviewActivityProgress progress,
  ) async {
    if (!await preferences.setString(key, jsonEncode(progress.toJson()))) {
      throw StateError('Review activity could not be saved on this device.');
    }
  }

  Future<ReviewActivityProgress> save(
    String userId,
    ReviewActivityProgress progress,
  ) {
    final key = storageKey(userId);
    return _serial(key, () async {
      final preferences = await _freshPreferences();
      final merged = _read(preferences, key).merge(progress);
      await _write(preferences, key, merged);
      return merged;
    });
  }

  Future<bool> claimAutomaticPrompt(
    String userId,
    ReviewActivityProgress progress,
  ) {
    final key = storageKey(userId);
    return _serial(key, () async {
      final preferences = await _freshPreferences();
      final merged = _read(preferences, key).merge(progress);
      if (!merged.eligible) return false;
      await _write(
        preferences,
        key,
        merged.copyWith(automaticPromptHandled: true),
      );
      return true;
    });
  }

  Future<ReviewActivityProgress> suppress(
    String userId,
    ReviewActivityProgress progress,
  ) => save(userId, progress.copyWith(suppressed: true));
}
