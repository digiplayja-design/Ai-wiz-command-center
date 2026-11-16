import 'dart:async';
import 'dart:ui' as ui;

import 'package:esha_by_korlix/services/selfie.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

const _width = 240;
const _height = 320;

class _Picker extends ImagePicker {
  _Picker(this.selection);

  final XFile? selection;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => selection;
}

// Two solid colors make pixel preservation observable without a user's photo.
Future<Uint8List> _syntheticPhoto() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xffff3366), ui.BlendMode.src);
  canvas.drawRect(
    ui.Rect.fromLTWH(_width / 2, 0, _width / 2, _height.toDouble()),
    ui.Paint()..color = const ui.Color(0xff2288ee),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(_width, _height);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Map<Object?, Object?> _faceResponse({
  ui.Rect bounds = const ui.Rect.fromLTWH(.15, .1, .7, .8),
}) {
  List<List<double>> points(List<List<double>> relative) => relative
      .map(
        (p) => [
          bounds.left + bounds.width * p[0],
          bounds.top + bounds.height * p[1],
        ],
      )
      .toList();

  return {
    'imageWidth': _width,
    'imageHeight': _height,
    'faceCount': 1,
    'faces': [
      {
        'bounds': {
          'left': bounds.left,
          'top': bounds.top,
          'width': bounds.width,
          'height': bounds.height,
        },
        'outerLips': points([
          [.3, .7],
          [.4, .66],
          [.5, .68],
          [.6, .66],
          [.7, .7],
          [.6, .75],
          [.4, .75],
        ]),
        'innerLips': points([
          [.35, .7],
          [.5, .69],
          [.65, .7],
          [.5, .73],
        ]),
        'leftEye': points([
          [.15, .3],
          [.25, .27],
          [.35, .3],
          [.25, .33],
        ]),
        'rightEye': points([
          [.65, .3],
          [.75, .27],
          [.85, .3],
          [.75, .33],
        ]),
        'yaw': 0.0,
        'pitch': 0.0,
      },
    ],
  };
}

// Actually rasterize the image: a non-null photo with disposed pixels is still
// a broken preview. Both halves must retain the decoded selection's colors.
Future<void> _expectOriginalRenderable(SelfiePhoto photo) async {
  expect(photo.size, ui.Size(_width.toDouble(), _height.toDouble()));
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImage(photo.image, ui.Offset.zero, ui.Paint());
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(_width, _height);
  try {
    final data = (await rendered.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    List<int> pixel(int x, int y) => List.generate(
      4,
      (channel) => data.getUint8((y * _width + x) * 4 + channel),
    );
    expect(pixel(20, 20), [255, 51, 102, 255]);
    expect(pixel(_width - 20, _height - 20), [34, 136, 238, 255]);
  } finally {
    rendered.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List source;
  late List<SelfiePhoto> ownedPhotos;

  setUpAll(() async {
    source = await _syntheticPhoto();
  });
  setUp(() => ownedPhotos = []);
  tearDown(() {
    for (final photo in ownedPhotos) {
      photo.dispose();
    }
  });

  void own(SelfiePhoto photo) => ownedPhotos.add(photo);
  Future<SelfiePhoto?> ownResult(Future<SelfiePhoto?> selection) async {
    final photo = await selection;
    if (photo != null) own(photo);
    return photo;
  }

  DeviceSelfiePhotoService service(SelfieDetector detector) =>
      DeviceSelfiePhotoService(
        picker: _Picker(XFile.fromData(source)),
        detector: detector,
      );

  test(
    'decoded photo renders while native alignment is still pending',
    () async {
      final previewArrived = Completer<SelfiePhoto>();
      final detectorStarted = Completer<Uint8List>();
      final detection = Completer<Map<Object?, Object?>>();
      final events = <String>[];
      var completed = false;
      final device = service((png) {
        events.add('detector');
        detectorStarted.complete(png);
        return detection.future;
      });
      final choice =
          ownResult(
            device.choose(
              onPreview: (photo) {
                own(photo);
                events.add('preview');
                previewArrived.complete(photo);
              },
            ),
          ).then((photo) {
            completed = true;
            return photo;
          });

      try {
        final preview = await previewArrived.future.timeout(
          const Duration(seconds: 5),
        );
        final detectorPng = await detectorStarted.future.timeout(
          const Duration(seconds: 5),
        );
        expect(events, ['preview', 'detector']);
        expect(completed, isFalse);
        expect(preview.hasMakeupAlignment, isFalse);
        await _expectOriginalRenderable(preview);
        // The fixture response describes these actual pixels, not an unrelated
        // fixed-size image that would fail dimension validation by accident.
        final decoded = await DeviceSelfiePhotoService.normalizeSelfie(
          detectorPng,
        );
        final detectorPhoto = SelfiePhoto(image: decoded);
        own(detectorPhoto);
        await _expectOriginalRenderable(detectorPhoto);
        expect(completed, isFalse);
      } finally {
        detection.complete(_faceResponse());
        await choice;
      }
      final result = (await choice)!;
      expect(result.hasMakeupAlignment, isTrue);
      expect(result.alignmentIssue, isNull);
      await _expectOriginalRenderable(result);
    },
  );

  test('disposing the early preview cannot invalidate the selected photo', () async {
    var previews = 0;
    final result = (await ownResult(
      service((_) async => _faceResponse()).choose(
        onPreview: (preview) {
          previews++;
          own(preview);
          // A removed preview may be disposed before PNG encoding or detection.
          preview.dispose();
        },
      ),
    ))!;

    expect(previews, 1);
    expect(result.hasMakeupAlignment, isTrue);
    expect(result.alignmentIssue, isNull);
    await _expectOriginalRenderable(result);
  });

  test(
    'disposing the final photo leaves the separately owned preview usable',
    () async {
      SelfiePhoto? preview;
      final result = (await ownResult(
        service((_) async => _faceResponse()).choose(
          onPreview: (photo) {
            own(photo);
            preview = photo;
          },
        ),
      ))!;

      expect(result, isNot(same(preview)));
      result.dispose();
      await _expectOriginalRenderable(preview!);
    },
  );

  final detectorFailures = <String, Object>{
    'native platform error': PlatformException(code: 'vision_failed'),
    'missing native plugin': MissingPluginException('fixture detector'),
    'alignment timeout': TimeoutException('fixture detector'),
    'explicit alignment error': const SelfieException(
      'fixture_alignment',
      'No usable landmarks.',
    ),
    'unexpected detector error': StateError('fixture detector'),
  };
  for (final failure in detectorFailures.entries) {
    test('${failure.key} retains a renderable original photo', () async {
      final previews = <SelfiePhoto>[];
      final result = (await ownResult(
        service((_) async => throw failure.value).choose(
          onPreview: (photo) {
            own(photo);
            previews.add(photo);
          },
        ),
      ))!;

      expect(previews, hasLength(1));
      expect(result.face, isNull);
      expect(result.hasMakeupAlignment, isFalse);
      expect(result.alignmentIssue, isA<SelfieException>());
      expect(result.alignmentIssue!.message, isNotEmpty);
      previews.single.dispose();
      await _expectOriginalRenderable(result);
    });
  }

  test(
    'no detected face disables makeup without rejecting the selected photo',
    () async {
      final result = (await ownResult(
        service(
          (_) async => {
            'imageWidth': _width,
            'imageHeight': _height,
            'faceCount': 0,
            'faces': <Object>[],
          },
        ).choose(),
      ))!;

      expect(result.face, isNull);
      expect(result.hasMakeupAlignment, isFalse);
      expect(result.alignmentIssue!.code, 'no_face');
      await _expectOriginalRenderable(result);
    },
  );

  test(
    'a small percentage face with complete valid landmarks can align',
    () async {
      const bounds = ui.Rect.fromLTWH(.45, .3, .1, .12);
      final result = (await ownResult(
        service((_) async => _faceResponse(bounds: bounds)).choose(),
      ))!;

      // Both dimensions are below the former .15/.18 relative framing cutoff.
      expect(result.hasMakeupAlignment, isTrue);
      expect(result.face!.bounds, bounds);
      expect(result.alignmentIssue, isNull);
      await _expectOriginalRenderable(result);
    },
  );

  for (final malformed in [
    'mismatched image dimensions',
    'incomplete eye contour',
  ]) {
    test('$malformed keeps the original and disables unsafe makeup', () async {
      final response = _faceResponse();
      if (malformed == 'mismatched image dimensions') {
        response['imageWidth'] = _width + 1;
      } else {
        ((response['faces'] as List).single as Map)['leftEye'] = <Object>[];
      }
      final result = (await ownResult(
        service((_) async => response).choose(),
      ))!;

      expect(result.face, isNull);
      expect(result.hasMakeupAlignment, isFalse);
      expect(result.alignmentIssue, isA<SelfieException>());
      await _expectOriginalRenderable(result);
    });
  }

  for (final invalid in ['corrupt image', 'oversized file']) {
    test('$invalid rejects selection without emitting a broken preview', () async {
      var previews = 0;
      var detectorCalls = 0;
      final file = invalid == 'corrupt image'
          ? XFile.fromData(Uint8List.fromList([1, 2, 3, 4]))
          : XFile.fromData(
              source,
              // Simulate a large file's reported length without allocating it.
              length: DeviceSelfiePhotoService.maxFileBytes + 1,
            );
      final device = DeviceSelfiePhotoService(
        picker: _Picker(file),
        detector: (_) async {
          detectorCalls++;
          return _faceResponse();
        },
      );

      await expectLater(
        device.choose(
          onPreview: (photo) {
            own(photo);
            previews++;
          },
        ),
        throwsA(
          isA<SelfieException>().having(
            (failure) => failure.code,
            'selection error',
            invalid == 'corrupt image' ? 'invalid_image' : 'image_too_large',
          ),
        ),
      );
      expect(previews, 0);
      expect(detectorCalls, 0);
    });
  }

  test(
    'picker cancellation returns no photo and never starts alignment',
    () async {
      var previews = 0;
      var detectorCalls = 0;
      final device = DeviceSelfiePhotoService(
        picker: _Picker(null),
        detector: (_) async {
          detectorCalls++;
          return _faceResponse();
        },
      );

      expect(
        await ownResult(
          device.choose(
            onPreview: (photo) {
              own(photo);
              previews++;
            },
          ),
        ),
        isNull,
      );
      expect(previews, 0);
      expect(detectorCalls, 0);
    },
  );
}
