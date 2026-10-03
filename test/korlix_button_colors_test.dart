import 'package:ai_wiz_command_center/theme/korlix_button_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color foreground, Color background) {
  final a = Color.alphaBlend(foreground, background).computeLuminance();
  final b = background.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

void main() {
  test(
    'every button palette is colorful with readable text across its gradient',
    () {
      expect(
        korlixButtonPalettes.map((palette) => palette.id).toSet().length,
        korlixButtonPalettes.length,
      );
      final hues = <int>{};
      for (final palette in korlixButtonPalettes) {
        expect(palette.gradientColors.length, greaterThanOrEqualTo(2));
        expect(palette.foreground.a, 1);
        for (final color in palette.gradientColors) {
          expect(color.a, 1, reason: '${palette.id} face should be opaque');
          expect(
            HSLColor.fromColor(color).saturation,
            greaterThan(.3),
            reason: '${palette.id} should remain colorful on neutral themes',
          );
        }
        hues.add((HSLColor.fromColor(palette.start).hue / 60).floor());
        for (var stop = 0; stop < palette.gradientColors.length - 1; stop++) {
          // Sampling between stops catches gradients whose endpoints alone look safe.
          for (var sample = 0; sample <= 20; sample++) {
            final background = Color.lerp(
              palette.gradientColors[stop],
              palette.gradientColors[stop + 1],
              sample / 20,
            )!;
            expect(
              _contrast(palette.foreground, background),
              greaterThanOrEqualTo(4.5),
              reason: '${palette.id}: stop $stop, sample $sample',
            );
          }
        }
      }
      expect(
        hues.length,
        greaterThanOrEqualTo(4),
        reason: 'Feature buttons should offer a varied range of colors',
      );
    },
  );

  test('feature aliases retain the same recognizable color identity', () {
    for (final aliases in [
      ['VoiceScribe', 'Voice-scribe', 'voice_scribe'],
      ['Copy Box', 'copybox', 'COPY BOX'],
      ['Improve my picture', 'IMPROVE MY PICTURE'],
      ['Workforce', 'WORKFORCE'],
    ]) {
      final expected = korlixButtonColorsFor(aliases.first);
      for (final alias in aliases.skip(1)) {
        final actual = korlixButtonColorsFor(alias);
        expect(actual.id, expected.id, reason: alias);
        expect(actual.gradientColors, expected.gradientColors, reason: alias);
      }
    }
  });

  test(
    'unrecognized labels get a deterministic and readable colorful fallback',
    () {
      final first = korlixButtonColorsFor('A future workspace');
      for (var request = 0; request < 5; request++) {
        final repeated = korlixButtonColorsFor('A future workspace');
        expect(repeated.gradientColors, first.gradientColors);
        for (final background in repeated.gradientColors) {
          expect(
            _contrast(repeated.foreground, background),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );

  test(
    'destructive intent receives one consistent palette regardless of label',
    () {
      final expected = korlixButtonColorsFor('Remove item', destructive: true);
      for (final label in ['Clear saved data', 'Delete draft', 'Remove item']) {
        final actual = korlixButtonColorsFor(label, destructive: true);
        expect(actual.id, expected.id);
        expect(actual.gradientColors, expected.gradientColors);
      }
    },
  );
}
