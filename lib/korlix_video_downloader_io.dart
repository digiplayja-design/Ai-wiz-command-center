import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'sharing/korlix_share.dart';

/// Downloads one video with a total deadline and bounded response memory.
/// The supplied client, when present, belongs to this operation and is closed.
Future<Uint8List> fetchKorlixVideoBytes({
  required String url,
  required Map<String, String> headers,
  http.Client? client,
  int maxBytes = 64 * 1024 * 1024,
  Duration timeout = const Duration(seconds: 90),
}) async {
  if (maxBytes <= 0 || timeout <= Duration.zero) {
    throw ArgumentError('Video download limits must be positive.');
  }
  final transport = client ?? http.Client();
  final aborted = Completer<void>();
  final result = Completer<Uint8List>();
  final bytes = BytesBuilder(copy: false);
  StreamSubscription<List<int>>? subscription;
  var finished = false;
  final timer = Timer(timeout, () {
    if (!result.isCompleted) {
      result.completeError(
        TimeoutException('Video download timed out. Please try again.'),
      );
    }
  });
  void fail(String message) {
    if (!result.isCompleted) result.completeError(Exception(message));
  }

  Future<void> receive() async {
    try {
      final request = http.AbortableRequest(
        'GET',
        Uri.parse(url),
        abortTrigger: aborted.future,
      )..headers.addAll(headers);
      final response = await transport.send(request);
      if (finished) {
        await response.stream.listen((_) {}).cancel();
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        fail('Video download failed. Status code: ${response.statusCode}');
        return;
      }
      if ((response.contentLength ?? 0) > maxBytes) {
        fail(
          'This video is too large to share in the app. Try a shorter video.',
        );
        return;
      }
      subscription = response.stream.listen(
        (chunk) {
          if (result.isCompleted) return;
          if (bytes.length + chunk.length > maxBytes) {
            fail(
              'This video is too large to share in the app. Try a shorter video.',
            );
            return;
          }
          bytes.add(chunk);
        },
        onError: (Object _) =>
            fail('Video download was interrupted. Please try again.'),
        onDone: () {
          if (result.isCompleted) return;
          if (bytes.isEmpty) {
            fail('The downloaded video was empty. Please try again.');
          } else {
            result.complete(bytes.takeBytes());
          }
        },
      );
    } catch (_) {
      fail('Video download was interrupted. Please try again.');
    }
  }

  unawaited(receive());
  try {
    return await result.future;
  } finally {
    finished = true;
    timer.cancel();
    aborted.complete();
    final cancelled = subscription?.cancel();
    transport.close();
    await cancelled;
  }
}

Future<void> downloadKorlixVideo({
  required String url,
  required Map<String, String> headers,
  required String filename,
}) async {
  final bytes = await fetchKorlixVideoBytes(url: url, headers: headers);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, name: filename, mimeType: 'video/mp4')],
      fileNameOverrides: [filename],
      text: 'Save or share your Korlix AI video.',
      subject: 'Korlix AI video',
      sharePositionOrigin: korlixShareOrigin(),
    ),
  );
}
