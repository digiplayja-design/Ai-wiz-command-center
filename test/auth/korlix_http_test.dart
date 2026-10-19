import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/auth/korlix_http.dart' as http;
import 'package:ai_wiz_command_center/auth/korlix_session_refresh.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as raw_http;

class _Client extends raw_http.BaseClient {
  _Client(this.respond);
  final FutureOr<raw_http.StreamedResponse> Function(raw_http.BaseRequest) respond;
  int closes = 0;

  @override
  Future<raw_http.StreamedResponse> send(raw_http.BaseRequest request) async =>
      respond(request);

  @override
  void close() {
    closes++;
  }
}

String _token(DateTime expires) {
  final claims = base64Url.encode(utf8.encode(jsonEncode({
    'iss': 'https://identity.test/auth/v1',
    'sub': 'member-a',
    'session_id': 'session-a',
    'exp': expires.millisecondsSinceEpoch ~/ 1000,
  }))).replaceAll('=', '');
  return 'header.$claims.signature';
}

void main() {
  final uri = Uri.parse('https://korlix.test/api/social/inbox');
  tearDown(() => http.configureClientFactory(null));

  test('configured factory is used outside its setup zone', () async {
    late _Client client;
    runZoned(() {
      http.configureClientFactory(() => client = _Client((request) {
        expect(request.url, uri);
        return raw_http.StreamedResponse(Stream.value(utf8.encode('ready')), 200);
      }));
    });
    expect((await http.get(uri)).body, 'ready');
    expect(client.closes, 1);
  });

  test('verbs and reads preserve request arguments and close owned clients', () async {
    final methods = <String>[];
    final clients = <_Client>[];
    http.configureClientFactory(() {
      final client = _Client((request) async {
        methods.add(request.method);
        expect(request.headers['x-feature'], 'social');
        if (['POST', 'PUT', 'PATCH', 'DELETE'].contains(request.method)) {
          expect(await request.finalize().bytesToString(), 'hello');
        }
        return raw_http.StreamedResponse(Stream.value(utf8.encode('ok')), 200);
      });
      clients.add(client);
      return client;
    });
    const headers = {'x-feature': 'social'};
    await http.get(uri, headers: headers);
    await http.head(uri, headers: headers);
    await http.post(uri, headers: headers, body: 'hello', encoding: utf8);
    await http.put(uri, headers: headers, body: 'hello', encoding: utf8);
    await http.patch(uri, headers: headers, body: 'hello', encoding: utf8);
    await http.delete(uri, headers: headers, body: 'hello', encoding: utf8);
    expect(await http.read(uri, headers: headers), 'ok');
    expect(await http.readBytes(uri, headers: headers), utf8.encode('ok'));
    expect(methods, ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'GET', 'GET']);
    expect(clients.map((client) => client.closes), everyElement(1));
  });

  test('failed top-level request closes its owned client', () async {
    final client = _Client((_) => throw StateError('connection failed'));
    http.configureClientFactory(() => client);
    await expectLater(http.get(uri), throwsStateError);
    expect(client.closes, 1);
  });

  test('explicit clients remain owned by the feature', () async {
    final client = _Client((_) => raw_http.StreamedResponse(Stream.value([1]), 200));
    http.configureClientFactory(() => client);
    final owned = http.createClient();
    await owned.get(uri);
    expect(client.closes, 0);
    owned.close();
    expect(client.closes, 1);
  });

  test('multipart preserves response metadata and closes after body completion', () async {
    final source = StreamController<List<int>>();
    final request = http.MultipartRequest('POST', uri)..fields['name'] = 'photo';
    final client = _Client((sent) {
      expect(identical(sent, request), isTrue);
      return raw_http.StreamedResponse(source.stream, 202,
          contentLength: 3, request: sent, headers: {'x-upload': 'accepted'},
          isRedirect: false, persistentConnection: false, reasonPhrase: 'Queued');
    });
    http.configureClientFactory(() => client);
    final response = await http.sendMultipart(request);
    expect(client.closes, 0);
    expect(response.statusCode, 202);
    expect(response.contentLength, 3);
    expect(response.request, same(request));
    expect(response.headers['x-upload'], 'accepted');
    expect(response.persistentConnection, isFalse);
    expect(response.reasonPhrase, 'Queued');
    final bytes = response.stream.toBytes();
    source.add([1, 2]);
    await Future<void>.delayed(Duration.zero);
    expect(client.closes, 0);
    source.add([3]);
    await source.close();
    expect(await bytes, [1, 2, 3]);
    expect(client.closes, 1);
  });

  test('immediate multipart cancellation closes source and client once', () async {
    var cancellations = 0;
    final source = StreamController<List<int>>(onCancel: () { cancellations++; });
    final client = _Client((_) => raw_http.StreamedResponse(source.stream, 200));
    http.configureClientFactory(() => client);
    final response = await http.sendMultipart(http.MultipartRequest('POST', uri));
    final subscription = response.stream.listen((_) {});
    await subscription.cancel();
    expect(cancellations, 1);
    expect(client.closes, 1);
    await source.close();
    expect(client.closes, 1);
  });

  test('multipart stream errors close source and client and reach consumer', () async {
    var cancellations = 0;
    final source = StreamController<List<int>>(onCancel: () { cancellations++; });
    final client = _Client((_) => raw_http.StreamedResponse(source.stream, 200));
    http.configureClientFactory(() => client);
    final response = await http.sendMultipart(http.MultipartRequest('POST', uri));
    final failure = expectLater(response.stream.toBytes(), throwsStateError);
    source.addError(StateError('broken upload response'));
    await failure;
    expect(cancellations, 1);
    expect(client.closes, 1);
    await source.close();
  });

  test('multipart send failure closes the client before returning error', () async {
    final client = _Client((_) => throw StateError('send failed'));
    http.configureClientFactory(() => client);
    await expectLater(http.sendMultipart(http.MultipartRequest('POST', uri)), throwsStateError);
    expect(client.closes, 1);
  });

  test('default SocialClient outside setup zone refreshes an expired bearer', () async {
    final now = DateTime.utc(2026, 10, 18, 12);
    final expired = _token(now.subtract(const Duration(minutes: 1)));
    final renewed = _token(now.add(const Duration(hours: 1)));
    var session = KorlixAuthSession(accessToken: expired, refreshToken: 'refresh-a');
    var refreshes = 0;
    final network = _Client((request) {
      expect(request.url.path, '/api/social/inbox');
      expect(request.headers['Authorization'], 'Bearer $renewed');
      return raw_http.StreamedResponse(Stream.value(utf8.encode('{"items":[]}')), 200);
    });
    final sessions = KorlixSessionRefreshCoordinator(
      current: () => session,
      revision: () => 1,
      now: () => now,
      refresh: (_) async {
        refreshes++;
        return KorlixAuthSession(accessToken: renewed, refreshToken: 'refresh-b');
      },
      persist: (_, stillCurrent) async { expect(stillCurrent(), isTrue); },
      publish: (next) => session = next,
      clear: () async { fail('A successful refresh must not clear the account.'); },
    );
    runZoned(() {
      http.configureClientFactory(() => KorlixSessionHttpClient(
          inner: network, sessions: sessions, baseUrl: 'https://korlix.test'));
    });
    // This feature receives no injected HTTP client and retains its old bearer.
    // The explicit factory must still route it through the refresh coordinator.
    final social = SocialClient(baseUrl: 'https://korlix.test',
        headersBuilder: () => {'Authorization': 'Bearer $expired'});
    expect(await social.get('inbox'), {'items': []});
    expect(refreshes, 1);
    expect(social.available, isTrue);
    expect(network.closes, 0);
    social.dispose();
    expect(network.closes, 1);
  });
}
