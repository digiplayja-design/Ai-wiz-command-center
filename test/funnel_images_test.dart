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
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_images.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_screen.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_templates.dart';
import 'funnel_studio_test.dart' show fixture;

const imageId = '00000000-0000-4000-8000-000000000005';
const secondId = '00000000-0000-4000-8000-000000000006';
final asset = {
  'id': imageId,
  'label': 'KORLIX logo.png',
  'width': 300,
  'height': 180,
  'bytes': 1000,
  'page_count': 0,
};
http.Response reply(Map data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List png;
  setUpAll(() async {
    png = await File('assets/branding/korlix_full_logo.png').readAsBytes();
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      for (final e in {
        'Roboto': 'Roboto-Regular.ttf',
        'MaterialIcons': 'MaterialIcons-Regular.otf',
      }.entries) {
        await (FontLoader(e.key)..addFont(
              File(
                '$root/bin/cache/artifacts/material_fonts/${e.value}',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    }
  });
  Future<void> tap(WidgetTester t, String label) async {
    await t.ensureVisible(find.text(label).last);
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester t,
    Future<http.Response> Function(http.Request) handler, {
    double width = 1440,
    double scale = 1,
    Future<FunnelPickedImage?> Function()? picker,
  }) async {
    await t.binding.setSurfaceSize(Size(width, 1100));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('k151-screenshot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: FunnelScreen(
            client: FunnelClient(
              backendBaseUrl: 'https://example.com',
              headersBuilder: () => {'Authorization': 'session'},
              client: MockClient(handler),
            ),
            imagePicker:
                picker ?? () async => FunnelPickedImage('KORLIX logo.png', png),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Open studio');
  }

  test(
    'Generated copy and duplication retain image references and descriptions',
    () {
      final current = {
        ...funnelTemplate('product'),
        'logo': {'id': imageId, 'alt': 'Our logo'},
        'hero_image': {'id': secondId, 'alt': 'Our team'},
      };
      final next = generatedCopy(current, funnelTemplate('event'));
      expect(next['logo'], current['logo']);
      expect(next['hero_image'], current['hero_image']);
      final clone = copyFunnel(current);
      clone['logo']['alt'] = 'Changed';
      expect(current['logo']['alt'], 'Our logo');
    },
  );
  testWidgets(
    'Upload selects an image as an unsaved edit; only Save draft attaches it and no publication occurs',
    (t) async {
      var f = fixture();
      final calls = <http.Request>[];
      await mount(t, (r) async {
        calls.add(r);
        if (r.url.path.endsWith('/images') && r.method == 'GET') {
          return reply({'images': [], 'used_bytes': 0});
        }
        if (r.url.path.endsWith('/images') && r.method == 'POST') {
          expect(r.headers['content-type'], contains('multipart/form-data'));
          expect(r.headers['Authorization'], 'session');
          return reply({'image': asset}, 201);
        }
        if (r.url.path.endsWith('/images/$imageId')) {
          return reply({'content': base64Encode(png)});
        }
        if (r.method == 'PUT') {
          final b = jsonDecode(r.body);
          expect(b['document']['logo']['id'], imageId);
          expect(b['document']['logo']['alt'], 'Our circuit-face emblem');
          f = {...f, 'draft': b['document'], 'version': 2};
          return reply({'funnel': f});
        }
        return reply({
          'funnels': [f],
        });
      });
      await tap(t, 'Choose logo');
      await tap(t, 'Upload image');
      expect(find.text('Remove logo'), findsOneWidget);
      expect(calls.where((r) => r.method == 'PUT'), isEmpty);
      // TextFormField exposes decoration through its descendant TextField.
      final editable = find.widgetWithText(TextFormField, 'KORLIX logo');
      await t.ensureVisible(editable);
      await t.enterText(editable, 'Our circuit-face emblem');
      await t.pumpAndSettle();
      await tap(t, 'Save draft');
      expect(calls.where((r) => r.method == 'PUT'), hasLength(1));
      expect(calls.where((r) => r.url.path.endsWith('/publish')), isEmpty);
    },
  );
  testWidgets(
    'Reusing and removing an image change only the local draft; current selections cannot be deleted',
    (t) async {
      final f = fixture();
      final calls = <http.Request>[];
      await mount(t, (r) async {
        calls.add(r);
        if (r.url.path.endsWith('/images')) {
          return reply({
            'images': [asset],
            'used_bytes': 1000,
          });
        }
        if (r.url.path.endsWith('/images/$imageId')) {
          return reply({'content': base64Encode(png)});
        }
        return reply({
          'funnels': [f],
        });
      });
      await tap(t, 'Choose main image');
      await tap(t, 'Use image');
      await tap(t, 'Choose logo');
      expect(find.text('Delete'), findsNothing);
      await tap(t, 'Close');
      await tap(t, 'Remove main image');
      expect(find.text('Remove main image'), findsNothing);
      expect(calls.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  testWidgets(
    'Cancelling the picker and rejecting an oversized file leave the draft unchanged',
    (t) async {
      var picks = 0;
      final calls = <http.Request>[];
      await mount(
        t,
        (r) async {
          calls.add(r);
          return r.url.path.endsWith('/images')
              ? reply({'images': [], 'used_bytes': 0})
              : reply({
                  'funnels': [fixture()],
                });
        },
        picker: () async => ++picks == 1
            ? null
            : FunnelPickedImage('Too big.png', Uint8List(5 * 1024 * 1024 + 1)),
      );
      await tap(t, 'Choose logo');
      await tap(t, 'Upload image');
      expect(find.byType(FunnelImageLibrary), findsOneWidget);
      await tap(t, 'Upload image');
      expect(find.text('Choose an image up to 5 MB.'), findsOneWidget);
      await tap(t, 'Close');
      expect(find.text('Remove logo'), findsNothing);
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
    },
  );
  testWidgets(
    'Pending upload disables repeated uploads and uncertain results offer refresh without claiming success',
    (t) async {
      final pending = Completer<http.Response>();
      var uploads = 0;
      await mount(t, (r) async {
        if (r.url.path.endsWith('/images')) {
          if (r.method == 'POST') {
            uploads++;
            return pending.future;
          }
          return reply({'images': [], 'used_bytes': 0});
        }
        return reply({
          'funnels': [fixture()],
        });
      });
      await tap(t, 'Choose logo');
      await t.tap(find.text('Upload image'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Upload image'),
            )
            .onPressed,
        isNull,
      );
      pending.complete(
        reply({
          'error':
              'Upload receipt was not confirmed. Refresh your image library.',
        }, 503),
      );
      await t.pumpAndSettle();
      expect(uploads, 1);
      expect(find.text('Refresh library'), findsOneWidget);
      expect(find.text('Remove logo'), findsNothing);
    },
  );
  testWidgets(
    'Deletion requires review and a stale in-use conflict preserves the image',
    (t) async {
      var deletes = 0;
      await mount(t, (r) async {
        if (r.method == 'DELETE') {
          deletes++;
          expect(jsonDecode(r.body)['confirmed'], true);
          return reply({'error': 'This image is used by a saved page.'}, 409);
        }
        if (r.url.path.endsWith('/images')) {
          return reply({
            'images': [asset],
            'used_bytes': 1000,
          });
        }
        if (r.url.path.endsWith('/images/$imageId')) {
          return reply({'content': base64Encode(png)});
        }
        return reply({
          'funnels': [fixture()],
        });
      });
      await tap(t, 'Choose logo');
      await tap(t, 'Delete');
      await tap(t, 'Cancel');
      expect(deletes, 0);
      await tap(t, 'Delete');
      await tap(t, 'Delete image');
      expect(deletes, 1);
      expect(find.text('This image is used by a saved page.'), findsOneWidget);
      expect(find.text('Use image'), findsOneWidget);
    },
  );
  testWidgets(
    'Access loss during a thumbnail read clears gallery identities and editor content',
    (t) async {
      await mount(t, (r) async {
        if (r.url.path.endsWith('/images')) {
          return reply({
            'images': [asset],
            'used_bytes': 1000,
          });
        }
        if (r.url.path.endsWith('/images/$imageId')) {
          return reply({'error': 'Enterprise access required.'}, 403);
        }
        return reply({
          'funnels': [fixture()],
        });
      });
      await tap(t, 'Choose logo');
      expect(find.text('KORLIX logo.png'), findsNothing);
      expect(find.text('Use image'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Enterprise access required'), findsOneWidget);
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets('Image library and preview fit ${width.toInt()} pixels', (
      t,
    ) async {
      final f = fixture();
      (f['draft'] as Map)['logo'] = {
        'id': imageId,
        'alt': 'KORLIX circuit-face emblem',
      };
      (f['draft'] as Map)['hero_image'] = {
        'id': imageId,
        'alt': 'KORLIX branding',
      };
      await mount(
        t,
        (r) async {
          if (r.url.path.endsWith('/images')) {
            return reply({
              'images': [
                {...asset, 'page_count': 1},
              ],
              'used_bytes': 1000,
            });
          }
          if (r.url.path.endsWith('/images/$imageId')) {
            return reply({'content': base64Encode(png)});
          }
          return reply({
            'funnels': [f],
          });
        },
        width: width,
        scale: width == 320 ? 1.3 : 1,
      );
      await tap(t, 'Choose main image');
      await t.runAsync(() async {
        for (final widget in t.widgetList<Image>(find.byType(Image))) {
          final stream = widget.image.resolve(ImageConfiguration.empty);
          final loaded = Completer<void>();
          late ImageStreamListener listener;
          listener = ImageStreamListener(
            (info, sync) {
              if (!loaded.isCompleted) loaded.complete();
            },
            onError: (Object error, StackTrace? stack) {
              if (!loaded.isCompleted) loaded.completeError(error, stack);
            },
          );
          stream.addListener(listener);
          try {
            await loaded.future.timeout(const Duration(seconds: 5));
          } finally {
            stream.removeListener(listener);
          }
        }
      });
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final repaint = find.byKey(const ValueKey('k151-screenshot'));
      if (repaint.evaluate().isNotEmpty) {
        await t.runAsync(() async {
          final node = t.renderObject<RenderRepaintBoundary>(repaint);
          final image = await node.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/k151-image-library-${width.toInt()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tap(t, 'Close');
      await tap(t, 'Preview');
      expect(t.takeException(), isNull);
    });
  }
}
