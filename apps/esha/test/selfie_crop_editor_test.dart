import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:esha_by_korlix/models.dart';
import 'package:esha_by_korlix/services/selfie.dart';
import 'package:esha_by_korlix/ui/brand.dart';
import 'package:esha_by_korlix/ui/selfie_crop_editor.dart';
import 'package:esha_by_korlix/ui/selfie_studio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const entirePhoto = Rect.fromLTWH(0, 0, 1, 1);

Future<void> loadQaFonts() async {
  // Optional local QA uses readable fonts without adding test assets or
  // changing the production theme. Normal CI tests need no local font files.
  for (final entry in {
    'Roboto': Platform.environment['ESHA_QA_FONT_PATH'],
    'MaterialIcons': Platform.environment['ESHA_QA_ICON_FONT_PATH'],
  }.entries) {
    final path = entry.value;
    if (path == null) continue;
    final loader = FontLoader(entry.key)
      ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
    await loader.load();
  }
}

Future<ui.Image> sampleImage({int width = 800, int height = 1000}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final halfWidth = width / 2, halfHeight = height / 2;
  for (final area in [
    (Rect.fromLTWH(0, 0, halfWidth, halfHeight), const Color(0xFFE4A6BF)),
    (
      Rect.fromLTWH(halfWidth, 0, halfWidth, halfHeight),
      const Color(0xFF86B9C8),
    ),
    (
      Rect.fromLTWH(0, halfHeight, halfWidth, halfHeight),
      const Color(0xFFDFC485),
    ),
    (
      Rect.fromLTWH(halfWidth, halfHeight, halfWidth, halfHeight),
      const Color(0xFF9886BA),
    ),
  ]) {
    canvas.drawRect(area.$1, Paint()..color = area.$2);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

class CropService implements SelfiePhotoService, SelfiePhotoCropper {
  CropService(this.selected);
  ui.Image selected;
  final requests = <Rect>[];
  Completer<SelfiePhoto>? pending;

  @override
  Future<void> discardInterruptedSelection() async {}

  @override
  Future<SelfiePhoto?> choose({
    void Function(String)? onProgress,
    void Function(SelfiePhoto)? onPreview,
  }) async => SelfiePhoto(
    image: selected.clone(),
    alignmentIssue: const SelfieException('no_face', 'Try a closer crop.'),
  );

  @override
  Future<SelfiePhoto> crop(
    ui.Image source,
    Rect normalizedCrop, {
    void Function(String)? onProgress,
    void Function(SelfiePhoto)? onPreview,
  }) async {
    requests.add(normalizedCrop);
    if (pending != null) return pending!.future;
    return SelfiePhoto(image: source.clone());
  }
}

Future<SelfieStudioController> controllerFor(CropService service) async {
  final controller = SelfieStudioController(service: service)
    ..updateAccess(
      ownerId: '11111111-1111-4111-8111-111111111111',
      accountEpoch: 1,
      allowed: true,
    );
  await controller.choosePhoto();
  return controller;
}

class CropNavigation extends NavigatorObserver {
  int pops = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
    super.didPop(route, previousRoute);
  }
}

Widget harness(
  SelfieStudioController controller, {
  CropNavigation? navigation,
  bool previewCard = false,
  double scale = 1,
  GlobalKey? capture,
}) => RepaintBoundary(
  key: capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: Platform.environment.containsKey('ESHA_QA_FONT_PATH')
        ? eshaTheme.copyWith(
            textTheme: eshaTheme.textTheme.apply(fontFamily: 'Roboto'),
            primaryTextTheme: eshaTheme.primaryTextTheme.apply(
              fontFamily: 'Roboto',
            ),
          )
        : eshaTheme,
    navigatorObservers: [?navigation],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  appBar: AppBar(title: const Text('Selected photo')),
                  body: previewCard
                      ? SingleChildScrollView(
                          child: SelfiePreviewCard(
                            controller: controller,
                            look: const StudioLook(),
                          ),
                        )
                      : Center(
                          child: FilledButton(
                            onPressed: () =>
                                showSelfieCropEditor(context, controller),
                            child: const Text('Open crop'),
                          ),
                        ),
                ),
              ),
            ),
            child: const Text('Open photo'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> openEditor(
  WidgetTester tester,
  SelfieStudioController controller, {
  CropNavigation? navigation,
  bool previewCard = false,
  double scale = 1,
  GlobalKey? capture,
}) async {
  await tester.pumpWidget(
    harness(
      controller,
      navigation: navigation,
      previewCard: previewCard,
      scale: scale,
      capture: capture,
    ),
  );
  await tester.tap(find.text('Open photo'));
  await tester.pumpAndSettle();
  final button = previewCard
      ? find.byKey(const Key('open-selfie-crop'))
      : find.text('Open crop');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byType(SelfieCropEditor), findsOneWidget);
}

SelfieCropPainter cropPainter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(find.byKey(const Key('selfie-crop-canvas')))
            .painter!
        as SelfieCropPainter;

Future<void> zoomTo(WidgetTester tester, double value) async {
  final slider = tester.widget<Slider>(
    find.byKey(const Key('selfie-crop-zoom')),
  );
  slider.onChanged!(value);
  await tester.pump();
}

void expectBounded(Rect crop) {
  expect(crop.left, inInclusiveRange(0, 1));
  expect(crop.top, inInclusiveRange(0, 1));
  expect(crop.right, inInclusiveRange(0, 1));
  expect(crop.bottom, inInclusiveRange(0, 1));
  expect(crop.width, closeTo(crop.height, 1e-10));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadQaFonts);

  test(
    'crop canvas maps the returned normalized region to the visible frame',
    () async {
      final image = await sampleImage(width: 400, height: 400);
      addTearDown(image.dispose);
      final recorder = ui.PictureRecorder();
      SelfieCropPainter(
        image: image,
        crop: const Rect.fromLTWH(.25, .25, .5, .5),
        frame: const Rect.fromLTWH(40, 20, 200, 200),
      ).paint(Canvas(recorder), const Size(280, 240));
      final picture = recorder.endRecording();
      final output = await picture.toImage(280, 240);
      picture.dispose();
      final data = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
      output.dispose();
      List<int> pixel(int x, int y) => [
        for (var channel = 0; channel < 4; channel++)
          data!.getUint8((y * 280 + x) * 4 + channel),
      ];
      expect(pixel(65, 45), [228, 166, 191, 255]);
      expect(pixel(215, 45), [134, 185, 200, 255]);
      expect(pixel(65, 195), [223, 196, 133, 255]);
      expect(pixel(215, 195), [152, 134, 186, 255]);
      expect(pixel(5, 5), [57, 32, 51, 255]);
    },
  );

  testWidgets(
    'alignment-failed photo can open crop and Cancel leaves it unchanged',
    (tester) async {
      final image = (await tester.runAsync(sampleImage))!;
      addTearDown(image.dispose);
      final service = CropService(image);
      final controller = await controllerFor(service);
      addTearDown(controller.dispose);
      final source = controller.sourcePhoto, displayed = controller.photo;
      expect(controller.canTryOn, isFalse);
      await openEditor(tester, controller, previewCard: true);
      final clone = cropPainter(tester).image;
      expect(identical(clone, source!.image), isFalse);
      expect(clone.isCloneOf(source.image), isTrue);
      await zoomTo(tester, 2);
      expect(cropPainter(tester).crop.width, closeTo(.5, 1e-10));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(SelfieCropEditor), findsNothing);
      expect(controller.photo, same(displayed));
      expect(controller.sourcePhoto, same(source));
      expect(controller.cropRect, entirePhoto);
      expect(service.requests, isEmpty);
      expect(clone.debugDisposed, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'current crop initializes the view and Reset applies the entire original',
    (tester) async {
      final image = (await tester.runAsync(sampleImage))!;
      addTearDown(image.dispose);
      final service = CropService(image);
      final controller = await controllerFor(service);
      addTearDown(controller.dispose);
      const previous = Rect.fromLTWH(.2, .3, .5, .5);
      await controller.applyCrop(previous);
      final source = controller.sourcePhoto;
      final navigation = CropNavigation();
      await openEditor(tester, controller, navigation: navigation);
      final shown = cropPainter(tester).crop;
      expect(shown.left, closeTo(previous.left, 1e-10));
      expect(shown.top, closeTo(previous.top, 1e-10));
      expect(shown.width, closeTo(previous.width, 1e-10));
      expect(cropPainter(tester).image.isCloneOf(source!.image), isTrue);
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(cropPainter(tester).crop, entirePhoto);
      await tester.tap(find.byKey(const Key('apply-selfie-crop')));
      await tester.pumpAndSettle();
      expect(service.requests.last, entirePhoto);
      expect(controller.sourcePhoto, same(source));
      expect(find.text('Selected photo'), findsOneWidget);
      expect(
        navigation.pops,
        1,
        reason: 'busy notification must not pop the photo route',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pinch preserves its focal point and dragging returns a bounded displayed crop',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final image = (await tester.runAsync(sampleImage))!;
      addTearDown(image.dispose);
      final service = CropService(image);
      final controller = await controllerFor(service);
      addTearDown(controller.dispose);
      await openEditor(tester, controller);
      await zoomTo(tester, 1.5);
      final before = cropPainter(tester);
      final origin = tester.getTopLeft(
        find.byKey(const Key('selfie-crop-gesture')),
      );
      final focal =
          origin +
          Offset(
            before.frame.left + before.frame.width * .60,
            before.frame.top + before.frame.height * .45,
          );
      final sourceAtFocal =
          before.crop.topLeft +
          Offset(before.crop.width * .60, before.crop.height * .45);
      final first = await tester.createGesture(pointer: 1);
      final second = await tester.createGesture(pointer: 2);
      await first.down(focal - const Offset(25, 0));
      await second.down(focal + const Offset(25, 0));
      await tester.pump();
      for (final span in [30.0, 45.0, 60.0]) {
        await first.moveTo(focal - Offset(span, 0));
        await second.moveTo(focal + Offset(span, 0));
        await tester.pump();
      }
      await first.up();
      await second.up();
      await tester.pump();
      final enlarged = cropPainter(tester).crop;
      expect(enlarged.width, lessThan(before.crop.width));
      final afterAtFocal =
          enlarged.topLeft +
          Offset(enlarged.width * .60, enlarged.height * .45);
      expect(afterAtFocal.dx, closeTo(sourceAtFocal.dx, .025));
      expect(afterAtFocal.dy, closeTo(sourceAtFocal.dy, .025));
      final frameCenter = origin + cropPainter(tester).frame.center;
      await tester.dragFrom(frameCenter, const Offset(45, 35));
      await tester.pump();
      final moved = cropPainter(tester).crop;
      expect(moved.left, lessThan(enlarged.left));
      expect(moved.top, lessThan(enlarged.top));
      await tester.dragFrom(frameCenter, const Offset(2000, 2000));
      await tester.pump();
      final displayed = cropPainter(tester).crop;
      expectBounded(displayed);
      expect(displayed.left, closeTo(0, 1e-10));
      expect(displayed.top, closeTo(0, 1e-10));
      await tester.tap(find.byKey(const Key('apply-selfie-crop')));
      await tester.pumpAndSettle();
      expect(service.requests.single, displayed);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final action in ['remove', 'access', 'account']) {
    testWidgets(
      '$action reset closes the editor and blocks an already captured Apply action',
      (tester) async {
        final image = (await tester.runAsync(sampleImage))!;
        addTearDown(image.dispose);
        final service = CropService(image);
        final controller = await controllerFor(service);
        addTearDown(controller.dispose);
        await openEditor(tester, controller);
        final clone = cropPainter(tester).image;
        final apply = tester
            .widget<FilledButton>(find.byKey(const Key('apply-selfie-crop')))
            .onPressed!;
        switch (action) {
          case 'remove':
            controller.removePhoto();
          case 'access':
            controller.updateAccess(
              ownerId: '11111111-1111-4111-8111-111111111111',
              accountEpoch: 1,
              allowed: false,
            );
          case 'account':
            controller.updateAccess(
              ownerId: '22222222-2222-4222-8222-222222222222',
              accountEpoch: 2,
              allowed: true,
            );
        }
        apply();
        await tester.pump();
        expect(find.byKey(const Key('selfie-crop-canvas')), findsNothing);
        await tester.pumpAndSettle();
        expect(find.byType(SelfieCropEditor), findsNothing);
        expect(find.text('Selected photo'), findsOneWidget);
        expect(service.requests, isEmpty);
        expect(clone.debugDisposed, isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('a new upload cannot receive a stale editor rectangle', (
    tester,
  ) async {
    final image = (await tester.runAsync(sampleImage))!;
    addTearDown(image.dispose);
    final service = CropService(image);
    final controller = await controllerFor(service);
    addTearDown(controller.dispose);
    await openEditor(tester, controller);
    final source = controller.sourcePhoto;
    final apply = tester
        .widget<FilledButton>(find.byKey(const Key('apply-selfie-crop')))
        .onPressed!;
    await controller.choosePhoto();
    expect(identical(source, controller.sourcePhoto), isFalse);
    apply();
    await tester.pumpAndSettle();
    expect(service.requests, isEmpty);
    expect(find.byType(SelfieCropEditor), findsNothing);
    expect(controller.photo, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Apply closes once when busy starts and a privacy reset cannot restore its image',
    (tester) async {
      final image = (await tester.runAsync(sampleImage))!;
      addTearDown(image.dispose);
      final service = CropService(image)..pending = Completer<SelfiePhoto>();
      final controller = await controllerFor(service);
      addTearDown(controller.dispose);
      final navigation = CropNavigation();
      await openEditor(tester, controller, navigation: navigation);
      final clone = cropPainter(tester).image;
      await zoomTo(tester, 2);
      await tester.tap(find.byKey(const Key('apply-selfie-crop')));
      expect(controller.busy, isTrue);
      controller.removePhoto();
      await tester.pumpAndSettle();
      expect(navigation.pops, 1);
      expect(find.text('Selected photo'), findsOneWidget);
      expect(clone.debugDisposed, isTrue);
      service.pending!.complete(SelfiePhoto(image: image.clone()));
      await tester.pumpAndSettle();
      expect(controller.photo, isNull);
      expect(service.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'zoom limit preserves 160 pixels and caps larger sources at 6 times',
    (tester) async {
      for (final spec in [
        (200, 320, 1.25),
        (160, 400, 1.0),
        (1200, 1600, 6.0),
      ]) {
        final image = (await tester.runAsync(
          () => sampleImage(width: spec.$1, height: spec.$2),
        ))!;
        final controller = await controllerFor(CropService(image));
        await openEditor(tester, controller);
        final slider = tester.widget<Slider>(
          find.byKey(const Key('selfie-crop-zoom')),
        );
        expect(slider.min, 1);
        expect(slider.max, spec.$3);
        if (spec.$3 == 1) {
          expect(slider.onChanged, isNull);
        } else {
          await zoomTo(tester, spec.$3);
          final crop = cropPainter(tester).crop;
          expectBounded(crop);
          expect(crop.width * image.width, greaterThanOrEqualTo(160));
          expect(crop.height * image.height, greaterThanOrEqualTo(160));
        }
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        image.dispose();
      }
    },
  );

  testWidgets(
    'phone crop editor and large text fit and can export synthetic QA image',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final image = (await tester.runAsync(sampleImage))!;
      addTearDown(image.dispose);
      final controller = await controllerFor(CropService(image));
      addTearDown(controller.dispose);
      final capture = GlobalKey();
      await openEditor(tester, controller, capture: capture);
      await zoomTo(tester, 1.6);
      expect(tester.takeException(), isNull);
      final path = Platform.environment['ESHA_CROP_QA_PATH'];
      if (path != null) {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final screenshot = await boundary.toImage(pixelRatio: 2);
          final png = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(path).writeAsBytes(png!.buffer.asUint8List());
          screenshot.dispose();
        });
      }
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());

      await tester.binding.setSurfaceSize(const Size(320, 720));
      await openEditor(tester, controller, scale: 1.7);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('selfie-crop-zoom')));
      await zoomTo(tester, 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Cancel').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('apply-selfie-crop')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
