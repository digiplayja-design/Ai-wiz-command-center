import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_wiz_command_center/characters/button_climbers.dart';
import 'package:ai_wiz_command_center/characters/button_climber_painter.dart';
import 'package:ai_wiz_command_center/characters/button_climber_artwork.dart';
import 'package:ai_wiz_command_center/characters/button_climbers_settings.dart';
import 'package:ai_wiz_command_center/theme/korlix_action_button.dart';
import 'package:ai_wiz_command_center/theme/korlix_action_grid.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:ai_wiz_command_center/theme/korlix_smoke_screensaver.dart';
import 'package:ai_wiz_command_center/theme/korlix_screensaver_controller.dart';

Future<void> frames(WidgetTester tester, [int count = 3]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

KorlixButtonClimbersPainter painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byKey(
                const Key('button-climbers-canvas'),
                skipOffstage: false,
              ),
            )
            .painter!
        as KorlixButtonClimbersPainter;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await KorlixClimberArtwork.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'both figures climb up, wave, reach out, and return down continuously',
    () {
      for (final size in [
        const Size(320, 700),
        const Size(390, 844),
        const Size(1024, 900),
      ]) {
        final button = Rect.fromLTWH(40, 140, size.width - 80, 136);
        for (final woman in [false, true]) {
          KorlixClimberPose pose(double seconds) => KorlixClimberPose.at(
            seconds - (woman ? KorlixClimberPose.womanDelay : 0),
            button,
            size,
            woman: woman,
          );
          expect(pose(6).position.dy, lessThan(pose(1).position.dy));
          expect(pose(11).wave, 1);
          expect(pose(13).reach, 1);
          expect(pose(22).position.dy, greaterThan(pose(18).position.dy));
          expect(
            (pose(24.7999).position - pose(24.8001).position).distance,
            lessThan(.01),
          );
          for (var frame = 0; frame <= 270; frame++) {
            final point = pose(frame / 10).position;
            expect(point.dx, inInclusiveRange(0, size.width));
            expect(point.dy, inInclusiveRange(48, size.height - 30));
          }
        }
      }
    },
  );

  test(
    'planted hands and toes stay on the rounded edge while the body pulls up',
    () {
      const button = Rect.fromLTWH(40, 140, 310, 136);
      const size = Size(390, 844);
      for (final woman in [false, true]) {
        KorlixClimberPose pose(double seconds) => KorlixClimberPose.at(
          seconds - (woman ? KorlixClimberPose.womanDelay : 0),
          button,
          size,
          woman: woman,
        );
        final first = pose(.76), pulled = pose(1.08);
        expect(pulled.position.dy, lessThan(first.position.dy - 1));
        for (final points in [
          (first.handA, pulled.handA),
          (first.handB, pulled.handB),
          (first.footA, pulled.footA),
          (first.footB, pulled.footB),
        ]) {
          expect(
            (first.toViewport(points.$1) - pulled.toViewport(points.$2))
                .distance,
            lessThan(.001),
          );
        }
        for (final h in [96.0, 112.0, 136.0, 300.0]) {
          final ledge = Rect.fromLTWH(40, 140, 310, h);
          for (var frame = 0; frame < 496; frame++) {
            final p = KorlixClimberPose.at(
              frame * .05,
              ledge,
              size,
              woman: woman,
            );
            final contacts = [
              (p.handA, p.handAPlanted),
              (p.handB, p.handBPlanted),
              (p.footA, p.footAPlanted),
              (p.footB, p.footBPlanted),
            ];
            expect(contacts.where((c) => c.$2).length, greaterThanOrEqualTo(3));
            for (final c in contacts.where((c) => c.$2)) {
              expect(c.$1.dy, inInclusiveRange(0, h));
              expect(
                c.$1.dx,
                closeTo(KorlixClimberPose.edgeInset(c.$1.dy, h) + .5, .001),
              );
            }
          }
        }
      }
    },
  );

  test(
    'setting restores, serializes rapid changes, and protects a new choice from a late load',
    () async {
      final gate = Completer<SharedPreferences>();
      final controller = KorlixClimbersController(load: () => gate.future);
      final restoring = controller.restore();
      final saving = controller.setEnabled(false);
      gate.complete(await SharedPreferences.getInstance());
      await restoring;
      expect(await saving, isTrue);
      expect(controller.enabled, isFalse);
      await Future.wait([
        controller.setEnabled(true),
        controller.setEnabled(false),
      ]);
      final restored = KorlixClimbersController();
      await restored.restore();
      expect(restored.enabled, isFalse);
      controller.dispose();
      restored.dispose();
      final blocked = KorlixClimbersController(
        load: () async => throw StateError('Unavailable'),
      );
      await blocked.restore();
      expect(await blocked.setEnabled(false), isFalse);
      expect(blocked.enabled, isFalse);
      blocked.dispose();
    },
  );

  testWidgets(
    'live figures track real controls through scrolling and resizing without stealing taps',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = KorlixClimbersController();
      final scroll = ScrollController();
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: korlixBuildTheme('korlix_blue'),
          home: Scaffold(
            body: KorlixButtonClimbers(
              controller: controller,
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(32, 140, 32, 80),
                child: Column(
                  children: [
                    KorlixActionButton(
                      key: const Key('real-button'),
                      size: KorlixButtonSize.hero,
                      label: 'Find a tool',
                      expand: true,
                      onPressed: () => taps++,
                    ),
                    const SizedBox(height: 90),
                    for (var row = 0; row < 12; row++) ...[
                      KorlixActionGrid(
                        children: [
                          KorlixActionButton(
                            label: 'Upload $row',
                            tile: true,
                            onPressed: () => taps++,
                          ),
                          KorlixActionButton(
                            label: 'Camera Ask $row',
                            tile: true,
                            onPressed: () => taps++,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await frames(tester);
      final art = painter(tester);
      expect(art.visible.value, isTrue);
      final first = art.buttons.value.first;
      final elapsed = art.seconds.value;
      await tester.pump(const Duration(seconds: 2));
      expect(art.seconds.value, greaterThan(elapsed));
      final pose = KorlixClimberPose.at(
        art.seconds.value,
        first,
        const Size(390, 844),
        woman: false,
      );
      // Tap through the planted fingers on the button's real edge.
      await tester.tapAt(pose.toViewport(pose.handA) + const Offset(4, 0));
      await frames(tester);
      expect(taps, 1);
      scroll.jumpTo(40);
      await frames(tester);
      expect(art.buttons.value.first.top, closeTo(first.top - 40, .01));
      scroll.jumpTo(500);
      await frames(tester);
      expect(art.buttons.value, isNotEmpty);
      expect(
        art.buttons.value.every((r) => r.bottom > 0 && r.top < 844),
        isTrue,
      );
      tester.view.physicalSize = const Size(1024, 768);
      await frames(tester);
      expect(art.buttons.value.any((r) => r.width > 400), isTrue);
      await controller.setEnabled(false);
      final stopped = art.seconds.value;
      await tester.pump(const Duration(seconds: 2));
      expect(art.visible.value, isFalse);
      expect(art.seconds.value, stopped);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      scroll.dispose();
      controller.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'navigation, background, editing and reduced motion pause and hide the figures',
    (tester) async {
      final controller = KorlixClimbersController();
      final navigation = GlobalKey<NavigatorState>();
      final focus = FocusNode();
      final reduced = ValueNotifier(false);
      final tickers = ValueNotifier(true);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigation,
          home: ValueListenableBuilder<bool>(
            valueListenable: reduced,
            builder: (context, reduce, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
              child: ValueListenableBuilder<bool>(
                valueListenable: tickers,
                builder: (_, enabled, child) => TickerMode(
                  enabled: enabled,
                  child: Scaffold(
                    body: KorlixButtonClimbers(
                      controller: controller,
                      child: ListView(
                        padding: const EdgeInsets.all(80),
                        children: [
                          KorlixActionButton(
                            label: 'Visible control',
                            size: KorlixButtonSize.hero,
                            expand: true,
                            onPressed: () {},
                          ),
                          const SizedBox(height: 80),
                          TextField(focusNode: focus),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await frames(tester);
      var art = painter(tester);
      expect(art.visible.value, isTrue);
      unawaited(
        navigation.currentState!.push(
          DialogRoute<void>(
            context: navigation.currentContext!,
            builder: (_) => const AlertDialog(title: Text('Other screen')),
          ),
        ),
      );
      await frames(tester, 12);
      expect(art.visible.value, isFalse);
      final atModal = art.seconds.value;
      await tester.pump(const Duration(seconds: 3));
      expect(art.seconds.value, atModal);
      navigation.currentState!.pop();
      await frames(tester, 12);
      expect(art.visible.value, isTrue);
      focus.requestFocus();
      await frames(tester);
      expect(art.visible.value, isFalse);
      focus.unfocus();
      await frames(tester);
      expect(art.visible.value, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await frames(tester);
      expect(art.visible.value, isFalse);
      final paused = art.seconds.value;
      await tester.pump(const Duration(seconds: 20));
      expect(art.seconds.value, paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await frames(tester);
      expect(art.seconds.value - paused, lessThan(1));
      reduced.value = true;
      await frames(tester);
      art = painter(tester);
      expect(art.visible.value, isFalse);
      reduced.value = false;
      tickers.value = false;
      await frames(tester);
      expect(art.visible.value, isFalse);
      tickers.value = true;
      await frames(tester);
      expect(art.visible.value, isTrue);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      focus.dispose();
      reduced.dispose();
      tickers.dispose();
      controller.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'animated climbers do not reset smoke idle time or consume its wake tap',
    (tester) async {
      final controller = KorlixClimbersController();
      final smoke = KorlixScreensaverController();
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              KorlixSmokeScreensaver(controller: smoke, child: child!),
          home: Scaffold(
            body: KorlixButtonClimbers(
              controller: controller,
              child: ListView(
                padding: const EdgeInsets.all(100),
                children: [
                  KorlixActionButton(
                    key: const Key('smoke-underlying-button'),
                    size: KorlixButtonSize.hero,
                    expand: true,
                    label: 'Find a tool',
                    onPressed: () => taps++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await frames(tester);
      expect(painter(tester).visible.value, isTrue);
      await tester.pump(const Duration(seconds: 31));
      await frames(tester);
      expect(find.byKey(const Key('smoke-screensaver')), findsOneWidget);
      final target = tester.getCenter(
        find.byKey(const Key('smoke-underlying-button')),
      );
      await tester.tapAt(target);
      await frames(tester);
      expect(find.byKey(const Key('smoke-screensaver')), findsNothing);
      expect(taps, 0);
      await tester.tapAt(target);
      await frames(tester);
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      controller.dispose();
      smoke.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('appearance switch persists and remains usable with large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = KorlixClimbersController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SingleChildScrollView(
              child: KorlixClimbersSettings(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('button-climbers-toggle')));
    await tester.pumpAndSettle();
    expect(controller.enabled, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        KorlixClimbersController.storageKey,
      ),
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('climbers render on phone and tablet in dark and light palettes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final output = Platform.environment['KORLIX_CLIMBERS_REVIEW'];
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
                ).readAsBytes().then((b) => ByteData.sublistView(b)),
              ))
              .load();
        }
      });
    }
    for (final size in [const Size(390, 844), const Size(1024, 900)]) {
      for (final theme in ['korlix_blue', 'pure_white']) {
        tester.view.physicalSize = size;
        final boundary = GlobalKey();
        final controller = KorlixClimbersController();
        await tester.pumpWidget(
          MaterialApp(
            theme: korlixBuildTheme(theme),
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                body: KorlixButtonClimbers(
                  controller: controller,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      size.width < 430 ? 32 : 48,
                      100,
                      size.width < 430 ? 32 : 48,
                      40,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'KORLIX AI',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 60),
                        KorlixActionButton(
                          label: 'Find a tool',
                          size: KorlixButtonSize.hero,
                          subtitle: 'Search KORLIX by name or task',
                          icon: Icons.search_rounded,
                          expand: true,
                          onPressed: () {},
                        ),
                        const SizedBox(height: 100),
                        KorlixActionSection(
                          title: 'Start here',
                          description: 'Choose how you want to work with Rici.',
                          icon: Icons.tune_rounded,
                          children: [
                            for (final action in [
                              ('Upload', Icons.upload_file_rounded),
                              ('Voice', Icons.mic_rounded),
                              ('Camera Ask', Icons.camera_alt_outlined),
                              ('More tools', Icons.apps_rounded),
                            ])
                              KorlixActionButton(
                                label: action.$1,
                                icon: action.$2,
                                tile: true,
                                onPressed: () {},
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await frames(tester);
        for (final phase in [1, 6, 10, 13, 19, 23]) {
          final art = painter(tester);
          await tester.pump(
            Duration(
              milliseconds: ((phase - art.seconds.value) * 1000).round(),
            ),
          );
          expect(tester.takeException(), isNull);
          if (output != null) {
            await tester.runAsync(() async {
              final shot =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 1.5);
              final bytes = await shot.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '$output/$theme-${size.width.toInt()}-$phase.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              shot.dispose();
            });
          }
        }
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        controller.dispose();
      }
    }
  });
}
