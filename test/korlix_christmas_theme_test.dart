import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_wiz_command_center/auth/korlix_entry_welcome.dart';
import 'package:ai_wiz_command_center/theme/korlix_appearance_preferences.dart';
import 'package:ai_wiz_command_center/theme/korlix_button_colors.dart';
import 'package:ai_wiz_command_center/theme/korlix_christmas_greeting.dart';
import 'package:ai_wiz_command_center/theme/korlix_default_appearance.dart';
import 'package:ai_wiz_command_center/theme/korlix_screen_skin.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the main hub starts with Christmas and restores an explicit saved look', () async {
    final previous = kKorlixThemeNotifier.value;
    addTearDown(() => kKorlixThemeNotifier.value = previous);
    await restoreKorlixDefaultAppearance();
    expect(kKorlixThemeNotifier.value, 'christmas_red');
    SharedPreferences.setMockInitialValues({
      KorlixAppearancePreferences.storageKey:
          jsonEncode({'theme': 'ocean_blue', 'skin': 'classic'}),
    });
    await restoreKorlixDefaultAppearance();
    expect(kKorlixThemeNotifier.value, 'ocean_blue');
    SharedPreferences.setMockInitialValues({'korlix_ui_theme': 'ultra_gold'});
    await restoreKorlixDefaultAppearance();
    expect(kKorlixThemeNotifier.value, 'ultra_gold');
  });

  test('Christmas actions use red while other themes keep feature colors', () {
    for (final label in ['Continue', 'Save', 'Imagine Studio', 'Voice']) {
      final colors = korlixButtonColorsFor(label, themeId: 'christmas_red');
      expect(colors.id, 'christmas_red');
      expect(colors.foreground, Colors.white);
      expect(korlixButtonColorsFor(label, themeId: 'ocean_blue').id,
          korlixButtonColorsFor(label).id);
    }
    expect(korlixButtonColorsFor('Delete draft', themeId: 'christmas_red').id,
        'danger');
  });

  testWidgets('Christmas welcome fits phones and enlarged text; controls work', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final output = Platform.environment['KORLIX_CHRISTMAS_REVIEW'];
    if (output != null) {
      await tester.runAsync(() async {
        final sdk = Platform.environment['KORLIX_FLUTTER_ROOT']!;
        for (final font in [
          ('MaterialIcons', '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),
          ('Roboto', 'assets/fieldproof/Roboto-Regular.ttf'),
        ]) {
          await (FontLoader(font.$1)..addFont(File(font.$2).readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)))).load();
        }
      });
    }
    for (final size in [const Size(390, 1100), const Size(320, 1300), const Size(820, 1180)]) {
      tester.view.physicalSize = size;
      final largeText = size.width == 320;
      final boundary = GlobalKey();
      var signups = 0;
      final palette = korlixSkinPaletteFor('christmas_red');
      await tester.pumpWidget(MaterialApp(
        theme: korlixBuildTheme('christmas_red'),
        home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(largeText ? 2 : 1),
              disableAnimations: true),
          child: RepaintBoundary(key: boundary, child: Scaffold(
            body: KorlixScreenBackdrop(palette: palette, skinId: 'classic',
              child: SingleChildScrollView(child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(padding: const EdgeInsets.all(24),
                  child: KorlixEntryWelcome(onCreateAccount: () => signups++, onSignIn: () {})),
              ))),
            ),
          )),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Create a little Christmas magic'), findsOneWidget);
      if (output != null && !largeText) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$output/christmas-welcome-${size.width.toInt()}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      final signup = find.byKey(const Key('welcome-create-account'));
      await tester.ensureVisible(signup);
      await tester.tap(signup);
      await tester.pumpAndSettle();
      expect(signups, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Christmas decoration disappears when a different theme is selected', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: korlixBuildTheme('ocean_blue'),
        home: const Scaffold(body: KorlixChristmasGreeting())));
    expect(find.text('Create a little Christmas magic'), findsNothing);
  });
}
