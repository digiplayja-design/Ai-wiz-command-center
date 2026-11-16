import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:esha_by_korlix/app_controller.dart';
import 'package:esha_by_korlix/models.dart';
import 'package:esha_by_korlix/services/korlix_api.dart';
import 'package:esha_by_korlix/services/purchases.dart';
import 'package:esha_by_korlix/services/selfie.dart';
import 'package:esha_by_korlix/services/vanity_sync.dart';
import 'package:esha_by_korlix/ui/app.dart';
import 'package:esha_by_korlix/ui/selfie_studio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

class _PhotoService implements SelfiePhotoService {
  Future<SelfiePhoto?> Function() next = () async => null;

  @override
  Future<void> discardInterruptedSelection() async {}

  @override
  Future<SelfiePhoto?> choose({
    void Function(String message)? onProgress,
    void Function(SelfiePhoto photo)? onPreview,
  }) {
    onProgress?.call('Aligning the look on your device…');
    return next();
  }
}

class _VanityGateway implements VanityGateway {
  @override
  Future<VanityRecord> loadVanity() async => VanityRecord(Vanity(), 1);

  @override
  Future<VanityRecord> saveVanity(Vanity state, int expectedVersion) async =>
      VanityRecord(state, expectedVersion + 1);
}

class _Fixture {
  final service = _PhotoService();
  bool accessAllowed = true;
  bool _closed = false;
  late EshaController c;

  void close() {
    if (_closed) return;
    _closed = true;
    c.dispose();
  }

  Future<void> start() async {
    final local = MemoryStore();
    final api = KorlixApi(
      config: fixtureConfig(),
      secureStorage: MemoryStore(),
      localStorage: local,
      platform: 'unsupported',
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/signin') {
          return http.Response(jsonEncode(authPayload(accountA)), 200);
        }
        if (request.url.path == '/api/esha/billing/status') {
          return http.Response(
            jsonEncode({
              'appAccess': {'active': accessAllowed, 'source': 'developer'},
              'membership': {'active': false, 'verificationFresh': false},
              'consultationEnabled': false,
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    c = EshaController(
      catalog: fixtureCatalog(),
      api: api,
      sync: VanitySync(gateway: _VanityGateway(), storage: local),
      purchases: EshaPurchases(api, store: NoNativeStore()),
      selfieService: service,
    )..initializing = false;
    addTearDown(close);
    await c.signIn('developer@example.test', 'fixture-only');
    await c.purchases.refresh();
    expect(c.canEditCollection, isTrue);
  }

  Future<void> selectPhoto({bool aligned = true}) async {
    final photo = await _photo(aligned: aligned);
    service.next = () async => photo;
    await c.selfie.choosePhoto();
    expect(c.selfie.photo, same(photo));
  }
}

Future<SelfiePhoto> _photo({bool aligned = true}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var y = 0; y < 200; y++) {
    canvas.drawRect(
      Rect.fromLTWH(0, y.toDouble(), 200, 1),
      Paint()
        ..isAntiAlias = false
        ..color = Color.fromARGB(255, 202 + y % 4 * 4, 151 + y % 4 * 3, 139),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 200);
  picture.dispose();
  List<Offset> ellipse(Offset center, double x, double y) =>
      List.generate(24, (i) {
        final angle = math.pi * 2 * i / 24;
        return center + Offset(x * math.cos(angle), y * math.sin(angle));
      });
  return SelfiePhoto(
    image: image,
    face: aligned
        ? FaceLandmarks(
            bounds: const Rect.fromLTWH(.1, .1, .8, .8),
            outerLips: ellipse(const Offset(.5, .69), .19, .08),
            innerLips: ellipse(const Offset(.5, .69), .11, .025),
            leftEye: ellipse(const Offset(.34, .38), .12, .04),
            rightEye: ellipse(const Offset(.66, .38), .12, .04),
          )
        : null,
    alignmentIssue: aligned
        ? null
        : const SelfieException('no_face', 'No clear face was found.'),
  );
}

Future<Uint8List> _render(EshaController c) async {
  final recorder = ui.PictureRecorder();
  SelfieMakeupPainter(
    photo: c.selfie.photo!,
    look: c.vanity.studio,
    showOriginal: c.selfie.showOriginal,
    intensity: c.selfie.intensity,
  ).paint(Canvas(recorder), const Size(200, 200));
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 200);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<_Fixture> _ready({bool aligned = true}) async {
  final fixture = _Fixture();
  await fixture.start();
  await fixture.selectPhoto(aligned: aligned);
  return fixture;
}

Future<void> _pumpStudio(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(500, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: eshaTheme,
      home: Scaffold(body: StudioScreen(controller: fixture.c)),
    ),
  );
}

SelfieMakeupPainter _widgetPainter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(find.byKey(const Key('selfie-preview-image')))
            .painter!
        as SelfieMakeupPainter;

String _lookStatus(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('studio-look-status'))).data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final edits = <String, StudioLook Function(StudioLook)>{
    'shade': (look) => look.copyWith(shade: 3),
    'finish': (look) => look.copyWith(finish: 'Gloss'),
    'lashes': (look) => look.copyWith(lashes: 'Bold'),
  };
  for (final edit in edits.entries) {
    test(
      '${edit.key} selection exits Original and visibly changes that look',
      () async {
        final f = await _ready();
        final initialTryOn = await _render(f.c);
        f.c.selfie.setShowOriginal(true);
        final original = await _render(f.c);

        f.c.setStudio(edit.value(f.c.vanity.studio));

        expect(f.c.selfie.showOriginal, isFalse);
        final editedTryOn = await _render(f.c);
        expect(listEquals(editedTryOn, original), isFalse);
        // This also proves the selected setting changes the makeup itself,
        // rather than only redisplaying the previous overlay.
        expect(listEquals(editedTryOn, initialTryOn), isFalse);
        f.c.selfie.setShowOriginal(true);
        expect(listEquals(await _render(f.c), original), isTrue);
      },
    );
  }

  test(
    'reselecting the same shade exits Original without a redundant save',
    () async {
      final f = await _ready();
      final initialTryOn = await _render(f.c);
      f.c.selfie.setShowOriginal(true);
      final unchangedVanity = f.c.vanity;

      f.c.setStudio(f.c.vanity.studio.copyWith(shade: f.c.vanity.studio.shade));

      expect(f.c.selfie.showOriginal, isFalse);
      expect(f.c.vanity, same(unchangedVanity));
      expect(listEquals(await _render(f.c), initialTryOn), isTrue);
    },
  );

  test(
    'opening a saved look activates its makeup after Original comparison',
    () async {
      final f = await _ready();
      f.c.setStudio(
        const StudioLook(shade: 3, finish: 'Gloss', lashes: 'Bold'),
      );
      expect(f.c.saveLook(), isTrue);
      final saved = f.c.vanity.looks.single;
      final savedPreview = await _render(f.c);
      f.c.setStudio(const StudioLook());
      f.c.selfie.setShowOriginal(true);

      f.c.setStudio(saved);

      expect(f.c.selfie.showOriginal, isFalse);
      expect(
        f.c.vanity.studio.toJson(includeId: false),
        saved.toJson(includeId: false),
      );
      expect(listEquals(await _render(f.c), savedPreview), isTrue);
      f.c.selfie.setShowOriginal(true);
      f.c.setStudio(saved);
      expect(f.c.selfie.showOriginal, isFalse);
    },
  );

  test(
    'loading or account transitions cannot change settings or Original mode',
    () async {
      final f = await _ready();
      f.c.selfie.setShowOriginal(true);
      final before = f.c.vanity;
      final next = before.studio.copyWith(shade: 2);
      f.c.sync.status = SyncState.loading;
      f.c.setStudio(next);
      expect(f.c.vanity, same(before));
      expect(f.c.selfie.showOriginal, isTrue);
      f.c.sync.status = SyncState.saved;
      f.c.authBusy = true;
      f.c.setStudio(next);
      expect(f.c.vanity, same(before));
      expect(f.c.selfie.showOriginal, isTrue);
      f.c.authBusy = false;
      f.c.initializing = true;
      f.c.setStudio(next);
      expect(f.c.vanity, same(before));
      expect(f.c.selfie.showOriginal, isTrue);
      f.c.initializing = false;
    },
  );

  test(
    'editing settings while a new selection is busy does not force Try-on',
    () async {
      final f = await _ready();
      f.c.selfie.setShowOriginal(true);
      final original = await _render(f.c);
      final picker = Completer<SelfiePhoto?>();
      f.service.next = () => picker.future;
      final selection = f.c.selfie.choosePhoto();
      try {
        await Future<void>.delayed(Duration.zero);
        expect(f.c.selfie.busy, isTrue);
        expect(f.c.selfie.canTryOn, isTrue);
        f.c.setStudio(f.c.vanity.studio.copyWith(shade: 3));
        expect(f.c.vanity.studio.shade, 3);
        expect(f.c.selfie.showOriginal, isTrue);
        expect(listEquals(await _render(f.c), original), isTrue);
      } finally {
        picker.complete(null);
        await selection;
      }
    },
  );

  test(
    'revoked app access cannot apply a look or retain a usable selfie',
    () async {
      final f = await _ready();
      final selected = f.c.selfie.photo!;
      final before = f.c.vanity;
      f.accessAllowed = false;
      await f.c.purchases.refresh();

      f.c.setStudio(before.studio.copyWith(shade: 3));

      expect(f.c.hasAppAccess, isFalse);
      expect(f.c.vanity, same(before));
      expect(f.c.selfie.photo, isNull);
      expect(f.c.selfie.canTryOn, isFalse);
      expect(selected.image.debugDisposed, isTrue);
    },
  );

  test(
    'sign-out clears the selected image before any later look selection',
    () async {
      final f = await _ready();
      final selected = f.c.selfie.photo!;
      f.c.selfie.setShowOriginal(true);
      await f.c.signOut();
      final guest = f.c.vanity;

      f.c.setStudio(
        const StudioLook(shade: 3, finish: 'Gloss', lashes: 'Bold'),
      );

      expect(f.c.session, isNull);
      expect(f.c.vanity, same(guest));
      expect(f.c.selfie.photo, isNull);
      expect(f.c.selfie.canTryOn, isFalse);
      expect(selected.image.debugDisposed, isTrue);
    },
  );

  testWidgets('look controls activate Try-on and Original remains selectable', (
    tester,
  ) async {
    final f = (await tester.runAsync(_ready))!;
    f.c.selfie.setShowOriginal(true);
    await _pumpStudio(tester, f);
    expect(_lookStatus(tester), contains('Original is showing'));

    await tester.ensureVisible(find.text('Gloss'));
    await tester.tap(find.text('Gloss'));
    await tester.pump();
    expect(f.c.selfie.showOriginal, isFalse);
    expect(_widgetPainter(tester).showOriginal, isFalse);
    expect(_widgetPainter(tester).look.finish, 'Gloss');

    await tester.ensureVisible(find.text('Original'));
    await tester.tap(find.text('Original'));
    await tester.pump();
    expect(f.c.selfie.showOriginal, isTrue);
    expect(_widgetPainter(tester).showOriginal, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    f.close();
  });

  testWidgets(
    'unaligned photo keeps Original and clearly labels settings-only edits',
    (tester) async {
      final f = (await tester.runAsync(() => _ready(aligned: false)))!;
      final original = (await tester.runAsync(() => _render(f.c)))!;
      await _pumpStudio(tester, f);
      expect(_lookStatus(tester), startsWith('Settings only.'));
      expect(_lookStatus(tester), contains('Crop / zoom'));
      expect(_lookStatus(tester), contains('Change selfie'));

      await tester.ensureVisible(find.text('Gloss'));
      await tester.tap(find.text('Gloss'));
      await tester.pump();
      expect(f.c.vanity.studio.finish, 'Gloss');
      expect(f.c.selfie.showOriginal, isTrue);
      expect(_widgetPainter(tester).showOriginal, isTrue);
      final after = (await tester.runAsync(() => _render(f.c)))!;
      expect(listEquals(after, original), isTrue);
      expect(_lookStatus(tester), startsWith('Settings only.'));

      await tester.ensureVisible(find.text('Save this look'));
      await tester.tap(find.text('Save this look'));
      await tester.pump();
      expect(f.c.vanity.looks.single.finish, 'Gloss');
      await tester.pumpWidget(const SizedBox.shrink());
      f.close();
    },
  );

  testWidgets(
    'pending preparation has distinct guidance beside the look controls',
    (tester) async {
      final f = _Fixture();
      await f.start();
      final picker = Completer<SelfiePhoto?>();
      f.service.next = () => picker.future;
      final selection = f.c.selfie.choosePhoto();
      await _pumpStudio(tester, f);
      try {
        expect(f.c.selfie.busy, isTrue);
        expect(
          _lookStatus(tester),
          startsWith('Photo preparation is in progress.'),
        );
        expect(_lookStatus(tester), isNot(contains('Settings only.')));
        await tester.ensureVisible(find.text('Gloss'));
        await tester.tap(find.text('Gloss'));
        await tester.pump();
        expect(f.c.vanity.studio.finish, 'Gloss');
        expect(f.c.selfie.photo, isNull);
      } finally {
        picker.complete(null);
        await tester.pump();
        await selection;
      }
      expect(_lookStatus(tester), contains('Upload selfie'));
      await tester.pumpWidget(const SizedBox.shrink());
      f.close();
    },
  );
}
