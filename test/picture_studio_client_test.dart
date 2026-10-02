import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_wiz_command_center/improve_picture/picture_studio_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAAE0lEQVQYlWNQnPb5Pz7MMDIUAABwQapBFKvYYAAAAABJRU5ErkJggg==',
);
PlatformFile _photo() =>
    PlatformFile(name: 'holiday.png', size: _png.length, bytes: _png);
http.Response _finished() => http.Response(
  jsonEncode({'imageDataUrl': 'data:image/png;base64,${base64Encode(_png)}'}),
  200,
);
Matcher _message(String text) => throwsA(
  isA<Exception>().having(
    (error) => error.toString(),
    'message',
    contains(text),
  ),
);

void main() {
  test(
    'color and light options are included in authenticated multipart',
    () async {
      final client = PictureStudioClient(
        backendBaseUrl: 'https://fixture.test///',
        headersBuilder: () async => {
          'Authorization': 'Bearer fixture',
          'cOnTeNt-TyPe': 'application/json',
        },
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://fixture.test/api/image/improve',
          );
          expect(request.headers['Authorization'], 'Bearer fixture');
          expect(
            request.headers['content-type'],
            startsWith('multipart/form-data;'),
          );
          final body = utf8.decode(request.bodyBytes, allowMalformed: true);
          expect(body, contains('name="look"\r\n\r\ncinematic'));
          expect(body, contains('name="lighting"\r\n\r\ngolden'));
          expect(body, contains('name="preserveIdentity"\r\n\r\ntrue'));
          expect(body, contains('filename="holiday.png"'));
          expect(body, contains('content-type: image/png'));
          return _finished();
        }),
      );
      addTearDown(client.dispose);
      final result = await client.improve(
        _photo(),
        const PictureEditOptions(look: 'cinematic', lighting: 'golden'),
      );
      expect(result.bytes, _png);
      expect(const PictureEditOptions().fields['look'], 'original');
      expect(const PictureEditOptions().fields['lighting'], 'original');
    },
  );

  test(
    'unreadable, unsupported and oversized uploads never reach auth or HTTP',
    () async {
      var headersRead = 0, sent = 0;
      final client = PictureStudioClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () {
          headersRead++;
          return {};
        },
        client: MockClient((_) async {
          sent++;
          return _finished();
        }),
      );
      addTearDown(client.dispose);
      for (final file in [
        PlatformFile(name: 'empty.png', size: 0, bytes: Uint8List(0)),
        PlatformFile(name: 'unreadable.png', size: 100),
        PlatformFile(name: 'document.pdf', size: _png.length, bytes: _png),
        PlatformFile(
          name: 'large.png',
          // Validate actual bytes even if the picker supplied a smaller size.
          size: 1,
          bytes: Uint8List(15 * 1024 * 1024 + 1),
        ),
      ]) {
        await expectLater(
          client.improve(file, const PictureEditOptions()),
          throwsException,
        );
      }
      expect(headersRead, 0);
      expect(sent, 0);
    },
  );

  test(
    'expired status has a useful message even when the body is HTML',
    () async {
      for (final status in [401, 419, 440]) {
        var sent = 0;
        final client = PictureStudioClient(
          backendBaseUrl: 'https://fixture.test',
          headersBuilder: () => {},
          client: MockClient((_) async {
            sent++;
            return http.Response('<html>Sign in</html>', status);
          }),
        );
        addTearDown(client.dispose);
        await expectLater(
          client.improve(_photo(), const PictureEditOptions()),
          _message('Your session expired'),
        );
        await expectLater(
          client.improve(_photo(), const PictureEditOptions()),
          _message('reopen Picture Studio'),
        );
        expect(sent, 1);
      }
    },
  );

  test(
    'service error JSON and non-JSON responses remain understandable',
    () async {
      for (final entry in <(http.Response, String)>[
        (
          http.Response('{"details":"Upgrade required"}', 403),
          'Upgrade required',
        ),
        (http.Response('upstream unavailable', 503), 'could not be completed'),
        (http.Response('busy', 429), 'Please wait a moment'),
        (
          http.Response(
            '{"details":{"internal":"trace"},"error":"Try later"}',
            502,
          ),
          'Try later',
        ),
      ]) {
        final client = PictureStudioClient(
          backendBaseUrl: 'https://fixture.test',
          headersBuilder: () => {},
          client: MockClient((_) async => entry.$1),
        );
        addTearDown(client.dispose);
        await expectLater(
          client.improve(_photo(), const PictureEditOptions()),
          _message(entry.$2),
        );
      }
    },
  );

  test('malformed success responses never become finished pictures', () async {
    for (final body in [
      'not JSON',
      '[]',
      'null',
      '{}',
      '{"imageDataUrl":"https://fixture.test/picture.png"}',
      '{"imageDataUrl":"data:image/png;base64,!invalid!"}',
      jsonEncode({
        'imageDataUrl':
            'data:image/png;base64,${base64Encode([137, 80, 78, 71, 0, 0, 0, 0])}',
      }),
      jsonEncode({
        'imageDataUrl':
            'data:image/png;base64,${base64Encode([137, 80, 78, 71])}',
      }),
    ]) {
      final client = PictureStudioClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient((_) async => http.Response(body, 200)),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.improve(_photo(), const PictureEditOptions()),
        throwsException,
      );
    }
  });

  test('a session change while resolving headers prevents uploading', () async {
    var current = true, sent = 0;
    final headers = Completer<Map<String, String>>();
    final client = PictureStudioClient(
      backendBaseUrl: 'https://fixture.test',
      headersBuilder: () => headers.future,
      isSessionCurrent: () => current,
      client: MockClient((_) async {
        sent++;
        return _finished();
      }),
    );
    addTearDown(client.dispose);
    final pending = client.improve(_photo(), const PictureEditOptions());
    final expectation = expectLater(pending, _message('Your session changed'));
    current = false;
    headers.complete({'Authorization': 'Bearer another-user'});
    await expectation;
    expect(sent, 0);
    current = true;
    await expectLater(
      client.improve(_photo(), const PictureEditOptions()),
      _message('Your session changed'),
    );
    expect(sent, 0);
  });

  test('a late picture from an old account is discarded', () async {
    var current = true;
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final client = PictureStudioClient(
      backendBaseUrl: 'https://fixture.test',
      headersBuilder: () => {},
      isSessionCurrent: () => current,
      client: MockClient((_) {
        started.complete();
        return response.future;
      }),
    );
    addTearDown(client.dispose);
    final pending = client.improve(_photo(), const PictureEditOptions());
    final expectation = expectLater(pending, _message('Your session changed'));
    await started.future;
    current = false;
    response.complete(_finished());
    await expectation;
  });

  test('session loss takes priority over a late network error', () async {
    var current = true;
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final client = PictureStudioClient(
      backendBaseUrl: 'https://fixture.test',
      headersBuilder: () => {},
      isSessionCurrent: () => current,
      client: MockClient((_) {
        started.complete();
        return response.future;
      }),
    );
    addTearDown(client.dispose);
    final pending = client.improve(_photo(), const PictureEditOptions());
    final expectation = expectLater(pending, _message('Your session changed'));
    await started.future;
    current = false;
    response.completeError(http.ClientException('private transport detail'));
    await expectation;
  });

  test('connection interruption gets an actionable message', () async {
    final client = PictureStudioClient(
      backendBaseUrl: 'https://fixture.test',
      headersBuilder: () => {},
      client: MockClient((_) async => throw http.ClientException('fixture')),
    );
    addTearDown(client.dispose);
    await expectLater(
      client.improve(_photo(), const PictureEditOptions()),
      _message('Check your connection'),
    );
  });

  test(
    'disposing rejects an in-flight result and subsequent requests',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final client = PictureStudioClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient((_) {
          started.complete();
          return response.future;
        }),
      );
      final pending = client.improve(_photo(), const PictureEditOptions());
      final expectation = expectLater(
        pending,
        _message('Reopen Picture Studio'),
      );
      await started.future;
      client.dispose();
      response.complete(_finished());
      await expectation;
      await expectLater(
        client.improve(_photo(), const PictureEditOptions()),
        _message('Reopen Picture Studio'),
      );
      client.dispose();
    },
  );
}
