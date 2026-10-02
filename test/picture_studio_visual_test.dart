import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/improve_picture/picture_studio_client.dart';
import 'package:ai_wiz_command_center/improve_picture/picture_studio_screen.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

// A locally drawn fixture makes layout review independent of personal photos,
// external image hosts, or a paid generation request.
Future<Uint8List> _landscape() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const bounds = Rect.fromLTWH(0, 0, 720, 540);
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF64B8EA), Color(0xFFFCE9C3)],
      ).createShader(bounds),
  );
  canvas.drawCircle(
    const Offset(540, 145),
    56,
    Paint()..color = const Color(0xFFFFCB66),
  );
  canvas.drawPath(
    Path()
      ..moveTo(0, 390)
      ..lineTo(220, 180)
      ..lineTo(510, 440)
      ..lineTo(720, 280)
      ..lineTo(720, 540)
      ..lineTo(0, 540)
      ..close(),
    Paint()..color = const Color(0xFF6F8B85),
  );
  canvas.drawPath(
    Path()
      ..moveTo(0, 420)
      ..quadraticBezierTo(210, 290, 440, 460)
      ..quadraticBezierTo(600, 360, 720, 430)
      ..lineTo(720, 540)
      ..lineTo(0, 540)
      ..close(),
    Paint()..color = const Color(0xFF254E51),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(720, 540);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets(
    'studio renders upload and result flows across themes and screen sizes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final output = Platform.environment['KORLIX_PICTURE_REVIEW'];
      late Uint8List bytes;
      await tester.runAsync(() async {
        bytes = await _landscape();
        if (output != null) {
          final sdk = Platform.environment['KORLIX_FLUTTER_ROOT']!;
          for (final font in [
            (
              'MaterialIcons',
              '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ),
            ('Roboto', 'assets/fieldproof/Roboto-Regular.ttf'),
          ]) {
            await (FontLoader(font.$1)..addFont(
                  File(font.$2).readAsBytes().then(ByteData.sublistView),
                ))
                .load();
          }
        }
      });
      for (final theme in ['korlix_blue', 'pure_white', 'pink_white']) {
        for (final width in [390.0, 1440.0]) {
          tester.view.physicalSize = Size(width, 1100);
          final boundary = GlobalKey();
          final file = PlatformFile(
            name: 'local-landscape.png',
            size: bytes.length,
            bytes: bytes,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: korlixBuildTheme(theme),
              home: RepaintBoundary(
                key: boundary,
                child: PictureStudioScreen(
                  pickPhoto: () async => file,
                  ensureConsent: () async => true,
                  onOpenTemplates: () {},
                  onImprove: (_, _) async => PictureEditResult(
                    bytes: bytes,
                    summary:
                        'Local layout fixture; no AI generation was requested.',
                    quality: 'max',
                    size: '720x540',
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$theme $width upload',
          );
          Future<void> capture(String state) async {
            if (output == null) return;
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 1);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('$output/$theme-${width.toInt()}-$state.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }

          await capture('upload');
          await tester.ensureVisible(find.text('Choose photo'));
          await tester.tap(find.text('Choose photo'));
          await tester.pumpAndSettle();
          final colors = find.text('Color & lighting');
          await tester.ensureVisible(colors);
          await tester.tap(colors);
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('picture-look-vivid')),
          );
          await tester.tap(find.byKey(const ValueKey('picture-look-vivid')));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$theme $width color controls',
          );
          await capture('colors');
          final submit = find.byKey(const Key('improve-picture-submit'));
          await tester.ensureVisible(submit);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$theme $width controls',
          );
          await capture('controls');
          await tester.tap(submit);
          await tester.pumpAndSettle();
          expect(find.text('Save PNG'), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: '$theme $width result',
          );
          await capture('result');
          await tester.ensureVisible(
            find.byKey(const ValueKey('picture-compare-side')),
          );
          await tester.tap(find.byKey(const ValueKey('picture-compare-side')));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$theme $width comparison',
          );
          await capture('comparison');
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      }
    },
  );
}
