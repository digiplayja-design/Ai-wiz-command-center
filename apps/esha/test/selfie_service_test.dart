import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:esha_by_korlix/app_controller.dart';
import 'package:esha_by_korlix/services/korlix_api.dart';
import 'package:esha_by_korlix/services/purchases.dart';
import 'package:esha_by_korlix/services/selfie.dart';
import 'package:esha_by_korlix/services/vanity_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

class _SelfieService implements SelfiePhotoService {
  final requests = <Completer<SelfiePhoto?>>[];
  int startupCalls = 0;
  @override
  Future<void> discardInterruptedSelection() async => startupCalls++;
  @override
  Future<SelfiePhoto?> choose({void Function(String message)? onProgress}) {
    onProgress?.call('Preparing on device');
    final request = Completer<SelfiePhoto?>();
    requests.add(request);
    return request.future;
  }
}

class _InterruptedStartupService extends _SelfieService {
  _InterruptedStartupService(this.startup);
  final Future<void> startup;
  @override
  Future<void> discardInterruptedSelection() => startup;
}

class _RestoringApi extends KorlixApi {
  _RestoringApi()
    : super(
        config: fixtureConfig(),
        secureStorage: MemoryStore(),
        localStorage: MemoryStore(),
        platform: 'unsupported',
        client: MockClient((_) async => http.Response('{}', 503)),
      );
  bool restored = false;
  @override
  Future<AuthSession?> restoreSession() async {
    restored = true;
    return null;
  }
}

Map<Object?, Object?> _response() => {
  'imageWidth': 240,
  'imageHeight': 320,
  'faceCount': 1,
  'faces': [
    {
      'bounds': {'left': .15, 'top': .1, 'width': .7, 'height': .8},
      'outerLips': [
        [.35, .65],
        [.43, .61],
        [.5, .63],
        [.57, .61],
        [.65, .65],
        [.56, .70],
        [.44, .70],
      ],
      'innerLips': [
        [.39, .65],
        [.5, .64],
        [.61, .65],
        [.5, .67],
      ],
      'leftEye': [
        [.25, .35],
        [.32, .32],
        [.4, .35],
        [.32, .38],
      ],
      'rightEye': [
        [.6, .35],
        [.68, .32],
        [.75, .35],
        [.68, .38],
      ],
      'yaw': 0.0,
      'pitch': 0.0,
    },
  ],
};

Future<SelfiePhoto> _photo() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xffbd997c), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(240, 320);
  picture.dispose();
  return SelfiePhoto(
    image: image,
    face: FaceLandmarks.fromResponse(_response(), const ui.Size(240, 320)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('selfie ownership and async lifecycle', () {
    late _SelfieService service;
    late SelfieStudioController controller;
    setUp(() {
      service = _SelfieService();
      controller = SelfieStudioController(service: service);
    });
    tearDown(() => controller.dispose());
    void allow([String user = 'owner-a', int epoch = 1]) => controller
        .updateAccess(ownerId: user, accountEpoch: epoch, allowed: true);

    test(
      'photo picker is unavailable without verified account access',
      () async {
        await controller.choosePhoto();
        expect(service.requests, isEmpty);
        controller.updateAccess(
          ownerId: 'owner-a',
          accountEpoch: 1,
          allowed: false,
        );
        await controller.choosePhoto();
        expect(service.requests, isEmpty);
      },
    );

    test(
      'photo preview and comparison are local to the active session',
      () async {
        allow();
        final pending = controller.choosePhoto();
        await Future<void>.delayed(Duration.zero);
        final selected = await _photo();
        service.requests.single.complete(selected);
        await pending;
        expect(controller.photo, same(selected));
        expect(controller.busy, isFalse);
        controller.setShowOriginal(true);
        controller.setIntensity(.7);
        expect(controller.showOriginal, isTrue);
        expect(controller.intensity, .7);
        controller.removePhoto();
        expect(controller.photo, isNull);
        expect(controller.showOriginal, isFalse);
        expect(controller.intensity, .55);
        expect(service.startupCalls, 1);
      },
    );

    test('cancelling the OS picker preserves the previous selfie', () async {
      allow();
      final first = controller.choosePhoto();
      await Future<void>.delayed(Duration.zero);
      final photo = await _photo();
      service.requests[0].complete(photo);
      await first;
      final second = controller.choosePhoto();
      await Future<void>.delayed(Duration.zero);
      service.requests[1].complete(null);
      await second;
      expect(controller.photo, same(photo));
      expect(controller.error, isNull);
      expect(controller.busy, isFalse);
    });

    test(
      'invalid replacement leaves a working previous preview and a clear error',
      () async {
        allow();
        final first = controller.choosePhoto();
        await Future<void>.delayed(Duration.zero);
        final photo = await _photo();
        service.requests[0].complete(photo);
        await first;
        final next = controller.choosePhoto();
        await Future<void>.delayed(Duration.zero);
        service.requests[1].completeError(
          const SelfieException('no_face', 'Choose one clear face.'),
        );
        await next;
        expect(controller.photo, same(photo));
        expect(controller.error, 'Choose one clear face.');
        expect(controller.canChoose, isTrue);
      },
    );

    test('account switch discards a late photo and cannot clear the new busy state', () async {
      allow();
      final old = controller.choosePhoto();
      await Future<void>.delayed(Duration.zero);
      allow('owner-b', 2);
      final current = controller.choosePhoto();
      await Future<void>.delayed(Duration.zero);
      service.requests[0].complete(await _photo());
      await old;
      expect(controller.photo, isNull);
      expect(controller.busy, isTrue);
      final newPhoto = await _photo();
      service.requests[1].complete(newPhoto);
      await current;
      expect(controller.photo, same(newPhoto));
      expect(controller.busy, isFalse);
    });

    test(
      'remove during detection prevents delayed image restoration',
      () async {
        allow();
        final request = controller.choosePhoto();
        await Future<void>.delayed(Duration.zero);
        controller.removePhoto();
        service.requests.single.complete(await _photo());
        await request;
        expect(controller.photo, isNull);
        expect(controller.busy, isFalse);
        expect(controller.error, isNull);
      },
    );

    test('revoked access and sign-out clear photos immediately', () async {
      allow();
      final request = controller.choosePhoto();
      await Future<void>.delayed(Duration.zero);
      service.requests.single.complete(await _photo());
      await request;
      controller.updateAccess(
        ownerId: 'owner-a',
        accountEpoch: 1,
        allowed: false,
      );
      expect(controller.photo, isNull);
      expect(controller.canChoose, isFalse);
      controller.updateAccess(ownerId: null, accountEpoch: 2, allowed: false);
      expect(controller.photo, isNull);
    });
  });

  test(
    'failed interrupted-selection cleanup does not poison new selections',
    () async {
      final service = _InterruptedStartupService(
        Future<void>.error(StateError('lost picker')),
      );
      final controller = SelfieStudioController(service: service);
      addTearDown(controller.dispose);
      controller.updateAccess(
        ownerId: 'owner-a',
        accountEpoch: 1,
        allowed: true,
      );
      final selected = controller.choosePhoto();
      await Future<void>.delayed(Duration.zero);
      expect(service.requests, hasLength(1));
      service.requests.single.complete(null);
      await selected;
      expect(controller.busy, isFalse);
      expect(controller.error, isNull);
    },
  );

  test(
    'unresponsive photo cleanup cannot block main app account restoration',
    () async {
      final startup = Completer<void>();
      final api = _RestoringApi();
      final controller = EshaController(
        catalog: fixtureCatalog(),
        api: api,
        sync: VanitySync(gateway: api, storage: MemoryStore()),
        purchases: EshaPurchases(api, store: NoNativeStore()),
        selfieService: _InterruptedStartupService(startup.future),
      );
      final initialized = controller.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(api.restored, isTrue);
      expect(controller.initializing, isFalse);
      startup.complete();
      await initialized;
      await controller.selfie.initialize();
      controller.dispose();
    },
  );

  testWidgets(
    'hanging cleanup is bounded and cannot keep the picker busy forever',
    (tester) async {
      final startup = Completer<void>();
      final service = _InterruptedStartupService(startup.future);
      final controller = SelfieStudioController(service: service);
      addTearDown(controller.dispose);
      controller.updateAccess(
        ownerId: 'owner-a',
        accountEpoch: 1,
        allowed: true,
      );
      final selected = controller.choosePhoto();
      await tester.pump(const Duration(seconds: 4));
      expect(service.requests, hasLength(1));
      service.requests.single.complete(null);
      await tester.pump();
      await selected;
      expect(controller.busy, isFalse);
      startup.complete();
      await tester.pump();
    },
  );

  group('face alignment contract', () {
    test('zero and multiple faces are rejected with actionable messages', () {
      for (final count in [0, 2]) {
        expect(
          () => FaceLandmarks.fromResponse({
            'imageWidth': 240,
            'imageHeight': 320,
            'faceCount': count,
            'faces': [],
          }, const ui.Size(240, 320)),
          throwsA(
            isA<SelfieException>().having(
              (e) => e.code,
              'code',
              count == 0 ? 'no_face' : 'multiple_faces',
            ),
          ),
        );
      }
    });
    test('preview and detector dimensions must agree', () {
      expect(
        () => FaceLandmarks.fromResponse(_response(), const ui.Size(320, 240)),
        throwsA(isA<SelfieException>()),
      );
    });
    test('missing inner mouth and invalid geometry cannot paint over teeth or background', () {
      final missing = _response();
      ((missing['faces'] as List).single as Map)['innerLips'] = [];
      expect(
        () => FaceLandmarks.fromResponse(missing, const ui.Size(240, 320)),
        throwsA(isA<SelfieException>()),
      );
      final invalid = _response();
      ((invalid['faces'] as List).single as Map)['leftEye'] = [
        [double.nan, .3],
        [.3, .3],
        [.4, .4],
        [.3, .4],
      ];
      expect(
        () => FaceLandmarks.fromResponse(invalid, const ui.Size(240, 320)),
        throwsA(isA<SelfieException>()),
      );
    });
    test('profile angle is rejected instead of making up a second eye', () {
      final response = _response();
      ((response['faces'] as List).single as Map)['yaw'] = 45.0;
      expect(
        () => FaceLandmarks.fromResponse(response, const ui.Size(240, 320)),
        throwsA(
          isA<SelfieException>().having((e) => e.code, 'code', 'face_angle'),
        ),
      );
    });
  });

  group('photo normalization', () {
    test(
      'EXIF rotated photo is decoded upright with matching pixels',
      () async {
        final bytes = await File('test/fixtures/selfie_orientation.jpg')
            .readAsBytes();
        final image = await DeviceSelfiePhotoService.normalizeSelfie(bytes);
        expect(image.width, 320);
        expect(image.height, 240);
        final pixels = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final offset = (40 * image.width + 40) * 4;
        // EXIF6 turns the original bottom-left blue quadrant to the top-left.
        expect(pixels!.getUint8(offset + 2), greaterThan(220));
        expect(pixels.getUint8(offset), lessThan(30));
        image.dispose();
      },
    );
    test('large image downscales before detection and malformed input fails safely', () async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
          .drawColor(const ui.Color(0xffcc9988), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final original = await picture.toImage(2000, 1000);
      picture.dispose();
      final data = await original.toByteData(format: ui.ImageByteFormat.png);
      original.dispose();
      final image = await DeviceSelfiePhotoService.normalizeSelfie(
        data!.buffer.asUint8List(),
      );
      expect(image.width, 1600);
      expect(image.height, 800);
      image.dispose();
      await expectLater(
        DeviceSelfiePhotoService.normalizeSelfie(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<SelfieException>()),
      );
    });
  });
}
