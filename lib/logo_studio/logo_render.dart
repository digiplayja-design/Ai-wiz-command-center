import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'logo_model.dart';
import 'logo_fonts.dart';
export 'logo_fonts.dart';

enum LogoSurface { light, dark, transparent }

enum LogoInk { color, black, white }

const logoArtSize = Size(1200, 800);

class LogoShape {
  const LogoShape(this.d, [this.secondary = false]);
  final String d;
  final bool secondary;
  static final _paths = Expando<Path>('logo paths');
  Path get path => Path.from(_paths[this] ??= _parsePath());
  Path _parsePath() {
    final tokens = RegExp(
      r'[MLCQZ]|-?\d+(?:\.\d+)?',
    ).allMatches(d).map((m) => m.group(0)!).toList();
    final p = Path();
    var i = 0;
    double n() => double.parse(tokens[i++]);
    while (i < tokens.length) {
      switch (tokens[i++]) {
        case 'M':
          p.moveTo(n(), n());
        case 'L':
          p.lineTo(n(), n());
        case 'C':
          p.cubicTo(n(), n(), n(), n(), n(), n());
        case 'Q':
          p.quadraticBezierTo(n(), n(), n(), n());
        case 'Z':
          p.close();
      }
    }
    return p;
  }
}

List<LogoShape> logoShapes(String name) => switch (name) {
  'Sunrise' => const [
    LogoShape(
      'M 18 60 C 18 15 82 15 82 60 L 67 60 C 67 35 33 35 33 60 Z M 4 70 L 96 70 L 96 80 L 4 80 Z',
    ),
    LogoShape(
      'M 45 3 L 55 3 L 55 17 L 45 17 Z M 9 22 L 16 15 L 27 26 L 20 33 Z M 73 26 L 84 15 L 91 22 L 80 33 Z M 22 89 L 78 89 L 78 96 L 22 96 Z',
      true,
    ),
  ],
  'Wings' => const [
    LogoShape(
      'M 4 16 L 46 41 L 46 85 L 25 67 L 25 49 L 14 43 L 14 30 L 4 26 Z',
    ),
    LogoShape(
      'M 96 16 L 54 41 L 54 85 L 75 67 L 75 49 L 86 43 L 86 30 L 96 26 Z',
      true,
    ),
  ],
  'Hexagon' => const [
    LogoShape(
      'M 50 3 L 93 27 L 93 73 L 50 97 L 7 73 L 7 27 Z M 22 36 L 22 64 L 50 80 L 78 64 L 78 36 L 50 20 Z',
    ),
    LogoShape('M 50 30 L 68 40 L 68 60 L 50 70 L 32 60 L 32 40 Z', true),
  ],
  'Crown' => const [
    LogoShape('M 6 24 L 29 44 L 50 10 L 71 44 L 94 24 L 82 75 L 18 75 Z'),
    LogoShape('M 20 83 L 80 83 L 80 94 L 20 94 Z', true),
  ],
  'Bolt' => const [
    LogoShape('M 54 3 L 17 57 L 46 57 L 34 97 L 85 37 L 55 37 L 73 3 Z'),
    LogoShape('M 55 48 L 36 82 L 64 48 Z', true),
  ],
  'Wave' => const [
    LogoShape(
      'M 4 64 C 23 66 23 9 63 14 C 79 15 91 25 96 38 C 78 26 64 31 63 44 C 56 33 44 41 42 56 C 37 80 18 88 4 82 Z',
    ),
    LogoShape(
      'M 47 75 C 69 75 79 58 96 60 L 96 77 C 78 76 71 94 47 93 Z',
      true,
    ),
  ],
  'Flame' => const [
    LogoShape(
      'M 53 3 C 61 34 91 44 87 66 C 84 108 10 107 12 65 C 13 44 34 34 37 18 C 39 34 37 43 32 50 C 51 48 53 23 53 3 Z',
    ),
    LogoShape(
      'M 48 50 C 50 68 70 67 68 82 C 67 99 36 99 33 82 C 29 71 42 66 48 50 Z',
      true,
    ),
  ],
  'Drop' => const [
    LogoShape(
      'M 50 3 C 38 26 14 44 14 63 C 14 109 86 109 86 63 C 86 44 62 26 50 3 Z',
    ),
    LogoShape(
      'M 61 39 C 63 54 76 57 72 72 C 69 83 60 88 50 87 C 68 75 65 60 61 39 Z',
      true,
    ),
  ],
  'Lotus' => const [
    LogoShape('M 50 8 C 24 34 26 62 50 85 C 74 62 76 34 50 8 Z'),
    LogoShape(
      'M 8 35 C 32 34 40 51 44 87 C 21 83 8 66 8 35 Z M 92 35 C 68 34 60 51 56 87 C 79 83 92 66 92 35 Z',
      true,
    ),
  ],
  'Mountain' => const [
    LogoShape('M 2 86 L 36 17 L 70 86 L 52 86 L 36 51 L 20 86 Z'),
    LogoShape('M 50 45 L 65 16 L 98 86 L 79 86 L 65 51 L 59 63 Z', true),
  ],
  'Pulse' => const [
    LogoShape(
      'M 3 47 L 24 47 L 37 14 L 55 70 L 67 38 L 77 47 L 97 47 L 97 59 L 72 59 L 64 80 L 52 94 L 36 45 L 32 59 L 3 59 Z',
    ),
    LogoShape('M 76 15 L 92 15 L 92 31 L 76 31 Z', true),
  ],
  'Infinity' => const [
    LogoShape(
      'M 50 40 C 27 5 2 26 3 50 C 3 78 31 93 50 63 L 43 51 C 30 74 17 69 17 50 C 17 30 31 31 43 50 Z',
    ),
    LogoShape(
      'M 50 60 C 73 95 98 74 97 50 C 97 22 69 7 50 37 L 57 49 C 70 26 83 31 83 50 C 83 70 69 69 57 50 Z',
      true,
    ),
  ],
  'Diamond' => const [
    LogoShape(
      'M 50 2 L 98 50 L 50 98 L 2 50 Z M 22 50 L 50 78 L 78 50 L 50 22 Z',
    ),
    LogoShape('M 50 31 L 69 50 L 50 69 L 31 50 Z', true),
  ],
  'Triangle' => const [
    LogoShape(
      'M 50 3 L 98 90 L 80 90 L 50 36 L 30 73 L 60 73 L 70 90 L 2 90 Z',
    ),
    LogoShape('M 50 52 L 62 73 L 38 73 Z', true),
  ],
  'Cube' => const [
    LogoShape(
      'M 50 4 L 93 27 L 50 51 L 7 27 Z M 7 37 L 44 58 L 44 96 L 7 74 Z',
    ),
    LogoShape('M 56 58 L 93 37 L 93 74 L 56 96 Z', true),
  ],
  'Steps' => const [
    LogoShape(
      'M 5 68 L 28 68 L 28 92 L 5 92 Z M 38 39 L 61 39 L 61 92 L 38 92 Z',
    ),
    LogoShape('M 71 8 L 94 8 L 94 92 L 71 92 Z', true),
  ],
  'Arrow' => const [
    LogoShape('M 6 39 L 57 39 L 57 13 L 96 50 L 57 87 L 57 61 L 6 61 Z'),
    LogoShape(
      'M 6 12 L 27 12 L 27 28 L 6 28 Z M 6 72 L 27 72 L 27 88 L 6 88 Z',
      true,
    ),
  ],
  'Bloom' => const [
    LogoShape(
      'M 50 50 C 9 21 33 0 50 10 C 67 0 91 21 50 50 Z M 50 50 C 91 79 67 100 50 90 C 33 100 9 79 50 50 Z',
    ),
    LogoShape(
      'M 50 50 C 79 9 100 33 90 50 C 100 67 79 91 50 50 Z M 50 50 C 21 91 0 67 10 50 C 0 33 21 9 50 50 Z',
      true,
    ),
  ],
  'Feather' => const [
    LogoShape(
      'M 14 88 C 9 16 57 0 92 9 C 89 52 61 84 27 83 L 16 98 L 7 93 L 68 28 L 19 70 Z',
    ),
    LogoShape('M 33 66 L 72 24 L 56 60 Z', true),
  ],
  'Sprout' => const [
    LogoShape(
      'M 44 94 L 44 61 C 12 66 2 39 8 18 C 39 16 49 38 50 48 C 53 23 70 11 94 13 C 99 42 79 62 56 58 L 56 94 Z',
    ),
    LogoShape(
      'M 13 94 L 13 84 L 36 84 L 36 94 Z M 64 84 L 87 84 L 87 94 L 64 94 Z',
      true,
    ),
  ],
  'Heart' => const [
    LogoShape(
      'M 50 90 C 38 79 4 57 5 32 C 6 4 39 3 50 25 C 61 3 94 4 95 32 C 96 57 62 79 50 90 Z',
    ),
    LogoShape(
      'M 58 36 C 64 18 81 19 82 32 C 83 45 64 63 55 69 C 67 52 70 44 58 36 Z',
      true,
    ),
  ],
  'Butterfly' => const [
    LogoShape(
      'M 45 48 C 6 1 0 7 7 43 C 9 57 27 62 45 48 Z M 44 58 C 8 61 6 91 22 94 C 36 98 48 78 44 58 Z',
    ),
    LogoShape(
      'M 55 48 C 94 1 100 7 93 43 C 91 57 73 62 55 48 Z M 56 58 C 92 61 94 91 78 94 C 64 98 52 78 56 58 Z',
      true,
    ),
  ],
  'Anchor' => const [
    LogoShape(
      'M 44 32 L 56 32 L 56 73 C 76 71 85 62 86 49 L 98 49 C 98 80 72 94 50 98 C 28 94 2 80 2 49 L 14 49 C 15 62 24 71 44 73 Z M 22 35 L 78 35 L 78 47 L 22 47 Z',
    ),
    LogoShape(
      'M 50 2 C 29 2 29 30 50 30 C 71 30 71 2 50 2 Z M 50 10 C 60 10 60 22 50 22 C 40 22 40 10 50 10 Z',
      true,
    ),
  ],
  'Bridge' => const [
    LogoShape(
      'M 4 87 L 4 31 L 17 31 L 17 43 C 34 57 66 57 83 43 L 83 31 L 96 31 L 96 87 L 83 87 L 83 59 C 63 70 37 70 17 59 L 17 87 Z',
    ),
    LogoShape(
      'M 3 18 L 19 18 L 19 27 L 3 27 Z M 81 18 L 97 18 L 97 27 L 81 27 Z M 28 75 L 72 75 L 72 86 L 28 86 Z',
      true,
    ),
  ],
  'Gateway' => const [
    LogoShape('M 6 7 L 94 7 L 94 92 L 78 92 L 78 23 L 22 23 L 22 92 L 6 92 Z'),
    LogoShape('M 36 39 L 64 39 L 64 92 L 36 92 Z', true),
  ],
  'Orbitals' => const [
    LogoShape(
      'M 50 3 C 8 3 8 97 50 97 C 92 97 92 3 50 3 Z M 50 17 C 73 17 73 83 50 83 C 27 83 27 17 50 17 Z',
    ),
    LogoShape(
      'M 3 50 C 3 8 97 8 97 50 C 97 92 3 92 3 50 Z M 17 50 C 17 73 83 73 83 50 C 83 27 17 27 17 50 Z',
      true,
    ),
  ],
  'Nexus' => const [
    LogoShape(
      'M 8 8 L 32 8 L 32 32 L 8 32 Z M 68 68 L 92 68 L 92 92 L 68 92 Z M 26 36 L 36 26 L 74 64 L 64 74 Z',
    ),
    LogoShape(
      'M 68 8 L 92 8 L 92 32 L 68 32 Z M 8 68 L 32 68 L 32 92 L 8 92 Z M 64 26 L 74 36 L 36 74 L 26 64 Z',
      true,
    ),
  ],
  'Weave' => const [
    LogoShape(
      'M 6 23 L 23 6 L 94 77 L 77 94 Z M 6 57 L 23 40 L 60 77 L 43 94 Z',
    ),
    LogoShape(
      'M 40 23 L 57 6 L 94 43 L 77 60 Z M 6 77 L 24 59 L 41 76 L 23 94 Z',
      true,
    ),
  ],
  'Target' => const [
    LogoShape(
      'M 50 4 C 111 4 111 96 50 96 C -11 96 -11 4 50 4 Z M 50 19 C 9 19 9 81 50 81 C 91 81 91 19 50 19 Z',
    ),
    LogoShape('M 50 31 C 75 31 75 69 50 69 C 25 69 25 31 50 31 Z', true),
  ],
  'Star' => const [
    LogoShape(
      'M 50 3 L 64 34 L 98 38 L 73 61 L 79 96 L 50 79 L 21 96 L 27 61 L 2 38 L 36 34 Z',
    ),
    LogoShape('M 50 26 L 57 43 L 76 46 L 62 58 L 65 76 L 50 67 Z', true),
  ],
  'Helix' => const [
    LogoShape('M 15 4 L 35 4 C 35 42 85 57 85 96 L 65 96 C 65 59 15 44 15 4 Z'),
    LogoShape(
      'M 65 4 L 85 4 C 85 29 65 46 50 59 L 35 44 C 49 32 65 18 65 4 Z M 35 62 L 50 76 C 40 84 35 89 35 96 L 15 96 C 15 82 24 71 35 62 Z',
      true,
    ),
  ],
  'Crescent' => const [
    LogoShape(
      'M 71 7 C 26 -3 3 25 5 51 C 7 87 41 108 75 88 C 24 98 9 21 71 7 Z',
    ),
    LogoShape(
      'M 76 24 L 82 39 L 98 43 L 84 53 L 84 70 L 71 59 L 55 64 L 62 48 L 52 35 L 69 36 Z',
      true,
    ),
  ],
  'Petal' => const [
    LogoShape(
      'M 50 48 C 14 50 7 14 13 9 C 42 4 55 21 50 48 Z M 50 52 C 86 50 93 86 87 91 C 58 96 45 79 50 52 Z',
    ),
    LogoShape(
      'M 52 50 C 50 14 86 7 91 13 C 96 42 79 55 52 50 Z M 48 50 C 50 86 14 93 9 87 C 4 58 21 45 48 50 Z',
      true,
    ),
  ],
  'Ribbon' => const [
    LogoShape('M 8 12 L 37 12 L 77 88 L 48 88 Z'),
    LogoShape(
      'M 63 12 L 92 12 L 63 63 L 49 37 Z M 8 88 L 30 48 L 44 74 L 37 88 Z',
      true,
    ),
  ],
  'Horizon' => const [
    LogoShape(
      'M 18 48 C 18 6 82 6 82 48 L 65 48 C 65 27 35 27 35 48 Z M 8 57 L 92 57 L 92 68 L 8 68 Z',
    ),
    LogoShape('M 21 77 L 79 77 L 79 87 L 21 87 Z', true),
  ],
  'Prism' => const [
    LogoShape('M 50 4 L 96 81 L 4 81 Z M 50 30 L 27 68 L 73 68 Z'),
    LogoShape(
      'M 50 30 L 73 68 L 50 57 Z M 4 89 L 96 89 L 96 96 L 4 96 Z',
      true,
    ),
  ],
  'Link' => const [
    LogoShape(
      'M 45 23 C 26 4 1 21 8 43 L 29 67 L 43 53 L 25 34 C 22 27 29 23 34 28 L 52 46 L 66 32 Z',
    ),
    LogoShape(
      'M 55 77 C 74 96 99 79 92 57 L 71 33 L 57 47 L 75 66 C 78 73 71 77 66 72 L 48 54 L 34 68 Z',
      true,
    ),
  ],
  'Compass' => const [
    LogoShape(
      'M 50 3 L 65 36 L 97 50 L 65 64 L 50 97 L 36 64 L 3 50 L 36 36 Z',
    ),
    LogoShape(
      'M 50 23 L 59 43 L 78 50 L 50 50 Z M 50 50 L 50 77 L 41 57 L 22 50 Z',
      true,
    ),
  ],
  'Peak' => const [
    LogoShape('M 8 84 L 48 12 L 69 49 L 55 49 L 48 37 L 22 84 Z'),
    LogoShape('M 41 84 L 69 35 L 96 84 L 80 84 L 69 64 L 58 84 Z', true),
  ],
  'Leaf' => const [
    LogoShape('M 48 91 C 3 79 5 31 12 14 C 58 21 69 58 48 91 Z'),
    LogoShape('M 49 81 C 44 39 66 13 94 11 C 101 50 83 77 49 81 Z', true),
  ],
  'Spark' => const [
    LogoShape(
      'M 50 3 L 62 36 L 96 49 L 63 61 L 50 98 L 37 62 L 3 49 L 37 37 Z',
    ),
    LogoShape(
      'M 82 2 L 86 14 L 98 18 L 86 22 L 82 34 L 78 22 L 66 18 L 78 14 Z',
      true,
    ),
  ],
  'Flow' => const [
    LogoShape(
      'M 2 39 C 21 7 42 7 61 36 C 73 54 82 50 98 31 L 98 54 C 80 75 60 75 43 51 C 31 33 18 33 2 55 Z',
    ),
    LogoShape(
      'M 2 64 C 21 40 40 46 57 66 C 71 82 83 79 98 65 L 98 85 C 77 102 56 98 40 81 C 24 64 16 63 2 80 Z',
      true,
    ),
  ],
  'Arch' => const [
    LogoShape(
      'M 9 92 L 9 47 C 9 0 91 0 91 47 L 91 92 L 72 92 L 72 47 C 72 20 28 20 28 47 L 28 92 Z',
    ),
    LogoShape('M 41 92 L 41 49 C 41 38 59 38 59 49 L 59 92 Z', true),
  ],
  'Shield' => const [
    LogoShape(
      'M 10 14 L 50 3 L 90 14 L 90 55 C 89 75 70 91 50 99 C 29 91 11 75 10 55 Z',
    ),
    LogoShape('M 27 49 L 44 64 L 76 29 L 76 47 L 45 81 L 27 64 Z', true),
  ],
  'Mosaic' => const [
    LogoShape(
      'M 8 8 L 46 8 L 46 46 L 8 46 Z M 54 54 L 92 54 L 92 92 L 54 92 Z',
    ),
    LogoShape(
      'M 54 8 L 92 8 L 92 46 L 54 46 Z M 8 54 L 46 54 L 46 92 L 8 92 Z',
      true,
    ),
  ],
  'Beacon' => const [
    LogoShape(
      'M 39 32 L 61 32 L 74 93 L 26 93 Z M 32 20 L 68 20 L 68 29 L 32 29 Z',
    ),
    LogoShape(
      'M 8 11 L 29 20 L 29 30 L 8 36 Z M 71 20 L 92 11 L 92 36 L 71 30 Z M 44 3 L 56 3 L 61 15 L 39 15 Z',
      true,
    ),
  ],
  _ => const [
    LogoShape(
      'M 50 3 L 97 50 L 50 97 L 3 50 L 21 50 L 50 79 L 79 50 L 50 21 L 50 3 Z',
    ),
    LogoShape('M 50 28 L 72 50 L 50 72 L 28 50 Z', true),
  ],
};

class LogoLettering {
  LogoLettering(
    this.value,
    this.rect,
    this.size,
    this.color,
    this.design, {
    this.tagline = false,
  });
  final String value, color;
  final Rect rect;
  final double size;
  final LogoDesign design;
  final bool tagline;
  double? _fittedFontSize;
  TextPainter get painter => _painter(false);
  TextPainter _painter(bool erase) {
    final face = tagline ? 'Clean' : design.typeface;
    TextPainter make(double fontSize) => TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: logoFontFamily(face),
          fontSize: fontSize,
          fontWeight:
              FontWeight.values[(logoFontWeight(face) ~/ 100 - 1).clamp(0, 8)],
          fontStyle: design.typeface == 'Slanted' && !tagline
              ? FontStyle.italic
              : FontStyle.normal,
          color: erase ? null : logoColor(color),
          foreground: erase
              ? (Paint()
                  ..color = Colors.black
                  ..blendMode = BlendMode.dstOut)
              : null,
          letterSpacing: tagline
              ? 2
              : design.tracking + (design.typeface == 'Wide' ? 3 : 0),
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (_fittedFontSize != null) return make(_fittedFontSize!);
    final original = make(size);
    if (original.width <= rect.width && original.height <= rect.height) {
      _fittedFontSize = size;
      return original;
    }
    original.dispose();
    // Tracking is a fixed distance, so scaling the font once does not reliably
    // fit long names. Measure the final lettering, including its spacing.
    var low = .1, high = size;
    for (var i = 0; i < 16; i++) {
      final middle = (low + high) / 2;
      final candidate = make(middle);
      final fits =
          candidate.width <= rect.width && candidate.height <= rect.height;
      candidate.dispose();
      if (fits) {
        low = middle;
      } else {
        high = middle;
      }
    }
    _fittedFontSize = low;
    return make(low);
  }

  Offset position(TextPainter p) =>
      Offset(rect.center.dx - p.width / 2, rect.center.dy - p.height / 2);
  void paint(Canvas canvas, {bool erase = false}) {
    final p = _painter(erase);
    p.paint(canvas, position(p));
    p.dispose();
  }

  String svg() {
    final p = painter;
    final face = tagline ? 'Clean' : design.typeface;
    final y =
        position(p).dy +
        p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final fontSize = p.text!.style!.fontSize!;
    p.dispose();
    return '<text x="${rect.center.dx}" y="$y" text-anchor="middle" font-family="${logoFontFamily(face)},Arial,sans-serif" font-size="$fontSize" font-weight="${logoFontWeight(face)}" font-style="${design.typeface == 'Slanted' && !tagline ? 'italic' : 'normal'}" letter-spacing="${tagline ? 2 : design.tracking + (design.typeface == 'Wide' ? 3 : 0)}" fill="#$color">${const HtmlEscape().convert(value)}</text>';
  }
}

class LogoComposition {
  LogoComposition(
    this.design, {
    this.surface = LogoSurface.light,
    this.ink = LogoInk.color,
    this.iconOnly = false,
  });
  final LogoDesign design;
  final LogoSurface surface;
  final LogoInk ink;
  final bool iconOnly;
  String get foreground => ink == LogoInk.black
      ? '000000'
      : ink == LogoInk.white || surface == LogoSurface.dark
      ? 'FFFFFF'
      : surface == LogoSurface.light
      ? _onColor(design.paper)
      : '17202B';
  String get primary => ink == LogoInk.black
      ? '000000'
      : ink == LogoInk.white
      ? 'FFFFFF'
      : design.primary;
  String get secondary => ink == LogoInk.black
      ? '000000'
      : ink == LogoInk.white
      ? 'FFFFFF'
      : design.secondary;
  String? get background => surface == LogoSurface.transparent
      ? null
      : surface == LogoSurface.dark
      ? '111927'
      : design.paper;
  bool get monogram =>
      design.layout == 'Monogram' ||
      design.mark == 'Initials' ||
      iconOnly && design.layout == 'Wordmark';
  Rect get markRect {
    final double side =
        (iconOnly || design.layout == 'Monogram'
            ? 430
            : design.layout == 'Stacked'
            ? 270
            : 210) *
        design.symbolScale;
    return Rect.fromCenter(
      center: iconOnly || design.layout == 'Monogram'
          ? const Offset(600, 390)
          : design.layout == 'Stacked'
          ? const Offset(600, 280)
          : const Offset(220, 390),
      width: side,
      height: side,
    );
  }

  late final List<LogoLettering> lettering = _lettering();
  List<LogoLettering> _lettering() {
    if (iconOnly || design.layout == 'Monogram') return [];
    final horizontal = design.layout == 'Horizontal';
    final rect = horizontal
        ? const Rect.fromLTWH(365, 285, 755, 155)
        : design.layout == 'Stacked'
        ? const Rect.fromLTWH(95, 480, 1010, 140)
        : const Rect.fromLTWH(80, 270, 1040, 175);
    return [
      LogoLettering(
        design.name,
        rect,
        horizontal ? 100 : 118,
        ink == LogoInk.black ? '000000' : foreground,
        design,
      ),
      if (design.tagline.isNotEmpty)
        LogoLettering(
          design.tagline,
          Rect.fromLTWH(rect.left, rect.bottom + 4, rect.width, 70),
          30,
          ink == LogoInk.black ? '000000' : foreground,
          design,
          tagline: true,
        ),
    ];
  }

  /// Bounds of the mark and measured lettering, without the old artboard's
  /// empty margins. All previews and exports use these same fitted bounds.
  late final Rect contentBounds = _contentBounds();
  Rect _contentBounds() {
    Rect? bounds;
    if (design.layout != 'Wordmark' || iconOnly) bounds = markRect;
    for (final text in lettering) {
      final painter = text.painter;
      final rect = text.position(painter) & painter.size;
      painter.dispose();
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    return bounds == null || bounds.width <= 0 || bounds.height <= 0
        ? const Rect.fromLTWH(0, 0, 1200, 800)
        : bounds;
  }

  _LogoViewport _viewport(Size size) =>
      _LogoViewport(contentBounds, size, paddingFraction: iconOnly ? .14 : .08);

  void paintFitted(Canvas canvas, Size size) {
    if (background != null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = logoColor(background!),
      );
    }
    final viewport = _viewport(size);
    canvas.save();
    canvas.translate(viewport.offset.dx, viewport.offset.dy);
    canvas.scale(viewport.scale);
    paint(canvas, paintBackground: false);
    canvas.restore();
  }

  void paint(Canvas canvas, {bool paintBackground = true}) {
    if (paintBackground && background != null) {
      canvas.drawRect(
        Offset.zero & logoArtSize,
        Paint()..color = logoColor(background!),
      );
    }
    if (design.layout != 'Wordmark' || iconOnly) {
      final rect = markRect;
      if (monogram) {
        if (ink != LogoInk.color) canvas.saveLayer(rect, Paint());
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(rect.width * .23)),
          Paint()..color = logoColor(primary),
        );
        LogoLettering(
          design.initials,
          rect.deflate(rect.width * .13),
          rect.width * .53,
          ink == LogoInk.white ? '111927' : _onColor(primary),
          design.copy(
            typeface: isClassicLogoFont(design.typeface)
                ? 'Strong'
                : design.typeface,
            tracking: 0,
          ),
        ).paint(canvas, erase: ink != LogoInk.color);
        if (ink != LogoInk.color) canvas.restore();
      } else {
        canvas.save();
        canvas.translate(rect.left, rect.top);
        canvas.scale(rect.width / 100);
        for (final shape in logoShapes(design.mark)) {
          canvas.drawPath(
            shape.path,
            Paint()..color = logoColor(shape.secondary ? secondary : primary),
          );
        }
        canvas.restore();
      }
    }
    for (final text in lettering) {
      text.paint(canvas);
    }
  }

  String svg({String fontStyle = '', int? width, int? height}) {
    final outputWidth = width ?? (iconOnly ? 1024 : 1200);
    final outputHeight = height ?? (iconOnly ? 1024 : 800);
    _checkLogoDimensions(outputWidth, outputHeight);
    final viewport = _viewport(
      Size(outputWidth.toDouble(), outputHeight.toDouble()),
    );
    final out = StringBuffer(
      '<svg xmlns="http://www.w3.org/2000/svg" width="$outputWidth" height="$outputHeight" viewBox="0 0 $outputWidth $outputHeight" role="img"><title>${const HtmlEscape().convert(design.name)} logo</title>$fontStyle',
    );
    if (background != null) {
      out.write(
        '<rect width="$outputWidth" height="$outputHeight" fill="#$background"/>',
      );
    }
    out.write(
      '<g transform="translate(${viewport.offset.dx} ${viewport.offset.dy}) scale(${viewport.scale})">',
    );
    if (design.layout != 'Wordmark' || iconOnly) {
      final rect = markRect;
      if (monogram) {
        final text = LogoLettering(
          design.initials,
          rect.deflate(rect.width * .13),
          rect.width * .53,
          ink != LogoInk.color ? '000000' : _onColor(primary),
          design.copy(
            typeface: isClassicLogoFont(design.typeface)
                ? 'Strong'
                : design.typeface,
            tracking: 0,
          ),
        ).svg();
        if (ink != LogoInk.color) {
          out.write(
            '<defs><mask id="initials" maskUnits="userSpaceOnUse" x="0" y="0" width="1200" height="800"><rect width="1200" height="800" fill="white"/>$text</mask></defs>',
          );
        }
        out.write(
          '<rect x="${rect.left}" y="${rect.top}" width="${rect.width}" height="${rect.height}" rx="${rect.width * .23}" fill="#$primary"${ink != LogoInk.color ? ' mask="url(#initials)"' : ''}/>',
        );
        if (ink == LogoInk.color) out.write(text);
      } else {
        out.write(
          '<g transform="translate(${rect.left} ${rect.top}) scale(${rect.width / 100})">',
        );
        for (final shape in logoShapes(design.mark)) {
          out.write(
            '<path d="${shape.d}" fill="#${shape.secondary ? secondary : primary}"/>',
          );
        }
        out.write('</g>');
      }
    }
    for (final text in lettering) {
      out.write(text.svg());
    }
    return '${out.toString()}</g></svg>';
  }
}

class _LogoViewport {
  _LogoViewport(Rect bounds, Size size, {required double paddingFraction}) {
    final padding = size.shortestSide * paddingFraction;
    scale = math.min(
      (size.width - padding * 2) / bounds.width,
      (size.height - padding * 2) / bounds.height,
    );
    offset = Offset(
      size.width / 2 - bounds.center.dx * scale,
      size.height / 2 - bounds.center.dy * scale,
    );
  }
  late final double scale;
  late final Offset offset;
}

void _checkLogoDimensions(int width, int height) {
  if (width < 1 || height < 1 || width * height > 6000000) {
    throw ArgumentError('Unsupported logo dimensions.');
  }
}

String _onColor(String hex) {
  final luminance = logoColor(hex).computeLuminance();
  final dark = logoColor('111927').computeLuminance();
  final whiteContrast = 1.05 / (luminance + .05);
  final darkContrast = (luminance + .05) / (dark + .05);
  return darkContrast >= whiteContrast ? '111927' : 'FFFFFF';
}

class LogoCanvas extends StatefulWidget {
  const LogoCanvas({
    super.key,
    required this.design,
    this.surface = LogoSurface.light,
    this.ink = LogoInk.color,
    this.iconOnly = false,
    this.aspectRatio,
  });
  final LogoDesign design;
  final LogoSurface surface;
  final LogoInk ink;
  final bool iconOnly;
  final double? aspectRatio;
  @override
  State<LogoCanvas> createState() => _LogoCanvasState();
}

class _LogoCanvasState extends State<LogoCanvas> {
  late _LogoPainter _painter;
  void _compose() => _painter = _LogoPainter(
    LogoComposition(
      widget.design,
      surface: widget.surface,
      ink: widget.ink,
      iconOnly: widget.iconOnly,
    ),
  );
  @override
  void initState() {
    super.initState();
    _compose();
  }

  @override
  void didUpdateWidget(LogoCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.design != widget.design ||
        oldWidget.surface != widget.surface ||
        oldWidget.ink != widget.ink ||
        oldWidget.iconOnly != widget.iconOnly) {
      _compose();
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${widget.design.name}, ${widget.design.layout} logo, ${widget.design.mark} symbol',
    image: true,
    child: AspectRatio(
      aspectRatio: widget.aspectRatio ?? (widget.iconOnly ? 1 : 1.5),
      child: RepaintBoundary(
        child: LogoFontReady(
          face: widget.design.typeface,
          builder: (_) => CustomPaint(painter: _painter, isComplex: true),
        ),
      ),
    ),
  );
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.composition);
  final LogoComposition composition;
  @override
  void paint(Canvas canvas, Size size) {
    if (composition.surface == LogoSurface.transparent) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFFF8FAFC),
      );
      for (var x = 0.0; x < size.width; x += 24) {
        for (var y = 0.0; y < size.height; y += 24) {
          if ((x ~/ 24 + y ~/ 24).isEven) {
            canvas.drawRect(
              Rect.fromLTWH(
                x,
                y,
                math.min(24, size.width - x),
                math.min(24, size.height - y),
              ),
              Paint()..color = const Color(0xFFE8ECF0),
            );
          }
        }
      }
    }
    composition.paintFitted(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) =>
      composition.design != oldDelegate.composition.design ||
      composition.surface != oldDelegate.composition.surface ||
      composition.ink != oldDelegate.composition.ink ||
      composition.iconOnly != oldDelegate.composition.iconOnly;
}

Future<Uint8List> logoPng(
  LogoDesign design, {
  LogoSurface surface = LogoSurface.transparent,
  LogoInk ink = LogoInk.color,
  int? width,
  int? height,
  bool iconOnly = false,
}) async {
  final outputWidth = width ?? (iconOnly ? 1024 : 2400);
  final outputHeight = height ?? (iconOnly ? 1024 : 1600);
  _checkLogoDimensions(outputWidth, outputHeight);
  await ensureLogoFonts(design.typeface);
  final recorder = ui.PictureRecorder();
  // Each export owns and releases its recording and image.
  final c = Canvas(recorder);
  LogoComposition(
    design,
    surface: surface,
    ink: ink,
    iconOnly: iconOnly,
  ).paintFitted(c, Size(outputWidth.toDouble(), outputHeight.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(outputWidth, outputHeight);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
