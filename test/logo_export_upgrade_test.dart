import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_export.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_export_options.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_model.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_render.dart';

const brand = LogoDesign(name: 'North & Pine', tagline: 'MADE FOR EVERY DAY');

Future<(int, int, Rect, Uint8List)> pixels(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  try {
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    var left = image.width, top = image.height, right = -1, bottom = -1;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (bytes[(y * image.width + x) * 4 + 3] < 128) continue;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    return (
      image.width,
      image.height,
      Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1, bottom + 1),
      bytes,
    );
  } finally {
    image.dispose();
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureLogoFonts);

  test(
    'export presets are bounded and distinguish full logos from profile marks',
    () {
      expect(logoExportPresets.map((p) => p.id), [
        'standard',
        'wide',
        'square',
        'profile',
      ]);
      expect(
        logoExportPresets.every((p) => p.width * p.height <= 6000000),
        isTrue,
      );
      expect(logoExportPresets.last.iconOnly, isTrue);
      expect(logoExportPresets.last.width, logoExportPresets.last.height);
    },
  );

  test(
    'long names fit including fixed tracking, and SVG uses measured type size',
    () {
      final design = brand.copy(
        name: 'W' * 50,
        tagline: 'W' * 80,
        tracking: 8,
        typeface: 'Wide',
      );
      for (final layout in ['Horizontal', 'Stacked', 'Wordmark']) {
        final composition = LogoComposition(design.copy(layout: layout));
        for (final line in composition.lettering) {
          final painter = line.painter;
          try {
            expect(painter.width, lessThanOrEqualTo(line.rect.width));
            expect(painter.height, lessThanOrEqualTo(line.rect.height));
            expect(
              line.svg(),
              contains('font-size="${painter.text!.style!.fontSize}"'),
            );
            expect(
              line.position(painter).dx,
              greaterThanOrEqualTo(line.rect.left),
            );
          } finally {
            painter.dispose();
          }
        }
      }
    },
  );

  testWidgets(
    'square icon SVG and decoded PNG have matching generous safe space',
    (t) async {
      await t.runAsync(() async {
        final design = brand.copy(layout: 'Monogram');
        final svg = await logoSvg(design, iconOnly: true);
        expect(
          svg,
          contains('width="1024" height="1024" viewBox="0 0 1024 1024"'),
        );
        final transform = RegExp(
          r'<g transform="translate\(([-\d.]+) ([-\d.]+)\) scale\(([-\d.]+)\)">',
        ).firstMatch(svg)!;
        final offsetX = double.parse(transform.group(1)!);
        final offsetY = double.parse(transform.group(2)!);
        final scale = double.parse(transform.group(3)!);
        final rect = LogoComposition(design, iconOnly: true).markRect;
        expect(rect.left * scale + offsetX, closeTo(1024 * .14, .01));
        expect(rect.top * scale + offsetY, closeTo(1024 * .14, .01));
        final decoded = await pixels(await logoPng(design, iconOnly: true));
        expect((decoded.$1, decoded.$2), (1024, 1024));
        expect(decoded.$3.width, closeTo(1024 * .72, 2));
        expect(decoded.$3.height, closeTo(decoded.$3.width, 1));
        expect(decoded.$3.center.dx, closeTo(512, 1));
        expect(decoded.$3.center.dy, closeTo(512, 1));
        expect(
          decoded.$4[3],
          0,
          reason: 'Export corners retain real transparency',
        );
      });
    },
  );

  testWidgets('wide exports fill their canvas without stretching or clipping', (
    t,
  ) async {
    await t.runAsync(() async {
      final full = await pixels(await logoPng(brand, width: 600, height: 300));
      expect((full.$1, full.$2), (600, 300));
      expect(full.$3.width, greaterThan(500));
      expect(full.$3.left, greaterThanOrEqualTo(22));
      expect(full.$3.right, lessThanOrEqualTo(578));
      expect(full.$3.top, greaterThan(0));
      expect(full.$3.bottom, lessThan(300));
      final svg = await logoSvg(
        brand,
        width: 600,
        height: 300,
        surface: LogoSurface.dark,
        ink: LogoInk.white,
      );
      expect(svg, contains('viewBox="0 0 600 300"'));
      expect(svg, contains('<rect width="600" height="300" fill="#111927"/>'));
      expect(svg, isNot(contains('fill="#2563EB"')));
    });
  });

  testWidgets(
    'single-color PNGs contain only selected ink and transparent space',
    (t) async {
      await t.runAsync(() async {
        for (final ink in [LogoInk.black, LogoInk.white]) {
          final expected = ink == LogoInk.white ? 255 : 0;
          for (final design in [brand, brand.copy(layout: 'Monogram')]) {
            final rgba = (await pixels(
              await logoPng(design, width: 256, height: 256, ink: ink),
            )).$4;
            for (var i = 0; i < rgba.length; i += 4) {
              if (rgba[i + 3] != 255) continue;
              expect(rgba.sublist(i, i + 3), [expected, expected, expected]);
            }
            expect(rgba[3], 0);
          }
        }
        final blackOnDark = LogoComposition(
          brand,
          surface: LogoSurface.dark,
          ink: LogoInk.black,
        );
        expect(blackOnDark.foreground, '000000');
        expect(
          blackOnDark.lettering.every((line) => line.color == '000000'),
          isTrue,
        );
      });
    },
  );

  testWidgets(
    'artwork validation rejects truncated and oversized PNGs before export',
    (t) async {
      await t.runAsync(() async {
        final valid = await logoPng(brand, width: 120, height: 80);
        await validateLogoArtwork(valid);
        await expectLater(
          validateLogoArtwork(Uint8List.fromList(valid.take(33).toList())),
          throwsFormatException,
        );
        final oversized = Uint8List.fromList(valid);
        ByteData.sublistView(oversized).setUint32(16, 1000000);
        await expectLater(
          validateLogoArtwork(oversized),
          throwsFormatException,
        );
      });
    },
  );

  testWidgets(
    'brand guide supports maximum-length names and taglines on one page',
    (t) async {
      await t.runAsync(() async {
        final pdf = await logoBrandGuide(
          brand.copy(name: 'W' * 50, tagline: 'W' * 80),
        );
        expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
        expect(
          RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(pdf)).length,
          1,
        );
        final directory = Platform.environment['LOGO_EXPORT_REVIEW_DIR'];
        if (directory != null) {
          await Directory(directory).create(recursive: true);
          await File('$directory/long-brand-guide.pdf').writeAsBytes(pdf);
        }
      });
    },
  );

  testWidgets(
    'brand kit includes all lockups and monochrome PNGs without changing the saved design',
    (t) async {
      await t.runAsync(() async {
        final before = jsonEncode(brand.json);
        final progress = <int>[];
        final archive = ZipDecoder().decodeBytes(
          await logoBrandKit(
            brand,
            onProgress: (done, total, stage) {
              expect(total, 26);
              expect(stage, isNotEmpty);
              progress.add(done);
            },
          ),
        );
        expect(progress, List.generate(27, (index) => index));
        final names = archive.files.map((f) => f.name);
        expect(
          names,
          containsAll([
            'logos/black-2400.png',
            'logos/white-2400.png',
            for (final layout in [
              'horizontal',
              'stacked',
              'wordmark',
              'monogram',
            ]) ...['layouts/$layout.svg', 'layouts/$layout-2400.png'],
          ]),
        );
        expect(
          utf8.decode(archive.findFile('social/icon.svg')!.content),
          contains('viewBox="0 0 1024 1024"'),
        );
        final project = jsonDecode(
          utf8.decode(archive.findFile('project.korlix-logo.json')!.content),
        );
        expect(project, brand.json);
        expect(jsonEncode(brand.json), before);
        final png = archive.findFile('logos/white-2400.png')!.content;
        expect(ByteData.sublistView(png).getUint32(16), 2400);
        expect(ByteData.sublistView(png).getUint32(20), 1600);
      });
    },
  );
}
