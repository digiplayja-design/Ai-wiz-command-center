import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/auth/korlix_welcome_confirmation.dart';
import 'package:ai_wiz_command_center/input_tools/upload_studio.dart';
import 'package:ai_wiz_command_center/input_tools/voice_composer.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

void main() {
  testWidgets('input studios and welcome fit phones, themes and enlarged text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final output = Platform.environment['KORLIX_INPUT_REVIEW'];
    if (output != null) {
      await tester.runAsync(() async {
        final sdk = Platform.environment['KORLIX_FLUTTER_ROOT']!;
        for (final font in [
          (
            'MaterialIcons',
            '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
          ('Roboto', 'assets/fieldproof/Roboto-Regular.ttf'),
        ]) {
          await (FontLoader(font.$1)..addFont(
                File(
                  font.$2,
                ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
              ))
              .load();
        }
      });
    }
    for (final theme in ['korlix_blue', 'pure_white', 'pure_black']) {
      for (final review in [(390.0, 1.0), (320.0, 2.0), (1000.0, 1.0)]) {
        tester.view.physicalSize = Size(
          review.$1,
          review.$2 == 2 ? 2000 : 1300,
        );
        for (final page in ['upload', 'voice', 'welcome']) {
          final boundary = GlobalKey();
          Widget screen;
          if (page == 'upload') {
            screen = KorlixUploadStudio(
              initialFiles: [
                PlatformFile(
                  name: 'Quarterly-inventory.pdf',
                  size: 32000,
                  bytes: Uint8List.fromList([1, 2, 3]),
                ),
              ],
            );
          } else if (page == 'voice') {
            screen = const KorlixVoiceComposer(
              initialText: 'Find inventory near me',
            );
          } else {
            screen = Scaffold(
              body: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: KorlixWelcomeConfirmation(
                        email: 'member@example.com',
                        onSignIn: () {},
                        onChangeEmail: () {},
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          await tester.pumpWidget(
            MaterialApp(
              theme: korlixBuildTheme(theme),
              home: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(review.$2),
                  disableAnimations: true,
                ),
                child: RepaintBoundary(key: boundary, child: screen),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$theme $page $review',
          );
          if (output != null && review.$2 == 1) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 1.5);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '$output/$page-$theme-${review.$1.toInt()}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          final scroll = find.byType(Scrollable).first;
          await tester.drag(scroll, const Offset(0, -1600));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Scrolled $theme $page $review',
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      }
    }
  });
}
