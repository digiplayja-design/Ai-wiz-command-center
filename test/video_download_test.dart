import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ai_wiz_command_center/korlix_video_downloader_io.dart';

class DownloadClient extends http.BaseClient {
  DownloadClient(this.respond);
  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      respond(request);
  @override
  void close() => closed = true;
}

void main() {
  const url = 'https://example.invalid/video';
  const headers = {'Authorization': 'Bearer test-only'};

  test(
    'streams successful downloads within the cap and preserves authentication',
    () async {
      var aborted = false;
      final client = DownloadClient((request) async {
        expect(request.headers['Authorization'], headers['Authorization']);
        expect(request, isA<http.AbortableRequest>());
        (request as http.AbortableRequest).abortTrigger!.then(
          (_) => aborted = true,
        );
        return http.StreamedResponse(
          Stream.fromIterable([
            [1, 2],
            [3, 4],
          ]),
          200,
        );
      });
      expect(
        await fetchKorlixVideoBytes(
          url: url,
          headers: headers,
          client: client,
          maxBytes: 4,
        ),
        [1, 2, 3, 4],
      );
      expect(client.closed, isTrue);
      expect(aborted, isTrue);
    },
  );

  test(
    'rejects declared oversized responses before consuming the body',
    () async {
      var listened = false;
      final controller = StreamController<List<int>>(
        onListen: () => listened = true,
      );
      final client = DownloadClient(
        (_) async =>
            http.StreamedResponse(controller.stream, 200, contentLength: 5),
      );
      await expectLater(
        fetchKorlixVideoBytes(
          url: url,
          headers: headers,
          client: client,
          maxBytes: 4,
        ),
        throwsA(predicate((e) => '$e'.contains('too large'))),
      );
      expect(listened, isFalse);
      expect(client.closed, isTrue);
      unawaited(controller.close());
    },
  );

  test(
    'actual streamed bytes enforce the cap without trusting Content-Length',
    () async {
      for (final declared in <int?>[null, 1]) {
        var cancelled = false;
        late StreamController<List<int>> controller;
        controller = StreamController<List<int>>(
          onListen: () {
            controller.add([1, 2, 3]);
            controller.add([4, 5]);
          },
          onCancel: () => cancelled = true,
        );
        final client = DownloadClient(
          (_) async => http.StreamedResponse(
            controller.stream,
            200,
            contentLength: declared,
          ),
        );
        await expectLater(
          fetchKorlixVideoBytes(
            url: url,
            headers: headers,
            client: client,
            maxBytes: 4,
          ),
          throwsA(predicate((e) => '$e'.contains('too large'))),
        );
        expect(cancelled, isTrue);
        expect(client.closed, isTrue);
        await controller.close();
      }
    },
  );

  test('deadline covers waiting for headers and aborts the request', () async {
    final abort = Completer<void>();
    final client = DownloadClient((request) {
      (request as http.AbortableRequest).abortTrigger!.then(
        (_) => abort.complete(),
      );
      return Completer<http.StreamedResponse>().future;
    });
    await expectLater(
      fetchKorlixVideoBytes(
        url: url,
        headers: headers,
        client: client,
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await abort.future;
    expect(client.closed, isTrue);
  });

  test(
    'total deadline cancels a body that continues sending small chunks',
    () async {
      var cancelled = false;
      Timer? trickle;
      late StreamController<List<int>> controller;
      controller = StreamController<List<int>>(
        onListen: () => trickle = Timer.periodic(
          const Duration(milliseconds: 5),
          (_) => controller.add([1]),
        ),
        onCancel: () {
          cancelled = true;
          trickle?.cancel();
        },
      );
      final client = DownloadClient(
        (_) async => http.StreamedResponse(controller.stream, 200),
      );
      await expectLater(
        fetchKorlixVideoBytes(
          url: url,
          headers: headers,
          client: client,
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(cancelled, isTrue);
      expect(client.closed, isTrue);
      await controller.close();
    },
  );

  test('failed and empty responses never produce a shareable file', () async {
    for (final status in [200, 403, 500]) {
      final client = DownloadClient(
        (_) async => http.StreamedResponse(const Stream.empty(), status),
      );
      await expectLater(
        fetchKorlixVideoBytes(url: url, headers: headers, client: client),
        throwsException,
      );
      expect(client.closed, isTrue);
    }
  });
}
