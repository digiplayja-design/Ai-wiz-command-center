import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_wiz_command_center/social/social_dump_truck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _scene = ValueKey('social-dump-scene');
const _truck = ValueKey('social-dump-truck');
const _preview = ValueKey('social-dump-preview');
const _capture = ValueKey('dump-capture');

Future<void> _mount(
  WidgetTester tester, {
  required VoidCallback onComplete,
  double width = 800,
  double height = 600,
  bool reducedMotion = false,
  bool dark = false,
  double textScale = 1,
  double? pickupY,
  VoidCallback? onBackgroundTap,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        fontFamily: 'Roboto',
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          disableAnimations: reducedMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: RepaintBoundary(
          key: _capture,
          child: Scaffold(
            backgroundColor: dark
                ? const Color(0xFF071626)
                : const Color(0xFFF0F6FD),
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onBackgroundTap,
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned.fill(
                  child: SocialDumpTruck(
                    preview:
                        'The blue folder is ready for tomorrow.\nThank you!',
                    onComplete: onComplete,
                    pickupY: pickupY,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('truck enters, scoops the selected message, and carries it off', (
    tester,
  ) async {
    var completions = 0;
    await _mount(tester, onComplete: () => completions++);
    final startingTruck = tester.getTopLeft(find.byKey(_truck));
    await tester.pump(const Duration(milliseconds: 1500));
    final parkedTruck = tester.getTopLeft(find.byKey(_truck));
    final waitingMessage = tester.getCenter(find.byKey(_preview));
    expect(parkedTruck.dx, greaterThan(startingTruck.dx));
    expect(find.text('Auto dump · Picking it up'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    final liftedMessage = tester.getCenter(find.byKey(_preview));
    expect(liftedMessage.dy, lessThan(waitingMessage.dy - 50));
    expect(liftedMessage.dx, lessThan(waitingMessage.dx - 50));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byKey(_preview), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(_truck)).dx,
      greaterThan(parkedTruck.dx),
    );
    expect(find.text('Auto dump · Carrying it away'), findsOneWidget);
    expect(completions, 0);
    await tester.pump(const Duration(milliseconds: 650));
    expect(completions, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(completions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion uses a short stationary notice without a truck', (
    tester,
  ) async {
    var completions = 0;
    await _mount(tester, onComplete: () => completions++, reducedMotion: true);
    expect(find.byKey(_scene), findsNothing);
    expect(find.byKey(_truck), findsNothing);
    expect(find.byKey(_preview), findsNothing);
    final notice = find.text('Message removed from your history');
    final position = tester.getCenter(notice);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getCenter(notice), position);
    expect(completions, 0);
    await tester.pump(const Duration(milliseconds: 160));
    expect(completions, 1);
  });

  testWidgets('overlay allows interaction with the underlying conversation', (
    tester,
  ) async {
    var taps = 0;
    await _mount(tester, onComplete: () {}, onBackgroundTap: () => taps++);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.tapAt(tester.getCenter(find.byKey(_preview)));
    expect(taps, 1);
  });

  testWidgets('dismissal cancels animation without firing completion later', (
    tester,
  ) async {
    var completions = 0;
    await _mount(tester, onComplete: () => completions++);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 8));
    expect(completions, 0);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      '320px ${dark ? 'dark' : 'light'} scene fits with double text',
      (tester) async {
        await _mount(
          tester,
          onComplete: () {},
          width: 320,
          height: 480,
          pickupY: 10,
          dark: dark,
          textScale: 2,
        );
        await tester.pump(const Duration(milliseconds: 2100));
        expect(tester.getRect(find.byKey(_scene)).left, 0);
        expect(tester.getRect(find.byKey(_scene)).right, 320);
        expect(tester.getRect(find.byKey(_scene)).top, greaterThanOrEqualTo(0));
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 3));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('announcement excludes message text from animation semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _mount(tester, onComplete: () {});
    await tester.pump(const Duration(milliseconds: 1600));
    expect(
      find.bySemanticsLabel(
        'Auto dump: removing the selected message from your history.',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('The blue folder')), findsNothing);
    semantics.dispose();
  });

  if (const bool.fromEnvironment('CAPTURE_DUMP')) {
    testWidgets('capture truck artwork with actual font', (tester) async {
      final loader = FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'));
      await loader.load();
      for (final dark in [false, true]) {
        await _mount(
          tester,
          onComplete: () {},
          width: 390,
          height: 650,
          dark: dark,
        );
        await tester.pump(const Duration(milliseconds: 1600));
        for (final stage in ['pickup', 'lift', 'loaded']) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(_capture),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final output = File(
              '/tmp/social-dump-${dark ? 'dark' : 'light'}-$stage.png',
            );
            await output.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
          await tester.pump(const Duration(milliseconds: 700));
        }
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}
