import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/camera_ask/camera_ask_client.dart';
import 'package:ai_wiz_command_center/camera_ask/camera_ask_screen.dart';

String token(String owner, [String signature = 's']) {
  final c = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'iss': 'test',
            'sub': owner,
            'session_id': owner + '-session',
          }),
        ),
      )
      .replaceAll('=', '');
  return 'Bearer h.$c.$signature';
}

final photo = CameraPhoto(
  bytes: File('assets/branding/korlix_mini_mark.png').readAsBytesSync(),
  name: 'test-photo.png',
);
http.Response answer([
  String text =
      '## What is visible\nA **clear label** is visible. Read its serial number before proceeding.',
]) => http.Response(
  jsonEncode({'content': text, 'generationId': 'saved-1', 'creditsUsed': 1}),
  200,
);

class Harness {
  String auth = token('alice');
  final revision = ValueNotifier<int>(0);
  int calls = 0, captures = 0, exports = 0, consents = 0;
  bool consent = true;
  List<CameraPhoto> picked = [photo];
  List<http.Request> requests = [];
  Future<http.Response> Function(http.Request)? respond;
  late final client = CameraAskClient(
    baseUrl: 'https://test.example',
    headersBuilder: () => {'Authorization': auth},
    sessionChanges: revision,
    client: MockClient((r) async {
      calls++;
      requests.add(r);
      return respond == null ? answer() : await respond!(r);
    }),
  );
  Widget screen() => CameraAskScreen(
    client: client,
    ensureConsent: (_) async {
      consents++;
      return consent;
    },
    pickPhotos: (_) async => picked,
    capture: (_) async {
      captures++;
      return photo;
    },
    saveFile: (bytes, name, mime, origin) async {
      exports++;
      expect(utf8.decode(bytes), contains('QUESTION'));
    },
  );
  void switchAccount() {
    auth = token('bob');
    revision.value++;
  }
}

Future<void> mount(
  WidgetTester t,
  Harness h, {
  double width = 390,
  bool dark = false,
}) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        brightness: dark ? Brightness.dark : Brightness.light,
        fontFamily: 'Roboto',
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(1.25),
        ),
        child: child!,
      ),
      initialRoute:'/camera',
      routes:{
        '/': (_) => const Scaffold(body:Text('Home')),
        '/camera': (_) => RepaintBoundary(
          key: const Key('camera-capture-test'),
          child: h.screen(),
        ),
      },
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder target) async {
  if (target.hitTestable().evaluate().isEmpty) {
    await t.scrollUntilVisible(
      target,
      280,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
}

Future<CameraAskTurn> ask(
  CameraAskClient c, {
  List<CameraPhoto>? photos,
  CameraAskMode mode = CameraAskMode.understand,
  List<CameraAskTurn> history = const [],
}) => c.ask(
  photos: photos ?? [photo],
  question: 'What is this?',
  mode: mode,
  language: 'es',
  detail: 'Brief',
  history: history,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null)
      await (FontLoader('MaterialIcons')..addFont(
            File(
              root +
                  '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
  });
  test('Photo validation rejects unsupported and oversized inputs', () {
    expect(
      () => CameraPhoto(bytes: Uint8List.fromList([1, 2, 3]), name: 'fake.jpg'),
      throwsA(isA<CameraAskException>()),
    );
    expect(
      () => CameraPhoto(bytes: Uint8List(8 * 1024 * 1024 + 1), name: 'big.jpg'),
      throwsA(isA<CameraAskException>()),
    );
    expect(photo.mime, 'image/png');
  });
  test(
    'Client sends exact photos and bounded context through the existing authenticated endpoint',
    () async {
      final h = Harness();
      final history = List.generate(
        6,
        (i) => CameraAskTurn(
          question: 'question-$i',
          answer: 'answer-$i',
          mode: CameraAskMode.understand,
        ),
      );
      final result = await ask(
        h.client,
        photos: [photo, photo],
        mode: CameraAskMode.compare,
        history: history,
      );
      expect(result.generationId, 'saved-1');
      expect(h.requests.single.url.path, '/api/analyze-documents');
      expect(h.requests.single.headers['Authorization'], token('alice'));
      final body = utf8.decode(
        h.requests.single.bodyBytes,
        allowMalformed: true,
      );
      expect(body, contains('camera-photo-1.png'));
      expect(body, contains('camera-photo-2.png'));
      expect(body, contains('Answer in Spanish'));
      expect(body, contains('question-5'));
      expect(body, isNot(contains('question-0')));
      expect(body, contains('K-Nova'));
      h.client.dispose();
    },
  );
  test('Invalid counts and comparison never make a request', () async {
    final h = Harness();
    await expectLater(
      ask(h.client, photos: []),
      throwsA(isA<CameraAskException>()),
    );
    await expectLater(
      ask(h.client, photos: [photo, photo, photo, photo]),
      throwsA(isA<CameraAskException>()),
    );
    await expectLater(
      ask(h.client, mode: CameraAskMode.compare),
      throwsA(isA<CameraAskException>()),
    );
    expect(h.calls, 0);
    h.client.dispose();
  });
  test('Duplicate clicks cannot start concurrent paid requests', () async {
    final h = Harness(), pending = Completer<http.Response>();
    h.respond = (_) => pending.future;
    final first = ask(h.client);
    await expectLater(ask(h.client), throwsA(isA<CameraAskException>()));
    pending.complete(answer());
    await first;
    expect(h.calls, 1);
    h.client.dispose();
  });
  test('An account change rejects a late answer and further sends', () async {
    final h = Harness(), pending = Completer<http.Response>();
    h.respond = (_) => pending.future;
    final first = ask(h.client);
    h.switchAccount();
    pending.complete(answer('private answer'));
    await expectLater(first, throwsA(isA<CameraAskException>()));
    await expectLater(ask(h.client), throwsA(isA<CameraAskException>()));
    expect(h.calls, 1);
    h.client.dispose();
  });
  test('Token refresh in the same session keeps access', () async {
    final h = Harness();
    final c = h.client;
    h.auth = token('alice', 'refreshed');
    h.revision.value++;
    expect((await ask(c)).answer, isNotEmpty);
    c.dispose();
  });
  test('Expired authentication closes the client access scope', () async {
    final h = Harness();
    h.respond = (_) async => http.Response('{"error":"expired"}', 401);
    await expectLater(ask(h.client), throwsA(isA<CameraAskException>()));
    await expectLater(ask(h.client), throwsA(isA<CameraAskException>()));
    expect(h.calls, 1);
    h.client.dispose();
  });
  test(
    'Timeout does not retry or claim the request failed without charging',
    () async {
      var calls = 0;
      final c = CameraAskClient(
        baseUrl: 'https://test.example',
        headersBuilder: () => {'Authorization': token('a')},
        timeout: const Duration(milliseconds: 20),
        client: MockClient((_) async {
          calls++;
          return Completer<http.Response>().future;
        }),
      );
      await expectLater(
        ask(c),
        throwsA(
          isA<CameraAskException>().having(
            (e) => e.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
      expect(calls, 1);
      c.dispose();
    },
  );
  test('An empty answer is not accepted as a successful result', () async {
    final h = Harness();
    h.respond = (_) async => answer(' ');
    await expectLater(ask(h.client), throwsA(isA<CameraAskException>()));
    h.client.dispose();
  });
  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 1280.0]) {
      testWidgets(
        'Camera Ask at $width dark=$dark has a visible capture action and fits large text',
        (t) async {
          final h = Harness();
          await mount(t, h, width: width, dark: dark);
          expect(
            find.byKey(const Key('camera-ask-submit')).hitTestable(),
            findsOneWidget,
          );
          expect(find.text('Take a photo'), findsOneWidget);
          await t.tap(find.byKey(const Key('camera-ask-submit')));
          await t.pumpAndSettle();
          expect(h.captures, 1);
          expect(h.calls, 0);
          expect(find.text('Ask K-Nova'), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets(
    'Preview, explicit consent, answer, follow-up, export, and new session work together',
    (t) async {
      final h = Harness();
      await mount(t, h);
      await tap(t, find.byKey(const Key('camera-ask-submit')));
      h.consent = false;
      await tap(t, find.byKey(const Key('camera-ask-submit')));
      expect(h.calls, 0);
      h.consent = true;
      await tap(t, find.byKey(const Key('camera-ask-submit')));
      expect(h.calls, 1);
      expect(find.text('Saved to History'), findsOneWidget);
      expect(find.text('What am I looking at?'), findsOneWidget);
      await tap(t, find.text('Export answers'));
      expect(h.exports, 1);
      await tap(t, find.text('Explain it simply'));
      expect(find.text('Explain that in simpler terms.'), findsOneWidget);
      await tap(t, find.byKey(const Key('camera-ask-submit')));
      expect(h.calls, 2);
      final body = utf8.decode(h.requests.last.bodyBytes, allowMalformed: true);
      expect(body, contains('What am I looking at?'));
      expect(body, contains('Explain that in simpler terms.'));
      await tap(t, find.byKey(const Key('camera-ask-new')));
      await tap(t, find.text('Start new'));
      expect(find.text('Saved to History'), findsNothing);
      expect(find.text('Take a photo'), findsOneWidget);
      await tap(t, find.byKey(const Key('camera-ask-submit')));
      await tap(t, find.byKey(const Key('camera-ask-submit')));
      expect(
        utf8.decode(h.requests.last.bodyBytes, allowMalformed: true),
        isNot(contains('Explain that in simpler terms.')),
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Comparison needs two photos and never auto-submits gallery selection',
    (t) async {
      final h = Harness()..picked = [photo, photo];
      await mount(t, h, width: 1280);
      await tap(t, find.byKey(const Key('camera-ask-gallery')));
      expect(h.calls, 0);
      await tap(t, find.text('Compare'));
      await tap(t, find.byKey(const Key('camera-ask-submit')));
      expect(h.calls, 1);
      expect(
        utf8.decode(h.requests.single.bodyBytes, allowMalformed: true),
        contains('camera-photo-2.png'),
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Pending requests keep the draft and never show a premature answer',
    (t) async {
      final h = Harness(), pending = Completer<http.Response>();
      h.respond = (_) => pending.future;
      await mount(t, h);
      await tap(t, find.byKey(const Key('camera-ask-submit')));
      await t.tap(find.byKey(const Key('camera-ask-submit')));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Looking closely…'), findsOneWidget);
      expect(find.text('Saved to History'), findsNothing);
      pending.complete(answer());
      await t.pumpAndSettle();
      expect(find.text('Saved to History'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Sign-out clears private photos and closes an enlarged preview', (
    t,
  ) async {
    final h = Harness();
    await mount(t, h);
    await tap(t, find.byKey(const Key('camera-ask-submit')));
    await tap(t, find.byTooltip('Enlarge photo'));
    expect(find.text('Photo 1'), findsOneWidget);
    h.switchAccount();
    await t.pumpAndSettle();
    expect(find.textContaining('Your sign-in changed'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text('Ask K-Nova'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('Camera Ask visual review', (t) async {
    for (final spec in [(false, 390.0), (true, 1280.0)]) {
      final h = Harness();
      await mount(t, h, width: spec.$2, dark: spec.$1);
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('camera-capture-test')),
      );
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5),
            data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'build/camera-ask-review/' +
              (spec.$1 ? 'desktop' : 'mobile') +
              '.png',
        );
        file.parent.createSync(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    }
  });
}
