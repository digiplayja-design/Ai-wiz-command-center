import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:korlix_magic_core/reveal_clip.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:korlix_magic_core/magic_client.dart';
import 'package:korlix_magic_core/magic_capture.dart';
import 'package:korlix_magic_core/magic_orbits.dart';
import 'package:korlix_magic_core/magic_result.dart';
import 'package:korlix_magic_core/magic_screen.dart';
import 'package:korlix_magic_core/magic_theme.dart';

String token(String user) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'https://fixture.invalid', 'sub': user, 'session_id': 'session-one'}))).replaceAll('=', '')}.signature';
const jobId = '10000000-0000-4000-8000-000000000001';
const opts = {
  'preset': 'executive',
  'style': 'all',
  'prompt': '',
  'intensity': 'natural',
  'accent': 'orange',
  'preserveFace': true,
};
Map<String, dynamic> job(String state) => {
  'id': jobId,
  'state': state,
  'options': opts,
};
final pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1sAAAAASUVORK5CYII=',
);

class FakeClient extends MagicClient {
  FakeClient()
    : super(
        backendUrl: 'https://fixture.invalid',
        headers: () => {'Authorization': 'Bearer ${token('owner')}'},
        client: MockClient((_) async => http.Response('{}', 200)),
      );
  final generated = Completer<Map<String, dynamic>>();
  Uint8List? submitted;
  int calls = 0;
  bool reportFails = false;
  int reports = 0;
  bool paged = false;
  final offsets = <int>[];
  @override
  Future<Map<String, dynamic>> generate(
    Uint8List bytes,
    Map<String, dynamic> options,
    String key,
  ) {
    submitted = bytes;
    calls++;
    return generated.future;
  }

  @override
  Future<Map<String, dynamic>> job(String id) async => {
    'id': id,
    'state': 'queued',
    'options': opts,
  };
  @override
  Future<Map<String, dynamic>> snapshot({int offset = 0}) async {
    offsets.add(offset);
    return {
      'plan': {'name': 'free', 'remaining': 0, 'can_generate': false},
      'jobs': paged
          ? [
              {'state': 'queued', 'options': opts, 'id': '$jobId-$offset'},
            ]
          : [],
      'next_offset': paged && offset == 0 ? 100 : null,
      'available': true,
    };
  }

  @override
  Future<void> report(String id, String reason, String details) async {
    reports++;
    if (reportFails) throw StateError('offline');
  }
}

class MemoryCapture extends XFile {
  MemoryCapture() : super('/tmp/korlix-test-no-original-file.jpg');
  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([11, 22, 33, 44]);
}

class FakeCamera extends CameraPlatform {
  int captures = 0;
  @override
  Future<List<CameraDescription>> availableCameras() async => [
    const CameraDescription(
      name: 'fake',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 0,
    ),
  ];
  @override
  Future<int> createCameraWithSettings(
    CameraDescription c,
    MediaSettings? settings,
  ) async => 1;
  @override
  Future<void> initializeCamera(
    int id, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int id) => Stream.value(
    CameraInitializedEvent(
      id,
      640,
      480,
      ExposureMode.auto,
      true,
      FocusMode.auto,
      true,
    ),
  );
  @override
  Stream<CameraErrorEvent> onCameraError(int id) =>
      StreamController<CameraErrorEvent>().stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      Stream.value(
        const DeviceOrientationChangedEvent(DeviceOrientation.portraitUp),
      );
  @override
  Widget buildPreview(int id) =>
      const ColoredBox(key: Key('live-viewfinder'), color: Colors.green);
  @override
  Future<XFile> takePicture(int id) async {
    captures++;
    return MemoryCapture();
  }

  @override
  Future<void> dispose(int id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['MAGIC_SCREENSHOT'] == '1') {
      final sdk = Platform.environment['FLUTTER_ROOT'];
      if (sdk != null) {
        for (final font in [
          ('Roboto', 'Roboto-Regular.ttf'),
          ('MaterialIcons', 'MaterialIcons-Regular.otf'),
        ]) {
          final loader = FontLoader(font.$1)
            ..addFont(
              File('$sdk/bin/cache/artifacts/material_fonts/${font.$2}')
                  .readAsBytes()
                  .then((b) => ByteData.sublistView(b)),
            );
          await loader.load();
        }
      }
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    rootBundle.evict('packages/korlix_magic_core/assets/presets.json');
  });
  test('client binds multipart key, never puts capture bytes in a URL, and clears results after account switch', () async {
    var user = 'owner';
    final changed = ValueNotifier(0);
    http.BaseRequest? seen;
    final c = MagicClient(
      backendUrl: 'https://fixture.invalid',
      headers: () => {'Authorization': 'Bearer ${token(user)}'},
      sessionChanges: changed,
      client: MockClient.streaming((q, b) async {
        seen = q;
        expect(utf8.decode(await b.toBytes()), contains('name="capture"'));
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'job': job('queued')}))),
          202,
        );
      }),
    );
    final key = magicRequestKey();
    await c.generate(Uint8List.fromList([1, 2, 3]), opts, key);
    expect(seen!.headers['X-Magic-Request-Key'], key);
    expect(seen!.url.query, isEmpty);
    expect(c.accountScope, contains('owner'));
    user = 'other';
    changed.value++;
    expect(c.valid, false);
    expect(c.accountScope, contains('owner'));
    expect(c.accountScope, isNot(contains('other')));
    expect(() => c.check(), throwsA(isA<MagicApiException>()));
    c.dispose();
    changed.dispose();
  });
  testWidgets(
    'shutter hides the viewfinder before capture; no original preview appears during upload',
    (tester) async {
      final previous = CameraPlatform.instance,
          fake = FakeCamera(),
          client = FakeClient();
      CameraPlatform.instance = fake;
      addTearDown(() => CameraPlatform.instance = previous);
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: magicTheme(),
          home: MagicCapture(client: client, options: opts),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('live-viewfinder')), findsOneWidget);
      await tester.tap(find.byKey(const Key('magic-shutter')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('live-viewfinder')), findsNothing);
      expect(find.byType(MagicOrbits), findsOneWidget);
      expect(fake.captures, 1);
      expect(client.calls, 1);
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .where((x) => x.image is MemoryImage),
        isEmpty,
      );
      client.generated.complete(job('queued'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(client.submitted, everyElement(0));
      expect(find.byKey(const Key('magic-final-image')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'report remains available without credits and reports failure honestly',
    (tester) async {
      final client = FakeClient()..reportFails = true;
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: magicTheme(),
          home: MagicResult(
            client: client,
            initialJob: job('ready'),
            autoReport: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Report this generation'), findsOneWidget);
      await tester.tap(find.text('Send report'));
      await tester.pump();
      expect(
        find.text('The report was not sent. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Report received'), findsNothing);
      client.reportFails = false;
      await tester.tap(find.text('Send report'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(client.reports, 2);
      expect(find.textContaining('Report received'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('reduced motion and pause stop orbit animation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Scaffold(body: MagicOrbits()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, false);
    expect(find.text('Pause animation'), findsOneWidget);
    await tester.tap(find.text('Pause animation'));
    await tester.pumpAndSettle();
    expect(find.text('Resume animation'), findsOneWidget);
  });
  test(
    'shareable reveal is an animated GIF ending with the final artwork',
    () async {
      final source = img.Image(width: 36, height: 48);
      img.fill(source, color: img.ColorRgb8(240, 90, 20));
      final bytes = await makeRevealClip(
        Uint8List.fromList(img.encodePng(source)),
      );
      final decoded = img.decodeGif(bytes)!;
      expect(decoded.frames.length, 24);
      expect(decoded.frames.first.getPixel(0, 0).r, lessThan(30));
      final last = decoded.frames.last;
      expect(
        last.getPixel(last.width ~/ 2, last.height ~/ 2).r,
        greaterThan(200),
      );
      expect(last.frameDuration, 2000);
    },
  );
  testWidgets('gallery loads older results without duplicating current cards', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await rootBundle.loadString(
        'packages/korlix_magic_core/assets/presets.json',
      );
      await SharedPreferences.getInstance();
    });
    final client = FakeClient()..paged = true;
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: magicTheme(),
        home: MagicScreen(
          client: client,
          ensureConsent: () async => true,
          standalone: true,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Load older photos'));
    await tester.tap(find.text('Load older photos'));
    await tester.pumpAndSettle();
    expect(client.offsets, contains(100));
    expect(find.text('Load older photos'), findsNothing);
    expect(find.byKey(ValueKey('$jobId-0')), findsOneWidget);
    expect(find.byKey(ValueKey('$jobId-100')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'phone layout renders real preset screen with no overflow or source image',
    (tester) async {
      await tester.runAsync(() async {
        await rootBundle.loadString(
          'packages/korlix_magic_core/assets/presets.json',
        );
        await SharedPreferences.getInstance();
      });
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = FakeClient();
      addTearDown(client.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: magicTheme(),
          home: RepaintBoundary(
            key: key,
            child: MagicScreen(
              client: client,
              ensureConsent: () async => true,
              standalone: true,
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Pick your kind of magic'), findsOneWidget);
      if (Platform.environment['MAGIC_SCREENSHOT'] == '1') {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/korlix-magic-home.png')
              .writeAsBytes(data!.buffer.asUint8List());
        });
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
