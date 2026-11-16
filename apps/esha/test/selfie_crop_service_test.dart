import 'dart:async';
import 'dart:ui' as ui;

import 'package:esha_by_korlix/services/selfie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _full = ui.Rect.fromLTWH(0, 0, 1, 1);
const _right = ui.Rect.fromLTWH(.5, 0, .5, 1);

Future<ui.Image> _image() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xffee3366), ui.BlendMode.src);
  canvas.drawRect(
    const ui.Rect.fromLTWH(200, 0, 200, 400),
    ui.Paint()..color = const ui.Color(0xff2288ee),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(400, 400);
  } finally {
    picture.dispose();
  }
}

Map<Object?, Object?> _response(int width, int height) => {
  'imageWidth': width,
  'imageHeight': height,
  'faceCount': 1,
  'faces': [
    {
      'bounds': {'left': .1, 'top': .1, 'width': .8, 'height': .8},
      'outerLips': [
        [.3, .65],
        [.4, .6],
        [.5, .63],
        [.6, .6],
        [.7, .65],
        [.6, .72],
        [.4, .72],
      ],
      'innerLips': [
        [.4, .65],
        [.5, .64],
        [.6, .65],
        [.5, .68],
      ],
      'leftEye': [
        [.2, .35],
        [.3, .31],
        [.4, .35],
        [.3, .39],
      ],
      'rightEye': [
        [.6, .35],
        [.7, .31],
        [.8, .35],
        [.7, .39],
      ],
      'yaw': 0,
      'pitch': 0,
    },
  ],
};

Future<ui.Image> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<List<int>> _pixel(ui.Image image, int x, int y) async {
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return List.generate(4, (c) => bytes.getUint8((y * image.width + x) * 4 + c));
}

class _CropRequest {
  _CropRequest(this.input, this.rect, this.preview);
  final ui.Image input;
  final ui.Rect rect;
  final void Function(SelfiePhoto)? preview;
  final result = Completer<SelfiePhoto>();
}

class _ControlledCropper implements SelfiePhotoService, SelfiePhotoCropper {
  SelfiePhoto? selection;
  final requests = <_CropRequest>[];
  @override
  Future<void> discardInterruptedSelection() async {}
  @override
  Future<SelfiePhoto?> choose({
    void Function(String)? onProgress,
    void Function(SelfiePhoto)? onPreview,
  }) async => selection;
  @override
  Future<SelfiePhoto> crop(
    ui.Image source,
    ui.Rect normalizedCrop, {
    void Function(String)? onProgress,
    void Function(SelfiePhoto)? onPreview,
  }) {
    final request = _CropRequest(source, normalizedCrop, onPreview);
    requests.add(request);
    return request.result.future;
  }
}

Future<SelfiePhoto> _photo({bool aligned = true}) async {
  final image = await _image();
  return SelfiePhoto(
    image: image,
    face: aligned
        ? FaceLandmarks.fromResponse(
            _response(400, 400),
            const ui.Size(400, 400),
          )
        : null,
    alignmentIssue: aligned
        ? null
        : const SelfieException('no_face', 'Crop closer to your face.'),
  );
}

Future<SelfieStudioController> _controller(_ControlledCropper service) async {
  service.selection = await _photo(aligned: false);
  final controller = SelfieStudioController(service: service)
    ..updateAccess(ownerId: 'owner-a', accountEpoch: 1, allowed: true);
  await controller.choosePhoto();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'crop uses selected source pixels and re-detects exact cropped dimensions',
    () async {
      final original = await _image();
      addTearDown(original.dispose);
      var calls = 0;
      final service = DeviceSelfiePhotoService(
        detector: (png) async {
          calls++;
          final image = await _decode(png);
          try {
            expect(image.width, 200);
            expect(image.height, 400);
            expect(await _pixel(image, 20, 20), [34, 136, 238, 255]);
            expect(await _pixel(image, 180, 380), [34, 136, 238, 255]);
            return _response(image.width, image.height);
          } finally {
            image.dispose();
          }
        },
      );
      final result = await service.crop(original, _right);
      addTearDown(result.dispose);
      expect(calls, 1);
      expect(result.size, const ui.Size(200, 400));
      expect(result.hasMakeupAlignment, isTrue);
      expect(result.face!.outerLips.first, const ui.Offset(.3, .65));
      expect(await _pixel(result.image, 20, 20), [34, 136, 238, 255]);
      expect(original.width, 400);
      expect(await _pixel(original, 20, 20), [238, 51, 102, 255]);
      expect(await _pixel(original, 380, 20), [34, 136, 238, 255]);
    },
  );

  test(
    'crop preview is visible before alignment and survives no-face result',
    () async {
      final original = await _image();
      addTearDown(original.dispose);
      final arrived = Completer<SelfiePhoto>();
      final detectStarted = Completer<void>();
      final detection = Completer<Map<Object?, Object?>>();
      final service = DeviceSelfiePhotoService(
        detector: (_) {
          detectStarted.complete();
          return detection.future;
        },
      );
      final pending = service.crop(
        original,
        _right,
        onPreview: arrived.complete,
      );
      final preview = await arrived.future;
      addTearDown(preview.dispose);
      await detectStarted.future;
      expect(await _pixel(preview.image, 20, 20), [34, 136, 238, 255]);
      expect(preview.hasMakeupAlignment, isFalse);
      preview.dispose();
      detection.complete({
        'imageWidth': 200,
        'imageHeight': 400,
        'faceCount': 0,
        'faces': [],
      });
      final result = await pending;
      addTearDown(result.dispose);
      expect(result.alignmentIssue!.code, 'no_face');
      expect(await _pixel(result.image, 20, 20), [34, 136, 238, 255]);
    },
  );

  for (final entry in <String, ui.Rect>{
    'outside source': const ui.Rect.fromLTWH(-.1, 0, .8, 1),
    'past right edge': const ui.Rect.fromLTWH(.4, 0, .8, 1),
    'empty': const ui.Rect.fromLTWH(0, 0, 0, .8),
    'non-finite': const ui.Rect.fromLTWH(double.nan, 0, 1, 1),
    'too little detail': const ui.Rect.fromLTWH(.4, .4, .2, .2),
  }.entries) {
    test(
      'rejects ${entry.key} without detection or a broken preview',
      () async {
        final original = await _image();
        addTearDown(original.dispose);
        var detections = 0, previews = 0;
        final service = DeviceSelfiePhotoService(
          detector: (_) async {
            detections++;
            return _response(400, 400);
          },
        );
        await expectLater(
          service.crop(
            original,
            entry.value,
            onPreview: (photo) {
              previews++;
              photo.dispose();
            },
          ),
          throwsA(isA<SelfieException>()),
        );
        expect(detections, 0);
        expect(previews, 0);
        expect(await _pixel(original, 20, 20), [238, 51, 102, 255]);
      },
    );
  }

  test(
    'successive crops and Reset always derive from the uploaded original',
    () async {
      final service = _ControlledCropper();
      final controller = await _controller(service);
      addTearDown(controller.dispose);
      final original = controller.sourcePhoto!;
      expect(controller.canCrop, isTrue);
      final crop = controller.applyCrop(_right);
      expect(controller.busy, isTrue);
      expect(service.requests.single.input.width, 400);
      final first = await DeviceSelfiePhotoService(
        detector: (_) async => _response(200, 400),
      ).crop(original.image, _right);
      expect(first.size, const ui.Size(200, 400));
      service.requests.single.result.complete(first);
      await crop;
      expect(controller.sourcePhoto, same(original));
      expect(controller.photo, same(first));
      expect(controller.cropRect, _right);
      expect(controller.showOriginal, isFalse);
      final reset = controller.applyCrop(_full);
      expect(service.requests.last.rect, _full);
      expect(service.requests.last.input.width, 400);
      expect(await _pixel(service.requests.last.input, 20, 20), [
        238,
        51,
        102,
        255,
      ]);
      service.requests.last.result.complete(await _photo());
      await reset;
      expect(controller.sourcePhoto, same(original));
      expect(controller.cropRect, _full);
    },
  );

  test(
    'failed crop preserves the prior photo and crop with an actionable error',
    () async {
      final service = _ControlledCropper();
      final controller = await _controller(service);
      addTearDown(controller.dispose);
      final previous = controller.photo;
      final original = controller.sourcePhoto;
      final crop = controller.applyCrop(_right);
      service.requests.single.result.completeError(
        const SelfieException('crop_too_small', 'Zoom out a little.'),
      );
      await crop;
      expect(controller.photo, same(previous));
      expect(controller.sourcePhoto, same(original));
      expect(controller.cropRect, _full);
      expect(controller.error, 'Zoom out a little.');
      expect(controller.canCrop, isTrue);
      expect(service.requests.single.input.debugDisposed, isTrue);
    },
  );

  for (final clear in [
    'remove',
    'sign out',
    'account change',
    'access revoked',
  ]) {
    test(
      '$clear during crop discards late preview/result and both stored originals',
      () async {
        final service = _ControlledCropper();
        final controller = await _controller(service);
        addTearDown(controller.dispose);
        final previous = controller.photo!;
        final original = controller.sourcePhoto!;
        final crop = controller.applyCrop(_right);
        final request = service.requests.single;
        if (clear == 'remove') {
          controller.removePhoto();
        } else {
          controller.updateAccess(
            ownerId: clear == 'sign out'
                ? null
                : clear == 'account change'
                ? 'owner-b'
                : 'owner-a',
            accountEpoch: clear == 'access revoked' ? 1 : 2,
            allowed: clear == 'account change',
          );
        }
        expect(controller.photo, isNull);
        expect(controller.sourcePhoto, isNull);
        expect(previous.image.debugDisposed, isTrue);
        expect(original.image.debugDisposed, isTrue);
        // Work still owns its independent source until the asynchronous call ends.
        expect(await _pixel(request.input, 20, 20), [238, 51, 102, 255]);
        final preview = await _photo(aligned: false);
        request.preview!(preview);
        final result = await _photo();
        request.result.complete(result);
        await crop;
        expect(controller.photo, isNull);
        expect(controller.sourcePhoto, isNull);
        expect(controller.busy, isFalse);
        expect(preview.image.debugDisposed, isTrue);
        expect(result.image.debugDisposed, isTrue);
        expect(request.input.debugDisposed, isTrue);
      },
    );
  }

  test(
    'old crop completion cannot replace a new account photo or its busy state',
    () async {
      final service = _ControlledCropper();
      final controller = await _controller(service);
      addTearDown(controller.dispose);
      final oldCrop = controller.applyCrop(_right);
      controller.updateAccess(
        ownerId: 'owner-b',
        accountEpoch: 2,
        allowed: true,
      );
      service.selection = await _photo();
      await controller.choosePhoto();
      final current = controller.photo;
      final currentCrop = controller.applyCrop(_full);
      final late = await _photo();
      service.requests.first.result.complete(late);
      await oldCrop;
      expect(controller.photo, same(current));
      expect(controller.busy, isTrue);
      expect(late.image.debugDisposed, isTrue);
      final fresh = await _photo();
      service.requests.last.result.complete(fresh);
      await currentCrop;
      expect(controller.photo, same(fresh));
      expect(controller.busy, isFalse);
    },
  );
}
