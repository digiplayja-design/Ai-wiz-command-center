import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/chat/chat_workspace.dart';
import 'package:ai_wiz_command_center/theme/korlix_action_button.dart';
import 'package:ai_wiz_command_center/theme/korlix_action_grid.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

Widget app(
  Widget child, {
  String theme = 'korlix_blue',
  double scale = 1,
  bool reduceMotion = false,
}) => MaterialApp(
  theme: korlixBuildTheme(theme),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduceMotion,
      ),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  testWidgets(
    'native activation works once with pointer, Enter and Space; disabled cannot activate',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var calls = 0;
      await tester.pumpWidget(
        app(
          KorlixActionButton(
            label: 'Upload',
            icon: Icons.upload_rounded,
            focusNode: focus,
            onPressed: () => calls++,
          ),
        ),
      );
      await tester.tap(find.text('Upload'));
      expect(calls, 1);
      focus.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(calls, 3);
      await tester.pumpWidget(
        app(
          const KorlixActionButton(
            label: 'Upload',
            icon: Icons.upload_rounded,
            onPressed: null,
          ),
        ),
      );
      await tester.tap(find.text('Upload'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, 3);
      expect(
        tester.getSemantics(find.byType(TextButton)),
        matchesSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          label: 'Upload',
        ),
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'locked opens access options, selected is announced and busy send cannot repeat',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var access = 0, send = 0;
      await tester.pumpWidget(
        app(
          Wrap(
            children: [
              KorlixActionButton(
                label: 'Upload',
                locked: true,
                icon: Icons.upload_rounded,
                onPressed: () => access++,
              ),
              KorlixActionButton(
                label: 'Voice',
                selected: true,
                icon: Icons.mic_rounded,
                onPressed: () {},
              ),
              KorlixActionButton(
                label: 'Sending',
                iconOnly: true,
                busy: true,
                icon: Icons.arrow_upward,
                onPressed: () => send++,
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Upload'));
      await tester.tap(find.byTooltip('Sending'));
      expect(access, 1);
      expect(send, 0);
      final selected = tester
          .getSemantics(find.widgetWithText(KorlixActionButton, 'Voice'))
          .getSemanticsData();
      expect(selected.flagsCollection.isSelected, ui.Tristate.isTrue);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'hover and pointer cancellation preserve activation; reduced motion stays still',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        app(
          KorlixActionButton(label: 'Camera Ask', onPressed: () => calls++),
          reduceMotion: true,
        ),
      );
      final target = find.byType(TextButton);
      final position = tester.getCenter(target);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(position);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(position);
      await tester.pump();
      final surface = tester.widget<AnimatedContainer>(
        find
            .descendant(of: target, matching: find.byType(AnimatedContainer))
            .last,
      );
      expect(surface.duration, Duration.zero);
      expect(surface.transform!.getTranslation().y, 0);
      await gesture.cancel();
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(target);
      expect(calls, 1);
    },
  );

  testWidgets(
    'front controls fit all themes on a narrow phone at 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final theme in korlixThemeIds) {
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: _ButtonReview(),
              ),
            ),
            theme: theme,
            scale: 2,
            reduceMotion: true,
          ),
        );
        await tester.pumpAndSettle();
        for (final button in find.byType(TextButton).evaluate()) {
          final box = button.renderObject! as RenderBox;
          expect(box.size.width, greaterThanOrEqualTo(48));
          expect(box.size.height, greaterThanOrEqualTo(48));
        }
        expect(tester.takeException(), isNull, reason: theme);
      }
    },
  );

  testWidgets('visual review of the shipping controls on mobile and desktop', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final output = Platform.environment['KORLIX_BUTTON_REVIEW'];
    if (output != null) {
      final sdk = Platform.environment['KORLIX_FLUTTER_ROOT']!;
      await tester.runAsync(() async {
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            File(
              '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          );
        final font = FontLoader('Roboto')
          ..addFont(
            File(
              'assets/fieldproof/Roboto-Regular.ttf',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          );
        await icons.load();
        await font.load();
      });
    }
    for (final review in [
      ('korlix_blue', 390.0),
      ('pure_black', 390.0),
      ('pure_white', 390.0),
      ('korlix_blue', 1000.0),
    ]) {
      tester.view.physicalSize = Size(review.$2, 2700);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: korlixSkinPaletteFor(review.$1).backgroundMid,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'KORLIX AI',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    _ButtonReview(),
                  ],
                ),
              ),
            ),
          ),
          theme: review.$1,
          reduceMotion: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (output != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$output/${review.$1}-${review.$2.toInt()}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}

class _ButtonReview extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      KorlixChatModeBar(
        imageMode: false,
        busy: false,
        size: 'auto',
        style: 'auto',
        onModeChanged: (_) {},
        onSizeChanged: (_) {},
        onStyleChanged: (_) {},
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          const Expanded(
            child: TextField(
              decoration: InputDecoration(hintText: 'Ask anything…'),
            ),
          ),
          const SizedBox(width: 10),
          KorlixActionButton(
            label: 'Send',
            icon: Icons.arrow_upward_rounded,
            iconOnly: true,
            onPressed: () {},
          ),
        ],
      ),
      const SizedBox(height: 18),
      KorlixLiveConvoButton(onPressed: () {}),
      const SizedBox(height: 18),
      KorlixActionSection(
        title: 'Start here',
        description: 'Choose how you want to work with K-Nova.',
        icon: Icons.tune_rounded,
        children: [
          for (final entry in [
            ('Upload', 'Files & photos', Icons.upload_file_rounded),
            ('Voice', 'Speak or type', Icons.mic_rounded),
            (
              'Camera Ask',
              'See it. Ask it.',
              Icons.center_focus_strong_rounded,
            ),
            ('More tools', 'Open the toolbox', Icons.apps_rounded),
          ])
            KorlixActionButton(
              label: entry.$1,
              subtitle: entry.$2,
              icon: entry.$3,
              tile: true,
              onPressed: () {},
            ),
        ],
      ),
      const SizedBox(height: 30),
      for (final section in [
        (
          'For business',
          'Manage operations, grow your reach, and get work done.',
          Icons.business_center_outlined,
          [
            'Inventory Studio',
            'Bookkeeping 2027',
            'FieldProof',
            'AI Visibility',
            'Contract Radar',
            'Workforce',
            'Email enhancer',
            'Create an App',
          ],
        ),
        (
          'For personal use',
          'Create, learn, organize, and explore your everyday life.',
          Icons.person_outline_rounded,
          [
            'Tax Prep',
            'BabyBlend',
            'Virtual Closet',
            'Cybersecurity Defender',
            'Improve my picture',
            'Study / learn',
            'Music Studio',
            'Locator',
          ],
        ),
      ]) ...[
        KorlixActionSection(
          title: section.$1,
          description: section.$2,
          icon: section.$3,
          children: [
            for (final tool in section.$4)
              KorlixActionButton(
                label: tool,
                icon: korlixToolIcon(tool),
                tile: true,
                onPressed: () {},
              ),
          ],
        ),
        const SizedBox(height: 30),
      ],
    ],
  );
}
