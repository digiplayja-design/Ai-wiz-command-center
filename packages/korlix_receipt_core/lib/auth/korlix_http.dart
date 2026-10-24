import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as transport;

export 'package:http/http.dart'
    hide get, post, put, patch, delete, head, read, readBytes;

/// Main-engine bootstrap installs the session-aware transport once. The factory
/// is isolate-local and deliberately independent of the current Dart zone, so
/// Flutter callbacks and independently constructed feature clients use it too.
/// Tests and engines that do not configure it retain the standard HTTP client.
transport.Client Function() _clientFactory = transport.Client.new;

void configureClientFactory(transport.Client Function()? factory) {
  _clientFactory = factory ?? transport.Client.new;
}

/// The caller owns the returned client and must close it when finished.
transport.Client createClient() => _clientFactory();

Future<T> _withClient<T>(Future<T> Function(transport.Client client) action) async {
  final client = createClient();
  try {
    return await action(client);
  } finally {
    client.close();
  }
}

Future<transport.Response> get(Uri url, {Map<String, String>? headers}) =>
    _withClient((client) => client.get(url, headers: headers));

Future<transport.Response> head(Uri url, {Map<String, String>? headers}) =>
    _withClient((client) => client.head(url, headers: headers));

Future<transport.Response> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _withClient(
  (client) => client.post(url, headers: headers, body: body, encoding: encoding),
);

Future<transport.Response> put(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _withClient(
  (client) => client.put(url, headers: headers, body: body, encoding: encoding),
);

Future<transport.Response> patch(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _withClient(
  (client) => client.patch(url, headers: headers, body: body, encoding: encoding),
);

Future<transport.Response> delete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _withClient(
  (client) => client.delete(url, headers: headers, body: body, encoding: encoding),
);

Future<String> read(Uri url, {Map<String, String>? headers}) =>
    _withClient((client) => client.read(url, headers: headers));

Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) =>
    _withClient((client) => client.readBytes(url, headers: headers));

/// MultipartRequest.send() constructs a package:http client internally. Route
/// explicitly through the configured factory instead, keeping its client alive
/// until the caller finishes or cancels the streamed response.
Future<transport.StreamedResponse> sendMultipart(
  transport.MultipartRequest request,
) async {
  final client = createClient();
  var closed = false;
  void closeClient() {
    if (closed) {
      return;
    }
    closed = true;
    client.close();
  }

  try {
    final response = await client.send(request);
    StreamSubscription<List<int>>? source;
    late final StreamController<List<int>> stream;
    stream = StreamController<List<int>>(
      onListen: () {
        try {
          source = response.stream.listen(
            stream.add,
            onError: (Object error, StackTrace stack) {
              closeClient();
              stream.addError(error, stack);
              unawaited(stream.close());
            },
            onDone: () {
              closeClient();
              unawaited(stream.close());
            },
            cancelOnError: true,
          );
        } catch (error, stack) {
          closeClient();
          stream.addError(error, stack);
          unawaited(stream.close());
        }
      },
      onPause: () => source?.pause(),
      onResume: () => source?.resume(),
      onCancel: () async {
        try {
          await source?.cancel();
        } finally {
          closeClient();
        }
      },
    );
    return transport.StreamedResponse(
      stream.stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  } catch (_) {
    closeClient();
    rethrow;
  }
}
