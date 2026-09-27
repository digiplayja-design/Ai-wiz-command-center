import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/babyblend/babyblend_client.dart';
import 'package:ai_wiz_command_center/babyblend/babyblend_screen.dart';

final photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAHgAAABQCAIAAABd+SbeAAAAzElEQVR4nO3QQRHAIADAMEDxRKEBfVOx8liioNf57DP43rod8BdGR4yOGB0xOmJ0xOiI0RGjI0ZHjI4YHTE6YnTE6IjREaMjRkeMjhgdMTpidMToiNERoyNGR4yOGB0xOmJ0xOiI0RGjI0ZHjI4YHTE6YnTE6IjREaMjRkeMjhgdMTpidMToiNERoyNGR4yOGB0xOmJ0xOiI0RGjI0ZHjI4YHTE6YnTE6IjREaMjRkeMjhgdMTpidMToiNERoyNGR4yOGB0xOmJ0xOiI0RGjI0ZHjI4YHTE6YnTE6IjREaMjRkeMjhgdMTpidMToiNERoyNGR4yOGB0xOmJ0xOjIC4/5Amrf5r6wAAAAAElFTkSuQmCC',
);
Map<String, dynamic> asset(
  String id, {
  String kind = 'source',
  String state = 'ready',
}) => {
  'id': id,
  'kind': kind,
  'state': state,
  'width': 120,
  'height': 80,
  'imageUrl': null,
  'thumbnailUrl': null,
  'details': kind == 'portrait'
      ? {
          'age': 'baby',
          'style': 'natural',
          'photoIds': ['source-1', 'source-2'],
        }
      : <String, dynamic>{},
};
Map<String, dynamic> makeJob(
  String id, {
  String state = 'running',
  List<String> ids = const ['source-1', 'source-2'],
  String age = 'baby',
  String style = 'natural',
}) => {
  'id': id,
  'state': state,
  'photoIds': ids,
  'age': age,
  'style': style,
  'charged': state == 'completed' ? 1 : 0,
  'error': state == 'failed' ? 'No credit was charged. Please retry.' : null,
};

class FakeBlend extends BabyBlendClient {
  FakeBlend()
    : super(backendBaseUrl: 'https://fixture.test', headersBuilder: () => {});
  List<Map<String, dynamic>> assets = [asset('source-1'), asset('source-2')],
      jobs = [];
  List<String> uploadKeys = [], startKeys = [];
  List<List<String>> pairs = [];
  bool failUpload = false,
      failStart = false,
      failRemove = false,
      finish = false;
  int starts = 0, polls = 0, deletes = 0, downloads = 0;
  @override
  Future<Map<String, dynamic>> load() async => {
    'assets': assets.map((a) => Map<String, dynamic>.from(a)).toList(),
    'jobs': jobs,
  };
  @override
  Future<Map<String, dynamic>> upload(BabyBlendPhoto p, String key) async {
    uploadKeys.add(key);
    if (failUpload) {
      throw const BabyBlendException('Upload interrupted. Retry this photo.');
    }
    final a = asset(key);
    assets.insert(0, a);
    return a;
  }

  @override
  Future<Map<String, dynamic>> start({
    required String key,
    required List<String> photoIds,
    required String age,
    required String style,
  }) async {
    starts++;
    startKeys.add(key);
    pairs.add(List.from(photoIds));
    if (failStart) {
      throw const BabyBlendException(
        'Connection interrupted. Refresh before retrying.',
      );
    }
    final j = makeJob(key, ids: photoIds, age: age, style: style);
    jobs = [j];
    return j;
  }

  @override
  Future<Map<String, dynamic>> job(String id) async {
    polls++;
    final j = jobs.first;
    if (finish) {
      j['state'] = 'completed';
      final a = asset(id, kind: 'portrait');
      assets.removeWhere((a) => a['id'] == id);
      assets.insert(0, a);
      return {'job': j, 'asset': a};
    }
    return {'job': j, 'asset': null};
  }

  @override
  Future<void> remove(String id) async {
    deletes++;
    if (failRemove) {
      throw const BabyBlendException('Removal incomplete. Retry.');
    }
    assets.removeWhere((a) => a['id'] == id);
  }

  @override
  Future<Uint8List> imageBytes(String id) async {
    downloads++;
    return photo;
  }
}

final boundary = GlobalKey();
Future<void> show(
  WidgetTester t,
  FakeBlend c, {
  double width = 390,
  double scale = 1,
  Future<bool> Function()? consent,
  Future<void> Function(Uint8List, String, String)? saver,
}) async {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto'),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1000),
          textScaler: TextScaler.linear(scale),
        ),
        child: RepaintBoundary(
          key: boundary,
          child: BabyBlendScreen(
            client: c,
            ensureConsent: consent ?? () async => true,
            pickPhoto: (_) async => BabyBlendPhoto('person.png', photo),
            saveFile: saver,
          ),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(f);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
  t.view.resetPhysicalSize();
  t.view.resetDevicePixelRatio();
}

Finder get create => find.byKey(const ValueKey('create-babyblend'));
Finder get permission => find.byKey(const ValueKey('photo-permission'));
Future<void> gallery(WidgetTester t) async =>
    tap(t, find.textContaining('My portraits ('));
String token(
  String sub, {
  String session = 'session-a',
  String suffix = 'sig',
}) =>
    'e30.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'issuer', 'sub': sub, 'session_id': session})))}.$suffix';
void main() {
  test(
    'client sends both references, chosen options and consent with an idempotency key',
    () async {
      final c = BabyBlendClient(
        backendBaseUrl: 'https://fixture.test/',
        headersBuilder: () => {'Authorization': 'Bearer test'},
        client: MockClient((r) async {
          expect(r.url.path, '/api/babyblend/jobs');
          final b = jsonDecode(r.body);
          expect(b['photo_ids'], ['one', 'two']);
          expect(b['consent'], true);
          expect(b['adult_photo_permission'], true);
          return http.Response(
            jsonEncode({
              'job': makeJob(
                'key',
                ids: ['one', 'two'],
                age: 'child',
                style: 'studio',
              ),
            }),
            202,
          );
        }),
      );
      await c.start(
        key: 'key',
        photoIds: ['one', 'two'],
        age: 'child',
        style: 'studio',
      );
      c.dispose();
    },
  );
  for (final failure in [
    'wrong-id',
    'wrong-pair',
    'wrong-age',
    'invalid-state',
  ]) {
    test('client rejects $failure generation acknowledgments', () async {
      final j = makeJob(
        failure == 'wrong-id' ? 'wrong' : 'key',
        ids: failure == 'wrong-pair' ? ['two', 'one'] : ['one', 'two'],
        age: failure == 'wrong-age' ? 'child' : 'baby',
        state: failure == 'invalid-state' ? 'unknown' : 'running',
      );
      final c = BabyBlendClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient(
          (r) async => http.Response(jsonEncode({'job': j}), 200),
        ),
      );
      await expectLater(
        c.start(
          key: 'key',
          photoIds: ['one', 'two'],
          age: 'baby',
          style: 'natural',
        ),
        throwsA(isA<BabyBlendException>()),
      );
      c.dispose();
    });
  }
  test(
    'client rejects malformed workspaces and unconfirmed deletion',
    () async {
      final c = BabyBlendClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient((r) async => http.Response('{}', 200)),
      );
      await expectLater(c.load(), throwsA(isA<BabyBlendException>()));
      await expectLater(c.remove('one'), throwsA(isA<BabyBlendException>()));
      c.dispose();
    },
  );
  test(
    'account switch blocks in-flight results while token refresh preserves the session',
    () async {
      final changes = ValueNotifier(0);
      String auth = token('one');
      final response = Completer<http.Response>();
      int locks = 0;
      final c = BabyBlendClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {'Authorization': 'Bearer $auth'},
        sessionChanges: changes,
        client: MockClient((r) => response.future),
      )..onAccessDenied = () => locks++;
      final pending = c.load();
      await Future<void>.delayed(Duration.zero);
      auth = token('one', suffix: 'new');
      changes.value++;
      expect(locks, 0);
      auth = token('two');
      changes.value++;
      expect(locks, 1);
      response.complete(http.Response('{"assets":[],"jobs":[]}', 200));
      await expectLater(pending, throwsA(isA<BabyBlendException>()));
      c.dispose();
      changes.dispose();
    },
  );
  testWidgets(
    'two ready photos enable creation after permission; successful job saves without redispatch',
    (t) async {
      final c = FakeBlend()..finish = true;
      await show(t, c);
      expect(t.widget<FilledButton>(create).onPressed, isNull);
      await tap(t, permission);
      expect(t.widget<FilledButton>(create).onPressed, isNotNull);
      await tap(t, create);
      expect(c.starts, 1);
      expect(c.pairs.single, ['source-1', 'source-2']);
      await t.pump(const Duration(seconds: 4));
      await t.pump();
      expect(find.text('Your little possibility'), findsOneWidget);
      expect(c.starts, 1);
      await close(t);
    },
  );
  testWidgets('missing second photo is explained and cannot create', (t) async {
    final c = FakeBlend()..assets = [asset('source-1')];
    await show(t, c);
    expect(
      find.text('Add a different adult photo for Person 2.'),
      findsOneWidget,
    );
    expect(t.widget<FilledButton>(create).onPressed, isNull);
    await close(t);
  });
  testWidgets('AI consent refusal prevents dispatch', (t) async {
    final c = FakeBlend();
    await show(t, c, consent: () async => false);
    await tap(t, permission);
    await tap(t, create);
    expect(c.starts, 0);
    await close(t);
  });
  testWidgets(
    'replacing one reference preserves the other; upload retry reuses the same key',
    (t) async {
      final c = FakeBlend()..failUpload = true;
      await show(t, c);
      await tap(t, find.byKey(const ValueKey('photo-1')));
      await tap(t, find.text('Choose photo'));
      await tap(t, find.text('Use this photo'));
      expect(
        find.text('Upload interrupted. Retry this photo.'),
        findsOneWidget,
      );
      c.failUpload = false;
      await tap(t, find.text('Use this photo'));
      expect(c.uploadKeys[0], c.uploadKeys[1]);
      await tap(t, permission);
      await tap(t, create);
      expect(c.pairs.single, [c.uploadKeys.first, 'source-2']);
      await close(t);
    },
  );
  testWidgets(
    'ambiguous generation failure reuses the same key on explicit retry',
    (t) async {
      final c = FakeBlend()..failStart = true;
      await show(t, c);
      await tap(t, permission);
      await tap(t, create);
      c.failStart = false;
      await tap(t, create);
      expect(c.startKeys[0], c.startKeys[1]);
      await close(t);
    },
  );
  testWidgets(
    'reopening a running generation polls without starting or charging another',
    (t) async {
      final c = FakeBlend()
        ..jobs = [makeJob('running-job')]
        ..finish = true;
      await show(t, c);
      expect(find.text('KORLIX is imagining…'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
      await t.pump();
      expect(c.polls, 1);
      expect(c.starts, 0);
      expect(find.text('Your little possibility'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets('account lock clears private data and closes a photo dialog', (
    t,
  ) async {
    final c = FakeBlend();
    await show(t, c);
    await tap(t, find.byKey(const ValueKey('photo-1')));
    expect(find.text('Person 1 photo'), findsOneWidget);
    c.onAccessDenied!();
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Person 1 photo'), findsNothing);
    expect(find.textContaining('Your session changed.'), findsOneWidget);
    expect(find.text('Person 1'), findsNothing);
    await close(t);
  });
  testWidgets(
    'changing choices clears an old result and failed deletion remains retryable',
    (t) async {
      final c = FakeBlend()
        ..assets.add(asset('portrait', kind: 'portrait'))
        ..jobs = [makeJob('portrait', state: 'completed')]
        ..failRemove = true;
      await show(t, c);
      expect(find.text('Your little possibility'), findsOneWidget);
      await tap(t, find.text('Toddler'));
      expect(find.text('Your little possibility'), findsNothing);
      await gallery(t);
      await tap(t, find.byTooltip('Remove portrait'));
      await tap(t, find.text('Remove'));
      expect(find.text('Removal incomplete. Retry.'), findsOneWidget);
      c.failRemove = false;
      await tap(t, find.byTooltip('Remove portrait'));
      await tap(t, find.text('Remove'));
      expect(c.deletes, 2);
      expect(find.text('My portraits (0)'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    'private portrait download uses the authenticated client and explicit save',
    (t) async {
      final c = FakeBlend()
        ..assets.add(asset('portrait', kind: 'portrait'))
        ..jobs = [makeJob('portrait', state: 'completed')];
      int saved = 0;
      await show(
        t,
        c,
        saver: (b, n, m) async {
          saved++;
          expect(b, photo);
          expect(n, 'KORLIX-BabyBlend-portrait.png');
          expect(m, 'image/png');
        },
      );
      await tap(t, find.text('Save portrait'));
      expect(c.downloads, 1);
      expect(saved, 1);
      await close(t);
    },
  );
  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets(
      'create and gallery layouts fit ${width.toInt()} px at 125% text',
      (t) async {
        final c = FakeBlend()..assets.add(asset('portrait', kind: 'portrait'));
        await show(t, c, width: width, scale: 1.25);
        expect(t.takeException(), isNull);
        await gallery(t);
        expect(t.takeException(), isNull);
        await close(t);
      },
    );
  }
  testWidgets('optional actual screen captures', (t) async {
    final dir = Platform.environment['BABYBLEND_CAPTURE_DIR'];
    if (dir == null) return;
    await t.runAsync(() async {
      await (FontLoader('Roboto')
            ..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf')))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '${Platform.environment['KORLIX_FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
    });
    for (final width in [390.0, 1440.0]) {
      final c = FakeBlend()..assets = [];
      await show(t, c, width: width);
      await t.pump(const Duration(milliseconds: 400));
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final b = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$dir/babyblend-${width.toInt()}.png',
        ).writeAsBytes(b!.buffer.asUint8List());
      });
      await close(t);
    }
  });
}
