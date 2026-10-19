import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ai_wiz_command_center/support/korlix_ai_report_client.dart';
import 'package:ai_wiz_command_center/support/korlix_report_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<String> fixtureImage(int width, int height, {bool noise = false}) async {
  final pixels = Uint8List(width * height * 4);
  final random = Random(42);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = noise ? random.nextInt(256) : 90;
    pixels[i + 1] = noise ? random.nextInt(256) : 130;
    pixels[i + 2] = noise ? random.nextInt(256) : 200;
    pixels[i + 3] = 255;
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  final image = await done.future;
  try {
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return 'data:image/png;base64,${base64Encode(png.buffer.asUint8List())}';
  } finally {
    image.dispose();
  }
}

Future<String> report(
  http.Client client, {
  String? image,
  String details = '',
  bool Function()? isCurrent,
}) => submitKorlixAiReport(
  endpoint: Uri.https('api.example.invalid', '/api/report-output'),
  headers: {'Authorization': 'Bearer fixture'},
  reason: 'Unsafe or harmful',
  details: details,
  prompt: 'Specific image prompt',
  outputSummary: 'Image generated.',
  contentId: 'specific image',
  contentType: 'image',
  imageDataUrl: image,
  client: client,
  isCurrent: isCurrent,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local image report includes bounded decodable evidence and original context',
    () async {
      final original = await fixtureImage(256, 256, noise: true);
      expect(original.length, greaterThan(32 * 1024));
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.headers['Authorization'], 'Bearer fixture');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['prompt'], 'Specific image prompt');
        expect(body['contentId'], 'specific image');
        final bytes = base64Decode(
          (body['imageDataUrl'] as String).split(',').last,
        );
        expect(bytes.length, lessThanOrEqualTo(maxKorlixReportImageBytes));
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 256);
        expect(frame.image.height, 256);
        frame.image.dispose();
        codec.dispose();
        return http.Response(
          '{"ok":true,"reportId":"korlix_report_20000000-0000-4000-8000-000000000001"}',
          200,
        );
      });
      await report(client, image: original);
      expect(requests, 1);
    },
  );

  test(
    'detailed images are downsampled until the upload fits the image budget',
    () async {
      final original = await fixtureImage(1280, 720, noise: true);
      expect(
        base64Decode(original.split(',').last).length,
        greaterThan(maxKorlixReportImageBytes),
      );
      final preview = await prepareKorlixReportImage(imageDataUrl: original);
      final bytes = base64Decode(preview.split(',').last);
      expect(bytes.length, lessThanOrEqualTo(maxKorlixReportImageBytes));
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, lessThan(1280));
      expect(frame.image.width / frame.image.height, closeTo(1280 / 720, 0.01));
      frame.image.dispose();
      codec.dispose();
    },
  );

  test('large images are reduced while preserving aspect ratio', () async {
    final preview = await prepareKorlixReportImage(
      imageDataUrl: await fixtureImage(2000, 1000),
    );
    final bytes = base64Decode(preview.split(',').last);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1280);
    expect(frame.image.height, 640);
    expect(bytes.length, lessThanOrEqualTo(maxKorlixReportImageBytes));
    frame.image.dispose();
    codec.dispose();
  });

  test(
    'missing/invalid image and excessive metadata send no partial report',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      for (final image in [null, 'data:image/png;base64,YmFk']) {
        await expectLater(
          report(client, image: image),
          throwsA(
            isA<KorlixAiReportException>().having(
              (e) => e.message,
              'message',
              contains('No report was sent'),
            ),
          ),
        );
      }
      await expectLater(
        report(client, image: await fixtureImage(8, 8), details: 'x' * 40000),
        throwsA(isA<KorlixAiReportException>()),
      );
      expect(requests, 0);
    },
  );

  test(
    'account changed during image preparation prevents transmission',
    () async {
      var checks = 0;
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      await expectLater(
        report(
          client,
          image: await fixtureImage(8, 8),
          isCurrent: () => ++checks == 1,
        ),
        throwsA(
          isA<KorlixAiReportException>().having(
            (e) => e.message,
            'message',
            contains('account changed'),
          ),
        ),
      );
      expect(checks, 2);
      expect(requests, 0);
    },
  );

  test(
    'remote image download sends no account headers; missing/redirected content fails',
    () async {
      final original = await fixtureImage(8, 8);
      final bytes = base64Decode(original.split(',').last);
      final client = MockClient((request) async {
        expect(request.headers.containsKey('Authorization'), false);
        expect(request.followRedirects, false);
        return http.Response.bytes(bytes, 200);
      });
      expect(
        await prepareKorlixReportImage(
          imageUrl: 'https://images.example.invalid/image.png',
          client: client,
        ),
        startsWith('data:image/png;base64,'),
      );
      for (final status in [302, 404]) {
        await expectLater(
          prepareKorlixReportImage(
            imageUrl: 'https://images.example.invalid/missing.png',
            client: MockClient((_) async => http.Response('', status)),
          ),
          throwsA(isA<KorlixReportImageException>()),
        );
      }
    },
  );
}
