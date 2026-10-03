import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ButtonStyle;

import 'korlix_sound_service.dart';

/// Decorates an actual activation callback, retaining native disabled, keyboard
/// and canceled-gesture behavior. Audio never delays or replaces the action.
VoidCallback? korlixSoundAction(
  VoidCallback? action, {
  KorlixSoundService? service,
}) {
  if (action == null) return null;
  return () {
    _click(service ?? kKorlixSounds);
    action();
  };
}

void _click(KorlixSoundService sounds) {
  // Request browser audio activation while still in the user gesture. If a
  // permission/device response takes longer, omit the now-unrelated click.
  final elapsed = Stopwatch()..start();
  try {
    final activation = sounds.activate();
    unawaited(
      activation
          .then<void>((active) {
            elapsed.stop();
            if (!active ||
                elapsed.elapsed > const Duration(milliseconds: 250)) {
              return;
            }
            unawaited(
              sounds
                  .play(KorlixSound.click)
                  .then<void>((_) {})
                  .catchError((Object _, StackTrace _) {}),
            );
          }, onError: (Object _, StackTrace _) => elapsed.stop())
          .catchError((Object _, StackTrace _) {}),
    );
  } catch (_) {
    elapsed.stop();
  }
}

/// Avoid a second Android system click outside the app's sound preferences.
ButtonStyle korlixSoundButtonStyle(ButtonStyle? style) =>
    (style ?? const ButtonStyle()).copyWith(enableFeedback: false);
