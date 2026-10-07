import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/image_to_video/image_to_video_media.dart';

void main() {
  const backend = 'https://chee-chai-chee-backend.onrender.com';
  const auth = {
    'Authorization': 'Bearer account-token',
    'X-Korlix-Device-Id': 'device',
    'Content-Type': 'application/json',
  };

  test(
    'protected I2V preview and download use authenticated headers, without URL tokens',
    () async {
      final media = ImageToVideoMedia(
        url: '$backend/api/video/image-to-video/content/job-123',
        backendBaseUrl: backend,
      );
      expect(media.protected, isTrue);
      final source = await media.preparePreview(() async => auth);
      expect(source.headers['Authorization'], 'Bearer account-token');
      expect(source.headers.containsKey('Content-Type'), isFalse);
      expect(source.url, '$backend/api/video/image-to-video/content/job-123');
      expect(media.uri.hasQuery, isFalse);
      expect(
        (await media.headers(() async => auth))['Authorization'],
        'Bearer account-token',
      );
    },
  );

  test(
    'Kling signed video URLs never call the private header builder',
    () async {
      var headerReads = 0;
      for (final url in [
        'https://cdn.klingai.com/video.mp4?signature=provider-token',
        'https://chee-chai-chee-backend.onrender.com.attacker.example/video.mp4',
        'https://chee-chai-chee-backend.onrender.com:8443/video.mp4',
      ]) {
        final media = ImageToVideoMedia(url: url, backendBaseUrl: backend);
        Future<Map<String, String>> headers() async {
          headerReads++;
          return auth;
        }

        final source = await media.preparePreview(headers);
        expect(source.url, url);
        expect(source.headers, isEmpty);
        expect(await media.headers(headers), isEmpty);
      }
      expect(headerReads, 0);
    },
  );

  test(
    'unsafe schemes, credentials, and unrelated protected routes are rejected',
    () {
      for (final url in [
        'http://cdn.klingai.com/video.mp4',
        'javascript:alert(1)',
        '$backend/api/auth/refresh',
        '$backend/api/video/image-to-video/content/../other',
        'https://name:password@cdn.klingai.com/video.mp4',
      ]) {
        expect(
          () => ImageToVideoMedia(url: url, backendBaseUrl: backend),
          throwsFormatException,
        );
      }
    },
  );

  test('private video fails closed without an authenticated session', () async {
    final media = ImageToVideoMedia(
      url: '$backend/api/video/image-to-video/content/job',
      backendBaseUrl: backend,
    );
    await expectLater(media.preparePreview(() async => {}), throwsStateError);
    await expectLater(
      media.headers(() async => {'Authorization': 'Bearer '}),
      throwsStateError,
    );
  });
}
