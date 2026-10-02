import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/improve_picture/picture_studio_client.dart';
import 'package:ai_wiz_command_center/improve_picture/picture_studio_screen.dart';

Future<Uint8List> png(Color color) async => base64Decode(
  color == Colors.blue
      ? 'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAAE0lEQVQYlWNQnPb5Pz7MMDIUAABwQapBFKvYYAAAAABJRU5ErkJggg=='
      : 'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAAEklEQVQYlWPwWR/wHx9mGBkKAFgtkoF0aEUHAAAAAElFTkSuQmCC',
);

Future<PlatformFile> photo() async {
  final bytes = await png(Colors.blue);
  return PlatformFile(name: 'source.png', size: bytes.length, bytes: bytes);
}

void main() {
  testWidgets(
    'client sends authenticated multipart options and retains a valid PNG',
    (tester) async {
      final file = await photo();
      final client = PictureStudioClient(
        backendBaseUrl: 'https://example.test/',
        headersBuilder: () => {
          'Authorization': 'Bearer offline',
          'Content-Type': 'application/json',
        },
        client: MockClient((request) async {
          expect(request.url.path, '/api/image/improve');
          expect(request.headers['Authorization'], 'Bearer offline');
          expect(
            request.headers['content-type'],
            startsWith('multipart/form-data;'),
          );
          final body = utf8.decode(request.bodyBytes, allowMalformed: true);
          expect(body, contains('name="preset"\r\n\r\nrestore'));
          expect(body, contains('name="imageSize"\r\n\r\n1536x2304'));
          expect(body, contains('name="preserveIdentity"\r\n\r\ntrue'));
          expect(body, contains('filename="source.png"'));
          return http.Response(
            jsonEncode({
              'imageDataUrl':
                  'data:image/png;base64,${base64Encode(file.bytes!)}',
              'imageQuality': 'max',
              'imageSize': '8x8',
              'editSummary': 'Repair fading.',
            }),
            200,
          );
        }),
      );
      final result = await client.improve(
        file,
        const PictureEditOptions(preset: 'restore', size: '1536x2304'),
      );
      expect(result.bytes, file.bytes);
      expect(result.quality, 'max');
      expect(result.summary, 'Repair fading.');
      client.dispose();
    },
  );

  testWidgets(
    'invalid files and failed service responses never become successful edits',
    (tester) async {
      final file = await photo();
      expect(
        pictureFileError(
          PlatformFile(name: 'a.pdf', size: 1, bytes: Uint8List(1)),
        ),
        contains('JPG'),
      );
      expect(pictureFileError(PlatformFile(name: 'a.png', size: 1)), isNotNull);
      for (final response in [
        http.Response('{"error":"Upgrade required"}', 403),
        http.Response('{"error":"Expired"}', 401),
        http.Response('not json', 500),
        http.Response(
          '{"imageDataUrl":"data:image/png;base64,bm90LXBpY3R1cmU="}',
          200,
        ),
      ]) {
        final client = PictureStudioClient(
          backendBaseUrl: 'https://example.test',
          headersBuilder: () => {},
          client: MockClient((_) async => response),
        );
        await expectLater(
          client.improve(file, const PictureEditOptions()),
          throwsException,
        );
        client.dispose();
      }
    },
  );

  Future<void> screen(
    WidgetTester tester, {
    PlatformFile? file,
    required PictureEditCallback edit,
    Future<bool> Function()? consent,
    Future<void> Function(Uint8List)? save,
    Size viewport = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: PictureStudioScreen(
          initialFile: file,
          onImprove: edit,
          ensureConsent: consent ?? () async => true,
          onOpenTemplates: () {},
          savePicture: save,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'phone workspace has treatments and a disabled submit until a photo is chosen',
    (tester) async {
      await screen(
        tester,
        edit: (_, _) async => throw StateError('Must not generate'),
      );
      expect(find.text('Choose photo'), findsOneWidget);
      expect(find.text('Restore a photo'), findsOneWidget);
      expect(find.text('Remove background'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('improve-picture-submit')),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit treatment and instructions reach the editor, with duplicate submit blocked',
    (tester) async {
      final pending = Completer<PictureEditResult>();
      final file = await photo();
      var calls = 0;
      PictureEditOptions? options;
      await screen(
        tester,
        file: file,
        edit: (_, value) {
          calls++;
          options = value;
          return pending.future;
        },
      );
      await tester.ensureVisible(find.text('Restore a photo'));
      await tester.tap(find.text('Restore a photo'));
      await tester.enterText(
        find.byType(TextField),
        'Keep the original hairline.',
      );
      final submit = find.byKey(const Key('improve-picture-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(calls, 1);
      expect(options!.preset, 'restore');
      expect(options!.preserveIdentity, isTrue);
      expect(options!.prompt, 'Keep the original hairline.');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(
        find.text('Studying your photo and creating your edit…'),
        findsOneWidget,
      );
      pending.complete(
        PictureEditResult(
          bytes: await png(Colors.green),
          quality: 'max',
          size: '8x8',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save PNG'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('consent denial never uploads and the draft remains available', (
    tester,
  ) async {
    var calls = 0;
    await screen(
      tester,
      file: await photo(),
      consent: () async => false,
      edit: (_, _) async {
        calls++;
        throw StateError('Must not upload');
      },
    );
    await tester.enterText(find.byType(TextField), 'Keep the original color.');
    final submit = find.byKey(const Key('improve-picture-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep the original color.',
    );
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  });

  testWidgets(
    'before/after, saving, refinement and return to original use the correct bytes',
    (tester) async {
      final file = await photo();
      final edited = await png(Colors.green);
      Uint8List? saved;
      final uploads = <Uint8List>[];
      await screen(
        tester,
        file: file,
        save: (bytes) async {
          saved = bytes;
        },
        edit: (source, _) async {
          uploads.add(source.bytes!);
          return PictureEditResult(bytes: edited, quality: 'max', size: '8x8');
        },
      );
      final submit = find.byKey(const Key('improve-picture-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Before'));
      await tester.tap(find.text('Before'));
      await tester.pump();
      Image image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).imageProvider, isA<MemoryImage>());
      expect(
        ((image.image as ResizeImage).imageProvider as MemoryImage).bytes,
        file.bytes,
      );
      await tester.tap(find.text('After'));
      await tester.pump();
      image = tester.widget<Image>(find.byType(Image));
      expect(
        ((image.image as ResizeImage).imageProvider as MemoryImage).bytes,
        edited,
      );
      await tester.ensureVisible(find.text('Save PNG'));
      await tester.tap(find.text('Save PNG'));
      await tester.pumpAndSettle();
      expect(saved, edited);
      await tester.ensureVisible(find.text('Refine this image'));
      await tester.tap(find.text('Refine this image'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Warm up the background.');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(uploads.last, edited);
      await tester.ensureVisible(find.text('Start from original'));
      await tester.tap(find.text('Start from original'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(uploads.last, file.bytes);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an editor failure keeps the photo and instructions for retry', (
    tester,
  ) async {
    await screen(
      tester,
      file: await photo(),
      edit: (_, _) async => throw Exception('Please try again.'),
    );
    await tester.enterText(find.byType(TextField), 'Keep the logo.');
    final submit = find.byKey(const Key('improve-picture-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Please try again.'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep the logo.',
    );
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  });
  Uint8List previewBytes(WidgetTester tester, Key key) {
    final image = tester.widget<Image>(find.byKey(key));
    return ((image.image as ResizeImage).imageProvider as MemoryImage).bytes;
  }

  testWidgets(
    'guided looks and light reach the edit while suggestions preserve the draft',
    (tester) async {
      PictureEditOptions? options;
      await screen(
        tester,
        file: await photo(),
        edit: (_, value) async {
          options = value;
          return PictureEditResult(bytes: await png(Colors.green));
        },
      );
      await tester.enterText(find.byType(TextField), 'Keep the red jacket.');
      await tester.ensureVisible(find.text('Natural skin'));
      await tester.tap(find.text('Natural skin'));
      await tester.tap(find.text('Natural skin'));
      final draft = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text;
      expect(
        draft,
        'Keep the red jacket.\nKeep natural skin texture; avoid an airbrushed look.',
      );
      await tester.ensureVisible(
        find.byKey(const Key('picture-color-lighting')),
      );
      await tester.tap(find.text('Color & lighting'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('picture-look-warm')));
      await tester.tap(find.byKey(const Key('picture-look-warm')));
      await tester.ensureVisible(find.text('Keep original lighting'));
      await tester.tap(find.text('Keep original lighting'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Golden hour').last);
      await tester.pumpAndSettle();
      final submit = find.byKey(const Key('improve-picture-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(options!.look, 'warm');
      expect(options!.lighting, 'golden');
      expect(options!.prompt, draft);
      expect(options!.preserveIdentity, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'each version keeps its source for comparison and earlier versions remain saveable',
    (tester) async {
      final original = await photo();
      final first = await png(Colors.green);
      final second = await png(Colors.blue);
      var count = 0;
      Uint8List? saved;
      await screen(
        tester,
        file: original,
        save: (bytes) async => saved = bytes,
        edit: (source, _) async {
          if (count == 1) expect(source.bytes, first);
          return PictureEditResult(bytes: count++ == 0 ? first : second);
        },
      );
      final submit = find.byKey(const Key('improve-picture-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Refine this image'));
      await tester.tap(find.text('Refine this image'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('picture-version-1')), findsOneWidget);
      expect(find.text('Editing: Version 1'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'Make the background softer.',
      );
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Side by side'));
      await tester.tap(find.text('Side by side'));
      await tester.pumpAndSettle();
      expect(previewBytes(tester, const Key('picture-before-image')), first);
      expect(previewBytes(tester, const Key('picture-after-image')), second);
      await tester.tap(find.text('View original'));
      await tester.pump();
      expect(
        previewBytes(tester, const Key('picture-preview-image')),
        original.bytes,
      );
      await tester.ensureVisible(find.byKey(const Key('picture-version-1')));
      await tester.tap(find.byKey(const Key('picture-version-1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Before'));
      await tester.tap(find.text('Before'));
      await tester.pump();
      expect(
        previewBytes(tester, const Key('picture-preview-image')),
        original.bytes,
      );
      await tester.ensureVisible(find.text('Save PNG'));
      await tester.tap(find.text('Save PNG'));
      await tester.pumpAndSettle();
      expect(saved, first);
      expect(find.byKey(const Key('picture-version-2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history retains at most six versions and a failed edit keeps the last result',
    (tester) async {
      var calls = 0;
      final bytes = await png(Colors.green);
      await screen(
        tester,
        file: await photo(),
        edit: (_, _) async {
          calls++;
          if (calls == 8) throw Exception('Temporary problem.');
          return PictureEditResult(bytes: bytes);
        },
      );
      final submit = find.byKey(const Key('improve-picture-submit'));
      for (var i = 0; i < 7; i++) {
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('picture-version-1')), findsNothing);
      expect(find.byKey(const Key('picture-version-2')), findsOneWidget);
      expect(find.byKey(const Key('picture-version-7')), findsOneWidget);
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Temporary problem.'), findsOneWidget);
      expect(find.byKey(const Key('picture-version-7')), findsOneWidget);
      expect(find.text('Save PNG'), findsOneWidget);
      expect(previewBytes(tester, const Key('picture-preview-image')), bytes);
      expect(tester.takeException(), isNull);
    },
  );

  for (final viewport in [const Size(390, 844), const Size(1200, 900)]) {
    testWidgets(
      'workspace supports large text at ${viewport.width.toInt()}px without overflow',
      (tester) async {
        await screen(
          tester,
          viewport: viewport,
          textScale: 2,
          edit: (_, _) async => throw StateError('No photo'),
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Color & lighting'));
        await tester.tap(find.text('Color & lighting'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Finish & output shape'));
        await tester.tap(find.text('Finish & output shape'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('improve-picture-submit')),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
