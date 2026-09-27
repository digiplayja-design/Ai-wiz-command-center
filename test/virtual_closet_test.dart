import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/virtual_closet/closet_client.dart';
import 'package:ai_wiz_command_center/virtual_closet/closet_screen.dart';

Map<String, dynamic> asset(String id, String kind, {String? name}) => {
  'id': id,
  'kind': kind,
  'name': name ?? (kind == 'photo' ? 'My photo' : 'Ivory blazer'),
  'category': kind == 'garment' ? 'outerwear' : kind,
  'state': 'ready',
  'imageUrl': null,
  'thumbnailUrl': null,
};
Map<String, dynamic> jobData(String state, {String kind = 'tryon'}) => {
  'id': 'job',
  'kind': kind,
  'state': state,
  'photo_id': 'photo',
  'garment_ids': ['garment'],
  'prompt': 'Business lunch',
  'result': kind == 'style'
      ? {
          'message': 'Try the blazer.',
          'garmentIds': ['garment'],
        }
      : {'asset_id': 'look'},
  'error': state == 'failed' ? 'Please retry.' : null,
};

class FakeCloset extends ClosetClient {
  FakeCloset()
    : super(backendBaseUrl: 'https://example.test', headersBuilder: () => {});
  List<Map<String, dynamic>> assets = [];
  List<Map<String, dynamic>> jobs = [];
  int uploads = 0, starts = 0, removes = 0, polls = 0;
  String? startedPhotoId;
  List<String> startedGarmentIds = [];
  bool failUpload = false;
  String? error;
  Completer<ClosetJob>? holdStart;
  @override
  Future<ClosetSnapshot> load() async {
    if (error != null) throw ClosetException(error!);
    return ClosetSnapshot.fromJson({'assets': assets, 'jobs': jobs});
  }

  @override
  Future<ClosetAsset> upload({
    required PlatformFile file,
    required String key,
    required String kind,
    required String name,
    required String category,
  }) async {
    uploads++;
    if (failUpload) throw const ClosetException('Upload interrupted.');
    final a = asset(key, kind, name: name);
    assets.add(a);
    return ClosetAsset.fromJson(a);
  }

  @override
  Future<ClosetJob> start({
    required String key,
    required String kind,
    required String prompt,
    String? photoId,
    List<String> garmentIds = const [],
  }) async {
    starts++;
    startedPhotoId = photoId;
    startedGarmentIds = List.of(garmentIds);
    if (holdStart != null) return holdStart!.future;
    jobs = [jobData('running', kind: kind)];
    return ClosetJob.fromJson(jobs.first);
  }

  @override
  Future<ClosetJob> job(String id) async {
    polls++;
    return ClosetJob.fromJson(jobs.first);
  }

  @override
  Future<void> remove(String id) async {
    removes++;
    assets.removeWhere((a) => a['id'] == id);
  }

  @override
  Future<Uint8List> imageBytes(String id) async =>
      Uint8List.fromList([137, 80, 78, 71]);
}

Future<void> show(
  WidgetTester tester,
  FakeCloset c, {
  double width = 1500,
  double scale = 1,
  Future<bool> Function()? consent,
  Future<PlatformFile?> Function()? picker,
  Future<void> Function(Uint8List, String)? save,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1100),
          textScaler: TextScaler.linear(scale),
        ),
        child: VirtualClosetScreen(
          client: c,
          ensureConsent: consent ?? () async => true,
          pickFile: picker,
          saveImage: save,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  tearDown(() {});
  test(
    'multipart upload uses authenticated headers and a reusable request key',
    () async {
      final c = ClosetClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {
          'Authorization': 'Bearer offline',
          'Content-Type': 'application/json',
        },
        client: MockClient((r) async {
          expect(r.url.path, '/api/virtual-closet/assets');
          expect(r.headers['Authorization'], 'Bearer offline');
          expect(r.headers['content-type'], startsWith('multipart/form-data;'));
          final s = utf8.decode(r.bodyBytes, allowMalformed: true);
          expect(s, contains('name="request_key"\r\n\r\nretry-key'));
          expect(s, contains('name="image"'));
          return http.Response(
            jsonEncode({'asset': asset('id', 'photo')}),
            201,
          );
        }),
      );
      await c.upload(
        file: PlatformFile(name: 'photo.jpg', size: 3, bytes: Uint8List(3)),
        key: 'retry-key',
        kind: 'photo',
        name: 'My photo',
        category: 'photo',
      );
      c.dispose();
    },
  );
  test(
    'session switch rejects an old in-flight response but token rotation keeps the session',
    () async {
      String token(String user, String session, String signature) =>
          'a.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'issuer', 'sub': user, 'session_id': session})))}.$signature';
      String auth = token('one', 'session', 'signature');
      final revision = ValueNotifier(0);
      final pending = Completer<http.Response>();
      int locked = 0;
      final c = ClosetClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {'Authorization': 'Bearer $auth'},
        sessionChanges: revision,
        client: MockClient((_) => pending.future),
      )..onAccessDenied = () => locked++;
      final work = c.load();
      auth = token('one', 'session', 'rotated');
      revision.value++;
      expect(locked, 0);
      auth = token('two', 'different', 'signature');
      revision.value++;
      expect(locked, 1);
      final expectation = expectLater(
        work,
        throwsA(isA<ClosetException>().having((e) => e.status, 'status', 401)),
      );
      pending.complete(http.Response('{"assets":[],"jobs":[]}', 200));
      await expectation;
      c.dispose();
      revision.dispose();
    },
  );
  test('missing session and malformed responses are readable errors', () async {
    for (final r in [
      http.Response('not json', 200),
      http.Response('{"error":"Upgrade required"}', 403),
      http.Response('{"error":"Sign in"}', 401),
    ]) {
      final c = ClosetClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {},
        client: MockClient((_) async => r),
      );
      await expectLater(c.load(), throwsA(isA<ClosetException>()));
      c.dispose();
    }
    for (var i = 0; i < 10; i++) {
      expect(closetRequestKey(), matches(RegExp(r'^[0-9a-f-]{36}$')));
    }
  });
  testWidgets(
    'empty closet gives clear first steps and prevents an incomplete try-on',
    (tester) async {
      final c = FakeCloset();
      await show(tester, c);
      expect(find.text('Your style starts here'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('closet-try-on')))
            .onPressed,
        isNull,
      );
      expect(find.text('Upload your photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('phone tabs and enlarged text stay usable', (tester) async {
    for (final width in [360.0, 390.0]) {
      final c = FakeCloset();
      await show(tester, c, width: width, scale: 1.6);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Try on'));
      await tester.pumpAndSettle();
      expect(find.text('Upload your photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('KORLIX').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('closet-style-prompt')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets('adding clothes and a photo in either order enables try-on', (
    tester,
  ) async {
    for (final width in [390.0, 1500.0]) {
      for (final photoFirst in [false, true]) {
        final c = FakeCloset();
        await show(
          tester,
          c,
          width: width,
          picker: () async =>
              PlatformFile(name: 'Outfit.jpg', size: 3, bytes: Uint8List(3)),
        );
        Future<void> tab(String label) async {
          if (width < 1100) {
            await tester.tap(find.text(label).last);
            await tester.pumpAndSettle();
          }
        }

        for (final kind
            in photoFirst ? ['photo', 'garment'] : ['garment', 'photo']) {
          await tab(kind == 'photo' ? 'Try on' : 'Closet');
          final button = find.byKey(
            Key(kind == 'photo' ? 'closet-upload-photo' : 'closet-add-clothes'),
          );
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          if (kind == 'garment') {
            await tester.tap(find.text('Save item'));
          }
          await tester.pumpAndSettle();
        }
        await tab('Try on');
        final button = find.byKey(const Key('closet-try-on'));
        expect(
          tester.widget<FilledButton>(button).onPressed,
          isNotNull,
          reason: 'width=$width photoFirst=$photoFirst',
        );
        expect(find.text('Ready to try on'), findsOneWidget);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        await tester.pump();
        expect(c.starts, 1);
        expect(
          c.startedPhotoId,
          c.assets.singleWhere((a) => a['kind'] == 'photo')['id'],
        );
        expect(c.startedGarmentIds, [
          c.assets.singleWhere((a) => a['kind'] == 'garment')['id'],
        ]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
  testWidgets('uploading a photo preserves clothes already selected by tap', (
    tester,
  ) async {
    final c = FakeCloset()..assets = [asset('garment', 'garment')];
    await show(
      tester,
      c,
      picker: () async =>
          PlatformFile(name: 'Photo.jpg', size: 3, bytes: Uint8List(3)),
    );
    await tester.tap(find.text('Ivory blazer').first);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('closet-upload-photo')));
    await tester.tap(find.byKey(const Key('closet-upload-photo')));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('closet-try-on'));
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump();
    expect(c.startedGarmentIds, ['garment']);
    expect(c.starts, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('declining AI consent never starts generation', (tester) async {
    final c = FakeCloset()
      ..assets = [asset('photo', 'photo'), asset('garment', 'garment')];
    await show(tester, c, consent: () async => false);
    await tester.tap(find.text('Ivory blazer').first);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('closet-try-on')));
    await tester.tap(find.byKey(const Key('closet-try-on')));
    await tester.pumpAndSettle();
    expect(c.starts, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'a fifth upload preserves the selected outfit and explains the limit',
    (tester) async {
      final c = FakeCloset()
        ..assets = [
          asset('photo', 'photo'),
          for (var i = 0; i < 4; i++)
            asset('item-$i', 'garment', name: 'Wardrobe item $i'),
        ];
      await show(
        tester,
        c,
        width: 390,
        scale: 1.6,
        picker: () async =>
            PlatformFile(name: 'Fifth item.jpg', size: 3, bytes: Uint8List(3)),
      );
      for (var i = 0; i < 4; i++) {
        await tester.ensureVisible(find.text('Wardrobe item $i'));
        await tester.tap(find.text('Wardrobe item $i'));
        await tester.pump();
      }
      await tester.ensureVisible(find.byKey(const Key('closet-add-clothes')));
      await tester.tap(find.byKey(const Key('closet-add-clothes')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Save item'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Fifth item saved. Four items are already selected; unselect one to include it.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Try on').last);
      await tester.pumpAndSettle();
      expect(find.text('Ready to try on'), findsOneWidget);
      expect(find.text('Try it on · 4 items'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 4; i++) {
        final chipDelete = find.byTooltip(
          'Unselect Wardrobe item $i for try-on',
        );
        await tester.ensureVisible(chipDelete);
        await tester.tap(chipDelete);
        await tester.pumpAndSettle();
      }
      expect(
        find.text('Choose at least one clothing item from My wardrobe.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('closet-try-on')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Choose clothes'));
      await tester.tap(find.text('Choose clothes'));
      await tester.pumpAndSettle();
      expect(find.text('My wardrobe'), findsOneWidget);
      expect(c.starts, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'generation cannot be duplicated and reopening resumes a pending job',
    (tester) async {
      final c = FakeCloset()
        ..assets = [asset('photo', 'photo'), asset('garment', 'garment')];
      await show(tester, c);
      await tester.tap(find.text('Ivory blazer').first);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('closet-try-on')));
      await tester.tap(find.byKey(const Key('closet-try-on')));
      await tester.pump();
      await tester.pump();
      expect(c.starts, 1);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('closet-try-on')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      final reopened = FakeCloset()
        ..assets = c.assets
        ..jobs = c.jobs;
      await show(tester, reopened);
      expect(
        find.text('KORLIX is creating your outfit preview…'),
        findsOneWidget,
      );
      reopened.assets.add(asset('look', 'look'));
      reopened.jobs = [jobData('completed')];
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Download PNG'), findsOneWidget);
      expect(reopened.starts, 0);
      expect(reopened.polls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'failed upload retains retry and completed uploads populate the closet',
    (tester) async {
      final c = FakeCloset()..failUpload = true;
      await show(
        tester,
        c,
        picker: () async =>
            PlatformFile(name: 'photo.jpg', size: 3, bytes: Uint8List(3)),
      );
      await tester.ensureVisible(find.byKey(const Key('closet-upload-photo')));
      await tester.tap(find.byKey(const Key('closet-upload-photo')));
      await tester.pumpAndSettle();
      expect(find.text('Upload interrupted.'), findsOneWidget);
      expect(find.text('Retry upload'), findsOneWidget);
      c.failUpload = false;
      await tester.ensureVisible(find.text('Retry upload'));
      await tester.tap(find.text('Retry upload'));
      await tester.pumpAndSettle();
      expect(c.uploads, 2);
      expect(find.text('My photo'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('account change clears photos and prompts immediately', (
    tester,
  ) async {
    final c = FakeCloset()
      ..assets = [asset('photo', 'photo'), asset('garment', 'garment')];
    await show(tester, c);
    await tester.enterText(
      find.byKey(const Key('closet-style-prompt')),
      'Private occasion',
    );
    c.onAccessDenied!();
    await tester.pumpAndSettle();
    expect(find.text('Your session changed'), findsOneWidget);
    expect(find.text('Ivory blazer'), findsNothing);
    expect(find.text('Private occasion'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('saved looks download and deletion needs confirmation', (
    tester,
  ) async {
    int saves = 0;
    final c = FakeCloset()
      ..assets = [asset('photo', 'photo'), asset('look', 'look')]
      ..jobs = [jobData('completed')];
    await show(
      tester,
      c,
      save: (b, n) async {
        saves++;
        expect(n, 'KORLIX-look.png');
      },
    );
    await tester.ensureVisible(find.text('Download PNG'));
    await tester.tap(find.text('Download PNG'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    await tester.tap(find.text('Saved Looks').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Ivory blazer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(c.removes, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'missing source photo never compares a saved look with another photo',
    (tester) async {
      final c = FakeCloset()
        ..assets = [asset('new-photo', 'photo'), asset('look', 'look')]
        ..jobs = [jobData('completed')];
      await show(tester, c);
      expect(find.text('Before'), findsNothing);
      expect(find.text('Download PNG'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('incomplete person photos remain visible for cleanup', (
    tester,
  ) async {
    final pending = asset('pending', 'photo')..['state'] = 'uploading';
    final c = FakeCloset()..assets = [pending];
    await show(tester, c);
    expect(find.text('My photo · uploading'), findsOneWidget);
    expect(find.byTooltip('Remove My photo'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('closet-try-on')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
