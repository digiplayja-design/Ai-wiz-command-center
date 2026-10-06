import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:ai_wiz_command_center/theme/korlix_screensaver_controller.dart';
import 'package:ai_wiz_command_center/theme/korlix_screensaver_settings.dart';
import 'package:ai_wiz_command_center/theme/korlix_smoke_screensaver.dart';
import 'package:ai_wiz_command_center/theme/korlix_smoke_veil.dart';

final smoke = find.byKey(const Key('smoke-screensaver'));

Future<void> mount(
  WidgetTester tester,
  KorlixScreensaverController controller, {
  Widget? child,
  bool reduced = false,
  bool accessible = false,
  Listenable? session,
  GlobalKey<NavigatorState>? navigator,
  Size size = const Size(390, 844),
  String theme = 'korlix_blue',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: [KorlixScreensaverObserver(controller)],
      theme: korlixBuildTheme(theme),
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduced,
          accessibleNavigation: accessible,
        ),
        child: RepaintBoundary(
          key: const Key('smoke-export'),
          child: KorlixSmokeScreensaver(
            controller: controller,
            sessionChanges: session,
            child: page!,
          ),
        ),
      ),
      home:
          child ?? const Scaffold(body: Center(child: Text('Your workspace'))),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'mouse motion resets idle and a wake scroll cannot scroll the hidden page',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = KorlixScreensaverController();
      final scroll = ScrollController();
      await mount(
        tester,
        controller,
        child: Scaffold(
          body: ListView(
            controller: scroll,
            children: List.generate(
              40,
              (i) => SizedBox(height: 80, child: Text('Item $i')),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(100, 200));
      await tester.pump(const Duration(seconds: 25));
      await mouse.moveTo(const Offset(150, 240));
      await tester.pump(const Duration(seconds: 29));
      expect(smoke, findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(smoke, findsOneWidget);
      tester.binding.handlePointerEvent(
        const PointerScrollEvent(
          position: Offset(150, 240),
          scrollDelta: Offset(0, 100),
        ),
      );
      await tester.pumpAndSettle();
      expect(smoke, findsNothing);
      expect(scroll.offset, 0);
      tester.binding.handlePointerEvent(
        const PointerScrollEvent(
          position: Offset(150, 240),
          scrollDelta: Offset(0, 100),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      await mouse.removePointer();
      await unmount(tester);
      scroll.dispose();
      controller.dispose();
    },
  );

  test(
    'enabled by default, off survives reload, and a late restore cannot undo a new setting',
    () async {
      final controller = KorlixScreensaverController();
      expect(controller.enabled, isTrue);
      expect(await controller.setEnabled(false), isTrue);
      final restored = KorlixScreensaverController();
      await restored.restore();
      expect(restored.enabled, isFalse);
      final gate = Completer<SharedPreferences>();
      final delayed = KorlixScreensaverController(load: () => gate.future);
      final loading = delayed.restore();
      final saving = delayed.setEnabled(true);
      gate.complete(await SharedPreferences.getInstance());
      await loading;
      await saving;
      expect(delayed.enabled, isTrue);
      controller.dispose();
      restored.dispose();
      delayed.dispose();
    },
  );

  test(
    'rapid preference writes keep the last selection and failure is reported',
    () async {
      final controller = KorlixScreensaverController();
      await Future.wait([
        controller.setEnabled(false),
        controller.setEnabled(true),
        controller.setEnabled(false),
      ]);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          KorlixScreensaverController.storageKey,
        ),
        isFalse,
      );
      final failing = KorlixScreensaverController(
        load: () async => throw StateError('Unavailable'),
      );
      await failing.restore();
      expect(await failing.setEnabled(false), isFalse);
      expect(failing.enabled, isFalse);
      controller.dispose();
      failing.dispose();
    },
  );

  testWidgets(
    'appears at 30 seconds and the first wake tap cannot click through',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = KorlixScreensaverController();
      var taps = 0;
      await mount(
        tester,
        controller,
        child: Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => taps++,
              child: const Text('Action'),
            ),
          ),
        ),
      );
      final point = tester.getCenter(find.text('Action'));
      await tester.pump(const Duration(seconds: 29));
      expect(smoke, findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      expect(smoke, findsOneWidget);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(smoke, findsNothing);
      expect(taps, 0);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(taps, 1);
      await tester.pump(const Duration(seconds: 29));
      expect(smoke, findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(smoke, findsOneWidget);
      await unmount(tester);
      controller.dispose();
    },
  );

  testWidgets('dragging and held pointers postpone idle until release', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = KorlixScreensaverController();
    await mount(tester, controller);
    await tester.pump(const Duration(seconds: 25));
    final drag = await tester.startGesture(const Offset(120, 300));
    await tester.pump(const Duration(seconds: 40));
    expect(smoke, findsNothing);
    await drag.moveBy(const Offset(40, 80));
    await drag.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 29));
    expect(smoke, findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(smoke, findsOneWidget);
    await unmount(tester);
    controller.dispose();
  });

  testWidgets(
    'keyboard wake consumes the wake key and leaves text and submit untouched',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = KorlixScreensaverController();
      final draft = TextEditingController(text: 'Keep this draft');
      final focus = FocusNode();
      var submissions = 0;
      await mount(
        tester,
        controller,
        child: Scaffold(
          body: Center(
            child: TextField(
              controller: draft,
              focusNode: focus,
              onSubmitted: (_) => submissions++,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pump(const Duration(seconds: 25));
      await tester.enterText(find.byType(TextField), 'Keep this updated draft');
      await tester.pump();
      await tester.pump(const Duration(seconds: 29));
      expect(smoke, findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(smoke, findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(smoke, findsNothing);
      expect(submissions, 0);
      expect(draft.text, 'Keep this updated draft');
      expect(focus.hasFocus, isTrue);
      await unmount(tester);
      focus.dispose();
      draft.dispose();
      controller.dispose();
    },
  );

  testWidgets(
    'background and account changes clear smoke and resume with a fresh idle period',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = KorlixScreensaverController();
      final session = ValueNotifier(0);
      await mount(tester, controller, session: session);
      await tester.pump(const Duration(seconds: 30));
      expect(smoke, findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 3));
      expect(smoke, findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 29));
      expect(smoke, findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(smoke, findsOneWidget);
      session.value++;
      await tester.pump();
      expect(smoke, findsNothing);
      await unmount(tester);
      controller.dispose();
      session.dispose();
    },
  );

  testWidgets('route changes wake the app and keep its navigation state', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = KorlixScreensaverController();
    final navigator = GlobalKey<NavigatorState>();
    await mount(tester, controller, navigator: navigator);
    await tester.pump(const Duration(seconds: 30));
    expect(smoke, findsOneWidget);
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Incoming call controls')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(smoke, findsNothing);
    expect(find.text('Incoming call controls'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Your workspace'), findsOneWidget);
    await unmount(tester);
    controller.dispose();
  });

  testWidgets(
    'off prevents automatic smoke but manual preview remains available',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = KorlixScreensaverController(initiallyEnabled: false);
      await mount(
        tester,
        controller,
        child: Scaffold(
          body: Center(
            child: KorlixScreensaverSettings(controller: controller),
          ),
        ),
      );
      await tester.pump(const Duration(minutes: 2));
      expect(smoke, findsNothing);
      await tester.tap(find.byKey(const Key('preview-smoke-screensaver')));
      await tester.pump();
      expect(smoke, findsOneWidget);
      await tester.tapAt(const Offset(100, 100));
      await tester.pumpAndSettle();
      expect(controller.enabled, isFalse);
      await tester.tap(find.byKey(const Key('smoke-screensaver-toggle')));
      await tester.pumpAndSettle();
      expect(controller.enabled, isTrue);
      await tester.pump(const Duration(seconds: 30));
      expect(smoke, findsOneWidget);
      await controller.setEnabled(false);
      await tester.pumpAndSettle();
      expect(smoke, findsNothing);
      await unmount(tester);
      controller.dispose();
    },
  );

  testWidgets(
    'reduced motion is still; screen readers retain control until explicit preview',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = KorlixScreensaverController();
      await mount(tester, controller, reduced: true);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(smoke, findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await unmount(tester);
      await mount(tester, controller, accessible: true);
      await tester.pump(const Duration(minutes: 2));
      expect(smoke, findsNothing);
      controller.preview();
      await tester.pumpAndSettle();
      expect(smoke, findsOneWidget);
      final semantics = tester.widget<Semantics>(smoke);
      semantics.properties.onTap!();
      await tester.pumpAndSettle();
      expect(smoke, findsNothing);
      await unmount(tester);
      controller.dispose();
    },
  );

  testWidgets(
    'paint fits phone, landscape and tablet without animation leaks',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in [
        const Size(320, 568),
        const Size(844, 390),
        const Size(1024, 1366),
      ]) {
        for (final theme in ['pure_white', 'korlix_blue']) {
          final controller = KorlixScreensaverController();
          await mount(tester, controller, size: size, theme: theme);
          await tester.pump(const Duration(seconds: 30));
          await tester.pump(const Duration(seconds: 2));
          final painter = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((w) => w.painter)
              .whereType<KorlixSmokePainter>()
              .single;
          final start = painter.seconds.value;
          await tester.pump(const Duration(seconds: 2));
          expect(painter.seconds.value, greaterThan(start));
          expect(tester.takeException(), isNull);
          await unmount(tester);
          controller.dispose();
          expect(tester.binding.hasScheduledFrame, isFalse);
        }
      }
    },
  );

  testWidgets('export smoke review', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final output = Platform.environment['KORLIX_SMOKE_PREVIEWS']!;
    await tester.runAsync(() async {
      final loader = FontLoader('Roboto')
        ..addFont(
          File(
            'assets/fieldproof/Roboto-Regular.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await loader.load();
    });
    for (final (name, size, theme) in [
      ('phone-dark', const Size(390, 844), 'korlix_blue'),
      ('tablet-light', const Size(1024, 1366), 'pure_white'),
    ]) {
      final controller = KorlixScreensaverController();
      await mount(
        tester,
        controller,
        size: size,
        theme: theme,
        reduced: true,
        child: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(32),
            children: [
              const Text(
                'Your KORLIX workspace',
                style: TextStyle(fontSize: 28),
              ),
              const SizedBox(height: 32),
              for (var i = 0; i < 4; i++)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Create · Connect · Learn'),
                  ),
                ),
            ],
          ),
        ),
      );
      controller.preview();
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('smoke-export')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$output/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      await unmount(tester);
      controller.dispose();
    }
  }, skip: Platform.environment['KORLIX_SMOKE_PREVIEWS'] == null);
}
