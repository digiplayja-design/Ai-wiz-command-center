import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:esha_by_korlix/models.dart';
import 'package:esha_by_korlix/services/selfie.dart';
import 'package:esha_by_korlix/ui/brand.dart';
import 'package:esha_by_korlix/ui/selfie_studio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class PreviewService implements SelfiePhotoService {
  Future<SelfiePhoto?> Function() next = () async => null;
  void Function(SelfiePhoto photo)? previewCallback;
  int selections = 0;

  @override
  Future<void> discardInterruptedSelection() async {}

  @override
  Future<SelfiePhoto?> choose({
    void Function(String message)? onProgress,
    void Function(SelfiePhoto photo)? onPreview,
  }) {
    selections++;
    previewCallback = onPreview;
    onProgress?.call('Aligning the look on your device…');
    return next();
  }
}

Offset rotate(Offset point, double angle) {
  final p = point - const Offset(.5, .5);
  return Offset(
        p.dx * math.cos(angle) - p.dy * math.sin(angle),
        p.dx * math.sin(angle) + p.dy * math.cos(angle),
      ) +
      const Offset(.5, .5);
}

FaceLandmarks landmarks({double roll = 0}) {
  List<Offset> ellipse(Offset center, double x, double y, int count) =>
      List.generate(count, (i) {
        final angle = math.pi * 2 * i / count;
        return rotate(
          center + Offset(x * math.cos(angle), y * math.sin(angle)),
          roll,
        );
      });
  return FaceLandmarks(
    bounds: const Rect.fromLTWH(.1, .1, .8, .8),
    outerLips: ellipse(const Offset(.5, .69), .19, .08, 32),
    innerLips: ellipse(const Offset(.5, .69), .11, .025, 24),
    leftEye: ellipse(const Offset(.34, .38), .12, .04, 24),
    rightEye: ellipse(const Offset(.66, .38), .12, .04, 24),
  );
}

Future<ui.Image> texturedImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var y = 0; y < 200; y++) {
    canvas.drawRect(
      Rect.fromLTWH(0, y.toDouble(), 200, 1),
      Paint()
        ..isAntiAlias = false
        ..color = Color.fromARGB(
          255,
          202 + (y % 4) * 4,
          151 + (y % 4) * 3,
          139,
        ),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 200);
  picture.dispose();
  return image;
}

Future<Uint8List> painted(
  SelfiePhoto photo, {
  Size size = const Size(200, 200),
  bool original = false,
  StudioLook look = const StudioLook(shade: 1, finish: 'Gloss', lashes: 'Bold'),
}) async {
  final recorder = ui.PictureRecorder();
  SelfieMakeupPainter(
    photo: photo,
    look: look,
    showOriginal: original,
    intensity: .55,
  ).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return Uint8List.fromList(data!.buffer.asUint8List());
}

List<int> pixel(Uint8List image, int width, int x, int y) =>
    image.sublist((y * width + x) * 4, (y * width + x + 1) * 4);

SelfieStudioController session(PreviewService service) =>
    SelfieStudioController(service: service)..updateAccess(
      ownerId: '11111111-1111-4111-8111-111111111111',
      accountEpoch: 1,
      allowed: true,
    );

Widget card(SelfieStudioController controller, {double scale = 1}) =>
    MaterialApp(
      theme: eshaTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SelfiePreviewCard(
            controller: controller,
            look: const StudioLook(),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Original renders exact source pixels without changing the photo',
    () async {
      final image = await texturedImage();
      final photo = SelfiePhoto(image: image, face: landmarks());
      addTearDown(photo.dispose);
      final source = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final original = await painted(photo, original: true);
      expect(original, orderedEquals(source!.buffer.asUint8List()));
      final secondLook = await painted(
        photo,
        original: true,
        look: const StudioLook(shade: 3, finish: 'Satin', lashes: 'Soft'),
      );
      expect(secondLook, orderedEquals(original));
    },
  );

  test('a photo without alignment renders original pixels even when try-on is requested', () async {
    final image = await texturedImage();
    final photo = SelfiePhoto(
      image: image,
      alignmentIssue: const SelfieException(
        'small_face',
        'Choose a closer selfie so Esha can place the lip color and lashes accurately.',
      ),
    );
    addTearDown(photo.dispose);
    final source = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(photo.hasMakeupAlignment, isFalse);
    for (final original in [false, true]) {
      final preview = await painted(photo, original: original);
      expect(preview, orderedEquals(source!.buffer.asUint8List()));
    }
  });

  test(
    'contained overlays preserve the mouth opening, background and lip texture',
    () async {
      final photo = SelfiePhoto(
        image: await texturedImage(),
        face: landmarks(),
      );
      addTearDown(photo.dispose);
      final original = await painted(
        photo,
        size: const Size(400, 200),
        original: true,
      );
      final makeup = await painted(photo, size: const Size(400, 200));
      // The square photo is centered at x=100 within a landscape preview.
      expect(pixel(makeup, 400, 20, 100), [0, 0, 0, 0]);
      expect(pixel(makeup, 400, 200, 138), pixel(original, 400, 200, 138));
      expect(pixel(makeup, 400, 120, 10), pixel(original, 400, 120, 10));
      expect(
        pixel(makeup, 400, 200, 128),
        isNot(pixel(original, 400, 200, 128)),
      );
      expect(pixel(makeup, 400, 200, 128), isNot(pixel(makeup, 400, 200, 129)));
    },
  );

  test(
    'lashes follow the upper eye contours when the face is rolled',
    () async {
      const roll = .60;
      final photo = SelfiePhoto(
        image: await texturedImage(),
        face: landmarks(roll: roll),
      );
      addTearDown(photo.dispose);
      final original = await painted(photo, original: true);
      final makeup = await painted(photo);
      final center = rotate(const Offset(.34, .38), roll) * 200;
      final up = Offset(math.sin(roll), -math.cos(roll));
      var upperChanges = 0, lowerChanges = 0;
      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 200; x++) {
          final delta = Offset(x + .5, y + .5) - center;
          if (delta.distance > 30) continue;
          if (listEquals(
            pixel(original, 200, x, y),
            pixel(makeup, 200, x, y),
          )) {
            continue;
          }
          final elevation = delta.dx * up.dx + delta.dy * up.dy;
          if (elevation > 1) upperChanges++;
          if (elevation < -2) lowerChanges++;
        }
      }
      expect(upperChanges, greaterThan(30));
      expect(lowerChanges, 0);
    },
  );

  test(
    'thin lips never paint an inner contour that crosses the outer edge',
    () async {
      final usual = landmarks();
      final photo = SelfiePhoto(
        image: await texturedImage(),
        face: FaceLandmarks(
          bounds: usual.bounds,
          outerLips: const [
            Offset(.34, .665),
            Offset(.4, .66),
            Offset(.5, .67),
            Offset(.6, .66),
            Offset(.66, .665),
            Offset(.6, .7),
            Offset(.5, .69),
            Offset(.4, .7),
          ],
          innerLips: const [
            Offset(.39, .655),
            Offset(.61, .655),
            Offset(.61, .71),
            Offset(.39, .71),
          ],
          leftEye: usual.leftEye,
          rightEye: usual.rightEye,
        ),
      );
      addTearDown(photo.dispose);
      final original = await painted(photo, original: true);
      final makeup = await painted(photo);
      for (var y = 132; y <= 140; y++) {
        for (var x = 80; x <= 120; x++) {
          expect(
            pixel(makeup, 200, x, y),
            pixel(original, 200, x, y),
            reason: 'Mouth opening at $x,$y',
          );
        }
      }
    },
  );

  testWidgets(
    'selfie controls compare, adjust and remove locally at narrow large-text sizes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      final image = await tester.runAsync(texturedImage);
      final service = PreviewService()
        ..next = () async => SelfiePhoto(image: image!, face: landmarks());
      final controller = session(service);
      addTearDown(controller.dispose);
      await tester.pumpWidget(card(controller, scale: 1.7));
      expect(find.text('Upload selfie'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('choose-selfie')));
      await tester.tap(find.byKey(const Key('choose-selfie')));
      await tester.pumpAndSettle();
      expect(service.selections, 1);
      expect(find.byKey(const Key('selfie-preview-image')), findsOneWidget);
      expect(find.text('Change selfie'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Original'));
      await tester.tap(find.text('Original'));
      await tester.pump();
      expect(controller.showOriginal, isTrue);
      expect(
        find.bySemanticsLabel('Your original selfie, without makeup overlays'),
        findsOneWidget,
      );
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      await tester.tap(find.text('Try-on'));
      await tester.pump();
      await tester.ensureVisible(find.byType(Slider));
      await tester.drag(find.byType(Slider), const Offset(45, 0));
      await tester.pump();
      expect(controller.intensity, greaterThan(.55));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Remove photo'));
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      expect(controller.photo, isNull);
      expect(find.text('Upload selfie'), findsOneWidget);
      expect(find.byKey(const Key('selfie-preview-image')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets(
    'picker cancel, decode errors and Cancel preview leave upload usable',
    (tester) async {
      final service = PreviewService();
      final controller = session(service);
      addTearDown(controller.dispose);
      await tester.pumpWidget(card(controller));
      await tester.tap(find.byKey(const Key('choose-selfie')));
      await tester.pumpAndSettle();
      expect(controller.photo, isNull);
      expect(controller.error, isNull);

      service.next = () async => throw const SelfieException(
        'invalid_image',
        'This photo could not be decoded. Choose another image.',
      );
      await tester.tap(find.byKey(const Key('choose-selfie')));
      await tester.pumpAndSettle();
      expect(
        find.text('This photo could not be decoded. Choose another image.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('choose-selfie')))
            .onPressed,
        isNotNull,
      );

      final pending = Completer<SelfiePhoto?>();
      service.next = () => pending.future;
      await tester.tap(find.byKey(const Key('choose-selfie')));
      await tester.pump();
      expect(find.text('Aligning the look on your device…'), findsOneWidget);
      expect(controller.busy, isTrue);
      await tester.ensureVisible(find.text('Cancel preview'));
      await tester.tap(find.text('Cancel preview'));
      await tester.pump();
      expect(controller.busy, isFalse);
      expect(controller.canChoose, isTrue);
      final image = await tester.runAsync(texturedImage);
      pending.complete(SelfiePhoto(image: image!, face: landmarks()));
      await tester.pumpAndSettle();
      expect(controller.photo, isNull);
      expect(find.byKey(const Key('selfie-preview-image')), findsNothing);
      expect(controller.error, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'small-face alignment warning keeps the photo visible and change/remove actionable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      final image = (await tester.runAsync(texturedImage))!;
      addTearDown(image.dispose);
      const issue = SelfieException(
        'small_face',
        'Choose a closer selfie so Esha can place the lip color and lashes accurately.',
      );
      final service = PreviewService()
        ..next = () async =>
            SelfiePhoto(image: image.clone(), alignmentIssue: issue);
      final controller = session(service);
      addTearDown(controller.dispose);
      await tester.pumpWidget(card(controller, scale: 1.7));
      await tester.ensureVisible(find.byKey(const Key('choose-selfie')));
      await tester.tap(find.byKey(const Key('choose-selfie')));
      await tester.pumpAndSettle();

      expect(controller.photo, isNotNull);
      expect(controller.canTryOn, isFalse);
      expect(controller.error, isNull);
      expect(find.byKey(const Key('selfie-preview-image')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('selfie-preview-image')));
      await tester.pump();
      expect(
        find.bySemanticsLabel('Your selected photo. Makeup is not applied.'),
        findsOneWidget,
      );
      expect(
        find.text('Original photo. Makeup is not applied.'),
        findsOneWidget,
      );
      expect(find.text(issue.message), findsOneWidget);
      expect(find.text('Try-on'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('choose-selfie')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Remove photo'));
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      expect(controller.photo, isNull);
      expect(find.text(issue.message), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('choose-selfie')));
      await tester.tap(find.byKey(const Key('choose-selfie')));
      await tester.pumpAndSettle();
      expect(controller.photo?.alignmentIssue, issue);
      service.next = () async =>
          SelfiePhoto(image: image.clone(), face: landmarks());
      await tester.ensureVisible(find.text('Change selfie'));
      await tester.tap(find.text('Change selfie'));
      await tester.pumpAndSettle();
      expect(controller.canTryOn, isTrue);
      expect(find.text(issue.message), findsNothing);
      expect(find.text('Try-on'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets(
    'decoded photo is visible during alignment and Cancel preview prevents a late restoration',
    (tester) async {
      final image = (await tester.runAsync(texturedImage))!;
      addTearDown(image.dispose);
      final pending = Completer<SelfiePhoto?>();
      final service = PreviewService()..next = () => pending.future;
      final controller = session(service);
      addTearDown(controller.dispose);
      await tester.pumpWidget(card(controller));
      await tester.tap(find.byKey(const Key('choose-selfie')));
      await tester.pump();
      expect(service.previewCallback, isNotNull);
      service.previewCallback!(SelfiePhoto(image: image.clone()));
      await tester.pump();
      expect(controller.busy, isTrue);
      expect(controller.photo, isNotNull);
      expect(controller.canTryOn, isFalse);
      expect(find.byKey(const Key('selfie-preview-image')), findsOneWidget);
      expect(
        find.text('Original photo. Makeup is not applied.'),
        findsOneWidget,
      );
      expect(find.text('Try-on'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('choose-selfie')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Cancel preview'));
      await tester.tap(find.text('Cancel preview'));
      await tester.pump();
      expect(controller.busy, isFalse);
      expect(controller.photo, isNull);
      expect(controller.canChoose, isTrue);
      pending.complete(SelfiePhoto(image: image.clone(), face: landmarks()));
      await tester.pumpAndSettle();
      expect(controller.photo, isNull);
      expect(find.byKey(const Key('selfie-preview-image')), findsNothing);
      expect(find.text('Upload selfie'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
