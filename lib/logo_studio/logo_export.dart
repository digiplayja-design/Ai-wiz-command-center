import 'dart:convert';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'logo_model.dart';
import 'logo_render.dart';

/// Verify optional AI artwork is a complete, decodable PNG before download.
Future<void> validateLogoArtwork(Uint8List bytes) async {
  const message =
      'This artwork could not be opened. Generate a new AI concept.';
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 33 || bytes.length > 32 * 1024 * 1024) {
    throw const FormatException(message);
  }
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) throw const FormatException(message);
  }
  final header = ByteData.sublistView(bytes);
  final width = header.getUint32(16), height = header.getUint32(20);
  if (header.getUint32(8) != 13 ||
      ascii.decode(bytes.sublist(12, 16), allowInvalid: true) != 'IHDR' ||
      width == 0 ||
      height == 0 ||
      width * height > 32000000) {
    throw const FormatException(message);
  }
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    image = (await codec.getNextFrame()).image;
    if (image.width != width || image.height != height) {
      throw const FormatException(message);
    }
  } catch (_) {
    throw const FormatException(message);
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

final _svgFontStyles = <String, Future<String>>{};
Future<String> _logoSvgFonts(String face) => _svgFontStyles.putIfAbsent(
  face,
  () => _loadSvgFonts(face).catchError((Object error) {
    _svgFontStyles.remove(face);
    throw error;
  }),
);
Future<String> _loadSvgFonts(String face) async {
  final buffer = StringBuffer('<defs><style>');
  Future<void> font(String asset, String family, String weight) async {
    final data = await rootBundle.load(asset);
    buffer.write(
      '@font-face{font-family:$family;src:url(data:font/ttf;base64,${base64Encode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))}) format("truetype");font-weight:$weight;}',
    );
  }

  await font('assets/fieldproof/Roboto-Regular.ttf', 'KorlixLogo', '400');
  if (isClassicLogoFont(face)) {
    await font('assets/fieldproof/Roboto-Bold.ttf', 'KorlixLogo', '700');
  } else {
    final selected = logoFontFor(face);
    await font(
      selected.asset,
      selected.family,
      selected.variable ? '100 900' : '${selected.weight}',
    );
  }
  buffer.write('</style></defs>');
  return buffer.toString();
}

Future<String> logoSvg(
  LogoDesign design, {
  LogoSurface surface = LogoSurface.transparent,
  LogoInk ink = LogoInk.color,
  bool iconOnly = false,
  int? width,
  int? height,
}) async {
  await ensureLogoFonts(design.typeface);
  final fonts = await _logoSvgFonts(design.typeface);
  return LogoComposition(
    design,
    surface: surface,
    ink: ink,
    iconOnly: iconOnly,
  ).svg(fontStyle: fonts, width: width, height: height);
}

Future<Uint8List> logoBrandGuide(
  LogoDesign design, {
  Uint8List? preview,
}) async {
  final image =
      preview ??
      await logoPng(
        design,
        surface: LogoSurface.light,
        width: 1200,
        height: 800,
      );
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fieldproof/Roboto-Bold.ttf'),
  );
  final doc = pw.Document(
    title: '${design.name} brand guide',
    author: 'KORLIX Logo Studio',
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'BRAND NOTES / KORLIX LOGO STUDIO',
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey600,
              letterSpacing: 1.5,
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            design.name,
            style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
          ),
          if (design.tagline.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                design.tagline,
                style: const pw.TextStyle(fontSize: 12),
              ),
            ),
          pw.SizedBox(height: 22),
          pw.Image(pw.MemoryImage(image), height: 240, fit: pw.BoxFit.contain),
          pw.SizedBox(height: 24),
          pw.Text(
            'COLOR PALETTE',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              for (final hex in [
                design.primary,
                design.secondary,
                design.paper,
              ])
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        height: 38,
                        margin: const pw.EdgeInsets.only(right: 8),
                        color: PdfColor.fromHex(hex),
                      ),
                      pw.SizedBox(height: 7),
                      pw.Text('#$hex', style: const pw.TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 26),
          pw.Text(
            'TYPOGRAPHY & COMPOSITION',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            '${logoFontFor(design.typeface).name} / ${design.typeface}\n${design.layout} composition / ${design.mark} symbol\nLetter spacing: ${design.tracking.toStringAsFixed(1)}',
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 4),
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            'USING YOUR LOGO',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Keep clear space around the mark. Use the transparent PNG on compatible backgrounds and the light or dark version for strong contrast. Avoid stretching, cropping, or adding effects. Test readability at the size you will use.',
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 4),
          ),
          pw.Spacer(),
          pw.Text(
            'SVG contains vector shapes and editable text. The matching fonts and licenses are included in the kit. PNG exports are raster images. Keep your project JSON to edit again in KORLIX.',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey600,
              lineSpacing: 3,
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

Future<Uint8List> logoBrandKit(
  LogoDesign design, {
  void Function()? checkCurrent,
  void Function(int completed, int total, String stage)? onProgress,
}) async {
  checkCurrent?.call();
  final output = OutputMemoryStream();
  final encoder = ZipEncoder()..startEncode(output);
  final total = isClassicLogoFont(design.typeface) ? 26 : 28;
  var completed = 0;
  Future<void> add(String name, List<int> bytes) async {
    checkCurrent?.call();
    encoder.add(ArchiveFile(name, bytes.length, bytes));
    completed++;
    final stage = name.startsWith('social/')
        ? 'Preparing social assets'
        : name.startsWith('layouts/')
        ? 'Building logo layouts'
        : name.startsWith('fonts/') || name == 'READ-ME.txt'
        ? 'Finishing your kit'
        : name == 'brand-guide.pdf'
        ? 'Creating your brand guide'
        : 'Building your logo files';
    onProgress?.call(completed, total, '$stage · $completed of $total');
    // Yield between files so the browser can paint progress and respond to
    // navigation/session changes. Do not retain every uncompressed kit asset.
    await Future<void>.delayed(Duration.zero);
    checkCurrent?.call();
  }

  Future<void> text(String name, String value) => add(name, utf8.encode(value));
  onProgress?.call(0, total, 'Building your logo files');
  await Future<void>.delayed(Duration.zero);
  for (final entry in [
    ('primary', LogoInk.color),
    ('black', LogoInk.black),
    ('white', LogoInk.white),
  ]) {
    await text('logos/${entry.$1}.svg', await logoSvg(design, ink: entry.$2));
  }
  await add('logos/transparent-2400.png', await logoPng(design));
  await add('logos/black-2400.png', await logoPng(design, ink: LogoInk.black));
  await add('logos/white-2400.png', await logoPng(design, ink: LogoInk.white));
  final light = await logoPng(design, surface: LogoSurface.light);
  await add('logos/light-2400.png', light);
  await add(
    'logos/dark-2400.png',
    await logoPng(design, surface: LogoSurface.dark),
  );
  // Export the same identity in useful lockups, without changing the project.
  for (final layout in ['Horizontal', 'Stacked', 'Wordmark', 'Monogram']) {
    final variant = design.copy(layout: layout);
    final name = layout.toLowerCase();
    await text('layouts/$name.svg', await logoSvg(variant));
    await add('layouts/$name-2400.png', await logoPng(variant));
  }
  await text('social/icon.svg', await logoSvg(design, iconOnly: true));
  await add(
    'social/avatar-1024.png',
    await logoPng(
      design,
      surface: LogoSurface.light,
      width: 1024,
      height: 1024,
      iconOnly: true,
    ),
  );
  await add(
    'social/icon-transparent-512.png',
    await logoPng(design, width: 512, height: 512, iconOnly: true),
  );
  await add(
    'social/cover-1500x500.png',
    await logoPng(
      design.copy(layout: 'Horizontal'),
      surface: LogoSurface.dark,
      width: 1500,
      height: 500,
    ),
  );
  await add('brand-guide.pdf', await logoBrandGuide(design, preview: light));
  await text(
    'project.korlix-logo.json',
    const JsonEncoder.withIndent('  ').convert(design.json),
  );
  for (final style in ['Regular', 'Bold']) {
    await add(
      'fonts/Roboto-$style.ttf',
      (await rootBundle.load(
        'assets/fieldproof/Roboto-$style.ttf',
      )).buffer.asUint8List(),
    );
  }
  await text(
    'fonts/LICENSE.txt',
    await rootBundle.loadString('assets/fieldproof/Roboto_LICENSE.txt'),
  );
  if (!isClassicLogoFont(design.typeface)) {
    final selected = logoFontFor(design.typeface);
    await add(
      'fonts/${selected.name.replaceAll(' ', '-')}.ttf',
      (await rootBundle.load(selected.asset)).buffer.asUint8List(),
    );
    await text(
      'fonts/${selected.slug}-OFL.txt',
      await rootBundle.loadString(selected.license),
    );
  }
  await text(
    'READ-ME.txt',
    '${design.name} / KORLIX Logo Studio\n\nYour editable logo collection and brand guide.\n\nPalette: #${design.primary}, #${design.secondary}, #${design.paper}\nTypography: ${logoFontFor(design.typeface).name} / ${design.typeface}. Some SVG editors may require installing the bundled fonts to preserve lettering.\n\nSVG logos contain real vector shapes and editable text; PNG files are raster images. The primary PNG is 2400 x 1600 pixels. Transparent black and white PNGs are included for single-color use. The layouts folder includes horizontal, stacked, wordmark and monogram SVG/PNG versions of your identity.\n\nAvatar and icon SVG are square, with proportional safe space. Avatar is 1024 x 1024; cover is 1500 x 500. Social sizes are general-purpose canvases; check each platform before publishing. White transparent logos need a dark background to be visible.\n\nTo edit again, open Logo Studio > Saved > Import project and choose project.korlix-logo.json. Saved projects in the app stay in this browser/device and account. Keep this backup.\n\nOptional AI artwork is exported separately as a PNG; it is not vectorized by this kit.\n\nFont licenses are included in the fonts folder. Install the selected family to edit the lettering in design software. Roboto is used for the supporting text.\n',
  );
  checkCurrent?.call();
  encoder.endEncode();
  return output.getBytes();
}
