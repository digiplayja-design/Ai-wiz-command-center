import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'logo_model.dart';

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

Future<void>? _fontLoading;
bool _fontsReady = false;
Future<void> ensureLogoFonts() {
  if (_fontsReady) return Future.value();
  return _fontLoading ??=
      (FontLoader('KorlixLogo')
            ..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fieldproof/Roboto-Bold.ttf')))
          .load()
          .then(
            (_) {
              _fontsReady = true;
            },
            onError: (Object e, StackTrace s) {
              _fontLoading = null;
              Error.throwWithStackTrace(e, s);
            },
          );
}

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
    final bold = !tagline && design.typeface == 'Strong';
    TextPainter make(double fontSize) => TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'KorlixLogo',
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
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
    final p = painter, bold = !tagline && design.typeface == 'Strong';
    final y =
        position(p).dy +
        p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final fontSize = p.text!.style!.fontSize!;
    p.dispose();
    return '<text x="${rect.center.dx}" y="$y" text-anchor="middle" font-family="KorlixLogo,Arial,sans-serif" font-size="$fontSize" font-weight="${bold ? 700 : 400}" font-style="${design.typeface == 'Slanted' && !tagline ? 'italic' : 'normal'}" letter-spacing="${tagline ? 2 : design.tracking + (design.typeface == 'Wide' ? 3 : 0)}" fill="#$color">${const HtmlEscape().convert(value)}</text>';
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
          design.copy(typeface: 'Strong', tracking: 0),
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
          design.copy(typeface: 'Strong', tracking: 0),
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
        child: CustomPaint(painter: _painter, isComplex: true),
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
  await ensureLogoFonts();
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
